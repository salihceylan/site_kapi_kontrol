import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

/// Windows masaüstü için doğrudan yerel ağda IP kamera arama servisi.
/// Sunucuya gitmeden, tarayıcı kısıtı olmadan doğrudan:
/// 1. ONVIF WS-Discovery (UDP 3702 çok noktaya yayın - Multicast)
/// 2. Yerel /24 alt ağındaki yaygın kamera portları (80, 554, 8000, 37777, 8899)
/// üzerinden kameraları saniyeler içinde tarar ve döndürür.
class LocalCameraDiscoveryService {
  LocalCameraDiscoveryService._();
  static final LocalCameraDiscoveryService instance = LocalCameraDiscoveryService._();

  static const List<int> _cameraPorts = <int>[80, 554, 8080, 8000, 37777, 8899];
  static const String _onvifProbeXml = '''<?xml version="1.0" encoding="utf-8"?>
<Envelope xmlns:dn="http://www.onvif.org/ver10/network/wsdl" xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Header>
    <wsa:MessageID xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">uuid:c0a80101-0000-0000-0000-000000000001</wsa:MessageID>
    <wsa:To xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>
    <wsa:Action xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>
  </Header>
  <Body>
    <Probe xmlns="http://schemas.xmlsoap.org/ws/2005/04/discovery">
      <Types>dn:NetworkVideoTransmitter</Types>
    </Probe>
  </Body>
</Envelope>''';

  /// Yerel ağdaki kameraları tarar.
  Future<List<DiscoveredDevice>> discoverCameras({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final results = <String, DiscoveredDevice>{};

    // 1. ONVIF WS-Discovery Taraması (UDP 3702)
    try {
      final onvifDevices = await _discoverOnvif(timeout: timeout);
      for (final dev in onvifDevices) {
        results[dev.ip] = dev;
      }
    } catch (e) {
      debugPrint('[LocalCameraDiscovery] ONVIF tarama hatası: $e');
    }

    // 2. Yerel /24 Alt Ağ TCP Port Taraması
    try {
      final localIps = await _getLocalSubnetIps();
      if (localIps.isNotEmpty) {
        final scannedDevices = await _scanSubnetCameras(localIps, existingIps: results.keys.toSet());
        for (final dev in scannedDevices) {
          if (!results.containsKey(dev.ip)) {
            results[dev.ip] = dev;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalCameraDiscovery] TCP alt ağ tarama hatası: $e');
    }

    return results.values.toList();
  }

  /// ONVIF WS-Discovery (UDP 3702)
  Future<List<DiscoveredDevice>> _discoverOnvif({Duration timeout = const Duration(seconds: 3)}) async {
    final devices = <String, DiscoveredDevice>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final probeBytes = utf8.encode(_onvifProbeXml);
      final multicastAddr = InternetAddress('239.255.255.250');
      socket.send(probeBytes, multicastAddr, 3702);

      final completer = Completer<void>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final senderIp = datagram.address.address;
            final responseStr = utf8.decode(datagram.data, allowMalformed: true);
            final dev = _parseOnvifResponse(senderIp, responseStr);
            if (dev != null) {
              devices[senderIp] = dev;
            }
          }
        }
      });

      await completer.future;
      timer.cancel();
    } finally {
      socket?.close();
    }
    return devices.values.toList();
  }

  DiscoveredDevice? _parseOnvifResponse(String ip, String xml) {
    if (!xml.contains('NetworkVideoTransmitter') && !xml.contains('onvif') && !xml.contains('XAddrs')) {
      return null;
    }
    String name = 'IP Kamera (ONVIF)';
    String model = 'ONVIF Uyumlu';
    int? port = 80;

    // XAddrs içinden portu çekmeye çalış
    final xAddrsMatch = RegExp(r'<[^>]*XAddrs[^>]*>([^<]+)<\/').firstMatch(xml);
    if (xAddrsMatch != null) {
      final uriStr = xAddrsMatch.group(1)?.split(' ').first;
      if (uriStr != null) {
        final uri = Uri.tryParse(uriStr);
        if (uri != null && uri.hasPort) {
          port = uri.port;
        }
      }
    }

    if (xml.toLowerCase().contains('hikvision')) {
      name = 'Hikvision Kamera';
      model = 'Hikvision';
    } else if (xml.toLowerCase().contains('dahua')) {
      name = 'Dahua Kamera';
      model = 'Dahua';
    } else if (xml.toLowerCase().contains('tiandy')) {
      name = 'Tiandy Kamera';
      model = 'Tiandy';
    }

    return DiscoveredDevice(
      ip: ip,
      ports: <int>[port, 554],
      name: name,
      model: model,
      source: 'onvif',
      label: '$name ($ip)',
      rtspPort: 554,
    );
  }

  /// Aktif yerel ağın /24 IP bloğunu bulur
  Future<List<String>> _getLocalSubnetIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            // .1 - .254 aralığı
            for (var i = 1; i < 255; i++) {
              ips.add('$subnetPrefix.$i');
            }
            return ips; // İlk geçerli yerel ağı tara
          }
        }
      }
    } catch (_) {}
    return ips;
  }

  /// Alt ağdaki kamera portlarını asenkron olarak paralel tarar
  Future<List<DiscoveredDevice>> _scanSubnetCameras(
    List<String> subnetIps, {
    required Set<String> existingIps,
  }) async {
    final found = <DiscoveredDevice>[];
    const batchSize = 32;

    for (var i = 0; i < subnetIps.length; i += batchSize) {
      final end = (i + batchSize < subnetIps.length) ? i + batchSize : subnetIps.length;
      final batch = subnetIps.sublist(i, end);

      final futures = batch.map((ip) async {
        if (existingIps.contains(ip)) return null;

        final openPorts = <int>[];
        for (final port in _cameraPorts) {
          final isOpen = await _isPortOpen(ip, port, timeout: const Duration(milliseconds: 300));
          if (isOpen) {
            openPorts.add(port);
          }
        }

        if (openPorts.isNotEmpty) {
          String brand = 'IP Kamera';
          if (openPorts.contains(8000)) brand = 'Hikvision / Tiandy Kamera';
          if (openPorts.contains(37777)) brand = 'Dahua Kamera';
          if (openPorts.contains(8080)) brand = 'Sanal / IP Kamera';

          return DiscoveredDevice(
            ip: ip,
            ports: openPorts,
            name: brand,
            model: 'Ağ Kamerası',
            source: 'tarama',
            label: '$brand ($ip)',
            rtspPort: openPorts.contains(554) ? 554 : null,
          );
        }
        return null;
      });

      final batchResults = await Future.wait(futures);
      for (final res in batchResults) {
        if (res != null) found.add(res);
      }
    }

    return found;
  }

  Future<bool> _isPortOpen(String host, int port, {required Duration timeout}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
