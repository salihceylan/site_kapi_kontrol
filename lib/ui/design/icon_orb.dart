// İkon rozeti (sade stil, İP-1C: karar G6 + G7).
//
// Listelerdeki, kart başlıklarındaki, diyalog ve boş durum başlıklarındaki ikon kutusudur: soluk yüzey zemin
// ([AppPalette.surfaceMuted]) + 1 px palet kenarı + tonun işaret renginde ikon ([AppTone.sign]: durum tonlarında `ink`,
// öteki tonlarda gövde metni rengi; mavi yalnız bağlantı ve odakta). Degrade, cila ve renkli parıltı YOKTUR. Durağandır
// (ticker yok), yalnız boyamadır; boyutu yazı ölçeğinden etkilenmez (sabit dp).
//
// **Erişilebilirlik**: rozet dekoratiftir (anlamsal ağaçta yok): anlamı yanındaki metin taşır.
// Rozet tek başına anlam taşıyorsa [semanticLabel] verilir. İkon zemine >= 4,5:1 (`icon_orb_test.dart`).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [IconOrb] biçimi.
enum IconOrbShape {
  /// Tam daire.
  circle,

  /// Yuvarlatılmış kare (köşe yarıçapı boyutun %30'u): liste/başlık rozetleri.
  squircle,
}

/// Düz ikon rozeti. [size] en az 24 dp; ikon boyutun yarısıdır.
class IconOrb extends StatelessWidget {
  const IconOrb({
    super.key,
    required this.icon,
    this.tone = AppTone.primary,
    this.size = 44,
    this.shape = IconOrbShape.circle,
    this.glow = false,
    this.semanticLabel,
  }) : assert(size >= 24, 'IconOrb en az 24 dp olmalı');

  final IconData icon;

  /// Anlamsal ton: yalnız durum tonları (success, warning, danger) ikonu renklendirir; öteki tonlar nötrdür.
  final AppTone tone;

  /// Kenar uzunluğu / çap (dp).
  final double size;

  final IconOrbShape shape;

  /// Geriye uyum için durur; sade stilde parıltı çizilmez (etkisiz).
  final bool glow;

  /// Rozet tek başına anlam taşıyorsa erişilebilirlik etiketi; null ise rozet dışlanır.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final circle = shape == IconOrbShape.circle;
    final radius = circle ? size / 2 : size * 0.30;
    final side = BorderSide(color: p.border);
    final orb = DecoratedBox(
      decoration: ShapeDecoration(
        shape: circle
            ? CircleBorder(side: side)
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: side,
              ),
        color: p.surfaceMuted,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(icon, size: size * 0.5, color: tone.sign(p)),
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: orb);
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: orb,
    );
  }
}
