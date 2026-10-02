import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

const _doorJson = <String, dynamic>{
  'id': 7,
  'site_code': 3,
  'door_name': 'Ana Kapı',
  'door_index': 1,
};

Map<String, dynamic> _runtimeStatusJson() => {
      'door': _doorJson,
      'device_status': {
        'device_uid': 'AABBCCDDEEFF',
        'mqtt_connected': true,
        'mqtt_bridge_connected': true,
      },
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

AuthApi _api(
  Future<http.Response> Function(http.Request request) handler, {
  Duration? doorOpenTimeout,
  Duration? requestTimeout,
}) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient(handler),
    doorOpenTimeout: doorOpenTimeout,
    requestTimeout: requestTimeout,
    retryDelay: Duration.zero,
  );
}

void main() {
  group('Retry policy: yalnızca GET tekrar denenir', () {
    test('GET aktarım hatasında bir kez yeniden denenir ve başarılı olur', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('connection reset');
        }
        return _json({'doors': <dynamic>[]});
      });

      final doors = await api.listMyDoors(token: 't');
      expect(doors, isEmpty);
      expect(calls, 2);
    });

    test('GET iki kez de başarısız olursa hata fırlatır (en fazla 2 deneme)', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        throw http.ClientException('connection reset');
      });

      await expectLater(api.listMyDoors(token: 't'), throwsA(isA<ApiException>()));
      expect(calls, 2);
    });

    test('POST (kapı açma) aktarım hatasında ASLA tekrar edilmez', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        throw http.ClientException('connection reset');
      });

      await expectLater(
        api.openDoor(token: 't', doorId: 7),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    });

    test('PATCH / DELETE / PUT mutasyonları da tekrar edilmez', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        throw http.ClientException('connection reset');
      });

      await expectLater(
        api.updateDoor(token: 't', doorId: 7, doorName: 'x'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.deleteManagedUser(token: 't', userCode: 5),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.setManagedUserActivation(token: 't', userCode: 5, isActive: false),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 3, reason: 'her mutasyon tam bir kez denenmeli');
    });

    test('mutasyon zaman aşımında tekrar edilmez ve işlemin belirsiz olduğu söylenir', () async {
      var calls = 0;
      final api = _api(
        (request) {
          calls++;
          return Completer<http.Response>().future; // asla cevap vermez
        },
        requestTimeout: const Duration(milliseconds: 40),
      );

      await expectLater(
        api.createDoor(token: 't', siteCode: 3, doorName: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('tamamlanmış olabilir'),
          ),
        ),
      );
      expect(calls, 1);
    });

    test('kapı açma 10 sn (burada kısaltılmış) zaman aşımı kullanır ve tekrar etmez', () async {
      var calls = 0;
      final api = _api(
        (request) {
          calls++;
          return Completer<http.Response>().future;
        },
        doorOpenTimeout: const Duration(milliseconds: 40),
        requestTimeout: const Duration(seconds: 30),
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(
        api.openDoor(token: 't', doorId: 7),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Kapı açılmış olabilir'),
          ),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(calls, 1);
    });
  });

  group('Durum kodu sınıflandırması', () {
    test('yetkili istekte 401, hata metninden bağımsız SessionExpiredException olur', () async {
      for (final text in ['Kullanici bulunamadi.', 'xyz', '']) {
        final api = _api((request) async => _json({'error': text}, 401));
        await expectLater(
          api.listMyDoors(token: 't'),
          throwsA(isA<SessionExpiredException>()),
          reason: 'error="$text"',
        );
      }
    });

    test('boş gövdeli 401 de oturum hatasıdır', () async {
      final api = _api((request) async => http.Response('', 401));
      await expectLater(api.listMyDoors(token: 't'), throwsA(isA<SessionExpiredException>()));
    });

    test('giriş uçlarında 401 oturum süresi değil, sunucu mesajıdır', () async {
      final api = _api(
        (request) async => _json({'error': 'E-posta veya sifre hatali.'}, 401),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e is SessionExpiredException, 'sessionExpired', isFalse)
              .having((e) => e.message, 'message', 'E-posta veya sifre hatali.'),
        ),
      );
    });

    test('403 durum kodu ve makine kodu ApiException içinde taşınır', () async {
      final api = _api(
        (request) async =>
            _json({'error': 'Kapı konumunda değilsiniz.', 'code': 'GEOFENCE_EXCEEDED'}, 403),
      );
      await expectLater(
        api.openDoor(token: 't', doorId: 7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.isForbidden, 'isForbidden', isTrue)
              .having((e) => e.isUnauthorized, 'isUnauthorized', isFalse)
              .having((e) => e.code, 'code', 'GEOFENCE_EXCEEDED'),
        ),
      );
    });

    test('502/503/504 HTML yanıtı "modem yok" değil sunucu sorunu olarak sınıflandırılır', () async {
      for (final status in [502, 503, 504]) {
        final api = _api(
          (request) async => http.Response(
            '<html><body>Bad Gateway - nginx gateway router</body></html>',
            status,
          ),
        );
        await expectLater(
          api.listMyDoors(token: 't'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.message, 'message', contains('Sunucu geçici olarak yanıt vermiyor'))
                .having((e) => e.message.contains('Modem'), 'modem', isFalse),
          ),
          reason: 'status $status',
        );
      }
    });

    test('200 dönen HTML (captive portal) hâlâ internet/modem uyarısı verir', () async {
      final api = _api((request) async => http.Response('<html>Login to modem</html>', 200));
      await expectLater(
        api.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('Modem')),
        ),
      );
    });

    test('5xx JSON yanıtında errorId destek kodu mesaja eklenir', () async {
      final api = _api(
        (request) async => _json({'error': 'Sunucu hatasi.', 'errorId': 'abc123'}, 500),
      );
      await expectLater(
        api.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('Hata kodu: abc123'))
              .having((e) => e.isServerError, 'isServerError', isTrue),
        ),
      );
    });

    test('allowEmptyBody yalnızca 2xx için geçerlidir: boş gövdeli 500 başarı sayılmaz', () async {
      final failing = _api((request) async => http.Response('', 500));
      await expectLater(
        failing.deleteManagedUser(token: 't', userCode: 5),
        throwsA(isA<ApiException>()),
      );

      final ok = _api((request) async => http.Response('', 204));
      await ok.deleteManagedUser(token: 't', userCode: 5);
    });
  });

  group('Sunucu hata kodları (S1 sözleşmesi)', () {
    final current = UserSession(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: UserRole.individual,
      isActive: true,
      token: 'tok',
    );

    Future<ApiException> profileError(http.Response response) async {
      final api = _api((request) async => response);
      try {
        await api.updateMyProfile(
          token: 'tok',
          id: current.id,
          role: current.role,
          isActive: true,
          password: 'yeniSifre1',
          currentPassword: 'x',
        );
      } on ApiException catch (e) {
        return e;
      }
      fail('ApiException bekleniyordu');
    }

    test('400 CURRENT_PASSWORD_REQUIRED anlaşılır mesaj verir ve oturumu kapatmaz', () async {
      final e = await profileError(
        _json({'error': 'current password required', 'code': 'CURRENT_PASSWORD_REQUIRED'}, 400),
      );
      expect(e.message, 'Şifrenizi değiştirmek için mevcut şifrenizi girmelisiniz.');
      expect(e.code, 'CURRENT_PASSWORD_REQUIRED');
      expect(e.invalidatesSession, isFalse);
    });

    test('400 CURRENT_PASSWORD_INVALID anlaşılır mesaj verir ve oturumu kapatmaz', () async {
      final e = await profileError(
        _json({'error': 'x', 'code': 'CURRENT_PASSWORD_INVALID'}, 400),
      );
      expect(e.message, 'Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.');
      expect(e.invalidatesSession, isFalse);
    });

    test('429 CURRENT_PASSWORD_LOCKED bekleme süresini gösterir', () async {
      final e = await profileError(
        _json({'error': 'x', 'code': 'CURRENT_PASSWORD_LOCKED', 'retry_after_seconds': 900}, 429),
      );
      expect(e.message, contains('15 dakika sonra tekrar deneyin'));
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 900);
      expect(e.invalidatesSession, isFalse);
    });

    test('login 429 LOGIN_LOCKED: gövdedeki retry_after_seconds ile dakika cinsinden mesaj', () async {
      final api = _api(
        (request) async => _json(
          {'error': 'Cok fazla deneme', 'code': 'LOGIN_LOCKED', 'retry_after_seconds': 290},
          429,
        ),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message',
                  'Çok fazla hatalı deneme yapıldı. 5 dakika sonra tekrar deneyin.')
              .having((e) => e.code, 'code', 'LOGIN_LOCKED')
              .having((e) => e.retryAfterSeconds, 'retryAfter', 290),
        ),
      );
    });

    test('login 429: gövdede süre yoksa Retry-After başlığı kullanılır', () async {
      final api = _api(
        (request) async => http.Response(
          jsonEncode({'error': 'x', 'code': 'LOGIN_LOCKED'}),
          429,
          headers: {'content-type': 'application/json', 'retry-after': '45'},
        ),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('45 saniye sonra tekrar deneyin'),
          ),
        ),
      );
    });

    test('kapı açma 429: sunucu mesajına bekleme süresi eklenir', () async {
      final api = _api(
        (request) async => http.Response(
          jsonEncode({'error': 'Cok fazla kapi komutu.'}),
          429,
          headers: {'content-type': 'application/json', 'retry-after': '12'},
        ),
      );
      await expectLater(
        api.openDoor(token: 't', doorId: 7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('Cok fazla kapi komutu.'))
              .having((e) => e.message, 'message', contains('12 saniye sonra tekrar deneyin'))
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
        ),
      );
    });

    test('JSON olmayan (nginx) 429 ve 413 yanıtları doğru sınıflandırılır', () async {
      final tooMany = _api(
        (request) async => http.Response(
          '<html><body>429 Too Many Requests nginx</body></html>',
          429,
          headers: {'retry-after': '30'},
        ),
      );
      await expectLater(
        tooMany.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('30 saniye sonra tekrar deneyin'))
              .having((e) => e.message.contains('Modem'), 'modem', isFalse),
        ),
      );

      final tooLarge = _api(
        (request) async => http.Response('<html>413 Request Entity Too Large</html>', 413),
      );
      await expectLater(
        tooLarge.listMyDoors(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 413)
              .having((e) => e.message, 'message', contains('çok büyük')),
        ),
      );
    });

    test('401 TOKEN_REVOKED oturum sonlandırır ve nedenini açıklar', () async {
      final api = _api(
        (request) async => _json({'error': 'Token iptal edildi.', 'code': 'TOKEN_REVOKED'}, 401),
      );
      await expectLater(
        api.listMyDoors(token: 'eski'),
        throwsA(
          isA<SessionExpiredException>()
              .having((e) => e.code, 'code', 'TOKEN_REVOKED')
              .having((e) => e.message, 'message', contains('Şifreniz değiştirildiği için'))
              .having((e) => e.invalidatesSession, 'invalidatesSession', isTrue),
        ),
      );
    });

    test('body-parser hataları: 400 geçersiz JSON mesajı olduğu gibi iletilir', () async {
      final api = _api((request) async => _json({'error': 'Gecersiz JSON govdesi.'}, 400));
      await expectLater(
        api.createDoor(token: 't', siteCode: 1, doorName: 'x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.message, 'message', 'Gecersiz JSON govdesi.'),
        ),
      );
    });

    test('formatWait: saniye / dakika / saat', () {
      expect(AuthApi.formatWait(1), '1 saniye');
      expect(AuthApi.formatWait(59), '59 saniye');
      expect(AuthApi.formatWait(60), '1 dakika');
      expect(AuthApi.formatWait(61), '2 dakika');
      expect(AuthApi.formatWait(3540), '59 dakika');
      expect(AuthApi.formatWait(3599), '1 saat');
      expect(AuthApi.formatWait(3600), '1 saat');
      expect(AuthApi.formatWait(3601), '2 saat');
    });
  });

  group('Kod -> mesaj eşlemesi (C2/C3/cihaz hataları)', () {
    const knownCodes = <String>[
      'REMOTE_OPEN_DISABLED',
      'QR_DISABLED',
      'QR_ENTRY_INACTIVE',
      'GUEST_DISABLED',
      'LOCAL_DISABLED',
      'DYNAMIC_QR_REQUIRED',
      'SCREEN_QR_ALREADY_USED',
      'SCREEN_QR_EXPIRED',
      'EKRAN_QR_BEKLENIYOR',
      'INVALID_QR_PAYLOAD',
      'INVALID_DOOR_ID',
      'DOOR_NOT_FOUND',
      'DOOR_ACCESS_DENIED',
      'MQTT_BRIDGE_NOT_CONNECTED',
      'DEVICE_OFFLINE',
      'DEVICE_NOT_ASSIGNABLE',
      'DEVICE_OWNED_BY_ANOTHER',
      'DEVICE_DEFECTIVE',
      'DEVICE_NOT_FOUND',
      'GEOFENCE_LOCATION_REQUIRED',
      'GEOFENCE_LOCATION_INVALID',
      'GEOFENCE_MOCK_LOCATION',
      'GEOFENCE_LOCATION_STALE',
      'GEOFENCE_LOCATION_INACCURATE',
      'GEOFENCE_OUT_OF_RANGE',
      'GEOFENCE_SITE_MISCONFIGURED',
      'USE_PROFILE_PASSWORD_CHANGE',
    ];

    test('tüm bilinen kodların anlaşılır, kısa Türkçe metni vardır', () {
      for (final code in knownCodes) {
        final message = AuthApi.messageForErrorCode(code);
        expect(message, isNotNull, reason: code);
        expect(message!.length, lessThan(140), reason: '$code mesajı kısa olmalı (taşmasız)');
        expect(message.contains('_'), isFalse, reason: '$code ham kod sızdırmamalı');
      }
      expect(AuthApi.messageForErrorCode('UNKNOWN_CODE_XYZ'), isNull);
      expect(AuthApi.messageForErrorCode(null), isNull);
    });

    test('USE_PROFILE_PASSWORD_CHANGE: kendi parolasını yönetici ucundan değiştirme reddi kısa Türkçe mesajla gösterilir',
        () async {
      expect(
        AuthApi.messageForErrorCode('USE_PROFILE_PASSWORD_CHANGE'),
        'Kendi şifrenizi Profilim ekranından değiştirin.',
      );

      // Sunucu: PATCH /admin/users/:id kendi hesabında parola gelirse 400 + bu kod (oturum KAPANMAZ).
      final api = _api(
        (request) async => _json({
          'error': 'Kendi şifrenizi Profilim ekranından mevcut şifrenizle değiştirin.',
          'code': 'USE_PROFILE_PASSWORD_CHANGE',
        }, 400),
      );
      await expectLater(
        api.updateManagedUser(token: 't', userCode: 5, password: 'yeniSifre1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.code, 'code', 'USE_PROFILE_PASSWORD_CHANGE')
              .having((e) => e.message, 'message', 'Kendi şifrenizi Profilim ekranından değiştirin.')
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse)
              .having((e) => e is SessionExpiredException, 'sessionExpired', isFalse),
        ),
      );
    });

    test('GEOFENCE_OUT_OF_RANGE mesafe ve izin verilen yarıçapı gösterir', () {
      expect(
        AuthApi.messageForErrorCode(
          'GEOFENCE_OUT_OF_RANGE',
          payload: {'distance_meters': 245.6, 'allowed_radius_meters': 100},
        ),
        '246 m uzaktasınız, izin verilen mesafe 100 m. Lütfen kapıya yaklaşın.',
      );
      expect(
        AuthApi.messageForErrorCode('GEOFENCE_OUT_OF_RANGE', payload: const {}),
        'Kapı konumunda değilsiniz. Lütfen kapıya yaklaşın.',
      );
    });

    test('kapı açma 403 GEOFENCE_OUT_OF_RANGE gövdesinden mesaj üretilir', () async {
      final api = _api(
        (request) async => _json({
          'error': 'Kapi konumunda degilsiniz',
          'code': 'GEOFENCE_OUT_OF_RANGE',
          'distance_meters': 180,
          'allowed_radius_meters': 100,
        }, 403),
      );
      await expectLater(
        api.openDoor(token: 't', doorId: 7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message',
                  '180 m uzaktasınız, izin verilen mesafe 100 m. Lütfen kapıya yaklaşın.')
              .having((e) => e.code, 'code', 'GEOFENCE_OUT_OF_RANGE')
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
        ),
      );
    });

    test('scan-qr-open 409 EKRAN_QR_BEKLENIYOR ve 503 / 409 cihaz hataları', () async {
      final cases = <int, String>{
        409: 'EKRAN_QR_BEKLENIYOR',
        503: 'MQTT_BRIDGE_NOT_CONNECTED',
      };
      for (final entry in cases.entries) {
        final api = _api(
          (request) async => _json({'error': 'ham sunucu metni', 'code': entry.value}, entry.key),
        );
        await expectLater(
          api.openDoorWithScannedQr(token: 't', qrPayload: 'x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', entry.key)
                .having((e) => e.message, 'message', AuthApi.messageForErrorCode(entry.value))
                .having((e) => e.message.contains('ham sunucu'), 'raw', isFalse),
          ),
        );
      }
      final offline = _api(
        (request) async => _json({'error': 'x', 'code': 'DEVICE_OFFLINE'}, 409),
      );
      await expectLater(
        offline.openDoor(token: 't', doorId: 7),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Cihaz şu an çevrimdışı. Cihazın internet bağlantısını kontrol edin.',
          ),
        ),
      );
    });

    test('kodsuz 404/409 hataları sunucu mesajıyla olduğu gibi taşınır', () async {
      for (final status in [404, 409]) {
        final api = _api((request) async => _json({'error': 'Basvuru bulunamadi.'}, status));
        await expectLater(
          api.approveJoinRequest(token: 't', requestId: 1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.message, 'message', 'Basvuru bulunamadi.')
                .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
          ),
        );
      }
    });

    test('daire üyesi şifre değişimi current_password gönderir ve yeni token\'ı döndürür', () async {
      late Map<String, dynamic> body;
      final api = _api((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/membership/apartments/4/members/5/change-password');
        return _json({'ok': true, 'message': 'tamam', 'token': 'yeni-token'});
      });
      final res = await api.changeApartmentMemberPassword(
        token: 'eski',
        apartmentId: 4,
        targetUserCode: 5,
        newPassword: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      expect(body['new_password'], 'yeniSifre1');
      expect(body['current_password'], 'eskiSifre1');
      expect(res['token'], 'yeni-token');
    });
  });

  group('Yol parametreleri URL-kodlanır', () {
    test('joinToken yol içinde kodlanır', () async {
      late Uri seen;
      final api = _api((request) async {
        seen = request.url;
        return _json({'ok': true});
      });
      await api.getSiteJoinInfo(token: 't', joinToken: 'a/b?c=d e');
      expect(seen.path, '/membership/join-info/a%2Fb%3Fc%3Dd%20e');
      expect(seen.query, isEmpty);
    });

    test('status sorgu parametresi kodlanır ve ek parametre enjekte edemez', () async {
      late Uri seen;
      final api = _api((request) async {
        seen = request.url;
        return _json({'requests': <dynamic>[]});
      });
      await api.getSiteJoinRequests(token: 't', siteCode: 3, status: 'PENDING&site_code=9');
      expect(seen.queryParameters.keys.toList(), ['status']);
      expect(seen.queryParameters['status'], 'PENDING&site_code=9');
    });

    test('cihaz UID ve yönetici userCode yol içinde kodlanır', () async {
      final seen = <Uri>[];
      final api = _api((request) async {
        seen.add(request.url);
        if (request.url.path.contains('connectivity-logs')) {
          return _json({'device_uid': 'x', 'logs': <dynamic>[], 'pagination': {}});
        }
        return _json({'ok': true});
      });
      await api.getDeviceConnectivityLogs(token: 't', deviceUid: 'AA/../BB');
      await api.removeSiteManager(token: 't', siteCode: 3, userCode: '12/../x');
      expect(seen[0].path, '/admin/devices/AA%2F..%2FBB/connectivity-logs');
      expect(seen[1].path, '/manager/sites/3/managers/12%2F..%2Fx');
    });

    test('log tarihleri UTC (Z) olarak gönderilir', () async {
      late Uri seen;
      final api = _api((request) async {
        seen = request.url;
        return _json({'logs': <dynamic>[], 'total': 0, 'page': 1, 'page_size': 50, 'total_pages': 1});
      });
      final start = DateTime(2026, 5, 1, 3, 0, 0);
      await api.listDoorAccessLogs(
        token: 't',
        role: UserRole.siteManager,
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
      );
      expect(seen.queryParameters['start_date'], start.toUtc().toIso8601String());
      expect(seen.queryParameters['start_date']!.endsWith('Z'), isTrue);
      expect(seen.queryParameters['end_date']!.endsWith('Z'), isTrue);
    });
  });

  group('Kapı açma istekleri (C3 konum alanları)', () {
    test('konum yoksa gövde boştur; varsa C3 alanları üst düzeyde gönderilir', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _api((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(_runtimeStatusJson(), 202);
      });

      await api.openDoor(token: 't', doorId: 7);
      await api.openDoor(
        token: 't',
        doorId: 7,
        location: {
          'latitude': 41.0,
          'longitude': 29.0,
          'accuracy': 9.5,
          'timestamp': '2026-05-01T12:00:00.000Z',
          'is_mocked': false,
        },
      );

      expect(bodies[0], isEmpty);
      expect(bodies[1]['latitude'], 41.0);
      expect(bodies[1]['longitude'], 29.0);
      expect(bodies[1]['accuracy'], 9.5);
      expect(bodies[1]['timestamp'], '2026-05-01T12:00:00.000Z');
      expect(bodies[1]['is_mocked'], false);
    });

    test('scan-qr-open: qr_payload ile birlikte konum alanları birleştirilir', () async {
      late Map<String, dynamic> body;
      final api = _api((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/app/doors/scan-qr-open');
        return _json({'door_name': 'Ana Kapı'});
      });

      await api.openDoorWithScannedQr(
        token: 't',
        qrPayload: '  QR-PAYLOAD  ',
        location: {'latitude': 41.0, 'longitude': 29.0, 'is_mocked': false},
      );
      expect(body['qr_payload'], 'QR-PAYLOAD');
      expect(body['latitude'], 41.0);
      expect(body['is_mocked'], false);
    });

    test('Authorization başlığı Bearer token ile gönderilir', () async {
      String? header;
      final api = _api((request) async {
        header = request.headers['Authorization'];
        return _json(_runtimeStatusJson(), 202);
      });
      await api.openDoor(token: 'secret-token', doorId: 7);
      expect(header, 'Bearer secret-token');
    });
  });

  group('Profil (C8) ve /me (C11)', () {
    final current = UserSession(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: UserRole.individual,
      isActive: true,
      token: 'tok',
    );

    Map<String, dynamic> userJson({String role = 'individual', bool active = true}) => {
          'user': {
            'id': 5,
            'full_name': 'Ali Veli',
            'email': 'ali@example.com',
            'login_name': null,
            'role': role,
            'is_active': active,
          },
        };

    test('şifre değişiyorsa current_password gönderilir; değişmiyorsa gönderilmez', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _api((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(userJson());
      });

      await api.updateMyProfile(
        token: 'tok',
        id: 5,
        role: UserRole.individual,
        isActive: true,
        fullName: 'Ali Veli',
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      await api.updateMyProfile(
        token: 'tok',
        id: 5,
        role: UserRole.individual,
        isActive: true,
        fullName: 'Ali Veli',
        currentPassword: 'eskiSifre1',
      );

      expect(bodies[0]['password'], 'yeniSifre1');
      expect(bodies[0]['current_password'], 'eskiSifre1');
      expect(bodies[1].containsKey('password'), isFalse);
      expect(bodies[1].containsKey('current_password'), isFalse,
          reason: 'şifre değişmiyorsa mevcut şifre sızdırılmaz');
    });

    test('yanlış mevcut şifre (sunucuda 400 CURRENT_PASSWORD_INVALID) oturum süresi dolmuş gibi sınıflandırılmaz',
        () async {
      final api = _api(
        (request) async => _json({'error': 'Mevcut parola hatali.', 'code': 'CURRENT_PASSWORD_INVALID'}, 400),
      );
      await expectLater(
        api.updateMyProfile(
          token: 'tok',
          id: 5,
          role: UserRole.individual,
          isActive: true,
          password: 'yeniSifre1',
          currentPassword: 'yanlis',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e is SessionExpiredException, 'sessionExpired', isFalse)
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse)
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.message, 'message',
                  'Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.'),
        ),
      );
    });

    test('PATCH /me 401 (token iptal / süre dolumu / silinmiş kullanıcı) GERÇEK oturum sonudur', () async {
      // Sunucu bu uçta 401'i yalnızca authRequired'dan üretir; yanlış mevcut şifre artık 400'dür.
      for (final body in <Map<String, dynamic>>[
        {'error': 'Token iptal edildi.', 'code': 'TOKEN_REVOKED'},
        {'error': 'Gecersiz veya suresi dolmus token.'},
        {'error': 'Kullanici bulunamadi.'},
      ]) {
        final api = _api((request) async => _json(body, 401));
        await expectLater(
          api.updateMyProfile(
            token: 'tok',
            id: 5,
            role: UserRole.individual,
            isActive: true,
            fullName: 'Ali Veli',
          ),
          throwsA(
            isA<SessionExpiredException>().having((e) => e.invalidatesSession, 'invalidates', isTrue),
          ),
          reason: '$body',
        );
      }
    });

    test('sunucu yeni token döndürürse (parola sürümü) oturum onu kullanır', () async {
      final api = _api((request) async {
        final body = userJson();
        body['token'] = 'yeni-token';
        return _json(body);
      });
      final session = await api.updateMyProfile(
        token: 'tok',
        id: 5,
        role: UserRole.individual,
        isActive: true,
        password: 'yeniSifre1',
        currentPassword: 'eskiSifre1',
      );
      expect(session.token, 'yeni-token');
    });

    test('fetchMe sunucudaki rolü okur ve mevcut token ile oturum döndürür', () async {
      final api = _api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/me');
        return _json(userJson(role: 'site_manager'));
      });
      final fresh = await api.fetchMe(token: 'tok', current: current);
      expect(fresh.role, UserRole.siteManager);
      expect(fresh.token, 'tok');
    });

    test('fetchMe: 401 oturum süresi, 403 hesap durumu olarak ayrışır', () async {
      final unauthorized = _api((request) async => _json({'error': 'x'}, 401));
      await expectLater(
        unauthorized.fetchMe(token: 'tok', current: current),
        throwsA(isA<SessionExpiredException>()),
      );

      final forbidden = _api((request) async => _json({'error': 'Hesap aktif degil.'}, 403));
      await expectLater(
        forbidden.fetchMe(token: 'tok', current: current),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isForbidden, 'isForbidden', isTrue)
              .having((e) => e is SessionExpiredException, 'sessionExpired', isFalse),
        ),
      );
    });
  });
}
