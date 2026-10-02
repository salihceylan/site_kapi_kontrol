class SiteRecord {
  const SiteRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    required this.blockCount,
    required this.apartmentCount,
    this.blockApartmentCounts = const [],
    required this.doorCount,
    required this.approvalStatus,
    required this.approvedAt,
    required this.mqttSiteId,
    required this.managerUserCode,
    required this.managerName,
    this.featureQrEnabled = true,
    this.featureRemoteOpenEnabled = true,
    this.featureLocalUdpEnabled = true,
    this.featureGuestPassEnabled = true,
    this.qrEntryActive = true,
    this.requireGeofence = false,
    this.geofenceLatitude,
    this.geofenceLongitude,
    this.geofenceRadiusMeters = 100,
    this.qrRotationSeconds = 30,
    this.deletionStatus = 'none',
    this.deletionRequestedByUserCode,
    this.deletionRequestedByName,
    this.deletionRequestedByRole,
    this.deletionRequestedAt,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String? address;
  final String? city;
  final String? district;
  final int blockCount;
  final int apartmentCount;
  final List<int> blockApartmentCounts;
  final int doorCount;
  final String approvalStatus;
  final DateTime? approvedAt;
  final int mqttSiteId;
  final int? managerUserCode;
  final String? managerName;
  final bool featureQrEnabled;
  final bool featureRemoteOpenEnabled;
  final bool featureLocalUdpEnabled;
  final bool featureGuestPassEnabled;
  final bool qrEntryActive;
  final bool requireGeofence;
  final double? geofenceLatitude;
  final double? geofenceLongitude;
  final int geofenceRadiusMeters;
  final int qrRotationSeconds;
  final String deletionStatus;
  final int? deletionRequestedByUserCode;
  final String? deletionRequestedByName;
  final String? deletionRequestedByRole;
  final DateTime? deletionRequestedAt;
  final DateTime? createdAt;

  bool get isApproved => approvalStatus == 'approved';

  bool get isDeletionPending =>
      deletionStatus == 'pending_super_user_approval' ||
      deletionStatus == 'pending_site_manager_approval';

  bool get isPendingSuperUserApproval =>
      deletionStatus == 'pending_super_user_approval';

  bool get isPendingSiteManagerApproval =>
      deletionStatus == 'pending_site_manager_approval';

  bool get isAppOnly => featureRemoteOpenEnabled && !featureQrEnabled;
  bool get isQrOnly => !featureRemoteOpenEnabled && featureQrEnabled;
  bool get isHybrid => featureRemoteOpenEnabled && featureQrEnabled;

  String get accessModeLabel {
    if (isAppOnly) return 'Sadece Uygulama';
    if (isQrOnly) return 'Sadece QR Kod';
    return 'Hibrit (Uygulama + QR)';
  }

  String get approvalLabel {
    switch (approvalStatus) {
      case 'pending':
        return 'Onay Bekliyor';
      case 'rejected':
        return 'Reddedildi';
      default:
        return 'Onaylandi';
    }
  }

  SiteRecord copyWith({
    int? id,
    String? name,
    String? address,
    String? city,
    String? district,
    int? blockCount,
    int? apartmentCount,
    List<int>? blockApartmentCounts,
    int? doorCount,
    String? approvalStatus,
    DateTime? approvedAt,
    int? mqttSiteId,
    int? managerUserCode,
    String? managerName,
    bool? featureQrEnabled,
    bool? featureRemoteOpenEnabled,
    bool? featureLocalUdpEnabled,
    bool? featureGuestPassEnabled,
    bool? qrEntryActive,
    bool? requireGeofence,
    double? geofenceLatitude,
    double? geofenceLongitude,
    int? geofenceRadiusMeters,
    int? qrRotationSeconds,
    String? deletionStatus,
    int? deletionRequestedByUserCode,
    String? deletionRequestedByName,
    String? deletionRequestedByRole,
    DateTime? deletionRequestedAt,
    DateTime? createdAt,
  }) {
    return SiteRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      district: district ?? this.district,
      blockCount: blockCount ?? this.blockCount,
      apartmentCount: apartmentCount ?? this.apartmentCount,
      blockApartmentCounts: blockApartmentCounts ?? this.blockApartmentCounts,
      doorCount: doorCount ?? this.doorCount,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      approvedAt: approvedAt ?? this.approvedAt,
      mqttSiteId: mqttSiteId ?? this.mqttSiteId,
      managerUserCode: managerUserCode ?? this.managerUserCode,
      managerName: managerName ?? this.managerName,
      featureQrEnabled: featureQrEnabled ?? this.featureQrEnabled,
      featureRemoteOpenEnabled: featureRemoteOpenEnabled ?? this.featureRemoteOpenEnabled,
      featureLocalUdpEnabled: featureLocalUdpEnabled ?? this.featureLocalUdpEnabled,
      featureGuestPassEnabled: featureGuestPassEnabled ?? this.featureGuestPassEnabled,
      qrEntryActive: qrEntryActive ?? this.qrEntryActive,
      requireGeofence: requireGeofence ?? this.requireGeofence,
      geofenceLatitude: geofenceLatitude ?? this.geofenceLatitude,
      geofenceLongitude: geofenceLongitude ?? this.geofenceLongitude,
      geofenceRadiusMeters: geofenceRadiusMeters ?? this.geofenceRadiusMeters,
      qrRotationSeconds: qrRotationSeconds ?? this.qrRotationSeconds,
      deletionStatus: deletionStatus ?? this.deletionStatus,
      deletionRequestedByUserCode: deletionRequestedByUserCode ?? this.deletionRequestedByUserCode,
      deletionRequestedByName: deletionRequestedByName ?? this.deletionRequestedByName,
      deletionRequestedByRole: deletionRequestedByRole ?? this.deletionRequestedByRole,
      deletionRequestedAt: deletionRequestedAt ?? this.deletionRequestedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  int get siteCode => id;

  factory SiteRecord.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['block_apartment_counts'];
    List<int> counts = [];
    if (rawCounts is List) {
      counts = rawCounts.map((e) => (e as num).toInt()).toList();
    }

    final rawId = json['id'] ?? json['site_code'];
    return SiteRecord(
      id: (rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '') ?? 0),
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      blockCount: (json['block_count'] as num?)?.toInt() ?? 1,
      apartmentCount: (json['apartment_count'] as num?)?.toInt() ?? 0,
      blockApartmentCounts: counts,
      doorCount: (json['door_count'] as num?)?.toInt() ?? 1,
      approvalStatus: json['approval_status'] as String? ?? 'approved',
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.tryParse(json['approved_at'].toString()),
      mqttSiteId: (json['mqtt_site_id'] as num?)?.toInt() ?? 0,
      managerUserCode: json['manager_user_code'] == null
          ? null
          : (json['manager_user_code'] as num?)?.toInt(),
      managerName: json['manager_name'] as String?,
      featureQrEnabled: json['feature_qr_enabled'] as bool? ?? true,
      featureRemoteOpenEnabled: json['feature_remote_open_enabled'] as bool? ?? true,
      featureLocalUdpEnabled: json['feature_local_udp_enabled'] as bool? ?? true,
      featureGuestPassEnabled: json['feature_guest_pass_enabled'] as bool? ?? true,
      qrEntryActive: json['qr_entry_active'] as bool? ?? true,
      requireGeofence: json['require_geofence'] as bool? ?? false,
      geofenceLatitude: (json['geofence_latitude'] as num?)?.toDouble(),
      geofenceLongitude: (json['geofence_longitude'] as num?)?.toDouble(),
      geofenceRadiusMeters: (json['geofence_radius_meters'] as num?)?.toInt() ?? 100,
      qrRotationSeconds: (json['qr_rotation_seconds'] as num?)?.toInt() ?? 30,
      deletionStatus: json['deletion_status'] as String? ?? 'none',
      deletionRequestedByUserCode: (json['deletion_requested_by_user_code'] as num?)?.toInt(),
      deletionRequestedByName: json['deletion_requested_by_name'] as String?,
      deletionRequestedByRole: json['deletion_requested_by_role'] as String?,
      deletionRequestedAt: json['deletion_requested_at'] == null
          ? null
          : DateTime.tryParse(json['deletion_requested_at'].toString()),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }
}
