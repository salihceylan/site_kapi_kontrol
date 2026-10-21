// PlatformRulesApi / PlatformRulesService (lib/services/platform_rules_api.dart): sahte HTTP istemcisiyle uçlar, sorgu ve gövde biçimleri, hata
// çevirisi (VALIDATION_FAILED alan metinleri, oturum bitişi, ara sunucu), oturum koruması.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/platform_rule.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/platform_rules_api.dart';

import 'fixtures/platform_rules_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

PlatformRulesApi _api(Future<http.Response> Function(http.Request request) handler) => PlatformRulesApi(
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
      : UserSession(id: 1, fullName: 'Test', email: 't@x.com', loginName: null, role: UserRole.superUser, isActive: true, token: token!);

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

void main() {
  group('uçlar', () {
    test('listAdmin: GET /admin/rules (site yoksa sorgu yok), Bearer belirteç; site_code sorgusu; yanıt ayrışır', () async {
      final seen = <http.Request>[];
      final api = _api((r) async {
        seen.add(r);
        return _json(200, prRulesJson(siteCode: r.url.queryParameters['site_code'] == null ? null : 11, siteName: 'Gül'));
      });
      final platform = await api.listAdmin(token: 'tk');
      expect(seen.last.method, 'GET');
      expect(seen.last.url.toString(), '$_base/admin/rules');
      expect(seen.last.headers['Authorization'], 'Bearer tk');
      expect(platform.items, hasLength(15));
      expect(platform.isSiteScope, isFalse);
      final site = await api.listAdmin(token: 'tk', siteCode: 11);
      expect(seen.last.url.toString(), '$_base/admin/rules?site_code=11');
      expect(site.siteCode, 11);
    });

    test('listForSite: GET /manager/sites/:siteCode/rules', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, prRulesJson(siteCode: 22, siteName: 'Lale', canEdit: false));
      });
      final view = await api.listForSite(token: 'tk', siteCode: 22);
      expect(seen!.url.path, '/manager/sites/22/rules');
      expect(view.canEdit, isFalse);
    });

    test('update: PUT /admin/rules gövdesi (site_code, valid_from, not, changes); yanıt changed taşır', () async {
      http.Request? seen;
      final api = _api((r) async {
        seen = r;
        return _json(200, <String, dynamic>{...prRulesJson(), 'changed': <String>['heat.measured_share_pct', 'heat.area_share_pct']});
      });
      final result = await api.update(
        token: 'tk',
        changes: const <PlatformRuleChange>[
          PlatformRuleChange(key: 'heat.measured_share_pct', value: 60),
          PlatformRuleChange(key: 'heat.area_share_pct', value: 40),
        ],
        validFrom: '2026-11-01',
        note: 'Kurul kararı',
      );
      expect(seen!.method, 'PUT');
      expect(seen!.url.path, '/admin/rules');
      expect(jsonDecode(seen!.body), <String, Object?>{
        'valid_from': '2026-11-01',
        'note': 'Kurul kararı',
        'changes': <Object?>[
          <String, Object?>{'key': 'heat.measured_share_pct', 'value': 60},
          <String, Object?>{'key': 'heat.area_share_pct', 'value': 40},
        ],
      });
      expect(result.changed, <String>['heat.measured_share_pct', 'heat.area_share_pct']);
      await api.update(token: 'tk', siteCode: 9, changes: const <PlatformRuleChange>[PlatformRuleChange.inherit('forecast.default_increase_bp')]);
      expect(jsonDecode(seen!.body), <String, Object?>{
        'site_code': 9,
        'changes': <Object?>[<String, Object?>{'key': 'forecast.default_increase_bp', 'inherit': true}],
      });
    });
  });

  group('hata çevirisi', () {
    test('VALIDATION_FAILED: alan metinleri yükte; ileti ilk kuralın metni (alan adı değil)', () async {
      final api = _api((_) async => _json(400, <String, dynamic>{
        'error': 'Bazı kurallar geçersiz.',
        'code': 'VALIDATION_FAILED',
        'fields': <String, String>{'finance.late_fee.monthly_bp_max': 'Gecikme tazminatı aylık üst sınırı: 0 ile 500 arasında bir tam sayı olmalıdır.'},
        'rule_codes': <String, String>{'finance.late_fee.monthly_bp_max': 'RULE_VALUE_INVALID'},
      }));
      final error = await _failureOf(() => api.update(token: 'tk', changes: const <PlatformRuleChange>[PlatformRuleChange(key: 'finance.late_fee.monthly_bp_max', value: 600)]));
      expect(error.code, 'VALIDATION_FAILED');
      expect(error.message, 'Gecikme tazminatı aylık üst sınırı: 0 ile 500 arasında bir tam sayı olmalıdır.');
      expect(ruleFieldErrors(error), <String, String>{'finance.late_fee.monthly_bp_max': 'Gecikme tazminatı aylık üst sınırı: 0 ile 500 arasında bir tam sayı olmalıdır.'});
      expect(ruleFieldErrors(Exception('x')), isEmpty);
    });

    test('bilinen kodlar Türkçe; 401 oturum bitti; JSON olmayan 403 ara sunucu; 5xx hata kodu iletiye eklenir', () async {
      expect((await _failureOf(() => _api((_) async => _json(403, <String, dynamic>{'error': 'x', 'code': 'FORBIDDEN_SITE'})).listForSite(token: 't', siteCode: 1))).message,
          'Bu sitenin kurallarını görme yetkiniz yok.');
      expect((await _failureOf(() => _api((_) async => _json(404, <String, dynamic>{'error': 'Site bulunamadı.', 'code': 'SITE_NOT_FOUND'})).listAdmin(token: 't', siteCode: 5))).message,
          'Site bulunamadı.');
      final session = await _failureOf(() => _api((_) async => _json(401, <String, dynamic>{'error': 'x'})).listAdmin(token: 't'));
      expect(session, isA<SessionExpiredException>());
      final proxy = await _failureOf(() => _api((_) async => http.Response('<html>engellendi</html>', 403)).listAdmin(token: 't'));
      expect(proxy.fromIntermediary, isTrue);
      final server = await _failureOf(() => _api((_) async => _json(500, <String, dynamic>{'error': 'Kurallar yüklenemedi.', 'errorId': 'e-12'})).listAdmin(token: 't'));
      expect(server.message, contains('e-12'));
      final offline = await _failureOf(() => _api((_) async => throw http.ClientException('bağlantı yok')).listAdmin(token: 't'));
      expect(offline.message, contains('bağlanılamadı'));
    });
  });

  group('servis', () {
    test('oturum belirteci auth servisinden; oturum yoksa istek gitmez; 401 sonrası oturum zorla tazelenir', () async {
      final auth = _FakeAuth();
      var calls = 0;
      final service = PlatformRulesService(
        authService: auth,
        api: _api((r) async {
          calls++;
          expect(r.headers['Authorization'], 'Bearer tok-1');
          return calls == 1 ? _json(200, prRulesJson()) : _json(401, <String, dynamic>{'error': 'x'});
        }),
      );
      expect((await service.listAdmin()).items, hasLength(15));
      await _failureOf(() => service.listForSite(3));
      expect(auth.refreshForced, 1);
      auth.token = null;
      await _failureOf(() => service.listAdmin());
      expect(calls, 2, reason: 'oturum yokken ağ isteği yapılmaz');
    });
  });
}
