// Hesap sunucuda silinmişse (başka cihazda ya da yanıtı kaybolan bir silme sonucu) `401 ACCOUNT_DELETED`:
// oturum kapanır VE uygulama içi silmedeki aynı yerel temizlik yapılır (kayıtlı e-posta, güvenilir cihaz belirteci,
// tercihler); bilgi mesajı "oturum süresi doldu" değil "hesap silinmiş" der.
//
// İki yol: açılışta /me doğrulaması (AuthService._runSessionRefresh) ve yetkili bir isteğin 401'i
// (AuthService._handleSessionError).
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
  loginName: null,
  role: UserRole.individual,
  isActive: true,
  token: 'tok-7',
);

void _seedStorage() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'saved_login_identifier': 'ayse@example.com',
    'remember_login_credentials': true,
    'tur_gorulduy': true,
    ThemeService.storageKey: 'dark',
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'auth_session': jsonEncode(_session.toJson()),
    'login_device_tokens_v1': '{"ayse@example.com":"cihaz-belirteci"}',
    'local_door_cache': '{}',
  });
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _expectWiped(AuthService auth) async {
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getKeys(), <String>{ThemeService.storageKey}, reason: 'e-posta, tur bayrağı vb. silinir; tema kalır');
  expect(await const FlutterSecureStorage().readAll(), isEmpty, reason: 'cihaz belirteci dahil güvenli depo boş');
  expect(auth.isLoggedIn, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('açılışta /me 401 ACCOUNT_DELETED: oturum kapanır, yerel veriler temizlenir, mesaj "hesap silinmiş"', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/me') {
            return _json(401, <String, dynamic>{'error': 'Bu hesap silinmis.', 'code': 'ACCOUNT_DELETED'});
          }
          return _json(404, <String, dynamic>{'error': 'yok'});
        }),
      ),
    );
    await auth.initialize();
    await _until(() => !auth.isLoggedIn);
    // Temizlik çıkıştan SONRA çalışır: tamamlanmasını bekle.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await _expectWiped(auth);
    final notice = auth.takeSessionNotice();
    expect(notice, contains('Bu hesap silinmiş'));
    expect(notice, isNot(contains('Oturum süreniz doldu')));
  });

  test('yetkili istekte 401 ACCOUNT_DELETED: aynı temizlik yapılır', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/me') {
            return _json(200, <String, dynamic>{
              'user': <String, dynamic>{
                'id': 7,
                'full_name': 'Ayşe Yılmaz',
                'email': 'ayse@example.com',
                'role': 'individual',
                'is_active': true,
              },
            });
          }
          return _json(401, <String, dynamic>{'error': 'Bu hesap silinmis.', 'code': 'ACCOUNT_DELETED'});
        }),
      ),
    );
    await auth.initialize();
    await _until(() => auth.sessionVerifiedAt != null);
    expect(auth.isLoggedIn, isTrue);

    await expectLater(auth.getMyRecords(), throwsA(isA<ApiException>()));
    await _until(() => !auth.isLoggedIn);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await _expectWiped(auth);
    expect(auth.takeSessionNotice(), contains('Bu hesap silinmiş'));
  });

  test('başka 401 (oturum süresi): yerel veriler SİLİNMEZ (yalnız çıkış)', () async {
    _seedStorage();
    final auth = AuthService(
      api: AuthApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/me') {
            return _json(401, <String, dynamic>{'error': 'x', 'code': 'TOKEN_EXPIRED'});
          }
          return _json(404, <String, dynamic>{});
        }),
      ),
    );
    await auth.initialize();
    await _until(() => !auth.isLoggedIn);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(auth.isLoggedIn, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_login_identifier'), 'ayse@example.com', reason: 'normal oturum sonunda e-posta kalır');
    expect((await const FlutterSecureStorage().readAll())['login_device_tokens_v1'], isNotNull,
        reason: 'güvenilir cihaz belirteci çıkışta silinmez');
    expect(auth.takeSessionNotice(), contains('Oturum süreniz doldu'));
  });
}
