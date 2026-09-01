const String apiBaseUrl = 'https://api.gudeteknoloji.com.tr';

class AppConfig {
  AppConfig._();

  static const String appName = 'Site Kapı Kontrol';
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;
  static const String baseUrl = apiBaseUrl;

  static String get versionDisplay => 'v$appVersion (Build $buildNumber)';
}
