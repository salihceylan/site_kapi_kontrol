// FAZ 5 / A1b-(ii): CountdownRing ve CountdownSeconds widget testleri.
//
// Halka: renk geçişi ve >= 3:1 kontrast (açık/koyu yüzey), CustomPainter çağrıları (iz + yay: açı, renk,
// kalınlık), gerçek piksel doğrulaması, `child`'ın yalnız bir kez kurulması ve halkayla yeniden
// BOYANMAMASI, orantılı küçülme (taşma yok), anlamsal içeriğin korunması, hareket azaltmada halkanın
// işlevsel olarak sürmesi, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu).
// Kalan saniye: yukarı yuvarlama (kayan nokta güvenli), yalnız rakam değişince yeniden kurulma,
// abonelik yönetimi (animasyon değişimi/dispose), canlı bölge OLMAMASI.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/countdown_ring.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

/// WidgetTester bir TickerProvider'dır: gerçek zamanlı değil, sahte zamanla ilerleyen denetleyici.
AnimationController _controller(
  WidgetTester t, {
  double value = 1.0,
  int seconds = 30,
}) {
  final c = AnimationController(
    vsync: t,
    value: value,
    duration: Duration(seconds: seconds),
  );
  addTearDown(c.dispose);
  return c;
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Halkanın kendi `RenderCustomPaint` nesnesi (çocuk CustomPaint içermeyen testlerde).
RenderObject _ring(WidgetTester t) => t.renderObject(
  find
      .descendant(
        of: find.byType(CountdownRing),
        matching: find.byType(CustomPaint),
      )
      .first,
);

const Widget _qr = SizedBox(width: 184, height: 184);

Widget _ringWidget(
  Animation<double> progress, {
  Widget child = _qr,
  Color? colorOverride,
  double size = 268,
  double stroke = 8,
}) => CountdownRing(
  progress: progress,
  colorOverride: colorOverride,
  size: size,
  stroke: stroke,
  child: child,
);

/// Sayaç painter'ı: `paint` kaç kez çağrıldı.
class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  group('CountdownRing.colorFor', () {
    test(
      'uç renkler: 1,0 yeşil • 0,4 amber • 0,0 kırmızı (spesifikasyon D6 değerleri)',
      () {
        expect(CountdownRing.goodColor, const Color(0xFF059669));
        expect(CountdownRing.warnColor, const Color(0xFFD97706));
        expect(CountdownRing.lowColor, const Color(0xFFDC2626));
        expect(CountdownRing.colorFor(1.0), CountdownRing.goodColor);
        expect(CountdownRing.colorFor(0.4), CountdownRing.warnColor);
        expect(CountdownRing.colorFor(0.0), CountdownRing.lowColor);
        expect(CountdownRing.successColor, CountdownRing.goodColor);
      },
    );

    test(
      'ara değerler doğrusal geçiş: 0,7 = yeşil/amber ortası... (0,4-1,0 diliminde)',
      () {
        // (0,7 - 0,4) / 0,6 kayan noktada 0,4999...: aynı ifadeyle karşılaştırılır.
        expect(
          CountdownRing.colorFor(0.7),
          Color.lerp(
            CountdownRing.warnColor,
            CountdownRing.goodColor,
            (0.7 - 0.4) / 0.6,
          ),
        );
        expect(
          CountdownRing.colorFor(0.2),
          Color.lerp(
            CountdownRing.lowColor,
            CountdownRing.warnColor,
            0.2 / 0.4,
          ),
        );
        // Süreklilik: 0,4 çevresinde sıçrama yok.
        final below = CountdownRing.colorFor(0.4 - 1e-6);
        final above = CountdownRing.colorFor(0.4 + 1e-6);
        expect((below.r - above.r).abs(), lessThan(1e-3));
        expect((below.g - above.g).abs(), lessThan(1e-3));
        expect((below.b - above.b).abs(), lessThan(1e-3));
      },
    );

    test('aralık dışı ve NaN değerler kenara sıkıştırılır', () {
      expect(CountdownRing.colorFor(-3), CountdownRing.lowColor);
      expect(CountdownRing.colorFor(7), CountdownRing.goodColor);
      expect(CountdownRing.colorFor(double.nan), CountdownRing.lowColor);
      expect(CountdownRing.colorFor(double.infinity), CountdownRing.goodColor);
    });

    test('tüm geçiş boyunca halka rengi açık ve koyu yüzeyde >= 3:1', () {
      // QR modalı Dialog zeminleri: açık = beyaz, koyu = #0F172A (= koyu surfaceMuted); A0 testi
      // palet `surface`'lerini doğrular. Amber, açık gri `surfaceMuted` (#F1F5F9) üstünde 2,9:1'e
      // iner: halka beyaz/`surface` üzerinde kullanılmalıdır (dartdoc'ta belirtilir).
      final surfaces = <String, Color>{
        'beyaz': Colors.white,
        'açık surface': AppPalette.light.surface,
        'koyu surface': AppPalette.dark.surface,
        'koyu surfaceMuted (modal zemini)': AppPalette.dark.surfaceMuted,
      };
      var worst = double.infinity;
      for (var i = 0; i <= 200; i++) {
        final color = CountdownRing.colorFor(i / 200);
        for (final entry in surfaces.entries) {
          final ratio = _contrast(color, entry.value);
          worst = math.min(worst, ratio);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                'ilerleme ${i / 200} / ${entry.key}: ${ratio.toStringAsFixed(2)}',
          );
        }
      }
      expect(worst, greaterThanOrEqualTo(3.0));
    });

    test('başarı/uyarı/ret sabitleri de >= 3:1', () {
      for (final color in [
        CountdownRing.successColor,
        CountdownRing.warnColor,
        CountdownRing.lowColor,
      ]) {
        for (final surface in [
          AppPalette.light.surface,
          AppPalette.dark.surface,
        ]) {
          expect(_contrast(color, surface), greaterThanOrEqualTo(3.0));
        }
      }
    });

    test(
      'başarı tiki ayarları: 320 ms easeOutBack (eski 700 ms elasticOut kısaldı)',
      () {
        expect(
          CountdownRing.successTickDuration,
          const Duration(milliseconds: 320),
        );
        expect(CountdownRing.successTickCurve, Curves.easeOutBack);
      },
    );
  });

  group('CountdownRing: boyama', () {
    testWidgets(
      'ilerleme 0,5: iz (soluk tam halka) + 12 yönünden saat yönünde yarım yay',
      (t) async {
        final c = _controller(t, value: 0.5);
        await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
        final color = CountdownRing.colorFor(0.5);
        expect(t.getSize(find.byType(CountdownRing)), const Size(268, 268));
        expect(
          _ring(t),
          paints
            ..circle(
              x: 134,
              y: 134,
              radius: 130,
              color: color.withValues(alpha: 0.14),
              style: PaintingStyle.stroke,
              strokeWidth: 8,
            )
            ..arc(
              rect: const Rect.fromLTWH(4, 4, 260, 260),
              startAngle: -math.pi / 2,
              sweepAngle: math.pi,
              useCenter: false,
              color: color,
              strokeWidth: 8,
              style: PaintingStyle.stroke,
              strokeCap: StrokeCap.round,
            ),
        );
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'ilerleme 1,0: tam yay (2 pi) yeşil; ilerleme 0: yay YOK, yalnız soluk iz',
      (t) async {
        final c = _controller(t, value: 1.0);
        await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
        expect(
          _ring(t),
          paints..arc(
            startAngle: -math.pi / 2,
            sweepAngle: 2 * math.pi,
            color: CountdownRing.goodColor,
          ),
        );
        c.value = 0.0;
        await t.pump();
        expect(
          _ring(t),
          paints..circle(color: CountdownRing.lowColor.withValues(alpha: 0.14)),
        );
        expect(
          _ring(t),
          isNot(paints..arc()),
          reason: 'boş halkada yay çizilmez',
        );
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'ilerleme değişince halka yeniden boyanır (renk ve açı güncellenir)',
      (t) async {
        final c = _controller(t, value: 1.0);
        await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
        for (final v in [0.8, 0.45, 0.4, 0.3, 0.1]) {
          c.value = v;
          await t.pump();
          expect(
            _ring(t),
            paints..arc(
              startAngle: -math.pi / 2,
              sweepAngle: 2 * math.pi * v,
              color: CountdownRing.colorFor(v),
            ),
            reason: 'ilerleme $v',
          );
        }
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('geri sayım animasyonu: yay kısalır, halka kare/dairesel kalır', (
      t,
    ) async {
      final c = _controller(t, seconds: 30);
      await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
      c.reverse(from: 1);
      await t.pump();
      await t.pump(const Duration(seconds: 15));
      expect(c.value, closeTo(0.5, 1e-9));
      expect(
        _ring(t),
        paints..arc(sweepAngle: math.pi, color: CountdownRing.colorFor(0.5)),
      );
      await t.pump(const Duration(seconds: 15));
      expect(c.value, 0.0);
      expect(_ring(t), isNot(paints..arc()));
      // Süre tam dolduğu karede benzetim "bitti" sayılmaz (isDone: t > süre): ticker'ı kapat.
      c.stop();
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('colorOverride: iz ve yay sabit renkte, ilerlemeden bağımsız', (
      t,
    ) async {
      final c = _controller(t, value: 0.2);
      await t.pumpWidget(
        harnessApp(
          Center(
            child: _ringWidget(c, colorOverride: CountdownRing.successColor),
          ),
        ),
      );
      expect(
        _ring(t),
        paints
          ..circle(color: CountdownRing.successColor.withValues(alpha: 0.14))
          ..arc(
            sweepAngle: 2 * math.pi * 0.2,
            color: CountdownRing.successColor,
          ),
      );
      c.value = 0.9;
      await t.pump();
      expect(
        _ring(t),
        paints..arc(
          sweepAngle: 2 * math.pi * 0.9,
          color: CountdownRing.successColor,
        ),
      );
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('colorOverride değişince yeniden boyanır', (t) async {
      final c = _controller(t, value: 0.5);
      Widget build(Color? override) =>
          harnessApp(Center(child: _ringWidget(c, colorOverride: override)));
      await t.pumpWidget(build(null));
      await t.pumpWidget(build(CountdownRing.warnColor));
      expect(_ring(t), paints..arc(color: CountdownRing.warnColor));
      await t.pumpWidget(build(null));
      expect(_ring(t), paints..arc(color: CountdownRing.colorFor(0.5)));
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('size ve stroke parametreleri geometriye uygulanır', (t) async {
      final c = _controller(t, value: 0.25);
      await t.pumpWidget(
        harnessApp(Center(child: _ringWidget(c, size: 100, stroke: 4))),
      );
      expect(t.getSize(find.byType(CountdownRing)), const Size(100, 100));
      expect(
        _ring(t),
        paints
          ..circle(x: 50, y: 50, radius: 48, strokeWidth: 4)
          ..arc(
            rect: const Rect.fromLTWH(2, 2, 96, 96),
            sweepAngle: 2 * math.pi * 0.25,
            strokeWidth: 4,
          ),
      );
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'sınır değerler: ilerleme 1,0 üstü/0 altı güvenle sıkıştırılır',
      (t) async {
        final c = AnimationController.unbounded(vsync: t, value: 1.7);
        addTearDown(c.dispose);
        await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
        expect(
          _ring(t),
          paints..arc(sweepAngle: 2 * math.pi, color: CountdownRing.goodColor),
        );
        c.value = -0.5;
        await t.pump();
        expect(_ring(t), isNot(paints..arc()));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'sabit animasyonlar: kAlwaysComplete tam halka, kAlwaysDismissed boş halka',
      (t) async {
        await t.pumpWidget(
          harnessApp(Center(child: _ringWidget(kAlwaysCompleteAnimation))),
        );
        expect(
          _ring(t),
          paints..arc(sweepAngle: 2 * math.pi, color: CountdownRing.goodColor),
        );
        await t.pumpWidget(
          harnessApp(Center(child: _ringWidget(kAlwaysDismissedAnimation))),
        );
        expect(_ring(t), isNot(paints..arc()));
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'GERÇEK PİKSEL: yay 12 yönünden saat yönünde, kalan kısım yalnız soluk iz',
      (t) async {
        final c = _controller(t, value: 0.5);
        final key = GlobalKey();
        await t.pumpWidget(
          harnessApp(
            Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.white,
                  child: _ringWidget(c, child: const SizedBox.shrink()),
                ),
              ),
            ),
          ),
        );
        final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
        final data = await t.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData();
          image.dispose();
          return bytes;
        });
        expect(data, isNotNull);
        Color pixel(int x, int y) {
          final i = (y * 268 + x) * 4;
          return Color.fromARGB(
            data!.getUint8(i + 3),
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          );
        }

        final solid = CountdownRing.colorFor(0.5);
        final faint = Color.alphaBlend(
          solid.withValues(alpha: 0.14),
          Colors.white,
        );
        void expectNear(Color actual, Color expected, String where) {
          expect(
            (actual.r - expected.r).abs() * 255,
            lessThan(3),
            reason: where,
          );
          expect(
            (actual.g - expected.g).abs() * 255,
            lessThan(3),
            reason: where,
          );
          expect(
            (actual.b - expected.b).abs() * 255,
            lessThan(3),
            reason: where,
          );
        }

        // Halka yarıçapı 130 (kalınlık 8): merkez (134,134).
        expectNear(pixel(264, 134), solid, '3 yönü (yay üstünde)');
        expectNear(pixel(134, 264), solid, '6 yönü (yayın ucu)');
        expectNear(pixel(4, 134), faint, '9 yönü (yalnız iz)');
        expectNear(pixel(134, 4), solid, '12 yönü (yayın başı)');
        expectNear(pixel(134, 134), Colors.white, 'merkez boş');
        expectNear(pixel(70, 40), Colors.white, 'iç alan boş');
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('CountdownRing: child ve yeniden boyama yalıtımı', () {
    testWidgets('child bir kez kurulur; geri sayım sürerken yeniden KURULMAZ', (
      t,
    ) async {
      final c = _controller(t, seconds: 30);
      var builds = 0;
      await t.pumpWidget(
        harnessApp(
          Center(
            child: _ringWidget(
              c,
              child: Builder(
                builder: (context) {
                  builds++;
                  return _qr;
                },
              ),
            ),
          ),
        ),
      );
      expect(builds, 1);
      c.reverse(from: 1);
      await t.pump(); // ticker'ın başlangıç karesi
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(c.value, 0.0);
      c.stop();
      expect(
        builds,
        1,
        reason: '30 sn x 30 kare boyunca child yeniden kurulmadı',
      );
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'child halkanın katmanı DIŞINDA: halka yeniden boyanırken child boyanmaz',
      (t) async {
        final c = _controller(t, seconds: 30);
        final counter = _CountingPainter();
        await t.pumpWidget(
          harnessApp(
            Center(
              child: _ringWidget(
                c,
                child: CustomPaint(
                  size: const Size(184, 184),
                  painter: counter,
                ),
              ),
            ),
          ),
        );
        final initial = counter.paints;
        expect(initial, greaterThanOrEqualTo(1), reason: 'ilk karede boyandı');
        c.reverse(from: 1);
        await t.pump();
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(c.value, lessThan(0.95), reason: 'animasyon gerçekten ilerledi');
        // Halka her karede boyandı (yay kısaldı)...
        expect(_ring(t), paints..arc(sweepAngle: 2 * math.pi * c.value));
        // ...ama QR çocuğu (ayrı katmanın dışında) yeniden boyanmadı.
        expect(
          counter.paints,
          initial,
          reason: 'child her karede yeniden BOYANMAMALI',
        );
        c.stop();
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'halka RepaintBoundary içinde ve child ortada, doğal boyutunda',
      (t) async {
        final c = _controller(t, value: 0.5);
        await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
        expect(
          find.descendant(
            of: find.byType(CountdownRing),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
        );
        final ring = t.getRect(find.byType(CountdownRing));
        final child = t.getRect(find.byType(SizedBox).last);
        expect(ring.size, const Size(268, 268));
        expect(child.size, const Size(184, 184));
        expect(child.center, ring.center);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'anlamsal içerik korunur; halka kendi anlamsal düğümünü EKLEMEZ',
      (t) async {
        final handle = t.ensureSemantics();
        final c = _controller(t, value: 0.5);
        await t.pumpWidget(
          harnessApp(
            Center(child: _ringWidget(c, child: const Text('Kapı Açıldı!'))),
          ),
        );
        expect(find.bySemanticsLabel('Kapı Açıldı!'), findsOneWidget);
        final nodes = t.semantics
            .simulatedAccessibilityTraversal()
            .where((n) => n.getSemanticsData().label.isNotEmpty)
            .length;
        expect(nodes, 1, reason: 'yalnız child\'ın metni okunur');
        await t.pumpWidget(const SizedBox.shrink());
        handle.dispose();
      },
    );

    testWidgets(
      'dispose: animasyon sürerken ağaç sökülürse ve sonra değer değişirse hata yok',
      (t) async {
        final c = _controller(t, seconds: 30);
        await t.pumpWidget(harnessApp(Center(child: _ringWidget(c))));
        c.reverse(from: 1);
        await t.pump(const Duration(seconds: 3));
        await t.pumpWidget(const SizedBox.shrink());
        c.value = 0.3;
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('animasyon nesnesi değişince yeni animasyona bağlanır', (
      t,
    ) async {
      final a = _controller(t, value: 0.9);
      final b = _controller(t, value: 0.2);
      await t.pumpWidget(harnessApp(Center(child: _ringWidget(a))));
      expect(_ring(t), paints..arc(sweepAngle: 2 * math.pi * 0.9));
      await t.pumpWidget(harnessApp(Center(child: _ringWidget(b))));
      expect(_ring(t), paints..arc(sweepAngle: 2 * math.pi * 0.2));
      a.value = 0.5; // eski animasyon artık etkilemez
      await t.pump();
      expect(_ring(t), paints..arc(sweepAngle: 2 * math.pi * 0.2));
      b.value = 0.6;
      await t.pump();
      expect(_ring(t), paints..arc(sweepAngle: 2 * math.pi * 0.6));
      await t.pumpWidget(const SizedBox.shrink());
    });
  });

  group('CountdownRing: hareket azaltma ve ticker', () {
    testWidgets(
      'hareket azaltma açıkken halka ilerlemesi İŞLEVSEL olarak sürer',
      (t) async {
        final c = _controller(t, seconds: 30);
        await t.pumpWidget(
          harnessApp(Center(child: _ringWidget(c)), reduce: true),
        );
        c.reverse(from: 1);
        await t.pump();
        await t.pump(const Duration(seconds: 10));
        expect(c.value, closeTo(1 - 10 / 30, 1e-9));
        expect(
          _ring(t),
          paints..arc(
            sweepAngle: 2 * math.pi * c.value,
            color: CountdownRing.colorFor(c.value),
          ),
        );
        c.stop();
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'halkanın kendi ticker\'ı yok: durağan ilerlemede pumpAndSettle hemen biter',
      (t) async {
        for (final reduce in [false, true]) {
          final c = _controller(t, value: 0.6);
          await t.pumpWidget(
            harnessApp(Center(child: _ringWidget(c)), reduce: reduce),
          );
          await t.pumpAndSettle();
          expect(t.binding.transientCallbackCount, 0, reason: 'reduce=$reduce');
          await t.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  });

  group('CountdownRing: taşma', () {
    testWidgets(
      'üst öğe 268 dp\'den dar bırakırsa halka + child ORANTILI küçülür (daire kalır)',
      (t) async {
        final c = _controller(t, value: 0.5);
        await t.pumpWidget(
          harnessApp(
            Center(child: SizedBox(width: 200, child: _ringWidget(c))),
          ),
        );
        expect(t.getSize(find.byType(CountdownRing)), const Size(200, 200));
        expect(t.takeException(), isNull);
        // Çocuk da aynı oranda küçüldü (184 x 200/268).
        final child = t.getRect(find.byType(SizedBox).last);
        expect(child.width, closeTo(184 * 200 / 268, 1e-6));
        expect(child.center, t.getRect(find.byType(CountdownRing)).center);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('geniş alanda doğal boyut (268) korunur; büyümez, ortalanır', (
      t,
    ) async {
      final c = _controller(t, value: 0.5);
      await t.pumpWidget(
        harnessApp(Center(child: SizedBox(width: 700, child: _ringWidget(c)))),
      );
      // Sıkı genişlikte bileşen alanı doldurur; halka 268'de kalır ve ortalanır.
      final paint = find
          .descendant(
            of: find.byType(CountdownRing),
            matching: find.byType(CustomPaint),
          )
          .first;
      expect(t.getRect(paint).size, const Size(268, 268));
      expect(
        t.getRect(paint).center,
        t.getRect(find.byType(CountdownRing)).center,
      );
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'taşma matrisi: 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu (QR modalı iç genişliğinde)',
      (t) async {
        await forEachHarnessCell((width, scale, dark) async {
          final c = AnimationController(
            vsync: t,
            value: 0.7,
            duration: const Duration(seconds: 30),
          );
          await pumpAt(
            t,
            Padding(
              // Modal: Dialog insetPadding 16 + içerik dolgusu 20 -> iki yanda 36 dp.
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: CountdownRing.goodColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      const Expanded(
                        child: Text(
                          'Kapı Geçiş QR Kodu: tarayıcıya gösterin',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      CountdownSeconds(progress: c),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Center(child: _ringWidget(c)),
                ],
              ),
            ),
            width: width,
            scale: scale,
            dark: dark,
          );
          expect(
            find.text('21 sn'),
            findsOneWidget,
            reason: '$width x $scale dark=$dark',
          );
          final size = t.getSize(find.byType(CountdownRing));
          expect(size.width, size.height, reason: 'halka dairesel kalır');
          expect(size.width, lessThanOrEqualTo(268));
          expect(size.width, lessThanOrEqualTo(width - 72 + 1e-6));
          await t.pumpWidget(const SizedBox.shrink());
          c.dispose();
        });
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('CountdownSeconds.secondsFor', () {
    test('yukarı yuvarlar; uçlar 0 ve toplam', () {
      expect(CountdownSeconds.secondsFor(1.0, 30), 30);
      expect(CountdownSeconds.secondsFor(0.0, 30), 0);
      expect(CountdownSeconds.secondsFor(0.5, 30), 15);
      expect(CountdownSeconds.secondsFor(0.51, 30), 16, reason: '15,3 -> 16');
      expect(CountdownSeconds.secondsFor(0.0001, 30), 1);
      expect(CountdownSeconds.secondsFor(0.99, 30), 30);
      expect(CountdownSeconds.secondsFor(29 / 30, 30), 29);
    });

    test('kayan nokta artığı bir üst saniyeye atlatmaz (epsilon koruması)', () {
      // Önkoşul: bu çarpımlar tam tamsayı DEĞİLDİR; epsilonsuz ceil() bir üst saniyeyi gösterirdi.
      expect((29 / 45) * 45, greaterThan(29), reason: '29,000000000000004');
      expect((31 / 60) * 60, greaterThan(31), reason: '31,000000000000004');
      expect(CountdownSeconds.secondsFor(29 / 45, 45), 29);
      expect(CountdownSeconds.secondsFor(31 / 60, 60), 31);
      for (final total in [10, 15, 20, 30, 45, 60]) {
        for (var s = 0; s <= total; s++) {
          expect(
            CountdownSeconds.secondsFor(s / total, total),
            s,
            reason: '$s/$total -> $s sn',
          );
        }
      }
    });

    test('aralık dışı, NaN ve geçersiz toplam güvenli', () {
      expect(CountdownSeconds.secondsFor(2.0, 30), 30);
      expect(CountdownSeconds.secondsFor(-1.0, 30), 0);
      expect(CountdownSeconds.secondsFor(double.nan, 30), 0);
      expect(CountdownSeconds.secondsFor(0.5, 0), 0);
      expect(CountdownSeconds.secondsFor(0.5, -5), 0);
      expect(CountdownSeconds.secondsFor(0.5, 60), 30);
    });
  });

  group('CountdownSeconds', () {
    Widget host(
      Animation<double> a, {
      int total = 30,
      String suffix = ' sn',
      TextStyle? style,
    }) => harnessApp(
      Center(
        child: CountdownSeconds(
          progress: a,
          totalSeconds: total,
          suffix: suffix,
          style: style,
        ),
      ),
    );

    testWidgets('ilk karede kalan saniye + " sn"', (t) async {
      final c = _controller(t, value: 1.0);
      await t.pumpWidget(host(c));
      expect(find.text('30 sn'), findsOneWidget);
      c.value = 0.5;
      await t.pump();
      expect(find.text('15 sn'), findsOneWidget);
      c.value = 0.0;
      await t.pump();
      expect(find.text('0 sn'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('geri sayım akışı: saniyede bir azalır (30, 29, 28 ... 0)', (
      t,
    ) async {
      final c = _controller(t, seconds: 30);
      await t.pumpWidget(host(c));
      c.reverse(from: 1);
      await t.pump();
      expect(find.text('30 sn'), findsOneWidget);
      for (var elapsed = 1; elapsed <= 30; elapsed++) {
        await t.pump(const Duration(seconds: 1));
        expect(
          find.text('${30 - elapsed} sn'),
          findsOneWidget,
          reason: '$elapsed. saniye',
        );
      }
      expect(c.value, 0.0);
      c.stop();
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('toplam saniye parametresi (60 sn denetleyici) uygulanır', (
      t,
    ) async {
      final c = _controller(t, value: 0.5, seconds: 60);
      await t.pumpWidget(host(c, total: 60));
      expect(find.text('30 sn'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'yalnız GÖSTERİLEN rakam değişince yeniden kurulur (aynı saniyede aynı Text örneği)',
      (t) async {
        final c = _controller(t, value: 0.99);
        await t.pumpWidget(host(c));
        final first = t.widget<Text>(find.byType(Text));
        expect(first.data, '30 sn');
        c.value = 0.98; // 29,4 -> hâlâ 30
        await t.pump();
        c.value = 0.97; // 29,1 -> hâlâ 30
        await t.pump();
        expect(
          identical(t.widget<Text>(find.byType(Text)), first),
          isTrue,
          reason: 'aynı saniye içinde widget yeniden kurulmadı',
        );
        c.value = 0.96; // 28,8 -> 29
        await t.pump();
        final second = t.widget<Text>(find.byType(Text));
        expect(identical(second, first), isFalse);
        expect(second.data, '29 sn');
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('özel ek, stil; rakamlar sabit genişlikli; tek satır + elips', (
      t,
    ) async {
      final c = _controller(t, value: 0.5);
      await t.pumpWidget(
        host(
          c,
          suffix: ' s',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.red,
          ),
        ),
      );
      final text = t.widget<Text>(find.text('15 s'));
      expect(text.style!.fontWeight, FontWeight.w800);
      expect(text.style!.color, Colors.red);
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'animasyon değişince yeniden abone olur; eskisi artık etkilemez',
      (t) async {
        final a = _controller(t, value: 1.0);
        final b = _controller(t, value: 0.5);
        await t.pumpWidget(host(a));
        expect(find.text('30 sn'), findsOneWidget);
        await t.pumpWidget(host(b));
        expect(find.text('15 sn'), findsOneWidget);
        a.value = 0.1;
        await t.pump();
        expect(
          find.text('15 sn'),
          findsOneWidget,
          reason: 'eski animasyon etkisiz',
        );
        b.value = 0.1;
        await t.pump();
        expect(find.text('3 sn'), findsOneWidget);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('toplam saniye değişince hemen yeniden hesaplanır', (t) async {
      final c = _controller(t, value: 0.5);
      await t.pumpWidget(host(c));
      expect(find.text('15 sn'), findsOneWidget);
      await t.pumpWidget(host(c, total: 60));
      expect(find.text('30 sn'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'dispose: ağaç sökülünce dinleyici düşer (sonraki değer değişimi hata vermez)',
      (t) async {
        final c = _controller(t, value: 1.0);
        await t.pumpWidget(host(c));
        await t.pumpWidget(const SizedBox.shrink());
        c.value = 0.2;
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'Semantics: etiket metindir; canlı bölge DEĞİL (her saniye duyuru yok)',
      (t) async {
        final handle = t.ensureSemantics();
        final c = _controller(t, value: 0.9);
        await t.pumpWidget(host(c));
        expect(
          t.getSemantics(find.byType(CountdownSeconds)),
          isSemantics(label: '27 sn', isLiveRegion: false),
        );
        await t.pumpWidget(const SizedBox.shrink());
        handle.dispose();
      },
    );

    testWidgets('pumpAndSettle biter (durağan ilerleme: ticker yok)', (
      t,
    ) async {
      final c = _controller(t, value: 0.5);
      await t.pumpWidget(host(c));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dar kutuda tek satır + elips: taşma yok', (t) async {
      final c = _controller(t, value: 1.0);
      await t.pumpWidget(
        harnessApp(
          Center(
            child: SizedBox(width: 24, child: CountdownSeconds(progress: c)),
          ),
          scale: 2.0,
        ),
      );
      expect(t.takeException(), isNull);
      expect(
        t.getSize(find.byType(CountdownSeconds)).width,
        lessThanOrEqualTo(24),
      );
      await t.pumpWidget(const SizedBox.shrink());
    });
  });
}
