import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class AppDecorations {
  // Arka Plan Gradient (Deep Obsidian & Ambient Sapphire)
  static BoxDecoration pageBackground = const BoxDecoration(
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

  // Koyu Buzlu Cam Kart (Dark Frosted Glassmorphic Card)
  static BoxDecoration glassCard = BoxDecoration(
  static final BoxDecoration glassCardDark = BoxDecoration(
    color: const Color(0xFF1E293B).withValues(alpha: 0.88),
    borderRadius: BorderRadius.circular(26),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.12),
      width: 1.2,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x60000000),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
      BoxShadow(
        color: Color(0x1038BDF8),
        blurRadius: 16,
        offset: Offset(0, 2),
      ),
    ],
  );

  // Aydınlık / İkincil Cam Kart
  static BoxDecoration glassCardLight = BoxDecoration(
    color: Colors.white.withValues(alpha: 0.95),
    borderRadius: BorderRadius.circular(22),
  // Açık Buzlu Cam Kart (Luminous Frosted Glassmorphic Card)
  static final BoxDecoration glassCardLight = BoxDecoration(
    color: Colors.white.withValues(alpha: 0.94),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.8),
      color: const Color(0xFFE2E8F0),
      width: 1.2,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x30000000),
        blurRadius: 18,
        color: Color(0x0F0F172A),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
      BoxShadow(
        color: Color(0x06000000),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ],
  );

  // Tema Duyarlı Cam Kart
  static BoxDecoration glassCard(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? glassCardDark
          : glassCardLight;

  // Bilgi Paneli / Kart
  static BoxDecoration infoCard = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.08),
      width: 1.0,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 14,
        offset: Offset(0, 6),
  static BoxDecoration infoCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.surface : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        width: 1.0,
      ),
    ],
  );
      boxShadow: [
        BoxShadow(
          color: isDark ? const Color(0x40000000) : const Color(0x0A000000),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  // Işıltılı Kapsül Rozet (Glowing Badge)
  static BoxDecoration glowingBadge(Color accentColor) => BoxDecoration(
    color: accentColor.withValues(alpha: 0.16),
  static BoxDecoration glowingBadge(Color accentColor, {bool isDark = true}) => BoxDecoration(
    color: accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(
      color: accentColor.withValues(alpha: 0.4),
      color: accentColor.withValues(alpha: isDark ? 0.4 : 0.35),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: accentColor.withValues(alpha: 0.2),
        color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
