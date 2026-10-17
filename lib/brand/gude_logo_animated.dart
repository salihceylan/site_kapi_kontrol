import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'gude_logo.dart';
import 'gude_logo_data.dart' show kLogoViewHeight, kLogoViewWidth;
import 'logo_palette.dart';

/// Güde Teknoloji logosunun ışıklı (animasyonlu) sürümleri: [AnimatedGudeLogo] ve [AnimatedGudeLeafMark].
///
/// Hareket dili (tek tekrarlayan denetleyici, [GudeLogoAnimation.cycle] ≈ 7 sn):
///  - Işık süpürmesi: ≈1,6 sn'lik yumuşak, çapraz bir parlak şerit logonun YALNIZ boyalı piksellerinin üstünden
///    geçer (`saveLayer` + `BlendMode.srcATop`: şerit, şeffaf piksellere ve yazının dışına taşmaz). Kalan sürede durağandır.
///  - Nefes alan parıltı: yaprakların arkasında hafifçe soluyup sönen altın bir ışıma (koyu temada belirgin, açıkta sönük).
///
/// Performans: yol ayrıştırması yoktur (çizimi `gude_logo.dart`daki ortak, bir kez çözülmüş yol önbelleği yapar);
/// `setState` yoktur, painter'lar `repaint:` ile yeniden çizilir. Parıltı ile logo ayrı `RepaintBoundary` katmanlarındadır:
/// süpürme dışında logo katmanı yeniden çizilmez, kare başına yalnız tek bir radyal gradyan çizilir.
/// Görünmezken (TickerMode kapalı, `Offstage`, saydamlık 0, örtülü rota) animasyon durur.
///
/// Erişilebilirlik: `MediaQuery.disableAnimations` açıkken ya da `animate: false` iken tamamen durağan çizilir.
abstract final class GudeLogoAnimation {
  /// `animate` verilmeyen logoların animasyonlu olup olmadığı. Uygulamada açıktır; widget testlerinde
  /// `pumpAndSettle` sonsuz animasyonda bitmediği için `test/flutter_test_config.dart` bunu kapatır.
  /// Animasyonu sınayan testler açıkça `animate: true` verir (ya da bu anahtarı açıp geri alır).
  static bool enabledByDefault = true;

  /// Bir turun süresi.
  static const Duration cycle = Duration(milliseconds: 7000);

  /// Turun başından süpürmenin başlamasına kadar geçen süre.
  static const Duration sweepDelay = Duration(milliseconds: 900);

  /// Süpürmenin süresi.
  static const Duration sweepDuration = Duration(milliseconds: 1600);

  /// Bir turda kaç kez "nefes alınır" (tam sayı: tur sonunda sıçrama olmaz).
  static const int breathsPerCycle = 2;

  /// Anlamsal ağaçtaki varsayılan etiket.
  static const String label = 'Güde Teknoloji';

  static double get _begin => sweepDelay.inMicroseconds / cycle.inMicroseconds;
  static double get _end => (sweepDelay + sweepDuration).inMicroseconds / cycle.inMicroseconds;

  /// Denetleyici değeri [t] (0..1) için süpürme ilerlemesi: açık aralıkta (0, 1); süpürme dışında -1.
  static double sweepProgress(double t) {
    final p = (t - _begin) / (_end - _begin);
    return p > 0 && p < 1 ? p : -1;
  }

  /// Nefes eğrisi 0..1 ([t]=0'da 0,5: durağan hâlin ara parlaklığı).
  static double breath(double t) => 0.5 + 0.5 * math.sin(2 * math.pi * breathsPerCycle * t);
}

/// Yaprakların birleşik sınırı, logo çizim uzayının oranları olarak (parıltının oturacağı yer).
final Rect _logoGlowRegion = () {
  final b = GudeLeafMarkPainter.leafBounds;
  return Rect.fromLTRB(b.left / kLogoViewWidth, b.top / kLogoViewHeight, b.right / kLogoViewWidth, b.bottom / kLogoViewHeight);
}();

/// Kare yaprak işaretinde yaprakların ([GudeLeafMarkPainter]: ortalanır, [padding] boşluklu) kareye oranları.
Rect _markGlowRegion(double padding) {
  final b = GudeLeafMarkPainter.leafBounds;
  final scale = (1 - 2 * padding) / math.max(b.width, b.height);
  final w = b.width * scale;
  final h = b.height * scale;
  return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
}

bool _isDark(BuildContext context, LogoPalette? palette, bool? darkBackground) =>
    darkBackground ?? (palette != null ? palette == LogoPalette.dark : Theme.of(context).brightness == Brightness.dark);

/// Işıklı Güde Teknoloji logosu (yazılı, yatay). Boyut yalnızca [height] ile verilir; en/boy oranı [GudeLogo.aspect].
class AnimatedGudeLogo extends StatelessWidget {
  const AnimatedGudeLogo({
    super.key,
    required this.height,
    this.semanticLabel = GudeLogoAnimation.label,
    this.palette,
    this.animate,
    this.darkBackground,
  });

  final double height;

  /// Görsel olarak okunan etiket; null ise (ör. başlığı olan bir bloğun içinde) anlamsal ağaçtan çıkarılır.
  final String? semanticLabel;

  /// Verilmezse etkin temaya göre [LogoPalette.of].
  final LogoPalette? palette;

  /// null ise [GudeLogoAnimation.enabledByDefault]. `MediaQuery.disableAnimations` açıkken her durumda durağandır.
  final bool? animate;

  /// Parıltı şiddeti için zeminin koyu olup olmadığı; null ise [palette] ya da etkin tema belirler.
  final bool? darkBackground;

  @override
  Widget build(BuildContext context) {
    return _AnimatedBrandArt(
      width: height * GudeLogo.aspect,
      height: height,
      art: GudeLogoPainter(palette ?? LogoPalette.of(context)),
      glowRegion: _logoGlowRegion,
      dark: _isDark(context, palette, darkBackground),
      semanticLabel: semanticLabel,
      animate: animate,
    );
  }
}

/// Işıklı kare yaprak işareti ([GudeLeafMark]'ın animasyonlu karşılığı): küçük, kare alanlar için.
class AnimatedGudeLeafMark extends StatelessWidget {
  const AnimatedGudeLeafMark({
    super.key,
    required this.size,
    this.padding = 0.06,
    this.semanticLabel = GudeLogoAnimation.label,
    this.animate,
    this.darkBackground,
  });

  final double size;

  /// Kenar boşluğu (kenarın oranı olarak; 0.06 = %6).
  final double padding;
  final String? semanticLabel;

  /// null ise [GudeLogoAnimation.enabledByDefault].
  final bool? animate;

  /// Parıltı şiddeti için zeminin koyu olup olmadığı; null ise etkin tema belirler (beyaz bir plaka üstünde false verin).
  final bool? darkBackground;

  @override
  Widget build(BuildContext context) {
    return _AnimatedBrandArt(
      width: size,
      height: size,
      art: GudeLeafMarkPainter(padding: padding),
      glowRegion: _markGlowRegion(padding),
      dark: _isDark(context, null, darkBackground),
      semanticLabel: semanticLabel,
      animate: animate,
    );
  }
}

class _AnimatedBrandArt extends StatefulWidget {
  const _AnimatedBrandArt({
    required this.width,
    required this.height,
    required this.art,
    required this.glowRegion,
    required this.dark,
    required this.semanticLabel,
    required this.animate,
  });

  final double width;
  final double height;
  final CustomPainter art;
  final Rect glowRegion;
  final bool dark;
  final String? semanticLabel;
  final bool? animate;

  @override
  State<_AnimatedBrandArt> createState() => _AnimatedBrandArtState();
}

class _AnimatedBrandArtState extends State<_AnimatedBrandArt> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Süpürme ilerlemesi (-1: süpürme yok). Yalnız süpürme sırasında (ve bittiği anda bir kez) değişir:
  /// logo katmanı süpürme dışında yeniden çizilmez.
  final ValueNotifier<double> _sweep = ValueNotifier<double>(-1);

  /// Görünürlük nabzı: parıltı painter'ı her çizildiğinde true olur. İki tık üst üste çizim olmazsa
  /// ([Offstage], saydamlık 0 gibi TickerMode'un yakalamadığı gizlenmeler) denetleyici durdurulur;
  /// yeniden çizilmeye başlayınca ([RenderObject] gizlenmeden çıkınca yeniden boyanır) sürdürülür.
  bool _painted = true;
  int _unpaintedTicks = 0;
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: GudeLogoAnimation.cycle)..addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_AnimatedBrandArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  bool get _wantsMotion =>
      (widget.animate ?? GudeLogoAnimation.enabledByDefault) && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    if (_wantsMotion) {
      if (!_controller.isAnimating) {
        _suspended = false;
        _painted = true;
        _unpaintedTicks = 0;
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) _controller.stop();
      _suspended = false;
      if (_controller.value != 0) _controller.value = 0; // durağan hâl: tur başı (süpürme yok, parıltı ara parlaklıkta)
    }
  }

  void _onTick() {
    _sweep.value = GudeLogoAnimation.sweepProgress(_controller.value);
    if (!_controller.isAnimating) return;
    if (_painted) {
      _painted = false;
      _unpaintedTicks = 0;
    } else if (++_unpaintedTicks >= 2) {
      _suspended = true;
      _controller.stop();
    }
  }

  void _markPainted() {
    _painted = true;
    if (_suspended) {
      _suspended = false;
      // Çizim sırasında ticker başlatılmaz; kareden sonra sürdür.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget art = SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: <Widget>[
          // Arka katman: nefes alan parıltı (her karede yalnız bir radyal gradyan).
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                willChange: true,
                painter: GudeLogoGlowPainter(
                  progress: _controller,
                  region: widget.glowRegion,
                  dark: widget.dark,
                  onPaint: _markPainted,
                ),
              ),
            ),
          ),
          // Ön katman: logo; yalnız süpürme sırasında yeniden çizilir.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: GudeLogoSweepPainter(art: widget.art, sweep: _sweep, dark: widget.dark),
              ),
            ),
          ),
        ],
      ),
    );
    final label = widget.semanticLabel;
    art = label == null ? ExcludeSemantics(child: art) : Semantics(label: label, image: true, child: ExcludeSemantics(child: art));
    return RepaintBoundary(child: art);
  }
}

/// Yaprakların arkasındaki nefes alan altın parıltı: yaprak kümesine oturan yumuşak bir elips (radyal gradyan).
/// Elips çizim alanının dışına taşmaz. Süpürme sırasında parıltı kısa süre güçlenir.
class GudeLogoGlowPainter extends CustomPainter {
  GudeLogoGlowPainter({required this.progress, required this.region, required this.dark, this.onPaint}) : super(repaint: progress);

  /// Tur ilerlemesi (0..1).
  final Animation<double> progress;

  /// Yaprak kümesinin çizim alanına oranı (sol, üst, sağ, alt: 0..1).
  final Rect region;
  final bool dark;

  /// Her çizimde çağrılır (görünürlük nabzı).
  final VoidCallback? onPaint;

  static const Color darkColor = Color(0xFFF2B04C);
  static const Color lightColor = Color(0xFFE0A044);

  /// Parıltının merkez saydamlığı: nefes [breath] (0..1). Koyu zeminde belirgin, açıkta sönük.
  static double intensity(double breath, {required bool dark}) =>
      dark ? 0.22 + 0.18 * breath : 0.06 + 0.07 * breath;

  /// Süpürme sırasında parıltının en çok bu oranda güçlenmesi.
  static const double sweepLift = 0.30;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint?.call();
    final t = progress.value;
    final b = GudeLogoAnimation.breath(t);
    final sp = GudeLogoAnimation.sweepProgress(t);
    final lift = sp < 0 ? 0.0 : math.sin(math.pi * sp);
    final peak = intensity(b, dark: dark) * (1 + sweepLift * lift);
    final scale = 0.96 + 0.08 * b;

    final r = Rect.fromLTRB(region.left * size.width, region.top * size.height, region.right * size.width, region.bottom * size.height);
    final c = r.center;
    final rx = math.min(r.width * 0.62 * scale, math.min(c.dx, size.width - c.dx));
    final ry = math.min(r.height * 0.74 * scale, math.min(c.dy, size.height - c.dy));
    if (rx <= 0 || ry <= 0) return;

    final base = dark ? darkColor : lightColor;
    final shader = ui.Gradient.radial(
      Offset.zero,
      1,
      <Color>[
        base.withValues(alpha: peak),
        base.withValues(alpha: peak * 0.55),
        base.withValues(alpha: peak * 0.18),
        base.withValues(alpha: 0),
      ],
      const <double>[0, 0.38, 0.72, 1],
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(rx, ry);
    canvas.drawRect(const Rect.fromLTRB(-1, -1, 1, 1), Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GudeLogoGlowPainter old) => old.progress != progress || old.region != region || old.dark != dark;
}

/// Logoyu çizer; süpürme sürerken parlak şeridi YALNIZ boyalı pikseller üstünde gösterir:
/// logo bir `saveLayer`a çizilir, şerit `BlendMode.srcATop` ile bindirilir (şeffaf pikseller değişmez, kenarlar kalınlaşmaz).
/// Süpürme yokken ([sweep] < 0) `saveLayer` açılmaz, logo düz çizilir.
class GudeLogoSweepPainter extends CustomPainter {
  GudeLogoSweepPainter({required this.art, required this.sweep, required this.dark}) : super(repaint: sweep);

  /// Logoyu çizen painter ([GudeLogoPainter] ya da [GudeLeafMarkPainter]).
  final CustomPainter art;

  /// Süpürme ilerlemesi: (0, 1) arası süpürme sürüyor, negatif: yok.
  final ValueListenable<double> sweep;
  final bool dark;

  static const Color bandColor = Color(0xFFFFF4D8);

  /// Şerit tepe saydamlığı (koyu / açık zeminde).
  static const double peakDark = 0.78;
  static const double peakLight = 0.62;

  /// Şeridin eğimi (derece): "/" biçimi.
  static const double angleDegrees = 20;

  /// Şeridin yarı genişliği (çaprazlama yayılımın oranı).
  static const double halfWidth = 0.11;

  @override
  void paint(Canvas canvas, Size size) {
    final p = sweep.value;
    if (p < 0) {
      art.paint(canvas, size);
      return;
    }
    // Gölge gibi kutunun dışına taşan boyamalar kırpılmasın diye sınır biraz geniş tutulur.
    final bounds = (Offset.zero & size).inflate(size.shortestSide * 0.1);
    canvas.saveLayer(bounds, Paint());
    art.paint(canvas, size);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = band(size, p, dark: dark),
    );
    canvas.restore();
  }

  /// [p] (0..1) anındaki şeridin gradyanı: yumuşak çıkış-giriş eğrisiyle soldan sağa geçer.
  static ui.Shader band(Size size, double p, {required bool dark}) {
    final angle = angleDegrees * math.pi / 180;
    final ux = math.cos(angle);
    final uy = math.sin(angle);
    final span = size.width * ux + size.height * uy;
    final hw = span * halfWidth;
    final center = -hw + (span + 2 * hw) * Curves.easeInOutSine.transform(p);
    final peak = dark ? peakDark : peakLight;
    Color at(double a) => bandColor.withValues(alpha: peak * a);
    return ui.Gradient.linear(
      Offset(ux, uy) * (center - hw),
      Offset(ux, uy) * (center + hw),
      <Color>[at(0), at(0.3), at(1), at(0.3), at(0)],
      const <double>[0, 0.3, 0.5, 0.7, 1],
    );
  }

  @override
  bool shouldRepaint(GudeLogoSweepPainter old) =>
      old.sweep != sweep || old.dark != dark || old.art.runtimeType != art.runtimeType || art.shouldRepaint(old.art);
}
