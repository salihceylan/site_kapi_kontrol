import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/plate_onnx_recognizer.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_live_box_overlay.dart';

void main() {
  group('PlateOnnxRecognizer Türk plaka doğrulama ve ayrıştırma testleri', () {
    test('Standart Türk plaka biçimlerini doğru ayrıştırır', () {
      expect(PlateOnnxRecognizer.formatTrPlate('34NBL304'), '34 NBL 304');
      expect(PlateOnnxRecognizer.formatTrPlate('35JU988'), '35 JU 988');
      expect(PlateOnnxRecognizer.formatTrPlate('35T7154'), '35 T 7154');
      expect(PlateOnnxRecognizer.formatTrPlate('34A12345'), '34 A 12345');
      expect(PlateOnnxRecognizer.formatTrPlate('06BJZ818'), '06 BJZ 818');
      expect(PlateOnnxRecognizer.formatTrPlate('34UUE62'), '34 UUE 62');
    });

    test('Sıfır düzeltmeli eşleşme varken rakamı harfe bozmaz (35 JU 888)', () {
      expect(PlateOnnxRecognizer.formatTrPlate('35JU888'), '35 JU 888');
    });

    test('Yaygın OCR karakter karışıklıklarını (0/O, 1/I, 8/B) düzeltir', () {
      expect(PlateOnnxRecognizer.formatTrPlate('34N8L3O4'), '34 NBL 304');
      expect(PlateOnnxRecognizer.formatTrPlate('O6BJZ8I8'), '06 BJZ 818');
    });

    test('Sol mavi TR şeridinden sızan karakterleri temizler', () {
      expect(PlateOnnxRecognizer.formatTrPlate('TR34NBL304'), '34 NBL 304');
      expect(PlateOnnxRecognizer.formatTrPlate('R34NBL304'), '34 NBL 304');
    });

    test('Geçersiz il kodlarını ve plaka olmayan metinleri reddeder', () {
      expect(PlateOnnxRecognizer.formatTrPlate('00ABC123'), isNull);
      expect(PlateOnnxRecognizer.formatTrPlate('82ABC123'), isNull);
      expect(PlateOnnxRecognizer.formatTrPlate('99NBL304'), isNull);
      expect(PlateOnnxRecognizer.formatTrPlate('CAMERA01'), isNull);
      expect(PlateOnnxRecognizer.formatTrPlate('197005'), isNull);
    });

    test('CCT-S [1, 10, 37] logit tensörünü doğru çözümler', () {
      const target = '34NBL304__';
      final logits = List<double>.filled(10 * 37, -5.0);
      for (var slot = 0; slot < 10; slot++) {
        final idx = PlateOnnxRecognizer.ocrAlphabet.indexOf(target[slot]);
        logits[slot * 37 + idx] = 12.0;
      }
      final (raw, prob) = PlateOnnxRecognizer.decodeOcrLogits(logits);
      expect(raw, '34NBL304');
      expect(prob, greaterThan(0.99));
      expect(PlateOnnxRecognizer.formatTrPlate(raw), '34 NBL 304');
    });

    test('YOLOv9t [N, 7] kutularını kaynak çözünürlüğe ölçekler ve sıralar', () {
      final flat = <double>[
        0, 38.4, 76.8, 115.2, 153.6, 0, 0.42, // düşük güven
        0, 96.0, 192.0, 192.0, 230.4, 0, 0.88, // yüksek güven
        0, 10.0, 10.0, 12.0, 12.0, 0, 0.95, // çok küçük gürültü -> elenmeli
        0, 50.0, 50.0, 150.0, 90.0, 0, 0.05, // eşik altı -> elenmeli
      ];
      final boxes = PlateOnnxRecognizer.parseYoloOutput(
        flat,
        origW: 1280,
        origH: 720,
      );
      expect(boxes.length, 2);
      expect(boxes.first.confidence, closeTo(0.88, 1e-5));
      expect(boxes.first.x1, closeTo(320.0, 1e-3));
      expect(boxes.first.y1, closeTo(360.0, 1e-3));
      expect(boxes.first.x2, closeTo(640.0, 1e-3));
      expect(boxes.first.y2, closeTo(432.0, 1e-3));
    });
  });

  testWidgets('PlateLiveBoxOverlay dar ve geniş ekranlarda taşma yapmadan çizilir', (tester) async {
    final overlay = PlateLiveOverlay(
      cameraId: 1,
      plate: '34 NBL 304',
      normalizedBox: const Rect.fromLTRB(0.15, 0.45, 0.42, 0.62),
      confidence: 0.94,
      sourceAspectRatio: 16 / 9,
      detectedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 190,
              height: 110,
              child: PlateLiveBoxOverlay(
                overlay: overlay,
                decisionType: PlateDecisionType.acildi,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('34 NBL 304'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
