import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_charts.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/finance_errors.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart' show FinanceInfoRow;
import 'package:site_kapi_kontrol/ui/widgets/finance_charts_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

/// "Grafikler" sekmesi: son 12 ayın finansal durumu beş grafikle (aylık gelir-gider, aidat tahsilatı, kasa + banka seyri,
/// gider kategorileri, geciken borç yaşlandırması). Tek salt okunur uç (`GET reports/charts`); yönetici ve kurul görür.
///
/// Kurallar: hata "veri yok / sıfır" demez ("Tekrar Dene" gösterilir ve eski grafik bırakılmaz); hız sınırı (429)
/// sonrası düğme geçici kilitlenir; yenilemede eski grafik yeni yanıt gelene dek kalır (yanıt gelince ya da hata olunca atılır).
class FinanceChartsTab extends StatefulWidget {
  const FinanceChartsTab({super.key, required this.scope, this.months = 12});

  final PeopleScope scope;
  final int months;

  @override
  State<FinanceChartsTab> createState() => FinanceChartsTabState();
}

class FinanceChartsTabState extends State<FinanceChartsTab> {
  FinanceCharts? _data;
  bool _loading = true;
  String? _error;
  int _token = 0;
  final RetryLock _retry = RetryLock();

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(FinanceChartsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.siteCode != widget.scope.siteCode) {
      _data = null;
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_token;
    _retry.dispose();
    super.dispose();
  }

  /// Grafikleri yeniden çeker (üst ekran "yenile" ve bayat sekme).
  Future<void> reload() async {
    if (!mounted || _retry.locked) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.scope.f4Call((api, t, s) => api.getFinanceCharts(token: t, siteCode: s, months: widget.months));
      if (!mounted || token != _token) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      final limited = _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      setState(() {
        _loading = false;
        // Eski grafik hata uyarısının altında güncelmiş gibi durmasın.
        _data = null;
        _error = limited
            ? RetryLock.messageFor(e)
            : financeMessageOf(e, 'Grafikler alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final data = _data;
    return Column(
      key: const ValueKey<String>('finance_charts_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Grafikler',
          trailing: IconButton(
            key: const ValueKey<String>('finance_charts_refresh'),
            onPressed: (_loading || _retry.locked) ? null : reload,
            tooltip: 'Grafikleri yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Son ${widget.months} ayın finansal durumu. Her grafiğin altındaki anahtarla aynı rakamları tablo olarak da görebilirsiniz.',
          style: th.bodyMedium,
        ),
        const SizedBox(height: AppSpace.md),
        if (data == null)
          if (_error != null)
            InlineNotice(
              key: const ValueKey<String>('finance_charts_error'),
              message: _error!,
              onRetry: (_loading || _retry.locked) ? null : reload,
            )
          else
            const ListSkeleton(key: ValueKey<String>('finance_charts_loading'), rows: 3)
        else
          ..._cards(data),
      ],
    );
  }

  List<Widget> _cards(FinanceCharts data) {
    final terms = widget.scope.terms;
    final months = data.months;
    final count = months.length;
    final income = chartSeriesColor(context, AppTone.success);
    final expense = chartSeriesColor(context, AppTone.warning);
    final written = chartSeriesColor(context, AppTone.info);
    final cash = chartSeriesColor(context, AppTone.info);

    final rate = data.overallRateBp;
    final lastCash = months.isEmpty ? null : months.last.cashBalanceMinor;

    // Gider kategorileri: ilk 6 + "Diğer".
    final cats = data.categories;
    final totalCats = cats.fold<int>(0, (a, c) => a + c.totalMinor);
    final catRows = <ChartBarRow>[
      for (final c in cats.take(6)) ChartBarRow(label: c.name, minor: c.totalMinor, color: expense),
      if (cats.length > 6) ChartBarRow(label: 'Diğer', minor: cats.skip(6).fold<int>(0, (a, c) => a + c.totalMinor), color: expense),
    ];

    final aging = data.aging;
    final danger = chartSeriesColor(context, AppTone.danger);
    final agingRows = <ChartBarRow>[
      ChartBarRow(label: '0-30 gün', minor: aging.d0to30Minor, color: expense),
      ChartBarRow(label: '31-60 gün', minor: aging.d31to60Minor, color: expense),
      ChartBarRow(label: '61-90 gün', minor: aging.d61to90Minor, color: danger),
      ChartBarRow(label: '90 günden fazla', minor: aging.d91plusMinor, color: danger),
    ];
    final unit = terms.unit.toLowerCase();

    return <Widget>[
      FinanceChartCard(
        id: 'income_expense',
        title: 'Aylık gelir ve gider',
        description: 'Her ay kasaya giren tahsilat ile yapılan gider. Son $count ayda ${formatMinor(data.totalCollectedMinor)} tahsil edildi, '
            '${formatMinor(data.totalExpenseMinor)} harcandı.',
        hasData: data.hasIncomeExpense,
        footnote: 'Tutarlar lira; B bin, Mn milyon demektir. Ay içinde iptal edilen gider çizimde sıfır görünür, tabloda gerçek değeri yazar.',
        chart: ChartPairBars(
          months: months,
          first: (m) => m.collectedMinor,
          second: (m) => m.expenseMinor,
          firstColor: income,
          secondColor: expense,
          firstLabel: 'Gelir (tahsilat)',
          secondLabel: 'Gider',
          summaryTitle: 'Aylık gelir ve gider grafiği',
        ),
        table: ChartMonthTable(
          months: months,
          lines: (m) => <ChartTableLine>[
            (label: 'Gelir (tahsilat)', minor: m.collectedMinor, text: null),
            (label: 'Gider', minor: m.expenseMinor, text: null),
            (label: 'Fark', minor: m.collectedMinor - m.expenseMinor, text: null),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      FinanceChartCard(
        id: 'collection',
        title: '${terms.fee} tahsilatı',
        description: 'Her ay yazılan borç ile toplanan tutar ve toplanma yüzdesi. Gecikme bedelleri yazılan borca dahildir.'
            '${rate == null ? '' : ' Son $count ayda toplanma oranı: ${chartPercent(rate)}.'}',
        hasData: data.hasCollection,
        footnote: 'Tutarlar lira; B bin, Mn milyon demektir. Borç yazılmayan ayın yüzdesi yoktur.',
        chart: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChartPairBars(
              months: months,
              first: (m) => m.writtenMinor,
              second: (m) => m.collectedMinor,
              firstColor: written,
              secondColor: income,
              firstLabel: 'Yazılan borç',
              secondLabel: 'Toplanan',
              summaryTitle: '${terms.fee} tahsilatı grafiği',
            ),
            const SizedBox(height: AppSpace.lg),
            Semantics(header: true, container: true, child: Text('Toplanma yüzdesi', style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: AppSpace.sm),
            ChartLine(
              months: months,
              values: <int?>[for (final m in months) m.collectionRateBp],
              color: income,
              legend: 'Toplanan / yazılan (%)',
              summaryTitle: 'Aylık toplanma yüzdesi grafiği',
              spoken: (bp) => 'yüzde ${(bp + 50) ~/ 100}',
              percent: true,
              height: 150,
            ),
          ],
        ),
        table: ChartMonthTable(
          months: months,
          lines: (m) => <ChartTableLine>[
            (label: 'Yazılan borç', minor: m.writtenMinor, text: null),
            (label: 'Toplanan', minor: m.collectedMinor, text: null),
            (label: 'Toplanma yüzdesi', minor: null, text: m.collectionRateBp == null ? 'Borç yazılmadı' : chartPercent(m.collectionRateBp)),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      FinanceChartCard(
        id: 'cash',
        title: 'Kasa ve banka bakiyesi',
        description: 'Tüm kasa ve banka hesaplarındaki toplam para; her ayın sonu, bu ay için bugün.'
            '${lastCash == null ? '' : ' Şu an toplam ${formatMinor(lastCash)}.'}',
        hasData: data.hasCash,
        emptyHint: 'Kasa sekmesinden hesap ekleyince burada görünür.',
        footnote: 'Tutarlar lira; B bin, Mn milyon demektir. Hesap eklenmeden önceki aylar boş kalır.',
        chart: ChartLine(
          months: months,
          values: <int?>[for (final m in months) m.cashBalanceMinor],
          color: cash,
          legend: 'Kasa + banka toplamı',
          summaryTitle: 'Kasa ve banka bakiyesi grafiği',
          spoken: moneySemanticLabel,
        ),
        table: ChartMonthTable(
          months: months,
          lines: (m) => <ChartTableLine>[
            (label: 'Kasa + banka toplamı', minor: m.cashBalanceMinor, text: 'Hesap yok'),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      FinanceChartCard(
        id: 'categories',
        title: 'Gider kategorileri',
        description: 'Son $count ayda paranın nereye harcandığı. Toplam gider ${formatMinor(totalCats)}.',
        hasData: data.hasCategories,
        chart: ChartBarRows(rows: catRows, total: totalCats, rowKeyPrefix: 'finance_chart_category'),
        table: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in cats) FinanceInfoRow(label: c.name, money: c.totalMinor),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      FinanceChartCard(
        id: 'aging',
        title: 'Geciken borçlar',
        description: 'Vadesi geçmiş borçların kaç gündür ödenmediğine göre dağılımı (bugün itibarıyla). '
            'Toplam ${formatMinor(aging.totalOverdueMinor)}, ${aging.debtorCount} $unit borçlu.',
        hasData: data.hasAging,
        emptyHint: 'Şu an vadesi geçmiş borç görünmüyor.',
        chart: ChartBarRows(rows: agingRows, total: aging.totalOverdueMinor, rowKeyPrefix: 'finance_chart_aging'),
        table: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in agingRows) FinanceInfoRow(label: r.label, money: r.minor),
            FinanceInfoRow(label: 'Toplam geciken', money: aging.totalOverdueMinor, emphasize: true),
          ],
        ),
      ),
    ];
  }
}
