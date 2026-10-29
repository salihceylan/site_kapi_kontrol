// Plaka Tanıma (`plate_recognition` modülü) uçları: karar kayıtları, misafir plaka izinleri, kara liste, kapı/kamera ayarları.
//
// Plaka kişisel veridir: günlüğe YAZILMAZ. Kapı açma bu sürümde YOKTUR ("Yakında…"): otomatik açma açık kapıda izinli okumalar yalnız
// "açılırdı" olarak kaydedilir. Olay alma ucu (kamera -> sunucu) 6B'nindir ve cihaz belirteciyle çalışır; istemci çağırmaz.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Kullanıcının bu sitedeki Plaka Tanıma erişimi.
enum PlateAccess {
  /// Yönetici: izin verir, kara listeyi ve ayarları yönetir.
  manager,

  /// Kurul üyesi / görevli: olayları, izinleri, kara listeyi ve ayarları SALT OKUR.
  viewer,

  /// Sakin: yalnız kendi dairesi için misafir plakası verir.
  resident,
}

/// Ekrandaki bir site ve erişim türü.
class PlateSite {
  const PlateSite({required this.code, required this.name, required this.access});

  final int code;
  final String name;
  final PlateAccess access;

  bool get canWrite => access == PlateAccess.manager;
  bool get isResident => access == PlateAccess.resident;
  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) => other is PlateSite && other.code == code && other.name == name && other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}

// --- Plaka biçimi (sunucuyla aynı kural) --------------------------------------------------------------------------

/// Türkiye plakası: il kodu 01-81 + 1-3 harf + 2-4 rakam.
final RegExp trPlatePattern = RegExp(r'^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})([0-9]{2,4})$');

/// Boşluk / tire / nokta atılır, büyük harf, Türkçe harfler ASCII'ye iner. Biçim doğrulanmaz.
String canonicalTrPlate(String raw) {
  if (raw.length > 24) return '';
  const map = <String, String>{'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U', 'ç': 'C', 'ğ': 'G', 'ı': 'I', 'ö': 'O', 'ş': 'S', 'ü': 'U'};
  final cleaned = raw.replaceAll(RegExp(r'[\s\-._]'), '');
  final out = StringBuffer();
  for (final rune in cleaned.runes) {
    final ch = String.fromCharCode(rune);
    out.write(map[ch] ?? ch.toUpperCase());
  }
  return out.toString();
}

/// Geçerli TR plakası ("34ABC123") ya da null.
String? normalizeTrPlate(String raw) {
  final plate = canonicalTrPlate(raw);
  return trPlatePattern.hasMatch(plate) ? plate : null;
}

/// "34ABC123" -> "34 ABC 123" (biçim geçersizse olduğu gibi).
String formatTrPlate(String plate) {
  final m = trPlatePattern.firstMatch(plate);
  return m == null ? plate : '${m.group(1)} ${m.group(2)} ${m.group(3)}';
}

// --- Modeller --------------------------------------------------------------------------------------------------------

/// Karar: ALLOWED | DENIED | UNKNOWN.
class PlateDecisionRow {
  const PlateDecisionRow({
    required this.id,
    required this.plate,
    required this.decision,
    required this.reasonLabel,
    required this.confidence,
    required this.autoAction,
    required this.seenAt,
    required this.deviceName,
    required this.doorName,
  });

  factory PlateDecisionRow.fromJson(Map<String, dynamic> json) => PlateDecisionRow(
    id: (json['id'] as num?)?.toInt() ?? 0,
    plate: '${json['plate'] ?? ''}',
    decision: '${json['decision'] ?? 'UNKNOWN'}',
    reasonLabel: '${json['reason_label'] ?? json['reason'] ?? ''}',
    confidence: (json['confidence'] as num?)?.toDouble(),
    autoAction: '${json['auto_action'] ?? 'none'}',
    seenAt: DateTime.tryParse('${json['seen_at'] ?? ''}')?.toLocal(),
    deviceName: json['device_name'] as String?,
    doorName: json['door_name'] as String?,
  );

  final int id;
  final String plate;
  final String decision;
  final String reasonLabel;
  final double? confidence;
  final String autoAction;
  final DateTime? seenAt;
  final String? deviceName;
  final String? doorName;

  /// Otomatik açma planlanmıştı ama kapı komutu gönderilmedi (bu sürümde kapı açma yok).
  bool get wouldOpen => autoAction == 'would_open';
}

class PlatePermit {
  const PlatePermit({
    required this.id,
    required this.apartmentId,
    required this.apartmentLabel,
    required this.plate,
    required this.validUntil,
    required this.note,
    required this.status,
    required this.createdByName,
  });

  factory PlatePermit.fromJson(Map<String, dynamic> json) => PlatePermit(
    id: (json['id'] as num?)?.toInt() ?? 0,
    apartmentId: (json['apartment_id'] as num?)?.toInt() ?? 0,
    apartmentLabel: json['apartment_label'] as String?,
    plate: '${json['plate'] ?? ''}',
    validUntil: DateTime.tryParse('${json['valid_until'] ?? ''}')?.toLocal(),
    note: json['note'] as String?,
    status: '${json['status'] ?? 'expired'}',
    createdByName: json['created_by_name'] as String?,
  );

  final int id;
  final int apartmentId;
  final String? apartmentLabel;
  final String plate;
  final DateTime? validUntil;
  final String? note;

  /// active | expired | revoked
  final String status;
  final String? createdByName;

  bool get isActive => status == 'active';
}

class PlateApartment {
  const PlateApartment({required this.id, required this.label});

  factory PlateApartment.fromJson(Map<String, dynamic> json) => PlateApartment(id: (json['id'] as num?)?.toInt() ?? 0, label: '${json['label'] ?? ''}');

  final int id;
  final String label;
}

class PlateBlacklistItem {
  const PlateBlacklistItem({required this.id, required this.plate, required this.reason, required this.createdByName});

  factory PlateBlacklistItem.fromJson(Map<String, dynamic> json) => PlateBlacklistItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    plate: '${json['plate'] ?? ''}',
    reason: json['reason'] as String?,
    createdByName: json['created_by_name'] as String?,
  );

  final int id;
  final String plate;
  final String? reason;
  final String? createdByName;
}

class PlateCamera {
  const PlateCamera({required this.id, required this.name, required this.isActive});

  factory PlateCamera.fromJson(Map<String, dynamic> json) =>
      PlateCamera(id: (json['id'] as num?)?.toInt() ?? 0, name: '${json['name'] ?? ''}', isActive: json['is_active'] != false);

  final int id;
  final String name;
  final bool isActive;
}

class PlateGateSetting {
  const PlateGateSetting({
    required this.doorId,
    required this.doorName,
    required this.deviceId,
    required this.cameraName,
    required this.autoOpen,
    required this.minConfidence,
    required this.cooldownSeconds,
  });

  factory PlateGateSetting.fromJson(Map<String, dynamic> json) => PlateGateSetting(
    doorId: (json['door_id'] as num?)?.toInt() ?? 0,
    doorName: '${json['door_name'] ?? ''}',
    deviceId: (json['device_id'] as num?)?.toInt(),
    cameraName: json['camera_name'] as String?,
    autoOpen: json['auto_open'] == true,
    minConfidence: (json['min_confidence'] as num?)?.toDouble() ?? 0.85,
    cooldownSeconds: (json['cooldown_seconds'] as num?)?.toInt() ?? 30,
  );

  final int doorId;
  final String doorName;
  final int? deviceId;
  final String? cameraName;
  final bool autoOpen;
  final double minConfidence;
  final int cooldownSeconds;
}

class PlateSettings {
  const PlateSettings({required this.doors, required this.cameras, required this.autoOpenSupported});

  factory PlateSettings.fromJson(Map<String, dynamic> json) => PlateSettings(
    doors: <PlateGateSetting>[for (final raw in (json['doors'] as List? ?? const <Object?>[])) if (raw is Map) PlateGateSetting.fromJson(Map<String, dynamic>.from(raw))],
    cameras: <PlateCamera>[for (final raw in (json['cameras'] as List? ?? const <Object?>[])) if (raw is Map) PlateCamera.fromJson(Map<String, dynamic>.from(raw))],
    autoOpenSupported: json['auto_open_supported'] == true,
  );

  final List<PlateGateSetting> doors;
  final List<PlateCamera> cameras;

  /// false: kapı açma bu sürümde yok ("Yakında…"); otomatik açma yalnız "açılırdı" kaydı üretir.
  final bool autoOpenSupported;
}

class PlateResidentOverview {
  const PlateResidentOverview({
    required this.apartments,
    required this.permits,
    required this.dailyLimit,
    required this.dailyRemaining,
    required this.maxDays,
  });

  factory PlateResidentOverview.fromJson(Map<String, dynamic> json) => PlateResidentOverview(
    apartments: <PlateApartment>[for (final raw in (json['apartments'] as List? ?? const <Object?>[])) if (raw is Map) PlateApartment.fromJson(Map<String, dynamic>.from(raw))],
    permits: <PlatePermit>[for (final raw in (json['permits'] as List? ?? const <Object?>[])) if (raw is Map) PlatePermit.fromJson(Map<String, dynamic>.from(raw))],
    dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? 5,
    dailyRemaining: (json['daily_remaining'] as num?)?.toInt() ?? 0,
    maxDays: (json['max_days'] as num?)?.toInt() ?? 30,
  );

  final List<PlateApartment> apartments;
  final List<PlatePermit> permits;
  final int dailyLimit;
  final int dailyRemaining;
  final int maxDays;
}

/// Misafir izni formu çıktısı. duration: day | week | custom.
class PermitDraft {
  const PermitDraft({required this.apartmentId, required this.plate, required this.duration, this.days, this.note});

  final int? apartmentId;
  final String plate;
  final String duration;
  final int? days;
  final String? note;

  Map<String, Object?> toBody() => <String, Object?>{
    if (apartmentId != null) 'apartment_id': apartmentId,
    'plate': plate,
    'duration': duration,
    if (duration == 'custom' && days != null) 'days': days,
    if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
  };
}

// --- API -------------------------------------------------------------------------------------------------------------

class PlateRecognitionApi {
  PlateRecognitionApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _site(int site, String tail) => '/manager/sites/$site/plate-recognition/$tail';

  Future<List<PlateDecisionRow>> events(String token, int site, {String? decision}) async {
    final json = await _send('GET', _site(site, 'events'), token, query: <String, String>{'limit': '50', 'decision': ?decision});
    return <PlateDecisionRow>[for (final raw in (json['events'] as List? ?? const <Object?>[])) if (raw is Map) PlateDecisionRow.fromJson(Map<String, dynamic>.from(raw))];
  }

  Future<List<PlatePermit>> permits(String token, int site) async {
    final json = await _send('GET', _site(site, 'permits'), token, query: const <String, String>{'status': 'active', 'limit': '100'});
    return <PlatePermit>[for (final raw in (json['permits'] as List? ?? const <Object?>[])) if (raw is Map) PlatePermit.fromJson(Map<String, dynamic>.from(raw))];
  }

  Future<List<PlateApartment>> searchApartments(String token, int site, String q) async {
    final json = await _send('GET', _site(site, 'apartments'), token, query: <String, String>{'q': q.trim()});
    return <PlateApartment>[for (final raw in (json['apartments'] as List? ?? const <Object?>[])) if (raw is Map) PlateApartment.fromJson(Map<String, dynamic>.from(raw))];
  }

  Future<void> createPermit(String token, int site, PermitDraft draft) async {
    await _send('POST', _site(site, 'permits'), token, body: draft.toBody(), okStatuses: const <int>{201});
  }

  Future<void> revokePermit(String token, int site, int id) async {
    await _send('POST', _site(site, 'permits/$id/revoke'), token, body: const <String, Object?>{});
  }

  Future<List<PlateBlacklistItem>> blacklist(String token, int site) async {
    final json = await _send('GET', _site(site, 'blacklist'), token);
    return <PlateBlacklistItem>[for (final raw in (json['items'] as List? ?? const <Object?>[])) if (raw is Map) PlateBlacklistItem.fromJson(Map<String, dynamic>.from(raw))];
  }

  Future<void> addBlacklist(String token, int site, String plate, String reason) async {
    await _send(
      'POST',
      _site(site, 'blacklist'),
      token,
      body: <String, Object?>{'plate': plate, if (reason.trim().isNotEmpty) 'reason': reason.trim()},
      okStatuses: const <int>{201},
    );
  }

  Future<void> removeBlacklist(String token, int site, int id) async {
    await _send('POST', _site(site, 'blacklist/$id/remove'), token, body: const <String, Object?>{});
  }

  Future<PlateSettings> settings(String token, int site) async => PlateSettings.fromJson(await _send('GET', _site(site, 'settings'), token));

  Future<PlateSettings> saveGate(
    String token,
    int site,
    int doorId, {
    required int? deviceId,
    required bool autoOpen,
    required double minConfidence,
    required int cooldownSeconds,
    required bool confirmRisk,
  }) async {
    final json = await _send(
      'PUT',
      _site(site, 'settings/$doorId'),
      token,
      body: <String, Object?>{
        'device_id': deviceId,
        'auto_open': autoOpen,
        'min_confidence': minConfidence,
        'cooldown_seconds': cooldownSeconds,
        if (autoOpen) 'confirm_risk': confirmRisk,
      },
    );
    return PlateSettings.fromJson(json);
  }

  // --- Geçiş noktaları (A1) ---

  Future<PlateGatesOverview> gatesOverview(String token, int site) async => PlateGatesOverview.fromJson(await _send('GET', _site(site, 'gates'), token));

  Future<PlateGatesOverview> createGatePoint(String token, int site, GateDraft draft) async =>
      PlateGatesOverview.fromJson(await _send('POST', _site(site, 'gates'), token, body: draft.toBody(), okStatuses: const <int>{201}));

  Future<PlateGatesOverview> updateGatePoint(String token, int site, int id, GateDraft draft) async =>
      PlateGatesOverview.fromJson(await _send('PUT', _site(site, 'gates/$id'), token, body: draft.toBody()));

  Future<PlateGatesOverview> deleteGatePoint(String token, int site, int id) async => PlateGatesOverview.fromJson(await _send('DELETE', _site(site, 'gates/$id'), token));

  Future<void> saveGateSettings(String token, int site, {required String guestRule, required int warnSeconds, required int critSeconds}) async {
    await _send(
      'PUT',
      _site(site, 'gate-settings'),
      token,
      body: <String, Object?>{'guest_rule': guestRule, 'heartbeat_warn_seconds': warnSeconds, 'heartbeat_crit_seconds': critSeconds},
    );
  }

  /// Kenar istemci kaydı: anahtar YALNIZ bu yanıtta döner (sunucuda yalnız özeti saklanır).
  Future<String> createEdgeClient(String token, int site, String name) async {
    final json = await _send('POST', _site(site, 'edge-clients'), token, body: <String, Object?>{'name': name.trim()}, okStatuses: const <int>{201});
    return '${json['edge_key']}';
  }

  Future<String> rotateEdgeKey(String token, int site, int id) async => '${(await _send('POST', _site(site, 'edge-clients/$id/rotate-key'), token, body: const <String, Object?>{}))['edge_key']}';

  Future<void> revokeEdgeClient(String token, int site, int id) async {
    await _send('POST', _site(site, 'edge-clients/$id/revoke'), token, body: const <String, Object?>{});
  }

  Future<PlateInside> inside(String token, int site) async => PlateInside.fromJson(await _send('GET', _site(site, 'inside'), token));

  Future<void> clearInside(String token, int site, int id) async {
    await _send('POST', _site(site, 'inside/$id/clear'), token, body: const <String, Object?>{});
  }

  Future<PlateResidentOverview> residentOverview(String token, int site) async {
    return PlateResidentOverview.fromJson(await _send('GET', '/app/plate-permits', token, query: <String, String>{'site_code': '$site'}));
  }

  Future<void> residentCreate(String token, int site, PermitDraft draft) async {
    await _send('POST', '/app/plate-permits', token, body: <String, Object?>{'site_code': site, ...draft.toBody()}, okStatuses: const <int>{201});
  }

  Future<void> residentRevoke(String token, int site, int id) async {
    await _send('POST', '/app/plate-permits/$id/revoke', token, body: <String, Object?>{'site_code': site});
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
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      final raw = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (raw is Map) payload = Map<String, dynamic>.from(raw);
    } on FormatException {
      // Gövde JSON değil.
    }
    if (okStatuses.contains(response.statusCode)) return payload;
    final code = payload['code'] is String ? payload['code'] as String : null;
    if (response.statusCode == 401) throw SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    throw ApiException(_message(code, payload['error'], response.statusCode), statusCode: response.statusCode, code: code, payload: payload);
  }

  /// Sunucu mesajı Türkçe ve kullanıcıya yöneliktir; bu kodlar için olduğu gibi gösterilir.
  static const Set<String> _serverTextCodes = <String>{
    'INVALID_BODY',
    'PLATE_INVALID',
    'PERMIT_EXISTS',
    'DAILY_LIMIT',
    'BLACKLIST_EXISTS',
    'BLACKLIST_FULL',
    'CAMERA_ALREADY_MAPPED',
    'GATE_NAME_TAKEN',
    'DEVICE_ALREADY_MAPPED',
    'DEVICE_NOT_FOUND',
    'CAMERA_NOT_FOUND',
    'CAMERA_DIRECTION_CONFLICT',
    'GATE_NOT_FOUND',
    'EDGE_CLIENT_NOT_FOUND',
    'RISK_CONFIRM_REQUIRED',
    'FORBIDDEN_APARTMENT',
  };

  static String _message(String? code, Object? serverText, int status) {
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Plaka Tanıma modülü bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
    }
    if (code != null && _serverTextCodes.contains(code) && serverText is String && serverText.trim().isNotEmpty) return serverText.trim();
    final mapped = code == null ? null : AuthApi.messageForErrorCode(code);
    if (mapped != null) return mapped;
    if (serverText is String && serverText.trim().isNotEmpty) return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    return 'İşlem başarısız ($status)';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman.
class PlateRecognitionService {
  PlateRecognitionService({required this.authService, PlateRecognitionApi? api}) : api = api ?? PlateRecognitionApi(baseUrl: authService.api.baseUrl);

  final AuthService authService;
  final PlateRecognitionApi api;

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

  Future<List<PlateDecisionRow>> events(int site, {String? decision}) => _guard((t) => api.events(t, site, decision: decision));
  Future<List<PlatePermit>> permits(int site) => _guard((t) => api.permits(t, site));
  Future<List<PlateApartment>> searchApartments(int site, String q) => _guard((t) => api.searchApartments(t, site, q));
  Future<void> createPermit(int site, PermitDraft draft) => _guard((t) => api.createPermit(t, site, draft));
  Future<void> revokePermit(int site, int id) => _guard((t) => api.revokePermit(t, site, id));
  Future<List<PlateBlacklistItem>> blacklist(int site) => _guard((t) => api.blacklist(t, site));
  Future<void> addBlacklist(int site, String plate, String reason) => _guard((t) => api.addBlacklist(t, site, plate, reason));
  Future<void> removeBlacklist(int site, int id) => _guard((t) => api.removeBlacklist(t, site, id));
  Future<PlateSettings> settings(int site) => _guard((t) => api.settings(t, site));
  Future<PlateSettings> saveGate(
    int site,
    int doorId, {
    required int? deviceId,
    required bool autoOpen,
    required double minConfidence,
    required int cooldownSeconds,
    required bool confirmRisk,
  }) => _guard(
    (t) => api.saveGate(t, site, doorId, deviceId: deviceId, autoOpen: autoOpen, minConfidence: minConfidence, cooldownSeconds: cooldownSeconds, confirmRisk: confirmRisk),
  );
  Future<PlateGatesOverview> gatesOverview(int site) => _guard((t) => api.gatesOverview(t, site));
  Future<PlateGatesOverview> createGatePoint(int site, GateDraft draft) => _guard((t) => api.createGatePoint(t, site, draft));
  Future<PlateGatesOverview> updateGatePoint(int site, int id, GateDraft draft) => _guard((t) => api.updateGatePoint(t, site, id, draft));
  Future<PlateGatesOverview> deleteGatePoint(int site, int id) => _guard((t) => api.deleteGatePoint(t, site, id));
  Future<void> saveGateSettings(int site, {required String guestRule, required int warnSeconds, required int critSeconds}) =>
      _guard((t) => api.saveGateSettings(t, site, guestRule: guestRule, warnSeconds: warnSeconds, critSeconds: critSeconds));
  Future<String> createEdgeClient(int site, String name) => _guard((t) => api.createEdgeClient(t, site, name));
  Future<String> rotateEdgeKey(int site, int id) => _guard((t) => api.rotateEdgeKey(t, site, id));
  Future<void> revokeEdgeClient(int site, int id) => _guard((t) => api.revokeEdgeClient(t, site, id));
  Future<PlateInside> inside(int site) => _guard((t) => api.inside(t, site));
  Future<void> clearInside(int site, int id) => _guard((t) => api.clearInside(t, site, id));
  Future<PlateResidentOverview> residentOverview(int site) => _guard((t) => api.residentOverview(t, site));
  Future<void> residentCreate(int site, PermitDraft draft) => _guard((t) => api.residentCreate(t, site, draft));
  Future<void> residentRevoke(int site, int id) => _guard((t) => api.residentRevoke(t, site, id));
}
