import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/deep_link_service.dart';

DoorRecord _door(int id, {int siteCode = 1, int index = 1, String name = 'Kapı'}) {
  return DoorRecord(
    id: id,
    siteCode: siteCode,
    siteName: 'Site $siteCode',
    doorName: name,
    doorIndex: index,
    isActive: true,
    assignedDeviceId: id,
    assignedDeviceUid: 'AABBCCDDEE0$id',
    mqttSiteId: siteCode,
    createdAt: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeepLinkAction', () {
    test('handles showQrForDoor type correctly', () {
      const action = DeepLinkAction(
        type: DeepLinkActionType.showQrForDoor,
        doorId: 42,
      );

      expect(action.type, DeepLinkActionType.showQrForDoor);
      expect(action.doorId, 42);
      expect(action.doorIndex, isNull);
      expect(action.siteCode, isNull);
      expect(action.opensDoor, isFalse);
    });

    test('opensDoor is true only for door-opening types', () {
      expect(
        const DeepLinkAction(type: DeepLinkActionType.openDoorById, doorId: 1)
            .opensDoor,
        isTrue,
      );
      expect(
        const DeepLinkAction(type: DeepLinkActionType.openDoorByIndex, doorIndex: 1)
            .opensDoor,
        isTrue,
      );
      expect(
        const DeepLinkAction(type: DeepLinkActionType.openFirstDoor).opensDoor,
        isTrue,
      );
      expect(
        const DeepLinkAction(type: DeepLinkActionType.triggerVoice).opensDoor,
        isFalse,
      );
    });
  });

  group('DeepLinkService.parseUri', () {
    test('parses open by doorId (and siteCode)', () {
      final a = DeepLinkService.parseUri(Uri.parse('sitekapi://open?doorId=5'));
      expect(a?.type, DeepLinkActionType.openDoorById);
      expect(a?.doorId, 5);
      expect(a?.siteCode, isNull);

      final b = DeepLinkService.parseUri(
        Uri.parse('sitekapi://open?siteCode=3&doorId=5'),
      );
      expect(b?.type, DeepLinkActionType.openDoorById);
      expect(b?.siteCode, 3);
      expect(b?.doorId, 5);
    });

    test('parses open by doorIndex (documented Siri/NFC link)', () {
      final a = DeepLinkService.parseUri(
        Uri.parse('sitekapi://open?doorIndex=1'),
      );
      expect(a?.type, DeepLinkActionType.openDoorByIndex);
      expect(a?.doorIndex, 1);
    });

    test('plain open and bare link map to openFirstDoor', () {
      expect(
        DeepLinkService.parseUri(Uri.parse('sitekapi://open'))?.type,
        DeepLinkActionType.openFirstDoor,
      );
      expect(
        DeepLinkService.parseUri(Uri.parse('sitekapi://'))?.type,
        DeepLinkActionType.openFirstDoor,
      );
    });

    test('parses voice and qr links', () {
      expect(
        DeepLinkService.parseUri(Uri.parse('sitekapi://voice'))?.type,
        DeepLinkActionType.triggerVoice,
      );
      final qr = DeepLinkService.parseUri(
        Uri.parse('sitekapi://qr?doorId=105'),
      );
      expect(qr?.type, DeepLinkActionType.showQrForDoor);
      expect(qr?.doorId, 105);
      // doorId olmayan qr bağlantısı eylem üretmez
      expect(DeepLinkService.parseUri(Uri.parse('sitekapi://qr')), isNull);
    });

    test('invalid ids NEVER fall back to "open first door"', () {
      for (final raw in [
        'sitekapi://open?doorId=abc',
        'sitekapi://open?doorId=',
        'sitekapi://open?doorId=0',
        'sitekapi://open?doorId=-3',
        'sitekapi://open?doorId=99999999999',
        'sitekapi://open?doorIndex=x',
        'sitekapi://open?siteCode=nope&doorId=1',
      ]) {
        expect(DeepLinkService.parseUri(Uri.parse(raw)), isNull, reason: raw);
      }
    });

    test('ignores foreign schemes, unknown hosts and widget container link', () {
      expect(
        DeepLinkService.parseUri(Uri.parse('https://evil.example/open?doorId=1')),
        isNull,
      );
      expect(DeepLinkService.parseUri(Uri.parse('sitekapi://door_control')), isNull);
      expect(DeepLinkService.parseUri(Uri.parse('sitekapi://other_action')), isNull);
      expect(DeepLinkService.parseUri(Uri.parse('sitekapi:///unknown')), isNull);
    });

    test('rejects oversized URIs', () {
      final long = 'sitekapi://open?doorId=1&x=${'a' * 600}';
      expect(DeepLinkService.parseUri(Uri.parse(long)), isNull);
    });
  });

  group('DeepLinkService queue and de-duplication', () {
    test('initial link delivered twice (getInitialLink + stream) is handled once', () {
      final service = DeepLinkService();
      final received = <DeepLinkAction>[];
      service.onAction = received.add;
      service.markReady();

      final uri = Uri.parse('sitekapi://open?doorIndex=2');
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      service.handleUri(uri, now: t0);
      service.handleUri(uri, now: t0.add(const Duration(milliseconds: 40)));

      expect(received, hasLength(1));
      expect(received.single.type, DeepLinkActionType.openDoorByIndex);

      // Pencere dışında gelen aynı bağlantı yeni bir kullanıcı eylemidir.
      service.handleUri(uri, now: t0.add(const Duration(seconds: 5)));
      expect(received, hasLength(2));

      service.dispose();
    });

    test('different links inside the window are both handled', () {
      final service = DeepLinkService();
      final received = <DeepLinkAction>[];
      service.onAction = received.add;
      service.markReady();

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      service.handleUri(Uri.parse('sitekapi://open?doorId=1'), now: t0);
      service.handleUri(
        Uri.parse('sitekapi://open?doorId=2'),
        now: t0.add(const Duration(milliseconds: 100)),
      );
      expect(received.map((a) => a.doorId), [1, 2]);
      service.dispose();
    });

    test('actions are queued until session is ready, then delivered', () {
      final service = DeepLinkService();
      final received = <DeepLinkAction>[];
      service.onAction = received.add;

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      service.handleUri(Uri.parse('sitekapi://open?doorId=7'), now: t0);
      expect(received, isEmpty);
      expect(service.pendingCount, 1);
      expect(service.isReady, isFalse);

      service.markReady(now: t0.add(const Duration(seconds: 3)));
      expect(received, hasLength(1));
      expect(received.single.doorId, 7);
      expect(service.pendingCount, 0);
      expect(service.isReady, isTrue);

      // Hazır olduktan sonra anında iletilir
      service.handleUri(
        Uri.parse('sitekapi://open?doorId=8'),
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(received.map((a) => a.doorId), [7, 8]);
      service.dispose();
    });

    test('stale queued actions (older than max age) are dropped', () {
      final service = DeepLinkService();
      final received = <DeepLinkAction>[];
      service.onAction = received.add;

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      service.handleUri(Uri.parse('sitekapi://open?doorId=7'), now: t0);
      service.markReady(now: t0.add(DeepLinkService.pendingMaxAge * 2));

      expect(received, isEmpty);
      service.dispose();
    });

    test('queue is capped and dispatch() queues non-uri sources too', () {
      final service = DeepLinkService();
      final received = <DeepLinkAction>[];
      service.onAction = received.add;

      for (var i = 1; i <= 6; i++) {
        service.dispatch(
          DeepLinkAction(type: DeepLinkActionType.openDoorById, doorId: i),
        );
      }
      expect(service.pendingCount, 3);
      service.markReady();
      expect(received.map((a) => a.doorId), [4, 5, 6]);
      service.dispose();
    });

    test('clearPending drops queued actions (logout)', () {
      final service = DeepLinkService();
      final received = <DeepLinkAction>[];
      service.onAction = received.add;
      service.dispatch(
        const DeepLinkAction(type: DeepLinkActionType.openFirstDoor),
      );
      service.clearPending();
      service.markReady();
      expect(received, isEmpty);
      service.dispose();
    });

    test('initialize registers the callback without throwing in test env', () {
      final service = DeepLinkService();
      DeepLinkAction? captured;
      service.initialize((a) => captured = a);
      expect(service.onAction, isNotNull);
      service.markReady();
      service.onAction!(
        const DeepLinkAction(type: DeepLinkActionType.showQrForDoor, doorId: 105),
      );
      expect(captured?.doorId, 105);
      service.dispose();
      expect(service.onAction, isNull);
    });
  });

  group('DeepLinkDoorResolver', () {
    final siteADoor1 = _door(10, siteCode: 1, index: 1, name: 'A Ana Kapı');
    final siteADoor2 = _door(11, siteCode: 1, index: 2, name: 'A Otopark');
    final siteBDoor1 = _door(20, siteCode: 2, index: 1, name: 'B Ana Kapı');

    test('doorId must exist in the user\'s own doors', () {
      final doors = [siteADoor1, siteADoor2];
      final found = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(type: DeepLinkActionType.openDoorById, doorId: 11),
        doors,
      );
      expect(found.status, DeepLinkDoorStatus.found);
      expect(found.door?.id, 11);

      final missing = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(type: DeepLinkActionType.openDoorById, doorId: 999),
        doors,
      );
      expect(missing.status, DeepLinkDoorStatus.notFound);
      expect(missing.door, isNull);
    });

    test('siteCode + doorId must agree (multi-site)', () {
      final doors = [siteADoor1, siteBDoor1];
      final ok = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(
          type: DeepLinkActionType.openDoorById,
          doorId: 20,
          siteCode: 2,
        ),
        doors,
      );
      expect(ok.status, DeepLinkDoorStatus.found);

      final mismatch = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(
          type: DeepLinkActionType.openDoorById,
          doorId: 20,
          siteCode: 1,
        ),
        doors,
      );
      expect(mismatch.status, DeepLinkDoorStatus.notFound);
    });

    test('doorIndex shared by several sites is ambiguous unless siteCode given', () {
      final doors = [siteADoor1, siteADoor2, siteBDoor1];
      final ambiguous = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(
          type: DeepLinkActionType.openDoorByIndex,
          doorIndex: 1,
        ),
        doors,
      );
      expect(ambiguous.status, DeepLinkDoorStatus.ambiguous);
      expect(ambiguous.candidates.map((d) => d.id), [10, 20]);
      expect(ambiguous.door, isNull);

      final scoped = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(
          type: DeepLinkActionType.openDoorByIndex,
          doorIndex: 1,
          siteCode: 2,
        ),
        doors,
      );
      expect(scoped.status, DeepLinkDoorStatus.found);
      expect(scoped.door?.id, 20);

      final unique = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(
          type: DeepLinkActionType.openDoorByIndex,
          doorIndex: 2,
        ),
        doors,
      );
      expect(unique.status, DeepLinkDoorStatus.found);
      expect(unique.door?.id, 11);
    });

    test('openFirstDoor only auto-resolves when the user has a SINGLE door', () {
      const action = DeepLinkAction(type: DeepLinkActionType.openFirstDoor);

      final single = DeepLinkDoorResolver.resolve(action, [siteADoor1]);
      expect(single.status, DeepLinkDoorStatus.found);
      expect(single.door?.id, 10);

      final multi = DeepLinkDoorResolver.resolve(action, [siteADoor1, siteBDoor1]);
      expect(multi.status, DeepLinkDoorStatus.multipleDoors);
      expect(multi.door, isNull);
      expect(multi.candidates, hasLength(2));

      final none = DeepLinkDoorResolver.resolve(action, const <DoorRecord>[]);
      expect(none.status, DeepLinkDoorStatus.notFound);
    });

    test('openFirstDoor with siteCode resolves within that site only', () {
      final res = DeepLinkDoorResolver.resolve(
        const DeepLinkAction(
          type: DeepLinkActionType.openFirstDoor,
          siteCode: 2,
        ),
        [siteADoor1, siteADoor2, siteBDoor1],
      );
      expect(res.status, DeepLinkDoorStatus.found);
      expect(res.door?.id, 20);
    });
  });
}
