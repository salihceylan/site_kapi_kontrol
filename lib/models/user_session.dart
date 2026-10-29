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
    this.mustChangePassword = false,
    this.phoneNumber,
    this.createdAt,
    this.trialExpiresAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String? loginName;
  final UserRole role;
  final bool isActive;
  final String token;
  final bool mustChangePassword;
  final String? phoneNumber;
  final DateTime? createdAt;

  /// Deneme erişim kodu oturumunun bitiş anı (P2-27, karar K10: 72 saat, demo siteye kilitli). Yalnız deneme hesabında
  /// dolu; sunucu `trial_expires_at` alanını giriş yanıtında ve `/me`'de verir. null = normal oturum.
  final DateTime? trialExpiresAt;

  /// Bu oturum deneme erişim kodu ile açılmış mı?
  bool get isTrial => trialExpiresAt != null;

  UserSession copyWith({
    int? id,
    String? fullName,
    String? email,
    String? loginName,
    UserRole? role,
    bool? isActive,
    String? token,
    bool? mustChangePassword,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? trialExpiresAt,
  }) {
    return UserSession(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      loginName: loginName ?? this.loginName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      token: token ?? this.token,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      trialExpiresAt: trialExpiresAt ?? this.trialExpiresAt,
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
      'must_change_password': mustChangePassword,
      'phone_number': phoneNumber,
      'created_at': createdAt?.toIso8601String(),
      if (trialExpiresAt != null) 'trial_expires_at': trialExpiresAt!.toUtc().toIso8601String(),
    };
  }

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    final trialRaw = json['trial_expires_at'];
    return UserSession(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      loginName: json['login_name'] as String?,
      role: UserRole.fromApi(json['role'] as String),
      isActive: json['is_active'] as bool? ?? true,
      token: json['token'] as String,
      mustChangePassword: json['must_change_password'] == true,
      phoneNumber: json['phone_number'] as String?,
      createdAt: createdAtRaw == null || createdAtRaw.isEmpty
          ? null
          : DateTime.tryParse(createdAtRaw),
      trialExpiresAt: trialRaw is String && trialRaw.isNotEmpty
          ? DateTime.tryParse(trialRaw)?.toLocal()
          : null,
    );
  }
}
