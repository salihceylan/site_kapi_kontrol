// FAZ 5 / P-f: soğuk açılış. AuthService.initialize içindeki bağımsız okumalar (güvenli depodaki
// oturum, eski SharedPreferences kopyası, yerel erişim önbelleği) eşzamanlı yapılır; NetworkService
// internet yoklaması ardışık 5+5 sn yerine kademeli eşzamanlıdır. Davranış sırası (oturum yüklendi ->
// hazır -> ekran seçimi) ve sonuçlar değişmez.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/network_service.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _sessionKey = 'auth_session';
const _cacheKey = 'local_door_cache';

String _sessionRaw({String email = 'ali@example.com'}) => jsonEncode(
      UserSession(
        id: 5,
        fullName: 'Ali Veli',
        email: email,
        loginName: null,
        role: UserRole.individual,
        isActive: true,
        token: 'tok-A',
      ).toJson(),
    );

String _cacheRaw() => jsonEncode({
      'AABBCCDDEEFF': {
        'device_uid': 'AABBCCDDEEFF',
        'token': 'local-token',
        'ip': '192.168.1.50',
        'port': 8765,
        'updated_at': DateTime.now().toIso8601String(),
      },
    });

DoorRecord _door() => DoorRecord(
      id: 7,
      siteCode: 3,
      siteName: 'Güneş Sitesi',
      doorName: 'Ana Kapı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'AABBCCDDEEFF',
      mqttSiteId: 3,
      createdAt: DateTime(2026, 1, 1),
    );

/// Sıfır ağ: açılış sırasında /me doğrulaması istekleri sahte istemciye gider.
AuthService _service() => AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async => http.Response('{}', 500)),
        retryDelay: Duration.zero,
      ),
    );

class _SecureStub {
  _SecureStub({this.sessionRaw, this.cacheRaw, this.readDelay = Duration.zero});

  final String? sessionRaw;
  final String? cacheRaw;
  final Duration readDelay;
  final List<String> calls = <String>[];
  Completer<void>? sessionReadGate;
  bool throwOnSessionRead = false;

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
    final key = args['key'] as String?;
    calls.add('${call.method}:$key');
    switch (call.method) {
      case 'read':
        if (readDelay > Duration.zero) await Future<void>.delayed(readDelay);
        if (key == _sessionKey) {
          final gate = sessionReadGate;
          if (gate != null) await gate.future;
          if (throwOnSessionRead) throw PlatformException(code: 'read-failed');
          return sessionRaw;
        }
        if (key == _cacheKey) return cacheRaw;
        return null;
      default:
        return null;
    }
  }

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handle);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('AuthService.initialize: bağımsız okumalar eşzamanlı', () {
    test('güvenli depo okuması sürerken eski kopya ve yerel önbellek de okunur', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{_sessionKey: _sessionRaw(email: 'eski@example.com')});
      final secure = _SecureStub(sessionRaw: null, cacheRaw: _cacheRaw())..sessionReadGate = Completer<void>();
      secure.install();

      final service = _service();
      final init = service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Oturum okuması hâlâ bekliyor: hazır DEĞİL.
      expect(service.isReady, isFalse);
      // ...ama bağımsız okumalar çoktan başladı/bitti:
      expect(secure.calls, contains('read:$_cacheKey'), reason: 'yerel önbellek okuması beklemeden başlar');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_sessionKey), isFalse, reason: 'eski kopya beklemeden alınır (okunur ve silinir)');

      secure.sessionReadGate!.complete();
      await init;

      expect(service.isReady, isTrue);
      // Güvenli depo boştu: eski kopya taşındı ve oturum o oldu.
      expect(service.session?.email, 'eski@example.com');
      expect(secure.calls, contains('write:$_sessionKey'));
      // Yerel erişim önbelleği yüklendi (sonuç eskisiyle aynı).
      expect(service.canTryLocalDoorOpen(_door()), isTrue);
      service.dispose();
    });

    test('oturum güvenli depodan yüklenir; hazır olunca oturum ve önbellek birlikte hazırdır', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final secure = _SecureStub(sessionRaw: _sessionRaw(), cacheRaw: _cacheRaw());
      secure.install();

      final service = _service();
      var notifiedReadyWithSession = false;
      service.addListener(() {
        if (service.isReady && service.session != null && service.canTryLocalDoorOpen(_door())) {
          notifiedReadyWithSession = true;
        }
      });
      await service.initialize();

      expect(service.isReady, isTrue);
      expect(service.isLoggedIn, isTrue);
      expect(service.session?.email, 'ali@example.com');
      expect(notifiedReadyWithSession, isTrue, reason: 'hazır bildirimi geldiğinde oturum + önbellek yüklü');
      service.dispose();
    });

    test('güvenli depo okuma hatası açılışı engellemez (oturumsuz hazır)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final secure = _SecureStub(sessionRaw: _sessionRaw(), cacheRaw: _cacheRaw())..throwOnSessionRead = true;
      secure.install();

      final service = _service();
      await service.initialize();

      expect(service.isReady, isTrue);
      expect(service.isLoggedIn, isFalse);
      expect(service.canTryLocalDoorOpen(_door()), isTrue, reason: 'önbellek bağımsızdır');
      service.dispose();
    });

    test('ÖLÇÜM: iki yavaş okuma (300 ms) toplanmaz, en yavaşı kadar sürer', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final secure = _SecureStub(
        sessionRaw: _sessionRaw(),
        cacheRaw: _cacheRaw(),
        readDelay: const Duration(milliseconds: 300),
      );
      secure.install();

      final service = _service();
      final clock = Stopwatch()..start();
      await service.initialize();
      clock.stop();
      print('ÖLÇÜM AuthService.initialize (2 x 300 ms okuma): ${clock.elapsedMilliseconds} ms (ardışık olsaydı >= 600 ms)');

      expect(service.isLoggedIn, isTrue);
      expect(clock.elapsedMilliseconds, lessThan(520), reason: 'ardışık olsaydı >= 600 ms');
      service.dispose();
    });
  });

  group('NetworkService: kademeli eşzamanlı internet yoklaması', () {
    Future<NetworkService> run(
      WidgetTester tester,
      FutureOr<http.Response> Function(http.Request request) handler,
      List<String> requests, {
      required List<Duration> checkpoints,
      required void Function(Duration at, NetworkService service) onCheckpoint,
    }) async {
      final service = NetworkService();
      http.runWithClient(
        () => unawaited(service.refresh()),
        () => MockClient((request) async {
          requests.add(request.url.path);
          return handler(request);
        }),
      );
      var elapsed = Duration.zero;
      await tester.pump();
      for (final at in checkpoints) {
        await tester.pump(at - elapsed);
        elapsed = at;
        onCheckpoint(at, service);
      }
      return service;
    }

    testWidgets('sağlıklı ağ: tek istek (/health), yedek adrese gidilmez', (tester) async {
      final requests = <String>[];
      final service = await run(
        tester,
        (r) => http.Response('ok', 200),
        requests,
        checkpoints: [const Duration(milliseconds: 100), const Duration(seconds: 3)],
        onCheckpoint: (at, s) {},
      );
      expect(service.isReady, isTrue);
      expect(service.hasInternet, isTrue);
      expect(requests, ['/health']);
      service.dispose();
    });

    testWidgets('/health hata verirse yedek adres hemen denenir', (tester) async {
      final requests = <String>[];
      final service = await run(
        tester,
        (r) {
          if (r.url.path == '/health') throw http.ClientException('connection reset');
          return http.Response('', 204);
        },
        requests,
        checkpoints: [const Duration(milliseconds: 100)],
        onCheckpoint: (at, s) {},
      );
      expect(service.isReady, isTrue);
      expect(service.hasInternet, isTrue);
      expect(requests, ['/health', '/generate_204']);
      service.dispose();
    });

    testWidgets('/health 5xx dönerse de yedek adres denenir', (tester) async {
      final requests = <String>[];
      final service = await run(
        tester,
        (r) => r.url.path == '/health' ? http.Response('x', 503) : http.Response('', 204),
        requests,
        checkpoints: [const Duration(milliseconds: 100)],
        onCheckpoint: (at, s) {},
      );
      expect(service.hasInternet, isTrue);
      expect(requests, ['/health', '/generate_204']);
      service.dispose();
    });

    testWidgets('/health yanıtsız: yedek 1,5 sn sonra eşzamanlı başlar, 5 sn beklenmez', (tester) async {
      final requests = <String>[];
      final readyAt = <Duration, bool>{};
      final service = await run(
        tester,
        (r) => r.url.path == '/health' ? Completer<http.Response>().future : http.Response('', 204),
        requests,
        checkpoints: [
          const Duration(milliseconds: 1400),
          const Duration(milliseconds: 1700),
          const Duration(seconds: 5),
        ],
        onCheckpoint: (at, s) => readyAt[at] = s.isReady,
      );
      expect(readyAt[const Duration(milliseconds: 1400)], isFalse, reason: 'yedek henüz başlamadı');
      expect(readyAt[const Duration(milliseconds: 1700)], isTrue, reason: 'yedek 1,5 sn\'de başladı ve başarılı oldu');
      expect(service.hasInternet, isTrue);
      expect(requests, ['/health', '/generate_204']);
      service.dispose();
    });

    testWidgets('iki adres de yanıtsız: ~6,5 sn sonra internet yok (eskiden 10 sn)', (tester) async {
      final requests = <String>[];
      final readyAt = <Duration, bool>{};
      final service = await run(
        tester,
        (r) => Completer<http.Response>().future,
        requests,
        checkpoints: [
          const Duration(seconds: 5),
          const Duration(milliseconds: 6400),
          const Duration(milliseconds: 6600),
        ],
        onCheckpoint: (at, s) => readyAt[at] = s.isReady,
      );
      expect(readyAt[const Duration(seconds: 5)], isFalse);
      expect(readyAt[const Duration(milliseconds: 6400)], isFalse);
      expect(readyAt[const Duration(milliseconds: 6600)], isTrue);
      expect(service.hasInternet, isFalse);
      expect(requests, ['/health', '/generate_204']);
      service.dispose();
    });
  });
}
