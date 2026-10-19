// ReservationApi / ReservationService (lib/services/reservation_api.dart): sahte HTTP istemcisiyle uç noktalar, gövde
// biçimleri, hata çevirisi (docs/PLATFORM_REZERVASYON.md "Hata kodları") ve idempotency anahtarı yönetimi.
//
// Kurallar: yazma istekleri ASLA otomatik yeniden denenmez; 401 oturum sonudur; JSON olmayan 401/403 ara katman
// hatasıdır; yeniden gönderimde (aynı veri) AYNI idempotency_key kullanılır, veri değişince, başarıdan sonra ve sunucu
// anahtarı reddedince (IDEMPOTENCY_CONFLICT) YENİ anahtar üretilir.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';

import 'screens/reservation_fixtures.dart';

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

ReservationApi _api(Future<http.Response> Function(http.Request request) handler) {
  return ReservationApi(
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
          role: UserRole.apartmentOwner,
          isActive: true,
          token: token!,
        );

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

const ReservationCreateRequest _request = ReservationCreateRequest(
  siteCode: 11,
  areaId: 3,
  date: '2026-10-20',
  start: '18:00',
  slots: 2,
  note: 'Doğum günü',
);

const ConciergeCreateRequest _conciergeRequest = ConciergeCreateRequest(
  siteCode: 11,
  category: ConciergeCategory.paketTeslim,
  note: 'Kargo',
);

void main() {
  group('sakin uçları', () {
    test('alanlar: GET, Bearer, site_code yalnız verilince; yalnız geçerli kayıtlar', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[rzArea(1), <String, dynamic>{'name': 'kimliksiz'}],
        });
      });
      final areas = await api.listAreas(token: 'tok-1', siteCode: 11);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/app/reservation-areas');
      expect(seen.url.queryParameters, <String, String>{'site_code': '11'});
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(areas.map((a) => a.id), <int>[1]);
      await api.listAreas(token: 'tok-1');
      expect(seen.url.queryParameters, isEmpty);
    });

    test('boş saatler: yol ve from / to yalnız verilince', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'area': rzArea(3),
          'days': rzDefaultDays(),
          'bookable_until': '2026-11-03',
        });
      });
      final result = await api.availability(token: 't', areaId: 3, from: '2026-10-25');
      expect(seen.url.path, '/app/reservation-areas/3/availability');
      expect(seen.url.queryParameters, <String, String>{'from': '2026-10-25'});
      expect(result.days.length, 3);
      expect(result.bookableUntil, '2026-11-03');
      await api.availability(token: 't', areaId: 3);
      expect(seen.url.queryParameters, isEmpty);
    });

    test('rezervasyon: POST gövdesi idempotency_key taşır; 201 kabul; replayed okunur', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(201, <String, dynamic>{'reservation': rzReservation(12), 'replayed': true});
      });
      final result = await api.createReservation(
        token: 'tok-1',
        request: _request,
        idempotencyKey: 'rz-0123456789abcdef',
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/app/reservations');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['idempotency_key'], 'rz-0123456789abcdef');
      expect(body['site_code'], 11);
      expect(body['area_id'], 3);
      expect(body['date'], '2026-10-20');
      expect(body['start'], '18:00');
      expect(body['slots'], 2);
      expect(body.containsKey('apartment_id'), isFalse);
      expect(result.replayed, isTrue);
      expect(result.reservation.id, 12);
    });

    test('rezervasyon listesi, ayrıntı ve iptal uçları', () async {
      final seen = <String>[];
      late Map<String, String> query;
      final api = _api((request) async {
        seen.add('${request.method} ${request.url.path}');
        query = request.url.queryParameters;
        if (request.url.path == '/app/reservations') {
          return _json(200, <String, dynamic>{
            'items': <Object>[rzReservation(9)],
            'next_before_id': 9,
          });
        }
        if (request.url.path.endsWith('/cancel')) {
          return _json(200, <String, dynamic>{'reservation': rzReservation(5, status: 'iptal')});
        }
        return _json(200, <String, dynamic>{'reservation': rzReservation(5)});
      });
      final page = await api.listMine(token: 't', siteCode: 11, scope: 'upcoming', limit: 30, beforeId: 40);
      expect(query, <String, String>{'site_code': '11', 'scope': 'upcoming', 'limit': '30', 'before_id': '40'});
      expect(page.nextBeforeId, 9);
      expect((await api.getMine(token: 't', id: 5)).id, 5);
      expect((await api.cancelMine(token: 't', id: 5)).status, ReservationStatus.iptal);
      expect(seen, <String>['GET /app/reservations', 'GET /app/reservations/5', 'POST /app/reservations/5/cancel']);
    });

    test('konsiyerj: liste, açma (201), iptal', () async {
      final seen = <String>[];
      Map<String, dynamic>? body;
      final api = _api((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.method == 'POST' && request.url.path == '/app/concierge-requests') {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(201, <String, dynamic>{'request': rzRequest(8), 'replayed': false});
        }
        if (request.url.path.endsWith('/cancel')) {
          return _json(200, <String, dynamic>{'request': rzRequest(8, status: 'iptal')});
        }
        expect(request.url.queryParameters['status'], 'open');
        return _json(200, <String, dynamic>{'items': <Object>[rzRequest(8)], 'next_before_id': null});
      });
      final page = await api.listMyRequests(token: 't', status: 'open');
      expect(page.items.single.id, 8);
      final created = await api.createRequest(token: 't', request: _conciergeRequest, idempotencyKey: 'rz-aaaaaaaa11111111');
      expect(created.request.id, 8);
      expect(body, <String, dynamic>{
        'site_code': 11,
        'category': 'paket_teslim',
        'note': 'Kargo',
        'idempotency_key': 'rz-aaaaaaaa11111111',
      });
      expect((await api.cancelMyRequest(token: 't', id: 8)).status, ConciergeStatus.iptal);
      expect(seen, <String>[
        'GET /app/concierge-requests',
        'POST /app/concierge-requests',
        'POST /app/concierge-requests/8/cancel',
      ]);
    });

    test('okunmamış: listeler unread + unread_count okur; ayrıntılar unread taşır; görüldü uçları boş gövdeyle POST', () async {
      final seen = <String>[];
      final bodies = <String>[];
      final api = _api((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') bodies.add(request.body);
        if (request.url.path.endsWith('/seen')) {
          return _json(200, <String, dynamic>{'id': 5, 'unread': false});
        }
        if (request.url.path == '/app/reservations') {
          return _json(200, <String, dynamic>{'items': <Object>[rzReservation(5, unread: true)], 'next_before_id': null, 'unread_count': 2});
        }
        if (request.url.path == '/app/concierge-requests') {
          return _json(200, <String, dynamic>{'items': <Object>[rzRequest(8, unread: true)], 'next_before_id': null, 'unread_count': 1});
        }
        if (request.url.path == '/app/concierge-requests/8') {
          return _json(200, <String, dynamic>{'request': rzRequest(8, unread: true)});
        }
        return _json(200, <String, dynamic>{'reservation': rzReservation(5, unread: true)});
      });
      final page = await api.listMine(token: 't');
      expect(page.items.single.unread, isTrue);
      expect(page.unreadCount, 2);
      final requests = await api.listMyRequests(token: 't');
      expect(requests.items.single.unread, isTrue);
      expect(requests.unreadCount, 1);
      expect((await api.getMine(token: 't', id: 5)).unread, isTrue);
      expect((await api.getMyRequest(token: 't', id: 8)).unread, isTrue);
      await api.markMineSeen(token: 't', id: 5);
      await api.markMyRequestSeen(token: 't', id: 8);
      expect(seen, <String>[
        'GET /app/reservations',
        'GET /app/concierge-requests',
        'GET /app/reservations/5',
        'GET /app/concierge-requests/8',
        'POST /app/reservations/5/seen',
        'POST /app/concierge-requests/8/seen',
      ]);
      expect(bodies, <String>['{}', '{}']);
    });

    test('eski sunucu: unread / unread_count yoksa false / 0 (çökmez)', () async {
      final api = _api(
        (request) async => _json(200, <String, dynamic>{
          'items': <Object>[rzReservation(5)..remove('unread')],
          'next_before_id': null,
        }),
      );
      final page = await api.listMine(token: 't');
      expect(page.items.single.unread, isFalse);
      expect(page.unreadCount, 0);
    });
  });

  group('yönetim uçları', () {
    test('alanlar: liste (pasifler dahil), ekleme (201) ve PATCH yalnız verilen alanları gönderir', () async {
      final calls = <String>[];
      Map<String, dynamic>? lastBody;
      final api = _api((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return _json(200, <String, dynamic>{'items': <Object>[rzArea(1), rzArea(2, active: false)], 'active_count': 1});
        }
        lastBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(request.method == 'POST' ? 201 : 200, <String, dynamic>{'area': rzArea(9, name: 'Yeni')});
      });
      final list = await api.listManagedAreas(token: 't', siteCode: 11);
      expect(list.items.length, 2);
      expect(list.activeCount, 1);
      final created = await api.createArea(
        token: 't',
        siteCode: 11,
        fields: <String, Object?>{'name': 'Yeni', 'description': null, 'capacity': 2},
      );
      expect(created.name, 'Yeni');
      expect(lastBody, <String, dynamic>{'name': 'Yeni', 'description': null, 'capacity': 2});
      await api.updateArea(token: 't', siteCode: 11, id: 9, fields: <String, Object?>{'is_active': false});
      expect(lastBody, <String, dynamic>{'is_active': false});
      expect(calls, <String>[
        'GET /manager/sites/11/reservation-areas',
        'POST /manager/sites/11/reservation-areas',
        'PATCH /manager/sites/11/reservation-areas/9',
      ]);
    });

    test('takvim: süzgeç parametreleri; boş süzgeç gönderilmez; opak imleç olduğu gibi; sayaç', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'items': <Object>[rzReservation(3)],
          'next_cursor': 'MTcyOTQ0.3',
          'pending_count': 2,
        });
      });
      final page = await api.listManaged(
        token: 'tok-1',
        siteCode: 11,
        areaId: 3,
        status: 'beklemede,onaylandi',
        from: '2026-10-20',
        to: '2026-10-27',
        cursor: 'abc.1',
      );
      expect(seen.url.path, '/manager/sites/11/reservations');
      expect(seen.url.queryParameters, <String, String>{
        'area_id': '3',
        'status': 'beklemede,onaylandi',
        'from': '2026-10-20',
        'to': '2026-10-27',
        'cursor': 'abc.1',
        'limit': '30',
      });
      expect(page.nextCursor, 'MTcyOTQ0.3');
      expect(page.pendingCount, 2);
      await api.listManaged(token: 'tok-1', siteCode: 11, status: '', cursor: '');
      expect(seen.url.queryParameters, <String, String>{'limit': '30'});
    });

    test('karar: action + not; boş not gönderilmez; changed okunur', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'reservation': rzReservation(3, status: 'reddedildi'), 'changed': false});
      });
      final result = await api.decide(token: 't', siteCode: 11, id: 3, action: 'reject', note: '  Uygun değil.  ');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/manager/sites/11/reservations/3/decision');
      expect(jsonDecode(seen.body), <String, dynamic>{'action': 'reject', 'note': 'Uygun değil.'});
      expect(result.changed, isFalse);
      await api.decide(token: 't', siteCode: 11, id: 3, action: 'approve');
      expect(jsonDecode(seen.body), <String, dynamic>{'action': 'approve'});
    });

    test('konsiyerj yönetimi: liste süzgeci, ayrıntı, PATCH (not null = sil)', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        if (request.method == 'PATCH') {
          return _json(200, <String, dynamic>{'request': rzRequest(4, status: 'hazirlaniyor'), 'next_statuses': <Object>['tamamlandi'], 'changed': true});
        }
        if (request.url.path.endsWith('/4')) {
          return _json(200, <String, dynamic>{'request': rzRequest(4), 'next_statuses': <Object>['hazirlaniyor']});
        }
        return _json(200, <String, dynamic>{'items': <Object>[rzRequest(4)], 'next_before_id': 4, 'counts': <String, dynamic>{'yeni': 1}});
      });
      final page = await api.listManagedRequests(token: 't', siteCode: 11, status: 'open', category: 'temizlik', beforeId: 50);
      expect(seen.url.path, '/manager/sites/11/concierge-requests');
      expect(seen.url.queryParameters, <String, String>{'status': 'open', 'category': 'temizlik', 'limit': '30', 'before_id': '50'});
      expect(page.counts[ConciergeStatus.yeni], 1);
      final detail = await api.getManagedRequest(token: 't', siteCode: 11, id: 4);
      expect(detail.nextStatuses, <ConciergeStatus>[ConciergeStatus.hazirlaniyor]);
      final updated = await api.updateManagedRequest(
        token: 't',
        siteCode: 11,
        id: 4,
        fields: <String, Object?>{'status': 'hazirlaniyor', 'note': null},
      );
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/manager/sites/11/concierge-requests/4');
      expect(jsonDecode(seen.body), <String, dynamic>{'status': 'hazirlaniyor', 'note': null});
      expect(updated.changed, isTrue);
      expect(updated.request.status, ConciergeStatus.hazirlaniyor);
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

    Future<String> messageOf(int status, String code, [Map<String, dynamic>? extra]) async =>
        (await fail(status, <String, dynamic>{'error': 'x', 'code': code, ...?extra})).message;

    test('403 kodları', () async {
      final off = await fail(403, <String, dynamic>{'error': 'x', 'code': 'MODULE_DISABLED', 'module': 'reservation'});
      expect(off.message, 'Rezervasyon ve Konsiyerj bu site için kapalı.');
      expect(off.code, 'MODULE_DISABLED');
      expect(await messageOf(403, 'FORBIDDEN_ROLE'), 'Bu işlem için yetkiniz yok.');
      expect(await messageOf(403, 'FORBIDDEN_SITE'), 'Bu siteye erişim yetkiniz yok.');
      expect(await messageOf(403, 'NOT_A_RESIDENT'), contains('daire sakini'));
    });

    test('404 kodları', () async {
      expect(await messageOf(404, 'AREA_NOT_FOUND'), contains('Alan bulunamadı'));
      expect(await messageOf(404, 'RESERVATION_NOT_FOUND'), contains('Rezervasyon bulunamadı'));
      expect(await messageOf(404, 'CONCIERGE_NOT_FOUND'), contains('Talep bulunamadı'));
      expect((await fail(404, <String, dynamic>{'error': 'x', 'code': 'SITE_NOT_FOUND'})).statusCode, 404);
    });

    test('409 kodları sınırları gövdeden okur', () async {
      expect(await messageOf(409, 'CANCEL_WINDOW_CLOSED', <String, dynamic>{'cancel_cutoff_hours': 2}), contains('2 saatten az'));
      expect(await messageOf(409, 'CANCEL_WINDOW_CLOSED'), contains('İptal süresi doldu'));
      expect(await messageOf(409, 'INVALID_SLOT_COUNT', <String, dynamic>{'min_slots': 1, 'max_slots': 4}), contains('en az 1, en çok 4'));
      expect(await messageOf(409, 'OUTSIDE_BOOKING_WINDOW', <String, dynamic>{'max_days_ahead': 14}), contains('14 gün'));
      expect(await messageOf(409, 'RESERVATION_DAILY_LIMIT', <String, dynamic>{'daily_limit': 2}), contains('en çok 2 rezervasyon'));
      expect(await messageOf(409, 'RESERVATION_WEEKLY_LIMIT', <String, dynamic>{'weekly_limit': 5}), contains('en çok 5 rezervasyon'));
      expect(await messageOf(409, 'RESERVATION_USER_LIMIT', <String, dynamic>{'active_limit': 30}), contains('en çok 30 geçerli'));
      expect(await messageOf(409, 'CONCIERGE_USER_LIMIT', <String, dynamic>{'user_open_limit': 10}), contains('en çok 10 açık talebiniz'));
      expect(await messageOf(409, 'AREA_LIMIT', <String, dynamic>{'area_limit': 50}), contains('en çok 50 alan'));
      expect(await messageOf(409, 'SLOT_FULL'), contains('bu arada doldu'));
      expect(await messageOf(409, 'ALREADY_BOOKED'), contains('zaten rezervasyonunuz var'));
      expect(await messageOf(409, 'AREA_NAME_TAKEN'), contains('aynı adlı bir alan'));
      expect(await messageOf(409, 'AREA_INACTIVE'), contains('rezervasyona kapalı'));
      expect(await messageOf(409, 'OUTSIDE_OPEN_HOURS'), contains('açık saatlerine uymuyor'));
      expect(await messageOf(409, 'RESERVATION_PAST'), contains('geçmiş rezervasyon onaylanamaz'));
      expect(await messageOf(409, 'INVALID_TRANSITION', <String, dynamic>{'from': 'iptal', 'to': 'onaylandi'}), contains('Başka biri'));
      expect(await messageOf(409, 'CONCIERGE_CLOSED'), contains('Tamamlanmış ya da iptal edilmiş'));
      expect(await messageOf(409, 'IDEMPOTENCY_CONFLICT'), contains('başka bilgilerle'));
      expect(await messageOf(409, 'RESERVATION_SITE_LIMIT'), contains('Yönetimle iletişime geçin'));
      expect(await messageOf(409, 'CONCIERGE_SITE_LIMIT'), contains('Yönetimle iletişime geçin'));
    });

    test('429 saatlik sınırlar: Retry-After saniyesi ve süre metni', () async {
      final e = await fail(
        429,
        <String, dynamic>{'error': 'x', 'code': 'RESERVATION_RATE_LIMITED', 'retry_after_seconds': 3600},
        headers: <String, String>{'retry-after': '3600'},
      );
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 3600);
      expect(e.message, contains('1 saat'));
      final concierge = await fail(429, <String, dynamic>{'error': 'x', 'code': 'CONCIERGE_RATE_LIMITED', 'retry_after_seconds': 1800});
      expect(concierge.message, contains('30 dakika'));
      final generic = await fail(429, <String, dynamic>{'error': 'Çok fazla istek.'}, headers: <String, String>{'retry-after': '90'});
      expect(generic.retryAfterSeconds, 90);
      expect(generic.message, contains('2 dakika'));
    });

    test('400: sunucunun alan etiketli Türkçe metni korunur; jargon gizlenir', () async {
      final field = await fail(400, <String, dynamic>{'error': 'Alan adı en fazla 80 karakter olabilir.', 'code': 'INVALID_BODY'});
      expect(field.message, 'Alan adı en fazla 80 karakter olabilir.');
      final jargon = await fail(400, <String, dynamic>{'error': 'idempotency_key geçersiz', 'code': 'INVALID_BODY'});
      expect(jargon.message, isNot(contains('idempotency_key')));
      final location = await fail(400, <String, dynamic>{'error': 'Daire bu kişiye ait değil.', 'code': 'INVALID_LOCATION'});
      expect(location.message, 'Daire bu kişiye ait değil.');
      expect(await messageOf(400, 'INVALID_QUERY'), contains('Süzgeç geçersiz'));
    });

    test('401 oturum sonu; JSON olmayan 401/403 ara katman; JSON olmayan 413; 5xx', () async {
      expect(await fail(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'}), isA<SessionExpiredException>());
      final deleted = await fail(401, <String, dynamic>{'error': 'x', 'code': 'ACCOUNT_DELETED'});
      expect(deleted.message, 'Bu hesap silinmiş.');
      final proxy = await fail(403, null, raw: '<html>blocked</html>', headers: <String, String>{'content-type': 'text/html'});
      expect(proxy.fromIntermediary, isTrue);
      expect(proxy.invalidatesSession, isFalse);
      final big = await fail(413, null, raw: '');
      expect(big.code, 'BODY_TOO_LARGE');
      final server = await fail(502, null, raw: 'bad gateway');
      expect(server.message, contains('502'));
      final withId = await fail(500, <String, dynamic>{'error': 'Sunucu hatası.', 'errorId': 'E-42'});
      expect(withId.message, contains('E-42'));
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
        () => api.createReservation(token: 't', request: _request, idempotencyKey: 'rz-0123456789abcdef'),
      );
      expect(calls, 1);
      expect(e.message, contains('Sunucuya bağlanılamadı'));
    });

    test('2xx ama beklenmeyen gövde: anlaşılır hata', () async {
      final api = _api((request) async => _json(200, <String, dynamic>{'reservation': <String, dynamic>{}}));
      final e = await _failureOf(() => api.getMine(token: 't', id: 1));
      expect(e.message, contains('beklenen biçimde değil'));
    });
  });

  group('ReservationService', () {
    test('oturum yoksa ağa çıkmaz; 401 merkezi doğrulamayı tetikler', () async {
      var calls = 0;
      final auth = _FakeAuth()..token = null;
      final service = ReservationService(
        authService: auth,
        api: _api((request) async {
          calls++;
          return _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'});
        }),
      );
      final none = await _failureOf(() => service.listAreas());
      expect(none.message, 'Oturum açmanız gerekmektedir.');
      expect(calls, 0);
      auth.token = 'tok-1';
      final expired = await _failureOf(() => service.listAreas());
      expect(expired, isA<SessionExpiredException>());
      expect(auth.refreshForced, 1);
    });

    test('rezervasyon anahtarı: hata sonrası aynı veri AYNI; başarıdan sonra ve veri değişince YENİ', () async {
      final keys = <String>[];
      var fail = true;
      final service = ReservationService(
        authService: _FakeAuth(),
        api: _api((request) async {
          keys.add((jsonDecode(request.body) as Map<String, dynamic>)['idempotency_key'] as String);
          if (fail) return _json(503, <String, dynamic>{'error': 'Geçici hata.'});
          return _json(201, <String, dynamic>{'reservation': rzReservation(12), 'replayed': false});
        }),
      );
      await _failureOf(() => service.createReservation(_request));
      await _failureOf(() => service.createReservation(_request));
      expect(keys[0], keys[1], reason: 'yanıtı kaybolan istek aynı anahtarla yinelenir');
      expect(keys[0], matches(RegExp(r'^[A-Za-z0-9_.:-]{8,64}$')));
      expect(keys[0], startsWith('rz-'));

      // Veri değişince yeni anahtar; ilk veriye dönülünce ilk anahtar (A -> B -> A çift kayıt yaratmaz).
      const changed = ReservationCreateRequest(siteCode: 11, areaId: 3, date: '2026-10-20', start: '19:00', slots: 2, note: 'Doğum günü');
      await _failureOf(() => service.createReservation(changed));
      expect(keys[2], isNot(keys[0]));
      await _failureOf(() => service.createReservation(_request));
      expect(keys[3], keys[0]);

      // Başarı: anahtar atılır; aynı veriyle SONRAKİ rezervasyon yeni anahtar alır.
      fail = false;
      await service.createReservation(_request);
      expect(keys[4], keys[0]);
      await service.createReservation(_request);
      expect(keys[5], isNot(keys[0]));
    });

    test('IDEMPOTENCY_CONFLICT: anahtar atılır, sonraki deneme yeni anahtarla gider', () async {
      final keys = <String>[];
      var conflict = true;
      final service = ReservationService(
        authService: _FakeAuth(),
        api: _api((request) async {
          keys.add((jsonDecode(request.body) as Map<String, dynamic>)['idempotency_key'] as String);
          if (conflict) {
            return _json(409, <String, dynamic>{'error': 'x', 'code': 'IDEMPOTENCY_CONFLICT'});
          }
          return _json(201, <String, dynamic>{'reservation': rzReservation(12), 'replayed': false});
        }),
      );
      final e = await _failureOf(() => service.createReservation(_request));
      expect(e.code, 'IDEMPOTENCY_CONFLICT');
      conflict = false;
      await service.createReservation(_request);
      expect(keys[1], isNot(keys[0]));
    });

    test('konsiyerj anahtarı: hata sonrası aynı; başarıdan sonra yeni; rezervasyon anahtarlarından bağımsız', () async {
      final keys = <String>[];
      var fail = true;
      final service = ReservationService(
        authService: _FakeAuth(),
        api: _api((request) async {
          keys.add((jsonDecode(request.body) as Map<String, dynamic>)['idempotency_key'] as String);
          if (fail) return _json(500, <String, dynamic>{'error': 'x'});
          return _json(201, <String, dynamic>{'request': rzRequest(8), 'replayed': false});
        }),
      );
      await _failureOf(() => service.createRequest(_conciergeRequest));
      await _failureOf(() => service.createRequest(_conciergeRequest));
      await _failureOf(() => service.createReservation(_request));
      expect(keys[0], keys[1]);
      expect(keys[2], isNot(keys[0]));
      fail = false;
      await service.createRequest(_conciergeRequest);
      await service.createRequest(_conciergeRequest);
      expect(keys[3], keys[0]);
      expect(keys[4], isNot(keys[0]));
    });

    test('unreadCounts: iki hafif liste isteği (limit 1, tüm kapsam / durum, site_code yalnız verilince); yalnız sayaçlar okunur', () async {
      final queries = <String, Map<String, String>>{};
      final service = ReservationService(
        authService: _FakeAuth(),
        api: _api((request) async {
          queries[request.url.path] = request.url.queryParameters;
          if (request.url.path == '/app/reservations') {
            return _json(200, <String, dynamic>{'items': <Object>[rzReservation(1)], 'next_before_id': 1, 'unread_count': 2});
          }
          return _json(200, <String, dynamic>{'items': <Object>[], 'next_before_id': null, 'unread_count': 1});
        }),
      );
      expect(await service.unreadCounts(siteCode: 11), (reservations: 2, concierge: 1));
      expect(queries['/app/reservations'], <String, String>{'site_code': '11', 'scope': 'all', 'limit': '1'});
      expect(queries['/app/concierge-requests'], <String, String>{'site_code': '11', 'status': 'all', 'limit': '1'});
      await service.unreadCounts();
      expect(queries['/app/reservations'], <String, String>{'scope': 'all', 'limit': '1'});
      expect(queries['/app/concierge-requests'], <String, String>{'status': 'all', 'limit': '1'});
    });

    test('unreadCounts: eski sunucu 0 / 0; bir istek düşerse hata çağırana gider (ekran yutar, rozet yardımcıdır)', () async {
      var fail = false;
      final service = ReservationService(
        authService: _FakeAuth(),
        api: _api((request) async {
          if (fail && request.url.path == '/app/concierge-requests') {
            return _json(503, <String, dynamic>{'error': 'Geçici hata.'});
          }
          return _json(200, <String, dynamic>{'items': <Object>[], 'next_before_id': null});
        }),
      );
      expect(await service.unreadCounts(), (reservations: 0, concierge: 0));
      fail = true;
      await expectLater(service.unreadCounts(), throwsA(anything));
    });
  });
}
