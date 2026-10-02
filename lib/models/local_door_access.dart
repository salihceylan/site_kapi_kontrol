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

  /// Yerel kontrol anahtarının (token) önbellekte güvenle tutulabileceği süre.
  /// Sunucu üyelik/izin kalkınca token'ı döndürdüğü için eski kopya uzun süre tutulmaz.
  static const Duration cacheValidity = Duration(hours: 24);

  /// Yerel açma için token şarttır (C4): token boşsa yerel kontrol KAPALI sayılır.
  bool get hasToken => token.trim().isNotEmpty;

  /// Kayıt, [now] anında önbellekte tutulmaya/kullanılmaya uygun mu?
  /// (cihaz kimliği + token dolu ve [cacheValidity] içinde güncellenmiş)
  bool isUsableAt(DateTime now) {
    if (deviceUid.trim().isEmpty || !hasToken) {
      return false;
    }
    final age = now.difference(updatedAt);
    // Gelecekteki bir damga (saat oynatma) güvenilmez sayılır.
    if (age.isNegative && age.inMinutes < -5) {
      return false;
    }
    return age <= cacheValidity;
  }

  bool get isUsable => isUsableAt(DateTime.now());

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
