import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:site_kapi_kontrol/config/app_config.dart' as build_config;
import 'package:site_kapi_kontrol/models/app_config.dart';

/// `major.minor.patch` sürüm numarası (docs/PLATFORM_SATISA_HAZIRLIK.md §1.1).
///
/// Sunucu sözleşmesiyle aynı kural: yalnızca üç sayısal bileşen karşılaştırılır; build numarası
/// (`+N`) ve ön sürüm eki (`-beta`) yok sayılır. Ayrıştırılamayan sürüm `null` döner ve çağıranlar
/// bunu "karşılaştırma yapma" (zorunlu güncelleme dayatma) olarak yorumlar.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// `1.2.3`, `1.2.3+4`, `v1.2`, `1.2.3-beta.1` biçimlerini kabul eder. Geçersizse `null`.
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    final dash = text.indexOf('-');
    if (dash >= 0) text = text.substring(0, dash);
    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      if (!RegExp(r'^\d{1,9}$').hasMatch(part)) return null;
      numbers.add(int.parse(part));
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// [current] sürümü [other]'dan KESİN olarak eski mi? İkisinden biri ayrıştırılamazsa `false`
/// (şüphede kullanıcıyı engelleme).
bool isVersionOlder(String? current, String? other) {
  final a = AppVersion.tryParse(current);
  final b = AppVersion.tryParse(other);
  if (a == null || b == null) return false;
  return a < b;
}

/// Cihaza kurulu uygulamanın sürümü.
@immutable
class InstalledAppInfo {
  const InstalledAppInfo({required this.version, required this.build});

  /// Örn. `1.0.0` (pubspec `version` alanının `+` öncesi).
  final String version;

  /// Örn. `1` (pubspec `version` alanının `+` sonrası).
  final String build;
}

InstalledAppInfo? _cachedInstalled;

/// Kurulu sürümü `package_info_plus` ile okur (bir kez; sonuç bellekte tutulur). Okuma başarısız olursa
/// derleme zamanı sabitlerine ([build_config.AppConfig]) düşer; asla hata fırlatmaz.
Future<InstalledAppInfo> loadInstalledAppInfo({bool refresh = false}) async {
  final cached = _cachedInstalled;
  if (cached != null && !refresh) return cached;
  InstalledAppInfo info;
  try {
    final package = await PackageInfo.fromPlatform();
    final version = package.version.trim();
    final build = package.buildNumber.trim();
    info = InstalledAppInfo(
      version: version.isEmpty ? build_config.AppConfig.appVersion : version,
      build: build.isEmpty ? '${build_config.AppConfig.buildNumber}' : build,
    );
  } catch (_) {
    info = InstalledAppInfo(
      version: build_config.AppConfig.appVersion,
      build: '${build_config.AppConfig.buildNumber}',
    );
  }
  return _cachedInstalled = info;
}

/// Yalnız testler: bellekteki kurulu sürümü sıfırlar.
@visibleForTesting
void resetInstalledAppInfoForTesting() => _cachedInstalled = null;

/// Açılış kapısının vereceği karar.
enum AppGateStatus {
  /// Uygulama normal açılır.
  open,

  /// Sunucu bakım modunda: bakım ekranı gösterilir.
  maintenance,

  /// Kurulu sürüm `min_supported_version` altında: tam ekran güncelleme zorunluluğu.
  updateRequired,
}

@immutable
class AppGateDecision {
  const AppGateDecision({
    required this.status,
    this.config,
    this.storeUrl,
    this.softUpdateVersion,
  });

  static const AppGateDecision open = AppGateDecision(
    status: AppGateStatus.open,
  );

  final AppGateStatus status;

  /// Kararın dayandığı yapılandırma (yapılandırma yüklenemediyse `null`).
  final AppConfig? config;

  /// Bu platformun mağaza bağlantısı (yalnız `https://`; tanımsızsa `null`).
  final String? storeUrl;

  /// Kapatılabilir yumuşak uyarı için en son sürüm: kurulu sürüm bundan eskiyse dolu, aksi hâlde `null`.
  /// Yalnız [status] == [AppGateStatus.open] iken anlamlıdır.
  final String? softUpdateVersion;

  bool get blocked => status != AppGateStatus.open;
}

/// Platforma göre mağaza bağlantısı. Yalnız `https://` bağlantılar kabul edilir (sunucu da böyle
/// doğrular); iOS ve Android dışındaki platformlarda `null`.
String? storeUrlFor(AppConfig config, TargetPlatform platform) {
  final raw = switch (platform) {
    TargetPlatform.android => config.updateUrlAndroid,
    TargetPlatform.iOS => config.updateUrlIos,
    _ => null,
  };
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return null;
  }
  return text;
}

/// Açılış kapısı kararı (saf işlev). Öncelik: bakım > zorunlu güncelleme > yumuşak uyarı > açık.
///
/// [config] `null` ise (yapılandırma yüklenemedi) uygulama ENGELLENMEZ.
AppGateDecision evaluateAppGate({
  required String installedVersion,
  required AppConfig? config,
  required TargetPlatform platform,
}) {
  if (config == null) return AppGateDecision.open;
  final storeUrl = storeUrlFor(config, platform);
  if (config.maintenanceActive) {
    return AppGateDecision(
      status: AppGateStatus.maintenance,
      config: config,
      storeUrl: storeUrl,
    );
  }
  if (isVersionOlder(installedVersion, config.minSupportedVersion)) {
    return AppGateDecision(
      status: AppGateStatus.updateRequired,
      config: config,
      storeUrl: storeUrl,
    );
  }
  final soft = isVersionOlder(installedVersion, config.latestVersion)
      ? AppVersion.tryParse(config.latestVersion)?.toString()
      : null;
  return AppGateDecision(
    status: AppGateStatus.open,
    config: config,
    storeUrl: storeUrl,
    softUpdateVersion: soft,
  );
}
