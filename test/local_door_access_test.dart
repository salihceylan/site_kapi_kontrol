import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/local_door_access.dart';

LocalDoorAccess _access({
  String uid = 'AABBCCDDEEFF',
  String token = 'tok',
  required DateTime updatedAt,
}) {
  return LocalDoorAccess(
    deviceUid: uid,
    token: token,
    ip: '192.168.1.60',
    port: 8765,
    updatedAt: updatedAt,
  );
}

void main() {
  final now = DateTime(2026, 6, 1, 12, 0, 0);

  group('LocalDoorAccess cache validity', () {
    test('cacheValidity is 24 hours', () {
      expect(LocalDoorAccess.cacheValidity, const Duration(hours: 24));
    });

    test('fresh entry is usable, expired entry is not', () {
      expect(_access(updatedAt: now.subtract(const Duration(hours: 1))).isUsableAt(now), isTrue);
      expect(_access(updatedAt: now.subtract(const Duration(hours: 23, minutes: 59))).isUsableAt(now), isTrue);
      expect(_access(updatedAt: now.subtract(const Duration(hours: 24, minutes: 1))).isUsableAt(now), isFalse);
      // eski 90 günlük pencere artık geçerli değil
      expect(_access(updatedAt: now.subtract(const Duration(days: 30))).isUsableAt(now), isFalse);
    });

    test('epoch-zero timestamp (missing updated_at) is unusable', () {
      final access = LocalDoorAccess.fromJson({
        'device_uid': 'AABBCCDDEEFF',
        'token': 'tok',
      });
      expect(access.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(access.isUsable, isFalse);
    });

    test('empty uid or empty token is unusable (C4 fail-closed)', () {
      expect(_access(uid: ' ', updatedAt: now).isUsableAt(now), isFalse);
      expect(_access(token: '', updatedAt: now).isUsableAt(now), isFalse);
      expect(_access(token: '  ', updatedAt: now).hasToken, isFalse);
      expect(_access(token: 'x', updatedAt: now).hasToken, isTrue);
    });

    test('timestamps far in the future (clock tampering) are not trusted', () {
      expect(_access(updatedAt: now.add(const Duration(hours: 5))).isUsableAt(now), isFalse);
      // küçük saat sapması tolere edilir
      expect(_access(updatedAt: now.add(const Duration(minutes: 2))).isUsableAt(now), isTrue);
    });

    test('toJson/fromJson roundtrip keeps usability', () {
      final original = _access(updatedAt: DateTime.now());
      final restored = LocalDoorAccess.fromJson(original.toJson());
      expect(restored.deviceUid, original.deviceUid);
      expect(restored.token, original.token);
      expect(restored.ip, original.ip);
      expect(restored.port, 8765);
      expect(restored.isUsable, isTrue);
    });
  });
}
