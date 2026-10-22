// Daire halki (Site Yönetimi > Daireler): dairenin TÜM güncel sakinleri, daire adminiyle birlikte.
// Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md ("Site yöneticisi: dairenin sakinleri");
// uç: GET /manager/sites/:siteCode/apartments/:id/household. Alan yoksa güvenli varsayılan (eski sunucuyla çalışır).
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
int _i(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);
Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Dairedeki bir kişi.
///
/// Kurul üyesi (`detail == 'basic'`) yalnız ad + ilişki + admin bilgisini alır: [phone] null, [isMinor] / [hasAccount] /
/// [accessSuspended] false gelir ve ekranda gösterilmez ([ApartmentHousehold.isDetailed] false).
@immutable
class HouseholdPerson {
  const HouseholdPerson({
    this.personId,
    required this.name,
    this.relation = ResidencyRelation.resident,
    this.isAdmin = false,
    this.isMinor = false,
    this.hasAccount = false,
    this.phone,
    this.accessSuspended = false,
  });

  factory HouseholdPerson.fromJson(Map<String, dynamic> j) {
    final phone = _s(j['phone']).trim();
    return HouseholdPerson(
      personId: j['person_id'] is num ? _i(j['person_id']) : null,
      name: _s(j['name']).trim().isEmpty ? 'İsimsiz kişi' : _s(j['name']).trim(),
      relation: ResidencyRelation.fromApi(j['relation']),
      isAdmin: j['is_admin'] == true,
      isMinor: j['is_minor'] == true,
      hasAccount: j['has_account'] == true,
      phone: phone.isEmpty ? null : phone,
      accessSuspended: j['access_suspended'] == true,
    );
  }

  /// Kişi kartı (`PersonCardDialog`) için kişi numarası; ilişkisi eşitlenmemiş eski kayıtta null.
  final int? personId;
  final String name;
  final ResidencyRelation relation;
  final bool isAdmin;
  final bool isMinor;
  final bool hasAccount;
  final String? phone;

  /// Kapı erişimi askıda (askıya alma kaydı ya da pasife alınmış üyelik).
  final bool accessSuspended;

  /// Aile listesindeki ilişki etiketi: küçük = "Çocuk"; başka ilişki ayrımı sunucuda yoktur (eş / yaşlı ebeveyn tutulmaz).
  String get relationLabel {
    if (isMinor) return 'Çocuk';
    return switch (relation) {
      ResidencyRelation.owner => 'Malik',
      ResidencyRelation.tenant => 'Kiracı',
      ResidencyRelation.familyMember => 'Aile üyesi',
      ResidencyRelation.resident => 'Sakin',
    };
  }
}

@immutable
class ApartmentHousehold {
  const ApartmentHousehold({
    required this.apartmentId,
    this.label = '',
    this.isDetailed = false,
    this.admin,
    this.absentOwner,
    this.members = const <HouseholdPerson>[],
    this.total = 0,
  });

  factory ApartmentHousehold.fromJson(Map<String, dynamic> j) {
    final admin = j['admin'];
    final absent = j['absent_owner'];
    final members = <HouseholdPerson>[
      if (j['members'] is List)
        for (final e in j['members'] as List)
          if (e is Map) HouseholdPerson.fromJson(_m(e)),
    ];
    final absentOwner = absent is Map ? HouseholdPerson.fromJson(_m(absent)) : null;
    final adminPerson = admin is Map ? HouseholdPerson.fromJson(_m(admin)) : null;
    return ApartmentHousehold(
      apartmentId: _i(j['apartment_id']),
      label: _s(j['label']),
      isDetailed: j['detail'] == 'full',
      admin: adminPerson,
      absentOwner: absentOwner,
      members: members,
      total: j['total'] is num
          ? _i(j['total'])
          : members.length + (adminPerson == null ? 0 : 1) + (absentOwner == null ? 0 : 1),
    );
  }

  final int apartmentId;
  final String label;

  /// true: yönetici / süper (telefon, çocuk, hesap durumu, erişim askısı var); false: kurul (yalnız ad + ilişki).
  final bool isDetailed;
  final HouseholdPerson? admin;

  /// Kiracı oturan dairede malik (admin değilse): "Malik (oturmuyor)" satırı.
  final HouseholdPerson? absentOwner;

  /// Admin ve oturmayan malik DIŞINDAKİ tüm güncel kişiler (aile üyeleri, kiracı admin değilse kiracı, ...).
  final List<HouseholdPerson> members;

  /// Dairedeki tüm güncel kişi (admin + oturmayan malik + [members]).
  final int total;
}
