// Kurallar tablosu (G11; docs/PLATFORM_KURALLAR.md) uçları.
//
// [PlatformRulesApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [PlatformRulesService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (DecisionBookApi ile aynı): yazma ASLA otomatik yeniden denenmez; 401 yetkili uçlarda "oturum bitti"dir; JSON olmayan 401/403 geçici ağ
// hatasıdır; belirteç ve yanıt gövdeleri günlüğe YAZILMAZ. `400 VALIDATION_FAILED` yanıtındaki `fields` (kural anahtarı -> Türkçe metin)
// [ruleFieldErrors] ile okunur; iletide ilk kuralın metni gösterilir.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/platform_rule.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class PlatformRulesApi {
  PlatformRulesApi({
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

  /// `GET /admin/rules[?site_code=]` (yalnız süper kullanıcı): platform ya da site görünümü, değiştirenin adı dahil.
  Future<PlatformRulesView> listAdmin({required String token, int? siteCode}) async {
    final response = await _send(
      'GET',
      '/admin/rules',
      token: token,
      query: <String, String>{'site_code': ?siteCode?.toString()},
      timeout: _readTimeout,
    );
    return PlatformRulesView.fromJson(_object(response));
  }

  /// `GET /manager/sites/:siteCode/rules` (site yöneticisi kendi sitesi): salt okunur.
  Future<PlatformRulesView> listForSite({required String token, required int siteCode}) async {
    final response = await _send('GET', '/manager/sites/$siteCode/rules', token: token, timeout: _readTimeout);
    return PlatformRulesView.fromJson(_object(response));
  }

  /// `PUT /admin/rules`: kısmi yazma. Yanıt güncel görünüm + `changed`.
  Future<PlatformRulesView> update({
    required String token,
    required List<PlatformRuleChange> changes,
    int? siteCode,
    String? validFrom,
    String? note,
  }) async {
    final trimmedNote = note?.trim() ?? '';
    final response = await _send(
      'PUT',
      '/admin/rules',
      token: token,
      body: <String, dynamic>{
        'site_code': ?siteCode,
        'valid_from': ?validFrom,
        if (trimmedNote.isNotEmpty) 'note': trimmedNote,
        'changes': <Map<String, Object?>>[for (final change in changes) change.toJson()],
      },
      timeout: _writeTimeout,
    );
    return PlatformRulesView.fromJson(_object(response));
  }

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
            : 'Sunucu yanıt vermedi. Değişiklik kaydedilmiş olabilir; kuralları yenileyip kontrol edin.',
      );
    } on http.ClientException {
      throw ApiException(_transportMessage);
    } on Exception {
      throw ApiException(_transportMessage);
    }
    if (response.statusCode == 200) return response;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw ApiException('Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin.', statusCode: response.statusCode);
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
      if ((status == 401 || status == 403) && !empty) {
        return ApiException(
          'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      if (status >= 500) {
        return ApiException('Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin.', statusCode: status);
      }
      if (status == 429) {
        return ApiException(_withRetryHint('Çok fazla istek gönderildi.', retryAfter), statusCode: status, retryAfterSeconds: retryAfter);
      }
      if (!empty) {
        return ApiException('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.', statusCode: status, fromIntermediary: true);
      }
    }

    final body = payload ?? const <String, dynamic>{};
    final rawCode = body['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final rawError = body['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty ? AuthApi.sanitizeServerMessage(rawError.trim()) : null;

    if (status == 401) {
      return SessionExpiredException(
        code == 'TOKEN_REVOKED'
            ? 'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.'
            : (code == 'ACCOUNT_DELETED' ? 'Bu hesap silinmiş.' : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }

    final fields = _fieldsOf(body);
    final mapped = code == 'VALIDATION_FAILED' && fields.isNotEmpty
        ? AuthApi.sanitizeServerMessage(fields.values.first)
        : rulesErrorMessage(code, retryAfterSeconds: retryAfter, serverText: serverText);
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    final fallback = mapped == null && serverText == null && generic == null;
    var message = mapped ?? serverText ?? generic ?? 'İşlem başarısız ($status)';
    if (status == 429 && mapped == null) message = _withRetryHint(message, retryAfter);
    if (status >= 500) {
      final errorId = body['errorId'] ?? body['error_id'];
      if (errorId is String && errorId.isNotEmpty) message = '$message (Hata kodu: $errorId)';
    }
    return ApiException(message, statusCode: status, code: code, retryAfterSeconds: retryAfter, payload: body, genericFallback: fallback);
  }

  /// Kurallar uçlarının hata kodları için düz Türkçe metin; bilinmiyorsa genel kodlar ya da null (sunucunun metni kullanılır).
  static String? rulesErrorMessage(String? code, {int? retryAfterSeconds, String? serverText}) {
    if (code == null) return null;
    switch (code) {
      case 'FORBIDDEN_SITE':
        return 'Bu sitenin kurallarını görme yetkiniz yok.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'INVALID_QUERY':
        return 'Site seçimi geçersiz. Ekranı yenileyip tekrar deneyin.';
      case 'VALIDATION_FAILED':
        return serverText ?? 'Girilen değer geçersiz. Kontrol edip tekrar deneyin.';
      case 'INVALID_BODY':
        return serverText ?? 'Girilen bilgiler geçersiz. Kontrol edip tekrar deneyin.';
    }
    return AuthApi.messageForErrorCode(code, retryAfterSeconds: retryAfterSeconds);
  }

  static Map<String, String> _fieldsOf(Map<String, dynamic> body) {
    final raw = body['fields'];
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.value is String && (entry.value as String).trim().isNotEmpty) entry.key.toString(): (entry.value as String).trim(),
    };
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

/// `400 VALIDATION_FAILED` yanıtındaki kural hataları (kural anahtarı -> Türkçe metin); başka hata için boş.
Map<String, String> ruleFieldErrors(Object error) {
  if (error is! ApiException || error.code != 'VALIDATION_FAILED') return const <String, String>{};
  final raw = error.payload?['fields'];
  if (raw is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in raw.entries)
      if (entry.value is String && (entry.value as String).trim().isNotEmpty) entry.key.toString(): (entry.value as String).trim(),
  };
}

/// Oturum belirtecini [AuthService]'ten alan ve oturum hatalarını merkezi çıkışa bağlayan katman (testlerde sahte [PlatformRulesApi] verilir).
class PlatformRulesService {
  PlatformRulesService({required this.authService, PlatformRulesApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? PlatformRulesApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [PlatformRulesApi] vermek için.
  @visibleForTesting
  static PlatformRulesApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final PlatformRulesApi api;

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

  Future<PlatformRulesView> listAdmin({int? siteCode}) => _guard((token) => api.listAdmin(token: token, siteCode: siteCode));

  Future<PlatformRulesView> listForSite(int siteCode) => _guard((token) => api.listForSite(token: token, siteCode: siteCode));

  Future<PlatformRulesView> update({required List<PlatformRuleChange> changes, int? siteCode, String? validFrom, String? note}) =>
      _guard((token) => api.update(token: token, changes: changes, siteCode: siteCode, validFrom: validFrom, note: note));
}
