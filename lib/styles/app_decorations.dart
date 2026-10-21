import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class AppDecorations {
  // Sayfa zemini (sade stil, karar G6): DÜZ renk = [AppPalette.background] (açıkta #F8FAFC "ana zemin", koyuda #0F172A).
  // Degrade ve ışıma yoktur. Adlar eskisiyle aynı (kabuk ve tam ekran kapılar bu sabitleri kullanır).
  static const BoxDecoration pageBackgroundDark = BoxDecoration(
    color: AppColors.backgroundTop,
  );

  static const BoxDecoration pageBackgroundLight = BoxDecoration(
    color: AppShowcaseColors.background,
  );

  static BoxDecoration pageBackground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? pageBackgroundDark
          // Açık tema: beyaz etiket (G9) zemini palet üzerinden gelir; varsayılan palette pageBackgroundLight ile aynı renk.
          : BoxDecoration(color: context.palette.background);

  // Kart yüzeyi (tasarım sistemi, sade stil G6): opak palet yüzeyi, AppRadius.lg, 1 px palet kenarı, GÖLGESİZ.
  // Eski "cam" kartların alfalı yüzeyi/çift gölgesi kalktı (kompozit maliyeti düşer; BackdropFilter yok).
  // Adlar ve imzalar eskisiyle aynı.
  static BoxDecoration _surfaceCard(AppPalette p) => BoxDecoration(
    color: p.surface,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: p.border),
  );

  // Koyu Kart (eski adıyla Dark Frosted Glassmorphic Card)
  static final BoxDecoration glassCardDark = _surfaceCard(AppPalette.dark);

  // Açık Kart (eski adıyla Luminous Frosted Glassmorphic Card)
  static final BoxDecoration glassCardLight = _surfaceCard(AppPalette.light);

  // Tema Duyarlı Kart
  static BoxDecoration glassCard(BuildContext context) =>
      context.palette.isDark ? glassCardDark : glassCardLight;

  // Bilgi Paneli / Kart
  static BoxDecoration infoCard(BuildContext context) =>
      context.palette.isDark ? glassCardDark : glassCardLight;

  // Kapsül Rozet (eski adıyla Glowing Badge): sade stilde ışıma (gölge) yok; ad geriye uyum için aynı.
  static BoxDecoration glowingBadge(Color accentColor, {bool isDark = true}) => BoxDecoration(
    color: accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
    borderRadius: BorderRadius.circular(AppRadius.pill),
    border: Border.all(
      color: accentColor.withValues(alpha: isDark ? 0.4 : 0.35),
      width: 1.2,
    ),
  );
}
