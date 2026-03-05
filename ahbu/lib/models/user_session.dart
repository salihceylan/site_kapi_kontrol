import 'package:ahbu/models/user_role.dart';

class UserSession {
  const UserSession({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.token,
    this.phoneNumber,
    this.createdAt,
  });

  final int id;
  final String fullName;
  final String email;
  final UserRole role;
  final String token;
  final String? phoneNumber;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'role': role.apiValue,
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
      role: UserRole.fromApi(json['role'] as String),
      token: json['token'] as String,
      phoneNumber: json['phone_number'] as String?,
      createdAt: createdAtRaw == null || createdAtRaw.isEmpty
          ? null
          : DateTime.tryParse(createdAtRaw),
    );
  }
}
