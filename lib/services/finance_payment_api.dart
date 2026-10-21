// Ödeme bilgisi uçları (Dalga 2 / 2A; sözleşme: docs/PLATFORM_FINANS_ODEME.md).
//
// [FinancePaymentApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [FinancePaymentService]: oturum belirtecini [AuthService]'ten alır, 401'i oturum doğrulamasına bağlar; testlerde [register] ile sahte kurulur.
// Yazma ASLA otomatik yeniden denenmez. Belirteç ve yanıt gövdeleri günlüğe yazılmaz.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/payment_info.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class FinancePaymentApi {
  FinancePaymentApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// `GET /app/my-finance/payment-info`
  Future<PaymentInfo> getMyPaymentInfo({required String token}) async {
    final body = await _send('GET', '/app/my-finance/payment-info', token: token);
    return PaymentInfo.fromJson(body);
  }

  /// `GET /manager/sites/:siteCode/finance/payment-settings`
  Future<PaymentSettings> getSettings({required String token, required int siteCode}) async {
    final body = await _send('GET', '/manager/sites/$siteCode/finance/payment-settings', token: token);
    return PaymentSettings.fromJson(body);
  }

  /// `PUT .../payment-settings` (kısmi: yalnız verilen alanlar). [expectedVersion] ayar satırı varken zorunludur.
  Future<PaymentSettings> putSettings({
    required String token,
    required int siteCode,
    required int expectedVersion,
    String? prefix,
    int? residentAccountId,
    bool clearResidentAccount = false,
    bool? noticesEnabled,
  }) async {
    final body = await _send(
      'PUT',
      '/manager/sites/$siteCode/finance/payment-settings',
      token: token,
      body: <String, dynamic>{
        'expected_settings_version': expectedVersion,
        'prefix': ?prefix,
        if (clearResidentAccount) 'resident_account_id': null else 'resident_account_id': ?residentAccountId,
        'notices_enabled': ?noticesEnabled,
      },
    );
    return PaymentSettings.fromJson(body);
  }

  /// `PUT .../accounts/:id/bank-details` -> yeni sürüm (201) ya da aynı değer (200).
  Future<void> putBankDetails({
    required String token,
    required int siteCode,
    required int accountId,
    required String iban,
    required String payeeName,
  }) async {
    await _send(
      'PUT',
      '/manager/sites/$siteCode/finance/accounts/$accountId/bank-details',
      token: token,
      body: <String, dynamic>{'iban': iban, 'payee_name': payeeName},
    );
  }

  Future<Map<String, dynamic>> _send(String method, String path, {required String token, Map<String, dynamic>? body}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
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

  ApiException _failure(http.Response response, Map<String, dynamic>? payload) {
    final status = response.statusCode;
    if (payload == null) {
      if ((status == 401 || status == 403) && response.bodyBytes.isNotEmpty) {
        return ApiException(
          'Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      return ApiException(
        status >= 500 ? 'Sunucu şu anda yanıt veremiyor. Lütfen biraz sonra tekrar deneyin.' : 'İşlem başarısız ($status)',
        statusCode: status,
        genericFallback: true,
      );
    }
    final rawCode = payload['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    if (status == 401) {
      return SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    }
    final rawError = payload['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty ? AuthApi.sanitizeServerMessage(rawError.trim()) : null;
    final message = paymentErrorMessage(code) ?? serverText ?? AuthApi.genericMessageForStatus(status, code: code) ?? 'İşlem başarısız ($status)';
    return ApiException(message, statusCode: status, code: code, payload: payload, genericFallback: paymentErrorMessage(code) == null && serverText == null);
  }

  /// Ödeme bilgisi hata kodları için düz Türkçe metin (bilinmiyorsa null: sunucu metni kullanılır).
  static String? paymentErrorMessage(String? code) {
    switch (code) {
      case 'IBAN_INVALID':
        return 'IBAN geçersiz. TR ile başlayan 26 haneli, sağlama basamağı doğru bir IBAN girin.';
      case 'PREFIX_TAKEN':
        return 'Bu önek başka bir sitede kullanılıyor. Başka bir önek seçin.';
      case 'SETTINGS_VERSION_CONFLICT':
        return 'Ayarlar siz bakarken değişti. Ekranı yenileyip tekrar deneyin.';
      case 'ACCOUNT_NOT_FOUND':
        return 'Hesap bulunamadı.';
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

class FinancePaymentService {
  FinancePaymentService({required this.authService, FinancePaymentApi? api, String? Function()? tokenProvider})
    : api = api ?? FinancePaymentApi(baseUrl: authService.api.baseUrl),
      _tokenProvider = tokenProvider ?? (() => authService.session?.token);

  final AuthService authService;
  final FinancePaymentApi api;
  final String? Function() _tokenProvider;

  static final Expando<FinancePaymentService> _registered = Expando<FinancePaymentService>('financePayment');

  static FinancePaymentService of(AuthService authService) => _registered[authService] ??= FinancePaymentService(authService: authService);

  @visibleForTesting
  static void register(AuthService authService, FinancePaymentService service) {
    _registered[authService] = service;
  }

  Future<T> run<T>(Future<T> Function(FinancePaymentApi api, String token) call) async {
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
