import 'package:flutter/foundation.dart';

class MqttDoorService extends ChangeNotifier {
  MqttDoorService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.siteId,
    required this.doorId,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String siteId;
  final String doorId;

  bool get connecting => false;
  bool get connected => false;
  bool get sending => false;
  bool get commandEnabled => false;
  bool? get doorLocked => null;
  String? get lastEvent => null;
  DateTime? get lastUpdatedAt => null;
  String? get lastError => 'Bu platform MQTT TCP baglantisini desteklemiyor.';

  String get cmdTopic => 'site/$siteId/door/$doorId/cmd';
  String get stateTopic => 'site/$siteId/door/$doorId/state';
  String get eventTopic => 'site/$siteId/door/$doorId/event';

  Future<void> connect() async {}

  Future<String?> sendPulseCommand({required String requestedBy}) async {
    return 'Bu platform MQTT TCP baglantisini desteklemiyor.';
  }
}
