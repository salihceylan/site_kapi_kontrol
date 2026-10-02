// FAZ 5 / A1b-(iii): ShimmerScope + SkeletonBox widget testleri.
//
// Durumlar (boyut, durağan/animasyonlu, açık/koyu), TEK denetleyici paylaşımı, yalnız yüklenirken
// animasyon (pumpAndSettle biter), hareket azaltma, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x
// açık/koyu) ve Semantics.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';

import 'harness.dart';

const Color _baseLight = Color(0xFFE2E8F0);
const Color _highlightLight = Color(0xFFF1F5F9);
const Color _baseDark = Color(0xFF273449);
const Color _highlightDark = Color(0xFF334155);

/// [box] içindeki (tek) CustomPaint.
Finder _paintOf(Finder box) =>
    find.descendant(of: box, matching: find.byType(CustomPaint));

CustomPainter _painterOf(WidgetTester t, Finder box) =>
    t.widget<CustomPaint>(_paintOf(box).first).painter!;

/// Kutunun o an çizdiği ilk `drawRRect` çağrısının boya nesnesi.
Paint _drawnPaint(WidgetTester t, Finder box) {
  Paint? drawn;
  expect(
    t.renderObject(_paintOf(box).first),
    paints..something((Symbol method, List<dynamic> args) {
      if (method == #drawRRect) {
        drawn = args[1] as Paint;
        return true;
      }
      return false;
    }),
  );
  return drawn!;
}

/// [boundary] içeriğinin (x, y) pikseli (devicePixelRatio 1,0). Gerçek raster gerekir: runAsync.
Future<Color> _pixel(WidgetTester t, GlobalKey boundary, int x, int y) async {
  final color = await t.runAsync<Color>(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final data = (await image.toByteData())!;
    final i = (y * image.width + x) * 4;
    final c = Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
    image.dispose();
    return c;
  });
  return color!;
}

/// Her kanalda en çok [tolerance] farkla aynı renk mi?
bool _near(Color a, Color b, {int tolerance = 3}) {
  int ch(double v) => (v * 255).round();
  return (ch(a.r) - ch(b.r)).abs() <= tolerance &&
      (ch(a.g) - ch(b.g)).abs() <= tolerance &&
      (ch(a.b) - ch(b.b)).abs() <= tolerance &&
      (ch(a.a) - ch(b.a)).abs() <= tolerance;
}

/// Kaç kez boyandığını sayan boyayıcı (kapsam dışı kardeşin yeniden boyanıp boyanmadığını ölçer).
class _CountingPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Gerçekçi bir yükleniyor yerleşimi: avatar + iki satır, tam genişlik başlık, yüzde genişlik satır,
/// düğme boyu kutu, `Row` içinde `Expanded`.
Widget _skeletonLayout() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SkeletonBox(width: 40, height: 40, radius: 999),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 16)),
          ],
        ),
        const SizedBox(height: 12),
        const SkeletonBox(),
        const SizedBox(height: 8),
        const FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: 0.6,
          child: SkeletonBox(),
        ),
        const SizedBox(height: 12),
        const SkeletonBox(height: 48, radius: 16),
      ],
    ),
  );
}

void main() {
  group('SkeletonBox: boyut ve görünüm', () {
    testWidgets(
      'genişlik verilmezse kullanılabilir genişliği kaplar; boyutlar uygulanır',
      (t) async {
        await pumpAt(
          t,
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SkeletonBox(), SkeletonBox(width: 120, height: 20)],
          ),
          scale: 1.0,
        );
        final boxes = find.byType(SkeletonBox);
        expect(
          t.getSize(boxes.at(0)),
          const Size(320, 14),
          reason: 'varsayılan yükseklik 14, genişlik = kullanılabilir',
        );
        expect(t.getSize(boxes.at(1)), const Size(120, 20));
      },
    );

    testWidgets(
      'kapsam yokken durağan çizilir: tek düz taban rengi, gölgelendirici yok (açık)',
      (t) async {
        await pumpAt(
          t,
          const Align(
            alignment: Alignment.topLeft,
            child: SkeletonBox(width: 200, height: 14, radius: 8),
          ),
          scale: 1.0,
        );
        final box = find.byType(SkeletonBox);
        expect(
          t.renderObject(_paintOf(box)),
          paints..rrect(
            rrect: RRect.fromRectAndRadius(
              const Rect.fromLTWH(0, 0, 200, 14),
              const Radius.circular(8),
            ),
            color: _baseLight,
          ),
        );
        expect(_drawnPaint(t, box).shader, isNull);
        expect(
          t.binding.transientCallbackCount,
          0,
          reason: 'kapsam yok: ticker yok',
        );
      },
    );

    testWidgets('koyu temada koyu taban rengi', (t) async {
      await pumpAt(
        t,
        const Align(
          alignment: Alignment.topLeft,
          child: SkeletonBox(width: 200),
        ),
        scale: 1.0,
        dark: true,
      );
      expect(
        t.renderObject(_paintOf(find.byType(SkeletonBox))),
        paints..rrect(color: _baseDark),
      );
    });

    testWidgets(
      'radius yüksekliğin yarısını aşınca daire/hap: hata yok, boyut korunur',
      (t) async {
        await pumpAt(
          t,
          const Align(
            alignment: Alignment.topLeft,
            child: SkeletonBox(width: 40, height: 40, radius: 999),
          ),
          scale: 1.0,
        );
        expect(t.getSize(find.byType(SkeletonBox)), const Size(40, 40));
      },
    );

    testWidgets(
      'Row içinde Expanded/sabit genişlik ve yüzde genişlik: taşma/sonsuz genişlik yok',
      (t) async {
        await pumpAt(t, _skeletonLayout(), width: 320, scale: 1.0);
        final boxes = find.byType(SkeletonBox);
        // avatar, Expanded başlık, tam genişlik, %60, düğme boyu
        expect(t.getSize(boxes.at(0)), const Size(40, 40));
        expect(t.getSize(boxes.at(1)).width, 320 - 32 - 40 - 12);
        expect(t.getSize(boxes.at(2)).width, 320 - 32);
        expect(t.getSize(boxes.at(3)).width, closeTo((320 - 32) * 0.6, 0.01));
        expect(t.getSize(boxes.at(4)).height, 48);
      },
    );
  });

  group('ShimmerScope: tek denetleyici, yalnız yüklenirken animasyon', () {
    testWidgets(
      'kapsamdaki N kutu = TEK ticker; kutular yeniden kurulmaz, yalnız boyanır',
      (t) async {
        await pumpAt(
          t,
          const ShimmerScope(
            child: Column(
              children: [
                SkeletonBox(),
                SkeletonBox(),
                SkeletonBox(),
                SkeletonBox(),
                SkeletonBox(),
                SkeletonBox(),
              ],
            ),
          ),
          scale: 1.0,
        );
        expect(
          t.binding.transientCallbackCount,
          1,
          reason: '6 kutu tek denetleyiciyi paylaşır: bir ticker',
        );

        final boxes = find.byType(SkeletonBox);
        final painter = _painterOf(t, boxes.first);
        var repaintSignals = 0;
        void onSignal() => repaintSignals++;
        painter.addListener(onSignal);
        await t.pump(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 100));
        painter.removeListener(onSignal);

        expect(
          repaintSignals,
          greaterThan(0),
          reason: 'her karede yeniden boyama sinyali',
        );
        expect(
          identical(_painterOf(t, boxes.first), painter),
          isTrue,
          reason:
              'kutu yeniden KURULMADI (aynı painter nesnesi): yalnız repaint',
        );
        expect(
          _drawnPaint(t, boxes.first).shader,
          isNotNull,
          reason: 'animasyonda gölgelendirici var',
        );
      },
    );

    testWidgets(
      'vurgu bandı soldan sağa süpürür: başta/sonda yok, ortada kutunun ortasında (açık)',
      (t) async {
        final key = GlobalKey();
        await t.pumpWidget(
          harnessApp(
            Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: const SizedBox(
                  width: 200,
                  child: ShimmerScope(child: SkeletonBox(height: 14)),
                ),
              ),
            ),
          ),
        );
        // Ticker'ın ilk karesi başlangıç anını belirler (değer 0): vurgu kutunun dışında.
        await t.pump();
        expect(
          _near(await _pixel(t, key, 100, 7), _baseLight),
          isTrue,
          reason: 'ilerleme 0: ortada taban rengi',
        );
        // Döngünün yarısı (1400 ms / 2): vurgunun merkezi kutunun ortasında.
        await t.pump(const Duration(milliseconds: 700));
        expect(
          _near(await _pixel(t, key, 100, 7), _highlightLight),
          isTrue,
          reason: 'ilerleme 0,5: merkez vurgu rengi',
        );
        expect(
          _near(await _pixel(t, key, 6, 7), _baseLight),
          isTrue,
          reason: 'vurgu bandı dar: kenar taban rengi',
        );
        // Köşe yuvarlak: dış piksel boş (gölgelendirici kutu dışına taşmaz).
        expect((await _pixel(t, key, 0, 0)).a, 0);
      },
    );

    testWidgets(
      'yeniden boyama kapsamın kendi katmanında kalır: kapsam dışı kardeşler her karede boyanmaz',
      (t) async {
        final sibling = _CountingPainter();
        await t.pumpWidget(
          harnessApp(
            Column(
              children: [
                CustomPaint(painter: sibling, size: const Size(10, 10)),
                const ShimmerScope(child: SkeletonBox()),
              ],
            ),
          ),
        );
        await t.pump();
        final before = sibling.paints;
        final painter = _painterOf(t, find.byType(SkeletonBox));
        var signals = 0;
        void onSignal() => signals++;
        painter.addListener(onSignal);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 16));
        }
        painter.removeListener(onSignal);

        expect(signals, 10, reason: 'iskelet her karede yeniden boyanır');
        expect(
          sibling.paints,
          before,
          reason:
              'RepaintBoundary yok olsaydı kardeş de 10 kez boyanırdı (ölçüm: 2 -> 12)',
        );
      },
    );

    testWidgets('vurgu bandı koyu temada koyu vurgu rengidir', (t) async {
      final key = GlobalKey();
      await t.pumpWidget(
        harnessApp(
          Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 200,
                child: ShimmerScope(child: SkeletonBox(height: 14)),
              ),
            ),
          ),
          dark: true,
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_near(await _pixel(t, key, 100, 7), _highlightDark), isTrue);
      expect(_near(await _pixel(t, key, 6, 7), _baseDark), isTrue);
    });

    testWidgets(
      'hareket azaltma: ticker yok, durağan gri; pumpAndSettle hemen biter',
      (t) async {
        await pumpAt(
          t,
          const ShimmerScope(
            child: Column(children: [SkeletonBox(), SkeletonBox()]),
          ),
          scale: 1.0,
          reduce: true,
        );
        expect(t.binding.transientCallbackCount, 0);
        final boxes = find.byType(SkeletonBox);
        expect(
          _drawnPaint(t, boxes.first).shader,
          isNull,
          reason: 'durağan: düz renk',
        );
        // Paint rengi float32 saklanır: Color == ile değil, kanal toleransıyla karşılaştırılır.
        expect(
          _near(_drawnPaint(t, boxes.first).color, _baseLight, tolerance: 0),
          isTrue,
        );
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'hareket azaltma çalışma anında açılıp kapanınca ticker durur/yeniden başlar',
      (t) async {
        Widget app({required bool reduce}) => harnessApp(
          const ShimmerScope(child: SkeletonBox()),
          reduce: reduce,
        );
        await t.pumpWidget(app(reduce: false));
        await t.pump(const Duration(milliseconds: 50));
        expect(t.binding.transientCallbackCount, 1);

        await t.pumpWidget(app(reduce: true));
        await t.pump();
        expect(
          t.binding.transientCallbackCount,
          0,
          reason: 'hareket azaltma açıldı: durur',
        );
        expect(_drawnPaint(t, find.byType(SkeletonBox)).shader, isNull);

        await t.pumpWidget(app(reduce: false));
        await t.pump(const Duration(milliseconds: 50));
        expect(
          t.binding.transientCallbackCount,
          1,
          reason: 'hareket azaltma kapandı: yeniden döner',
        );
        expect(_drawnPaint(t, find.byType(SkeletonBox)).shader, isNotNull);
      },
    );

    testWidgets('active: false iken durağan; true yapılınca yeniden döner', (
      t,
    ) async {
      Widget app({required bool active}) =>
          harnessApp(ShimmerScope(active: active, child: const SkeletonBox()));
      await t.pumpWidget(app(active: false));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.binding.transientCallbackCount, 0);
      expect(_drawnPaint(t, find.byType(SkeletonBox)).shader, isNull);
      await t.pumpAndSettle();

      await t.pumpWidget(app(active: true));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.binding.transientCallbackCount, 1);
      expect(_drawnPaint(t, find.byType(SkeletonBox)).shader, isNotNull);

      await t.pumpWidget(app(active: false));
      await t.pump();
      expect(
        t.binding.transientCallbackCount,
        0,
        reason: 'yükleme bitti: ticker kalmaz',
      );
      expect(_drawnPaint(t, find.byType(SkeletonBox)).shader, isNull);
      await t.pumpAndSettle();
    });

    testWidgets(
      'yalnız yüklenirken animasyon: kapsam sürerken pumpAndSettle BİTMEZ, kalkınca biter',
      (t) async {
        await t.pumpWidget(
          harnessApp(
            const ShimmerScope(
              child: Column(children: [SkeletonBox(), SkeletonBox()]),
            ),
          ),
        );
        // Pozitif kontrol: yükleniyor iken sonsuz animasyon vardır (test bunu yakalayabiliyor).
        Object? error;
        try {
          await t.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
        } catch (e) {
          error = e;
        }
        expect(
          error,
          isNotNull,
          reason: 'yüklenirken ticker sürer: settle olmaz',
        );

        // Yükleme bitti: kapsam ağaçtan çıkar -> denetleyici dispose, ticker kalmaz.
        await t.pumpWidget(harnessApp(const Text('Yüklendi')));
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0);
        expect(find.text('Yüklendi'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('TickerMode kapalıyken (örn. üstü kapalı rota) kare istenmez', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          const TickerMode(
            enabled: false,
            child: ShimmerScope(child: SkeletonBox()),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'kapsam sökülünce denetleyici dispose edilir (ticker sızıntısı yok)',
      (t) async {
        await t.pumpWidget(
          harnessApp(const ShimmerScope(child: SkeletonBox())),
        );
        await t.pump(const Duration(milliseconds: 100));
        await t.pumpWidget(harnessApp(const SizedBox()));
        await t.pump();
        expect(
          t.takeException(),
          isNull,
          reason: '"Ticker was not disposed" hatası yok',
        );
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'liste içinde (ListView.builder) tek kapsam: 30 kutu, tek ticker',
      (t) async {
        await pumpAt(
          t,
          SizedBox(
            height: 400,
            child: ShimmerScope(
              child: ListView.builder(
                itemCount: 30,
                itemBuilder: (_, i) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: SkeletonBox(height: 16),
                ),
              ),
            ),
          ),
          scale: 1.0,
        );
        expect(t.binding.transientCallbackCount, 1);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('Semantics', () {
    testWidgets(
      'etkin kapsam: tek "Yükleniyor" canlı bölgesi; kutular anlamsal ağaçta yok',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          harnessApp(
            const ShimmerScope(
              child: Column(
                children: [SkeletonBox(), SkeletonBox(), SkeletonBox()],
              ),
            ),
          ),
        );
        expect(
          t.getSemantics(find.byType(ShimmerScope)),
          isSemantics(label: 'Yükleniyor', isLiveRegion: true),
        );
        expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
        final labelled = t.semantics
            .simulatedAccessibilityTraversal()
            .where((n) => n.getSemanticsData().label.isNotEmpty)
            .toList();
        expect(
          labelled,
          hasLength(1),
          reason: 'yalnız kapsayıcı okunur, 3 kutu sessiz',
        );
        handle.dispose();
      },
    );

    testWidgets('kapsam içindeki gerçek içeriğin anlamı korunur', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        harnessApp(
          const ShimmerScope(
            child: Column(children: [Text('Kapılar'), SkeletonBox()]),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
      expect(find.bySemanticsLabel('Kapılar'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('active: false: "Yükleniyor" etiketi yok (yükleme bitti)', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        harnessApp(const ShimmerScope(active: false, child: SkeletonBox())),
      );
      expect(find.bySemanticsLabel('Yükleniyor'), findsNothing);
      handle.dispose();
    });

    testWidgets(
      'hareket azaltmada da "Yükleniyor" okunur (iskelet durağan olsa bile)',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          harnessApp(const ShimmerScope(child: SkeletonBox()), reduce: true),
        );
        expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('kapsamsız kutu anlamsal ağaçta hiçbir şey eklemez', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        harnessApp(const Column(children: [SkeletonBox(), SkeletonBox()])),
      );
      expect(find.bySemanticsLabel('Yükleniyor'), findsNothing);
      final labelled = t.semantics.simulatedAccessibilityTraversal().where(
        (n) => n.getSemanticsData().label.isNotEmpty,
      );
      expect(labelled, isEmpty);
      handle.dispose();
    });
  });

  group('taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu)', () {
    testWidgets('yükleniyor yerleşimi hiçbir hücrede taşmaz ve ekranı aşmaz', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          ShimmerScope(child: _skeletonLayout()),
          width: width,
          scale: scale,
          dark: dark,
        );
        for (final box in find.byType(SkeletonBox).evaluate()) {
          final size = (box.renderObject! as RenderBox).size;
          expect(
            size.width,
            lessThanOrEqualTo(width),
            reason: '${width}px x$scale ${dark ? 'koyu' : 'açık'}',
          );
          expect(size.width.isFinite, isTrue);
        }
        expect(t.binding.transientCallbackCount, 1);
      });
    });

    testWidgets('hareket azaltmada da taşma yok (statik)', (t) async {
      for (final width in kHarnessWidths) {
        await pumpAt(
          t,
          ShimmerScope(child: _skeletonLayout()),
          width: width,
          scale: 2.0,
          reduce: true,
        );
        expect(t.binding.transientCallbackCount, 0);
      }
    });
  });
}
