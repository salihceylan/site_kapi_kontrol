const String _defaultApiBaseUrl = 'https://api.gudeteknoloji.com.tr';

class AppConfig {
  AppConfig._();

  static const String appName = 'Site Kapı Kontrol';
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  /// Can be overridden at build-time via `--dart-define=API_BASE_URL=https://...`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static String get versionDisplay => 'v$appVersion (Build $buildNumber)';
}

/// Backwards compatibility top-level alias
const String apiBaseUrl = AppConfig.baseUrl;
