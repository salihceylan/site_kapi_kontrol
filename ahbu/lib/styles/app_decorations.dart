import 'package:flutter/material.dart';
import 'package:ahbu/styles/app_colors.dart';

class AppDecorations {
  static BoxDecoration pageBackground = const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
    ),
  );

  static BoxDecoration glassCard = BoxDecoration(
    color: Colors.white.withValues(alpha: 0.86),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.2),
    boxShadow: const [
      BoxShadow(
        color: AppColors.shadowDark,
        blurRadius: 28,
        offset: Offset(0, 14),
      ),
      BoxShadow(
        color: AppColors.shadowSoft,
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration infoCard = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    boxShadow: const [
      BoxShadow(
        color: AppColors.shadowDark,
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );
}
