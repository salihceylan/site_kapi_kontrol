// ContractApi / ContractService (lib/services/contract_api.dart): sahte HTTP istemcisiyle uç noktalar, sorgu ve gövde
// biçimleri, imleç (YALNIZ opak `cursor`; `before_id` gönderilmez) ve hata çevirisi (INVALID_FIELD {field}, VENDOR_NAME_TAKEN,
// VENDOR_INACTIVE, LIMIT_REACHED, MODULE_DISABLED, FORBIDDEN_ROLE, 401, ara katman 403).
//
// Kurallar: yazma istekleri ASLA otomatik yeniden denenmez; 401 oturum sonudur; JSON olmayan 401/403 ara katman
// hatasıdır; firma / sözleşme metinleri günlüğe yazılmaz.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';

import 'screens/contract_fixtures.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body, {Map<String, String>? headers}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...?headers},
);

ContractApi _api(Future<http.Response> Function(http.Request request) handler) => ContractApi(
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
  group('firma uçları', () {
    test('liste: GET .../contract-vendors?active=all; arama kırpılır; Bearer', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[ctVendor(1), ctVendor(2, name: 'Kale')],
        });
      });
      final items = await api.listVendors(token: 'tok-1', siteCode: 11, query: '  kale ');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/manager/sites/11/contract-vendors');
      expect(seen.url.queryParameters, <String, String>{'active': 'all', 'q': 'kale'});
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(items.map((v) => v.id), <int>[1, 2]);

      await api.listVendors(token: 'tok-1', siteCode: 11, active: ContractVendorFilter.passive);
      expect(seen.url.queryParameters, <String, String>{'active': '0'});
    });

    test('ekle: POST 201 {vendor}; güncelle: PATCH {is_active}', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        if (request.method == 'POST') {
          return _json(201, <String, dynamic>{'vendor': ctVendor(7, name: 'Mavi Havuz', category: 'havuz')});
        }
        return _json(200, <String, dynamic>{'vendor': ctVendor(7, active: false)});
      });
      final created = await api.createVendor(
        token: 'tok-1',
        siteCode: 11,
        draft: const ContractVendorDraft(name: 'Mavi Havuz', category: ContractCategory.havuz),
      );
      expect(created.id, 7);
      expect(seen.last.url.path, '/manager/sites/11/contract-vendors');
      expect(jsonDecode(seen.last.body), <String, dynamic>{'name': 'Mavi Havuz', 'category': 'havuz'});
      expect(seen.last.headers['Content-Type'], startsWith('application/json'));

      final service = ContractService(authService: _FakeAuth(), api: api);
      final passive = await service.setVendorActive(11, 7, false);
      expect(passive.isActive, isFalse);
      expect(seen.last.method, 'PATCH');
      expect(seen.last.url.path, '/manager/sites/11/contract-vendors/7');
      expect(jsonDecode(seen.last.body), <String, dynamic>{'is_active': false});
    });
  });

  group('sözleşme uçları', () {
    test('liste: varsayılan state=all, limit; süzgeçler; imleç yalnız `cursor`', () async {
      final seen = <http.Request>[];
      var body = <String, dynamic>{
        'items': <Object>[ctContract(11)],
        'next_cursor': 'WyIyMDI2LTEyLTMxIiwxMV0',
      };
      final api = _api((request) async {
        seen.add(request);
        return _json(200, body);
      });
      final first = await api.listContracts(token: 'tok-1', siteCode: 11);
      expect(seen.last.url.path, '/manager/sites/11/contracts');
      expect(seen.last.url.queryParameters, <String, String>{'state': 'all', 'limit': '30'});
      expect(first.nextCursor, 'WyIyMDI2LTEyLTMxIiwxMV0');

      await api.listContracts(
        token: 'tok-1',
        siteCode: 11,
        state: 'yaklasiyor',
        vendorId: 3,
        category: 'asansor',
        query: ' bakım ',
        cursor: first.nextCursor,
        limit: 30,
      );
      expect(seen.last.url.queryParameters, <String, String>{
        'state': 'yaklasiyor',
        'vendor_id': '3',
        'category': 'asansor',
        'q': 'bakım',
        'cursor': 'WyIyMDI2LTEyLTMxIiwxMV0',
        'limit': '30',
      });

      // Sunucu `before_id` kabul etmez: `next_before_id` gelse bile imleç sayılmaz ve hiçbir istekte gönderilmez.
      body = <String, dynamic>{'items': <Object>[ctContract(12)], 'next_cursor': null, 'next_before_id': 12};
      final last = await api.listContracts(token: 'tok-1', siteCode: 11);
      expect(last.nextCursor, isNull);
      for (final request in seen) {
        expect(request.url.queryParameters.containsKey('before_id'), isFalse);
      }
    });

    test('özet, ayrıntı, ekle (201 {contract}), güncelle, fesih / yeniden etkinleştirme', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        final path = request.url.path;
        if (path.endsWith('/summary')) {
          return _json(200, <String, dynamic>{'active': 2, 'expiring_soon': 1, 'expired': 1, 'terminated': 1});
        }
        if (request.method == 'POST') return _json(201, <String, dynamic>{'contract': ctContract(101)});
        if (request.method == 'PATCH') {
          return _json(200, <String, dynamic>{'contract': ctContract(11, status: 'feshedildi')});
        }
        return _json(200, <String, dynamic>{'contract': ctContract(11)});
      });
      final summary = await api.summary(token: 'tok-1', siteCode: 11);
      expect(seen.last.url.path, '/manager/sites/11/contracts/summary');
      expect(summary.expiringSoon, 1);

      final one = await api.getContract(token: 'tok-1', siteCode: 11, id: 11);
      expect(seen.last.url.path, '/manager/sites/11/contracts/11');
      expect(one.id, 11);

      final created = await api.createContract(
        token: 'tok-1',
        siteCode: 11,
        draft: ContractDraft(
          vendorId: 1,
          title: 'Bakım',
          category: ContractCategory.asansor,
          startDate: DateTime(2026, 11, 1),
          endDate: DateTime(2027, 10, 31),
          noticeDays: 30,
          remindBeforeDays: 15,
          amountMinor: 125050,
          period: ContractPeriod.aylik,
          autoRenew: true,
        ),
      );
      expect(created.id, 101);
      expect(jsonDecode(seen.last.body), <String, dynamic>{
        'vendor_id': 1,
        'title': 'Bakım',
        'category': 'asansor',
        'start_date': '2026-11-01',
        'end_date': '2027-10-31',
        'notice_days': 30,
        'remind_before_days': 15,
        'amount': '1250.50',
        'period': 'aylik',
        'auto_renew': true,
      });

      final service = ContractService(authService: _FakeAuth(), api: api);
      final terminated = await service.setContractStatus(11, 11, ContractStatus.feshedildi);
      expect(seen.last.method, 'PATCH');
      expect(seen.last.url.path, '/manager/sites/11/contracts/11');
      expect(jsonDecode(seen.last.body), <String, dynamic>{'status': 'feshedildi'});
      expect(terminated.state, ContractState.feshedildi);
      await service.setContractStatus(11, 11, ContractStatus.aktif);
      expect(jsonDecode(seen.last.body), <String, dynamic>{'status': 'aktif'});
    });

    test('başarılı ama bozuk gövde: okunamadı / beklenen biçimde değil', () async {
      final bad = _api((request) async => http.Response('<html>', 200));
      expect(
        (await _failureOf(() => bad.listVendors(token: 't', siteCode: 1))).message,
        'Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.',
      );
      final noId = _api((request) async => _json(201, <String, dynamic>{'contract': <String, dynamic>{}}));
      final error = await _failureOf(
        () => noId.createContract(
          token: 't',
          siteCode: 1,
          draft: ContractDraft(
            vendorId: 1,
            title: 'x',
            category: ContractCategory.diger,
            startDate: DateTime(2026),
            noticeDays: 0,
            remindBeforeDays: 0,
          ),
        ),
      );
      expect(error.message, 'Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin.');
    });
  });

  group('hata çevirisi', () {
    Future<ApiException> failWith(int status, Object? body, {Map<String, String>? headers}) {
      final api = _api((request) async => _json(status, body, headers: headers));
      return _failureOf(() => api.listContracts(token: 't', siteCode: 11));
    }

    test('400 INVALID_FIELD: sunucu metni önceliklidir; metin yoksa alan etiketi; alan payload\'da', () async {
      final withText = await failWith(400, <String, dynamic>{
        'error': 'Bitiş tarihi başlangıç tarihinden önce olamaz.',
        'code': 'INVALID_FIELD',
        'field': 'end_date',
      });
      expect(withText.message, 'Bitiş tarihi başlangıç tarihinden önce olamaz.');
      expect(withText.code, 'INVALID_FIELD');
      expect(withText.payload?['field'], 'end_date');

      final noText = await failWith(400, <String, dynamic>{'code': 'INVALID_FIELD', 'field': 'notice_days'});
      expect(noText.message, '"Fesih bildirim süresi" alanı geçersiz. Kontrol edip tekrar deneyin.');
      final cursor = await failWith(400, <String, dynamic>{
        'error': 'Sayfa imleci geçersiz.',
        'code': 'INVALID_FIELD',
        'field': 'cursor',
      });
      expect(cursor.message, 'Sayfa bilgisi geçersiz. Listeyi yenileyip tekrar deneyin.');
      final state = await failWith(400, <String, dynamic>{'code': 'INVALID_FIELD', 'field': 'state'});
      expect(state.message, 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.');
      final unknown = await failWith(400, <String, dynamic>{'code': 'INVALID_FIELD', 'field': 'xyz'});
      expect(unknown.message, 'Girilen bilgilerden biri geçersiz. Alanları kontrol edip tekrar deneyin.');
    });

    test('409 kodları ve 403 modül / rol / site', () async {
      expect(
        (await failWith(409, <String, dynamic>{'code': 'VENDOR_NAME_TAKEN', 'error': 'x'})).message,
        'Bu adla kayıtlı bir firma zaten var. Farklı bir ad girin ya da mevcut firmayı kullanın.',
      );
      expect(
        (await failWith(409, <String, dynamic>{'code': 'VENDOR_INACTIVE'})).message,
        'Seçilen firma pasif. Başka bir firma seçin ya da firmayı Firmalar sekmesinden etkinleştirin.',
      );
      final limit = await failWith(409, <String, dynamic>{
        'code': 'LIMIT_REACHED',
        'error': 'Bir sitede en fazla 500 firma kaydedilebilir.',
        'limit': 500,
      });
      expect(limit.message, 'Bir sitede en fazla 500 firma kaydedilebilir.');
      expect(
        (await failWith(409, <String, dynamic>{'code': 'LIMIT_REACHED'})).message,
        'Bu site için kayıt sınırına ulaşıldı.',
      );
      final off = await failWith(403, <String, dynamic>{'code': 'MODULE_DISABLED', 'module': 'contracts'});
      expect(off.code, 'MODULE_DISABLED');
      expect(off.message, 'Firma ve sözleşme takibi bu site için kapalı.');
      expect(
        (await failWith(403, <String, dynamic>{'code': 'FORBIDDEN_ROLE'})).message,
        startsWith('Bu işlem için yetkiniz yok.'),
      );
      expect(
        (await failWith(404, <String, dynamic>{'code': 'CONTRACT_NOT_FOUND'})).message,
        'Sözleşme bulunamadı ya da erişiminiz yok. Listeyi yenileyin.',
      );
      expect(
        (await failWith(404, <String, dynamic>{'code': 'VENDOR_NOT_FOUND'})).message,
        'Firma bulunamadı ya da erişiminiz yok. Listeyi yenileyin.',
      );
    });

    test('401 oturum sonu; JSON olmayan 403 ara katman; 500 hata kodu; 429 bekleme', () async {
      final expired = await failWith(401, <String, dynamic>{'code': 'TOKEN_EXPIRED'});
      expect(expired, isA<SessionExpiredException>());
      expect(expired.invalidatesSession, isTrue);

      final proxy = _api((request) async => http.Response('<html>blocked</html>', 403));
      final blocked = await _failureOf(() => proxy.summary(token: 't', siteCode: 11));
      expect(blocked.fromIntermediary, isTrue);
      expect(blocked.isForbidden, isFalse);

      final server = await failWith(500, <String, dynamic>{'error': 'Sözleşmeler yüklenemedi.', 'errorId': 'abc123'});
      expect(server.message, contains('(Hata kodu: abc123)'));

      final limited = await failWith(429, <String, dynamic>{'code': 'RATE_LIMITED'}, headers: <String, String>{'retry-after': '30'});
      expect(limited.retryAfterSeconds, 30);
      expect(limited.isRateLimited, isTrue);
    });
  });

  group('ContractService', () {
    test('oturum yoksa istek atılmaz; 401 oturumu tazeler', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        return _json(401, <String, dynamic>{'code': 'TOKEN_EXPIRED'});
      });
      final auth = _FakeAuth();
      final service = ContractService(authService: auth, api: api);
      await expectLater(service.summary(11), throwsA(isA<SessionExpiredException>()));
      expect(auth.refreshForced, 1);
      auth.token = null;
      await expectLater(service.listVendors(11), throwsA(isA<ApiException>()));
      expect(calls, 1);
    });

    test('mutasyon hatası yeniden denenmez (tek istek)', () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        return _json(503, <String, dynamic>{'error': 'Geçici hata'});
      });
      final service = ContractService(authService: _FakeAuth(), api: api);
      await expectLater(
        service.updateContract(11, 1, <String, dynamic>{'title': 'x'}),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    });
  });
}
