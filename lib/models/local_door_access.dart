class LocalDoorAccess {
  const LocalDoorAccess({
    required this.deviceUid,
    required this.token,
    required this.ip,
    required this.port,
    required this.updatedAt,
  });

  final String deviceUid;
  final String token;
  final String? ip;
  final int port;
  final DateTime updatedAt;

  static const Duration cacheValidity = Duration(days: 90);
  bool get isUsable {
    if (deviceUid.isEmpty || token.isEmpty) {
      return false;
    }
    return DateTime.now().difference(updatedAt) <= cacheValidity;
  }

  Map<String, dynamic> toJson() {
    return {
      'device_uid': deviceUid,
      'token': token,
      'ip': ip,
      'port': port,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LocalDoorAccess.fromJson(Map<String, dynamic> json) {
    return LocalDoorAccess(
      deviceUid: (json['device_uid'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      ip: (json['ip'] ?? '').toString().trim().isEmpty
          ? null
          : (json['ip'] ?? '').toString(),
      port: (json['port'] as num?)?.toInt() ?? 8765,
      updatedAt:
          DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
