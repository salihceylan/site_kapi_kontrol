// "Cilalı Safir": QR tarama kılavuzu (QrScanOverlay: ipucu kapsülü + köşe işaretli çerçeve) ve
// desteklenmeyen platform ekranı. Kamera/tarama mantığı (MobileScanner) bu testte YOKTUR: kılavuz
// kameradan bağımsız, salt görüntü bileşenidir.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/qr_scan_page.dart';

import '../design/harness.dart';

const String _long =
    'Modemin veya paylaşılan Wi-Fi ağının karekodunu kameraya gösterin.';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

Future<void> _pumpOverlay(
  WidgetTester t, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  Color accent = const Color(0xFF3B82F6),
  String text = _long,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    harnessApp(
      SizedBox.expand(
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF222831))),
            Positioned.fill(
              child: QrScanOverlay(accentColor: accent, instructionText: text),
            ),
          ],
        ),
      ),
      dark: dark,
      scale: scale,
    ),
  );
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull);
}

void main() {
  for (final (w, h, s) in const <(double, double, double)>[
    (320, 640, 2.0),
    (360, 640, 1.5),
  ]) {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'taşma matrisi ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}',
        (t) async {
          await _pumpOverlay(t, width: w, height: h, scale: s, dark: dark);
          expect(find.text(_long), findsOneWidget);
          expect(find.byType(IconOrb), findsOneWidget);
          expect(find.byType(QrScanFrame), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'ipucu: yazı ölçeğini izler, kırpılmaz; rozet dekoratif (anlamsal ağaçta yok)',
    (t) async {
      final handle = t.ensureSemantics();
      await _pumpOverlay(t, width: 320, scale: 2.0);
      final text = t.widget<Text>(find.text(_long));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(
        find.descendant(
          of: find.byType(IconOrb),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      expect(find.bySemanticsLabel(_long), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('çerçeve genişliğin %65\'i, 180-280 dp ile sınırlı ve ortalı', (
    t,
  ) async {
    await _pumpOverlay(t, width: 360);
    expect(t.getSize(find.byType(QrScanFrame)), const Size(234, 234));
    await _pumpOverlay(t, width: 200);
    expect(t.getSize(find.byType(QrScanFrame)), const Size(180, 180));
    await _pumpOverlay(t, width: 820, height: 900);
    expect(t.getSize(find.byType(QrScanFrame)), const Size(280, 280));
    expect(t.getCenter(find.byType(QrScanFrame)).dx, closeTo(410, 0.5));
  });

  testWidgets(
    'çerçeve: pencere çizgisi + dört köşe kolu (koyu iz + ton rengi); durağan',
    (t) async {
      await _pumpOverlay(t);
      final paint = find.descendant(
        of: find.byType(QrScanFrame),
        matching: find.byType(CustomPaint),
      );
      expect(
        t.renderObject(paint),
        paints
          ..rrect()
          ..path(strokeWidth: QrScanFramePainter.stroke + 2)
          ..path(
            color: const Color(0xFF3B82F6),
            strokeWidth: QrScanFramePainter.stroke,
          ),
      );
      expect(
        t.binding.transientCallbackCount,
        0,
        reason: 'sonsuz animasyon yok',
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    },
  );

  testWidgets('kılavuz dokunmayı yutmaz (IgnorePointer)', (t) async {
    await _pumpOverlay(t);
    expect(
      find.ancestor(
        of: find.byType(QrScanFrame),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });

  test('ton eşleme ve AppBar renkleri: rol renginde koyu uç, ön plan >= 4,5:1', () {
    for (final tone in AppTone.values) {
      expect(QrScanOverlay.toneFor(tone.hue), tone);
      final bar = QrScanOverlay.barColorFor(tone.hue);
      expect(bar, tone.a);
      expect(
        _contrast(QrScanOverlay.onBarColor(bar), bar),
        greaterThanOrEqualTo(4.5),
        reason: tone.name,
      );
    }
    expect(QrScanOverlay.toneFor(const Color(0xFF123456)), AppTone.primary);
    expect(
      QrScanOverlay.barColorFor(const Color(0xFF123456)),
      const Color(0xFF123456),
    );
  });

  testWidgets(
    'desteklenmeyen platform (masaüstü): EmptyState + aynı mesaj, kamera yok',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(harnessApp(const QrScanPage(), scale: 2.0));
        await t.pump(const Duration(milliseconds: 450));
        expect(find.byType(EmptyState), findsOneWidget);
        expect(
          find.text(
            'Bu platformda kamera ile QR tarama desteklenmiyor. Şirket uygulamasını Android veya iPhone üzerinde kullanın.',
          ),
          findsOneWidget,
        );
        expect(find.text('QR Kod Oku'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
