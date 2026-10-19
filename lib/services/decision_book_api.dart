// Karar Defteri (`decision_book`) uçları.
//
// [DecisionBookApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [DecisionBookService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (SurveyApi ile aynı): mutasyonlar ASLA otomatik yeniden denenmez; 401 yetkili uçlarda "oturum bitti"dir;
// JSON olmayan 401/403 geçici ağ hatasıdır; karar metni, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ. Yanıtlar
// savunmacı okunur: `{decision: {...}}` sarmalı ya da doğrudan nesne; sayfa imleci `next_before_id` ya da
// `next_cursor`.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class DecisionBookApi {
  DecisionBookApi({
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
      '/manager/sites/$siteCode/decisions${tail.isEmpty ? '' : '/$tail'}';

  // --- Yönetim ------------------------------------------------------------------------------

  /// `GET /manager/sites/:siteCode/decisions?year=&status=&meeting_type=&q=&before_id|cursor=&limit=`.
  Future<DecisionPage> listManaged({
    required String token,
    required int siteCode,
    int? year,
    String status = 'all',
    String? meetingType,
    String? query,
    DecisionCursor? cursor,
    int limit = 30,
  }) async {
    final q = (query ?? '').trim();
    final response = await _send(
      'GET',
      _managerPath(siteCode),
      token: token,
      query: <String, String>{
        'year': ?year?.toString(),
        'status': status,
        if (meetingType != null && meetingType.isNotEmpty) 'meeting_type': meetingType,
        if (q.isNotEmpty) 'q': q,
        ...?cursor?.query,
        'limit': '$limit',
      },
      timeout: _readTimeout,
    );
    return DecisionPage.fromJson(_object(response));
  }

  /// `GET .../decisions/:id` -> `{decision}`.
  Future<Decision> getManaged({required String token, required int siteCode, required int id}) async {
    final response = await _send('GET', _managerPath(siteCode, '$id'), token: token, timeout: _readTimeout);
    return _decision(response);
  }

  /// `POST .../decisions` (201) -> `{decision}`.
  Future<Decision> create({required String token, required int siteCode, required DecisionInput input}) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode),
      token: token,
      body: input.toJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _decision(response);
  }

  /// `PATCH .../decisions/:id` (yalnız taslak): yalnız [fields] gönderilir.
  Future<Decision> update({
    required String token,
    required int siteCode,
    required int id,
    required Map<String, Object?> fields,
  }) async {
    final response = await _send(
      'PATCH',
      _managerPath(siteCode, '$id'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      timeout: _writeTimeout,
    );
    return _decision(response);
  }

  /// `DELETE .../decisions/:id` (yalnız taslak) -> `{deleted: true}` (204 boş gövde de kabul).
  Future<void> delete({required String token, required int siteCode, required int id}) async {
    final response = await _send(
      'DELETE',
      _managerPath(siteCode, '$id'),
      token: token,
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 204},
    );
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return;
    final json = _object(response);
    if (json['deleted'] == false || json['ok'] == false) throw _unexpected(response);
  }

  /// `POST .../decisions/:id/finalize` -> `{decision}` (numara alır, artık değişmez).
  Future<Decision> finalize({required String token, required int siteCode, required int id}) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode, '$id/finalize'),
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _decision(response);
  }

  // --- Sakin --------------------------------------------------------------------------------

  /// `GET /app/decisions?site_code=&year=&before_id|cursor=&limit=`.
  Future<DecisionPage> listMine({
    required String token,
    int? siteCode,
    int? year,
    DecisionCursor? cursor,
    int limit = 30,
  }) async {
    final response = await _send(
      'GET',
      '/app/decisions',
      token: token,
      query: <String, String>{
        'site_code': ?siteCode?.toString(),
        'year': ?year?.toString(),
        ...?cursor?.query,
        'limit': '$limit',
      },
      timeout: _readTimeout,
    );
    return DecisionPage.fromJson(_object(response), resident: true);
  }

  /// `GET /app/decisions/:id` -> `{decision}`.
  Future<Decision> getMine({required String token, required int id}) async {
    final response = await _send('GET', '/app/decisions/$id', token: token, timeout: _readTimeout);
    return _decision(response, resident: true);
  }

  // --- Gövde yardımcıları -------------------------------------------------------------------

  Decision _decision(http.Response response, {bool resident = false}) {
    final decision = Decision.fromResponse(_object(response), resident: resident);
    if (decision == null) throw _unexpected(response);
    return decision;
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
        return ApiException(decisionErrorMessage('BODY_TOO_LARGE')!, statusCode: 413, code: 'BODY_TOO_LARGE');
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
    final rawField = body['field'];
    final field = rawField is String && rawField.trim().isNotEmpty ? rawField.trim() : null;

    if (status == 401) {
      return SessionExpiredException(
        code == 'TOKEN_REVOKED'
            ? 'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.'
            : (code == 'ACCOUNT_DELETED' ? 'Bu hesap silinmiş.' : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }

    final mapped = decisionErrorMessage(code, field: field, retryAfterSeconds: retryAfter, serverText: serverText);
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

  /// `INVALID_FIELD` yanıtındaki `field` adlarının ekrandaki karşılığı.
  static const Map<String, String> fieldLabels = <String, String>{
    'meeting_type': 'Toplantı türü',
    'meeting_date': 'Toplantı tarihi',
    'title': 'Başlık',
    'body': 'Karar metni',
    'attendees': 'Katılanlar',
    'vote_result': 'Oylama sonucu',
    'votes_for': 'Kabul oyu',
    'votes_against': 'Ret oyu',
    'votes_abstain': 'Çekimser oy',
    'visibility': 'Görünürlük',
    'supersedes_id': 'Değiştirilen karar',
    'year': 'Yıl',
    'status': 'Durum',
    'q': 'Arama',
  };

  /// Karar Defteri hata kodları için düz Türkçe metin; bilinmiyorsa genel kodlar ([AuthApi.messageForErrorCode]) ya
  /// da null (sunucunun kendi `error` metni kullanılır).
  static String? decisionErrorMessage(String? code, {String? field, int? retryAfterSeconds, String? serverText}) {
    if (code == null) return null;
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Karar Defteri bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'DECISION_NOT_FOUND':
        return 'Karar bulunamadı ya da erişiminiz yok. Listeyi yenileyin.';
      case 'DECISION_FINAL':
        return 'Bu karar kesinleşmiş; değiştirilemez ya da silinemez. Düzeltme gerekirse yeni bir karar yazın.';
      case 'DECISION_LIMIT_REACHED':
        return serverText ?? 'Bu sitede tutulabilecek en çok karar sayısına ulaşıldı.';
      case 'INVALID_FIELD':
        final label = field == null ? null : fieldLabels[field];
        if (serverText != null) return serverText;
        return label == null
            ? 'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.'
            : '$label geçersiz. Kontrol edip tekrar deneyin.';
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

/// `INVALID_FIELD` hatasının alan adı (yoksa null): form bu alanın altında hata gösterir.
String? decisionInvalidField(Object error) {
  if (error is! ApiException || error.code != 'INVALID_FIELD') return null;
  final field = error.payload?['field'];
  return field is String && field.trim().isNotEmpty ? field.trim() : null;
}

/// Oturum belirtecini [AuthService]'ten alan ve oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar bunu
/// kullanır (testlerde sahte [DecisionBookService] kurulur).
class DecisionBookService {
  DecisionBookService({required this.authService, DecisionBookApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? DecisionBookApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [DecisionBookApi] vermek için.
  @visibleForTesting
  static DecisionBookApi Function(AuthService authService)? debugApiFactory;

  /// PDF için toplanan en çok sayfa (sayfa başına [pdfPageSize] karar).
  static const int pdfMaxPages = 50;
  static const int pdfPageSize = 100;

  final AuthService authService;
  final DecisionBookApi api;

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

  Future<DecisionPage> listManaged(
    int siteCode, {
    int? year,
    String status = 'all',
    String? meetingType,
    String? query,
    DecisionCursor? cursor,
    int limit = 30,
  }) => _guard(
    (token) => api.listManaged(
      token: token,
      siteCode: siteCode,
      year: year,
      status: status,
      meetingType: meetingType,
      query: query,
      cursor: cursor,
      limit: limit,
    ),
  );

  Future<Decision> getManaged(int siteCode, int id) =>
      _guard((token) => api.getManaged(token: token, siteCode: siteCode, id: id));

  Future<Decision> create(int siteCode, DecisionInput input) =>
      _guard((token) => api.create(token: token, siteCode: siteCode, input: input));

  Future<Decision> update(int siteCode, int id, Map<String, Object?> fields) =>
      _guard((token) => api.update(token: token, siteCode: siteCode, id: id, fields: fields));

  Future<void> delete(int siteCode, int id) => _guard((token) => api.delete(token: token, siteCode: siteCode, id: id));

  Future<Decision> finalize(int siteCode, int id) =>
      _guard((token) => api.finalize(token: token, siteCode: siteCode, id: id));

  /// [year] yılının TÜM kesin kararları (PDF için): sayfalar sırayla toplanır (en çok [pdfMaxPages] sayfa), metni
  /// listede gelmeyen kayıt ayrıntıdan tamamlanır. Karar numarasına göre sıralı döner.
  Future<List<Decision>> collectFinalForYear(int siteCode, int year) async {
    final byId = <int, Decision>{};
    final seen = <int>{};
    DecisionCursor? cursor;
    for (var page = 0; page < pdfMaxPages; page++) {
      final result = await listManaged(siteCode, year: year, status: 'kesin', cursor: cursor, limit: pdfPageSize);
      var fresh = 0;
      for (final item in result.items) {
        if (seen.add(item.id)) fresh++;
        // Sunucu süzgeci yok sayarsa bile yalnız o yılın KESİN kararları alınır.
        if (item.isFinal && item.effectiveYear == year) byId.putIfAbsent(item.id, () => item);
      }
      final next = result.next;
      // Son sayfa, aynı imleç ya da yalnız tekrar eden kayıtlar: sunucu tutarsız, dur (sonsuz döngü olmasın).
      if (next == null || next == cursor || fresh == 0) break;
      cursor = next;
    }
    final out = <Decision>[];
    for (final item in byId.values) {
      out.add(item.body.isEmpty ? await getManaged(siteCode, item.id) : item);
    }
    out.sort(compareDecisionsByNumber);
    return out;
  }

  // --- Sakin ---

  Future<DecisionPage> listMine({int? siteCode, int? year, DecisionCursor? cursor, int limit = 30}) =>
      _guard((token) => api.listMine(token: token, siteCode: siteCode, year: year, cursor: cursor, limit: limit));

  Future<Decision> getMine(int id) => _guard((token) => api.getMine(token: token, id: id));
}
