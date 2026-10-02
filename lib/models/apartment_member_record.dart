class ApartmentMemberRecord {
  const ApartmentMemberRecord({
    required this.membershipId,
    required this.userCode,
    required this.fullName,
    required this.email,
    this.phoneNumber = '',
    required this.role,
    this.isCurrentUser = false,
    this.isApartmentAdmin = false,
    this.joinedAt,
  });

  final int membershipId;
  final int userCode;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String role;
  final bool isCurrentUser;
  final bool isApartmentAdmin;
  final DateTime? joinedAt;

  factory ApartmentMemberRecord.fromJson(Map<String, dynamic> json) {
    return ApartmentMemberRecord(
      membershipId: (json['membership_id'] as num?)?.toInt() ?? 0,
      userCode: (json['user_code'] as num?)?.toInt() ?? 0,
      fullName: json['full_name'] as String? ?? json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? json['phoneNumber'] as String? ?? '',
      role: json['role'] as String? ?? 'FAMILY_MEMBER',
      isCurrentUser: json['is_current_user'] as bool? ?? false,
      isApartmentAdmin: json['is_apartment_admin'] as bool? ?? (json['role'] == 'APARTMENT_ADMIN'),
      joinedAt: json['joined_at'] != null ? DateTime.tryParse(json['joined_at'].toString()) : null,
    );
  }
}

class MyApartmentRecord {
  const MyApartmentRecord({
    required this.apartmentId,
    required this.unitLabel,
    this.blockId,
    this.blockName = '',
    required this.siteCode,
    required this.siteName,
    this.city = '',
    this.district = '',
    required this.apartmentRole,
    this.joinedAt,
    this.members = const [],
  });

  final int apartmentId;
  final String unitLabel;
  final int? blockId;
  final String blockName;
  final int siteCode;
  final String siteName;
  final String city;
  final String district;
  final String apartmentRole;
  final DateTime? joinedAt;
  final List<ApartmentMemberRecord> members;

  bool get isApartmentAdmin => apartmentRole == 'APARTMENT_ADMIN';

  String get fullDisplayName {
    final b = blockName.trim();
    if (b.isNotEmpty) {
      return '$siteName - $b / $unitLabel';
    }
    return '$siteName / $unitLabel';
  }

  factory MyApartmentRecord.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? const [];
    return MyApartmentRecord(
      apartmentId: (json['apartment_id'] as num?)?.toInt() ?? (json['apartmentId'] as num?)?.toInt() ?? 0,
      unitLabel: json['unit_label'] as String? ?? json['unitLabel'] as String? ?? '',
      blockId: (json['block_id'] as num?)?.toInt() ?? (json['blockId'] as num?)?.toInt(),
      blockName: json['block_name'] as String? ?? json['blockName'] as String? ?? '',
      siteCode: (json['site_code'] as num?)?.toInt() ?? (json['siteCode'] as num?)?.toInt() ?? 0,
      siteName: json['site_name'] as String? ?? json['siteName'] as String? ?? '',
      city: json['city'] as String? ?? '',
      district: json['district'] as String? ?? '',
      apartmentRole: json['apartment_role'] as String? ?? json['apartmentRole'] as String? ?? 'FAMILY_MEMBER',
      joinedAt: json['joined_at'] != null ? DateTime.tryParse(json['joined_at'].toString()) : null,
      members: rawMembers
          .map((m) => ApartmentMemberRecord.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

