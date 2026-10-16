import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';

/// Cihazdaki kayıtlı oturumun türü (açılış kapısı için).
enum StoredSessionKind {
  /// Kayıtlı oturum yok (ya da okunamadı).
  none,

  /// Etkin bir süper kullanıcı oturumu kayıtlı.
  superUser,

  /// Başka bir rolün oturumu kayıtlı.
  other,
}

/// Kayıtlı oturum türünü okuyan işlev; testlerde değiştirilebilir.
typedef StoredSessionProbe = Future<StoredSessionKind> Function();

/// `AuthService` oturumu bu anahtarla güvenli depoda saklar (`_storageKey`); iki yer aynı kalmalıdır
/// (`test/release_identity_test.dart` kaynakta karşılaştırır).
const String kStoredSessionKey = 'auth_session';

/// Güvenli depodaki oturum metnini sınıflandırır. Belirteç ve kişisel alanlar çıktıya KONMAZ.
StoredSessionKind classifyStoredSession(String? raw) {
  if (raw == null || raw.isEmpty) return StoredSessionKind.none;
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return StoredSessionKind.none;
    final role = data['role'];
    final token = data['token'];
    if (role is! String || token is! String || token.isEmpty) {
      return StoredSessionKind.none;
    }
    final active = data['is_active'] is bool ? data['is_active'] as bool : true;
    if (role == UserRole.superUser.apiValue && active) {
      return StoredSessionKind.superUser;
    }
    return StoredSessionKind.other;
  } catch (_) {
    return StoredSessionKind.none;
  }
}

/// Varsayılan sınama: güvenli depodan okur; her hata `none` sayılır (kapıyı çökertmez).
Future<StoredSessionKind> probeStoredSession() async {
  try {
    final raw = await const FlutterSecureStorage().read(key: kStoredSessionKey);
    return classifyStoredSession(raw);
  } catch (_) {
    return StoredSessionKind.none;
  }
}
