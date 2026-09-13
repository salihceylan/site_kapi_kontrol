class SiteManagerRecord {
  const SiteManagerRecord({
    required this.userCode,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    required this.userRole,
    required this.siteRole,
    required this.isOwner,
    this.createdAt,
  });

  final int userCode;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String userRole;
  final String siteRole;
  final bool isOwner;
  final DateTime? createdAt;

  factory SiteManagerRecord.fromJson(Map<String, dynamic> json) {
    return SiteManagerRecord(
      userCode: (json['user_code'] as num).toInt(),
      fullName: json['full_name'] as String? ?? 'İsimsiz',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
      userRole: json['user_role'] as String? ?? 'site_manager',
      siteRole: json['site_role'] as String? ?? 'SITE_ADMIN',
      isOwner: json['is_owner'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  String get roleLabel => isOwner ? 'Kurucu Yönetici' : 'Site Yöneticisi';
}

class SiteManagerInvitationRecord {
  const SiteManagerInvitationRecord({
    required this.id,
    required this.siteCode,
    required this.email,
    this.fullName,
    required this.invitedByUserCode,
    required this.inviterName,
    required this.status,
    this.createdAt,
    this.expiresAt,
  });

  final int id;
  final int siteCode;
  final String email;
  final String? fullName;
  final int invitedByUserCode;
  final String inviterName;
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory SiteManagerInvitationRecord.fromJson(Map<String, dynamic> json) {
    return SiteManagerInvitationRecord(
      id: (json['id'] as num).toInt(),
      siteCode: (json['site_code'] as num).toInt(),
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      invitedByUserCode: (json['invited_by_user_code'] as num).toInt(),
      inviterName: json['inviter_name'] as String? ?? 'Site Yönetimi',
      status: json['status'] as String? ?? 'PENDING',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
    );
  }
}

class SiteManagersData {
  const SiteManagersData({
    required this.managers,
    required this.invitations,
  });

  final List<SiteManagerRecord> managers;
  final List<SiteManagerInvitationRecord> invitations;

  factory SiteManagersData.fromJson(Map<String, dynamic> json) {
    final mgrList = (json['managers'] as List<dynamic>?) ?? [];
    final invList = (json['invitations'] as List<dynamic>?) ?? [];

    return SiteManagersData(
      managers: mgrList
          .map((m) => SiteManagerRecord.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      invitations: invList
          .map((i) => SiteManagerInvitationRecord.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList(),
    );
  }
}

