import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _messageSub;

  bool _connecting = false;
  bool _connected = false;
  bool _sending = false;
  bool? _doorLocked;
  String? _lastEvent;
  DateTime? _lastUpdatedAt;
  String? _lastError;

  bool get connecting => _connecting;
  bool get connected => _connected;
  bool get sending => _sending;
  bool get commandEnabled => _connected && !_sending;
  bool? get doorLocked => _doorLocked;
  String? get lastEvent => _lastEvent;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  String? get lastError => _lastError;

  String get cmdTopic => 'site/$siteId/door/$doorId/cmd';
  String get stateTopic => 'site/$siteId/door/$doorId/state';
  String get eventTopic => 'site/$siteId/door/$doorId/event';

  Future<void> connect() async {
    if (_connected || _connecting) {
      return;
    }

    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final client = MqttServerClient.withPort(
        host,
        'flutter-app-${DateTime.now().millisecondsSinceEpoch}',
        port,
      );
      client.secure = true;
      client.keepAlivePeriod = 20;
      client.logging(on: false);
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;
      client.onAutoReconnect = _onAutoReconnect;
      client.onAutoReconnected = _onAutoReconnected;

      final connMessage = MqttConnectMessage()
          .authenticateAs(username, password)
          .withClientIdentifier(
            'flutter-app-${DateTime.now().millisecondsSinceEpoch}',
          )
          .withWillQos(MqttQos.atLeastOnce)
          .startClean();
      client.connectionMessage = connMessage;

      _client = client;
      await client.connect();

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
          'MQTT baglanti hatasi: ${client.connectionStatus?.state}',
        );
      }

      _messageSub?.cancel();
      _messageSub = client.updates?.listen(_onMessage);

      client.subscribe(stateTopic, MqttQos.atLeastOnce);
      client.subscribe(eventTopic, MqttQos.atLeastOnce);

      _connected = true;
      _lastError = null;
    } catch (e) {
      _connected = false;
      _lastError = 'MQTT baglanamadi: $e';
      _safeDisconnect();
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<String?> sendPulseCommand({required String requestedBy}) async {
    if (!_connected) {
      await connect();
    }

    if (!_connected || _client == null) {
      return _lastError ?? 'MQTT baglantisi kurulamadi.';
    }

    _sending = true;
    _lastError = null;
    notifyListeners();

    try {
      final payload = jsonEncode({
        'action': 'pulse',
        'requested_by': requestedBy,
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      });

      final builder = MqttClientPayloadBuilder()..addString(payload);
      _client!.publishMessage(
        cmdTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );
      return null;
    } catch (e) {
      _lastError = 'Komut gonderilemedi: $e';
      return _lastError;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final envelope in messages) {
      final payloadMessage = envelope.payload;
      if (payloadMessage is! MqttPublishMessage) {
        continue;
      }

      final topic = envelope.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        payloadMessage.payload.message,
      );
      _lastUpdatedAt = DateTime.now();

      if (topic == stateTopic) {
        _applyStatePayload(payload);
      } else if (topic == eventTopic) {
        _lastEvent = payload;
      }
    }

    notifyListeners();
  }

  void _applyStatePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic> && decoded['locked'] is bool) {
        _doorLocked = decoded['locked'] as bool;
      } else if (decoded is Map && decoded['locked'] != null) {
        _doorLocked = decoded['locked'].toString().toLowerCase() == 'true';
      } else {
        _doorLocked = null;
      }
    } catch (_) {
      _doorLocked = null;
    }
  }

  void _onConnected() {
    _connected = true;
    _lastError = null;
    notifyListeners();
  }

  void _onDisconnected() {
    _connected = false;
    notifyListeners();
  }

  void _onAutoReconnect() {
    _connecting = true;
    notifyListeners();
  }

  void _onAutoReconnected() {
    _connecting = false;
    _connected = true;
    _client?.subscribe(stateTopic, MqttQos.atLeastOnce);
    _client?.subscribe(eventTopic, MqttQos.atLeastOnce);
    notifyListeners();
  }

  void _safeDisconnect() {
    try {
      _client?.disconnect();
    } catch (_) {
      // no-op
    }
    _client = null;
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _safeDisconnect();
    super.dispose();
  }
}
