import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'gude_logo_data.dart';
import 'logo_model.dart';
import 'logo_palette.dart';

/// Güde Teknoloji logosu: vektör, şeffaf zeminli; renkleri [LogoPalette] belirler (etkin temaya göre koyu/açık).
/// Plaka yoktur; koyu temada koyu, açık temada açık zeminin üstünde doğrudan çizilir.
/// En/boy oranı [kLogoViewWidth] / [kLogoViewHeight]; boyut yalnızca [height] ile verilir.
class GudeLogo extends StatelessWidget {
  const GudeLogo({super.key, required this.height, this.semanticLabel, this.palette});

  final double height;

  /// Verilmezse etkin temaya göre [LogoPalette.of] (uygulama ikonu üretimi gibi tema dışı çizimlerde açıkça verilir).
  final LogoPalette? palette;

  /// Verilirse görsel olarak okunur; null ise (ör. etiketli bir düğmenin içinde) anlamsal ağaçtan çıkarılır.
  final String? semanticLabel;

  static double get aspect => kLogoViewWidth / kLogoViewHeight;

  @override
  Widget build(BuildContext context) {
    final resolved = palette ?? LogoPalette.of(context);
    Widget art = SizedBox(
      width: height * aspect,
      height: height,
      child: CustomPaint(painter: GudeLogoPainter(resolved), isComplex: true),
    );
    art = semanticLabel == null ? ExcludeSemantics(child: art) : Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: art));
    return RepaintBoundary(child: art);
  }
}

/// Yol verisi bir kez çözülür ve bütün logolarca paylaşılır ([Path] değişmez olarak kullanılır).
class _ParsedShape {
  _ParsedShape(this.shape) : path = parseLogoPath(shape.d);
  final LogoShape shape;
  final Path path;
}

class _ParsedLogo {
  _ParsedLogo._()
      : shadow = [for (final s in kLogoShadow) _ParsedShape(s)],
        leaves = [for (final s in kLogoLeaves) _ParsedShape(s)],
        wordmark = [for (final s in kLogoWordmark) _ParsedShape(s)],
        tagline = [for (final s in kLogoTagline) _ParsedShape(s)];

  static final instance = _ParsedLogo._();

  final List<_ParsedShape> shadow;
  final List<_ParsedShape> leaves;
  final List<_ParsedShape> wordmark;
  final List<_ParsedShape> tagline;
}

@visibleForTesting
const wordmarkFillId = 'wordmark-fill';

class GudeLogoPainter extends CustomPainter {
  const GudeLogoPainter(this.palette);

  final LogoPalette palette;

  /// Gölge yumuşaklığı (logo çizim uzayı birimi; 1600 birim genişlikte).
  static const shadowBlur = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final parsed = _ParsedLogo.instance;
    canvas.save();
    canvas.scale(size.width / kLogoViewWidth, size.height / kLogoViewHeight);

    if (palette.shadow.a > 0) {
      for (final p in parsed.shadow) {
        final paint = Paint()
          ..isAntiAlias = true
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, shadowBlur)
          ..color = palette.shadow.withValues(alpha: palette.shadow.a * p.shape.opacity * _solidAlpha(p.shape.fill));
        canvas.drawPath(p.path, paint);
      }
    }

    for (final p in parsed.leaves) {
      canvas.drawPath(p.path, _paintFor(p.shape));
    }

    for (final p in parsed.wordmark) {
      canvas.drawPath(p.path, _wordmarkPaint(p.shape, p.path));
    }

    for (final p in parsed.tagline) {
      final isOutline = p.shape.id.endsWith('outline');
      canvas.drawPath(
        p.path,
        Paint()
          ..isAntiAlias = true
          ..color = isOutline ? palette.taglineEdge : palette.tagline,
      );
    }
    canvas.restore();
  }

  /// SVG'deki özgün dolgu (gradyan ya da düz renk), şeklin kendi saydamlığıyla.
  static Paint _paintFor(LogoShape s) {
    final paint = Paint()..isAntiAlias = true;
    final fill = s.fill;
    if (fill is LogoSolid) {
      paint.color = fill.color.withValues(alpha: fill.color.a * s.opacity);
    } else {
      paint.shader = fill.shader(s.opacity);
    }
    return paint;
  }

  static double _solidAlpha(LogoFill f) => f is LogoSolid ? f.color.a : 1.0;

  /// Harf yüzleri: SVG'deki gradyan geometrisi (yön/uzunluk) korunur, renk durakları temadan gelir.
  /// Koyu kenar: tek düz renk.
  Paint _wordmarkPaint(LogoShape s, Path path) {
    final paint = Paint()..isAntiAlias = true;
    if (s.id != wordmarkFillId) {
      paint.color = palette.wordOutline;
      return paint;
    }
    final fill = s.fill;
    final b = path.getBounds();
    final from = fill is LogoLinear ? Offset(fill.x1, fill.y1) : b.centerLeft;
    final to = fill is LogoLinear ? Offset(fill.x2, fill.y2) : b.centerRight;
    paint.shader = ui.Gradient.linear(from, to, [palette.wordStart, palette.wordMid, palette.wordEnd], const [0.0, 0.5, 1.0]);
    return paint;
  }

  @override
  bool shouldRepaint(GudeLogoPainter old) => old.palette != palette;
}

/// Yalnız dört altın yaprak ("marka işareti"): küçük ve kare alanlar için (uygulama ikonu, yan menü, favicon).
/// Yaprakların sınırları mantıksal olarak kareye [padding] oranında boşlukla sığdırılır ve ortalanır.
class GudeLeafMark extends StatelessWidget {
  const GudeLeafMark({super.key, required this.size, this.padding = 0.06, this.semanticLabel});

  final double size;

  /// Kenar boşluğu (kenarın oranı olarak; 0.06 = %6).
  final double padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget art = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: GudeLeafMarkPainter(padding: padding), isComplex: true),
    );
    art = semanticLabel == null ? ExcludeSemantics(child: art) : Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: art));
    return RepaintBoundary(child: art);
  }
}

/// Yaprakları kareye sığdırıp çizer (gölge ve yazı yok).
class GudeLeafMarkPainter extends CustomPainter {
  const GudeLeafMarkPainter({this.padding = 0.06});

  final double padding;

  /// Yaprakların logo çizim uzayındaki birleşik sınırı (bir kez hesaplanır).
  static final Rect leafBounds = () {
    Rect? union;
    for (final p in _ParsedLogo.instance.leaves) {
      final b = p.path.getBounds();
      union = union == null ? b : union.expandToInclude(b);
    }
    return union!;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final b = leafBounds;
    final inner = size.shortestSide * (1 - 2 * padding);
    final scale = inner / (b.width > b.height ? b.width : b.height);
    canvas.save();
    canvas.translate(
      (size.width - b.width * scale) / 2 - b.left * scale,
      (size.height - b.height * scale) / 2 - b.top * scale,
    );
    canvas.scale(scale);
    for (final p in _ParsedLogo.instance.leaves) {
      canvas.drawPath(p.path, GudeLogoPainter._paintFor(p.shape));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GudeLeafMarkPainter old) => old.padding != padding;
}
