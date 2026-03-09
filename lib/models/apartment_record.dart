class ApartmentRecord {
  const ApartmentRecord({
    required this.id,
    required this.siteCode,
    required this.blockId,
    required this.blockName,
    required this.unitLabel,
    required this.sortOrder,
    required this.isActive,
    required this.residentUserCode,
    required this.residentFullName,
    required this.residentLoginName,
    required this.residentEmail,
    required this.residentPinCode,
    required this.residentPhoneNumber,
    required this.residentIsActive,
    required this.createdAt,
  });

  final int id;
  final int siteCode;
  final int blockId;
  final String blockName;
  final String unitLabel;
  final int sortOrder;
  final bool isActive;
  final int? residentUserCode;
  final String? residentFullName;
  final String? residentLoginName;
  final String? residentEmail;
  final String? residentPinCode;
  final String? residentPhoneNumber;
  final bool? residentIsActive;
  final DateTime? createdAt;

  String get label => '$blockName / $unitLabel';

  factory ApartmentRecord.fromJson(Map<String, dynamic> json) {
    return ApartmentRecord(
      id: json['id'] as int,
      siteCode: json['site_code'] as int,
      blockId: json['block_id'] as int,
      blockName: json['block_name'] as String? ?? '',
      unitLabel: json['unit_label'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      residentUserCode: json['resident_user_code'] as int?,
      residentFullName: json['resident_full_name'] as String?,
      residentLoginName: json['resident_login_name'] as String?,
      residentEmail: json['resident_email'] as String?,
      residentPinCode: json['resident_pin_code'] as String?,
      residentPhoneNumber: json['resident_phone_number'] as String?,
      residentIsActive: json['resident_is_active'] as bool?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
