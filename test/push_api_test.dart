// Telefon bildirimi uçları (Faz 3b-B, docs/PLATFORM_BELGELER.md B3): istek biçimi, kısmi tercih güncellemesi,
// jetonun yanıtlarda / hatalarda görünmemesi ve Türkçe hata eşlemesi (PUSH_UNAVAILABLE, 401, 429, ara katman).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/push_api.dart';

http.Response _json(Object body, [int status = 200, Map<String, String> headers = const <String, String>{}]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...headers},
    );

({PushApi api, List<http.Request> requests}) _api(http.Response Function(http.Request) handler) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });
  return (api: PushApi(baseUrl: 'https://api.example.test/', client: client), requests: requests);
}

void main() {
  group('cihaz uçları', () {
    test('PUT /app/push/devices: gövde sözleşmedeki alanlar, Bearer, sürüm ≤ 32; yanıt jeton taşımaz', () async {
      final h = _api((_) => _json(<String, Object?>{'ok': true, 'device_id': 9, 'push_available': true}));
      final result = await h.api.registerDevice(
        token: 'tok-A',
        installId: '0f8fad5b-d9cb-469f-a165-70867728950e',
        platform: 'android',
        fcmToken: 'fcm-xyz',
        appVersion: '1.0.0-${'x' * 40}',
        notificationsEnabled: true,
      );
      final request = h.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.toString(), 'https://api.example.test/app/push/devices');
      expect(request.headers['Authorization'], 'Bearer tok-A');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), <String>{
        'install_id',
        'platform',
        'token',
        'app_version',
        'notifications_enabled',
      });
      expect(body['token'], 'fcm-xyz');
      expect((body['app_version'] as String).length, PushApi.maxAppVersionLength);
      expect(result.deviceId, 9);
      expect(result.pushAvailable, isTrue);
    });

    test('sunucu desenine uymayan sürüm gönderilmez (kayıt sürüm yüzünden reddedilmesin)', () {
      expect(PushApi.safeAppVersion('1.0.0+12'), '1.0.0+12');
      expect(PushApi.safeAppVersion(' 2.1.0 '), '2.1.0');
      expect(PushApi.safeAppVersion('1.0 beta'), isNull);
      expect(PushApi.safeAppVersion('sürüm-1'), isNull);
      expect(PushApi.safeAppVersion('-1.0'), isNull);
      expect(PushApi.safeAppVersion(''), isNull);
      expect(PushApi.safeAppVersion(null), isNull);
    });

    test('sürüm boşsa app_version gönderilmez', () async {
      final h = _api((_) => _json(<String, Object?>{'ok': true}));
      await h.api.registerDevice(
        token: 't',
        installId: '0f8fad5b-d9cb-469f-a165-70867728950e',
        platform: 'ios',
        fcmToken: 'f',
        appVersion: '  ',
        notificationsEnabled: false,
      );
      final body = jsonDecode(h.requests.single.body) as Map<String, dynamic>;
      expect(body.containsKey('app_version'), isFalse);
      expect(body['notifications_enabled'], isFalse);
      expect(body['platform'], 'ios');
    });

    test('DELETE /app/push/devices/:installId kodlanır; GET liste jetonsuz ve en son görülen önce', () async {
      final h = _api((request) {
        if (request.method == 'DELETE') return _json(<String, Object?>{'ok': true});
        return _json(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{'install_id': 'eski', 'platform': 'ios', 'last_seen_at': '2026-10-01T10:00:00Z'},
            <String, Object?>{
              'install_id': 'yeni',
              'platform': 'android',
              'app_version': '1.0.0',
              'last_seen_at': '2026-10-16T10:00:00Z',
              'fcm_token': 'ASLA-GOSTERILMEZ',
            },
            <String, Object?>{'platform': 'android'},
            'bozuk',
          ],
        });
      });
      await h.api.deleteDevice(token: 't', installId: 'a/b c');
      expect(h.requests.single.url.path, '/app/push/devices/a%2Fb%20c');
      final devices = await h.api.listDevices(token: 't');
      expect(devices.map((d) => d.installId), <String>['yeni', 'eski']);
      expect(devices.first.appVersion, '1.0.0');
      expect(devices.first.platformLabel, 'Android telefon');
      expect(devices.last.platformLabel, 'iPhone / iPad');
    });

    test('POST /app/push/test: sayılar; 503 PUSH_UNAVAILABLE -> "Telefon bildirimi şu an kullanılamıyor."', () async {
      var unavailable = false;
      final h = _api((_) {
        if (unavailable) {
          return _json(<String, Object?>{'error': 'push yapılandırılmamış', 'code': 'PUSH_UNAVAILABLE'}, 503);
        }
        return _json(<String, Object?>{'ok': true, 'sent': 2, 'failed': 1});
      });
      final result = await h.api.sendTest(token: 't');
      expect(result.sent, 2);
      expect(result.failed, 1);
      expect(h.requests.single.method, 'POST');
      expect(h.requests.single.url.path, '/app/push/test');

      unavailable = true;
      await expectLater(
        h.api.sendTest(token: 't'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Telefon bildirimi şu an kullanılamıyor.')
              .having((e) => e.code, 'code', 'PUSH_UNAVAILABLE')
              .having((e) => e.statusCode, 'status', 503),
        ),
      );
    });

    test('test bildirimi 429: günlük sınır metni + bekleme ipucu', () async {
      final h = _api((_) => _json(<String, Object?>{'error': 'Too many', 'code': 'RATE_LIMITED'}, 429, <String, String>{
        'retry-after': '3600',
      }));
      await expectLater(
        h.api.sendTest(token: 't'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('test bildirimi sınırına ulaşıldı'), contains('1 saat sonra')),
          ),
        ),
      );
    });

    test('401 -> SessionExpiredException (oturum doğrulanır); JSON olmayan 401 ara katman hatasıdır', () async {
      var html = false;
      final h = _api((_) => html
          ? http.Response('<html>login</html>', 401)
          : _json(<String, Object?>{'error': 'Oturum geçersiz', 'code': 'TOKEN_REVOKED'}, 401));
      await expectLater(h.api.listDevices(token: 't'), throwsA(isA<SessionExpiredException>()));
      html = true;
      await expectLater(
        h.api.listDevices(token: 't'),
        throwsA(isA<ApiException>().having((e) => e.invalidatesSession, 'oturum sonu değil', isFalse)),
      );
    });

    test('ağ hatası Türkçe mesajla; istek gövdesi / jeton hata metnine girmez', () async {
      final client = MockClient((_) async => throw http.ClientException('socket kapandı fcm-xyz'));
      final api = PushApi(baseUrl: 'https://api.example.test', client: client);
      await expectLater(
        api.registerDevice(
          token: 'tok',
          installId: '0f8fad5b-d9cb-469f-a165-70867728950e',
          platform: 'android',
          fcmToken: 'fcm-xyz',
          notificationsEnabled: true,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', startsWith('Sunucuya bağlanılamadı'))
              .having((e) => e.message, 'jeton yok', isNot(contains('fcm-xyz'))),
        ),
      );
    });
  });

  group('tercihler', () {
    test('GET: push alanları; PUT KISMİ (yalnız değişen anahtar, "HH:MM")', () async {
      final h = _api((request) {
        if (request.method == 'GET') {
          return _json(<String, Object?>{
            'email_announcements': true,
            'push_announcements': false,
            'push_available': true,
            'push_show_preview': true,
            'push_quiet': <String, Object?>{'enabled': true, 'start': '22:30', 'end': '06:15'},
            'push_devices': 2,
          });
        }
        return _json(<String, Object?>{'push_available': true, 'push_quiet': <String, Object?>{'start': '21:05'}});
      });
      final prefs = await h.api.getPreferences(token: 't');
      expect(prefs.available, isTrue);
      expect(prefs.announcements, isFalse);
      expect(prefs.showPreview, isTrue);
      expect(prefs.quietEnabled, isTrue);
      expect(prefs.quietStart, 22 * 60 + 30);
      expect(prefs.quietEnd, 6 * 60 + 15);
      expect(prefs.deviceCount, 2);

      final saved = await h.api.updatePreferences(
        token: 't',
        patch: const PushPreferencesPatch(quietStart: 21 * 60 + 5),
        current: prefs,
      );
      final put = h.requests.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/app/notification-preferences');
      expect(jsonDecode(put.body), <String, Object?>{'push_quiet_start': '21:05'});
      expect(saved.quietStart, 21 * 60 + 5);
      // Yanıtta olmayan alanlar mevcut + istenen değerden gelir.
      expect(saved.showPreview, isTrue);
      expect(saved.announcements, isFalse);
      expect(saved.quietEnd, 6 * 60 + 15);
    });

    test('PUT yanıtı boşsa istenen değer geçerli sayılır; boş yama hata', () async {
      final h = _api((_) => http.Response('', 200));
      final saved = await h.api.updatePreferences(
        token: 't',
        patch: const PushPreferencesPatch(announcements: true, showPreview: false, quietEnabled: true),
        current: const PushPreferences(available: true, announcements: false, showPreview: true),
      );
      expect(jsonDecode(h.requests.single.body), <String, Object?>{
        'push_announcements': true,
        'push_show_preview': false,
        'push_quiet_enabled': true,
      });
      expect(saved.announcements, isTrue);
      expect(saved.showPreview, isFalse);
      expect(saved.quietEnabled, isTrue);
      expect(saved.available, isTrue);
      expect(
        () => h.api.updatePreferences(token: 't', patch: const PushPreferencesPatch(), current: saved),
        throwsArgumentError,
      );
    });

    test('400 INVALID_BODY Türkçe genel metne düşer (alan adı jargonu gösterilmez)', () async {
      final h = _api((_) => _json(<String, Object?>{'error': 'push_quiet_start invalid', 'code': 'INVALID_BODY'}, 400));
      await expectLater(
        h.api.updatePreferences(
          token: 't',
          patch: const PushPreferencesPatch(quietStart: 60),
          current: const PushPreferences(),
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', isNot(contains('push_quiet_start')))),
      );
    });
  });
}
