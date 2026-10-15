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
  });

  final int residencyId;
  final int personId;
  final String fullName;
  final ResidencyRelation relation;
  final DateTime? moveInDate;
  final DateTime? moveOutDate;
  final bool hasAccount;

  factory ApartmentResident.fromJson(Map<String, dynamic> json) {
    return ApartmentResident(
      residencyId: crmInt(json['residency_id']),
      personId: crmInt(json['person_id']),
      fullName: json['full_name']?.toString() ?? '',
      relation: ResidencyRelation.fromApi(json['relation']),
      moveInDate: crmDate(json['move_in_date']),
      moveOutDate: crmDate(json['move_out_date']),
      hasAccount: json['has_account'] == true,
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
  });

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
  final ApartmentPartyRef? owner;
  final ApartmentPartyRef? tenant;
  final int residentCount;

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
    this.currentResidents = const <ApartmentResident>[],
    this.pastResidents = const <ApartmentResident>[],
  });

  final List<ApartmentResident> currentResidents;
  final List<ApartmentResident> pastResidents;

  factory ApartmentDetail.fromJson(Map<String, dynamic> json) {
    final base = ApartmentSummary.fromJson(json);
    final current = ApartmentResident.listFrom(json['current_residents']);
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
