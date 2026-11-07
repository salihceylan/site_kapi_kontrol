import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_discovery_local.dart';

void main() {
  test('LocalCameraDiscoveryService yerel ag taramasini hatasiz tamamlar', () async {
    final devices = await LocalCameraDiscoveryService.instance.discoverCameras(
      timeout: const Duration(seconds: 2),
    );
    expect(devices, isA<List<DiscoveredDevice>>());
  });
}
