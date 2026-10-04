// Premium ikon rozeti: cilalı küre / squircle.
//
// Listelerdeki, kart başlıklarındaki, diyalog ve boş durum başlıklarındaki DÜZ renkli ikon
// kutularının yerine geçer: ton gradyanı + [Gloss] cilası + beyaz ikon (+ isteğe bağlı glow).
// Durağandır (ticker yok), yalnız boyamadır; boyutu yazı ölçeğinden etkilenmez (sabit dp).
//
// **Erişilebilirlik**: rozet dekoratiftir (anlamsal ağaçta yok): anlamı yanındaki metin taşır.
// Rozet tek başına anlam taşıyorsa [semanticLabel] verilir. Beyaz ikon ton gradyanında >= 3:1
// (cila dahil, `gloss_test.dart` ölçer).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// [IconOrb] biçimi.
enum IconOrbShape {
  /// Tam daire.
  circle,

  /// Yuvarlatılmış kare (köşe yarıçapı boyutun %30'u): liste/başlık rozetleri.
  squircle,
}

/// Cilalı ikon rozeti. [size] en az 24 dp; ikon boyutun yarısıdır.
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

  /// Gradyan tonu (anlamsal): primary, success, warning, info, danger, violet, neutral.
  final AppTone tone;

  /// Kenar uzunluğu / çap (dp).
  final double size;

  final IconOrbShape shape;

  /// true: tonun renkli glow gölgesi (tek katman, blur <= 16). Vurgulu başlıklarda kullanın.
  final bool glow;

  /// Rozet tek başına anlam taşıyorsa erişilebilirlik etiketi; null ise rozet dışlanır.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final circle = shape == IconOrbShape.circle;
    final radius = circle ? size / 2 : size * 0.30;
    final orb = DecoratedBox(
      decoration: ShapeDecoration(
        shape: circle
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        gradient: tone.gradient,
        shadows: glow
            ? [
                BoxShadow(
                  color: tone.a.withValues(alpha: 0.32),
                  blurRadius: (size * 0.30).clamp(6.0, 16.0),
                  offset: Offset(0, size * 0.09),
                ),
              ]
            : null,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Gloss(
                shape: circle ? GlossShape.circle : GlossShape.rounded,
                radius: radius,
                strength: 0.9,
                // Listelerde onlarca rozet olabilir: ayrı katman gereksiz.
                isolate: false,
              ),
            ),
            Icon(
              icon,
              size: size * 0.5,
              color: Colors.white,
              shadows: const <Shadow>[
                Shadow(
                  color: Color(0x40000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ],
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
