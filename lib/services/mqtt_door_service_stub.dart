import 'package:flutter/foundation.dart';

class MqttDoorService extends ChangeNotifier {
  MqttDoorService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.siteId,
    required this.doorId,
    this.topicPrefix,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String siteId;
  final String doorId;
  final String? topicPrefix;

  bool get connecting => false;
  bool get connected => false;
  bool get sending => false;
  bool get commandEnabled => false;
  bool? get deviceOnline => null;
  bool? get doorLocked => null;
  String? get lastEvent => null;
  DateTime? get lastUpdatedAt => null;
  String? get lastError => 'Bu platform MQTT TCP baglantisini desteklemiyor.';

  String get _topicPrefix => topicPrefix ?? 'site/$siteId/door/$doorId';
  String get cmdTopic => '$_topicPrefix/cmd';
  String get stateTopic => '$_topicPrefix/state';
  String get eventTopic => '$_topicPrefix/event';
  String get availabilityTopic => '$_topicPrefix/availability';

  Future<void> connect() async {}

  Future<String?> sendPulseCommand({required String requestedBy}) async {
    return 'Bu platform MQTT TCP baglantisini desteklemiyor.';
  }
}
