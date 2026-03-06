import 'package:site_kapi_kontrol/models/user_role.dart';

class ManagedUserAccount {
  const ManagedUserAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.phoneNumber,
    required this.createdAt,
  });

  final int id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool isActive;
  final String? phoneNumber;
  final DateTime? createdAt;

  ManagedUserAccount copyWith({
    int? id,
    String? fullName,
    String? email,
    UserRole? role,
    bool? isActive,
    String? phoneNumber,
    DateTime? createdAt,
  }) {
    return ManagedUserAccount(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ManagedUserAccount.fromJson(Map<String, dynamic> json) {
    return ManagedUserAccount(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: UserRole.fromApi(json['role'] as String),
      isActive: json['is_active'] as bool? ?? true,
      phoneNumber: json['phone_number'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
