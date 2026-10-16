import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/config/app_config.dart' as build_config;
import 'package:site_kapi_kontrol/models/app_config.dart';

/// `GET /public/app-config` istemcisi (docs/PLATFORM_SATISA_HAZIRLIK.md §1.1 / §1.8).
///
/// Kurallar:
/// - Kimliksiz çağrı; 4 sn zaman aşımı.
/// - Her hata (ağ, zaman aşımı, 4xx/5xx, bozuk JSON) sessizce `null` döner: uygulama açılmaya
///   devam eder, kapı/destek bilgisi yalnızca "yoksa gösterme" olur.
/// - Son başarılı yanıt bellekte tutulur ([current]); aynı anda yapılan çağrılar tek isteği paylaşır.
class AppConfigService {
  AppConfigService({
    http.Client? client,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 4),
    Duration cacheTtl = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _client = client,
       _baseUrl = baseUrl,
       _timeout = timeout,
       _cacheTtl = cacheTtl,
       _now = now ?? DateTime.now;

  /// Uygulama genelinde paylaşılan örnek.
  static final AppConfigService instance = AppConfigService();

  final http.Client? _client;
  final String? _baseUrl;
  final Duration _timeout;
  final Duration _cacheTtl;
  final DateTime Function() _now;

  AppConfig? _current;
  DateTime? _loadedAt;
  Future<AppConfig?>? _inFlight;

  /// Son başarılı yükleme (hiç başarılı yükleme yoksa `null`).
  AppConfig? get current => _current;

  /// Yapılandırmayı getirir.
  ///
  /// [force] `false` iken bellekteki yanıt tazeyse (15 dk) ağa gitmeden onu döndürür. Ağ/sunucu hatasında
  /// `null` döner (önceki başarılı yanıt [current] içinde kalır).
  Future<AppConfig?> load({bool force = false}) {
    if (!force) {
      final cached = _current;
      final at = _loadedAt;
      if (cached != null && at != null && _now().difference(at) < _cacheTtl) {
        return Future<AppConfig?>.value(cached);
      }
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<AppConfig?> _fetch() async {
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final base = (_baseUrl ?? build_config.apiBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      );
      final response = await client
          .get(
            Uri.parse('$base/public/app-config'),
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final config = AppConfig.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      _current = config;
      _loadedAt = _now();
      return config;
    } catch (error) {
      // Yapılandırma ZORUNLU değildir: hata sessizce yutulur (ayrıntı yalnız hata ayıklamada).
      if (kDebugMode) debugPrint('AppConfigService: yüklenemedi (${error.runtimeType})');
      return null;
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Yalnız testler: belleği sıfırlar.
  @visibleForTesting
  void resetForTesting() {
    _current = null;
    _loadedAt = null;
    _inFlight = null;
  }
}
