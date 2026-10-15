import 'package:flutter/foundation.dart';

/// Site yöneticisinin isteğe bağlı atayabildiği ek roller (`site_memberships.role`).
/// Kullanıcının genel rolü (`users.role`) DEĞİŞMEZ.
enum StaffRoleType {
  boardMember('BOARD_MEMBER', 'Yönetim Kurulu / Denetçi'),
  staff('STAFF', 'Görevli');

  const StaffRoleType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Bilinmeyen değerde null (satır ham değerle gösterilir).
  static StaffRoleType? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toUpperCase();
    for (final type in values) {
      if (type.apiValue == normalized) return type;
    }
    return null;
  }
}

/// `GET /manager/sites/:siteCode/staff-roles` -> `items[]` (ve `PUT` -> `item`).
@immutable
class StaffRoleRecord {
  const StaffRoleRecord({
    required this.userCode,
    required this.fullName,
    required this.email,
    required this.role,
    this.createdAt,
  });

  final int userCode;
  final String fullName;
  final String email;

  /// `BOARD_MEMBER` ya da `STAFF` (sunucudaki ham değer).
  final String role;
  final DateTime? createdAt;

  StaffRoleType? get roleType => StaffRoleType.tryParse(role);

  /// Okunur rol adı; bilinmeyen değerde ham değer.
  String get roleLabel => roleType?.label ?? role;

  factory StaffRoleRecord.fromJson(Map<String, dynamic> json) {
    final rawCode = json['user_code'] ?? json['id'];
    return StaffRoleRecord(
      userCode: rawCode is num
          ? rawCode.toInt()
          : int.tryParse(rawCode?.toString() ?? '') ?? 0,
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString())?.toLocal(),
    );
  }
}
