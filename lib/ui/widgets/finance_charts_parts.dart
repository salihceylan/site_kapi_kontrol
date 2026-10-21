import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_charts.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart' show StaggeredEntry;
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_4b_parts.dart' show FinanceInfoRow;
import 'package:site_kapi_kontrol/ui/widgets/finance_chart_reveal.dart';
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
/// - Giriş animasyonu: çubuklar alttan büyür, çizgiler soldan sağa çizilir, tutar ve yüzde 0'dan sayar (800 ms, easeOutCubic,
///   kart başına tek denetleyici, kartlar kademeli; bkz. `finance_chart_reveal.dart`). Sekme açılınca bir kez, veri değişince
///   yeniden oynar; "Tablo olarak göster" ile dönüşte yeniden oynamaz. Sonsuz animasyon yoktur.
/// - `MediaQuery.disableAnimations` açıkken animasyon yoktur (ilk karede son hal).

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
    this.index = 0,
    this.replayKey,
  });

  /// Kartın sırası (0'dan): giriş animasyonu [kChartRevealStagger] x sıra kadar geç başlar.
  final int index;

  /// Değişince giriş animasyonu yeniden oynar (örn. verinin özeti). Aynı kalırsa yenilemede tekrar oynamaz.
  final Object? replayKey;

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

class _FinanceChartCardState extends State<FinanceChartCard> with SingleTickerProviderStateMixin {
  bool _asTable = false;

  // Kart başına tek denetleyici: "Tablo olarak göster" ile grafik yeniden kurulsa da giriş yeniden oynamaz.
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    final delay = kChartRevealStagger * (widget.index < 0 ? 0 : widget.index);
    final total = kChartRevealDuration + delay;
    _controller = AnimationController(vsync: this, duration: total);
    _progress = _controller.drive(
      CurveTween(curve: Interval(delay.inMilliseconds / total.inMilliseconds, 1, curve: AppMotion.enter)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_decided) {
      _decided = true;
      _play();
    } else if (AppMotion.reduced(context)) {
      // Hareket azaltma giriş sürerken açılırsa grafik hemen son haline gelir.
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(FinanceChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replayKey != widget.replayKey || oldWidget.hasData != widget.hasData) _play();
  }

  void _play() {
    if (!widget.hasData || AppMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final p = context.palette;
    final card = AppCard(
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
              KeyedSubtree(
                key: ValueKey<String>('finance_chart_${widget.id}'),
                child: ChartRevealScope(progress: _progress, child: widget.chart),
              ),
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
    // Kart girişi: hafif kademeli (sıraya göre) solarak ve 12 dp yukarıdan kayarak gelir; yalnız ilk kurulumda bir kez oynar.
    return StaggeredEntry(index: widget.index, child: card);
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
    final reveal = ChartRevealScope.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final slot = months.isEmpty ? 40.0 : (c.maxWidth - _leftAxisWidth) / months.length;
            final rodWidth = (slot / 3.2).clamp(3.0, 12.0).toDouble();
            final grid = _grid(context, interval);
            final titles = _titles(context, labels: labels, step: _labelStep(slot), interval: interval, leftLabel: compactLira);
            return Semantics(
              label: summary(),
              container: true,
              excludeSemantics: true,
              child: SizedBox(
                height: 220,
                // Giriş: çubuklar tabandan büyür (eksen en büyük değere sabit). Kapsam varsa fl_chart'ın kendi geçişi kapalıdır.
                child: AnimatedBuilder(
                  animation: reveal ?? kAlwaysCompleteAnimation,
                  builder: (context, _) {
                    final p = reveal?.value ?? 1.0;
                    return BarChart(
                      duration: reveal == null ? AppMotion.of(context, AppMotion.base) : Duration.zero,
                      BarChartData(
                        minY: 0,
                        maxY: maxY,
                        alignment: BarChartAlignment.spaceAround,
                        gridData: grid,
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: titles,
                        barGroups: [
                          for (var i = 0; i < months.length; i++)
                            BarChartGroupData(
                              x: i,
                              barsSpace: 1,
                              barRods: [
                                BarChartRodData(toY: _y(first(months[i])) * p, width: rodWidth, color: firstColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                                BarChartRodData(toY: _y(second(months[i])) * p, width: rodWidth, color: secondColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
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
    final reveal = ChartRevealScope.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final slot = months.isEmpty ? 40.0 : (c.maxWidth - _leftAxisWidth) / months.length;
            final grid = _grid(context, interval);
            final titles = _titles(
              context,
              labels: labels,
              step: _labelStep(slot),
              interval: interval,
              leftLabel: percent ? (v) => '%${v.round()}' : compactLira,
            );
            return Semantics(
              label: summary(),
              container: true,
              excludeSemantics: true,
              child: SizedBox(
                height: height,
                // Giriş: çizgi soldan sağa çizilir (eksenler sabit); aradaki ara değerli uç nokta için nokta çizilmez.
                child: AnimatedBuilder(
                  animation: reveal ?? kAlwaysCompleteAnimation,
                  builder: (context, _) {
                    final shown = revealSpots(spots, reveal?.value ?? 1.0);
                    return LineChart(
                      duration: reveal == null ? AppMotion.of(context, AppMotion.base) : Duration.zero,
                      LineChartData(
                        minX: -0.5,
                        maxX: math.max(months.length - 1, 0) + 0.5,
                        minY: minY,
                        maxY: maxY,
                        gridData: grid,
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        titlesData: titles,
                        lineBarsData: [
                          if (shown.any((s) => s.isNotNull()))
                            LineChartBarData(
                              spots: shown,
                              color: color,
                              barWidth: 2.5,
                              isCurved: false,
                              dotData: FlDotData(
                                show: true,
                                checkToShowDot: (spot, _) => spot.x == spot.x.roundToDouble(),
                                getDotPainter: (spot, _, bar, index) => FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
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
    final reveal = ChartRevealScope.maybeOf(context);
    // Giriş: çubuk soldan dolar, tutar ve yüzde 0'dan sayar. Ekran okuyucu etiketi hep son değerdir (ara değer okunmaz).
    return AnimatedBuilder(
      animation: reveal ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        final t = reveal?.value ?? 1.0;
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
                            _rowAmountText(row.minor, total, t),
                            style: th.bodyMedium?.copyWith(
                              color: p.textSecondary,
                              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (total <= 0 ? 0.0 : (row.minor / total).clamp(0.0, 1.0)) * t,
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
      },
    );
  }

  /// "1.250,00 ₺ · %25"; [t] (0..1) giriş ilerlemesidir: tutar ve yüzde 0'dan saydırılır, 1'de tam değerdir.
  static String _rowAmountText(int minor, int total, double t) {
    final shown = t >= 1 ? minor : (minor * t).round();
    final pct = percentOf(shown, total);
    return pct == null ? formatMinor(shown) : '${formatMinor(shown)} · %$pct';
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
