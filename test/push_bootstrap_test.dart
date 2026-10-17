// Telefon bildirimi (Faz 3b-B) açılış başlatıcısı — platform kapısı (B8/B11): web ve masaüstünde Firebase HİÇ
// çağrılmaz; Android/iOS'ta başlatma hatası uygulamayı bozmaz, push devre dışı kalır.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/push_firebase_gateway.dart';
import 'package:site_kapi_kontrol/services/push_gateway.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';

import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PushService service;
  late FakePushGateway gateway;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = PushService(observeLifecycle: false);
    gateway = FakePushGateway(<String>[]);
  });

  tearDown(() async {
    await service.dispose();
    await gateway.close();
  });

  for (final (label, isWeb, platform) in <(String, bool, TargetPlatform)>[
    ('web', true, TargetPlatform.android),
    ('Windows', false, TargetPlatform.windows),
    ('macOS', false, TargetPlatform.macOS),
    ('Linux', false, TargetPlatform.linux),
  ]) {
    test('$label: Firebase başlatılmaz, gateway kurulmaz, push devre dışı', () async {
      var initCalls = 0;
      var gatewayCalls = 0;
      final started = await startPushMessaging(
        service: service,
        isSupportedPlatform: () => pushPlatformSupported(isWeb: isWeb, platform: platform),
        initializeFirebase: () async => initCalls++,
        createGateway: () {
          gatewayCalls++;
          return gateway;
        },
      );
      expect(started, isFalse);
      expect(initCalls, 0);
      expect(gatewayCalls, 0);
      expect(service.isSupported, isFalse);
      expect(service.startState.value, PushStartState.idle);
    });
  }

  test('varsayılan kapı (main.dart çağrısı gibi): masaüstü platformda Firebase başlatılmaz', () async {
    var initCalls = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final started = await startPushMessaging(
        service: service,
        initializeFirebase: () async => initCalls++,
        createGateway: () => gateway,
      );
      expect(started, isFalse);
      expect(initCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Android: Firebase başlatılamazsa (google-services.json yok) hata yutulur, push devre dışı', () async {
    var gatewayCalls = 0;
    final started = await startPushMessaging(
      service: service,
      isSupportedPlatform: () => pushPlatformSupported(isWeb: false, platform: TargetPlatform.android),
      initializeFirebase: () async => throw Exception('no-app'),
      createGateway: () {
        gatewayCalls++;
        return gateway;
      },
    );
    expect(started, isFalse);
    expect(gatewayCalls, 0);
    expect(service.isSupported, isFalse);
    expect(service.startState.value, PushStartState.failed, reason: 'ekran "bu sürümde yok" der');
  });

  test('Android / iOS: başlatma başarılıysa gateway kurulur ve kapalıyken dokunulan bildirim okunur', () async {
    for (final platform in <TargetPlatform>[TargetPlatform.android, TargetPlatform.iOS]) {
      final svc = PushService(observeLifecycle: false);
      final gw = FakePushGateway(<String>[]);
      var initCalls = 0;
      final started = await startPushMessaging(
        service: svc,
        isSupportedPlatform: () => pushPlatformSupported(isWeb: false, platform: platform),
        initializeFirebase: () async => initCalls++,
        createGateway: () => gw,
      );
      expect(started, isTrue, reason: '$platform');
      expect(initCalls, 1);
      expect(svc.isSupported, isTrue);
      expect(svc.startState.value, PushStartState.ready);
      expect(gw.initCalls, 1);
      expect(gw.initialCalls, 1);
      expect(gw.requestCalls, 0, reason: 'açılışta izin SORULMAZ');
      await svc.dispose();
      await gw.close();
    }
  });

  test('başlatma zaman aşımında da uygulama açılır (push devre dışı); sürerken "hazırlanıyor"', () async {
    final future = startPushMessaging(
      service: service,
      isSupportedPlatform: () => true,
      initializeFirebase: () => Future<void>.delayed(const Duration(milliseconds: 300)),
      createGateway: () => gateway,
      initTimeout: const Duration(milliseconds: 10),
    );
    expect(service.startState.value, PushStartState.starting);
    expect(await future, isFalse);
    expect(service.isSupported, isFalse);
    expect(service.startState.value, PushStartState.failed);
  });
}
