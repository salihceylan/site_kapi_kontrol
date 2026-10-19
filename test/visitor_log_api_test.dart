// VisitorLogApi / VisitorLogService (lib/services/visitor_log_api.dart): sahte HTTP istemcisiyle uç noktalar, gövde
// biçimleri ve hata çevirisi (docs/PLATFORM_ZIYARETCI_KARGO.md "Hata kodları").
//
// Kurallar: yazma istekleri ASLA otomatik yeniden denenmez; 401 oturum sonudur; JSON olmayan 401/403 ara katman
// hatasıdır; ziyaretçi adı / firma / not günlüğe yazılmaz.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';

import 'screens/visitor_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...?headers},
);

VisitorLogApi _api(Future<http.Response> Function(http.Request request) handler) => VisitorLogApi(
  baseUrl: '$_base/',
  client: MockClient(handler),
  readTimeout: const Duration(seconds: 5),
  writeTimeout: const Duration(seconds: 5),
);

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

void main() {
  group('sakin uçları', () {
    test('liste: GET /app/visitor-entries, Bearer, sorgu; imleç', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'items': <Object>[vkEntry(9)], 'next_before_id': 9});
      });
      final page = await api.listMine(token: 'tok-1', siteCode: 11, limit: 30, beforeId: 40);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/app/visitor-entries');
      expect(seen.url.queryParameters, <String, String>{'site_code': '11', 'limit': '30', 'before_id': '40'});
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(page.items.single.id, 9);
      expect(page.nextBeforeId, 9);
    });

    test('özet: {unread} okunur; bozuk / eksik değer 0', () async {
      var body = <String, dynamic>{'unread': 3};
      final api = _api((request) async {
        expect(request.url.path, '/app/visitor-entries/summary');
        return _json(200, body);
      });
      expect(await api.unreadCount(token: 'tok-1'), 3);
      body = <String, dynamic>{'unread': '2'};
      expect(await api.unreadCount(token: 'tok-1'), 2);
      body = <String, dynamic>{'unread': -1};
      expect(await api.unreadCount(token: 'tok-1'), 0);
      body = <String, dynamic>{};
      expect(await api.unreadCount(token: 'tok-1'), 0);
    });

    test('görüldü: POST /app/visitor-entries/:id/seen; 200 {ok:true}', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'ok': true});
      });
      await api.markSeen(token: 'tok-1', id: 12);
      expect(seen.method, 'POST');
      expect(seen.url.path, '/app/visitor-entries/12/seen');
    });
  });

  group('yönetim uçları', () {
    test('liste: GET /manager/sites/:site/visitor-entries; tüm süzgeçler sorguda; items + total', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'items': <Object>[vkEntry(2), vkEntry(1)], 'total': 12});
      });
      final page = await api.listManaged(
        token: 'tok-1',
        siteCode: 11,
        kind: 'cargo',
        status: 'bekliyor',
        apartmentId: 301,
        query: '  aras ',
        from: '2026-10-01',
        to: '2026-10-31',
        limit: 20,
        offset: 40,
      );
      expect(seen.url.path, '/manager/sites/11/visitor-entries');
      expect(seen.url.queryParameters, <String, String>{
        'kind': 'cargo',
        'status': 'bekliyor',
        'apartment_id': '301',
        'q': 'aras',
        'from': '2026-10-01',
        'to': '2026-10-31',
        'limit': '20',
        'offset': '40',
      });
      expect(page.items.map((e) => e.id), <int>[2, 1]);
      expect(page.total, 12);
    });

    test('liste: boş süzgeçler sorguya yazılmaz', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'items': <Object>[], 'total': 0});
      });
      await api.listManaged(token: 'tok-1', siteCode: 11, kind: '', status: null, query: '  ');
      expect(seen.url.queryParameters, <String, String>{'limit': '50', 'offset': '0'});
    });

    test('create: POST gövdesi; 201 Entry; durum sunucudan', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(201, vkEntry(50, kind: 'visitor', name: 'Ayşe'));
      });
      final entry = await api.create(
        token: 'tok-1',
        siteCode: 11,
        request: const VisitorCreateRequest(kind: VisitorKind.visitor, visitorName: 'Ayşe', apartmentId: 301),
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/manager/sites/11/visitor-entries');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), <String, dynamic>{'kind': 'visitor', 'apartment_id': 301, 'visitor_name': 'Ayşe'});
      expect(entry.id, 50);
      expect(entry.status, VisitorStatus.iceride);
    });

    test('update: PATCH {status} / {note}; yalnız verilen alanlar', () async {
      final bodies = <Map<String, dynamic>>[];
      late http.Request last;
      final api = _api((request) async {
        last = request;
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(200, vkEntry(3, status: 'teslim_edildi'));
      });
      final entry = await api.update(token: 'tok-1', siteCode: 11, id: 3, status: VisitorStatus.teslimEdildi);
      await api.update(token: 'tok-1', siteCode: 11, id: 3, note: ' Kapıcıda ');
      expect(last.method, 'PATCH');
      expect(last.url.path, '/manager/sites/11/visitor-entries/3');
      expect(bodies, <Map<String, dynamic>>[
        <String, dynamic>{'status': 'teslim_edildi'},
        <String, dynamic>{'note': 'Kapıcıda'},
      ]);
      expect(entry.status, VisitorStatus.teslimEdildi);
    });

    test('kimliksiz Entry yanıtı anlaşılır hataya çevrilir; JSON olmayan 200 gövdesi de', () async {
      final noId = _api((request) async => _json(201, <String, dynamic>{'kind': 'cargo'}));
      final e1 = await _failureOf(
        () => noId.create(token: 't', siteCode: 11, request: const VisitorCreateRequest(kind: VisitorKind.cargo, visitorName: 'A')),
      );
      expect(e1.message, contains('beklenen biçimde değil'));
      final html = _api((request) async => http.Response('<html>', 200));
      final e2 = await _failureOf(() => html.listManaged(token: 't', siteCode: 11));
      expect(e2.message, contains('okunamadı'));
    });
  });

  group('hata çevirisi', () {
    test('sözleşme kodları düz Türkçe; `_` içermez; 140 karakterden kısa', () async {
      final cases = <(int, String)>[
        (403, 'MODULE_DISABLED'),
        (403, 'FORBIDDEN_ROLE'),
        (403, 'FORBIDDEN_SITE'),
        (404, 'VISITOR_ENTRY_NOT_FOUND'),
        (404, 'APARTMENT_NOT_FOUND'),
        (409, 'INVALID_TRANSITION'),
        (400, 'INVALID_BODY'),
      ];
      for (final (status, code) in cases) {
        final api = _api((request) async => _json(status, <String, dynamic>{'error': 'x_y', 'code': code}));
        final e = await _failureOf(() => api.listManaged(token: 't', siteCode: 11));
        expect(e.statusCode, status, reason: code);
        expect(e.code, code);
        expect(e.message, isNot(contains('_')), reason: code);
        expect(e.message.length, lessThan(140), reason: code);
      }
      final off = _api((request) async => _json(403, <String, dynamic>{'error': 'kapalı', 'code': 'MODULE_DISABLED', 'module': 'visitor_log'}));
      expect((await _failureOf(() => off.listManaged(token: 't', siteCode: 11))).message, 'Ziyaretçi ve kargo kaydı bu site için kapalı.');
      final transition = _api((request) async => _json(409, <String, dynamic>{'error': 'x', 'code': 'INVALID_TRANSITION', 'from': 'iptal', 'to': 'ayrildi'}));
      expect((await _failureOf(() => transition.update(token: 't', siteCode: 11, id: 1, status: VisitorStatus.ayrildi))).message, contains('değiştirilemez'));
    });

    test('401 JSON: oturum sonu (SessionExpiredException); JSON olmayan 403: ara katman, oturum sonu DEĞİL', () async {
      final expired = _api((request) async => _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'}));
      final e1 = await _failureOf(() => expired.unreadCount(token: 't'));
      expect(e1, isA<SessionExpiredException>());
      expect(e1.invalidatesSession, isTrue);
      final proxy = _api((request) async => http.Response('<html>blocked</html>', 403));
      final e2 = await _failureOf(() => proxy.unreadCount(token: 't'));
      expect(e2, isNot(isA<SessionExpiredException>()));
      expect(e2.fromIntermediary, isTrue);
    });

    test('429: Retry-After süresi mesaja ve istisnaya işlenir', () async {
      final api = _api((request) async => _json(429, <String, dynamic>{'error': 'Çok fazla istek.', 'code': 'RATE_LIMITED'}, headers: <String, String>{'retry-after': '120'}));
      final e = await _failureOf(() => api.create(token: 't', siteCode: 11, request: const VisitorCreateRequest(kind: VisitorKind.cargo, visitorName: 'A')));
      expect(e.statusCode, 429);
      expect(e.retryAfterSeconds, 120);
    });

    test('yazma hatasında yeniden deneme YOK: 500 tek istek', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        return _json(500, <String, dynamic>{'error': 'patladı', 'errorId': 'abc'});
      });
      final e = await _failureOf(() => api.update(token: 't', siteCode: 11, id: 1, status: VisitorStatus.iptal));
      expect(calls, 1);
      expect(e.message, contains('abc'));
    });

    test('ağ hatası düz Türkçe', () async {
      final api = _api((request) async => throw http.ClientException('boom'));
      final e = await _failureOf(() => api.listMine(token: 't'));
      expect(e.message, contains('bağlanılamadı'));
    });
  });

  group('VisitorLogService', () {
    test('belirteç oturumdan; oturum yoksa istek gitmez', () async {
      final auth = _FakeAuth();
      var calls = 0;
      final service = VisitorLogService(
        authService: auth,
        api: _api((request) async {
          calls++;
          expect(request.headers['Authorization'], 'Bearer tok-1');
          return _json(200, <String, dynamic>{'unread': 1});
        }),
      );
      expect(await service.unreadCount(), 1);
      auth.token = null;
      final e = await _failureOf(service.unreadCount);
      expect(e.message, contains('Oturum'));
      expect(calls, 1);
    });

    test('401: oturum sunucudan doğrulatılır (refreshSession force)', () async {
      final auth = _FakeAuth();
      final service = VisitorLogService(
        authService: auth,
        api: _api((request) async => _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'})),
      );
      await _failureOf(() => service.listMine());
      expect(auth.refreshForced, 1);
    });

    test('debugApiFactory: ekranlar servisi kendileri kurduğunda sahte API verilir', () async {
      final auth = _FakeAuth();
      VisitorLogService.debugApiFactory = (_) => _api((request) async => _json(200, <String, dynamic>{'unread': 7}));
      addTearDown(() => VisitorLogService.debugApiFactory = null);
      expect(await VisitorLogService(authService: auth).unreadCount(), 7);
    });

    test('sahte servis kalıbı: fixtures sunucu kurallarını uygular (geçiş, kurul, sakin görünümü)', () async {
      final service = seededVisitor(VisitorFakeAuth());
      final closed = await service.update(11, 3, status: VisitorStatus.teslimEdildi);
      expect(closed.status, VisitorStatus.teslimEdildi);
      expect(closed.nextStatuses, isEmpty);
      final e = await _failureOf(() => service.update(11, 3, status: VisitorStatus.iptal));
      expect(e.code, 'INVALID_TRANSITION');
      final mine = await service.listMine();
      expect(mine.items.map((i) => i.id), <int>[3, 2, 1], reason: 'ortak alan kaydı (4) sakine gelmez');
      expect(mine.items.every((i) => i.recordedByName == null), isTrue);
      expect(await service.unreadCount(), 1, reason: 'kapanmak görüldü saymaz: 3 hâlâ görülmemiş');
      await service.markSeen(3);
      expect(await service.unreadCount(), 0);
    });
  });
}
