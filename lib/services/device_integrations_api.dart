// Kart ödemesi arayüzü (Aidat ve Finans'ın parçası; eski `card_payments` modülü kaldırıldı) ve kamera/plaka bağdaştırıcıları (`plate_cameras`) uçları.
//
// Ödeme sağlayıcıları (iyzico, PayTR) henüz "Yakında…" durumundadır: yalnız komisyon bilgi alanı kaydedilir.
// Kamera plaka olayları yalnız KAYIT altına alınır; kapı açma / geçiş YOKTUR. Kamera parolası ve olay belirteci günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// "Kamera ve Plaka" ekranındaki bir site (`plate_cameras` modülü AÇIK) ve yazma yetkisi var mı.
class DeviceSite {
  const DeviceSite({
    required this.code,
    required this.name,
    this.canWrite = true,
  });

  final int code;
  final String name;
  final bool canWrite;

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

/// Online tahsilat sağlayıcı alanı (sunucudaki tanımdan; sır değeri HİÇBİR zaman gelmez).
class CollectionField {
  const CollectionField({required this.key, required this.label, required this.secret, required this.required, this.hint});

  final String key;
  final String label;
  final bool secret;
  final bool required;
  final String? hint;
}

class CollectionProvider {
  const CollectionProvider({required this.code, required this.name, required this.driverActive, required this.fields});

  final String code;
  final String name;
  final bool driverActive;
  final List<CollectionField> fields;
}

/// Bağlantı durumu: `none` (yok), `not_ready` (sanal POS hazır değil), `configured_test`, `configured_live`.
class OnlineCollectionState {
  const OnlineCollectionState({
    required this.status,
    this.provider,
    this.mode,
    this.values = const <String, String>{},
    this.secretsSet = const <String, bool>{},
    this.complete = false,
    this.driverActive = false,
    this.lastTestStatus,
    this.lastTestMessage,
    this.providers = const <CollectionProvider>[],
  });

  factory OnlineCollectionState.fromJson(Map<String, dynamic> json) {
    final test = json['last_test'] is Map ? Map<String, dynamic>.from(json['last_test'] as Map) : null;
    return OnlineCollectionState(
      status: '${json['status'] ?? 'none'}',
      provider: json['provider'] as String?,
      mode: json['mode'] as String?,
      values: <String, String>{
        if (json['values'] is Map) for (final e in (json['values'] as Map).entries) '${e.key}': '${e.value}',
      },
      secretsSet: <String, bool>{
        if (json['secrets_set'] is Map) for (final e in (json['secrets_set'] as Map).entries) '${e.key}': e.value == true,
      },
      complete: json['complete'] == true,
      driverActive: json['driver_active'] == true,
      lastTestStatus: test?['status'] as String?,
      lastTestMessage: test?['message'] as String?,
      providers: <CollectionProvider>[
        for (final raw in (json['providers'] as List? ?? const []))
          if (raw is Map)
            CollectionProvider(
              code: '${raw['code']}',
              name: '${raw['name']}',
              driverActive: raw['driver_active'] == true,
              fields: <CollectionField>[
                for (final f in (raw['fields'] as List? ?? const []))
                  if (f is Map)
                    CollectionField(
                      key: '${f['key']}',
                      label: '${f['label']}',
                      secret: f['secret'] == true,
                      required: f['required'] == true,
                      hint: f['hint'] as String?,
                    ),
              ],
            ),
      ],
    );
  }

  final String status;
  final String? provider;
  final String? mode;
  final Map<String, String> values;
  final Map<String, bool> secretsSet;
  final bool complete;
  final bool driverActive;
  final String? lastTestStatus;
  final String? lastTestMessage;
  final List<CollectionProvider> providers;

  CollectionProvider? get current {
    for (final p in providers) {
      if (p.code == provider) return p;
    }
    return null;
  }
}

/// "Bağlantıyı sına" sonucu. [ok] yalnız sağlayıcı gerçekten doğruladıysa true'dur.
class CollectionTestResult {
  const CollectionTestResult({required this.ok, required this.message, required this.state});

  final bool ok;
  final String message;
  final OnlineCollectionState state;
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

  Future<OnlineCollectionState> onlineCollection(String token, int siteCode) async {
    final json = await _send('GET', _site(siteCode, 'payment-provider'), token);
    return OnlineCollectionState.fromJson(Map<String, dynamic>.from(json['state'] as Map));
  }

  /// [values]: sır alanı boş bırakılırsa sunucu mevcut sırrı korur.
  Future<OnlineCollectionState> saveOnlineCollection(
    String token,
    int siteCode, {
    required String provider,
    required String mode,
    required Map<String, String> values,
  }) async {
    final json = await _send(
      'PUT',
      _site(siteCode, 'payment-provider'),
      token,
      body: <String, Object?>{'provider': provider, 'mode': mode, 'values': values},
    );
    return OnlineCollectionState.fromJson(Map<String, dynamic>.from(json['state'] as Map));
  }

  Future<CollectionTestResult> testOnlineCollection(String token, int siteCode) async {
    final json = await _send('POST', _site(siteCode, 'payment-provider/test'), token, body: const <String, Object?>{});
    final result = Map<String, dynamic>.from(json['result'] as Map);
    return CollectionTestResult(
      ok: result['ok'] == true,
      message: '${result['message'] ?? ''}',
      state: OnlineCollectionState.fromJson(Map<String, dynamic>.from(json['state'] as Map)),
    );
  }

  Future<void> removeOnlineCollection(String token, int siteCode) async {
    await _send('DELETE', _site(siteCode, 'payment-provider'), token);
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
      case 'PAYMENT_NOT_CONFIGURED':
        return 'Online tahsilat bu sunucuda henüz etkinleştirilmedi. Sistem yöneticisi sunucu ayarını tamamlayınca burada kurulum yapabilirsiniz.';
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
  Future<OnlineCollectionState> onlineCollection(int site) => _guard((t) => api.onlineCollection(t, site));
  Future<OnlineCollectionState> saveOnlineCollection(int site, {required String provider, required String mode, required Map<String, String> values}) =>
      _guard((t) => api.saveOnlineCollection(t, site, provider: provider, mode: mode, values: values));
  Future<CollectionTestResult> testOnlineCollection(int site) => _guard((t) => api.testOnlineCollection(t, site));
  Future<void> removeOnlineCollection(int site) => _guard((t) => api.removeOnlineCollection(t, site));
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
