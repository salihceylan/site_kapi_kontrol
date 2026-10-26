// Banka dosyası uçları (Dalga 2 / 2C; sözleşme: docs/PLATFORM_FINANS_BANKA.md).
//
// [BankImportApi]: yalnız HTTP katmanı. [BankImportService]: oturum belirtecini [AuthService]'ten alır. Yazma ASLA otomatik yeniden denenmez
// (yükleme `idempotency_key` ile elle güvenle tekrarlanır). Satır verisi ve yanıt gövdeleri günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/bank_statement_reader.dart';

String? bankErrorMessage(String? code) {
  switch (code) {
    case 'FILE_ALREADY_IMPORTED':
      return 'Bu dosya bu hesaba daha önce yüklenmiş.';
    case 'BANK_PREVIEW_STALE':
      return 'Önizlemeden sonra kayıtlar değişti. Önizlemeyi yenileyip tekrar deneyin.';
    case 'BANK_LINE_NOT_OPEN':
      return 'Bu satır artık işlenmeyi beklemiyor. Listeyi yenileyin.';
    case 'BANK_IMPORT_HAS_CLASSIFIED':
      return 'Gelir/gider olarak ayrılmış satırlar var. Önce onları tek tek geri alın.';
    case 'BANK_IMPORT_REVERTED':
      return 'Bu yükleme zaten geri alınmış.';
    case 'POSSIBLE_DUPLICATE_PAYMENT':
      return 'Aynı tutar ve tarihte başka bir banka satırının tahsilatı var; çift tahsilat olmasın diye kontrol edin.';
    case 'LINK_AMBIGUOUS':
      return 'Birden çok benzer tahsilat var. "Mevcut tahsilata bağla" ile birini seçin.';
    case 'LINK_NOT_POSSIBLE':
      return 'Bu tahsilat bağlanamaz (tutar uyuşmuyor, iptal edilmiş ya da başka satıra bağlı).';
    case 'PERIOD_CLOSED':
      return 'Bu tarihin dönemi kapatılmış. Önce dönemi açın.';
    case 'MODULE_DISABLED':
      return 'Aidat ve Finans özelliği bu sitede kapalı.';
    case 'IDEMPOTENCY_CONFLICT':
      return 'Bu yükleme farklı bilgilerle daha önce gönderilmiş. Dosyayı yeniden seçin.';
    case 'BANK_PDF_SCANNED':
      return 'Bu PDF taranmış bir resim; metni okunamıyor. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin.';
  }
  return null;
}

class BankImportApi {
  BankImportApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  String _base(int siteCode) => '/manager/sites/$siteCode/finance';

  Map<String, dynamic> _statementBody({
    required int accountId,
    required BankFile file,
    required List<BankLine> lines,
    String? accountIban,
    String? from,
    String? to,
  }) => <String, dynamic>{
    'account_id': accountId,
    // PDF'den okunan satırlar tablo satırıdır: sunucuda 'csv' biçimiyle kaydedilir (dosya adı .pdf kalır).
    'format': file.kind == BankFileKind.pdf ? 'csv' : file.kind.name,
    'file': bankFileJson(file),
    'statement': <String, dynamic>{'from': ?from, 'to': ?to, 'account_iban': ?accountIban},
    'lines': lines.map((e) => e.toJson()).toList(),
  };

  Future<({BankMapping mapping, String signature})?> getProfile({required String token, required int siteCode, required int accountId}) async {
    final body = await _send('GET', '${_base(siteCode)}/accounts/$accountId/bank-profile', token: token);
    final p = body['profile'];
    if (p is! Map) return null;
    final map = Map<String, dynamic>.from(p);
    return (
      mapping: BankMapping.fromJson(map['mapping'] is Map ? Map<String, dynamic>.from(map['mapping'] as Map) : <String, dynamic>{}),
      signature: '${map['header_signature'] ?? ''}',
    );
  }

  Future<void> putProfile({
    required String token,
    required int siteCode,
    required int accountId,
    required BankFileKind kind,
    required String signature,
    required BankMapping mapping,
  }) async {
    await _send(
      'PUT',
      '${_base(siteCode)}/accounts/$accountId/bank-profile',
      token: token,
      body: <String, dynamic>{'format': kind == BankFileKind.xlsx ? 'xlsx' : 'csv', 'header_signature': signature, 'mapping': mapping.toJson(), 'options': <String, dynamic>{}},
    );
  }

  /// PDF hesap ekstresini (en çok 5 MB) sunucuya ham ikili gövde olarak gönderir; sunucu metin katmanını okur (OCR yok, dosya saklanmaz).
  Future<BankPdfExtract> extractPdf({required String token, required int siteCode, required Uint8List bytes}) async {
    final body = await _send('POST', '${_base(siteCode)}/bank-imports/pdf-extract', token: token, rawBody: bytes, rawContentType: 'application/pdf');
    return BankPdfExtract.fromJson(body);
  }

  Future<BankPreview> preview({
    required String token,
    required int siteCode,
    required int accountId,
    required BankFile file,
    required List<BankLine> lines,
    String? accountIban,
  }) async {
    final body = await _send(
      'POST',
      '${_base(siteCode)}/bank-imports/preview',
      token: token,
      body: _statementBody(accountId: accountId, file: file, lines: lines, accountIban: accountIban),
    );
    return BankPreview.fromJson(body);
  }

  Future<BankCommitResult> commit({
    required String token,
    required int siteCode,
    required int accountId,
    required BankFile file,
    required List<BankLine> lines,
    required String previewHash,
    required String idempotencyKey,
    String? accountIban,
  }) async {
    final body = await _send(
      'POST',
      '${_base(siteCode)}/bank-imports',
      token: token,
      body: <String, dynamic>{
        ..._statementBody(accountId: accountId, file: file, lines: lines, accountIban: accountIban),
        'expected_hash': previewHash,
        'idempotency_key': idempotencyKey,
      },
    );
    return BankCommitResult.fromJson(body);
  }

  Future<List<BankImportItem>> listImports({required String token, required int siteCode}) async {
    final body = await _send('GET', '${_base(siteCode)}/bank-imports', token: token);
    return _list(body['imports']).map(BankImportItem.fromJson).toList();
  }

  Future<void> revertImport({required String token, required int siteCode, required int importId}) async {
    await _send('POST', '${_base(siteCode)}/bank-imports/$importId/revert', token: token, body: <String, dynamic>{});
  }

  /// [status]: `attention` (bekleyen) ya da `done` (gelir/gider olarak ayrılan).
  Future<List<BankLineItem>> listLinesByStatus({required String token, required int siteCode, required String status}) async {
    final body = await _send('GET', '${_base(siteCode)}/bank-lines?status=$status&limit=200', token: token);
    return _list(body['lines']).map(BankLineItem.fromJson).toList();
  }

  Future<int> attentionCount({required String token, required int siteCode}) async {
    final body = await _send('GET', '${_base(siteCode)}/bank-lines/summary', token: token);
    final a = body['attention'];
    return a is int ? a : 0;
  }

  Future<void> assignLine({required String token, required int siteCode, required int lineId, required int apartmentId, String? party, bool saveIban = false}) async {
    await _send(
      'POST',
      '${_base(siteCode)}/bank-lines/$lineId/assign',
      token: token,
      body: <String, dynamic>{'apartment_id': apartmentId, 'account_party': ?party, 'save_iban': saveIban},
    );
  }

  /// Önerilen daireleri toplu onaylar; işlenemeyenlerin sayısını döner.
  Future<({int done, int failed})> confirmLines({required String token, required int siteCode, required List<int> lineIds}) async {
    final body = await _send('POST', '${_base(siteCode)}/bank-lines/confirm', token: token, body: <String, dynamic>{'line_ids': lineIds});
    return (done: (body['done'] as List?)?.length ?? 0, failed: (body['failed'] as List?)?.length ?? 0);
  }

  Future<void> classifyLine({
    required String token,
    required int siteCode,
    required int lineId,
    required String kind,
    int? categoryId,
    int? transferAccountId,
    String? note,
  }) async {
    await _send(
      'POST',
      '${_base(siteCode)}/bank-lines/$lineId/classify',
      token: token,
      body: <String, dynamic>{'kind': kind, 'category_id': ?categoryId, 'transfer_account_id': ?transferAccountId, 'note': ?note},
    );
  }

  Future<void> unclassifyLine({required String token, required int siteCode, required int lineId}) async {
    await _send('POST', '${_base(siteCode)}/bank-lines/$lineId/unclassify', token: token, body: <String, dynamic>{});
  }

  Future<List<BankIbanItem>> listIbans({required String token, required int siteCode}) async {
    final body = await _send('GET', '${_base(siteCode)}/bank-ibans', token: token);
    return _list(body['ibans']).map(BankIbanItem.fromJson).toList();
  }

  Future<void> deleteIban({required String token, required int siteCode, required String iban, required int apartmentId}) async {
    await _send('DELETE', '${_base(siteCode)}/bank-ibans/$iban?apartment_id=$apartmentId', token: token);
  }

  static List<Map<String, dynamic>> _list(Object? v) =>
      (v is List ? v : const <Object?>[]).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<Map<String, dynamic>> _send(String method, String path, {required String token, Map<String, dynamic>? body, Uint8List? rawBody, String? rawContentType}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        if (rawBody != null) 'Content-Type': rawContentType ?? 'application/octet-stream',
      });
    if (body != null) request.body = jsonEncode(body);
    if (rawBody != null) request.bodyBytes = rawBody;
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiException(
        method == 'GET' ? 'Sunucu yanıt vermedi, tekrar deneyin.' : 'Sunucu yanıt vermedi. Kayıt yapılmış olabilir; yüklemeler listesini yenileyip kontrol edin.',
      );
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    final payload = _tryObject(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (payload == null) throw ApiException('Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.', statusCode: response.statusCode);
      return payload;
    }
    throw _failure(response, payload);
  }

  ApiException _failure(http.Response response, Map<String, dynamic>? payload) {
    final status = response.statusCode;
    if (payload == null) {
      if ((status == 401 || status == 403) && response.bodyBytes.isNotEmpty) {
        return ApiException('Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin.', statusCode: status, fromIntermediary: true);
      }
      return ApiException(
        status >= 500 ? 'Sunucu şu anda yanıt veremiyor. Lütfen biraz sonra tekrar deneyin.' : 'İşlem başarısız ($status)',
        statusCode: status,
        genericFallback: true,
      );
    }
    final rawCode = payload['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    if (status == 401) return SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    final rawError = payload['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty ? AuthApi.sanitizeServerMessage(rawError.trim()) : null;
    final known = bankErrorMessage(code);
    final message = known ?? serverText ?? AuthApi.genericMessageForStatus(status, code: code) ?? 'İşlem başarısız ($status)';
    return ApiException(message, statusCode: status, code: code, payload: payload, genericFallback: known == null && serverText == null);
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
}

class BankImportService {
  BankImportService({required this.authService, BankImportApi? api, String? Function()? tokenProvider})
    : api = api ?? BankImportApi(baseUrl: authService.api.baseUrl),
      _tokenProvider = tokenProvider ?? (() => authService.session?.token);

  final AuthService authService;
  final BankImportApi api;
  final String? Function() _tokenProvider;

  static final Expando<BankImportService> _registered = Expando<BankImportService>('bankImport');

  static BankImportService of(AuthService authService) => _registered[authService] ??= BankImportService(authService: authService);

  @visibleForTesting
  static void register(AuthService authService, BankImportService service) {
    _registered[authService] = service;
  }

  Future<T> run<T>(Future<T> Function(BankImportApi api, String token) call) async {
    final token = _tokenProvider();
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await call(api, token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }
}
