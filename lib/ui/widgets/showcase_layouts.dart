// Panel vitrininin ek yerleşimleri (P2-22 + P2-25): liste satırı (liste ↔ kutucuk anahtarı) ve KOLAY GÖRÜNÜM büyük
// düğmesi. Vitrinin kendisi `lib/ui/views/module_showcase_view.dart`; burası yalnız ek parçalardır.
//
// Renkler: normal temada vitrinin kendi renkleri ([AppShowcaseColors], işverenin tablosu), koyu temada ve kolay görünümün
// yüksek karşıtlık paletinde ([isEasyPalette]) palet; düz hex yazılmaz.
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/easy_view_theme.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show isLargeText;

/// Vitrin kartının zemini: açıkta işverenin beyazı, koyuda ve kolay görünümde palet yüzeyi.
Color showcaseCardColor(AppPalette p) => p.isDark || isEasyPalette(p) ? p.surface : AppShowcaseColors.card;

/// Vitrin kartının çerçevesi: kolay görünümde güçlü palet kenarı (>= 4,5:1), normalde ince #E2E8F0.
Color showcaseCardBorder(AppPalette p) => p.isDark || isEasyPalette(p) ? p.border : AppShowcaseColors.cardBorder;

/// Vitrin gövde metni: kolay görünümde palet ikincil metni (>= 7:1), normalde #475569.
Color showcaseBodyInk(AppPalette p) => p.isDark || isEasyPalette(p) ? p.textSecondary : AppShowcaseColors.text;

/// Rozet sayısı metni (99'dan büyük "99+").
String _countText(int count) => count > 99 ? '99+' : '$count';

/// Liste satırının sağındaki rozet: metnin soluna nokta + sayı (kutucuktaki rozetle aynı görünüm ve anahtarlar).
/// Dekoratiftir: sayı satırın erişilebilirlik etiketindedir.
class ShowcaseBadge extends StatelessWidget {
  const ShowcaseBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey<String>('panel_kart_rozet'),
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                key: const ValueKey<String>('panel_durum_noktasi'),
                decoration: BoxDecoration(color: AppTone.danger.a, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 8),
              ),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(
                  _countText(count),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.text, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste kipinde modül satırı: görsel + başlık + tek satır açıklama + rozet + ok. Kutucukla aynı anlamsal düğüm
/// (etiket = başlık + rozet, ipucu = açıklama) ve aynı kart anahtarıdır. Dar ekranda başlık ve açıklama sarar; çok büyük
/// yazıda (>= 1,75x) dekoratif görsel gizlenir, metne yer kalır.
class ShowcaseModuleRow extends StatelessWidget {
  const ShowcaseModuleRow({
    super.key,
    required this.title,
    required this.description,
    required this.art,
    required this.semanticLabel,
    required this.onTap,
    this.badge = 0,
  });

  final String title;
  final String description;
  final ModuleArtKind art;
  final String semanticLabel;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final showArt = !isLargeText(context);
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      hint: description.isEmpty ? null : description,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: showcaseCardColor(p),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: showcaseCardBorder(p)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  if (showArt) ...[
                    ModuleArt(kind: art, size: 44),
                    const SizedBox(width: AppSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: th.titleMedium),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(description, style: th.bodySmall?.copyWith(color: showcaseBodyInk(p))),
                        ],
                      ],
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: AppSpace.sm),
                    ShowcaseBadge(count: badge),
                  ],
                  const SizedBox(width: AppSpace.xs),
                  ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: showcaseBodyInk(p))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// KOLAY GÖRÜNÜM ana ekran düğmesi: tam genişlik, en az 72 dp, büyük başlık, kalın çerçeve (yüksek karşıtlık paleti), sağda ok.
/// Açıklama görünmez (sade ana ekran) ama ekran okuyucuya ipucu olarak okunur; bekleyen sayı başlığın altında "3 okunmamış"
/// biçiminde ve nokta işaretiyle yazılır. [art] (modül görseli) ya da [icon] (hesap / ayar öğeleri) soldadır; çok büyük
/// yazıda (>= 1,75x) gizlenir. Tek anlamsal düğüm.
class ShowcaseEasyButton extends StatelessWidget {
  const ShowcaseEasyButton({
    super.key,
    required this.title,
    required this.onTap,
    this.hint = '',
    this.art,
    this.icon,
    this.badge = 0,
    this.badgeNoun = 'bekleyen',
  });

  /// Düğmenin en düşük yüksekliği (dp); büyük yazıda içerik kadar uzar.
  static const double minHeight = 72;

  final String title;
  final String hint;
  final ModuleArtKind? art;
  final IconData? icon;
  final int badge;
  final String badgeNoun;
  final VoidCallback onTap;

  /// Ekran okuyucu etiketi: başlık + (varsa) rozet.
  String get semanticLabel => badge > 0 ? '$title, $badge $badgeNoun' : title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final art = this.art;
    final icon = this.icon;
    final showLead = !isLargeText(context) && (art != null || icon != null);
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      hint: hint.isEmpty ? null : hint,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: showcaseCardColor(p),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: showcaseCardBorder(p), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          focusColor: p.focusRing.withValues(alpha: 0.20),
          hoverColor: p.text.withValues(alpha: 0.06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: [
                  if (showLead) ...[
                    if (art != null)
                      ModuleArt(kind: art, size: 48)
                    else
                      SizedBox.square(
                        dimension: 48,
                        child: Center(child: Icon(icon, size: 30, color: p.text)),
                      ),
                    const SizedBox(width: AppSpace.lg),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: th.titleLarge),
                        if (badge > 0) ...[
                          const SizedBox(height: AppSpace.xs),
                          Row(
                            key: const ValueKey<String>('panel_kolay_rozet'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: AppTone.danger.a, shape: BoxShape.circle),
                                  child: const SizedBox.square(dimension: 10),
                                ),
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Flexible(
                                child: Text(
                                  '${_countText(badge)} $badgeNoun',
                                  style: th.bodyLarge?.copyWith(color: p.text, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, size: 32, color: p.text)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
