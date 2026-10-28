// K8 (P1-16): site menü yerleşimi uçları (MenuLayoutService). Yöntem + yol + gövde, hata eşlemesi, oturum kuralları.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/menu_layout_api.dart';

class _Auth extends AuthService {
  _Auth({this.token = 'tok'}) : super(api: AuthApi(baseUrl: 'https://api.example.com/'));

  final String? token;
  int refreshes = 0;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(
          id: 5,
          fullName: 'Ayşe Yılmaz',
          email: 'a@example.com',
          loginName: null,
          role: UserRole.siteManager,
          isActive: true,
          token: token!,
        );

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshes++;
  }
}

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _view({bool customized = false, List<String> compact = const <String>['finance']}) => <String, dynamic>{
      'site_code': 7,
      'site_name': 'Gül Sitesi',
      'management_type': 'apartment_site',
      'management_type_label': 'Apartman ve Site',
      'customized': customized,
      'compact_modules': compact,
      'default_compact_modules': <String>['finance', 'people'],
      'modules': <Object>[
        <String, dynamic>{
          'code': 'finance',
          'name': 'Aidat ve Finans',
          'description': 'Aidat',
          'core': true,
          'enabled': true,
          'compact': true,
          'recommended': true,
        },
      ],
    };

void main() {
  test('load: GET /manager/sites/:kod/menu-layout, Authorization başlığı, gövde modele çevrilir', () async {
    late http.BaseRequest seen;
    final service = MenuLayoutService(
      authService: _Auth(),
      client: MockClient((request) async {
        seen = request;
        return _json(200, _view());
      }),
    );
    final state = await service.load(7);
    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'https://api.example.com/manager/sites/7/menu-layout');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(state.siteCode, 7);
    expect(state.compactModules, <String>['finance']);
    expect(state.defaultCompactModules, <String>['finance', 'people']);
    expect(state.modules.single.core, isTrue);
  });

  test('save: PUT, gövde yalnız { compact_modules: [...] } (modül açma/kapama alanı yok)', () async {
    String? body;
    http.BaseRequest? seen;
    final service = MenuLayoutService(
      authService: _Auth(),
      client: MockClient((request) async {
        seen = request;
        body = request.body;
        return _json(200, _view(customized: true, compact: const <String>['finance', 'survey']));
      }),
    );
    final state = await service.save(7, <String>['finance', 'survey']);
    expect(seen!.method, 'PUT');
    expect(seen!.url.path, '/manager/sites/7/menu-layout');
    expect(jsonDecode(body!), <String, dynamic>{'compact_modules': <String>['finance', 'survey']});
    expect(seen!.headers['Content-Type'], contains('application/json'));
    expect(state.customized, isTrue);
  });

  test('reset: DELETE, gövdesiz', () async {
    http.Request? seen;
    final service = MenuLayoutService(
      authService: _Auth(),
      client: MockClient((request) async {
        seen = request;
        return _json(200, _view());
      }),
    );
    final state = await service.reset(7);
    expect(seen!.method, 'DELETE');
    expect(seen!.url.path, '/manager/sites/7/menu-layout');
    expect(seen!.body, isEmpty);
    expect(state.customized, isFalse);
  });

  test('sunucu hatası: Türkçe ileti ve kod ApiException ile gelir; 401 oturumu yeniler', () async {
    final auth = _Auth();
    final service = MenuLayoutService(
      authService: auth,
      client: MockClient((request) async => _json(400, <String, dynamic>{'error': 'Geçersiz modül kodu.', 'code': 'INVALID_MENU_MODULE'})),
    );
    await expectLater(
      service.save(7, <String>['yok']),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Geçersiz modül kodu.').having((e) => e.code, 'code', 'INVALID_MENU_MODULE')),
    );
    expect(auth.refreshes, 0);

    final expired = MenuLayoutService(authService: auth, client: MockClient((request) async => _json(401, <String, dynamic>{'error': 'Yetkisiz erisim.'})));
    await expectLater(expired.load(7), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(auth.refreshes, 1, reason: '401 oturum bitişidir');
  });

  test('oturum yok: ağa çıkılmaz; ağ hatası: kullanıcıya dönük ileti (ham hata sızmaz)', () async {
    var calls = 0;
    final noSession = MenuLayoutService(
      authService: _Auth(token: null),
      client: MockClient((request) async {
        calls++;
        return _json(200, _view());
      }),
    );
    await expectLater(noSession.load(7), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Oturum açmanız gerekmektedir.')));
    expect(calls, 0);

    final offline = MenuLayoutService(authService: _Auth(), client: MockClient((request) async => throw http.ClientException('SECRET_HOST_DETAIL')));
    await expectLater(
      offline.load(7),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.')),
    );
  });

  test('JSON olmayan gövde: genel hata iletisi (durum kodu ile)', () async {
    final service = MenuLayoutService(authService: _Auth(), client: MockClient((request) async => http.Response('<html>', 502)));
    await expectLater(service.load(7), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'İşlem başarısız (502).')));
  });
}
