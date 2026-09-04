import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class AppDecorations {
  // Arka Plan Gradient (Deep Obsidian & Ambient Sapphire)
  static BoxDecoration pageBackground = const BoxDecoration(
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

  // Koyu Buzlu Cam Kart (Dark Frosted Glassmorphic Card)
  static BoxDecoration glassCard = BoxDecoration(
    color: const Color(0xFF1E293B).withValues(alpha: 0.88),
    borderRadius: BorderRadius.circular(26),
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
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.8),
      width: 1.2,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x30000000),
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );

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
      ),
    ],
  );

  // Işıltılı Kapsül Rozet (Glowing Badge)
  static BoxDecoration glowingBadge(Color accentColor) => BoxDecoration(
    color: accentColor.withValues(alpha: 0.16),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(
      color: accentColor.withValues(alpha: 0.4),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: accentColor.withValues(alpha: 0.2),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
