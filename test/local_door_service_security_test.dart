import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';

Datagram _dg(Object payload, String ip, [int port = 8765]) {
  final bytes = payload is String
      ? utf8.encode(payload)
      : utf8.encode(jsonEncode(payload));
  return Datagram(Uint8List.fromList(bytes), InternetAddress(ip), port);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isPrivateLanAddress', () {
    test('accepts RFC1918 and link-local ranges', () {
      for (final ip in [
        '10.0.0.1',
        '10.255.255.254',
        '172.16.0.1',
        '172.31.255.1',
        '192.168.0.10',
        '192.168.1.255',
        '169.254.1.5',
      ]) {
        expect(LocalDoorService.isPrivateLanAddress(ip), isTrue, reason: ip);
      }
    });

    test('rejects public, loopback, malformed and out-of-range addresses', () {
      for (final ip in [
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '192.169.0.1',
        '169.253.1.1',
        '127.0.0.1',
        '0.0.0.0',
        '11.0.0.1',
        '256.1.1.1',
        '10.0.0',
        '10.0.0.0.1',
        '10.0.0.x',
        '10.0.0.+1',
        '',
        'abc',
      ]) {
        expect(LocalDoorService.isPrivateLanAddress(ip), isFalse, reason: ip);
      }
    });
  });

  group('handleBeaconDatagram (beacon IP = paket kaynağı)', () {
    late LocalDoorService service;

    setUp(() {
      service = LocalDoorService();
      service.clearCache();
    });

    test('uses the datagram source address and IGNORES the json "ip" field', () {
      final now = DateTime.now();
      final loc = service.handleBeaconDatagram(
        _dg(
          {
            'device_uid': 'aabbccddeeff',
            'ip': '203.0.113.50', // saldırgan yönlendirmesi: yok sayılmalı
            'port': 8765,
            'rssi': -55,
          },
          '192.168.1.50',
        ),
        now: now,
      );

      expect(loc, isNotNull);
      expect(loc!.deviceUid, 'AABBCCDDEEFF');
      expect(loc.ip, '192.168.1.50');
      expect(loc.port, 8765);
      expect(loc.rssi, -55);
      expect(service.getCachedDevice('aabbccddeeff')?.ip, '192.168.1.50');
    });

    test('beacons from public / non-private sources are dropped', () {
      final res = service.handleBeaconDatagram(
        _dg({'device_uid': 'AABBCCDDEEFF', 'ip': '192.168.1.5'}, '203.0.113.9'),
      );
      expect(res, isNull);
      expect(service.getCachedDevice('AABBCCDDEEFF'), isNull);
    });

    test('link-local source is accepted', () {
      final res = service.handleBeaconDatagram(
        _dg({'device_uid': 'AABBCCDDEEFF'}, '169.254.10.20'),
      );
      expect(res?.ip, '169.254.10.20');
    });

    test('invalid port falls back to 8765; invalid rssi is dropped', () {
      final res = service.handleBeaconDatagram(
        _dg({'device_uid': 'AABBCCDDEEFF', 'port': 22, 'rssi': 40}, '10.0.0.7'),
      );
      expect(res?.port, 8765);
      expect(res?.rssi, isNull);
    });

    test('malformed / oversized / non-json / bad-uid packets are ignored', () {
      expect(service.handleBeaconDatagram(_dg('not json', '192.168.1.5')), isNull);
      expect(service.handleBeaconDatagram(_dg('[1,2,3]', '192.168.1.5')), isNull);
      expect(service.handleBeaconDatagram(_dg({'x': 1}, '192.168.1.5')), isNull);
      expect(
        service.handleBeaconDatagram(_dg({'device_uid': '<script>'}, '192.168.1.5')),
        isNull,
      );
      expect(
        service.handleBeaconDatagram(_dg({'device_uid': 123}, '192.168.1.5')),
        isNull,
      );
      expect(
        service.handleBeaconDatagram(
          _dg({'device_uid': 'AABBCCDDEEFF', 'pad': 'x' * 2000}, '192.168.1.5'),
        ),
        isNull,
      );
    });

    test('beacon cache is bounded (spoofed uid flood cannot grow it forever)', () {
      final base = DateTime.now();
      String uidOf(int i) =>
          (0x100000000000 + i).toRadixString(16).toUpperCase();

      for (var i = 0; i < 200; i++) {
        service.handleBeaconDatagram(
          _dg({'device_uid': uidOf(i)}, '192.168.1.5'),
          now: base.add(Duration(milliseconds: i)),
        );
      }

      var retained = 0;
      for (var i = 0; i < 200; i++) {
        if (service.getCachedDevice(uidOf(i)) != null) retained++;
      }
      expect(retained, lessThanOrEqualTo(64));
      // En yeni kayıt durur, en eskisi atılmıştır
      expect(service.getCachedDevice(uidOf(199)), isNotNull);
      expect(service.getCachedDevice(uidOf(0)), isNull);
    });
  });

  group('parseDiscoveryReply', () {
    test('returns the datagram source address when uid and source port match', () {
      final ip = LocalDoorService.parseDiscoveryReply(
        _dg(
          {'ok': true, 'device_uid': 'aabbccddeeff', 'ip': '203.0.113.9', 'port': 8765},
          '192.168.1.60',
        ),
        'AABBCCDDEEFF',
      );
      expect(ip, '192.168.1.60');
    });

    test('rejects uid mismatch, wrong source port, public source and garbage', () {
      expect(
        LocalDoorService.parseDiscoveryReply(
          _dg({'ok': true, 'device_uid': '112233445566'}, '192.168.1.60'),
          'AABBCCDDEEFF',
        ),
        isNull,
      );
      expect(
        LocalDoorService.parseDiscoveryReply(
          _dg({'ok': true, 'device_uid': 'AABBCCDDEEFF'}, '192.168.1.60', 40000),
          'AABBCCDDEEFF',
        ),
        isNull,
      );
      expect(
        LocalDoorService.parseDiscoveryReply(
          _dg({'ok': true, 'device_uid': 'AABBCCDDEEFF'}, '8.8.8.8'),
          'AABBCCDDEEFF',
        ),
        isNull,
      );
      // Eski kodun "metinde uid geçiyorsa kabul et" yedeği kaldırıldı
      expect(
        LocalDoorService.parseDiscoveryReply(
          _dg('hello AABBCCDDEEFF', '192.168.1.60'),
          'AABBCCDDEEFF',
        ),
        isNull,
      );
      expect(
        LocalDoorService.parseDiscoveryReply(
          _dg({'ok': false, 'device_uid': 'AABBCCDDEEFF'}, '192.168.1.60'),
          'AABBCCDDEEFF',
        ),
        isNull,
      );
    });
  });

  group('isValidOpenReply', () {
    bool check(
      Object payload, {
      String from = '192.168.1.60',
      int fromPort = 8765,
      String nonce = 'n0nce',
    }) {
      return LocalDoorService.isValidOpenReply(
        datagram: _dg(payload, from, fromPort),
        expectedIp: '192.168.1.60',
        expectedPort: 8765,
        expectedUid: 'AABBCCDDEEFF',
        nonce: nonce,
      );
    }

    test('accepts ok + matching uid from the expected ip:port', () {
      expect(check({'ok': true, 'device_uid': 'AABBCCDDEEFF'}), isTrue);
      expect(check({'ok': true, 'device_uid': 'aabbccddeeff'}), isTrue);
    });

    test('nonce is enforced when the device echoes one, optional otherwise', () {
      expect(
        check({'ok': true, 'device_uid': 'AABBCCDDEEFF', 'nonce': 'n0nce'}),
        isTrue,
      );
      expect(
        check({'ok': true, 'device_uid': 'AABBCCDDEEFF', 'nonce': 'other'}),
        isFalse,
      );
    });

    test('rejects wrong source ip/port, uid mismatch, missing uid, ok:false, garbage', () {
      expect(check({'ok': true, 'device_uid': 'AABBCCDDEEFF'}, from: '192.168.1.61'), isFalse);
      expect(check({'ok': true, 'device_uid': 'AABBCCDDEEFF'}, fromPort: 9999), isFalse);
      expect(check({'ok': true, 'device_uid': '112233445566'}), isFalse);
      // uid yoksa kabul edilmez (eski kod null'a izin veriyordu)
      expect(check({'ok': true}), isFalse);
      expect(check({'ok': false, 'device_uid': 'AABBCCDDEEFF'}), isFalse);
      expect(check('{"ok":true}'), isFalse);
      expect(check('garbage'), isFalse);
      // metin içinde "ok":true geçen ama JSON olmayan yanıt
      expect(check('xx "ok":true AABBCCDDEEFF'), isFalse);
    });
  });

  group('openDoor (C4: token zorunlu)', () {
    test('empty token => local open is NOT attempted and falls back to cloud', () async {
      final service = LocalDoorService();
      final result = await service.openDoor(
        LocalDoorAccess(
          deviceUid: 'AABBCCDDEEFF',
          token: '',
          ip: '192.168.1.60',
          port: 8765,
          updatedAt: DateTime.now(),
        ),
      );
      expect(result.ok, isFalse);
      expect(result.ip, isNull);
      expect(result.message, contains('anahtar'));
    });

    test('whitespace-only token counts as empty', () async {
      final result = await LocalDoorService().openDoor(
        LocalDoorAccess(
          deviceUid: 'AABBCCDDEEFF',
          token: '   ',
          ip: null,
          port: 8765,
          updatedAt: DateTime.now(),
        ),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('anahtar'));
    });

    test('empty device uid is rejected', () async {
      final result = await LocalDoorService().openDoor(
        LocalDoorAccess(
          deviceUid: ' ',
          token: 'tok',
          ip: null,
          port: 8765,
          updatedAt: DateTime.now(),
        ),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('kimli'));
    });

    test('with a token but no live beacon it hands over to the cloud immediately', () async {
      final service = LocalDoorService()..clearCache();
      final result = await service.openDoor(
        LocalDoorAccess(
          deviceUid: 'AABBCCDDEEFF',
          token: 'secret-token',
          ip: '192.168.1.60',
          port: 8765,
          updatedAt: DateTime.now(),
        ),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('bulut'));
    });
  });
}
