// Premium yüzey: cilalı ("parlatılmış") katman.
//
// [Gloss], bir yüzeyin (gradyan düğme, yuvarlak düğme, kart) ÜSTÜNE bindirilen dört ince katmandır:
//  1. hacim: sol-üstten gelen yumuşak ışık,
//  2. alt gölge: yüzeyin altına doğru koyulaşma (yüzey "yuvarlak" görünür),
//  3. kenar ışığı: iç kenar boyunca ince, yönlü parlak çizgi,
//  4. özel parıltı: üstte cam gibi oval yansıma (yalnız daire; çubukta üst yarı cilası).
// Yüzeyin dolgusunu ve gölgesini çağıran çizer; bu dosya yalnız BOYAMA taşır (davranış yoktur).
//
// **Performans sözleşmesi**: tek `CustomPaint`, `RepaintBoundary` içinde. `saveLayer`, `Opacity`,
// `BackdropFilter`, `ShaderMask`, bulanıklık YOKTUR; yalnız gradyan dolgu/çizgi. Durağanken hiçbir
// karede yeniden boyanmaz (ticker yok). Yalnız [sweep] verilirse ve ilerlemesi 0-1 arasındayken
// (tek seferlik ışıltı süpürmesi) o animasyonla yeniden boyanır.
//
// **Erişilebilirlik**: dekoratiftir (anlamsal düğüm yok, dokunmayı yutmaz, yüksek karşıtlıkta kapanır).
// Ton gradyanının uçları beyazla >= 4,5:1 olduğundan cila, beyaz içeriğin durduğu bölgeyi sınırlı
// açar: ETİKET bölgesinde >= 4,5:1, İKON bölgesinde >= 3:1 (WCAG 1.4.11 grafik nesne) kalır;
// `test/design/gloss_test.dart` bunu GERÇEK boyanmış piksellerle ölçer (parametreleri kalibre eder).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [Gloss] geometrisi.
enum GlossShape {
  /// Tam daire (kısa kenar çap alınır; kare alanda kullanın).
  circle,

  /// Köşe yarıçaplı dikdörtgen ([Gloss.radius]).
  rounded,
}

/// Yüzey üstü cila katmanı. Çağıran `Stack` içinde `Positioned.fill` ile yerleştirir:
///
/// ```dart
/// Stack(children: [
///   Positioned.fill(child: Gloss(shape: GlossShape.circle)),
///   content,
/// ])
/// ```
class Gloss extends StatelessWidget {
  const Gloss({
    super.key,
    this.shape = GlossShape.rounded,
    this.radius = AppRadius.md,
    this.strength = 1.0,
    this.sweep,
    this.isolate = true,
  }) : assert(strength >= 0 && strength <= 1, 'strength 0..1 olmalı');

  /// Daire ya da yuvarlatılmış dikdörtgen.
  final GlossShape shape;

  /// [GlossShape.rounded] için köşe yarıçapı (yüzeyinkiyle AYNI olmalı).
  final double radius;

  /// 0..1: tüm katmanların şiddet çarpanı (0 = hiçbir şey çizilmez).
  final double strength;

  /// Tek seferlik ışıltı süpürmesi ilerlemesi (0 -> 1). null ya da 0/1 iken süpürme çizilmez.
  final Animation<double>? sweep;

  /// true (varsayılan): cila kendi `RepaintBoundary` katmanındadır (büyük yüzey ya da süpürme
  /// animasyonu: üst öğenin yeniden boyanması cilayı, cilanın animasyonu üst öğeyi etkilemez).
  /// false: katmansız (listelerde onlarca küçük rozet için gereksiz katman maliyeti yok); [sweep]
  /// verilmişse yine de katman ayrılır.
  final bool isolate;

  @override
  Widget build(BuildContext context) {
    // Yüksek karşıtlık modunda süs yoktur: düz zemin + düz metin (kullanıcının açık isteği).
    if (MediaQuery.maybeHighContrastOf(context) ?? false) {
      return const SizedBox.shrink();
    }
    final paint = CustomPaint(
      painter: GlossPainter(
        shape: shape,
        radius: radius,
        strength: strength,
        sweep: sweep,
      ),
    );
    return IgnorePointer(
      child: isolate || sweep != null ? RepaintBoundary(child: paint) : paint,
    );
  }
}

/// [Gloss] boyayıcısı. Test edilebilsin diye herkese açıktır (örn. piksel kontrast ölçümü).
class GlossPainter extends CustomPainter {
  GlossPainter({
    required this.shape,
    required this.radius,
    required this.strength,
    this.sweep,
  }) : super(repaint: sweep);

  final GlossShape shape;
  final double radius;
  final double strength;
  final Animation<double>? sweep;

  static Color _white(double alpha) => Color.fromRGBO(255, 255, 255, alpha);
  static Color _black(double alpha) => Color.fromRGBO(0, 0, 0, alpha);

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0 || size.isEmpty) return;
    switch (shape) {
      case GlossShape.circle:
        _paintCircle(canvas, size);
      case GlossShape.rounded:
        _paintRounded(canvas, size);
    }
    final t = sweep?.value;
    if (t != null && t > 0 && t < 1) _paintSweep(canvas, size, t);
  }

  void _paintCircle(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final disc = Rect.fromLTWH(
      (size.width - d) / 2,
      (size.height - d) / 2,
      d,
      d,
    );
    final s = strength;

    canvas.save();
    canvas.clipPath(Path()..addOval(disc));

    // 1) Hacim: ışık kaynağı sol-üstte; yumuşak, geniş. Merkezde (içerik) payı küçük kalır.
    canvas.drawRect(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.7),
          radius: 0.8,
          colors: <Color>[_white(0.16 * s), _white(0.0)],
        ).createShader(disc),
    );

    // 2) Alt gölge: yüzey aşağıya doğru koyulaşır (küre hissi).
    canvas.drawRect(
      disc,
      Paint()
        ..shader = ui.Gradient.linear(
          disc.topCenter,
          disc.bottomCenter,
          <Color>[_black(0.0), _black(0.24 * s)],
          <double>[0.52, 1.0],
        ),
    );

    // 3) Yansıyan ışık: alt kenarda ince, geniş aydınlık (zeminden dönen ışık).
    canvas.drawRect(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.05),
          radius: 0.62,
          colors: <Color>[_white(0.12 * s), _white(0.0)],
        ).createShader(disc),
    );
    canvas.restore();

    // 4) Kenar ışığı: sol-üst parlak, sağ-altta zayıf geri yansıma.
    canvas.drawOval(
      disc.deflate(0.9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.linear(
          disc.topLeft,
          disc.bottomRight,
          <Color>[_white(0.62 * s), _white(0.0), _white(0.16 * s)],
          <double>[0.0, 0.55, 1.0],
        ),
    );

    // 5) Özel parıltı: üst yarıda cam gibi oval yansıma (üstte belirgin, aşağıda sönük).
    final cap = Rect.fromLTRB(
      disc.left + d * 0.20,
      disc.top + d * 0.045,
      disc.left + d * 0.80,
      disc.top + d * 0.30,
    );
    canvas.drawOval(
      cap,
      Paint()
        ..shader = ui.Gradient.linear(
          cap.topCenter,
          cap.bottomCenter,
          // Alt kenar tam saydamdır: parıltı bir "kenar çizgisi" bırakmadan yüzeyle kaynaşır.
          <Color>[_white(0.42 * s), _white(0.0)],
        ),
    );
  }

  void _paintRounded(Canvas canvas, Size size) {
    final s = strength;
    final bounds = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(bounds, Radius.circular(radius));

    canvas.save();
    canvas.clipRRect(rr);

    // Üst cila: yukarıda belirgin, kısa sürede sönen (metin bölgesini açmaz).
    final top = Rect.fromLTWH(0, 0, size.width, size.height * 0.42);
    canvas.drawRect(
      top,
      Paint()
        ..shader = ui.Gradient.linear(
          top.topCenter,
          top.bottomCenter,
          <Color>[_white(0.20 * s), _white(0.0)],
        ),
    );

    // Alt gölge: alt kenara doğru hafif koyulaşma.
    final bottom = Rect.fromLTWH(
      0,
      size.height * 0.55,
      size.width,
      size.height * 0.45,
    );
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = ui.Gradient.linear(
          bottom.topCenter,
          bottom.bottomCenter,
          <Color>[_black(0.0), _black(0.16 * s)],
        ),
    );
    canvas.restore();

    // Kenar ışığı: üstte parlak, altta çok zayıf ince iç çizgi.
    canvas.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          <Color>[_white(0.46 * s), _white(0.06 * s)],
        ),
    );
  }

  /// Tek seferlik ışıltı: yüzeyin üzerinden soldan sağa geçen eğik, yumuşak beyaz şerit.
  void _paintSweep(Canvas canvas, Size size, double t) {
    canvas.save();
    switch (shape) {
      case GlossShape.circle:
        final d = math.min(size.width, size.height);
        canvas.clipPath(
          Path()
            ..addOval(
              Rect.fromLTWH(
                (size.width - d) / 2,
                (size.height - d) / 2,
                d,
                d,
              ),
            ),
        );
      case GlossShape.rounded:
        canvas.clipRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    }
    final w = size.width;
    final h = size.height;
    final eased = Curves.easeInOut.transform(t);
    final cx = ui.lerpDouble(-0.30 * w, 1.30 * w, eased)!;
    final band = 0.34 * math.max(w, h);
    // Giriş/çıkışta şerit solar: ortada en parlak.
    final alpha = 0.34 * math.sin(math.pi * t) * strength;
    canvas.translate(cx, h / 2);
    canvas.rotate(-math.pi / 6);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: band,
      height: math.max(w, h) * 2.4,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          <Color>[_white(0.0), _white(alpha), _white(0.0)],
          <double>[0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlossPainter old) =>
      old.shape != shape ||
      old.radius != radius ||
      old.strength != strength ||
      old.sweep != sweep;
}

/// Tema düzeyinde cilalı düğme katmanı: `ElevatedButton`/`FilledButton` stillerinin
/// `ButtonStyle.backgroundBuilder`'ı olarak bağlanır (`AppTheme`).
///
/// Düğmenin düz dolgusunun ÜSTÜNE (InkWell, dalga ve içeriğin ALTINA) [Gloss] biner; devre dışı
/// düğme düz kalır. Üst düzey işlevdir (kapanış yok): `AppTheme.light() == AppTheme.light()`
/// eşitliği bozulmaz. Köşe yarıçapı temadaki düğme şekliyle aynıdır (16); farklı şekilli bir
/// düğmede Material zaten katmanı kendi şekline kırpar.
Widget glossyButtonLayer(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  if (child == null || states.contains(WidgetState.disabled)) {
    return child ?? const SizedBox.shrink();
  }
  return Stack(
    fit: StackFit.passthrough,
    children: [
      const Positioned.fill(child: Gloss(radius: 16, strength: 0.8)),
      child,
    ],
  );
}
