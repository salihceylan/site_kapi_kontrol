// FAZ 5 / A1b-(ii): QR geri sayım halkası ve kalan saniye.
//
// Eski QR modalı her karede `AnimatedBuilder` ile `QrImageView`'ı YENİDEN KURUYORDU. [CountdownRing]
// yalnız `paint()` çalıştırır: halka `CustomPainter(repaint: progress)` ile çizilir, `child` (QR
// kartı) bir kez kurulur ve halka katmanının dışında kaldığından her karede yeniden BOYANMAZ da.
// [CountdownSeconds] kalan saniyeyi gösterir ve yalnız rakam değişince (saniyede bir) yeniden kurulur.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// QR halkası: ilerleme 1 -> 0 azalırken yeşil -> amber -> kırmızı geçişli yay çizer.
///
/// [progress] 1,0 (tam halka) -> 0,0 (boş) giden bir animasyondur (örn. süresi `initialSeconds` olan
/// `AnimationController`). Sabit bir değer gerekiyorsa `kAlwaysCompleteAnimation` (dolu halka: örn.
/// başarı) ya da `kAlwaysDismissedAnimation` (boş halka: örn. süre doldu/ret) verilir.
///
/// Renk [colorFor] ile painter içinde hesaplanır; [colorOverride] verilirse sabit renk kullanılır
/// (başarı/ret/uyarı anları). Halka renklerinin tamamı beyaz/açık `surface` üzerinde ve koyu
/// zeminlerde (`#1E293B`, `#0F172A`) en az 3:1 kontrasttır ([goodColor], [warnColor], [lowColor]);
/// override için bu sabitleri kullanın (success tonunun canlı #10B981 rengi beyazda 2,5:1'dir:
/// kullanmayın). Halka açık gri `surfaceMuted` (#F1F5F9) üstüne konmamalıdır (amber 2,9:1'e iner).
///
/// **Taşma**: [size] tercih edilen boyuttur; üst öğe daha dar bırakırsa halka + [child] ORANTILI
/// küçülür (halka daire kalır). **Erişilebilirlik**: halka dekoratiftir (anlamsal düğüm yok);
/// [child]'ın anlamsal içeriği korunur, durum metni başlıkta okunur. **Hareket azaltma**: halka
/// ilerlemesi işlevseldir ve sürer.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.progress,
    required this.child,
    this.colorOverride,
    this.size = 268,
    this.stroke = 8,
  });

  /// 1 -> 0 giden ilerleme (1 = tam halka).
  final Animation<double> progress;

  /// Halkanın ortasındaki içerik (QR kartı). Bir kez kurulur.
  final Widget child;

  /// Verilirse halka rengi sabittir (başarı/ret/uyarı).
  final Color? colorOverride;

  /// Tercih edilen kenar uzunluğu (dp).
  final double size;

  /// Halka kalınlığı (dp).
  final double stroke;

  /// Akış ilk dilimi (ilerleme > 0,4): yeşil. Beyaz/açık yüzeyde 3,77:1, koyu yüzeyde 3,88:1.
  static const Color goodColor = Color(0xFF059669);

  /// Orta dilim (ilerleme ~0,4): amber. Beyazda 3,19:1, koyu yüzeyde 4,59:1.
  static const Color warnColor = Color(0xFFD97706);

  /// Son dilim (ilerleme -> 0): kırmızı. Beyazda 4,83:1, koyu yüzeyde 3,03:1.
  static const Color lowColor = Color(0xFFDC2626);

  /// Başarı gösterimi için halka rengi: success tonuna yakın, beyazda >= 3:1 olan yeşil
  /// (canlı `AppTone.success.hue` #10B981 beyazda 2,5:1'dir; halka için kullanılmaz).
  static const Color successColor = goodColor;

  /// Başarı tikinin ölçek animasyonu süresi (eski 700 ms `elasticOut` kısaltıldı).
  static const Duration successTickDuration = Duration(milliseconds: 320);

  /// Başarı tikinin ölçek eğrisi.
  static const Curve successTickCurve = Curves.easeOutBack;

  /// İlerlemeye göre halka rengi: 1,0 -> yeşil, 0,4 -> amber, 0,0 -> kırmızı (arası doğrusal geçiş).
  /// [t] 0..1 dışındaysa kenara sıkıştırılır.
  static Color colorFor(double t) {
    final v = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    return v > 0.4
        ? Color.lerp(warnColor, goodColor, ((v - 0.4) / 0.6).clamp(0.0, 1.0))!
        : Color.lerp(lowColor, warnColor, (v / 0.4).clamp(0.0, 1.0))!;
  }

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Yalnız halka kendi katmanında yeniden boyanır; child (QR) bu katmanın DIŞINDA.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RingPainter(progress, colorOverride, stroke),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.fixedColor, this.stroke)
    : super(repaint: progress);

  final Animation<double> progress;
  final Color? fixedColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value.isNaN ? 0.0 : progress.value.clamp(0.0, 1.0);
    final color = fixedColor ?? CountdownRing.colorFor(t);
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.14);
    // İz: soluk tam halka.
    canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
    if (t > 0) {
      // Kalan süre: 12 yönünden saat yönünde yay, yuvarlak uçlu.
      paint
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * t, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fixedColor != fixedColor ||
      oldDelegate.stroke != stroke;
}

/// Kalan saniye metni ("27 sn"): [progress] (1 -> 0) x [totalSeconds] yukarı yuvarlanır.
///
/// Yalnız GÖSTERİLEN rakam değişince (saniyede bir) yeniden kurulur; aynı saniye içinde animasyon
/// kareleri widget ağacını etkilemez. Rakamlar sabit genişliklidir (tabular), metin tek satırdır
/// ve elips ile kısalır (taşmaz). Canlı bölge DEĞİLDİR: ekran okuyucuyu her saniye duyuruyla
/// bölmez (durum başlıkta okunur).
class CountdownSeconds extends StatefulWidget {
  const CountdownSeconds({
    super.key,
    required this.progress,
    this.totalSeconds = 30,
    this.suffix = ' sn',
    this.style,
  });

  /// 1 -> 0 giden ilerleme ([CountdownRing.progress] ile aynı animasyon).
  final Animation<double> progress;

  /// İlerleme 1,0 iken gösterilen saniye (genelde geri sayım denetleyicisinin süresi).
  final int totalSeconds;

  /// Rakamın arkasına eklenen sabit metin (tek yeni metin: ' sn').
  final String suffix;

  final TextStyle? style;

  /// [value] (0..1) ilerlemesine karşılık gelen kalan saniye (yukarı yuvarlanır, 0..[totalSeconds]).
  static int secondsFor(double value, int totalSeconds) {
    if (value.isNaN || totalSeconds <= 0) return 0;
    // 1e-6: 0,9 x 30 gibi çarpımlardaki kayan nokta artığı bir üst saniyeye atlatmasın.
    final raw = (value.clamp(0.0, 1.0) * totalSeconds - 1e-6).ceil();
    return raw.clamp(0, totalSeconds);
  }

  @override
  State<CountdownSeconds> createState() => _CountdownSecondsState();
}

class _CountdownSecondsState extends State<CountdownSeconds> {
  late int _seconds = _read();

  int _read() =>
      CountdownSeconds.secondsFor(widget.progress.value, widget.totalSeconds);

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onTick);
  }

  @override
  void didUpdateWidget(CountdownSeconds oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_onTick);
      widget.progress.addListener(_onTick);
    }
    _seconds = _read();
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    final next = _read();
    if (next != _seconds && mounted) setState(() => _seconds = next);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '$_seconds${widget.suffix}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}
