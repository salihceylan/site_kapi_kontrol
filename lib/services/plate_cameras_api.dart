// Plaka kenar sözleşmesi v3 (docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md) yönetici uçları: kamera ızgarası, kamera ekleme / düzenleme / sınama,
// "Ağda kamera ara" (kenar PC'ye uzaktan komut) ve görüntü karoları. Sunucu yerel ağı taramaz ve RTSP izlemez; kenar PC köprüdür, bu yüzden
// her durum (komut bekliyor, kenar çevrimdışı, sınama sonucu) SUNUCUDAN okunur ve dürüstçe gösterilir. Kamera PAROLASI hiçbir yanıtta dönmez;
// günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/plate_gates.dart' show GateBadge, GateColor;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? <Map<String, dynamic>>[for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const <Map<String, dynamic>>[];

/// Sunucu hata kodları (uygulamada ayırt edilenler).
abstract final class PlateCameraErrors {
  static const String moduleDisabled = 'MODULE_DISABLED';
  static const String noEdgeClient = 'NO_EDGE_CLIENT';
  static const String edgeClientRequired = 'EDGE_CLIENT_REQUIRED';
  static const String noSnapshot = 'NO_SNAPSHOT';
}

/// Kameranın bağlı olduğu kapı.
@immutable
class PlateCameraGate {
  const PlateCameraGate({required this.id, required this.name, required this.directionMode});

  factory PlateCameraGate.fromJson(Map<String, dynamic> m) => PlateCameraGate(id: _int(m['id']), name: _str(m['name']) ?? 'Kapı', directionMode: _str(m['direction_mode']) ?? 'cift');

  final int id;
  final String name;

  /// `giris` | `cikis` | `cift`.
  final String directionMode;
}

/// Kenar PC'nin RTSP sınama sonucu: `none` | `pending` | `ok` | `failed`.
@immutable
class ProbeInfo {
  const ProbeInfo({required this.status, this.message, this.width, this.height, this.at});

  factory ProbeInfo.fromJson(Object? json) {
    final m = _map(json);
    return ProbeInfo(status: _str(m['status']) ?? 'none', message: _str(m['message']), width: _intOrNull(m['width']), height: _intOrNull(m['height']), at: _date(m['at']));
  }

  final String status;
  final String? message;
  final int? width;
  final int? height;
  final DateTime? at;
}

@immutable
class SnapshotInfo {
  const SnapshotInfo({required this.available, this.capturedAt});

  factory SnapshotInfo.fromJson(Object? json) {
    final m = _map(json);
    return SnapshotInfo(available: m['available'] == true, capturedAt: _date(m['captured_at']));
  }

  final bool available;
  final DateTime? capturedAt;
}

@immutable
class PlateCameraRow {
  const PlateCameraRow({
    required this.id,
    required this.name,
    required this.brand,
    required this.brandLabel,
    required this.host,
    required this.isActive,
    required this.managed,
    required this.status,
    required this.probe,
    required this.snapshot,
    this.port,
    this.rtspUrl,
    this.username,
    this.hasPassword = false,
    this.gate,
    this.direction,
    this.lastFrameAt,
    this.lastReadAt,
  });

  factory PlateCameraRow.fromJson(Map<String, dynamic> m) {
    final gate = m['gate'];
    final brand = _str(m['brand']) ?? '';
    return PlateCameraRow(
      id: _int(m['id']),
      name: _str(m['name']) ?? 'Kamera',
      brand: brand,
      brandLabel: _str(m['brand_label']) ?? brand,
      host: _str(m['host']) ?? '',
      port: _intOrNull(m['port']),
      rtspUrl: _str(m['rtsp_url']),
      username: _str(m['username']),
      hasPassword: m['has_password'] == true,
      isActive: m['is_active'] != false,
      managed: m['managed'] == true,
      gate: gate is Map ? PlateCameraGate.fromJson(Map<String, dynamic>.from(gate)) : null,
      direction: _str(m['direction']),
      status: GateBadge.fromJson(m['status']),
      lastFrameAt: _date(m['last_frame_at']),
      lastReadAt: _date(m['last_read_at']),
      probe: ProbeInfo.fromJson(m['probe']),
      snapshot: SnapshotInfo.fromJson(m['snapshot']),
    );
  }

  final int id;
  final String name;
  final String brand;
  final String brandLabel;
  final String host;
  final int? port;

  /// Kimliksiz RTSP adresi (parola yok).
  final String? rtspUrl;
  final String? username;
  final bool hasPassword;
  final bool isActive;

  /// true: yeni akışla (kenar PC RTSP'sini yönetir) eklenmiş; false: eski olay belirteçli kamera.
  final bool managed;
  final PlateCameraGate? gate;

  /// `giris` | `cikis` | `auto` (kapı yoksa null).
  final String? direction;
  final GateBadge status;
  final DateTime? lastFrameAt;
  final DateTime? lastReadAt;
  final ProbeInfo probe;
  final SnapshotInfo snapshot;
}

/// Kenar PC (kenar istemci) özeti.
@immutable
class EdgeClientInfo {
  const EdgeClientInfo({required this.id, required this.name, required this.status, required this.online, this.lastSeenAt, this.recognitionReady, this.recognitionNote});

  factory EdgeClientInfo.fromJson(Map<String, dynamic> m) => EdgeClientInfo(
    id: _int(m['id']),
    name: _str(m['name']) ?? 'Kenar PC',
    status: GateBadge.fromJson(m['status']),
    online: m['online'] == true,
    lastSeenAt: _date(m['last_seen_at']),
    recognitionReady: m['recognition_ready'] is bool ? m['recognition_ready'] as bool : null,
    recognitionNote: _str(m['recognition_note']),
  );

  final int id;
  final String name;
  final GateBadge status;
  final bool online;
  final DateTime? lastSeenAt;

  /// Okuma modeli onaylı mı (kenarın kalp atışında bildirdiği); bilinmiyorsa null.
  final bool? recognitionReady;
  final String? recognitionNote;
}

@immutable
class EdgeSummary {
  const EdgeSummary({required this.clients, required this.online, required this.count});

  factory EdgeSummary.fromJson(Object? json) {
    final m = _map(json);
    final clients = <EdgeClientInfo>[for (final c in _maps(m['clients'])) EdgeClientInfo.fromJson(c)];
    return EdgeSummary(clients: clients, online: m['online'] == true, count: _int(m['count'], clients.length));
  }

  final List<EdgeClientInfo> clients;
  final bool online;
  final int count;
}

/// Plakayla otomatik kapı açma durumu (sunucu hesaplar): `active` | `inactive` + nedeni.
@immutable
class AutoOpenStatus {
  const AutoOpenStatus({required this.state, required this.message, this.reason});

  factory AutoOpenStatus.fromJson(Object? json) {
    final m = _map(json);
    return AutoOpenStatus(state: _str(m['state']) ?? 'inactive', reason: _str(m['reason']), message: _str(m['message']) ?? '');
  }

  final String state;

  /// `no_edge_client` | `edge_offline` | `model_not_approved` | `no_camera` | null.
  final String? reason;
  final String message;

  bool get active => state == 'active';
}

@immutable
class BrandTemplate {
  const BrandTemplate({required this.code, required this.label, this.defaultRtspPath});

  factory BrandTemplate.fromJson(Map<String, dynamic> m) => BrandTemplate(code: _str(m['code']) ?? '', label: _str(m['label']) ?? _str(m['code']) ?? '', defaultRtspPath: _str(m['default_rtsp_path']));

  final String code;
  final String label;
  final String? defaultRtspPath;
}

@immutable
class SnapshotSettings {
  const SnapshotSettings({required this.intervalSeconds, required this.idleIntervalSeconds, required this.keepMinutes});

  factory SnapshotSettings.fromJson(Object? json) {
    final m = _map(json);
    return SnapshotSettings(
      intervalSeconds: _int(m['interval_seconds'], 4).clamp(1, 600),
      idleIntervalSeconds: _int(m['idle_interval_seconds'], 15).clamp(1, 3600),
      keepMinutes: _int(m['keep_minutes'], 30),
    );
  }

  final int intervalSeconds;
  final int idleIntervalSeconds;
  final int keepMinutes;
}

@immutable
class PlateCamerasOverview {
  const PlateCamerasOverview({
    required this.cameras,
    required this.gates,
    required this.edge,
    required this.autoOpen,
    required this.snapshot,
    required this.brands,
    this.serverTime,
  });

  factory PlateCamerasOverview.fromJson(Map<String, dynamic> json) => PlateCamerasOverview(
    serverTime: _date(json['server_time']),
    cameras: <PlateCameraRow>[for (final c in _maps(json['cameras'])) PlateCameraRow.fromJson(c)],
    gates: <PlateCameraGate>[for (final g in _maps(json['gates'])) PlateCameraGate.fromJson(g)],
    edge: EdgeSummary.fromJson(json['edge']),
    autoOpen: AutoOpenStatus.fromJson(json['auto_open']),
    snapshot: SnapshotSettings.fromJson(json['snapshot']),
    brands: <BrandTemplate>[for (final b in _maps(json['brands'])) BrandTemplate.fromJson(b)],
  );

  final DateTime? serverTime;
  final List<PlateCameraRow> cameras;
  final List<PlateCameraGate> gates;
  final EdgeSummary edge;
  final AutoOpenStatus autoOpen;
  final SnapshotSettings snapshot;
  final List<BrandTemplate> brands;
}

// --- Komutlar (ağda kamera ara) -----------------------------------------------------------------------------------------

@immutable
class DiscoveredDevice {
  const DiscoveredDevice({required this.ip, required this.ports, required this.source, this.name, this.model, this.label, this.rtspPort});

  factory DiscoveredDevice.fromJson(Map<String, dynamic> m) => DiscoveredDevice(
    ip: _str(m['ip']) ?? '',
    ports: <int>[for (final p in (m['ports'] is List ? m['ports'] as List : const <Object?>[])) _int(p)],
    name: _str(m['name']),
    model: _str(m['model']),
    source: _str(m['source']) ?? 'tarama',
    label: _str(m['label']),
    rtspPort: _intOrNull(m['rtsp_port']),
  );

  final String ip;
  final List<int> ports;
  final String? name;
  final String? model;

  /// `onvif` | `onvif+tarama` | `tarama`.
  final String source;
  final String? label;
  final int? rtspPort;

  /// Listede gösterilecek ad: model ya da cihaz adı, yoksa etiket.
  String get title {
    final parts = <String>[?name, if (model != null && model != name) model!];
    return parts.isEmpty ? (label ?? 'Ağ cihazı') : parts.join(' · ');
  }
}

@immutable
class DiscoveryResult {
  const DiscoveryResult({required this.devices, this.summary});

  factory DiscoveryResult.fromJson(Map<String, dynamic> m) => DiscoveryResult(devices: <DiscoveredDevice>[for (final d in _maps(m['devices'])) DiscoveredDevice.fromJson(d)], summary: _str(m['summary']));

  final List<DiscoveredDevice> devices;
  final String? summary;
}

@immutable
class EdgeCommandEdge {
  const EdgeCommandEdge({required this.id, required this.name, required this.online, this.lastSeenAt});

  factory EdgeCommandEdge.fromJson(Object? json) {
    final m = _map(json);
    return EdgeCommandEdge(id: _int(m['id']), name: _str(m['name']) ?? 'Kenar PC', online: m['online'] == true, lastSeenAt: _date(m['last_seen_at']));
  }

  final int id;
  final String name;
  final bool online;
  final DateTime? lastSeenAt;
}

/// Kenar PC'ye verilen uzak komut (`discover` | `probe`). Durum: `pending` | `running` | `done` | `failed` | `expired`.
@immutable
class EdgeCommand {
  const EdgeCommand({
    required this.id,
    required this.kind,
    required this.status,
    required this.waitingOffline,
    this.createdAt,
    this.pickedAt,
    this.completedAt,
    this.expiresAt,
    this.ttlSeconds,
    this.message,
    this.result,
    this.edge,
  });

  factory EdgeCommand.fromJson(Map<String, dynamic> m) => EdgeCommand(
    id: _int(m['id']),
    kind: _str(m['kind']) ?? '',
    status: _str(m['status']) ?? 'pending',
    createdAt: _date(m['created_at']),
    pickedAt: _date(m['picked_at']),
    completedAt: _date(m['completed_at']),
    expiresAt: _date(m['expires_at']),
    ttlSeconds: _intOrNull(m['ttl_seconds']),
    message: _str(m['message']),
    result: m['result'] is Map ? Map<String, dynamic>.from(m['result'] as Map) : null,
    edge: m['edge'] is Map ? EdgeCommandEdge.fromJson(m['edge']) : null,
    waitingOffline: m['waiting_offline'] == true,
  );

  final int id;
  final String kind;
  final String status;
  final DateTime? createdAt;
  final DateTime? pickedAt;
  final DateTime? completedAt;

  /// Sunucu komutun ne zamana kadar bekleyeceğini bildiriyorsa (`expires_at` / `ttl_seconds`; sözleşmede isteğe bağlı); yoksa null.
  final DateTime? expiresAt;
  final int? ttlSeconds;
  final String? message;
  final Map<String, dynamic>? result;
  final EdgeCommandEdge? edge;

  /// Hedef kenar PC çevrimdışı: komut kuyrukta bekliyor.
  final bool waitingOffline;

  bool get inFlight => status == 'pending' || status == 'running';
  bool get finished => !inFlight;
  DiscoveryResult? get discovery => status == 'done' && result != null ? DiscoveryResult.fromJson(result!) : null;
}

/// Keşif başlatma yanıtı: `reused` = aynı kenarda zaten çalışan / bekleyen arama vardı, yenisi açılmadı.
@immutable
class DiscoveryStart {
  const DiscoveryStart({required this.command, required this.reused});

  final EdgeCommand command;
  final bool reused;
}

/// Kamera kaydı / düzenleme taslağı. `rtspInput`: "rtsp://…" ile başlıyorsa `rtsp_url`, aksi halde `rtsp_path` olarak gider.
@immutable
class PlateCameraDraft {
  const PlateCameraDraft({
    required this.name,
    required this.brand,
    required this.host,
    this.port,
    this.rtspInput,
    this.username,
    this.password,
    this.clearPassword = false,
    this.gateId,
    this.direction,
  });

  final String name;
  final String brand;
  final String host;
  final String? port;
  final String? rtspInput;
  final String? username;

  /// Düzenlemede boş = mevcut parola korunur (gövdeye girmez).
  final String? password;
  final bool clearPassword;
  final int? gateId;
  final String? direction;

  Map<String, Object?> toBody({required bool edit}) {
    final rtsp = (rtspInput ?? '').trim();
    final isUrl = rtsp.toLowerCase().startsWith('rtsp://') || rtsp.toLowerCase().startsWith('rtsps://');
    final portText = (port ?? '').trim();
    final user = (username ?? '').trim();
    return <String, Object?>{
      'name': name.trim(),
      'brand': brand,
      'host': host.trim(),
      if (portText.isNotEmpty) 'port': int.tryParse(portText) ?? portText,
      if (rtsp.isNotEmpty) (isUrl ? 'rtsp_url' : 'rtsp_path'): isUrl || rtsp.startsWith('/') ? rtsp : '/$rtsp',
      if (user.isNotEmpty || edit) 'username': user.isEmpty ? null : user,
      if (clearPassword) 'password': '' else if ((password ?? '').isNotEmpty) 'password': password,
      if (gateId != null) 'gate_id': gateId else if (edit) 'gate_id': null,
      if (gateId != null && (direction ?? '').isNotEmpty) 'direction': direction,
    };
  }
}

/// Karo görüntüsü sonucu: [bytes] null iken [notModified] (304, eldeki görüntü güncel) ya da kare yok ([noSnapshot]).
@immutable
class SnapshotFetch {
  const SnapshotFetch({this.bytes, this.etag, this.capturedAt, this.notModified = false, this.noSnapshot = false});

  final Uint8List? bytes;
  final String? etag;
  final DateTime? capturedAt;
  final bool notModified;
  final bool noSnapshot;
}

// --- API -------------------------------------------------------------------------------------------------------------------

class PlateCamerasApi {
  PlateCamerasApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _site(int site, String tail) => '/manager/sites/$site/plate-recognition/$tail';

  Future<PlateCamerasOverview> overview(String token, int site) async => PlateCamerasOverview.fromJson(await _send('GET', _site(site, 'cameras'), token));

  /// 201 yanıtı: `camera` + `probe_command_id` (kenar tanımlıysa kenar RTSP'yi sınar).
  Future<({PlateCameraRow camera, int? probeCommandId})> createCamera(String token, int site, PlateCameraDraft draft) async {
    final json = await _send('POST', _site(site, 'cameras'), token, body: draft.toBody(edit: false), okStatuses: const <int>{200, 201});
    return (camera: PlateCameraRow.fromJson(_map(json['camera'])), probeCommandId: _intOrNull(json['probe_command_id']));
  }

  Future<({PlateCameraRow camera, int? probeCommandId})> updateCamera(String token, int site, int cameraId, PlateCameraDraft draft) async {
    final json = await _send('PUT', _site(site, 'cameras/$cameraId'), token, body: draft.toBody(edit: true));
    return (camera: PlateCameraRow.fromJson(_map(json['camera'])), probeCommandId: _intOrNull(json['probe_command_id']));
  }

  Future<PlateCameraRow> setActive(String token, int site, int cameraId, {required bool active}) async {
    final json = await _send('PUT', _site(site, 'cameras/$cameraId'), token, body: <String, Object?>{'is_active': active});
    return PlateCameraRow.fromJson(_map(json['camera']));
  }

  Future<EdgeCommand> probe(String token, int site, int cameraId) async {
    final json = await _send('POST', _site(site, 'cameras/$cameraId/probe'), token, body: const <String, Object?>{}, okStatuses: const <int>{200, 202});
    return EdgeCommand.fromJson(_map(json['command']));
  }

  Future<DiscoveryStart> startDiscovery(String token, int site, {int? edgeClientId}) async {
    final json = await _send(
      'POST',
      _site(site, 'discovery'),
      token,
      body: <String, Object?>{'edge_client_id': ?edgeClientId},
      okStatuses: const <int>{200, 201, 202},
    );
    return DiscoveryStart(command: EdgeCommand.fromJson(_map(json['command'])), reused: json['reused'] == true);
  }

  /// Son keşif komutu (yoksa null) + hedef kenar özeti.
  Future<EdgeCommand?> latestDiscovery(String token, int site) async {
    final json = await _send('GET', _site(site, 'discovery'), token);
    final raw = json['command'];
    return raw is Map ? EdgeCommand.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  /// Kameranın SON karesi. [etag] verilirse 304 => [SnapshotFetch.notModified]; `NO_SNAPSHOT` (404) => [SnapshotFetch.noSnapshot].
  Future<SnapshotFetch> snapshot(String token, int site, int cameraId, {String? etag}) async {
    final uri = Uri.parse('$_baseUrl${_site(site, 'cameras/$cameraId/snapshot')}');
    final request = http.Request('GET', uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'image/jpeg',
        if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
      });
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    if (response.statusCode == 304) return SnapshotFetch(etag: etag, notModified: true);
    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      return SnapshotFetch(bytes: response.bodyBytes, etag: response.headers['etag'], capturedAt: _date(response.headers['x-captured-at']));
    }
    final payload = _payloadOf(response);
    final code = payload['code'] is String ? payload['code'] as String : null;
    if (response.statusCode == 404 && code == PlateCameraErrors.noSnapshot) return const SnapshotFetch(noSnapshot: true);
    throw _error(response, payload);
  }

  Map<String, dynamic> _payloadOf(http.Response response) {
    try {
      final raw = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } on FormatException {
      // Gövde JSON değil.
    }
    return const <String, dynamic>{};
  }

  ApiException _error(http.Response response, Map<String, dynamic> payload) {
    final code = payload['code'] is String ? payload['code'] as String : null;
    if (response.statusCode == 401) return SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    return ApiException(messageFor(code, payload['error'], response.statusCode), statusCode: response.statusCode, code: code, payload: payload);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String token, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    Set<int> okStatuses = const <int>{200},
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    final payload = _payloadOf(response);
    if (okStatuses.contains(response.statusCode)) return payload;
    throw _error(response, payload);
  }

  /// Türkçe hata metni; sunucunun Türkçe metni (INVALID_BODY, CAMERA_DIRECTION_CONFLICT vb.) varsa o.
  @visibleForTesting
  static String messageFor(String? code, Object? serverText, int status) {
    switch (code) {
      case PlateCameraErrors.moduleDisabled:
        return 'Kamera ızgarası ve canlı akış için Plaka Tanıma modülünün bu site için açık olması gerekir.';
      case PlateCameraErrors.noEdgeClient:
        return 'Bu site için kenar uygulama (güvenlik kulübesindeki PC) tanımlı değil. Plaka Tanıma > Geçiş noktaları bölümünden bir kenar istemci ekleyin.';
      case PlateCameraErrors.edgeClientRequired:
        return 'Birden çok kenar PC var; komutun hangisine verileceğini seçin.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
    }
    if (serverText is String && serverText.trim().isNotEmpty && (code == 'INVALID_BODY' || (status >= 400 && status < 500))) {
      return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    }
    final mapped = code == null ? null : AuthApi.messageForErrorCode(code);
    if (mapped != null) return mapped;
    if (serverText is String && serverText.trim().isNotEmpty) return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    return 'İşlem başarısız ($status)';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman.
class PlateCamerasService {
  PlateCamerasService({required this.authService, PlateCamerasApi? api}) : api = api ?? PlateCamerasApi(baseUrl: authService.api.baseUrl);

  final AuthService authService;
  final PlateCamerasApi api;

  Future<T> _guard<T>(Future<T> Function(String token) call) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }

  Future<PlateCamerasOverview> overview(int site) => _guard((t) => api.overview(t, site));
  Future<({PlateCameraRow camera, int? probeCommandId})> createCamera(int site, PlateCameraDraft draft) => _guard((t) => api.createCamera(t, site, draft));
  Future<({PlateCameraRow camera, int? probeCommandId})> updateCamera(int site, int cameraId, PlateCameraDraft draft) => _guard((t) => api.updateCamera(t, site, cameraId, draft));
  Future<PlateCameraRow> setActive(int site, int cameraId, {required bool active}) => _guard((t) => api.setActive(t, site, cameraId, active: active));
  Future<EdgeCommand> probe(int site, int cameraId) => _guard((t) => api.probe(t, site, cameraId));
  Future<DiscoveryStart> startDiscovery(int site, {int? edgeClientId}) => _guard((t) => api.startDiscovery(t, site, edgeClientId: edgeClientId));
  Future<EdgeCommand?> latestDiscovery(int site) => _guard((t) => api.latestDiscovery(t, site));
  Future<SnapshotFetch> snapshot(int site, int cameraId, {String? etag}) => _guard((t) => api.snapshot(t, site, cameraId, etag: etag));
}

/// Rozet rengi -> kısa çevrimiçi metni: yeşil Çevrimiçi, sarı Gecikmeli, kırmızı Çevrimdışı, gri Hiç bağlanmadı.
String cameraOnlineLabel(GateBadge badge) => switch (badge.color) {
  GateColor.yesil => 'Çevrimiçi',
  GateColor.sari => 'Gecikmeli',
  GateColor.kirmizi => 'Çevrimdışı',
  GateColor.gri => 'Hiç bağlanmadı',
};

/// Kamera yönü etiketi: kapı yoksa "Kapı yok"; aksi halde Giriş / Çıkış / Otomatik.
String cameraDirectionLabel(PlateCameraRow camera) {
  if (camera.gate == null) return 'Kapı yok';
  return switch (camera.direction) {
    'giris' => 'Giriş',
    'cikis' => 'Çıkış',
    _ => 'Otomatik',
  };
}
