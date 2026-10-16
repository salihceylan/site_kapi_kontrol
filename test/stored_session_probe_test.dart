// Satışa hazırlık / F3: açılış kapısının yönetici kaçışı için kayıtlı oturum sınıflandırması.
//
// AuthService oturumu güvenli depoda `auth_session` anahtarıyla JSON olarak saklar (UserSession.toJson).
// Kapı yalnız rolü ve etkinliği okur; belirteç/kişisel alanlar sınıflandırma çıktısına sızmaz.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/stored_session_probe.dart';

String _stored(UserRole role, {bool active = true, String token = 'jeton'}) {
  return jsonEncode(
    UserSession(
      id: 1,
      fullName: 'Ayşe Yılmaz',
      email: 'ayse@example.com',
      loginName: null,
      role: role,
      isActive: active,
      token: token,
    ).toJson(),
  );
}

void main() {
  group('classifyStoredSession', () {
    test('etkin süper kullanıcı oturumu -> superUser (UserSession.toJson biçimiyle)', () {
      expect(
        classifyStoredSession(_stored(UserRole.superUser)),
        StoredSessionKind.superUser,
      );
    });

    test('diğer tüm roller -> other', () {
      for (final role in UserRole.values) {
        if (role == UserRole.superUser) continue;
        expect(
          classifyStoredSession(_stored(role)),
          StoredSessionKind.other,
          reason: role.apiValue,
        );
      }
    });

    test('pasif süper kullanıcı kaçış hakkı vermez', () {
      expect(
        classifyStoredSession(_stored(UserRole.superUser, active: false)),
        StoredSessionKind.other,
      );
    });

    test('belirteçsiz/bozuk/boş oturum -> none', () {
      expect(classifyStoredSession(null), StoredSessionKind.none);
      expect(classifyStoredSession(''), StoredSessionKind.none);
      expect(classifyStoredSession('{bozuk'), StoredSessionKind.none);
      expect(classifyStoredSession('[1,2]'), StoredSessionKind.none);
      expect(classifyStoredSession('"super_user"'), StoredSessionKind.none);
      expect(
        classifyStoredSession(_stored(UserRole.superUser, token: '')),
        StoredSessionKind.none,
        reason: 'belirteçsiz kayıt oturum sayılmaz',
      );
      expect(
        classifyStoredSession(jsonEncode(<String, dynamic>{'role': 5, 'token': 't'})),
        StoredSessionKind.none,
      );
    });

    test('rol metni süper kullanıcıya benzese bile tam eşleşme aranır', () {
      expect(
        classifyStoredSession(jsonEncode(<String, dynamic>{'role': 'super_user_x', 'token': 't'})),
        StoredSessionKind.other,
      );
      expect(
        classifyStoredSession(jsonEncode(<String, dynamic>{'role': 'SUPER_USER', 'token': 't'})),
        StoredSessionKind.other,
      );
    });
  });

  test('depo anahtarı AuthService ile aynıdır (kaynakta karşılaştırma)', () {
    final auth = File('lib/services/auth_service.dart').readAsStringSync();
    final key = RegExp(r"_storageKey = '([^']+)'").firstMatch(auth)![1];
    expect(kStoredSessionKey, key);
  });

  test('varsayılan sınama eklenti yokken (hata) none döner, çökmez', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await probeStoredSession(), StoredSessionKind.none);
  });
}
