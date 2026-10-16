// Satışa hazırlık / F3: uygulama yapılandırması (GET /public/app-config) modeli ve istemcisi.
//
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.1 ve §1.8. Sunucu yanıtı SAHTE (MockClient) olarak verilir.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/app_config.dart';
import 'package:site_kapi_kontrol/services/app_config_service.dart';

const Map<String, dynamic> _full = <String, dynamic>{
  'server_time': '2026-10-16T10:00:00.000Z',
  'min_supported_version': '1.2.0',
  'latest_version': '1.4.1',
  'update_url_android': 'https://play.google.com/store/apps/details?id=x',
  'update_url_ios': 'https://apps.apple.com/app/id1',
  'maintenance': <String, dynamic>{'active': true, 'message': 'Gece bakımı'},
  'support': <String, dynamic>{
    'email': 'destek@example.com',
    'phone': '+90 850 000 00 00',
    'hours': 'Hafta içi 09:00-18:00',
    'web_url': 'https://example.com/destek',
  },
  'legal_enforced': true,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('AppConfig.fromJson', () {
    test('tam yanıt alanlara eşlenir', () {
      final c = AppConfig.fromJson(_full);
      expect(c.minSupportedVersion, '1.2.0');
      expect(c.latestVersion, '1.4.1');
      expect(c.updateUrlAndroid, startsWith('https://play.google.com'));
      expect(c.updateUrlIos, startsWith('https://apps.apple.com'));
      expect(c.maintenanceActive, isTrue);
      expect(c.maintenanceMessage, 'Gece bakımı');
      expect(c.supportEmail, 'destek@example.com');
      expect(c.supportPhone, '+90 850 000 00 00');
      expect(c.supportHours, 'Hafta içi 09:00-18:00');
      expect(c.supportWebUrl, 'https://example.com/destek');
      expect(c.legalEnforced, isTrue);
      expect(c.serverTime, DateTime.utc(2026, 10, 16, 10));
      expect(c.hasSupportInfo, isTrue);
    });

    test('varsayılan sunucu yanıtı (null/boş alanlar) güvenli varsayılanlar verir', () {
      final c = AppConfig.fromJson(<String, dynamic>{
        'server_time': '2026-10-16T10:00:00.000Z',
        'min_supported_version': '1.0.0',
        'latest_version': '1.0.0',
        'update_url_android': null,
        'update_url_ios': null,
        'maintenance': <String, dynamic>{'active': false, 'message': null},
        'support': <String, dynamic>{
          'email': null,
          'phone': null,
          'hours': null,
          'web_url': null,
        },
        'legal_enforced': false,
      });
      expect(c.minSupportedVersion, '1.0.0');
      expect(c.updateUrlAndroid, isNull);
      expect(c.updateUrlIos, isNull);
      expect(c.maintenanceActive, isFalse);
      expect(c.maintenanceMessage, isNull);
      expect(c.hasSupportInfo, isFalse);
      expect(c.legalEnforced, isFalse);
    });

    test('boş nesne: hata fırlatmaz; sürümler 0.0.0, bakım kapalı', () {
      final c = AppConfig.fromJson(const <String, dynamic>{});
      expect(c.minSupportedVersion, '0.0.0');
      expect(c.latestVersion, '0.0.0');
      expect(c.maintenanceActive, isFalse);
      expect(c.legalEnforced, isFalse);
      expect(c.serverTime, isNull);
    });

    test('beklenmeyen türler ve bozuk iç içe alanlar dayanıklıdır', () {
      final c = AppConfig.fromJson(<String, dynamic>{
        'min_supported_version': 12,
        'latest_version': <String>['x'],
        'update_url_android': 42,
        'maintenance': 'evet',
        'support': <dynamic>[1, 2],
        'legal_enforced': 'true',
        'server_time': 'dün',
      });
      expect(c.minSupportedVersion, '0.0.0');
      expect(c.latestVersion, '0.0.0');
      expect(c.updateUrlAndroid, isNull);
      expect(c.maintenanceActive, isFalse);
      expect(c.hasSupportInfo, isFalse);
      expect(c.legalEnforced, isTrue); // metinsel "true" kabul edilir
      expect(c.serverTime, isNull);
    });

    test('boşluk kırpılır, yalnız boşluk içeren metin null olur', () {
      final c = AppConfig.fromJson(<String, dynamic>{
        'min_supported_version': ' 1.1.0 ',
        'support': <String, dynamic>{'email': '   ', 'phone': ' 123 '},
        'maintenance': <String, dynamic>{'active': 1, 'message': '  '},
      });
      expect(c.minSupportedVersion, '1.1.0');
      expect(c.supportEmail, isNull);
      expect(c.supportPhone, '123');
      expect(c.maintenanceActive, isTrue); // 1 -> açık
      expect(c.maintenanceMessage, isNull);
    });
  });

  group('AppConfigService', () {
    test('başarılı yükleme: doğru URL, kimliksiz istek, current dolar', () async {
      late http.Request seen;
      final service = AppConfigService(
        baseUrl: 'https://api.example.test/',
        client: MockClient((request) async {
          seen = request;
          return _json(_full);
        }),
      );
      expect(service.current, isNull);

      final c = await service.load();
      expect(c, isNotNull);
      expect(c!.latestVersion, '1.4.1');
      expect(service.current, same(c));
      expect(seen.method, 'GET');
      // Çift eğik çizgi yok; yol sözleşmedeki gibi.
      expect(seen.url.toString(), 'https://api.example.test/public/app-config');
      // Kimliksiz: Authorization başlığı gönderilmez.
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('Türkçe karakterler UTF-8 olarak doğru çözülür', () async {
      final body = utf8.encode(
        jsonEncode(<String, dynamic>{
          'maintenance': <String, dynamic>{
            'active': true,
            'message': 'Bakım: çalışıyoruz, şimdi dönüyoruz ğüşiöç',
          },
        }),
      );
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        // Üstbilgide charset yok: gövde baytları UTF-8 olarak çözülmelidir.
        client: MockClient(
          (_) async => http.Response.bytes(
            body,
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
      final c = await service.load();
      expect(c!.maintenanceMessage, 'Bakım: çalışıyoruz, şimdi dönüyoruz ğüşiöç');
    });

    test('4xx/5xx, bozuk JSON ve JSON olmayan gövde -> null (hata fırlatmaz)', () async {
      for (final response in <http.Response>[
        http.Response('hata', 500),
        http.Response('', 404),
        http.Response('{bozuk', 200),
        http.Response('[1,2,3]', 200),
        http.Response('"metin"', 200),
      ]) {
        final service = AppConfigService(
          baseUrl: 'https://x.test',
          client: MockClient((_) async => response),
        );
        expect(await service.load(), isNull, reason: response.body);
        expect(service.current, isNull);
      }
    });

    test('ağ hatası -> null', () async {
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        client: MockClient((_) async => throw http.ClientException('ağ yok')),
      );
      expect(await service.load(), isNull);
      expect(service.current, isNull);
    });

    test('zaman aşımı: yanıt gelmezse null döner', () async {
      final never = Completer<http.Response>();
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        timeout: const Duration(milliseconds: 50),
        client: MockClient((_) => never.future),
      );
      expect(await service.load(), isNull);
      expect(service.current, isNull);
    });

    testWidgets('varsayılan zaman aşımı 4 saniyedir (sahte saat)', (t) async {
      final never = Completer<http.Response>();
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        client: MockClient((_) => never.future),
      );
      var done = false;
      AppConfig? result = AppConfig.fromJson(const <String, dynamic>{});
      service.load().then((c) {
        done = true;
        result = c;
      });
      await t.pump(const Duration(milliseconds: 3900));
      expect(done, isFalse, reason: '3,9 sn: hâlâ bekliyor');
      await t.pump(const Duration(milliseconds: 200));
      expect(done, isTrue, reason: '4 sn dolunca vazgeçer');
      expect(result, isNull);
    });

    test('taze önbellek: ikinci çağrı ağa gitmez; force: yeniden sorar', () async {
      var calls = 0;
      var now = DateTime(2026, 10, 16, 10);
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return _json(<String, dynamic>{'latest_version': '1.0.$calls'});
        }),
      );
      final first = await service.load();
      final second = await service.load();
      expect(calls, 1);
      expect(second, same(first));

      final forced = await service.load(force: true);
      expect(calls, 2);
      expect(forced!.latestVersion, '1.0.2');
      expect(service.current, same(forced));

      // Önbellek süresi (15 dk) dolunca force olmadan da yenilenir.
      now = now.add(const Duration(minutes: 16));
      await service.load();
      expect(calls, 3);
    });

    test('hata sonrası son başarılı yanıt current içinde kalır; load null döner', () async {
      var fail = false;
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        client: MockClient((_) async {
          if (fail) return http.Response('x', 503);
          return _json(_full);
        }),
      );
      final ok = await service.load();
      expect(ok, isNotNull);

      fail = true;
      expect(await service.load(force: true), isNull);
      expect(service.current, same(ok));
    });

    test('eşzamanlı çağrılar tek isteği paylaşır', () async {
      var calls = 0;
      final gate = Completer<void>();
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        client: MockClient((_) async {
          calls++;
          await gate.future;
          return _json(_full);
        }),
      );
      final a = service.load(force: true);
      final b = service.load(force: true);
      gate.complete();
      final results = await Future.wait([a, b]);
      expect(calls, 1);
      expect(results[0], same(results[1]));
    });

    test('hata sonrası yeni deneme yapılabilir (askıda kalan istek sızmaz)', () async {
      var calls = 0;
      final service = AppConfigService(
        baseUrl: 'https://x.test',
        client: MockClient((_) async {
          calls++;
          if (calls == 1) throw http.ClientException('ağ yok');
          return _json(_full);
        }),
      );
      expect(await service.load(), isNull);
      expect(await service.load(), isNotNull);
      expect(calls, 2);
    });
  });
}
