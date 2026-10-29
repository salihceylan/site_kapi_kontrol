// Kamera ızgarası / keşif / ekran testleri için ortak sahte servis ve sözleşme (v3) JSON üreticileri.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';

/// 1x1 geçerli PNG (Image.memory çözer).
final Uint8List tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

Map<String, dynamic> cameraJson({
  int id = 1,
  String name = 'Giriş kamerası',
  String color = 'yesil',
  String state = 'calisiyor',
  bool managed = true,
  bool active = true,
  Map<String, dynamic>? gate = const <String, dynamic>{'id': 7, 'name': 'Ana Kapı', 'direction_mode': 'cift'},
  String? direction = 'giris',
  Map<String, dynamic> probe = const <String, dynamic>{'status': 'ok', 'width': 1920, 'height': 1080},
  bool snapshot = true,
  String brand = 'hikvision',
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'brand': brand,
  'brand_label': brand == 'hikvision' ? 'Hikvision' : brand,
  'host': '192.168.1.${60 + id}',
  'port': 554,
  'rtsp_url': managed ? 'rtsp://192.168.1.${60 + id}:554/Streaming/Channels/101' : null,
  'username': 'admin',
  'has_password': true,
  'is_active': active,
  'managed': managed,
  'gate': gate,
  'direction': gate == null ? null : direction,
  'status': <String, dynamic>{'state': state, 'color': color},
  'last_frame_at': '2026-10-29T12:00:00.000Z',
  'last_read_at': null,
  'probe': probe,
  'snapshot': <String, dynamic>{'available': snapshot, 'captured_at': snapshot ? '2026-10-29T12:00:03.000Z' : null},
};

Map<String, dynamic> edgeClientJson({int id = 3, String name = 'Kulübe PC', String color = 'yesil', bool online = true, bool? ready = true}) => <String, dynamic>{
  'id': id,
  'name': name,
  'status': <String, dynamic>{'state': color == 'kirmizi' ? 'koptu' : 'calisiyor', 'color': color},
  'last_seen_at': '2026-10-29T11:58:00.000Z',
  'online': online,
  'recognition_ready': ready,
  'recognition_note': null,
};

Map<String, dynamic> overviewJson({
  List<Map<String, dynamic>>? cameras,
  List<Map<String, dynamic>>? clients,
  bool edgeOnline = true,
  Map<String, dynamic>? autoOpen,
  int interval = 4,
}) {
  final list = clients ?? <Map<String, dynamic>>[edgeClientJson(online: edgeOnline, color: edgeOnline ? 'yesil' : 'kirmizi')];
  return <String, dynamic>{
    'server_time': '2026-10-29T12:00:05.000Z',
    'cameras': cameras ?? <Map<String, dynamic>>[cameraJson()],
    'gates': <Map<String, dynamic>>[
      <String, dynamic>{'id': 7, 'name': 'Ana Kapı', 'direction_mode': 'cift'},
      <String, dynamic>{'id': 8, 'name': 'Çıkış Kapısı', 'direction_mode': 'cikis'},
    ],
    'edge': <String, dynamic>{'clients': list, 'online': edgeOnline, 'count': list.length},
    'auto_open': autoOpen ?? <String, dynamic>{'state': 'active', 'reason': null, 'message': 'Kenar PC bağlı ve okuma modeli onaylı; kapılar plakayla açılabilir.'},
    'snapshot': <String, dynamic>{'interval_seconds': interval, 'idle_interval_seconds': 15, 'keep_minutes': 30},
    'brands': <Map<String, dynamic>>[
      <String, dynamic>{'code': 'hikvision', 'label': 'Hikvision', 'default_rtsp_path': '/Streaming/Channels/101'},
      <String, dynamic>{'code': 'tiandy', 'label': 'Tiandy', 'default_rtsp_path': '/1/1'},
      <String, dynamic>{'code': 'onvif', 'label': 'ONVIF (diğer)', 'default_rtsp_path': null},
    ],
  };
}

Map<String, dynamic> commandJson({
  int id = 11,
  String status = 'pending',
  bool waitingOffline = false,
  Map<String, dynamic>? result,
  String? message,
  Map<String, dynamic>? edge,
  String kind = 'discover',
}) => <String, dynamic>{
  'id': id,
  'kind': kind,
  'status': status,
  'created_at': '2026-10-29T12:00:00.000Z',
  'picked_at': status == 'pending' ? null : '2026-10-29T12:00:02.000Z',
  'completed_at': status == 'done' || status == 'failed' ? '2026-10-29T12:00:20.000Z' : null,
  'message': message,
  'result': result,
  'edge': edge ?? <String, dynamic>{'id': 3, 'name': 'Kulübe PC', 'online': !waitingOffline, 'last_seen_at': '2026-10-29T11:40:00.000Z'},
  'waiting_offline': waitingOffline,
};

Map<String, dynamic> discoveryResultJson() => <String, dynamic>{
  'devices': <Map<String, dynamic>>[
    <String, dynamic>{'ip': '192.168.1.64', 'ports': <int>[554, 80, 8000], 'name': 'DS-2CD2043', 'model': 'Hikvision', 'source': 'onvif+tarama', 'label': 'ONVIF kamera', 'rtsp_port': 554},
    <String, dynamic>{'ip': '192.168.1.1', 'ports': <int>[80], 'name': null, 'model': null, 'source': 'tarama', 'label': 'Ağ cihazı — yalnız web arayüzü (kamera olabilir)', 'rtsp_port': 554},
  ],
  'summary': '2 cihaz bulundu (ONVIF: 1, tarama: 2). Birini seçin.',
};

/// Sahte kamera servisi: tüm davranışlar test tarafından ayarlanır; çağrılar sayılır.
class FakeCamerasService extends Fake implements PlateCamerasService {
  FakeCamerasService({Map<String, dynamic>? overview}) : overviewBody = overview ?? overviewJson();

  Map<String, dynamic> overviewBody;
  ApiException? overviewError;
  int overviewCalls = 0;

  /// (cameraId, etag, çağrı sırası) -> yanıt; fırlatabilir.
  FutureOr<SnapshotFetch> Function(int cameraId, String? etag, int call)? snapshotResponder;
  final List<({int cameraId, String? etag})> snapshotCalls = <({int cameraId, String? etag})>[];

  final List<int> probed = <int>[];
  final List<({int id, bool active})> activeChanges = <({int id, bool active})>[];
  final List<PlateCameraDraft> created = <PlateCameraDraft>[];
  final List<({int id, PlateCameraDraft draft})> updated = <({int id, PlateCameraDraft draft})>[];
  ApiException? createError;

  /// Keşif: başlatma yanıtı ve yoklama dizisi (her yoklamada sıradaki; sonuncusu tekrarlanır).
  FutureOr<DiscoveryStart> Function(int? edgeClientId)? startResponder;
  List<Map<String, dynamic>?> discoveryPolls = <Map<String, dynamic>?>[];
  int pollIndex = 0;
  int startCalls = 0;
  int pollCalls = 0;
  int? lastEdgeId;

  @override
  Future<PlateCamerasOverview> overview(int site) async {
    overviewCalls++;
    final error = overviewError;
    if (error != null) throw error;
    return PlateCamerasOverview.fromJson(overviewBody);
  }

  @override
  Future<SnapshotFetch> snapshot(int site, int cameraId, {String? etag}) async {
    snapshotCalls.add((cameraId: cameraId, etag: etag));
    final responder = snapshotResponder;
    if (responder == null) return const SnapshotFetch(noSnapshot: true);
    return responder(cameraId, etag, snapshotCalls.length);
  }

  @override
  Future<EdgeCommand> probe(int site, int cameraId) async {
    probed.add(cameraId);
    return EdgeCommand.fromJson(commandJson(id: 99, kind: 'probe'));
  }

  @override
  Future<PlateCameraRow> setActive(int site, int cameraId, {required bool active}) async {
    activeChanges.add((id: cameraId, active: active));
    return PlateCameraRow.fromJson(cameraJson(id: cameraId, active: active));
  }

  @override
  Future<({PlateCameraRow camera, int? probeCommandId})> createCamera(int site, PlateCameraDraft draft) async {
    final error = createError;
    if (error != null) throw error;
    created.add(draft);
    return (camera: PlateCameraRow.fromJson(cameraJson(id: 50, name: draft.name)), probeCommandId: 77);
  }

  @override
  Future<({PlateCameraRow camera, int? probeCommandId})> updateCamera(int site, int cameraId, PlateCameraDraft draft) async {
    updated.add((id: cameraId, draft: draft));
    return (camera: PlateCameraRow.fromJson(cameraJson(id: cameraId, name: draft.name)), probeCommandId: 78);
  }

  @override
  Future<DiscoveryStart> startDiscovery(int site, {int? edgeClientId}) async {
    startCalls++;
    lastEdgeId = edgeClientId;
    final responder = startResponder;
    if (responder != null) return responder(edgeClientId);
    return DiscoveryStart(command: EdgeCommand.fromJson(commandJson(status: 'pending')), reused: false);
  }

  @override
  Future<EdgeCommand?> latestDiscovery(int site) async {
    pollCalls++;
    if (discoveryPolls.isEmpty) return null;
    final body = discoveryPolls[pollIndex.clamp(0, discoveryPolls.length - 1)];
    if (pollIndex < discoveryPolls.length - 1) pollIndex++;
    return body == null ? null : EdgeCommand.fromJson(body);
  }
}
