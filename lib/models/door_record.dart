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
    this.featureQrEnabled = true,
    this.featureRemoteOpenEnabled = true,
    this.featureLocalUdpEnabled = true,
    this.featureGuestPassEnabled = true,
    this.qrEntryActive = true,
    this.requireGeofence = false,
    this.geofenceLatitude,
    this.geofenceLongitude,
    this.geofenceRadiusMeters = 75,
    this.qrTotpSecret,
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
  final bool featureQrEnabled;
  final bool featureRemoteOpenEnabled;
  final bool featureLocalUdpEnabled;
  final bool featureGuestPassEnabled;
  final bool qrEntryActive;
  final bool requireGeofence;
  final double? geofenceLatitude;
  final double? geofenceLongitude;
  final int geofenceRadiusMeters;
  final String? qrTotpSecret;
  final DateTime? createdAt;

  bool get canOpenRemote => featureRemoteOpenEnabled;
  bool get canOpenLocalUdp => featureLocalUdpEnabled;
  bool get canOpenQr => featureQrEnabled && qrEntryActive;
  bool get canCreateGuestPass => featureGuestPassEnabled;

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
      featureQrEnabled: json['feature_qr_enabled'] as bool? ?? true,
      featureRemoteOpenEnabled: json['feature_remote_open_enabled'] as bool? ?? true,
      featureLocalUdpEnabled: json['feature_local_udp_enabled'] as bool? ?? true,
      featureGuestPassEnabled: json['feature_guest_pass_enabled'] as bool? ?? true,
      qrEntryActive: json['qr_entry_active'] as bool? ?? true,
      requireGeofence: json['require_geofence'] as bool? ?? false,
      geofenceLatitude: (json['geofence_latitude'] as num?)?.toDouble(),
      geofenceLongitude: (json['geofence_longitude'] as num?)?.toDouble(),
      geofenceRadiusMeters: (json['geofence_radius_meters'] as num?)?.toInt() ?? 75,
      qrTotpSecret: json['qr_totp_secret'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
