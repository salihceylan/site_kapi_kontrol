// Anket ve Oylama uçları: docs/PLATFORM_ANKET.md (F11.01).
//
// [SurveyApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [SurveyService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (ReservationApi ile aynı): mutasyonlar ASLA otomatik yeniden denenmez; 401 yetkili uçlarda "oturum
// bitti"dir; JSON olmayan 401/403 geçici ağ hatasıdır; oy içeriği, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class SurveyApi {
  SurveyApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 20),
    Duration writeTimeout = const Duration(seconds: 45),
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;

  static String _managerPath(int siteCode, String tail) => '/manager/sites/$siteCode/$tail';

  // --- Yönetim ------------------------------------------------------------------------------

  /// `GET /manager/sites/:siteCode/surveys?status=&limit=&offset=` -> `{items, total}`.
  Future<SurveyListPage> listManaged({
    required String token,
    required int siteCode,
    String status = 'all',
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'surveys'),
      token: token,
      query: <String, String>{'status': status, 'limit': '$limit', 'offset': '$offset'},
      timeout: _readTimeout,
    );
    return SurveyListPage.fromJson(_object(response));
  }

  /// `POST .../surveys` (201) -> Detail.
  Future<SurveyDetail> create({
    required String token,
    required int siteCode,
    required SurveyCreateRequest request,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode, 'surveys'),
      token: token,
      body: request.toJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _detail(response);
  }

  /// `GET .../surveys/:id` -> Detail.
  Future<SurveyDetail> getManaged({required String token, required int siteCode, required int id}) async {
    final response = await _send('GET', _managerPath(siteCode, 'surveys/$id'), token: token, timeout: _readTimeout);
    return _detail(response);
  }

  /// `PATCH .../surveys/:id`: yalnız [fields] içindekiler gönderilir (taslakta her alan; açıkta title ve closes_at).
  Future<SurveyDetail> update({
    required String token,
    required int siteCode,
    required int id,
    required Map<String, Object?> fields,
  }) async {
    final response = await _send(
      'PATCH',
      _managerPath(siteCode, 'surveys/$id'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      timeout: _writeTimeout,
    );
    return _detail(response);
  }

  /// `POST .../surveys/:id/open` (draft -> open).
  Future<SurveyDetail> open({required String token, required int siteCode, required int id}) =>
      _transition(token: token, siteCode: siteCode, id: id, action: 'open');

  /// `POST .../surveys/:id/close` (open -> closed).
  Future<SurveyDetail> close({required String token, required int siteCode, required int id}) =>
      _transition(token: token, siteCode: siteCode, id: id, action: 'close');

  Future<SurveyDetail> _transition({
    required String token,
    required int siteCode,
    required int id,
    required String action,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode, 'surveys/$id/$action'),
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
    return _detail(response);
  }

  /// `DELETE .../surveys/:id` -> `{ok:true}` (yalnız taslak).
  Future<void> delete({required String token, required int siteCode, required int id}) async {
    final response = await _send('DELETE', _managerPath(siteCode, 'surveys/$id'), token: token, timeout: _writeTimeout);
    if (_object(response)['ok'] != true) throw _unexpected(response);
  }

  /// `GET .../surveys/:id/voters?limit&offset` (yalnız anonim olmayan anket; kurul 403).
  Future<SurveyVoterPage> voters({
    required String token,
    required int siteCode,
    required int id,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'surveys/$id/voters'),
      token: token,
      query: <String, String>{'limit': '$limit', 'offset': '$offset'},
      timeout: _readTimeout,
    );
    return SurveyVoterPage.fromJson(_object(response));
  }

  // --- Sakin --------------------------------------------------------------------------------

  /// `GET /app/surveys?site_code=&limit=&before_id=` -> `{items, next_before_id}`.
  Future<SurveyResidentPage> listMine({
    required String token,
    int? siteCode,
    int limit = 30,
    int? beforeId,
  }) async {
    final response = await _send(
      'GET',
      '/app/surveys',
      token: token,
      query: <String, String>{
        if (siteCode != null) 'site_code': '$siteCode',
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return SurveyResidentPage.fromJson(_object(response));
  }

  /// `GET /app/surveys/:id`.
  Future<SurveyResidentItem> getMine({required String token, required int id}) async {
    final response = await _send('GET', '/app/surveys/$id', token: token, timeout: _readTimeout);
    return _residentItem(response);
  }

  /// `POST /app/surveys/:id/vote {option_index}` -> güncel öğe (oy + sonuç).
  Future<SurveyResidentItem> vote({required String token, required int id, required int optionIndex}) async {
    final response = await _send(
      'POST',
      '/app/surveys/$id/vote',
      token: token,
      body: <String, dynamic>{'option_index': optionIndex},
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _residentItem(response);
  }

  // --- Gövde yardımcıları -------------------------------------------------------------------

  SurveyDetail _detail(http.Response response) {
    final detail = SurveyDetail.fromJson(_object(response));
    if (detail.id <= 0) throw _unexpected(response);
    return detail;
  }

  SurveyResidentItem _residentItem(http.Response response) {
    final json = _object(response);
    // Sunucu `{survey: {...}}` sarmalı da döndürebilir.
    final inner = json['survey'];
    final item = SurveyResidentItem.fromJson(inner is Map ? Map<String, dynamic>.from(inner) : json);
    if (item.id <= 0) throw _unexpected(response);
    return item;
  }

  ApiException _unexpected(http.Response response) =>
      ApiException('Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin.', statusCode: response.statusCode);

  // --- JSON taşıma katmanı ------------------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? query]) {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    return uri;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    required Duration timeout,
    Set<int> okStatuses = const <int>{200},
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        method == 'GET'
            ? 'Sunucu yanıt vermedi, tekrar deneyin.'
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; ekranı yenileyip kontrol edin.',
      );
    } on http.ClientException {
      throw ApiException(_transportMessage);
    } on Exception {
      throw ApiException(_transportMessage);
    }
    if (okStatuses.contains(response.statusCode)) return response;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw ApiException(
        'Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    throw _failure(response);
  }

  static const String _transportMessage = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  // --- Hata çevirisi ------------------------------------------------------------------------

  ApiException _failure(http.Response response) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
      if (status == 413) {
        return ApiException(surveyErrorMessage('BODY_TOO_LARGE')!, statusCode: 413, code: 'BODY_TOO_LARGE');
      }
      if ((status == 401 || status == 403) && !empty) {
        return ApiException(
          'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      if (status >= 500) {
        return ApiException(
          'Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin.',
          statusCode: status,
        );
      }
      if (status == 429) {
        return ApiException(
          _withRetryHint('Çok fazla istek gönderildi.', retryAfter),
          statusCode: status,
          retryAfterSeconds: retryAfter,
        );
      }
      if (!empty) {
        return ApiException(
          'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
    }

    final body = payload ?? const <String, dynamic>{};
    final rawCode = body['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final rawError = body['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty
        ? AuthApi.sanitizeServerMessage(rawError.trim())
        : null;

    if (status == 401) {
      return SessionExpiredException(
        code == 'TOKEN_REVOKED'
            ? 'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.'
            : (code == 'ACCOUNT_DELETED' ? 'Bu hesap silinmiş.' : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }

    final mapped = surveyErrorMessage(code, retryAfterSeconds: retryAfter, serverText: serverText);
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    final fallback = mapped == null && serverText == null && generic == null;
    var message = mapped ?? serverText ?? generic ?? 'İşlem başarısız ($status)';
    if (status == 429 && mapped == null) message = _withRetryHint(message, retryAfter);
    if (status >= 500) {
      final errorId = body['errorId'] ?? body['error_id'];
      if (errorId is String && errorId.isNotEmpty) message = '$message (Hata kodu: $errorId)';
    }
    return ApiException(
      message,
      statusCode: status,
      code: code,
      retryAfterSeconds: retryAfter,
      payload: body,
      genericFallback: fallback,
    );
  }

  /// Anket hata kodları için düz Türkçe metin (sözleşme "Hata kodları"); bilinmiyorsa genel kodlar
  /// ([AuthApi.messageForErrorCode]) ya da null (sunucunun kendi `error` metni kullanılır). `INVALID_BODY` sunucunun
  /// alan etiketli metnini taşır ([serverText]).
  static String? surveyErrorMessage(String? code, {int? retryAfterSeconds, String? serverText}) {
    if (code == null) return null;
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Anket ve Oylama bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'SURVEY_NOT_FOUND':
        return 'Anket bulunamadı ya da erişiminiz yok. Listeyi yenileyin.';
      case 'INVALID_STATE':
        return 'Anket bu durumda bu işleme izin vermiyor. Başkası güncellemiş olabilir; yenileyip tekrar deneyin.';
      case 'SURVEY_CLOSED':
        return 'Bu anket oylamaya kapalı.';
      case 'ALREADY_VOTED':
        return 'Bu ankette zaten oy kullandınız. Oy değiştirilemez.';
      case 'APARTMENT_ALREADY_VOTED':
        return 'Bu ankette daireniz adına zaten oy kullanılmış (daire başına tek oy).';
      case 'NOT_ELIGIBLE':
        return 'Bu anketin hedef kitlesinde değilsiniz.';
      case 'INVALID_TARGET':
        return serverText ?? 'Hedef geçersiz. Seçilen blok ya da daireler bu siteye ait olmalı (en çok 500).';
      case 'INVALID_BODY':
        return serverText ?? 'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.';
      case 'INVALID_QUERY':
        return 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.';
      case 'BODY_TOO_LARGE':
        return 'Gönderilen içerik çok büyük. Metni kısaltın.';
    }
    return AuthApi.messageForErrorCode(code, retryAfterSeconds: retryAfterSeconds);
  }

  static String _withRetryHint(String base, int? retryAfter) {
    if (retryAfter == null) return base;
    if (base.toLowerCase().contains('sonra')) return base;
    final trimmed = base.endsWith('.') ? base : '$base.';
    return '$trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin.';
  }

  static int? _retryAfterSeconds(http.Response response, Map<String, dynamic>? payload) {
    final body = payload?['retry_after_seconds'] ?? payload?['retryAfterSeconds'];
    if (body is num && body.isFinite && body > 0) return body.ceil();
    if (body is String) {
      final parsed = int.tryParse(body.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    final header = response.headers['retry-after'];
    if (header != null) {
      final parsed = int.tryParse(header.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map<String, dynamic> ? raw : (raw is Map ? Map<String, dynamic>.from(raw) : null);
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic> _object(http.Response response) {
    final parsed = _tryObject(response.bodyBytes);
    if (parsed == null) {
      throw ApiException('Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.', statusCode: response.statusCode);
    }
    return parsed;
  }
}

/// Oturum belirtecini [AuthService]'ten alan ve oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar bunu
/// kullanır (testlerde sahte [SurveyService] kurulur).
class SurveyService {
  SurveyService({required this.authService, SurveyApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? SurveyApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [SurveyApi] vermek için.
  @visibleForTesting
  static SurveyApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final SurveyApi api;

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

  // --- Yönetim ---

  Future<SurveyListPage> listManaged(int siteCode, {String status = 'all', int limit = 30, int offset = 0}) =>
      _guard((token) => api.listManaged(token: token, siteCode: siteCode, status: status, limit: limit, offset: offset));

  Future<SurveyDetail> create(int siteCode, SurveyCreateRequest request) =>
      _guard((token) => api.create(token: token, siteCode: siteCode, request: request));

  Future<SurveyDetail> getManaged(int siteCode, int id) =>
      _guard((token) => api.getManaged(token: token, siteCode: siteCode, id: id));

  Future<SurveyDetail> update(int siteCode, int id, Map<String, Object?> fields) =>
      _guard((token) => api.update(token: token, siteCode: siteCode, id: id, fields: fields));

  Future<SurveyDetail> open(int siteCode, int id) => _guard((token) => api.open(token: token, siteCode: siteCode, id: id));

  Future<SurveyDetail> close(int siteCode, int id) =>
      _guard((token) => api.close(token: token, siteCode: siteCode, id: id));

  Future<void> delete(int siteCode, int id) => _guard((token) => api.delete(token: token, siteCode: siteCode, id: id));

  Future<SurveyVoterPage> voters(int siteCode, int id, {int limit = 50, int offset = 0}) =>
      _guard((token) => api.voters(token: token, siteCode: siteCode, id: id, limit: limit, offset: offset));

  // --- Sakin ---

  Future<SurveyResidentPage> listMine({int? siteCode, int limit = 30, int? beforeId}) =>
      _guard((token) => api.listMine(token: token, siteCode: siteCode, limit: limit, beforeId: beforeId));

  Future<SurveyResidentItem> getMine(int id) => _guard((token) => api.getMine(token: token, id: id));

  Future<SurveyResidentItem> vote(int id, int optionIndex) =>
      _guard((token) => api.vote(token: token, id: id, optionIndex: optionIndex));
}
