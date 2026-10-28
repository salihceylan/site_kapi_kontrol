import 'package:flutter/foundation.dart';

// K8 (P1-16): YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır.
//  - Yetenek: hangi modülün sitede açık olduğu (sunucu kataloğu, `MySiteModules.modules`); temel (core) modüller her sitede açık kalır.
//  - Menü yerleşimi: açık yeteneklerden hangilerinin ana menüde (çekmece + Panel vitrini) öne çıkacağı = site başına "kompakt menü" kümesi.
//    Kümede olmayan açık modül KAYBOLMAZ: "Tüm işlemler" ekranından erişilir.
// Bu dosya yalnız veri modelidir; menü kuralı `ui/helpers/menu_layout.dart`, sunucu sözleşmesi `docs/PLATFORM_MENU_KATMANI.md`.

/// `GET /app/my-modules` site nesnesindeki `menu_layout`: bu sitede ana menüde öne çıkan modül kodları.
@immutable
class SiteMenuLayout {
  const SiteMenuLayout({this.compactModules = const <String>[], this.customized = false});

  /// Ana menüde öne çıkan modül kodları (sunucu katalog sırasıyla).
  final List<String> compactModules;

  /// Yöneticinin seçimi mi (true), yönetim türü önerilerinden türetilen varsayılan mı (false)?
  final bool customized;

  bool features(String code) => compactModules.contains(code);

  /// Sunucu nesnesinden. Alan yoksa ya da bozuksa (eski sunucu) null: çağıran menüyü KISALTMAZ (her şey öne çıkar).
  static SiteMenuLayout? tryParse(Object? json) {
    if (json is! Map) return null;
    final raw = json['compact_modules'];
    if (raw is! List) return null;
    return SiteMenuLayout(
      compactModules: List<String>.unmodifiable(raw.whereType<String>()),
      customized: json['customized'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SiteMenuLayout && other.customized == customized && listEquals(other.compactModules, compactModules);

  @override
  int get hashCode => Object.hash(customized, Object.hashAll(compactModules));
}

/// Menü düzeni ekranındaki bir modül satırı (`GET /manager/sites/:siteCode/menu-layout` -> `modules[]`).
@immutable
class MenuLayoutModule {
  const MenuLayoutModule({
    required this.code,
    required this.name,
    this.description = '',
    this.core = false,
    this.enabled = false,
    this.compact = false,
    this.recommended = false,
  });

  final String code;
  final String name;
  final String description;

  /// Temel modül: her sitede açık, kapatılamaz (yetenek katmanı). Menüde öne çıkması ayrıca seçilir.
  final bool core;

  /// YETENEK: modül bu sitede açık mı? (Bu ekran değiştirmez.)
  final bool enabled;

  /// YERLEŞİM: ana menüde öne çıkıyor mu?
  final bool compact;

  /// Sitenin yönetim türü için önerilen modül mü?
  final bool recommended;

  factory MenuLayoutModule.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    return MenuLayoutModule(
      code: code,
      name: json['name']?.toString().trim().isNotEmpty == true ? json['name'].toString().trim() : code,
      description: json['description']?.toString() ?? '',
      core: json['core'] == true,
      enabled: json['enabled'] == true,
      compact: json['compact'] == true,
      recommended: json['recommended'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MenuLayoutModule &&
      other.code == code &&
      other.name == name &&
      other.description == description &&
      other.core == core &&
      other.enabled == enabled &&
      other.compact == compact &&
      other.recommended == recommended;

  @override
  int get hashCode => Object.hash(code, name, description, core, enabled, compact, recommended);
}

/// Bir sitenin menü düzeni (yönetici ekranı): seçili küme, varsayılan küme ve modül satırları.
@immutable
class SiteMenuLayoutState {
  const SiteMenuLayoutState({
    required this.siteCode,
    required this.siteName,
    this.managementTypeLabel = '',
    this.customized = false,
    this.compactModules = const <String>[],
    this.defaultCompactModules = const <String>[],
    this.modules = const <MenuLayoutModule>[],
  });

  final int siteCode;
  final String siteName;
  final String managementTypeLabel;
  final bool customized;
  final List<String> compactModules;
  final List<String> defaultCompactModules;
  final List<MenuLayoutModule> modules;

  factory SiteMenuLayoutState.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        raw is List ? List<String>.unmodifiable(raw.whereType<String>()) : const <String>[];
    final rawModules = json['modules'];
    return SiteMenuLayoutState(
      siteCode: (json['site_code'] is num ? (json['site_code'] as num).toInt() : int.tryParse('${json['site_code']}')) ?? 0,
      siteName: json['site_name']?.toString() ?? '',
      managementTypeLabel: json['management_type_label']?.toString() ?? '',
      customized: json['customized'] == true,
      compactModules: strings(json['compact_modules']),
      defaultCompactModules: strings(json['default_compact_modules']),
      modules: rawModules is List
          ? List<MenuLayoutModule>.unmodifiable(
              rawModules.whereType<Map>().map((m) => MenuLayoutModule.fromJson(Map<String, dynamic>.from(m))),
            )
          : const <MenuLayoutModule>[],
    );
  }
}
