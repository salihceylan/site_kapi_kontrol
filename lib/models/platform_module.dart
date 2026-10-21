import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';

/// Katalogdaki modül kodları (sunucuda sabit: `server/src/modules/catalog.js`).
abstract final class PlatformModuleCodes {
  static const String doorControl = 'door_control';
  static const String people = 'people';
  static const String announcements = 'announcements';
  static const String finance = 'finance';

  /// Belgeler (dosya deposu; Faz 3b-A). Varsayılan KAPALI.
  static const String documents = 'documents';
  static const String reservation = 'reservation';
  static const String workTracking = 'work_tracking';
  static const String metering = 'metering';
  static const String onlinePayment = 'online_payment';

  /// Anket ve Oylama (F11.01). Varsayılan KAPALI.
  static const String survey = 'survey';
  /// Ziyaretçi ve Kargo (kapı kaydı; F11.03). Varsayılan KAPALI.
  static const String visitorLog = 'visitor_log';
  /// Firma ve Sözleşme Takibi. Varsayılan KAPALI.
  static const String contracts = 'contracts';
  /// Karar Defteri (yönetim / genel / denetim kurulu kararları). Varsayılan KAPALI.
  static const String decisionBook = 'decision_book';

  /// İşletme Projesi (bütçe). Varsayılan KAPALI.
  static const String budget = 'budget';
}

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

int _asInt(Object? raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

/// Bir platform modülü: katalog satırı (`/app/modules/catalog`) ya da bir sitenin modül durumu
/// (`/manager/sites/:siteCode/modules`). Katalogda yalnız `code/name/description/core/status` gelir;
/// kalan alanlar için sunucudaki hesapla aynı varsayılanlar kullanılır.
@immutable
class PlatformModule {
  const PlatformModule({
    required this.code,
    required this.name,
    this.description = '',
    this.core = false,
    this.status = 'available',
    this.enabled = false,
    this.toggleable = false,
    bool? canToggle,
    this.requestStatus,
    this.updatedAt,
    this.updatedBy,
    this.recommended = false,
  }) : canToggle = canToggle ?? toggleable;

  final String code;
  final String name;
  final String description;

  /// Çekirdek modül: her sitede hep açık, kapatılamaz.
  final bool core;

  /// `available` ya da `coming_soon`.
  final String status;

  /// Bu sitede hesaplanmış açık/kapalı durumu.
  final bool enabled;

  /// Katalog özelliği: açılıp kapatılabilir bir modül mü (`!core && status == available`).
  final bool toggleable;

  /// ÇAĞIRAN bu modülü şimdi anahtarla açıp kapatabilir mi? Faz 1.1: yalnız süper kullanıcı VE modül
  /// [toggleable] ise true (site yöneticisi modül TALEP eder). Eski sunucuda alan yoksa [toggleable].
  final bool canToggle;

  /// O siteye ait bekleyen modül talebi varsa `"pending"`, yoksa null (eski sunucuda alan yok = null).
  final String? requestStatus;

  /// Bu modül için bekleyen bir talep var mı?
  bool get hasPendingRequest => requestStatus == 'pending';

  final DateTime? updatedAt;
  final String? updatedBy;

  /// Sitenin yönetim türü için ÖNERİLEN modül mü (`recommended`, F9)? Eski sunucuda alan yok = false.
  final bool recommended;

  bool get isAvailable => status == 'available';
  bool get isComingSoon => status == 'coming_soon';

  /// Modül satırı olmayan sitede katalog varsayılanı (sunucudaki `computeModuleEnabled` ile aynı
  /// sıra): `available` olmayan modül KAPALI (çekirdek `people`/`announcements` de, ekranları
  /// gelene dek); çekirdek modül açık; aksi halde yalnız `door_control` AÇIK.
  static bool defaultEnabled(
    String code, {
    bool core = false,
    String status = 'available',
  }) {
    if (status != 'available') return false;
    if (core) return true;
    return code == PlatformModuleCodes.doorControl;
  }

  factory PlatformModule.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final core = json['core'] == true;
    final status = json['status']?.toString() ?? 'available';
    final toggleable = json['toggleable'] is bool
        ? json['toggleable'] as bool
        : (!core && status == 'available');
    return PlatformModule(
      code: code,
      name: json['name']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      core: core,
      status: status,
      enabled: json['enabled'] is bool
          ? json['enabled'] as bool
          : defaultEnabled(code, core: core, status: status),
      toggleable: toggleable,
      canToggle: json['can_toggle'] is bool ? json['can_toggle'] as bool : toggleable,
      requestStatus: json['request_status'] is String &&
              (json['request_status'] as String).trim().isNotEmpty
          ? (json['request_status'] as String).trim()
          : null,
      updatedAt: _parseDate(json['updated_at']),
      updatedBy: json['updated_by']?.toString(),
      recommended: json['recommended'] == true,
    );
  }

  PlatformModule copyWith({
    bool? enabled,
    String? requestStatus,
    bool clearRequestStatus = false,
  }) {
    return PlatformModule(
      code: code,
      name: name,
      description: description,
      core: core,
      status: status,
      enabled: enabled ?? this.enabled,
      toggleable: toggleable,
      canToggle: canToggle,
      requestStatus: clearRequestStatus ? null : (requestStatus ?? this.requestStatus),
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      recommended: recommended,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlatformModule &&
      other.code == code &&
      other.name == name &&
      other.description == description &&
      other.core == core &&
      other.status == status &&
      other.enabled == enabled &&
      other.toggleable == toggleable &&
      other.canToggle == canToggle &&
      other.requestStatus == requestStatus &&
      other.updatedAt == updatedAt &&
      other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(
        code,
        name,
        description,
        core,
        status,
        enabled,
        toggleable,
        canToggle,
        requestStatus,
        updatedAt,
        updatedBy,
      );
}

/// Bir sitenin modül durumu (`GET/PUT /manager/sites/:siteCode/modules...` gövdesi).
@immutable
class SiteModulesState {
  const SiteModulesState({
    required this.siteCode,
    required this.siteName,
    this.managementType = ManagementType.apartmentSite,
    this.managementTypeLabel = 'Apartman ve Site',
    this.modules = const <PlatformModule>[],
    this.managementTerms = ManagementTerms.defaults,
  });

  final int siteCode;
  final String siteName;
  final ManagementType managementType;
  final String managementTypeLabel;
  final List<PlatformModule> modules;

  /// Türün arayüz terimleri (`management_terms`, F9); eski sunucuda varsayılan.
  final ManagementTerms managementTerms;

  PlatformModule? module(String code) {
    for (final m in modules) {
      if (m.code == code) return m;
    }
    return null;
  }

  factory SiteModulesState.fromJson(Map<String, dynamic> json) {
    final type = ManagementType.fromApi(json['management_type']);
    final label = json['management_type_label'];
    final rawModules = json['modules'];
    return SiteModulesState(
      siteCode: _asInt(json['site_code'] ?? json['id']),
      siteName: json['site_name']?.toString() ?? '',
      managementType: type,
      managementTypeLabel:
          label is String && label.trim().isNotEmpty ? label.trim() : type.label,
      modules: rawModules is List
          ? rawModules
              .whereType<Map>()
              .map((m) => PlatformModule.fromJson(Map<String, dynamic>.from(m)))
              .toList(growable: false)
          : const <PlatformModule>[],
      managementTerms: ManagementTerms.fromJson(json['management_terms']),
    );
  }
}

/// `GET /app/my-modules` içindeki bir site: kullanıcının o sitedeki rolü ve modül durumları.
@immutable
class MySiteModules {
  const MySiteModules({
    required this.siteCode,
    required this.siteName,
    this.managementType = ManagementType.apartmentSite,
    this.role = 'resident',
    this.modules = const <String, bool>{},
    this.doorAccess = true,
    this.managementTerms = ManagementTerms.defaults,
    this.recommendedModules = const <String>[],
  });

  final int siteCode;
  final String siteName;
  final ManagementType managementType;

  /// `manager`, `resident`, `board_member` ya da `staff`.
  final String role;

  /// Kullanıcının bu sitede GERÇEK bir kapı erişim yolu var mı (yönetici, daire/sakin, kapı izni)?
  /// Yalnız BOARD_MEMBER/STAFF bağı olanlarda false. Eski sunucuda alan yoksa true (fail-open).
  /// "Geçiş Kontrol kapalı" kararı yalnız bu alanı true olan siteler üzerinden verilir.
  final bool doorAccess;

  /// Katalogdaki tüm kodlar için hesaplanmış açık/kapalı.
  final Map<String, bool> modules;

  /// Türün arayüz terimleri (`management_terms`, F9); eski sunucuda varsayılan.
  final ManagementTerms managementTerms;

  /// Bu tür için önerilen modül kodları (`recommended_modules`, F9); eski sunucuda boş. Bilinmeyen kod
  /// listede kalır, katalogda eşleşmediği için gösterilmez.
  final List<String> recommendedModules;

  /// Kullanıcı bu sitede Yönetim Kurulu / Denetçi (salt okunur) mu?
  bool get isBoardMember => role == 'board_member';

  /// Kod listede yoksa (eski sunucu / yeni modül) katalog varsayılanı.
  bool isEnabled(String code) =>
      modules[code] ?? PlatformModule.defaultEnabled(code);

  factory MySiteModules.fromJson(Map<String, dynamic> json) {
    final rawModules = json['modules'];
    final modules = <String, bool>{};
    if (rawModules is Map) {
      rawModules.forEach((key, value) {
        if (value is bool) modules[key.toString()] = value;
      });
    }
    return MySiteModules(
      siteCode: _asInt(json['site_code'] ?? json['id']),
      siteName: json['site_name']?.toString() ?? '',
      managementType: ManagementType.fromApi(json['management_type']),
      role: json['role']?.toString() ?? 'resident',
      modules: Map<String, bool>.unmodifiable(modules),
      doorAccess: json['door_access'] is bool ? json['door_access'] as bool : true,
      managementTerms: ManagementTerms.fromJson(json['management_terms']),
      recommendedModules: json['recommended_modules'] is List
          ? List<String>.unmodifiable(
              (json['recommended_modules'] as List).whereType<String>(),
            )
          : const <String>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MySiteModules &&
      other.siteCode == siteCode &&
      other.siteName == siteName &&
      other.managementType == managementType &&
      other.role == role &&
      other.doorAccess == doorAccess &&
      mapEquals(other.modules, modules);

  @override
  int get hashCode => Object.hash(
        siteCode,
        siteName,
        managementType,
        role,
        doorAccess,
        Object.hashAllUnordered(
          modules.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}

/// `GET /app/my-modules` yanıtı. Süper kullanıcıda `scope == 'all'` ve site listesi boştur
/// (menüler modüllerden etkilenmez).
@immutable
class MyModulesResult {
  const MyModulesResult({
    this.scope = 'sites',
    this.sites = const <MySiteModules>[],
  });

  final String scope;
  final List<MySiteModules> sites;

  bool get isAll => scope == 'all';

  /// Kullanıcının GERÇEK kapı erişimi olan siteler ([MySiteModules.doorAccess]). "Geçiş Kontrol
  /// kapalı" kararı yalnız bunlar üzerinden verilir (yalnız kurul/görevli bağı olan site sayılmaz).
  List<MySiteModules> get doorAccessSites =>
      sites.where((s) => s.doorAccess).toList(growable: false);

  /// Kullanıcı en az bir sitede kapı erişimine sahip VE o sitelerin HEPSİNDE [code] kapalı mı?
  ///
  /// Süper kullanıcıda (`scope: all`) ve kapı erişimi olan hiç sitesi olmayanda (yalnız kurul/görevli
  /// bağı ya da hiç site) false: ona gösterilecek kapı yoktur, menü ve ekranlar değişmez.
  /// [PlatformModuleCodes.doorControl] dışındaki modüllerde tüm siteler dikkate alınır.
  bool isDisabledEverywhere(String code) {
    if (isAll) return false;
    final relevant = code == PlatformModuleCodes.doorControl ? doorAccessSites : sites;
    return relevant.isNotEmpty && !relevant.any((s) => s.isEnabled(code));
  }

  factory MyModulesResult.fromJson(Map<String, dynamic> json) {
    final rawSites = json['sites'];
    return MyModulesResult(
      scope: json['scope']?.toString() ?? 'sites',
      sites: rawSites is List
          ? rawSites
              .whereType<Map>()
              .map((s) => MySiteModules.fromJson(Map<String, dynamic>.from(s)))
              .toList(growable: false)
          : const <MySiteModules>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MyModulesResult &&
      other.scope == scope &&
      listEquals(other.sites, sites);

  @override
  int get hashCode => Object.hash(scope, Object.hashAll(sites));
}
