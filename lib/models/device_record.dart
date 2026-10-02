class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.deviceUid,
    required this.assignedUserCode,
    required this.gateName,
    required this.assignedDoorId,
    required this.siteCode,
    required this.siteName,
    required this.assignedDoorName,
    required this.siteApprovalStatus,
    required this.mqttUsername,
    required this.mqttConfigured,
    required this.mqttConnected,
    required this.firmwareVersion,
    required this.otaStatus,
    required this.otaLastVersion,
    required this.wifiRssi,
    required this.wifiSignalPercent,
    required this.lastSeenAt,
    required this.lastEvent,
    this.localIp,
    this.publicIp,
    this.hardwareTarget,
    this.hardwareType,
    required this.createdAt,
    this.ownerUserCode,
    this.ownerUserId,
    this.ownerFullName,
    this.ownerEmail,
    this.isDefective = false,
    this.defectiveReason,
    this.defectiveAt,
    this.inventoryNotes,
  });

  final int id;
  final String deviceUid;
  final int? assignedUserCode;
  final String? gateName;
  final int? assignedDoorId;
  final int? siteCode;
  final String? siteName;
  final String? assignedDoorName;
  final String siteApprovalStatus;
  final String? mqttUsername;
  final bool mqttConfigured;
  final bool? mqttConnected;
  final String? firmwareVersion;
  /// Donanım hedefi ('esp32-c3' | 'esp32-wroom'): sunucudaki `hardware_target` (cihazın bildirdiği),
  /// yoksa `hardware_type` değerinden türetilir.
  final String? hardwareTarget;
  /// Kayıtlı donanım türü (devices.hardware_type: 'esp32_c3' | 'esp32_wroom').
  final String? hardwareType;
  final String? otaStatus;
  final String? otaLastVersion;
  final int? wifiRssi;
  final int? wifiSignalPercent;
  final String? localIp;
  final String? publicIp;
  final DateTime? lastSeenAt;
  final String? lastEvent;
  final DateTime? createdAt;
  final int? ownerUserCode;
  final int? ownerUserId;
  final String? ownerFullName;
  final String? ownerEmail;
  final bool isDefective;
  final String? defectiveReason;
  final DateTime? defectiveAt;
  final String? inventoryNotes;

  /// Cihaz bir kullanıcı tarafından sahiplenilmiş mi (kapıya atanmış olmasa da).
  bool get hasOwner =>
      ownerUserCode != null ||
      ownerUserId != null ||
      (ownerFullName ?? '').isNotEmpty ||
      (ownerEmail ?? '').isNotEmpty;

  /// 'esp32_c3' -> 'esp32-c3' (cihazın bildirdiği / OTA hedef biçimi); boş ise null.
  static String? normalizeHardwareTarget(Object? raw) {
    final text = raw?.toString().trim().toLowerCase().replaceAll('_', '-') ?? '';
    return text.isEmpty ? null : text;
  }

  /// Kayıtlı donanım türü, cihazın bildirdiği hedefle çelişiyor mu (OTA 403 teşhisi için).
  bool get hasHardwareMismatch {
    final typeTarget = normalizeHardwareTarget(hardwareType);
    final target = normalizeHardwareTarget(hardwareTarget);
    return typeTarget != null && target != null && typeTarget != target;
  }

  String get displayOtaStatus {
    if (otaStatus == null || otaStatus!.trim().isEmpty) return '-';
    final s = otaStatus!.trim().toLowerCase();
    if (s == 'guncel' || s == 'up_to_date' || s == 'guncelleme tamam') {
      return 'Güncel';
    }
    if (s == 'guncelleme indiriliyor' || s == 'indiriliyor') {
      if (firmwareVersion != null && otaLastVersion != null && firmwareVersion == otaLastVersion) {
        return 'Güncel';
      }
      return 'İndiriliyor';
    }
    if (s == 'beklemede') return 'Beklemede';
    if (s.contains('hata') || s.contains('basarisiz') || s.contains('failed')) {
      return 'Hata';
    }
    return otaStatus!;
  }

  factory DeviceRecord.fromJson(Map<String, dynamic> json) {
    return DeviceRecord(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      deviceUid: json['device_uid'] as String? ?? '',
      assignedUserCode: int.tryParse(json['assigned_user_code']?.toString() ?? ''),
      gateName: json['gate_name'] as String?,
      assignedDoorId: int.tryParse(json['assigned_door_id']?.toString() ?? ''),
      siteCode: int.tryParse(json['site_code']?.toString() ?? ''),
      siteName: json['site_name'] as String?,
      assignedDoorName: json['assigned_door_name'] as String?,
      siteApprovalStatus: json['site_approval_status'] as String? ?? 'approved',
      mqttUsername: json['mqtt_username'] as String?,
      mqttConfigured: json['mqtt_configured'] as bool? ?? false,
      mqttConnected: json['mqtt_connected'] as bool?,
      firmwareVersion: json['firmware_version'] as String?,
      // Sunucu `hardware_target` (cihaz bildirimi) ve `hardware_type` (kayıtlı tür) gönderir.
      hardwareTarget: normalizeHardwareTarget(json['hardware_target']) ??
          normalizeHardwareTarget(json['hardware_type']),
      hardwareType: json['hardware_type'] as String?,
      otaStatus: json['ota_status'] as String?,
      otaLastVersion: json['ota_last_version'] as String?,
      wifiRssi: int.tryParse(json['wifi_rssi']?.toString() ?? ''),
      wifiSignalPercent: int.tryParse(json['wifi_signal_percent']?.toString() ?? ''),
      localIp: json['local_ip'] as String?,
      publicIp: json['public_ip'] as String? ?? json['client_ip'] as String?,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.tryParse(json['last_seen_at'].toString()),
      lastEvent: json['last_event'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
      ownerUserCode: int.tryParse(json['owner_user_code']?.toString() ?? ''),
      // Eski sunucu yalnız users.id (owner_user_id) döndürür; sahiplik varlığı için yedek.
      ownerUserId: int.tryParse(json['owner_user_id']?.toString() ?? ''),
      ownerFullName: json['owner_full_name'] as String?,
      ownerEmail: json['owner_email'] as String?,
      isDefective: json['is_defective'] == true || json['is_defective'] == 1,
      defectiveReason: json['defective_reason'] as String?,
      defectiveAt: json['defective_at'] == null
          ? null
          : DateTime.tryParse(json['defective_at'].toString()),
      inventoryNotes: json['inventory_notes'] as String?,
    );
  }
}
