// EmergencyService (lib/services/emergency_api.dart): uç yolları, gövde biçimi, hata çevirisi, oturum bitişi.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _FakeAuth extends AuthService {
  _FakeAuth() : super(api: AuthApi(baseUrl: '$_base/'));

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

Future<ApiException> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

void main() {
  test('listSites: GET /app/emergency, taşıyıcı belirteç, siteler sırayla ayrıştırılır; site olmayan girdiler atılır', () async {
    final auth = _FakeAuth();
    late http.Request seen;
    final service = EmergencyService(
      authService: auth,
      client: MockClient((request) async {
        seen = request;
        return _json(200, <String, dynamic>{
          'sites': <Object>[
            <String, dynamic>{'site_code': 1, 'site_name': 'Gül Sitesi', 'address': 'Atatürk Mah.', 'city': 'İstanbul', 'district': 'Kadıköy', 'elevator_firm_name': 'Yıldız', 'elevator_firm_phone': '0212 555 12 34', 'can_edit': true},
            'bozuk',
            <String, dynamic>{'site_code': 2, 'site_name': 'Lale Sitesi', 'address': null, 'can_edit': false},
          ],
        });
      }),
    );
    final sites = await service.listSites();
    expect(seen.method, 'GET');
    expect(seen.url.toString(), '$_base/app/emergency');
    expect(seen.headers['Authorization'], 'Bearer tok-1');
    expect(sites.map((s) => s.siteCode), <int>[1, 2]);
    expect(sites.first.addressLine, 'Atatürk Mah., Kadıköy / İstanbul');
    expect(sites.first.canEdit, isTrue);
    expect(sites.last.hasAddress, isFalse);
    expect(sites.last.canEdit, isFalse);
  });

  test('listSites: sites alanı yoksa ya da liste değilse boş liste', () async {
    final service = EmergencyService(authService: _FakeAuth(), client: MockClient((_) async => _json(200, <String, dynamic>{'sites': 'x'})));
    expect(await service.listSites(), isEmpty);
    final none = EmergencyService(authService: _FakeAuth(), client: MockClient((_) async => _json(200, <String, dynamic>{})));
    expect(await none.listSites(), isEmpty);
  });

  test('saveElevatorFirm: PUT /manager/sites/:kod/emergency, iki alan gövdede; yanıt temizlenmiş değerleri döner', () async {
    late http.Request seen;
    final service = EmergencyService(
      authService: _FakeAuth(),
      client: MockClient((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'site_code': 1000000001, 'elevator_firm_name': ' Yıldız Asansör ', 'elevator_firm_phone': '0212 555 12 34'});
      }),
    );
    final saved = await service.saveElevatorFirm(1000000001, name: 'Yıldız   Asansör', phone: '0212 555 12 34');
    expect(seen.method, 'PUT');
    expect(seen.url.path, '/manager/sites/1000000001/emergency');
    expect(seen.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(seen.body), <String, dynamic>{'elevator_firm_name': 'Yıldız   Asansör', 'elevator_firm_phone': '0212 555 12 34'});
    expect(saved, (name: 'Yıldız Asansör', phone: '0212 555 12 34'));
  });

  test('saveElevatorFirm: kaldırma iki alanı da null gönderir; yanıt null döner', () async {
    late http.Request seen;
    final service = EmergencyService(
      authService: _FakeAuth(),
      client: MockClient((request) async {
        seen = request;
        return _json(200, <String, dynamic>{'site_code': 1, 'elevator_firm_name': null, 'elevator_firm_phone': null});
      }),
    );
    final saved = await service.saveElevatorFirm(1);
    expect(jsonDecode(seen.body), <String, dynamic>{'elevator_firm_name': null, 'elevator_firm_phone': null});
    expect(saved, (name: null, phone: null));
  });

  test('sunucu hatası: sunucunun Türkçe metni ve kodu korunur; 401 oturumu yeniler; genel hata yedek metin taşır', () async {
    final auth = _FakeAuth();
    final forbidden = EmergencyService(
      authService: auth,
      client: MockClient((_) async => _json(403, <String, dynamic>{'error': 'Bu işlem için yetkiniz yok.', 'code': 'FORBIDDEN_ROLE'})),
    );
    final denied = await _failureOf(() => forbidden.saveElevatorFirm(1, name: 'A', phone: '112'));
    expect(denied.message, 'Bu işlem için yetkiniz yok.');
    expect(denied.code, 'FORBIDDEN_ROLE');
    expect(denied.statusCode, 403);

    final expired = EmergencyService(authService: auth, client: MockClient((_) async => _json(401, <String, dynamic>{'error': 'Oturum süresi doldu.'})));
    final unauthorized = await _failureOf(expired.listSites);
    expect(unauthorized.statusCode, 401);
    expect(auth.refreshForced, 1);

    final broken = EmergencyService(authService: auth, client: MockClient((_) async => http.Response('<html>', 502)));
    final generic = await _failureOf(broken.listSites);
    expect(generic.statusCode, 502);
    expect(generic.message, contains('502'));
  });

  test('ağ hatası Türkçe mesajlı ApiException olur; oturum yoksa istek hiç gitmez', () async {
    final offline = EmergencyService(authService: _FakeAuth(), client: MockClient((_) async => throw http.ClientException('yok')));
    final failure = await _failureOf(offline.listSites);
    expect(failure.message, contains('Sunucuya bağlanılamadı'));

    final signedOut = _FakeAuth()..token = null;
    var requests = 0;
    final service = EmergencyService(authService: signedOut, client: MockClient((_) async {
      requests++;
      return _json(200, <String, dynamic>{});
    }));
    final noSession = await _failureOf(service.listSites);
    expect(noSession.message, contains('Oturum'));
    expect(requests, 0);
  });
}
