import 'package:site_kapi_kontrol/models/user_role.dart';

class UserSession {
  const UserSession({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.token,
  });

  final int id;
  final String fullName;
  final String email;
  final UserRole role;
  final String token;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'role': role.apiValue,
      'token': token,
    };
  }

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: UserRole.fromApi(json['role'] as String),
      token: json['token'] as String,
    );
  }
}
