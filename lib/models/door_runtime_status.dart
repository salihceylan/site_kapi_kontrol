import 'package:site_kapi_kontrol/models/door_record.dart';

class DoorRuntimeStatus {
  const DoorRuntimeStatus({
    required this.door,
    required this.deviceUid,
    required this.mqttBridgeConnected,
    required this.mqttConnected,
    required this.doorLocked,
    required this.firmwareVersion,
    required this.otaStatus,
    required this.wifiRssi,
    required this.wifiSignalPercent,
    required this.localIp,
    this.publicIp,
    required this.localControlPort,
    required this.localControlToken,
    required this.localControlAvailable,
    required this.lastEvent,
    required this.lastSeenAt,
  });

  final DoorRecord door;
  final String deviceUid;
  final bool mqttBridgeConnected;
  final bool mqttConnected;
  final bool? doorLocked;
  final String? firmwareVersion;
  final String? otaStatus;
  final int? wifiRssi;
  final int? wifiSignalPercent;
  final String? localIp;
  final String? publicIp;
  final int? localControlPort;
  final String? localControlToken;
  final bool localControlAvailable;
  final String? lastEvent;
  final DateTime? lastSeenAt;

  bool get commandEnabled =>
      (mqttBridgeConnected && mqttConnected) ||
      (localControlAvailable &&
          (localControlToken ?? '').isNotEmpty &&
          (localIp ?? '').isNotEmpty);

  factory DoorRuntimeStatus.fromJson(Map<String, dynamic> json) {
    final status = json['device_status'] as Map<String, dynamic>? ?? {};
    final localControl =
        status['local_control'] as Map<String, dynamic>? ?? const {};
    return DoorRuntimeStatus(
      door: DoorRecord.fromJson(json['door'] as Map<String, dynamic>),
      deviceUid: status['device_uid'] as String? ?? '',
      mqttBridgeConnected: status['mqtt_bridge_connected'] as bool? ?? false,
      mqttConnected: status['mqtt_connected'] as bool? ?? false,
      doorLocked: status['door_locked'] as bool?,
      firmwareVersion: status['firmware_version'] as String?,
      otaStatus: status['ota_status'] as String?,
      wifiRssi: status['wifi_rssi'] as int?,
      wifiSignalPercent: status['wifi_signal_percent'] as int?,
      localIp:
          localControl['ip'] as String? ?? status['local_ip'] as String?,
      publicIp: status['public_ip'] as String? ?? status['client_ip'] as String?,
      localControlPort:
          localControl['port'] as int? ?? status['local_control_port'] as int?,
      localControlToken: localControl['token'] as String?,
      localControlAvailable:
          localControl['available'] as bool? ??
          status['local_control_available'] as bool? ??
          false,
      lastEvent: status['last_event'] as String?,
      lastSeenAt: status['last_seen_at'] == null
          ? null
          : DateTime.tryParse(status['last_seen_at'] as String),
    );
  }
}
