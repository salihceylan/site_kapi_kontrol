import 'package:flutter/material.dart';
import 'package:ahbu/styles/app_colors.dart';

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: AppColors.textDark),
        bodyMedium: TextStyle(color: AppColors.textMuted),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.white,
        backgroundColor: AppColors.primary,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFB8D7F7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFB8D7F7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      drawerTheme: const DrawerThemeData(
        surfaceTintColor: Colors.transparent,
        backgroundColor: AppColors.surface,
      ),
    );
  }
}
