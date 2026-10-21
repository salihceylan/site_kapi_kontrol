// Kamera (CCTV) bağlantısı uçları (`cctv_link` modülü). Sözleşme: docs/PLATFORM_KAMERA_CCTV.md.
//
// Video uygulamada ve sunucuda SAKLANMAZ. Kameralar sitenin yerel ağındadır: kayıt bağlantısı (NVR arayüzü) kullanıcının cihazında
// açılır; anlık görüntü yalnız kamera herkese açık https adresi verdiyse sunucudan gelir. Kimlik bilgisi (kullanıcı / parola) yalnız
// gönderilir, sunucu hiçbir yanıtta geri vermez.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Kamera ekranının KVKK bilgi notu (sunucudaki `KVKK_NOTE` ile aynı).
const String cctvKvkkNote = 'Kamera görüntüsü kişisel veridir; aydınlatma ve saklama sorumluluğu site yönetimindedir.';

/// Anlık görüntü alınamayınca gösterilen metin (sunucudaki ile aynı).
const String cctvSnapshotUnavailable = 'Bu kameraya sunucudan ulaşılamıyor; kayıt bağlantısını kullanın.';

/// Olay anından önce / sonra kayıt penceresi (sn); sunucudaki değerle aynı.
const int cctvClipWindowSeconds = 30;

/// Ekrandaki bir site: yazma yetkisi (yönetici) ya da salt okuma (kurul üyesi / görevli).
class CctvSite {
  const CctvSite({required this.code, required this.name, this.canWrite = false});

  final int code;
  final String name;
  final bool canWrite;

  String get label => name.trim().isEmpty ? 'Site $code' : name;
}

const Map<String, String> cctvKindLabels = <String, String>{
  'ip_camera': 'IP kamera',
  'nvr_channel': 'NVR kanalı',
};

String cctvKindLabel(String code) => cctvKindLabels[code] ?? code;

/// Kayıt bağlantı şablonunda kullanılabilen yer tutucular (sunucudaki liste).
const List<String> cctvPlaceholders = <String>['{start}', '{end}', '{start_unix}', '{end_unix}', '{channel}', '{camera}'];

String? _s(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
int _i(Object? v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

class CctvDoor {
  const CctvDoor(this.id, this.name);

  factory CctvDoor.fromJson(Map<String, dynamic> j) => CctvDoor(_i(j['id']), '${j['name'] ?? ''}');

  final int id;
  final String name;
}

class CctvCamera {
  const CctvCamera({
    required this.id,
    required this.name,
    this.location,
    this.kind = 'ip_camera',
    this.channel,
    this.isActive = true,
    this.hasClipLink = false,
    this.hasSnapshot = false,
    this.hasCredentials = false,
    this.clipUrlTemplate,
    this.snapshotUrl,
    this.doors = const <CctvDoor>[],
  });

  factory CctvCamera.fromJson(Map<String, dynamic> j) => CctvCamera(
    id: _i(j['id']),
    name: '${j['name'] ?? ''}',
    location: _s(j['location']),
    kind: '${j['kind'] ?? 'ip_camera'}',
    channel: _s(j['channel']),
    isActive: j['is_active'] != false,
    hasClipLink: j['has_clip_link'] == true,
    hasSnapshot: j['has_snapshot'] == true,
    hasCredentials: j['has_credentials'] == true,
    clipUrlTemplate: _s(j['clip_url_template']),
    snapshotUrl: _s(j['snapshot_url']),
    doors: <CctvDoor>[
      for (final d in (j['doors'] as List? ?? const [])) if (d is Map) CctvDoor.fromJson(Map<String, dynamic>.from(d)),
    ],
  );

  final int id;
  final String name;
  final String? location;
  final String kind;
  final String? channel;
  final bool isActive;
  final bool hasClipLink;
  final bool hasSnapshot;
  final bool hasCredentials;

  /// Yalnız yazma yetkisinde gelir (belirteç içerebilir); salt okuyanda null.
  final String? clipUrlTemplate;
  final String? snapshotUrl;
  final List<CctvDoor> doors;
}

/// Bir olayın kapısına eşlenmiş aktif kamera.
class CctvEventCamera {
  const CctvEventCamera({required this.id, required this.name, this.location, this.hasClipLink = false, this.hasSnapshot = false});

  factory CctvEventCamera.fromJson(Map<String, dynamic> j) => CctvEventCamera(
    id: _i(j['id']),
    name: '${j['name'] ?? ''}',
    location: _s(j['location']),
    hasClipLink: j['has_clip_link'] == true,
    hasSnapshot: j['has_snapshot'] == true,
  );

  final int id;
  final String name;
  final String? location;
  final bool hasClipLink;
  final bool hasSnapshot;
}

class CctvEvent {
  const CctvEvent({
    required this.id,
    required this.doorName,
    required this.triggerType,
    this.doorId,
    this.openedAt,
    this.userName,
    this.apartmentLabel,
    this.cameras = const <CctvEventCamera>[],
  });

  factory CctvEvent.fromJson(Map<String, dynamic> j) => CctvEvent(
    id: _i(j['id']),
    doorId: j['door_id'] == null ? null : _i(j['door_id']),
    doorName: _s(j['door_name']) ?? 'Site Kapısı',
    triggerType: '${j['trigger_type'] ?? ''}',
    openedAt: DateTime.tryParse('${j['opened_at'] ?? ''}')?.toLocal(),
    userName: _s(j['user_name']),
    apartmentLabel: _s(j['apartment_label']),
    cameras: <CctvEventCamera>[
      for (final c in (j['cameras'] as List? ?? const [])) if (c is Map) CctvEventCamera.fromJson(Map<String, dynamic>.from(c)),
    ],
  );

  final int id;
  final int? doorId;
  final String doorName;
  final String triggerType;
  final DateTime? openedAt;

  /// Yalnız yazma yetkisinde gelir.
  final String? userName;
  final String? apartmentLabel;
  final List<CctvEventCamera> cameras;
}

class CctvClipLink {
  const CctvClipLink({required this.url, this.start, this.end});

  factory CctvClipLink.fromJson(Map<String, dynamic> j) =>
      CctvClipLink(url: '${j['url'] ?? ''}', start: DateTime.tryParse('${j['start'] ?? ''}')?.toLocal(), end: DateTime.tryParse('${j['end'] ?? ''}')?.toLocal());

  final String url;
  final DateTime? start;
  final DateTime? end;
}

/// Anlık görüntü yanıtı: ham bayt ve tür.
class CctvSnapshot {
  const CctvSnapshot(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// Kayıt bağlantı şablonu `https://` ile başlamalı (sunucu da denetler); istemci tarafı hızlı ön denetim.
String? validateClipTemplate(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  if (!v.toLowerCase().startsWith('https://')) return 'Kayıt bağlantı şablonu https:// ile başlamalı.';
  if (RegExp(r'\s').hasMatch(v)) return 'Kayıt bağlantı şablonu boşluk içeremez.';
  final unknown = RegExp(r'\{([^{}]*)\}').allMatches(v).map((m) => '{${m.group(1)}}').where((p) => !cctvPlaceholders.contains(p));
  if (unknown.isNotEmpty) return 'Bilinmeyen yer tutucu: ${unknown.first}.';
  return null;
}

/// Anlık görüntü adresi `https://` ile başlamalı (yerel ağ adresleri sunucu tarafından reddedilir).
String? validateSnapshotUrl(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  if (!v.toLowerCase().startsWith('https://')) return 'Anlık görüntü adresi https:// ile başlamalı.';
  if (RegExp(r'\s').hasMatch(v)) return 'Anlık görüntü adresi boşluk içeremez.';
  return null;
}

class CctvApi {
  CctvApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _p(int site, String tail) => '/manager/sites/$site/cctv/$tail';

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) => <T>[
    for (final r in (raw as List? ?? const [])) if (r is Map) f(Map<String, dynamic>.from(r)),
  ];

  Future<List<CctvCamera>> cameras(String token, int site) async => _list((await _send('GET', _p(site, 'cameras'), token))['cameras'], CctvCamera.fromJson);

  Future<List<CctvDoor>> doors(String token, int site) async => _list((await _send('GET', _p(site, 'doors'), token))['doors'], CctvDoor.fromJson);

  Future<List<CctvEvent>> events(String token, int site, {int limit = 30}) async =>
      _list((await _send('GET', _p(site, 'events'), token, query: <String, String>{'limit': '$limit'}))['events'], CctvEvent.fromJson);

  Future<void> create(String token, int site, Map<String, Object?> body) async => _send('POST', _p(site, 'cameras'), token, body: body, ok: const {201});

  Future<void> update(String token, int site, int id, Map<String, Object?> body) async => _send('PATCH', _p(site, 'cameras/$id'), token, body: body);

  Future<void> remove(String token, int site, int id) async => _send('DELETE', _p(site, 'cameras/$id'), token);

  Future<CctvClipLink> clipLink(String token, int site, {required int logId, required int cameraId}) async =>
      CctvClipLink.fromJson(await _send('POST', _p(site, 'clip-link'), token, body: <String, Object?>{'log_id': logId, 'camera_id': cameraId}));

  Future<CctvSnapshot> snapshot(String token, int site, int id) async {
    final response = await _request('GET', _p(site, 'cameras/$id/snapshot'), token, accept: 'image/jpeg, image/png');
    if (response.statusCode == 200) {
      final type = (response.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
      if (type == 'image/jpeg' || type == 'image/png') return CctvSnapshot(response.bodyBytes, type);
      throw ApiException(cctvSnapshotUnavailable, statusCode: 424, code: 'SNAPSHOT_UNAVAILABLE');
    }
    throw _error(response);
  }

  Future<http.Response> _request(String method, String path, String token, {Map<String, Object?>? body, Map<String, String>? query, String accept = 'application/json'}) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': accept,
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      return await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, String token, {Map<String, Object?>? body, Map<String, String>? query, Set<int> ok = const <int>{200}}) async {
    final response = await _request(method, path, token, body: body, query: query);
    if (ok.contains(response.statusCode)) return _payload(response);
    throw _error(response);
  }

  static Map<String, dynamic> _payload(http.Response response) {
    try {
      final raw = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } on FormatException {
      // Gövde JSON değil.
    }
    return const <String, dynamic>{};
  }

  static ApiException _error(http.Response response) {
    final payload = _payload(response);
    final code = payload['code'] is String ? payload['code'] as String : null;
    if (response.statusCode == 401) return SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    return ApiException(_message(code, payload['error'], response.statusCode), statusCode: response.statusCode, code: code, payload: payload);
  }

  static String _message(String? code, Object? serverText, int status) {
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Bu modül bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'SNAPSHOT_UNAVAILABLE':
        return cctvSnapshotUnavailable;
      case 'NOT_FOUND':
        return 'Kayıt bulunamadı ya da erişiminiz yok.';
    }
    if (serverText is String && serverText.trim().isNotEmpty && (status == 400 || status == 409)) {
      return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    }
    final mapped = code == null ? null : AuthApi.messageForErrorCode(code);
    if (mapped != null) return mapped;
    if (serverText is String && serverText.trim().isNotEmpty) return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    return 'İşlem başarısız ($status)';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman.
class CctvService {
  CctvService({required this.authService, CctvApi? api}) : api = api ?? CctvApi(baseUrl: authService.api.baseUrl);

  final AuthService authService;
  final CctvApi api;

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

  Future<List<CctvCamera>> cameras(int site) => _guard((t) => api.cameras(t, site));
  Future<List<CctvDoor>> doors(int site) => _guard((t) => api.doors(t, site));
  Future<List<CctvEvent>> events(int site) => _guard((t) => api.events(t, site));
  Future<void> create(int site, Map<String, Object?> body) => _guard((t) => api.create(t, site, body));
  Future<void> update(int site, int id, Map<String, Object?> body) => _guard((t) => api.update(t, site, id, body));
  Future<void> remove(int site, int id) => _guard((t) => api.remove(t, site, id));
  Future<CctvClipLink> clipLink(int site, {required int logId, required int cameraId}) => _guard((t) => api.clipLink(t, site, logId: logId, cameraId: cameraId));
  Future<CctvSnapshot> snapshot(int site, int id) => _guard((t) => api.snapshot(t, site, id));
}
