class SiteJoinTokenRecord {
  const SiteJoinTokenRecord({
    required this.id,
    required this.siteCode,
    required this.siteName,
    required this.token,
    required this.qrPayload,
    required this.isActive,
    this.createdAt,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final String token;
  final String qrPayload;
  final bool isActive;
  final DateTime? createdAt;

  factory SiteJoinTokenRecord.fromJson(Map<String, dynamic> json) {
    return SiteJoinTokenRecord(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      siteCode: json['site_code'] is int
          ? json['site_code'] as int
          : int.tryParse(json['site_code']?.toString() ?? '') ?? 0,
      siteName: json['site_name'] as String? ?? '',
      token: json['token'] as String? ?? '',
      qrPayload: json['qr_payload'] as String? ??
          (json['token'] != null ? 'SITE_JOIN:${json['token']}' : ''),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'site_code': siteCode,
      'site_name': siteName,
      'token': token,
      'qr_payload': qrPayload,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

