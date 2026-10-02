import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';

DoorRecord _door() => DoorRecord(
      id: 7,
      siteCode: 101,
      siteName: 'Güneş Sitesi',
      doorName: 'Ana Giriş',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'ESP32_C3_TEST',
      mqttSiteId: 101,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pumpDialog(WidgetTester tester, {double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(360 * 2, 640 * 2);
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CreateGuestPassDialog(
          door: _door(),
          authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('CreateGuestPassDialog Türkçe metinler (E2E bulgusu: Türkçe karakterler eksikti)', () {
    testWidgets('başlık, alan etiketi ve düğmeler Türkçe karakterlerle yazılır', (tester) async {
      await _pumpDialog(tester);

      expect(find.text('Ana Giriş - Geçiş Linki'), findsOneWidget);
      expect(find.text('Geçiş Başlığı / Açıklama'), findsOneWidget);
      expect(find.text('Geçiş Süresi ve Türü'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);
      expect(find.text('Linki Oluştur'), findsOneWidget);

      // Eski (diyakritiksiz) metinler görünmemeli.
      expect(find.textContaining('Gecis'), findsNothing);
      expect(find.text('Iptal'), findsNothing);
      expect(find.text('Linki Olustur'), findsNothing);
    });

    testWidgets('boş başlık doğrulama mesajı Türkçe karakterlidir', (tester) async {
      await _pumpDialog(tester);

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Linki Oluştur'));
      await tester.pump();

      expect(find.text('Başlık alanı boş bırakılamaz.'), findsOneWidget);
    });

    testWidgets('küçük ekran + yazı ölçeği 1.5: taşma yok', (tester) async {
      await _pumpDialog(tester, textScale: 1.5);
      expect(tester.takeException(), isNull);
    });
  });
}
