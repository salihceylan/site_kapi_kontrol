// Sayfa bağlamlı "Geri bildirim" uçları (docs/PLATFORM_GERI_BILDIRIM.md, karar K11).
//
// [FeedbackApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir). [FeedbackService]: oturum belirtecini
// [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (WorkTrackingApi ile aynı ilkeler):
// - Mutasyonlar (POST/PUT) ASLA otomatik yeniden denenmez; yeniden deneme kullanıcı kararıdır.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive portal) geçici ağ hatasıdır.
// - Metin, dosya adı, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
// - Ekler iş takibi fotoğraf eki gibi iki adımlıdır: `POST /app/feedback` (üstveri; ek kayıtları `uploading`), sonra her ek için
//   `PUT /app/feedback/:id/attachments/:attId/content` (ham gövde `application/octet-stream`, `Content-Length` = bildirilen boyut).
//   Dosyalar istemcide küçültülüp (en çok 5 MB) bellekten gönderilir; gövde bellekte olduğu için `http.Request.bodyBytes` yeter.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class FeedbackApi {
  FeedbackApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 20),
    Duration writeTimeout = const Duration(seconds: 45),
    Duration uploadTimeout = const Duration(seconds: 180),
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout,
       _uploadTimeout = uploadTimeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;
  final Duration _uploadTimeout;

  static const String _transportMessage =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
  static const String _uploadMessage =
      'Dosya yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  /// `POST /app/feedback` (201): kayıt + `uploading` ekler (içerik [uploadAttachment] ile gider).
  Future<FeedbackRecord> create({
    required String token,
    required FeedbackCreateRequest request,
  }) async {
    final response = await _send(
      'POST',
      '/app/feedback',
      token: token,
      body: request.toJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    final record = FeedbackRecord.fromJson(_object(response)['feedback']);
    if (record == null) throw _unexpected(response);
    return record;
  }

  /// `PUT .../attachments/:attId/content`: baytlar `application/octet-stream` olarak gider; başarıda hazır ek döner.
  /// 409 `UPLOAD_ALREADY_COMPLETED` çağıran tarafından BAŞARI sayılır (önceki denemenin yanıtı kaybolmuştu).
  Future<FeedbackAttachment> uploadAttachment({
    required String token,
    required int feedbackId,
    required int attachmentId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw ApiException('Dosya okunamadı. Yeniden seçip tekrar deneyin.');
    }
    final request = http.Request(
      'PUT',
      _uri('/app/feedback/$feedbackId/attachments/$attachmentId/content'),
    )
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Accept': 'application/json',
      })
      ..bodyBytes = bytes;
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(_uploadTimeout);
    } on TimeoutException {
      throw ApiException(_uploadMessage);
    } on Exception {
      throw ApiException(_uploadMessage);
    }
    if (response.statusCode == 200 || response.statusCode == 201) {
      final attachment = FeedbackAttachment.fromJson(_object(response)['attachment']);
      if (attachment == null) throw _unexpected(response);
      return attachment;
    }
    throw _failure(response);
  }

  /// `GET /manager/sites/:siteCode/feedback` (site yöneticisi + süper kullanıcı).
  Future<FeedbackPage> listForSite({
    required String token,
    required int siteCode,
    int? cursor,
    int limit = 30,
  }) async {
    final response = await _send(
      'GET',
      '/manager/sites/$siteCode/feedback',
      token: token,
      query: _pageQuery(cursor: cursor, limit: limit),
      timeout: _readTimeout,
    );
    return FeedbackPage.fromJson(_object(response));
  }

  /// `GET /admin/feedback` (yalnız süper kullanıcı); [siteCode] süzer.
  Future<FeedbackPage> listAll({
    required String token,
    int? siteCode,
    int? cursor,
    int limit = 30,
  }) async {
    final response = await _send(
      'GET',
      '/admin/feedback',
      token: token,
      query: <String, String>{
        ..._pageQuery(cursor: cursor, limit: limit),
        if (siteCode != null) 'site_code': '$siteCode',
      },
      timeout: _readTimeout,
    );
    return FeedbackPage.fromJson(_object(response));
  }

  /// Ek görüntüsü: [siteCode] verilirse yönetici yolu, null ise sahip (`/admin`) yolu.
  Future<Uint8List> downloadAttachment({
    required String token,
    int? siteCode,
    required int feedbackId,
    required int attachmentId,
  }) async {
    final path = siteCode == null
        ? '/admin/feedback/$feedbackId/attachments/$attachmentId/content'
        : '/manager/sites/$siteCode/feedback/$feedbackId/attachments/$attachmentId/content';
    final request = http.Request('GET', _uri(path))
      ..followRedirects = false
      ..headers.addAll(<String, String>{'Authorization': 'Bearer $token'});
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(_uploadTimeout);
    } on TimeoutException {
      throw ApiException('Dosya alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    } on Exception {
      throw ApiException(_transportMessage);
    }
    if (response.statusCode != 200) throw _failure(response);
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    if (!type.startsWith('image/') || response.bodyBytes.isEmpty) {
      throw ApiException('Dosya beklenen biçimde değil. Tekrar deneyin.');
    }
    return response.bodyBytes;
  }

  static Map<String, String> _pageQuery({int? cursor, required int limit}) => <String, String>{
    'limit': '$limit',
    if (cursor != null) 'cursor': '$cursor',
  };

  // --- Taşıma katmanı ---------------------------------------------------------------------------

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
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; birkaç dakika sonra tekrar deneyin.',
      );
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

  ApiException _unexpected(http.Response response) => ApiException(
    'Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin.',
    statusCode: response.statusCode,
  );

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _object(http.Response response) =>
      _tryObject(response.bodyBytes) ?? const <String, dynamic>{};

  static int? _retryAfterSeconds(http.Response response, Map<String, dynamic>? payload) {
    final fromBody = payload?['retry_after_seconds'];
    if (fromBody is num && fromBody > 0) return fromBody.toInt();
    final header = int.tryParse((response.headers['retry-after'] ?? '').trim());
    return header != null && header > 0 ? header : null;
  }

  /// Hata çevirisi: sunucu `{ error, code }` gövdesi Türkçe iletiyle taşınır; JSON olmayan yanıtlar (ara katman) genel iletiye döner.
  ApiException _failure(http.Response response) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);
    if (payload == null) {
      if ((status == 401 || status == 403) && response.bodyBytes.isNotEmpty) {
        return ApiException(
          'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      if (status == 413) {
        return ApiException(
          'Dosya çok büyük. Her dosya en fazla 5 MB olabilir.',
          statusCode: status,
          code: 'BODY_TOO_LARGE',
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
      return ApiException(
        'İşlem tamamlanamadı ($status). Lütfen tekrar deneyin.',
        statusCode: status,
        genericFallback: true,
      );
    }
    final rawCode = payload['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final rawError = payload['error'];
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
    final message = switch (status) {
      429 => _withRetryHint(serverText ?? 'Çok fazla istek gönderildi.', retryAfter),
      >= 500 => serverText ?? 'Sunucu şu anda yanıt veremiyor. Lütfen biraz sonra tekrar deneyin.',
      _ => serverText ?? 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
    };
    return ApiException(
      message,
      statusCode: status,
      code: code,
      retryAfterSeconds: retryAfter,
      payload: payload,
      genericFallback: serverText == null,
    );
  }

  static String _withRetryHint(String message, int? seconds) {
    if (seconds == null) return message;
    if (message.contains('tekrar deneyin')) return message;
    return '$message ${AuthApi.formatWait(seconds)} sonra tekrar deneyin.';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman. Ekranlar bunu kullanır (testlerde sahte kurulur).
class FeedbackService {
  FeedbackService({required this.authService, FeedbackApi? api})
    : api =
          api ??
          debugApiFactory?.call(authService) ??
          FeedbackApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda (HomePage) sahte [FeedbackApi] vermek için.
  @visibleForTesting
  static FeedbackApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final FeedbackApi api;

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

  Future<FeedbackRecord> send(FeedbackCreateRequest request) =>
      _guard((token) => api.create(token: token, request: request));

  Future<FeedbackAttachment> upload({
    required int feedbackId,
    required int attachmentId,
    required Uint8List bytes,
  }) => _guard(
    (token) => api.uploadAttachment(
      token: token,
      feedbackId: feedbackId,
      attachmentId: attachmentId,
      bytes: bytes,
    ),
  );

  Future<FeedbackPage> listForSite(int siteCode, {int? cursor, int limit = 30}) => _guard(
    (token) => api.listForSite(token: token, siteCode: siteCode, cursor: cursor, limit: limit),
  );

  Future<FeedbackPage> listAll({int? siteCode, int? cursor, int limit = 30}) => _guard(
    (token) => api.listAll(token: token, siteCode: siteCode, cursor: cursor, limit: limit),
  );

  Future<Uint8List> download({
    int? siteCode,
    required int feedbackId,
    required int attachmentId,
  }) => _guard(
    (token) => api.downloadAttachment(
      token: token,
      siteCode: siteCode,
      feedbackId: feedbackId,
      attachmentId: attachmentId,
    ),
  );
}
