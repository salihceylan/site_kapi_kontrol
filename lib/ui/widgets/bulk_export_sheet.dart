// Dışa aktarma alt sayfası (Platform Faz 2b). Faz 4b finans raporları AYNI sayfayı yeni [ExportSource]'larla kullanır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart' show formatByteSize;
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_error_notice.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';

/// Dışa aktarılacak bir veri kaynağı (sözleşme: `ExportSource { label; Future<ExportEnvelope> fetch(format); }`).
///
/// [fetch] zarfı sunucudan alır (TÜM sayfalar, yalnız yüklenenler değil). [fetchWithNotes] verilirse ve [notesLabel]
/// doluysa sayfa «notları da ekle» anahtarını (varsayılan KAPALI) gösterir ve [fetch] yerine onu çağırır.
@immutable
class ExportSource {
  const ExportSource({
    required this.label,
    required this.fetch,
    this.icon = Icons.table_chart_rounded,
    this.filterSummary,
    this.notesLabel,
    this.fetchWithNotes,
    this.sheetName,
  });

  /// Kullanıcıya görünen ad ("Kişiler").
  final String label;
  final Future<ExportEnvelope> Function(ExportFormat format) fetch;
  final IconData icon;

  /// Açık sekmenin süzgeçlerinin okunur özeti ("Aktif kişiler, Malik"); null ise gösterilmez.
  final String? filterSummary;

  final String? notesLabel;
  final Future<ExportEnvelope> Function(ExportFormat format, bool includeNotes)? fetchWithNotes;

  /// XLSX sayfa adı (varsayılan: zarf türü).
  final String? sheetName;

  bool get hasNotesToggle => notesLabel != null && fetchWithNotes != null;
}

typedef ExportRenderer =
    Future<RenderedFile> Function(ExportEnvelope envelope, ExportFormat format, {String? sheetName});

class ExportSheet extends StatefulWidget {
  /// Test düzeneği: teslim [delivery] verilmediğinde gerçek paylaşım / kaydetme yerine sahtesi kullanılır.
  @visibleForTesting
  static BulkFileDelivery Function()? debugDeliveryFactory;

  const ExportSheet({
    super.key,
    required this.sources,
    this.initialIndex = 0,
    this.delivery,
    this.renderer = renderExportAsync,
    this.title = 'Dışa Aktar',
  }) : assert(sources.length > 0, 'En az bir kaynak gerekir');

  final List<ExportSource> sources;
  final int initialIndex;
  final BulkFileDelivery? delivery;
  final ExportRenderer renderer;
  final String title;

  /// Alt sayfayı açar. Kapatılana dek sonuç dönmez.
  static Future<void> show(
    BuildContext context, {
    required List<ExportSource> sources,
    int initialIndex = 0,
    BulkFileDelivery? delivery,
    ExportRenderer renderer = renderExportAsync,
    String title = 'Dışa Aktar',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ExportSheet(
        sources: sources,
        initialIndex: initialIndex,
        delivery: delivery,
        renderer: renderer,
        title: title,
      ),
    );
  }

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  late int _index = widget.initialIndex.clamp(0, widget.sources.length - 1);
  ExportFormat _format = ExportFormat.xlsx;
  bool _includeNotes = false;
  bool _busy = false;
  String? _error;
  String? _info;
  String? _success;
  final RetryLock _retry = RetryLock();
  late final BulkFileDelivery _delivery =
      widget.delivery ?? ExportSheet.debugDeliveryFactory?.call() ?? BulkFileSharer();
  final GlobalKey _buttonKey = GlobalKey();
  int _token = 0;

  ExportSource get _source => widget.sources[_index];

  @override
  void initState() {
    super.initState();
    // Önceki oturumlardan (sistem süreci öldürüldüyse) kalan kişisel veri dosyaları süpürülür.
    if (widget.delivery == null && ExportSheet.debugDeliveryFactory == null) {
      unawaited(BulkFileSharer.sweepAll(staleAfter: const Duration(minutes: 10)));
    }
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    super.dispose();
  }

  Rect? _origin() {
    final box = _buttonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _select(int index) {
    if (_busy || index == _index) return;
    setState(() {
      _index = index;
      _includeNotes = false;
      _error = null;
      _info = null;
      _success = null;
    });
  }

  Future<void> _save() async {
    if (_busy || _retry.locked) return;
    final source = _source;
    final format = _format;
    final notes = source.hasNotesToggle && _includeNotes;
    final token = ++_token;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _success = null;
    });
    try {
      final envelope = notes
          ? await source.fetchWithNotes!(format, true)
          : (source.hasNotesToggle ? await source.fetchWithNotes!(format, false) : await source.fetch(format));
      if (!mounted || token != _token) return;
      if (envelope.rowCount == 0) {
        setState(() => _info = 'Bu süzgeçle dışa aktarılacak kayıt yok. Süzgeci değiştirip tekrar deneyin.');
        return;
      }
      final file = await widget.renderer(envelope, format, sheetName: source.sheetName);
      if (!mounted || token != _token) return;
      final outcome = await _delivery.deliver(file, sharePositionOrigin: _origin(), subject: source.label);
      if (!mounted || token != _token) return;
      setState(() {
        switch (outcome) {
          case ExportShareOutcome.dismissed:
            _info = BulkFileSharer.platformUsesSaveDialog
                ? 'Dosya kaydedilmedi.'
                : 'Paylaşım iptal edildi; dosya gönderilmedi.';
          case ExportShareOutcome.shared:
          case ExportShareOutcome.unknown:
            _success =
                '${BulkFileSharer.platformUsesSaveDialog ? 'Dosya kaydedildi' : 'Dosya hazır'}: ${file.fileName} '
                '(${envelope.rowCount} satır, ${formatByteSize(file.bytes.length)}).';
        }
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _error = limited
            ? RetryLock.messageFor(e)
            : (e is ApiException && !e.genericFallback && e.message.trim().isNotEmpty
                  ? e.message
                  : 'Dışa aktarma yapılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    } finally {
      if (mounted && token == _token) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final source = _source;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final saveLabel = BulkFileSharer.platformUsesSaveDialog ? 'Kaydet' : 'Paylaş';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(widget.title, style: th.titleLarge),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Kayıtlar sunucudan alınır, dosya cihazınızda hazırlanır. Tüm sayfalardaki kayıtlar dahil edilir.',
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          if (widget.sources.length > 1) ...[
            const SizedBox(height: AppSpace.lg),
            Semantics(header: true, child: Text('Ne aktarılsın?', style: th.titleSmall)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (var i = 0; i < widget.sources.length; i++)
                  ChoiceChip(
                    key: ValueKey<String>('export_source_$i'),
                    avatar: Icon(widget.sources[i].icon, size: 18),
                    label: Text(widget.sources[i].label),
                    selected: _index == i,
                    onSelected: _busy ? null : (_) => _select(i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Semantics(header: true, child: Text('Dosya biçimi', style: th.titleSmall)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final format in ExportFormat.values)
                ChoiceChip(
                  key: ValueKey<String>('export_format_${format.apiValue}'),
                  label: Text(format == ExportFormat.xlsx ? 'Excel (.xlsx) · önerilen' : format.label),
                  selected: _format == format,
                  onSelected: _busy ? null : (_) => setState(() => _format = format),
                ),
            ],
          ),
          if (source.filterSummary != null) ...[
            const SizedBox(height: AppSpace.lg),
            AppCard(
              key: const ValueKey<String>('export_filter_summary'),
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Uygulanan süzgeç', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                  const SizedBox(height: AppSpace.xs),
                  Text(source.filterSummary!, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          if (source.hasNotesToggle) ...[
            const SizedBox(height: AppSpace.sm),
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const ValueKey<String>('export_include_notes'),
                contentPadding: EdgeInsets.zero,
                title: Text(source.notesLabel!),
                subtitle: const Text('Varsayılan olarak kapalıdır.'),
                value: _includeNotes,
                onChanged: _busy ? null : (value) => setState(() => _includeNotes = value),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          const InlineNotice(
            key: ValueKey<String>('export_privacy_notice'),
            tone: AppTone.warning,
            message: 'Bu dosya kişisel veri içerir; güvenli saklayın ve yetkisiz kişilerle paylaşmayın.',
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            BulkErrorNotice(key: const ValueKey<String>('export_error'), message: _error!),
          ],
          if (_info != null) ...[
            const SizedBox(height: AppSpace.md),
            InlineNotice(key: const ValueKey<String>('export_info'), tone: AppTone.info, message: _info!),
          ],
          if (_success != null) ...[
            const SizedBox(height: AppSpace.md),
            InlineNotice(key: const ValueKey<String>('export_success'), tone: AppTone.success, message: _success!),
          ],
          const SizedBox(height: AppSpace.lg),
          KeyedSubtree(
            key: _buttonKey,
            child: PrimaryActionButton(
              key: const ValueKey<String>('export_save'),
              label: _busy ? 'Hazırlanıyor…' : saveLabel,
              icon: BulkFileSharer.platformUsesSaveDialog ? Icons.save_alt_rounded : Icons.ios_share_rounded,
              loading: _busy,
              onPressed: _busy || _retry.locked ? null : _save,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const ValueKey<String>('export_close'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Kapat', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
