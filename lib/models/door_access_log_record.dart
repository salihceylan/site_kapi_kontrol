class DoorAccessLogRecord {
  final int id;
  final int siteCode;
  final String? siteName;
  final int? doorId;
  final String doorName;
  final int? userCode;
  final String userName;
  final String? userRole;
  final String? apartmentLabel;
  final String triggerType;
  final DateTime openedAt;
  final String? ipAddress;

  const DoorAccessLogRecord({
    required this.id,
    required this.siteCode,
    this.siteName,
    this.doorId,
    required this.doorName,
    this.userCode,
    required this.userName,
    this.userRole,
    this.apartmentLabel,
    required this.triggerType,
    required this.openedAt,
    this.ipAddress,
  });

  factory DoorAccessLogRecord.fromJson(Map<String, dynamic> json) {
    return DoorAccessLogRecord(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      siteCode: int.tryParse(json['site_code']?.toString() ?? '') ?? 0,
      siteName: json['site_name'] as String?,
      doorId: int.tryParse(json['door_id']?.toString() ?? ''),
      doorName: (json['door_name'] as String?)?.trim() ?? 'Site Kapısı',
      userCode: int.tryParse(json['user_code']?.toString() ?? ''),
      userName: (json['user_name'] as String?)?.trim() ?? 'Yetkili Kullanıcı',
      userRole: json['user_role'] as String?,
      apartmentLabel: json['apartment_label'] as String?,
      triggerType: json['trigger_type'] as String? ?? 'cloud_app',
      openedAt: DateTime.tryParse(json['opened_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      ipAddress: json['ip_address'] as String?,
    );
  }

  String get triggerTypeDisplay {
    switch (triggerType) {
      case 'voice':
        return 'Sesli Komut';
      case 'local_wifi':
        return 'Yerel Wi-Fi';
      case 'guest_pass':
        return 'Misafir Linki';
      case 'offline_sync':
        return 'Çevrimdışı (ESP32)';
      case 'cloud_app':
      default:
        return 'Mobil Bulut';
    }
  }

  String get userRoleDisplay {
    switch (userRole) {
      case 'super_user':
        return 'Süper Yönetici';
      case 'site_manager':
        return 'Site Yöneticisi';
      case 'apartment_owner':
        return 'Daire Sakini';
      case 'guest_pass':
        return 'Misafir / Kurye';
      default:
        return 'Kullanıcı';
    }
  }
}

class DoorAccessLogPage {
  final List<DoorAccessLogRecord> logs;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  const DoorAccessLogPage({
    required this.logs,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory DoorAccessLogPage.fromJson(Map<String, dynamic> json) {
    final list = (json['logs'] as List<dynamic>? ?? [])
        .map((e) => DoorAccessLogRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return DoorAccessLogPage(
      logs: list,
      total: int.tryParse(json['total']?.toString() ?? '') ?? list.length,
      page: int.tryParse(json['page']?.toString() ?? '') ?? 1,
      pageSize: int.tryParse(json['page_size']?.toString() ?? '') ?? 50,
      totalPages: int.tryParse(json['total_pages']?.toString() ?? '') ?? 1,
    );
  }
}

