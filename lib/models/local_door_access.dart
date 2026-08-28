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

  bool get isUsable => deviceUid.isNotEmpty && token.isNotEmpty;

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
