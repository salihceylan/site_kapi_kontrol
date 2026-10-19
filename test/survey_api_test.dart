// SurveyApi / SurveyService (lib/services/survey_api.dart): sahte HTTP istemcisiyle uç noktalar, gövde biçimleri ve
// hata çevirisi (docs/PLATFORM_ANKET.md "Hata kodları").
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/survey_api.dart';

import 'screens/survey_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...?headers},
);

SurveyApi _api(Future<http.Response> Function(http.Request request) handler) => SurveyApi(
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
      : UserSession(id: 1, fullName: 'Test', email: 't@x.com', loginName: null, role: UserRole.apartmentOwner, isActive: true, token: token!);

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

void main() {
  group('yönetim uçları', () {
    test('listManaged: yol, süzgeç ve sayfa; yanıt ayrışır', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'items': <Object>[svSurvey(1), svSurvey(2, status: 'draft')], 'total': 2});
      });
      final page = await api.listManaged(token: 't', siteCode: 11, status: 'open', limit: 10, offset: 20);
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/manager/sites/11/surveys');
      expect(seen!.url.queryParameters, <String, String>{'status': 'open', 'limit': '10', 'offset': '20'});
      expect(seen!.headers['Authorization'], 'Bearer t');
      expect(page.total, 2);
      expect(page.items.map((s) => s.id), <int>[1, 2]);
    });

    test('create: POST gövdesi sözleşmeye uygun, 201 Detail', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(201, svSurvey(7, status: 'draft'));
      });
      final detail = await api.create(
        token: 't',
        siteCode: 11,
        request: const SurveyCreateRequest(
          title: 'Başlık',
          question: 'Soru',
          options: <String>['A', 'B'],
          targetType: SurveyTargetType.apartments,
          apartmentIds: <int>[5, 6],
          anonymous: false,
        ),
      );
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['target'], <String, dynamic>{'type': 'apartments', 'apartment_ids': <int>[5, 6]});
      expect(body['anonymous'], isFalse);
      expect(body['publish'], 'draft');
      expect(detail.id, 7);
      expect(detail.summary.isDraft, isTrue);
    });

    test('open / close / delete / voters / update yolları', () async {
      final calls = <String>[];
      final api = _api((r) async {
        calls.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
        if (r.url.path.endsWith('/voters')) {
          return _json(200, <String, dynamic>{'items': <Object>[<String, dynamic>{'user_code': 1, 'full_name': 'A', 'option_index': 0}], 'total': 1});
        }
        if (r.method == 'DELETE') return _json(200, <String, dynamic>{'ok': true});
        return _json(200, svSurvey(3));
      });
      await api.open(token: 't', siteCode: 11, id: 3);
      await api.close(token: 't', siteCode: 11, id: 3);
      await api.update(token: 't', siteCode: 11, id: 3, fields: <String, Object?>{'title': 'x'});
      await api.delete(token: 't', siteCode: 11, id: 3);
      final voters = await api.voters(token: 't', siteCode: 11, id: 3, limit: 5, offset: 10);
      expect(voters.items.single.fullName, 'A');
      expect(calls, <String>[
        'POST /manager/sites/11/surveys/3/open',
        'POST /manager/sites/11/surveys/3/close',
        'PATCH /manager/sites/11/surveys/3',
        'DELETE /manager/sites/11/surveys/3',
        'GET /manager/sites/11/surveys/3/voters?limit=5&offset=10',
      ]);
    });

    test('delete: ok:true gelmezse hata', () async {
      final api = _api((r) async => _json(200, <String, dynamic>{}));
      final e = await _failureOf(() => api.delete(token: 't', siteCode: 11, id: 3));
      expect(e.message, contains('beklenen biçimde değil'));
    });
  });

  group('sakin uçları', () {
    test('listMine: site_code / before_id isteğe bağlı', () async {
      final urls = <Uri>[];
      final api = _api((r) async {
        urls.add(r.url);
        return _json(200, <String, dynamic>{'items': <Object>[svSurvey(1)], 'next_before_id': null});
      });
      await api.listMine(token: 't');
      final page = await api.listMine(token: 't', siteCode: 11, beforeId: 9, limit: 5);
      expect(urls[0].path, '/app/surveys');
      expect(urls[0].queryParameters, <String, String>{'limit': '30'});
      expect(urls[1].queryParameters, <String, String>{'site_code': '11', 'limit': '5', 'before_id': '9'});
      expect(page.items.single.id, 1);
    });

    test('vote: gövde {option_index}; sarmalı yanıt da okunur', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{'survey': svSurvey(1, myVote: 2)});
      });
      final item = await api.vote(token: 't', id: 1, optionIndex: 2);
      expect(seen!.url.path, '/app/surveys/1/vote');
      expect(jsonDecode(seen!.body), <String, dynamic>{'option_index': 2});
      expect(item.myVote, 2);
      expect(item.showsResults, isTrue);
    });
  });

  group('hata çevirisi', () {
    for (final (status, code, fragment) in const <(int, String, String)>[
      (404, 'SURVEY_NOT_FOUND', 'Anket bulunamadı'),
      (409, 'INVALID_STATE', 'bu durumda'),
      (409, 'SURVEY_CLOSED', 'oylamaya kapalı'),
      (409, 'ALREADY_VOTED', 'zaten oy'),
      (409, 'APARTMENT_ALREADY_VOTED', 'daire başına tek oy'),
      (403, 'NOT_ELIGIBLE', 'hedef kitlesinde'),
      (400, 'INVALID_TARGET', 'x'), // sunucunun kendi metni taşınır
      (403, 'MODULE_DISABLED', 'kapalı'),
      (403, 'FORBIDDEN_ROLE', 'yetkiniz yok'),
      (403, 'FORBIDDEN_SITE', 'siteye erişim'),
    ]) {
      test('$code -> Türkçe, alt çizgi yok', () async {
        final api = _api((r) async => _json(status, <String, dynamic>{'error': 'x', 'code': code}));
        final e = await _failureOf(() => api.getManaged(token: 't', siteCode: 11, id: 1));
        expect(e.statusCode, status);
        expect(e.code, code);
        expect(e.message, contains(fragment));
        expect(e.message, isNot(contains('_')));
        expect(e.message.length, lessThan(140));
      });
    }

    test('INVALID_BODY sunucu metnini taşır', () async {
      final api = _api((r) async => _json(400, <String, dynamic>{'error': 'Başlık 1-120 karakter olmalı.', 'code': 'INVALID_BODY'}));
      final e = await _failureOf(() => api.getManaged(token: 't', siteCode: 11, id: 1));
      expect(e.message, 'Başlık 1-120 karakter olmalı.');
    });

    test('401 oturum sonu; JSON olmayan 403 ara katman', () async {
      final api = _api((r) async => _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'}));
      final e = await _failureOf(() => api.listMine(token: 't'));
      expect(e, isA<SessionExpiredException>());
      final proxy = _api((r) async => http.Response('<html>denied</html>', 403));
      final p = await _failureOf(() => proxy.listMine(token: 't'));
      expect(p.fromIntermediary, isTrue);
    });

    test('429 Retry-After ipucu', () async {
      final api = _api((r) async => _json(429, <String, dynamic>{'error': 'x', 'code': 'RATE_LIMITED'}, headers: <String, String>{'retry-after': '30'}));
      final e = await _failureOf(() => api.vote(token: 't', id: 1, optionIndex: 0));
      expect(e.retryAfterSeconds, 30);
      expect(e.message, isNot(contains('_')));
    });
  });

  group('SurveyService', () {
    test('oturum yoksa çağrı yapılmaz; 401 oturumu yeniler', () async {
      final auth = _FakeAuth();
      var hits = 0;
      final service = SurveyService(
        authService: auth,
        api: _api((r) async {
          hits++;
          return _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'});
        }),
      );
      await expectLater(service.listMine(), throwsA(isA<SessionExpiredException>()));
      expect(hits, 1);
      await Future<void>.delayed(Duration.zero);
      expect(auth.refreshForced, 1);
      auth.token = null;
      final e = await _failureOf(() => service.listMine());
      expect(e.message, contains('Oturum'));
      expect(hits, 1);
    });
  });
}
