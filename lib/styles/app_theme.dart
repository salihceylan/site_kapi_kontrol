import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class AppTheme {
  static ThemeData light() {
    const p = AppPalette.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      extensions: const <ThemeExtension<dynamic>>[AppPalette.light],
      // Masaüstünde de 48 dp isabet alanı ve standart yoğunluk (compact isabeti küçültür).
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // InkSparkle shader maliyeti yok.
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: appPageTransitions,
      textTheme: appTextTheme(p),
      listTileTheme: ListTileThemeData(
        textColor: p.text,
        iconColor: p.text,
        titleTextStyle: TextStyle(
          color: p.text,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        subtitleTextStyle: TextStyle(
          color: p.textSecondary,
          fontSize: 12.5,
        ),
      ),
      // Seçili çipin onay işareti çağrı yerinde belirlenir: seçili dolgu (saturasyonlu mavi ya da
      // %20 tint) bilinmeden genel bir işaret rengi iki durumdan birinde görünmez kalır.
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        side: BorderSide(color: p.border),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.textDark,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        // İpucu metni de metindir (>= 4,5:1): eski #94A3B8 beyaz üstünde ~2,6:1 idi.
        hintStyle: TextStyle(color: p.textMuted),
        helperStyle: TextStyle(color: p.textMuted),
        errorStyle: TextStyle(color: AppTone.danger.ink(p)),
        prefixIconColor: AppColors.primary,
        suffixIconColor: AppColors.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.rose, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.rose, width: 1.8),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: const Color(0x100F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textDark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppColors.shadowSoft,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
      ),
    );
  }

  static ThemeData dark() {
    const p = AppPalette.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accentLight,
      surface: AppColors.surface,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFCBD5E1),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      extensions: const <ThemeExtension<dynamic>>[AppPalette.dark],
      // Masaüstünde de 48 dp isabet alanı ve standart yoğunluk (compact isabeti küçültür).
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // InkSparkle shader maliyeti yok.
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: appPageTransitions,
      textTheme: appTextTheme(p),
      // Seçili çipin onay işareti çağrı yerinde belirlenir (bkz. açık tema notu).
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        side: BorderSide(color: p.border),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.textLight,
        iconColor: AppColors.textLight,
        titleTextStyle: TextStyle(
          color: AppColors.textLight,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        subtitleTextStyle: TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 12.5,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B).withValues(alpha: 0.9),
        labelStyle: const TextStyle(color: AppColors.textMutedLight),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        helperStyle: TextStyle(color: p.textMuted),
        errorStyle: TextStyle(color: AppTone.danger.ink(p)),
        prefixIconColor: AppColors.primarySoft,
        suffixIconColor: AppColors.textMutedLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.rose, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.rose, width: 1.8),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: const Color(0x50000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textLight,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: Color(0xFFCBD5E1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: AppColors.shadowSoft,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF93C5FD),
          side: const BorderSide(color: Color(0x403B82F6), width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x333B82F6), width: 1.2),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Color(0xFF0F172A),
      ),
    );
  }
}
