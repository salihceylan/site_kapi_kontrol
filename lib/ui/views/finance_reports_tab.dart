import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/crm_pickers.dart' show CrmPickerField, showApartmentPicker;
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_export_sources.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// "Raporlar" sekmesi (Platform Faz 4b, Ö5): borç yaşlandırma, aylık gelir-gider, kasa durumu, daire ekstresi ve yönetim
/// kurulu özeti. Her rapor ekranda görüntülenir, PDF olarak yazdırılır / paylaşılır ve (kurul özeti hariç) CSV / Excel
/// olarak dışa aktarılır.
///
/// Kurallar (Faz 4a incelemelerinin dersleri):
/// - Rapor tek `REPEATABLE READ` işleminde hesaplanır; bir bölüm başarısızsa BÜTÜN yanıt hatadır. İstemci hatayı hata
///   olarak gösterir ("Tekrar Dene"); ASLA "borç yok / 0 / veri yok" demez ve eski rakamı hata uyarısının altında bırakmaz.
/// - Süzgeç değişince rapor SESSİZCE eskimiş kalmaz: "Raporu Getir"e basılana dek PDF ve dışa aktarma kapalıdır
///   ("süzgeçler değişti" notu); PDF ve dosya her zaman EKRANDAKİ (uygulanmış) süzgeçle üretilir.
/// - Kapalı olmayan aylar "kesinleşmemiş" işaretlenir (`closed_through`); raporlar noter onaylı karar defterinin yerine geçmez.
/// - Kurul: raporları okur; dosya dışa aktarma YOKTUR (403); yalnız "Yönetim Kuruluna Sun" (kurul özeti) PDF'i basılır.
/// - Rapor ağır uçtur: sunucu `REPORT_BUSY` (503) dönebilir; bekleme süresi gösterilir ve düğme geçici kilitlenir.
class FinanceReportsTab extends StatefulWidget {
  const FinanceReportsTab({
    super.key,
    required this.scope,
    this.now,
    this.exportLauncher = defaultFinanceExportLauncher,
  });

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher exportLauncher;

  @override
  State<FinanceReportsTab> createState() => FinanceReportsTabState();
}

enum FinanceReportKind {
  aging('aging', 'Yaşlandırma', Icons.hourglass_bottom_rounded),
  incomeExpense('income_expense', 'Gelir-Gider', Icons.stacked_bar_chart_rounded),
  cashPosition('cash_position', 'Kasa Durumu', Icons.account_balance_rounded),
  statement('statement', 'Daire Ekstresi', Icons.receipt_long_rounded),
  boardSummary('board_summary', 'Kurul Özeti', Icons.groups_rounded);

  const FinanceReportKind(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class FinanceReportsTabState extends State<FinanceReportsTab> {
  FinanceReportKind _kind = FinanceReportKind.aging;

  /// Seçili raporu yeniden yükletmek için (üst ekran "yenile").
  int _generation = 0;

  Future<void> reload() async {
    if (mounted) setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Raporlar',
          trailing: IconButton(
            key: const ValueKey<String>('finance_reports_refresh'),
            onPressed: reload,
            tooltip: 'Raporu yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('Rapor türünü seçin; rakamlar sunucudan alınır, PDF cihazınızda hazırlanır.', style: th.bodyMedium),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final kind in FinanceReportKind.values)
              ChoiceChip(
                key: ValueKey<String>('finance_report_chip_${kind.key}'),
                avatar: Icon(kind.icon, size: 18),
                label: Text(kind.label),
                selected: _kind == kind,
                onSelected: (_) {
                  if (_kind != kind) setState(() => _kind = kind);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        KeyedSubtree(key: ValueKey<String>('finance_report_${_kind.key}_$_generation'), child: _body()),
      ],
    );
  }

  Widget _body() {
    switch (_kind) {
      case FinanceReportKind.aging:
        return _AgingReportView(scope: widget.scope, now: widget.now, launcher: widget.exportLauncher);
      case FinanceReportKind.incomeExpense:
        return _IncomeExpenseReportView(scope: widget.scope, now: widget.now, launcher: widget.exportLauncher);
      case FinanceReportKind.cashPosition:
        return _CashPositionReportView(scope: widget.scope, now: widget.now, launcher: widget.exportLauncher);
      case FinanceReportKind.statement:
        return _StatementReportView(scope: widget.scope, now: widget.now, launcher: widget.exportLauncher);
      case FinanceReportKind.boardSummary:
        return _BoardSummaryReportView(scope: widget.scope, now: widget.now, launcher: widget.exportLauncher);
    }
  }
}

// --- Ortak iskelet ------------------------------------------------------------------------------

/// Her raporun ortak durumu: yükleme / hata / veri, uygulanmış süzgeç imzası, PDF ve dışa aktarma işlemleri.
abstract class _ReportState<W extends StatefulWidget, T> extends State<W> {
  PeopleScope get scope;
  DateTime Function()? get nowFn;
  FinanceExportLauncher get launcher;

  T? data;
  bool loading = false;
  String? error;
  int _token = 0;
  String? appliedSignature;
  bool outputBusy = false;
  String? outputError;
  final RetryLock retry = RetryLock();

  // REPORT_BUSY (503): sunucudaki rapor yuvaları dolu; düğme `Retry-After` süresince (varsayılan 5 sn) kilitli kalır.
  Timer? _busyTimer;
  bool get busyLocked => _busyTimer != null;

  /// Şu anki süzgeç değerlerinin imzası (UI).
  String get currentSignature;

  /// Raporu getirir (UYGULANMIŞ süzgeçleri bu çağrı anında dondurur).
  Future<T> fetch();

  /// Süzgeç doğrulaması; hata varsa metni döner (istek gönderilmez).
  String? validateFilters() => null;

  String get fallbackError => 'Rapor alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  bool get canWrite => scope.canWrite;
  DateTime get today {
    final wall = istanbulNow(nowFn?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  bool get filtersChanged => data != null && appliedSignature != currentSignature;

  /// false: rapor, kullanıcı süzgeci tamamlayıp "Getir"e basana dek yüklenmez (örn. daire seçilmemiş ekstre).
  bool get autoLoad => true;

  /// Rapor yenilenemeyecek ek meşguliyet (örn. yaşlandırmada "Daha fazla" sayfası yükleniyor): yenileme sayfayı eski süzgeçle
  /// yeni rapora karıştırmasın.
  bool get extraBusy => false;

  @override
  void initState() {
    super.initState();
    if (autoLoad) unawaited(load());
  }

  @override
  void dispose() {
    ++_token;
    _busyTimer?.cancel();
    retry.dispose();
    super.dispose();
  }

  void _lockBusy(Object error) {
    final wait = error is ApiException ? (error.retryAfterSeconds ?? 5) : 5;
    _busyTimer?.cancel();
    _busyTimer = Timer(Duration(seconds: wait.clamp(1, 30)), () {
      _busyTimer = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> load() async {
    if (!mounted || loading || extraBusy || busyLocked) return;
    final problem = validateFilters();
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    final token = ++_token;
    final signature = currentSignature;
    setState(() {
      loading = true;
      error = null;
      outputError = null;
    });
    try {
      final result = await fetch();
      if (!mounted || token != _token) return;
      setState(() {
        data = result;
        loading = false;
        appliedSignature = signature;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      final limited = retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      if (hasErrorCode(e, 'REPORT_BUSY')) _lockBusy(e);
      setState(() {
        loading = false;
        // Eski rakamlar hata uyarısının altında güncelmiş gibi durmasın.
        data = null;
        appliedSignature = null;
        error = limited ? RetryLock.messageFor(e) : financeMessageOf(e, fallbackError);
      });
    }
  }

  Future<void> runOutput(Future<void> Function() action, {String failure = 'PDF hazırlanamadı. Tekrar deneyin.'}) async {
    if (outputBusy || data == null || filtersChanged) return;
    setState(() {
      outputBusy = true;
      outputError = null;
    });
    try {
      await action();
      if (mounted) setState(() => outputBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        outputBusy = false;
        outputError = financeMessageOf(e, failure);
      });
    }
  }

  /// "Raporu Getir" düğmesi.
  Widget fetchButton({String label = 'Raporu Getir'}) => PrimaryActionButton(
    key: const ValueKey<String>('finance_report_fetch'),
    label: label,
    icon: Icons.search_rounded,
    loading: loading,
    onPressed: (loading || extraBusy || retry.locked || busyLocked) ? null : load,
  );

  /// Yükleniyor / hata / (süzgeç değişti) bildirimleri; veri varsa null döner ki çağıran içeriği çizsin.
  Widget? statusWidget() {
    if (data == null) {
      if (loading || error == null) return const ListSkeleton(rows: 2);
      return InlineNotice(
        key: const ValueKey<String>('finance_report_error'),
        message: error!,
        onRetry: (retry.locked || busyLocked) ? null : load,
      );
    }
    return null;
  }

  /// Rapor ekranda iken (önceki süzgeçle) yeni bir süzgeç hatası / doğrulama sorunu: bildirim gösterilir.
  Widget? errorBanner() => (error != null && data != null)
      ? Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: InlineNotice(key: const ValueKey<String>('finance_report_filter_error'), message: error!),
        )
      : null;

  Widget? staleNote() => filtersChanged
      ? const InlineNotice(
          key: ValueKey<String>('finance_report_stale'),
          tone: AppTone.warning,
          message: 'Süzgeçler değişti. Güncel rapor için "Raporu Getir"e basın; PDF ve dosya ekrandaki rapora aittir.',
        )
      : null;

  /// Rapor üstverisi: oluşturma zamanı + kapalı dönem bilgisi (kesinleşmemiş uyarısı).
  Widget metaCard(ReportMeta meta) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final through = meta.closedThrough;
    final closedText = through == null
        ? 'Kapatılmış dönem yok: rakamlar kesinleşmemiştir.'
        : 'Kapalı dönem: ${through.label} ve öncesi. Sonraki aylar kesinleşmemiştir.';
    return DialogPanel(
      key: const ValueKey<String>('finance_report_meta'),
      tone: through == null ? AppTone.warning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.siteName.isNotEmpty) Text(meta.siteName, style: th.titleSmall),
          if (meta.generatedAt != null)
            Text('Hazırlanma: ${formatIstanbulDateTime(meta.generatedAt)}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
          Text(closedText, style: th.bodySmall),
          Text(
            'Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  /// PDF ve (verilirse) dışa aktarma düğmeleri. [pdfAllowed] kurulda yalnız kurul özetinde true'dur.
  Widget actions({
    required bool pdfAllowed,
    required Future<void> Function(bool share) onPdf,
    List<ExportSource> Function()? exportSources,
  }) {
    final blocked = outputBusy || filtersChanged || data == null;
    final sources = canWrite && exportSources != null ? exportSources() : const <ExportSource>[];
    if (!pdfAllowed && sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outputError != null)
          FinanceSubmitError(key: const ValueKey<String>('finance_report_output_error'), message: outputError!),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            if (pdfAllowed)
              PrimaryActionButton(
                key: const ValueKey<String>('finance_report_pdf_print'),
                label: scope.canWrite ? 'PDF Yazdır' : 'Yönetim Kuruluna Sun (PDF)',
                icon: Icons.picture_as_pdf_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: outputBusy,
                onPressed: blocked ? null : () => onPdf(false),
              ),
            if (pdfAllowed)
              PrimaryActionButton(
                key: const ValueKey<String>('finance_report_pdf_share'),
                label: 'PDF Paylaş',
                icon: Icons.ios_share_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                onPressed: blocked ? null : () => onPdf(true),
              ),
            if (sources.isNotEmpty)
              PrimaryActionButton(
                key: const ValueKey<String>('finance_report_export'),
                label: 'Dışa Aktar',
                icon: Icons.table_chart_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                onPressed: blocked ? null : () => unawaited(launcher(context, sources)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Ay seçici: önceki / sonraki ay düğmeleri (tarih yazmadan, ay sınırlarıyla).
class _MonthStepper extends StatelessWidget {
  const _MonthStepper({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final FinancePeriod value;
  final FinancePeriod min;
  final FinancePeriod max;
  final ValueChanged<FinancePeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return DialogPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: th.bodySmall),
          Row(
            children: [
              IconButton(
                key: ValueKey<String>('${keyPrefix}_prev'),
                tooltip: '$label: önceki ay',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: value <= min ? null : () => onChanged(value.previous),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(value.label, key: ValueKey<String>('${keyPrefix}_label'), textAlign: TextAlign.center, style: th.titleMedium),
                ),
              ),
              IconButton(
                key: ValueKey<String>('${keyPrefix}_next'),
                tooltip: '$label: sonraki ay',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: value >= max ? null : () => onChanged(value.next),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- 1. Yaşlandırma -------------------------------------------------------------------------------

/// Yaşlandırma sayfalarını daire kimliğine göre TEKİLLEŞTİREREK birleştirir (her sayfa ayrı anlık görüntüdür; kayan sayfada
/// aynı daire iki kez gelebilir). Sıra korunur; yeni gelenler sona eklenir.
@visibleForTesting
List<AgingItem> mergeAgingItems(List<AgingItem> current, List<AgingItem> page) {
  final known = current.map((i) => i.apartmentId).toSet();
  return <AgingItem>[
    ...current,
    for (final item in page)
      if (known.add(item.apartmentId)) item,
  ];
}

class _AgingReportView extends StatefulWidget {
  const _AgingReportView({required this.scope, required this.now, required this.launcher});

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher launcher;

  @override
  State<_AgingReportView> createState() => _AgingReportViewState();
}

class _AgingReportViewState extends _ReportState<_AgingReportView, AgingReport> {
  @override
  PeopleScope get scope => widget.scope;
  @override
  DateTime Function()? get nowFn => widget.now;
  @override
  FinanceExportLauncher get launcher => widget.launcher;

  late final TextEditingController _asOf = TextEditingController(text: formatDateField(today));
  String _status = 'debtor';
  DateTime? _appliedAsOf;
  String _appliedStatus = 'debtor';
  List<AgingItem> _items = const <AgingItem>[];
  bool _loadingMore = false;
  String? _moreError;

  static const int _pageSize = 200;

  @override
  void dispose() {
    _asOf.dispose();
    super.dispose();
  }

  @override
  String get currentSignature => '${_asOf.text.trim()}|$_status';

  @override
  String? validateFilters() {
    final date = parseDateField(_asOf.text);
    if (date == null) return 'Rapor tarihini GG.AA.YYYY biçiminde girin.';
    if (date.isAfter(today)) return 'Rapor tarihi bugünden ileri olamaz.';
    if (date.isBefore(DateTime(today.year - 5, today.month, today.day))) return 'Rapor tarihi en çok 5 yıl öncesi olabilir.';
    return null;
  }

  // Rapor sürümü: her yeni rapor alımı artırır; eski süzgeçle başlamış "Daha fazla" / PDF sayfaları yeni rapora KARIŞMAZ.
  int _generation = 0;

  @override
  bool get extraBusy => _loadingMore;

  @override
  Future<AgingReport> fetch() async {
    final asOf = parseDateField(_asOf.text);
    final status = _status;
    ++_generation;
    final report = await scope.f4Call(
      (api, t, s) => api.getAgingReport(token: t, siteCode: s, asOf: asOf, status: status, limit: _pageSize),
    );
    // Yanıt GELDİKTEN sonra uygulanır (hata olursa eski süzgeç / satırlar bozulmaz).
    _appliedAsOf = asOf;
    _appliedStatus = status;
    _moreError = null;
    _items = report.items;
    return report;
  }

  Future<void> _loadMore() async {
    final report = data;
    if (report == null || _loadingMore || _items.length >= report.total) return;
    final generation = _generation;
    final asOf = _appliedAsOf;
    final status = _appliedStatus;
    final offset = _items.length;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await scope.f4Call(
        (api, t, s) => api.getAgingReport(token: t, siteCode: s, asOf: asOf, status: status, limit: _pageSize, offset: offset),
      );
      if (!mounted) return;
      if (generation != _generation) {
        // Bu sayfa eski rapora aitti (rapor arada yenilendi): atılır.
        setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        _items = mergeAgingItems(_items, page.items);
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        if (generation == _generation) _moreError = financeMessageOf(e, 'Daha fazla daire yüklenemedi. Tekrar deneyin.');
      });
    }
  }

  /// PDF için TÜM daireler okunur (yalnız ekrandaki sayfa değil). Sayfalar ayrı anlık görüntülerdir: daire kimliğine göre
  /// tekilleştirilir; rapor arada yenilenirse PDF eski/yeni karışımı üretmez (hata verir).
  Future<AgingReport> _complete(AgingReport first) async {
    final generation = _generation;
    final asOf = _appliedAsOf;
    final status = _appliedStatus;
    var items = List<AgingItem>.of(_items);
    while (items.length < first.total) {
      final offset = items.length;
      final page = await scope.f4Call(
        (api, t, s) => api.getAgingReport(token: t, siteCode: s, asOf: asOf, status: status, limit: _pageSize, offset: offset),
      );
      if (generation != _generation) throw StateError('Rapor yenilendi');
      if (page.items.isEmpty) break;
      final merged = mergeAgingItems(items, page.items);
      if (merged.length == items.length) break; // yeni daire gelmedi: sonsuz döngü olmasın
      items = merged;
    }
    return AgingReport(
      meta: first.meta,
      asOf: first.asOf,
      totals: first.totals,
      creditMinor: first.creditMinor,
      lateFeeOutstandingMinor: first.lateFeeOutstandingMinor,
      totalOverdueMinor: first.totalOverdueMinor,
      items: items,
      total: first.total,
    );
  }

  List<ExportSource> _sources() => <ExportSource>[
    financeExportSource(
      scope: scope,
      label: 'Yaşlandırma',
      kind: 'finance_aging',
      icon: Icons.hourglass_bottom_rounded,
      query: <String, String>{
        if (_appliedAsOf != null) 'as_of': crmDateParam(_appliedAsOf!),
        'status': _appliedStatus,
      },
      filterSummary: '${formatCrmDate(_appliedAsOf)} • ${_appliedStatus == 'debtor' ? 'Yalnız borçlu daireler' : 'Tüm daireler'}',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final report = data;
    final status = statusWidget();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey<String>('finance_aging_as_of'),
          controller: _asOf,
          keyboardType: TextInputType.number,
          inputFormatters: [DateInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Rapor tarihi',
            hintText: 'GG.AA.YYYY',
            prefixIcon: Icon(Icons.event_rounded),
            helperText: 'Borçlar bu tarih itibarıyla, vadesi en eski borçtan mahsupla yaşlandırılır.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const FinanceGroupTitle('Daireler'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            ChoiceChip(
              key: const ValueKey<String>('finance_aging_status_debtor'),
              label: const Text('Yalnız borçlu'),
              selected: _status == 'debtor',
              onSelected: (_) => setState(() => _status = 'debtor'),
            ),
            ChoiceChip(
              key: const ValueKey<String>('finance_aging_status_all'),
              label: const Text('Tümü'),
              selected: _status == 'all',
              onSelected: (_) => setState(() => _status = 'all'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        fetchButton(),
        const SizedBox(height: AppSpace.md),
        ?errorBanner(),
        ?staleNote(),
        if (status != null) status else ...[
          metaCard(report!.meta),
          const SizedBox(height: AppSpace.md),
          _totals(context, report),
          const SizedBox(height: AppSpace.md),
          actions(
            pdfAllowed: canWrite,
            onPdf: (share) => runOutput(() async {
              final full = await _complete(report);
              await FinancePdfActions.aging(full, share: share);
            }),
            exportSources: _sources,
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(header: true, container: true, child: Text('Daireler (${report.total})', style: th.titleMedium)),
          const SizedBox(height: AppSpace.sm),
          if (_items.isEmpty)
            const EmptyCard(
              key: ValueKey<String>('finance_aging_empty'),
              icon: Icons.check_circle_outline_rounded,
              title: 'Bu tarihte vadesi geçmiş borç yok.',
            )
          else
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: _AgingItemCard(item: item),
              ),
          if (_moreError != null) ...[InlineNotice(message: _moreError!, onRetry: _loadMore), const SizedBox(height: AppSpace.md)],
          if (_items.length < report.total)
            Align(
              child: PrimaryActionButton(
                key: const ValueKey<String>('finance_aging_more'),
                label: 'Daha fazla göster (${report.total - _items.length})',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: _loadingMore,
                onPressed: _loadingMore ? null : _loadMore,
              ),
            ),
        ],
      ],
    );
  }

  Widget _totals(BuildContext context, AgingReport r) {
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey<String>('finance_aging_totals'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, container: true, child: Text('Toplam', style: th.titleMedium)),
          const SizedBox(height: AppSpace.sm),
          FinanceInfoRow(label: 'Vadesi geçmiş toplam', money: r.totalOverdueMinor, emphasize: true),
          for (final b in AgingBucket.values) FinanceInfoRow(label: b.label, money: r.totals[b] ?? 0),
          FinanceInfoRow(label: 'Kullanılmamış alacak', money: r.creditMinor),
          if (r.lateFeeOutstandingMinor != null)
            FinanceInfoRow(label: 'Ödenmemiş gecikme tazminatı (bilgi)', money: r.lateFeeOutstandingMinor),
        ],
      ),
    );
  }
}

class _AgingItemCard extends StatelessWidget {
  const _AgingItemCard({required this.item});

  final AgingItem item;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final title = financeApartmentTitle(item.blockName, item.label);
    final nonZero = AgingBucket.values.where((b) => (item.buckets[b] ?? 0) != 0).toList();
    final semantic = StringBuffer('Daire: $title. Vadesi geçmiş toplam: ${moneySemanticLabel(item.totalOverdueMinor)}.');
    for (final b in nonZero) {
      semantic.write(' ${b.label}: ${moneySemanticLabel(item.buckets[b]!)}.');
    }
    if (item.creditMinor != 0) semantic.write(' Alacak: ${moneySemanticLabel(item.creditMinor)}.');
    return AppCard(
      key: ValueKey<String>('aging_item_${item.apartmentId}'),
      padding: listCardPadding(context),
      child: Semantics(
        container: true,
        label: semantic.toString(),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: th.titleMedium),
              if (item.ownerName != null) Text('Malik: ${item.ownerName}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              if (item.tenantName != null) Text('Kiracı: ${item.tenantName}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
              const SizedBox(height: AppSpace.xs),
              Text(
                formatMinor(item.totalOverdueMinor),
                style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final b in nonZero)
                    DialogMetaPill('${b.label}: ${formatMinor(item.buckets[b]!)}', tone: b.isOverdue ? AppTone.warning : AppTone.neutral),
                  if (item.creditMinor != 0)
                    DialogMetaPill('Alacak: ${formatMinor(item.creditMinor)}', tone: AppTone.success, icon: Icons.arrow_circle_down_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 2. Gelir-gider ----------------------------------------------------------------------------

class _IncomeExpenseReportView extends StatefulWidget {
  const _IncomeExpenseReportView({required this.scope, required this.now, required this.launcher});

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher launcher;

  @override
  State<_IncomeExpenseReportView> createState() => _IncomeExpenseReportViewState();
}

class _IncomeExpenseReportViewState extends _ReportState<_IncomeExpenseReportView, IncomeExpenseReport> {
  @override
  PeopleScope get scope => widget.scope;
  @override
  DateTime Function()? get nowFn => widget.now;
  @override
  FinanceExportLauncher get launcher => widget.launcher;

  late FinancePeriod _from = FinancePeriod.of(today).addMonths(-11);
  late FinancePeriod _to = FinancePeriod.of(today);
  FinancePeriod? _appliedFrom;
  FinancePeriod? _appliedTo;

  FinancePeriod get _maxMonth => FinancePeriod.of(today);
  FinancePeriod get _minMonth => FinancePeriod.of(today).addMonths(-60);

  @override
  String get currentSignature => '${_from.toApi()}|${_to.toApi()}';

  @override
  String? validateFilters() {
    if (_from > _to) return 'Başlangıç ayı bitiş ayından sonra olamaz.';
    final months = (_to.year * 12 + _to.month) - (_from.year * 12 + _from.month) + 1;
    if (months > 36) return 'Rapor en çok 36 ay olabilir. Dönemi daraltın.';
    return null;
  }

  @override
  Future<IncomeExpenseReport> fetch() {
    _appliedFrom = _from;
    _appliedTo = _to;
    return scope.f4Call((api, t, s) => api.getIncomeExpenseReport(token: t, siteCode: s, from: _from, to: _to));
  }

  List<ExportSource> _sources() => <ExportSource>[
    financeExportSource(
      scope: scope,
      label: 'Gelir-Gider',
      kind: 'finance_income_expense',
      icon: Icons.stacked_bar_chart_rounded,
      query: <String, String>{'from': _appliedFrom!.toApi(), 'to': _appliedTo!.toApi()},
      filterSummary: '${_appliedFrom!.label} - ${_appliedTo!.label}',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final report = data;
    final status = statusWidget();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthStepper(
          keyPrefix: 'finance_ie_from',
          label: 'Başlangıç ayı',
          value: _from,
          min: _minMonth,
          max: _maxMonth,
          onChanged: (v) => setState(() => _from = v),
        ),
        const SizedBox(height: AppSpace.sm),
        _MonthStepper(
          keyPrefix: 'finance_ie_to',
          label: 'Bitiş ayı',
          value: _to,
          min: _minMonth,
          max: _maxMonth,
          onChanged: (v) => setState(() => _to = v),
        ),
        const SizedBox(height: AppSpace.md),
        fetchButton(),
        const SizedBox(height: AppSpace.md),
        ?errorBanner(),
        ?staleNote(),
        if (status != null) status else ...[
          metaCard(report!.meta),
          const SizedBox(height: AppSpace.md),
          actions(
            pdfAllowed: canWrite,
            onPdf: (share) => runOutput(() => FinancePdfActions.incomeExpense(report, share: share)),
            exportSources: _sources,
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            key: const ValueKey<String>('finance_ie_totals'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, container: true, child: Text('Dönem toplamı', style: th.titleMedium)),
                const SizedBox(height: AppSpace.sm),
                FinanceInfoRow(label: 'Tahakkuk', money: report.chargedMinor),
                FinanceInfoRow(label: 'Tahsilat', money: report.collectedMinor),
                FinanceInfoRow(label: 'Gider', money: report.expenseMinor),
                FinanceInfoRow(label: 'Net nakit', money: report.netCashMinor, emphasize: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (report.months.isEmpty)
            const EmptyCard(icon: Icons.stacked_bar_chart_rounded, title: 'Bu dönem için ay satırı dönmedi.')
          else
            for (final m in report.months)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: _MonthCard(month: m, final_: report.meta.isFinal(m.period)),
              ),
          if (report.expenseByCategory.isNotEmpty) ...[
            Semantics(header: true, container: true, child: Text('Gider kategorileri', style: th.titleMedium)),
            const SizedBox(height: AppSpace.sm),
            for (final c in report.expenseByCategory) FinanceInfoRow(label: c.categoryName, money: c.totalMinor),
          ],
        ],
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month, required this.final_});

  final IncomeExpenseMonth month;
  final bool final_;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final m = month;
    return AppCard(
      key: ValueKey<String>('finance_ie_month_${m.period.toApi()}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(m.period.label, style: th.titleMedium),
              DialogMetaPill(
                final_ ? 'Kesinleşmiş' : 'Kesinleşmemiş',
                tone: final_ ? AppTone.success : AppTone.warning,
                icon: final_ ? Icons.lock_rounded : Icons.lock_open_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          FinanceInfoRow(label: 'Tahakkuk', money: m.chargedMinor),
          if (m.lateFeeMinor != 0) FinanceInfoRow(label: 'Gecikme tazminatı', money: m.lateFeeMinor),
          FinanceInfoRow(label: 'Tahsilat', money: m.collectedMinor),
          FinanceInfoRow(label: 'Tahsilat oranı', value: percentOrDash(m.collectionRateBp)),
          FinanceInfoRow(label: 'Gider', money: m.expenseMinor),
          FinanceInfoRow(label: 'Net nakit', money: m.netCashMinor, emphasize: true),
        ],
      ),
    );
  }
}

// --- 3. Kasa durumu ----------------------------------------------------------------------------

class _CashPositionReportView extends StatefulWidget {
  const _CashPositionReportView({required this.scope, required this.now, required this.launcher});

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher launcher;

  @override
  State<_CashPositionReportView> createState() => _CashPositionReportViewState();
}

class _CashPositionReportViewState extends _ReportState<_CashPositionReportView, CashPositionReport> {
  @override
  PeopleScope get scope => widget.scope;
  @override
  DateTime Function()? get nowFn => widget.now;
  @override
  FinanceExportLauncher get launcher => widget.launcher;

  late final TextEditingController _asOf = TextEditingController(text: formatDateField(today));
  DateTime? _appliedAsOf;

  @override
  void dispose() {
    _asOf.dispose();
    super.dispose();
  }

  @override
  String get currentSignature => _asOf.text.trim();

  @override
  String? validateFilters() {
    final date = parseDateField(_asOf.text);
    if (date == null) return 'Rapor tarihini GG.AA.YYYY biçiminde girin.';
    if (date.isAfter(today)) return 'Rapor tarihi bugünden ileri olamaz.';
    return null;
  }

  @override
  Future<CashPositionReport> fetch() {
    _appliedAsOf = parseDateField(_asOf.text);
    return scope.f4Call((api, t, s) => api.getCashPositionReport(token: t, siteCode: s, asOf: _appliedAsOf));
  }

  List<ExportSource> _sources() => <ExportSource>[
    financeExportSource(
      scope: scope,
      label: 'Kasa Durumu',
      kind: 'finance_cash_position',
      icon: Icons.account_balance_rounded,
      query: <String, String>{if (_appliedAsOf != null) 'as_of': crmDateParam(_appliedAsOf!)},
      filterSummary: formatCrmDate(_appliedAsOf),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final report = data;
    final status = statusWidget();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey<String>('finance_cash_report_as_of'),
          controller: _asOf,
          keyboardType: TextInputType.number,
          inputFormatters: [DateInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Rapor tarihi',
            hintText: 'GG.AA.YYYY',
            prefixIcon: Icon(Icons.event_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        fetchButton(),
        const SizedBox(height: AppSpace.md),
        ?errorBanner(),
        ?staleNote(),
        if (status != null) status else ...[
          metaCard(report!.meta),
          const SizedBox(height: AppSpace.md),
          if (report.unassigned.any) ...[
            InlineNotice(
              key: const ValueKey<String>('finance_cash_report_unassigned'),
              tone: AppTone.warning,
              message:
                  'Hesaba eşlenmemiş ${report.unassigned.count} tahsilat var (toplam ${formatMinor(report.unassigned.totalMinor)}). Kasa rakamları eksik olabilir.',
              semanticsLabel: spokenMoneyText(
                'Hesaba eşlenmemiş ${report.unassigned.count} tahsilat var (toplam ${formatMinor(report.unassigned.totalMinor)}). Kasa rakamları eksik olabilir.',
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          actions(
            pdfAllowed: canWrite,
            onPdf: (share) => runOutput(() => FinancePdfActions.cashPosition(report, share: share)),
            exportSources: _sources,
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            key: const ValueKey<String>('finance_cash_report_total'),
            padding: listCardPadding(context),
            child: FinanceInfoRow(label: 'Toplam bakiye', money: report.totalBalanceMinor, emphasize: true),
          ),
          const SizedBox(height: AppSpace.md),
          if (report.items.isEmpty)
            const EmptyCard(icon: Icons.account_balance_rounded, title: 'Bu tarihte hesap bulunmuyor.')
          else
            for (final a in report.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: AppCard(
                  key: ValueKey<String>('finance_cash_report_${a.accountId ?? a.name}'),
                  padding: listCardPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpace.sm,
                        children: [
                          DialogMetaPill(a.kind.label, tone: AppTone.info, icon: cashKindIcon(a.kind)),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(a.name, style: th.titleMedium),
                      FinanceInfoRow(label: 'Açılış', money: a.openingMinor),
                      FinanceInfoRow(label: 'Tahsilat', money: a.collectionsMinor),
                      FinanceInfoRow(label: 'Gider', money: a.expensesMinor),
                      FinanceInfoRow(label: 'Aktarım (giriş)', money: a.transfersInMinor),
                      FinanceInfoRow(label: 'Aktarım (çıkış)', money: a.transfersOutMinor),
                      FinanceInfoRow(label: 'Düzeltme', money: a.adjustmentsMinor),
                      FinanceInfoRow(label: 'Ters kayıt', money: a.reversalsMinor),
                      FinanceInfoRow(label: 'Bakiye', money: a.balanceMinor, emphasize: true),
                      if (a.lastReconciliation != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xs),
                          child: FinanceSpokenText(
                            reconciliationSummary(a.lastReconciliation!),
                            style: th.bodySmall?.copyWith(
                              color: a.lastReconciliation!.hasOpenDifference ? AppTone.warning.ink(context.palette) : null,
                              fontWeight: a.lastReconciliation!.hasOpenDifference ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

// --- 4. Daire ekstresi -------------------------------------------------------------------------

class _StatementReportView extends StatefulWidget {
  const _StatementReportView({required this.scope, required this.now, required this.launcher});

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher launcher;

  @override
  State<_StatementReportView> createState() => _StatementReportViewState();
}

class _StatementReportViewState extends _ReportState<_StatementReportView, ApartmentStatement> {
  @override
  PeopleScope get scope => widget.scope;
  @override
  DateTime Function()? get nowFn => widget.now;
  @override
  FinanceExportLauncher get launcher => widget.launcher;

  late final TextEditingController _from = TextEditingController(text: formatDateField(DateTime(today.year, 1, 1)));
  late final TextEditingController _to = TextEditingController(text: formatDateField(today));
  ({int id, String label})? _apartment;
  ({int id, DateTime from, DateTime to})? _applied;
  String? _pickError;
  int _visible = 50;
  bool _picking = false;

  // Daire seçilmeden rapor getirilmez: otomatik yükleme yapılmaz.
  @override
  bool get autoLoad => false;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  String get currentSignature => '${_apartment?.id}|${_from.text.trim()}|${_to.text.trim()}';

  @override
  String? validateFilters() {
    if (_apartment == null) return 'Önce bir daire seçin.';
    final from = parseDateField(_from.text);
    final to = parseDateField(_to.text);
    if (from == null || to == null) return 'Tarihleri GG.AA.YYYY biçiminde girin.';
    if (from.isAfter(to)) return 'Başlangıç tarihi bitiş tarihinden sonra olamaz.';
    if (to.isAfter(today)) return 'Bitiş tarihi bugünden ileri olamaz.';
    return null;
  }

  @override
  String get fallbackError => 'Ekstre alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  @override
  Future<ApartmentStatement> fetch() {
    final apartment = _apartment!;
    final from = parseDateField(_from.text)!;
    final to = parseDateField(_to.text)!;
    _applied = (id: apartment.id, from: from, to: to);
    _visible = 50;
    return scope.f4Call(
      (api, t, s) => api.getApartmentStatement(token: t, siteCode: s, apartmentId: apartment.id, from: from, to: to),
    );
  }

  Future<void> _pick() async {
    if (_picking) return;
    _picking = true;
    try {
      final picked = await showApartmentPicker(context, scope);
      if (picked == null || !mounted) return;
      setState(() {
        _apartment = (id: picked.id, label: picked.fullLabel);
        _pickError = null;
      });
    } finally {
      _picking = false;
    }
  }

  List<ExportSource> _sources() {
    final applied = _applied;
    if (applied == null) return const <ExportSource>[];
    return <ExportSource>[
      financeExportSource(
        scope: scope,
        label: 'Daire Ekstresi',
        kind: 'finance_statement',
        icon: Icons.receipt_long_rounded,
        query: <String, String>{
          'apartment_id': '${applied.id}',
          'from': crmDateParam(applied.from),
          'to': crmDateParam(applied.to),
        },
        filterSummary: '${data?.apartment.label ?? ''} • ${formatCrmDate(applied.from)} - ${formatCrmDate(applied.to)}',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final report = data;
    final hasLoadedOnce = report != null || loading || error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrmPickerField(
          key: const ValueKey<String>('finance_statement_apartment'),
          label: 'Daire',
          icon: Icons.apartment_rounded,
          value: _apartment?.label,
          placeholder: 'Daire seçmek için dokunun',
          errorText: _pickError,
          onTap: _pick,
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey<String>('finance_statement_from'),
          controller: _from,
          keyboardType: TextInputType.number,
          inputFormatters: [DateInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Başlangıç tarihi', hintText: 'GG.AA.YYYY', prefixIcon: Icon(Icons.event_rounded)),
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey<String>('finance_statement_to'),
          controller: _to,
          keyboardType: TextInputType.number,
          inputFormatters: [DateInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Bitiş tarihi', hintText: 'GG.AA.YYYY', prefixIcon: Icon(Icons.event_rounded)),
        ),
        const SizedBox(height: AppSpace.md),
        fetchButton(label: 'Ekstreyi Getir'),
        const SizedBox(height: AppSpace.md),
        ?errorBanner(),
        ?staleNote(),
        if (!hasLoadedOnce)
          Text(
            'Bir daire seçip "Ekstreyi Getir"e basın. Ekstre en çok 5.000 satırdır; uzunsa tarih aralığını daraltın.',
            style: th.bodySmall?.copyWith(color: p.textSecondary),
          )
        else if (statusWidget() != null)
          statusWidget()!
        else ...[
          metaCard(report!.meta),
          const SizedBox(height: AppSpace.md),
          actions(
            pdfAllowed: canWrite,
            onPdf: (share) => runOutput(() => FinancePdfActions.statement(report, share: share)),
            exportSources: _sources,
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            key: const ValueKey<String>('finance_statement_summary'),
            padding: listCardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(financeApartmentTitle(report.apartment.blockName, report.apartment.label), style: th.titleMedium),
                Text('${formatCrmDate(report.from)} - ${formatCrmDate(report.to)}', style: th.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: AppSpace.xs),
                FinanceInfoRow(label: 'Önceki bakiye', money: report.openingBalanceMinor),
                FinanceInfoRow(label: 'Borçlandırılan', money: report.totals.chargedMinor),
                if (report.totals.lateFeeMinor != 0) FinanceInfoRow(label: 'Gecikme tazminatı', money: report.totals.lateFeeMinor),
                FinanceInfoRow(label: 'Ödenen', money: report.totals.paidMinor),
                FinanceInfoRow(label: 'İptal edilen', money: report.totals.reversedMinor),
                FinanceInfoRow(label: 'Dönem sonu bakiye', money: report.closingBalanceMinor, emphasize: true),
                if (report.overdueMinor != null) FinanceInfoRow(label: 'Vadesi geçmiş', money: report.overdueMinor),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (report.items.isEmpty)
            const EmptyCard(
              key: ValueKey<String>('finance_statement_empty'),
              icon: Icons.receipt_long_rounded,
              title: 'Bu aralıkta hareket yok.',
            )
          else ...[
            for (final item in report.items.take(_visible))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LedgerEntryTile(entry: item.entry, showActor: canWrite, showNotes: canWrite, related: const <int, LedgerEntry>{}),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.sm),
                      child: Semantics(
                        label: 'Bakiye: ${moneySemanticLabel(item.runningBalanceMinor)}',
                        child: ExcludeSemantics(
                          child: Text(
                            'Bakiye: ${formatMinor(item.runningBalanceMinor)}',
                            style: th.bodySmall?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (report.items.length > _visible)
              Align(
                child: PrimaryActionButton(
                  key: const ValueKey<String>('finance_statement_more'),
                  label: 'Daha fazla göster (${report.items.length - _visible})',
                  icon: Icons.expand_more_rounded,
                  variant: AppButtonVariant.tonal,
                  expand: false,
                  onPressed: () => setState(() => _visible += 50),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

// --- 5. Yönetim kurulu özeti ----------------------------------------------------------------

class _BoardSummaryReportView extends StatefulWidget {
  const _BoardSummaryReportView({required this.scope, required this.now, required this.launcher});

  final PeopleScope scope;
  final DateTime Function()? now;
  final FinanceExportLauncher launcher;

  @override
  State<_BoardSummaryReportView> createState() => _BoardSummaryReportViewState();
}

class _BoardSummaryReportViewState extends _ReportState<_BoardSummaryReportView, BoardSummaryReport> {
  @override
  PeopleScope get scope => widget.scope;
  @override
  DateTime Function()? get nowFn => widget.now;
  @override
  FinanceExportLauncher get launcher => widget.launcher;

  late FinancePeriod _from = FinancePeriod(today.year, 1);
  late FinancePeriod _to = FinancePeriod.of(today);
  bool _debtorList = false;

  FinancePeriod get _maxMonth => FinancePeriod.of(today);
  FinancePeriod get _minMonth => FinancePeriod.of(today).addMonths(-60);

  @override
  String get currentSignature => '${_from.toApi()}|${_to.toApi()}|$_debtorList';

  @override
  String? validateFilters() {
    if (_from > _to) return 'Başlangıç ayı bitiş ayından sonra olamaz.';
    return null;
  }

  @override
  Future<BoardSummaryReport> fetch() => scope.f4Call(
    (api, t, s) => api.getBoardSummary(token: t, siteCode: s, from: _from, to: _to, includeDebtorList: canWrite && _debtorList),
  );

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final report = data;
    final status = statusWidget();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthStepper(
          keyPrefix: 'finance_board_from',
          label: 'Başlangıç ayı',
          value: _from,
          min: _minMonth,
          max: _maxMonth,
          onChanged: (v) => setState(() => _from = v),
        ),
        const SizedBox(height: AppSpace.sm),
        _MonthStepper(
          keyPrefix: 'finance_board_to',
          label: 'Bitiş ayı',
          value: _to,
          min: _minMonth,
          max: _maxMonth,
          onChanged: (v) => setState(() => _to = v),
        ),
        if (canWrite) ...[
          const SizedBox(height: AppSpace.sm),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey<String>('finance_board_debtor_list'),
              contentPadding: EdgeInsets.zero,
              title: const Text('En yüksek 10 borçlu daireyi ekle'),
              subtitle: const Text('Yalnız etiket ve tutar; kişi adı yok. Kullanımı denetim kaydına işlenir.'),
              value: _debtorList,
              onChanged: (v) => setState(() => _debtorList = v),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        fetchButton(),
        const SizedBox(height: AppSpace.md),
        ?errorBanner(),
        ?staleNote(),
        if (status != null) status else ...[
          metaCard(report!.meta),
          const SizedBox(height: AppSpace.md),
          actions(
            pdfAllowed: true,
            onPdf: (share) => runOutput(() => FinancePdfActions.boardSummary(report, share: share)),
          ),
          const SizedBox(height: AppSpace.md),
          if (report.warnings.isNotEmpty) ...[
            DialogPanel(
              key: const ValueKey<String>('finance_board_warnings'),
              tone: AppTone.warning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(icon: Icons.warning_amber_rounded, title: 'Uyarılar', tone: AppTone.warning),
                  const SizedBox(height: AppSpace.sm),
                  for (final w in report.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: Text('• ${w.message}', style: th.bodyMedium),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          ..._sections(context, report),
          if (report.chargedMinor == null &&
              report.debtTotalMinor == null &&
              report.expenseTotalMinor == null &&
              report.cashTotalMinor == null)
            Text('Sunucu bu dönem için bölüm bilgisi döndürmedi.', style: th.bodySmall?.copyWith(color: p.textSecondary)),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, String key, String title, IconData icon, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        key: ValueKey<String>('finance_board_$key'),
        padding: listCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, container: true, child: DialogSectionTitle(icon: icon, title: title)),
            const SizedBox(height: AppSpace.sm),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, BoardSummaryReport r) {
    final th = Theme.of(context).textTheme;
    return <Widget>[
      if (r.chargedMinor != null || r.collectedMinor != null)
        _section(context, 'collection', 'Tahakkuk ve tahsilat', Icons.payments_rounded, [
          if (r.chargedMinor != null) FinanceInfoRow(label: 'Tahakkuk', money: r.chargedMinor),
          if (r.lateFeeMinor != null) FinanceInfoRow(label: 'Gecikme tazminatı', money: r.lateFeeMinor),
          if (r.collectedMinor != null) FinanceInfoRow(label: 'Tahsilat', money: r.collectedMinor),
          if (r.collectionRateBp != null) FinanceInfoRow(label: 'Tahsilat oranı', value: percentOrDash(r.collectionRateBp)),
        ]),
      if (r.debtTotalMinor != null)
        _section(context, 'receivables', 'Alacak durumu', Icons.hourglass_bottom_rounded, [
          // Sunucu `total_overdue_minor`: yalnız VADESİ GEÇMİŞ borç. Vadesi gelmemiş kova toplama dahil değildir.
          FinanceInfoRow(label: 'Vadesi geçmiş borç', money: r.debtTotalMinor),
          if (r.debtorCount != null)
            FinanceInfoRow(
              label: 'Borçlu daire',
              value: boardDebtorText(r.debtorCount!, r.apartmentCount, r.debtorRateBp),
            ),
          for (final a in r.overdueAging) FinanceInfoRow(label: '${a.label} (${a.count} daire)', money: a.totalMinor),
          if (r.notDueMinor != null)
            FinanceInfoRow(
              key: const ValueKey<String>('finance_board_not_due'),
              label: 'Vadesi gelmemiş (bilgi, toplama dahil değil) (${r.notDueCount ?? 0} daire)',
              money: r.notDueMinor,
            ),
        ]),
      if (r.expenseTotalMinor != null)
        _section(context, 'expenses', 'Gider', Icons.shopping_bag_rounded, [
          FinanceInfoRow(label: 'Toplam gider', money: r.expenseTotalMinor),
          for (final c in r.expenseByCategory) FinanceInfoRow(label: c.categoryName, money: c.totalMinor),
          if (r.topExpenses.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text('En büyük gider kalemleri', style: th.titleSmall),
            for (final e in r.topExpenses)
              FinanceInfoRow(label: '${e.categoryName} • ${formatCrmDate(e.expenseDate)}', money: e.amountMinor),
          ],
        ]),
      if (r.cashAccounts.isNotEmpty || r.cashTotalMinor != null)
        _section(context, 'cash', 'Kasa ve banka', Icons.account_balance_rounded, [
          for (final a in r.cashAccounts) ...[
            FinanceInfoRow(label: a.name, money: a.balanceMinor),
            if (a.lastReconciliation != null && a.lastReconciliation!.hasOpenDifference)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: FinanceSpokenText(
                  'Son mutabakat farkı ${formatMinor(a.lastReconciliation!.differenceMinor)}',
                  style: th.bodySmall?.copyWith(color: AppTone.warning.ink(context.palette), fontWeight: FontWeight.w700),
                ),
              ),
          ],
          if (r.cashTotalMinor != null) FinanceInfoRow(label: 'Toplam', money: r.cashTotalMinor, emphasize: true),
          if (r.unassigned != null && r.unassigned!.any)
            FinanceInfoRow(label: 'Hesaba eşlenmemiş tahsilat (${r.unassigned!.count})', money: r.unassigned!.totalMinor),
        ]),
      if (r.lateFeeTotalMinor != null)
        _section(context, 'late_fee', 'Gecikme tazminatı', Icons.schedule_rounded, [
          FinanceInfoRow(label: 'Dönem toplamı', money: r.lateFeeTotalMinor),
          if (r.lateFeeWaivedCount != null) FinanceInfoRow(label: 'Muaf tutulan daire', value: '${r.lateFeeWaivedCount}'),
        ]),
      if (r.remindersSentCount != null)
        _section(context, 'reminders', 'Borç hatırlatma', Icons.mark_email_read_rounded, [
          FinanceInfoRow(label: 'Gönderilen hatırlatma', value: '${r.remindersSentCount}'),
        ]),
      if (r.debtors.isNotEmpty)
        _section(context, 'debtors', 'En yüksek borçlu daireler', Icons.priority_high_rounded, [
          for (final d in r.debtors) FinanceInfoRow(label: d.label, money: d.totalMinor),
        ]),
    ];
  }
}
