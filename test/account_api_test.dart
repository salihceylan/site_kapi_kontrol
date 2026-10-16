// AccountApi / AccountService (lib/services/account_api.dart): sahte HTTP istemcisiyle uç noktalar, gövde
// biçimleri ve hata çevirisi (docs/PLATFORM_SATISA_HAZIRLIK.md §1.2, §1.3, §1.5, §1.6).
//
// Kurallar: yanlış parola oturumu KAPATMAZ (400), 401 oturum sonudur, JSON olmayan 401/403 ara katman hatasıdır,
// mutasyonlar yeniden denenmez, başarı yalnız `200 {"deleted":true}`, dışa aktarma boyut sınırı akışta uygulanır.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...?headers},
);

AccountApi _api(
  Future<http.Response> Function(http.Request request) handler, {
  Duration timeout = const Duration(seconds: 5),
  int maxExportBytes = 1024 * 1024,
}) {
  return AccountApi(
    baseUrl: '$_base/',
    client: MockClient(handler),
    readTimeout: timeout,
    writeTimeout: timeout,
    exportTimeout: timeout,
    maxExportBytes: maxExportBytes,
    now: () => DateTime(2026, 10, 16),
  );
}

Future<ApiException> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

void main() {
  group('hesap silme', () {
    test('önizleme: POST, Bearer belirteç, boş gövde; yanıt çözülür', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'can_delete': true,
          'blockers': <Object>[],
          'will_remove': <String>['Ad'],
          'will_keep': <String>['Aidat'],
        });
      });
      final preview = await api.previewDeletion(token: 'tok-1');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), '$_base/me/account-deletion/preview');
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(jsonDecode(seen.body), isEmpty);
      expect(preview.canDelete, isTrue);
      expect(preview.willRemove, <String>['Ad']);
    });

    test('silme: gövde current_password + confirm:true; 200 {deleted:true} başarı', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'deleted': true});
      });
      await api.deleteAccount(token: 't', currentPassword: 'Gizli123');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/me/account-deletion');
      expect(jsonDecode(seen.body), <String, dynamic>{'current_password': 'Gizli123', 'confirm': true});
    });

    test('silme: 200 ama deleted:true değil -> başarı SAYILMAZ', () async {
      final api = _api((_) async => _json(200, <String, dynamic>{'ok': true}));
      final error = await _failureOf(() => api.deleteAccount(token: 't', currentPassword: 'x'));
      expect(error.message, contains('beklenen biçimde değil'));
    });

    test('silme: 201 / 202 / 204 başarı SAYILMAZ (yalnız 200 {deleted:true}); ileti belirsizliği söyler', () async {
      for (final status in <int>[201, 202]) {
        final api = _api((_) async => _json(status, <String, dynamic>{'deleted': true}));
        final error = await _failureOf(() => api.deleteAccount(token: 't', currentPassword: 'x'));
        expect(error.statusCode, status);
        expect(error.message, contains('Silme işlemi tamamlanmış olabilir'));
      }
      final empty = _api((_) async => http.Response('', 204));
      final error = await _failureOf(() => empty.deleteAccount(token: 't', currentPassword: 'x'));
      expect(error.message, contains('beklenmeyen bir yanıt'));
    });

    test('silme: 409 ACCOUNT_DELETE_BLOCKED -> engel listesiyle özel hata', () async {
      final api = _api(
        (_) async => _json(409, <String, dynamic>{
          'error': 'Hesabınız şu anda silinemez.',
          'code': 'ACCOUNT_DELETE_BLOCKED',
          'blockers': <Object>[
            <String, dynamic>{'code': 'LAST_SITE_MANAGER', 'message': 'Tek yöneticisiniz.', 'site_id': 9},
          ],
        }),
      );
      final error = await _failureOf(() => api.deleteAccount(token: 't', currentPassword: 'x'));
      expect(error, isA<AccountDeleteBlockedException>());
      final blocked = error as AccountDeleteBlockedException;
      expect(blocked.statusCode, 409);
      expect(blocked.blockers.single.siteId, 9);
      expect(blocked.message, 'Hesabınız şu anda silinemez. Nedenleri aşağıda görebilirsiniz.');
    });

    test('409 ACCOUNT_DELETE_BUSY (sunucu meşgul): sunucunun Türkçe iletisi aynen; engel istisnası DEĞİL', () async {
      final api = _api(
        (_) async => _json(409, <String, dynamic>{
          'error': 'Hesap silme şu anda tamamlanamadı. Birkaç saniye sonra tekrar deneyin.',
          'code': 'ACCOUNT_DELETE_BUSY',
        }),
      );
      final error = await _failureOf(() => api.deleteAccount(token: 't', currentPassword: 'x'));
      expect(error, isNot(isA<AccountDeleteBlockedException>()));
      expect(error.message, 'Hesap silme şu anda tamamlanamadı. Birkaç saniye sonra tekrar deneyin.');
      expect(error.code, 'ACCOUNT_DELETE_BUSY');
      expect(error.invalidatesSession, isFalse);
    });

    test('yanlış parola: 400 CURRENT_PASSWORD_INVALID -> doğru Türkçe, OTURUM KAPANMAZ', () async {
      final api = _api(
        (_) async => _json(400, <String, dynamic>{
          'error': 'Mevcut parola hatalı.',
          'code': 'CURRENT_PASSWORD_INVALID',
        }),
      );
      final error = await _failureOf(() => api.deleteAccount(token: 't', currentPassword: 'x'));
      expect(error.message, 'Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.');
      expect(error.code, 'CURRENT_PASSWORD_INVALID');
      expect(error.invalidatesSession, isFalse);
      expect(error.statusCode, 400);
    });

    test('parola gerekli ve kilitli iletileri; kilitte bekleme süresi gösterilir', () async {
      final required = _api(
        (_) async => _json(400, <String, dynamic>{'error': 'x', 'code': 'CURRENT_PASSWORD_REQUIRED'}),
      );
      expect(
        (await _failureOf(() => required.exportData(token: 't', currentPassword: ''))).message,
        'Devam etmek için şifrenizi girin.',
      );
      final locked = _api(
        (_) async => _json(429, <String, dynamic>{
          'error': 'Çok fazla hatalı mevcut parola denemesi.',
          'code': 'CURRENT_PASSWORD_LOCKED',
          'retry_after_seconds': 900,
        }),
      );
      final error = await _failureOf(() => locked.exportData(token: 't', currentPassword: 'x'));
      expect(error.message, 'Şifre için çok fazla hatalı deneme yapıldı. 15 dakika sonra tekrar deneyin.');
      expect(error.isRateLimited, isTrue);
      expect(error.retryAfterSeconds, 900);
      expect(error.invalidatesSession, isFalse);
    });

    test('401 -> SessionExpiredException (oturum sonu); TOKEN_REVOKED ayrı metin; ACCOUNT_DELETED', () async {
      final expired = _api((_) async => _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'}));
      final e1 = await _failureOf(() => expired.previewDeletion(token: 't'));
      expect(e1, isA<SessionExpiredException>());
      expect(e1.invalidatesSession, isTrue);
      expect(e1.message, 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.');

      final revoked = _api((_) async => _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_REVOKED'}));
      final e2 = await _failureOf(() => revoked.previewDeletion(token: 't'));
      expect(e2.message, contains('Şifreniz değiştirildiği için'));

      final gone = _api((_) async => _json(401, <String, dynamic>{'error': 'x', 'code': 'ACCOUNT_DELETED'}));
      final e3 = await _failureOf(() => gone.deleteAccount(token: 't', currentPassword: 'x'));
      expect(e3.code, 'ACCOUNT_DELETED');
      expect(e3.message, 'Bu hesap silinmiş.');
    });

    test('JSON olmayan 401/403 (proxy / captive portal) oturum sonu DEĞİLDİR', () async {
      for (final status in <int>[401, 403]) {
        final api = _api(
          (_) async => http.Response.bytes(
            utf8.encode('<html>Giriş yapın</html>'),
            status,
            headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
          ),
        );
        final error = await _failureOf(() => api.previewDeletion(token: 't'));
        expect(error.fromIntermediary, isTrue);
        expect(error.invalidatesSession, isFalse);
        expect(error.isForbidden, isFalse);
        expect(error.message, contains('Sunucuya ulaşılamadı'));
      }
    });

    test('5xx: errorId iletiye eklenir; JSON olmayan 502 teknik sızıntı yapmaz', () async {
      final withId = _api(
        (_) async => _json(500, <String, dynamic>{'error': 'Hesap silinemedi.', 'errorId': 'E-7F3A'}),
      );
      final e1 = await _failureOf(() => withId.deleteAccount(token: 't', currentPassword: 'x'));
      expect(e1.message, 'Hesap silinemedi. (Hata kodu: E-7F3A)');
      expect(e1.isServerError, isTrue);

      final gateway = _api((_) async => http.Response('<html>Bad Gateway</html>', 502));
      final e2 = await _failureOf(() => gateway.previewDeletion(token: 't'));
      expect(e2.message, contains('Sunucu şu anda yanıt veremiyor (502)'));
      expect(e2.message, isNot(contains('html')));
    });

    test('zaman aşımı: silmede "tamamlanmış olabilir" uyarısı, okumada yeniden dene', () async {
      final slow = _api((_) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 30));
      final del = await _failureOf(() => slow.deleteAccount(token: 't', currentPassword: 'x'));
      expect(del.message, contains('Silme işlemi tamamlanmış olabilir'));
      final read = await _failureOf(() => slow.previewDeletion(token: 't'));
      expect(read.message, 'Sunucu yanıt vermedi, tekrar deneyin.');
    });

    test('ağ hatası: bağlantı metni; ayrıntı sızmaz; mutasyon TEKRARLANMAZ', () async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        throw http.ClientException('Connection reset by peer 10.0.0.5');
      });
      final error = await _failureOf(() => api.deleteAccount(token: 't', currentPassword: 'x'));
      expect(calls, 1);
      expect(error.message, isNot(contains('10.0.0.5')));
      expect(error.message, contains('Silme işlemi tamamlanmış olabilir'));
      final read = await _failureOf(() => api.previewDeletion(token: 't'));
      expect(read.message, 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    });

    test('başarılı yanıt JSON nesnesi değilse anlaşılır hata', () async {
      final api = _api((_) async => http.Response('merhaba', 200));
      final error = await _failureOf(() => api.previewDeletion(token: 't'));
      expect(error.message, 'Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.');
    });
  });

  group('veri dışa aktarma', () {
    const body = '{"format_version":1,"user":{"user_code":42}}';

    test('200: baytlar olduğu gibi, dosya adı Content-Disposition\'dan; gövde current_password', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'content-disposition': 'attachment; filename="kisisel-veri-42-20261016.json"',
            'cache-control': 'no-store',
          },
        );
      });
      final export = await api.exportData(token: 'tok', currentPassword: 'Gizli123');
      expect(seen.url.path, '/me/data-export');
      expect(jsonDecode(seen.body), <String, dynamic>{'current_password': 'Gizli123'});
      expect(utf8.decode(export.bytes), body);
      expect(export.fileName, 'kisisel-veri-42-20261016.json');
    });

    test('başlık yoksa yedek dosya adı; tehlikeli ad temizlenir', () async {
      final none = _api(
        (_) async => http.Response(body, 200, headers: <String, String>{'content-type': 'application/json'}),
      );
      expect((await none.exportData(token: 't', currentPassword: 'x')).fileName, 'kisisel-veri-20261016.json');

      final evil = _api(
        (_) async => http.Response(
          body,
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            'content-disposition': 'attachment; filename="../../x/evil.json"',
          },
        ),
      );
      expect((await evil.exportData(token: 't', currentPassword: 'x')).fileName, 'evil.json');
    });

    test('202 / 204 dışa aktarma dosyası DEĞİLDİR (yalnız 200)', () async {
      for (final status in <int>[202, 204]) {
        final api = _api(
          (_) async => http.Response(body, status, headers: <String, String>{'content-type': 'application/json'}),
        );
        final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
        expect(error.statusCode, status);
        expect(error.message, contains('beklenmeyen bir yanıt'));
      }
    });

    test('429 EXPORT_RATE_LIMITED: 24 saatte 3 kez iletisi + bekleme süresi', () async {
      final api = _api(
        (_) async => _json(429, <String, dynamic>{
          'error': 'Kişisel veri dışa aktarma sınırına ulaştınız (24 saatte en fazla 3). Daha sonra tekrar deneyin.',
          'code': 'EXPORT_RATE_LIMITED',
          'retry_after_seconds': 18000,
        }),
      );
      final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
      expect(
        error.message,
        'Kişisel verilerinizi 24 saat içinde en fazla 3 kez indirebilirsiniz. 5 saat sonra tekrar deneyin.',
      );
      expect(error.isRateLimited, isTrue);
      expect(error.code, 'EXPORT_RATE_LIMITED');
    });

    test('429 bekleme süresi bilinmiyorsa genel "daha sonra" ifadesi', () async {
      final api = _api(
        (_) async => _json(429, <String, dynamic>{'error': 'x', 'code': 'EXPORT_RATE_LIMITED'}),
      );
      final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
      expect(error.message, endsWith('Lütfen daha sonra tekrar deneyin.'));
    });

    test('Retry-After başlığı bekleme süresi olarak okunur (kodsuz genel 429)', () async {
      final api = _api(
        (_) async => _json(429, <String, dynamic>{'error': 'Çok fazla istek.'}, headers: <String, String>{'retry-after': '90'}),
      );
      final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
      expect(error.retryAfterSeconds, 90);
      expect(error.message, contains('2 dakika sonra tekrar deneyin'));
    });

    test('boyut sınırı: bildirilen uzunluk sınırı aşarsa akış hiç okunmaz', () async {
      final api = _api(
        (_) async => http.Response('{"a":"${'x' * 5000}"}', 200, headers: <String, String>{'content-type': 'application/json'}),
        maxExportBytes: 1000,
      );
      final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
      expect(error.code, 'EXPORT_TOO_LARGE');
      expect(error.message, contains('çok büyük'));
    });

    test('boyut sınırı: uzunluk bildirilmese de akış sınırı aşınca kesilir', () async {
      var chunks = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        Stream<List<int>> generate() async* {
          for (var i = 0; i < 100; i++) {
            chunks++;
            yield utf8.encode('{"x":"${'y' * 100}"}');
          }
        }

        return http.StreamedResponse(
          generate(),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final api = AccountApi(baseUrl: _base, client: client, maxExportBytes: 500);
      final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
      expect(error.code, 'EXPORT_TOO_LARGE');
      expect(chunks, lessThan(100), reason: 'sınır aşıldığında indirme durdurulur');
    });

    test('beklenmeyen dosya: boş gövde, JSON olmayan içerik türü, nesne olmayan JSON reddedilir', () async {
      for (final response in <http.Response>[
        http.Response('', 200, headers: <String, String>{'content-type': 'application/json'}),
        http.Response(body, 200, headers: <String, String>{'content-type': 'text/html'}),
        http.Response('[1,2]', 200, headers: <String, String>{'content-type': 'application/json'}),
        http.Response('<html></html>', 200, headers: <String, String>{'content-type': 'application/json'}),
      ]) {
        final api = _api((_) async => response);
        final error = await _failureOf(() => api.exportData(token: 't', currentPassword: 'x'));
        expect(error.message, 'Sunucu beklenmeyen bir dosya döndürdü. Lütfen tekrar deneyin.');
      }
    });

    test('UTF-8 BOM ve baştaki boşluk kabul edilir', () async {
      final bytes = <int>[0xEF, 0xBB, 0xBF, 0x0A, ...utf8.encode(body)];
      final api = _api(
        (_) async => http.Response.bytes(bytes, 200, headers: <String, String>{'content-type': 'application/json'}),
      );
      expect((await api.exportData(token: 't', currentPassword: 'x')).bytes, bytes);
    });
  });

  group('platform ayarları', () {
    final configBody = <String, dynamic>{
      'app': <String, dynamic>{'latest_version': '1.2.0', 'maintenance_active': false},
      'support': <String, dynamic>{'email': 'destek@x.com'},
      'legal': <String, dynamic>{'enforce_consents': true},
    };

    test('GET: yol, yetki başlığı ve çözümleme', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, configBody);
      });
      final config = await api.getPlatformConfig(token: 'tok');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/admin/platform-config');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(config.app.latestVersion, '1.2.0');
      expect(config.legal.enforceConsents, isTrue);
    });

    test('PUT: yalnız verilen kısmi gövde gider; yanıttaki güncel ayar döner', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, configBody);
      });
      final updated = await api.updatePlatformConfig(
        token: 't',
        patch: <String, Map<String, Object>>{
          'app': <String, Object>{'latest_version': '1.2.0'},
        },
      );
      expect(seen.method, 'PUT');
      expect(jsonDecode(seen.body), <String, dynamic>{
        'app': <String, dynamic>{'latest_version': '1.2.0'},
      });
      expect(updated?.app.latestVersion, '1.2.0');
    });

    test('PUT yanıtı ayar taşımıyorsa null; boş patch programlama hatasıdır', () async {
      final api = _api((_) async => _json(200, <String, dynamic>{'ok': true}));
      expect(
        await api.updatePlatformConfig(token: 't', patch: <String, Map<String, Object>>{
          'support': <String, Object>{'email': ''},
        }),
        isNull,
      );
      expect(
        () => api.updatePlatformConfig(token: 't', patch: <String, Map<String, Object>>{}),
        throwsArgumentError,
      );
    });

    test('400 VALIDATION_FAILED: sunucu iletisi ve alan haritası (payload) korunur', () async {
      final api = _api(
        (_) async => _json(400, <String, dynamic>{
          'error': 'Bazı alanlar geçersiz.',
          'code': 'VALIDATION_FAILED',
          'fields': <String, dynamic>{'app.latest_version': 'sürüm major.minor.patch biçiminde olmalıdır.'},
        }),
      );
      final error = await _failureOf(
        () => api.updatePlatformConfig(token: 't', patch: <String, Map<String, Object>>{
          'app': <String, Object>{'latest_version': 'x'},
        }),
      );
      expect(error.message, 'Bazı alanlar geçersiz.');
      expect(error.statusCode, 400);
      expect((error.payload?['fields'] as Map)['app.latest_version'], contains('major.minor.patch'));
    });

    test('403 (süper kullanıcı değil): sunucu iletisi; oturum sonu sayılmaz', () async {
      final api = _api(
        (_) async => _json(403, <String, dynamic>{'error': 'Bu işlem için süper kullanıcı yetkisi gerekir.', 'code': 'FORBIDDEN_ROLE'}),
      );
      final error = await _failureOf(() => api.getPlatformConfig(token: 't'));
      expect(error.message, 'Bu işlem için yetkiniz yok.');
      expect(error.isForbidden, isTrue);
      expect(error.invalidatesSession, isFalse);
    });

    test('jargonlu sunucu iletisi (alan adı) kullanıcıya gösterilmez', () async {
      final api = _api((_) async => _json(400, <String, dynamic>{'error': 'update_url_ios geçersiz'}));
      final error = await _failureOf(() => api.getPlatformConfig(token: 't'));
      expect(error.message, AuthApi.jargonFallbackMessage);
    });
  });

  group('istemci hataları', () {
    test('GET: limit ve imleç sorgu parametresi (opak imleç aynen, URL kaçışlı)', () async {
      final seen = <Uri>[];
      final api = _api((request) async {
        seen.add(request.url);
        return _json(200, <String, dynamic>{'items': <Object>[], 'next_cursor': null});
      });
      await api.listClientErrors(token: 't');
      await api.listClientErrors(token: 't', limit: 25, cursor: 'WyIyMDI2Iiwi+/=Il0');
      expect(seen[0].queryParameters, <String, String>{'limit': '50'});
      expect(seen[1].queryParameters, <String, String>{'limit': '25', 'cursor': 'WyIyMDI2Iiwi+/=Il0'});
      expect(seen[1].path, '/admin/client-errors');
    });

    test('sayfa çözülür; 400 INVALID_CURSOR iletisi iletilir', () async {
      final ok = _api(
        (_) async => _json(200, <String, dynamic>{
          'items': <Object>[
            <String, dynamic>{'fingerprint': 'a', 'error_type': 'StateError', 'count': 3},
          ],
          'next_cursor': 'sonraki',
        }),
      );
      final page = await ok.listClientErrors(token: 't');
      expect(page.items.single.count, 3);
      expect(page.nextCursor, 'sonraki');

      final bad = _api((_) async => _json(400, <String, dynamic>{'error': 'Geçersiz imleç.', 'code': 'INVALID_CURSOR'}));
      expect((await _failureOf(() => bad.listClientErrors(token: 't', cursor: 'x'))).message, 'Geçersiz imleç.');
    });
  });

  group('AccountService', () {
    test('belirteç AuthService oturumundan alınır; oturum yoksa ağa çıkılmaz', () async {
      final auth = _FakeAuth();
      final seen = <String?>[];
      final service = AccountService(
        authService: auth,
        api: _api((request) async {
          seen.add(request.headers['Authorization']);
          return _json(200, <String, dynamic>{'can_delete': false});
        }),
        wiper: _FakeWiper(),
      );
      await service.previewDeletion();
      expect(seen, <String?>['Bearer tok-1']);

      auth.token = null;
      final error = await _failureOf(() => service.previewDeletion());
      expect(error.message, 'Oturum açmanız gerekmektedir.');
      expect(seen, hasLength(1));
    });

    test('401: oturum doğrulaması (refreshSession force) tetiklenir; yerel çıkış yapılmaz', () async {
      final auth = _FakeAuth();
      final service = AccountService(
        authService: auth,
        api: _api((_) async => _json(401, <String, dynamic>{'error': 'x'})),
        wiper: _FakeWiper(),
      );
      await _failureOf(() => service.previewDeletion());
      await Future<void>.delayed(Duration.zero);
      expect(auth.refreshForced, 1);
      expect(auth.logouts, 0);
    });

    test('yanlış parola (400) oturum doğrulaması TETİKLEMEZ', () async {
      final auth = _FakeAuth();
      final service = AccountService(
        authService: auth,
        api: _api((_) async => _json(400, <String, dynamic>{'error': 'x', 'code': 'CURRENT_PASSWORD_INVALID'})),
        wiper: _FakeWiper(),
      );
      await _failureOf(() => service.deleteAccount('yanlis'));
      await Future<void>.delayed(Duration.zero);
      expect(auth.refreshForced, 0);
      expect(auth.logouts, 0);
    });

    test('başarılı silme: ÖNCE merkezi çıkış, SONRA yerel temizlik', () async {
      final order = <String>[];
      final auth = _FakeAuth(order: order);
      final wiper = _FakeWiper(order: order);
      final service = AccountService(
        authService: auth,
        api: _api((_) async => _json(200, <String, dynamic>{'deleted': true})),
        wiper: wiper,
      );
      final report = await service.deleteAccount('Gizli123');
      expect(order, <String>['hint', 'logout', 'wipe'], reason: 'kayıtlı e-posta çıkıştan önce silinir');
      expect(report.complete, isTrue);
    });

    test('başarısız silme (engel / parola / ağ): çıkış ve temizlik YAPILMAZ', () async {
      for (final response in <http.Response>[
        _json(409, <String, dynamic>{'code': 'ACCOUNT_DELETE_BLOCKED', 'error': 'x', 'blockers': <Object>[]}),
        _json(400, <String, dynamic>{'code': 'CURRENT_PASSWORD_INVALID', 'error': 'x'}),
        _json(500, <String, dynamic>{'error': 'x'}),
      ]) {
        final order = <String>[];
        final service = AccountService(
          authService: _FakeAuth(order: order),
          api: _api((_) async => response),
          wiper: _FakeWiper(order: order),
        );
        await _failureOf(() => service.deleteAccount('x'));
        expect(order, isEmpty, reason: '${response.statusCode}');
      }
    });

    test('ACCOUNT_DELETED (hesap zaten silinmiş): hedef durum sağlanmıştır -> yerel temizliğe geçilir', () async {
      final order = <String>[];
      final auth = _FakeAuth(order: order);
      final service = AccountService(
        authService: auth,
        api: _api((_) async => _json(401, <String, dynamic>{'code': 'ACCOUNT_DELETED', 'error': 'Bu hesap silinmiş.'})),
        wiper: _FakeWiper(order: order),
      );
      await service.deleteAccount('x');
      expect(order, <String>['hint', 'logout', 'wipe']);
      expect(auth.refreshForced, 0, reason: '"oturum süresi doldu" iletisi bırakılmaz');
    });

    test('çıkış hata verse de silme tamamlanır ve temizlik çalışır', () async {
      final order = <String>[];
      final auth = _FakeAuth(order: order)..logoutThrows = true;
      final service = AccountService(
        authService: auth,
        api: _api((_) async => _json(200, <String, dynamic>{'deleted': true})),
        wiper: _FakeWiper(order: order),
      );
      await service.deleteAccount('x');
      expect(order, <String>['hint', 'logout', 'wipe']);
    });

    test('platform ayarı kaydı: yanıt ayar taşımıyorsa GET ile tazelenir', () async {
      final calls = <String>[];
      final service = AccountService(
        authService: _FakeAuth(),
        api: _api((request) async {
          calls.add(request.method);
          return request.method == 'PUT'
              ? _json(200, <String, dynamic>{'ok': true})
              : _json(200, <String, dynamic>{
                  'app': <String, dynamic>{'latest_version': '9.9.9'},
                });
        }),
        wiper: _FakeWiper(),
      );
      final config = await service.updatePlatformConfig(<String, Map<String, Object>>{
        'app': <String, Object>{'latest_version': '9.9.9'},
      });
      expect(calls, <String>['PUT', 'GET']);
      expect(config.app.latestVersion, '9.9.9');
    });

    test('isSuperUser rolden okunur', () {
      final auth = _FakeAuth();
      final service = AccountService(authService: auth, api: _api((_) async => _json(200, <String, dynamic>{})), wiper: _FakeWiper());
      expect(service.isSuperUser, isFalse);
      auth.role = UserRole.superUser;
      expect(service.isSuperUser, isTrue);
    });
  });

  group('accountErrorMessage', () {
    test('parola kodları bu akışa uygun (profil şifre değiştirme metni DEĞİL)', () {
      expect(AccountApi.accountErrorMessage('CURRENT_PASSWORD_REQUIRED'), isNot(contains('değiştirmek')));
      expect(AccountApi.accountErrorMessage('CURRENT_PASSWORD_INVALID'), isNot(contains('Mevcut şifre')));
      expect(AccountApi.accountErrorMessage('CURRENT_PASSWORD_LOCKED', retryAfterSeconds: 45), contains('45 saniye'));
    });

    test('bilinmeyen kod genel eşlemeye düşer; null null döner', () {
      expect(AccountApi.accountErrorMessage('FORBIDDEN_ROLE'), 'Bu işlem için yetkiniz yok.');
      expect(AccountApi.accountErrorMessage('BILINMEYEN_KOD'), isNull);
      expect(AccountApi.accountErrorMessage(null), isNull);
    });
  });
}

class _FakeAuth extends AuthService {
  _FakeAuth({this.order}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<String>? order;
  String? token = 'tok-1';
  UserRole role = UserRole.individual;
  int refreshForced = 0;
  int logouts = 0;
  bool logoutThrows = false;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(
          id: 1,
          fullName: 'Test',
          email: 't@x.com',
          loginName: null,
          role: role,
          isActive: true,
          token: token!,
        );

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }

  @override
  Future<void> logout() async {
    logouts++;
    order?.add('logout');
    if (logoutThrows) throw StateError('çıkış temizliği başarısız');
  }
}

class _FakeWiper implements LocalDataWiper {
  _FakeWiper({this.order});

  final List<String>? order;

  @override
  Future<void> clearSavedLoginIdentifier() async {
    order?.add('hint');
  }

  @override
  Future<LocalWipeReport> wipe() async {
    order?.add('wipe');
    return const LocalWipeReport();
  }
}
