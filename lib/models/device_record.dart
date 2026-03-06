class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.deviceUid,
    required this.assignedUserCode,
    required this.siteCode,
    required this.createdAt,
  });

  final int id;
  final String deviceUid;
  final int? assignedUserCode;
  final int? siteCode;
  final DateTime? createdAt;

  factory DeviceRecord.fromJson(Map<String, dynamic> json) {
    return DeviceRecord(
      id: json['id'] as int,
      deviceUid: json['device_uid'] as String? ?? '',
      assignedUserCode: json['assigned_user_code'] as int?,
      siteCode: json['site_code'] as int?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
