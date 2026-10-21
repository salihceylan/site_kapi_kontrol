import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/expense_analysis.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// Gider analizi grafiği (R1): ay başına gider yığını (rutin altta, beklenmedik üstte) ve yanında gelir çubuğu.
///
/// Erişilebilirlik: grafiğin tamamı tek `Semantics` özetiyle okunur (ayrıntı için ekran "Tablo olarak göster" sunar);
/// `MediaQuery.disableAnimations` açıkken animasyon süresi sıfırdır; renkler palet tonlarından gelir, anlam efsanede yazılıdır.
/// Negatif net değerler (sonraki dönemde iptal) çizimde 0'a sabitlenir; tabloda gerçek değer görünür.
class ExpenseAnalysisChart extends StatelessWidget {
  const ExpenseAnalysisChart({super.key, required this.months});

  final List<AnalysisMonth> months;

  static String shortLabel(String period) {
    if (period.length < 7) return period;
    return '${period.substring(5, 7)}.${period.substring(2, 4)}';
  }

  /// Ekran okuyucu özeti.
  static String summary(List<AnalysisMonth> months) {
    if (months.isEmpty) return 'Grafik: veri yok.';
    final parts = <String>[
      for (final m in months)
        '${shortLabel(m.period)}: gider ${formatMinor(m.expenseMinor)}, rutin ${formatMinor(m.routineMinor)}, '
            'beklenmedik ${formatMinor(m.unexpectedMinor)}, gelir ${formatMinor(m.incomeMinor)}',
    ];
    return 'Aylık gider ve gelir grafiği. ${parts.join('. ')}.';
  }

  static double _y(int minor) => minor <= 0 ? 0 : minor / 100.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final routine = AppTone.info.hue;
    final unexpected = AppTone.warning.hue;
    final income = AppTone.success.hue;
    var maxY = 1.0;
    for (final m in months) {
      final top = _y(m.expenseMinor) > _y(m.incomeMinor) ? _y(m.expenseMinor) : _y(m.incomeMinor);
      if (top > maxY) maxY = top;
    }
    final groups = <BarChartGroupData>[
      for (var i = 0; i < months.length; i++)
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          barRods: [
            BarChartRodData(
              toY: _y(months[i].expenseMinor),
              width: 14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              rodStackItems: [
                BarChartRodStackItem(0, _y(months[i].routineMinor), routine),
                BarChartRodStackItem(_y(months[i].routineMinor), _y(months[i].routineMinor) + _y(months[i].unexpectedMinor), unexpected),
              ],
            ),
            BarChartRodData(
              toY: _y(months[i].incomeMinor),
              width: 8,
              color: income,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: summary(months),
          container: true,
          excludeSemantics: true,
          child: SizedBox(
            key: const ValueKey<String>('expense_analysis_chart'),
            height: 220,
            child: BarChart(
              duration: AppMotion.of(context, AppMotion.base),
              BarChartData(
                maxY: maxY * 1.1,
                alignment: BarChartAlignment.spaceAround,
                barGroups: groups,
                gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= months.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(shortLabel(months[i].period), style: th.bodySmall?.copyWith(color: p.textSecondary)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.xs,
          children: [
            _Legend(color: routine, label: 'Rutin gider'),
            _Legend(color: unexpected, label: 'Beklenmedik gider'),
            _Legend(color: income, label: 'Gelir (net tahsilat)'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(label, style: th.bodySmall)),
      ],
    );
  }
}
