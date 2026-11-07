import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_camera_rtsp_helper.dart';
import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

void main() {
  PlateCameraRow makeCam({
    String host = '192.168.1.64',
    int? port = 80,
    String? rtspUrl,
    String? username = 'admin',
  }) =>
      PlateCameraRow(
        id: 1,
        name: 'Giriş Kamerası',
        brand: 'hikvision',
        brandLabel: 'Hikvision',
        host: host,
        port: port,
        rtspUrl: rtspUrl,
        username: username,
        isActive: true,
        managed: true,
        status: const GateBadge(state: 'calisiyor', color: GateColor.yesil),
        probe: const ProbeInfo(status: 'ok'),
        snapshot: const SnapshotInfo(available: true),
      );

  test('Kullanıcının ayrı girdiği şifreyi RTSP adresine enjekte eder ve alt/ana akışı doğru sıralar', () {
    PlateCameraSnapshot.recordCredentials(
      host: '192.168.1.64',
      username: 'admin',
      password: 'gude2134',
      cameraId: 1,
    );

    final cam = makeCam(
      rtspUrl: 'rtsp://192.168.1.64:554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1',
    );

    final subCandidates = PlateCameraRtspHelper.buildCandidateUrls(cam, preferSubStream: true);
    expect(subCandidates.first, 'rtsp://admin:gude2134@192.168.1.64:554/Streaming/Channels/102');
    expect(
      subCandidates[1],
      'rtsp://admin:gude2134@192.168.1.64:554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1',
    );

    final mainCandidates = PlateCameraRtspHelper.buildCandidateUrls(cam, preferSubStream: false);
    expect(
      mainCandidates.first,
      'rtsp://admin:gude2134@192.168.1.64:554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1',
    );
  });

  test('HTTP portu (80) verilmiş ve RTSP adresi boş bırakılmışsa 554 üzerinden RTSP adayları üretir', () {
    final cam = makeCam(port: 80, rtspUrl: '');
    expect(PlateCameraRtspHelper.resolveRtspPort(cam), 554);

    final urls = PlateCameraRtspHelper.buildCandidateUrls(cam, preferSubStream: true);
    expect(urls.first, 'rtsp://admin:gude2134@192.168.1.64:554/Streaming/Channels/102');
    expect(urls, contains('rtsp://admin:gude2134@192.168.1.64:554/Streaming/Channels/101'));
  });
}
