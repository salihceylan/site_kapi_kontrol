// Telefon bildirimi (Faz 3b-B) istemci akışı — docs/PLATFORM_BELGELER.md B8, B11 (Flutter maddeleri).
//
// Sahte gateway + sahte PushApi ile (Firebase GEREKMEZ): AÇIK RIZA kapısı (rıza + push_available olmadan jeton /
// kayıt yok; Android 12- varsayılan izinde bile), izin akışları (verildi / reddedildi / kalıcı reddedildi), kayıt
// tazeleme zamanlaması (jeton yenilemesi "günde bir"i delmez), çıkışta SIRA (sunucu silmesi oturum belirteci
// silinmeden önce; FCM jetonu ona bağlı olmadan), kalıcı temizlik (çevrimdışı çıkış, yeniden deneme), hesap
// değişimi (yanlış belirteç gitmez), tıklama yönlendirmesi (oturum / ana sayfa / bakım / "Güncellenen koşullar"
// kapısı beklenir; geçersiz yük yok sayılır), ön plan olayları (duyuru, test), yumuşak istem kartı koşulları.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/app_gate_state.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/services/push_store.dart' show PushLocalStore, PushRegistrationStamp;
import 'package:site_kapi_kontrol/ui/views/legal_consent_gate.dart' show LegalConsentBlock;

import 'push_fakes.dart';

const PushMessage _valid42 = PushMessage(<String, Object?>{
  'type': 'announcement',
  'announcement_id': '42',
  'site_code': '1234567890',
  'importance': 'normal',
});

/// Kayıtlı oturumla açılan GERÇEK AuthService (çıkış kancası gerçek `logout` içinden çalışsın diye).
Future<AuthService> _realAuth() async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'auth_session': jsonEncode(pushSession().toJson()),
  });
  final client = MockClient((request) async {
    if (request.url.path == '/me') {
      return http.Response(
        jsonEncode(<String, Object?>{
          'user': <String, Object?>{
            'id': 5,
            'full_name': 'Ali Veli',
            'email': 'ali5@example.com',
            'login_name': null,
            'role': 'apartment_owner',
            'is_active': true,
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('{"error":"yok","code":"NOT_FOUND"}', 404);
  });
  final auth = AuthService(
    api: AuthApi(baseUrl: 'http://push.test', client: client, retryDelay: Duration.zero),
  );
  await auth.initialize();
  await pushSettle();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PushEventLog events;
  late FakePushGateway gateway;
  late FakePushApi api;
  late DateTime clock;
  late PushService service;
  final extra = <PushService>[];

  PushService makeService({
    List<Duration> cleanupRetryDelays = const <Duration>[],
    int cleanupBlockLimit = 5,
  }) => PushService(
    store: PushLocalStore(),
    apiFactory: (_) => api,
    appVersion: () async => '1.2.3',
    now: () => clock,
    observeLifecycle: false,
    cleanupRetryDelays: cleanupRetryDelays,
    cleanupBlockLimit: cleanupBlockLimit,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    events = <String>[];
    gateway = FakePushGateway(events);
    api = FakePushApi(events);
    clock = DateTime(2026, 10, 17, 10);
    service = makeService();
  });

  tearDown(() async {
    await service.dispose();
    for (final s in extra) {
      await s.dispose();
    }
    extra.clear();
    await gateway.close();
    AppGateBlock.active.value = false;
    AppGateBlock.pendingFirstCheck.value = false;
    LegalConsentBlock.active.value = false;
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();
  Future<String?> storedInstallId() async => (await prefs()).getString(PushLocalStore.installIdKey);

  /// Rıza verilmiş, kayıtlı A hesabı.
  Future<SwitchableAuth> registeredA() async {
    await pushConsent(5);
    final auth = SwitchableAuth(pushSession());
    await service.start(gateway);
    service.attach(auth);
    await pushSettle();
    expect(api.registers, hasLength(1));
    return auth;
  }

  group('AÇIK RIZA kapısı', () {
    test('Android 12- (izin varsayılan AÇIK) ama rıza YOK: girişte jeton, kayıt, tercih isteği HİÇ yok', () async {
      gateway.permission = PushPermission.granted;
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      service.onAppResumed();
      await pushSettle();
      expect(gateway.getTokenCalls, 0, reason: 'jeton üretilmez');
      expect(api.registers, isEmpty);
      expect(api.prefsCalls, 0);
      expect(service.activeHere.value, isFalse);
      expect(await storedInstallId(), isNull, reason: 'kurulum kimliği bile üretilmez');
    });

    test('rıza VAR ama sunucuda push_available=false: jeton yok, kayıt yok; açma sonucu pushUnavailable', () async {
      await pushConsent(5);
      api.prefs = const PushPreferences(available: false);
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      expect(gateway.getTokenCalls, 0);
      expect(api.registers, isEmpty);
      expect(api.prefsCalls, 1);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.pushUnavailable);
      expect(gateway.getTokenCalls, 0);
    });

    test('rıza + push_available + izin: kayıt yapılır (platform, sürüm, izin, ayrı UUID kurulum kimliği)', () async {
      await registeredA();
      final reg = api.registers.single;
      expect(reg['token'], 'tok-A');
      expect(reg['platform'], 'android');
      expect(reg['app_version'], '1.2.3');
      expect(reg['enabled'], isTrue);
      final id = await storedInstallId();
      expect(reg['install_id'], id);
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect((await prefs()).getString('crash_reporter.install_id'), isNull, reason: 'çökme raporundan AYRI');
      expect((await prefs()).getString(PushLocalStore.stampKey), isNot(contains('fcm-token-1')));
      expect(service.activeHere.value, isTrue);
    });

    test('rıza başka kullanıcınınsa bu kullanıcı için kayıt YOK', () async {
      await pushConsent(99);
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      expect(api.registers, isEmpty);
    });

    test('duyuru alamayan roller (süper / bireysel) rıza olsa da kaydolmaz; rol değişince kayıt yapılır', () async {
      await pushConsent(5);
      final auth = SwitchableAuth(pushSession(role: UserRole.individual));
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      expect(api.registers, isEmpty);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.unsupported);
      auth.switchTo(pushSession(role: UserRole.superUser));
      await pushSettle();
      expect(api.registers, isEmpty);
      auth.switchTo(pushSession(role: UserRole.siteManager));
      await pushSettle();
      expect(api.registers, hasLength(1));
    });
  });

  group('izin akışları (bağlam içinde, "Bu cihazda aç")', () {
    test('izin zaten VAR: istem açılmaz; rıza işaretlenir, kayıt yapılır', () async {
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.registered);
      expect(gateway.requestCalls, 0);
      expect(api.registers, hasLength(1));
      expect(await PushLocalStore().isEnabledHere(5), isTrue);
    });

    test('hiç sorulmamış: izin bağlamda İSTENİR; verilirse kaydedilir', () async {
      gateway
        ..permission = PushPermission.notDetermined
        ..permissionAfterRequest = PushPermission.granted;
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.registered);
      expect(gateway.requestCalls, 1);
      expect(events.first, 'requestPermission', reason: 'önce izin, sonra kayıt');
    });

    test('REDDEDİLDİ: kayıt yok, jeton istenmez; rıza KALIR, izin sonra verilince ön plana dönüşte kaydolur', () async {
      gateway
        ..permission = PushPermission.notDetermined
        ..permissionAfterRequest = PushPermission.denied;
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.permissionDenied);
      expect(api.registers, isEmpty);
      expect(gateway.getTokenCalls, 0);
      final state = await service.deviceState(auth);
      expect(state.enabledHere, isTrue);
      expect(state.permission!.canAsk, isTrue);

      gateway.permission = PushPermission.granted; // kullanıcı ayarlardan izin verdi
      service.onAppResumed();
      await pushSettle();
      expect(api.registers, hasLength(1));
    });

    test('KALICI reddedildi: istem açılmaz, kayıt yok; ayarlar düğmesi rızayı işaretler ve ayarları açar', () async {
      gateway.permission = PushPermission.permanentlyDenied;
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.permissionPermanentlyDenied);
      expect(gateway.requestCalls, 0);
      expect(api.registers, isEmpty);
      await PushLocalStore().setEnabledHere(5, false);
      expect(await service.openSettingsToEnable(auth), isTrue);
      expect(gateway.settingsOpened, isTrue);
      expect(await PushLocalStore().isEnabledHere(5), isTrue);
    });

    test('jeton alınamazsa tokenUnavailable; sunucu hatası çağırana gider', () async {
      gateway.token = null;
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.tokenUnavailable);
      gateway.token = 'fcm-token-1';
      api.registerError = ApiException('Telefon bildirimi şu an kullanılamıyor.', statusCode: 503, code: 'PUSH_UNAVAILABLE');
      await expectLater(service.enableOnThisDevice(auth), throwsA(isA<ApiException>()));
    });

    test('gateway yok (web / masaüstü / Firebase başlatılamadı): unsupported, hiçbir çağrı yapılmaz', () async {
      final auth = SwitchableAuth(pushSession());
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.unsupported);
      expect((await service.deviceState(auth)).supported, isFalse);
      expect(api.registers, isEmpty);
      expect(gateway.permissionChecks, 0);
    });
  });

  group('kayıt tazeleme zamanlaması', () {
    test('24 saat içinde ön plana dönüş SUNUCUYA GİTMEZ; sonra gider; açılışta izin sorulmaz', () async {
      await registeredA();
      service.onAppResumed();
      await pushSettle();
      clock = clock.add(const Duration(hours: 23));
      service.onAppResumed();
      await pushSettle();
      expect(api.registers, hasLength(1));
      clock = clock.add(const Duration(hours: 2));
      service.onAppResumed();
      await pushSettle();
      expect(api.registers, hasLength(2));
      expect(gateway.requestCalls, 0);
    });

    test('jeton yenileme olayı "günde bir"i DELMEZ: jeton aynıysa kayıt yok, değiştiyse hemen', () async {
      await registeredA();
      gateway.refreshController.add('fcm-token-1'); // iOS her açılışta olay atar
      await pushSettle();
      expect(api.registers, hasLength(1));
      gateway.token = 'fcm-token-2';
      gateway.refreshController.add('fcm-token-2');
      await pushSettle();
      expect(api.registers, hasLength(2));
      expect(api.registers.last['fcm'], 'fcm-token-2');
    });

    test('izin ayarlardan kapatıldı: aynı gün de olsa notifications_enabled=false ile HEMEN tazelenir', () async {
      await registeredA();
      gateway.permission = PushPermission.permanentlyDenied;
      service.onAppResumed();
      await pushSettle();
      expect(api.registers, hasLength(2));
      expect(api.registers.last['enabled'], isFalse);
      expect(service.activeHere.value, isFalse);
      service.onAppResumed();
      await pushSettle();
      expect(api.registers, hasLength(2));
    });

    test('soğuk açılış: Firebase oturumdan SONRA hazır olursa kayıt yine yapılır', () async {
      await pushConsent(5);
      final auth = SwitchableAuth(pushSession());
      service.attach(auth);
      await pushSettle();
      expect(api.registers, isEmpty);
      await service.start(gateway);
      await pushSettle();
      expect(api.registers, hasLength(1));
    });

    test('arka plan kaydında 401: oturum sunucudan doğrulanır (çıkış AuthService\'te)', () async {
      await pushConsent(5);
      api.registerError = SessionExpiredException();
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      expect(auth.refreshCalls, 1);
    });
  });

  group('çıkışta sıra ve kalıcı temizlik', () {
    Future<AuthService> realRegistered() async {
      await pushConsent(5);
      final auth = await _realAuth();
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      expect(api.registers, hasLength(1));
      return auth;
    }

    test('DELETE oturum belirteci SİLİNMEDEN önce ve aynı belirteçle; deleteToken ona bağlı olmadan; damga silinir', () async {
      final auth = await realRegistered();
      final installId = await storedInstallId();
      api.watchAuth = auth;
      events.clear();
      await auth.logout();
      await pushSettle();
      final delete = api.deletes.single;
      expect(delete.sessionPresent, isTrue, reason: 'istek yola çıktığında oturum belirteci hâlâ yerinde');
      expect(delete.token, 'tok-A');
      expect(delete.installId, installId);
      expect(events, <String>['delete:tok-A', 'deleteToken']);
      expect((await prefs()).getString(PushLocalStore.stampKey), isNull);
      expect(await PushLocalStore().hasPendingCleanup(), isFalse);
      expect(await storedInstallId(), installId);
      expect(service.activeHere.value, isFalse);
    });

    test('deleteToken sunucu yanıtını BEKLEMEZ (sunucu askıdayken de jeton silinir); arayüz beklemez', () async {
      final auth = await realRegistered();
      api.deleteGate = Completer<void>();
      events.clear();
      await auth.logout();
      await pushSettle();
      expect(auth.session, isNull);
      expect(events, <String>['delete:tok-A', 'deleteToken']);
      api.deleteGate!.complete();
      await pushSettle();
    });

    test('ÇEVRİMDIŞI çıkış: jeton silinemezse işaret + damga kalır; YENİ açılışta oturum yokken yeniden denenir', () async {
      final auth = await realRegistered();
      api.deleteError = ApiException('Sunucuya bağlanılamadı.');
      gateway.deleteTokenError = Exception('ağ yok');
      await auth.logout();
      await pushSettle();
      expect(await PushLocalStore().hasPendingCleanup(), isTrue);
      expect((await prefs()).getString(PushLocalStore.stampKey), isNotNull, reason: 'damga yalnız başarıda silinir');

      // Uygulama yeniden açıldı (oturum yok), ağ geri geldi.
      gateway.deleteTokenError = null;
      final next = makeService();
      extra.add(next);
      final calls = gateway.deleteTokenCalls;
      await next.start(gateway);
      await pushSettle();
      expect(gateway.deleteTokenCalls, calls + 1);
      expect(await PushLocalStore().hasPendingCleanup(), isFalse);
      expect((await prefs()).getString(PushLocalStore.stampKey), isNull);
    });

    test('bekleyen temizlik uygulama açıkken kısa aralıklarla ve ön plana dönüşte yeniden denenir', () async {
      await service.dispose();
      service = makeService(cleanupRetryDelays: const <Duration>[Duration(milliseconds: 5)]);
      final auth = await realRegistered();
      gateway.deleteTokenError = Exception('ağ yok');
      await auth.logout();
      await pushSettle();
      final failed = gateway.deleteTokenCalls;
      expect(failed, greaterThanOrEqualTo(2), reason: 'zamanlayıcıyla bir kez daha denendi');
      gateway.deleteTokenError = null;
      service.onAppResumed();
      await pushSettle();
      expect(await PushLocalStore().hasPendingCleanup(), isFalse);
    });

    test('bekleyen temizlik varken yeni hesabın kaydından ÖNCE eski jeton silinir; silinemezse kayıt yapılmaz', () async {
      await pushConsent(5);
      await pushConsent(6);
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      gateway.deleteTokenError = Exception('ağ yok');
      auth.switchTo(null);
      await pushSettle();
      events.clear();
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      await pushSettle();
      expect(events, <String>['deleteToken'], reason: 'silinemedi: B kaydedilmez (eski jeton taşınmaz)');
      gateway.deleteTokenError = null;
      events.clear();
      service.onAppResumed();
      await pushSettle();
      expect(events, <String>['deleteToken', 'register:tok-B']);
    });

    test('Firebase HAZIR OLMADAN çıkış: sunucu silmesi yine gider, işaret yazılır; start() hazır olunca jetonu siler', () async {
      // Önceki çalıştırmadan kalan kayıt: kurulum kimliği + damga (jeton FCM'de canlı).
      final store = PushLocalStore();
      final installId = await store.installId();
      await store.writeStamp(
        PushRegistrationStamp(userId: 5, tokenHash: 'h', notificationsEnabled: true, at: clock),
      );
      final auth = SwitchableAuth(pushSession());
      service.markStarting(); // Firebase başlatması sürüyor
      service.attach(auth);
      await pushSettle();
      auth.switchTo(null); // çıkış
      await pushSettle();
      expect(api.deletes.single.token, 'tok-A');
      expect(api.deletes.single.installId, installId);
      expect(await PushLocalStore().hasPendingCleanup(), isTrue);
      expect(gateway.deleteTokenCalls, 0);

      await service.start(gateway);
      await pushSettle();
      expect(gateway.deleteTokenCalls, 1, reason: 'gateway hazır olunca yerel jeton silinir');
      expect(await PushLocalStore().hasPendingCleanup(), isFalse);
      expect(await PushLocalStore().readStamp(), isNull);
    });

    test('Firebase hiç başlatılamayan cihazda (kayıt yok) çıkış hiçbir şey yazmaz', () async {
      final auth = SwitchableAuth(pushSession());
      service
        ..markStarting()
        ..markStartFailed()
        ..attach(auth);
      auth.switchTo(null);
      await pushSettle();
      expect(api.deletes, isEmpty);
      expect(await PushLocalStore().hasPendingCleanup(), isFalse);
    });

    test('zamanlayıcıyla başarılan temizlikten sonra oturum varsa kayıt KENDİLİĞİNDEN yapılır', () async {
      await service.dispose();
      service = makeService(cleanupRetryDelays: const <Duration>[Duration(milliseconds: 150)]);
      await pushConsent(5);
      await pushConsent(6);
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      gateway.deleteTokenError = Exception('ağ yok');
      auth.switchTo(null);
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      await pushSettle();
      expect(api.registers.map((r) => r['token']), <Object?>['tok-A'], reason: 'B temizlik bekliyor');
      gateway.deleteTokenError = null; // ağ geri geldi; ön plana dönüş YOK
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(api.registers.map((r) => r['token']), <Object?>['tok-A', 'tok-B']);
      expect(await PushLocalStore().hasPendingCleanup(), isFalse);
    });

    test('yeni çıkışta yeniden deneme takvimi baştan başlar', () async {
      await service.dispose();
      service = makeService(cleanupRetryDelays: const <Duration>[Duration(milliseconds: 5)]);
      await pushConsent(5);
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      gateway.deleteTokenError = Exception('ağ yok');
      auth.switchTo(null); // 1. çıkış: hemen + zamanlayıcı (takvim biter)
      await pushSettle();
      final afterFirst = gateway.deleteTokenCalls;
      expect(afterFirst, 2);
      auth.switchTo(pushSession()); // aynı kullanıcı yeniden girdi (kayıt temizlik yüzünden bekler)
      await pushSettle();
      final beforeSecond = gateway.deleteTokenCalls;
      auth.switchTo(null); // 2. çıkış: takvim sıfırlandı, zamanlayıcı yeniden çalışır
      await pushSettle();
      expect(gateway.deleteTokenCalls, greaterThanOrEqualTo(beforeSecond + 2));
    });

    test('kalıcı (ağ dışı) silme hatası kaydı süresiz ENGELLEMEZ: sınırdan önce "temizlik bekliyor", sonra kayıt', () async {
      await pushConsent(5);
      await pushConsent(6);
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      gateway.deleteTokenError = Exception('FCM yapılandırma hatası');
      auth.switchTo(null); // 1. başarısızlık
      auth.switchTo(pushSession(id: 6, token: 'tok-B')); // 2. başarısızlık: B bekler
      await pushSettle();
      expect(api.registers, hasLength(1));
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.cleanupPending); // 3.
      expect(await PushLocalStore().pendingCleanupFailures(), 3);
      service.onAppResumed(); // 4. (yeniden deneme) + 5. (kayıttan önce) -> sınır doldu, kayıt yapılır
      await pushSettle();
      expect(api.registers.map((r) => r['token']), <Object?>['tok-A', 'tok-B']);
      expect(await PushLocalStore().hasPendingCleanup(), isTrue, reason: 'temizlik arka planda sürer');
    });

    test('kanca olmadan kapanan oturum (dinleyici yolu) aynı akış; yeni giriş eski silme BİTMEDEN kaydolmaz', () async {
      await pushConsent(6);
      final auth = await registeredA();
      api.deleteGate = Completer<void>();
      events.clear();
      auth.switchTo(null);
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      await pushSettle();
      expect(events, <String>['delete:tok-A', 'deleteToken'], reason: 'yeni kayıt sırada bekler');
      api.deleteGate!.complete();
      await pushSettle();
      expect(events, <String>['delete:tok-A', 'deleteToken', 'register:tok-B']);
    });

    test('hiç kaydolmamış cihazda çıkış sunucuya ve FCM\'e gitmez', () async {
      final auth = await _realAuth();
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      await auth.logout();
      await pushSettle();
      expect(api.deletes, isEmpty);
      expect(gateway.deleteTokenCalls, 0);
    });
  });

  group('hesap değişimi', () {
    test('oturum kapanmadan başka hesaba geçiş: önceki hesabın çıkış akışı (kendi belirteciyle), sonra yeni kayıt', () async {
      await pushConsent(6);
      final auth = await registeredA();
      events.clear();
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      await pushSettle();
      expect(events, <String>['delete:tok-A', 'deleteToken', 'register:tok-B']);
    });

    test('A\'nın kaydı sürerken B\'ye geçilirse A için B\'nin belirteciyle kayıt GİTMEZ', () async {
      await pushConsent(5);
      await pushConsent(6);
      api.prefsGate = Completer<void>(); // A'nın kaydı push_available denetiminde bekler
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      await pushSettle();
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      api.prefsGate!.complete();
      await pushSettle();
      expect(api.registers.map((r) => r['token']), <Object?>['tok-B']);
      expect(events.where((e) => e.startsWith('register')), <String>['register:tok-B']);
    });

    test('aynı hesapta belirteç değişimi (parola) çıkış akışı başlatmaz', () async {
      final auth = await registeredA();
      events.clear();
      auth.switchTo(pushSession(token: 'tok-A2'));
      await pushSettle();
      expect(events, isEmpty);
    });
  });

  group('tıklama yönlendirmesi', () {
    test('SOĞUK açılış: getInitialMessage bekletilir, ana sayfa bağlanınca BİR kez açılır', () async {
      gateway.initial = _valid42;
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      final opened = <int>[];
      void opener(int id) => opened.add(id);
      service.bindAnnouncementOpener(opener);
      expect(opened, <int>[42]);
      service.unbindAnnouncementOpener(opener);
      service.bindAnnouncementOpener(opener);
      expect(opened, <int>[42], reason: 'bir kez tüketilir');
    });

    test('ARKA PLAN: onMessageOpenedApp, açıcı bağlıyken hemen açılır', () async {
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      final opened = <int>[];
      service.bindAnnouncementOpener(opened.add);
      gateway.openedController.add(_valid42);
      await pushSettle();
      expect(opened, <int>[42]);
    });

    test('OTURUM YOKKEN bekletilir; giriş yapılınca teslim edilir', () async {
      final auth = SwitchableAuth();
      await service.start(gateway);
      service.attach(auth);
      final opened = <int>[];
      service.bindAnnouncementOpener(opened.add);
      gateway.openedController.add(_valid42);
      await pushSettle();
      expect(opened, isEmpty);
      auth.switchTo(pushSession());
      await pushSettle();
      expect(opened, <int>[42]);
    });

    test('ana sayfa hazır değilken (açıcı yok) bekletilir, bağlanınca açılır', () async {
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      gateway.openedController.add(_valid42);
      await pushSettle();
      final opened = <int>[];
      service.bindAnnouncementOpener(opened.add);
      expect(opened, <int>[42]);
    });

    test('GEÇERSİZ yük yok sayılır (tür / numara beyaz liste dışı; test bildirimi yönlendirmez)', () async {
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      final opened = <int>[];
      final foreground = <int>[];
      final sub = service.foregroundAnnouncements.listen(foreground.add);
      service.bindAnnouncementOpener(opened.add);
      const invalid = <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'announcement_id': '42'},
        <String, Object?>{'type': 'document', 'announcement_id': '42'},
        <String, Object?>{'type': 'test', 'announcement_id': '42'},
        <String, Object?>{'type': 'Announcement', 'announcement_id': '42'},
        <String, Object?>{'type': 'announcement'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '0'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '-3'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '0042'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '42abc'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '4 2'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '1234567890123456'},
        <String, Object?>{'type': 'announcement', 'announcement_id': '../42'},
      ];
      for (final data in invalid) {
        gateway.openedController.add(PushMessage(data));
        gateway.messageController.add(PushMessage(data));
      }
      await pushSettle();
      expect(opened, isEmpty);
      expect(foreground, isEmpty);
      await sub.cancel();
    });

    test('bayat yönlendirme (30 dk\'dan eski) açılmaz', () async {
      final auth = SwitchableAuth();
      await service.start(gateway);
      service.attach(auth);
      final opened = <int>[];
      service.bindAnnouncementOpener(opened.add);
      gateway.openedController.add(_valid42);
      await pushSettle();
      clock = clock.add(const Duration(minutes: 31));
      auth.switchTo(pushSession());
      await pushSettle();
      expect(opened, isEmpty);
    });

    for (final (label, ValueNotifier<bool> blocker) in <(String, ValueNotifier<bool>)>[
      ('bakım / zorunlu güncelleme', AppGateBlock.active),
      ('açılış kapısı ilk denetimi', AppGateBlock.pendingFirstCheck),
      ('"Güncellenen koşullar" kapısı', LegalConsentBlock.active),
    ]) {
      test('$label açıkken bekletilir, kapanınca açılır', () async {
        final auth = SwitchableAuth(pushSession());
        await service.start(gateway);
        service.attach(auth);
        final opened = <int>[];
        service.bindAnnouncementOpener(opened.add);
        blocker.value = true;
        gateway.openedController.add(_valid42);
        await pushSettle();
        expect(opened, isEmpty);
        blocker.value = false;
        expect(opened, <int>[42]);
      });
    }

    test('çıkış, bekleyen yönlendirmeyi atar (başka hesaba taşınmaz)', () async {
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      gateway.openedController.add(_valid42);
      await pushSettle();
      auth.switchTo(null);
      await pushSettle();
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      final opened = <int>[];
      service.bindAnnouncementOpener(opened.add);
      expect(opened, isEmpty);
    });
  });

  group('ön planda alınan bildirim', () {
    test('duyuru -> foregroundAnnouncements; test -> foregroundTests; oturum yoksa hiçbiri', () async {
      final auth = SwitchableAuth(pushSession());
      await service.start(gateway);
      service.attach(auth);
      final got = <int>[];
      var tests = 0;
      final sub = service.foregroundAnnouncements.listen(got.add);
      final testSub = service.foregroundTests.listen((_) => tests++);
      gateway.messageController
        ..add(_valid42)
        ..add(const PushMessage(<String, Object?>{'type': 'test'}));
      await pushSettle();
      expect(got, <int>[42]);
      expect(tests, 1);
      auth.switchTo(null);
      gateway.messageController
        ..add(_valid42)
        ..add(const PushMessage(<String, Object?>{'type': 'test'}));
      await pushSettle();
      expect(got, <int>[42]);
      expect(tests, 1);
      await sub.cancel();
      await testSub.cancel();
    });
  });

  group('cihazı kaldırma', () {
    test('BU cihaz: DELETE + deleteToken + rıza silinir; kendiliğinden geri gelmez; "Bu cihazda aç" ile döner', () async {
      final auth = await registeredA();
      final id = (await storedInstallId())!;
      events.clear();
      await service.removeDevice(auth, id);
      expect(events, <String>['delete:tok-A', 'deleteToken']);
      expect((await service.deviceState(auth)).enabledHere, isFalse);
      expect(service.activeHere.value, isFalse);
      clock = clock.add(const Duration(days: 2));
      service.onAppResumed();
      await pushSettle();
      expect(api.registers, hasLength(1));
      expect(await service.enableOnThisDevice(auth), PushEnableOutcome.registered);
      expect(api.registers, hasLength(2));
    });

    test('BAŞKA cihaz: yalnız DELETE; bu cihazın jetonu silinmez', () async {
      final auth = await registeredA();
      events.clear();
      await service.removeDevice(auth, 'baska-cihaz-0000-1111');
      expect(events, <String>['delete:tok-A']);
      expect(gateway.deleteTokenCalls, 0);
    });
  });

  group('yumuşak istem kartı koşulları', () {
    test('hepsi sağlanınca göster; rıza / kapatma / kalıcı ret / push kapalı / gateway yok ise gösterme', () async {
      final auth = SwitchableAuth(pushSession());
      expect(await service.shouldShowSoftPrompt(auth), isFalse, reason: 'gateway yok');
      await service.start(gateway);
      gateway.permission = PushPermission.notDetermined;
      expect(await service.shouldShowSoftPrompt(auth), isTrue);

      gateway.permission = PushPermission.permanentlyDenied;
      expect(await service.shouldShowSoftPrompt(auth), isFalse);
      gateway.permission = PushPermission.notDetermined;

      await service.dismissSoftPrompt(auth);
      expect(await service.shouldShowSoftPrompt(auth), isFalse, reason: 'kalıcı kapatıldı');
      expect(await service.shouldShowSoftPrompt(SwitchableAuth(pushSession(id: 7))), isTrue, reason: 'kullanıcı başına');

      await pushConsent(8);
      expect(await service.shouldShowSoftPrompt(SwitchableAuth(pushSession(id: 8))), isFalse, reason: 'zaten açık');
      expect(
        await service.shouldShowSoftPrompt(SwitchableAuth(pushSession(id: 9, role: UserRole.superUser))),
        isFalse,
      );
    });

    test('sunucuda push kapalıysa kart yok (push_available önbelleği kullanılır)', () async {
      api.prefs = const PushPreferences(available: false);
      await service.start(gateway);
      gateway.permission = PushPermission.notDetermined;
      final auth = SwitchableAuth(pushSession());
      expect(await service.shouldShowSoftPrompt(auth), isFalse);
      expect(await service.shouldShowSoftPrompt(auth), isFalse);
      expect(api.prefsCalls, 1, reason: 'önbellek');
    });
  });

  group('başlatma durumu', () {
    test('idle -> starting -> failed ("bu sürümde yok"); başarılı başlatmada ready', () async {
      final auth = SwitchableAuth(pushSession());
      expect(service.startState.value, PushStartState.idle);
      expect((await service.deviceState(auth)).support, PushSupport.preparing);
      service.markStarting();
      expect(service.startState.value, PushStartState.starting);
      service.markStartFailed();
      expect((await service.deviceState(auth)).support, PushSupport.notConfigured);
      final ok = makeService();
      extra.add(ok);
      ok.markStarting();
      await ok.start(gateway);
      expect(ok.startState.value, PushStartState.ready);
      expect((await ok.deviceState(auth)).support, PushSupport.ready);
    });

    test('masaüstünde: unsupportedPlatform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect((await service.deviceState(SwitchableAuth(pushSession()))).support, PushSupport.unsupportedPlatform);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('"bu cihaza bildirim gelir" (activeHere) koşulları', () {
    Future<PushService> coldStart() async {
      await registeredA(); // önceki çalıştırma: kayıtlı ve damgalı
      final next = makeService();
      extra.add(next);
      await next.start(gateway);
      next.attach(SwitchableAuth(pushSession()));
      await pushSettle();
      return next;
    }

    test('soğuk açılışta (kayıt güncel) push_available tembel doğrulanır: açıksa true', () async {
      final next = await coldStart();
      expect(api.registers, hasLength(1), reason: 'damga güncel: yeniden kayıt yok');
      expect(api.prefsCalls, 2, reason: 'ilk kayıt + soğuk açılışta tembel doğrulama');
      expect(next.activeHere.value, isTrue);
    });

    test('soğuk açılışta sunucu push\'u KAPALIYSA false ("gelir" denmez)', () async {
      await registeredA();
      api.prefs = const PushPreferences(available: false);
      final next = makeService();
      extra.add(next);
      await next.start(gateway);
      next.attach(SwitchableAuth(pushSession()));
      await pushSettle();
      expect(next.activeHere.value, isFalse);
    });

    test('soğuk açılışta uygunluk okunamazsa iddia edilmez (false kalır)', () async {
      await registeredA();
      api.prefsError = ApiException('Sunucuya bağlanılamadı.');
      final next = makeService();
      extra.add(next);
      await next.start(gateway);
      next.attach(SwitchableAuth(pushSession()));
      await pushSettle();
      expect(next.activeHere.value, isFalse);
    });

    test('tercihler ekranı push_available=false okursa true -> false', () async {
      final auth = await registeredA();
      expect(service.activeHere.value, isTrue);
      api.prefs = const PushPreferences(available: false);
      await service.getPreferences(auth);
      expect(service.activeHere.value, isFalse);
    });
  });

  group('gateway yokken', () {
    test('attach, çıkış ve hesap değişimi hiçbir ağ / FCM çağrısı yapmaz', () async {
      await pushConsent(5);
      final auth = await _realAuth();
      service.attach(auth);
      await pushSettle();
      await auth.logout();
      await pushSettle();
      expect(api.registers, isEmpty);
      expect(api.deletes, isEmpty);
      expect(gateway.deleteTokenCalls, 0);
      expect(service.isSupported, isFalse);
    });
  });
}
