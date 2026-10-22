// Daire kartında "Eski sakinler / Adli kayıt" bölümü (YALNIZ site yöneticisi ve süper kullanıcı; kurul ve görevli görmez).
// Sözleşme: docs/PLATFORM_ADLI_KAYIT.md. Kayıt yalnız resmî talep halinde bilgi amaçlıdır; sakinlere gösterilmez.
//
// Kayıtlar açılışta DEĞİL, "Kayıtları göster" ile çekilir (bu veri her kart açılışında istenmez). Zaman çizgisi düz bir [Column]'dur
// (iç içe kaydırılan liste yok: ana gövdede sınırsız yükseklik hatası oluşmaz). Döküm: gerekçe kodu + not zorunlu, PDF ya da CSV, indirme.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show ExportFormat;
import 'package:site_kapi_kontrol/models/residency_log.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart' show RenderedFile;
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

const String kResidencyLogNotice = 'Bu kayıt yalnız resmî talep halinde bilgi amaçlıdır; sakinlere gösterilmez.';

class ResidencyLogSection extends StatefulWidget {
  const ResidencyLogSection({
    super.key,
    required this.service,
    required this.siteCode,
    required this.apartmentId,
    required this.apartmentLabel,
    this.delivery,
  });

  final ApartmentManagementService service;
  final int siteCode;
  final int apartmentId;
  final String apartmentLabel;

  /// Dökümü kullanıcıya veren katman (testlerde sahte; yoksa [BulkFileSharer]).
  final BulkFileDelivery? delivery;

  @override
  State<ResidencyLogSection> createState() => _ResidencyLogSectionState();
}

class _ResidencyLogSectionState extends State<ResidencyLogSection> {
  final List<ResidencyLogItem> _items = <ResidencyLogItem>[];
  List<ResidencyLogItem> _legacy = const <ResidencyLogItem>[];
  int _total = 0;
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  int _token = 0;

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.residencyLog(widget.siteCode, widget.apartmentId, offset: more ? _items.length : 0);
      if (!mounted || token != _token) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        if (!more) _legacy = page.legacyItems;
        _total = page.total;
        _loaded = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Kayıtlar yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _export() async {
    await ForensicExportDialog.show(
      context,
      service: widget.service,
      siteCode: widget.siteCode,
      apartmentId: widget.apartmentId,
      apartmentLabel: widget.apartmentLabel,
      delivery: widget.delivery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    final empty = _loaded && _items.isEmpty && _legacy.isEmpty;
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogSectionTitle(icon: Icons.history_edu_rounded, title: 'Eski sakinler / Adli kayıt', tone: AppTone.neutral),
          const SizedBox(height: AppSpace.sm),
          Text(kResidencyLogNotice, style: secondary),
          const SizedBox(height: AppSpace.md),
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: () => unawaited(_load(more: _loaded && _items.isNotEmpty))),
            const SizedBox(height: AppSpace.sm),
          ],
          if (!_loaded && _error == null && !_loading)
            PrimaryActionButton(
              key: const ValueKey<String>('residency_log_show'),
              label: 'Kayıtları göster',
              icon: Icons.visibility_rounded,
              variant: AppButtonVariant.outline,
              onPressed: () => unawaited(_load()),
            ),
          if (_loading && !_loaded) const DialogRowsSkeleton(rows: 2, caption: 'Kayıtlar yükleniyor...'),
          if (empty) Text('Bu daire için kayıt yok.', style: secondary),
          for (final item in _items) ...[_row(context, item), const SizedBox(height: AppSpace.md)],
          if (_legacy.isNotEmpty) ...[
            Text('Eski kayıtlar', style: th.titleSmall),
            const SizedBox(height: AppSpace.xs),
            Text('Bu dönemler adli kayıt başlamadan önceki ilişki geçmişinden türetilmiştir (salt okunur).', style: secondary),
            const SizedBox(height: AppSpace.sm),
            for (final item in _legacy) ...[_row(context, item), const SizedBox(height: AppSpace.md)],
          ],
          if (_loaded && _items.length < _total)
            PrimaryActionButton(
              key: const ValueKey<String>('residency_log_more'),
              label: 'Daha fazla göster',
              variant: AppButtonVariant.outline,
              loading: _loading,
              onPressed: _loading ? null : () => unawaited(_load(more: true)),
            ),
          if (_loaded) ...[
            const SizedBox(height: AppSpace.sm),
            PrimaryActionButton(
              key: const ValueKey<String>('residency_log_export'),
              label: 'Adli bilgi dökümü al',
              icon: Icons.download_rounded,
              variant: AppButtonVariant.tonal,
              onPressed: () => unawaited(_export()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ResidencyLogItem item) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodySmall?.copyWith(color: context.palette.textSecondary);
    final period = <String>[
      if (item.periodStart != null) formatCrmDate(item.periodStart),
      if (item.periodEnd != null) formatCrmDate(item.periodEnd),
    ].join(' - ');
    final who = <String>[
      if (item.actorName.isNotEmpty) item.actorName,
      if (item.actorRoleLabel.isNotEmpty && !item.isLegacy) item.actorRoleLabel,
    ].join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.subjectName, style: th.titleSmall),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            if (item.relationLabel.isNotEmpty) InfoChip(item.relationLabel),
            InfoChip(item.eventLabel),
            if (period.isNotEmpty) InfoChip(period),
            if (item.isLegacy) InfoChip(item.sourceLabel),
          ],
        ),
        if (item.reasonLabel.isNotEmpty || who.isNotEmpty || item.occurredAt != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            <String>[
              if (item.reasonLabel.isNotEmpty) 'Neden: ${item.reasonLabel}',
              if (who.isNotEmpty) 'İşlemi yapan: $who',
              if (item.occurredAt != null && !item.isLegacy) 'Kayıt: ${formatCrmDate(item.occurredAt)}',
            ].join(' • '),
            style: secondary,
          ),
        ],
      ],
    );
  }
}

/// "Adli bilgi dökümü al": biçim (PDF / CSV), gerekçe kodu ve not (zorunlu). Döküm alma sunucuda denetim kaydına yazılır.
class ForensicExportDialog extends StatefulWidget {
  const ForensicExportDialog({
    super.key,
    required this.service,
    required this.siteCode,
    required this.apartmentId,
    required this.apartmentLabel,
    this.delivery,
  });

  final ApartmentManagementService service;
  final int siteCode;
  final int apartmentId;
  final String apartmentLabel;
  final BulkFileDelivery? delivery;

  static Future<void> show(
    BuildContext context, {
    required ApartmentManagementService service,
    required int siteCode,
    required int apartmentId,
    required String apartmentLabel,
    BulkFileDelivery? delivery,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ForensicExportDialog(
        service: service,
        siteCode: siteCode,
        apartmentId: apartmentId,
        apartmentLabel: apartmentLabel,
        delivery: delivery,
      ),
    );
  }

  @override
  State<ForensicExportDialog> createState() => _ForensicExportDialogState();
}

class _ForensicExportDialogState extends State<ForensicExportDialog> {
  final TextEditingController _note = TextEditingController();
  String _reason = 'official_request';
  String _format = 'pdf';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final note = _note.text.trim();
    if (note.length < 5) {
      setState(() => _error = 'Gerekçe notu zorunludur (en az 5 karakter).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await widget.service.residencyLogExport(
        widget.siteCode,
        format: _format,
        reasonCode: _reason,
        note: note,
        apartmentId: widget.apartmentId,
      );
      final delivery = widget.delivery ?? BulkFileSharer();
      // `format` RenderedFile'da yalnız etikettir (teslim yolu dosya adı ve MIME'a bakar); PDF de aynı yoldan verilir.
      await delivery.deliver(
        RenderedFile(bytes: file.bytes, fileName: file.fileName, mimeType: file.mimeType, format: ExportFormat.csv),
        subject: 'Adli bilgi dökümü',
      );
      if (!mounted) return;
      AppSnack.show(context, 'Döküm hazırlandı. Dökümü alma işlemi denetim kaydına yazıldı.', kind: AppSnackKind.success);
      popIfCurrent(context);
    } catch (e) {
      if (mounted) setState(() => _error = crmMessageOf(e, 'Döküm alınamadı. Biraz sonra tekrar deneyin.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return AppDialog(
      title: 'Adli bilgi dökümü',
      subtitle: widget.apartmentLabel,
      icon: Icons.download_rounded,
      actions: [
        TextButton(onPressed: _busy ? null : () => popIfCurrent(context), child: const Text('Vazgeç')),
        ElevatedButton(
          key: const ValueKey<String>('forensic_submit'),
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: Text(_busy ? 'Hazırlanıyor...' : 'Dökümü al'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(kResidencyLogNotice, style: th.bodyMedium?.copyWith(color: context.palette.textSecondary)),
          const SizedBox(height: AppSpace.md),
          if (_error != null) ...[InlineNotice(message: _error!), const SizedBox(height: AppSpace.sm)],
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('forensic_reason'),
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Gerekçe'),
            items: <DropdownMenuItem<String>>[
              for (final entry in kForensicReasons.entries) DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: AppSpace.sm),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('forensic_format'),
            initialValue: _format,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Biçim'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: 'pdf', child: Text('PDF')),
              DropdownMenuItem<String>(value: 'csv', child: Text('CSV (Excel uyumlu)')),
            ],
            onChanged: _busy ? null : (v) => setState(() => _format = v ?? _format),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            key: const ValueKey<String>('forensic_note'),
            controller: _note,
            enabled: !_busy,
            maxLines: 3,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Gerekçe notu (zorunlu)', helperText: 'Örn. mahkeme yazısı tarihi ve sayısı. Denetim kaydına yazılır.'),
          ),
        ],
      ),
    );
  }
}
