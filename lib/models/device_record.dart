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
    required this.createdAt,
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
  final String? otaStatus;
  final String? otaLastVersion;
  final int? wifiRssi;
  final int? wifiSignalPercent;
  final DateTime? lastSeenAt;
  final String? lastEvent;
  final DateTime? createdAt;

  factory DeviceRecord.fromJson(Map<String, dynamic> json) {
    return DeviceRecord(
      id: json['id'] as int,
      deviceUid: json['device_uid'] as String? ?? '',
      assignedUserCode: json['assigned_user_code'] as int?,
      gateName: json['gate_name'] as String?,
      assignedDoorId: json['assigned_door_id'] as int?,
      siteCode: json['site_code'] as int?,
      siteName: json['site_name'] as String?,
      assignedDoorName: json['assigned_door_name'] as String?,
      siteApprovalStatus: json['site_approval_status'] as String? ?? 'approved',
      mqttUsername: json['mqtt_username'] as String?,
      mqttConfigured: json['mqtt_configured'] as bool? ?? false,
      mqttConnected: json['mqtt_connected'] as bool?,
      firmwareVersion: json['firmware_version'] as String?,
      otaStatus: json['ota_status'] as String?,
      otaLastVersion: json['ota_last_version'] as String?,
      wifiRssi: json['wifi_rssi'] as int?,
      wifiSignalPercent: json['wifi_signal_percent'] as int?,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.tryParse(json['last_seen_at'] as String),
      lastEvent: json['last_event'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
