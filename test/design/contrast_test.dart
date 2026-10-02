// FAZ 5 / A0: tasarım tokenlarının HAKEM testi.
//
// - Tüm metin/zemin çiftleri (palet metinleri, her AppTone.ink yüzeyde ve kendi tint'inde, dolgu
//   üstünde beyaz) WCAG >= 4,5:1; QR halka renkleri >= 3,0:1.
// - AppTone.hue == role.accentColor (rol vurgusu tek kaynak).
// - AppTheme.light()/dark() kurulur, AppPalette uzantısı dolu; yerleşik widget tipleri (ElevatedButton,
//   AlertDialog, ListTile, ...) temada çalışmaya devam eder.
// - Dekorasyon/gölge bütçesi (tek katman, blur <= 16, spread yok) ve hareket tokenları.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/styles/role_theme.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// WCAG 2.x kontrast oranı; saydam ön plan [background] üzerine bindirilir.
double contrast(Color foreground, Color background) {
  expect(
    background.a,
    greaterThan(0.999),
    reason: 'Arka plan opak olmalı (saydam ise önce bindirin)',
  );
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const double kTextMin = 4.5;
const double kRingMin = 3.0;

List<Color> _pageColors(bool dark) {
  final decoration = dark
      ? AppDecorations.pageBackgroundDark
      : AppDecorations.pageBackgroundLight;
  return (decoration.gradient! as LinearGradient).colors;
}

/// Metnin üstünde durabileceği yüzeyler (metin tokenları için sözleşme kapsamı).
Map<String, Color> _surfaces(AppPalette p) {
  final page = _pageColors(p.isDark);
  return <String, Color>{
    'surface': p.surface,
    'surfaceMuted': p.surfaceMuted,
    if (p.isDark) ...{
      'surfaceAt(2)': p.surfaceAt(2),
      'surfaceAt(3)': p.surfaceAt(3),
    },
    'sayfa üstü': page[0],
    'sayfa ortası': page[1],
    // Koyuda sayfanın en altı da kapsamda; açıkta (E2E8F0) yalnız text/textSecondary için
    // (aşağıdaki ayrı test): muted metin ve tint'li rozet orada kapsam dışıdır.
    if (p.isDark) 'sayfa altı': page[2],
  };
}

void main() {
  const palettes = <String, AppPalette>{
    'açık': AppPalette.light,
    'koyu': AppPalette.dark,
  };

  group('AppPalette: tüm metin/zemin çiftleri >= 4,5:1', () {
    for (final entry in palettes.entries) {
      final p = entry.value;
      final texts = <String, Color>{
        'text': p.text,
        'textSecondary': p.textSecondary,
        'textMuted': p.textMuted,
      };
      for (final text in texts.entries) {
        for (final surface in _surfaces(p).entries) {
          test('${entry.key}: ${text.key} / ${surface.key}', () {
            final ratio = contrast(text.value, surface.value);
            expect(
              ratio,
              greaterThanOrEqualTo(kTextMin),
              reason: 'oran=${ratio.toStringAsFixed(2)}',
            );
          });
        }
      }
    }

    test(
      'açık: sayfa zemininin en alt ucunda (E2E8F0) text ve textSecondary >= 4,5',
      () {
        final bottom = _pageColors(false).last;
        expect(
          contrast(AppPalette.light.text, bottom),
          greaterThanOrEqualTo(kTextMin),
        );
        expect(
          contrast(AppPalette.light.textSecondary, bottom),
          greaterThanOrEqualTo(kTextMin),
        );
      },
    );

    test(
      'appTextTheme renkleri palet metinleridir (varsayılan metin = textSecondary)',
      () {
        for (final p in palettes.values) {
          final t = appTextTheme(p);
          expect(t.headlineMedium!.color, p.text);
          expect(t.titleLarge!.color, p.text);
          expect(t.titleMedium!.color, p.text);
          expect(t.bodyLarge!.color, p.text);
          expect(t.bodyMedium!.color, p.textSecondary);
          expect(t.bodySmall!.color, p.textMuted);
        }
      },
    );
  });

  group('AppTone: ink yüzeyde ve kendi tint\'inde >= 4,5:1', () {
    for (final tone in AppTone.values) {
      for (final entry in palettes.entries) {
        final p = entry.value;
        test('${tone.name} (${entry.key} tema)', () {
          final ink = tone.ink(p);
          expect(ink.a, 1.0, reason: 'ink opak olmalı');
          for (final surface in _surfaces(p).entries) {
            // Açıkta sayfa zemininin en alt ucu bu listede yok (bkz. _surfaces notu).
            final plain = contrast(ink, surface.value);
            expect(
              plain,
              greaterThanOrEqualTo(kTextMin),
              reason: '${surface.key} oran=${plain.toStringAsFixed(2)}',
            );
            final tinted = contrast(
              ink,
              Color.alphaBlend(tone.tint(p), surface.value),
            );
            expect(
              tinted,
              greaterThanOrEqualTo(kTextMin),
              reason: '${surface.key} + tint oran=${tinted.toStringAsFixed(2)}',
            );
          }
        });
      }

      test('${tone.name}: dolgu gradyanı (a ve b) üstünde beyaz >= 4,5', () {
        const white = Color(0xFFFFFFFF);
        expect(
          contrast(white, tone.a),
          greaterThanOrEqualTo(kTextMin),
          reason: 'a',
        );
        expect(
          contrast(white, tone.b),
          greaterThanOrEqualTo(kTextMin),
          reason: 'b',
        );
        final g = tone.gradient;
        expect(g.colors, <Color>[tone.a, tone.b]);
        expect(g.begin, Alignment.topLeft);
        expect(g.end, Alignment.bottomRight);
        expect(
          identical(g, tone.gradient),
          isTrue,
          reason: 'ton başına tek örnek',
        );
        // Gradyanın ortası da (a-b ara değeri) beyaz metni taşır.
        final mid = Color.lerp(tone.a, tone.b, 0.5)!;
        expect(
          contrast(white, mid),
          greaterThanOrEqualTo(kTextMin),
          reason: 'orta',
        );
      });

      test(
        '${tone.name}: açık ink koyu, koyu ink açık seviyededir; hue ikisinden de canlı',
        () {
          expect(
            tone.inkLight.computeLuminance(),
            lessThan(tone.hue.computeLuminance()),
          );
          expect(
            tone.inkDark.computeLuminance(),
            greaterThan(tone.hue.computeLuminance()),
          );
          expect(tone.ink(AppPalette.light), tone.inkLight);
          expect(tone.ink(AppPalette.dark), tone.inkDark);
        },
      );
    }

    test('tint: açıkta %12, koyuda %16 saydamlık (hue üstünde)', () {
      for (final tone in AppTone.values) {
        expect(tone.tint(AppPalette.light), tone.hue.withValues(alpha: 0.12));
        expect(tone.tint(AppPalette.dark), tone.hue.withValues(alpha: 0.16));
      }
    });
  });

  group('QR halka renkleri (DESIGN_SPEC D6) >= 3,0:1', () {
    const ring = <String, Color>{
      'iyi': Color(0xFF059669),
      'orta': Color(0xFFD97706),
      'az': Color(0xFFDC2626),
    };
    for (final entry in ring.entries) {
      for (final pe in palettes.entries) {
        test('${entry.key} / ${pe.key} yüzey', () {
          final ratio = contrast(entry.value, pe.value.surface);
          expect(
            ratio,
            greaterThanOrEqualTo(kRingMin),
            reason: 'oran=${ratio.toStringAsFixed(2)}',
          );
        });
      }
    }
  });

  group('Rol -> ton', () {
    test('AppTone.hue == role.accentColor (tüm roller)', () {
      for (final role in UserRole.values) {
        expect(role.tone.hue, role.accentColor, reason: role.name);
      }
    });

    test(
      'eşleme: süper=primary, site yöneticisi=success, daire/bireysel=violet',
      () {
        expect(UserRole.superUser.tone, AppTone.primary);
        expect(UserRole.siteManager.tone, AppTone.success);
        expect(UserRole.apartmentOwner.tone, AppTone.violet);
        expect(UserRole.individual.tone, AppTone.violet);
      },
    );

    test(
      'inkColor: rol rengi metin olarak okunur (>= 4,5), accentColor açıkta okunmaz',
      () {
        for (final role in UserRole.values) {
          for (final p in palettes.values) {
            expect(role.inkColor(p), role.tone.ink(p));
            expect(
              contrast(role.inkColor(p), p.surface),
              greaterThanOrEqualTo(kTextMin),
            );
          }
        }
        // Eski davranışın gerekçesi: zümrüt vurgu beyaz üstünde metin için yetersiz.
        expect(
          contrast(UserRole.siteManager.accentColor, AppPalette.light.surface),
          lessThan(kTextMin),
        );
      },
    );

    test('role_theme.dart mevcut üyeleri korunur (yalnız ek yapıldı)', () {
      expect(UserRole.superUser.accentColor, const Color(0xFF3B82F6));
      expect(UserRole.siteManager.lightAccentColor, const Color(0xFF34D399));
      expect(UserRole.individual.surfaceColor, const Color(0xFF3B0764));
      expect(UserRole.superUser.gradient.colors.length, 2);
    });
  });

  group('Ölçekler ve tokenlar', () {
    test('AppSpace / AppRadius değerleri', () {
      expect(
        <double>[
          AppSpace.xs,
          AppSpace.sm,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.xxl,
        ],
        <double>[4, 8, 12, 16, 24, 32],
      );
      expect(
        <double>[
          AppRadius.sm,
          AppRadius.md,
          AppRadius.lg,
          AppRadius.xl,
          AppRadius.pill,
        ],
        <double>[10, 16, 20, 28, 999],
      );
    });

    test('AppMotion süreleri ve eğrileri', () {
      expect(AppMotion.fast, const Duration(milliseconds: 120));
      expect(AppMotion.base, const Duration(milliseconds: 200));
      expect(AppMotion.slow, const Duration(milliseconds: 320));
      expect(
        AppMotion.slow,
        lessThanOrEqualTo(const Duration(milliseconds: 320)),
      );
      expect(AppMotion.enter, Curves.easeOutCubic);
      expect(AppMotion.exit, Curves.easeInCubic);
      expect(AppMotion.standard, Curves.fastOutSlowIn);
      expect(AppMotion.emphasized, Curves.easeInOutCubicEmphasized);
    });

    testWidgets(
      'AppMotion.of: hareket azaltmada Duration.zero, aksi hâlde aynı süre',
      (t) async {
        late BuildContext normal;
        late BuildContext reduced;
        await t.pumpWidget(
          MaterialApp(
            home: Column(
              children: [
                MediaQuery(
                  data: const MediaQueryData(),
                  child: Builder(
                    builder: (c) {
                      normal = c;
                      return const SizedBox();
                    },
                  ),
                ),
                MediaQuery(
                  data: const MediaQueryData(disableAnimations: true),
                  child: Builder(
                    builder: (c) {
                      reduced = c;
                      return const SizedBox();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
        expect(AppMotion.reduced(normal), isFalse);
        expect(AppMotion.of(normal, AppMotion.slow), AppMotion.slow);
        expect(AppMotion.reduced(reduced), isTrue);
        expect(AppMotion.of(reduced, AppMotion.slow), Duration.zero);
        expect(AppMotion.of(reduced, AppMotion.fast), Duration.zero);
      },
    );

    testWidgets('AppMotion.reduced: MediaQuery yoksa false (düz ağaç)', (
      t,
    ) async {
      late bool result;
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (c) {
              result = AppMotion.reduced(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isFalse);
    });

    test(
      'yükselti gölgesi bütçesi: tek katman, blur <= 16, spread yok, sabit liste',
      () {
        for (final p in palettes.values) {
          for (var level = 1; level <= 3; level++) {
            final shadows = p.shadow(level);
            expect(shadows, hasLength(1), reason: 'seviye $level');
            expect(shadows.single.blurRadius, lessThanOrEqualTo(16));
            expect(shadows.single.spreadRadius, 0);
            expect(shadows.single.offset, Offset(0, 2.0 * level));
            expect(
              identical(shadows, p.shadow(level)),
              isTrue,
              reason: 'canonical',
            );
          }
          // Seviye arttıkça gölge belirginleşir.
          expect(
            p.shadow(3).single.color.a,
            greaterThan(p.shadow(1).single.color.a),
          );
          expect(
            p.shadow(3).single.blurRadius,
            greaterThan(p.shadow(1).single.blurRadius),
          );
        }
      },
    );

    test('surfaceAt: açıkta sabit, koyuda seviye başına daha açık', () {
      expect(AppPalette.light.surfaceAt(1), AppPalette.light.surface);
      expect(AppPalette.light.surfaceAt(3), AppPalette.light.surface);
      final dark = AppPalette.dark;
      expect(dark.surfaceAt(1), dark.surface);
      expect(
        dark.surfaceAt(2).computeLuminance(),
        greaterThan(dark.surfaceAt(1).computeLuminance()),
      );
      expect(
        dark.surfaceAt(3).computeLuminance(),
        greaterThan(dark.surfaceAt(2).computeLuminance()),
      );
    });

    test(
      'AppPalette.lerp gerçekten ara değerler; copyWith ve null güvenli',
      () {
        const a = AppPalette.light;
        const b = AppPalette.dark;
        expect(a.lerp(b, 0).surface, a.surface);
        expect(a.lerp(b, 1).surface, b.surface);
        final mid = a.lerp(b, 0.5);
        expect(mid.surface, Color.lerp(a.surface, b.surface, 0.5));
        expect(mid.text, isNot(a.text));
        expect(mid.text, isNot(b.text));
        expect(a.lerp(b, 0.4).isDark, isFalse);
        expect(a.lerp(b, 0.6).isDark, isTrue);
        expect(a.lerp(null, 0.5), same(a));
        final c = a.copyWith(border: const Color(0xFF123456));
        expect(c.border, const Color(0xFF123456));
        expect(c.surface, a.surface);
        expect(c.isDark, isFalse);
      },
    );

    test(
      'appTextTheme ölçüleri (yalnız mevcut slotlar; label* dokunulmaz)',
      () {
        final t = appTextTheme(AppPalette.light);
        expect(t.headlineMedium!.fontSize, 24);
        expect(t.headlineMedium!.fontWeight, FontWeight.w800);
        expect(t.titleLarge!.fontSize, 18);
        expect(t.titleMedium!.fontSize, 15.5);
        expect(t.bodyLarge!.fontSize, 15);
        expect(t.bodyMedium!.fontSize, 13.5);
        expect(t.bodySmall!.fontSize, 12);
        for (final style in [
          t.headlineMedium,
          t.titleLarge,
          t.titleMedium,
          t.bodyLarge,
          t.bodyMedium,
          t.bodySmall,
        ]) {
          expect(style!.fontSize, greaterThanOrEqualTo(11));
          expect(style.height, isNotNull);
        }
        expect(t.labelLarge, isNull);
        expect(t.labelMedium, isNull);
        expect(t.labelSmall, isNull);
        expect(t.displayLarge, isNull);
        expect(t.titleSmall, isNull);
      },
    );

    test('sayfa ışıması: statik const, düşük alfa, iki tema', () {
      for (final g in [AppGradients.pageGlowLight, AppGradients.pageGlowDark]) {
        expect(g.center, const Alignment(0.9, -1.1));
        expect(g.colors.first.a, lessThanOrEqualTo(0.13));
        expect(g.colors.last.a, 0);
      }
      expect(
        AppGradients.pageGlowDark.colors.first.a,
        greaterThan(AppGradients.pageGlowLight.colors.first.a),
      );
    });
  });

  group('AppTheme', () {
    for (final entry in <String, ThemeData Function()>{
      'açık': AppTheme.light,
      'koyu': AppTheme.dark,
    }.entries) {
      final dark = entry.key == 'koyu';
      final palette = dark ? AppPalette.dark : AppPalette.light;

      test(
        '${entry.key}: kurulur, AppPalette uzantısı dolu ve doğru parlaklıkta',
        () {
          final theme = entry.value();
          expect(theme.useMaterial3, isTrue);
          expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
          final ext = theme.extension<AppPalette>();
          expect(ext, isNotNull);
          expect(ext!.isDark, dark);
          expect(identical(ext, palette), isTrue);
          expect(theme.scaffoldBackgroundColor, Colors.transparent);
        },
      );

      test('${entry.key}: tipografi, geçiş, yoğunluk ve tıklama hedefi', () {
        final theme = entry.value();
        final expected = appTextTheme(palette);
        expect(
          theme.textTheme.titleLarge!.fontSize,
          expected.titleLarge!.fontSize,
        );
        expect(theme.textTheme.titleLarge!.color, palette.text);
        expect(theme.textTheme.bodyMedium!.color, palette.textSecondary);
        expect(theme.textTheme.bodySmall!.color, palette.textMuted);
        expect(theme.textTheme.bodyLarge!.fontSize, 15);
        expect(
          identical(theme.pageTransitionsTheme, appPageTransitions),
          isTrue,
        );
        expect(theme.visualDensity, VisualDensity.standard);
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
        expect(identical(theme.splashFactory, InkRipple.splashFactory), isTrue);
      });

      test(
        '${entry.key}: appBar, chip, divider, input, dialog ve listTile',
        () {
          final theme = entry.value();
          expect(theme.appBarTheme.scrolledUnderElevation, 0);
          expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
          expect(theme.appBarTheme.elevation, 0);
          expect(theme.appBarTheme.backgroundColor, Colors.transparent);

          final chipShape = theme.chipTheme.shape! as RoundedRectangleBorder;
          expect(chipShape.borderRadius, BorderRadius.circular(AppRadius.md));
          expect(theme.chipTheme.side!.color, palette.border);

          expect(theme.dividerTheme.color, palette.border);
          expect(theme.dividerTheme.thickness, 1);
          expect(theme.dividerTheme.space, 1);

          final input = theme.inputDecorationTheme;
          expect(input.disabledBorder, isA<OutlineInputBorder>());
          expect(input.focusedErrorBorder, isA<OutlineInputBorder>());
          expect(input.disabledBorder!.borderSide.color, palette.border);
          expect(input.errorStyle!.color, AppTone.danger.ink(palette));
          expect(input.helperStyle!.color, palette.textMuted);
          expect(input.filled, isTrue);

          final dialogShape =
              theme.dialogTheme.shape! as RoundedRectangleBorder;
          expect(dialogShape.borderRadius, BorderRadius.circular(AppRadius.xl));

          expect(theme.listTileTheme.titleTextStyle, isNotNull);
          expect(theme.listTileTheme.subtitleTextStyle, isNotNull);
          expect(theme.listTileTheme.textColor, isNotNull);
          expect(
            theme.listTileTheme.titleTextStyle!.fontWeight,
            FontWeight.w600,
          );
        },
      );

      test(
        '${entry.key}: düğme temaları ve snackBar/drawer anahtarları aynı kaldı',
        () {
          final theme = entry.value();
          expect(
            theme.elevatedButtonTheme.style!.backgroundColor!.resolve(
              <WidgetState>{},
            ),
            AppColors.primary,
          );
          expect(
            theme.filledButtonTheme.style!.backgroundColor!.resolve(
              <WidgetState>{},
            ),
            AppColors.primary,
          );
          expect(theme.outlinedButtonTheme.style, isNotNull);
          expect(theme.textButtonTheme.style, isNotNull);
          expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
          expect(theme.drawerTheme.surfaceTintColor, Colors.transparent);
          expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        },
      );

      test(
        '${entry.key}: girdi ipucu/yardım/etiket metinleri >= 4,5 (alan dolgusu üstünde)',
        () {
          final theme = entry.value();
          final fill = dark
              ? Color.alphaBlend(
                  const Color(0xFF1E293B).withValues(alpha: 0.9),
                  _pageColors(true)[1],
                )
              : const Color(0xFFFFFFFF);
          final input = theme.inputDecorationTheme;
          for (final style in [
            input.hintStyle,
            input.helperStyle,
            input.labelStyle,
            input.errorStyle,
          ]) {
            final ratio = contrast(style!.color!, fill);
            expect(
              ratio,
              greaterThanOrEqualTo(kTextMin),
              reason: 'oran=${ratio.toStringAsFixed(2)}',
            );
          }
        },
      );
    }

    test(
      'tema DEĞER olarak eşittir (MyApp her yeniden kurulduğunda tema bağımlıları gereksiz yeniden kurulmaz)',
      () {
        expect(AppTheme.light() == AppTheme.light(), isTrue);
        expect(AppTheme.dark() == AppTheme.dark(), isTrue);
        expect(AppTheme.light() == AppTheme.dark(), isFalse);
        expect(AppTheme.light().hashCode, AppTheme.light().hashCode);
      },
    );

    test(
      'sayfa geçişi: Android/Windows/Linux AppPageTransitionsBuilder, iOS/macOS Cupertino',
      () {
        final b = appPageTransitions.builders;
        expect(b[TargetPlatform.android], isA<AppPageTransitionsBuilder>());
        expect(b[TargetPlatform.windows], isA<AppPageTransitionsBuilder>());
        expect(b[TargetPlatform.linux], isA<AppPageTransitionsBuilder>());
        expect(b[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
        expect(b[TargetPlatform.macOS], isA<CupertinoPageTransitionsBuilder>());
      },
    );

    for (final dark in [false, true]) {
      testWidgets(
        '${dark ? 'koyu' : 'açık'}: yerleşik widget tipleri temada çalışır (tip bulucuları)',
        (t) async {
          t.view.physicalSize = const Size(800, 1400);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          final palette = dark ? AppPalette.dark : AppPalette.light;
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: Scaffold(
                appBar: AppBar(title: const Text('Başlık')),
                body: ListView(
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Elevated'),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Outlined'),
                    ),
                    FilledButton(onPressed: () {}, child: const Text('Filled')),
                    TextButton(onPressed: () {}, child: const Text('Text')),
                    const ListTile(
                      title: Text('Liste'),
                      subtitle: Text('Alt metin'),
                      leading: Icon(Icons.home),
                    ),
                    const SwitchListTile(
                      value: true,
                      onChanged: null,
                      title: Text('Anahtar'),
                    ),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: 'Etiket',
                        errorText: 'Hata metni',
                      ),
                    ),
                    const TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Pasif',
                        helperText: 'Yardım metni',
                      ),
                    ),
                    Wrap(
                      children: [
                        ChoiceChip(
                          label: const Text('Seçili'),
                          selected: true,
                          onSelected: (_) {},
                        ),
                        FilterChip(
                          label: const Text('Süz'),
                          selected: false,
                          onSelected: (_) {},
                        ),
                      ],
                    ),
                    const Divider(),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Kart'),
                      ),
                    ),
                    const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          );
          await t.pump(const Duration(milliseconds: 300));
          expect(t.takeException(), isNull);
          expect(find.byType(ElevatedButton), findsOneWidget);
          expect(find.byType(OutlinedButton), findsOneWidget);
          expect(find.byType(FilledButton), findsOneWidget);
          expect(find.byType(TextButton), findsOneWidget);
          expect(find.byType(ListTile), findsWidgets);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.byType(ChoiceChip), findsOneWidget);
          // Hata metni temadaki ink rengiyle çizilir.
          final error = t.widget<Text>(find.text('Hata metni'));
          expect(error.style!.color, AppTone.danger.ink(palette));
          final helper = t.widget<Text>(find.text('Yardım metni'));
          expect(helper.style!.color, palette.textMuted);
        },
      );
    }

    testWidgets(
      'AppBar kaydırınca gri tonlanmaz: yükselti 0 ve tint şeffaf kalır (M3 scrolledUnder tonu yok)',
      (t) async {
        for (final dark in [false, true]) {
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: Scaffold(
                appBar: AppBar(title: const Text('Başlık')),
                body: ListView(
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 60, child: Text('Satır $i')),
                  ],
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          // M3, kaydırılınca AppBar'ın yüksekliğini scrolledUnderElevation'a çıkarıp surfaceTint
          // ile boyar (şeffaf bantta gri ton). Ton, Material'in elevation + surfaceTintColor'ındadır
          // (Material.color değil).
          Material appBarMaterial() => t.widget<Material>(
            find
                .descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Material),
                )
                .first,
          );
          final before = appBarMaterial();
          expect(before.elevation, 0, reason: 'dark=$dark');
          expect(
            before.surfaceTintColor,
            Colors.transparent,
            reason: 'dark=$dark',
          );
          await t.drag(find.byType(ListView), const Offset(0, -600));
          await t.pumpAndSettle();
          expect(
            find.text('Satır 0'),
            findsNothing,
            reason: 'liste gerçekten kaydı',
          );
          final after = appBarMaterial();
          expect(
            after.elevation,
            0,
            reason: 'kaydırınca yükselmez (dark=$dark)',
          );
          expect(
            after.surfaceTintColor,
            Colors.transparent,
            reason: 'dark=$dark',
          );
          expect(after.color, Colors.transparent, reason: 'dark=$dark');
        }
      },
    );

    testWidgets(
      'AlertDialog tipi korunur ve tema yarıçapını alır (açık+koyu)',
      (t) async {
        for (final dark in [false, true]) {
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: Builder(
                builder: (c) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: c,
                      builder: (_) => const AlertDialog(
                        title: Text('Onay'),
                        content: Text('İçerik'),
                      ),
                    ),
                    child: const Text('Aç'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Aç'));
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          final dialog = t.widget<AlertDialog>(find.byType(AlertDialog));
          expect(dialog.title, isA<Text>());
          final material = t.widget<Material>(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          );
          final shape = material.shape! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(AppRadius.xl));
          Navigator.of(t.element(find.byType(AlertDialog))).pop();
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
      },
    );
  });

  group('AppDecorations (imzalar aynı, içi tokenlara bağlı)', () {
    for (final dark in [false, true]) {
      testWidgets(
        '${dark ? 'koyu' : 'açık'}: glassCard/infoCard opak, tek katman gölge, AppRadius.lg',
        (t) async {
          final p = dark ? AppPalette.dark : AppPalette.light;
          late BoxDecoration glass;
          late BoxDecoration info;
          late BoxDecoration badge;
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: Builder(
                builder: (c) {
                  glass = AppDecorations.glassCard(c);
                  info = AppDecorations.infoCard(c);
                  badge = AppDecorations.glowingBadge(Colors.red, isDark: dark);
                  return const SizedBox();
                },
              ),
            ),
          );
          for (final d in [glass, info]) {
            expect(d.color, p.surface);
            expect(d.color!.a, 1.0, reason: 'opak yüzey (kompozit maliyeti)');
            expect(d.borderRadius, BorderRadius.circular(AppRadius.lg));
            expect((d.border! as Border).top.color, p.border);
            expect(d.boxShadow, hasLength(1));
            expect(d.boxShadow!.single.blurRadius, lessThanOrEqualTo(16));
            expect(d.boxShadow!.single.spreadRadius, 0);
            expect(d.boxShadow, p.shadow(1));
          }
          expect(badge.borderRadius, BorderRadius.circular(AppRadius.pill));
        },
      );
    }

    test('glassCardDark/Light statikleri ve pageBackground* korunur', () {
      expect(AppDecorations.glassCardLight.color, AppPalette.light.surface);
      expect(AppDecorations.glassCardDark.color, AppPalette.dark.surface);
      expect(
        AppDecorations.pageBackgroundLight.gradient,
        isA<LinearGradient>(),
      );
      expect(AppDecorations.pageBackgroundDark.gradient, isA<LinearGradient>());
      expect(_pageColors(false), const <Color>[
        Color(0xFFF8FAFC),
        Color(0xFFF1F5F9),
        Color(0xFFE2E8F0),
      ]);
      expect(_pageColors(true).first, AppColors.backgroundTop);
    });
  });

  group('context.palette', () {
    testWidgets(
      'temadaki uzantıyı verir; uzantısız düz tema parlaklığa göre varsayılana döner',
      (t) async {
        late AppPalette withExtension;
        late AppPalette plainLight;
        late AppPalette plainDark;
        await t.pumpWidget(
          Column(
            textDirection: TextDirection.ltr,
            children: [
              Theme(
                data: AppTheme.dark(),
                child: Builder(
                  builder: (c) {
                    withExtension = c.palette;
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: ThemeData(brightness: Brightness.light),
                child: Builder(
                  builder: (c) {
                    plainLight = c.palette;
                    return const SizedBox();
                  },
                ),
              ),
              Theme(
                data: ThemeData(brightness: Brightness.dark),
                child: Builder(
                  builder: (c) {
                    plainDark = c.palette;
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        );
        expect(withExtension, same(AppPalette.dark));
        expect(plainLight, same(AppPalette.light));
        expect(plainDark, same(AppPalette.dark));
      },
    );
  });
}
