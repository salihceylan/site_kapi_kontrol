// Toplu yükleme ve dışa aktarma uçları (docs/PLATFORM_TOPLU_ISLEMLER.md "Uçlar").
//
// [BulkApi]: yalnız HTTP katmanı (belirteci çağıran verir; hata gövdesini Türkçe [ApiException]'a çevirir).
// [BulkService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi doğrulamaya bağlar.
//
// Kurallar (AuthApi / AccountApi ile aynı):
// - Mutasyonlar (önizleme ve onay) ASLA otomatik yeniden denenmez; onay `idempotency_key` ile güvenle elle
//   yeniden denenir.
// - 401 yetkili uçlarda "oturum bitti"dir; JSON olmayan 401/403 (proxy / captive portal) geçici ağ hatasıdır.
// - Satır verisi (kişisel veri) ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/finance_opening.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Sözleşmedeki hata kodları için kısa, bağlama uygun Türkçe metinler (hepsi < 140 karakter, `_` yok).
String? bulkErrorMessage(String? code) {
  switch (code) {
    case 'PREVIEW_STALE':
      return 'Veriler değişti. Önizleme yenilendi, tekrar inceleyin.';
    case 'IMPORT_HAS_ERRORS':
      return 'Hatalı satırlar var. Düzeltip yeniden yükleyin.';
    case 'IMPORT_TOO_MANY_ROWS':
      return 'Bir seferde en çok 5.000 satır yüklenebilir.';
    case 'IMPORT_EMPTY':
      return 'Yüklenecek satır bulunamadı.';
    case 'IMPORT_IN_PROGRESS':
      return 'Bu site için başka bir yükleme sürüyor.';
    case 'SITE_BUSY':
      return 'Site kayıtları şu an meşgul, biraz sonra deneyin.';
    case 'IMPORT_SPEC_MISMATCH':
      return 'Uygulamayı güncelleyin.';
    case 'ACK_REQUIRED':
      return 'Devam etmek için onay kutusunu işaretleyin.';
    case 'EXPORT_TOO_LARGE':
      return 'Çok fazla kayıt var. Süzgeçle daraltın.';
    case 'IMPORT_DISABLED':
      return 'Toplu işlemler geçici olarak kapalı.';
    case 'IMPORT_KIND_NOT_FOUND':
      return 'Bu yükleme türü bulunamadı.';
    // Mevcut eşleme "daire hesaplarını kontrol edin" der (mali akış); yükleme bağlamında yanıltıcı olurdu.
    case 'IDEMPOTENCY_CONFLICT':
      return 'Bu yükleme farklı bilgilerle daha önce gönderilmiş. Dosyayı yeniden seçip yükleyin.';
    case 'FORBIDDEN_SITE':
      return 'Bu site için yetkiniz yok.';
    case 'TOTAL_MISMATCH':
      return 'Toplam tutar değişti. Önizleme yenilendi, tekrar inceleyin.';
    case 'OPENING_ALREADY_REVERTED':
      return 'Bu devir yüklemesi zaten geri alınmış.';
    case 'OPENING_CHANGED':
      return 'Devir kayıtları değişti. Ayrıntıyı yenileyip tekrar inceleyin.';
    case 'OPENING_RUN_NOT_FOUND':
      return 'Devir yüklemesi bulunamadı.';
  }
  return null;
}

class BulkApi {
  BulkApi({
    required String baseUrl,
    http.Client? client,
    this.readTimeout = const Duration(seconds: 20),
    this.previewTimeout = const Duration(seconds: 90),
    this.commitTimeout = const Duration(seconds: 120),
    this.exportTimeout = const Duration(seconds: 90),
    this.maxResponseBytes = defaultMaxResponseBytes,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  /// Önizleme ≤ 1 MB, dışa aktarma zarfı (20.000 satır) birkaç MB'dır; güvenli üst sınır 40 MB.
  static const int defaultMaxResponseBytes = 40 * 1024 * 1024;

  /// Bu kadar büyük yanıt gövdesi ayrı isolate'ta çözülür (arayüz donmasın).
  static const int offloadThresholdBytes = 512 * 1024;

  final String _baseUrl;
  final http.Client _client;
  final Duration readTimeout;
  final Duration previewTimeout;
  final Duration commitTimeout;
  final Duration exportTimeout;
  final int maxResponseBytes;

  String _imports(int siteCode, String tail) => '/manager/sites/$siteCode/imports/$tail';

  /// `GET imports/spec`.
  Future<ImportSpec> getImportSpec({required String token, required int siteCode}) async {
    final response = await _send(
      'GET',
      _imports(siteCode, 'spec'),
      token: token,
      timeout: readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return _parse(response, ImportSpec.fromJson);
  }

  Map<String, dynamic> _rowsBody({
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    required bool allowOverwrite,
    Map<String, Object?>? options,
  }) => <String, dynamic>{
    'spec_version': specVersion,
    // Yalnız devir bakiyesinde (`cutover_date`, onayda `expected_total_minor`).
    'options': ?options,
    // Yalnız `apartments`'ta geçerlidir (diğerlerinde gönderilirse sunucu 400 der).
    if (kind.supportsOverwrite) 'allow_overwrite': allowOverwrite,
    'rows': <Map<String, Object?>>[for (final row in rows) row.toJson()],
  };

  /// `POST imports/:kind/preview` (YAZMAZ).
  Future<ImportPreview> previewImport({
    required String token,
    required int siteCode,
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    bool allowOverwrite = false,
    Map<String, Object?>? options,
  }) async {
    final response = await _send(
      'POST',
      _imports(siteCode, '${kind.apiValue}/preview'),
      token: token,
      body: _rowsBody(kind: kind, specVersion: specVersion, rows: rows, allowOverwrite: allowOverwrite, options: options),
      timeout: previewTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Önizleme alınamadı, tekrar deneyin.',
    );
    return _parse(response, ImportPreview.fromJson);
  }

  /// `POST imports/:kind/accounts` (YAZMAZ): önizleme tablosundaki «Kullanıcı Adı» sütunu için hesap önerileri. Yalnız kişi türleri.
  Future<List<AccountProposal>> previewAccounts({
    required String token,
    required int siteCode,
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
  }) async {
    final response = await _send(
      'POST',
      _imports(siteCode, '${kind.apiValue}/accounts'),
      token: token,
      body: _rowsBody(kind: kind, specVersion: specVersion, rows: rows, allowOverwrite: false),
      timeout: previewTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Kullanıcı adları hazırlanamadı, tekrar deneyin.',
    );
    return _parse(response, (json) {
      if (json['accounts'] is! List) throw const FormatException('Hesap listesi yok.');
      return AccountProposal.listFrom(json['accounts']);
    });
  }

  /// `POST imports/login-names/check` (YAZMAZ): yöneticinin yazdığı kullanıcı adının biçimi ve BU SİTEDEKİ kullanılabilirliği (başka sitede kayıtlı ad «kullanılabilir» döner; sistem geneli kesin ad onayda verilir).
  Future<LoginNameCheck> checkLoginName({required String token, required int siteCode, required String loginName}) async {
    final response = await _send(
      'POST',
      _imports(siteCode, 'login-names/check'),
      token: token,
      body: <String, dynamic>{'login_name': loginName},
      timeout: readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Kullanıcı adı denetlenemedi, tekrar deneyin.',
    );
    return _parse(response, LoginNameCheck.fromJson);
  }

  /// `POST imports/:kind/commit` (201 ya da replay 200). Sonuç belirsizse (zaman aşımı / ağ) mesaj "yükleme
  /// tamamlanmış olabilir; aynı işlem anahtarıyla tekrar denemek çift kayıt yaratmaz" der.
  Future<ImportResult> commitImport({
    required String token,
    required int siteCode,
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    required String expectedHash,
    required String idempotencyKey,
    bool allowOverwrite = false,
    bool strict = false,
    bool acknowledged = false,
    Map<String, Object?>? options,
  }) async {
    final body = _rowsBody(kind: kind, specVersion: specVersion, rows: rows, allowOverwrite: allowOverwrite, options: options)
      ..['expected_hash'] = expectedHash
      ..['idempotency_key'] = idempotencyKey
      ..['strict'] = strict;
    if (kind.needsAcknowledgement) body['acknowledged'] = acknowledged;
    const ambiguous =
        'Sunucudan yanıt alınamadı. Yükleme tamamlanmış olabilir; aynı işlemi tekrar denerseniz çift kayıt oluşmaz.';
    final response = await _send(
      'POST',
      _imports(siteCode, '${kind.apiValue}/commit'),
      token: token,
      body: body,
      timeout: commitTimeout,
      timeoutMessage: ambiguous,
      transportMessage: ambiguous,
      acceptStatuses: const <int>{200, 201},
    );
    return _parse(response, ImportResult.fromJson);
  }

  /// `GET exports/:kind` -> zarf. [kind] serbest metindir (Faz 4b yeni türler ekler); [pathPrefix] finans gibi
  /// farklı yollar içindir.
  Future<ExportEnvelope> exportData({
    required String token,
    required int siteCode,
    required String kind,
    BulkExportFilters filters = const BulkExportFilters(),
    bool includeNotes = false,
    ExportFormat format = ExportFormat.xlsx,
    String pathPrefix = '',
  }) async {
    final query = <String, String>{
      ...filters.toQuery(),
      if (includeNotes) 'include_notes': 'true',
      'format': format.apiValue,
    };
    final response = await _send(
      'GET',
      '/manager/sites/$siteCode/${pathPrefix.isEmpty ? '' : '$pathPrefix/'}exports/$kind',
      token: token,
      query: query,
      timeout: exportTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Veriler hazırlanamadı, biraz sonra tekrar deneyin.',
      maxBytes: maxResponseBytes,
    );
    return _parse(response, ExportEnvelope.fromJson);
  }

  String _opening(int siteCode, String tail) => '/manager/sites/$siteCode/finance/opening-balances$tail';

  /// `GET finance/opening-balances`.
  Future<List<OpeningRun>> listOpeningRuns({required String token, required int siteCode}) async {
    final response = await _send(
      'GET',
      _opening(siteCode, ''),
      token: token,
      timeout: readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return _parse(response, (json) {
      final runs = json['runs'];
      if (runs is! List) throw const FormatException('Devir listesi yok.');
      return <OpeningRun>[for (final r in runs) if (r is Map) OpeningRun.fromJson(Map<String, dynamic>.from(r))];
    });
  }

  /// `GET finance/opening-balances/:runId` (geri alma önizlemesi).
  Future<OpeningRevertPreview> getOpeningRun({required String token, required int siteCode, required int runId}) async {
    final response = await _send(
      'GET',
      _opening(siteCode, '/$runId'),
      token: token,
      timeout: readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return _parse(response, OpeningRevertPreview.fromJson);
  }

  /// `POST finance/opening-balances/:runId/revert` (201 ya da replay 200). Aynı anahtarla tekrar güvenlidir.
  Future<int> revertOpening({
    required String token,
    required int siteCode,
    required int runId,
    required String reason,
    required String idempotencyKey,
    required int expectedCount,
    required int expectedTotalMinor,
    int expectedCreditTotalMinor = 0,
  }) async {
    const ambiguous =
        'Sunucudan yanıt alınamadı. Geri alma tamamlanmış olabilir; aynı işlemi tekrar denerseniz çift kayıt oluşmaz.';
    final response = await _send(
      'POST',
      _opening(siteCode, '/$runId/revert'),
      token: token,
      body: <String, dynamic>{
        'reason': reason,
        'idempotency_key': idempotencyKey,
        'expected_count': expectedCount,
        'expected_total_minor': expectedTotalMinor,
        // Alacaklı devir (K16): alacak toplamı AYRI onaylanır (yalnız alacaklı yüklemede gönderilir).
        if (expectedCreditTotalMinor > 0) 'expected_credit_total_minor': expectedCreditTotalMinor,
      },
      timeout: commitTimeout,
      timeoutMessage: ambiguous,
      transportMessage: ambiguous,
      acceptStatuses: const <int>{200, 201},
    );
    return _parse(response, (json) => json['reversed_count'] is num ? (json['reversed_count'] as num).toInt() : 0);
  }

  // --- Taşıma katmanı --------------------------------------------------------------------------

  Future<http.Response> _send(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    required Duration timeout,
    required String timeoutMessage,
    String transportMessage =
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    int? maxBytes,
    Set<int> acceptStatuses = const <int>{200},
  }) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);

    var timedOut = false;
    final http.Response response;
    try {
      response = await _exchange(request, maxBytes: maxBytes ?? maxResponseBytes, isCancelled: () => timedOut)
          .timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              throw TimeoutException(null, timeout);
            },
          );
    } on TimeoutException {
      throw ApiException(timeoutMessage);
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw ApiException(transportMessage);
    } on Exception {
      // SocketException, TlsException, ... (ayrıntı kullanıcıya gösterilmez). Programlama hataları (Error)
      // bilerek yakalanmaz.
      throw ApiException(transportMessage);
    }
    if (acceptStatuses.contains(response.statusCode)) return response;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw ApiException(
        'Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    throw _failure(response);
  }

  Future<http.Response> _exchange(
    http.Request request, {
    required int maxBytes,
    required bool Function() isCancelled,
  }) async {
    final streamed = await _client.send(request);
    final declared = streamed.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(streamed.stream.listen((_) {}).cancel());
      throw _tooLarge();
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      if (isCancelled()) break;
      builder.add(chunk);
      if (builder.length > maxBytes) throw _tooLarge();
    }
    return http.Response.bytes(
      builder.takeBytes(),
      streamed.statusCode,
      headers: streamed.headers,
      request: request,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  ApiException _tooLarge() => ApiException(
    'Sunucu yanıtı çok büyük. Süzgeçle daraltıp tekrar deneyin.',
    statusCode: 413,
    code: 'EXPORT_TOO_LARGE',
  );

  // --- Hata çevirisi ---------------------------------------------------------------------------

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
      if (status == 413) {
        return ApiException(
          'Dosya çok büyük. Satırları parçalara bölüp ayrı ayrı yükleyin.',
          statusCode: status,
          code: 'PAYLOAD_TOO_LARGE',
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
            : (code == 'ACCOUNT_DELETED'
                  ? 'Bu hesap silinmiş.'
                  : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }
    if (status == 413) {
      return ApiException(
        'Dosya çok büyük. Satırları parçalara bölüp ayrı ayrı yükleyin.',
        statusCode: status,
        code: code ?? 'PAYLOAD_TOO_LARGE',
        payload: body,
      );
    }

    final mapped = bulkErrorMessage(code) ??
        AuthApi.messageForErrorCode(code, retryAfterSeconds: retryAfter, payload: body);
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

  /// Başarılı yanıt gövdesini [build] ile modele çevirir. Yapısal bozukluk ([FormatException]) kullanıcıya
  /// anlaşılır hata olur; yanlış "boş" sonuç üretilmez.
  Future<T> _parse<T>(http.Response response, T Function(Map<String, dynamic>) build) async {
    Map<String, dynamic>? parsed;
    if (response.bodyBytes.length > offloadThresholdBytes) {
      parsed = await compute(_decodeObject, response.bodyBytes);
    } else {
      parsed = _tryObject(response.bodyBytes);
    }
    if (parsed == null) {
      throw ApiException(
        'Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    try {
      return build(parsed);
    } on FormatException {
      throw ApiException(
        'Sunucu yanıtı beklenen biçimde değil. Uygulamayı güncelleyip tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
  }
}

Map<String, dynamic>? _decodeObject(Uint8List bytes) => BulkApi._tryObject(bytes);

/// Oturum belirtecini [AuthService]'ten alan, oturum hatalarını merkezi doğrulamaya bağlayan katman.
/// Ekranlar bunu kullanır (testlerde sahte [BulkApi] ile kurulur).
class BulkService {
  BulkService({required this.authService, BulkApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? BulkApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [BulkApi] vermek için.
  @visibleForTesting
  static BulkApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final BulkApi api;

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

  Future<ImportSpec> getImportSpec(int siteCode) =>
      _guard((token) => api.getImportSpec(token: token, siteCode: siteCode));

  Future<ImportPreview> previewImport(
    int siteCode, {
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    bool allowOverwrite = false,
    Map<String, Object?>? options,
  }) => _guard(
    (token) => api.previewImport(
      token: token,
      siteCode: siteCode,
      kind: kind,
      specVersion: specVersion,
      rows: rows,
      allowOverwrite: allowOverwrite,
      options: options,
    ),
  );

  Future<List<AccountProposal>> previewAccounts(
    int siteCode, {
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
  }) => _guard(
    (token) => api.previewAccounts(token: token, siteCode: siteCode, kind: kind, specVersion: specVersion, rows: rows),
  );

  Future<LoginNameCheck> checkLoginName(int siteCode, String loginName) =>
      _guard((token) => api.checkLoginName(token: token, siteCode: siteCode, loginName: loginName));

  Future<ImportResult> commitImport(
    int siteCode, {
    required ImportKind kind,
    required int specVersion,
    required List<ImportRow> rows,
    required String expectedHash,
    required String idempotencyKey,
    bool allowOverwrite = false,
    bool strict = false,
    bool acknowledged = false,
    Map<String, Object?>? options,
  }) => _guard(
    (token) => api.commitImport(
      token: token,
      siteCode: siteCode,
      kind: kind,
      specVersion: specVersion,
      rows: rows,
      expectedHash: expectedHash,
      idempotencyKey: idempotencyKey,
      allowOverwrite: allowOverwrite,
      strict: strict,
      acknowledged: acknowledged,
      options: options,
    ),
  );

  Future<List<OpeningRun>> listOpeningRuns(int siteCode) =>
      _guard((token) => api.listOpeningRuns(token: token, siteCode: siteCode));

  Future<OpeningRevertPreview> getOpeningRun(int siteCode, int runId) =>
      _guard((token) => api.getOpeningRun(token: token, siteCode: siteCode, runId: runId));

  Future<int> revertOpening(
    int siteCode,
    int runId, {
    required String reason,
    required String idempotencyKey,
    required int expectedCount,
    required int expectedTotalMinor,
    int expectedCreditTotalMinor = 0,
  }) => _guard(
    (token) => api.revertOpening(
      token: token,
      siteCode: siteCode,
      runId: runId,
      reason: reason,
      idempotencyKey: idempotencyKey,
      expectedCount: expectedCount,
      expectedTotalMinor: expectedTotalMinor,
      expectedCreditTotalMinor: expectedCreditTotalMinor,
    ),
  );

  Future<ExportEnvelope> exportData(
    int siteCode, {
    required String kind,
    BulkExportFilters filters = const BulkExportFilters(),
    bool includeNotes = false,
    ExportFormat format = ExportFormat.xlsx,
    String pathPrefix = '',
  }) => _guard(
    (token) => api.exportData(
      token: token,
      siteCode: siteCode,
      kind: kind,
      filters: filters,
      includeNotes: includeNotes,
      format: format,
      pathPrefix: pathPrefix,
    ),
  );
}
