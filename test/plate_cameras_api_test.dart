// Plaka kenar sözleşmesi v3 istemci katmanı: istek gövdeleri, görüntü (ETag / 304 / NO_SNAPSHOT), hata metinleri, kapı günlüğü 'plate' etiketi,
// denetim eylem başlıkları. Ağ yok (MockClient).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/door_access_log_record.dart';
import 'package:site_kapi_kontrol/models/plate_audit_label.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

import 'plate_cameras_support.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});

void main() {
  group('PlateCameraDraft.toBody', () {
    test('ekleme: RTSP adresi / yolu ayrılır, boş alanlar gönderilmez, kapı yoksa yön gitmez', () {
      final url = const PlateCameraDraft(name: ' Giriş ', brand: 'hikvision', host: ' 192.168.1.64 ', port: '554', rtspInput: 'rtsp://192.168.1.64:554/Streaming/Channels/102', username: 'admin', password: 'p').toBody(edit: false);
      expect(url, <String, Object?>{'name': 'Giriş', 'brand': 'hikvision', 'host': '192.168.1.64', 'port': 554, 'rtsp_url': 'rtsp://192.168.1.64:554/Streaming/Channels/102', 'username': 'admin', 'password': 'p'});
      final path = const PlateCameraDraft(name: 'a', brand: 'tiandy', host: 'h', rtspInput: '1/1', gateId: 7, direction: 'cikis').toBody(edit: false);
      expect(path['rtsp_path'], '/1/1');
      expect(path.containsKey('rtsp_url'), isFalse);
      expect(path['gate_id'], 7);
      expect(path['direction'], 'cikis');
      final bare = const PlateCameraDraft(name: 'a', brand: 'onvif', host: 'h', direction: 'giris').toBody(edit: false);
      expect(bare.keys, <String>['name', 'brand', 'host'], reason: 'kapı yokken yön gönderilmez');
    });

    test('düzenleme: parola boşsa korunur, "sil" boş parola yollar, kapı kaldırılırsa gate_id null', () {
      final keep = const PlateCameraDraft(name: 'a', brand: 'onvif', host: 'h', password: '').toBody(edit: true);
      expect(keep.containsKey('password'), isFalse);
      expect(keep['gate_id'], isNull);
      expect(keep.containsKey('gate_id'), isTrue, reason: 'null = kapıdan ayır');
      expect(keep['username'], isNull);
      final clear = const PlateCameraDraft(name: 'a', brand: 'onvif', host: 'h', clearPassword: true, password: 'yok sayılır').toBody(edit: true);
      expect(clear['password'], '');
    });
  });

  group('PlateCamerasApi', () {
    test('overview: sözleşme alanları ayrıştırılır; parola alanı modelde yoktur', () async {
      late http.Request seen;
      final api = PlateCamerasApi(
        baseUrl: 'https://api.test/',
        client: MockClient((req) async {
          seen = req;
          return _json(overviewJson());
        }),
      );
      final o = await api.overview('tok', 5);
      expect(seen.url.path, '/manager/sites/5/plate-recognition/cameras');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(o.cameras.single.name, 'Giriş kamerası');
      expect(o.cameras.single.probe.width, 1920);
      expect(o.cameras.single.gate?.name, 'Ana Kapı');
      expect(o.edge.online, isTrue);
      expect(o.autoOpen.active, isTrue);
      expect(o.snapshot.intervalSeconds, 4);
      expect(o.brands.map((b) => b.code), <String>['hikvision', 'tiandy', 'onvif']);
      expect(o.brands.last.defaultRtspPath, isNull);
      expect(cameraOnlineLabel(o.cameras.single.status), 'Çevrimiçi');
    });

    test('startDiscovery: edge_client_id yalnız verilince gider; reused okunur; latestDiscovery yoksa null', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = PlateCamerasApi(
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          if (req.method == 'POST') {
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            return _json(<String, dynamic>{'command': commandJson(status: 'running'), 'reused': true}, 202);
          }
          return _json(<String, dynamic>{'command': null, 'edge': null});
        }),
      );
      final first = await api.startDiscovery('t', 5);
      final second = await api.startDiscovery('t', 5, edgeClientId: 3);
      expect(bodies, <Map<String, dynamic>>[<String, dynamic>{}, <String, dynamic>{'edge_client_id': 3}]);
      expect(first.reused, isTrue);
      expect(second.command.status, 'running');
      expect(await api.latestDiscovery('t', 5), isNull);
    });

    test('snapshot: 200 baytlar + ETag + X-Captured-At; If-None-Match gönderilir; 304 notModified; 404 NO_SNAPSHOT noSnapshot; 500 hata', () async {
      final seen = <http.Request>[];
      var mode = 200;
      final api = PlateCamerasApi(
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          seen.add(req);
          switch (mode) {
            case 200:
              return http.Response.bytes(tinyPng, 200, headers: <String, String>{'etag': '"173"', 'x-captured-at': '2026-10-29T12:00:03.000Z', 'content-type': 'image/jpeg'});
            case 304:
              return http.Response('', 304);
            case 404:
              return _json(<String, dynamic>{'error': 'Kare yok.', 'code': 'NO_SNAPSHOT'}, 404);
            default:
              return _json(<String, dynamic>{'error': 'Sunucu hatası', 'code': 'X'}, 500);
          }
        }),
      );
      final ok = await api.snapshot('tok', 5, 12);
      expect(ok.bytes, tinyPng);
      expect(ok.etag, '"173"');
      expect(ok.capturedAt?.toUtc().toIso8601String(), '2026-10-29T12:00:03.000Z');
      expect(seen.single.url.path, '/manager/sites/5/plate-recognition/cameras/12/snapshot');
      expect(seen.single.headers.containsKey('If-None-Match'), isFalse);

      mode = 304;
      final same = await api.snapshot('tok', 5, 12, etag: '"173"');
      expect(seen.last.headers['If-None-Match'], '"173"');
      expect(same.notModified, isTrue);
      expect(same.bytes, isNull);
      expect(same.etag, '"173"');

      mode = 404;
      expect((await api.snapshot('tok', 5, 12)).noSnapshot, isTrue);

      mode = 500;
      await expectLater(api.snapshot('tok', 5, 12), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)));
    });

    test('hata metinleri: modül kapalı / kenar yok / kenar seçilmeli Türkçe; MODULE_DISABLED kodu korunur; 401 oturum sonu', () async {
      final api = PlateCamerasApi(
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          final code = req.url.queryParameters['c'] ?? 'MODULE_DISABLED';
          if (code == 'AUTH') return _json(<String, dynamic>{'error': 'x', 'code': 'TOKEN_REVOKED'}, 401);
          return _json(<String, dynamic>{'error': 'ham', 'code': code}, code == 'MODULE_DISABLED' ? 403 : 409);
        }),
      );
      await expectLater(
        api.overview('t', 5),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', PlateCameraErrors.moduleDisabled).having((e) => e.message, 'mesaj', contains('Plaka Tanıma modülünün'))),
      );
      expect(PlateCamerasApi.messageFor(PlateCameraErrors.noEdgeClient, 'x', 409), contains('Geçiş noktaları'));
      expect(PlateCamerasApi.messageFor(PlateCameraErrors.edgeClientRequired, 'x', 400), contains('hangisine'));
      expect(PlateCamerasApi.messageFor('INVALID_BODY', 'Kamera adı gerekli.', 400), 'Kamera adı gerekli.');
      expect(PlateCamerasApi.messageFor(null, null, 502), 'İşlem başarısız (502)');
    });
  });

  group('kapı günlüğü ve denetim başlıkları', () {
    test("trigger_type 'plate' -> \"Plaka ile\"; bilinmeyen role güvenli; özet grubu dışlayıcı kalır", () {
      final log = DoorAccessLogRecord.fromJson(<String, dynamic>{
        'id': 1,
        'site_code': 5,
        'door_name': 'Ana Kapı',
        'user_name': '34 ABC 123 · Ali Y.',
        'user_role': 'plate_vehicle',
        'apartment_label': 'A - 5',
        'trigger_type': 'plate',
        'opened_at': '2026-10-29T12:00:00Z',
      });
      expect(log.triggerTypeDisplay, 'Plaka ile');
      expect(log.userRoleDisplay, 'Kullanıcı');
      expect(log.triggerGroup, 'other');
      expect(log.userName, '34 ABC 123 · Ali Y.');
    });

    test('yeni denetim eylemleri Türkçe başlık alır', () {
      expect(plateActionLabel('plate.camera_created'), 'Plaka kamerası eklendi');
      expect(plateActionLabel('plate.camera_updated'), 'Plaka kamerası değişti');
      expect(plateActionLabel('plate.camera_probe_requested'), 'Plaka kamerası sınama komutu verildi');
      expect(plateActionLabel('plate.discovery_requested'), 'Ağda kamera arama komutu verildi');
    });
  });
}
