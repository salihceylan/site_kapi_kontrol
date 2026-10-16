import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/config/app_config.dart' as build_config;
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

/// Yasal belge ve onay uçları (docs/PLATFORM_SATISA_HAZIRLIK.md §1.4):
///
/// - `GET /public/legal-documents` ve `GET /public/legal-documents/:id` (kimliksiz),
/// - `GET /me/consents` ve `POST /me/consents` (Bearer belirteci gerekir).
///
/// Her hata [ApiException] olarak fırlar (Türkçe iletiyle); ağ/zaman aşımı hatalarında `statusCode`
/// null'dır. Hiçbir yöntem sessizce "boş" sonuç döndürmez: çağıran hata ile boş listeyi ayırt eder.
/// Yazma (POST) tekrar denenmez; okumalar tek denemedir (kullanıcı "Yeniden dene" der).
class LegalApi {
  LegalApi({
    String? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 12),
  }) : _baseUrl = (baseUrl ?? build_config.apiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
       _client = client,
       _timeout = timeout;

  /// Varsayılan (derleme zamanı adresine bağlı) örnek. Ekranlar `widget.legalApi ?? LegalApi.defaultInstance()`
  /// kullanır; testler [debugDefaultFactory] ile sahte yanıtlı bir örnek verir.
  factory LegalApi.defaultInstance() => debugDefaultFactory?.call() ?? LegalApi();

  /// Yalnız testler: [LegalApi.defaultInstance] yerine döndürülecek örneği üretir (test sonunda null'a çekin).
  @visibleForTesting
  static LegalApi Function()? debugDefaultFactory;

  final String _baseUrl;
  final http.Client? _client;
  final Duration _timeout;

  /// Belge kimliği için güvenli yol parçası: yalnız `[a-z0-9_-]` (yol enjeksiyonu yok).
  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  /// Belgenin tam metninin web sayfası (`GET /legal/:id`, sunucunun sade HTML sayfası). Yalnız https ve geçerli
  /// kimlikte döner (aksi hâlde null): dış uygulamada açılabilecek tek adres budur.
  Uri? webPageUri(String id) {
    if (!_safeId.hasMatch(id)) return null;
    final uri = Uri.tryParse('$_baseUrl/legal/$id');
    return (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) ? uri : null;
  }

  /// Yayımlanmış belgelerin özeti (sunucu sırasıyla).
  Future<List<LegalDocumentSummary>> listDocuments() async {
    final response = await _send('GET', '/public/legal-documents');
    final payload = _decode(response);
    _ensure(response, payload, 200);
    // `documents` yoksa yanıt anlaşılamamıştır: "belge yok" DEĞİL, hatadır (sahte onay/boş liste yok).
    if (payload['documents'] is! List) throw _unreadable(response.statusCode);
    return parseLegalDocumentList(payload['documents']);
  }

  /// Tek belge (metin dahil). Geçersiz kimlik ağa çıkmadan "bulunamadı" ([ApiException], 404) ile reddedilir.
  Future<LegalDocument> getDocument(String id) async {
    if (!_safeId.hasMatch(id)) {
      throw ApiException('Belge bulunamadı.', statusCode: 404);
    }
    final response = await _send('GET', '/public/legal-documents/$id');
    final payload = _decode(response);
    _ensure(response, payload, 200);
    final document = LegalDocument.tryParse(payload);
    if (document == null) throw _unreadable(response.statusCode);
    return document;
  }

  /// Oturum açmış kullanıcının onayları ve onay bekleyen belgeleri.
  Future<MyConsents> getMyConsents({required String token}) async {
    final response = await _send('GET', '/me/consents', token: token);
    final payload = _decode(response);
    _ensure(response, payload, 200);
    // `pending` yoksa "bekleyen yok" varsayılmaz (kapı yanlışlıkla açılmasın): hata sayılır.
    if (payload['pending'] is! List) throw _unreadable(response.statusCode);
    return MyConsents.fromJson(payload);
  }

  /// Belgeleri onaylar. Sürüm güncel değilse `409 CONSENT_VERSION_STALE` ([ApiException.code]); diğer hata
  /// kodları: 400 `DOCUMENT_NOT_ACCEPTABLE` / `INVALID_ACCEPTED_DOCUMENTS`, 409 `DOCUMENT_INCOMPLETE`.
  Future<ConsentAcceptResult> acceptDocuments({
    required String token,
    required List<AcceptedDocument> documents,
  }) async {
    if (documents.isEmpty) {
      throw ArgumentError.value(documents, 'documents', 'Onaylanacak belge yok');
    }
    final response = await _send(
      'POST',
      '/me/consents',
      token: token,
      body: <String, dynamic>{
        'documents': <Map<String, dynamic>>[for (final d in documents) d.toJson()],
      },
    );
    final payload = _decode(response);
    _ensure(response, payload, 200);
    return ConsentAcceptResult.fromJson(payload);
  }

  static ApiException _unreadable(int status) => ApiException(
    'Sunucu yanıtı anlaşılamadı. Biraz sonra tekrar deneyin.',
    statusCode: status,
  );

  Future<http.Response> _send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (method != 'GET') 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final future = method == 'GET'
          ? client.get(uri, headers: headers)
          : client.post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}));
      return await future.timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
        method == 'GET'
            ? 'Sunucu yanıt vermedi. Biraz sonra tekrar deneyin.'
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; durumu kontrol edip tekrar deneyin.',
      );
    } on http.ClientException {
      throw ApiException(
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Gövdeyi sözlük olarak çözer; JSON olmayan gövdede boş sözlük döner (durum kodu ayrıca denetlenir).
  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final raw = jsonDecode(text);
      if (raw is Map) return raw.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      // Aşağıda durum koduna göre sınıflandırılır.
    }
    return <String, dynamic>{};
  }

  void _ensure(http.Response response, Map<String, dynamic> payload, int expected) {
    final status = response.statusCode;
    if (status == expected) {
      // 200 ama gövde JSON değil (captive portal / proxy sayfası): belge yok demek DEĞİL, hatadır.
      if (payload.isEmpty && !_looksLikeEmptyJson(response)) {
        throw ApiException(
          'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      return;
    }
    final rawError = payload['error'];
    final errorText = rawError is String && rawError.trim().isNotEmpty
        ? AuthApi.sanitizeServerMessage(rawError.trim())
        : null;
    final rawCode = payload['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final retryAfter = _retryAfter(response, payload);

    if ((status == 401 || status == 403) && payload.isEmpty && response.body.trim().isNotEmpty) {
      // JSON olmayan 401/403: araya giren katman; oturum sonu sayılmaz.
      throw ApiException(
        'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        statusCode: status,
        fromIntermediary: true,
      );
    }

    String? mapped = AuthApi.messageForErrorCode(
      code,
      retryAfterSeconds: retryAfter,
      payload: payload,
    );
    if (code == 'CONSENT_VERSION_STALE') mapped = LegalMessages.consentVersionStale;
    if (code == 'CONSENT_REQUIRED') mapped = LegalMessages.consentRequired;
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    var message = mapped ?? errorText ?? generic ?? _statusFallback(status);
    if (status >= 500) {
      final errorId = payload['errorId'] ?? payload['error_id'];
      if (errorId is String && errorId.isNotEmpty) message = '$message (Hata kodu: $errorId)';
    }
    throw ApiException(
      message,
      statusCode: status,
      code: code,
      retryAfterSeconds: retryAfter,
      payload: payload.isEmpty ? null : payload,
      genericFallback: mapped == null && errorText == null && generic == null,
    );
  }

  static bool _looksLikeEmptyJson(http.Response response) {
    final text = response.body.trim();
    return text == '{}';
  }

  static String _statusFallback(int status) {
    if (status == 404) return 'Belge bulunamadı.';
    if (status == 502 || status == 503 || status == 504) {
      return 'Sunucu geçici olarak yanıt vermiyor ($status). Lütfen biraz sonra tekrar deneyin.';
    }
    if (status >= 500) {
      return 'Sunucuda beklenmeyen bir hata oluştu ($status). Lütfen biraz sonra tekrar deneyin.';
    }
    return 'İşlem başarısız ($status).';
  }

  static int? _retryAfter(http.Response response, Map<String, dynamic> payload) {
    final fromBody = payload['retry_after_seconds'] ?? payload['retryAfterSeconds'];
    if (fromBody is num && fromBody > 0) return fromBody.ceil();
    final header = response.headers['retry-after'];
    if (header != null) {
      final parsed = int.tryParse(header.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }
}
