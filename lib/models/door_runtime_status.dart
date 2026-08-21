import 'package:site_kapi_kontrol/models/door_record.dart';

class DoorRuntimeStatus {
  const DoorRuntimeStatus({
    required this.door,
    required this.deviceUid,
    required this.mqttBridgeConnected,
    required this.mqttConnected,
    required this.doorLocked,
    required this.lastEvent,
    required this.lastSeenAt,
  });

  final DoorRecord door;
  final String deviceUid;
  final bool mqttBridgeConnected;
  final bool mqttConnected;
  final bool? doorLocked;
  final String? lastEvent;
  final DateTime? lastSeenAt;

  bool get commandEnabled => mqttBridgeConnected && mqttConnected;

  factory DoorRuntimeStatus.fromJson(Map<String, dynamic> json) {
    final status = json['device_status'] as Map<String, dynamic>? ?? {};
    return DoorRuntimeStatus(
      door: DoorRecord.fromJson(json['door'] as Map<String, dynamic>),
      deviceUid: status['device_uid'] as String? ?? '',
      mqttBridgeConnected: status['mqtt_bridge_connected'] as bool? ?? false,
      mqttConnected: status['mqtt_connected'] as bool? ?? false,
      doorLocked: status['door_locked'] as bool?,
      lastEvent: status['last_event'] as String?,
      lastSeenAt: status['last_seen_at'] == null
          ? null
          : DateTime.tryParse(status['last_seen_at'] as String),
    );
  }
}
