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

  static const Duration _knownIpTimeout = Duration(milliseconds: 1500);
  static const Duration _scanTimeout = Duration(milliseconds: 600);
  static const int _scanWorkers = 64;

  Future<bool> hasLocalWifiConnection() async {
    final addr = await _getWifiAddress();
    return addr != null;
  }

  Future<InternetAddress?> _getWifiAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        debugPrint(
          '[AğArayüzü] Bulundu: ${iface.name} -> ${iface.addresses.map((a) => a.address).join(', ')}',
        );
      }

      // 1. Kesin Wi-Fi / Ethernet arayüzleri (wlan0, wlan1, wifi, eth)
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isWifiName = name.startsWith('wlan') ||
            name.startsWith('wifi') ||
            name == 'wlan0' ||
            name == 'wlan1' ||
            name.startsWith('eth');
        if (isWifiName) {
          for (final addr in iface.addresses) {
            if (_isPrivateLocalIp(addr.address)) {
              return addr;
            }
          }
        }
      }

      // 2. İkincil kontrol: Kesinlikle hücresel/mobil olmayan özel yerel IP'ler
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('rmnet') ||
            name.contains('ipa') ||
            name.contains('radio') ||
            name.contains('clat') ||
            name.contains('ccmni') ||
            name.contains('pdp') ||
            name.contains('tun') ||
            name.contains('ppp') ||
            name.contains('cellular') ||
            name.contains('mobile') ||
            name.contains('wwan') ||
            name.contains('epdg') ||
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

  Future<LocalDoorOpenResult> openDoor(LocalDoorAccess access) async {
    if (kIsWeb) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel ağ ile kapı açma yalnızca mobil uygulamada desteklenir.',
      );
    }
    if (access.deviceUid.trim().isEmpty) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Cihaz kimliği bulunamadı.',
      );
    }

    final wifiAddr = await _getWifiAddress();
    debugPrint(
      '[YerelKapi] Başlatıldı -> Cihaz: ${access.deviceUid}, Kayıtlı IP: ${access.ip}, Telefon Wi-Fi: ${wifiAddr?.address}',
    );

    // 1. Bilinen IP varsa doğrudan kapıyı açmayı dene
    final knownIp = access.ip?.trim();
    if (knownIp != null && knownIp.isNotEmpty) {
      debugPrint('[YerelKapi] Kayıtlı IP deneniyor: $knownIp...');
      final opened = await _directPostOpen(
        knownIp,
        access,
        _knownIpTimeout,
        wifiAddress: wifiAddr,
      );
      if (opened) {
        debugPrint('[YerelKapi] Kayıtlı IP ($knownIp) üzerinden açıldı!');
        return LocalDoorOpenResult(
          ok: true,
          ip: knownIp,
          message: 'Kapı yerel ağdan başarıyla açıldı.',
        );
      }
    }

    // 2. mDNS üzerinden dene (ahbu-<uid>.local)
    final mdnsHost = 'ahbu-${access.deviceUid.toLowerCase()}.local';
    final mdnsOpened = await _directPostOpen(
      mdnsHost,
      access,
      const Duration(milliseconds: 900),
      wifiAddress: wifiAddr,
    );
    if (mdnsOpened) {
      debugPrint('[YerelKapi] mDNS ($mdnsHost) üzerinden açıldı!');
      return LocalDoorOpenResult(
        ok: true,
        ip: mdnsHost,
        message: 'Kapı yerel ağdan başarıyla açıldı.',
      );
    }

    // 3. Alt ağdaki tüm aday IP'leri hızlı paralel işçilerle dene
    final candidates = await _candidateIps(knownIp, wifiAddress: wifiAddr);
    debugPrint(
      '[YerelKapi] Alt ağ taraması başlatılıyor (${candidates.length} aday IP)...',
    );
    var cursor = 0;
    String? foundIp;
    var stopped = false;

    Future<void> worker() async {
      while (!stopped && cursor < candidates.length) {
        final current = candidates[cursor];
        cursor += 1;
        final ok = await _directPostOpen(
          current,
          access,
          _scanTimeout,
          wifiAddress: wifiAddr,
        );
        if (ok && !stopped) {
          foundIp = current;
          stopped = true;
          return;
        }
      }
    }

    final workerCount =
        candidates.length < _scanWorkers ? candidates.length : _scanWorkers;
    if (workerCount > 0) {
      await Future.wait(List.generate(workerCount, (_) => worker()));
    }

    if (foundIp != null) {
      debugPrint('[YerelKapi] Tarama başarılı! Cihaz bulundu: $foundIp');
      return LocalDoorOpenResult(
        ok: true,
        ip: foundIp,
        message: 'Kapı yerel ağdan başarıyla açıldı.',
      );
    }

    debugPrint('[YerelKapi] Cihaz yerel ağda bulunamadı.');
    return const LocalDoorOpenResult(
      ok: false,
      ip: null,
      message:
          'Cihaz yerel ağda bulunamadı. Lütfen telefonunuzun cihazla aynı Wi-Fi ağına bağlı olduğundan emin olun.',
    );
  }

  Future<bool> _directPostOpen(
    String ip,
    LocalDoorAccess access,
    Duration timeout, {
    InternetAddress? wifiAddress,
  }) async {
    // 1. Raw Socket POST (Wi-Fi arayüzüne bağlı)
    final socketOk = await _rawSocketPost(
      ip,
      access.port,
      access.deviceUid,
      access.token,
      timeout,
      wifiAddress: wifiAddress,
    );
    if (socketOk) {
      return true;
    }

    // 2. Raw Socket POST (Bağlamasız direkt soket)
    if (wifiAddress != null) {
      final socketOk2 = await _rawSocketPost(
        ip,
        access.port,
        access.deviceUid,
        access.token,
        timeout,
        wifiAddress: null,
      );
      if (socketOk2) {
        return true;
      }
    }

    // 3. HttpClient POST yedeği
    final client = _createHttpClient(timeout, wifiAddress);
    try {
      final uri = Uri.parse('http://$ip:${access.port}/ahbu/open');
      final request = await client.postUrl(uri);
      request.headers.set('X-AHBU-Device-Uid', access.deviceUid);
      if (access.token.isNotEmpty) {
        request.headers.set('X-AHBU-Local-Token', access.token);
      }
      request.headers.set('Cache-Control', 'no-cache');

      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _rawSocketPost(
    String host,
    int port,
    String deviceUid,
    String token,
    Duration timeout, {
    InternetAddress? wifiAddress,
  }) async {
    Socket? socket;
    try {
      if (wifiAddress != null) {
        try {
          socket = await Socket.connect(
            host,
            port,
            sourceAddress: wifiAddress,
            timeout: timeout,
          );
        } catch (_) {
          socket = await Socket.connect(host, port, timeout: timeout);
        }
      } else {
        socket = await Socket.connect(host, port, timeout: timeout);
      }

      final payload =
          'POST /ahbu/open HTTP/1.1\r\n'
          'Host: $host:$port\r\n'
          'X-AHBU-Device-Uid: $deviceUid\r\n'
          '${token.isNotEmpty ? 'X-AHBU-Local-Token: $token\r\n' : ''}'
          'Content-Length: 0\r\n'
          'Connection: close\r\n\r\n';

      socket.write(payload);
      await socket.flush();

      final buffer = <int>[];
      final completer = Completer<bool>();
      late StreamSubscription<List<int>> sub;

      sub = socket.listen(
        (data) {
          buffer.addAll(data);
          final text = utf8.decode(buffer, allowMalformed: true);
          if (text.contains('202') ||
              text.contains('200') ||
              text.contains('"ok":true')) {
            if (!completer.isCompleted) completer.complete(true);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) {
            final text = utf8.decode(buffer, allowMalformed: true);
            completer.complete(
              text.contains('202') ||
                  text.contains('200') ||
                  text.contains('"ok":true'),
            );
          }
        },
        cancelOnError: true,
      );

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      await sub.cancel();
      return result;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  HttpClient _createHttpClient(
    Duration timeout,
    InternetAddress? sourceAddress,
  ) {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    if (sourceAddress != null) {
      client.connectionFactory = (uri, host, port) async {
        try {
          return await Socket.startConnect(
            host,
            port ?? 80,
            sourceAddress: sourceAddress,
          );
        } catch (_) {
          return await Socket.startConnect(host, port ?? 80);
        }
      };
    }
    return client;
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

    // 1. Eğer telefonun gerçek Wi-Fi IP'si bulunduysa öncelikle o bloğu ekle
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
    }

    // 2. Standart ev/site modem ağlarını DAİMA adaylara ekle
    for (final prefix in const [
      '192.168.1',
      '192.168.0',
      '192.168.4',
      '192.168.2',
      '192.168.178',
    ]) {
      for (var host = 1; host <= 254; host += 1) {
        candidates.add('$prefix.$host');
      }
    }

    candidates.removeAll(ownIps);
    if (knownIp != null && knownIp.isNotEmpty) {
      candidates.remove(knownIp);
    }
    return candidates.toList(growable: false);
  }

  void dispose() {}
}
