import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/config/app_config.dart' as build_config;
import 'package:site_kapi_kontrol/services/app_version.dart';

/// Hata raporlarındaki kişisel veriyi İSTEMCİ tarafında temizler (sunucu da ayrıca temizler).
///
/// Maskelenenler: JWT, `Bearer ...`, `token=...`/`password: ...` türü anahtar-değer çiftleri,
/// e-posta adresleri, telefon numaraları (ayraçlı ya da 10-13 haneli ardışık) ve kullanıcı dizin adları.
/// Dart AOT yığın izlerindeki bellek adresleri/ofsetleri (onaltılık) bozulmaz.
abstract final class CrashSanitizer {
  // Başarım ve sızıntı ilkesi: HİÇBİR kural üst sınırla "yarım" maskelemez (sınırı aşan uzun belirteç/adres
  // kalan parçasıyla sızardı). Bunun yerine tüm taramalar DOĞRUSAL zamanlıdır:
  // - JWT ve e-posta, geri izlemesiz elle yazılmış tek geçişli tarayıcılarla maskelenir ([_maskJwts], [_maskEmails]);
  // - Bearer, anahtar-değer ve kullanıcı yolu düzenli ifadelerinin başlangıç noktaları anahtar sözcüktür
  //   (her sözcüğün arkasındaki koşu yalnız bir kez taranır, koşular çakışmaz);
  // - telefon kalıpları kendiliğinden sınırlıdır (en çok 13 hane / 6 ayraçlı grup);
  // - girdi en baştan `maxLength * 2`'ye kırpılır.
  static final RegExp _bearer = RegExp(
    r'\b(Bearer|Basic)\s{1,8}[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );
  static final RegExp _secretPair = RegExp(
    r'''\b(access_token|refresh_token|token|password|parola|sifre|secret|authorization|api[_-]?key|current_password)\b(["']?\s{0,8}[:=]\s{0,8}["']?)([^\s"',;&}]+)''',
    caseSensitive: false,
  );
  static final RegExp _phoneSeparated = RegExp(
    r'(?<![\w.])\+?\d{1,4}(?:[ ().\-]{1,6}\d{1,4}){2,5}(?!\w)',
  );
  static final RegExp _phoneContiguous = RegExp(
    r'(?<![\w.])\+?\d{10,13}(?!\w)',
  );
  static final RegExp _userPath = RegExp(
    r'([\\/](?:Users|home)[\\/])[^\\/\s:]+',
    caseSensitive: false,
  );
  static final RegExp _nonDigit = RegExp(r'\D');
  static final RegExp _bearerWord = RegExp('bearer|basic', caseSensitive: false);

  /// [input] metnini temizler ve en çok [maxLength] karaktere kırpar.
  ///
  /// Girdi önce `maxLength * 2` karaktere kırpılır (maskeleme metni kısaltabilir; son kırpma yine
  /// [maxLength]'e yapılır). Kırpma bir boşluğun yakınına denk geliyorsa metin o boşluğa kadar geri çekilir:
  /// böylece kesilen yarım bir adres/numara maskelenemeden kalmaz.
  static String sanitize(String input, {int maxLength = 500}) {
    var text = input;
    final cap = maxLength * 2;
    if (text.length > cap) {
      text = text.substring(0, cap);
      final window = maxLength ~/ 2;
      for (var k = text.length - 1; k > 0 && k >= text.length - window; k--) {
        final c = text.codeUnitAt(k);
        if (c == 0x20 || c == 0x0a || c == 0x09 || c == 0x0d) {
          text = text.substring(0, k);
          break;
        }
      }
    }
    text = _maskJwts(text);
    if (text.contains(_bearerWord)) {
      text = text.replaceAll(_bearer, r'Bearer [token]');
    }
    text = text.replaceAllMapped(_secretPair, (m) => '${m[1]}${m[2]}[gizli]');
    text = _maskEmails(text);
    text = text.replaceAllMapped(_phoneSeparated, (m) {
      final digits = m[0]!.replaceAll(_nonDigit, '').length;
      return digits >= 9 ? '[telefon]' : m[0]!;
    });
    text = text.replaceAll(_phoneContiguous, '[telefon]');
    if (text.contains('/') || text.contains(r'\')) {
      text = text.replaceAllMapped(_userPath, (m) => '${m[1]}[kullanici]');
    }
    if (text.length > maxLength) {
      text = text.substring(0, maxLength);
    }
    return text;
  }

  /// Base64url belirteç karakteri: harf, rakam, `_`, `-`.
  static bool _isTokenChar(int c) =>
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5f ||
      c == 0x2d;

  static bool _isAlnum(int c) =>
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x30 && c <= 0x39);

  /// E-posta yerel kısmı: harf, rakam, `. _ % + -` ve ASCII dışı (Unicode adres) karakterler.
  static bool _isLocalChar(int c) =>
      c >= 0x80 || _isTokenChar(c) || c == 0x2e || c == 0x25 || c == 0x2b;

  /// E-posta alan etiketi: harf, rakam, `-` ve ASCII dışı (uluslararası alan adı) karakterler.
  static bool _isDomainChar(int c) => c >= 0x80 || _isAlnum(c) || c == 0x2d;

  /// `eyJ…` ile başlayan üç bölümlü (`a.b.c`) JWT'leri `[token]` yapar. Bir belirtecin başına bitişik
  /// karakter (`abc_eyJ…`, `id-eyJ…`) maskelemeyi engellemez; uzunluk sınırı yoktur (tamamı maskelenir).
  /// Tek geçişli: her belirteç koşusu en çok bir kez taranır.
  static String _maskJwts(String text) {
    var i = text.indexOf('eyJ');
    if (i < 0) return text;
    final n = text.length;
    final out = StringBuffer();
    var copied = 0;
    var runStart = -1;
    var runEnd = -1;
    var failedRunEnd = -1;
    while (i >= 0) {
      if (i < runStart || i >= runEnd) {
        runStart = i;
        var j = i + 3;
        while (j < n && _isTokenChar(text.codeUnitAt(j))) {
          j++;
        }
        runEnd = j;
      }
      var next = i + 3;
      if (runEnd != failedRunEnd &&
          runEnd - (i + 3) >= 5 &&
          runEnd < n &&
          text.codeUnitAt(runEnd) == 0x2e) {
        var e2 = runEnd + 1;
        while (e2 < n && _isTokenChar(text.codeUnitAt(e2))) {
          e2++;
        }
        if (e2 - (runEnd + 1) >= 5 && e2 < n && text.codeUnitAt(e2) == 0x2e) {
          var e3 = e2 + 1;
          while (e3 < n && _isTokenChar(text.codeUnitAt(e3))) {
            e3++;
          }
          out
            ..write(text.substring(copied, i))
            ..write('[token]');
          copied = e3;
          next = e3;
          runStart = e3;
          runEnd = e3;
        } else {
          failedRunEnd = runEnd;
        }
      }
      i = text.indexOf('eyJ', next);
    }
    out.write(text.substring(copied));
    return out.toString();
  }

  /// `yerel@alan.uzantı` biçimli adresleri `[e-posta]` yapar. Uzunluk sınırı yoktur: çok uzun yerel kısım,
  /// uzun etiket ya da çok etiketli alan adının TAMAMI maskelenir (kalan parça sızmaz). Her `@` için sola
  /// ve sağa tek geçiş; `@` yerel/alan karakteri olmadığından taramalar çakışmaz (doğrusal).
  static String _maskEmails(String text) {
    var at = text.indexOf('@');
    if (at < 0) return text;
    final n = text.length;
    final out = StringBuffer();
    var copied = 0;
    while (at >= 0) {
      var start = at;
      while (start > copied && _isLocalChar(text.codeUnitAt(start - 1))) {
        start--;
      }
      var end = at + 1;
      final labelStart = end;
      while (end < n && _isDomainChar(text.codeUnitAt(end))) {
        end++;
      }
      var matched = false;
      if (start < at && end > labelStart) {
        var dots = 0;
        var cur = end;
        while (cur + 1 < n &&
            text.codeUnitAt(cur) == 0x2e &&
            _isDomainChar(text.codeUnitAt(cur + 1))) {
          cur++;
          while (cur < n && _isDomainChar(text.codeUnitAt(cur))) {
            cur++;
          }
          dots++;
          end = cur;
        }
        matched = dots >= 1;
      }
      if (matched) {
        out
          ..write(text.substring(copied, start))
          ..write('[e-posta]');
        copied = end;
        at = text.indexOf('@', end);
      } else {
        at = text.indexOf('@', at + 1);
      }
    }
    out.write(text.substring(copied));
    return out.toString();
  }
}

enum _SendResult { sent, retryLater, drop }

/// İstemci hata raporlayıcı: `POST /public/client-errors` (docs/PLATFORM_SATISA_HAZIRLIK.md §1.3).
///
/// Güvenceler:
/// - Raporlama HATASI uygulamayı asla bozmaz ve döngüye girmez: tüm yollar try/catch içindedir, kendi ağ
///   hatalarını raporlamaz, yeniden giriş korumalıdır ve saatlik/tekrar sınırları vardır.
/// - Kişisel veri istemcide de temizlenir ([CrashSanitizer]); `install_id` rastgele UUID'dir (kişisel veri değil).
/// - Ağ yoksa son [maxQueue] rapor yerelde tutulur, sonraki açılışta gönderilir.
/// - Hata ayıklama (debug) ve test modunda varsayılan olarak KAPALIDIR.
class CrashReporter {
  CrashReporter({
    http.Client? client,
    String? baseUrl,
    bool? enabled,
    Future<SharedPreferences> Function()? prefsLoader,
    DateTime Function()? now,
    Future<InstalledAppInfo> Function()? appInfoLoader,
    String? platformName,
    String? osVersion,
    Duration timeout = const Duration(seconds: 8),
    Duration startupFlushDelay = const Duration(seconds: 5),
  }) : _client = client,
       _baseUrl = baseUrl,
       enabled = enabled ?? _defaultEnabled,
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now,
       _appInfoLoader = appInfoLoader ?? loadInstalledAppInfo,
       _platformName = platformName,
       _osVersion = osVersion,
       _timeout = timeout,
       _startupFlushDelay = startupFlushDelay;

  /// Uygulama genelinde paylaşılan örnek.
  static final CrashReporter instance = CrashReporter();

  /// Yalnız yayın/profil derlemelerinde açık. `--dart-define=CRASH_REPORTING=true` debug'da da açar
  /// (geliştirici doğrulaması), `--dart-define=CRASH_REPORTING=false` yayın/profilde bile KAPATIR
  /// (örn. profil kipinde çalışan ölçüm/entegrasyon koşuları). `flutter test` (debug) kapalıdır.
  static final bool _defaultEnabled = switch (const String.fromEnvironment(
    'CRASH_REPORTING',
  ).toLowerCase()) {
    'true' || '1' || 'on' => true,
    'false' || '0' || 'off' => false,
    _ => !kDebugMode,
  };

  static bool _suppressed = false;

  /// Süreç boyunca raporlamayı KAPATIR (tüm örnekler). Entegrasyon/ölçüm sürücüleri `app.main()`
  /// çağırmadan önce çağırır; böylece profil/yayın kipindeki koşular üretim sunucusuna rapor göndermez.
  static void suppress() => _suppressed = true;

  /// Yalnız testler: bastırmayı kaldırır.
  @visibleForTesting
  static void resetSuppressionForTesting() => _suppressed = false;

  /// Bu örnek şu an raporlama yapar mı?
  bool get isActive => enabled && !_suppressed;

  /// Yerel kuyrukta tutulan en çok rapor sayısı (aşılınca en eskisi atılır).
  static const int maxQueue = 20;

  /// Saatte en çok gönderilecek YENİ rapor (sunucu sınırı: install_id başına 10/saat).
  static const int maxReportsPerHour = 8;

  /// Aynı hata parmak izi için tekrar bildirme aralığı.
  static const Duration dedupeWindow = Duration(minutes: 10);

  /// Bir kuyruk boşaltma turunda en çok gönderim.
  static const int maxFlushPerRun = 5;

  static const String installIdKey = 'crash_reporter.install_id';
  static const String queueKey = 'crash_reporter.queue.v1';

  final bool enabled;
  final http.Client? _client;
  final String? _baseUrl;
  final Future<SharedPreferences> Function() _prefsLoader;
  final DateTime Function() _now;
  final Future<InstalledAppInfo> Function() _appInfoLoader;
  final String? _platformName;
  final String? _osVersion;
  final Duration _timeout;
  final Duration _startupFlushDelay;

  /// Şu anki ekran/rota adı (isteğe bağlı; rota adlarındaki sayılar maskelenir). Uygulama bir
  /// `NavigatorObserver` ile güncelleyebilir; bilinmiyorsa rapora konmaz.
  String? currentRoute;

  bool _installed = false;
  bool _building = false;
  bool _flushing = false;
  String? _installId;
  final List<DateTime> _recentSends = <DateTime>[];
  final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};
  Future<void> _lockTail = Future<void>.value();

  /// Hata kancalarını kurar ve bekleyen yerel kuyruğu (kısa bir gecikmeyle) göndermeyi dener.
  /// Kapalıyken hiçbir şey yapmaz. Kancalar eşzamanlı kurulur (ilk `await` öncesi).
  Future<void> install() async {
    if (!isActive || _installed) return;
    _installed = true;

    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      try {
        if (!details.silent) {
          unawaited(
            report(
              details.exception,
              details.stack,
              fatal: false,
              message: details.exceptionAsString(),
            ),
          );
        }
      } catch (_) {
        // Raporlama asla çağıran hata yoluna sızmaz.
      }
      if (previousFlutter != null) {
        previousFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      try {
        unawaited(report(error, stack, fatal: true));
      } catch (_) {}
      final handledByPrevious = previousPlatform?.call(error, stack);
      return handledByPrevious ?? true;
    };

    unawaited(
      Future<void>.delayed(_startupFlushDelay, flushQueue).catchError((_) {}),
    );
  }

  /// Hatayı temizleyip gönderir; gönderilemezse yerel kuyruğa yazar. Asla hata fırlatmaz.
  Future<void> report(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? errorType,
    String? message,
    String? route,
  }) async {
    if (!isActive || _building) return;
    try {
      final Map<String, dynamic>? payload = await _prepare(
        error,
        stack,
        fatal: fatal,
        errorType: errorType,
        message: message,
        route: route,
      );
      if (payload == null) return;
      final result = await _post(payload);
      if (result == _SendResult.retryLater) {
        await _enqueue(payload);
      } else if (result == _SendResult.sent) {
        // Ağ çalışıyor: kuyrukta bekleyenler varsa gönder.
        unawaited(flushQueue());
      }
    } catch (_) {
      // Raporlama hatası yutulur (döngü yok).
    }
  }

  Future<Map<String, dynamic>?> _prepare(
    Object error,
    StackTrace? stack, {
    required bool fatal,
    String? errorType,
    String? message,
    String? route,
  }) async {
    // Yeniden giriş koruması: temizleme sırasında tetiklenecek bir hata yeni rapor üretmez.
    _building = true;
    final String type;
    final String text;
    final String trace;
    try {
      type = _cleanType(errorType ?? _safe(() => error.runtimeType));
      text = CrashSanitizer.sanitize(
        message ?? _safe(error.toString),
        maxLength: 500,
      );
      trace = CrashSanitizer.sanitize(
        _safe(() => stack?.toString() ?? ''),
        maxLength: 8000,
      );
    } finally {
      _building = false;
    }

    final now = _now();
    if (!_admit(type, text, trace, now)) return null;

    final info = await _appInfoLoader();
    final id = await _loadInstallId();
    final cleanRoute = (route ?? currentRoute);
    return <String, dynamic>{
      'install_id': id,
      'app_version': info.version,
      'build': info.build,
      'platform': _platform(),
      'os_version': _osVersionText(),
      'error_type': type,
      'message': text,
      'stack': trace,
      'fatal': fatal,
      'occurred_at': now.toUtc().toIso8601String(),
      if (cleanRoute != null && cleanRoute.trim().isNotEmpty)
        'route': CrashSanitizer.sanitize(
          cleanRoute.trim().replaceAll(RegExp(r'\d{4,}'), '#'),
          maxLength: 100,
        ),
    };
  }

  /// Hız ve tekrar sınırı: aynı parmak izi [dedupeWindow] içinde bir kez, saatte en çok
  /// [maxReportsPerHour] yeni rapor.
  bool _admit(String type, String message, String stack, DateTime now) {
    final hourAgo = now.subtract(const Duration(hours: 1));
    _recentSends.removeWhere((t) => t.isBefore(hourAgo));
    _recentFingerprints.removeWhere((_, t) => now.difference(t) > dedupeWindow);

    final firstLine = message.split('\n').first;
    final topFrame = stack.split('\n').firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    final fingerprint = '$type|$firstLine|$topFrame';
    if (_recentFingerprints.containsKey(fingerprint)) return false;
    if (_recentSends.length >= maxReportsPerHour) return false;
    _recentFingerprints[fingerprint] = now;
    _recentSends.add(now);
    return true;
  }

  Uri get _endpoint {
    final base = (_baseUrl ?? build_config.apiBaseUrl).replaceAll(
      RegExp(r'/+$'),
      '',
    );
    return Uri.parse('$base/public/client-errors');
  }

  Future<_SendResult> _post(Map<String, dynamic> payload) async {
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      final code = response.statusCode;
      if (code >= 200 && code < 300) return _SendResult.sent;
      if (code == 408 || code == 429 || code >= 500) {
        return _SendResult.retryLater;
      }
      // Diğer 4xx: yük reddedildi; yeniden göndermek anlamsız.
      return _SendResult.drop;
    } catch (_) {
      return _SendResult.retryLater;
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Yerel kuyruktaki raporları sırayla göndermeyi dener (turda en çok [maxFlushPerRun]). İlk geçici
  /// hatada durur; kalıcı reddedilenler (4xx) kuyruktan atılır.
  Future<void> flushQueue() async {
    if (!isActive || _flushing) return;
    _flushing = true;
    try {
      for (var i = 0; i < maxFlushPerRun; i++) {
        final next = await _peek();
        if (next == null) break;
        final result = await _post(next);
        if (result == _SendResult.retryLater) break;
        await _removeFirst();
      }
    } catch (_) {
      // Sessiz.
    } finally {
      _flushing = false;
    }
  }

  // --- yerel kuyruk (SharedPreferences, sıralı erişim) ---

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lockTail = _lockTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    try {
      await _locked(() async {
        final prefs = await _prefsLoader();
        final list = List<String>.of(
          prefs.getStringList(queueKey) ?? const <String>[],
        )..add(jsonEncode(payload));
        while (list.length > maxQueue) {
          list.removeAt(0);
        }
        await prefs.setStringList(queueKey, list);
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _peek() async {
    try {
      return await _locked<Map<String, dynamic>?>(() async {
        final prefs = await _prefsLoader();
        final list = List<String>.of(
          prefs.getStringList(queueKey) ?? const <String>[],
        );
        while (list.isNotEmpty) {
          try {
            final decoded = jsonDecode(list.first);
            if (decoded is Map<String, dynamic>) return decoded;
          } catch (_) {}
          list.removeAt(0); // bozuk kayıt atılır
          await prefs.setStringList(queueKey, list);
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeFirst() async {
    try {
      await _locked(() async {
        final prefs = await _prefsLoader();
        final list = List<String>.of(
          prefs.getStringList(queueKey) ?? const <String>[],
        );
        if (list.isNotEmpty) {
          list.removeAt(0);
          await prefs.setStringList(queueKey, list);
        }
      });
    } catch (_) {}
  }

  /// Yerel kuyruğun anlık kopyası (testler ve tanılama için).
  @visibleForTesting
  Future<List<Map<String, dynamic>>> debugQueue() async {
    final prefs = await _prefsLoader();
    return <Map<String, dynamic>>[
      for (final raw in prefs.getStringList(queueKey) ?? const <String>[])
        jsonDecode(raw) as Map<String, dynamic>,
    ];
  }

  // --- kimlik ve ortam ---

  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Cihaz başına rastgele UUID (kişisel veri değildir; hesaba bağlanmaz).
  Future<String> _loadInstallId() async {
    final cached = _installId;
    if (cached != null) return cached;
    String? stored;
    SharedPreferences? prefs;
    try {
      prefs = await _prefsLoader();
      stored = prefs.getString(installIdKey);
    } catch (_) {}
    if (stored != null && _uuidV4.hasMatch(stored)) {
      return _installId = stored;
    }
    final fresh = generateUuidV4();
    try {
      await prefs?.setString(installIdKey, fresh);
    } catch (_) {}
    return _installId = fresh;
  }

  /// RFC 4122 sürüm 4 UUID (güvenli rastgele).
  static String generateUuidV4([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  String _platform() {
    final override = _platformName;
    if (override != null) return override;
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'other',
    };
  }

  String _osVersionText() {
    final override = _osVersion;
    if (override != null) return override;
    if (kIsWeb) return '';
    try {
      return CrashSanitizer.sanitize(
        Platform.operatingSystemVersion,
        maxLength: 64,
      );
    } catch (_) {
      return '';
    }
  }

  static String _safe(Object? Function() read) {
    try {
      return read()?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _cleanType(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_$<>.,? ]'), '');
    final text = cleaned.trim();
    if (text.isEmpty) return 'Error';
    return text.length > 80 ? text.substring(0, 80) : text;
  }
}
