import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

const String bleWifiServiceUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f001';
const String bleWifiStateUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f002';
const String bleWifiCommandUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f003';
const String bleWifiNetworksUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f004';
const String bleWifiResultUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f005';

class BleProvisionException implements Exception {
  const BleProvisionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BleProvisionDevice {
  const BleProvisionDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

class BleWifiState {
  const BleWifiState({
    required this.deviceUid,
    required this.wifiConnected,
    required this.provisioning,
    required this.hasCredentials,
    required this.ssid,
    required this.ip,
  });

  final String deviceUid;
  final bool wifiConnected;
  final bool provisioning;
  final bool hasCredentials;
  final String ssid;
  final String ip;

  factory BleWifiState.fromPayload(String payload) {
    final Map<String, dynamic> json = _decodeJsonMap(payload);
    return BleWifiState(
      deviceUid: (json['device_uid'] ?? '').toString(),
      wifiConnected: json['wifi_connected'] == true,
      provisioning: json['provisioning'] == true,
      hasCredentials: json['has_credentials'] == true,
      ssid: (json['ssid'] ?? '').toString(),
      ip: (json['ip'] ?? '').toString(),
    );
  }
}

class BleWifiNetwork {
  const BleWifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  final String ssid;
  final int rssi;
  final bool secure;
}

class BleWifiResult {
  const BleWifiResult({required this.status, required this.message});

  final String status;
  final String message;

  bool get isFailure => status == 'error' || status == 'failed';
  bool get isScanComplete => status == 'scan_complete';

  factory BleWifiResult.fromPayload(String payload) {
    final Map<String, dynamic> json = _decodeJsonMap(payload);
    return BleWifiResult(
      status: (json['status'] ?? 'idle').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

Map<String, dynamic> _decodeJsonMap(String payload) {
  if (payload.trim().isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{};
}

class BleWifiProvisionService {
  BleWifiProvisionService({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  final Uuid _serviceUuid = Uuid.parse(bleWifiServiceUuid);
  final Uuid _stateUuid = Uuid.parse(bleWifiStateUuid);
  final Uuid _commandUuid = Uuid.parse(bleWifiCommandUuid);
  final Uuid _networksUuid = Uuid.parse(bleWifiNetworksUuid);
  final Uuid _resultUuid = Uuid.parse(bleWifiResultUuid);

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  String? _deviceId;

  bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> ensureReady() async {
    if (!isSupportedPlatform) {
      throw const BleProvisionException(
        'Bluetooth ile Wi-Fi kurulumu yalnizca Android ve iPhone cihazlarda destekleniyor.',
      );
    }

    await _requestPermissions();

    final BleStatus status = await _ble.statusStream
        .firstWhere((BleStatus value) => value != BleStatus.unknown)
        .timeout(const Duration(seconds: 8));

    switch (status) {
      case BleStatus.ready:
        return;
      case BleStatus.poweredOff:
        throw const BleProvisionException(
          'Bluetooth kapali. Once Bluetooth acin.',
        );
      case BleStatus.locationServicesDisabled:
        throw const BleProvisionException(
          'Konum servislerini acip tekrar deneyin.',
        );
      case BleStatus.unauthorized:
        throw const BleProvisionException(
          'Bluetooth izni verilmedi. Uygulama izinlerini acin.',
        );
      case BleStatus.unsupported:
        throw const BleProvisionException(
          'Bu cihaz Bluetooth LE desteklemiyor.',
        );
      case BleStatus.unknown:
        throw const BleProvisionException('Bluetooth durumu okunamadi.');
    }
  }

  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final Map<Permission, PermissionStatus> statuses = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final bool denied = statuses.values.any(
        (PermissionStatus status) => !status.isGranted,
      );
      if (denied) {
        throw const BleProvisionException(
          'Bluetooth tarama ve konum izinleri zorunludur.',
        );
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final PermissionStatus bluetoothStatus = await Permission.bluetooth
          .request();
      if (!bluetoothStatus.isGranted) {
        throw const BleProvisionException('Bluetooth izni verilmedi.');
      }
    }
  }

  Future<List<BleProvisionDevice>> scanDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    await ensureReady();

    final Map<String, BleProvisionDevice> devices =
        <String, BleProvisionDevice>{};
    Object? scanError;

    final StreamSubscription<DiscoveredDevice> subscription = _ble
        .scanForDevices(
          withServices: <Uuid>[_serviceUuid],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(
          (DiscoveredDevice device) {
            final String name = device.name.trim();
            if (!name.toUpperCase().startsWith('AHBU-')) {
              return;
            }
            devices[device.id] = BleProvisionDevice(
              id: device.id,
              name: name,
              rssi: device.rssi,
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            scanError = error;
          },
        );

    await Future<void>.delayed(duration);
    await subscription.cancel();

    if (scanError != null) {
      throw BleProvisionException(_messageFromError(scanError!));
    }

    final List<BleProvisionDevice> values = devices.values.toList()
      ..sort(
        (BleProvisionDevice left, BleProvisionDevice right) =>
            right.rssi.compareTo(left.rssi),
      );
    return values;
  }

  Future<BleWifiState> connect(BleProvisionDevice device) async {
    await ensureReady();
    await disconnect();

    final Completer<void> completer = Completer<void>();
    _deviceId = device.id;
    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: <Uuid, List<Uuid>>{
            _serviceUuid: <Uuid>[
              _stateUuid,
              _commandUuid,
              _networksUuid,
              _resultUuid,
            ],
          },
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (ConnectionStateUpdate update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !completer.isCompleted) {
              completer.complete();
            }
            if (update.connectionState == DeviceConnectionState.disconnected) {
              if (!completer.isCompleted) {
                completer.completeError(
                  const BleProvisionException(
                    'Cihaza baglanilamadi veya baglanti koptu.',
                  ),
                );
              }
              _deviceId = null;
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(
                BleProvisionException(_messageFromError(error)),
              );
            }
            _deviceId = null;
          },
        );

    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw const BleProvisionException(
        'Bluetooth baglantisi zaman asimina ugradi.',
      ),
    );

    try {
      await _ble.requestMtu(deviceId: device.id, mtu: 180);
    } catch (_) {
      // MTU arttirimi zorunlu degil.
    }

    return readState();
  }

  Future<BleWifiState> readState() async {
    final List<int> raw = await _ble.readCharacteristic(
      _qualifiedCharacteristic(_stateUuid),
    );
    return BleWifiState.fromPayload(utf8.decode(raw, allowMalformed: true));
  }

  Future<BleWifiResult> readResult() async {
    final List<int> raw = await _ble.readCharacteristic(
      _qualifiedCharacteristic(_resultUuid),
    );
    return BleWifiResult.fromPayload(utf8.decode(raw, allowMalformed: true));
  }

  Future<List<BleWifiNetwork>> readNetworks() async {
    final List<int> raw = await _ble.readCharacteristic(
      _qualifiedCharacteristic(_networksUuid),
    );
    final Map<String, dynamic> json = _decodeJsonMap(
      utf8.decode(raw, allowMalformed: true),
    );
    final List<dynamic> items =
        (json['networks'] as List<dynamic>?) ?? <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> item) => BleWifiNetwork(
            ssid: (item['ssid'] ?? '').toString(),
            rssi: (item['rssi'] as num?)?.toInt() ?? 0,
            secure: item['secure'] == true,
          ),
        )
        .where((BleWifiNetwork item) => item.ssid.isNotEmpty)
        .toList();
  }

  Future<List<BleWifiNetwork>> scanNetworks() async {
    await _ble.writeCharacteristicWithResponse(
      _qualifiedCharacteristic(_commandUuid),
      value: utf8.encode('{"action":"scan"}'),
    );

    BleWifiResult result = const BleWifiResult(status: 'idle', message: '');
    for (int index = 0; index < 20; index += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      result = await readResult();
      if (result.isFailure) {
        throw BleProvisionException(
          result.message.isEmpty ? 'Wi-Fi taramasi basarisiz.' : result.message,
        );
      }
      if (result.isScanComplete) {
        return readNetworks();
      }
    }

    throw const BleProvisionException('Wi-Fi taramasi zaman asimina ugradi.');
  }

  Future<BleWifiResult> provisionWifi({
    required String ssid,
    required String password,
  }) async {
    if (ssid.trim().isEmpty) {
      throw const BleProvisionException('SSID secimi zorunludur.');
    }

    final String payload = jsonEncode(<String, String>{
      'ssid': ssid.trim(),
      'password': password,
    });
    await _ble.writeCharacteristicWithResponse(
      _qualifiedCharacteristic(_commandUuid),
      value: utf8.encode(payload),
    );

    BleWifiResult result = const BleWifiResult(status: 'idle', message: '');
    for (int index = 0; index < 28; index += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));
      result = await readResult();
      final BleWifiState state = await readState();
      if (state.wifiConnected) {
        return BleWifiResult(
          status: 'connected',
          message: result.message.isEmpty
              ? 'Wi-Fi baglantisi kaydedildi.'
              : result.message,
        );
      }
      if (result.isFailure) {
        throw BleProvisionException(
          result.message.isEmpty
              ? 'Wi-Fi baglantisi kurulamadi.'
              : result.message,
        );
      }
    }

    throw const BleProvisionException('Wi-Fi baglantisi zaman asimina ugradi.');
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _deviceId = null;
  }

  Future<void> dispose() async {
    await disconnect();
  }

  QualifiedCharacteristic _qualifiedCharacteristic(Uuid characteristicUuid) {
    final String? deviceId = _deviceId;
    if (deviceId == null) {
      throw const BleProvisionException('Once Bluetooth cihazina baglanin.');
    }

    return QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );
  }

  String _messageFromError(Object error) {
    final String message = error.toString();
    if (message.isEmpty) {
      return 'Bluetooth islemi basarisiz oldu.';
    }
    return message;
  }
}
