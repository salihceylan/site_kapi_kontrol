import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/person_record.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';

/// Arsa payı kesri (örn. 35/1000). İkisi birlikte dolu ya da boştur; payda > 0, pay <= payda.
@immutable
class LandShare {
  const LandShare(this.numerator, this.denominator);

  final int numerator;
  final int denominator;

  /// "35/1000".
  String get label => '$numerator/$denominator';

  /// Geçerli kesir mi (payda > 0, 0 <= pay <= payda)?
  static bool isValid(int? numerator, int? denominator) =>
      numerator != null &&
      denominator != null &&
      denominator > 0 &&
      numerator >= 0 &&
      numerator <= denominator;

  static LandShare? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final numerator = crmIntOrNull(raw['numerator']);
    final denominator = crmIntOrNull(raw['denominator']);
    if (numerator == null || denominator == null || denominator <= 0) return null;
    return LandShare(numerator, denominator);
  }

  @override
  bool operator ==(Object other) =>
      other is LandShare && other.numerator == numerator && other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);
}

/// Dairenin güncel malik / kiracısı (liste ve kart özeti).
@immutable
class ApartmentPartyRef {
  const ApartmentPartyRef({required this.personId, this.fullName = ''});

  final int personId;
  final String fullName;

  static ApartmentPartyRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = crmIntOrNull(raw['person_id']);
    if (id == null) return null;
    return ApartmentPartyRef(personId: id, fullName: raw['full_name']?.toString() ?? '');
  }
}

/// Dairenin güncel ya da geçmiş sakini.
@immutable
class ApartmentResident {
  const ApartmentResident({
    required this.residencyId,
    required this.personId,
    this.fullName = '',
    this.relation = ResidencyRelation.resident,
    this.moveInDate,
    this.moveOutDate,
    this.hasAccount = false,
    this.isAccountHolder = false,
  });

  final int residencyId;
  final int personId;
  final String fullName;
  final ResidencyRelation relation;
  final DateTime? moveInDate;
  final DateTime? moveOutDate;
  final bool hasAccount;

  /// Çoklu malik (104): bu kişi dairenin HESAP MUHATABI mı (yalnız malik satırında dolu gelir; eski sunucuda alan yok -> false).
  final bool isAccountHolder;

  factory ApartmentResident.fromJson(Map<String, dynamic> json) {
    return ApartmentResident(
      residencyId: crmInt(json['residency_id']),
      personId: crmInt(json['person_id']),
      fullName: json['full_name']?.toString() ?? '',
      relation: ResidencyRelation.fromApi(json['relation']),
      moveInDate: crmDate(json['move_in_date']),
      moveOutDate: crmDate(json['move_out_date']),
      hasAccount: json['has_account'] == true,
      isAccountHolder: json['is_account_holder'] == true,
    );
  }

  static List<ApartmentResident> listFrom(Object? raw) {
    if (raw is! List) return const <ApartmentResident>[];
    return raw
        .whereType<Map>()
        .map((e) => ApartmentResident.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}

/// Daire listesi satırı (`GET .../apartments` -> `items[]`).
@immutable
class ApartmentSummary {
  const ApartmentSummary({
    required this.id,
    this.label = '',
    this.blockId,
    this.blockName,
    this.floor,
    this.category,
    this.grossAreaM2,
    this.netAreaM2,
    this.landShare,
    this.responsibleParty = ResponsibleParty.both,
    this.owner,
    this.tenant,
    this.residentCount = 0,
    int? ownerCount,
  }) : ownerCount = ownerCount ?? (owner == null ? 0 : 1);

  final int id;
  final String label;
  final int? blockId;
  final String? blockName;
  final int? floor;
  final String? category;
  final double? grossAreaM2;
  final double? netAreaM2;
  final LandShare? landShare;
  final ResponsibleParty responsibleParty;
  /// Hesap muhatabı olan malik (çoklu malik, 104; eski istemci uyumu için alan adı değişmedi).
  final ApartmentPartyRef? owner;
  final ApartmentPartyRef? tenant;
  final int residentCount;

  /// Dairedeki güncel malik sayısı (alan yoksa: owner doluysa 1, değilse 0).
  final int ownerCount;

  String get fullLabel => crmApartmentTitle(blockName, label);

  factory ApartmentSummary.fromJson(Map<String, dynamic> json) {
    return ApartmentSummary(
      id: crmInt(json['id']),
      label: json['label']?.toString() ?? '',
      blockId: crmIntOrNull(json['block_id']),
      blockName: crmText(json['block_name']),
      floor: crmIntOrNull(json['floor']),
      category: crmText(json['category']),
      grossAreaM2: crmDoubleOrNull(json['gross_area_m2']),
      netAreaM2: crmDoubleOrNull(json['net_area_m2']),
      landShare: LandShare.fromJson(json['land_share']),
      responsibleParty: ResponsibleParty.fromApi(json['responsible_party']),
      owner: ApartmentPartyRef.fromJson(json['owner']),
      tenant: ApartmentPartyRef.fromJson(json['tenant']),
      residentCount: crmInt(json['resident_count']),
      ownerCount: json['owner_count'] == null ? null : crmInt(json['owner_count']),
    );
  }
}

/// Dairenin bir maliki (çoklu malik, 104): tüm malikler kayıtlı, içlerinden TAM BİRİ hesap muhatabıdır.
/// Borç / ekstre / makbuz / hatırlatma muhataba bakar; diğer malikler borç görmez ve malik yetkisi taşımaz.
@immutable
class ApartmentOwner {
  const ApartmentOwner({
    required this.residencyId,
    required this.personId,
    this.fullName = '',
    this.isAccountHolder = false,
    this.hasAccount = false,
    this.moveInDate,
  });

  final int residencyId;
  final int personId;
  final String fullName;

  /// Hesap muhatabı mı (dairede tam bir malikte true).
  final bool isAccountHolder;
  final bool hasAccount;
  final DateTime? moveInDate;

  factory ApartmentOwner.fromJson(Map<String, dynamic> json) {
    return ApartmentOwner(
      residencyId: crmInt(json['residency_id']),
      personId: crmInt(json['person_id']),
      fullName: json['full_name']?.toString() ?? '',
      isAccountHolder: json['is_account_holder'] == true,
      hasAccount: json['has_account'] == true,
      moveInDate: crmDate(json['move_in_date']),
    );
  }

  factory ApartmentOwner.fromResident(ApartmentResident resident, {required bool isAccountHolder}) {
    return ApartmentOwner(
      residencyId: resident.residencyId,
      personId: resident.personId,
      fullName: resident.fullName,
      isAccountHolder: isAccountHolder,
      hasAccount: resident.hasAccount,
      moveInDate: resident.moveInDate,
    );
  }

  static List<ApartmentOwner> listFrom(Object? raw) {
    if (raw is! List) return const <ApartmentOwner>[];
    return raw
        .whereType<Map>()
        .map((e) => ApartmentOwner.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Eski sunucu (`owners` alanı yok): güncel sakinlerden malikler. Muhatap: bayraklı olan; yoksa `owner` ile aynı kişi; tek malik varsa o.
  static List<ApartmentOwner> deriveFrom(List<ApartmentResident> current, ApartmentPartyRef? ownerRef) {
    final owners = current.where((r) => r.relation == ResidencyRelation.owner).toList(growable: false);
    if (owners.isEmpty) return const <ApartmentOwner>[];
    int? holderId;
    for (final r in owners) {
      if (r.isAccountHolder) {
        holderId = r.residencyId;
        break;
      }
    }
    if (holderId == null && ownerRef != null) {
      for (final r in owners) {
        if (r.personId == ownerRef.personId) {
          holderId = r.residencyId;
          break;
        }
      }
    }
    if (holderId == null && owners.length == 1) holderId = owners.single.residencyId;
    final list = <ApartmentOwner>[
      for (final r in owners) ApartmentOwner.fromResident(r, isAccountHolder: r.residencyId == holderId),
    ];
    list.sort((a, b) => a.isAccountHolder == b.isAccountHolder ? 0 : (a.isAccountHolder ? -1 : 1));
    return list;
  }
}

/// Dairenin malik listesi yanıtı (`GET/POST/PUT .../apartments/:id/owners...`): muhatap başta.
@immutable
class ApartmentOwnersView {
  const ApartmentOwnersView({
    required this.apartmentId,
    this.label = '',
    this.owners = const <ApartmentOwner>[],
    this.accountHolderResidencyId,
    this.ownerLimit = 10,
  });

  final int apartmentId;
  final String label;
  final List<ApartmentOwner> owners;
  final int? accountHolderResidencyId;
  final int ownerLimit;

  bool get canAddMore => owners.length < ownerLimit;

  factory ApartmentOwnersView.fromJson(Map<String, dynamic> json) {
    return ApartmentOwnersView(
      apartmentId: crmInt(json['apartment_id']),
      label: json['label']?.toString() ?? '',
      owners: ApartmentOwner.listFrom(json['owners']),
      accountHolderResidencyId: crmIntOrNull(json['account_holder_residency_id']),
      ownerLimit: crmInt(json['owner_limit'], 10),
    );
  }
}

/// Daire kartı (`GET/PATCH .../apartments/:id`): özet + güncel ve geçmiş sakinler.
@immutable
class ApartmentDetail extends ApartmentSummary {
  const ApartmentDetail({
    required super.id,
    super.label,
    super.blockId,
    super.blockName,
    super.floor,
    super.category,
    super.grossAreaM2,
    super.netAreaM2,
    super.landShare,
    super.responsibleParty,
    super.owner,
    super.tenant,
    super.residentCount,
    super.ownerCount,
    this.owners = const <ApartmentOwner>[],
    this.currentResidents = const <ApartmentResident>[],
    this.pastResidents = const <ApartmentResident>[],
  });

  /// Tüm güncel malikler (çoklu malik, 104), hesap muhatabı başta. Eski sunucuda `owners` yoksa güncel sakinlerden türetilir.
  final List<ApartmentOwner> owners;
  final List<ApartmentResident> currentResidents;
  final List<ApartmentResident> pastResidents;

  /// Dairede birden çok malik var mı (muhatap rozeti ve malik yönetimi yalnız o zaman gösterilir).
  bool get hasMultipleOwners => owners.length > 1;

  factory ApartmentDetail.fromJson(Map<String, dynamic> json) {
    final base = ApartmentSummary.fromJson(json);
    final current = ApartmentResident.listFrom(json['current_residents']);
    final owners = json['owners'] is List
        ? ApartmentOwner.listFrom(json['owners'])
        : ApartmentOwner.deriveFrom(current, base.owner);
    return ApartmentDetail(
      id: base.id,
      label: base.label,
      blockId: base.blockId,
      blockName: base.blockName,
      floor: base.floor,
      category: base.category,
      grossAreaM2: base.grossAreaM2,
      netAreaM2: base.netAreaM2,
      landShare: base.landShare,
      responsibleParty: base.responsibleParty,
      owner: base.owner,
      tenant: base.tenant,
      residentCount: json['resident_count'] == null ? current.length : base.residentCount,
      // Eski sunucuda owner_count yok: türetilen malik sayısı ile `owner` alanından gelen en az 1 arasında büyüğü.
      ownerCount: json['owner_count'] == null ? (owners.length > base.ownerCount ? owners.length : base.ownerCount) : base.ownerCount,
      owners: owners,
      currentResidents: current,
      pastResidents: ApartmentResident.listFrom(json['past_residents']),
    );
  }
}

/// `GET .../apartments` sayfası.
@immutable
class ApartmentPage {
  const ApartmentPage({this.items = const <ApartmentSummary>[], this.total = 0});

  final List<ApartmentSummary> items;
  final int total;

  factory ApartmentPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => ApartmentSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <ApartmentSummary>[];
    return ApartmentPage(items: items, total: crmInt(json['total'], items.length));
  }
}

/// Sakinin kendi kaydı (`GET /app/my-records` -> `records[]`): yalnız çağıranın güncel kayıtları.
@immutable
class MyRecord {
  const MyRecord({
    required this.apartmentId,
    this.siteCode = 0,
    this.siteName = '',
    this.label = '',
    this.blockName,
    this.relation = ResidencyRelation.resident,
    this.moveInDate,
    this.vehicles = const <VehicleRecord>[],
  });

  final int apartmentId;
  final int siteCode;
  final String siteName;
  final String label;
  final String? blockName;
  final ResidencyRelation relation;
  final DateTime? moveInDate;
  final List<VehicleRecord> vehicles;

  String get fullLabel => crmApartmentTitle(blockName, label);

  factory MyRecord.fromJson(Map<String, dynamic> json) {
    return MyRecord(
      apartmentId: crmInt(json['apartment_id']),
      siteCode: crmInt(json['site_code']),
      siteName: json['site_name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      blockName: crmText(json['block_name']),
      relation: ResidencyRelation.fromApi(json['relation']),
      moveInDate: crmDate(json['move_in_date']),
      // Sunucu araç notunu artık göndermez; eski sürümden gelirse de yok sayılır.
      vehicles: VehicleRecord.listFrom(json['vehicles'])
          .map((v) => v.withoutNote())
          .toList(growable: false),
    );
  }

  static List<MyRecord> listFrom(Object? raw) {
    if (raw is! List) return const <MyRecord>[];
    return raw
        .whereType<Map>()
        .map((e) => MyRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
