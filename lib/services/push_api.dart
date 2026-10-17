// Telefon bildirimi uçları (Platform Faz 3b-B, docs/PLATFORM_BELGELER.md B3).
//
// Yalnız HTTP katmanı ([AccountApi] kalıbı): belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a
// çevirir. Kurallar:
// - Mutasyonlar (PUT/DELETE/POST) ASLA otomatik yeniden denenmez.
// - 401 yetkili uçta "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive
//   portal) geçici ağ hatasıdır.
// - FCM kayıt jetonu, oturum belirteci ve yanıt gövdeleri günlüğe YAZILMAZ; jeton yalnız `PUT /app/push/devices`
//   gövdesinde gider, hiçbir yanıtta dönmez.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

/// `PUT /app/push/devices` sonucu.
typedef PushRegistration = ({int? deviceId, bool pushAvailable});

class PushApi {
  PushApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 20),
    Duration writeTimeout = const Duration(seconds: 20),
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;

  /// Sunucunun kabul ettiği alan sınırları (B2): install_id 16–64, jeton 20–4096, sürüm ≤ 32.
  static const int maxAppVersionLength = 32;

  static final RegExp _safeVersion = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,31}$');

  /// Sunucunun sürüm desenine uyan (≤ 32 karakter, harf/rakam ve `.+_-`) sürüm; uymuyorsa null ve alan
  /// GÖNDERİLMEZ (isteğe bağlı alan yüzünden cihaz kaydı reddedilmesin).
  static String? safeAppVersion(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final cut = value.length > maxAppVersionLength ? value.substring(0, maxAppVersionLength) : value;
    return _safeVersion.hasMatch(cut) ? cut : null;
  }

  // --- Cihaz kaydı -----------------------------------------------------------------------------

  /// `PUT /app/push/devices`: kayıt / tazeleme (aynı kurulum için UPSERT). [notificationsEnabled] işletim
  /// sistemi izninin GÜNCEL hâlidir.
  Future<PushRegistration> registerDevice({
    required String token,
    required String installId,
    required String platform,
    required String fcmToken,
    String? appVersion,
    required bool notificationsEnabled,
  }) async {
    final response = await _send(
      'PUT',
      '/app/push/devices',
      token: token,
      body: <String, dynamic>{
        'install_id': installId,
        'platform': platform,
        'token': fcmToken,
        'app_version': ?safeAppVersion(appVersion),
        'notifications_enabled': notificationsEnabled,
      },
      timeout: _writeTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Cihaz kaydedilemedi, tekrar deneyin.',
    );
    final payload = _objectOrEmpty(response);
    final id = payload['device_id'];
    return (
      deviceId: id is int ? id : (id is String ? int.tryParse(id) : null),
      pushAvailable: payload['push_available'] == true,
    );
  }

  /// `DELETE /app/push/devices/:installId` (idempotent; yalnız çağıranın satırı).
  Future<void> deleteDevice({
    required String token,
    required String installId,
    Duration? timeout,
  }) async {
    await _send(
      'DELETE',
      '/app/push/devices/${Uri.encodeComponent(installId)}',
      token: token,
      timeout: timeout ?? _writeTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Cihaz kaldırılmış olabilir; listeyi yenileyip kontrol edin.',
    );
  }

  /// `GET /app/push/devices`: kullanıcının cihazları (jeton YOK).
  Future<List<PushDevice>> listDevices({required String token}) async {
    final response = await _send(
      'GET',
      '/app/push/devices',
      token: token,
      timeout: _readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return PushDevice.listFromJson(_object(response));
  }

  /// `POST /app/push/test`: çağıranın cihazlarına genel "Test bildirimi" (günde en çok 5).
  Future<PushTestResult> sendTest({required String token}) async {
    final response = await _send(
      'POST',
      '/app/push/test',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Test bildirimi gönderilmiş olabilir; telefonunuzu kontrol edin.',
      rateLimitMessage: 'Bugün için test bildirimi sınırına ulaşıldı (günde en çok 5).',
    );
    return PushTestResult.fromJson(_object(response));
  }

  // --- Tercihler -------------------------------------------------------------------------------

  /// `GET /app/notification-preferences` (telefon bildirimi alanları).
  Future<PushPreferences> getPreferences({required String token}) async {
    final response = await _send(
      'GET',
      '/app/notification-preferences',
      token: token,
      timeout: _readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return PushPreferences.fromJson(_object(response));
  }

  /// `PUT /app/notification-preferences` KISMİ güncelleme (yalnız [patch] anahtarları). Yanıtta alan yoksa
  /// istenen değer geçerli sayılır ([current] + [patch]).
  Future<PushPreferences> updatePreferences({
    required String token,
    required PushPreferencesPatch patch,
    required PushPreferences current,
  }) async {
    if (patch.isEmpty) {
      throw ArgumentError.value(patch, 'patch', 'Değişiklik yok');
    }
    final response = await _send(
      'PUT',
      '/app/notification-preferences',
      token: token,
      body: patch.toJson(),
      timeout: _writeTimeout,
      timeoutMessage:
          'Sunucu zaman aşımına uğradı. Tercih kaydedilmiş olabilir; sayfayı yenileyip kontrol edin.',
    );
    return PushPreferences.fromJson(_objectOrEmpty(response), fallback: patch.applyTo(current));
  }

  // --- Taşıma katmanı --------------------------------------------------------------------------

  Future<http.Response> _send(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    required Duration timeout,
    required String timeoutMessage,
    String? rateLimitMessage,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      // İstek bu satırda (eşzamanlı olarak) yola çıkar: çıkışta cihaz kaydını silen çağrı, oturum belirteci
      // yerelde silinmeden önce gönderilmiş olur (bkz. PushService).
      response = await _exchange(request).timeout(timeout);
    } on TimeoutException {
      throw ApiException(timeoutMessage);
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw ApiException(_transportMessage);
    } on Exception catch (_) {
      // SocketException, TlsException, ... (ayrıntı gösterilmez). Programlama hataları (Error) yakalanmaz.
      throw ApiException(_transportMessage);
    }
    // Sözleşme başarılı yanıtlar için YALNIZ 200 verir.
    if (response.statusCode == 200) return response;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw ApiException(
        'Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    throw _failure(response, rateLimitMessage: rateLimitMessage);
  }

  Future<http.Response> _exchange(http.Request request) async {
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  static const String _transportMessage =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  // --- Hata çevirisi ---------------------------------------------------------------------------

  ApiException _failure(http.Response response, {String? rateLimitMessage}) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
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
          _withRetryHint(rateLimitMessage ?? 'Çok fazla istek gönderildi.', retryAfter),
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
            : (code == 'ACCOUNT_DELETED'
                  ? 'Bu hesap silinmiş.'
                  : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }

    final mapped = pushErrorMessage(code, retryAfterSeconds: retryAfter, payload: body);
    // 429: bu uca özgü sınır metni sunucu metninden önce gelir (sunucu genel "çok fazla istek" yazabilir).
    final limited = status == 429 && mapped == null ? rateLimitMessage : null;
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    final fallback = mapped == null && limited == null && serverText == null && generic == null;
    var message = mapped ?? limited ?? serverText ?? generic ?? 'İşlem başarısız ($status)';
    if (status == 429 && mapped == null) message = _withRetryHint(message, retryAfter);
    if (status >= 500 && code != 'PUSH_UNAVAILABLE') {
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

  /// Push uçlarına özgü sunucu kodları için Türkçe metin; bilinmiyorsa [AuthApi.messageForErrorCode].
  static String? pushErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
  }) {
    if (code == null) return null;
    switch (code) {
      case 'PUSH_UNAVAILABLE':
        return pushUnavailableMessage;
      case 'PUSH_DEVICE_NOT_FOUND':
        return 'Cihaz bulunamadı. Listeyi yenileyip tekrar deneyin.';
      default:
        return AuthApi.messageForErrorCode(
          code,
          retryAfterSeconds: retryAfterSeconds,
          payload: payload,
        );
    }
  }

  /// `503 PUSH_UNAVAILABLE` metni (B8).
  static const String pushUnavailableMessage = 'Telefon bildirimi şu an kullanılamıyor.';

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

  // --- Gövde çözümleme -------------------------------------------------------------------------

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map<String, dynamic> ? raw : (raw is Map ? Map<String, dynamic>.from(raw) : null);
    } on FormatException {
      return null;
    }
  }

  /// Başarılı yanıt gövdesi JSON nesnesi olmak ZORUNDA.
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

  /// Gövdesi boş olabilen başarılı yanıt (PUT / DELETE): boşsa boş harita.
  static Map<String, dynamic> _objectOrEmpty(http.Response response) =>
      _tryObject(response.bodyBytes) ?? const <String, dynamic>{};
}
