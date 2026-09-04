import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';

class NativeWifiHelper {
  static const MethodChannel _channel =
      MethodChannel('com.example.site_kapi_kontrol/wifi_helper');

  static Future<bool> isWifiConnected() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isWifiConnected');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> bindToWifiNetwork() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('bindToWifiNetwork');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unbindNetwork() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('unbindNetwork');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> acquireMulticastLock() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('acquireMulticastLock');
    } catch (_) {}
  }

  static Future<void> releaseMulticastLock() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseMulticastLock');
    } catch (_) {}
  }
}

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

class CachedDeviceLocation {
  const CachedDeviceLocation({
    required this.deviceUid,
    required this.ip,
    required this.port,
    required this.lastSeen,
    this.rssi,
  });

  final String deviceUid;
  final String ip;
  final int port;
  final DateTime lastSeen;
  final int? rssi;

  bool get isFresh =>
      DateTime.now().difference(lastSeen).inSeconds < 60;
}

class LocalDoorService {
  LocalDoorService() {
    startBeaconListener();
  }

  static const Duration _scanTimeout = Duration(milliseconds: 250);
  static const int _scanWorkers = 64;

  static const _cellularKeywords = [
    'rmnet',
    'ccmni',
    'pdp',
    'wwan',
    'cellular',
    'mobile',
    'radio',
    'dummy',
    'tun',
    'tap',
    'v4-rmnet',
    'v6-rmnet',
    'lo',
    'p2p',
    'sit',
    'ip6',
    'bond',
  ];

  final Map<String, CachedDeviceLocation> _deviceIpCache = {};
  final List<RawDatagramSocket> _beaconListenerSockets = [];
  Timer? _beaconRefreshTimer;

  void startBeaconListener() async {
    if (kIsWeb) return;
    stopBeaconListener();
    unawaited(NativeWifiHelper.acquireMulticastLock());

    void bindAndListen(InternetAddress bindAddr) async {
      try {
        final socket = await RawDatagramSocket.bind(
          bindAddr,
          8765,
          reuseAddress: true,
          reusePort: !Platform.isWindows,
        );
        socket.broadcastEnabled = true;
        _beaconListenerSockets.add(socket);

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = socket.receive();
            if (dg != null) {
              try {
                final text = utf8.decode(dg.data, allowMalformed: true);
                final json = jsonDecode(text) as Map<String, dynamic>;
                final uid = (json['device_uid'] as String?)?.trim().toUpperCase();
                if (uid != null && uid.isNotEmpty) {
                  final ip = (json['ip'] as String?)?.trim() ?? dg.address.address;
                  final port = (json['port'] as num?)?.toInt() ?? 8765;
                  final rssi = (json['rssi'] as num?)?.toInt();
                  _deviceIpCache[uid] = CachedDeviceLocation(
                    deviceUid: uid,
                    ip: ip,
                    port: port,
                    lastSeen: DateTime.now(),
                    rssi: rssi,
                  );
                  debugPrint('[YerelKapi] 📡 Beacon alındı (${bindAddr.address}) -> UID: $uid, IP: $ip, Port: $port, RSSI: $rssi');
                }
              } catch (_) {}
            }
          }
        });
      } catch (_) {}
    }

    // anyIPv4 soketi
    bindAndListen(InternetAddress.anyIPv4);

    // Wi-Fi arayüzlerine özel soketler (Hücresel açıkken Wi-Fi paketlerinin kaçırılmaması için)
    final wifiAddrs = await getAllLocalWifiAddresses();
    for (final addr in wifiAddrs) {
      bindAndListen(addr);
    }

    // Periyodik olarak (her 10 sn) yeni bağlanan Wi-Fi arayüzü varsa dinleyiciyi güncelle
    _beaconRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final currentAddrs = await getAllLocalWifiAddresses();
      for (final addr in currentAddrs) {
        final alreadyBound = _beaconListenerSockets.any(
          (s) => s.address.address == addr.address,
        );
        if (!alreadyBound) {
          bindAndListen(addr);
        }
      }
    });

    debugPrint('[YerelKapi] UDP Beacon dinleyicisi port 8765 üzerinde aktif.');
  }

  void stopBeaconListener() {
    _beaconRefreshTimer?.cancel();
    _beaconRefreshTimer = null;
    for (final s in _beaconListenerSockets) {
      try {
        s.close();
      } catch (_) {}
    }
    _beaconListenerSockets.clear();
  }

  CachedDeviceLocation? getCachedDevice(String deviceUid) {
    final cleanUid = deviceUid.trim().toUpperCase();
    final cached = _deviceIpCache[cleanUid];
    if (cached != null && cached.isFresh) {
      return cached;
    }
    return null;
  }

  Future<bool> hasLocalWifiConnection() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final nativeWifi = await NativeWifiHelper.isWifiConnected();
      if (nativeWifi) return true;
    }
    final addrs = await getAllLocalWifiAddresses();
    return addrs.isNotEmpty;
  }

  Future<List<InternetAddress>> getAllLocalWifiAddresses() async {
    final results = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // 1. ÖNCE: Kesin Wi-Fi / Ethernet arayüzleri (wlan*, wifi*, eth*, en*, wl*, lan*)
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (_cellularKeywords.any((k) => name.contains(k))) {
          continue;
        }
        if (name.startsWith('wlan') ||
            name.startsWith('wifi') ||
            name.startsWith('eth') ||
            name.startsWith('en') ||
            name.startsWith('wl') ||
            name.startsWith('lan')) {
          for (final addr in iface.addresses) {
            if (_isPrivateLocalIp(addr.address) && !results.any((a) => a.address == addr.address)) {
              results.add(addr);
            }
          }
        }
      }

      // 2. İKİNCİL: Diğer hücresel olmayan yerel arayüzler
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (_cellularKeywords.any((k) => name.contains(k))) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (_isPrivateLocalIp(addr.address) && !results.any((a) => a.address == addr.address)) {
            results.add(addr);
          }
        }
      }
    } catch (_) {}
    return results;
  }

  Future<InternetAddress?> _getWifiAddress() async {
    final list = await getAllLocalWifiAddresses();
    return list.isNotEmpty ? list.first : null;
  }

  Future<LocalDoorOpenResult> openDoor(LocalDoorAccess access) async {
    if (kIsWeb) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel ağ ile kapı açma yalnızca mobil uygulamada desteklenir.',
      );
    }
    final targetUid = access.deviceUid.trim().toUpperCase();
    if (targetUid.isEmpty) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Cihaz kimliği bulunamadı.',
      );
    }

    // Android: Hücresel açık olsa bile tüm soketleri Wi-Fi arayüzüne bağla
    await NativeWifiHelper.bindToWifiNetwork();

    try {
      final wifiAddr = await _getWifiAddress();
      final knownIp = access.ip?.trim();
      debugPrint(
        '[YerelKapi] Başlatıldı -> Cihaz: $targetUid, Kayıtlı IP: $knownIp, Telefon Wi-Fi: ${wifiAddr?.address}',
      );

      // 0. SIFIR GECİKME ÖNCELİĞİ: Canlı Beacon Önbelleğindeki Doğrulanmış IP (0 ms Keşif)
      final cached = getCachedDevice(targetUid);
      if (cached != null && cached.ip.isNotEmpty) {
        debugPrint('[YerelKapi] ⚡ CANLI BEACON ÖNBELLEĞİ KULLANILIYOR -> ${cached.ip}:8765 (0 ms Keşif)');
        final udpOpened = await _directUdpOpen(cached.ip, access, wifiAddress: wifiAddr);
        if (udpOpened) {
          debugPrint('[YerelKapi] ⚡ CANLI ÖNBELLEK İLE ANINDA AÇILDI! (${cached.ip})');
          return LocalDoorOpenResult(
            ok: true,
            ip: cached.ip,
            message: 'Kapı yerel ağdan anında açıldı.',
          );
        }
      }

      // 1. Bilinen IP varsa önce kimliğini doğrula ve sadece ona özel aç
      if (knownIp != null && knownIp.isNotEmpty) {
        final matches = await _probeDeviceIp(
          knownIp,
          targetUid,
          wifiAddress: wifiAddr,
          timeout: const Duration(milliseconds: 100),
        );
        if (matches) {
          debugPrint('[YerelKapi] Kayıtlı IP ($knownIp) doğrulandı, UNICAST UDP deneniyor...');
          final udpOpened = await _directUdpOpen(knownIp, access, wifiAddress: wifiAddr);
          if (udpOpened) {
            debugPrint('[YerelKapi] Kayıtlı IP ($knownIp) UNICAST UDP ile açıldı!');
            _deviceIpCache[targetUid] = CachedDeviceLocation(
              deviceUid: targetUid,
              ip: knownIp,
              port: access.port,
              lastSeen: DateTime.now(),
            );
            return LocalDoorOpenResult(
              ok: true,
              ip: knownIp,
              message: 'Kapı yerel ağdan başarıyla açıldı.',
            );
          }

          final postOpened = await _directPostOpen(
            knownIp,
            access,
            const Duration(milliseconds: 300),
            wifiAddress: wifiAddr,
          );
          if (postOpened) {
            debugPrint('[YerelKapi] Kayıtlı IP ($knownIp) HTTP üzerinden açıldı!');
            return LocalDoorOpenResult(
              ok: true,
              ip: knownIp,
              message: 'Kapı yerel ağdan başarıyla açıldı.',
            );
          }
        }
      }

      // 2. IP bilinmiyorsa veya değiştiyse UDP Alt Ağ Keşif ile hedef UID'ye sahip cihazın IP'sini bul
      debugPrint('[YerelKapi] UDP Keşif ile hedef cihaz ($targetUid) aranıyor...');
      final discoveredIp = await _discoverDeviceIpViaUdp(
        targetUid,
        wifiAddress: wifiAddr,
      );
      if (discoveredIp != null && discoveredIp.isNotEmpty) {
        debugPrint('[YerelKapi] Hedef IP ($discoveredIp) bulundu, UNICAST UDP ile açılıyor...');
        final udpOpened = await _directUdpOpen(discoveredIp, access, wifiAddress: wifiAddr);
        if (udpOpened) {
          debugPrint('[YerelKapi] Hedef IP ($discoveredIp) UNICAST UDP ile açıldı!');
          _deviceIpCache[targetUid] = CachedDeviceLocation(
            deviceUid: targetUid,
            ip: discoveredIp,
            port: access.port,
            lastSeen: DateTime.now(),
          );
          return LocalDoorOpenResult(
            ok: true,
            ip: discoveredIp,
            message: 'Kapı yerel ağdan başarıyla açıldı.',
          );
        }

        final postOpened = await _directPostOpen(
          discoveredIp,
          access,
          const Duration(milliseconds: 350),
          wifiAddress: wifiAddr,
        );
        if (postOpened) {
          return LocalDoorOpenResult(
            ok: true,
            ip: discoveredIp,
            message: 'Kapı yerel ağdan başarıyla açıldı.',
          );
        }
      }

      // 3. Alt ağdaki tüm aday IP'leri kimlik sorgusuyla (discover) tara (ASLA röle tetiklemez!)
      final candidates = await _candidateIps(knownIp, wifiAddress: wifiAddr);
      debugPrint(
        '[YerelKapi] Alt ağ kimlik taraması başlatılıyor (${candidates.length} aday IP)...',
      );
      var cursor = 0;
      String? foundIp;
      var stopped = false;

      Future<void> worker() async {
        while (!stopped && cursor < candidates.length) {
          final current = candidates[cursor];
          cursor += 1;
          final matches = await _probeDeviceIp(
            current,
            targetUid,
            wifiAddress: wifiAddr,
            timeout: _scanTimeout,
          );
          if (matches && !stopped) {
            debugPrint('[YerelKapi] Alt ağ taramasında eşleşen cihaz bulundu -> $current');
            final ok = await _directPostOpen(
              current,
              access,
              const Duration(milliseconds: 350),
              wifiAddress: wifiAddr,
            );
            if (ok && !stopped) {
              foundIp = current;
              stopped = true;
              _deviceIpCache[targetUid] = CachedDeviceLocation(
                deviceUid: targetUid,
                ip: current,
                port: access.port,
                lastSeen: DateTime.now(),
              );
              return;
            }
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
    } finally {
      // Bulut isteklerinin hücresel veya varsayılan ağdan devam edebilmesi için bağı çöz
      await NativeWifiHelper.unbindNetwork();
    }
  }

  Future<String?> _discoverDeviceIpViaUdp(
    String deviceUid, {
    InternetAddress? wifiAddress,
  }) async {
    final cleanUid = deviceUid.trim().toUpperCase();
    final wifiAddrs = await getAllLocalWifiAddresses();
    final bindAddrs = <InternetAddress>[
      ?wifiAddress,
      ...wifiAddrs,
      InternetAddress.anyIPv4,
    ];

    final distinctBindAddrs = <InternetAddress>[];
    for (final a in bindAddrs) {
      if (!distinctBindAddrs.any((x) => x.address == a.address)) {
        distinctBindAddrs.add(a);
      }
    }

    final targetBroadcasts = <InternetAddress>{};
    for (final a in wifiAddrs) {
      final parts = a.address.split('.');
      if (parts.length == 4) {
        targetBroadcasts.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
      }
    }
    targetBroadcasts.add(InternetAddress('255.255.255.255'));
    targetBroadcasts.add(InternetAddress('192.168.1.255'));
    targetBroadcasts.add(InternetAddress('192.168.0.255'));
    targetBroadcasts.add(InternetAddress('192.168.4.255'));
    targetBroadcasts.add(InternetAddress('192.168.2.255'));
    targetBroadcasts.add(InternetAddress('192.168.178.255'));

    final payload = utf8.encode(jsonEncode({
      'action': 'discover',
      'target_uid': cleanUid,
    }));

    final completer = Completer<String?>();
    final activeSockets = <RawDatagramSocket>[];

    for (final bindAddr in distinctBindAddrs) {
      try {
        final socket = await RawDatagramSocket.bind(bindAddr, 0);
        socket.broadcastEnabled = true;
        activeSockets.add(socket);

        for (final bcast in targetBroadcasts) {
          try {
            socket.send(payload, bcast, 8765);
          } catch (_) {}
        }

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = socket.receive();
            if (dg != null) {
              final text = utf8.decode(dg.data, allowMalformed: true);
              try {
                final json = jsonDecode(text) as Map<String, dynamic>;
                final respUid = (json['device_uid'] as String?)?.trim().toUpperCase();
                if (respUid != null && respUid == cleanUid) {
                  final ip = json['ip'] as String? ?? dg.address.address;
                  debugPrint('[YerelKapi] UDP Keşif ile cihaz bulundu -> $ip ($respUid)');
                  if (!completer.isCompleted) completer.complete(ip);
                }
              } catch (_) {
                if (text.contains(cleanUid)) {
                  final fallbackIp = dg.address.address;
                  if (!completer.isCompleted) completer.complete(fallbackIp);
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    try {
      return await completer.future.timeout(
        const Duration(milliseconds: 350),
        onTimeout: () => null,
      );
    } finally {
      for (final s in activeSockets) {
        try {
          s.close();
        } catch (_) {}
      }
    }
  }

  Future<bool> isDeviceReachableLocally(String deviceUid) async {
    if (kIsWeb || deviceUid.trim().isEmpty) return false;
    final cached = getCachedDevice(deviceUid);
    if (cached != null) return true;
    await NativeWifiHelper.bindToWifiNetwork();
    try {
      final wifiAddr = await _getWifiAddress();
      if (wifiAddr == null) return false;
      final ip = await _discoverDeviceIpViaUdp(deviceUid, wifiAddress: wifiAddr);
      return ip != null && ip.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      await NativeWifiHelper.unbindNetwork();
    }
  }

  Future<bool> _probeDeviceIp(
    String ip,
    String targetUid, {
    InternetAddress? wifiAddress,
    Duration timeout = const Duration(milliseconds: 120),
  }) async {
    if (kIsWeb || ip.trim().isEmpty || targetUid.trim().isEmpty) return false;
    final cleanUid = targetUid.trim().toUpperCase();
    final payload = utf8.encode(jsonEncode({
      'action': 'discover',
      'target_uid': cleanUid,
    }));

    final wifiAddrs = await getAllLocalWifiAddresses();
    final bindAddrs = <InternetAddress>[
      ?wifiAddress,
      ...wifiAddrs,
      InternetAddress.anyIPv4,
    ];

    final distinctBindAddrs = <InternetAddress>[];
    for (final a in bindAddrs) {
      if (!distinctBindAddrs.any((x) => x.address == a.address)) {
        distinctBindAddrs.add(a);
      }
    }

    final completer = Completer<bool>();
    final activeSockets = <RawDatagramSocket>[];

    for (final bindAddr in distinctBindAddrs) {
      try {
        final socket = await RawDatagramSocket.bind(bindAddr, 0);
        activeSockets.add(socket);
        socket.send(payload, InternetAddress(ip), 8765);

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = socket.receive();
            if (dg != null) {
              final text = utf8.decode(dg.data, allowMalformed: true);
              try {
                final json = jsonDecode(text) as Map<String, dynamic>;
                final respUid = (json['device_uid'] as String?)?.trim().toUpperCase();
                if (respUid != null && respUid == cleanUid) {
                  if (!completer.isCompleted) completer.complete(true);
                }
              } catch (_) {
                if (text.contains(cleanUid)) {
                  if (!completer.isCompleted) completer.complete(true);
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      for (final s in activeSockets) {
        try {
          s.close();
        } catch (_) {}
      }
    }
  }

  Future<bool> _directUdpOpen(
    String ip,
    LocalDoorAccess access, {
    InternetAddress? wifiAddress,
  }) async {
    final targetUid = access.deviceUid.trim().toUpperCase();
    final wifiAddrs = await getAllLocalWifiAddresses();
    final bindAddrs = <InternetAddress>[
      ?wifiAddress,
      ...wifiAddrs,
      InternetAddress.anyIPv4,
    ];

    final distinctBindAddrs = <InternetAddress>[];
    for (final a in bindAddrs) {
      if (!distinctBindAddrs.any((x) => x.address == a.address)) {
        distinctBindAddrs.add(a);
      }
    }

    final payload = utf8.encode(jsonEncode({
      'action': 'open',
      'target_uid': targetUid,
      'device_uid': targetUid,
      'token': access.token,
    }));

    final completer = Completer<bool>();
    final activeSockets = <RawDatagramSocket>[];

    for (final bindAddr in distinctBindAddrs) {
      try {
        final socket = await RawDatagramSocket.bind(bindAddr, 0);
        activeSockets.add(socket);

        socket.send(payload, InternetAddress(ip), access.port);
        // Hızlı güvenilirlik için 25ms sonra 2. paket
        Future.delayed(const Duration(milliseconds: 25), () {
          if (!completer.isCompleted) {
            try {
              socket.send(payload, InternetAddress(ip), access.port);
            } catch (_) {}
          }
        });

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = socket.receive();
            if (dg != null) {
              final text = utf8.decode(dg.data, allowMalformed: true);
              debugPrint('[YerelKapi] UDP Açma yanıtı geldi: $text');
              try {
                final json = jsonDecode(text) as Map<String, dynamic>;
                final respUid = (json['device_uid'] as String?)?.trim().toUpperCase();
                if (json['ok'] == true && (respUid == null || respUid == targetUid)) {
                  if (!completer.isCompleted) completer.complete(true);
                }
              } catch (_) {
                if (text.contains('"ok":true') && (text.contains(targetUid) || !text.contains('device_uid'))) {
                  if (!completer.isCompleted) completer.complete(true);
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    try {
      return await completer.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[YerelKapi] UDP Açma hatası: $e');
      return false;
    } finally {
      for (final s in activeSockets) {
        try {
          s.close();
        } catch (_) {}
      }
    }
  }

  Future<bool> _directPostOpen(
    String ip,
    LocalDoorAccess access,
    Duration timeout, {
    InternetAddress? wifiAddress,
  }) async {
    // 1. Hızlı ve doğrudan UNICAST UDP ile açmayı dene (1-5 ms)
    final udpOk = await _directUdpOpen(ip, access, wifiAddress: wifiAddress);
    if (udpOk) {
      debugPrint('[YerelKapi] UDP doğrudan komutuyla kapı AÇILDI! ($ip)');
      return true;
    }

    // 2. Raw Socket POST (Wi-Fi arayüzüne bağlı)
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
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode >= 200 &&
          response.statusCode < 300 &&
          body.contains('"ok":true');
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
          final isHttpSuccess = text.contains('HTTP/1.1 200') ||
              text.contains('HTTP/1.1 202');
          if (isHttpSuccess && text.contains('"ok":true')) {
            if (!completer.isCompleted) completer.complete(true);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) {
            final text = utf8.decode(buffer, allowMalformed: true);
            final isHttpSuccess = text.contains('HTTP/1.1 200') ||
                text.contains('HTTP/1.1 202');
            completer.complete(isHttpSuccess && text.contains('"ok":true'));
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
    final candidates = <String>[];
    final added = <String>{};

    void addIp(String ip) {
      if (ip != knownIp && !ownIps.contains(ip) && added.add(ip)) {
        candidates.add(ip);
      }
    }

    final wifiAddrs = await getAllLocalWifiAddresses();
    for (final a in wifiAddrs) {
      final ip = a.address;
      ownIps.add(ip);
      final parts = ip.split('.');
      if (parts.length == 4) {
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (var host = 1; host <= 254; host += 1) {
          addIp('$prefix.$host');
        }
      }
    }

    if (wifiAddress != null) {
      final ip = wifiAddress.address;
      ownIps.add(ip);
      final parts = ip.split('.');
      if (parts.length == 4) {
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (var host = 1; host <= 254; host += 1) {
          addIp('$prefix.$host');
        }
      }
    }

    // Standart alt ağlar
    for (final prefix in const [
      '192.168.1',
      '192.168.0',
      '192.168.4',
      '192.168.2',
      '192.168.178',
    ]) {
      for (var host = 1; host <= 254; host += 1) {
        addIp('$prefix.$host');
      }
    }

    return candidates;
  }

  void dispose() {
    stopBeaconListener();
  }
}
