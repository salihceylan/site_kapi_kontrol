import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';

void main() {
  test('PlateCameraSnapshot connects to Hikvision and fetches live JPEG using Digest Auth', () async {
    final client = http.Client();
    final camera = PlateCameraRow(
      id: 1,
      name: 'Giris Kamerasi',
      brand: 'hikvision',
      brandLabel: 'Hikvision',
      host: '192.168.1.64',
      port: 554,
      rtspUrl: 'rtsp://192.168.1.64:554/Streaming/Channels/101',
      username: 'admin',
      hasPassword: true,
      isActive: true,
      managed: true,
      status: const GateBadge(state: 'calisiyor', color: GateColor.yesil),
      probe: const ProbeInfo(status: 'ok'),
      snapshot: const SnapshotInfo(available: true),
    );

    PlateCameraSnapshot.recordCredentials(
      host: '192.168.1.64',
      username: 'admin',
      password: 'gude2134',
      cameraId: 1,
    );

    final (uri, result) = await PlateCameraSnapshot.discover(client, camera);
    client.close();

    expect(result.ok, isTrue, reason: result.error);
    expect(result.bytes, isNotNull);
    expect(result.bytes!.length, greaterThan(1000));
    expect(uri, isNotNull);
  });
}
