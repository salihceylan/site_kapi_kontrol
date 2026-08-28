import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
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
  LocalDoorService({http.Client? client}) : _client = client ?? http.Client();

  static const Duration _knownIpTimeout = Duration(milliseconds: 900);
  static const Duration _scanTimeout = Duration(milliseconds: 350);
  static const int _scanWorkers = 32;

  final http.Client _client;

  Future<LocalDoorOpenResult> openDoor(LocalDoorAccess access) async {
    if (!access.isUsable) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel kapi anahtari bulunamadi.',
      );
    }

    final foundIp = await _findDeviceIp(access);
    if (foundIp == null) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Cihaz ayni yerel agda bulunamadi.',
      );
    }

    final uri = Uri.http('$foundIp:${access.port}', '/ahbu/open');
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'X-AHBU-Device-Uid': access.deviceUid,
              'X-AHBU-Local-Token': access.token,
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(_knownIpTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return LocalDoorOpenResult(
          ok: true,
          ip: foundIp,
          message: 'Kapi komutu yerel agdan gonderildi.',
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
        message: 'Yerel cihaza komut gonderilemedi.',
      );
    }
  }

  Future<String?> _findDeviceIp(LocalDoorAccess access) async {
    final knownIp = access.ip?.trim();
    if (knownIp != null && knownIp.isNotEmpty) {
      if (await _matchesDevice(knownIp, access, _knownIpTimeout)) {
        return knownIp;
      }
    }

    // Hizli mDNS cozumu: ahbu-<device_uid>.local
    final mdnsHost = 'ahbu-${access.deviceUid.toLowerCase()}.local';
    if (await _matchesDevice(mdnsHost, access, const Duration(milliseconds: 600))) {
      return mdnsHost;
    }

    final candidates = await _candidateIps(knownIp);
    var cursor = 0;
    String? found;

    Future<void> worker() async {
      while (found == null && cursor < candidates.length) {
        final current = candidates[cursor];
        cursor += 1;
        if (await _matchesDevice(current, access, _scanTimeout)) {
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
    Duration timeout,
  ) async {
    final uri = Uri.http('$ip:${access.port}', '/ahbu/status');
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'X-AHBU-Device-Uid': access.deviceUid,
              'X-AHBU-Local-Token': access.token,
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        return false;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final uid = (payload['device_uid'] ?? '').toString().toUpperCase();
      return uid == access.deviceUid.toUpperCase();
    } catch (_) {
      return false;
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

  Future<List<String>> _candidateIps(String? knownIp) async {
    final ownIps = <String>{};
    final candidates = <String>{};
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
          name.contains('ppp')) {
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

    candidates.removeAll(ownIps);
    if (knownIp != null && knownIp.isNotEmpty) {
      candidates.remove(knownIp);
    }
    return candidates.toList();
  }

  void dispose() {
    _client.close();
  }
}
