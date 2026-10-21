import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/cctv_api.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});

void main() {
  test('kamera JSON eşlemesi: kimlik bilgisi alanı yok, yalnız has_credentials', () {
    final c = CctvCamera.fromJson(<String, dynamic>{
      'id': 5,
      'name': 'Giriş kamerası',
      'location': 'A blok girişi',
      'kind': 'nvr_channel',
      'channel': '101',
      'is_active': true,
      'has_clip_link': true,
      'has_snapshot': false,
      'has_credentials': true,
      'doors': <Object>[
        <String, Object>{'id': 2, 'name': 'Ana kapı'},
      ],
    });
    expect(c.id, 5);
    expect(cctvKindLabel(c.kind), 'NVR kanalı');
    expect(c.hasCredentials, isTrue);
    expect(c.clipUrlTemplate, isNull);
    expect(c.doors.single.name, 'Ana kapı');
    expect(cctvKindLabel('bilinmeyen'), 'bilinmeyen');
  });

  test('olay JSON eşlemesi: kişi adı salt okuyanda yok, kameralar eşlenir', () {
    final e = CctvEvent.fromJson(<String, dynamic>{
      'id': '90',
      'door_id': '2',
      'door_name': 'Ana kapı',
      'trigger_type': 'cloud_app',
      'opened_at': '2026-10-22T12:00:00.000Z',
      'user_name': null,
      'cameras': <Object>[
        <String, Object>{'id': 5, 'name': 'Giriş', 'has_clip_link': true, 'has_snapshot': false},
      ],
    });
    expect(e.id, 90);
    expect(e.doorId, 2);
    expect(e.userName, isNull);
    expect(e.openedAt, isNotNull);
    expect(e.cameras.single.hasClipLink, isTrue);
  });

  test('şablon ve adres ön denetimi', () {
    expect(validateClipTemplate('https://nvr.example.com/p?c={channel}&s={start}'), isNull);
    expect(validateClipTemplate(''), isNull);
    expect(validateClipTemplate('http://nvr.example.com/p'), isNotNull);
    expect(validateClipTemplate('https://nvr.example.com/p?x={gizli}'), contains('{gizli}'));
    expect(validateClipTemplate('https://nvr.example.com/p x'), isNotNull);
    expect(validateSnapshotUrl('https://cam.example.com/snap.jpg'), isNull);
    expect(validateSnapshotUrl('http://cam.example.com/snap.jpg'), isNotNull);
  });

  test('anlık görüntü: bayt döner; sunucu 424 verirse sabit ulaşılamıyor iletisi', () async {
    final jpeg = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    final ok = CctvApi(
      baseUrl: 'https://api.example.com/',
      client: MockClient((request) async {
        expect(request.url.path, '/manager/sites/1/cctv/cameras/5/snapshot');
        expect(request.headers['Authorization'], 'Bearer tok');
        return http.Response.bytes(jpeg, 200, headers: <String, String>{'content-type': 'image/jpeg'});
      }),
    );
    final snap = await ok.snapshot('tok', 1, 5);
    expect(snap.bytes, jpeg);
    expect(snap.contentType, 'image/jpeg');

    final soft = CctvApi(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async => _json(424, <String, Object>{'error': 'ham', 'code': 'SNAPSHOT_UNAVAILABLE'})),
    );
    await expectLater(
      soft.snapshot('tok', 1, 5),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Bu kameraya sunucudan ulaşılamıyor; kayıt bağlantısını kullanın.')),
    );

    final wrongType = CctvApi(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async => http.Response('<html>', 200, headers: <String, String>{'content-type': 'text/html'})),
    );
    await expectLater(wrongType.snapshot('tok', 1, 5), throwsA(isA<ApiException>()));
  });

  test('kayıt bağlantısı isteği ve hata eşlemesi', () async {
    late http.Request seen;
    final api = CctvApi(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        seen = request;
        if (request.url.path.endsWith('/clip-link')) {
          return _json(200, <String, Object>{'url': 'https://nvr.example.com/p?s=1', 'start': '2026-10-22T11:59:30.000Z', 'end': '2026-10-22T12:00:30.000Z'});
        }
        return _json(403, <String, Object>{'error': 'x', 'code': 'MODULE_DISABLED'});
      }),
    );
    final link = await api.clipLink('tok', 1, logId: 90, cameraId: 5);
    expect(link.url, 'https://nvr.example.com/p?s=1');
    expect(link.start, isNotNull);
    expect(seen.method, 'POST');
    expect(jsonDecode(seen.body), <String, Object>{'log_id': 90, 'camera_id': 5});
    await expectLater(api.cameras('tok', 1), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Bu modül bu site için kapalı.')));
  });

  test('kamera ekleme 201 bekler; düzenleme gövdesi aynen gider', () async {
    final calls = <String>[];
    final api = CctvApi(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path} ${request.body}');
        return request.method == 'POST' ? _json(201, <String, Object>{'camera': <String, Object>{}}) : _json(200, <String, Object>{'camera': <String, Object>{}});
      }),
    );
    await api.create('tok', 1, <String, Object?>{'name': 'K', 'door_ids': <int>[2]});
    await api.update('tok', 1, 5, <String, Object?>{'clear_credentials': true});
    await api.remove('tok', 1, 5);
    expect(calls, <String>[
      'POST /manager/sites/1/cctv/cameras {"name":"K","door_ids":[2]}',
      'PATCH /manager/sites/1/cctv/cameras/5 {"clear_credentials":true}',
      'DELETE /manager/sites/1/cctv/cameras/5 ',
    ]);
  });
}
