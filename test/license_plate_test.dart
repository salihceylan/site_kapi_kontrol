import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';

void main() {
  group('LicensePlateBadge format ve ayrıştırma testleri', () {
    test('Standart Türk plakası formatı (35 EA 8875)', () {
      expect(LicensePlateBadge.format('35ea8875'), '35 EA 8875');
      expect(LicensePlateBadge.format('35 EA 8875'), '35 EA 8875');
      expect(LicensePlateBadge.format('35-EA-8875'), '35 EA 8875');

      final parts = LicensePlateBadge.parseTrPlate('35 EA 8875');
      expect(parts, isNotNull);
      expect(parts!.city, '35');
      expect(parts.letters, 'EA');
      expect(parts.digits, '8875');
    });

    test('4 harfli plaka formatı (06 TEST 001)', () {
      expect(LicensePlateBadge.format('06test001'), '06 TEST 001');

      final parts = LicensePlateBadge.parseTrPlate('06 TEST 001');
      expect(parts, isNotNull);
      expect(parts!.city, '06');
      expect(parts.letters, 'TEST');
      expect(parts.digits, '001');
    });

    test('Farklı standart plaka formatları (34 CAS 934, 35 T 5771, 06 BJZ 818)', () {
      final p1 = LicensePlateBadge.parseTrPlate('34CAS934');
      expect(p1?.city, '34');
      expect(p1?.letters, 'CAS');
      expect(p1?.digits, '934');

      final p2 = LicensePlateBadge.parseTrPlate('35 T 5771');
      expect(p2?.city, '35');
      expect(p2?.letters, 'T');
      expect(p2?.digits, '5771');

      final p3 = LicensePlateBadge.parseTrPlate('06BJZ818');
      expect(p3?.city, '06');
      expect(p3?.letters, 'BJZ');
      expect(p3?.digits, '818');
    });

    test('Standart dışı / yabancı plaka fallback', () {
      expect(LicensePlateBadge.format('ABC 1234'), 'ABC 1234');
      expect(LicensePlateBadge.parseTrPlate('ABC 1234'), isNull);
    });
  });

  group('LicensePlateBadge Arayüz ve Boyut (Oran) Testleri', () {
    testWidgets('Standart plaka ölçüsü (152x32) ve TR / mühür bileşenleri', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LicensePlateBadge(plate: '35 EA 8875'),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(LicensePlateBadge));
      expect(size.width, 152.0);
      expect(size.height, 32.0);

      expect(find.text('TR'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
      expect(find.text('EA'), findsOneWidget);
      expect(find.text('8875'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget); // Resmi hologram mühür
    });

    testWidgets('Kompakt plaka ölçüsü (114x24)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LicensePlateBadge(plate: '06 TEST 001', compact: true),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(LicensePlateBadge));
      expect(size.width, 114.0);
      expect(size.height, 24.0);

      expect(find.text('TR'), findsOneWidget);
      expect(find.text('06'), findsOneWidget);
      expect(find.text('TEST'), findsOneWidget);
      expect(find.text('001'), findsOneWidget);
    });

    testWidgets('Column veya Expanded içinde ASLA yayılmaz / taşmaz (152x32 sabit kalır)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500, // Geniş ebeveyn
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LicensePlateBadge(plate: '35 EA 8875'),
                  Text('Açıklama metni'),
                ],
              ),
            ),
          ),
        ),
      );

      // 500 px genişliğindeki sütunda plaka yayılmamalı, tam 152 px olmalıdır!
      final size = tester.getSize(find.byType(LicensePlateBadge));
      expect(size.width, 152.0);
      expect(size.height, 32.0);
    });
  });
}
