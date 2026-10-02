import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';

/// Yerel kontrol protokolü v2 (challenge'a bağlı HMAC) istemci testleri.
/// Şartname: LOCALCTRL_V2; cihaz tarafı: yerel_kontrol_cekirdek.h (ana makine testleri aynı vektörleri doğrular).

// BİLİNEN-CEVAP vektörü (firmware + simülatör + uygulama aynı değerleri doğrular).
const String kToken = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE';
const String kUid = '240AC4E2E001';
const String kCh = '0123456789abcdef';
const String kSigOpen = '92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4';
const String kSigPulse = '3bb6390fa9c7a2135232000306e9a6293e38fabd736edcf7400ecd55c597b881';

Datagram _dg(Map<String, dynamic> body, {String ip = '192.168.1.50', int port = 8765}) =>
    Datagram(utf8.encode(jsonEncode(body)), InternetAddress(ip), port);

/// v2 cihazının (yerel_kontrol_cekirdek.h) davranışını loopback UDP üzerinde taklit eden sahte cihaz.
/// İmza, uygulamanın kendi fonksiyonundan BAĞIMSIZ olarak (doğrudan package:crypto) hesaplanır.
class FakeV2Device {
  FakeV2Device._(this.socket, this.token, this.uid);

  final RawDatagramSocket socket;
  final String token;
  final String uid;
  bool silent = false;
  String ch = '0123456789abcdef';
  int opens = 0;
  final List<Map<String, dynamic>> received = <Map<String, dynamic>>[];
  String? _lastCh;
  String? _lastSig;
  DateTime? _lastAt;
  final Random _rnd = Random(7);

  int get port => socket.port;

  static Future<FakeV2Device> start({String token = kToken, String uid = kUid}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final device = FakeV2Device._(socket, token, uid);
    socket.listen(device._onEvent);
    return device;
  }

  String _newCh() => List<int>.generate(8, (_) => _rnd.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  void _reply(Datagram dg, Map<String, dynamic> body, String nonce) {
    if (nonce.isNotEmpty) body['nonce'] = nonce;
    socket.send(utf8.encode(jsonEncode(body)), dg.address, dg.port);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final doc = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
    received.add(doc);
    if (silent || doc['action'] != 'open') return;
    final nonce = (doc['nonce'] ?? '').toString();
    final gotCh = (doc['ch'] ?? '').toString();
    final gotSig = (doc['sig'] ?? '').toString();
    final now = DateTime.now();
    if (_lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 3) &&
        gotCh == _lastCh &&
        gotSig == _lastSig) {
      _reply(dg, {'ok': true, 'duplicate': true, 'device_uid': uid}, nonce);
      return;
    }
    if (gotCh != ch) {
      _reply(dg, {'ok': false, 'error': 'challenge', 'ch': ch, 'device_uid': uid}, nonce);
      return;
    }
    final expected = Hmac(sha256, utf8.encode(token)).convert(utf8.encode('open|$uid|$gotCh')).toString();
    if (expected != gotSig) {
      _reply(
        dg,
        {'ok': false, 'error': 'unauthorized', 'device_uid': uid, 'local_control_available': true},
        nonce,
      );
      return;
    }
    opens += 1;
    _lastCh = gotCh;
    _lastSig = gotSig;
    _lastAt = now;
    ch = _newCh(); // başarılı açmada challenge yenilenir
    _reply(dg, {'ok': true, 'message': 'yerel_kapi_acma_komutu_alindi', 'device_uid': uid}, nonce);
  }

  void close() => socket.close();
}

LocalDoorAccess _access(int port, {String token = kToken}) => LocalDoorAccess(
      deviceUid: kUid,
      token: token,
      ip: '127.0.0.1',
      port: port,
      updatedAt: DateTime.now(),
    );

void main() {
  group('localOpenSignature (bilinen-cevap vektörü)', () {
    test('open ve pulse imzaları şartnamedeki vektörlerle birebir eşleşir', () {
      expect(
        LocalDoorService.localOpenSignature(token: kToken, uid: kUid, challenge: kCh),
        kSigOpen,
      );
      expect(
        LocalDoorService.localOpenSignature(token: kToken, uid: kUid, challenge: kCh, action: 'pulse'),
        kSigPulse,
      );
    });

    test('UID küçük harf / boşluklu gelse de BÜYÜK harfe çevrilir; çıktı 64 küçük hex', () {
      final sig = LocalDoorService.localOpenSignature(
        token: kToken,
        uid: ' ${kUid.toLowerCase()} ',
        challenge: kCh,
      );
      expect(sig, kSigOpen);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sig), isTrue);
    });

    test('farklı token / ch / eylem farklı imza üretir', () {
      final base = LocalDoorService.localOpenSignature(token: kToken, uid: kUid, challenge: kCh);
      expect(LocalDoorService.localOpenSignature(token: '${kToken}x', uid: kUid, challenge: kCh), isNot(base));
      expect(LocalDoorService.localOpenSignature(token: kToken, uid: kUid, challenge: 'fedcba9876543210'), isNot(base));
      expect(LocalDoorService.localOpenSignature(token: kToken, uid: kUid, challenge: kCh, action: 'pulse'), isNot(base));
    });
  });

  group('beacon / keşif challenge (ch)', () {
    test('geçerli ch önbelleğe işlenir', () {
      final service = LocalDoorService();
      service.clearCache();
      final location = service.handleBeaconDatagram(
        _dg({'device_uid': kUid, 'port': 8765, 'ch': kCh}),
      );
      expect(location, isNotNull);
      expect(location!.challenge, kCh);
      service.clearCache();
    });

    test('geçersiz ch (büyük harf, kısa, uzun, sayı) yok sayılır', () {
      final service = LocalDoorService();
      for (final bad in <Object?>['0123456789ABCDEF', '0123', '0123456789abcdef0', 12345, null, '']) {
        service.clearCache();
        final location = service.handleBeaconDatagram(
          _dg({'device_uid': kUid, 'port': 8765, 'ch': ?bad}),
        );
        expect(location, isNotNull, reason: 'beacon yine de kabul edilir (ch olmadan)');
        expect(location!.challenge, isNull, reason: 'ch=$bad');
      }
      service.clearCache();
    });

    test('freshChallenge yalnızca challengeMaxAge içinde döner', () {
      final taze = CachedDeviceLocation(
        deviceUid: kUid,
        ip: '192.168.1.50',
        port: 8765,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 2)),
        challenge: kCh,
      );
      final eski = CachedDeviceLocation(
        deviceUid: kUid,
        ip: '192.168.1.50',
        port: 8765,
        lastSeen: DateTime.now().subtract(LocalDoorService.challengeMaxAge + const Duration(seconds: 1)),
        challenge: kCh,
      );
      final yok = CachedDeviceLocation(
        deviceUid: kUid,
        ip: '192.168.1.50',
        port: 8765,
        lastSeen: DateTime.now(),
      );
      expect(taze.freshChallenge, kCh);
      expect(eski.freshChallenge, isNull);
      expect(yok.freshChallenge, isNull);
    });

    test('parseDiscoveryChallenge: UID + kaynak port eşleşmeli, ch geçerli olmalı', () {
      final ok = _dg({'ok': true, 'device_uid': kUid, 'ch': kCh});
      expect(LocalDoorService.parseDiscoveryChallenge(ok, kUid), kCh);
      expect(LocalDoorService.parseDiscoveryChallenge(ok, 'BASKA_UID'), isNull);
      expect(
        LocalDoorService.parseDiscoveryChallenge(_dg({'ok': true, 'device_uid': kUid, 'ch': 'XYZ'}), kUid),
        isNull,
      );
      expect(
        LocalDoorService.parseDiscoveryChallenge(
          _dg({'ok': true, 'device_uid': kUid, 'ch': kCh}, port: 9999),
          kUid,
        ),
        isNull,
      );
      expect(
        LocalDoorService.parseDiscoveryChallenge(
          _dg({'ok': true, 'device_uid': kUid, 'ch': kCh}, ip: '8.8.8.8'),
          kUid,
        ),
        isNull,
      );
    });
  });

  group('parseChallengeReply', () {
    String? parse(Map<String, dynamic> body, {String ip = '192.168.1.50', int port = 8765, String nonce = 'n1'}) {
      return LocalDoorService.parseChallengeReply(
        datagram: _dg(body, ip: ip, port: port),
        expectedIp: '192.168.1.50',
        expectedPort: 8765,
        expectedUid: kUid,
        nonce: nonce,
      );
    }

    final good = <String, dynamic>{
      'ok': false,
      'error': 'challenge',
      'ch': 'fedcba9876543210',
      'device_uid': kUid,
      'nonce': 'n1',
    };

    test('geçerli challenge hata yanıtından ch çıkarılır', () {
      expect(parse(good), 'fedcba9876543210');
    });

    test('nonce yoksa kabul, farklıysa ret', () {
      expect(parse({...good}..remove('nonce')), 'fedcba9876543210');
      expect(parse({...good, 'nonce': 'baska'}), isNull);
    });

    test('kaynak ip/port, uid, ok:true, başka hata kodu ve bozuk ch reddedilir', () {
      expect(parse(good, ip: '192.168.1.99'), isNull);
      expect(parse(good, port: 9999), isNull);
      expect(parse({...good, 'device_uid': 'BASKA_UID'}), isNull);
      expect(parse({...good, 'ok': true}), isNull);
      expect(parse({...good, 'error': 'unauthorized'}), isNull);
      expect(parse({...good, 'ch': 'FEDCBA9876543210'}), isNull);
      expect(parse({...good, 'ch': 'kisa'}), isNull);
      expect(parse({...good}..remove('ch')), isNull);
    });
  });

  group('openDoor ↔ sahte v2 cihaz (loopback UDP)', () {
    late FakeV2Device device;
    final service = LocalDoorService();

    setUp(() async {
      LocalDoorService.targetFilter = (ip) => ip == '127.0.0.1';
      service.clearCache();
      device = await FakeV2Device.start();
    });

    tearDown(() {
      device.close();
      service.clearCache();
      LocalDoorService.targetFilter = LocalDoorService.isPrivateLanAddress;
    });

    test('taze challenge önbellekteyken tek denemede açar; pakette token YOK, ch+sig var', () async {
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
        challenge: device.ch,
      ));

      final result = await service.openDoor(_access(device.port));

      expect(result.ok, isTrue, reason: result.message);
      expect(device.opens, 1, reason: 'yinelenen paket röleyi ikinci kez tetiklememeli');
      expect(device.received, isNotEmpty);
      for (final packet in device.received) {
        expect(packet.containsKey('token'), isFalse);
        expect(jsonEncode(packet).contains(kToken), isFalse, reason: 'token ağa çıkmamalı');
        expect(RegExp(r'^[0-9a-f]{16}$').hasMatch((packet['ch'] ?? '').toString()), isTrue);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch((packet['sig'] ?? '').toString()), isTrue);
        expect(packet['action'], 'open');
        expect(packet['target_uid'], kUid);
      }
    });

    test('challenge bilinmiyorsa: boş ch → challenge hatası → tek yeniden deneme → açar', () async {
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
      ));

      final result = await service.openDoor(_access(device.port));

      expect(result.ok, isTrue, reason: result.message);
      expect(device.opens, 1);
      expect(device.received.first['ch'], '');
      expect(device.received.first['sig'], '');
      expect(
        device.received.any((p) => (p['ch'] ?? '').toString().length == 16 && (p['sig'] ?? '').toString().length == 64),
        isTrue,
        reason: 'yeniden deneme güncel ch ile imzalı gitmeli',
      );
    });

    test('eski (döndürülmüş) challenge → challenge yanıtıyla toparlanır ve açar', () async {
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
        challenge: 'ffffffffffffffff', // cihazın güncel ch'si değil
      ));

      final result = await service.openDoor(_access(device.port));

      expect(result.ok, isTrue, reason: result.message);
      expect(device.opens, 1);
    });

    test('art arda iki açma: ikincisi de (cihaz ch yeniledi) challenge yanıtıyla açılır', () async {
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
        challenge: device.ch,
      ));
      expect((await service.openDoor(_access(device.port))).ok, isTrue);
      expect((await service.openDoor(_access(device.port))).ok, isTrue);
      expect(device.opens, 2);
    });

    test('yanlış token → unauthorized: açılmaz, yeniden deneme döngüsü yok', () async {
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
        challenge: device.ch,
      ));

      final result = await service.openDoor(_access(device.port, token: 'yanlis-token-yanlis-token-yanlis-token'));

      expect(result.ok, isFalse);
      expect(device.opens, 0);
      expect(device.received.length, lessThanOrEqualTo(2), reason: 'ilk paket + en fazla 25 ms yedek paket');
    });

    test('cihaz sessizse kısa sürede vazgeçer (buluta devredilir)', () async {
      device.silent = true;
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
        challenge: device.ch,
      ));

      final watch = Stopwatch()..start();
      final result = await service.openDoor(_access(device.port));
      watch.stop();

      expect(result.ok, isFalse);
      expect(device.opens, 0);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('hedef filtresi: özel ağ dışı adrese açma paketi HİÇ gönderilmez', () async {
      LocalDoorService.targetFilter = LocalDoorService.isPrivateLanAddress; // üretim davranışı
      service.putDeviceForTest(CachedDeviceLocation(
        deviceUid: kUid,
        ip: '127.0.0.1',
        port: device.port,
        lastSeen: DateTime.now(),
        challenge: device.ch,
      ));

      final result = await service.openDoor(_access(device.port));

      expect(result.ok, isFalse);
      expect(device.received, isEmpty);
    });
  });
}
