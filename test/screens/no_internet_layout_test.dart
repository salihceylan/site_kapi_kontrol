// FAZ 5 / A2-G1: internet yok ekranı (NoInternetPage) taşma + tasarım sistemi testleri.
//
// AGENTS.md kural 6: hiçbir ekranda taşma olmaz. Matris: 320x640 x2,0 ve 360x640 x1,5, her biri açık
// ve koyu temada, hem "tekrar dene" hem "kontrol ediliyor" durumunda. Davranış (yeniden deneme
// çağrısı, kontrol sırasında pasif düğme) ve metinler (ASCII Türkçe dahil) değişmez; yalnız görünüm:
// AppCard(2) + uyarı tonlu ikon karosu; açıklama metni koyu temada `textSecondary`
// (eskiden `textMuted`, koyuda ~3,1:1); "Tekrar Dene" `ElevatedButton.icon` olarak KALIR (tema).
//
// Not: widget testleri Ahem yazı tipiyle çalışır (her harf 1 em genişliğinde): satır sarma gerçek
// cihazdan daha serttir; geçen taşma testi gerçek yazı tipinde de geçer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/no_internet_page.dart';

import '../design/harness.dart';

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

const String _title = 'Internet baglantisi bulunamadi';
const String _message =
    'Lutfen cihazinizda Wi-Fi veya mobil veriyi acin. Sonra tekrar deneyin.';

/// Sayfayı verilen ölçüde kurar (pumpAt gövdeyi kaydırılabilir sarar: sayfaya sabit boyut verilir).
Future<void> _pumpPage(
  WidgetTester t, {
  bool checking = false,
  Future<void> Function()? onRetry,
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
}) {
  return pumpAt(
    t,
    SizedBox(
      width: width,
      height: height,
      child: NoInternetPage(
        isChecking: checking,
        onRetry: onRetry ?? () async {},
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (w, h, s) in _cells) {
    for (final dark in const <bool>[false, true]) {
      for (final checking in const <bool>[false, true]) {
        final cell =
            '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'} ${checking ? 'kontrol ediliyor' : 'tekrar dene'}';

        testWidgets(
          'NoInternetPage taşma matrisi ($cell): öğeler var, taşma yok',
          (t) async {
            await _pumpPage(
              t,
              checking: checking,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );

            expect(
              find.text('Baglanti Gerekli'),
              findsOneWidget,
            ); // AppBar başlığı
            expect(find.text(_title), findsOneWidget);
            expect(find.text(_message), findsOneWidget);
            expect(
              find.text(checking ? 'Kontrol Ediliyor...' : 'Tekrar Dene'),
              findsOneWidget,
            );
            expect(find.byType(ElevatedButton), findsOneWidget);
            expect(
              find.byType(CircularProgressIndicator),
              checking ? findsOneWidget : findsNothing,
            );
            expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }

  group('NoInternetPage: davranış ve tasarım sistemi bağları', () {
    testWidgets(
      '"Tekrar Dene" ElevatedButton.icon KALIR; dokunmak onRetry\'yi bir kez çağırır',
      (t) async {
        var retries = 0;
        await _pumpPage(t, onRetry: () async => retries++);

        final button = find.widgetWithText(ElevatedButton, 'Tekrar Dene');
        expect(button, findsOneWidget);
        expect(t.getSize(button).height, greaterThanOrEqualTo(44));
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        await t.tap(button);
        await t.pump();
        expect(retries, 1);
      },
    );

    testWidgets(
      'kontrol sırasında düğme pasif (mevcut davranış); çark pasif zeminde görünür',
      (t) async {
        var retries = 0;
        for (final dark in const <bool>[false, true]) {
          await _pumpPage(
            t,
            checking: true,
            onRetry: () async => retries++,
            dark: dark,
          );
          final button = find.widgetWithText(
            ElevatedButton,
            'Kontrol Ediliyor...',
          );
          expect(button, findsOneWidget);
          expect(t.widget<ElevatedButton>(button).onPressed, isNull);

          // Beyaz çark soluk (pasif) zeminde görünmez olurdu: palet rengi kullanılır.
          final palette = dark ? AppPalette.dark : AppPalette.light;
          final spinner = t.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          );
          expect(spinner.color, palette.textSecondary, reason: 'dark=$dark');
          expect(spinner.color, isNot(Colors.white));

          await t.tap(button, warnIfMissed: false);
          await t.pump();
        }
        expect(retries, 0);
      },
    );

    testWidgets(
      'tek AppCard(seviye 2); uyarı tonlu ikon karosu; başlık anlamsal başlık',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpPage(t, dark: dark);
          final palette = dark ? AppPalette.dark : AppPalette.light;
          expect(t.widget<AppCard>(find.byType(AppCard)).level, 2);

          final icon = t.widget<Icon>(find.byIcon(Icons.wifi_off_rounded));
          expect(
            icon.color,
            AppTone.warning.ink(palette),
            reason: 'dark=$dark',
          );
          expect(
            _contrast(
              icon.color!,
              Color.alphaBlend(AppTone.warning.tint(palette), palette.surface),
            ),
            greaterThanOrEqualTo(4.5),
            reason: 'ikon tint karosu üstünde',
          );
          // Ikon dekoratif: durum aşağıdaki başlıkta okunur.
          expect(
            find.ancestor(
              of: find.byIcon(Icons.wifi_off_rounded),
              matching: find.byType(ExcludeSemantics),
            ),
            findsWidgets,
          );
          final title = t.widget<Text>(find.text(_title));
          expect(
            title.style,
            Theme.of(t.element(find.text(_title))).textTheme.titleLarge,
          );
          expect(title.textAlign, TextAlign.center);
        }
      },
    );

    testWidgets(
      'açıklama metni her iki temada textSecondary (>= 4,5:1); koyuda textMuted DEĞİL',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpPage(t, dark: dark);
          final palette = dark ? AppPalette.dark : AppPalette.light;
          final message = t.widget<Text>(find.text(_message));
          expect(
            message.style!.color,
            palette.textSecondary,
            reason: 'dark=$dark',
          );
          expect(
            _contrast(message.style!.color!, palette.surfaceAt(2)),
            greaterThanOrEqualTo(4.5),
            reason: 'dark=$dark',
          );
          expect(message.textAlign, TextAlign.center);
        }
      },
    );

    testWidgets('Scaffold şeffaf (zemin kökte); pahalı efektler yok', (
      t,
    ) async {
      await _pumpPage(t);
      final scaffold = t.widget<Scaffold>(
        find.descendant(
          of: find.byType(NoInternetPage),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.backgroundColor, isNull);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('geniş ekranlarda kart en çok 520 dp (ortalı); taşma yok', (
      t,
    ) async {
      await _pumpPage(t, width: 820, height: 900);
      final card = t.getRect(find.byType(AppCard));
      expect(card.width, lessThanOrEqualTo(520));
      expect(card.center.dx, closeTo(410, 1));
      expect(t.takeException(), isNull);
    });

    testWidgets('kısa/yatay pencerede (640x240 x2,0) kaydırılır, taşma yok', (
      t,
    ) async {
      await _pumpPage(t, width: 640, height: 240, scale: 2.0);
      expect(find.text(_title), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('hareket azaltma: tek pump ile son durum, taşma yok', (
      t,
    ) async {
      await _pumpPage(t, width: 320, scale: 2.0, reduce: true);
      expect(find.text(_title), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
