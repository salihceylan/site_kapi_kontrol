import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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
    this.challenge,
  });

  final String deviceUid;
  final String ip;
  final int port;
  final DateTime lastSeen;
  final int? rssi;

  /// Cihazın en son duyurduğu tek kullanımlık challenge (`ch`, 16 küçük hex); beacon / keşif / `challenge`
  /// hata yanıtından gelir. Yerel kontrol protokolü v2: açma imzası bu değere bağlıdır.
  final String? challenge;

  bool get isFresh =>
      DateTime.now().difference(lastSeen).inSeconds < 60;

  /// Challenge hâlâ kullanılabilir mi? Cihaz `ch`'yi ~10 sn'de bir döndürür ve her başarılı açmada yeniler;
  /// bu yüzden yalnızca [LocalDoorService.challengeMaxAge] içinde alınmış olan denenir (eskiyse boş gönderilir,
  /// cihaz güncel değeri `challenge` hatasıyla döndürür).
  String? get freshChallenge {
    final ch = challenge;
    if (ch == null) return null;
    return DateTime.now().difference(lastSeen) < LocalDoorService.challengeMaxAge ? ch : null;
  }
}

/// Yerel ağ (UDP) ile kapı açma servisi.
///
/// TEK ÖRNEK: `LocalDoorService()` her çağrıda aynı örneği döndürür; böylece
/// AuthService, app.dart yaşam döngüsü (pause/resume) ve testler aynı soketleri
/// ve beacon önbelleğini paylaşır. Kurucuda yan etki YOKTUR; dinleyici
/// [startBeaconListener] ile (idempotent) başlatılır.
///
/// Güvenlik (C4 + protokol v2): yerel açma yalnızca sunucudan gelen `local_control_token` ile
/// yetkilendirilir; token ağa ASLA çıkmaz. İstek, cihazın yayınladığı tek kullanımlık `ch` (challenge)
/// değerine bağlı `sig = HMAC-SHA256(token, "open|UID|ch")` taşır ([localOpenSignature]). Token yoksa
/// yerel açma denenmez (bulut yoluna düşülür). Şartname: LOCALCTRL_V2 (cihaz: yerel_kontrol_cekirdek.h).
class LocalDoorService {
  factory LocalDoorService() => _instance;

  LocalDoorService._internal();

  static final LocalDoorService _instance = LocalDoorService._internal();

  /// Cihazın yerel UDP/HTTP kontrol portu (firmware YEREL_KAPI_KONTROL_PORT).
  static const int defaultControlPort = 8765;

  static const int _maxCachedDevices = 64;
  static const int _maxDatagramBytes = 1024;
  static final RegExp _uidPattern = RegExp(r'^[0-9A-Z_-]{4,32}$');
  static final RegExp _challengePattern = RegExp(r'^[0-9a-f]{16}$');

  /// Beacon/keşifle alınan challenge'ın denemeye uygun kalma süresi (cihaz ~10 sn'de bir döndürür).
  static const Duration challengeMaxAge = Duration(seconds: 12);

  /// Açma paketinin gidebileceği hedef adres filtresi. Üretimde YALNIZCA özel/yerel ağ adresleri
  /// ([isPrivateLanAddress]); testler döngü adresi (127.0.0.1) için geçici olarak değiştirir.
  @visibleForTesting
  static bool Function(String ip) targetFilter = isPrivateLanAddress;

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

  /// Dinleyici istenen durumda mı? (start/stop idempotansı için)
  bool _beaconActive = false;

  /// Her stop/start döngüsünde artar; geç tamamlanan asenkron bind'lerin
  /// durdurulmuş bir dinleyiciye soket sızdırmasını önler.
  int _beaconGeneration = 0;

  @visibleForTesting
  bool get isBeaconListenerActive => _beaconActive;

  @visibleForTesting
  int get beaconSocketCount => _beaconListenerSockets.length;

  /// Yalnızca özel/yerel ağ adreslerine güvenilir:
  /// 10/8, 172.16/12, 192.168/16 ve link-local 169.254/16.
  static bool isPrivateLanAddress(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) {
      return false;
    }
    final octets = <int>[];
    for (final part in parts) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(part)) {
        return false;
      }
      final value = int.parse(part);
      if (value > 255) {
        return false;
      }
      octets.add(value);
    }
    final first = octets[0];
    final second = octets[1];
    if (first == 10) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    if (first == 192 && second == 168) {
      return true;
    }
    if (first == 169 && second == 254) {
      return true;
    }
    return false;
  }

  static int _sanitizePort(int? port) {
    if (port == null || port < 1024 || port > 65535) {
      return defaultControlPort;
    }
    return port;
  }

  /// Gelen beacon paketini doğrular ve önbelleğe işler.
  ///
  /// - IP adresi YALNIZCA paketin kaynak adresidir (`dg.address`); JSON'daki `ip`
  ///   alanı yok sayılır (sahte yönlendirmeyi önler).
  /// - Kaynak yalnızca özel ağ aralıklarından olabilir.
  /// - Geçersiz / aşırı büyük / JSON olmayan paketler sessizce atılır.
  @visibleForTesting
  CachedDeviceLocation? handleBeaconDatagram(Datagram dg, {DateTime? now}) {
    try {
      if (dg.address.type != InternetAddressType.IPv4) {
        return null;
      }
      final sourceIp = dg.address.address;
      if (!isPrivateLanAddress(sourceIp)) {
        return null;
      }
      if (dg.data.isEmpty || dg.data.length > _maxDatagramBytes) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(dg.data, allowMalformed: true));
      if (decoded is! Map) {
        return null;
      }
      final rawUid = decoded['device_uid'];
      if (rawUid is! String) {
        return null;
      }
      final uid = rawUid.trim().toUpperCase();
      if (!_uidPattern.hasMatch(uid)) {
        return null;
      }
      final rawPort = decoded['port'];
      final port = _sanitizePort(rawPort is num ? rawPort.toInt() : null);
      final rawRssi = decoded['rssi'];
      int? rssi = rawRssi is num ? rawRssi.toInt() : null;
      if (rssi != null && (rssi > 0 || rssi < -127)) {
        rssi = null;
      }

      final seenAt = now ?? DateTime.now();
      final rawCh = decoded['ch'];
      final location = CachedDeviceLocation(
        deviceUid: uid,
        ip: sourceIp,
        port: port,
        lastSeen: seenAt,
        rssi: rssi,
        challenge: rawCh is String && _challengePattern.hasMatch(rawCh) ? rawCh : null,
      );
      _putLocation(location);
      debugPrint('[YerelKapi] Beacon alındı -> UID: $uid, IP: $sourceIp');
      return location;
    } catch (_) {
      return null;
    }
  }

  void _putLocation(CachedDeviceLocation location) {
    if (!_deviceIpCache.containsKey(location.deviceUid) &&
        _deviceIpCache.length >= _maxCachedDevices) {
      _evictOldestCachedDevice();
    }
    _deviceIpCache[location.deviceUid] = location;
  }

  /// Cihazın duyurduğu güncel challenge'ı önbellekteki kayda işler (null: kullanıldı/yenilendi → sonraki açma
  /// önce güncel değeri öğrenir). Kayıt yoksa hiçbir şey yapmaz.
  void _storeChallenge(String uid, String? ch) {
    final cur = _deviceIpCache[uid];
    if (cur == null) return;
    _deviceIpCache[uid] = CachedDeviceLocation(
      deviceUid: cur.deviceUid,
      ip: cur.ip,
      port: cur.port,
      lastSeen: ch != null ? DateTime.now() : cur.lastSeen,
      rssi: cur.rssi,
      challenge: ch,
    );
  }

  /// Yalnızca testler: önbelleğe doğrudan kayıt koyar (döngü adresi beacon filtresinden geçmez).
  @visibleForTesting
  void putDeviceForTest(CachedDeviceLocation location) => _putLocation(location);

  void _evictOldestCachedDevice() {
    String? oldestKey;
    DateTime? oldest;
    _deviceIpCache.forEach((key, value) {
      if (oldest == null || value.lastSeen.isBefore(oldest!)) {
        oldest = value.lastSeen;
        oldestKey = key;
      }
    });
    if (oldestKey != null) {
      _deviceIpCache.remove(oldestKey);
    }
  }

  /// Keşif (discover) yanıtından cihazın IP'sini çıkarır: IP = paketin kaynak
  /// adresi, UID eşleşmeli, kaynak port cihazın kontrol portu olmalı.
  @visibleForTesting
  static String? parseDiscoveryReply(Datagram dg, String expectedUid) {
    try {
      if (dg.address.type != InternetAddressType.IPv4 ||
          !isPrivateLanAddress(dg.address.address) ||
          dg.port != defaultControlPort ||
          dg.data.isEmpty ||
          dg.data.length > _maxDatagramBytes) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(dg.data, allowMalformed: true));
      if (decoded is! Map || decoded['ok'] == false) {
        return null;
      }
      final respUid = decoded['device_uid'];
      if (respUid is! String ||
          respUid.trim().toUpperCase() != expectedUid.trim().toUpperCase()) {
        return null;
      }
      return dg.address.address;
    } catch (_) {
      return null;
    }
  }

  /// Açma isteğine gelen yanıtı doğrular: kaynak ip:port hedefle aynı olmalı,
  /// `ok:true`, `device_uid` hedef UID ile eşleşmeli ve (yanıtta varsa) `nonce`
  /// bizim gönderdiğimizle aynı olmalı.
  @visibleForTesting
  static bool isValidOpenReply({
    required Datagram datagram,
    required String expectedIp,
    required int expectedPort,
    required String expectedUid,
    required String nonce,
  }) {
    try {
      if (datagram.address.address != expectedIp ||
          datagram.port != expectedPort ||
          datagram.data.isEmpty ||
          datagram.data.length > _maxDatagramBytes) {
        return false;
      }
      final decoded = jsonDecode(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      if (decoded is! Map || decoded['ok'] != true) {
        return false;
      }
      final respUid = decoded['device_uid'];
      if (respUid is! String ||
          respUid.trim().toUpperCase() != expectedUid.trim().toUpperCase()) {
        return false;
      }
      final respNonce = decoded['nonce'];
      if (respNonce != null && respNonce.toString() != nonce) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Keşif (discover) yanıtındaki `ch` (challenge). UID eşleşmeli, kaynak özel ağdan ve cihaz portundan olmalı.
  @visibleForTesting
  static String? parseDiscoveryChallenge(Datagram dg, String expectedUid) {
    try {
      if (parseDiscoveryReply(dg, expectedUid) == null) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(dg.data, allowMalformed: true));
      if (decoded is! Map) return null;
      final ch = decoded['ch'];
      return ch is String && _challengePattern.hasMatch(ch) ? ch : null;
    } catch (_) {
      return null;
    }
  }

  /// Açma isteğine gelen `challenge` hata yanıtından güncel `ch`'yi çıkarır: kaynak ip:port hedefle aynı,
  /// `ok:false`, `error:"challenge"`, `device_uid` eşleşir ve (varsa) `nonce` bizimkiyle aynı olmalı.
  @visibleForTesting
  static String? parseChallengeReply({
    required Datagram datagram,
    required String expectedIp,
    required int expectedPort,
    required String expectedUid,
    required String nonce,
  }) {
    try {
      if (datagram.address.address != expectedIp ||
          datagram.port != expectedPort ||
          datagram.data.isEmpty ||
          datagram.data.length > _maxDatagramBytes) {
        return null;
      }
      final decoded = jsonDecode(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      if (decoded is! Map ||
          decoded['ok'] != false ||
          decoded['error'] != 'challenge') {
        return null;
      }
      final respUid = decoded['device_uid'];
      if (respUid is! String ||
          respUid.trim().toUpperCase() != expectedUid.trim().toUpperCase()) {
        return null;
      }
      final respNonce = decoded['nonce'];
      if (respNonce != null && respNonce.toString() != nonce) {
        return null;
      }
      final ch = decoded['ch'];
      return ch is String && _challengePattern.hasMatch(ch) ? ch : null;
    } catch (_) {
      return null;
    }
  }

  /// Yerel kontrol protokolü v2 imzası: `lowerhex(HMAC-SHA256(key = UTF-8(token), msg = action|UID_BÜYÜK|ch))`.
  /// Cihaz (yerel_kontrol_cekirdek.h) ve simülatörle BİLİNEN-CEVAP vektörleriyle doğrulanır (bkz. testler).
  static String localOpenSignature({
    required String token,
    required String uid,
    required String challenge,
    String action = 'open',
  }) {
    final key = utf8.encode(token);
    final message = utf8.encode('$action|${uid.trim().toUpperCase()}|$challenge');
    return Hmac(sha256, key).convert(message).toString();
  }

  static String _generateNonce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(8, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// UDP beacon dinleyicisini başlatır. İdempotent: zaten aktifse hiçbir şey yapmaz.
  Future<void> startBeaconListener() async {
    if (kIsWeb || _beaconActive) return;
    _beaconActive = true;
    final generation = ++_beaconGeneration;
    unawaited(NativeWifiHelper.acquireMulticastLock());

    // anyIPv4 soketi
    await _bindBeaconSocket(InternetAddress.anyIPv4, generation);
    if (generation != _beaconGeneration) return;

    // Wi-Fi arayüzlerine özel soketler (Hücresel açıkken Wi-Fi paketlerinin kaçırılmaması için)
    final wifiAddrs = await getAllLocalWifiAddresses();
    for (final addr in wifiAddrs) {
      if (generation != _beaconGeneration) return;
      await _bindBeaconSocket(addr, generation);
    }
    if (generation != _beaconGeneration) return;

    // Periyodik olarak (her 10 sn) yeni bağlanan Wi-Fi arayüzü varsa dinleyiciyi güncelle
    _beaconRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_refreshBeaconSockets(generation)),
    );

    debugPrint('[YerelKapi] UDP Beacon dinleyicisi port 8765 üzerinde aktif.');
  }

  Future<void> _bindBeaconSocket(
    InternetAddress bindAddr,
    int generation,
  ) async {
    try {
      final socket = await RawDatagramSocket.bind(
        bindAddr,
        defaultControlPort,
        reuseAddress: true,
        reusePort: !(Platform.isWindows || Platform.isAndroid),
      );
      if (generation != _beaconGeneration) {
        // Bind sürerken dinleyici durduruldu: soketi sızdırma.
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _beaconListenerSockets.add(socket);

      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = socket.receive();
            if (dg != null) {
              handleBeaconDatagram(dg);
            }
          }
        },
        onError: (_) {},
        onDone: () => _beaconListenerSockets.remove(socket),
      );
    } catch (_) {}
  }

  Future<void> _refreshBeaconSockets(int generation) async {
    if (generation != _beaconGeneration) return;
    final currentAddrs = await getAllLocalWifiAddresses();
    for (final addr in currentAddrs) {
      if (generation != _beaconGeneration) return;
      final alreadyBound = _beaconListenerSockets.any(
        (s) => s.address.address == addr.address,
      );
      if (!alreadyBound) {
        await _bindBeaconSocket(addr, generation);
      }
    }
  }

  void stopBeaconListener() {
    _beaconActive = false;
    _beaconGeneration++;
    _beaconRefreshTimer?.cancel();
    _beaconRefreshTimer = null;
    for (final s in List<RawDatagramSocket>.of(_beaconListenerSockets)) {
      try {
        s.close();
      } catch (_) {}
    }
    _beaconListenerSockets.clear();
  }

  /// Uygulama arka plana geçtiğinde UDP soketlerini ve periyodik timer'ı kapatarak pil tasarrufu sağlar
  void pauseListening() {
    debugPrint('[YerelKapi] Arka plana geçildi: UDP dinleyici durduruldu (pil tasarrufu).');
    stopBeaconListener();
    unawaited(NativeWifiHelper.releaseMulticastLock());
  }

  /// Uygulama ön plana döndüğünde UDP dinleyicisini yeniden etkinleştirir
  void resumeListening() {
    debugPrint('[YerelKapi] Ön plana dönüldü: UDP dinleyici yeniden başlatılıyor.');
    unawaited(startBeaconListener());
  }

  /// Oturum kapanınca ağ konum önbelleğini temizler.
  void clearCache() {
    _deviceIpCache.clear();
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
            if (isPrivateLanAddress(addr.address) && !results.any((a) => a.address == addr.address)) {
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
          if (isPrivateLanAddress(addr.address) && !results.any((a) => a.address == addr.address)) {
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
    // C4: token yoksa yerel kontrol KAPALI (fail-closed). Ağa hiç çıkmadan buluta düş.
    if (!access.hasToken) {
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel kontrol anahtarı yok, bulut üzerinden açılıyor.',
      );
    }
    final targetIp = access.ip?.trim();

    try {
      final wifiAddr = await _getWifiAddress();
      debugPrint(
        '[YerelKapi] Başlatıldı -> Cihaz: $targetUid, Kayıtlı IP: $targetIp, Telefon Wi-Fi: ${wifiAddr?.address}',
      );

      // 0. SIFIR GECİKME ÖNCELİĞİ: Canlı Beacon Önbelleğindeki Doğrulanmış IP (0 ms Keşif)
      final cached = getCachedDevice(targetUid);
      final effectiveIp = (cached != null &&
              cached.isFresh &&
              targetFilter(cached.ip))
          ? cached.ip
          : null;

      if (effectiveIp != null) {
        debugPrint('[YerelKapi] Canlı beacon önbelleği kullanılıyor -> $effectiveIp');
        final udpOpened = await _directUdpOpen(effectiveIp, access, wifiAddress: wifiAddr);
        if (udpOpened) {
          debugPrint('[YerelKapi] Canlı önbellek ile açıldı ($effectiveIp)');
          return LocalDoorOpenResult(
            ok: true,
            ip: effectiveIp,
            message: 'Kapı yerel ağdan anında açıldı.',
          );
        }
      }

      // Canlı beacon yoksa veya 150ms'de yanıt vermediyse: Kullanıcıyı ASLA bekletme, anında buluta devret!
      debugPrint('[YerelKapi] Yerel ağda canlı cihaz bulunamadı/yanıt vermedi -> Anında buluta devrediliyor.');
      return const LocalDoorOpenResult(
        ok: false,
        ip: null,
        message: 'Yerel ağ yanıt vermedi, bulut üzerinden açılıyor.',
      );
    } finally {
      // Bağı çöz
      unawaited(NativeWifiHelper.unbindNetwork());
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
            socket.send(payload, bcast, defaultControlPort);
          } catch (_) {}
        }

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = socket.receive();
            if (dg != null) {
              // IP = paketin kaynak adresi; JSON'daki `ip` alanına güvenilmez.
              final ip = parseDiscoveryReply(dg, cleanUid);
              if (ip != null) {
                // v2: keşif yanıtı güncel challenge'ı da taşır → ilk açma ek gidiş-dönüş gerektirmez.
                _putLocation(CachedDeviceLocation(
                  deviceUid: cleanUid,
                  ip: ip,
                  port: dg.port,
                  lastSeen: DateTime.now(),
                  challenge: parseDiscoveryChallenge(dg, cleanUid),
                ));
                debugPrint('[YerelKapi] UDP Keşif ile cihaz bulundu -> $ip ($cleanUid)');
                if (!completer.isCompleted) completer.complete(ip);
              }
            }
          }
        }, onError: (_) {});
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


  /// UDP ile yerel açma (protokol v2; cihaz: yerel_kapi_kontrol.h / yerel_kontrol_cekirdek.h).
  ///
  /// Token ASLA ağa çıkmaz. İstek, cihazın yayınladığı tek kullanımlık `ch` değerine bağlı
  /// `sig = HMAC-SHA256(token, "open|UID|ch")` imzasını taşır. `ch` önbellekteki beacon/keşif yanıtından gelir
  /// ([CachedDeviceLocation.freshChallenge]); yoksa/eskiyse boş gönderilir ve cihaz `challenge` hatasıyla güncel
  /// değeri döndürür → aynı soketten TEK yeniden deneme (her denemede 150 ms bekleme penceresi).
  /// Kesin ret (`unauthorized`, `role_mesgul` vb.) yeniden denenmez; çağıran buluta düşer.
  Future<bool> _directUdpOpen(
    String ip,
    LocalDoorAccess access, {
    InternetAddress? wifiAddress,
  }) async {
    final targetUid = access.deviceUid.trim().toUpperCase();
    // C4: token olmadan açma paketi ASLA gönderilmez; hedef yalnızca özel ağ adresi olabilir.
    if (!access.hasToken || !targetFilter(ip)) {
      return false;
    }
    final targetPort = _sanitizePort(access.port);
    final targetAddress = InternetAddress(ip);
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

    // Yanıtı bu isteğe bağlamak için tek kullanımlık nonce (cihaz yankılar).
    final nonce = _generateNonce();
    final cached = getCachedDevice(targetUid);
    var challenge = (cached != null && cached.ip == ip) ? (cached.freshChallenge ?? '') : '';
    var retried = false;

    List<int> buildPayload(String ch) => utf8.encode(jsonEncode({
          'action': 'open',
          'target_uid': targetUid,
          'device_uid': targetUid,
          'ch': ch,
          'sig': ch.isEmpty
              ? ''
              : localOpenSignature(token: access.token, uid: targetUid, challenge: ch),
          'nonce': nonce,
        }));

    final completer = Completer<bool>();
    final activeSockets = <RawDatagramSocket>[];
    Timer? deadline;
    void armDeadline() {
      deadline?.cancel();
      deadline = Timer(const Duration(milliseconds: 150), () {
        if (!completer.isCompleted) completer.complete(false);
      });
    }

    for (final bindAddr in distinctBindAddrs) {
      try {
        final socket = await RawDatagramSocket.bind(bindAddr, 0);
        activeSockets.add(socket);

        socket.send(buildPayload(challenge), targetAddress, targetPort);
        // Hızlı güvenilirlik için 25ms sonra 2. paket (cihaz yinelenen paketi `duplicate:true` ile yanıtlar).
        Future.delayed(const Duration(milliseconds: 25), () {
          if (!completer.isCompleted && !retried) {
            try {
              socket.send(buildPayload(challenge), targetAddress, targetPort);
            } catch (_) {}
          }
        });

        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          if (isValidOpenReply(
            datagram: dg,
            expectedIp: targetAddress.address,
            expectedPort: targetPort,
            expectedUid: targetUid,
            nonce: nonce,
          )) {
            debugPrint('[YerelKapi] UDP açma yanıtı doğrulandı ($ip)');
            _storeChallenge(targetUid, null); // cihaz başarılı açmada challenge'ı yeniler
            if (!completer.isCompleted) completer.complete(true);
            return;
          }
          if (!retried && !completer.isCompleted) {
            final fresh = parseChallengeReply(
              datagram: dg,
              expectedIp: targetAddress.address,
              expectedPort: targetPort,
              expectedUid: targetUid,
              nonce: nonce,
            );
            if (fresh != null) {
              retried = true;
              challenge = fresh;
              _storeChallenge(targetUid, fresh);
              armDeadline(); // yeniden deneme için yeni 150 ms penceresi
              try {
                socket.send(buildPayload(fresh), targetAddress, targetPort);
              } catch (_) {}
            }
          }
        }, onError: (_) {
          // UDP soket hatası (ör. Windows'ta ICMP "port ulaşılamaz" → bağlantı sıfırlama): açma denemesini düşürmesin;
          // bekleme penceresi dolunca çağıran buluta düşer.
        });
      } catch (_) {}
    }

    armDeadline();
    try {
      return await completer.future;
    } catch (e) {
      debugPrint('[YerelKapi] UDP Açma hatası: $e');
      return false;
    } finally {
      deadline?.cancel();
      for (final s in activeSockets) {
        try {
          s.close();
        } catch (_) {}
      }
    }
  }

  /// Soketleri ve zamanlayıcıyı kapatır, önbelleği temizler. Tek örnek yeniden
  /// başlatılabilir (resumeListening / startBeaconListener).
  void dispose() {
    stopBeaconListener();
    unawaited(NativeWifiHelper.releaseMulticastLock());
    clearCache();
  }
}
