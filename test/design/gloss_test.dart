// Premium cila katmanı (Gloss) testleri.
//
// Sözleşme: (1) cila beyaz içeriğin (etiket/ikon) durduğu bölgede kontrastı >= 4,5:1 altına
// düşürmez (GERÇEK boyanmış piksellerle ölçülür); (2) dokunmayı yutmaz; (3) yüksek karşıtlıkta ve
// strength 0'da çizmez; (4) ışıltı süpürmesi yalnız 0-1 arasında çizilir; (5) pahalı efekt
// (saveLayer üreten widget) içermez.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

const double _d = 148;

/// Cilalı zemin: ton gradyanı + [Gloss]. İçerik (metin/ikon) YOK: pikseller yalnız zemindir.
Widget _surface(
  AppTone tone, {
  GlossShape shape = GlossShape.circle,
  double? width,
  double? height,
  double strength = 1,
  Animation<double>? sweep,
}) {
  final circle = shape == GlossShape.circle;
  final w = width ?? _d;
  final h = height ?? _d;
  return SizedBox(
    width: w,
    height: h,
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: circle
                  ? const CircleBorder()
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
              gradient: tone.gradient,
            ),
          ),
        ),
        Positioned.fill(
          child: Gloss(
            shape: shape,
            radius: AppRadius.md,
            strength: strength,
            sweep: sweep,
          ),
        ),
      ],
    ),
  );
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// [key] altındaki katmanı 1:1 ölçekte çizip piksel okuyucusunu döndürür.
Future<Color Function(int x, int y)> _pixels(
  WidgetTester t,
  GlobalKey key,
) async {
  late ByteData bytes;
  late int width;
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    width = image.width;
    bytes = (await image.toByteData())!;
  });
  return (x, y) {
    final i = (y * width + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  };
}

Future<GlobalKey> _pump(WidgetTester t, Widget surface) async {
  final key = GlobalKey();
  await t.pumpWidget(
    harnessApp(
      Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(key: key, child: surface),
      ),
    ),
  );
  await t.pump();
  return key;
}

/// [zone] içindeki (kesirli dikdörtgen) piksellerin beyazla EN DÜŞÜK kontrastı.
double _minContrast(
  Color Function(int, int) px,
  Size size,
  Rect zone, {
  int step = 2,
}) {
  var lowest = double.infinity;
  final x0 = (zone.left * size.width).round();
  final x1 = (zone.right * size.width).round();
  final y0 = (zone.top * size.height).round();
  final y1 = (zone.bottom * size.height).round();
  for (var y = y0; y < y1; y += step) {
    for (var x = x0; x < x1; x += step) {
      lowest = math.min(lowest, _contrast(Colors.white, px(x, y)));
    }
  }
  return lowest;
}

const List<AppTone> _liveTones = <AppTone>[
  AppTone.primary,
  AppTone.success,
  AppTone.warning,
  AppTone.info,
  AppTone.danger,
  AppTone.violet,
];

void main() {
  group('kontrast (gerçek piksel)', () {
    testWidgets(
      'daire: ikon bölgesi >= 3:1, etiket bölgesi >= 4,5:1 (tüm canlı tonlar)',
      (t) async {
        for (final tone in _liveTones) {
          final key = await _pump(t, _surface(tone));
          final px = await _pixels(t, key);
          const size = Size(_d, _d);
          final icon = _minContrast(px, size, const Rect.fromLTRB(0.33, 0.22, 0.67, 0.52));
          final label = _minContrast(px, size, const Rect.fromLTRB(0.20, 0.56, 0.80, 0.74));
          // İkon grafik nesnedir (WCAG 1.4.11: >= 3:1); etiket metindir (>= 4,5:1).
          expect(
            icon,
            greaterThanOrEqualTo(3.0),
            reason: '${tone.name} ikon bölgesi ${icon.toStringAsFixed(2)}',
          );
          expect(
            label,
            greaterThanOrEqualTo(4.5),
            reason: '${tone.name} etiket bölgesi ${label.toStringAsFixed(2)}',
          );
        }
      },
    );

    testWidgets(
      'çubuk (52 dp): içerik şeridi beyazla >= 4,5:1 (tüm canlı tonlar)',
      (t) async {
        for (final tone in _liveTones) {
          final key = await _pump(
            t,
            _surface(
              tone,
              shape: GlossShape.rounded,
              width: 320,
              height: 52,
            ),
          );
          final px = await _pixels(t, key);
          final ratio = _minContrast(
            px,
            const Size(320, 52),
            const Rect.fromLTRB(0.15, 0.25, 0.85, 0.80),
          );
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${tone.name} çubuk ${ratio.toStringAsFixed(2)}',
          );
        }
      },
    );

    testWidgets('küçük daire (44 dp ikon rozeti): ikon bölgesi >= 3:1', (t) async {
      for (final tone in _liveTones) {
        final key = await _pump(t, _surface(tone, width: 44, height: 44));
        final px = await _pixels(t, key);
        final ratio = _minContrast(
          px,
          const Size(44, 44),
          const Rect.fromLTRB(0.28, 0.28, 0.72, 0.72),
          step: 1,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '${tone.name} 44 dp ${ratio.toStringAsFixed(2)}',
        );
      }
    });
  });

  group('davranış', () {
    testWidgets('dokunmayı yutmaz (IgnorePointer): altındaki düğme çalışır', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(
        harnessApp(
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: const ColoredBox(color: Colors.blue),
                    ),
                  ),
                  const Positioned.fill(child: Gloss()),
                ],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byType(GestureDetector));
      expect(taps, 1);
    });

    testWidgets('yüksek karşıtlık modunda çizilmez', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: const Scaffold(body: SizedBox(width: 50, height: 50, child: Gloss())),
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is GlossPainter,
        ),
        findsNothing,
      );
    });

    testWidgets('strength 0: boyayıcı hiçbir şey çizmez', (t) async {
      final key = await _pump(
        t,
        _surface(AppTone.primary, strength: 0),
      );
      final px = await _pixels(t, key);
      // Daire içi: yalnız düz ton gradyanı; sol-üst ışıma ve parıltı yok -> üst parlaklık <= alt.
      final top = px(74, 14).computeLuminance();
      final mid = px(74, 74).computeLuminance();
      expect(top, lessThanOrEqualTo(mid + 0.02));
    });

    testWidgets('pahalı efekt widget\'ı içermez (Opacity/BackdropFilter/ShaderMask/ImageFiltered)', (
      t,
    ) async {
      await t.pumpWidget(harnessApp(Center(child: _surface(AppTone.primary))));
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('durağanken ticker/kare yok', (t) async {
      await t.pumpWidget(harnessApp(Center(child: _surface(AppTone.primary))));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('ışıltı süpürmesi yalnız 0-1 arasında çizilir ve animasyonla yeniden boyanır', (
      t,
    ) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 600),
      );
      addTearDown(controller.dispose);
      final key = await _pump(
        t,
        _surface(AppTone.primary, sweep: controller),
      );
      var px = await _pixels(t, key);
      final before = px(74, 100);

      controller.value = 0.5; // şerit ortada
      await t.pump();
      px = await _pixels(t, key);
      final during = px(74, 100);
      expect(
        during.computeLuminance(),
        greaterThan(before.computeLuminance()),
        reason: 'şerit tam ortadan geçerken piksel aydınlanır',
      );

      controller.value = 1.0; // bitti: çizim yok
      await t.pump();
      px = await _pixels(t, key);
      expect(px(74, 100), before);
    });
  });
}
