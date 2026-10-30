import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/plate_discovery_local.dart';

void main() {
  test('LocalCameraDiscoveryService Sanal IP Kamerayi Agda Otomatik Kesfeder', () async {
    final devices = await LocalCameraDiscoveryService.instance.discoverCameras(
      timeout: const Duration(seconds: 3),
    );
    print('Bulunan cihazlar (${devices.length}):');
    for (final d in devices) {
      print('  - IP: ${d.ip}, Isim: ${d.name}, Portlar: ${d.ports}, Model: ${d.model}');
    }
    expect(devices, isNotEmpty);
    final found = devices.any((d) => d.ip == '127.0.0.1' || d.ip.startsWith('192.168.1.') || d.ports.contains(8080));
    expect(found, isTrue);
  });
}
