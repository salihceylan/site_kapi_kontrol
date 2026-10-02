// FAZ 5 / A0: uygulama kökü (lib/app.dart builder) — yazı ölçeği üst sınırı ve statik ışıma.
//
// Mevcut mantık değişmedi: sayfa zemini gradyanı (AppDecorations.pageBackground) ve giriş ekranı aynı;
// üstüne metin ölçeği <= 2,0 sınırı ve tek, statik sayfa ışıması eklendi.
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
  await t.pumpWidget(const MyApp(networkCheckEnabled: false));
  await t.pumpAndSettle();
}

double _scaled(WidgetTester t) =>
    MediaQuery.textScalerOf(t.element(find.text('AHBU Giriş'))).scale(10);

Finder _glow(Gradient gradient) => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      identical((w.decoration as BoxDecoration).gradient, gradient),
);

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
        expect(find.text('AHBU Giriş'), findsOneWidget);
        expect(find.text('Giriş Yap'), findsOneWidget);
        expect(find.text('Şifremi Unuttum?'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('MyApp builder: sayfa zemini ve statik ışıma', () {
    testWidgets('açık tema: zemin gradyanı AYNI + üstünde tek açık ışıma', (
      t,
    ) async {
      await _pumpApp(t, textScale: 1.0);
      final bg = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            identical(w.decoration, AppDecorations.pageBackgroundLight),
      );
      // Kökteki zemin korunur (giriş sayfası şimdilik kendi zeminini de çiziyor: >= 1).
      expect(bg, findsWidgets, reason: 'mevcut sayfa zemini korunur');
      expect(_glow(AppGradients.pageGlowLight), findsOneWidget);
      expect(_glow(AppGradients.pageGlowDark), findsNothing);
      // Işıma kök zeminin içinde (üstünde boyanır), uygulama içeriğini sarar.
      expect(
        find.descendant(
          of: bg.first,
          matching: _glow(AppGradients.pageGlowLight),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _glow(AppGradients.pageGlowLight),
          matching: find.text('AHBU Giriş'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('koyu tema: koyu zemin + koyu ışıma', (t) async {
      await _pumpApp(t, textScale: 1.0, brightness: Brightness.dark);
      final bg = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            identical(w.decoration, AppDecorations.pageBackgroundDark),
      );
      expect(bg, findsWidgets);
      expect(
        find.descendant(
          of: bg.first,
          matching: _glow(AppGradients.pageGlowDark),
        ),
        findsOneWidget,
      );
      expect(_glow(AppGradients.pageGlowDark), findsOneWidget);
      expect(_glow(AppGradients.pageGlowLight), findsNothing);
    });

    testWidgets('ışıma statik: kararlı durumda ticker/kare yok', (t) async {
      await _pumpApp(t, textScale: 1.0);
      expect(t.binding.transientCallbackCount, 0);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('tema AppPalette uzantısını taşır (kökten erişilebilir)', (
      t,
    ) async {
      await _pumpApp(t, textScale: 1.0);
      final palette = t.element(find.text('AHBU Giriş')).palette;
      expect(palette, same(AppPalette.light));
    });
  });
}
