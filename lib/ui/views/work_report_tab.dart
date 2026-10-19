// Yönetim "Rapor" sekmesi (docs/PLATFORM_IS_TAKIBI.md `GET /manager/sites/:siteCode/work-items/report`): dönem ön
// ayarları (Bu ay / Son 30 gün / Son 90 gün / Özel aralık), özet kartları, görevliye ve kategoriye göre dökümler.
//
// - Sekme yalnız yönetici ve kurul için çizilir (kapı WorkManagerView'dadır; görevli ve diğer roller için KAPALI
//   kalır; sunucu da görevliye 403 verir). Bu dosya veriyi çeker ve çizer.
// - Özel aralık GG.AA.YYYY metin alanlarıyla girilir (uygulamada Türkçe takvim yerelleştirmesi yoktur, bkz.
//   ui/helpers/date_input.dart); en çok 366 gün; başlangıç bitişten sonra olamaz; aralık sunucuya `YYYY-AA-GG`
//   gider.
// - Yarış: her istek numaralanır; eski yanıt yeni aralığın ekranına yazılmaz. HATA asla "hareket yok" demez (boş
//   durum yalnız sunucu gerçekten boş toplam verince çizilir). Çözüm süreleri "x sa" / "x gün y sa" yazılır.
// - Taşma: özet kartları sütun sayısını genişliğe göre seçer; görevli dökümü geniş ekranda tablo, dar ekranda ve
//   büyük yazıda kart kart (hiçbir hücre kırpılmaz).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Dönem ön ayarı.
enum WorkReportPreset {
  thisMonth('this_month', 'Bu ay'),
  last30('last_30', 'Son 30 gün'),
  last90('last_90', 'Son 90 gün'),
  custom('custom', 'Özel aralık');

  const WorkReportPreset(this.key, this.label);

  final String key;
  final String label;
}

/// Özel aralıkta izin verilen en uzun süre (gün, iki uç dahil).
const int kWorkReportMaxDays = 366;

/// Rapor sekmesi yalnız bu erişim türlerine çizilir (fail-closed: liste dışı her şey kapalı).
bool workReportAllowed(WorkSiteAccess access) =>
    access == WorkSiteAccess.manager || access == WorkSiteAccess.board;

/// Takvim gününün UTC gün numarası: cihazın yaz saati geçişi gün farkını bir saat kaydırıp sayımı bozmasın
/// (sunucu da iki uç dahil gün sayar: `to - from + 1 <= 366`).
int _dayNumber(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

class WorkReportTab extends StatefulWidget {
  const WorkReportTab({
    super.key,
    required this.service,
    required this.site,
    this.now,
  });

  final WorkTrackingService service;
  final WorkTrackingSite site;

  /// Şimdi (testler içindir); verilmezse cihaz saati (İstanbul duvar saatine çevrilir).
  final DateTime Function()? now;

  @override
  State<WorkReportTab> createState() => WorkReportTabState();
}

class WorkReportTabState extends State<WorkReportTab> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fromField = TextEditingController();
  final TextEditingController _toField = TextEditingController();

  WorkReportPreset _preset = WorkReportPreset.thisMonth;
  late DateTime _from;
  late DateTime _to;
  String? _rangeError;

  WorkReport? _report;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    final (from, to) = _presetRange(WorkReportPreset.thisMonth);
    _from = from;
    _to = to;
    _syncFields();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(WorkReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.code != widget.site.code ||
        !identical(oldWidget.service, widget.service)) {
      _report = null;
      _error = null;
      _loadedOnce = false;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_token;
    _fromField.dispose();
    _toField.dispose();
    super.dispose();
  }

  /// Bugün (İstanbul takvim günü).
  DateTime _today() {
    final wall = istanbulNow(widget.now?.call());
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// Ön ayarın (başlangıç, bitiş) takvim günleri; özel aralıkta mevcut seçim.
  (DateTime, DateTime) _presetRange(WorkReportPreset preset) {
    final today = _today();
    return switch (preset) {
      WorkReportPreset.thisMonth => (DateTime(today.year, today.month, 1), today),
      WorkReportPreset.last30 => (DateTime(today.year, today.month, today.day - 29), today),
      WorkReportPreset.last90 => (DateTime(today.year, today.month, today.day - 89), today),
      WorkReportPreset.custom => (_from, _to),
    };
  }

  void _syncFields() {
    _fromField.text = formatDateField(_from);
    _toField.text = formatDateField(_to);
  }

  /// Raporu yeniden çeker (sayfa kabuğunun çekip yenilemesi ve yenile düğmesi). Ön ayarlı dönem BUGÜNE göre yeniden
  /// hesaplanır (sekme açıkken gece yarısı / ay dönümü geçtiyse "Bu ay" yeni ayı gösterir); özel aralık korunur.
  Future<void> reload() {
    if (_preset != WorkReportPreset.custom && mounted) {
      final (from, to) = _presetRange(_preset);
      if (from != _from || to != _to) {
        setState(() {
          _from = from;
          _to = to;
          _syncFields();
        });
      }
    }
    return _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final token = ++_token;
    final from = _from;
    final to = _to;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.service.report(widget.site.code, from: from, to: to);
      if (!mounted || token != _token) return;
      setState(() {
        _report = report;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _error = crmMessageOf(
          e,
          'Rapor yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  void _selectPreset(WorkReportPreset preset) {
    if (preset == _preset) return;
    if (preset == WorkReportPreset.custom) {
      setState(() {
        _preset = preset;
        _rangeError = null;
        _syncFields();
      });
      return;
    }
    final (from, to) = _presetRange(preset);
    setState(() {
      _preset = preset;
      _from = from;
      _to = to;
      _rangeError = null;
      _syncFields();
    });
    unawaited(_load());
  }

  /// Özel aralık: iki alan da geçerli tarih, başlangıç <= bitiş, en çok [kWorkReportMaxDays] gün.
  void _applyCustom() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() => _rangeError = null);
      return;
    }
    final from = parseDateField(_fromField.text);
    final to = parseDateField(_toField.text);
    if (from == null || to == null) return;
    String? error;
    if (from.isAfter(to)) {
      error = 'Başlangıç tarihi bitiş tarihinden sonra olamaz.';
    } else if (_dayNumber(to) - _dayNumber(from) + 1 > kWorkReportMaxDays) {
      error = 'Aralık en çok $kWorkReportMaxDays gün olabilir.';
    } else if (from.year < 1990) {
      error = 'Başlangıç tarihi 1990 ve sonrası olmalıdır.';
    }
    setState(() => _rangeError = error);
    if (error != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _from = from;
      _to = to;
    });
    unawaited(_load());
  }

  String? _requiredDate(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Tarih girin (GG.AA.YYYY).';
    return validateDateField(value);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final report = _report;
    return Column(
      key: const ValueKey<String>('work_report_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodCard(context),
        const SizedBox(height: AppSpace.md),
        SectionHeader(
          title: 'Özet',
          trailing: IconButton(
            onPressed: _loading ? null : reload,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          _rangeCaption(report),
          key: const ValueKey<String>('work_report_range'),
          style: th.bodySmall,
        ),
        const SizedBox(height: AppSpace.md),
        if (report == null && (_loading || !_loadedOnce))
          const ListSkeleton(rows: 3)
        else if (report == null)
          InlineNotice(
            key: const ValueKey<String>('work_report_error'),
            message: _error ?? 'Rapor yüklenemedi.',
            onRetry: reload,
          )
        else ...[
          if (_error != null) ...[
            InlineNotice(
              key: const ValueKey<String>('work_report_error'),
              message: _error!,
              onRetry: reload,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          if (report.isEmpty)
            const EmptyCard(
              key: ValueKey<String>('work_report_empty'),
              icon: Icons.insights_rounded,
              title: 'Bu aralıkta talep hareketi yok.',
              message: 'Başka bir dönem seçebilirsiniz.',
            )
          else ...[
            _totals(context, report.totals),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader(title: 'Görevliye göre'),
            const SizedBox(height: AppSpace.md),
            _assignees(context, report.byAssignee),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader(title: 'Kategoriye göre'),
            const SizedBox(height: AppSpace.md),
            _categories(context, report.byCategory),
          ],
        ],
      ],
    );
  }

  String _rangeCaption(WorkReport? report) {
    final from = report?.from ?? _from;
    final to = report?.to ?? _to;
    final generated = report?.generatedAt;
    final range = '${formatDateField(from)} – ${formatDateField(to)}';
    if (generated == null) return range;
    return '$range · Hesaplanma: ${formatIstanbulDateTime(generated)}';
  }

  Widget _periodCard(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final custom = _preset == WorkReportPreset.custom;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dönem', style: th.titleSmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final preset in WorkReportPreset.values)
                ChoiceChip(
                  key: ValueKey<String>('work_report_preset_${preset.key}'),
                  label: Text(preset.label),
                  selected: _preset == preset,
                  onSelected: (_) => _selectPreset(preset),
                ),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: AppSpace.md),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey<String>('work_report_from'),
                    controller: _fromField,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: const [DateInputFormatter()],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Başlangıç',
                      hintText: 'GG.AA.YYYY',
                      prefixIcon: Icon(Icons.event_rounded),
                    ),
                    validator: _requiredDate,
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    key: const ValueKey<String>('work_report_to'),
                    controller: _toField,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: const [DateInputFormatter()],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _applyCustom(),
                    decoration: const InputDecoration(
                      labelText: 'Bitiş',
                      hintText: 'GG.AA.YYYY',
                      prefixIcon: Icon(Icons.event_available_rounded),
                    ),
                    validator: _requiredDate,
                  ),
                  if (_rangeError != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    InlineNotice(
                      key: const ValueKey<String>('work_report_range_error'),
                      message: _rangeError!,
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  PrimaryActionButton(
                    key: const ValueKey<String>('work_report_apply'),
                    label: 'Uygula',
                    icon: Icons.check_rounded,
                    variant: AppButtonVariant.tonal,
                    onPressed: _loading ? null : _applyCustom,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'En çok $kWorkReportMaxDays günlük bir aralık seçilebilir.',
                    style: th.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totals(BuildContext context, WorkReportTotals t) {
    final tiles = <(String, String, AppTone, String)>[
      ('Açılan', '${t.opened}', AppTone.info, 'opened'),
      ('Çözülen', '${t.resolved}', AppTone.success, 'resolved'),
      ('Kapanan', '${t.closed}', AppTone.neutral, 'closed'),
      ('İptal', '${t.cancelled}', AppTone.danger, 'cancelled'),
      ('Şu an açık', '${t.openNow}', AppTone.primary, 'open_now'),
      (
        'Gecikmiş',
        '${t.overdueNow}',
        t.overdueNow > 0 ? AppTone.warning : AppTone.neutral,
        'overdue_now',
      ),
      ('Ort. çözüm süresi', workHoursText(t.avgResolutionHours), AppTone.primary, 'avg'),
      ('Medyan çözüm süresi', workHoursText(t.medianResolutionHours), AppTone.primary, 'median'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final columns = maxWidth >= 560 ? 4 : 2;
        final width = (maxWidth - AppSpace.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final (label, value, tone, key) in tiles)
              SizedBox(
                width: width,
                child: _StatTile(
                  key: ValueKey<String>('work_report_total_$key'),
                  label: label,
                  value: value,
                  tone: tone,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _assignees(BuildContext context, List<WorkReportAssignee> rows) {
    final th = Theme.of(context).textTheme;
    if (rows.isEmpty) {
      return Text(
        'Bu aralıkta görevli dökümü yok.',
        key: const ValueKey<String>('work_report_assignees_empty'),
        style: th.bodyMedium,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final wide = constraints.maxWidth.isFinite &&
            constraints.maxWidth >= 600 &&
            scale <= 1.3;
        return wide ? _assigneeTable(context, rows) : _assigneeCards(context, rows);
      },
    );
  }

  Widget _assigneeTable(BuildContext context, List<WorkReportAssignee> rows) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final head = th.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: p.textSecondary);
    final cell = th.bodyMedium?.copyWith(color: p.text);
    Widget pad(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
      child: child,
    );
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Table(
        key: const ValueKey<String>('work_report_assignee_table'),
        columnWidths: const <int, TableColumnWidth>{0: FlexColumnWidth(2.2)},
        defaultColumnWidth: const FlexColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(horizontalInside: BorderSide(color: p.border)),
        children: [
          TableRow(
            children: [
              pad(Text('Görevli', style: head)),
              pad(Text('Açık', style: head)),
              pad(Text('Gecikmiş', style: head)),
              pad(Text('Çözülen', style: head)),
              pad(Text('Ort. süre', style: head)),
              pad(Text('Zamanında', style: head)),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                pad(Text(row.label, style: cell)),
                pad(Text('${row.openNow}', style: cell)),
                pad(Text('${row.overdueNow}', style: cell)),
                pad(Text('${row.resolved}', style: cell)),
                pad(Text(workHoursText(row.avgResolutionHours), style: cell)),
                pad(Text(workRateText(row.onTimeRate), style: cell)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _assigneeCards(BuildContext context, List<WorkReportAssignee> rows) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : AppSpace.sm),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpace.md),
              semanticLabel:
                  '${rows[i].label}. Açık ${rows[i].openNow}, gecikmiş ${rows[i].overdueNow}, '
                  'çözülen ${rows[i].resolved}, ortalama süre ${workHoursText(rows[i].avgResolutionHours)}, '
                  'zamanında ${workRateText(rows[i].onTimeRate)}.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rows[i].label, style: th.titleMedium),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        InfoChip('Açık: ${rows[i].openNow}'),
                        InfoChip(
                          'Gecikmiş: ${rows[i].overdueNow}',
                          tone: rows[i].overdueNow > 0 ? AppTone.warning : null,
                        ),
                        InfoChip('Çözülen: ${rows[i].resolved}'),
                        InfoChip('Ort. süre: ${workHoursText(rows[i].avgResolutionHours)}'),
                        InfoChip('Zamanında: ${workRateText(rows[i].onTimeRate)}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _categories(BuildContext context, List<WorkReportCategory> rows) {
    final th = Theme.of(context).textTheme;
    if (rows.isEmpty) {
      return Text(
        'Bu aralıkta kategori dökümü yok.',
        key: const ValueKey<String>('work_report_categories_empty'),
        style: th.bodyMedium,
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : AppSpace.sm),
              child: MergeSemantics(
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(rows[i].label, style: th.titleSmall),
                    InfoChip('Açılan: ${rows[i].opened}'),
                    InfoChip('Çözülen: ${rows[i].resolved}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Özet kartı: etiket + değer (metin sarar, kırpılmaz).
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    return MergeSemantics(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: th.bodySmall?.copyWith(color: p.textSecondary)),
            const SizedBox(height: AppSpace.xs),
            Text(
              value,
              style: th.titleLarge?.copyWith(color: tone.ink(p)),
            ),
          ],
        ),
      ),
    );
  }
}
