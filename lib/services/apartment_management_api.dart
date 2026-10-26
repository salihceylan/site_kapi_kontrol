// Daire sahipliği ve yönetimi (Dairem) uçları. Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md.
//
// [ApartmentManagementApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [ApartmentManagementService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
// Kurallar: mutasyonlar ASLA otomatik yeniden denenmez; 401 yetkili uçlarda "oturum bitti"dir; yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/apartment_household.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/models/apartment_vehicles.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/models/residency_log.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class ApartmentManagementApi {
  ApartmentManagementApi({
    required String baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 25),
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _timeout = timeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _timeout;

  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    required String token,
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        method == 'GET'
            ? 'Sunucu yanıt vermedi, tekrar deneyin.'
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; ekranı yenileyip kontrol edin.',
      );
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    final parsed = _object(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) return parsed ?? <String, dynamic>{};
    throw _failure(response, parsed);
  }

  /// Dosya (PDF / CSV) döndüren uç: başarıda gövde baytları ve `Content-Disposition` dosya adı; hata gövdesi [call] ile aynı çevrilir.
  Future<({Uint8List bytes, String? fileName})> callFile(String method, String path, {required String token, Object? body}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': '*/*',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final disposition = response.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename="([A-Za-z0-9._-]{1,120})"').firstMatch(disposition);
      return (bytes: response.bodyBytes, fileName: match?.group(1));
    }
    throw _failure(response, _object(response.bodyBytes));
  }

  static Map<String, dynamic>? _object(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } on FormatException {
      return null;
    }
  }

  static ApiException _failure(http.Response response, Map<String, dynamic>? body) {
    final status = response.statusCode;
    if (body == null) {
      if ((status == 401 || status == 403) && response.bodyBytes.isNotEmpty) {
        return ApiException(
          'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      return ApiException(
        status >= 500 ? 'Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin.' : 'İşlem başarısız ($status)',
        statusCode: status,
      );
    }
    final rawCode = body['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final rawError = body['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty ? AuthApi.sanitizeServerMessage(rawError.trim()) : null;
    if (status == 401) {
      return SessionExpiredException(
        code == 'ACCOUNT_DELETED' ? 'Bu hesap silinmiş.' : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.',
        code,
      );
    }
    final retry = body['retry_after_seconds'];
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    return ApiException(
      serverText ?? generic ?? 'İşlem başarısız ($status)',
      statusCode: status,
      code: code,
      retryAfterSeconds: retry is num ? retry.ceil() : null,
      payload: body,
      genericFallback: serverText == null && generic == null,
    );
  }
}

/// Oturum belirtecini [AuthService]'ten alan ve oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar bunu kullanır
/// (testlerde sahte alt sınıf kurulur; her yöntem geçersiz kılınabilir).
class ApartmentManagementService {
  ApartmentManagementService({required this.authService, ApartmentManagementApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? ApartmentManagementApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [ApartmentManagementApi] vermek için.
  @visibleForTesting
  static ApartmentManagementApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final ApartmentManagementApi api;

  Future<T> _guard<T>(Future<T> Function(String token) run) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await run(token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }

  String _apt(int id, [String tail = '']) => '/app/apartments/$id${tail.isEmpty ? '' : '/$tail'}';
  String _mgr(int siteCode, String tail) => '/manager/sites/$siteCode/$tail';

  // --- Sakin ---

  Future<MyApartmentsData> mine() async =>
      MyApartmentsData.fromJson(await _guard((t) => api.call('GET', '/app/apartments/mine', token: t)));

  Future<PersonSearchResult> searchPeople(String q) async => PersonSearchResult.fromJson(
    await _guard((t) => api.call('GET', '/app/apartments/people-search', token: t, query: <String, String>{'q': q})),
  );

  Future<void> addTenant(int apartmentId, Map<String, Object?> body) =>
      _guard((t) => api.call('POST', _apt(apartmentId, 'tenant'), token: t, body: body));

  Future<void> addFamily(int apartmentId, Map<String, Object?> body) =>
      _guard((t) => api.call('POST', _apt(apartmentId, 'family'), token: t, body: body));

  /// 'removed' (hemen çıkarıldı) ya da 'consent_requested' (yetişkin üyeye onay isteği gitti).
  Future<String> removeFamily(int apartmentId, int residencyId) async {
    final r = await _guard((t) => api.call('DELETE', _apt(apartmentId, 'family/$residencyId'), token: t));
    return r['mode'] is String ? r['mode'] as String : 'removed';
  }

  Future<ExitPreview> exitPreview(int apartmentId) async =>
      ExitPreview.fromJson(await _guard((t) => api.call('GET', _apt(apartmentId, 'exit-preview'), token: t)));

  Future<void> exitTenancy(int apartmentId) => _guard((t) => api.call('POST', _apt(apartmentId, 'exit'), token: t));

  Future<void> leave(int apartmentId) => _guard((t) => api.call('POST', _apt(apartmentId, 'leave'), token: t));

  Future<void> requestDisconnect(int apartmentId) =>
      _guard((t) => api.call('POST', _apt(apartmentId, 'disconnect-requests'), token: t));

  Future<void> respond(int requestId, {required bool accept}) => _guard(
    (t) => api.call('POST', '/app/apartments/requests/$requestId/respond', token: t, body: <String, Object?>{'accept': accept}),
  );

  Future<void> cancelRequest(int requestId) =>
      _guard((t) => api.call('POST', '/app/apartments/requests/$requestId/cancel', token: t));

  Future<void> createProxy(int apartmentId, {required String scope, String? validFrom, String? validUntil}) => _guard(
    (t) => api.call(
      'POST',
      _apt(apartmentId, 'proxies'),
      token: t,
      body: <String, Object?>{'scope': scope, 'valid_from': ?validFrom, 'valid_until': ?validUntil},
    ),
  );

  Future<void> revokeProxy(int apartmentId, int proxyId) =>
      _guard((t) => api.call('DELETE', _apt(apartmentId, 'proxies/$proxyId'), token: t));

  // --- Araçlarım (daire araçları; yazma: daire yöneticisi ya da site yöneticisi) ---

  Future<ApartmentVehicles> vehicles(int apartmentId) async =>
      ApartmentVehicles.fromJson(await _guard((t) => api.call('GET', _apt(apartmentId, 'vehicles'), token: t)));

  Future<VehicleRecord> addVehicle(int apartmentId, {required String plate, String? note, int? personId}) async {
    final r = await _guard(
      (t) => api.call(
        'POST',
        _apt(apartmentId, 'vehicles'),
        token: t,
        body: <String, Object?>{'plate': plate, 'note': ?note, 'person_id': ?personId},
      ),
    );
    return VehicleRecord.fromJson(Map<String, dynamic>.from(r['vehicle'] as Map));
  }

  /// Plaka değişmez; not (boş metin = notu sil) ve/veya sahip.
  Future<void> updateVehicle(int apartmentId, int vehicleId, {String? note, int? personId}) => _guard(
    (t) => api.call(
      'PUT',
      _apt(apartmentId, 'vehicles/$vehicleId'),
      token: t,
      body: <String, Object?>{'note': ?note, 'person_id': ?personId},
    ),
  );

  Future<void> removeVehicle(int apartmentId, int vehicleId) =>
      _guard((t) => api.call('DELETE', _apt(apartmentId, 'vehicles/$vehicleId'), token: t));

  Future<void> markNoticesRead([List<int>? ids]) => _guard(
    (t) => api.call('POST', '/app/apartments/notices/read', token: t, body: <String, Object?>{'ids': ?ids}),
  );

  Future<void> sendSafetyRequest(int apartmentId, {required String message, String? contactPref}) => _guard(
    (t) => api.call(
      'POST',
      _apt(apartmentId, 'safety-requests'),
      token: t,
      body: <String, Object?>{'message': message, 'contact_pref': ?contactPref},
    ),
  );

  Future<bool> getSearchVisibility() async =>
      (await _guard((t) => api.call('GET', '/app/apartments/search-visibility', token: t)))['search_visible'] == true;

  Future<void> setSearchVisibility(bool value) => _guard(
    (t) => api.call('PUT', '/app/apartments/search-visibility', token: t, body: <String, Object?>{'search_visible': value}),
  );

  // --- Yönetim (site yöneticisi / kurul okur) ---

  Future<SigningRoster> signingRoster(int siteCode, {String? date}) async => SigningRoster.fromJson(
    await _guard(
      (t) => api.call('GET', _mgr(siteCode, 'signing-roster'), token: t, query: <String, String>{'date': ?date}),
    ),
  );

  /// Dairenin TÜM güncel sakinleri + daire admini (salt okunur). Yönetici / süper tam bilgi, kurul yalnız ad + ilişki alır.
  Future<ApartmentHousehold> household(int siteCode, int apartmentId) async => ApartmentHousehold.fromJson(
    await _guard((t) => api.call('GET', _mgr(siteCode, 'apartments/$apartmentId/household'), token: t)),
  );

  Future<AdminCandidates> adminCandidates(int siteCode, int apartmentId) async => AdminCandidates.fromJson(
    await _guard((t) => api.call('GET', _mgr(siteCode, 'apartments/$apartmentId/admin-candidates'), token: t)),
  );

  Future<void> changeAdmin(
    int siteCode,
    int apartmentId, {
    int? userCode,
    int? personId,
  }) => _guard(
    (t) => api.call('PUT', _mgr(siteCode, 'apartments/$apartmentId/admin'), token: t, body: <String, Object?>{
      'user_code': ?userCode,
      'person_id': ?personId,
    }),
  );

  Future<List<SafetyRequestItem>> safetyRequests(int siteCode, {String? status}) async {
    final r = await _guard(
      (t) => api.call('GET', _mgr(siteCode, 'safety-requests'), token: t, query: <String, String>{'status': ?status}),
    );
    final items = r['items'];
    return <SafetyRequestItem>[
      if (items is List) for (final e in items) if (e is Map) SafetyRequestItem.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> updateSafetyRequest(int siteCode, int id, {String? status, String? note}) => _guard(
    (t) => api.call(
      'PUT',
      _mgr(siteCode, 'safety-requests/$id'),
      token: t,
      body: <String, Object?>{'status': ?status, 'note': ?note},
    ),
  );

  Future<List<SuspensionItem>> suspensions(int siteCode, int apartmentId) async {
    final r = await _guard((t) => api.call('GET', _mgr(siteCode, 'apartments/$apartmentId/suspensions'), token: t));
    final items = r['items'];
    return <SuspensionItem>[
      if (items is List) for (final e in items) if (e is Map) SuspensionItem.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> suspend(int siteCode, int apartmentId, int userCode, {required String reasonCode, required String note}) => _guard(
    (t) => api.call(
      'POST',
      _mgr(siteCode, 'apartments/$apartmentId/members/$userCode/suspend'),
      token: t,
      body: <String, Object?>{'reason_code': reasonCode, 'note': note},
    ),
  );

  Future<void> lift(int siteCode, int apartmentId, int userCode, {String? note}) => _guard(
    (t) => api.call(
      'POST',
      _mgr(siteCode, 'apartments/$apartmentId/members/$userCode/lift'),
      token: t,
      body: <String, Object?>{'note': ?note},
    ),
  );

  // --- Adli kayıt (yalnız site yöneticisi / süper kullanıcı; kurul ve görevli 403) ---

  /// Dairenin eski sakin / adli kaydı (yeniden eskiye, sayfalı) + kayda yazılmamış eski dönemler (yalnız ilk sayfa).
  Future<ResidencyLogPage> residencyLog(int siteCode, int apartmentId, {int offset = 0, int limit = 20}) async => ResidencyLogPage.fromJson(
    await _guard(
      (t) => api.call(
        'GET',
        _mgr(siteCode, 'apartments/$apartmentId/residency-log'),
        token: t,
        query: <String, String>{'limit': '$limit', 'offset': '$offset'},
      ),
    ),
  );

  /// Adli bilgi dökümü (PDF ya da CSV). Gerekçe kodu ve not ZORUNLUdur; not URL'ye değil POST gövdesine konur. Döküm alma sunucuda denetim kaydına yazılır.
  Future<ForensicExportFile> residencyLogExport(
    int siteCode, {
    required String format,
    required String reasonCode,
    required String note,
    int? apartmentId,
  }) {
    return _guard((t) async {
      final file = await api.callFile(
        'POST',
        _mgr(siteCode, 'residency-log/export'),
        token: t,
        body: <String, Object?>{'format': format, 'reason_code': reasonCode, 'note': note, 'apartment_id': ?apartmentId},
      );
      return ForensicExportFile(
        bytes: file.bytes,
        fileName: file.fileName ?? 'adli-bilgi-dokumu.$format',
        mimeType: format == 'pdf' ? 'application/pdf' : 'text/csv',
      );
    });
  }
}
