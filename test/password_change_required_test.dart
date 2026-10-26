// Sunucu zorunlu şifre belirlemeyi istediğinde (`403 PASSWORD_CHANGE_REQUIRED`: yönetimin verdiği geçici şifre / PIN değişene kadar
// GET/PATCH /me dışındaki her uç) oturum DÜŞMEZ; yerel oturum `mustChangePassword` olarak işaretlenir ve dinleyiciler (ana sayfa)
// zorunlu şifre diyaloğunu açabilir. Diğer 403'ler (hesap pasif vb.) davranışını korur: /me ile doğrulanır.
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
import 'package:site_kapi_kontrol/services/theme_service.dart';

http.Response _json(int status, Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

const UserSession _session = UserSession(
  id: 7,
  fullName: 'Ayşe Yılmaz',
  email: 'ayse@example.com',
  loginName: 'ayse.y',
  role: UserRole.apartmentOwner,
  isActive: true,
  token: 'tok-7',
);

const Map<String, dynamic> _passwordChangeRequired = <String, dynamic>{
  'error': 'Devam etmeden once yeni bir sifre belirlemelisiniz.',
  'code': 'PASSWORD_CHANGE_REQUIRED',
};

Map<String, dynamic> _meBody({bool mustChange = false}) => <String, dynamic>{
  'user': <String, dynamic>{
    'id': 7,
    'full_name': 'Ayşe Yılmaz',
    'email': 'ayse@example.com',
    'login_name': 'ayse.y',
    'role': 'apartment_owner',
    'is_active': true,
    'must_change_password': mustChange,
  },
};

void _seedStorage() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'tur_gorulduy': true,
    ThemeService.storageKey: 'dark',
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'auth_session': jsonEncode(_session.toJson()),
    'local_door_cache': '{}',
  });
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('yetkili istekte 403 PASSWORD_CHANGE_REQUIRED: oturum KORUNUR, mustChangePassword işaretlenir, dinleyiciler uyarılır, hata çağırana iletilir', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/me') return _json(200, _meBody());
          return _json(403, _passwordChangeRequired);
        }),
      ),
    );
    await auth.initialize();
    await _until(() => auth.sessionVerifiedAt != null);
    expect(auth.isLoggedIn, isTrue);
    expect(auth.session!.mustChangePassword, isFalse);

    var notified = 0;
    auth.addListener(() => notified++);

    await expectLater(
      auth.getMyRecords(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PASSWORD_CHANGE_REQUIRED')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(auth.isLoggedIn, isTrue, reason: 'oturum düşmez (kimlik bilgisi geçerli; yalnız şifre belirlenmeli)');
    expect(auth.session!.mustChangePassword, isTrue);
    expect(auth.session!.token, 'tok-7');
    expect(notified, greaterThan(0), reason: 'ana sayfa zorunlu şifre diyaloğunu açabilsin');
    expect(auth.takeSessionNotice(), isNull, reason: 'çıkış bildirimi yok');

    // İşaret yerel depoya da yazılır (uygulama yeniden açılınca diyalog hemen çıkar).
    final stored = jsonDecode((await const FlutterSecureStorage().read(key: 'auth_session'))!) as Map<String, dynamic>;
    expect(stored['must_change_password'], isTrue);
  });

  test('ikinci kez aynı hata: tekrar bildirim üretmez (zaten işaretli)', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/me') return _json(200, _meBody());
          return _json(403, _passwordChangeRequired);
        }),
      ),
    );
    await auth.initialize();
    await _until(() => auth.sessionVerifiedAt != null);
    await expectLater(auth.getMyRecords(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    var notified = 0;
    auth.addListener(() => notified++);
    await expectLater(auth.getMyRecords(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notified, 0);
    expect(auth.session!.mustChangePassword, isTrue);
  });

  test('açılışta /me 403 PASSWORD_CHANGE_REQUIRED dönse bile (olağan dışı) oturum kapanmaz', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async => _json(403, _passwordChangeRequired)),
      ),
    );
    await auth.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(auth.isLoggedIn, isTrue);
    expect(auth.session!.mustChangePassword, isTrue);
  });

  test('başka bir 403 (kodsuz / farklı kod): zorunlu şifre durumuna GEÇİLMEZ', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/me') return _json(200, _meBody());
          return _json(403, <String, dynamic>{'error': 'Bu islem icin yetkiniz yok.', 'code': 'FORBIDDEN_ROLE'});
        }),
      ),
    );
    await auth.initialize();
    await _until(() => auth.sessionVerifiedAt != null);
    await expectLater(auth.getMyRecords(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(auth.session!.mustChangePassword, isFalse);
    expect(auth.isLoggedIn, isTrue);
  });
}
