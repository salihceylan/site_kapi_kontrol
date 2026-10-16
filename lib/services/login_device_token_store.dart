import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Güvenilir cihaz belirteci deposu (sunucu: `POST /auth/login` yanıtındaki `device_token`, HMAC, 180 gün).
///
/// Belirteç hesaba bağlıdır ve PAROLA YERİNE GEÇMEZ: yalnız dağıtık parola püskürtmesinde hesap sahibinin
/// kilitlenmesini önler. Bu yüzden her giriş tanımlayıcısı (e-posta / kullanıcı adı, küçük harf) için ayrı
/// saklanır ve girişte yalnız o tanımlayıcının belirteci gönderilir; en çok [maxEntries] kayıt tutulur
/// (en eskisi atılır).
///
/// Depolama: `flutter_secure_storage`, tek anahtar [storageKey]. Tanımlayıcılar düz metin değil SHA-256
/// özeti olarak saklanır. Her işlem hata yutar (depolama okunamazsa giriş belirteçsiz sürer).
///
/// ÇIKIŞ (`AuthService.logout`) belirteci SİLMEZ: kilitlenme koruması tam da çıkış yapıp geri dönen sahibi
/// içindir. HESAP SİLMEDE yerel durum temizliği (`LocalDataWiper`: `secureStorage.deleteAll()`) bu anahtarı da
/// siler; ayrı bir silme gerekmez.
class LoginDeviceTokenStore {
  LoginDeviceTokenStore({FlutterSecureStorage? storage, DateTime Function()? now})
    : _storage = storage ?? const FlutterSecureStorage(),
      _now = now ?? DateTime.now;

  /// Güvenli depodaki anahtar adı (F1'in hesap silme temizliği `deleteAll` kullandığından çakışma yoktur).
  static const String storageKey = 'login_device_tokens_v1';

  /// Saklanan en çok tanımlayıcı sayısı.
  static const int maxEntries = 8;

  /// Sunucunun kabul ettiği en uzun belirteç.
  static const int maxTokenLength = 512;

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  /// Tanımlayıcıyı katlar (kırp + küçük harf). Boşsa null.
  static String? normalize(String? identifier) {
    final text = identifier?.trim().toLowerCase();
    return (text == null || text.isEmpty) ? null : text;
  }

  static String _hash(String normalized) =>
      sha256.convert(utf8.encode(normalized)).toString();

  /// Yalnız yazdırılabilir ASCII ve makul uzunluk (başlık/gövde enjeksiyonuna karşı).
  static bool isPlausibleToken(String? token) =>
      token != null &&
      token.isNotEmpty &&
      token.length <= maxTokenLength &&
      token.codeUnits.every((c) => c > 0x20 && c < 0x7F);

  Future<Map<String, dynamic>> _readAll() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Bozuk / okunamayan kayıt: yok sayılır.
    }
    return <String, dynamic>{};
  }

  /// [identifier] için saklı belirteç; yoksa / bozuksa null.
  Future<String?> read(String? identifier) async {
    final key = normalize(identifier);
    if (key == null) return null;
    final entry = (await _readAll())[_hash(key)];
    if (entry is Map) {
      final token = entry['t'];
      if (token is String && isPlausibleToken(token)) return token;
    }
    return null;
  }

  /// [token]'ı verilen tanımlayıcıların (örn. girilen ad + oturumun e-postası + kullanıcı adı) hepsi için saklar.
  /// Geçersiz belirteçte hiçbir şey yazmaz.
  Future<void> save(Iterable<String?> identifiers, String token) async {
    if (!isPlausibleToken(token)) return;
    final keys = <String>{
      for (final id in identifiers)
        if (normalize(id) case final String key) _hash(key),
    };
    if (keys.isEmpty) return;
    try {
      final all = await _readAll();
      final stamp = _now().millisecondsSinceEpoch;
      for (final key in keys) {
        all[key] = <String, dynamic>{'t': token, 'at': stamp};
      }
      // En eskileri at: yalnız son [maxEntries] kayıt kalır.
      if (all.length > maxEntries) {
        final entries = all.entries.toList()
          ..sort((a, b) => _stamp(b.value).compareTo(_stamp(a.value)));
        all
          ..clear()
          ..addEntries(entries.take(maxEntries));
      }
      await _storage.write(key: storageKey, value: jsonEncode(all));
    } catch (_) {
      // Yazılamadı: bir sonraki girişte belirteçsiz devam edilir.
    }
  }

  static int _stamp(Object? entry) {
    if (entry is Map && entry['at'] is int) return entry['at'] as int;
    return 0;
  }

  /// Tüm kayıtları siler (açık bir "bu cihazı unut" eylemi için; çıkışta ÇAĞRILMAZ).
  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
    } catch (_) {}
  }
}
