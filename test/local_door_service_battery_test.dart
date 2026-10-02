import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/local_door_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LocalDoorService pauseListening and resumeListening operate without error', () async {
    final service = LocalDoorService();

    // Verify pauseListening shuts down sockets and cancels timer
    service.pauseListening();

    // Verify multiple pauses do not throw
    service.pauseListening();

    // Verify resumeListening restarts beacon listener safely
    service.resumeListening();

    // Clean up
    service.pauseListening();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.isBeaconListenerActive, isFalse);
    expect(service.beaconSocketCount, 0);
  });

  test('LocalDoorService() is a single shared instance with no constructor side effects', () {
    final a = LocalDoorService();
    final b = LocalDoorService();
    expect(identical(a, b), isTrue);

    a.stopBeaconListener();
    // Kurucu dinleyici BAŞLATMAZ (yan etki yok)
    expect(LocalDoorService().isBeaconListenerActive, isFalse);
  });

  test('startBeaconListener is idempotent', () async {
    final service = LocalDoorService();
    service.stopBeaconListener();

    await service.startBeaconListener();
    expect(service.isBeaconListenerActive, isTrue);
    final socketsAfterFirst = service.beaconSocketCount;

    // İkinci/üçüncü çağrı yeni soket/zamanlayıcı üretmemeli
    await service.startBeaconListener();
    await service.startBeaconListener();
    expect(service.isBeaconListenerActive, isTrue);
    expect(service.beaconSocketCount, socketsAfterFirst);

    service.stopBeaconListener();
    expect(service.isBeaconListenerActive, isFalse);
    expect(service.beaconSocketCount, 0);
  });

  test('pause during an in-flight start does not leak sockets', () async {
    final service = LocalDoorService();
    service.stopBeaconListener();

    final starting = service.startBeaconListener();
    service.pauseListening(); // bind tamamlanmadan durdur
    await starting;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(service.isBeaconListenerActive, isFalse);
    expect(service.beaconSocketCount, 0);
  });

  test('dispose closes everything and the shared instance can be restarted', () async {
    final service = LocalDoorService();
    await service.startBeaconListener();
    service.dispose();
    expect(service.isBeaconListenerActive, isFalse);
    expect(service.beaconSocketCount, 0);

    await service.startBeaconListener();
    expect(service.isBeaconListenerActive, isTrue);
    service.dispose();
  });
}
