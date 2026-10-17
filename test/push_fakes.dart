// Telefon bildirimi (Faz 3b-B) testlerinin ortak sahteleri: Firebase GEREKMEZ.
//
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
import 'dart:async';

import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_api.dart';
import 'package:site_kapi_kontrol/services/push_gateway.dart';
import 'package:site_kapi_kontrol/services/push_store.dart';

/// Olay sırası (gateway + API ortak): "çıkışta sıra" ve "hesap değişimi" testleri bu listeye bakar.
typedef PushEventLog = List<String>;

class FakePushGateway implements PushMessagingGateway {
  FakePushGateway(
    this.events, {
    this.platform = 'android',
    this.permission = PushPermission.granted,
    this.token = 'fcm-token-1',
  });

  final PushEventLog events;

  @override
  String platform;

  /// Güncel izin ([permissionStatus]).
  PushPermission permission;

  /// [requestPermission] sonrası izin; null ise değişmez.
  PushPermission? permissionAfterRequest;

  String? token;
  Object? deleteTokenError;
  PushMessage? initial;
  bool settingsOpened = false;
  bool openSettingsResult = true;

  int initCalls = 0;
  int permissionChecks = 0;
  int requestCalls = 0;
  int getTokenCalls = 0;
  int deleteTokenCalls = 0;
  int initialCalls = 0;

  final StreamController<String> refreshController = StreamController<String>.broadcast();
  final StreamController<PushMessage> messageController = StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> openedController = StreamController<PushMessage>.broadcast();

  @override
  Future<void> init() async => initCalls++;

  @override
  Future<PushPermission> permissionStatus() async {
    permissionChecks++;
    return permission;
  }

  @override
  Future<PushPermission> requestPermission() async {
    requestCalls++;
    events.add('requestPermission');
    final next = permissionAfterRequest;
    if (next != null) permission = next;
    return permission;
  }

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refreshController.stream;

  @override
  Stream<PushMessage> get onMessage => messageController.stream;

  @override
  Stream<PushMessage> get onMessageOpenedApp => openedController.stream;

  @override
  Future<PushMessage?> getInitialMessage() async {
    initialCalls++;
    final message = initial;
    initial = null; // bir kez tüketilir
    return message;
  }

  @override
  Future<void> deleteToken() async {
    deleteTokenCalls++;
    events.add('deleteToken');
    final error = deleteTokenError;
    if (error != null) throw error;
  }

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened = true;
    return openSettingsResult;
  }

  Future<void> close() async {
    await refreshController.close();
    await messageController.close();
    await openedController.close();
  }
}

/// Uçları kaydeden sahte [PushApi]. Kayıtlar ÇAĞRI ANINDA (ilk `await`ten önce) yazılır: "silme isteği oturum
/// belirteci silinmeden önce yola çıktı mı" bununla ölçülür.
class FakePushApi extends PushApi {
  FakePushApi(this.events) : super(baseUrl: 'http://push.test');

  final PushEventLog events;

  /// Çağrı anında oturumun hâlâ açık olup olmadığını görmek için (çıkış sırası testi).
  AuthService? watchAuth;

  final List<Map<String, Object?>> registers = <Map<String, Object?>>[];
  final List<({String token, String installId, bool sessionPresent})> deletes =
      <({String token, String installId, bool sessionPresent})>[];
  final List<Map<String, Object>> updates = <Map<String, Object>>[];
  int listCalls = 0;
  int prefsCalls = 0;
  int testCalls = 0;

  Object? registerError;
  Object? deleteError;
  Object? listError;
  Object? prefsError;
  Object? updateError;
  Object? testError;
  Completer<void>? deleteGate;
  Completer<void>? registerGate;
  Completer<void>? prefsGate;
  Completer<void>? updateGate;

  PushPreferences prefs = const PushPreferences(available: true);
  List<PushDevice> devices = <PushDevice>[];
  PushTestResult testResult = const PushTestResult(sent: 1, failed: 0);

  @override
  Future<PushRegistration> registerDevice({
    required String token,
    required String installId,
    required String platform,
    required String fcmToken,
    String? appVersion,
    required bool notificationsEnabled,
  }) async {
    events.add('register:$token');
    registers.add(<String, Object?>{
      'token': token,
      'install_id': installId,
      'platform': platform,
      'fcm': fcmToken,
      'app_version': appVersion,
      'enabled': notificationsEnabled,
    });
    final gate = registerGate;
    if (gate != null) await gate.future;
    final error = registerError;
    if (error != null) throw error;
    if (!devices.any((d) => d.installId == installId)) {
      devices = <PushDevice>[
        PushDevice(
          installId: installId,
          platform: platform,
          appVersion: appVersion,
          lastSeenAt: DateTime.utc(2026, 10, 17, 9),
        ),
        ...devices,
      ];
    }
    return (deviceId: 1, pushAvailable: true);
  }

  @override
  Future<void> deleteDevice({
    required String token,
    required String installId,
    Duration? timeout,
  }) async {
    events.add('delete:$token');
    deletes.add((token: token, installId: installId, sessionPresent: watchAuth?.session != null));
    final gate = deleteGate;
    if (gate != null) await gate.future;
    final error = deleteError;
    if (error != null) throw error;
    devices = <PushDevice>[
      for (final d in devices)
        if (d.installId != installId) d,
    ];
  }

  @override
  Future<List<PushDevice>> listDevices({required String token}) async {
    listCalls++;
    final error = listError;
    if (error != null) throw error;
    return List<PushDevice>.of(devices);
  }

  @override
  Future<PushTestResult> sendTest({required String token}) async {
    testCalls++;
    final error = testError;
    if (error != null) throw error;
    return testResult;
  }

  @override
  Future<PushPreferences> getPreferences({required String token}) async {
    prefsCalls++;
    final gate = prefsGate;
    if (gate != null) await gate.future;
    final error = prefsError;
    if (error != null) throw error;
    return prefs;
  }

  @override
  Future<PushPreferences> updatePreferences({
    required String token,
    required PushPreferencesPatch patch,
    required PushPreferences current,
  }) async {
    updates.add(patch.toJson());
    final gate = updateGate;
    if (gate != null) await gate.future;
    final error = updateError;
    if (error != null) throw error;
    prefs = patch.applyTo(prefs);
    return prefs;
  }
}

UserSession pushSession({int id = 5, String token = 'tok-A', UserRole role = UserRole.apartmentOwner}) =>
    UserSession(
      id: id,
      fullName: 'Ali Veli',
      email: 'ali$id@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: token,
    );

/// Oturumu testten sürülen [AuthService] (hesap değişimi, oturum yokken bekletme). Gerçek `logout` kancası için
/// gerçek [AuthService] kullanılır.
class SwitchableAuth extends AuthService {
  SwitchableAuth([this._current]) : super(api: AuthApi(baseUrl: 'http://push.test'));

  UserSession? _current;
  int refreshCalls = 0;

  @override
  UserSession? get session => _current;

  void switchTo(UserSession? next) {
    _current = next;
    notifyListeners();
  }

  @override
  Future<void> refreshSession({bool force = false}) async => refreshCalls++;
}

/// Mikro görevlerin ve kısa zamanlayıcıların bitmesini bekler (gerçek zaman; `test()` içinde).
Future<void> pushSettle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Kullanıcının bu cihazda telefon bildirimini AÇIKÇA açmış olduğu durum (açık rıza işareti).
Future<void> pushConsent(int userId) => PushLocalStore().setEnabledHere(userId, true);
