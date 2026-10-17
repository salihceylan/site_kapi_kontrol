// Telefon bildirimi (Faz 3b-B) — FirebasePushGateway çağrı sırası ve izin eşlemesi (sahte FcmClient; Firebase
// GEREKMEZ). iOS eklentisi APNs kaydını yalnız otomatik başlatma AÇIKKEN ister: jeton alınırken önce açılır, sonra
// APNs beklenir; silinirken önce kapatılır, sonra jeton silinir. Android 13 öncesinde "denied" kalıcı rettir.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/push_firebase_gateway.dart';

class _FakeFcm implements FcmClient {
  final List<String> calls = <String>[];
  AuthorizationStatus status = AuthorizationStatus.authorized;
  AuthorizationStatus? afterRequest;
  int? sdk;
  int apnsReadyAfter = 0; // kaçıncı okumada APNs jetonu hazır (0: hemen)
  bool apnsNever = false;
  int _apnsReads = 0;
  bool autoInit = false;
  Object? autoInitError;
  Object? deleteError;
  Map<String, Object?>? initial;
  final StreamController<Map<String, Object?>> message = StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> opened = StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<AuthorizationStatus> getAuthorizationStatus() async {
    calls.add('status');
    return status;
  }

  @override
  Future<AuthorizationStatus> requestPermission() async {
    calls.add('request');
    if (afterRequest != null) status = afterRequest!;
    return status;
  }

  @override
  Future<String?> getApnsToken() async {
    calls.add('apns');
    _apnsReads++;
    // Gerçek eklenti gibi: otomatik başlatma kapalıyken APNs kaydı hiç istenmez, jeton gelmez.
    if (apnsNever || !autoInit) return null;
    return _apnsReads > apnsReadyAfter ? 'apns' : null;
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) async {
    calls.add('autoInit:$enabled');
    final error = autoInitError;
    if (error != null) throw error;
    autoInit = enabled;
  }

  @override
  Future<String?> getToken() async {
    calls.add('getToken');
    return 'fcm';
  }

  @override
  Future<void> deleteToken() async {
    calls.add('deleteToken');
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Stream<Map<String, Object?>> get onMessage => message.stream;

  @override
  Stream<Map<String, Object?>> get onMessageOpenedApp => opened.stream;

  @override
  Future<Map<String, Object?>?> getInitialMessage() async => initial;

  @override
  Future<void> disableForegroundPresentation() async => calls.add('noForeground');

  @override
  Future<bool> openAppSettings() async {
    calls.add('settings');
    return true;
  }

  @override
  Future<int?> androidSdkInt() async {
    calls.add('sdk');
    return sdk;
  }
}

FirebasePushGateway _gateway(_FakeFcm fcm, {required bool ios}) => FirebasePushGateway(
  fcm,
  isIos: ios,
  apnsWait: const Duration(milliseconds: 200),
  apnsPoll: const Duration(milliseconds: 5),
);

void main() {
  group('iOS jeton sırası', () {
    test('getToken: otomatik başlatma APNs beklemesinden ÖNCE açılır; APNs gelince FCM jetonu alınır', () async {
      final fcm = _FakeFcm()..apnsReadyAfter = 2;
      final token = await _gateway(fcm, ios: true).getToken();
      expect(token, 'fcm');
      expect(fcm.calls.first, 'autoInit:true');
      expect(fcm.calls.indexOf('autoInit:true'), lessThan(fcm.calls.indexOf('apns')));
      expect(fcm.calls.last, 'getToken');
      expect(fcm.calls.where((c) => c == 'apns'), hasLength(3));
    });

    test('bir kez çıkış yapmış cihaz (otomatik başlatma kapalı) yeniden kaydolabilir', () async {
      final fcm = _FakeFcm();
      final gateway = _gateway(fcm, ios: true);
      expect(await gateway.getToken(), 'fcm');
      await gateway.deleteToken();
      expect(fcm.autoInit, isFalse);
      fcm.calls.clear();
      expect(await gateway.getToken(), 'fcm', reason: 'APNs kaydı yeniden istenir');
      expect(fcm.calls.first, 'autoInit:true');
    });

    test('APNs hiç gelmezse süre dolunca null (sonra yeniden denenir); FCM jetonu istenmez', () async {
      final fcm = _FakeFcm()..apnsNever = true;
      expect(await _gateway(fcm, ios: true).getToken(), isNull);
      expect(fcm.calls, isNot(contains('getToken')));
    });

    test('Android: APNs beklenmez, yine önce otomatik başlatma', () async {
      final fcm = _FakeFcm();
      expect(await _gateway(fcm, ios: false).getToken(), 'fcm');
      expect(fcm.calls, <String>['autoInit:true', 'getToken']);
    });
  });

  group('silme sırası', () {
    test('deleteToken: ÖNCE otomatik başlatma kapatılır, sonra jeton silinir', () async {
      final fcm = _FakeFcm();
      await _gateway(fcm, ios: true).deleteToken();
      expect(fcm.calls, <String>['autoInit:false', 'deleteToken']);
    });

    test('otomatik başlatma kapatılamasa da jeton silinir; silme hatası çağırana gider', () async {
      final fcm = _FakeFcm()..autoInitError = Exception('x');
      await _gateway(fcm, ios: false).deleteToken();
      expect(fcm.calls, <String>['autoInit:false', 'deleteToken']);
      fcm
        ..autoInitError = null
        ..deleteError = Exception('çevrimdışı');
      await expectLater(_gateway(fcm, ios: false).deleteToken(), throwsException);
    });
  });

  group('izin eşlemesi', () {
    Future<PushPermission> status(AuthorizationStatus s, {required bool ios, int? sdk}) =>
        _gateway(_FakeFcm()
          ..status = s
          ..sdk = sdk, ios: ios).permissionStatus();

    test('authorized / provisional -> granted; notDetermined; deniedPermanently -> kalıcı', () async {
      expect(await status(AuthorizationStatus.authorized, ios: false), PushPermission.granted);
      expect(await status(AuthorizationStatus.provisional, ios: true), PushPermission.granted);
      expect(await status(AuthorizationStatus.notDetermined, ios: true), PushPermission.notDetermined);
      expect(await status(AuthorizationStatus.deniedPermanently, ios: false, sdk: 34), PushPermission.permanentlyDenied);
    });

    test('denied: iOS ve Android < 33 KALICI (yalnız ayarlar); Android 13+ yeniden sorulabilir', () async {
      expect(await status(AuthorizationStatus.denied, ios: true), PushPermission.permanentlyDenied);
      expect(await status(AuthorizationStatus.denied, ios: false, sdk: 32), PushPermission.permanentlyDenied);
      expect(await status(AuthorizationStatus.denied, ios: false, sdk: 26), PushPermission.permanentlyDenied);
      expect(await status(AuthorizationStatus.denied, ios: false, sdk: 33), PushPermission.denied);
      expect(await status(AuthorizationStatus.denied, ios: false), PushPermission.denied, reason: 'sürüm okunamazsa');
    });

    test('requestPermission sonucu da eşlenir; API düzeyi bir kez okunur', () async {
      final fcm = _FakeFcm()
        ..status = AuthorizationStatus.notDetermined
        ..afterRequest = AuthorizationStatus.denied
        ..sdk = 30;
      final gateway = _gateway(fcm, ios: false);
      expect(await gateway.requestPermission(), PushPermission.permanentlyDenied);
      expect(await gateway.permissionStatus(), PushPermission.permanentlyDenied);
      expect(fcm.calls.where((c) => c == 'sdk'), hasLength(1));
    });
  });

  group('başlatma ve mesajlar', () {
    test('init: yalnız iOS\'ta ön plan sunumu kapatılır', () async {
      final ios = _FakeFcm();
      await _gateway(ios, ios: true).init();
      expect(ios.calls, <String>['noForeground']);
      final android = _FakeFcm();
      await _gateway(android, ios: false).init();
      expect(android.calls, isEmpty);
    });

    test('yük data haritasına indirgenir; kapalıyken dokunulan bildirim okunur; platform adı', () async {
      final fcm = _FakeFcm()..initial = <String, Object?>{'type': 'announcement', 'announcement_id': '5'};
      final gateway = _gateway(fcm, ios: false);
      expect(gateway.platform, 'android');
      expect(_gateway(fcm, ios: true).platform, 'ios');
      expect((await gateway.getInitialMessage())!.announcementId, 5);
      final got = <int?>[];
      final sub = gateway.onMessageOpenedApp.listen((m) => got.add(m.announcementId));
      fcm.opened.add(<String, Object?>{'type': 'announcement', 'announcement_id': '9'});
      await Future<void>.delayed(Duration.zero);
      expect(got, <int?>[9]);
      await sub.cancel();
      expect(await gateway.openSystemSettings(), isTrue);
    });
  });
}
