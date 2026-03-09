class DoorRecord {
  const DoorRecord({
    required this.id,
    required this.siteCode,
    required this.siteName,
    required this.doorName,
    required this.doorIndex,
    required this.isActive,
    required this.assignedDeviceId,
    required this.assignedDeviceUid,
    required this.mqttSiteId,
    required this.createdAt,
  });

  final int id;
  final int siteCode;
  final String? siteName;
  final String doorName;
  final int doorIndex;
  final bool isActive;
  final int? assignedDeviceId;
  final String? assignedDeviceUid;
  final int? mqttSiteId;
  final DateTime? createdAt;

  factory DoorRecord.fromJson(Map<String, dynamic> json) {
    return DoorRecord(
      id: json['id'] as int,
      siteCode: json['site_code'] as int,
      siteName: json['site_name'] as String?,
      doorName: json['door_name'] as String? ?? '',
      doorIndex: json['door_index'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      assignedDeviceId: json['assigned_device_id'] as int?,
      assignedDeviceUid: json['assigned_device_uid'] as String?,
      mqttSiteId: json['mqtt_site_id'] as int?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
