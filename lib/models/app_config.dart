/// Sunucudan gelen uygulama yapılandırması (`GET /public/app-config`).
///
/// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.1 / §1.8. Tüm alanlar eksik, `null` ya da
/// beklenmeyen türde gelebilir; ayrıştırma ASLA hata fırlatmaz (kapı/destek bilgisi uygulamanın
/// açılmasını engellememelidir).
///
/// Not: `lib/config/app_config.dart` içinde derleme-zamanı sabitlerini tutan başka bir `AppConfig`
/// sınıfı vardır. İkisini aynı dosyada kullanırken `import '…/models/app_config.dart' as remote;`
/// gibi bir önek kullanın.
class AppConfig {
  const AppConfig({
    this.minSupportedVersion = '0.0.0',
    this.latestVersion = '0.0.0',
    this.updateUrlAndroid,
    this.updateUrlIos,
    this.maintenanceActive = false,
    this.maintenanceMessage,
    this.supportEmail,
    this.supportPhone,
    this.supportHours,
    this.supportWebUrl,
    this.legalEnforced = false,
    this.serverTime,
  });

  /// Bu sürümün altındaki istemciler zorunlu güncellemeye yönlendirilir (`major.minor.patch`).
  final String minSupportedVersion;

  /// Mağazadaki en son sürüm; istemci bunun altındaysa kapatılabilir bir uyarı gösterilir.
  final String latestVersion;
  final String? updateUrlAndroid;
  final String? updateUrlIos;
  final bool maintenanceActive;
  final String? maintenanceMessage;
  final String? supportEmail;
  final String? supportPhone;
  final String? supportHours;
  final String? supportWebUrl;
  final bool legalEnforced;

  /// Sunucu saati (bilgi amaçlı; yoksa/bozuksa `null`).
  final DateTime? serverTime;

  /// Destek kanallarından en az biri tanımlı mı?
  bool get hasSupportInfo =>
      supportEmail != null ||
      supportPhone != null ||
      supportHours != null ||
      supportWebUrl != null;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final maintenance = _map(json['maintenance']);
    final support = _map(json['support']);
    return AppConfig(
      minSupportedVersion: _text(json['min_supported_version']) ?? '0.0.0',
      latestVersion: _text(json['latest_version']) ?? '0.0.0',
      updateUrlAndroid: _text(json['update_url_android']),
      updateUrlIos: _text(json['update_url_ios']),
      maintenanceActive: _bool(maintenance['active']),
      maintenanceMessage: _text(maintenance['message']),
      supportEmail: _text(support['email']),
      supportPhone: _text(support['phone']),
      supportHours: _text(support['hours']),
      supportWebUrl: _text(support['web_url']),
      legalEnforced: _bool(json['legal_enforced']),
      serverTime: _time(json['server_time']),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const <String, dynamic>{};
  }

  /// Boşlukları kırpılmış, boş değilse metin; aksi hâlde `null`.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'on' || v == 'yes';
    }
    return false;
  }

  static DateTime? _time(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value.trim());
  }
}
