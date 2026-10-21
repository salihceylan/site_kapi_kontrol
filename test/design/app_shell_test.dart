// FAZ 5 / A0: uygulama kökü (lib/app.dart builder) — yazı ölçeği üst sınırı ve sayfa zemini.
//
// Mevcut mantık değişmedi: sayfa zemini (AppDecorations.pageBackground) ve giriş ekranı aynı; metin ölçeği <= 2,0
// sınırı korunur. İP-1C (karar G6, sade stil): zemin DÜZ renktir (açıkta #F8FAFC, koyuda #0F172A) ve üstünde ışıma
// katmanı YOKTUR.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/app.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

Future<void> _pumpApp(
  WidgetTester t, {
  required double textScale,
  Brightness brightness = Brightness.light,
  String? savedTheme,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'app_theme_mode': ?savedTheme,
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  t.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  await t.pumpWidget(const MyApp(networkCheckEnabled: false));
  await t.pumpAndSettle();
}

double _scaled(WidgetTester t) =>
    MediaQuery.textScalerOf(t.element(find.text('Site ve Toplu Yaşam Yönetim Sistemi'))).scale(10);

/// Kabuğun (MaterialApp.builder) sayfa içeriğini (Navigator) saran süsleme katmanları, dıştan içe.
List<BoxDecoration> _shellLayers(WidgetTester t) => t
    .widgetList<DecoratedBox>(
      find.ancestor(of: find.byType(Navigator).first, matching: find.byType(DecoratedBox)),
    )
    .map((b) => b.decoration)
    .whereType<BoxDecoration>()
    .toList();

void main() {
  group('MyApp builder: metin ölçeği sınırı', () {
    testWidgets('sistem ölçeği 3,0 iken uygulama içinde en çok 2,0 görülür', (
      t,
    ) async {
      await _pumpApp(t, textScale: 3.0);
      expect(_scaled(t), closeTo(20, 1e-9), reason: '10 punto x 2,0');
      expect(t.takeException(), isNull);
    });

    testWidgets('2,0 üstü hepsi 2,0\'a iner; altı değişmez (1,0 / 1,5 / 2,0)', (
      t,
    ) async {
      for (final entry in <double, double>{
        1.0: 10,
        1.5: 15,
        2.0: 20,
        2.5: 20,
      }.entries) {
        await _pumpApp(t, textScale: entry.key);
        expect(
          _scaled(t),
          closeTo(entry.value, 1e-9),
          reason: 'sistem ölçeği ${entry.key}',
        );
      }
    });

    testWidgets(
      'giriş ekranı 2,0 ölçekte taşmadan kurulur (mevcut mantık korunur)',
      (t) async {
        await _pumpApp(t, textScale: 3.0);
        expect(find.text('Site ve Toplu Yaşam Yönetim Sistemi'), findsOneWidget);
        expect(find.text('Giriş Yap'), findsOneWidget);
        expect(find.text('Şifremi Unuttum?'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('MyApp: kullanıcı tema tercihi (aydınlık / karanlık geçiş düğmesi)', () {
    testWidgets('kayıtlı "dark" tercihi sistem AÇIK olsa da koyu temayla açılır', (t) async {
      await _pumpApp(
        t,
        textScale: 1.0,
        brightness: Brightness.light,
        savedTheme: 'dark',
      );
      expect(Theme.of(t.element(find.text('Site ve Toplu Yaşam Yönetim Sistemi'))).brightness, Brightness.dark);
      expect(_shellLayers(t).any((d) => identical(d, AppDecorations.pageBackgroundDark)), isTrue);
    });

    testWidgets('kayıtlı tercih yoksa sistem teması izlenir (varsayılan davranış)', (t) async {
      await _pumpApp(t, textScale: 1.0, brightness: Brightness.dark);
      expect(Theme.of(t.element(find.text('Site ve Toplu Yaşam Yönetim Sistemi'))).brightness, Brightness.dark);
      await _pumpApp(t, textScale: 1.0, brightness: Brightness.light);
      expect(Theme.of(t.element(find.text('Site ve Toplu Yaşam Yönetim Sistemi'))).brightness, Brightness.light);
    });

    testWidgets('giriş ekranındaki düğme temayı değiştirir, zemin güncellenir ve tercih saklanır', (t) async {
      await _pumpApp(t, textScale: 1.0, brightness: Brightness.light);
      expect(_shellLayers(t).any((d) => identical(d, AppDecorations.pageBackgroundLight)), isTrue);

      await t.tap(find.byTooltip('Koyu temaya geç'));
      await t.pumpAndSettle();

      expect(Theme.of(t.element(find.text('Site ve Toplu Yaşam Yönetim Sistemi'))).brightness, Brightness.dark);
      expect(_shellLayers(t).any((d) => identical(d, AppDecorations.pageBackgroundDark)), isTrue);
      expect(_shellLayers(t).any((d) => identical(d, AppDecorations.pageBackgroundLight)), isFalse);
      expect(find.byTooltip('Aydınlık temaya geç'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('app_theme_mode'),
        'dark',
      );
      expect(t.takeException(), isNull);
    });
  });

  group('MyApp builder: sayfa zemini (sade stil: düz renk, ışıma yok)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets('${dark ? 'koyu' : 'açık'} tema: kök zemin düz palet zemini, içeriği sarar; degrade / ışıma katmanı yok', (
        t,
      ) async {
        await _pumpApp(t, textScale: 1.0, brightness: dark ? Brightness.dark : Brightness.light);
        final expected = dark ? AppDecorations.pageBackgroundDark : AppDecorations.pageBackgroundLight;
        final layers = _shellLayers(t);
        expect(layers.where((d) => identical(d, expected)), hasLength(1), reason: 'kök zemin tek ve mevcut sabit');
        expect(expected.color, dark ? AppPalette.dark.background : AppPalette.light.background);
        expect(expected.gradient, isNull);
        expect(layers.where((d) => d.gradient != null), isEmpty, reason: 'ışıma / degrade katmanı yok');
        expect(
          find.descendant(
            of: find.byWidgetPredicate((w) => w is DecoratedBox && identical(w.decoration, expected)),
            matching: find.text('Site ve Toplu Yaşam Yönetim Sistemi'),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('zemin statik: kararlı durumda ticker/kare yok', (t) async {
      await _pumpApp(t, textScale: 1.0);
      expect(t.binding.transientCallbackCount, 0);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('tema AppPalette uzantısını taşır (kökten erişilebilir)', (
      t,
    ) async {
      await _pumpApp(t, textScale: 1.0);
      final palette = t.element(find.text('Site ve Toplu Yaşam Yönetim Sistemi')).palette;
      expect(palette, same(AppPalette.light));
    });
  });
}
