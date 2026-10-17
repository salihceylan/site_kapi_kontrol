// Telefon bildirimi (Platform Faz 3b-B) için cihazda tutulan küçük durum — docs/PLATFORM_BELGELER.md B2, B8.
//
// SharedPreferences'ta (kişisel veri ve jeton YOK):
// - Kurulum kimliği (`install_id`): ilk cihaz kaydında üretilen rastgele UUID v4. Çökme raporunun `install_id`'sinden
//   AYRI üretilir ve ayrı anahtarda durur (iki kimlik birbirine bağlanamaz). iOS anahtar zincirinde değil
//   tercihlerde tutulur: uygulama silinince gider, yeniden kurulumda yeni kimlik üretilir. Android'de
//   `allowBackup=false` olduğundan yedekten de dönmez. Disktekiyle bellekteki her okumada eşitlenir (hesap
//   silmedeki yerel temizlik anahtarı silerse yenisi üretilir).
// - "Bu cihazda bildirim açık" işareti (AÇIK RIZA, kullanıcı başına): yalnız kullanıcının bu cihazda açıkça
//   yaptığı işlemle konur (tercihlerde "Bu cihazda aç" / "Telefon bildirimi" anahtarı, Duyurular'daki "Aç").
//   Varsayılan KAPALI: işaret yokken jeton üretilmez, sunucuya kayıt gitmez. "Bu cihazı kaldır" işareti siler.
// - Son kayıt damgası: kullanıcı no, FCM jetonunun SHA-256 özeti (jetonun kendisi değil), bildirilen izin
//   durumu ve zaman. "Günde en çok bir kez" tazeleme bununla karar verir.
// - Bekleyen FCM temizliği: çıkışta jeton silinemediyse (çevrimdışı) işaret kalır, sonraki açılışta / ön plana
//   dönüşte yeniden denenir (eski hesabın bildirimleri bu cihaza gelmeye devam etmesin).
// - Duyurular ekranındaki "telefon bildirimini aç" kartını kapatan kullanıcılar (kullanıcı başına, kalıcı).
//
// Hesap silmedeki yerel temizlik (`LocalDataWiper`) tema dışındaki tüm tercihleri sildiği için bunlar da gider.
// Her işlem hata yutar: depolama okunamazsa push kaydı sonraki açılışa kalır, uygulama etkilenmez.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Son başarılı cihaz kaydının özeti.
@immutable
class PushRegistrationStamp {
  const PushRegistrationStamp({
    required this.userId,
    required this.tokenHash,
    required this.notificationsEnabled,
    required this.at,
  });

  final int userId;
  final String tokenHash;
  final bool notificationsEnabled;
  final DateTime at;

  Map<String, Object> toJson() => <String, Object>{
    'u': userId,
    'h': tokenHash,
    'e': notificationsEnabled,
    'at': at.millisecondsSinceEpoch,
  };

  static PushRegistrationStamp? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final user = decoded['u'];
      final hash = decoded['h'];
      final enabled = decoded['e'];
      final at = decoded['at'];
      if (user is! int || hash is! String || enabled is! bool || at is! int) return null;
      return PushRegistrationStamp(
        userId: user,
        tokenHash: hash,
        notificationsEnabled: enabled,
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (_) {
      return null;
    }
  }
}

class PushLocalStore {
  PushLocalStore({Future<SharedPreferences> Function()? prefsLoader, Random? random})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
      _random = random ?? Random.secure();

  static const String installIdKey = 'push.install_id';
  static const String stampKey = 'push.registration';
  static const String enabledKey = 'push.device_enabled';
  static const String pendingCleanupKey = 'push.pending_fcm_cleanup';
  static const String promptDismissedKey = 'push.prompt_dismissed';

  final Future<SharedPreferences> Function() _prefsLoader;
  final Random _random;
  String? _installId;

  static final RegExp _validInstallId = RegExp(r'^[0-9a-f-]{16,64}$');

  /// Bellekteki kurulum kimliği (henüz okunmadıysa / hiç üretilmediyse null). Çıkışta eşzamanlı erişim içindir:
  /// diskten silinmiş olsa da sunucudaki eski kaydı silebilmek için son bilinen değer tutulur.
  String? get cachedInstallId => _installId;

  /// Kurulum kimliği; diskte yoksa (hiç üretilmedi ya da yerel temizlikte silindi) YENİSİ üretilip yazılır.
  Future<String> installId() async {
    SharedPreferences? prefs;
    try {
      prefs = await _prefsLoader();
      final stored = prefs.getString(installIdKey);
      if (stored != null && _validInstallId.hasMatch(stored)) return _installId = stored;
    } catch (_) {
      // Okunamadı: bellekteki değer bu çalıştırma boyunca kullanılır.
      final cached = _installId;
      if (cached != null) return cached;
    }
    final fresh = _uuidV4();
    _installId = fresh;
    try {
      await (prefs ?? await _prefsLoader()).setString(installIdKey, fresh);
    } catch (_) {}
    return fresh;
  }

  /// Diskteki kurulum kimliği; yoksa null (ÜRETMEZ: hiç kayıt olmamış cihazda silinecek bir şey yok).
  Future<String?> readInstallId() async {
    try {
      final prefs = await _prefsLoader();
      final stored = prefs.getString(installIdKey);
      if (stored != null && _validInstallId.hasMatch(stored)) return _installId = stored;
      return null;
    } catch (_) {
      return _installId;
    }
  }

  Future<PushRegistrationStamp?> readStamp() async {
    try {
      final prefs = await _prefsLoader();
      return PushRegistrationStamp.tryParse(prefs.getString(stampKey));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeStamp(PushRegistrationStamp stamp) async {
    try {
      final prefs = await _prefsLoader();
      await prefs.setString(stampKey, jsonEncode(stamp.toJson()));
    } catch (_) {}
  }

  Future<void> clearStamp() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(stampKey);
    } catch (_) {}
  }

  // --- Kullanıcı başına kümeler ----------------------------------------------------------------

  Future<Set<int>> _readSet(String key) async {
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return <int>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) return <int>{for (final v in decoded) if (v is int) v};
    } catch (_) {}
    return <int>{};
  }

  Future<void> _writeMember(String key, int userId, bool member) async {
    try {
      final set = await _readSet(key);
      final changed = member ? set.add(userId) : set.remove(userId);
      if (!changed) return;
      final prefs = await _prefsLoader();
      if (set.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(set.toList()..sort()));
      }
    } catch (_) {}
  }

  /// Kullanıcı bu cihazda telefon bildirimini AÇIKÇA açtı mı (açık rıza)? Varsayılan hayır.
  Future<bool> isEnabledHere(int userId) async => (await _readSet(enabledKey)).contains(userId);

  Future<void> setEnabledHere(int userId, bool value) => _writeMember(enabledKey, userId, value);

  /// Duyurular ekranındaki kart bu kullanıcı için kapatıldı mı?
  Future<bool> isPromptDismissed(int userId) async =>
      (await _readSet(promptDismissedKey)).contains(userId);

  Future<void> setPromptDismissed(int userId) => _writeMember(promptDismissedKey, userId, true);

  // --- Bekleyen FCM temizliği ------------------------------------------------------------------

  // Değer: o ana dek başarısız silme denemesi sayısı (anahtar varsa temizlik bekliyor).

  Future<bool> hasPendingCleanup() async {
    try {
      final prefs = await _prefsLoader();
      return prefs.containsKey(pendingCleanupKey);
    } catch (_) {
      return false;
    }
  }

  /// Bekleyen temizliğin başarısız deneme sayısı (bekleyen yoksa 0).
  Future<int> pendingCleanupFailures() async {
    try {
      final prefs = await _prefsLoader();
      final value = prefs.get(pendingCleanupKey);
      return value is int && value > 0 ? value : 0;
    } catch (_) {
      return 0;
    }
  }

  /// true: temizlik bekliyor (sayaç korunur); false: işaret ve sayaç silinir.
  Future<void> setPendingCleanup(bool value) async {
    try {
      final prefs = await _prefsLoader();
      if (!value) {
        await prefs.remove(pendingCleanupKey);
      } else if (prefs.get(pendingCleanupKey) is! int) {
        await prefs.setInt(pendingCleanupKey, 0);
      }
    } catch (_) {}
  }

  /// Başarısız bir silme denemesini sayar; yeni sayıyı döndürür.
  Future<int> recordCleanupFailure() async {
    try {
      final prefs = await _prefsLoader();
      final current = prefs.get(pendingCleanupKey);
      final next = (current is int && current > 0 ? current : 0) + 1;
      await prefs.setInt(pendingCleanupKey, next);
      return next;
    } catch (_) {
      return 0;
    }
  }

  /// RFC 4122 sürüm 4 UUID (küçük harf, 36 karakter).
  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) =>
        bytes.sublist(from, to).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
