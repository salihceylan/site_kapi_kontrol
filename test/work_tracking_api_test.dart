// WorkTrackingApi / WorkTrackingService (lib/services/work_tracking_api.dart): sahte HTTP istemcisiyle uç noktalar,
// gövde biçimleri, hata çevirisi (docs/PLATFORM_IS_TAKIBI.md "Hata kodları") ve idempotency anahtarı yönetimi.
//
// Kurallar: yazma istekleri ASLA otomatik yeniden denenmez; 401 oturum sonudur; JSON olmayan 401/403 ara katman
// hatasıdır; yeniden gönderimde (aynı veri) AYNI idempotency_key kullanılır, veri değişince ya da başarıdan sonra
// YENİ anahtar üretilir.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';

import 'screens/work_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        ...?headers,
      },
    );

WorkTrackingApi _api(Future<http.Response> Function(http.Request request) handler) {
  return WorkTrackingApi(
    baseUrl: '$_base/',
    client: MockClient(handler),
    readTimeout: const Duration(seconds: 5),
    writeTimeout: const Duration(seconds: 5),
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

class _FakeAuth extends AuthService {
  _FakeAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  String? token = 'tok-1';
  int refreshForced = 0;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(
          id: 1,
          fullName: 'Test',
          email: 't@x.com',
          loginName: null,
          role: UserRole.siteManager,
          isActive: true,
          token: token!,
        );

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

const WorkCreateRequest _request = WorkCreateRequest(
  siteCode: 11,
  category: WorkCategory.ariza,
  locationType: WorkLocationType.ortakAlan,
  title: 'Asansör',
  description: 'Çalışmıyor',
);

void main() {
  group('sakin uçları', () {
    test('liste: GET, Bearer, sorgu; imleç ve okunmamış sayısı', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[wkResident(9, unread: true)],
          'next_before_id': 9,
          'unread_updates': 1,
        });
      });
      final page = await api.listMine(
        token: 'tok-1',
        siteCode: 11,
        status: 'open',
        limit: 30,
        beforeId: 40,
      );
      expect(seen.method, 'GET');
      expect(seen.url.path, '/app/work-items');
      expect(seen.url.queryParameters, <String, String>{
        'site_code': '11',
        'status': 'open',
        'limit': '30',
        'before_id': '40',
      });
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(page.items.single.unread, isTrue);
      expect(page.nextBeforeId, 9);
      expect(page.unreadUpdates, 1);
    });

    test('create: POST gövdesi idempotency_key taşır; 201 kabul; replayed okunur', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(201, <String, dynamic>{'item': wkResident(12), 'replayed': true});
      });
      final result = await api.create(
        token: 'tok-1',
        request: _request,
        idempotencyKey: 'wk-0123456789abcdef',
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/app/work-items');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['idempotency_key'], 'wk-0123456789abcdef');
      expect(body['site_code'], 11);
      expect(body.containsKey('apartment_id'), isFalse);
      expect(result.replayed, isTrue);
      expect(result.item.id, 12);
    });

    test('ayrıntı, iptal, yorum ve görüldü uçları', () async {
      final seen = <String>[];
      final api = _api((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/cancel')) {
          return _json(200, <String, dynamic>{'item': wkResident(5, status: 'iptal')});
        }
        if (request.url.path.endsWith('/comments')) {
          expect(jsonDecode(request.body), <String, dynamic>{
            'body': 'Merhaba',
            'idempotency_key': 'wk-abcdefgh12345678',
          });
          return _json(201, <String, dynamic>{'event': wkEvent(8, body: 'Merhaba'), 'replayed': false});
        }
        if (request.url.path.endsWith('/seen')) {
          return _json(200, <String, dynamic>{'id': 5, 'unread': false});
        }
        return _json(200, <String, dynamic>{'item': wkResident(5), 'events': <Object>[wkEvent(1, type: 'created', to: 'yeni')]});
      });
      final detail = await api.getMine(token: 't', id: 5);
      expect(detail.events.single.type, WorkEventType.created);
      final cancelled = await api.cancelMine(token: 't', id: 5);
      expect(cancelled.status, WorkStatus.iptal);
      final event = await api.commentMine(token: 't', id: 5, body: ' Merhaba ', idempotencyKey: 'wk-abcdefgh12345678');
      expect(event.body, 'Merhaba');
      await api.markSeen(token: 't', id: 5);
      expect(seen, <String>[
        'GET /app/work-items/5',
        'POST /app/work-items/5/cancel',
        'POST /app/work-items/5/comments',
        'POST /app/work-items/5/seen',
      ]);
    });
  });

  group('yönetim uçları', () {
    test('liste: süzgeç parametreleri; boş süzgeç gönderilmez; sayaçlar', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[wkManaged(3)],
          'next_before_id': null,
          'counts': <String, dynamic>{'yeni': 1},
        });
      });
      final page = await api.listManaged(
        token: 'tok-1',
        siteCode: 11,
        status: 'open',
        category: 'ariza',
        priority: 'acil',
        assigned: 'me',
        query: '  asansör ',
        beforeId: 50,
      );
      expect(seen.url.path, '/manager/sites/11/work-items');
      expect(seen.url.queryParameters, <String, String>{
        'status': 'open',
        'category': 'ariza',
        'priority': 'acil',
        'assigned': 'me',
        'q': 'asansör',
        'limit': '30',
        'before_id': '50',
      });
      expect(page.counts[WorkStatus.yeni], 1);

      await api.listManaged(token: 'tok-1', siteCode: 11, status: '', query: '  ');
      expect(seen.url.queryParameters, <String, String>{'limit': '30'});
    });

    test('PATCH yalnız verilen alanları gönderir (null = temizle); yanıt ayrıntıdır', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'item': wkManaged(3, status: 'islemde'),
          'events': <Object>[],
          'next_statuses': <Object>['beklemede'],
        });
      });
      final detail = await api.updateManaged(
        token: 't',
        siteCode: 11,
        id: 3,
        fields: <String, Object?>{'status': 'islemde', 'assigned_to': null, 'due_date': '2026-10-25'},
      );
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/manager/sites/11/work-items/3');
      expect(jsonDecode(seen.body), <String, dynamic>{
        'status': 'islemde',
        'assigned_to': null,
        'due_date': '2026-10-25',
      });
      expect(detail.nextStatuses, <WorkStatus>[WorkStatus.beklemede]);
    });

    test('yorum görünürlüğü: internal / public; atanabilir kişiler', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _api((request) async {
        if (request.url.path.endsWith('/assignees')) {
          return _json(200, <String, dynamic>{
            'items': <Object>[<String, dynamic>{'user_code': 7, 'name': 'Ben', 'role': 'manager'}],
          });
        }
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(201, <String, dynamic>{'event': wkEvent(8, visibility: 'internal', body: 'x'), 'replayed': false});
      });
      await api.commentManaged(token: 't', siteCode: 11, id: 3, body: 'x', internal: true, idempotencyKey: 'wk-aaaaaaaa11111111');
      await api.commentManaged(token: 't', siteCode: 11, id: 3, body: 'x', internal: false, idempotencyKey: 'wk-bbbbbbbb22222222');
      expect(bodies.map((b) => b['visibility']), <String>['internal', 'public']);
      final list = await api.assignees(token: 't', siteCode: 11);
      expect(list.single.userCode, 7);
    });
  });

  group('hata çevirisi (düz Türkçe)', () {
    Future<ApiException> fail(int status, Map<String, dynamic>? body, {Map<String, String>? headers, String? raw}) {
      final api = _api((request) async {
        if (raw != null) return http.Response(raw, status, headers: headers ?? const <String, String>{});
        return _json(status, body, headers: headers);
      });
      return _failureOf(() => api.getMine(token: 't', id: 1));
    }

    test('403 MODULE_DISABLED / FORBIDDEN_ROLE / FORBIDDEN_SITE / NOT_A_RESIDENT', () async {
      final off = await fail(403, <String, dynamic>{'error': 'x', 'code': 'MODULE_DISABLED', 'module': 'work_tracking'});
      expect(off.message, 'İş takibi bu site için kapalı.');
      expect(off.code, 'MODULE_DISABLED');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_ROLE'})).message, 'Bu işlem için yetkiniz yok.');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_SITE'})).message, 'Bu siteye erişim yetkiniz yok.');
      expect((await fail(403, <String, dynamic>{'error': 'x', 'code': 'NOT_A_RESIDENT'})).message, contains('daire sakini'));
    });

    test('404 / 409 kodları', () async {
      final missing = await fail(404, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_NOT_FOUND'});
      expect(missing.statusCode, 404);
      expect(missing.message, 'Talep bulunamadı ya da erişiminiz yok.');
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'INVALID_TRANSITION', 'from': 'yeni', 'to': 'kapandi'})).message, contains('değiştirilemez'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_CLOSED'})).message, contains('kapandığı'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_LIMIT', 'open_limit': 2000})).message, contains('sınırına'));
      expect((await fail(409, <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_COMMENT_LIMIT'})).message, contains('yorum eklenemez'));
    });

    test('429 saatlik talep sınırı: Retry-After saniyesi ve süre metni', () async {
      final e = await fail(
        429,
        <String, dynamic>{'error': 'x', 'code': 'WORK_ITEM_RATE_LIMITED', 'retry_after_seconds': 1800},
        headers: <String, String>{'retry-after': '1800'},
      );
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 1800);
      expect(e.message, contains('30 dakika'));
      final generic = await fail(429, <String, dynamic>{'error': 'Çok fazla istek.'}, headers: <String, String>{'retry-after': '90'});
      expect(generic.retryAfterSeconds, 90);
      expect(generic.message, contains('2 dakika'));
    });

    test('400 INVALID_BODY: sunucunun alan etiketli Türkçe metni korunur; jargon gizlenir', () async {
      final field = await fail(400, <String, dynamic>{'error': 'Başlık 1-120 karakter olmalıdır.', 'code': 'INVALID_BODY'});
      expect(field.message, 'Başlık 1-120 karakter olmalıdır.');
      final jargon = await fail(400, <String, dynamic>{'error': 'idempotency_key geçersiz', 'code': 'INVALID_BODY'});
      expect(jargon.message, isNot(contains('idempotency_key')));
    });

    test('401 oturum sonu; JSON olmayan 401/403 ara katman; JSON olmayan 413; 5xx', () async {
      expect(await fail(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'}), isA<SessionExpiredException>());
      final proxy = await fail(403, null, raw: '<html>blocked</html>', headers: <String, String>{'content-type': 'text/html'});
      expect(proxy.fromIntermediary, isTrue);
      expect(proxy.invalidatesSession, isFalse);
      final big = await fail(413, null, raw: '');
      expect(big.code, 'BODY_TOO_LARGE');
      final server = await fail(502, null, raw: 'bad gateway');
      expect(server.message, contains('502'));
    });
  });

  group('taşıma', () {
    test('yazma isteği ağ hatasında YENİDEN DENENMEZ', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        throw http.ClientException('kopuk');
      });
      final e = await _failureOf(
        () => api.create(token: 't', request: _request, idempotencyKey: 'wk-0123456789abcdef'),
      );
      expect(calls, 1);
      expect(e.message, contains('Sunucuya bağlanılamadı'));
    });

    test('2xx ama beklenmeyen gövde: anlaşılır hata', () async {
      final api = _api((request) async => _json(200, <String, dynamic>{'item': <String, dynamic>{}}));
      final e = await _failureOf(() => api.getMine(token: 't', id: 1));
      expect(e.message, contains('beklenen biçimde değil'));
    });
  });

  group('WorkTrackingService', () {
    test('oturum yoksa ağa çıkmaz; 401 merkezi doğrulamayı tetikler', () async {
      var calls = 0;
      final auth = _FakeAuth()..token = null;
      final service = WorkTrackingService(
        authService: auth,
        api: _api((request) async {
          calls++;
          return _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'});
        }),
      );
      final none = await _failureOf(() => service.listMine());
      expect(none.message, 'Oturum açmanız gerekmektedir.');
      expect(calls, 0);
      auth.token = 'tok-1';
      final expired = await _failureOf(() => service.listMine());
      expect(expired, isA<SessionExpiredException>());
      expect(auth.refreshForced, 1);
    });

    test('idempotency: hata sonrası aynı veri AYNI anahtar; başarıdan sonra ve veri değişince YENİ anahtar', () async {
      final keys = <String>[];
      var fail = true;
      final auth = _FakeAuth();
      final service = WorkTrackingService(
        authService: auth,
        api: _api((request) async {
          keys.add((jsonDecode(request.body) as Map<String, dynamic>)['idempotency_key'] as String);
          if (fail) return _json(503, <String, dynamic>{'error': 'Geçici hata.'});
          return _json(201, <String, dynamic>{'item': wkResident(12), 'replayed': false});
        }),
      );
      await _failureOf(() => service.createItem(_request));
      await _failureOf(() => service.createItem(_request));
      expect(keys[0], keys[1], reason: 'yanıtı kaybolan istek aynı anahtarla yinelenir');
      expect(keys[0], matches(RegExp(r'^[A-Za-z0-9_.:-]{8,64}$')));

      // Veri değişince yeni anahtar.
      const changed = WorkCreateRequest(siteCode: 11, category: WorkCategory.ariza, locationType: WorkLocationType.ortakAlan, title: 'Asansör', description: 'Çalışmıyor, çok acil', urgent: true);
      await _failureOf(() => service.createItem(changed));
      expect(keys[2], isNot(keys[0]));
      // İlk veriye dönülünce ilk anahtar yeniden kullanılır (A -> B -> A çift kayıt yaratmaz).
      await _failureOf(() => service.createItem(_request));
      expect(keys[3], keys[0]);

      // Başarı: anahtar atılır; aynı veriyle SONRAKİ talep yeni anahtar alır.
      fail = false;
      await service.createItem(_request);
      expect(keys[4], keys[0]);
      await service.createItem(_request);
      expect(keys[5], isNot(keys[0]));
    });

    test('yorum anahtarı: hata sonrası aynı; başarıdan sonra yeni; iç / public ayrı', () async {
      final keys = <String>[];
      var fail = true;
      final service = WorkTrackingService(
        authService: _FakeAuth(),
        api: _api((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          keys.add('${body['visibility']}:${body['idempotency_key']}');
          if (fail) return _json(500, <String, dynamic>{'error': 'x'});
          return _json(201, <String, dynamic>{'event': wkEvent(8, body: 'a'), 'replayed': false});
        }),
      );
      await _failureOf(() => service.commentManaged(11, 3, 'a', internal: true));
      await _failureOf(() => service.commentManaged(11, 3, 'a', internal: true));
      await _failureOf(() => service.commentManaged(11, 3, 'a', internal: false));
      expect(keys[0], keys[1]);
      expect(keys[2].split(':').last, isNot(keys[0].split(':').last), reason: 'iç not ile herkese açık yorum ayrı kayıttır');
      fail = false;
      await service.commentManaged(11, 3, 'a', internal: true);
      await service.commentManaged(11, 3, 'a', internal: true);
      expect(keys[3], keys[0]);
      expect(keys[4], isNot(keys[0]));
    });
  });
}
