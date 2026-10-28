// Site yöneticisinin "İşlem kayıtları" ucu (docs/PLATFORM_ISLEM_KAYITLARI.md): `GET /manager/sites/:siteCode/audit-log`.
//
// Yalnız OKUR (kayıt eklemez / değiştirmez). Yanıtta kullanıcı kodu, site kodu, e-posta, telefon, parola / belirteç
// yoktur; bu katman da hiçbirini günlüğe yazmaz.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/site_audit_log.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Sayfa başına kayıt (sunucu varsayılanı).
const int siteAuditPageSize = 50;

/// Takvim gününü sunucunun beklediği `YYYY-AA-GG` metnine çevirir. Saat dilimi dönüşümü YAPILMAZ: kullanıcının seçtiği
/// takvim günüdür, sunucu bunu İstanbul günü sayar.
String siteAuditDayParam(DateTime day) {
  final year = day.year.toString().padLeft(4, '0');
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return '$year-$month-$dayOfMonth';
}

class SiteAuditLogApi {
  SiteAuditLogApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// Bir sitenin işlem kayıtları (`id DESC`). [from] / [to] takvim günüdür, ikisi de dahil; [category] bir
  /// [siteAuditCategories] anahtarı; sonraki sayfa için önceki yanıttaki `next_before_id` [beforeId] olarak verilir.
  Future<SiteAuditPage> list(
    String token,
    int siteCode, {
    DateTime? from,
    DateTime? to,
    String? category,
    int limit = siteAuditPageSize,
    int? beforeId,
  }) async {
    final query = <String, String>{
      if (from != null) 'from': siteAuditDayParam(from),
      if (to != null) 'to': siteAuditDayParam(to),
      if (category != null && category.isNotEmpty) 'category': category,
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
    };
    final payload = await _get('/manager/sites/$siteCode/audit-log', token, query);
    return SiteAuditPage.fromJson(payload);
  }

  Future<Map<String, dynamic>> _get(String path, String token, Map<String, String> query) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request('GET', uri)
      ..headers.addAll(<String, String>{'Authorization': 'Bearer $token', 'Accept': 'application/json'});
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    if (response.statusCode == 200) return _payload(response);
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
    if (response.statusCode == 401) {
      return SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    }
    final retry = payload['retry_after_seconds'];
    return ApiException(
      _message(code, payload['error'], response.statusCode),
      statusCode: response.statusCode,
      code: code,
      retryAfterSeconds: retry is num ? retry.toInt() : null,
      payload: payload,
    );
  }

  static String _message(String? code, Object? serverText, int status) {
    switch (code) {
      case 'FORBIDDEN_ROLE':
        return 'İşlem kayıtlarını yalnızca site yöneticisi görebilir.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'INVALID_DATE_RANGE':
        return 'Başlangıç tarihi bitiş tarihinden sonra olamaz.';
      case 'INVALID_QUERY':
        return 'Filtre geçersiz. Tarihleri ve işlem türünü kontrol edin.';
    }
    if (status == 429) return 'Çok fazla istek. Biraz sonra tekrar deneyin.';
    if (serverText is String && serverText.trim().isNotEmpty && status == 400) {
      return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    }
    final mapped = code == null ? null : AuthApi.messageForErrorCode(code);
    if (mapped != null) return mapped;
    if (serverText is String && serverText.trim().isNotEmpty) {
      return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    }
    return 'İşlem başarısız ($status)';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman; oturum geçersizse oturumu yeniler.
class SiteAuditLogService {
  SiteAuditLogService({required this.authService, SiteAuditLogApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? SiteAuditLogApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [SiteAuditLogApi] vermek için.
  @visibleForTesting
  static SiteAuditLogApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final SiteAuditLogApi api;

  Future<SiteAuditPage> list(
    int siteCode, {
    DateTime? from,
    DateTime? to,
    String? category,
    int limit = siteAuditPageSize,
    int? beforeId,
  }) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await api.list(token, siteCode, from: from, to: to, category: category, limit: limit, beforeId: beforeId);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }
}
