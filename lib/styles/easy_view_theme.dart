import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

// "Kolay görünüm" tema varyantı (P2-25): YÜKSEK KARŞITLIK paletleri + tema düzeyi büyük dokunma hedefleri.
//
// Kural: ekranlar yeniden çizilmez. Kolay görünüm açıkken uygulama kökü (lib/app.dart) bu temayı verir ve yazı ölçeğini
// en az [EasyViewService.minTextScale] yapar; paletten renk okuyan her bileşen (kart, çip, düğme, girdi) kendiliğinden
// uyar. Yalnız ana ekran (Panel vitrini) ayrıca sadeleşir (büyük düğmeler: `lib/ui/widgets/showcase_layouts.dart`).
//
// Kontrast (docs/TASARIM_DILI.md "Kolay görünüm" tablosu, `test/design/easy_view_theme_test.dart`): metin >= 7:1 (WCAG AAA),
// kart / girdi kenarı ve odak halkası >= 3:1 (kenar >= 4,5:1). Beyaz etiket (marka) paleti bu modda uygulanmaz:
// okunabilirlik markadan önce gelir.

/// Açık tema, yüksek karşıtlık: saf beyaz yüzey, siyah metin, koyu arduvaz kenar (beyazda 7,58:1).
final AppPalette kEasyLightPalette = AppPalette.light.copyWith(
  background: const Color(0xFFFFFFFF),
  surface: const Color(0xFFFFFFFF),
  surfaceMuted: const Color(0xFFF1F5F9),
  border: const Color(0xFF475569),
  text: const Color(0xFF000000),
  textSecondary: const Color(0xFF1E293B),
  textMuted: const Color(0xFF334155),
  action: const Color(0xFF000000),
  onAction: const Color(0xFFFFFFFF),
  link: const Color(0xFF1E40AF),
  focusRing: const Color(0xFF1E40AF),
  // Durum noktaları beyaz yüzeyde >= 3:1 (yeşil 5,48, kehribar 5,02, mercan 6,29): açık temadaki koyu kenar gerekmez.
  statusOk: const Color(0xFF047857),
  statusWarn: const Color(0xFFB45309),
  statusCrit: const Color(0xFFBE123C),
  critical: const Color(0xFF000000),
  onCritical: const Color(0xFFFFFFFF),
  criticalBorder: const Color(0xFF000000),
);

/// Koyu tema, yüksek karşıtlık: aynı koyu yüzeyler, saf beyaz metin, açık arduvaz kenar (kartta 5,71:1).
final AppPalette kEasyDarkPalette = AppPalette.dark.copyWith(
  border: const Color(0xFF94A3B8),
  text: const Color(0xFFFFFFFF),
  textSecondary: const Color(0xFFF1F5F9),
  textMuted: const Color(0xFFCBD5E1),
  action: const Color(0xFFFFFFFF),
  onAction: const Color(0xFF000000),
  link: const Color(0xFFBFDBFE),
  focusRing: const Color(0xFFBFDBFE),
  onCritical: const Color(0xFFFFFFFF),
  criticalBorder: const Color(0xFF93C5FD),
);

/// [p] kolay görünümün yüksek karşıtlık paleti mi? Renk tabanlıdır (kenar rengi): açık <-> koyu geçişinde ara değerli
/// palet (AnimatedTheme) kısa süre "hayır" döner, geçiş bitince doğru değere oturur.
bool isEasyPalette(AppPalette p) =>
    p.border == kEasyLightPalette.border || p.border == kEasyDarkPalette.border;

/// Kolay görünümün açık teması (ilk kullanımda bir kez kurulur).
final ThemeData easyViewLightTheme = _build(AppTheme.light(kEasyLightPalette), kEasyLightPalette);

/// Kolay görünümün koyu teması (ilk kullanımda bir kez kurulur).
final ThemeData easyViewDarkTheme = _build(AppTheme.dark(kEasyDarkPalette), kEasyDarkPalette);

/// Dokunma hedefi: kolay görünümde düğmeler en az bu yükseklikte (normalde 48).
const double kEasyMinButtonHeight = 56;

/// Çerçevenin kalınlığı (normalde 1): kart dışındaki girdi ve ikincil düğme çerçeveleri.
const double _borderWidth = 1.5;

ThemeData _build(ThemeData base, AppPalette p) {
  // Tema içinde sabit yazılmış gri tonlar (girdi etiketi, simge, kenar) paletin güçlü renklerine çekilir.
  OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: width),
  );

  ButtonStyle? taller(ButtonStyle? style) => style?.copyWith(
    minimumSize: const WidgetStatePropertyAll<Size>(Size(64, kEasyMinButtonHeight)),
  );

  final outlined = base.outlinedButtonTheme.style;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      outline: p.border,
      outlineVariant: p.border,
      onSurface: p.text,
      onSurfaceVariant: p.textSecondary,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      labelStyle: TextStyle(color: p.textSecondary),
      hintStyle: TextStyle(color: p.textMuted),
      suffixIconColor: p.textSecondary,
      border: outline(p.border, _borderWidth),
      enabledBorder: outline(p.border, _borderWidth),
      focusedBorder: outline(p.focusRing, 2.5),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: taller(base.elevatedButtonTheme.style)),
    filledButtonTheme: FilledButtonThemeData(style: taller(base.filledButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: taller(base.textButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: taller(outlined)?.copyWith(
        side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: p.border, width: _borderWidth)),
      ),
    ),
  );
}
