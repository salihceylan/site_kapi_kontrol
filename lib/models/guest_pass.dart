class GuestPassRecord {
  const GuestPassRecord({
    required this.id,
    required this.title,
    required this.token,
    required this.passType,
    required this.expiresAt,
    required this.maxUses,
    required this.usedCount,
    required this.isActive,
    required this.webUrl,
    required this.doorName,
    required this.siteName,
  });

  final int id;
  final String title;
  final String token;
  final String passType;
  final DateTime expiresAt;
  final int maxUses;
  final int usedCount;
  final bool isActive;
  final String webUrl;
  final String doorName;
  final String siteName;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isExhausted => usedCount >= maxUses;
  bool get isUsable => isActive && !isExpired && !isExhausted;

  factory GuestPassRecord.fromJson(Map<String, dynamic> json) {
    return GuestPassRecord(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Misafir / Kurye',
      token: json['token'] as String? ?? '',
      passType: json['pass_type'] as String? ?? 'single_use',
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
          DateTime.now(),
      maxUses: json['max_uses'] as int? ?? 1,
      usedCount: json['used_count'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      webUrl: json['web_url'] as String? ?? '',
      doorName: json['door_name'] as String? ?? 'Site Kapisi',
      siteName: json['site_name'] as String? ?? 'Site',
    );
  }
}
