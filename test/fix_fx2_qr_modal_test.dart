import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';

class _QrAuth extends AuthService {
  _QrAuth(this.status) : super(api: AuthApi(baseUrl: 'http://localhost'));

  Map<String, dynamic> status;
  int statusCalls = 0;
  int tokenCalls = 0;

  @override
  Future<(Map<String, dynamic>?, String?)> requestDoorQrToken(
    int doorId, {
    Map<String, dynamic>? location,
  }) async {
    tokenCalls++;
    return (<String, dynamic>{'token': 'tok-$tokenCalls', 'expires_in_seconds': 30}, null);
  }

  @override
  Future<(Map<String, dynamic>?, String?)> getDoorQrStatus(String qrToken) async {
    statusCalls++;
    return (status, null);
  }

  @override
  Future<(Map<String, dynamic>?, String?)> revokeMyDoorQr(int doorId) async => (null, null);
}

DoorRecord _door() => DoorRecord(
      id: 7,
      siteCode: 101,
      siteName: 'Güneş Sitesi Çok Uzun İsimli Konutları 2. Etap',
      doorName: 'A Blok Giriş Kapısı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'ESP32_WROOM_T1',
      mqttSiteId: 101,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _openModal(WidgetTester tester, _QrAuth auth) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DynamicQrPassModal(door: _door(), authService: auth),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pump(); // diyalog
  await tester.pump(const Duration(milliseconds: 50)); // token isteği tamamlanır
}

void main() {
  setUp(() {
    // flutter_tts eklentisi testte yok: kanal çağrılarını sessizce yanıtla.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
  });

  testWidgets('ACCESS_REVOKED: neden gösterilir, yoklama durur, kod soluklaşır (320 px taşmasız)', (tester) async {
    final auth = _QrAuth({'last_denial_reason': 'ACCESS_REVOKED', 'last_denied_at': '2026-05-01T10:00:00Z'});
    await _openModal(tester, auth);
    expect(auth.tokenCalls, 1);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 50));

    // Başlık + rozet
    expect(find.text('Kapı Yetkisi Yok'), findsNWidgets(2));
    expect(find.textContaining('yetkiniz kaldırılmış'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final callsAfterDenial = auth.statusCalls;
    await tester.pump(const Duration(seconds: 3));
    expect(auth.statusCalls, callsAfterDenial, reason: 'kalıcı retten sonra yoklama durur');

    // Yeni kod isteği ret durumunu temizler
    auth.status = {};
    await tester.tap(find.text('Kodu Yenile'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(auth.tokenCalls, 2);
    expect(find.text('Kapı Yetkisi Yok'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR_DISABLED sunucu ret koduna uygun anlaşılır mesaj gösterir', (tester) async {
    final auth = _QrAuth({'last_denial_reason': 'QR_DISABLED', 'last_denied_at': 'a'});
    await _openModal(tester, auth);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Karekod Girişi Kapalı'), findsNWidgets(2));
    expect(find.text('Bu sitede QR ile giriş kapalı.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PULSE_FAILED geçicidir: uyarı bir süre görünür, kod geçerli kalır, yoklama sürer', (tester) async {
    final auth = _QrAuth({'last_denial_reason': 'PULSE_FAILED', 'last_denied_at': 'x'});
    await _openModal(tester, auth);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Kapı Komutu Gönderilemedi'), findsNWidgets(2));
    expect(find.textContaining('tekrar gösterin'), findsOneWidget);

    final callsBefore = auth.statusCalls;
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Kapı Komutu Gönderilemedi'), findsNothing, reason: 'uyarı süresi doldu');
    expect(auth.statusCalls, greaterThan(callsBefore), reason: 'yoklama sürer');

    // Aynı ret olayı (aynı last_denied_at) tekrar tekrar gösterilmez
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Kapı Komutu Gönderilemedi'), findsNothing);
    expect(tester.takeException(), isNull);

    // Yeni bir ret olayı (farklı zaman) yeniden gösterilir
    auth.status = {'last_denial_reason': 'PULSE_FAILED', 'last_denied_at': 'y'};
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Kapı Komutu Gönderilemedi'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('EXPIRED_TOKEN süre dolmuş durumuna geçirir', (tester) async {
    final auth = _QrAuth({'last_denial_reason': 'EXPIRED_TOKEN', 'last_denied_at': 'z'});
    await _openModal(tester, auth);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Yeni QR Kod Al'), findsOneWidget);
    expect(find.text('Süresi Doldu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
