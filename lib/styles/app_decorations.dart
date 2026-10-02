import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class AppDecorations {
  // Arka Plan Gradientleri
  static const BoxDecoration pageBackgroundDark = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.backgroundTop,
        Color(0xFF0B1120),
        AppColors.backgroundBottom,
      ],
      stops: [0.0, 0.5, 1.0],
    ),
  );

  static const BoxDecoration pageBackgroundLight = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFF8FAFC),
        Color(0xFFF1F5F9),
        Color(0xFFE2E8F0),
      ],
      stops: [0.0, 0.5, 1.0],
    ),
  );

  static BoxDecoration pageBackground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? pageBackgroundDark
          : pageBackgroundLight;

  // Kart yüzeyi (tasarım sistemi): opak palet yüzeyi, AppRadius.lg, palet kenarı, tek katman
  // seviye-1 gölge. Eski "cam" kartların alfalı yüzeyi/çift gölgesi kalktı (kompozit maliyeti
  // düşer; BackdropFilter yok). Adlar ve imzalar eskisiyle aynı.
  static BoxDecoration _surfaceCard(AppPalette p) => BoxDecoration(
    color: p.surface,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: p.border),
    boxShadow: p.shadow(1),
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

  // Işıltılı Kapsül Rozet (Glowing Badge)
  static BoxDecoration glowingBadge(Color accentColor, {bool isDark = true}) => BoxDecoration(
    color: accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
    borderRadius: BorderRadius.circular(AppRadius.pill),
    border: Border.all(
      color: accentColor.withValues(alpha: isDark ? 0.4 : 0.35),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
