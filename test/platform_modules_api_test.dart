// Platform modül sistemi Faz 1: AuthApi / AuthService uçları (docs/PLATFORM_MODUL_SISTEMI.md).
//
// MockClient ile: uç yolları, HTTP yöntemleri, gövdeler, sorgu parametreleri, Bearer başlığı, hata
// kodu -> Türkçe mesaj eşlemeleri ve oturum hataları. Sunucu gerekmez.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
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

  Map<String, dynamic> get lastBody =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

AuthApi _api(
  _Recorder rec,
  FutureOr<http.Response> Function(http.Request request) handler,
) {
  return AuthApi(
    baseUrl: 'https://api.example.test',
    client: MockClient((request) async {
      rec.requests.add(request);
      return handler(request);
    }),
    retryDelay: Duration.zero,
  );
}

Map<String, dynamic> _siteModulesBody({bool doorEnabled = true}) =>
    <String, dynamic>{
      'site_code': 1234567890,
      'site_name': 'Gül Sitesi',
      'management_type': 'apartment_site',
      'management_type_label': 'Apartman ve Site',
      'modules': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': 'door_control',
          'name': 'Geçiş Kontrol (AHBU)',
          'description': 'Kapı açma',
          'core': false,
          'status': 'available',
          'enabled': doorEnabled,
          'toggleable': true,
          'updated_at': null,
          'updated_by': null,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthApi: modül uçları', () {
    test('getModuleCatalog: GET /app/modules/catalog, Bearer başlığı, liste ayrışır', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'modules': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'door_control',
            'name': 'Geçiş Kontrol (AHBU)',
            'description': 'x',
            'core': false,
            'status': 'available',
          },
          <String, dynamic>{
            'code': 'people',
            'name': 'Kişi ve Daire Kayıtları',
            'description': 'y',
            'core': true,
            'status': 'coming_soon',
          },
        ],
      }));

      final modules = await api.getModuleCatalog(token: 'tok');
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/modules/catalog');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      expect(modules.map((m) => m.code), <String>['door_control', 'people']);
      expect(modules.last.core, isTrue);
    });

    test('getMyModules: GET /app/my-modules (siteler ve scope: all)', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'scope': 'sites',
        'sites': <Map<String, dynamic>>[
          <String, dynamic>{
            'site_code': 1234567890,
            'site_name': 'Gül Sitesi',
            'management_type': 'apartment_site',
            'role': 'manager',
            'modules': <String, dynamic>{'door_control': true, 'finance': false},
          },
        ],
      }));
      final result = await api.getMyModules(token: 'tok');
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/app/my-modules');
      expect(result.isAll, isFalse);
      expect(result.sites.single.siteCode, 1234567890);
      expect(result.sites.single.isEnabled('door_control'), isTrue);
      expect(result.sites.single.isEnabled('finance'), isFalse);

      final all = _api(rec, (r) => _json({'scope': 'all', 'sites': <dynamic>[]}));
      expect((await all.getMyModules(token: 'tok')).isAll, isTrue);
    });

    test('getSiteModules: GET /manager/sites/:siteCode/modules', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_siteModulesBody()));
      final state = await api.getSiteModules(token: 'tok', siteCode: 1234567890);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/1234567890/modules');
      expect(state.siteName, 'Gül Sitesi');
      expect(state.managementType, ManagementType.apartmentSite);
      expect(state.module('door_control')!.enabled, isTrue);
    });

    test('setSiteModule: PUT, gövde {enabled, confirm}; confirm varsayılanı false', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(_siteModulesBody(doorEnabled: false)));

      final off = await api.setSiteModule(
        token: 'tok',
        siteCode: 1234567890,
        moduleCode: 'door_control',
        enabled: false,
        confirm: true,
      );
      expect(rec.last.method, 'PUT');
      expect(rec.last.url.path, '/manager/sites/1234567890/modules/door_control');
      expect(rec.lastBody, <String, dynamic>{'enabled': false, 'confirm': true});
      expect(rec.last.headers['Content-Type'], contains('application/json'));
      expect(off.module('door_control')!.enabled, isFalse);

      await api.setSiteModule(
        token: 'tok',
        siteCode: 1,
        moduleCode: 'door_control',
        enabled: true,
      );
      expect(rec.lastBody, <String, dynamic>{'enabled': true, 'confirm': false});
    });

    test('setSiteModule: 409 MODULE_CONFIRM_REQUIRED sunucu metnini ve kodunu taşır', () async {
      const warning =
          'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?';
      final api = _api(
        _Recorder(),
        (r) => _json({'error': warning, 'code': 'MODULE_CONFIRM_REQUIRED'}, 409),
      );
      await expectLater(
        api.setSiteModule(
          token: 'tok',
          siteCode: 1,
          moduleCode: 'door_control',
          enabled: false,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.code, 'code', 'MODULE_CONFIRM_REQUIRED')
              .having((e) => e.message, 'message', warning),
        ),
      );
    });

    test('listAuditLog: GET /admin/audit-log sorgu parametreleri', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json({
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 7,
            'created_at': '2026-10-15T09:30:00Z',
            'actor_user_code': 1,
            'actor_name': 'Süper Yönetici',
            'actor_role': 'super_user',
            'action': 'module.disabled',
            'site_code': 1234567890,
            'site_name': 'Gül Sitesi',
            'target_type': 'module',
            'target_id': 'door_control',
            'details': <String, dynamic>{'enabled': false},
          },
        ],
        'next_before_id': 7,
      }));

      final page = await api.listAuditLog(
        token: 'tok',
        siteCode: 1234567890,
        limit: 25,
        beforeId: 99,
      );
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/admin/audit-log');
      expect(rec.last.url.queryParameters, <String, String>{
        'site_code': '1234567890',
        'limit': '25',
        'before_id': '99',
      });
      expect(page.items.single.action, 'module.disabled');
      expect(page.nextBeforeId, 7);

      await api.listAuditLog(token: 'tok');
      expect(rec.last.url.queryParameters, <String, String>{'limit': '50'},
          reason: 'site_code, action ve before_id verilmezse hiç gönderilmez');

      await api.listAuditLog(token: 'tok', action: 'module.disabled');
      expect(rec.last.url.queryParameters, <String, String>{
        'action': 'module.disabled',
        'limit': '50',
      });
      await api.listAuditLog(token: 'tok', action: '');
      expect(rec.last.url.queryParameters.containsKey('action'), isFalse,
          reason: 'boş eylem "tümü" demektir: gönderilmez');
    });

    test('listStaffRoles / assignStaffRole / removeStaffRole: yollar ve gövdeler', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) {
        if (r.method == 'DELETE') return _json({'ok': true});
        if (r.method == 'PUT') {
          return _json({
            'item': <String, dynamic>{
              'user_code': 42,
              'full_name': 'Selin Aydın',
              'email': 'selin@ornek.com',
              'role': 'BOARD_MEMBER',
              'created_at': '2026-10-15T09:30:00Z',
            },
          });
        }
        return _json({
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'user_code': 42,
              'full_name': 'Selin Aydın',
              'email': 'selin@ornek.com',
              'role': 'BOARD_MEMBER',
              'created_at': '2026-10-15T09:30:00Z',
            },
          ],
        });
      });

      final list = await api.listStaffRoles(token: 'tok', siteCode: 5);
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/manager/sites/5/staff-roles');
      expect(list.single.fullName, 'Selin Aydın');

      final item = await api.assignStaffRole(
        token: 'tok',
        siteCode: 5,
        email: 'selin@ornek.com',
        role: 'BOARD_MEMBER',
      );
      expect(rec.last.method, 'PUT');
      expect(rec.last.url.path, '/manager/sites/5/staff-roles');
      expect(rec.lastBody, <String, dynamic>{
        'email': 'selin@ornek.com',
        'role': 'BOARD_MEMBER',
      });
      expect(item.userCode, 42);

      await api.removeStaffRole(token: 'tok', siteCode: 5, userCode: 42);
      expect(rec.last.method, 'DELETE');
      expect(rec.last.url.path, '/manager/sites/5/staff-roles/42');
    });

    test('bozuk gövde ApiException olur (TypeError sızmaz)', () async {
      final api = _api(_Recorder(), (r) => _json({'item': 'metin'}));
      await expectLater(
        api.assignStaffRole(
          token: 'tok',
          siteCode: 5,
          email: 'a@b.co',
          role: 'STAFF',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('401 oturum sonu: SessionExpiredException', () async {
      final api = _api(
        _Recorder(),
        (r) => _json({'error': 'Oturum geçersiz', 'code': 'TOKEN_INVALID'}, 401),
      );
      await expectLater(
        api.getMyModules(token: 'tok'),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('Hata kodu -> Türkçe mesaj (modül sistemi)', () {
    const expected = <String, String>{
      'MODULE_DISABLED':
          'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.',
      'MODULE_COMING_SOON': 'Bu modül yakında.',
      'MODULE_NOT_TOGGLEABLE': 'Bu modül kapatılamaz.',
      'MODULE_NOT_FOUND': 'Modül bulunamadı.',
      'MANAGEMENT_TYPE_COMING_SOON': 'Bu yönetim türü yakında.',
      'MANAGEMENT_TYPE_INVALID': 'Geçersiz yönetim türü.',
      'USER_NOT_FOUND': 'Bu e-posta ile kayıtlı hesap yok.',
      'USER_NOT_ACTIVE': 'Bu hesap henüz etkin değil.',
      'ALREADY_SITE_MANAGER': 'Bu kişi zaten site yöneticisi.',
      'ROLE_INVALID': 'Geçersiz rol.',
      'ROLE_NOT_FOUND': 'Bu kişide kurul veya görevli rolü yok.',
    };

    test('sözleşmedeki 11 kodun metni birebir ve kısa', () {
      for (final entry in expected.entries) {
        final message = AuthApi.messageForErrorCode(entry.key);
        expect(message, entry.value, reason: entry.key);
        expect(message!.length, lessThan(140));
        expect(message.contains('_'), isFalse);
      }
    });

    test('MODULE_CONFIRM_REQUIRED eşlenmez: sunucu metni kullanılır', () {
      expect(AuthApi.messageForErrorCode('MODULE_CONFIRM_REQUIRED'), isNull);
    });

    test('HTTP yanıtından geçince ApiException.message Türkçe eşleme olur (sunucu metni değil)', () async {
      for (final entry in expected.entries) {
        final api = _api(
          _Recorder(),
          (r) => _json({'error': 'sunucu metni', 'code': entry.key}, 409),
        );
        await expectLater(
          api.getSiteModules(token: 'tok', siteCode: 1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', entry.value)
                .having((e) => e.code, 'code', entry.key),
          ),
          reason: entry.key,
        );
      }
    });

    test('MODULE_DISABLED (403 + module alanı) ApiException olur ve oturumu KAPATMAZ', () async {
      final api = _api(
        _Recorder(),
        (r) => _json({
          'error': 'Geçiş Kontrol modülü kapalı.',
          'code': 'MODULE_DISABLED',
          'module': 'door_control',
        }, 403),
      );
      await expectLater(
        api.getSiteModules(token: 'tok', siteCode: 1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.invalidatesSession, 'invalidatesSession', isFalse)
              .having(
                (e) => e.message,
                'message',
                'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.',
              ),
        ),
      );
    });
  });

  group('Site oluşturma: management_type', () {
    test('createSite: managementType verilirse gövdeye yazılır, verilmezse hiç gönderilmez', () async {
      final rec = _Recorder();
      final api = _api(
        rec,
        (r) => _json({
          'site': <String, dynamic>{
            'id': 1,
            'name': 'Yeni',
            'management_type': 'apartment_site',
            'management_type_label': 'Apartman ve Site',
          },
        }, 201),
      );

      final site = await api.createSite(
        token: 'tok',
        role: UserRole.superUser,
        name: 'Yeni',
        blockApartmentCounts: const <int>[10],
        doorCount: 1,
        managementType: 'apartment_site',
      );
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/admin/sites');
      expect(rec.lastBody['management_type'], 'apartment_site');
      expect(site.managementType, ManagementType.apartmentSite);

      await api.createSite(
        token: 'tok',
        role: UserRole.superUser,
        name: 'Yeni',
        blockApartmentCounts: const <int>[10],
        doorCount: 1,
      );
      expect(rec.lastBody.containsKey('management_type'), isFalse);
    });

    test('setupSite: management_type gövdeye yazılır; yönetim türü sunucu hatası ApiException', () async {
      final rec = _Recorder();
      final api = _api(rec, (r) => _json(<String, dynamic>{'ok': true}, 201));
      await api.setupSite(
        token: 'tok',
        name: 'Gül Sitesi',
        blocks: const <Map<String, dynamic>>[],
        managementType: 'apartment_site',
      );
      expect(rec.last.url.path, '/membership/setup-site');
      expect(rec.lastBody['management_type'], 'apartment_site');

      await api.setupSite(
        token: 'tok',
        name: 'Gül Sitesi',
        blocks: const <Map<String, dynamic>>[],
      );
      expect(rec.lastBody.containsKey('management_type'), isFalse);

      final rejecting = _api(
        rec,
        (r) => _json({
          'error': 'Bu yönetim türü yakında.',
          'code': 'MANAGEMENT_TYPE_COMING_SOON',
        }, 400),
      );
      await expectLater(
        rejecting.setupSite(
          token: 'tok',
          name: 'X',
          blocks: const <Map<String, dynamic>>[],
          managementType: 'residence',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Bu yönetim türü yakında.',
          ),
        ),
      );
    });
  });

  group('AuthService: modül sarmalayıcıları', () {
    UserSession session0({UserRole role = UserRole.siteManager}) => UserSession(
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
      UserRole role = UserRole.siteManager,
      bool loggedIn = true,
    }) async {
      if (loggedIn) {
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'auth_session': jsonEncode(session0(role: role).toJson()),
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

    test('getMyModules oturum belirtecini kullanır', () async {
      final h = await makeService(
        (r) => _json({'scope': 'sites', 'sites': <dynamic>[]}),
      );
      final result = await h.service.getMyModules();
      expect(result.sites, isEmpty);
      expect(h.rec.last.headers['Authorization'], 'Bearer tok-A');
      expect(h.rec.last.url.path, '/app/my-modules');
      h.service.dispose();
    });

    test('tüm sarmalayıcılar sözleşmedeki yollara gider', () async {
      final h = await makeService((r) {
        if (r.url.path == '/app/modules/catalog') {
          return _json({'modules': <dynamic>[]});
        }
        if (r.url.path.endsWith('/staff-roles') && r.method == 'GET') {
          return _json({'items': <dynamic>[]});
        }
        if (r.url.path.endsWith('/staff-roles') && r.method == 'PUT') {
          return _json({
            'item': {
              'user_code': 9,
              'full_name': 'K',
              'email': 'k@x.co',
              'role': 'STAFF',
            },
          });
        }
        if (r.method == 'DELETE') return _json({'ok': true});
        if (r.url.path == '/admin/audit-log') {
          return _json({'items': <dynamic>[], 'next_before_id': null});
        }
        return _json(_siteModulesBody());
      });
      final s = h.service;

      await s.getModuleCatalog();
      expect(h.rec.last.url.path, '/app/modules/catalog');
      await s.getSiteModules(7);
      expect(h.rec.last.url.path, '/manager/sites/7/modules');
      await s.setSiteModule(7, 'door_control', false, confirm: true);
      expect(h.rec.last.method, 'PUT');
      expect(h.rec.last.url.path, '/manager/sites/7/modules/door_control');
      expect(h.rec.lastBody, <String, dynamic>{'enabled': false, 'confirm': true});
      await s.listAuditLog(siteCode: 7, limit: 10, beforeId: 3);
      expect(h.rec.last.url.queryParameters, <String, String>{
        'site_code': '7',
        'limit': '10',
        'before_id': '3',
      });
      await s.listStaffRoles(7);
      expect(h.rec.last.url.path, '/manager/sites/7/staff-roles');
      final assigned = await s.assignStaffRole(7, 'k@x.co', 'STAFF');
      expect(assigned.userCode, 9);
      expect(h.rec.lastBody, <String, dynamic>{'email': 'k@x.co', 'role': 'STAFF'});
      await s.removeStaffRole(7, 9);
      expect(h.rec.last.url.path, '/manager/sites/7/staff-roles/9');
      s.dispose();
    });

    test('oturum yokken ApiException (ağ isteği yapılmaz)', () async {
      final h = await makeService(
        (r) => _json({'scope': 'all', 'sites': <dynamic>[]}),
        loggedIn: false,
      );
      await expectLater(h.service.getMyModules(), throwsA(isA<ApiException>()));
      expect(h.rec.requests, isEmpty);
      h.service.dispose();
    });

    test('401 -> oturum kapanır (merkezi oturum hatası işleme)', () async {
      final h = await makeService(
        (r) => _json({'error': 'Oturum geçersiz', 'code': 'TOKEN_INVALID'}, 401),
      );
      expect(h.service.isLoggedIn, isTrue);
      await expectLater(
        h.service.getSiteModules(7),
        throwsA(isA<SessionExpiredException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.service.isLoggedIn, isFalse);
      h.service.dispose();
    });

    DoorRecord door0({bool remote = true, bool localUdp = true}) => DoorRecord(
      id: 7,
      siteCode: 3,
      siteName: 'Güneş Sitesi',
      doorName: 'Ana Kapı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'AABBCCDDEEFF',
      mqttSiteId: 3,
      featureRemoteOpenEnabled: remote,
      featureLocalUdpEnabled: localUdp,
      createdAt: DateTime(2026, 1, 1),
    );

    Map<String, dynamic> siteModulesBody(int siteCode, {required bool door}) =>
        <String, dynamic>{
          'site_code': siteCode,
          'site_name': 'Güneş Sitesi',
          'modules': <Map<String, dynamic>>[
            <String, dynamic>{
              'code': 'door_control',
              'name': 'Geçiş Kontrol (AHBU)',
              'core': false,
              'status': 'available',
              'enabled': door,
              'toggleable': true,
            },
          ],
        };

    const moduleDisabled =
        'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.';
    const noRemote =
        'Bu kapıda uzaktan açma kapalı. Cihaza yerel ağdan ulaşılamadı; telefonu cihazla aynı Wi-Fi ağına bağlayıp tekrar deneyin.';

    test('Geçiş Kontrol kapalı site: yerel (LAN) kısayol denenmez; yalnız yerel açılabilen kapıda MODULE_DISABLED mesajı', () async {
      var doorOn = false;
      final h = await makeService(
        (r) => _json(siteModulesBody(3, door: doorOn)),
      );
      final localOnly = door0(remote: false);

      // Bilinmiyorken (fail-open) eski davranış: yerel denenir, ulaşılamayınca eski mesaj.
      expect(await h.service.openDoor(doorId: 7, door: localOnly), (null, noRemote));

      await h.service.getSiteModules(3); // süper kullanıcının Panel'inde bilinen durum: kapalı
      expect(await h.service.openDoor(doorId: 7, door: localOnly), (null, moduleDisabled));
      expect(
        h.rec.requests.where((r) => r.url.path.contains('/open')),
        isEmpty,
        reason: 'kapalı modülde kapı açma isteği hiç gönderilmez (yerel yol yok, uzak yol kapalı)',
      );

      doorOn = true; // yeniden açıldı ve istemci öğrendi
      await h.service.getSiteModules(3);
      expect(await h.service.openDoor(doorId: 7, door: localOnly), (null, noRemote));
      h.service.dispose();
    });

    test('uzak yol açıksa istek sunucuya gider; karar sunucunun MODULE_DISABLED yanıtıdır (bayat "kapalı" yanlış engellemez)', () async {
      final h = await makeService((r) {
        if (r.url.path.contains('/open')) {
          return _json({
            'error': 'Geçiş Kontrol modülü kapalı.',
            'code': 'MODULE_DISABLED',
            'module': 'door_control',
          }, 403);
        }
        return _json(siteModulesBody(3, door: false));
      });
      await h.service.getSiteModules(3);

      final (status, error) = await h.service.openDoor(doorId: 7, door: door0());
      expect(status, isNull);
      expect(error, moduleDisabled);
      expect(h.rec.requests.where((r) => r.url.path.contains('/open')), hasLength(1));
      h.service.dispose();
    });

    test('getMyModules: kapı erişimli kapalı site yerel yolu kapatır; kurul sitesi kapatmaz; önbellek ve çıkış temizliği', () async {
      var doorOn = false;
      var boardOnly = false;
      final h = await makeService((r) {
        if (r.url.path == '/app/my-modules') {
          return _json({
            'scope': 'sites',
            'sites': <Map<String, dynamic>>[
              <String, dynamic>{
                'site_code': 3,
                'site_name': 'Güneş Sitesi',
                'role': boardOnly ? 'board_member' : 'resident',
                'door_access': !boardOnly,
                'modules': <String, dynamic>{'door_control': doorOn},
              },
            ],
          });
        }
        return _json({}, 404);
      });
      final localOnly = door0(remote: false);
      expect(h.service.cachedMyModules, isNull);

      await h.service.getMyModules();
      expect(h.service.cachedMyModules!.sites.single.siteCode, 3);
      expect(await h.service.openDoor(doorId: 7, door: localOnly), (null, moduleDisabled));

      boardOnly = true; // yalnız kurul bağı: kapı erişimi yok -> kapalı SAYILMAZ
      await h.service.getMyModules();
      expect(await h.service.openDoor(doorId: 7, door: localOnly), (null, noRemote));

      boardOnly = false;
      doorOn = true;
      await h.service.getMyModules();
      expect(await h.service.openDoor(doorId: 7, door: localOnly), (null, noRemote));

      doorOn = false;
      await h.service.getMyModules();
      await h.service.logout();
      expect(h.service.cachedMyModules, isNull, reason: 'çıkışta önbellek temizlenir');
      h.service.dispose();
    });

    test('setupSite managementType iletir', () async {
      final h = await makeService((r) => _json(<String, dynamic>{'ok': true}, 201));
      await h.service.setupSite(
        name: 'Gül Sitesi',
        blocks: const <Map<String, dynamic>>[],
        managementType: 'apartment_site',
      );
      final setup = h.rec.requests.firstWhere(
        (r) => r.url.path == '/membership/setup-site',
      );
      expect((jsonDecode(setup.body) as Map<String, dynamic>)['management_type'],
          'apartment_site');
      h.service.dispose();
    });

    test('createSite managementType iletir (süper kullanıcı)', () async {
      final h = await makeService((r) {
        return _json({
          'site': <String, dynamic>{'id': 1, 'name': 'Yeni'},
        }, 201);
      }, role: UserRole.superUser);
      final (site, error) = await h.service.createSite(
        name: 'Yeni',
        blockApartmentCounts: const <int>[5],
        doorCount: 1,
        managementType: 'apartment_site',
      );
      expect(error, isNull);
      expect(site, isNotNull);
      expect(h.rec.last.url.path, '/admin/sites');
      expect(h.rec.lastBody['management_type'], 'apartment_site');
      h.service.dispose();
    });
  });
}
