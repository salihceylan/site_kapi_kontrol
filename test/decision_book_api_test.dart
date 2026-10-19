// DecisionBookApi / DecisionBookService (lib/services/decision_book_api.dart): sahte HTTP istemcisiyle uç noktalar,
// sorgu ve gövde biçimleri, iki imleç türü (`before_id` / `cursor`), hata çevirisi ve PDF için yıl toplama.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';

import 'screens/decision_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

DecisionBookApi _api(Future<http.Response> Function(http.Request request) handler) => DecisionBookApi(
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
      : UserSession(id: 1, fullName: 'Test', email: 't@x.com', loginName: null, role: UserRole.siteManager, isActive: true, token: token!);

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

final DecisionInput _input = DecisionInput(
  meetingType: DecisionMeetingType.yonetimKurulu,
  meetingDate: DateTime(2026, 10, 2),
  title: 'Çatı onarımı',
  body: 'Çatı onarımı için üç teklif alınmasına karar verildi.',
  voteResult: DecisionVoteResult.kabul,
  votesFor: 3,
  supersedesId: 1,
);

void main() {
  group('yönetim uçları', () {
    test('listManaged: yol ve tüm süzgeçler; before_id imleci; yanıt ayrışır', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'items': <Object>[dcJson(1, status: 'kesin', no: 1), dcJson(2)], 'next_before_id': 2, 'years': <int>[2026, 2025]});
      });
      final page = await api.listManaged(
        token: 't',
        siteCode: 11,
        year: 2026,
        status: 'kesin',
        meetingType: 'genel_kurul',
        query: ' 2026/3 ',
        cursor: const DecisionCursor.beforeId(40),
        limit: 25,
      );
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/manager/sites/11/decisions');
      expect(seen!.url.queryParameters, <String, String>{
        'year': '2026',
        'status': 'kesin',
        'meeting_type': 'genel_kurul',
        'q': '2026/3',
        'before_id': '40',
        'limit': '25',
      });
      expect(seen!.headers['Authorization'], 'Bearer t');
      expect(page.items.map((d) => d.id), <int>[1, 2]);
      expect(page.next, const DecisionCursor.beforeId(2));
      expect(page.years, <int>[2026, 2025]);
    });

    test('listManaged: boş süzgeçler gönderilmez; opak cursor imleci "cursor" olarak gider', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'items': <Object>[], 'next_cursor': null});
      });
      await api.listManaged(token: 't', siteCode: 11, query: '  ', cursor: const DecisionCursor.opaque('eyJpZCI6M30'));
      expect(seen!.url.queryParameters, <String, String>{'status': 'all', 'cursor': 'eyJpZCI6M30', 'limit': '30'});
    });

    test('getManaged: {decision} sarmalı', () async {
      final api = _api((r) async => _json(200, <String, dynamic>{'decision': dcJson(4, status: 'kesin', no: 1)}));
      final d = await api.getManaged(token: 't', siteCode: 11, id: 4);
      expect(d.id, 4);
      expect(d.numberLabel, '2026/1');
    });

    test('create: POST gövdesi sözleşmeye uygun, 201', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(201, <String, dynamic>{'decision': dcJson(9, supersedesId: 1, supersedesLabel: '2026/1')});
      });
      final d = await api.create(token: 't', siteCode: 11, input: _input);
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/manager/sites/11/decisions');
      expect(jsonDecode(seen!.body), <String, dynamic>{
        'meeting_type': 'yonetim_kurulu',
        'meeting_date': '2026-10-02',
        'title': 'Çatı onarımı',
        'body': 'Çatı onarımı için üç teklif alınmasına karar verildi.',
        'vote_result': 'kabul',
        'votes_for': 3,
        'visibility': 'yonetim',
        'supersedes_id': 1,
      });
      expect(d.supersedes, const DecisionRef(id: 1, numberLabel: '2026/1'));
    });

    test('update: PATCH yalnız verilen alanlar (null dahil)', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'decision': dcJson(9, title: 'Yeni')});
      });
      await api.update(token: 't', siteCode: 11, id: 9, fields: <String, Object?>{'title': 'Yeni', 'attendees': null});
      expect(seen!.method, 'PATCH');
      expect(seen!.url.path, '/manager/sites/11/decisions/9');
      expect(jsonDecode(seen!.body), <String, dynamic>{'title': 'Yeni', 'attendees': null});
    });

    test('delete: {deleted:true} ve 204 kabul; {deleted:false} hata', () async {
      http.Request? seen;
      await _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'deleted': true});
      }).delete(token: 't', siteCode: 11, id: 9);
      expect(seen!.method, 'DELETE');
      expect(seen!.url.path, '/manager/sites/11/decisions/9');
      await _api((r) async => http.Response('', 204)).delete(token: 't', siteCode: 11, id: 9);
      final e = await _failureOf(() => _api((r) async => _json(200, <String, dynamic>{'deleted': false})).delete(token: 't', siteCode: 11, id: 9));
      expect(e.message, contains('beklenen biçimde değil'));
    });

    test('finalize: POST .../finalize; numaralı karar döner', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'decision': dcJson(9, status: 'kesin', no: 3)});
      });
      final d = await api.finalize(token: 't', siteCode: 11, id: 9);
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/manager/sites/11/decisions/9/finalize');
      expect(d.isFinal, isTrue);
      expect(d.numberLabel, '2026/3');
    });
  });

  group('sakin uçları', () {
    test('listMine: yol, site / yıl / imleç; sakin biçimi (status yok) kesin okunur', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{
          'items': <Object>[dcResident(dcJson(1, status: 'kesin', no: 1, visibility: 'sakinler'))],
          'next_before_id': null,
          'years': <int>[2026],
        });
      });
      final page = await api.listMine(token: 't', siteCode: 11, year: 2026, cursor: const DecisionCursor.beforeId(8));
      expect(seen!.url.path, '/app/decisions');
      expect(seen!.url.queryParameters, <String, String>{'site_code': '11', 'year': '2026', 'before_id': '8', 'limit': '30'});
      expect(page.items.single.isFinal, isTrue);
      expect(page.items.single.visibility, isNull);
      expect(page.next, isNull);
    });

    test('getMine: /app/decisions/:id', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'decision': dcResident(dcJson(1, status: 'kesin', no: 1))});
      });
      final d = await api.getMine(token: 't', id: 1);
      expect(seen!.url.path, '/app/decisions/1');
      expect(d.createdByName, isNull);
    });
  });

  group('hata çevirisi', () {
    test('400 INVALID_FIELD: sunucu metni ve alan adı taşınır', () async {
      final e = await _failureOf(
        () => _api((r) async => _json(400, <String, dynamic>{'code': 'INVALID_FIELD', 'field': 'title', 'error': 'Karar başlığı en fazla 160 karakter olabilir.'}))
            .create(token: 't', siteCode: 11, input: _input),
      );
      expect(e.message, 'Karar başlığı en fazla 160 karakter olabilir.');
      expect(decisionInvalidField(e), 'title');
      final bare = await _failureOf(
        () => _api((r) async => _json(400, <String, dynamic>{'code': 'INVALID_FIELD', 'field': 'meeting_date'})).create(token: 't', siteCode: 11, input: _input),
      );
      expect(bare.message, 'Toplantı tarihi geçersiz. Kontrol edip tekrar deneyin.');
    });

    test('404 / 409 / 403 kodları Türkçe', () async {
      Future<ApiException> of(int status, String code) => _failureOf(
        () => _api((r) async => _json(status, <String, dynamic>{'code': code, 'error': 'x'})).getManaged(token: 't', siteCode: 11, id: 1),
      );
      expect((await of(404, 'DECISION_NOT_FOUND')).message, contains('Karar bulunamadı'));
      final finalErr = await of(409, 'DECISION_FINAL');
      expect(finalErr.message, contains('kesinleşmiş'));
      expect(finalErr.code, 'DECISION_FINAL');
      expect((await of(403, 'FORBIDDEN_ROLE')).message, 'Bu işlem için yetkiniz yok.');
      expect((await of(403, 'MODULE_DISABLED')).message, 'Karar Defteri bu site için kapalı.');
    });

    test('401 oturum sonu; JSON olmayan 403 aracı katman (oturum düşmez)', () async {
      final expired = await _failureOf(() => _api((r) async => _json(401, <String, dynamic>{'code': 'TOKEN_EXPIRED'})).listMine(token: 't'));
      expect(expired, isA<SessionExpiredException>());
      final proxy = await _failureOf(() => _api((r) async => http.Response('<html>engellendi</html>', 403)).listMine(token: 't'));
      expect(proxy.fromIntermediary, isTrue);
      expect(proxy.invalidatesSession, isFalse);
    });
  });

  group('DecisionBookService', () {
    test('401 oturum yenilemeyi tetikler; oturum yoksa istek yapılmaz', () async {
      final auth = _FakeAuth();
      var calls = 0;
      final service = DecisionBookService(
        authService: auth,
        api: _api((r) async {
          calls++;
          return _json(401, <String, dynamic>{'code': 'TOKEN_EXPIRED'});
        }),
      );
      await expectLater(service.listMine(), throwsA(isA<SessionExpiredException>()));
      expect(auth.refreshForced, 1);
      auth.token = null;
      await expectLater(service.listMine(), throwsA(isA<ApiException>()));
      expect(calls, 1);
    });

    test('collectFinalForYear: imleçle tüm sayfalar, yalnız o yılın kesinleri, metinsiz kayıt ayrıntıdan, numara sırası', () async {
      final requests = <Uri>[];
      final api = _api((r) async {
        requests.add(r.url);
        if (r.url.path.endsWith('/decisions/7')) {
          return _json(200, <String, dynamic>{'decision': dcJson(7, status: 'kesin', no: 1, body: 'Tam metin')});
        }
        final cursor = r.url.queryParameters['cursor'];
        if (cursor == null) {
          return _json(200, <String, dynamic>{
            'items': <Object>[dcJson(8, status: 'kesin', no: 3), dcJson(9), dcJson(5, status: 'kesin', no: 2, date: '2025-01-01')],
            'next_cursor': 'p2',
          });
        }
        return _json(200, <String, dynamic>{
          'items': <Object>[dcJson(7, status: 'kesin', no: 1, body: ''), dcJson(6, status: 'kesin', no: 2)],
          'next_cursor': null,
        });
      });
      final service = DecisionBookService(authService: _FakeAuth(), api: api);
      final list = await service.collectFinalForYear(11, 2026);
      expect(list.map((d) => d.id), <int>[7, 6, 8]);
      expect(list.first.body, 'Tam metin');
      expect(requests.first.queryParameters['status'], 'kesin');
      expect(requests.first.queryParameters['year'], '2026');
      expect(requests.first.queryParameters['limit'], '${DecisionBookService.pdfPageSize}');
      expect(requests[1].queryParameters['cursor'], 'p2');
      expect(requests.length, 3);
    });

    test('collectFinalForYear: aynı imleci tekrarlayan sunucuda döngü yok', () async {
      var calls = 0;
      final api = _api((r) async {
        calls++;
        return _json(200, <String, dynamic>{'items': <Object>[dcJson(1, status: 'kesin', no: 1)], 'next_before_id': 1});
      });
      final list = await DecisionBookService(authService: _FakeAuth(), api: api).collectFinalForYear(11, 2026);
      expect(list.single.id, 1);
      expect(calls, 2, reason: 'ikinci sayfa yalnız bilinen kaydı döndürür: durur');
    });
  });
}
