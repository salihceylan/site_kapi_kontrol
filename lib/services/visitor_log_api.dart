// Ziyaretçi ve Kargo (`visitor_log`) uçları: docs/PLATFORM_ZIYARETCI_KARGO.md.
//
// [VisitorLogApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [VisitorLogService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (WorkTrackingApi ile aynı):
// - Mutasyonlar (POST/PATCH) ASLA otomatik yeniden denenmez; çift işlem riski. Yeniden deneme kullanıcı kararıdır.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive
//   portal) geçici ağ hatasıdır.
// - Ziyaretçi adı, firma, not, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class VisitorLogApi {
  VisitorLogApi({
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

  static String _managerPath(int siteCode, [String tail = '']) =>
      '/manager/sites/$siteCode/visitor-entries${tail.isEmpty ? '' : '/$tail'}';

  // --- Sakin --------------------------------------------------------------------------------

  /// `GET /app/visitor-entries?site_code=&limit=&before_id=` (yalnız kendi dairelerinin kayıtları).
  Future<VisitorResidentPage> listMine({
    required String token,
    int? siteCode,
    int limit = 30,
    int? beforeId,
  }) async {
    final response = await _send(
      'GET',
      '/app/visitor-entries',
      token: token,
      query: <String, String>{
        if (siteCode != null) 'site_code': '$siteCode',
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return VisitorResidentPage.fromJson(_object(response));
  }

  /// `GET /app/visitor-entries/summary` -> okunmamış kayıt sayısı.
  Future<int> unreadCount({required String token}) async {
    final response = await _send(
      'GET',
      '/app/visitor-entries/summary',
      token: token,
      timeout: _readTimeout,
    );
    final raw = _object(response)['unread'];
    if (raw is num && raw.isFinite && raw > 0) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  /// `POST /app/visitor-entries/:id/seen` (idempotent).
  Future<void> markSeen({required String token, required int id}) async {
    await _send(
      'POST',
      '/app/visitor-entries/$id/seen',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
  }

  // --- Yönetim ------------------------------------------------------------------------------

  /// `GET /manager/sites/:siteCode/visitor-entries?kind=&status=&apartment_id=&q=&from=&to=&limit=&offset=`.
  Future<VisitorManagedPage> listManaged({
    required String token,
    required int siteCode,
    String? kind,
    String? status,
    int? apartmentId,
    String? query,
    String? from,
    String? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _send(
      'GET',
      _managerPath(siteCode),
      token: token,
      query: <String, String>{
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (status != null && status.isNotEmpty) 'status': status,
        if (apartmentId != null) 'apartment_id': '$apartmentId',
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'limit': '$limit',
        'offset': '$offset',
      },
      timeout: _readTimeout,
    );
    return VisitorManagedPage.fromJson(_object(response));
  }

  /// `POST .../visitor-entries` (201 Entry; durumu sunucu hesaplar).
  Future<VisitorEntry> create({
    required String token,
    required int siteCode,
    required VisitorCreateRequest request,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode),
      token: token,
      body: request.toJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _entry(response);
  }

  /// `PATCH .../visitor-entries/:id {status?, note?}` -> Entry (geçiş kuralları sunucuda).
  Future<VisitorEntry> update({
    required String token,
    required int siteCode,
    required int id,
    VisitorStatus? status,
    String? note,
  }) async {
    final response = await _send(
      'PATCH',
      _managerPath(siteCode, '$id'),
      token: token,
      body: <String, dynamic>{
        if (status != null) 'status': status.apiValue,
        if (note != null) 'note': note.trim(),
      },
      timeout: _writeTimeout,
    );
    return _entry(response);
  }

  VisitorEntry _entry(http.Response response) {
    final entry = VisitorEntry.fromJson(_object(response));
    if (entry.id <= 0) throw _unexpected(response);
    return entry;
  }

  ApiException _unexpected(http.Response response) => ApiException(
    'Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin.',
    statusCode: response.statusCode,
  );

  // --- JSON taşıma katmanı ------------------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? query]) {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
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
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        method == 'GET'
            ? 'Sunucu yanıt vermedi, tekrar deneyin.'
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; ekranı yenileyip kontrol edin.',
      );
    } on http.ClientException {
      throw ApiException(_transportMessage);
    } on Exception {
      // SocketException, TlsException, ... (ayrıntı kullanıcıya gösterilmez).
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

  static const String _transportMessage =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  // --- Hata çevirisi ------------------------------------------------------------------------

  ApiException _failure(http.Response response) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
      if (status == 413) {
        return ApiException(
          visitorLogErrorMessage('BODY_TOO_LARGE')!,
          statusCode: 413,
          code: 'BODY_TOO_LARGE',
        );
      }
      if ((status == 401 || status == 403) && !empty) {
        // JSON olmayan 401/403: proxy / WAF / captive portal; oturum sonu DEĞİL.
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
    final code = rawCode is String && rawCode.trim().isNotEmpty
        ? rawCode.trim()
        : null;
    final rawError = body['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty
        ? AuthApi.sanitizeServerMessage(rawError.trim())
        : null;

    if (status == 401) {
      return SessionExpiredException(
        code == 'TOKEN_REVOKED'
            ? 'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.'
            : (code == 'ACCOUNT_DELETED'
                  ? 'Bu hesap silinmiş.'
                  : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }

    final mapped = visitorLogErrorMessage(
      code,
      retryAfterSeconds: retryAfter,
      payload: body,
      serverText: serverText,
    );
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    final fallback = mapped == null && serverText == null && generic == null;
    var message =
        mapped ?? serverText ?? generic ?? 'İşlem başarısız ($status)';
    if (status == 429 && mapped == null) {
      message = _withRetryHint(message, retryAfter);
    }
    if (status >= 500) {
      final errorId = body['errorId'] ?? body['error_id'];
      if (errorId is String && errorId.isNotEmpty) {
        message = '$message (Hata kodu: $errorId)';
      }
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

  /// Ziyaretçi ve Kargo hata kodları için düz Türkçe metin (sözleşme "Hata kodları"); bilinmiyorsa genel kodlar
  /// ([AuthApi.messageForErrorCode]) ya da null (sunucunun kendi `error` metni kullanılır).
  static String? visitorLogErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
    String? serverText,
  }) {
    if (code == null) return null;
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Ziyaretçi ve kargo kaydı bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'VISITOR_ENTRY_NOT_FOUND':
        return 'Kayıt bulunamadı ya da erişiminiz yok.';
      case 'APARTMENT_NOT_FOUND':
        return 'Seçilen daire bu sitede bulunamadı. Daireyi yeniden seçin.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'INVALID_SITE_CODE':
        return 'Site geçersiz. Siteyi yeniden seçin.';
      case 'INVALID_BODY':
        return serverText ??
            'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.';
      case 'INVALID_QUERY':
        return 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.';
      case 'INVALID_TRANSITION':
        return 'Kaydın durumu bu şekilde değiştirilemez. Kayıt başka biri tarafından kapatılmış olabilir; yenileyip tekrar deneyin.';
      case 'BODY_TOO_LARGE':
        return 'Gönderilen içerik çok büyük. Metni kısaltın.';
    }
    return AuthApi.messageForErrorCode(
      code,
      retryAfterSeconds: retryAfterSeconds,
      payload: payload,
    );
  }

  static String _withRetryHint(String base, int? retryAfter) {
    if (retryAfter == null) return base;
    if (base.toLowerCase().contains('sonra')) return base;
    final trimmed = base.endsWith('.') ? base : '$base.';
    return '$trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin.';
  }

  static int? _retryAfterSeconds(
    http.Response response,
    Map<String, dynamic>? payload,
  ) {
    final body =
        payload?['retry_after_seconds'] ?? payload?['retryAfterSeconds'];
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

  // --- Gövde çözümleme ----------------------------------------------------------------------

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map<String, dynamic>
          ? raw
          : (raw is Map ? Map<String, dynamic>.from(raw) : null);
    } on FormatException {
      return null;
    }
  }

  /// Başarılı yanıt gövdesi JSON nesnesi olmak ZORUNDA (yoksa kullanıcıya anlaşılır hata).
  static Map<String, dynamic> _object(http.Response response) {
    final parsed = _tryObject(response.bodyBytes);
    if (parsed == null) {
      throw ApiException(
        'Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    return parsed;
  }
}

/// Oturum belirtecini [AuthService]'ten alan ve oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar bunu
/// kullanır (testlerde sahte [VisitorLogService] kurulur).
class VisitorLogService {
  VisitorLogService({required this.authService, VisitorLogApi? api})
    : api =
          api ??
          debugApiFactory?.call(authService) ??
          VisitorLogApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [VisitorLogApi] vermek için.
  @visibleForTesting
  static VisitorLogApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final VisitorLogApi api;

  Future<T> _guard<T>(Future<T> Function(String token) call) async {
    final token = authService.session?.token;
    if (token == null) {
      throw ApiException('Oturum açmanız gerekmektedir.');
    }
    try {
      return await call(token);
    } on ApiException catch (e) {
      // 401: oturum gerçekten bitmiş olabilir; çıkışı AuthService'in /me doğrulaması yapar.
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }

  // --- Sakin ---

  Future<VisitorResidentPage> listMine({
    int? siteCode,
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listMine(
      token: token,
      siteCode: siteCode,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<int> unreadCount() => _guard((token) => api.unreadCount(token: token));

  Future<void> markSeen(int id) =>
      _guard((token) => api.markSeen(token: token, id: id));

  // --- Yönetim ---

  Future<VisitorManagedPage> listManaged(
    int siteCode, {
    String? kind,
    String? status,
    int? apartmentId,
    String? query,
    String? from,
    String? to,
    int limit = 50,
    int offset = 0,
  }) => _guard(
    (token) => api.listManaged(
      token: token,
      siteCode: siteCode,
      kind: kind,
      status: status,
      apartmentId: apartmentId,
      query: query,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
    ),
  );

  Future<VisitorEntry> create(int siteCode, VisitorCreateRequest request) =>
      _guard(
        (token) => api.create(token: token, siteCode: siteCode, request: request),
      );

  Future<VisitorEntry> update(
    int siteCode,
    int id, {
    VisitorStatus? status,
    String? note,
  }) => _guard(
    (token) => api.update(
      token: token,
      siteCode: siteCode,
      id: id,
      status: status,
      note: note,
    ),
  );
}
