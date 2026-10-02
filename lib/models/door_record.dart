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
    this.geofenceRadiusMeters = 100,
    this.qrRotationSeconds = 30,
    this.assignedDeviceHardwareTarget,
    this.assignedDeviceHardwareType,
    this.assignedDeviceFirmwareVersion,
    this.assignedDeviceIsOnline,
    this.assignedDeviceLocalIp,
    this.assignedDevicePublicIp,
    this.assignedDeviceWifiRssi,
    this.assignedDeviceWifiSignalPercent,
    this.assignedDeviceLastSeenAt,
    this.assignedDeviceQrReaderEnabled = false,
    this.accessScope = 'SITE_COMMON',
    this.blockId,
    this.blockName,
    required this.createdAt,
  });

  final int id;
  final int siteCode;
  final String? siteName;
  final String doorName;
  final int doorIndex;
  final bool isActive;
  final String accessScope;
  final int? blockId;
  final String? blockName;
  final int? assignedDeviceId;
  final String? assignedDeviceUid;
  final String? assignedDeviceHardwareTarget;
  final String? assignedDeviceHardwareType;
  final String? assignedDeviceFirmwareVersion;
  final bool? assignedDeviceIsOnline;
  final String? assignedDeviceLocalIp;
  final String? assignedDevicePublicIp;
  final int? assignedDeviceWifiRssi;
  final int? assignedDeviceWifiSignalPercent;
  final DateTime? assignedDeviceLastSeenAt;
  final bool assignedDeviceQrReaderEnabled;
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
  final int qrRotationSeconds;
  final DateTime? createdAt;

  /// Alan alan değer eşitliği. `==` BİLEREK değiştirilmedi (nesne kimliği olarak kalır); yoklama
  /// sonucu ekrandakiyle aynıysa arayüzü gereksiz yeniden kurmamak için kullanılır.
  bool hasSameFieldsAs(DoorRecord other) =>
      identical(this, other) || _fieldValues == other._fieldValues;

  /// Tüm alanların kaydı (kayıtlar yapısal olarak karşılaştırılır).
  Object get _fieldValues => (
        id,
        siteCode,
        siteName,
        doorName,
        doorIndex,
        isActive,
        accessScope,
        blockId,
        blockName,
        assignedDeviceId,
        assignedDeviceUid,
        assignedDeviceHardwareTarget,
        assignedDeviceHardwareType,
        assignedDeviceFirmwareVersion,
        assignedDeviceIsOnline,
        assignedDeviceLocalIp,
        assignedDevicePublicIp,
        assignedDeviceWifiRssi,
        assignedDeviceWifiSignalPercent,
        assignedDeviceLastSeenAt,
        assignedDeviceQrReaderEnabled,
        mqttSiteId,
        featureQrEnabled,
        featureRemoteOpenEnabled,
        featureLocalUdpEnabled,
        featureGuestPassEnabled,
        qrEntryActive,
        requireGeofence,
        geofenceLatitude,
        geofenceLongitude,
        geofenceRadiusMeters,
        qrRotationSeconds,
        createdAt,
      );

  bool get canOpenRemote => featureRemoteOpenEnabled;
  bool get canOpenLocalUdp => featureLocalUdpEnabled;

  /// Kapıda fiziksel bir optik QR okuyucu (GM60 vb.) kameranın bulunup bulunmadığı
  bool get hasPhysicalQrScanner =>
      hasDevice && !isHardwareC3 && assignedDeviceQrReaderEnabled;

  /// Sakinin bu kapıda dinamik QR kodu okutarak geçiş yapabilmesi için:
  /// 1. Kapı ve site politikasında QR ile geçiş aktif olmalı (featureQrEnabled && qrEntryActive)
  /// 2. Kapıya atanmış donanımda fiziksel olarak GM60 QR okuyucu bulunmalı ve aktif olmalı (C3 olmamalı, qr_reader_enabled: true olmalı)
  bool get canOpenQr =>
      featureQrEnabled && qrEntryActive && hasPhysicalQrScanner;

  bool get canShowQrCode => canOpenQr;
  bool get canCreateGuestPass => featureGuestPassEnabled;

  bool get hasDevice => assignedDeviceUid != null && assignedDeviceUid!.trim().isNotEmpty;

  /// Karekod okutarak açarken konumun istemci tarafından GÖNDERİLMESİ gerekir mi?
  /// Site konum doğrulaması açıksa; ayrıca ekransız (statik UID karekodlu) cihazlarda sunucu
  /// site bayrağından bağımsız olarak konum ister (sözleşme C3).
  bool get requiresLocationForQrScan => requireGeofence || (hasDevice && !hasDisplay);

  String get hardwareBadgeText {
    final target = (assignedDeviceHardwareTarget ?? assignedDeviceHardwareType ?? '').toLowerCase();
    if (target.contains('wroom')) return 'ESP32-WROOM';
    if (target.contains('c3')) return 'ESP32-C3';
    if (target.isNotEmpty) return target.toUpperCase();
    return hasDevice ? 'ESP32' : 'CİHAZ YOK';
  }

  String get hardwareModelTitle {
    final target = (assignedDeviceHardwareTarget ?? assignedDeviceHardwareType ?? '').toLowerCase();
    if (target.contains('wroom')) return 'ESP32-WROOM-32E Röle Kartı';
    if (target.contains('c3')) return 'ESP32-C3 Süper Mini';
    if (target.isNotEmpty) return target.toUpperCase();
    return hasDevice ? 'ESP32 Cihazı' : 'Cihaz Atanmamış';
  }

  bool get isHardwareWroom {
    final target = (assignedDeviceHardwareTarget ?? assignedDeviceHardwareType ?? '').toLowerCase();
    return target.contains('wroom') || target.contains('esp32dev');
  }

  /// Bu kapıda fiziksel 2.4" ekran bulunup bulunmadığı (Sadece ESP32-WROOM modellerinde mevcuttur)
  bool get hasDisplay => hasDevice && (isHardwareWroom || (!isHardwareC3 && (assignedDeviceHardwareTarget ?? '').isEmpty));

  bool get isQrOnly => !canOpenRemote && (canOpenQr || hasDisplay);

  bool get isHardwareC3 =>
      (assignedDeviceHardwareTarget ?? assignedDeviceHardwareType ?? '').toLowerCase().contains('c3');

  bool get isSiteCommon => accessScope == 'SITE_COMMON';
  bool get isBlockScope => accessScope == 'BLOCK';
  bool get isCustomScope => accessScope == 'CUSTOM';

  String get accessScopeLabel {
    if (isBlockScope) {
      return blockName != null && blockName!.isNotEmpty ? '$blockName Kapısı' : 'Blok Kapısı';
    }
    if (isCustomScope) return 'Özel Giriş';
    return 'Site Ortak Giriş';
  }

  factory DoorRecord.fromJson(Map<String, dynamic> json) {
    return DoorRecord(
      id: json['id'] as int,
      siteCode: json['site_code'] as int,
      siteName: json['site_name'] as String?,
      doorName: json['door_name'] as String? ?? '',
      doorIndex: json['door_index'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      accessScope: json['access_scope'] as String? ?? 'SITE_COMMON',
      blockId: json['block_id'] as int?,
      blockName: json['block_name'] as String?,
      assignedDeviceId: json['assigned_device_id'] as int?,
      assignedDeviceUid: json['assigned_device_uid'] as String?,
      assignedDeviceHardwareTarget: json['assigned_device_hardware_target'] as String? ?? json['hardware_target'] as String?,
      assignedDeviceHardwareType: json['assigned_device_hardware_type'] as String? ?? json['hardware_type'] as String?,
      assignedDeviceFirmwareVersion: json['assigned_device_firmware_version'] as String? ?? json['firmware_version'] as String?,
      assignedDeviceIsOnline: json['assigned_device_is_online'] as bool? ?? json['is_online'] as bool?,
      assignedDeviceLocalIp: json['assigned_device_local_ip'] as String? ?? json['local_ip'] as String?,
      assignedDevicePublicIp: json['assigned_device_public_ip'] as String? ?? json['public_ip'] as String?,
      assignedDeviceWifiRssi: (json['assigned_device_wifi_rssi'] as num?)?.toInt() ?? (json['wifi_rssi'] as num?)?.toInt(),
      assignedDeviceWifiSignalPercent: (json['assigned_device_wifi_signal_percent'] as num?)?.toInt() ?? (json['wifi_signal_percent'] as num?)?.toInt(),
      assignedDeviceLastSeenAt: json['assigned_device_last_seen_at'] == null
          ? (json['last_seen_at'] == null ? null : DateTime.tryParse(json['last_seen_at'] as String))
          : DateTime.tryParse(json['assigned_device_last_seen_at'] as String),
      assignedDeviceQrReaderEnabled: json['assigned_device_qr_reader_enabled'] as bool? ?? false,
      mqttSiteId: json['mqtt_site_id'] as int?,
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
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
