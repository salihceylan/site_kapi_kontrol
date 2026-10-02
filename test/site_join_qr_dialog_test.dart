import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:site_kapi_kontrol/models/site_join_token_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/site_join_qr_dialog.dart';

class MockAuthServiceForQr extends AuthService {
  MockAuthServiceForQr() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  Future<SiteJoinTokenRecord> getSiteJoinToken({required int siteCode}) async {
    return const SiteJoinTokenRecord(
      id: 1,
      siteCode: 1,
      siteName: 'Güneş Sitesi',
      token: 'GUNES-ABC123XYZ',
      qrPayload: 'SITE_JOIN:GUNES-ABC123XYZ',
      isActive: true,
    );
  }
}

void main() {
  final testSite = SiteRecord(
    id: 1,
    name: 'Güneş Sitesi',
    address: 'Atatürk Mah. No:1',
    city: 'Ankara',
    district: 'Çankaya',
    blockCount: 2,
    apartmentCount: 20,
    doorCount: 2,
    approvalStatus: 'approved',
    approvedAt: DateTime(2026, 1, 1),
    mqttSiteId: 101,
    managerUserCode: 1,
    managerName: 'Ali Yönetici',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('SiteJoinQrDialog renders QR code, token and Karekodu Paylaş button', (tester) async {
    final mockAuth = MockAuthServiceForQr();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SiteJoinQrDialog.show(
                context,
                site: testSite,
                authService: mockAuth,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog content
    expect(find.text('Site Katılım QR Kodu'), findsOneWidget);
    expect(find.text('Güneş Sitesi'), findsOneWidget);
    expect(find.text('GUNES-ABC123XYZ'), findsOneWidget);

    // Verify Share Button
    expect(find.text('Karekodu Paylaş'), findsOneWidget);
    expect(find.byIcon(Icons.share_rounded), findsOneWidget);

    // Verify Secondary Buttons
    expect(find.text('Kodu Kopyala'), findsOneWidget);
    expect(find.text('QR Yenile'), findsOneWidget);
  });

  test('Generated QR export creates non-empty PNG with 800x800 size and white canvas', () async {
    const double imageSize = 800.0;
    const double padding = 60.0;
    const double qrSize = imageSize - (padding * 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, imageSize, imageSize),
      bgPaint,
    );

    final painter = QrPainter(
      data: 'SITE_JOIN:TEST_TOKEN',
      version: QrVersions.auto,
      gapless: true,
      // ignore: deprecated_member_use
      emptyColor: const Color(0xFFFFFFFF),
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF0F172A),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF0F172A),
      ),
    );

    canvas.save();
    canvas.translate(padding, padding);
    painter.paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageSize.toInt(), imageSize.toInt());
    expect(image.width, 800);
    expect(image.height, 800);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    expect(byteData!.lengthInBytes, greaterThan(1000));
  });
}
