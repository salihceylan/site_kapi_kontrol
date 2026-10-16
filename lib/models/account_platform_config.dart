// Süper kullanıcı platform ayarları (docs/PLATFORM_SATISA_HAZIRLIK.md §1.2).
//
// `GET/PUT /admin/platform-config`; yalnız `super_user`. Boş dize = ayarsız. PUT KISMİ güncellemedir: yalnız
// değişen alanlar, aynı iç içe biçimde (`{"app":{"latest_version":"1.2.0"}}`) gönderilir.
//
// Doğrulama (sözleşme): sürümler `^\d+\.\d+\.\d+$`; URL'ler yalnız `https://`; e-posta biçimi; uzunluk
// sınırları. İstemci sınırları sunucununkinden gevşek olmamalı ama sunucu yine de nihai hakemdir.

/// Alan uzunluk sınırları (karakter).
abstract final class PlatformFieldLimits {
  static const int version = 20;
  static const int url = 500;
  static const int message = 500;
  static const int hours = 200;
  static const int email = 254;
  static const int phone = 30;
  static const int companyName = 200;
  static const int companyAddress = 500;
  static const int mersis = 16;
}

/// Uygulama sürümü ve bakım ayarları (`app.*`).
class PlatformAppConfig {
  const PlatformAppConfig({
    this.minSupportedVersion = '',
    this.latestVersion = '',
    this.updateUrlAndroid = '',
    this.updateUrlIos = '',
    this.maintenanceActive = false,
    this.maintenanceMessage = '',
  });

  final String minSupportedVersion;
  final String latestVersion;
  final String updateUrlAndroid;
  final String updateUrlIos;
  final bool maintenanceActive;
  final String maintenanceMessage;

  factory PlatformAppConfig.fromJson(Object? raw) {
    final json = _map(raw);
    return PlatformAppConfig(
      minSupportedVersion: _text(json['min_supported_version']),
      latestVersion: _text(json['latest_version']),
      updateUrlAndroid: _text(json['update_url_android']),
      updateUrlIos: _text(json['update_url_ios']),
      maintenanceActive: json['maintenance_active'] == true,
      maintenanceMessage: _text(json['maintenance_message']),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'min_supported_version': minSupportedVersion,
    'latest_version': latestVersion,
    'update_url_android': updateUrlAndroid,
    'update_url_ios': updateUrlIos,
    'maintenance_active': maintenanceActive,
    'maintenance_message': maintenanceMessage,
  };
}

/// Destek iletişim bilgileri (`support.*`).
class PlatformSupportConfig {
  const PlatformSupportConfig({
    this.email = '',
    this.phone = '',
    this.hours = '',
    this.webUrl = '',
  });

  final String email;
  final String phone;
  final String hours;
  final String webUrl;

  factory PlatformSupportConfig.fromJson(Object? raw) {
    final json = _map(raw);
    return PlatformSupportConfig(
      email: _text(json['email']),
      phone: _text(json['phone']),
      hours: _text(json['hours']),
      webUrl: _text(json['web_url']),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'email': email,
    'phone': phone,
    'hours': hours,
    'web_url': webUrl,
  };
}

/// Şirket ve yasal bilgiler (`legal.*`).
class PlatformLegalConfig {
  const PlatformLegalConfig({
    this.companyName = '',
    this.companyAddress = '',
    this.mersisNo = '',
    this.kepAddress = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.enforceConsents = false,
  });

  final String companyName;
  final String companyAddress;
  final String mersisNo;
  final String kepAddress;
  final String contactEmail;
  final String contactPhone;

  /// true: eksik/eski onayı olan kullanıcı kayıt ve site başvurusunda reddedilir (yalnız tamamlanmış belgeler).
  final bool enforceConsents;

  factory PlatformLegalConfig.fromJson(Object? raw) {
    final json = _map(raw);
    return PlatformLegalConfig(
      companyName: _text(json['company_name']),
      companyAddress: _text(json['company_address']),
      mersisNo: _text(json['mersis_no']),
      kepAddress: _text(json['kep_address']),
      contactEmail: _text(json['contact_email']),
      contactPhone: _text(json['contact_phone']),
      enforceConsents: json['enforce_consents'] == true,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'company_name': companyName,
    'company_address': companyAddress,
    'mersis_no': mersisNo,
    'kep_address': kepAddress,
    'contact_email': contactEmail,
    'contact_phone': contactPhone,
    'enforce_consents': enforceConsents,
  };
}

/// Platform ayarlarının tamamı.
class PlatformConfig {
  const PlatformConfig({
    this.app = const PlatformAppConfig(),
    this.support = const PlatformSupportConfig(),
    this.legal = const PlatformLegalConfig(),
  });

  final PlatformAppConfig app;
  final PlatformSupportConfig support;
  final PlatformLegalConfig legal;

  /// Eksik / null / yanlış tipli alanlara dayanıklıdır (eksik metin = boş, eksik anahtar = kapalı).
  factory PlatformConfig.fromJson(Map<String, dynamic> json) {
    return PlatformConfig(
      app: PlatformAppConfig.fromJson(json['app']),
      support: PlatformSupportConfig.fromJson(json['support']),
      legal: PlatformLegalConfig.fromJson(json['legal']),
    );
  }

  /// Yanıt `app` / `support` / `legal` bölümlerinden en az birini taşıyor mu? (PUT yanıtı güncel ayarları
  /// içermiyorsa çağıran GET ile tazeler.)
  static bool looksLikeConfig(Map<String, dynamic> json) =>
      json['app'] is Map || json['support'] is Map || json['legal'] is Map;

  Map<String, Map<String, Object>> toJson() => <String, Map<String, Object>>{
    'app': app.toJson(),
    'support': support.toJson(),
    'legal': legal.toJson(),
  };

  /// [base]'e göre DEĞİŞEN alanlar: PUT kısmi güncelleme gövdesi. Metinler kırpılarak karşılaştırılır ve
  /// kırpılmış hâliyle gönderilir. Değişiklik yoksa boş harita.
  Map<String, Map<String, Object>> patchAgainst(PlatformConfig base) {
    final result = <String, Map<String, Object>>{};
    final mine = toJson();
    final theirs = base.toJson();
    for (final section in mine.keys) {
      final changed = <String, Object>{};
      for (final entry in mine[section]!.entries) {
        final value = entry.value is String ? (entry.value as String).trim() : entry.value;
        final old = theirs[section]![entry.key];
        final oldValue = old is String ? old.trim() : old;
        if (value != oldValue) changed[entry.key] = value;
      }
      if (changed.isNotEmpty) result[section] = changed;
    }
    return result;
  }

  /// Kırpılmış metinlerle eşdeğer kopya (karşılaştırma ve kaydetme için).
  PlatformConfig trimmed() => PlatformConfig.fromJson(<String, dynamic>{
    'app': app.toJson(),
    'support': support.toJson(),
    'legal': legal.toJson(),
  });

  /// İki yapılandırma kırpılmış metinlerle aynı mı?
  bool sameAs(PlatformConfig other) => patchAgainst(other).isEmpty;
}

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

String _text(Object? value) => value is String ? value.trim() : '';

// ---------------------------------------------------------------------------
// Doğrulayıcılar. Sunucunun kurallarını (server/src/modules/platform_config_service.js) aynalar; sunucu
// yine de nihai hakemdir. Hepsi geçerliyse (ya da alan boşsa: "ayarsız") null döner.
// ---------------------------------------------------------------------------

final RegExp _versionPattern = RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$');
final RegExp _phonePattern = RegExp(r'^\+?[0-9 ()\-./]{6,29}$');
final RegExp _emailForbidden = RegExp(r'[<>"' "'" r'`\\,;]');
final RegExp _urlForbidden = RegExp(r'[\s"' "'" r'<>`\\]');
// Yasal belgelere yer tutucu olarak girer: Markdown bağlantı / HTML / kod / kaçış karakterleri yasak.
final RegExp _legalMarkup = RegExp(r'[\[\]<>`\\]|\*\*');
final RegExp _legalLeadingMarker = RegExp(r'^[#>*+\-]');

String? _tooLong(String value, int max, String label) =>
    value.runes.length > max ? '$label en çok $max karakter olabilir.' : null;

/// Sürüm: boş (ayarsız) ya da `major.minor.patch`.
String? validatePlatformVersion(String? raw, String label) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  if (!_versionPattern.hasMatch(value)) {
    return '$label 1.2.3 biçiminde olmalı (üç sayı, noktalarla).';
  }
  return null;
}

/// URL: boş ya da yalnız `https://` (sunucu `http://` kabul etmez); boşluk / tırnak / `<>` içermez, kullanıcı
/// adı-parola taşımaz.
String? validatePlatformUrl(String? raw, String label) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  final long = _tooLong(value, PlatformFieldLimits.url, label);
  if (long != null) return long;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !RegExp(r'^https://', caseSensitive: false).hasMatch(value) ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      _urlForbidden.hasMatch(value)) {
    return '$label https:// ile başlayan geçerli bir adres olmalı (boşluk ve özel işaret içeremez).';
  }
  return null;
}

/// E-posta: boş ya da `ad@alan.uzantı`.
String? validatePlatformEmail(String? raw, String label) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  final long = _tooLong(value, PlatformFieldLimits.email, label);
  if (long != null) return long;
  final at = value.indexOf('@');
  final valid =
      value.length >= 5 &&
      !RegExp(r'\s').hasMatch(value) &&
      !value.contains('..') &&
      at >= 1 &&
      at == value.lastIndexOf('@') &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(value) &&
      !_emailForbidden.hasMatch(value);
  return valid ? null : '$label geçerli bir e-posta adresi olmalı.';
}

/// Telefon: boş ya da rakam, boşluk, `+`, `-`, `(`, `)`, `.`, `/` (7-15 rakam).
String? validatePlatformPhone(String? raw, String label) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '').length;
  if (!_phonePattern.hasMatch(value) || digits < 7 || digits > 15) {
    return '$label geçerli bir telefon numarası olmalı (örn. +90 212 000 00 00).';
  }
  return null;
}

/// MERSİS numarası: boş ya da 16 rakam (boşluk ve tireler yok sayılır).
String? validatePlatformMersis(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  final compact = value.replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^[0-9]{16}$').hasMatch(compact)) {
    return 'MERSİS numarası 16 haneli olmalı.';
  }
  return null;
}

/// Serbest metin: yalnız uzunluk sınırı (sunucu satır sonlarını boşluğa çevirir).
String? validatePlatformText(String? raw, int max, String label) =>
    _tooLong((raw ?? '').trim(), max, label);

/// Yasal belgelere girecek metin (şirket unvanı / adresi): uzunluk + Markdown / HTML ayırıcı yasağı.
String? validatePlatformLegalText(String? raw, int max, String label) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  final long = _tooLong(value, max, label);
  if (long != null) return long;
  if (_legalMarkup.hasMatch(value) || _legalLeadingMarker.hasMatch(value)) {
    return '$label köşeli parantez, < >, ters eğik çizgi, ters tırnak veya ** içeremez; '
        '#, -, +, *, > ile başlayamaz.';
  }
  return null;
}

/// `a.b.c` sürümlerini karşılaştırır: a < b ise negatif, eşitse 0, a > b ise pozitif. Biçim geçersizse null.
int? comparePlatformVersions(String a, String b) {
  List<int>? parse(String v) {
    final t = v.trim();
    if (!_versionPattern.hasMatch(t)) return null;
    return t.split('.').map(int.parse).toList();
  }

  final pa = parse(a);
  final pb = parse(b);
  if (pa == null || pb == null) return null;
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}
