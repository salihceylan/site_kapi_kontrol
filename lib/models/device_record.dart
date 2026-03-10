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
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
