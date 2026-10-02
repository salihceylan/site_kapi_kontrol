// E2E ortam bilgisi: --dart-define-from-file (integration_test/tool/make_defines.mjs) ile gelir.
//
// Tanimlar:
//   E2E_USERS    JSON-STRING { "<rol anahtari>": {login,password,role,full_name} }
//   E2E_FIXTURE  JSON-STRING { sites:{...}, users:{...} } (ekranda beklenen ad/metinler, sir yok)
//   E2E_API_BASE API taban adresi (yoksa uygulamanin API_BASE_URL'i kullanilir)
//   E2E_OUT_DIR  ekran goruntusu + rapor dizini (Android'de yok sayilir: Directory.systemTemp)
//   E2E_RUN      kosu adi (varsayilan zaman damgasi)
//   E2E_COMBOS   calistirilacak gorunum/yazi-olcegi kombinasyonlari (virgullu; ornek:
//                "phone@1.0,small@1.5"; "quick" = yalniz phone@1.0; "all" = 3 preset x {1.0,1.5})
//   E2E_ONLY     virgullu kullanici anahtarlari filtresi (ornek: "manager_2,resident_a1")
//   E2E_SCREENS  virgullu ekran adlari filtresi (ornek: "panel,siteler")
//   E2E_SHOT_MAX ekran goruntusunun uzun kenar piksel ust siniri (varsayilan 1100)

import 'dart:convert';
import 'dart:io';

import 'package:site_kapi_kontrol/config/app_config.dart';

/// E2E test kullanicisi. Parola ASLA yazdirilmaz (toString'te yok).
class E2eUser {
  const E2eUser({
    required this.key,
    required this.login,
    required this.password,
    required this.role,
    required this.fullName,
  });

  final String key;
  final String login;
  final String password;
  final String role;
  final String fullName;

  @override
  String toString() => 'E2eUser($key, $role)';
}

class E2eEnv {
  E2eEnv._();

  static const String _usersRaw = String.fromEnvironment('E2E_USERS');
  static const String _fixtureRaw = String.fromEnvironment('E2E_FIXTURE');
  static const String _apiBase = String.fromEnvironment('E2E_API_BASE');
  static const String _outDir = String.fromEnvironment('E2E_OUT_DIR');
  static const String _runName = String.fromEnvironment('E2E_RUN');
  static const String _combos = String.fromEnvironment('E2E_COMBOS');
  static const String _only = String.fromEnvironment('E2E_ONLY');
  static const String _screens = String.fromEnvironment('E2E_SCREENS');
  static const String _shotMax = String.fromEnvironment('E2E_SHOT_MAX');

  static final String _autoRun = _stamp(DateTime.now());

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// Uygulamanin gercekte kullandigi API adresi (dart-define API_BASE_URL).
  static String get appApiBase => AppConfig.baseUrl;

  static String get apiBase => _apiBase.isNotEmpty ? _apiBase : appApiBase;

  /// Uretime baglanmayi engelleyen emniyet: yalniz yerel/emulator adreslerine izin verir.
  static void assertLocalApi() {
    final uri = Uri.tryParse(appApiBase);
    final host = (uri?.host ?? '').toLowerCase();
    const allowed = <String>{'127.0.0.1', 'localhost', '10.0.2.2', '::1'};
    if (!allowed.contains(host)) {
      throw StateError(
        'E2E yalnizca yerel arka uca baglanir; API_BASE_URL="$appApiBase" izinli degil. '
        '--dart-define=API_BASE_URL=http://127.0.0.1:18080 verin.',
      );
    }
  }

  static Map<String, E2eUser> get users {
    if (_usersRaw.isEmpty) {
      throw StateError(
        'E2E_USERS bos: --dart-define-from-file=<E2E>/dart_defines.json verin '
        '(node integration_test/tool/make_defines.mjs --e2e <E2E>).',
      );
    }
    final decoded = jsonDecode(_usersRaw) as Map<String, dynamic>;
    return <String, E2eUser>{
      for (final entry in decoded.entries)
        entry.key: E2eUser(
          key: entry.key,
          login: (entry.value as Map)['login'] as String,
          password: (entry.value as Map)['password'] as String,
          role: ((entry.value as Map)['role'] ?? '') as String,
          fullName: ((entry.value as Map)['full_name'] ?? '') as String,
        ),
    };
  }

  static E2eUser user(String key) {
    final found = users[key];
    if (found == null) {
      throw StateError('E2E_USERS icinde "$key" yok (var olanlar: ${users.keys.join(', ')}).');
    }
    return found;
  }

  /// Beklenen metinler (site/kapi/kullanici adlari). Yoksa bos harita.
  static Map<String, dynamic> get fixture {
    if (_fixtureRaw.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(_fixtureRaw) as Map<String, dynamic>;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  static String? siteName(String siteKey) {
    final sites = fixture['sites'];
    if (sites is Map && sites[siteKey] is Map) {
      return (sites[siteKey] as Map)['name'] as String?;
    }
    return null;
  }

  /// Ilk dairenin kart etiketi ("BLOK / Daire 1"), bilinmiyorsa null.
  static String? firstApartmentLabel(String siteKey) {
    final sites = fixture['sites'];
    if (sites is Map && sites[siteKey] is Map) {
      final blocks = (sites[siteKey] as Map)['blocks'];
      if (blocks is List && blocks.isNotEmpty) return '${blocks.first} / Daire 1';
    }
    return null;
  }

  static List<String> doorNames(String siteKey) {
    final sites = fixture['sites'];
    if (sites is Map && sites[siteKey] is Map) {
      final doors = (sites[siteKey] as Map)['doors'];
      if (doors is List) return doors.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  /// Site katilim kodu (SJT-...). Yalnizca okuma amacli "Site Bilgilerini Getir" icin kullanilir.
  static String? joinToken(String siteKey) {
    final t = fixture['join_tokens'];
    if (t is Map && t[siteKey] is Map) return (t[siteKey] as Map)['token'] as String?;
    return null;
  }

  /// Sahipsiz (sahiplenilmemis) cihaz UID'si, yoksa null.
  static String? unclaimedDeviceUid() {
    final d = fixture['devices'];
    if (d is Map) {
      for (final v in d.values) {
        if (v is Map && v['claimed'] == false) return v['uid'] as String?;
      }
    }
    return null;
  }

  /// Verilen sitelere atanmis cihazlarin UID'leri (fixture'daki devices[*].site).
  static List<String> deviceUidsForSites(List<String> siteKeys) {
    final d = fixture['devices'];
    final out = <String>[];
    if (d is Map) {
      for (final v in d.values) {
        if (v is Map && siteKeys.contains(v['site']) && v['uid'] is String) {
          out.add(v['uid'] as String);
        }
      }
    }
    return out;
  }

  static String? deviceUid(String deviceKey) {
    final d = fixture['devices'];
    if (d is Map && d[deviceKey] is Map) return (d[deviceKey] as Map)['uid'] as String?;
    return null;
  }

  static String? userFullName(String userKey) {
    final u = fixture['users'];
    if (u is Map && u[userKey] is Map) {
      return (u[userKey] as Map)['full_name'] as String?;
    }
    return null;
  }

  static String get runName => _runName.isNotEmpty ? _runName : _autoRun;

  /// Cikti kok dizini. Android'de host yolu gecersizdir -> Directory.systemTemp.
  static String get outRoot {
    if (Platform.isAndroid || _outDir.isEmpty) {
      return '${Directory.systemTemp.path}${Platform.pathSeparator}e2e_out';
    }
    return _outDir;
  }

  static String get runDir => '$outRoot/$runName'.replaceAll(r'\', '/');

  static int get shotMax {
    final parsed = int.tryParse(_shotMax);
    return (parsed != null && parsed >= 300) ? parsed : 1100;
  }

  static Set<String> get onlyUsers => _splitSet(_only);

  static Set<String> get onlyScreens => _splitSet(_screens);

  static String get combosRaw => _combos;

  static Set<String> _splitSet(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
}
