// FX1 düzeltmeleri: oturum / API katmanı regresyon testleri (DB'siz, MockClient).
//
// error-contract#2/#3/#10, auth-session#1/#5, site-manager-admin#7, door-open#4/#5/#6.
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
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';

const _storageKey = 'auth_session';

UserSession _session({String token = 'tok-A', UserRole role = UserRole.individual}) {
  return UserSession(
    id: 5,
    fullName: 'Ali Veli',
    email: 'ali@example.com',
    loginName: null,
    role: role,
    isActive: true,
    token: token,
  );
}

String _sessionRaw(UserSession s) => jsonEncode(s.toJson());

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _html(int status) => http.Response(
      '<html><body><h1>$status</h1> Access Denied - proxy/WAF</body></html>',
      status,
      headers: {'content-type': 'text/html'},
    );

Map<String, dynamic> _meBody({String role = 'individual'}) => {
      'user': {
        'id': 5,
        'full_name': 'Ali Veli',
        'email': 'ali@example.com',
        'login_name': null,
        'role': role,
        'is_active': true,
      },
    };

DoorRecord _door({bool remote = true, bool localUdp = true}) {
  return DoorRecord(
    id: 7,
    siteCode: 3,
    siteName: 'Güneş Sitesi',
    doorName: 'Ana Kapı',
    doorIndex: 1,
    isActive: true,
    assignedDeviceId: 1,
    assignedDeviceUid: 'AABBCCDDEEFF',
    mqttSiteId: 3,
    featureRemoteOpenEnabled: remote,
    featureLocalUdpEnabled: localUdp,
    createdAt: DateTime(2026, 1, 1),
  );
}

Position _position() => Position(
      latitude: 41.0,
      longitude: 29.0,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: false,
    );

Map<String, dynamic> _statusBody({String? localToken}) => {
      'door': {'id': 7, 'site_code': 3, 'door_name': 'Ana Kapı', 'door_index': 1},
      'device_status': {
        'device_uid': 'AABBCCDDEEFF',
        'mqtt_connected': true,
        if (localToken != null)
          'local_control': {
            'token': localToken,
            'ip': '192.168.1.50',
            'port': 8765,
            'available': true,
          },
      },
    };

AuthApi _api(Future<http.Response> Function(http.Request request) handler) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient(handler),
    retryDelay: Duration.zero,
  );
}

class _Harness {
  _Harness(this.service, this.requests);

  final AuthService service;
  final List<http.Request> requests;

  Iterable<http.Request> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);
}

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

/// Kayıtlı oturumla başlatır; açılıştaki GET /me başarılı döner (rol [meRole]).
Future<_Harness> _startLoggedIn(
  FutureOr<http.Response> Function(http.Request r) handler, {
  UserSession? session,
  String meRole = 'individual',
  Future<LocationFixResult> Function()? location,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    _storageKey: _sessionRaw(session ?? _session()),
  });
  final h = _makeService(
    (r) {
      if (r.url.path == '/me' && r.method == 'GET') return _json(_meBody(role: meRole));
      return handler(r);
    },
    locationProvider: location,
  );
  await h.service.initialize();
  await _settle();
  return h;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('error-contract#2: JSON olmayan 401/403 (proxy / WAF / captive portal) oturum sonu değildir', () {
    test('HTML 403: ara katman hatası olarak sınıflanır, "modem yok" demez, hesap-pasif sinyali değildir', () async {
      final api = _api((r) async => _html(403));
      await expectLater(
        api.fetchMe(token: 't', current: _session()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.fromIntermediary, 'fromIntermediary', isTrue)
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.isForbidden, 'isForbidden', isFalse)
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse)
              .having((e) => e.message.contains('Modem'), 'modem', isFalse)
              .having((e) => e.message, 'message', contains('Sunucuya ulaşılamadı')),
        ),
      );
    });

    test('HTML / düz metin 401: SessionExpiredException DEĞİL, oturumu kapatmaz', () async {
      for (final response in [_html(401), http.Response('Unauthorized', 401)]) {
        final api = _api((r) async => response);
        await expectLater(
          api.listMyDoors(token: 't'),
          throwsA(
            isA<ApiException>()
                .having((e) => e is SessionExpiredException, 'sessionExpired', isFalse)
                .having((e) => e.isUnauthorized, 'isUnauthorized', isFalse)
                .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
          ),
          reason: response.body,
        );
      }
    });

    test('sunucunun JSON hata zarfı olan 401/403 hâlâ oturum / hesap sinyalidir', () async {
      await expectLater(
        _api((r) async => _json({'error': 'x'}, 401)).listMyDoors(token: 't'),
        throwsA(isA<SessionExpiredException>()),
      );
      await expectLater(
        _api((r) async => _json({'error': 'Hesap aktif degil.'}, 403))
            .fetchMe(token: 't', current: _session()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isForbidden, 'isForbidden', isTrue)
              .having((e) => e.fromIntermediary, 'fromIntermediary', isFalse),
        ),
      );
    });

    test('AuthService: HTML 403 /me yoklaması oturumu kapatmaz ve bildirim üretmez', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) => _html(403));
      await h.service.initialize();
      await _settle();
      expect(h.where('GET', '/me'), isNotEmpty);
      expect(h.service.isLoggedIn, isTrue, reason: 'WAF/proxy engeli oturumu bitirmemeli');
      expect(h.service.takeSessionNotice(), isNull);
      h.service.dispose();
    });

    test('AuthService: HTML 401 yetkili istek oturumu kapatmaz', () async {
      final h = await _startLoggedIn((r) => _html(401));
      final (doors, error) = await h.service.listMyDoors();
      await _settle();
      expect(doors, isNull);
      expect(error, isNotNull);
      expect(h.service.isLoggedIn, isTrue);
      expect(h.service.takeSessionNotice(), isNull);
      h.service.dispose();
    });

    test('AuthService: HTML 403 yetkili istek /me hesap doğrulamasını da tetiklemez', () async {
      final h = await _startLoggedIn((r) => _html(403));
      final meBefore = h.where('GET', '/me').length;
      await h.service.listMyDoors();
      await _settle();
      await h.service.refreshSession(force: false);
      expect(h.where('GET', '/me').length, meBefore,
          reason: 'ara katman 403 hesap-pasif sinyali değildir');
      expect(h.service.isLoggedIn, isTrue);
      h.service.dispose();
    });
  });

  group('error-contract#3: deleteSite yalnızca 2xx başarıdır', () {
    for (final status in [400, 401, 403, 500, 502, 504]) {
      test('boş gövdeli $status başarı SAYILMAZ', () async {
        final api = _api((r) async => http.Response('', status));
        await expectLater(
          api.deleteSite(token: 't', role: UserRole.siteManager, siteCode: 3),
          throwsA(isA<ApiException>()),
        );
      });
    }

    test('204 ve boş gövdeli 200 silinmiş sayılır; JSON gövde aynen döner', () async {
      final noContent = _api((r) async => http.Response('', 204));
      expect(
        await noContent.deleteSite(token: 't', role: UserRole.siteManager, siteCode: 3),
        {'ok': true, 'deleted': true},
      );
      final emptyOk = _api((r) async => http.Response('', 200));
      expect(
        await emptyOk.deleteSite(token: 't', role: UserRole.superUser, siteCode: 3),
        {'ok': true, 'deleted': true},
      );
      final pending = _api(
        (r) async => _json({'ok': true, 'pending': true, 'message': 'Talep iletildi.'}),
      );
      final res = await pending.deleteSite(token: 't', role: UserRole.siteManager, siteCode: 3);
      expect(res['pending'], isTrue);
      expect(res['deleted'], isNull);
    });

    test('AuthService.deleteSite: boş gövdeli 502 "Site silindi." demez', () async {
      final h = await _startLoggedIn(
        (r) => http.Response('', 502),
        session: _session(role: UserRole.siteManager),
        meRole: 'site_manager',
      );
      final result = await h.service.deleteSite(siteCode: 3);
      expect(result.deleted, isFalse);
      expect(result.error, isNotNull);
      h.service.dispose();
    });
  });

  group('site-manager-admin#7: e-posta doğrulandı bilgisi sunucuya gider', () {
    test('AuthApi.updateManagedUser: email_verified yalnızca verildiğinde (false dahil) gövdeye eklenir', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _api((r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        expect(r.method, 'PATCH');
        expect(r.url.path, '/admin/users/9');
        return _json({'user': {}});
      });
      await api.updateManagedUser(token: 't', userCode: 9, fullName: 'Ali Veli', emailVerified: true);
      await api.updateManagedUser(token: 't', userCode: 9, fullName: 'Ali Veli', emailVerified: false);
      await api.updateManagedUser(token: 't', userCode: 9, fullName: 'Ali Veli');

      expect(bodies[0]['email_verified'], isTrue);
      expect(bodies[1]['email_verified'], isFalse, reason: 'false değeri de iletilmeli');
      expect(bodies[2].containsKey('email_verified'), isFalse, reason: 'değişmediyse sunucuya dokunulmaz');
    });

    test('AuthService.updateManagedUser: kendi parolası 400 USE_PROFILE_PASSWORD_CHANGE -> kısa mesaj, oturum açık', () async {
      final h = await _startLoggedIn(
        (r) => _json({
          'error': 'Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin.',
          'code': 'USE_PROFILE_PASSWORD_CHANGE',
        }, 400),
        session: _session(role: UserRole.superUser),
        meRole: 'super_user',
      );
      final error = await h.service.updateManagedUser(userCode: 5, password: 'yeniSifre1');
      await _settle();
      expect(error, 'Kendi şifrenizi Profilim ekranından değiştirin.');
      expect(h.service.isLoggedIn, isTrue, reason: '400 oturum sonu değildir');
      h.service.dispose();
    });

    test('AuthService.updateManagedUser emailVerified parametresini iletir', () async {
      final h = await _startLoggedIn(
        (r) => _json({'user': {}}),
        session: _session(role: UserRole.superUser),
        meRole: 'super_user',
      );
      final error = await h.service.updateManagedUser(userCode: 9, emailVerified: true);
      expect(error, isNull);
      final body = jsonDecode(h.where('PATCH', '/admin/users/9').single.body) as Map<String, dynamic>;
      expect(body['email_verified'], isTrue);
      h.service.dispose();
    });
  });

  group('auth-session#1: PATCH /me gerçek 401 oturumu kapatır', () {
    test('profil kaydederken TOKEN_REVOKED -> çıkış (şifre değişmese de)', () async {
      final h = await _startLoggedIn(
        (r) => _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401),
      );
      final error = await h.service.updateMyProfile(fullName: 'Yeni Ad', email: 'ali@example.com');
      await _settle();
      expect(error, contains('Şifreniz değiştirildiği için'));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('süresi dolmuş token (401, kodsuz) -> çıkış', () async {
      final h = await _startLoggedIn(
        (r) => _json({'error': 'Gecersiz veya suresi dolmus token.'}, 401),
      );
      await h.service.updateMyProfile(fullName: 'Yeni Ad', email: 'ali@example.com');
      await _settle();
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });
  });

  group('auth-session#5 / error-contract#5: parola değişimi sırasında eşzamanlı TOKEN_REVOKED', () {
    test('eşzamanlı isteğin TOKEN_REVOKED 401\'i oturumu kapatmaz; PATCH yanıtı yeni token\'ı yazar', () async {
      final patchGate = Completer<http.Response>();
      final h = await _startLoggedIn((r) {
        if (r.method == 'PATCH' && r.url.path == '/me') return patchGate.future;
        if (r.url.path == '/app/my-doors') {
          return _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401);
        }
        return _json({'error': 'x'}, 404);
      });

      final pending = h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      await _settle(); // PATCH sunucuya gitti, yanıt bekleniyor

      // Sunucu parolayı yazdı; eski token'lı 3 sn'lik yoklama TOKEN_REVOKED aldı.
      await h.service.listMyDoors();
      await _settle();
      expect(h.service.isLoggedIn, isTrue, reason: 'yeni token yanıtla gelecek; oturum kapanmamalı');
      expect(h.service.takeSessionNotice(), isNull);

      final body = _meBody();
      body['token'] = 'tok-yeni';
      patchGate.complete(_json(body));
      expect(await pending, isNull);

      expect(h.service.isLoggedIn, isTrue);
      expect(h.service.session?.token, 'tok-yeni');
      final stored = await const FlutterSecureStorage().read(key: _storageKey);
      expect(jsonDecode(stored!)['token'], 'tok-yeni');
      h.service.dispose();
    });

    test('eşzamanlı /me doğrulaması (ön plana dönüş) TOKEN_REVOKED alsa da değişim sürerken çıkış yapmaz', () async {
      final patchGate = Completer<http.Response>();
      var meCalls = 0;
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        _storageKey: _sessionRaw(_session()),
      });
      final h = _makeService((r) {
        if (r.url.path == '/me' && r.method == 'GET') {
          meCalls++;
          return meCalls == 1
              ? _json(_meBody())
              : _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401);
        }
        if (r.method == 'PATCH' && r.url.path == '/me') return patchGate.future;
        return _json({'error': 'x'}, 404);
      });
      await h.service.initialize();
      await _settle();

      final pending = h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      await _settle();
      await h.service.refreshSession(force: true);
      await _settle();
      expect(meCalls, 2);
      expect(h.service.isLoggedIn, isTrue);
      expect(h.service.takeSessionNotice(), isNull);

      final body = _meBody();
      body['token'] = 'tok-yeni';
      patchGate.complete(_json(body));
      expect(await pending, isNull);
      expect(h.service.session?.token, 'tok-yeni');
      h.service.dispose();
    });

    test('parola değişiminin KENDİ isteği TOKEN_REVOKED alırsa bu gerçek oturum sonudur', () async {
      final h = await _startLoggedIn((r) {
        if (r.method == 'PATCH' && r.url.path == '/me') {
          return _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401);
        }
        return _json({'error': 'x'}, 404);
      });
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      await _settle();
      expect(error, contains('Şifreniz değiştirildiği için'));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    test('parola değişimi bittikten sonra gelen TOKEN_REVOKED yine oturumu kapatır (sayaç sızmaz)', () async {
      final h = await _startLoggedIn((r) {
        if (r.method == 'PATCH' && r.url.path == '/me') {
          return _json({'error': 'x', 'code': 'CURRENT_PASSWORD_INVALID'}, 400);
        }
        if (r.url.path == '/app/my-doors') {
          return _json({'error': 'iptal', 'code': 'TOKEN_REVOKED'}, 401);
        }
        return _json({'error': 'x'}, 404);
      });
      final error = await h.service.updateMyProfile(
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        password: 'yeniSifre1',
        currentPassword: 'yanlis',
      );
      expect(error, contains('Mevcut şifreniz hatalı'));
      expect(h.service.isLoggedIn, isTrue);

      await h.service.listMyDoors();
      await _settle();
      expect(h.service.isLoggedIn, isFalse, reason: 'swap penceresi kapandı; TOKEN_REVOKED artık oturumu bitirir');
      h.service.dispose();
    });

    test('PATCH yanıtı beklenirken çıkış yapıldıysa oturum yeniden yazılmaz', () async {
      final patchGate = Completer<http.Response>();
      final h = await _startLoggedIn((r) {
        if (r.method == 'PATCH' && r.url.path == '/me') return patchGate.future;
        return _json({'error': 'x'}, 404);
      });

      final pending = h.service.updateMyProfile(fullName: 'Yeni Ad', email: 'ali@example.com');
      await _settle();
      await h.service.logout();
      patchGate.complete(_json(_meBody()));
      expect(await pending, isNull);

      expect(h.service.isLoggedIn, isFalse, reason: 'geç gelen yanıt oturumu diriltmemeli');
      expect(await const FlutterSecureStorage().read(key: _storageKey), isNull);
      h.service.dispose();
    });
  });

  group('door-open#4: qr-token isteğinde konumlu tek yeniden deneme', () {
    test('GEOFENCE_LOCATION_REQUIRED -> konum alınır ve BİR kez yeniden denenir', () async {
      var calls = 0;
      final h = await _startLoggedIn(
        (r) {
          if (r.url.path != '/app/doors/7/qr-token') return _json({'error': 'x'}, 404);
          calls++;
          if (calls == 1) {
            return _json({'error': 'x', 'code': 'GEOFENCE_LOCATION_REQUIRED'}, 403);
          }
          return _json({'token': 'QR:abc'});
        },
        location: () async => LocationFixResult.success(_position()),
      );

      final (data, error) = await h.service.requestDoorQrToken(7);
      expect(error, isNull);
      expect(data?['token'], 'QR:abc');

      final calls2 = h.where('POST', '/app/doors/7/qr-token').toList();
      expect(calls2, hasLength(2));
      expect(jsonDecode(calls2[0].body), isEmpty, reason: 'ilk istek konumsuz');
      final location = (jsonDecode(calls2[1].body) as Map<String, dynamic>)['location'] as Map;
      expect(location['latitude'], 41.0);
      expect(location['is_mocked'], false);
      h.service.dispose();
    });

    test('konum alınamazsa ikinci istek GÖNDERİLMEZ ve neden gösterilir', () async {
      final h = await _startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'GEOFENCE_LOCATION_REQUIRED'}, 403),
        location: () async => const LocationFixResult.failure('Konum izni verilmedi.'),
      );
      final (data, error) = await h.service.requestDoorQrToken(7);
      expect(data, isNull);
      expect(error, 'Konum izni verilmedi.');
      expect(h.where('POST', '/app/doors/7/qr-token'), hasLength(1));
      h.service.dispose();
    });

    test('diğer 403 kodlarında yeniden deneme YAPILMAZ ve konum istenmez', () async {
      var locationCalls = 0;
      final h = await _startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'QR_DISABLED'}, 403),
        location: () async {
          locationCalls++;
          return LocationFixResult.success(_position());
        },
      );
      final (data, error) = await h.service.requestDoorQrToken(7);
      expect(data, isNull);
      expect(error, 'Bu sitede QR ile giriş kapalı.');
      expect(h.where('POST', '/app/doors/7/qr-token'), hasLength(1));
      expect(locationCalls, 0);
      h.service.dispose();
    });

    test('konum zaten gönderildiyse GEOFENCE_LOCATION_REQUIRED tekrar denenmez', () async {
      final h = await _startLoggedIn(
        (r) => _json({'error': 'x', 'code': 'GEOFENCE_LOCATION_REQUIRED'}, 403),
        location: () async => LocationFixResult.success(_position()),
      );
      final (data, error) = await h.service.requestDoorQrToken(
        7,
        location: GeofenceService.locationRequestFields(_position()),
      );
      expect(data, isNull);
      expect(error, isNotNull);
      expect(h.where('POST', '/app/doors/7/qr-token'), hasLength(1));
      h.service.dispose();
    });
  });

  group('door-open#5: süper kullanıcı remote/local politikası istisnası istemcide de uygulanır', () {
    test('süper kullanıcı: uzaktan ve yerel açma kapalı kapıda istek yine de gönderilir', () async {
      final h = await _startLoggedIn(
        (r) => r.url.path == '/app/doors/7/open'
            ? _json(_statusBody(), 202)
            : _json({'error': 'x'}, 404),
        session: _session(role: UserRole.superUser),
        meRole: 'super_user',
      );
      final (status, error) =
          await h.service.openDoor(doorId: 7, door: _door(remote: false, localUdp: false));
      expect(error, isNull);
      expect(status, isNotNull);
      expect(h.where('POST', '/app/doors/7/open'), hasLength(1));
      h.service.dispose();
    });

    test('süper olmayan kullanıcı: aynı kapıda istek GÖNDERİLMEZ (mevcut davranış korunur)', () async {
      final h = await _startLoggedIn(
        (r) => _json(_statusBody(), 202),
        meRole: 'site_manager',
        session: _session(role: UserRole.siteManager),
      );
      final (status, error) =
          await h.service.openDoor(doorId: 7, door: _door(remote: false, localUdp: false));
      expect(status, isNull);
      expect(error, contains('açma kapalı'));
      expect(h.where('POST', '/app/doors/7/open'), isEmpty);
      h.service.dispose();
    });
  });

  group('door-open#6: yerel açma yalnızca token + politika varsa mümkündür', () {
    Future<_Harness> withLocalToken(UserRole role, String meRole) async {
      final h = await _startLoggedIn(
        (r) => r.url.path == '/app/doors/7/status'
            ? _json(_statusBody(localToken: 'LTOK-1'))
            : _json({'error': 'x'}, 404),
        session: _session(role: role),
        meRole: meRole,
      );
      final (status, error) = await h.service.getDoorRuntimeStatus(doorId: 7);
      expect(error, isNull);
      expect(status, isNotNull);
      return h;
    }

    test('token önbellekteyse ve politika açıksa true; politika kapalıysa (süper değilse) false', () async {
      final h = await withLocalToken(UserRole.individual, 'individual');
      expect(h.service.canTryLocalDoorOpen(_door(localUdp: true)), isTrue);
      expect(h.service.canTryLocalDoorOpen(_door(localUdp: false)), isFalse);
      h.service.dispose();
    });

    test('süper kullanıcı için politika bayrağı yok sayılır (token yine sunucudan gelmeli)', () async {
      final h = await withLocalToken(UserRole.superUser, 'super_user');
      expect(h.service.canTryLocalDoorOpen(_door(localUdp: false)), isTrue);
      h.service.dispose();

      final noToken = await _startLoggedIn(
        (r) => _json({'error': 'x'}, 404),
        session: _session(role: UserRole.superUser),
        meRole: 'super_user',
      );
      expect(noToken.service.canTryLocalDoorOpen(_door(localUdp: false)), isFalse,
          reason: 'token yoksa süper kullanıcı için de yerel yok (C4)');
      noToken.service.dispose();
    });
  });

  group('error-contract#10: kapı durumu hatası türüne göre sınıflanır (mesaj alt dizisine değil)', () {
    Future<bool> cloudDownAfter(FutureOr<http.Response> Function(http.Request r) handler) async {
      final h = await _startLoggedIn(handler);
      final (status, error) = await h.service.getDoorRuntimeStatus(doorId: 7);
      final flag = h.service.isDoorStatusCloudUnreachable(7);
      if (status == null) {
        expect(error, isNotNull);
      }
      h.service.dispose();
      return flag;
    }

    test('ağ yok, zaman aşımı, 5xx, proxy HTML ve captive portal -> bulut erişilemiyor', () async {
      expect(await cloudDownAfter((r) => throw http.ClientException('connection reset')), isTrue);
      expect(await cloudDownAfter((r) => _json({'error': 'x'}, 503)), isTrue);
      expect(await cloudDownAfter((r) => http.Response('<html>Bad Gateway</html>', 502)), isTrue);
      expect(await cloudDownAfter((r) => http.Response('<html>Login to modem</html>', 200)), isTrue);
      expect(await cloudDownAfter((r) => _html(403)), isTrue);
    });

    test('sunucunun açık iş hataları ve başarı bulut sorunu SAYILMAZ', () async {
      expect(
        await cloudDownAfter(
          (r) => _json({'error': 'Kapi bulunamadi.', 'code': 'DOOR_NOT_FOUND'}, 404),
        ),
        isFalse,
      );
      expect(
        await cloudDownAfter((r) => _json({'error': 'x', 'code': 'DEVICE_OFFLINE'}, 409)),
        isFalse,
      );
      expect(await cloudDownAfter((r) => _json(_statusBody())), isFalse);
    });

    test('bayrak son yoklamaya göredir: hata sonrası başarı bayrağı temizler', () async {
      var fail = true;
      final h = await _startLoggedIn((r) {
        if (r.url.path != '/app/doors/7/status') return _json({'error': 'x'}, 404);
        return fail ? _json({'error': 'x'}, 503) : _json(_statusBody());
      });
      await h.service.getDoorRuntimeStatus(doorId: 7);
      expect(h.service.isDoorStatusCloudUnreachable(7), isTrue);
      fail = false;
      await h.service.getDoorRuntimeStatus(doorId: 7);
      expect(h.service.isDoorStatusCloudUnreachable(7), isFalse);
      h.service.dispose();
    });
  });
}
