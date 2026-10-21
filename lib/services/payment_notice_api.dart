// Dekont bildirimi uçları (Dalga 2 / 2B; sözleşme: docs/PLATFORM_FINANS_DEKONT.md).
//
// [PaymentNoticeApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [PaymentNoticeService]: oturum belirtecini [AuthService]'ten alır, 401'i oturum doğrulamasına bağlar; testlerde [register] ile sahte kurulur.
// Yazma ASLA otomatik yeniden denenmez (aynı işlem anahtarıyla kullanıcı yeniden dener). Belirteç, dosya adı ve gövdeler günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/payment_notice.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Tekrar gönderimi güvenli kılan işlem anahtarı (1-64 görünür ASCII).
String newNoticeKey() {
  final rnd = Random.secure();
  final tail = List<int>.generate(8, (_) => rnd.nextInt(36)).map((n) => n.toRadixString(36)).join();
  return 'pn${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$tail';
}

/// Sakin bir bildirim gönderince/geri çekince artar; "İnceleniyor" satırı kendini yeniler.
final ValueNotifier<int> paymentNoticeRevision = ValueNotifier<int>(0);

class PaymentNoticeApi {
  PaymentNoticeApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static const String _mine = '/app/my-finance/payment-notices';
  static String _mgr(int siteCode) => '/manager/sites/$siteCode/finance/payment-notices';

  // --- Sakin -----------------------------------------------------------------------------------------

  Future<NoticeCreated> createMine({required String token, required Map<String, dynamic> body}) async =>
      NoticeCreated.fromJson(await _send('POST', _mine, token: token, body: body));

  Future<PaymentNotice> putMineContent({required String token, required int id, required Uint8List bytes}) async {
    final out = await _send('PUT', '$_mine/$id/content', token: token, bytes: bytes);
    return PaymentNotice.fromJson(Map<String, dynamic>.from(out['notice'] as Map));
  }

  Future<MyNotices> listMine({required String token, int? apartmentId}) async =>
      MyNotices.fromJson(await _send('GET', apartmentId == null ? _mine : '$_mine?apartment_id=$apartmentId', token: token));

  Future<void> withdrawMine({required String token, required int id}) => _send('POST', '$_mine/$id/withdraw', token: token, body: const <String, dynamic>{});

  Future<void> markSeen({required String token}) => _send('POST', '$_mine/seen', token: token, body: const <String, dynamic>{});

  Future<Uint8List> mineFile({required String token, required int id}) => _bytes('$_mine/$id/file', token: token);

  // --- Yönetici --------------------------------------------------------------------------------------

  Future<NoticePage> list({required String token, required int siteCode, String status = 'pending', int? apartmentId, int? beforeId}) async {
    final q = <String>['status=$status', if (apartmentId != null) 'apartment_id=$apartmentId', if (beforeId != null) 'before_id=$beforeId'];
    return NoticePage.fromJson(await _send('GET', '${_mgr(siteCode)}?${q.join('&')}', token: token));
  }

  Future<NoticeAttention> summary({required String token, required int siteCode}) async =>
      NoticeAttention.fromJson(await _send('GET', '${_mgr(siteCode)}/summary', token: token));

  Future<NoticeDetail> detail({required String token, required int siteCode, required int id}) async =>
      NoticeDetail.fromJson(await _send('GET', '${_mgr(siteCode)}/$id', token: token));

  Future<NoticeCreated> createManual({required String token, required int siteCode, required Map<String, dynamic> body}) async =>
      NoticeCreated.fromJson(await _send('POST', _mgr(siteCode), token: token, body: body));

  Future<PaymentNotice> putContent({required String token, required int siteCode, required int id, required Uint8List bytes}) async {
    final out = await _send('PUT', '${_mgr(siteCode)}/$id/content', token: token, bytes: bytes);
    return PaymentNotice.fromJson(Map<String, dynamic>.from(out['notice'] as Map));
  }

  Future<Uint8List> file({required String token, required int siteCode, required int id}) => _bytes('${_mgr(siteCode)}/$id/file', token: token);

  Future<Map<String, dynamic>> approve({
    required String token,
    required int siteCode,
    required int id,
    int? accountId,
    String? accountParty,
    bool bookInOpenPeriod = false,
    List<String> acknowledged = const <String>[],
  }) => _send(
    'POST',
    '${_mgr(siteCode)}/$id/approve',
    token: token,
    body: <String, dynamic>{
      'account_id': ?accountId,
      'account_party': ?accountParty,
      'book_in_open_period': bookInOpenPeriod,
      'acknowledged': acknowledged,
    },
  );

  Future<void> link({required String token, required int siteCode, required int id, required int ledgerEntryId}) =>
      _send('POST', '${_mgr(siteCode)}/$id/link', token: token, body: <String, dynamic>{'ledger_entry_id': ledgerEntryId});

  Future<void> reject({required String token, required int siteCode, required int id, required String reasonCode, String? note}) => _send(
    'POST',
    '${_mgr(siteCode)}/$id/reject',
    token: token,
    body: <String, dynamic>{'reason_code': reasonCode, if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
  );

  Future<List<NoticeBulkResult>> bulkApprove({required String token, required int siteCode, required List<int> ids, int? accountId, bool bookInOpenPeriod = false}) async =>
      parseBulkResults(
        await _send(
          'POST',
          '${_mgr(siteCode)}/bulk-approve',
          token: token,
          body: <String, dynamic>{'ids': ids, 'account_id': ?accountId, 'book_in_open_period': bookInOpenPeriod},
        ),
      );

  Future<List<NoticeBulkResult>> bulkReject({required String token, required int siteCode, required List<int> ids, required String reasonCode}) async =>
      parseBulkResults(await _send('POST', '${_mgr(siteCode)}/bulk-reject', token: token, body: <String, dynamic>{'ids': ids, 'reason_code': reasonCode}));

  // --- Aktarım ---------------------------------------------------------------------------------------

  Future<Map<String, dynamic>> _send(String method, String path, {required String token, Map<String, dynamic>? body, Uint8List? bytes}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        if (bytes != null) 'Content-Type': 'application/octet-stream',
      });
    if (body != null) request.body = jsonEncode(body);
    if (bytes != null) request.bodyBytes = bytes;
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(Duration(seconds: bytes != null ? 120 : 30));
    } on TimeoutException {
      throw ApiException(
        method == 'GET' ? 'Sunucu yanıt vermedi, tekrar deneyin.' : 'Sunucu yanıt vermedi. Kayıt yapılmış olabilir; ekranı yenileyip kontrol edin.',
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

  Future<Uint8List> _bytes(String path, {required String token}) async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('$_baseUrl$path'), headers: <String, String>{'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw ApiException('Dosya indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return response.bodyBytes;
    throw _failure(response, _tryObject(response.bodyBytes));
  }

  ApiException _failure(http.Response response, Map<String, dynamic>? payload) {
    final status = response.statusCode;
    if (payload == null) {
      if ((status == 401 || status == 403) && response.bodyBytes.isNotEmpty) {
        return ApiException('Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin.', statusCode: status, fromIntermediary: true);
      }
      if (status == 413) return ApiException('Dosya çok büyük (en fazla 10 MB).', statusCode: status);
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
    final message = noticeErrorMessage(code) ?? serverText ?? AuthApi.genericMessageForStatus(status, code: code) ?? 'İşlem başarısız ($status)';
    return ApiException(message, statusCode: status, code: code, payload: payload, genericFallback: noticeErrorMessage(code) == null && serverText == null);
  }

  /// Hata kodları için düz Türkçe metin (bilinmiyorsa null: sunucu metni kullanılır).
  static String? noticeErrorMessage(String? code) {
    switch (code) {
      case 'PAYMENT_NOTICES_DISABLED':
        return 'Bu sitede dekont bildirimi henüz açık değil. Yönetime sorun.';
      case 'NOTICE_LIMIT_REACHED':
        return 'Çok fazla bekleyen bildiriminiz var. Yönetim karar verdikten sonra yenisini gönderin.';
      case 'NOTICE_WARNINGS_UNACKNOWLEDGED':
        return 'Önemli uyarılar var. Her birini gözden geçirdiğinizi işaretleyin.';
      case 'NOTICE_PERIOD_CLOSED':
        return 'Dekontun tarihi kapalı bir döneme düşüyor. "Açık döneme yaz" seçeneğiyle bugünün tarihine işleyebilirsiniz.';
      case 'ACCOUNT_REQUIRED':
        return 'Tahsilatın gireceği kasa ya da banka hesabını seçin.';
      case 'NOTICE_PDF_ACTIVE_CONTENT':
        return 'Bu PDF kabul edilemedi. Dekontun ekran görüntüsünü yüklemeyi deneyin.';
      case 'MODULE_DISABLED':
        return 'Aidat ve Finans özelliği bu sitede kapalı.';
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
}

class PaymentNoticeService {
  PaymentNoticeService({required this.authService, PaymentNoticeApi? api, String? Function()? tokenProvider})
    : api = api ?? PaymentNoticeApi(baseUrl: authService.api.baseUrl),
      _tokenProvider = tokenProvider ?? (() => authService.session?.token);

  final AuthService authService;
  final PaymentNoticeApi api;
  final String? Function() _tokenProvider;

  static final Expando<PaymentNoticeService> _registered = Expando<PaymentNoticeService>('paymentNotice');

  static PaymentNoticeService of(AuthService authService) => _registered[authService] ??= PaymentNoticeService(authService: authService);

  @visibleForTesting
  static void register(AuthService authService, PaymentNoticeService service) {
    _registered[authService] = service;
  }

  Future<T> run<T>(Future<T> Function(PaymentNoticeApi api, String token) call) async {
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
