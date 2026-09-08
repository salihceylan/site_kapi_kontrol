class DeviceConnectivityLogRecord {
  const DeviceConnectivityLogRecord({
    required this.id,
    required this.deviceUid,
    required this.eventType,
    this.onlineAt,
    this.offlineAt,
    this.durationSeconds,
    required this.durationText,
    required this.reason,
    this.wifiRssi,
    this.wifiSignalPercent,
    this.localIp,
    required this.createdAt,
  });

  final int id;
  final String deviceUid;
  final String eventType;
  final DateTime? onlineAt;
  final DateTime? offlineAt;
  final int? durationSeconds;
  final String durationText;
  final String reason;
  final int? wifiRssi;
  final int? wifiSignalPercent;
  final String? localIp;
  final DateTime createdAt;

  factory DeviceConnectivityLogRecord.fromJson(Map<String, dynamic> json) {
    return DeviceConnectivityLogRecord(
      id: json['id'] as int? ?? 0,
      deviceUid: json['device_uid'] as String? ?? '',
      eventType: json['event_type'] as String? ?? 'offline',
      onlineAt: json['online_at'] != null ? DateTime.tryParse(json['online_at'] as String) : null,
      offlineAt: json['offline_at'] != null ? DateTime.tryParse(json['offline_at'] as String) : null,
      durationSeconds: json['duration_seconds'] as int?,
      durationText: json['duration_text'] as String? ?? '-',
      reason: json['reason'] as String? ?? 'Bağlantı Kesildi',
      wifiRssi: json['wifi_rssi'] as int?,
      wifiSignalPercent: json['wifi_signal_percent'] as int?,
      localIp: json['local_ip'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class DeviceConnectivityReport {
  const DeviceConnectivityReport({
    required this.deviceUid,
    required this.isOnline,
    this.currentOnlineSince,
    this.currentOnlineDurationSeconds,
    this.currentOnlineDurationText,
    this.lastOfflineAt,
    required this.logs,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });

  final String deviceUid;
  final bool isOnline;
  final DateTime? currentOnlineSince;
  final int? currentOnlineDurationSeconds;
  final String? currentOnlineDurationText;
  final DateTime? lastOfflineAt;
  final List<DeviceConnectivityLogRecord> logs;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  factory DeviceConnectivityReport.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final rawLogs = json['logs'] as List<dynamic>? ?? [];

    return DeviceConnectivityReport(
      deviceUid: json['device_uid'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      currentOnlineSince: json['current_online_since'] != null
          ? DateTime.tryParse(json['current_online_since'] as String)
          : null,
      currentOnlineDurationSeconds: json['current_online_duration_seconds'] as int?,
      currentOnlineDurationText: json['current_online_duration_text'] as String?,
      lastOfflineAt: json['last_offline_at'] != null
          ? DateTime.tryParse(json['last_offline_at'] as String)
          : null,
      logs: rawLogs
          .whereType<Map<String, dynamic>>()
          .map(DeviceConnectivityLogRecord.fromJson)
          .toList(),
      page: pagination['page'] as int? ?? 1,
      pageSize: pagination['pageSize'] as int? ?? 10,
      total: pagination['total'] as int? ?? 0,
      totalPages: pagination['totalPages'] as int? ?? 1,
    );
  }
}
