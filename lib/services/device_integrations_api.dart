// Kart ödemesi arayüzü (`card_payments`) ve kamera/plaka bağdaştırıcıları (`plate_cameras`) uçları.
//
// Ödeme sağlayıcıları (iyzico, PayTR) henüz "Yakında…" durumundadır: yalnız komisyon bilgi alanı kaydedilir.
// Kamera plaka olayları yalnız KAYIT altına alınır; kapı açma / geçiş YOKTUR. Kamera parolası ve olay belirteci günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Ekrandaki bir site: hangi modüller açık ve yazma yetkisi var mı.
class DeviceSite {
  const DeviceSite({
    required this.code,
    required this.name,
    this.canWrite = true,
    this.paymentsOn = false,
    this.camerasOn = false,
  });

  final int code;
  final String name;
  final bool canWrite;
  final bool paymentsOn;
  final bool camerasOn;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();
}

class PaymentProviderInfo {
  const PaymentProviderInfo({required this.code, required this.name, required this.commissionInfo});

  final String code;
  final String name;
  final String? commissionInfo;
}

class PaymentOverview {
  const PaymentOverview({required this.notice, required this.providers});

  final String notice;
  final List<PaymentProviderInfo> providers;
}

class CameraDevice {
  const CameraDevice({
    required this.id,
    required this.brand,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.hasPassword,
    required this.isActive,
    required this.lastEventAt,
  });

  factory CameraDevice.fromJson(Map<String, dynamic> json) => CameraDevice(
    id: (json['id'] as num?)?.toInt() ?? 0,
    brand: '${json['brand'] ?? ''}',
    name: '${json['name'] ?? ''}',
    host: '${json['host'] ?? ''}',
    port: (json['port'] as num?)?.toInt(),
    username: json['username'] as String?,
    hasPassword: json['has_password'] == true,
    isActive: json['is_active'] != false,
    lastEventAt: DateTime.tryParse('${json['last_event_at'] ?? ''}')?.toLocal(),
  );

  final int id;
  final String brand;
  final String name;
  final String host;
  final int? port;
  final String? username;
  final bool hasPassword;
  final bool isActive;
  final DateTime? lastEventAt;

  String get brandLabel => cameraBrandLabels[brand] ?? brand;
}

const Map<String, String> cameraBrandLabels = <String, String>{
  'hikvision': 'Hikvision',
  'tiandy': 'Tiandy',
  'onvif': 'ONVIF (diğer)',
};

class PlateEventRow {
  const PlateEventRow({required this.id, required this.plate, required this.matched, required this.seenAt, required this.deviceName});

  factory PlateEventRow.fromJson(Map<String, dynamic> json) => PlateEventRow(
    id: (json['id'] as num?)?.toInt() ?? 0,
    plate: '${json['plate'] ?? ''}',
    matched: json['matched'] == true,
    seenAt: DateTime.tryParse('${json['seen_at'] ?? ''}')?.toLocal(),
    deviceName: '${json['device_name'] ?? ''}',
  );

  final int id;
  final String plate;
  final bool matched;
  final DateTime? seenAt;
  final String deviceName;
}

/// Kamera kaydı sonucu: belirteç yalnız bir kez gösterilir.
class CameraCreated {
  const CameraCreated({required this.camera, required this.eventToken});

  final CameraDevice camera;
  final String eventToken;
}

class DeviceIntegrationsApi {
  DeviceIntegrationsApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _site(int siteCode, String tail) => '/manager/sites/$siteCode/$tail';

  Future<PaymentOverview> payments(String token, int siteCode) async {
    final json = await _send('GET', _site(siteCode, 'card-payments'), token);
    return _overview(json);
  }

  Future<PaymentOverview> saveCommissionInfo(String token, int siteCode, String provider, String info) async {
    final json = await _send('PUT', _site(siteCode, 'card-payments/$provider'), token, body: <String, Object?>{'commission_info': info.trim()});
    return _overview(json);
  }

  Future<List<CameraDevice>> cameras(String token, int siteCode) async {
    final json = await _send('GET', _site(siteCode, 'cameras'), token);
    return <CameraDevice>[for (final raw in (json['cameras'] as List? ?? const [])) if (raw is Map) CameraDevice.fromJson(Map<String, dynamic>.from(raw))];
  }

  Future<CameraCreated> createCamera(
    String token,
    int siteCode, {
    required String brand,
    required String name,
    required String host,
    String? port,
    String? username,
    String? password,
  }) async {
    final json = await _send(
      'POST',
      _site(siteCode, 'cameras'),
      token,
      body: <String, Object?>{
        'brand': brand,
        'name': name.trim(),
        'host': host.trim(),
        if ((port ?? '').trim().isNotEmpty) 'port': port!.trim(),
        if ((username ?? '').trim().isNotEmpty) 'username': username!.trim(),
        if ((password ?? '').isNotEmpty) 'password': password,
      },
      okStatuses: const <int>{201},
    );
    return CameraCreated(camera: CameraDevice.fromJson(Map<String, dynamic>.from(json['camera'] as Map)), eventToken: '${json['event_token']}');
  }

  Future<String> rotateToken(String token, int siteCode, int cameraId) async {
    final json = await _send('POST', _site(siteCode, 'cameras/$cameraId/rotate-token'), token, body: const <String, Object?>{});
    return '${json['event_token']}';
  }

  Future<void> deactivate(String token, int siteCode, int cameraId) async {
    await _send('POST', _site(siteCode, 'cameras/$cameraId/deactivate'), token, body: const <String, Object?>{});
  }

  Future<List<PlateEventRow>> plateEvents(String token, int siteCode) async {
    final json = await _send('GET', _site(siteCode, 'plate-events'), token, query: const <String, String>{'limit': '30'});
    return <PlateEventRow>[for (final raw in (json['events'] as List? ?? const [])) if (raw is Map) PlateEventRow.fromJson(Map<String, dynamic>.from(raw))];
  }

  PaymentOverview _overview(Map<String, dynamic> json) => PaymentOverview(
    notice: '${json['commission_notice'] ?? ''}',
    providers: <PaymentProviderInfo>[
      for (final raw in (json['providers'] as List? ?? const []))
        if (raw is Map)
          PaymentProviderInfo(code: '${raw['code']}', name: '${raw['name']}', commissionInfo: raw['commission_info'] as String?),
    ],
  );

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
    throw ApiException(
      _message(code, payload['error'], response.statusCode),
      statusCode: response.statusCode,
      code: code,
      payload: payload,
    );
  }

  static String _message(String? code, Object? serverText, int status) {
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Bu modül bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'INVALID_BODY':
        if (serverText is String && serverText.trim().isNotEmpty) return serverText.trim();
        return 'Girilen bilgiler geçersiz.';
    }
    final mapped = code == null ? null : AuthApi.messageForErrorCode(code);
    if (mapped != null) return mapped;
    if (serverText is String && serverText.trim().isNotEmpty) return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    return 'İşlem başarısız ($status)';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman.
class DeviceIntegrationsService {
  DeviceIntegrationsService({required this.authService, DeviceIntegrationsApi? api})
    : api = api ?? DeviceIntegrationsApi(baseUrl: authService.api.baseUrl);

  final AuthService authService;
  final DeviceIntegrationsApi api;

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

  Future<PaymentOverview> payments(int site) => _guard((t) => api.payments(t, site));
  Future<PaymentOverview> saveCommissionInfo(int site, String provider, String info) => _guard((t) => api.saveCommissionInfo(t, site, provider, info));
  Future<List<CameraDevice>> cameras(int site) => _guard((t) => api.cameras(t, site));
  Future<List<PlateEventRow>> plateEvents(int site) => _guard((t) => api.plateEvents(t, site));
  Future<CameraCreated> createCamera(
    int site, {
    required String brand,
    required String name,
    required String host,
    String? port,
    String? username,
    String? password,
  }) => _guard((t) => api.createCamera(t, site, brand: brand, name: name, host: host, port: port, username: username, password: password));
  Future<String> rotateToken(int site, int id) => _guard((t) => api.rotateToken(t, site, id));
  Future<void> deactivate(int site, int id) => _guard((t) => api.deactivate(t, site, id));
}
