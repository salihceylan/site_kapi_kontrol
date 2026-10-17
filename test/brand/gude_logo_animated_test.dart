// Işıklı Güde Teknoloji logosu (AnimatedGudeLogo / AnimatedGudeLeafMark) testleri.
//
// Zamanlama, ilerleme, hareket azaltma / `animate: false` / varsayılan anahtar, TickerMode ve Offstage'de durma,
// anlamsal etiket, piksel düzeyinde "ışık yalnız boyalı pikselde" doğrulaması ve taşma matrisi.
//
// Not: animasyonlu sınamalar `pumpAndSettle` KULLANMAZ (sonsuz animasyon); `tester.pump(Duration)` kullanır.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/brand/gude_logo.dart';
import 'package:site_kapi_kontrol/brand/gude_logo_animated.dart';
import 'package:site_kapi_kontrol/brand/logo_palette.dart';

import '../design/harness.dart';

Finder _glow() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is GudeLogoGlowPainter);
Finder _sweepLayer() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is GudeLogoSweepPainter);

GudeLogoGlowPainter _glowPainter(WidgetTester t) => t.widget<CustomPaint>(_glow().first).painter! as GudeLogoGlowPainter;
GudeLogoSweepPainter _sweepPainter(WidgetTester t) => t.widget<CustomPaint>(_sweepLayer().first).painter! as GudeLogoSweepPainter;

/// Tur ilerlemesi (0..1).
double _progress(WidgetTester t) => _glowPainter(t).progress.value;

/// Süpürme ilerlemesi (-1: süpürme yok).
double _sweep(WidgetTester t) => _sweepPainter(t).sweep.value;

/// İlk tık (geçen süre 0) alındıktan sonra tur başındayız.
Future<void> _start(WidgetTester t, Widget w, {bool dark = false, bool reduce = false}) async {
  await t.pumpWidget(const SizedBox.shrink()); // önceki sınamanın durumu (tema geçişi dahil) taşınmasın
  await t.pumpWidget(harnessApp(Center(child: w), dark: dark, reduce: reduce));
  await t.pump();
}

const Widget _logo = AnimatedGudeLogo(height: 120, animate: true);

Future<ByteData> _rgba(WidgetTester t, Widget painted, {Size size = const Size(400, 264)}) async {
  final key = GlobalKey();
  await t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: size, child: painted)),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = await t.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  return data!;
}

void main() {
  group('GudeLogoAnimation: zamanlama', () {
    const total = 7000.0;

    test('tur 7 sn; süpürme 0,9 sn\'de başlar, 1,6 sn sürer (açık aralık)', () {
      expect(GudeLogoAnimation.cycle, const Duration(seconds: 7));
      expect(GudeLogoAnimation.sweepDuration, const Duration(milliseconds: 1600));
      expect(GudeLogoAnimation.sweepProgress(0), -1);
      expect(GudeLogoAnimation.sweepProgress(900 / total), -1, reason: 'başlangıç sınırı: şerit henüz dışarıda');
      expect(GudeLogoAnimation.sweepProgress(2500 / total), -1, reason: 'bitiş sınırı');
      expect(GudeLogoAnimation.sweepProgress(1700 / total), closeTo(0.5, 1e-9));
      expect(GudeLogoAnimation.sweepProgress(1000 / total), closeTo(0.0625, 1e-9));
      expect(GudeLogoAnimation.sweepProgress(0.99), -1);
    });

    test('süpürme ilerlemesi pencerede tekdüze artar; dışında -1', () {
      var last = 0.0;
      for (var ms = 905; ms < 2500; ms += 5) {
        final p = GudeLogoAnimation.sweepProgress(ms / total);
        expect(p, inExclusiveRange(0, 1), reason: '$ms ms');
        expect(p, greaterThan(last));
        last = p;
      }
      for (var ms = 0; ms <= 900; ms += 50) {
        expect(GudeLogoAnimation.sweepProgress(ms / total), -1);
      }
      for (var ms = 2500; ms < 7000; ms += 100) {
        expect(GudeLogoAnimation.sweepProgress(ms / total), -1);
      }
    });

    test('nefes eğrisi 0..1, tur başında 0,5 ve tur sonunda aynı değer (dikişsiz döngü)', () {
      expect(GudeLogoAnimation.breath(0), closeTo(0.5, 1e-12));
      expect(GudeLogoAnimation.breath(1), closeTo(GudeLogoAnimation.breath(0), 1e-9));
      for (var i = 0; i <= 100; i++) {
        expect(GudeLogoAnimation.breath(i / 100), inInclusiveRange(0, 1));
      }
      expect(GudeLogoAnimation.breathsPerCycle, isA<int>());
    });

    test('parıltı: koyu zeminde açığa göre hep belirgin; ikisi de görünür', () {
      for (final b in const [0.0, 0.5, 1.0]) {
        expect(GudeLogoGlowPainter.intensity(b, dark: true), greaterThan(GudeLogoGlowPainter.intensity(b, dark: false)));
        expect(GudeLogoGlowPainter.intensity(b, dark: false), greaterThan(0.04));
      }
      expect(
        GudeLogoGlowPainter.intensity(1, dark: false),
        lessThan(GudeLogoGlowPainter.intensity(0, dark: true)),
        reason: 'açık temada en parlak an bile koyu temanın en sönüğünden sönük',
      );
      expect(GudeLogoGlowPainter.intensity(1, dark: true) * (1 + GudeLogoGlowPainter.sweepLift), lessThan(0.7), reason: 'kibar');
    });
  });

  group('AnimatedGudeLogo: boyut ve çizim', () {
    testWidgets('logo: yükseklik x aspect genişlik; yaprak işareti kare', (t) async {
      await _start(t, const Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedGudeLogo(height: 100, animate: false),
        AnimatedGudeLeafMark(size: 52, animate: false),
      ]));
      expect(t.getSize(find.byType(AnimatedGudeLogo)), Size(100 * GudeLogo.aspect, 100));
      expect(t.getSize(find.byType(AnimatedGudeLeafMark)), const Size(52, 52));
    });

    testWidgets('açık ve koyu temada logo ve yaprak işareti, süpürme dahil, hata vermeden çizilir', (t) async {
      for (final dark in const [false, true]) {
        await _start(
          t,
          const Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedGudeLogo(height: 120, animate: true),
            AnimatedGudeLeafMark(size: 64, animate: true),
          ]),
          dark: dark,
        );
        for (final ms in const [100, 700, 600, 400, 500, 1500, 3000]) {
          await t.pump(Duration(milliseconds: ms));
          expect(t.takeException(), isNull, reason: 'dark=$dark +$ms ms');
        }
        expect(_glow(), findsNWidgets(2));
        expect(_sweepLayer(), findsNWidgets(2));
      }
    });

    testWidgets('açık/koyu palet seçimi: tema parlaklığına göre; açıkça verilen palet ve darkBackground önceliklidir', (t) async {
      await _start(t, const AnimatedGudeLogo(height: 80, animate: false), dark: true);
      expect(_glowPainter(t).dark, isTrue);
      expect((_sweepPainter(t).art as GudeLogoPainter).palette, LogoPalette.dark);
      await _start(t, const AnimatedGudeLogo(height: 80, animate: false));
      expect(_glowPainter(t).dark, isFalse);
      expect((_sweepPainter(t).art as GudeLogoPainter).palette, LogoPalette.light);
      await _start(t, const AnimatedGudeLogo(height: 80, animate: false, palette: LogoPalette.dark));
      expect(_glowPainter(t).dark, isTrue, reason: 'palet açıkça koyu');
      await _start(t, const AnimatedGudeLeafMark(size: 52, animate: false, darkBackground: false), dark: true);
      expect(_glowPainter(t).dark, isFalse, reason: 'beyaz plaka üstünde koyu tema olsa da açık zemin şiddeti');
    });
  });

  group('AnimatedGudeLogo: animasyon ilerler (tek denetleyici, setState yok)', () {
    testWidgets('tur ilerler; süpürme 0,9-2,5 sn arasında; 7 sn\'de başa sarar ve tekrarlar', (t) async {
      await _start(t, _logo);
      expect(_progress(t), 0);
      expect(_sweep(t), -1);
      final glowBefore = _glowPainter(t);
      final sweepBefore = _sweepPainter(t);

      await t.pump(const Duration(milliseconds: 500));
      expect(_progress(t), closeTo(500 / 7000, 0.003));
      expect(_sweep(t), -1, reason: '0,5 sn: süpürme henüz başlamadı');

      await t.pump(const Duration(milliseconds: 1200)); // 1,7 sn
      expect(_progress(t), closeTo(1700 / 7000, 0.003));
      expect(_sweep(t), closeTo(0.5, 0.02), reason: 'süpürme ortası');

      await t.pump(const Duration(milliseconds: 1000)); // 2,7 sn
      expect(_sweep(t), -1, reason: 'süpürme bitti, geri kalan sürede durağan');

      await t.pump(const Duration(milliseconds: 4300)); // 7,0 sn
      final wrapped = _progress(t);
      expect(wrapped < 0.02 || wrapped > 0.98, isTrue, reason: 'tur sonu: başa sarıldı ($wrapped)');

      await t.pump(const Duration(milliseconds: 1700)); // 8,7 sn
      expect(_sweep(t), closeTo(0.5, 0.03), reason: 'ikinci turun süpürmesi');

      // Kare başına yeniden kurulum yok: painter nesneleri aynı kaldı (yalnız repaint: dinleyicileri çalıştı).
      expect(identical(_glowPainter(t), glowBefore), isTrue);
      expect(identical(_sweepPainter(t), sweepBefore), isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('süpürme yokken logo katmanı yeniden çizilmez (sweep bildirimi yalnız süpürmede ve bitişte)', (t) async {
      await _start(t, _logo);
      var notifications = 0;
      _sweepPainter(t).sweep.addListener(() => notifications++);
      // 0 - 0,9 sn: süpürme yok -> bildirim yok.
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(notifications, 0, reason: 'süpürme dışında logo katmanı boşa çizilmez');
      // Süpürme penceresi: bildirimler başlar.
      for (var i = 0; i < 18; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(notifications, greaterThan(10));
      final during = notifications;
      // Süpürme bitti (sweep -1'e döndü); sonrasında yine bildirim yok.
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_sweep(t), -1);
      expect(notifications - during, lessThanOrEqualTo(1), reason: 'yalnız bitişteki -1 bildirimi');
    });

    testWidgets('animasyon açıkken ticker çalışır', (t) async {
      await _start(t, _logo);
      expect(t.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('widget ağaçtan kalkınca ticker kalmaz (sızıntı yok)', (t) async {
      await _start(t, _logo);
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpWidget(const SizedBox.shrink());
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
    });
  });

  group('AnimatedGudeLogo: durağan modlar', () {
    Future<void> expectStatic(WidgetTester t) async {
      expect(t.binding.transientCallbackCount, 0, reason: 'ticker yok');
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 1700));
      expect(_progress(t), 0, reason: 'tur ilerlemez');
      expect(_sweep(t), -1, reason: 'süpürme yok');
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
    }

    testWidgets('animate: false', (t) async {
      await _start(t, const AnimatedGudeLogo(height: 120, animate: false));
      await expectStatic(t);
    });

    testWidgets('varsayılan (testlerde anahtar kapalı: flutter_test_config.dart)', (t) async {
      expect(GudeLogoAnimation.enabledByDefault, isFalse);
      await _start(t, const AnimatedGudeLogo(height: 120));
      await expectStatic(t);
      await _start(t, const AnimatedGudeLeafMark(size: 52));
      await expectStatic(t);
    });

    testWidgets('varsayılan anahtar açılınca (animate verilmedi) animasyon çalışır', (t) async {
      GudeLogoAnimation.enabledByDefault = true;
      addTearDown(() => GudeLogoAnimation.enabledByDefault = false);
      await _start(t, const AnimatedGudeLogo(height: 120));
      await t.pump(const Duration(milliseconds: 1700));
      expect(_progress(t), closeTo(1700 / 7000, 0.003));
      expect(_sweep(t), closeTo(0.5, 0.02));
    });

    testWidgets('hareket azaltma (MediaQuery.disableAnimations) animate: true olsa bile TAMAMEN durağan', (t) async {
      await _start(t, _logo, reduce: true);
      await expectStatic(t);
    });

    testWidgets('hareket azaltma çalışma anında açılıp kapanınca durur / yeniden başlar', (t) async {
      await _start(t, _logo);
      await t.pump(const Duration(milliseconds: 1700));
      expect(_sweep(t), closeTo(0.5, 0.02));

      await t.pumpWidget(harnessApp(const Center(child: _logo), reduce: true));
      await t.pump();
      expect(t.binding.transientCallbackCount, 0, reason: 'azaltma açıldı: ticker durdu');
      expect(_progress(t), 0, reason: 'durağan hâl: tur başı');
      expect(_sweep(t), -1);

      await t.pumpWidget(harnessApp(const Center(child: _logo)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1700));
      expect(_sweep(t), closeTo(0.5, 0.02), reason: 'azaltma kapandı: yeniden animasyonlu');
    });

    testWidgets('pumpAndSettle (varsayılan kapalı) biter', (t) async {
      await t.pumpWidget(harnessApp(const Center(child: AnimatedGudeLogo(height: 120))));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });
  });

  group('AnimatedGudeLogo: görünmezken durur', () {
    testWidgets('TickerMode kapalı: ilerlemez, ticker kareleri zamanlamaz; açılınca sürer', (t) async {
      Widget app({required bool enabled}) => harnessApp(Center(child: TickerMode(enabled: enabled, child: _logo)));
      await t.pumpWidget(app(enabled: false));
      await t.pump();
      await t.pump(const Duration(milliseconds: 2000));
      expect(_progress(t), 0);
      expect(t.binding.transientCallbackCount, 0, reason: 'sessize alınmış ticker kare zamanlamaz');

      // Sessize alınmış ticker zamanı saymaya devam eder: açılınca denetleyici gerçek geçen süreye atlar.
      await t.pumpWidget(app(enabled: true));
      await t.pump();
      final resumed = _progress(t);
      expect(t.binding.transientCallbackCount, greaterThan(0));
      await t.pump(const Duration(milliseconds: 500));
      final delta = (_progress(t) - resumed) * 7000;
      expect(delta, closeTo(500, 25), reason: 'açılınca normal hızda ilerler');
    });

    testWidgets('Offstage: birkaç kare sonra ticker durur; görünür olunca yeniden başlar', (t) async {
      Widget app({required bool offstage}) => harnessApp(Center(child: Offstage(offstage: offstage, child: _logo)));
      await t.pumpWidget(app(offstage: true));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.binding.transientCallbackCount, 0, reason: 'görünmeyen logo kare zamanlamaz');

      await t.pumpWidget(app(offstage: false));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.binding.transientCallbackCount, greaterThan(0), reason: 'yeniden görünür: sürüyor');
      final before = _progress(t);
      await t.pump(const Duration(milliseconds: 1000));
      expect(_progress(t), greaterThan(before));
    });

    testWidgets('saydamlık 0 (çizim atlanır): durur; saydamlaşınca sürer', (t) async {
      Widget app(double opacity) => harnessApp(Center(child: Opacity(opacity: opacity, child: _logo)));
      await t.pumpWidget(app(0));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(app(1));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.binding.transientCallbackCount, greaterThan(0));
    });
  });

  group('AnimatedGudeLogo: Semantics', () {
    testWidgets('varsayılan etiket "Güde Teknoloji" (resim); etiket null ise anlamsal ağaçta yok', (t) async {
      final handle = t.ensureSemantics();
      await _start(
        t,
        const Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedGudeLogo(height: 80, animate: false),
          AnimatedGudeLeafMark(size: 40, animate: false),
          AnimatedGudeLogo(height: 80, animate: false, semanticLabel: null),
          AnimatedGudeLeafMark(size: 40, animate: false, semanticLabel: null),
        ]),
      );
      expect(GudeLogoAnimation.label, 'Güde Teknoloji');
      expect(find.bySemanticsLabel('Güde Teknoloji'), findsNWidgets(2));
      expect(t.getSemantics(find.bySemanticsLabel('Güde Teknoloji').first), isSemantics(label: 'Güde Teknoloji', isImage: true));
      final labelled = t.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.getSemanticsData().label)
          .where((l) => l.isNotEmpty)
          .toList();
      expect(labelled, ['Güde Teknoloji', 'Güde Teknoloji'], reason: 'etiketsiz iki logo dekoratif');
      handle.dispose();
    });

    testWidgets('animasyon açıkken de etiket aynı kalır', (t) async {
      final handle = t.ensureSemantics();
      await _start(t, _logo);
      await t.pump(const Duration(milliseconds: 1700));
      expect(find.bySemanticsLabel('Güde Teknoloji'), findsOneWidget);
      handle.dispose();
    });
  });

  group('GudeLogoSweepPainter / GudeLogoGlowPainter', () {
    testWidgets('süpürme yokken saveLayer açılmaz; süpürmede açılır', (t) async {
      for (final p in const [-1.0, 0.5]) {
        await t.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 200,
              height: 132,
              child: CustomPaint(
                painter: GudeLogoSweepPainter(art: GudeLogoPainter(LogoPalette.dark), sweep: ValueNotifier<double>(p), dark: true),
              ),
            ),
          ),
        );
        final matcher = paints..something((method, arguments) => method == #saveLayer);
        if (p < 0) {
          expect(t.renderObject(find.byType(CustomPaint).last), isNot(matcher));
        } else {
          expect(t.renderObject(find.byType(CustomPaint).last), matcher);
        }
      }
    });

    test('shouldRepaint: aynı girdilerde false; palet / zemin / dinleyici değişince true', () {
      final sweep = ValueNotifier<double>(-1);
      final base = GudeLogoSweepPainter(art: GudeLogoPainter(LogoPalette.dark), sweep: sweep, dark: true);
      expect(GudeLogoSweepPainter(art: GudeLogoPainter(LogoPalette.dark), sweep: sweep, dark: true).shouldRepaint(base), isFalse);
      expect(GudeLogoSweepPainter(art: GudeLogoPainter(LogoPalette.light), sweep: sweep, dark: true).shouldRepaint(base), isTrue);
      expect(GudeLogoSweepPainter(art: GudeLogoPainter(LogoPalette.dark), sweep: sweep, dark: false).shouldRepaint(base), isTrue);
      expect(GudeLogoSweepPainter(art: GudeLogoPainter(LogoPalette.dark), sweep: ValueNotifier<double>(-1), dark: true).shouldRepaint(base), isTrue);
      expect(GudeLogoSweepPainter(art: const GudeLeafMarkPainter(), sweep: sweep, dark: true).shouldRepaint(base), isTrue, reason: 'farklı çizici türü');

      final glow = GudeLogoGlowPainter(progress: const AlwaysStoppedAnimation<double>(0), region: Rect.largest, dark: true);
      expect(GudeLogoGlowPainter(progress: glow.progress, region: Rect.largest, dark: true).shouldRepaint(glow), isFalse);
      expect(GudeLogoGlowPainter(progress: glow.progress, region: Rect.largest, dark: false).shouldRepaint(glow), isTrue);
    });

    testWidgets('PİKSEL: ışık yalnız boyalı pikselde; şeffaf pikseller şeffaf kalır, kenarlar kalınlaşmaz, şerit görünür', (t) async {
      for (final pal in const [LogoPalette.dark, LogoPalette.light]) {
        final dark = pal == LogoPalette.dark;
        Widget layer(double p) => CustomPaint(
              painter: GudeLogoSweepPainter(art: GudeLogoPainter(pal), sweep: ValueNotifier<double>(p), dark: dark),
            );
        final plain = await _rgba(t, layer(-1));
        final swept = await _rgba(t, layer(0.5));
        expect(plain.lengthInBytes, swept.lengthInBytes);

        var painted = 0;
        var changed = 0;
        var maxAlphaDiff = 0;
        for (var i = 0; i < plain.lengthInBytes; i += 4) {
          final a0 = plain.getUint8(i + 3);
          final a1 = swept.getUint8(i + 3);
          if (a0 == 0) {
            expect(a1, 0, reason: 'şeffaf piksel ($i) ışıkla boyanmamalı');
          } else {
            painted++;
          }
          maxAlphaDiff = a1 - a0 > maxAlphaDiff ? a1 - a0 : (a0 - a1 > maxAlphaDiff ? a0 - a1 : maxAlphaDiff);
          final dr = (swept.getUint8(i) - plain.getUint8(i)).abs();
          final dg = (swept.getUint8(i + 1) - plain.getUint8(i + 1)).abs();
          final db = (swept.getUint8(i + 2) - plain.getUint8(i + 2)).abs();
          if (dr + dg + db > 24) changed++;
        }
        expect(painted, greaterThan(2000), reason: 'logo çizildi (dark=$dark)');
        expect(maxAlphaDiff, lessThanOrEqualTo(2), reason: 'alfa değişmez: kenar kalınlaşması yok (dark=$dark)');
        expect(changed, greaterThan(300), reason: 'şerit boyalı piksellerde görünür (dark=$dark)');
        expect(changed, lessThan(painted), reason: 'şerit logonun yalnız bir kısmını aydınlatır (dark=$dark)');
      }
    });

    testWidgets('PİKSEL: parıltı koyu temada açık temadan belirgin; alan dışına taşmaz', (t) async {
      Widget glow(bool dark) => CustomPaint(
            painter: GudeLogoGlowPainter(
              progress: const AlwaysStoppedAnimation<double>(0),
              region: const Rect.fromLTRB(0.18, 0.02, 0.87, 0.6),
              dark: dark,
            ),
          );
      const size = Size(400, 264);
      final dk = await _rgba(t, glow(true), size: size);
      final lt = await _rgba(t, glow(false), size: size);
      int alphaAt(ByteData d, int x, int y) => d.getUint8((y * 400 + x) * 4 + 3);
      // Merkez: koyuda belirgin, açıkta sönük ama görünür.
      final centerDark = alphaAt(dk, 210, 80);
      final centerLight = alphaAt(lt, 210, 80);
      expect(centerDark, greaterThan(centerLight));
      expect(centerLight, greaterThan(8));
      expect(centerDark, lessThan(180), reason: 'kibar: opak değil');
      // Köşeler boş (parıltı alan içinde söner).
      for (final (x, y) in const [(0, 0), (399, 0), (0, 263), (399, 263), (200, 263)]) {
        expect(alphaAt(dk, x, y), 0, reason: '($x,$y)');
      }
    });
  });

  group('AnimatedGudeLogo: taşma matrisi', () {
    testWidgets('logo ve yaprak işareti sabit boyutlu; 320x640@2,0 / 360x640@1,5 / 640x360@2,0 / tablet x açık+koyu: taşma yok', (t) async {
      const cells = <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (640, 360, 2.0), (820, 1180, 1.0), (412, 915, 2.0)];
      for (final (w, h, s) in cells) {
        for (final dark in const [false, true]) {
          await pumpAt(
            t,
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedGudeLogo(height: 100, animate: true),
                SizedBox(height: 8),
                AnimatedGudeLeafMark(size: 52, padding: 0.1, animate: true),
              ],
            ),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(t.getSize(find.byType(AnimatedGudeLogo)).width, closeTo(100 * GudeLogo.aspect, 0.01));
          await t.pump(const Duration(milliseconds: 1250)); // süpürmenin içinde
          expect(t.takeException(), isNull, reason: '${w}x$h @$s dark=$dark');
        }
      }
    });
  });
}
