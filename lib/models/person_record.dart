import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';

/// Kişinin bir dairedeki güncel ilişkisi (liste kartındaki daire etiketi).
@immutable
class PersonApartmentRef {
  const PersonApartmentRef({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.relation = ResidencyRelation.resident,
    this.isAdmin = false,
  });

  final int apartmentId;
  final String label;
  final String? blockName;
  final ResidencyRelation relation;
  final bool isAdmin;

  /// "A Blok / Daire 5" gibi tek metin (blok adı etikette yoksa başa eklenir).
  String get fullLabel => crmApartmentTitle(blockName, label);

  factory PersonApartmentRef.fromJson(Map<String, dynamic> json) {
    return PersonApartmentRef(
      apartmentId: crmInt(json['apartment_id']),
      label: json['label']?.toString() ?? '',
      blockName: crmText(json['block_name']),
      relation: ResidencyRelation.fromApi(json['relation']),
      isAdmin: json['is_admin'] == true,
    );
  }
}

/// Blok adı + daire etiketi: etiket zaten blok adını içeriyorsa tekrar etmez.
String crmApartmentTitle(String? blockName, String label) {
  final block = (blockName ?? '').trim();
  final unit = label.trim();
  if (block.isEmpty) return unit.isEmpty ? '-' : unit;
  if (unit.isEmpty) return block;
  if (unit.toLowerCase().contains(block.toLowerCase())) return unit;
  return '$block / $unit';
}

/// Kişi listesi satırı (`GET .../people` -> `items[]`).
///
/// Hesabı olan kişide ad/telefon/e-posta `users` tablosundan okunur ve CRM'den DEĞİŞTİRİLEMEZ
/// ([hasAccount]).
@immutable
class PersonSummary {
  const PersonSummary({
    required this.id,
    this.fullName = '',
    this.phone,
    this.email,
    this.hasAccount = false,
    this.isActive = true,
    this.relations = const <ResidencyRelation>[],
    this.apartments = const <PersonApartmentRef>[],
    this.vehicleCount = 0,
    this.accountKind,
    this.isAdmin = false,
  });

  final int id;
  final String fullName;
  final String? phone;
  final String? email;
  final bool hasAccount;
  final bool isActive;
  final bool isAdmin;

  /// Hesap türü: `internal` (dahili @ahbu.local hesabı), `registered` (kayıtlı kullanıcı), `none`.
  /// Alan yoksa null (eski sunucu): `hasAccount` true ise tüm kimlik alanları salt okunur sayılır.
  final String? accountKind;

  /// Dahili hesapta ad / telefon salt okunur kalır ama iletişim e-postası düzenlenebilir.
  bool get isInternalAccount => hasAccount && accountKind == 'internal';

  /// Güncel ilişki türleri (tekrarsız, sırayla).
  final List<ResidencyRelation> relations;
  final List<PersonApartmentRef> apartments;
  final int vehicleCount;

  static List<ResidencyRelation> _relationsFrom(Object? raw) {
    if (raw is! List) return const <ResidencyRelation>[];
    final seen = <ResidencyRelation>[];
    for (final item in raw) {
      final relation = ResidencyRelation.tryParse(item);
      if (relation != null && !seen.contains(relation)) seen.add(relation);
    }
    return seen;
  }

  static List<PersonApartmentRef> _apartmentsFrom(Object? raw) {
    if (raw is! List) return const <PersonApartmentRef>[];
    return raw
        .whereType<Map>()
        .map((e) => PersonApartmentRef.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  factory PersonSummary.fromJson(Map<String, dynamic> json) {
    final rels = _relationsFrom(json['relations']);
    final apts = _apartmentsFrom(json['apartments']);
    final isDaireAdmin = json['is_admin'] == true ||
        rels.contains(ResidencyRelation.owner) ||
        rels.contains(ResidencyRelation.tenant) ||
        apts.any((a) => a.isAdmin || a.relation == ResidencyRelation.owner || a.relation == ResidencyRelation.tenant);
    return PersonSummary(
      id: crmInt(json['id']),
      fullName: json['full_name']?.toString() ?? '',
      phone: crmText(json['phone']),
      email: crmText(json['email']),
      hasAccount: json['has_account'] == true,
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      relations: rels,
      apartments: apts,
      vehicleCount: crmInt(json['vehicle_count']),
      accountKind: crmText(json['account_kind']),
      isAdmin: isDaireAdmin,
    );
  }
}

/// Kişinin bir dairedeki ilişki kaydı (geçmiş dahil).
@immutable
class Residency {
  const Residency({
    required this.id,
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.relation = ResidencyRelation.resident,
    this.isCurrent = true,
    this.moveInDate,
    this.moveOutDate,
  });

  final int id;
  final int apartmentId;
  final String label;
  final String? blockName;
  final ResidencyRelation relation;
  final bool isCurrent;
  final DateTime? moveInDate;
  final DateTime? moveOutDate;

  String get fullLabel => crmApartmentTitle(blockName, label);

  factory Residency.fromJson(Map<String, dynamic> json) {
    return Residency(
      id: crmInt(json['id']),
      apartmentId: crmInt(json['apartment_id']),
      label: json['label']?.toString() ?? '',
      blockName: crmText(json['block_name']),
      relation: ResidencyRelation.fromApi(json['relation']),
      isCurrent: json['is_current'] is bool ? json['is_current'] as bool : true,
      moveInDate: crmDate(json['move_in_date']),
      moveOutDate: crmDate(json['move_out_date']),
    );
  }
}

/// Kişi kartı (`GET/POST .../people[/:id]`): özet alanlar + not, ilişki geçmişi, araçlar.
@immutable
class PersonDetail extends PersonSummary {
  const PersonDetail({
    required super.id,
    super.fullName,
    super.phone,
    super.email,
    super.hasAccount,
    super.isActive,
    super.relations,
    super.apartments,
    super.vehicleCount,
    super.accountKind,
    this.note,
    this.createdAt,
    this.residencies = const <Residency>[],
    this.vehicles = const <VehicleRecord>[],
    this.userCode,
    this.credentialsSent,
    this.credentialsEmail,
    this.identityEditable = false,
  });

  final String? note;

  /// Ad ve telefon CRM'den (yönetimce) değiştirilebilir mi (`identity_editable`)? Hesapsız kişide ve SİTENİN YÖNETTİĞİ
  /// hesapta (yönetimce açılmış sakin hesabı; toplu yüklemeyle açılanlar dahil) true; kişinin kendi kaydolduğu / sahiplendiği
  /// hesapta false (kişi kendi profilinden değiştirir). Alan yoksa (eski sunucu) false: hesabı olan kişide ad / telefon
  /// salt okunur kalır. Hesapsız kişi her zaman düzenlenebilir ([PersonSummary.hasAccount] false).
  final bool identityEditable;

  /// Kişi eklenirken boş daireye dahili hesap açıldıysa giriş bilgisi e-postasının gönderilip
  /// gönderilmediği (`credentials_sent`): true gönderildi, false gönderilemedi, null: [credentialsEmail] doluysa
  /// gönderim sürüyor (sunucu ~8 sn'den fazla beklemedi), boşsa hesap açılmadı.
  final bool? credentialsSent;

  /// Giriş bilgisi e-postasının gönderildiği / gönderilmekte olduğu adres (`credentials_email`; hesap açılmadıysa null).
  final String? credentialsEmail;
  final DateTime? createdAt;

  /// Geçmiş dahil tüm ilişki kayıtları.
  final List<Residency> residencies;
  final List<VehicleRecord> vehicles;

  /// Yalnız yönetici / süper kullanıcıya dönen hesap numarası.
  final int? userCode;

  List<Residency> get currentResidencies =>
      residencies.where((r) => r.isCurrent).toList(growable: false);

  List<Residency> get pastResidencies =>
      residencies.where((r) => !r.isCurrent).toList(growable: false);

  factory PersonDetail.fromJson(Map<String, dynamic> json) {
    final base = PersonSummary.fromJson(json);
    final rawResidencies = json['residencies'];
    final residencies = rawResidencies is List
        ? rawResidencies
              .whereType<Map>()
              .map((e) => Residency.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <Residency>[];
    final vehicles = VehicleRecord.listFrom(json['vehicles']);
    return PersonDetail(
      id: base.id,
      fullName: base.fullName,
      phone: base.phone,
      email: base.email,
      hasAccount: base.hasAccount,
      isActive: base.isActive,
      relations: base.relations,
      apartments: base.apartments,
      vehicleCount: json['vehicle_count'] == null ? vehicles.length : base.vehicleCount,
      accountKind: base.accountKind,
      credentialsSent: json['credentials_sent'] is bool ? json['credentials_sent'] as bool : null,
      credentialsEmail: crmText(json['credentials_email']),
      note: crmText(json['note']),
      createdAt: crmTimestamp(json['created_at']),
      residencies: residencies,
      vehicles: vehicles,
      userCode: crmIntOrNull(json['user_code']),
      identityEditable: json['identity_editable'] == true,
    );
  }
}

/// `GET .../people` sayfası.
@immutable
class PersonPage {
  const PersonPage({this.items = const <PersonSummary>[], this.total = 0});

  final List<PersonSummary> items;
  final int total;

  factory PersonPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => PersonSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <PersonSummary>[];
    return PersonPage(items: items, total: crmInt(json['total'], items.length));
  }
}
