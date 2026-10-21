import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_charts.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart' show FinanceInfoRow;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show listCardPadding;

/// Finans > Grafikler'in çizim parçaları.
///
/// Kurallar:
/// - Her grafik kartı: başlık, tek cümlelik açıklama (yöneticinin dili), grafik, "Tablo olarak göster" anahtarı (grafiğin
///   altında; erişilebilir eşdeğer) ve kayıt yoksa "Bu dönemde kayıt yok". Hata "kayıt yok" demez (üst ekran hata gösterir).
/// - Grafiğin tamamı tek `Semantics` özetiyle okunur; tutarlar rakam yığını değil okunuşla ("bin iki yüz lira").
/// - Renk tek başına anlam taşımaz: efsane + eksen etiketi + tablo. Seri renkleri palet tonlarından gelir
///   (açık temada koyu ton, koyu temada canlı ton; zemine karşı en az 3:1).
/// - Eksen yazıları en çok 1,3x büyür (büyük yazıda grafik taşmaz); asıl değerler tabloda ve açıklamada tam ölçekte.
/// - Grafik koordinatları kayan nokta (yalnız çizim); para hesabı tamsayı kuruştur.
/// - `MediaQuery.disableAnimations` açıkken animasyon yoktur.

const String kChartEmptyText = 'Bu dönemde kayıt yok';

const List<String> _shortMonths = <String>['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// '2026-10' -> 'Eki' (okunamazsa metin aynen).
String chartMonthLabel(String period) {
  final parts = period.split('-');
  final m = parts.length >= 2 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return period;
  return _shortMonths[m - 1];
}

/// Seri rengi: açık temada koyu ton (beyaz zemine karşı >= 3:1), koyu temada canlı ton.
Color chartSeriesColor(BuildContext context, AppTone tone) => context.palette.isDark ? tone.hue : tone.a;

/// "%83" (en yakın tam yüzde); oran yoksa "-".
String chartPercent(int? bp) => bp == null ? '-' : '%${(bp + 50) ~/ 100}';

/// Eksen etiketi için kısa tutar: 1250 -> "1.250", 12500 -> "12,5 B", 1.5e6 -> "1,5 Mn" (yalnız görüntü).
String compactLira(double value) {
  final negative = value < 0;
  final a = value.abs();
  String one(double x) {
    final r = (x * 10).round() / 10;
    return r == r.truncateToDouble() ? r.toInt().toString() : r.toStringAsFixed(1).replaceAll('.', ',');
  }

  final String text;
  if (a >= 1000000) {
    text = '${one(a / 1000000)} Mn';
  } else if (a >= 10000) {
    text = '${one(a / 1000)} B';
  } else {
    final whole = a.round().toString();
    text = whole.length > 3 ? '${whole.substring(0, whole.length - 3)}.${whole.substring(whole.length - 3)}' : whole;
  }
  return negative ? '-$text' : text;
}

/// Eksen aralığı: 1, 2, 5 x 10^k (yaklaşık [ticks] aralık); en az 1 lira.
double niceInterval(double maxValue, {int ticks = 4}) {
  if (maxValue <= 0) return 1;
  final raw = maxValue / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / magnitude;
  final nice = norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10));
  return math.max(1.0, nice * magnitude);
}

double _lira(int minor) => minor / 100.0;

// --- Kart ---------------------------------------------------------------------------------------

/// Grafik kartı: başlık + açıklama + (grafik | tablo | kayıt yok) + "Tablo olarak göster".
class FinanceChartCard extends StatefulWidget {
  const FinanceChartCard({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.hasData,
    required this.chart,
    required this.table,
    this.emptyHint,
    this.footnote,
  });

  /// Anahtar soneki: `finance_chart_card_<id>`, `finance_chart_<id>`, `finance_chart_table_<id>`, `finance_chart_empty_<id>`.
  final String id;
  final String title;
  final String description;
  final bool hasData;
  final Widget chart;
  final Widget table;

  /// Kayıt yoksa "Bu dönemde kayıt yok" altına küçük ipucu (örn. "Kasa sekmesinden hesap ekleyin.").
  final String? emptyHint;

  /// Grafiğin altına küçük not (örn. eksen birimi).
  final String? footnote;

  @override
  State<FinanceChartCard> createState() => _FinanceChartCardState();
}

class _FinanceChartCardState extends State<FinanceChartCard> {
  bool _asTable = false;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      key: ValueKey<String>('finance_chart_card_${widget.id}'),
      padding: listCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, container: true, child: Text(widget.title, style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(height: AppSpace.xs),
          Text(
            widget.description,
            key: ValueKey<String>('finance_chart_desc_${widget.id}'),
            semanticsLabel: spokenMoneyText(widget.description),
            style: th.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          if (!widget.hasData) ...[
            Text(kChartEmptyText, key: ValueKey<String>('finance_chart_empty_${widget.id}'), style: th.titleSmall),
            if (widget.emptyHint != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(widget.emptyHint!, style: th.bodyMedium?.copyWith(color: p.textSecondary)),
            ],
          ] else ...[
            if (_asTable)
              KeyedSubtree(key: ValueKey<String>('finance_chart_table_${widget.id}'), child: widget.table)
            else
              KeyedSubtree(key: ValueKey<String>('finance_chart_${widget.id}'), child: widget.chart),
            if (!_asTable && widget.footnote != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(widget.footnote!, style: th.bodySmall?.copyWith(color: p.textSecondary)),
            ],
            SwitchListTile(
              key: ValueKey<String>('finance_chart_table_switch_${widget.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Tablo olarak göster', style: th.bodyMedium),
              value: _asTable,
              onChanged: (v) => setState(() => _asTable = v),
            ),
          ],
        ],
      ),
    );
  }
}

/// Efsane satırı (renk kutusu + ad).
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.xs,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text(label, style: th.bodySmall)),
            ],
          ),
      ],
    );
  }
}

// --- Eksenler -----------------------------------------------------------------------------------

TextScaler _axisScaler(BuildContext context) => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

Widget _axisText(BuildContext context, String text) {
  final p = context.palette;
  return Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.visible,
    textScaler: _axisScaler(context),
    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textSecondary, fontSize: 11),
  );
}

const double _leftAxisWidth = 44;

/// Kaç ayda bir etiket yazılır (dar ekranda seyreltilir; son ay hep yazılır).
int _labelStep(double slotWidth) => slotWidth >= 30 ? 1 : (slotWidth >= 15 ? 2 : 3);

FlTitlesData _titles(
  BuildContext context, {
  required List<String> labels,
  required int step,
  required double interval,
  required String Function(double value) leftLabel,
  bool leftTitles = true,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: leftTitles,
        reservedSize: _leftAxisWidth,
        interval: interval,
        getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, space: 4, child: _axisText(context, leftLabel(value))),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if ((value - i).abs() > 0.01 || i < 0 || i >= labels.length || (labels.length - 1 - i) % step != 0) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, child: _axisText(context, labels[i]));
        },
      ),
    ),
  );
}

FlGridData _grid(BuildContext context, double interval) => FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) => FlLine(color: context.palette.border, strokeWidth: 1),
);

// --- İkili çubuk (gelir-gider, yazılan-toplanan) ------------------------------------------------

/// Ay başına iki çubuk. Negatif değer çizimde 0'a sabitlenir (tabloda gerçek değer görünür).
class ChartPairBars extends StatelessWidget {
  const ChartPairBars({
    super.key,
    required this.months,
    required this.first,
    required this.second,
    required this.firstColor,
    required this.secondColor,
    required this.firstLabel,
    required this.secondLabel,
    required this.summaryTitle,
  });

  final List<FinanceChartMonth> months;
  final int Function(FinanceChartMonth) first;
  final int Function(FinanceChartMonth) second;
  final Color firstColor;
  final Color secondColor;
  final String firstLabel;
  final String secondLabel;
  final String summaryTitle;

  static double _y(int minor) => minor <= 0 ? 0 : _lira(minor);

  String summary() {
    if (months.isEmpty) return '$summaryTitle: veri yok.';
    final parts = <String>[
      for (final m in months) '${m.title}: $firstLabel ${moneySemanticLabel(first(m))}, $secondLabel ${moneySemanticLabel(second(m))}',
    ];
    return '$summaryTitle. ${parts.join('. ')}.';
  }

  @override
  Widget build(BuildContext context) {
    var maxV = 0.0;
    for (final m in months) {
      maxV = math.max(maxV, math.max(_y(first(m)), _y(second(m))));
    }
    final interval = niceInterval(maxV);
    final maxY = math.max(interval, (maxV / interval).ceil() * interval);
    final labels = <String>[for (final m in months) chartMonthLabel(m.period)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final slot = months.isEmpty ? 40.0 : (c.maxWidth - _leftAxisWidth) / months.length;
            final rodWidth = (slot / 3.2).clamp(3.0, 12.0).toDouble();
            return Semantics(
              label: summary(),
              container: true,
              excludeSemantics: true,
              child: SizedBox(
                height: 220,
                child: BarChart(
                  duration: AppMotion.of(context, AppMotion.base),
                  BarChartData(
                    minY: 0,
                    maxY: maxY,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: _grid(context, interval),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: _titles(context, labels: labels, step: _labelStep(slot), interval: interval, leftLabel: compactLira),
                    barGroups: [
                      for (var i = 0; i < months.length; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 1,
                          barRods: [
                            BarChartRodData(toY: _y(first(months[i])), width: rodWidth, color: firstColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                            BarChartRodData(toY: _y(second(months[i])), width: rodWidth, color: secondColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpace.sm),
        ChartLegend(items: [(firstColor, firstLabel), (secondColor, secondLabel)]),
      ],
    );
  }
}

// --- Çizgi grafikler -----------------------------------------------------------------------------

/// Tek seri çizgi. [values] null olan ay boş kalır (çizgi kopar; 0 gösterilmez).
class ChartLine extends StatelessWidget {
  const ChartLine({
    super.key,
    required this.months,
    required this.values,
    required this.color,
    required this.legend,
    required this.summaryTitle,
    required this.spoken,
    this.percent = false,
    this.height = 200,
  });

  final List<FinanceChartMonth> months;

  /// Ay başına değer; kuruş (para) ya da baz puan ([percent]).
  final List<int?> values;
  final Color color;
  final String legend;
  final String summaryTitle;

  /// Değerin ekran okuyucu okunuşu.
  final String Function(int value) spoken;
  final bool percent;
  final double height;

  String summary() {
    final parts = <String>[
      for (var i = 0; i < months.length; i++) '${months[i].title}: ${values[i] == null ? 'veri yok' : spoken(values[i]!)}',
    ];
    return parts.isEmpty ? '$summaryTitle: veri yok.' : '$summaryTitle. ${parts.join('. ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final present = <double>[
      for (final v in values)
        if (v != null) percent ? v / 100.0 : _lira(v),
    ];
    var minV = present.isEmpty ? 0.0 : present.reduce(math.min);
    var maxV = present.isEmpty ? 0.0 : present.reduce(math.max);
    if (percent) {
      minV = 0;
      maxV = math.max(100.0, maxV);
    } else {
      minV = math.min(0.0, minV);
      maxV = math.max(0.0, maxV);
    }
    final span = math.max(maxV - minV, 1.0);
    final interval = percent ? (maxV <= 100 ? 50.0 : niceInterval(span, ticks: 2)) : niceInterval(span);
    final minY = (minV / interval).floor() * interval;
    var maxY = (maxV / interval).ceil() * interval;
    if (maxY <= minY) maxY = minY + interval;
    final labels = <String>[for (final m in months) chartMonthLabel(m.period)];
    final spots = <FlSpot>[
      for (var i = 0; i < months.length; i++)
        values[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), percent ? values[i]! / 100.0 : _lira(values[i]!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final slot = months.isEmpty ? 40.0 : (c.maxWidth - _leftAxisWidth) / months.length;
            return Semantics(
              label: summary(),
              container: true,
              excludeSemantics: true,
              child: SizedBox(
                height: height,
                child: LineChart(
                  duration: AppMotion.of(context, AppMotion.base),
                  LineChartData(
                    minX: -0.5,
                    maxX: math.max(months.length - 1, 0) + 0.5,
                    minY: minY,
                    maxY: maxY,
                    gridData: _grid(context, interval),
                    borderData: FlBorderData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    titlesData: _titles(
                      context,
                      labels: labels,
                      step: _labelStep(slot),
                      interval: interval,
                      leftLabel: percent ? (v) => '%${v.round()}' : compactLira,
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        color: color,
                        barWidth: 2.5,
                        isCurved: false,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, _, bar, index) => FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpace.sm),
        ChartLegend(items: [(color, legend)]),
      ],
    );
  }
}

// --- Yatay çubuk satırları -----------------------------------------------------------------------

class ChartBarRow {
  const ChartBarRow({required this.label, required this.minor, required this.color});

  final String label;
  final int minor;
  final Color color;
}

/// Yatay çubuk listesi (kategori dağılımı, yaşlandırma): ad + tutar + yüzde + çubuk. Çubuk uzunluğu [total]'e oranlıdır.
class ChartBarRows extends StatelessWidget {
  const ChartBarRows({super.key, required this.rows, required this.total, this.rowKeyPrefix = 'finance_chart_row'});

  final List<ChartBarRow> rows;

  /// Yüzdenin paydası (kuruş); 0 ise yüzde yazılmaz.
  final int total;
  final String rowKeyPrefix;

  /// Tam yüzde (en yakın), pay 0 ise null.
  static int? percentOf(int minor, int total) => total <= 0 ? null : ((minor * 200 + total) ~/ (total * 2));

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed)
          Padding(
            key: ValueKey<String>('${rowKeyPrefix}_$i'),
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : AppSpace.md),
            child: Semantics(
              container: true,
              excludeSemantics: true,
              label: '${row.label}: ${moneySemanticLabel(row.minor)}${percentOf(row.minor, total) == null ? '' : ', yüzde ${percentOf(row.minor, total)}'}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpace.sm,
                    runSpacing: 2,
                    children: [
                      Text(row.label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        percentOf(row.minor, total) == null ? formatMinor(row.minor) : '${formatMinor(row.minor)} · %${percentOf(row.minor, total)}',
                        style: th.bodyMedium?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total <= 0 ? 0.0 : (row.minor / total).clamp(0.0, 1.0),
                      minHeight: 10,
                      color: row.color,
                      backgroundColor: p.surfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// --- Tablolar ------------------------------------------------------------------------------------

/// Tablo satırı: [minor] doluysa tutar, değilse [text] (ya da "-").
typedef ChartTableLine = ({String label, int? minor, String? text});

/// Ay satırlı tablo eşdeğeri: her ay bir başlık + değer satırları.
class ChartMonthTable extends StatelessWidget {
  const ChartMonthTable({super.key, required this.months, required this.lines});

  final List<FinanceChartMonth> months;
  final List<ChartTableLine> Function(FinanceChartMonth month) lines;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in months)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, container: true, child: Text(m.title, style: th.titleSmall)),
                for (final line in lines(m))
                  line.minor == null
                      ? FinanceInfoRow(label: line.label, value: line.text ?? '-')
                      : FinanceInfoRow(label: line.label, money: line.minor),
              ],
            ),
          ),
      ],
    );
  }
}
