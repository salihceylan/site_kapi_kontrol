import 'package:site_kapi_kontrol/models/user_role.dart';

class UserSession {
  const UserSession({
    required this.id,
    required this.fullName,
    required this.email,
    required this.loginName,
    required this.role,
    required this.isActive,
    required this.token,
    this.phoneNumber,
    this.createdAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String? loginName;
  final UserRole role;
  final bool isActive;
  final String token;
  final String? phoneNumber;
  final DateTime? createdAt;

  UserSession copyWith({
    int? id,
    String? fullName,
    String? email,
    String? loginName,
    UserRole? role,
    bool? isActive,
    String? token,
    String? phoneNumber,
    DateTime? createdAt,
  }) {
    return UserSession(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      loginName: loginName ?? this.loginName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      token: token ?? this.token,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'login_name': loginName,
      'role': role.apiValue,
      'is_active': isActive,
      'token': token,
      'phone_number': phoneNumber,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    return UserSession(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      loginName: json['login_name'] as String?,
      role: UserRole.fromApi(json['role'] as String),
      isActive: json['is_active'] as bool? ?? true,
      token: json['token'] as String,
      phoneNumber: json['phone_number'] as String?,
      createdAt: createdAtRaw == null || createdAtRaw.isEmpty
          ? null
          : DateTime.tryParse(createdAtRaw),
    );
  }
}
