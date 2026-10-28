// "Kolay görünüm" tema varyantı (P2-25): yüksek karşıtlık paletleri (kontrast ölçümü), tema düzeyi büyük dokunma hedefleri ve
// uygulama kökü (MyApp) bağlantısı: büyük yazı ölçeği tabanı, tema değişimi ve açılıp kapanınca yeniden kurulum.
//
// Ekranlar yeniden çizilmez: tema ve yazı ölçeği değişir; paletten renk okuyan her bileşen kendiliğinden uyar.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/app.dart';
import 'package:site_kapi_kontrol/services/easy_view_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/styles/easy_view_theme.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// WCAG 2.x kontrast oranı (saydam ön plan opak [background] üstüne bindirilir).
double _contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Kolay görünüm kontrast tablosunun bir satırı: (ad, ön plan, zemin, en az oran).
typedef _Row = (String, Color, Color, double);

List<_Row> _table(AppPalette p) {
  final surfaces = <String, Color>{
    'sayfa': p.background,
    'kart': p.surface,
    'soluk yüzey': p.surfaceMuted,
    if (p.isDark) 'kart seviye 3': p.surfaceAt(3),
  };
  return <_Row>[
    for (final s in surfaces.entries) ...[
      // Metin: WCAG AAA (7:1).
      ('başlık metni / ${s.key}', p.text, s.value, 7.0),
      ('gövde metni / ${s.key}', p.textSecondary, s.value, 7.0),
      ('etiket metni / ${s.key}', p.textMuted, s.value, 7.0),
      ('bağlantı / ${s.key}', p.link, s.value, 7.0),
      ('odak halkası / ${s.key}', p.focusRing, s.value, 3.0),
    ],
    // Kart ve girdi kenarı belirgin: kartın ve sayfanın üstünde >= 4,5:1 (en az 3:1 gerekir).
    ('kenar / kart', p.border, p.surface, 4.5),
    ('kenar / sayfa', p.border, p.background, 4.5),
    ('ana düğme metni / ana düğme', p.onAction, p.action, 7.0),
    ('ana düğme / sayfa', p.action, p.background, 3.0),
    ('kritik kutu metni / kritik kutu', p.onCritical, p.critical, 7.0),
    ('kritik kutu ${p.isDark ? 'kenarı ' : ''}/ sayfa', p.isDark ? p.criticalBorder : p.critical, p.background, 3.0),
    ('durum noktası tamam / kart', p.statusOk, p.surface, 3.0),
    ('durum noktası bekliyor / kart', p.statusWarn, p.surface, 3.0),
    ('durum noktası kritik / kart', p.statusCrit, p.surface, 3.0),
  ];
}

Future<void> _pumpApp(
  WidgetTester t, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  EasyViewService? easy,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  t.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  await t.pumpWidget(MyApp(networkCheckEnabled: false, easyViewService: easy));
  await t.pumpAndSettle();
}

const String _anchor = 'Site ve Toplu Yaşam Yönetim Sistemi';

BuildContext _ctx(WidgetTester t) => t.element(find.text(_anchor));

double _scaled(WidgetTester t) => MediaQuery.textScalerOf(_ctx(t)).scale(10);

void main() {
  group('yüksek karşıtlık paletleri (kontrast tablosu)', () {
    for (final entry in <String, AppPalette>{'açık': kEasyLightPalette, 'koyu': kEasyDarkPalette}.entries) {
      test('${entry.key} palet: metin >= 7:1, kenar >= 4,5:1, bağlantı >= 7:1, odak ve durum noktaları >= 3:1', () {
        final failures = <String>[];
        for (final (name, fg, bg, min) in _table(entry.value)) {
          final ratio = _contrast(fg, bg);
          if (ratio < min) failures.add('$name: ${ratio.toStringAsFixed(2)}:1 < $min:1');
        }
        expect(failures, isEmpty);
      });
    }

    test('açık palet saf beyaz yüzey + siyah metin; koyu palet normal koyu paletten daha parlak metin ve kenar', () {
      expect(kEasyLightPalette.background, const Color(0xFFFFFFFF));
      expect(kEasyLightPalette.surface, const Color(0xFFFFFFFF));
      expect(kEasyLightPalette.text, const Color(0xFF000000));
      expect(kEasyLightPalette.isDark, isFalse);
      expect(kEasyDarkPalette.isDark, isTrue);
      expect(
        _contrast(kEasyDarkPalette.textMuted, kEasyDarkPalette.surface),
        greaterThan(_contrast(AppPalette.dark.textMuted, AppPalette.dark.surface)),
      );
      expect(
        _contrast(kEasyLightPalette.border, kEasyLightPalette.surface),
        greaterThan(_contrast(AppPalette.light.border, AppPalette.light.surface) * 3),
        reason: 'kart kenarı normal temadan çok daha belirgin',
      );
    });

    test('isEasyPalette yalnız kolay görünüm paletlerini tanır', () {
      expect(isEasyPalette(kEasyLightPalette), isTrue);
      expect(isEasyPalette(kEasyDarkPalette), isTrue);
      expect(isEasyPalette(AppPalette.light), isFalse);
      expect(isEasyPalette(AppPalette.dark), isFalse);
    });
  });

  group('tema varyantı', () {
    test('kolay görünüm temaları kendi paletini taşır; koyu / açık parlaklığı doğru', () {
      expect(easyViewLightTheme.brightness, Brightness.light);
      expect(easyViewDarkTheme.brightness, Brightness.dark);
      expect(easyViewLightTheme.extension<AppPalette>(), same(kEasyLightPalette));
      expect(easyViewDarkTheme.extension<AppPalette>(), same(kEasyDarkPalette));
    });

    test('metin teması paletin yüksek karşıtlık renklerinden gelir', () {
      expect(easyViewLightTheme.textTheme.titleMedium?.color, kEasyLightPalette.text);
      expect(easyViewLightTheme.textTheme.bodyMedium?.color, kEasyLightPalette.textSecondary);
      expect(easyViewDarkTheme.textTheme.bodySmall?.color, kEasyDarkPalette.textMuted);
    });

    test('düğmeler tema düzeyinde büyük: en az 56 dp yükseklik; ikincil düğme kalın çerçeveli', () {
      for (final theme in <ThemeData>[easyViewLightTheme, easyViewDarkTheme]) {
        for (final style in <ButtonStyle?>[
          theme.elevatedButtonTheme.style,
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
        ]) {
          expect(style?.minimumSize?.resolve(<WidgetState>{})?.height, kEasyMinButtonHeight);
        }
        final side = theme.outlinedButtonTheme.style?.side?.resolve(<WidgetState>{});
        expect(side?.width, greaterThanOrEqualTo(1.5));
        expect(side?.color, theme.extension<AppPalette>()!.border);
      }
    });

    test('girdi çerçevesi güçlü (>= 1,5 px palet kenarı), odak çerçevesi kalın', () {
      for (final theme in <ThemeData>[easyViewLightTheme, easyViewDarkTheme]) {
        final p = theme.extension<AppPalette>()!;
        final enabled = theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
        final focused = theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
        expect(enabled.borderSide.color, p.border);
        expect(enabled.borderSide.width, greaterThanOrEqualTo(1.5));
        expect(focused.borderSide.color, p.focusRing);
        expect(focused.borderSide.width, greaterThanOrEqualTo(2.5));
        expect(theme.inputDecorationTheme.labelStyle?.color, p.textSecondary);
        expect(theme.colorScheme.outline, p.border);
      }
    });

    test('normal temalar DEĞİŞMEDİ: aynı çağrı eşit, palet normal', () {
      expect(AppTheme.light() == AppTheme.light(), isTrue);
      expect(AppTheme.dark() == AppTheme.dark(), isTrue);
      expect(AppTheme.dark().extension<AppPalette>(), same(AppPalette.dark));
      expect(AppTheme.light().extension<AppPalette>(), same(AppPalette.light));
      expect(AppTheme.dark().elevatedButtonTheme.style?.minimumSize, isNull);
    });
  });

  group('MyApp: kolay görünüm uygulama köküne bağlı', () {
    testWidgets('kapalıyken (varsayılan) hiçbir şey değişmez: ölçek aynen, normal tema', (t) async {
      await _pumpApp(t, textScale: 1.0);
      expect(_scaled(t), closeTo(10, 1e-9));
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(AppPalette.light));
    });

    testWidgets('açıkken yazı ölçeği en az 1,3: 1,0 -> 1,3; 1,5 aynen; 2,0 üstü 2,0\'a iner', (t) async {
      final easy = EasyViewService();
      await easy.setEnabled(true);
      for (final entry in <double, double>{1.0: 13, 1.15: 13, 1.5: 15, 2.0: 20, 3.0: 20}.entries) {
        await _pumpApp(t, textScale: entry.key, easy: easy);
        expect(_scaled(t), closeTo(entry.value, 1e-9), reason: 'sistem ölçeği ${entry.key}');
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('açıkken tema yüksek karşıtlık paletidir (açık ve koyu); giriş ekranı taşmadan kurulur', (t) async {
      final easy = EasyViewService();
      await easy.setEnabled(true);
      await _pumpApp(t, textScale: 2.0, brightness: Brightness.light, easy: easy);
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(kEasyLightPalette));
      expect(find.text('Giriş Yap'), findsOneWidget);

      await _pumpApp(t, textScale: 2.0, brightness: Brightness.dark, easy: easy);
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(kEasyDarkPalette));
      expect(t.takeException(), isNull);
    });

    testWidgets('çalışırken açıp kapatınca ağaç yeniden kurulur: ölçek ve palet anında değişir, tercih saklanır', (t) async {
      final easy = EasyViewService();
      await _pumpApp(t, textScale: 1.0, easy: easy);
      expect(_scaled(t), closeTo(10, 1e-9));
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(AppPalette.light));

      await easy.setEnabled(true);
      await t.pumpAndSettle();
      expect(_scaled(t), closeTo(13, 1e-9));
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(kEasyLightPalette));
      expect((await SharedPreferences.getInstance()).getBool(EasyViewService.storageKey), isTrue);

      await easy.setEnabled(false);
      await t.pumpAndSettle();
      expect(_scaled(t), closeTo(10, 1e-9));
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(AppPalette.light));
      expect(t.takeException(), isNull);
    });

    testWidgets('servis verilmezse MyApp kendisi kurar ve kayıtlı tercihi yükler (testler / eski çağrılar)', (t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{EasyViewService.storageKey: true});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MyApp(networkCheckEnabled: false));
      await t.pumpAndSettle();
      expect(_scaled(t), closeTo(13, 1e-9));
      expect(Theme.of(_ctx(t)).extension<AppPalette>(), same(kEasyLightPalette));
    });
  });
}
