import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';

class LocalDoorOpenResult {
  const LocalDoorOpenResult({
    required this.ok,
    required this.ip,
    required this.message,
  });

  final bool ok;
  final String? ip;
  final String message;
}

class LocalDoorService {
  LocalDoorService();

  static const Duration _knownIpTimeout = Duration(milliseconds: 1200);
  static const Duration _scanTimeout = Duration(milliseconds: 400);
  static const int _scanWorkers = 32;

  Future<InternetAddress?> _getWifiAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // 1. Wi-Fi / Ethernet arayüzleri
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('eth') ||
            name.contains('en') ||
            name.contains('ap')) {
          for (final addr in iface.addresses) {
            if (_isPrivateLocalIp(addr.address)) {
              return addr;
            }
          }
        }
      }

      // 2. Mobil veri arayüzleri dışındaki herhangi bir yerel IP
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('rmnet') ||
            name.contains('ccmni') ||
            name.contains('pdp') ||
            name.contains('tun') ||
            name.contains('ppp') ||
            name.contains('cellular') ||
            name.contains('mobile') ||
            name.contains('dummy')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (_isPrivateLocalIp(addr.address)) {
            return addr;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  HttpClient _createHttpClient(Duration timeout, InternetAddress? sourceAddress) {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    if (sourceAddress != null) {
      client.connectionFactory = (uri, host, port) {
        return Socket.startConnect(
          host,
          port ?? 80,
          sourceAddress: sourceAddress,
        );
      };
    }
    return client;
  }

  Future<LocalDoorOpenResult> openDoor(LocalDoorAccess access) async {
    if (kIsWeb) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel ag ile kapi acma yalnizca mobil uygulamada desteklenir.',
      );
    }
    if (!access.isUsable) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel kapı anahtarı bulunamadı.',
      );
    }

    final wifiAddr = await _getWifiAddress();
    final foundIp = await _findDeviceIp(access, wifiAddress: wifiAddr);
    if (foundIp == null) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Cihaz aynı yerel ağda bulunamadı.',
      );
    }

    final client = _createHttpClient(_knownIpTimeout, wifiAddr);
    try {
      final uri = Uri.parse('http://$foundIp:${access.port}/ahbu/open');
      final request = await client.postUrl(uri);
      request.headers.set('X-AHBU-Device-Uid', access.deviceUid);
      request.headers.set('X-AHBU-Local-Token', access.token);
      request.headers.set('Cache-Control', 'no-cache');

      final response = await request.close().timeout(_knownIpTimeout);
      await response.drain<void>();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return LocalDoorOpenResult(
          ok: true,
          ip: foundIp,
          message: 'Kapı komutu yerel ağdan gönderildi.',
        );
      }
      return LocalDoorOpenResult(
        ok: false,
        ip: foundIp,
        message: 'Yerel cihaz komutu reddetti (${response.statusCode}).',
      );
    } catch (_) {
      return LocalDoorOpenResult(
        ok: false,
        ip: foundIp,
        message: 'Yerel cihaza komut gönderilemedi.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _findDeviceIp(
    LocalDoorAccess access, {
    InternetAddress? wifiAddress,
  }) async {
    final knownIp = access.ip?.trim();
    if (knownIp != null && knownIp.isNotEmpty) {
      if (await _matchesDevice(knownIp, access, _knownIpTimeout, wifiAddress: wifiAddress)) {
        return knownIp;
      }
    }

    // Hızlı mDNS çözümü: ahbu-<device_uid>.local
    final mdnsHost = 'ahbu-${access.deviceUid.toLowerCase()}.local';
    if (await _matchesDevice(mdnsHost, access, const Duration(milliseconds: 700), wifiAddress: wifiAddress)) {
      return mdnsHost;
    }

    final candidates = await _candidateIps(knownIp, wifiAddress: wifiAddress);
    var cursor = 0;
    String? found;

    Future<void> worker() async {
      while (found == null && cursor < candidates.length) {
        final current = candidates[cursor];
        cursor += 1;
        if (await _matchesDevice(current, access, _scanTimeout, wifiAddress: wifiAddress)) {
          found = current;
          return;
        }
      }
    }

    final workerCount = candidates.length < _scanWorkers
        ? candidates.length
        : _scanWorkers;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return found;
  }

  Future<bool> _matchesDevice(
    String ip,
    LocalDoorAccess access,
    Duration timeout, {
    InternetAddress? wifiAddress,
  }) async {
    final client = _createHttpClient(timeout, wifiAddress);
    try {
      final uri = Uri.parse('http://$ip:${access.port}/ahbu/status');
      final request = await client.getUrl(uri);
      request.headers.set('X-AHBU-Device-Uid', access.deviceUid);
      request.headers.set('X-AHBU-Local-Token', access.token);
      request.headers.set('Cache-Control', 'no-cache');

      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        return false;
      }
      final body = await response.transform(utf8.decoder).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final uid = (payload['device_uid'] ?? '').toString().toUpperCase();
      return uid == access.deviceUid.toUpperCase();
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  bool _isPrivateLocalIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) {
      return false;
    }
    if (first == 192 && second == 168) {
      return true;
    }
    if (first == 10) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    return false;
  }

  Future<List<String>> _candidateIps(
    String? knownIp, {
    InternetAddress? wifiAddress,
  }) async {
    final ownIps = <String>{};
    final candidates = <String>{};

    if (wifiAddress != null && _isPrivateLocalIp(wifiAddress.address)) {
      final ip = wifiAddress.address;
      ownIps.add(ip);
      final parts = ip.split('.');
      if (parts.length == 4) {
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (var host = 1; host <= 254; host += 1) {
          candidates.add('$prefix.$host');
        }
      }
    } else {
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );

        for (final interface in interfaces) {
          final name = interface.name.toLowerCase();
          if (name.contains('rmnet') ||
              name.contains('ccmni') ||
              name.contains('pdp') ||
              name.contains('tun') ||
              name.contains('ppp') ||
              name.contains('cellular') ||
              name.contains('mobile')) {
            continue;
          }
          for (final address in interface.addresses) {
            final ip = address.address;
            if (!_isPrivateLocalIp(ip)) {
              continue;
            }
            ownIps.add(ip);
            final parts = ip.split('.');
            if (parts.length != 4) {
              continue;
            }
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            for (var host = 1; host <= 254; host += 1) {
              candidates.add('$prefix.$host');
            }
          }
        }
      } catch (_) {}
    }

    candidates.removeAll(ownIps);
    if (knownIp != null && knownIp.isNotEmpty) {
      candidates.remove(knownIp);
    }
    return candidates.toList();
  }

  void dispose() {}
}
