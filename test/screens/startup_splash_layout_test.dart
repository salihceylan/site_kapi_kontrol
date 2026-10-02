// FAZ 5 / A2-G1: açılış / ara ekranı (StartupSplash, lib/app.dart) taşma + tasarım sistemi testleri.
//
// Oturum ya da ağ durumu belli olana dek eskiden tek başına bir çark gösteriliyordu; artık marka
// logosu (LoginHero, başlıksız) + aynı ilerleme göstergesi. Ekran seçim mantığı (`home`) değişmez.
// AGENTS.md kural 6: hiçbir pencerede taşma olmaz (320x640 x2,0 ve 360x640 x1,5, açık + koyu; alçak
// pencerede kaydırılır).
//
// Not: widget testleri Ahem yazı tipiyle çalışır; bu ekranda metin yoktur.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/app.dart';
import 'package:site_kapi_kontrol/ui/design/login_hero.dart';

import '../design/harness.dart';

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

Future<void> _pumpSplash(
  WidgetTester t, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
}) {
  return pumpAt(
    t,
    SizedBox(width: width, height: height, child: const StartupSplash()),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

void main() {
  for (final (w, h, s) in _cells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'StartupSplash taşma matrisi (${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'})',
        (t) async {
          await _pumpSplash(t, width: w, height: h, scale: s, dark: dark);

          expect(find.byType(LoginHero), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.byType(Image), findsOneWidget);
          // Yalnız logo: başlık / alt başlık yok (giriş ekranına özgü).
          expect(find.text('AHBU Giriş'), findsNothing);
          expect(
            find.text('Akıllı Kapı & Site Otomasyon Paneli'),
            findsNothing,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  group('StartupSplash: kompozisyon', () {
    testWidgets('logo çarkın ÜSTÜNDE ve yatayda ortalı', (t) async {
      await _pumpSplash(t, width: 360, height: 640);
      final hero = t.getRect(find.byType(LoginHero));
      final spinner = t.getRect(find.byType(CircularProgressIndicator));
      expect(hero.bottom, lessThanOrEqualTo(spinner.top));
      expect(hero.center.dx, closeTo(180, 1));
      expect(spinner.center.dx, closeTo(180, 1));
      // Düşey olarak kabaca ortada (içerik bloğu ekranın ortasında).
      final block = Rect.fromLTRB(
        hero.left,
        hero.top,
        hero.right,
        spinner.bottom,
      );
      expect(block.center.dy, closeTo(320, 24));
    });

    testWidgets('alçak pencerede (320x120 x2,0 / 640x240) taşmaz, kaydırılır', (
      t,
    ) async {
      for (final (w, h, s) in const <(double, double, double)>[
        (320, 120, 2.0),
        (640, 240, 1.0),
        (200, 160, 2.0),
      ]) {
        await _pumpSplash(t, width: w, height: h, scale: s);
        expect(find.byType(LoginHero), findsOneWidget, reason: '${w}x$h');
        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(t.takeException(), isNull, reason: '${w}x$h');
      }
    });

    testWidgets('hareket azaltma: tek pump ile logo tam görünür, taşma yok', (
      t,
    ) async {
      await _pumpSplash(t, width: 320, scale: 2.0, reduce: true);
      expect(find.byType(LoginHero), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('MyApp: açılış ekranı seçimi (mantık değişmedi)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    testWidgets(
      'ilk kare açılış ekranı (logo + çark); oturum hazır olunca giriş ekranı',
      (t) async {
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        await t.pumpWidget(const MyApp(networkCheckEnabled: false));
        // Kimlik servisi henüz hazır değil: tek başına çark yerine marka logosu + çark.
        expect(find.byType(StartupSplash), findsOneWidget);
        expect(find.byType(LoginHero), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Giriş Yap'), findsNothing);

        await t.pumpAndSettle();
        expect(find.byType(StartupSplash), findsNothing);
        expect(find.text('AHBU Giriş'), findsOneWidget);
        expect(find.text('Giriş Yap'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  });
}
