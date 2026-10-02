import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';

const _storageKey = 'auth_session';

UserSession _session({
  String token = 'tok-A',
  UserRole role = UserRole.individual,
  bool isActive = true,
}) {
  return UserSession(
    id: 5,
    fullName: 'Ali Veli',
    email: 'ali@example.com',
    loginName: null,
    role: role,
    isActive: isActive,
    token: token,
  );
}

String _sessionRaw(UserSession s) => jsonEncode(s.toJson());

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _meBody({String role = 'individual', bool active = true}) => {
      'user': {
        'id': 5,
        'full_name': 'Ali Veli',
        'email': 'ali@example.com',
        'login_name': null,
        'role': role,
        'is_active': active,
      },
    };

DoorRecord _door({
  bool remote = true,
  bool localUdp = true,
  bool requireGeofence = false,
  String? uid = 'AABBCCDDEEFF',
}) {
  return DoorRecord(
    id: 7,
    siteCode: 3,
    siteName: 'Güneş Sitesi',
    doorName: 'Ana Kapı',
    doorIndex: 1,
    isActive: true,
    assignedDeviceId: uid == null ? null : 1,
    assignedDeviceUid: uid,
    mqttSiteId: 3,
    featureRemoteOpenEnabled: remote,
    featureLocalUdpEnabled: localUdp,
    requireGeofence: requireGeofence,
    geofenceLatitude: 41.0,
    geofenceLongitude: 29.0,
    createdAt: DateTime(2026, 1, 1),
  );
}

Position _position({double accuracy = 10, bool mocked = false}) => Position(
      latitude: 41.0,
      longitude: 29.0,
      timestamp: DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

Map<String, dynamic> _openStatusBody() => {
      'door': {'id': 7, 'site_code': 3, 'door_name': 'Ana Kapı', 'door_index': 1},
      'device_status': {'device_uid': 'AABBCCDDEEFF', 'mqtt_connected': true},
    };

class _Harness {
  _Harness(this.service, this.requests);

  final AuthService service;
  final List<http.Request> requests;

  Iterable<http.Request> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);
}

/// [handler] içinde istek kaydedilir; testler istek sayısı ve gövdesini doğrular.
_Harness _makeService(
  FutureOr<http.Response> Function(http.Request request) handler, {
  Future<LocationFixResult> Function()? locationProvider,
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });
  final service = AuthService(
    api: AuthApi(
      baseUrl: 'https://api.example.test',
      client: client,
      retryDelay: Duration.zero,
    ),
    locationProvider: locationProvider,
  );
  return _Harness(service, requests);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('Oturum saklama: yalnızca güvenli depo', () {
    test('eski SharedPreferences kopyası güvenli depoya taşınır ve silinir', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _storageKey: _sessionRaw(_session(token: 'legacy-token')),
      });

      final h = _makeService((r) => _json(_meBody()));
      await h.service.initialize();

      expect(h.service.session?.token, 'legacy-token');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_storageKey), isFalse,
          reason: 'düz metin kopya taşındıktan sonra silinmeli');
      final secure = await const FlutterSecureStorage().read(key: _storageKey);
      expect(secure, isNotNull);
      expect(jsonDecode(secure!)['token'], 'legacy-token');

      await _settle();
      h.service.dispose();
    });

    test('güvenli depo doluysa eski kopya yine de silinir ve güvenli depo esas alınır', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _storageKey: _sessionRaw(_session(token: 'legacy-token')),
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session(token: 'secure-token')),
      });

      final h = _makeService((r) => _json(_meBody()));
      await h.service.initialize();

      expect(h.service.session?.token, 'secure-token');
      expect((await SharedPreferences.getInstance()).containsKey(_storageKey), isFalse);

      await _settle();
      h.service.dispose();
    });

    test('girişten sonra oturum SharedPreferences\'a YAZILMAZ', () async {
      final h = _makeService((r) {
        if (r.url.path == '/auth/login') {
          return _json({
            'token': 'new-token',
            'user': _meBody()['user'],
          });
        }
        return _json(_meBody());
      });
      await h.service.initialize();

      final error = await h.service.login(email: 'ali@example.com', password: 'x');
      expect(error, isNull);
      expect(h.service.session?.token, 'new-token');

      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(await const FlutterSecureStorage().read(key: _storageKey), isNotNull);
      h.service.dispose();
    });

    test('logout oturumu her iki depodan da siler', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _storageKey: _sessionRaw(_session()),
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) => _json(_meBody()));
      await h.service.initialize();
      await _settle();

      await h.service.logout();

      expect(h.service.isLoggedIn, isFalse);
      expect(await const FlutterSecureStorage().read(key: _storageKey), isNull);
      expect((await SharedPreferences.getInstance()).containsKey(_storageKey), isFalse);
      h.service.dispose();
    });
  });

  group('C11: /me ile rol ve oturum doğrulama', () {
    Future<_Harness> startWith(
      FutureOr<http.Response> Function(http.Request r) handler, {
      UserSession? session,
    }) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(session ?? _session()),
      });
      final h = _makeService(handler);
      await h.service.initialize();
      await _settle();
      return h;
    }

    test('açılışta /me çağrılır ve sunucudaki rol uygulanır', () async {
      final h = await startWith((r) => _json(_meBody(role: 'site_manager')));
      expect(h.where('GET', '/me'), hasLength(1));
      expect(h.service.session?.role, UserRole.siteManager);
      h.service.dispose();
    });

    test('401 -> oturum kapatılır', () async {
      final h = await startWith((r) => _json({'error': 'Gecersiz token.'}, 401));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('403 (hesap pasif / onaysız) -> oturum kapatılır', () async {
      final h = await startWith((r) => _json({'error': 'Hesap aktif degil.'}, 403));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('yanıtta is_active=false ise oturum kapatılır', () async {
      final h = await startWith((r) => _json(_meBody(active: false)));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('ağ hatasında çevrimdışı oturum korunur', () async {
      final h = await startWith((r) => throw http.ClientException('offline'));
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });

    test('5xx hatasında oturum korunur', () async {
      final h = await startWith((r) => _json({'error': 'x'}, 503));
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });

    test('ön plana dönüşte (force olmadan) art arda çağrılar kısıtlanır', () async {
      final h = await startWith((r) => _json(_meBody()));
      expect(h.where('GET', '/me'), hasLength(1));

      await h.service.refreshSession();
      await h.service.refreshSession();
      expect(h.where('GET', '/me'), hasLength(1), reason: '20 sn içinde tekrar çağrılmamalı');

      await h.service.refreshSession(force: true);
      expect(h.where('GET', '/me'), hasLength(2));
      h.service.dispose();
    });

    test('claimDevice sonrası rol yerelde tahmin edilmez, /me ile eşitlenir', () async {
      var meRole = 'individual';
      final h = await startWith((r) {
        if (r.url.path == '/membership/claim-device') {
          meRole = 'site_manager';
          return _json({'ok': true, 'device_uid': 'AABBCCDDEEFF'});
        }
        return _json(_meBody(role: meRole));
      });
      expect(h.service.session?.role, UserRole.individual);

      await h.service.claimDevice(deviceInput: 'AABBCCDDEEFF');
      expect(h.service.session?.role, UserRole.siteManager);
      h.service.dispose();
    });

    test('getMyClaimedDevices rol yükseltmez ve 401\'i yutmaz', () async {
      final h = await startWith((r) {
        if (r.url.path == '/membership/my-devices') {
          return _json({'error': 'x'}, 401);
        }
        return _json(_meBody());
      });
      await expectLater(h.service.getMyClaimedDevices(), throwsA(anything));
      await _settle();
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });
  });

  group('C11 uyumu: TOKEN_REVOKED, 403 doğrulaması ve oturum bildirimi', () {
    Future<_Harness> startLoggedIn(
      FutureOr<http.Response> Function(http.Request r) handler,
    ) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) {
        if (r.url.path == '/me' && r.method == 'GET') return _json(_meBody());
        return handler(r);
      });
      await h.service.initialize();
      await _settle();
      return h;
    }

    test('401 TOKEN_REVOKED -> merkezi çıkış ve giriş ekranı için açıklama', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401),
      );
      await h.service.listMyDoors();
      await _settle();

      expect(h.service.isLoggedIn, isFalse);
      final notice = h.service.takeSessionNotice();
      expect(notice, contains('Şifreniz değiştirildiği için'));
      expect(h.service.takeSessionNotice(), isNull, reason: 'bildirim yalnızca bir kez okunur');
      h.service.dispose();
    });

    test('düz 403 (politika reddi) oturumu kapatmaz ama /me ile hesap durumu doğrulanır', () async {
      var meCalls = 0;
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) {
        if (r.url.path == '/me') {
          meCalls++;
          // İlk çağrı (açılış) başarılı, sonraki çağrıda hesap pasif.
          return meCalls == 1 ? _json(_meBody()) : _json({'error': 'Hesap aktif degil.'}, 403);
        }
        return _json({'error': 'Uzaktan acma kapali.', 'code': 'REMOTE_OPEN_DISABLED'}, 403);
      });
      await h.service.initialize();
      await _settle();
      expect(h.service.isLoggedIn, isTrue);

      // Throttle penceresini aş: ilk /me'den sonra yeniden doğrulanabilsin.
      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      expect(status, isNull);
      expect(error, 'Bu sitede uygulamadan uzaktan kapı açma kapalı.');

      await h.service.refreshSession(force: true);
      await _settle();
      expect(h.service.isLoggedIn, isFalse, reason: '403 /me yanıtı hesabı pasif gösteriyor');
      expect(h.service.takeSessionNotice(), 'Hesap aktif degil.');
      h.service.dispose();
    });

    test('400 CURRENT_PASSWORD_INVALID oturumu kapatmaz ve Türkçe mesaj döner', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'CURRENT_PASSWORD_INVALID'}, 400),
      );
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'yanlis',
      );
      await _settle();
      expect(error, 'Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.');
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });

    test('429 CURRENT_PASSWORD_LOCKED bekleme süresini döndürür, oturum açık kalır', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'CURRENT_PASSWORD_LOCKED', 'retry_after_seconds': 600}, 429),
      );
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'yanlis',
      );
      await _settle();
      expect(error, contains('10 dakika sonra tekrar deneyin'));
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });

    test('parola değişiminde dönen yeni token oturuma ve güvenli depoya yazılır', () async {
      final h = await startLoggedIn((r) {
        final body = _meBody();
        body['token'] = 'tok-yeni';
        return _json(body);
      });

      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      expect(error, isNull);
      expect(h.service.session?.token, 'tok-yeni');

      final stored = await const FlutterSecureStorage().read(key: _storageKey);
      expect(jsonDecode(stored!)['token'], 'tok-yeni');
      h.service.dispose();
    });

    test('login 429 LOGIN_LOCKED mesajı kullanıcıya iletilir', () async {
      final h = _makeService(
        (r) => _json({'error': 'x', 'code': 'LOGIN_LOCKED', 'retry_after_seconds': 300}, 429),
      );
      await h.service.initialize();
      final error = await h.service.login(email: 'a@b.c', password: 'x');
      expect(error, 'Çok fazla hatalı deneme yapıldı. 5 dakika sonra tekrar deneyin.');
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });
  });

  group('Merkezi oturum hatası (401) tüm API yollarında', () {
    Future<_Harness> startLoggedIn() async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) {
        if (r.url.path == '/me') return _json(_meBody());
        return _json({'error': 'Gecersiz token.'}, 401);
      });
      await h.service.initialize();
      await _settle();
      expect(h.service.isLoggedIn, isTrue);
      return h;
    }

    test('openDoor 401 -> çıkış', () async {
      final h = await startLoggedIn();
      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      await _settle();
      expect(status, isNull);
      expect(error, isNotNull);
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('openDoorWithScannedQr 401 -> çıkış', () async {
      final h = await startLoggedIn();
      final (res, error) = await h.service.openDoorWithScannedQr(qrPayload: 'abc');
      await _settle();
      expect(res, isNull);
      expect(error, isNotNull);
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('setupSite / createDoor / updateDoor / deleteDoor / getSiteJoinToken 401 -> çıkış', () async {
      final calls = <Future<Object?> Function(AuthService)>[
        (s) => s.setupSite(name: 'x', blocks: const []),
        (s) => s.createDoor(siteCode: 3, doorName: 'x'),
        (s) => s.updateDoor(doorId: 7, doorName: 'x'),
        (s) => s.deleteDoor(doorId: 7),
        (s) => s.getSiteJoinToken(siteCode: 3),
        (s) => s.claimDevice(deviceInput: 'AABBCCDDEEFF'),
      ];
      for (final call in calls) {
        final h = await startLoggedIn();
        await expectLater(call(h.service), throwsA(anything));
        await _settle();
        expect(h.service.isLoggedIn, isFalse);
        h.service.dispose();
      }
    });

    test('eski token\'ın geç gelen 401\'i yeni oturumu kapatmaz', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session(token: 'tok-A')),
      });
      final slowDoors = Completer<http.Response>();
      final h = _makeService((r) {
        if (r.url.path == '/me') return _json(_meBody());
        if (r.url.path == '/app/my-doors') return slowDoors.future;
        if (r.url.path == '/auth/login') {
          return _json({'token': 'tok-B', 'user': _meBody()['user']});
        }
        return _json({'error': 'x'}, 404);
      });
      await h.service.initialize();
      await _settle();

      final pending = h.service.listMyDoors(); // tok-A ile
      await _settle();
      expect(await h.service.login(email: 'ali@example.com', password: 'x'), isNull);
      expect(h.service.session?.token, 'tok-B');

      slowDoors.complete(_json({'error': 'Gecersiz token.'}, 401));
      await pending;
      await _settle();

      expect(h.service.session?.token, 'tok-B');
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });
  });

  group('openDoor: kapı politikası ve C3 geofence', () {
    Future<_Harness> startLoggedIn({
      Future<LocationFixResult> Function()? location,
      FutureOr<http.Response> Function(http.Request r)? onOpen,
    }) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService(
        (r) {
          if (r.url.path == '/me') return _json(_meBody());
          if (r.url.path == '/app/doors/7/open') {
            return onOpen != null ? onOpen(r) : _json(_openStatusBody(), 202);
          }
          return _json({'error': 'beklenmeyen'}, 404);
        },
        locationProvider: location,
      );
      await h.service.initialize();
      await _settle();
      return h;
    }

    test('uzaktan ve yerel açma kapalıysa istek gönderilmeden anlaşılır hata döner', () async {
      final h = await startLoggedIn();
      final (status, error) =
          await h.service.openDoor(doorId: 7, door: _door(remote: false, localUdp: false));
      expect(status, isNull);
      expect(error, contains('açma kapalı'));
      expect(h.where('POST', '/app/doors/7/open'), isEmpty);
      h.service.dispose();
    });

    test('uzaktan açma kapalı + yerelde canlı cihaz yoksa buluta İSTEK gönderilmez', () async {
      final h = await startLoggedIn();
      final (status, error) =
          await h.service.openDoor(doorId: 7, door: _door(remote: false, localUdp: true));
      expect(status, isNull);
      expect(error, contains('Uzaktan') .or(contains('uzaktan')));
      expect(h.where('POST', '/app/doors/7/open'), isEmpty);
      h.service.dispose();
    });

    test('canTryLocalDoorOpen: token önbellekte yoksa veya UDP kapalıysa false', () async {
      final h = await startLoggedIn();
      expect(h.service.canTryLocalDoorOpen(_door()), isFalse, reason: 'token yok -> yerel yok (C4)');
      expect(h.service.canTryLocalDoorOpen(_door(localUdp: false)), isFalse);
      expect(h.service.canTryLocalDoorOpen(_door(uid: null)), isFalse);
      h.service.dispose();
    });

    test('konum zorunlu kapıda konum alınamazsa istek GÖNDERİLMEZ ve neden döner', () async {
      final h = await startLoggedIn(
        location: () async => const LocationFixResult.failure(
          'Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın.',
        ),
      );
      final (status, error) =
          await h.service.openDoor(doorId: 7, door: _door(requireGeofence: true));
      expect(status, isNull);
      expect(error, contains('Konum servisleri kapalı'));
      expect(h.where('POST', '/app/doors/7/open'), isEmpty);
      h.service.dispose();
    });

    test('konum zorunlu kapıda C3 alanları isteğe eklenir', () async {
      final h = await startLoggedIn(
        location: () async => LocationFixResult.success(_position(accuracy: 12)),
      );
      final (status, error) =
          await h.service.openDoor(doorId: 7, door: _door(requireGeofence: true));
      expect(error, isNull);
      expect(status, isNotNull);

      final body = jsonDecode(h.where('POST', '/app/doors/7/open').single.body)
          as Map<String, dynamic>;
      expect(body['latitude'], 41.0);
      expect(body['longitude'], 29.0);
      expect(body['accuracy'], 12.0);
      expect(body['is_mocked'], false);
      expect((body['timestamp'] as String).endsWith('Z'), isTrue);
      h.service.dispose();
    });

    test('konum zorunlu olmayan kapıda konum istenmez ve gövde boştur', () async {
      var locationCalls = 0;
      final h = await startLoggedIn(
        location: () async {
          locationCalls++;
          return LocationFixResult.success(_position());
        },
      );
      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      expect(error, isNull);
      expect(status, isNotNull);
      expect(locationCalls, 0);
      expect(jsonDecode(h.where('POST', '/app/doors/7/open').single.body), isEmpty);
      h.service.dispose();
    });

    test('scan-qr-open: requireLocation true iken konum yoksa istek gönderilmez', () async {
      final h = await startLoggedIn(
        location: () async => const LocationFixResult.failure('Konum izni verilmedi.'),
      );
      final (res, error) =
          await h.service.openDoorWithScannedQr(qrPayload: 'abc', requireLocation: true);
      expect(res, isNull);
      expect(error, 'Konum izni verilmedi.');
      expect(h.where('POST', '/app/doors/scan-qr-open'), isEmpty);
      h.service.dispose();
    });

    test('scan-qr-open: konum varsa C3 alanları gövdeye eklenir', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService(
        (r) {
          if (r.url.path == '/me') return _json(_meBody());
          return _json({'door_name': 'Ana Kapı'});
        },
        locationProvider: () async => LocationFixResult.success(_position()),
      );
      await h.service.initialize();
      await _settle();

      final (res, error) =
          await h.service.openDoorWithScannedQr(qrPayload: 'abc', requireLocation: true);
      expect(error, isNull);
      expect(res?['door_name'], 'Ana Kapı');
      final body = jsonDecode(h.where('POST', '/app/doors/scan-qr-open').single.body)
          as Map<String, dynamic>;
      expect(body['qr_payload'], 'abc');
      expect(body['latitude'], 41.0);
      expect(body['is_mocked'], false);
      h.service.dispose();
    });

    test('kapı açma komutu ağ hatasında tekrar GÖNDERİLMEZ (çift açma yok)', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) {
        if (r.url.path == '/me') return _json(_meBody());
        throw http.ClientException('connection reset');
      });
      await h.service.initialize();
      await _settle();

      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      expect(status, isNull);
      expect(error, isNotNull);
      expect(h.where('POST', '/app/doors/7/open'), hasLength(1));
      h.service.dispose();
    });
  });

  group('Sunucu konum istiyorsa ikinci şans (yan etkisiz ret sonrası tek yeniden deneme)', () {
    Future<_Harness> startLoggedIn(
      FutureOr<http.Response> Function(http.Request r) handler, {
      Future<LocationFixResult> Function()? location,
    }) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService(
        (r) {
          if (r.url.path == '/me') return _json(_meBody());
          return handler(r);
        },
        locationProvider: location,
      );
      await h.service.initialize();
      await _settle();
      return h;
    }

    test('openDoor: GEOFENCE_LOCATION_REQUIRED -> konum alınır ve BİR kez yeniden denenir', () async {
      var openCalls = 0;
      final h = await startLoggedIn(
        (r) {
          openCalls++;
          if (openCalls == 1) {
            return _json({'error': 'x', 'code': 'GEOFENCE_LOCATION_REQUIRED'}, 403);
          }
          return _json(_openStatusBody(), 202);
        },
        location: () async => LocationFixResult.success(_position()),
      );

      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      expect(error, isNull);
      expect(status, isNotNull);

      final calls = h.where('POST', '/app/doors/7/open').toList();
      expect(calls, hasLength(2));
      expect(jsonDecode(calls[0].body), isEmpty);
      expect((jsonDecode(calls[1].body) as Map)['latitude'], 41.0);
      h.service.dispose();
    });

    test('openDoor: konum alınamazsa ikinci istek GÖNDERİLMEZ, neden gösterilir', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'GEOFENCE_LOCATION_REQUIRED'}, 403),
        location: () async => const LocationFixResult.failure('Konum izni verilmedi.'),
      );

      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      expect(status, isNull);
      expect(error, 'Konum izni verilmedi.');
      expect(h.where('POST', '/app/doors/7/open'), hasLength(1));
      h.service.dispose();
    });

    test('scan-qr-open: konum zorunlu değil denen kapıda sunucu isterse yeniden denenir', () async {
      var calls = 0;
      final h = await startLoggedIn(
        (r) {
          calls++;
          if (calls == 1) {
            return _json({'error': 'x', 'code': 'GEOFENCE_LOCATION_REQUIRED'}, 403);
          }
          return _json({'door_name': 'Ana Kapı'});
        },
        location: () async => LocationFixResult.success(_position()),
      );

      final (res, error) = await h.service.openDoorWithScannedQr(qrPayload: 'abc');
      expect(error, isNull);
      expect(res?['door_name'], 'Ana Kapı');
      final scans = h.where('POST', '/app/doors/scan-qr-open').toList();
      expect(scans, hasLength(2));
      expect((jsonDecode(scans[1].body) as Map)['qr_payload'], 'abc');
      expect((jsonDecode(scans[1].body) as Map)['is_mocked'], false);
      h.service.dispose();
    });

    test('diğer 403 kodlarında (örn. REMOTE_OPEN_DISABLED) yeniden deneme YAPILMAZ', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'REMOTE_OPEN_DISABLED'}, 403),
        location: () async => LocationFixResult.success(_position()),
      );
      final (status, error) = await h.service.openDoor(doorId: 7, door: _door());
      expect(status, isNull);
      expect(error, 'Bu sitede uygulamadan uzaktan kapı açma kapalı.');
      expect(h.where('POST', '/app/doors/7/open'), hasLength(1));
      h.service.dispose();
    });

    test('daire üyesi şifre değişimi: yeni token oturuma ve güvenli depoya yazılır', () async {
      final h = await startLoggedIn(
        (r) => _json({'ok': true, 'message': 'Güncellendi', 'token': 'tok-yeni'}),
      );
      final (ok, message) = await h.service.changeApartmentMemberPassword(
        apartmentId: 4,
        targetUserCode: 5,
        newPassword: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      expect(ok, isTrue);
      expect(message, 'Güncellendi');
      expect(h.service.session?.token, 'tok-yeni');
      final stored = await const FlutterSecureStorage().read(key: _storageKey);
      expect(jsonDecode(stored!)['token'], 'tok-yeni');
      final body = jsonDecode(
        h.where('POST', '/membership/apartments/4/members/5/change-password').single.body,
      ) as Map<String, dynamic>;
      expect(body['current_password'], 'eskiSifre1');
      h.service.dispose();
    });

    test('daire üyesi şifre değişimi mevcut şifre olmadan istek göndermez', () async {
      final h = await startLoggedIn((r) => _json({'ok': true}));
      final (ok, message) = await h.service.changeApartmentMemberPassword(
        apartmentId: 4,
        targetUserCode: 5,
        newPassword: 'yeniSifre1',
        currentPassword: '',
      );
      expect(ok, isFalse);
      expect(message, contains('mevcut şifrenizi'));
      expect(h.where('POST', '/membership/apartments/4/members/5/change-password'), isEmpty);
      h.service.dispose();
    });

    test('doğrulama kodu 404 -> kodun 10 dk geçerli olduğu ve yeniden gönderme ipucu', () async {
      final h = _makeService(
        (r) => _json({'error': 'Aktif bir dogrulama kodu bulunamadi.'}, 404),
      );
      await h.service.initialize();
      final error = await h.service.verifyIndividualCode(email: 'a@b.c', code: '123456');
      expect(error, contains('Aktif bir dogrulama kodu bulunamadi.'));
      expect(error, contains('10 dakika'));
      expect(error, contains('Kodu Tekrar Gönder'));

      final wrongCode = _makeService((r) => _json({'error': 'Kod hatali.'}, 400));
      await wrongCode.service.initialize();
      expect(
        await wrongCode.service.verifyIndividualCode(email: 'a@b.c', code: '123456'),
        'Kod hatali.',
      );
      h.service.dispose();
      wrongCode.service.dispose();
    });
  });

  group('Profil ve cihaz log senkronu', () {
    Future<_Harness> startLoggedIn(
      FutureOr<http.Response> Function(http.Request r) handler,
    ) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) {
        if (r.url.path == '/me' && r.method == 'GET') return _json(_meBody());
        return handler(r);
      });
      await h.service.initialize();
      await _settle();
      return h;
    }

    test('şifre değişiyorsa mevcut şifre olmadan istek gönderilmez', () async {
      final h = await startLoggedIn((r) => _json(_meBody()));
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
      );
      expect(error, contains('mevcut şifre'));
      expect(h.where('PATCH', '/me'), isEmpty);
      h.service.dispose();
    });

    test('şifre değişiminde current_password gönderilir', () async {
      final h = await startLoggedIn((r) => _json(_meBody()));
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      expect(error, isNull);
      final body = jsonDecode(h.where('PATCH', '/me').single.body) as Map<String, dynamic>;
      expect(body['current_password'], 'eskiSifre1');
      expect(body['password'], 'yeniSifre1');
      h.service.dispose();
    });

    test('yanlış mevcut şifre (400 CURRENT_PASSWORD_INVALID) mesajı gösterilir ama oturum kapatılmaz', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'Mevcut parola hatali.', 'code': 'CURRENT_PASSWORD_INVALID'}, 400),
      );
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'yanlis',
      );
      await _settle();
      expect(error, 'Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.');
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });

    test('PATCH /me 401 TOKEN_REVOKED (gerçek oturum sonu) oturumu kapatır ve nedeni açıklar', () async {
      final h = await startLoggedIn(
        (r) => _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401),
      );
      final error = await h.service.updateMyProfile(
        fullName: 'Yeni Ad',
        email: 'ali@example.com',
      );
      await _settle();
      expect(error, contains('Şifreniz değiştirildiği için'));
      expect(h.service.isLoggedIn, isFalse,
          reason: 'profil kaydederken alınan gerçek 401 ölü token ile ekranda bırakmamalı');
      expect(h.service.takeSessionNotice(), contains('Şifreniz değiştirildiği için'));
      h.service.dispose();
    });

    test('syncDeviceLogs Authorization başlığını gönderir', () async {
      final h = await startLoggedIn((r) => _json({'synced_count': 2}));
      final (count, error) = await h.service.syncDeviceLogs(
        deviceUid: 'AABBCCDDEEFF',
        logs: [
          {'action': 'open'},
        ],
      );
      expect(error, isNull);
      expect(count, 2);
      final req = h.where('POST', '/device/sync-logs').single;
      expect(req.headers['Authorization'], 'Bearer tok-A');
      h.service.dispose();
    });

    test('syncDeviceLogs oturum yoksa istek göndermez', () async {
      final h = _makeService((r) => _json({'synced_count': 2}));
      await h.service.initialize();
      final (count, error) = await h.service.syncDeviceLogs(
        deviceUid: 'AABBCCDDEEFF',
        logs: const [],
      );
      expect(count, 0);
      expect(error, isNotNull);
      expect(h.requests, isEmpty);
      h.service.dispose();
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
