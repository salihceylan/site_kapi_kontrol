// Telefon bildirimi (Platform Faz 3b-B) Firebase gerçekleştirmesi ve açılış başlatıcısı — B8, B9.
//
// Firebase YALNIZ Android ve iOS'ta, `try/catch` içinde başlatılır ([startPushMessaging]); web, Windows, macOS ve
// Linux'ta HİÇ çağrılmaz. `google-services.json` / `GoogleService-Info.plist` yoksa ya da başlatma başarısızsa
// push devre dışı kalır, uygulama normal çalışır. Arka plan mesaj işleyicisi (`onBackgroundMessage`) YOKTUR:
// arka planda / kapalıyken sistem `notification` yükünü kendisi gösterir. `flutter_local_notifications`
// kullanılmaz (K7); Android kanalları MainActivity.kt'de oluşturulur.
//
// FCM otomatik başlatma KAPALIDIR (Android manifesti `firebase_messaging_auto_init_enabled=false`, iOS Info.plist
// `FirebaseMessagingAutoInitEnabled=false`): kullanıcı bu cihazda telefon bildirimini açıkça açmadıkça jeton
// üretilmez, Google'a gitmez. Jeton alınırken ÖNCE otomatik başlatma açılır (iOS eklentisi APNs kaydını ancak bu
// açıkken ister), çıkışta / cihaz kaldırılınca ÖNCE kapatılır sonra jeton silinir.
//
// Firebase çağrıları ince bir adaptörün ([FcmClient]) arkasındadır: çağrı sırası birim testle doğrulanır.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:permission_handler/permission_handler.dart' as permissions show openAppSettings;
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/push_gateway.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';

/// `FirebaseMessaging`in kullanılan yüzü (yük `data` haritasına indirgenir; başlık / gövde tutulmaz).
abstract class FcmClient {
  Future<AuthorizationStatus> getAuthorizationStatus();
  Future<AuthorizationStatus> requestPermission();
  Future<String?> getApnsToken();
  Future<void> setAutoInitEnabled(bool enabled);
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  Stream<Map<String, Object?>> get onMessage;
  Stream<Map<String, Object?>> get onMessageOpenedApp;
  Future<Map<String, Object?>?> getInitialMessage();

  /// iOS: ön planda sistem bildirimi gösterilmez.
  Future<void> disableForegroundPresentation();
  Future<bool> openAppSettings();

  /// Android API düzeyi (iOS'ta / okunamazsa null).
  Future<int?> androidSdkInt();
}

/// Gerçek [FcmClient] (Firebase başlatıldıktan SONRA kurulur).
class FirebaseFcmClient implements FcmClient {
  FirebaseFcmClient({FirebaseMessaging? messaging}) : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// MainActivity.kt: `sdkInt` (Android 13 öncesinde bildirim izni yalnız ayarlardan açılır).
  static const MethodChannel _channel = MethodChannel('tr.com.gudeteknoloji.siteyonetim/push');

  @override
  Future<AuthorizationStatus> getAuthorizationStatus() async =>
      (await _messaging.getNotificationSettings()).authorizationStatus;

  @override
  Future<AuthorizationStatus> requestPermission() async =>
      // Rozet sayısı gönderilmez (B5): rozet izni istenmez.
      (await _messaging.requestPermission(alert: true, badge: false, sound: true)).authorizationStatus;

  @override
  Future<String?> getApnsToken() => _messaging.getAPNSToken();

  @override
  Future<void> setAutoInitEnabled(bool enabled) => _messaging.setAutoInitEnabled(enabled);

  // Sunucu FCM HTTP v1 `message.token` (kayıt jetonu) ile gönderir (B1); FlutterFire 17'nin FID tabanlı
  // `register()` yolu bu sözleşmede kullanılmaz.
  @override
  // ignore: deprecated_member_use
  Future<String?> getToken() => _messaging.getToken();

  @override
  // ignore: deprecated_member_use
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, Object?>> get onMessage => FirebaseMessaging.onMessage.map(_data);

  @override
  Stream<Map<String, Object?>> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp.map(_data);

  @override
  Future<Map<String, Object?>?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _data(message);
  }

  @override
  Future<void> disableForegroundPresentation() =>
      _messaging.setForegroundNotificationPresentationOptions(alert: false, badge: false, sound: false);

  @override
  Future<bool> openAppSettings() => permissions.openAppSettings();

  @override
  Future<int?> androidSdkInt() async {
    try {
      return await _channel.invokeMethod<int>('sdkInt');
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> _data(RemoteMessage message) => Map<String, Object?>.from(message.data);
}

class FirebasePushGateway implements PushMessagingGateway {
  FirebasePushGateway(
    this._client, {
    required bool isIos,
    this.apnsWait = const Duration(seconds: 10),
    this.apnsPoll = const Duration(seconds: 1),
  }) : _isIos = isIos;

  final FcmClient _client;
  final bool _isIos;

  /// iOS'ta FCM jetonu APNs jetonu hazır olmadan alınamaz: en çok bu kadar beklenir (sonra null, yeniden denenir).
  final Duration apnsWait;
  final Duration apnsPoll;

  int? _sdkInt;
  bool _sdkRead = false;

  @override
  String get platform => _isIos ? 'ios' : 'android';

  @override
  Future<void> init() async {
    // Ön planda sistem bildirimi GÖSTERİLMEZ: uygulama içi şerit / SnackBar yeterlidir (B8).
    if (_isIos) await _client.disableForegroundPresentation();
  }

  Future<int?> _androidSdk() async {
    if (!_sdkRead) {
      _sdkInt = await _client.androidSdkInt();
      _sdkRead = true;
    }
    return _sdkInt;
  }

  Future<PushPermission> _map(AuthorizationStatus status) async {
    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return PushPermission.granted;
      case AuthorizationStatus.notDetermined:
        return PushPermission.notDetermined;
      case AuthorizationStatus.deniedPermanently:
        return PushPermission.permanentlyDenied;
      case AuthorizationStatus.denied:
        // iOS bir kez reddedilen izni bir daha sormaz; Android 13 öncesinde çalışma zamanı izni yoktur (kapalıysa
        // ayarlardan kapatılmıştır). İkisinde de yalnız telefon ayarlarından açılır.
        if (_isIos) return PushPermission.permanentlyDenied;
        final sdk = await _androidSdk();
        return sdk != null && sdk < 33 ? PushPermission.permanentlyDenied : PushPermission.denied;
    }
  }

  @override
  Future<PushPermission> permissionStatus() async => _map(await _client.getAuthorizationStatus());

  @override
  Future<PushPermission> requestPermission() async => _map(await _client.requestPermission());

  @override
  Future<String?> getToken() async {
    // ÖNCE otomatik başlatma: iOS eklentisi APNs kaydını yalnız bu açıkken ister (kapalıyken APNs jetonu hiç
    // gelmez ve kayıt hiçbir zaman tamamlanmaz).
    await _client.setAutoInitEnabled(true);
    if (_isIos) {
      final deadline = DateTime.now().add(apnsWait);
      while ((await _client.getApnsToken()) == null) {
        if (!DateTime.now().isBefore(deadline)) return null;
        await Future<void>.delayed(apnsPoll);
      }
    }
    return _client.getToken();
  }

  @override
  Stream<String> get onTokenRefresh => _client.onTokenRefresh;

  @override
  Stream<PushMessage> get onMessage => _client.onMessage.map(PushMessage.new);

  @override
  Stream<PushMessage> get onMessageOpenedApp => _client.onMessageOpenedApp.map(PushMessage.new);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final data = await _client.getInitialMessage();
    return data == null ? null : PushMessage(data);
  }

  @override
  Future<void> deleteToken() async {
    // ÖNCE otomatik başlatma kapatılır: silinen jetonun yerine kendiliğinden yenisi üretilmesin.
    try {
      await _client.setAutoInitEnabled(false);
    } catch (_) {
      // Kapatılamasa da jeton silinir.
    }
    await _client.deleteToken();
  }

  @override
  Future<bool> openSystemSettings() => _client.openAppSettings();
}

/// Açılışta (lib/main.dart) BİR kez çağrılır; açılışı beklemez. Dönüş: push başlatıldı mı.
///
/// Platform Android/iOS değilse Firebase'e HİÇ dokunulmaz. Başlatma başarısızsa (yapılandırma dosyası yok, ağ,
/// eklenti hatası) push devre dışı kalır ve durum "yapılandırılmamış" olur; hata uygulamaya yansımaz. Parametreler
/// yalnız testler içindir (platform kapısı, sahte başlatma ve gateway).
Future<bool> startPushMessaging({
  PushService? service,
  bool Function()? isSupportedPlatform,
  Future<void> Function()? initializeFirebase,
  PushMessagingGateway Function()? createGateway,
  Duration initTimeout = const Duration(seconds: 15),
}) async {
  final target = service ?? PushService.instance;
  final supported = (isSupportedPlatform ?? pushPlatformSupported)();
  if (!supported) return false;
  target.markStarting();
  try {
    final initialize = initializeFirebase ?? () => Firebase.initializeApp();
    await initialize().timeout(initTimeout);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Telefon bildirimi devre dışı: Firebase başlatılamadı (${e.runtimeType}).');
    }
    target.markStartFailed();
    return false;
  }
  try {
    final gateway =
        (createGateway ??
            () => FirebasePushGateway(
              FirebaseFcmClient(),
              isIos: defaultTargetPlatform == TargetPlatform.iOS,
            ))();
    await target.start(gateway);
    return true;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Telefon bildirimi devre dışı: başlatma hatası (${e.runtimeType}).');
    }
    target.markStartFailed();
    return false;
  }
}
