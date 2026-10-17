// Telefon bildirimi (Platform Faz 3b-B) mesajlaşma katmanı soyutlaması — docs/PLATFORM_BELGELER.md B8.
//
// [PushMessagingGateway] işletim sistemi izni, FCM kayıt jetonu ve gelen bildirim akışlarını tek arayüzde
// toplar. Gerçek gerçekleştirme `push_firebase_gateway.dart` içindeki FirebasePushGateway'dir; testler sahte
// gateway kullanır (Firebase GEREKMEZ). Bu dosya Firebase paketlerini içe AKTARMAZ.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';

abstract class PushMessagingGateway {
  /// Sunucuya bildirilen platform: `android` | `ios`.
  String get platform;

  /// Bir kez, başlatmada: iOS ön plan sunumunu kapatır (ön planda sistem bildirimi gösterilmez, B8).
  Future<void> init();

  /// İzni SORMADAN güncel durumu okur.
  Future<PushPermission> permissionStatus();

  /// İzin penceresini açar (Android 13+ `POST_NOTIFICATIONS` dahil). Yalnız bağlam içinde çağrılır.
  Future<PushPermission> requestPermission();

  /// FCM kayıt jetonu; alınamazsa (iOS'ta APNs jetonu henüz hazır değil, ağ yok) null.
  Future<String?> getToken();

  /// Jeton yenilendi (yeni jeton değeri; içerik günlüğe yazılmaz).
  Stream<String> get onTokenRefresh;

  /// Uygulama ön plandayken gelen bildirim.
  Stream<PushMessage> get onMessage;

  /// Uygulama ARKA PLANDAYKEN gelen bildirime dokunuldu.
  Stream<PushMessage> get onMessageOpenedApp;

  /// Uygulama KAPALIYKEN dokunulup açıldıysa o bildirim (bir kez tüketilir); yoksa null.
  Future<PushMessage?> getInitialMessage();

  /// FCM jetonunu geçersiz kılar (çıkış / cihazı kaldırma).
  Future<void> deleteToken();

  /// Uygulamanın sistem ayarları sayfasını açar (kalıcı ret sonrası izin için).
  Future<bool> openSystemSettings();
}

/// Telefon bildirimi bu platformda desteklenir mi? Yalnız Android ve iOS: web, Windows, macOS ve Linux'ta
/// Firebase HİÇ başlatılmaz (mevcut derlemeler ve davranış değişmez).
bool pushPlatformSupported({bool? isWeb, TargetPlatform? platform}) {
  if (isWeb ?? kIsWeb) return false;
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.android || target == TargetPlatform.iOS;
}
