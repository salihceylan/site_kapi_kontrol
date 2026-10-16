// Platform: site başvurusu (site yöneticisi olma) AuthApi / AuthService uçları
// (docs/PLATFORM_SITE_BASVURUSU.md).
//
// MockClient ile: uç yolları, HTTP yöntemleri, gövdeler, sorgu parametreleri, Bearer başlığı, hata kodu ->
// Türkçe mesaj eşlemeleri (başvuran bakış açısı dahil), hız sınırı (429), oturum hataları. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Recorder {
  final List<http.Request> requests = <http.Request>[];

  http.Request get last => requests.last;

  Map<String, dynamic> get lastBody => jsonDecode(last.body) as Map<String, dynamic>;
}

AuthApi _api(_Recorder rec, FutureOr<http.Response> Function(http.Request request) handler) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient((request) async {
      rec.requests.add(request);
      return handler(request);
    }),
    retryDelay: Duration.zero,
  );
}

Map<String, dynamic> _app({int id = 12, String status = 'pending', Map<String, dynamic>? extra}) =>
    <String, dynamic>{
      'id': id,
      'status': status,
      'site_name': 'Gül Sitesi',
      'block_count': 1,
      'apartment_count': 10,
      'door_count': 1,
      'blocks': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'A Blok', 'apartment_count': 10},
      ],
      'doors': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Ana Giriş'},
      ],
      'created_at': '2026-10-16T11:30:00Z',
      ...?extra,
    };

const List<Map<String, dynamic>> _blocks = <Map<String, dynamic>>[
  <String, dynamic>{'name': 'A Blok', 'apartmentCount': 10},
];
const List<Map<String, dynamic>> _doors = <Map<String, dynamic>>[
  <String, dynamic>{'name': 'Ana Giriş', 'doorIndex': 1},
];

/// Sözleşmedeki yeni hata kodları ve beklenen Türkçe metinler.
const Map<String, String> _expected = <String, String>{
  'APPLICATION_REQUIRED': 'Site kurmak için başvuru yapmalısınız.',
  'APPLICATION_PENDING': 'Zaten bekleyen bir site başvurunuz var.',
  'APPLICATION_NOT_FOUND': 'Başvuru bulunamadı.',
  'APPLICATION_NOT_PENDING': 'Bu başvuru artık bekleyen durumda değil.',
  'APPLICANT_UNAVAILABLE': 'Başvuran hesap silinmiş ya da pasif; başvuru onaylanamaz.',
  'APPLICATION_DAILY_LIMIT': 'Günlük başvuru sınırına ulaştınız. Yarın tekrar deneyin.',
  'PAYMENT_NOT_AVAILABLE': 'Ödeme ile site açma yakında.',
  'APPLICATION_DATA_INVALID': 'Başvuru bilgileri geçersiz. Alanları kontrol edip tekrar deneyin.',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Hata kodu -> Türkçe mesaj (site başvurusu)', () {
    test('yeni kodların metni birebir, kısa ve ham kod sızdırmaz', () {
      for (final entry in _expected.entries) {
        final message = AuthApi.messageForErrorCode(entry.key);
        expect(message, entry.value, reason: entry.key);
        expect(message!.length, lessThan(140));
        expect(message.contains('_'), isFalse);
      }
    });

    test('ALREADY_SITE_MANAGER ve DEVICE_NOT_FOUND genel eşlemesi korunur', () {
      expect(AuthApi.messageForErrorCode('ALREADY_SITE_MANAGER'), 'Bu kişi zaten site yöneticisi.');
      expect(AuthApi.messageForErrorCode('DEVICE_NOT_FOUND'), 'Cihaz bulunamadı.');
    });

    test('HTTP yanıtından geçince ApiException.message Türkçe eşleme olur (sunucu metni değil)', () async {
      for (final entry in _expected.entries) {
        final api = _api(_Recorder(), (r) => _json({'error': 'sunucu metni', 'code': entry.key}, 409));
        await expectLater(
          api.getMySiteApplications(token: 'tok'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', entry.value)
                .having((e) => e.code, 'code', entry.key)
                .having((e) => e.statusCode, 'status', 409)
                .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
          ),
          reason: entry.key,
        );
      }
    });

    test('bilinmeyen kodda sunucunun Türkçe metni; jargonlu metin genel Türkçe ile değişir', () async {
      final known = _api(
        _Recorder(),
        (r) => _json({'error': 'Site adı zorunludur.', 'code': 'INVALID_BODY'}, 400),
      );
      await expectLater(
        known.createSiteApplication(token: 'tok', name: '', blocks: _blocks),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Site adı zorunludur.')),
      );
      final jargon = _api(
        _Recorder(),
        (r) => _json({'error': 'apartment_count geçersiz', 'code': 'INVALID_BODY'}, 400),
      );
      await expectLater(
        jargon.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', AuthApi.jargonFallbackMessage)
              .having((e) => e.message.contains('_'), 'alan adı sızıntısı', isFalse),
        ),
      );
    });
  });

  group('AuthApi: başvuran uçları', () {
    test('createSiteApplication: POST /membership/site-applications, Bearer, gövde, 201 ayrışır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'application': _app()}, 201));

      final app = await api.createSiteApplication(
        token: 'tok',
        name: 'Gül Sitesi',
        city: 'İstanbul',
        district: 'Kadıköy',
        address: 'Moda Cad.',
        blocks: _blocks,
        doors: _doors,
        deviceUid: 'ESP32_C3_ABC',
        managementType: 'apartment_site',
        note: '  Acil kurulum  ',
      );

      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/membership/site-applications');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(rec.lastBody, <String, dynamic>{
        'name': 'Gül Sitesi',
        'city': 'İstanbul',
        'district': 'Kadıköy',
        'address': 'Moda Cad.',
        'blocks': _blocks,
        'doors': _doors,
        'doorCount': 1,
        'deviceUid': 'ESP32_C3_ABC',
        'management_type': 'apartment_site',
        'note': 'Acil kurulum',
      });
      expect(app.id, 12);
      expect(app.isPending, isTrue);
    });

    test('createSiteApplication: cihaz / not / şehir boşsa alanlar HİÇ gönderilmez (cihaz şart değil)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'application': _app()}, 201));

      await api.createSiteApplication(
        token: 'tok',
        name: 'Gül Sitesi',
        city: '',
        address: '',
        blocks: _blocks,
        deviceUid: '',
        note: '   ',
      );

      expect(rec.lastBody.containsKey('deviceUid'), isFalse);
      expect(rec.lastBody.containsKey('note'), isFalse);
      expect(rec.lastBody.containsKey('city'), isFalse);
      expect(rec.lastBody.containsKey('address'), isFalse);
      expect(rec.lastBody['doorCount'], 1);
    });

    test('createSiteApplication: 200 de kabul edilir (savunmacı durum kodu)', () async {
      final api = _api(_Recorder(), (r) => _json({'application': _app()}, 200));
      final app = await api.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks);
      expect(app.id, 12);
    });

    test('createSiteApplication 409 ALREADY_SITE_MANAGER: başvuran bakış açısıyla yeniden yazılır', () async {
      final api = _api(
        _Recorder(),
        (r) => _json({'error': 'Bu kişi zaten site yöneticisi.', 'code': 'ALREADY_SITE_MANAGER'}, 409),
      );
      await expectLater(
        api.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', AuthApi.siteApplicationAlreadyManagerMessage)
              .having((e) => e.message, 'başvuran dili', startsWith('Zaten site yöneticisisiniz'))
              .having((e) => e.code, 'code', 'ALREADY_SITE_MANAGER')
              .having((e) => e.statusCode, 'status', 409),
        ),
      );
    });

    test('createSiteApplication 404 DEVICE_NOT_FOUND: cihaz seçimini kaldırma yönlendirmesi', () async {
      final api = _api(
        _Recorder(),
        (r) => _json({'error': 'Cihaz bulunamadı.', 'code': 'DEVICE_NOT_FOUND'}, 404),
      );
      await expectLater(
        api.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks, deviceUid: 'X'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            AuthApi.siteApplicationDeviceNotFoundMessage,
          ),
        ),
      );
    });

    test('createSiteApplication 429: hız sınırı ve bekleme süresi korunur', () async {
      final api = _api(
        _Recorder(),
        (r) => _json({'error': 'Çok sık', 'retry_after_seconds': 90}, 429),
      );
      await expectLater(
        api.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isRateLimited, 'rateLimited', isTrue)
              .having((e) => e.retryAfterSeconds, 'retryAfter', 90)
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse),
        ),
      );
    });

    test('createSiteApplication 403 FORBIDDEN_ROLE oturumu KAPATMAZ; yanıt bozuksa ApiException', () async {
      final forbidden = _api(
        _Recorder(),
        (r) => _json({'error': 'Yetkiniz yok', 'code': 'FORBIDDEN_ROLE'}, 403),
      );
      await expectLater(
        forbidden.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks),
        throwsA(
          isA<ApiException>()
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse)
              .having((e) => e.message, 'message', 'Bu işlem için yetkiniz yok.'),
        ),
      );
      final broken = _api(_Recorder(), (r) => _json({'tamam': true}, 201));
      await expectLater(
        broken.createSiteApplication(token: 'tok', name: 'x', blocks: _blocks),
        throwsA(isA<ApiException>()),
      );
    });

    test('getMySiteApplications: GET /membership/site-applications/mine; pending ve items', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'pending': _app(id: 5),
        'items': <Map<String, dynamic>>[_app(id: 5), _app(id: 4, status: 'rejected')],
      }));
      final mine = await api.getMySiteApplications(token: 'tok');
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/membership/site-applications/mine');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(mine.pending!.id, 5);
      expect(mine.items.map((e) => e.status), <String>['pending', 'rejected']);
    });

    test('cancelSiteApplication: POST /membership/site-applications/:id/cancel', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'application': _app(id: 5, status: 'cancelled')}));
      final app = await api.cancelSiteApplication(token: 'tok', applicationId: 5);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/membership/site-applications/5/cancel');
      expect(app.isCancelled, isTrue);
    });

    test('cancelSiteApplication 409 / 404: Türkçe mesajlar', () async {
      final notPending = _api(
        _Recorder(),
        (r) => _json({'error': 'x', 'code': 'APPLICATION_NOT_PENDING'}, 409),
      );
      await expectLater(
        notPending.cancelSiteApplication(token: 'tok', applicationId: 5),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', _expected['APPLICATION_NOT_PENDING'])),
      );
      final notFound = _api(
        _Recorder(),
        (r) => _json({'error': 'x', 'code': 'APPLICATION_NOT_FOUND'}, 404),
      );
      await expectLater(
        notFound.cancelSiteApplication(token: 'tok', applicationId: 5),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', _expected['APPLICATION_NOT_FOUND'])),
      );
    });
  });

  group('AuthApi: süper kullanıcı uçları', () {
    test('listAdminSiteApplications: GET /admin/site-applications, süzgeç / arama / sayfalama sorgusu', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'items': <Map<String, dynamic>>[_app(id: 3), _app(id: 2)],
        'total': 7,
      }));
      final page = await api.listAdminSiteApplications(
        token: 'tok',
        status: 'approved',
        query: '  Gül Sitesi  ',
        limit: 30,
        offset: 60,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/admin/site-applications');
      expect(rec.last.url.queryParameters, <String, String>{
        'status': 'approved',
        'q': 'Gül Sitesi',
        'limit': '30',
        'offset': '60',
      });
      expect(page.items.map((e) => e.id), <int>[3, 2]);
      expect(page.total, 7);
    });

    test('listAdminSiteApplications: boş arama q göndermez; süzgeç verilmezse status yok', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'items': <Object>[], 'total': 0}));
      await api.listAdminSiteApplications(token: 'tok', query: '   ');
      expect(rec.last.url.queryParameters.containsKey('q'), isFalse);
      expect(rec.last.url.queryParameters.containsKey('status'), isFalse);
      expect(rec.last.url.queryParameters['limit'], '30');
      expect(rec.last.url.queryParameters['offset'], '0');
    });

    test('summary: GET /admin/site-applications/summary -> bekleyen sayı; bozuk yanıt ApiException', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'pending': 4}));
      expect(await api.getAdminSiteApplicationsPendingCount(token: 'tok'), 4);
      expect(rec.last.url.path, '/admin/site-applications/summary');

      final negative = _api(_Recorder(), (r) => _json({'pending': -3}));
      expect(await negative.getAdminSiteApplicationsPendingCount(token: 'tok'), 0);

      final broken = _api(_Recorder(), (r) => _json({'tamam': true}));
      await expectLater(
        broken.getAdminSiteApplicationsPendingCount(token: 'tok'),
        throwsA(isA<ApiException>()),
      );
    });

    test('getAdminSiteApplication: doğrudan Application ve {application} sarmalı okunur', () async {
      final rec = _Recorder();
      final direct = _api(rec, (r) => _json(_app(id: 9, extra: <String, dynamic>{
        'applicant': <String, dynamic>{'user_code': 3, 'full_name': 'Ayşe Yılmaz'},
        'device_available': false,
      })));
      final a = await direct.getAdminSiteApplication(token: 'tok', applicationId: 9);
      expect(rec.last.url.path, '/admin/site-applications/9');
      expect(a.applicant!.fullName, 'Ayşe Yılmaz');
      expect(a.deviceAvailable, isFalse);

      final wrapped = _api(_Recorder(), (r) => _json({'application': _app(id: 9)}));
      expect((await wrapped.getAdminSiteApplication(token: 'tok', applicationId: 9)).id, 9);
    });

    test('approve: POST .../approve, boş gövde; yanıt site + cihaz bağlandı bilgisi', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'application': _app(id: 9, status: 'approved', extra: <String, dynamic>{'site_code': 55}),
        'site': <String, dynamic>{'site_code': 55, 'name': 'Gül Sitesi'},
        'device_attached': false,
      }));
      final decision = await api.approveSiteApplication(token: 'tok', applicationId: 9);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/admin/site-applications/9/approve');
      expect(rec.lastBody, isEmpty);
      expect(decision.application.isApproved, isTrue);
      expect(decision.siteCode, 55);
      expect(decision.deviceAttached, isFalse);
    });

    test('approve: not verilirse gövdeye girer; 409 APPLICANT_UNAVAILABLE / APPLICATION_NOT_PENDING Türkçe', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'application': _app(status: 'approved')}));
      await api.approveSiteApplication(token: 'tok', applicationId: 9, note: ' Hoş geldiniz ');
      expect(rec.lastBody, <String, dynamic>{'note': 'Hoş geldiniz'});

      for (final code in <String>['APPLICANT_UNAVAILABLE', 'APPLICATION_NOT_PENDING']) {
        final failing = _api(_Recorder(), (r) => _json({'error': 'x', 'code': code}, 409));
        await expectLater(
          failing.approveSiteApplication(token: 'tok', applicationId: 9),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', _expected[code])),
          reason: code,
        );
      }
    });

    test('reject: POST .../reject, gerekçe `reason` olarak (boşsa gönderilmez)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({'application': _app(id: 9, status: 'rejected')}));
      final app = await api.rejectSiteApplication(token: 'tok', applicationId: 9, reason: '  Eksik bilgi  ');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/admin/site-applications/9/reject');
      expect(rec.lastBody, <String, dynamic>{'reason': 'Eksik bilgi'});
      expect(app.isRejected, isTrue);

      await api.rejectSiteApplication(token: 'tok', applicationId: 9, reason: '  ');
      expect(rec.lastBody, isEmpty);
    });
  });

  group('AuthService: site başvurusu', () {
    UserSession session0(UserRole role) => UserSession(
      id: 5,
      fullName: 'Ali Veli',
      email: 'ali@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: 'tok-A',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    Future<({AuthService service, _Recorder rec})> makeService(
      FutureOr<http.Response> Function(http.Request request) handler, {
      UserRole role = UserRole.individual,
      bool loggedIn = true,
    }) async {
      if (loggedIn) {
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'auth_session': jsonEncode(session0(role).toJson()),
        });
      }
      final rec = _Recorder();
      final service = AuthService(api: _api(rec, (r) {
        if (r.url.path == '/me') {
          return _json({
            'user': {
              'id': 5,
              'full_name': 'Ali Veli',
              'email': 'ali@example.com',
              'login_name': null,
              'role': role.apiValue,
              'is_active': true,
            },
          });
        }
        return handler(r);
      }));
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rec.requests.clear();
      return (service: service, rec: rec);
    }

    test('createSiteApplication oturum belirtecini kullanır ve rolü YEREL değiştirmez', () async {
      final h = await makeService((r) => _json({'application': _app()}, 201));
      final app = await h.service.createSiteApplication(name: 'Gül Sitesi', blocks: _blocks);
      expect(app.id, 12);
      expect(h.rec.last.headers['Authorization'], 'Bearer tok-A');
      expect(h.service.session!.role, UserRole.individual);
      h.service.dispose();
    });

    test('mine / cancel / admin uçları doğru yol ve yöntemle çağrılır', () async {
      final h = await makeService((r) {
        switch (r.url.path) {
          case '/membership/site-applications/mine':
            return _json({'pending': null, 'items': <Object>[]});
          case '/membership/site-applications/5/cancel':
            return _json({'application': _app(id: 5, status: 'cancelled')});
          case '/admin/site-applications':
            return _json({'items': <Object>[], 'total': 0});
          case '/admin/site-applications/summary':
            return _json({'pending': 2});
          case '/admin/site-applications/5':
            return _json(_app(id: 5));
          case '/admin/site-applications/5/approve':
            return _json({'application': _app(id: 5, status: 'approved'), 'site': <String, dynamic>{}});
          case '/admin/site-applications/5/reject':
            return _json({'application': _app(id: 5, status: 'rejected')});
        }
        return _json({}, 404);
      }, role: UserRole.superUser);
      final s = h.service;
      expect((await s.getMySiteApplications()).latest, isNull);
      expect((await s.cancelSiteApplication(5)).isCancelled, isTrue);
      expect((await s.listAdminSiteApplications(status: 'all')).total, 0);
      expect(h.rec.last.url.queryParameters['status'], 'all');
      expect(await s.getAdminSiteApplicationsPendingCount(), 2);
      expect((await s.getAdminSiteApplication(5)).id, 5);
      expect((await s.approveSiteApplication(5)).application.isApproved, isTrue);
      expect((await s.rejectSiteApplication(5, reason: 'x')).isRejected, isTrue);
      s.dispose();
    });

    test('oturum yokken ApiException (ağ isteği yapılmaz)', () async {
      final h = await makeService((r) => _json({}), loggedIn: false);
      await expectLater(h.service.getMySiteApplications(), throwsA(isA<ApiException>()));
      await expectLater(
        h.service.createSiteApplication(name: 'x', blocks: _blocks),
        throwsA(isA<ApiException>()),
      );
      expect(h.rec.requests, isEmpty);
      h.service.dispose();
    });

    test('401 -> oturum kapanır (merkezi oturum hatası işleme)', () async {
      final h = await makeService(
        (r) => _json({'error': 'Oturum geçersiz', 'code': 'TOKEN_INVALID'}, 401),
      );
      expect(h.service.isLoggedIn, isTrue);
      await expectLater(h.service.getMySiteApplications(), throwsA(isA<SessionExpiredException>()));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });
  });
}
