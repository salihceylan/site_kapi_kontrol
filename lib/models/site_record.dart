class SiteRecord {
  const SiteRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    required this.blockCount,
    required this.apartmentCount,
    required this.doorCount,
    required this.approvalStatus,
    required this.approvedAt,
    required this.mqttSiteId,
    required this.managerUserCode,
    required this.managerName,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String? address;
  final String? city;
  final String? district;
  final int blockCount;
  final int apartmentCount;
  final int doorCount;
  final String approvalStatus;
  final DateTime? approvedAt;
  final int mqttSiteId;
  final int? managerUserCode;
  final String? managerName;
  final DateTime? createdAt;

  bool get isApproved => approvalStatus == 'approved';

  String get approvalLabel {
    switch (approvalStatus) {
      case 'pending':
        return 'Onay Bekliyor';
      case 'rejected':
        return 'Reddedildi';
      default:
        return 'Onaylandi';
    }
  }

  SiteRecord copyWith({
    int? id,
    String? name,
    String? address,
    String? city,
    String? district,
    int? blockCount,
    int? apartmentCount,
    int? doorCount,
    String? approvalStatus,
    DateTime? approvedAt,
    int? mqttSiteId,
    int? managerUserCode,
    String? managerName,
    DateTime? createdAt,
  }) {
    return SiteRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      district: district ?? this.district,
      blockCount: blockCount ?? this.blockCount,
      apartmentCount: apartmentCount ?? this.apartmentCount,
      doorCount: doorCount ?? this.doorCount,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      approvedAt: approvedAt ?? this.approvedAt,
      mqttSiteId: mqttSiteId ?? this.mqttSiteId,
      managerUserCode: managerUserCode ?? this.managerUserCode,
      managerName: managerName ?? this.managerName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory SiteRecord.fromJson(Map<String, dynamic> json) {
    return SiteRecord(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      blockCount: json['block_count'] as int? ?? 1,
      apartmentCount: json['apartment_count'] as int? ?? 0,
      doorCount: json['door_count'] as int? ?? 1,
      approvalStatus: json['approval_status'] as String? ?? 'approved',
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.tryParse(json['approved_at'] as String),
      mqttSiteId: json['mqtt_site_id'] as int? ?? 0,
      managerUserCode: json['manager_user_code'] as int?,
      managerName: json['manager_name'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
