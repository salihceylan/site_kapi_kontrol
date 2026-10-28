// Sayaç Okuma ve Faturalandırma (`metering`) uçları.
//
// [MeterApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [MeterService]: oturum belirtecini [AuthService]'ten alır. Mutasyonlar (POST/PATCH/DELETE) ASLA otomatik yeniden denenmez.
// Seri numarası, okuma değeri, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class MeterApi {
  MeterApi({required String baseUrl, http.Client? client, Duration readTimeout = const Duration(seconds: 20), Duration writeTimeout = const Duration(seconds: 60)})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client(),
      _readTimeout = readTimeout,
      _writeTimeout = writeTimeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;

  static String _path(int siteCode, String tail) => '/manager/sites/$siteCode/$tail';

  Future<List<MeterApartment>> listApartments({required String token, required int siteCode}) async =>
      MeterApartment.listFrom(await _call('GET', _path(siteCode, 'meter-apartments'), token: token, timeout: _readTimeout));

  Future<List<Meter>> listMeters({required String token, required int siteCode, MeterKind? kind}) async => Meter.listFrom(
    await _call('GET', _path(siteCode, 'meters'), token: token, timeout: _readTimeout, query: <String, String>{if (kind != null) 'kind': kind.api}),
  );

  Future<Meter> createMeter({required String token, required int siteCode, required int apartmentId, required MeterKind kind, required String serialNo}) async {
    final body = await _call(
      'POST',
      _path(siteCode, 'meters'),
      token: token,
      timeout: _writeTimeout,
      body: <String, dynamic>{'apartment_id': apartmentId, 'kind': kind.api, 'serial_no': serialNo},
      ok: const <int>{201},
    );
    return Meter.fromJson(Map<String, dynamic>.from(body['meter'] as Map));
  }

  Future<Meter> updateMeter({required String token, required int siteCode, required int meterId, String? serialNo, bool? isActive}) async {
    final body = await _call(
      'PATCH',
      _path(siteCode, 'meters/$meterId'),
      token: token,
      timeout: _writeTimeout,
      body: <String, dynamic>{'serial_no': ?serialNo, 'is_active': ?isActive},
    );
    return Meter.fromJson(Map<String, dynamic>.from(body['meter'] as Map));
  }

  Future<List<MeterReading>> listReadings({required String token, required int siteCode, required int meterId}) async {
    final body = await _call('GET', _path(siteCode, 'meters/$meterId/readings'), token: token, timeout: _readTimeout);
    return <MeterReading>[for (final m in (body['items'] as List? ?? const <Object?>[])) MeterReading.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  Future<void> addReading({required String token, required int siteCode, required int meterId, required String date, required String value}) => _call(
    'POST',
    _path(siteCode, 'meters/$meterId/readings'),
    token: token,
    timeout: _writeTimeout,
    body: <String, dynamic>{'date': date, 'value': value},
    ok: const <int>{200, 201},
  );

  // --- Saha okuması (görevli; fotoğraflı) ---

  /// [date] ("2026-10-28"): okuma tarihi; sunucu sıçrama tabanını ve "önceki okuma"yı bu tarihten ÖNCEKİ okumalardan hesaplar (verilmezse sunucu bugünü).
  Future<List<FieldMeter>> listFieldMeters({required String token, required int siteCode, MeterKind? kind, String? date}) async => FieldMeter.listFrom(
    await _call(
      'GET',
      '/sites/$siteCode/meter-field/meters',
      token: token,
      timeout: _readTimeout,
      query: <String, String>{'kind': ?kind?.api, 'date': ?date},
    ),
  );

  /// Tekrar gönderim güvenlidir (aynı sayaç+tarih+değer sunucuda `replayed`); bu yüzden çevrimdışı kuyruk aynı okumayı yeniden deneyebilir.
  ///
  /// [confirmJump] verilirse (YENİ istemci) sunucu olağan dışı tüketimi denetler: `false` iken eşik aşılırsa 409 `READING_JUMP` döner ve
  /// okuma kaydedilmez; `true` görevlinin onayıdır (kaydedilir, onay izi tutulur). Verilmezse (null) denetim yapılmaz.
  /// [replace]: yeniden çekim; o gün bu sayaç için okuma varsa değerini değiştirir (yoksa normal ekler).
  Future<FieldReadingResult> postFieldReading({
    required String token,
    required int siteCode,
    required int meterId,
    required String date,
    required String value,
    String? photoBase64,
    bool? confirmJump,
    bool replace = false,
  }) async => FieldReadingResult.fromJson(
    await _call(
      'POST',
      '/sites/$siteCode/meter-field/readings',
      token: token,
      timeout: const Duration(seconds: 40),
      body: <String, dynamic>{
        'meter_id': meterId,
        'date': date,
        'value': value,
        if (photoBase64 != null) ...<String, dynamic>{'photo_b64': photoBase64, 'photo_mime': 'image/jpeg'},
        'confirm_jump': ?confirmJump,
        if (replace) 'replace': true,
      },
      ok: const <int>{200, 201},
    ),
  );

  Future<void> deleteReading({required String token, required int siteCode, required int meterId, required int readingId}) =>
      _call('DELETE', _path(siteCode, 'meters/$meterId/readings/$readingId'), token: token, timeout: _writeTimeout);

  Future<MeterImportResult> importReadings({
    required String token,
    required int siteCode,
    required MeterKind kind,
    required String readingDate,
    required List<Map<String, dynamic>> rows,
    required bool dryRun,
  }) async => MeterImportResult.fromJson(
    await _call(
      'POST',
      _path(siteCode, 'meter-readings/import'),
      token: token,
      timeout: _writeTimeout,
      body: <String, dynamic>{'kind': kind.api, 'reading_date': readingDate, 'rows': rows, 'dry_run': dryRun},
    ),
  );

  Future<BillingPreview> previewBilling({required String token, required int siteCode, required Map<String, dynamic> input}) async =>
      BillingPreview.fromJson(await _call('POST', _path(siteCode, 'meter-billings/preview'), token: token, timeout: _writeTimeout, body: input));

  /// Borçlandırır. `idempotency_key` çağıranın ürettiği tek anahtardır; aynı anahtarla yeniden gönderim çift borç yazmaz.
  Future<MeterBilling> postBilling({required String token, required int siteCode, required Map<String, dynamic> input}) async {
    final body = await _call('POST', _path(siteCode, 'meter-billings'), token: token, timeout: _writeTimeout, body: input, ok: const <int>{200, 201});
    return MeterBilling.fromJson(Map<String, dynamic>.from(body['billing'] as Map));
  }

  Future<List<MeterBilling>> listBillings({required String token, required int siteCode}) async =>
      MeterBilling.listFrom(await _call('GET', _path(siteCode, 'meter-billings'), token: token, timeout: _readTimeout));

  // --- JSON taşıma katmanı ---------------------------------------------------------------------

  static const String _transportMessage = 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    required String token,
    required Duration timeout,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Set<int> ok = const <int>{200},
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
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw ApiException(method == 'GET' ? 'Sunucu yanıt vermedi, tekrar deneyin.' : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; ekranı yenileyip kontrol edin.');
    } on Exception {
      throw ApiException(_transportMessage);
    }
    final parsed = _tryObject(response.bodyBytes);
    if (ok.contains(response.statusCode)) {
      if (parsed == null) throw ApiException('Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.', statusCode: response.statusCode);
      return parsed;
    }
    throw _failure(response, parsed);
  }

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } on FormatException {
      return null;
    }
  }

  ApiException _failure(http.Response response, Map<String, dynamic>? payload) {
    final status = response.statusCode;
    if (payload == null) {
      if ((status == 401 || status == 403) && response.bodyBytes.isNotEmpty) {
        return ApiException('Sunucuya ulaşılamadı. Ağ bağlantınızı kontrol edip tekrar deneyin.', statusCode: status, fromIntermediary: true);
      }
      return ApiException(status >= 500 ? 'Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin.' : 'İşlem başarısız ($status)', statusCode: status);
    }
    final rawCode = payload['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final rawError = payload['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty ? AuthApi.sanitizeServerMessage(rawError.trim()) : null;
    if (status == 401) return SessionExpiredException(code == 'ACCOUNT_DELETED' ? 'Bu hesap silinmiş.' : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    final message = meterErrorMessage(code, serverText: serverText) ?? serverText ?? AuthApi.genericMessageForStatus(status, code: code) ?? 'İşlem başarısız ($status)';
    return ApiException(message, statusCode: status, code: code, payload: payload);
  }

  /// Sayaç hata kodları için düz Türkçe metin; bilinmiyorsa null (sunucunun kendi metni kullanılır).
  static String? meterErrorMessage(String? code, {String? serverText}) => switch (code) {
    'MODULE_DISABLED' => serverText ?? 'Bu özellik bu site için kapalı.',
    'FORBIDDEN_ROLE' => 'Bu işlem için yetkiniz yok. Sayaçları yalnızca site yöneticisi düzenleyebilir.',
    'FORBIDDEN_SITE' => 'Bu siteye erişim yetkiniz yok.',
    'SERIAL_TAKEN' => 'Bu seri numaralı sayaç bu türde zaten kayıtlı.',
    'READING_EXISTS' => 'Bu sayaç için bu tarihte farklı bir okuma zaten var.',
    'READING_OUT_OF_ORDER' => serverText ?? 'Okuma, komşu tarihlerdeki okumalarla tutarsız.',
    'READING_LOCKED' => 'Bu okuma faturalandırılmış bir döneme dahil olduğu için silinemez.',
    'READING_RETAKE_LOCKED' => 'Bu okuma faturalandırılmış bir döneme dahil olduğu için değiştirilemez. Yönetici ile görüşün.',
    'RETAKE_WINDOW' => 'Yeniden çekim yalnızca bugünkü ve dünkü okumalar için yapılabilir. Eski okumayı yönetici düzeltir.',
    kReadingJumpCode => serverText ?? 'Olağan dışı tüketim: bu okuma son dönemlerin çok üzerinde. Değeri kontrol edin; doğruysa onaylayın.',
    'PREVIEW_STALE' => 'Okumalar önizlemeden sonra değişti. Önizlemeyi yenileyip tekrar deneyin.',
    'READINGS_INCOMPLETE' => 'Bazı dairelerin okuması eksik. Eksikleri tamamlayın ya da "eksikleri atla" seçeneğini işaretleyin.',
    'BILLING_OVERLAP' => 'Seçilen tarih aralığı daha önce faturalandırılmış bir aralıkla çakışıyor.',
    'NO_CONSUMPTION' => 'Seçilen aralıkta dağıtılacak tüketim yok.',
    'NOTHING_TO_POST' => 'Borçlandırılacak daire yok.',
    'PERIOD_CLOSED' => 'İlgili finans dönemi kapalı; yeni borç yazılamaz.',
    'IDEMPOTENCY_CONFLICT' => 'Bu işlem farklı bilgilerle daha önce gönderilmiş. Önizlemeyi yenileyin.',
    'METER_NOT_FOUND' => 'Sayaç bulunamadı. Listeyi yenileyin.',
    'APARTMENT_NOT_FOUND' => 'Daire bulunamadı. Listeyi yenileyin.',
    'INVALID_BODY' => serverText ?? 'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.',
    'BODY_TOO_LARGE' => 'Gönderilen içerik çok büyük. Dosyayı parçalara bölün.',
    _ => null,
  };
}

/// Oturum belirtecini [AuthService]'ten alan katman. Ekranlar bunu kullanır (testlerde sahte [MeterApi]).
class MeterService {
  MeterService({required this.authService, MeterApi? api})
    : api = api ?? debugApiFactory?.call(authService) ?? MeterApi(baseUrl: authService.api.baseUrl);

  @visibleForTesting
  static MeterApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final MeterApi api;

  Future<T> _guard<T>(Future<T> Function(String token) call) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) unawaited(authService.refreshSession(force: true));
      rethrow;
    }
  }

  Future<List<MeterApartment>> listApartments(int siteCode) => _guard((t) => api.listApartments(token: t, siteCode: siteCode));
  Future<List<Meter>> listMeters(int siteCode, {MeterKind? kind}) => _guard((t) => api.listMeters(token: t, siteCode: siteCode, kind: kind));
  Future<Meter> createMeter(int siteCode, {required int apartmentId, required MeterKind kind, required String serialNo}) =>
      _guard((t) => api.createMeter(token: t, siteCode: siteCode, apartmentId: apartmentId, kind: kind, serialNo: serialNo));
  Future<Meter> updateMeter(int siteCode, int meterId, {String? serialNo, bool? isActive}) =>
      _guard((t) => api.updateMeter(token: t, siteCode: siteCode, meterId: meterId, serialNo: serialNo, isActive: isActive));
  Future<List<MeterReading>> listReadings(int siteCode, int meterId) => _guard((t) => api.listReadings(token: t, siteCode: siteCode, meterId: meterId));
  Future<void> addReading(int siteCode, int meterId, {required String date, required String value}) =>
      _guard((t) => api.addReading(token: t, siteCode: siteCode, meterId: meterId, date: date, value: value));
  Future<List<FieldMeter>> listFieldMeters(int siteCode, {MeterKind? kind, String? date}) =>
      _guard((t) => api.listFieldMeters(token: t, siteCode: siteCode, kind: kind, date: date));
  Future<FieldReadingResult> postFieldReading(
    int siteCode, {
    required int meterId,
    required String date,
    required String value,
    String? photoBase64,
    bool? confirmJump,
    bool replace = false,
  }) => _guard(
    (t) => api.postFieldReading(token: t, siteCode: siteCode, meterId: meterId, date: date, value: value, photoBase64: photoBase64, confirmJump: confirmJump, replace: replace),
  );
  Future<void> deleteReading(int siteCode, int meterId, int readingId) =>
      _guard((t) => api.deleteReading(token: t, siteCode: siteCode, meterId: meterId, readingId: readingId));
  Future<MeterImportResult> importReadings(
    int siteCode, {
    required MeterKind kind,
    required String readingDate,
    required List<Map<String, dynamic>> rows,
    required bool dryRun,
  }) => _guard((t) => api.importReadings(token: t, siteCode: siteCode, kind: kind, readingDate: readingDate, rows: rows, dryRun: dryRun));
  Future<BillingPreview> previewBilling(int siteCode, Map<String, dynamic> input) =>
      _guard((t) => api.previewBilling(token: t, siteCode: siteCode, input: input));
  Future<MeterBilling> postBilling(int siteCode, Map<String, dynamic> input) => _guard((t) => api.postBilling(token: t, siteCode: siteCode, input: input));
  Future<List<MeterBilling>> listBillings(int siteCode) => _guard((t) => api.listBillings(token: t, siteCode: siteCode));
}
