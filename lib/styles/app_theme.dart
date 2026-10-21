import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Uygulama teması: sade stil (karar G6 + G7, `docs/TASARIM_DILI.md`).
///
/// - Ana onay düğmesi (`ElevatedButton`, `FilledButton`): [AppPalette.action] zemin + [AppPalette.onAction] metin, DÜZ
///   (yükselti 0, gölge yok, cila / degrade katmanı yok). Açıkta #0F172A + #F8FAFC, koyuda #F8FAFC + #0F172A (17,06:1).
/// - İkincil düğme (`OutlinedButton`): yüzey zemin + 1 px [AppPalette.border] çerçeve + başlık metni. Metin düğmesi
///   (`TextButton`, çoğunlukla "Vazgeç" / "Kapat") başlık metni renginde.
/// - Kart: yüzey + 1 px çerçeve, gölgesiz. Mavi yalnız odak halkasında (girdinin odak kenarı) ve bağlantıda.
/// - Yüzen katmanlar (diyalog, alt sayfa, açılır menü, bildirim çubuğu, ipucu) yükseltisini korur: sayfa içeriği değildir.
///
/// Tema DEĞER olarak eşittir (`AppTheme.light() == AppTheme.light()`): kapanış ya da `resolveWith` YOK.
class AppTheme {
  static ThemeData light() {
    const p = AppPalette.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: p.action,
      primary: p.action,
      onPrimary: p.onAction,
      // Seçili çip, bölümlü düğme ve gezinme göstergesi: nötr gri (tohumdan türeyen açık mavi-mor değil; mavi yalnız
      // bağlantı ve odakta). Üstündeki metin başlık rengi (14,5:1).
      secondaryContainer: p.border,
      onSecondaryContainer: p.text,
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
        // Sade stil: ikon gövde metni renginde (mavi yalnız odak halkasında).
        prefixIconColor: p.textSecondary,
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
          borderSide: BorderSide(color: p.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        // Odak halkası mavi (>= 3:1 beyaz alanda: 6,70:1).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.focusRing, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTone.danger.hue, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTone.danger.hue, width: 1.8),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
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
          backgroundColor: p.action,
          foregroundColor: p.onAction,
          elevation: 0,
          shadowColor: Colors.transparent,
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
          backgroundColor: p.action,
          foregroundColor: p.onAction,
          elevation: 0,
          shadowColor: Colors.transparent,
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
          foregroundColor: p.text,
          backgroundColor: p.surface,
          side: BorderSide(color: p.border),
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
          foregroundColor: p.text,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      // Bildirim çubuğu: kritik uyarı rengi (#0F172A); eylem bağlantı mavisi (koyu zeminde >= 4,5:1).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.critical,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: AppPalette.dark.link,
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
      // İnce ayarlar (tüm ekranlara tek yerden): yuvarlak uçlu ilerleme göstergeleri,
      // yuvarlatılmış açılır menü, koyu yumuşak ipucu ve üstü yuvarlak alt sayfa.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        linearMinHeight: 6,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x330F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: p.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xEB0F172A),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const p = AppPalette.dark;
    final colorScheme = ColorScheme.fromSeed(
      // Açık temayla aynı tohum (gece kömürü): türeyen kap renkleri aynı mavi-gri ailede kalır.
      seedColor: AppPalette.light.action,
      primary: p.action,
      onPrimary: p.onAction,
      // Seçili çip / gezinme göstergesi: nötr arduvaz (#334155), üstünde başlık metni (açık temadaki notla aynı).
      secondaryContainer: const Color(0xFF334155),
      onSecondaryContainer: p.text,
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
        prefixIconColor: p.textSecondary,
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
        // Odak halkası açık mavi (koyu alanda 8,11:1).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.focusRing, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTone.danger.hue, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTone.danger.hue, width: 1.8),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
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
      // Koyu temada ana düğme açık zemin + koyu metin: koyu sayfada en yüksek karşıtlık (17,06:1; karta 13,98:1).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.action,
          foregroundColor: p.onAction,
          elevation: 0,
          shadowColor: Colors.transparent,
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
          backgroundColor: p.action,
          foregroundColor: p.onAction,
          elevation: 0,
          shadowColor: Colors.transparent,
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
          foregroundColor: p.text,
          backgroundColor: p.surface,
          side: BorderSide(color: p.border),
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
          foregroundColor: p.text,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: p.link,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border, width: 1.2),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Color(0xFF0F172A),
      ),
      // İnce ayarlar (açık temadaki karşılıkları).
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        linearMinHeight: 6,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x80000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xF0334155),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1E293B),
        modalBackgroundColor: Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
    );
  }
}
