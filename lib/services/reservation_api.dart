// Rezervasyon ve Konsiyerj uçları: docs/PLATFORM_REZERVASYON.md.
//
// [ReservationApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [ReservationService]: oturum belirtecini [AuthService]'ten alır, oturum hatasını merkezi çıkışa bağlar ve yazan
// uçların `idempotency_key` değerini oturum boyu saklar.
//
// Kurallar (WorkTrackingApi / DocumentApi ile aynı):
// - Mutasyonlar (POST/PATCH) ASLA otomatik yeniden denenmez; çift işlem riski. Yeniden deneme kullanıcı kararıdır
//   ve rezervasyon / talep açmada `idempotency_key` ile güvenlidir.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive
//   portal) geçici ağ hatasıdır.
// - Not, gerekçe, talep metni, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';

class ReservationApi {
  ReservationApi({
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

  static String _managerPath(int siteCode, String tail) =>
      '/manager/sites/$siteCode/$tail';

  // --- Sakin: alanlar ve rezervasyon --------------------------------------------------------

  /// `GET /app/reservation-areas` (yalnız aktif alanlar).
  Future<List<ReservationArea>> listAreas({
    required String token,
    int? siteCode,
  }) async {
    final response = await _send(
      'GET',
      '/app/reservation-areas',
      token: token,
      query: <String, String>{if (siteCode != null) 'site_code': '$siteCode'},
      timeout: _readTimeout,
    );
    return ReservationArea.listFrom(_object(response)['items']);
  }

  /// `GET /app/reservation-areas/:id/availability`. [from] / [to]: "YYYY-MM-DD" (en çok 14 gün).
  Future<ReservationAvailability> availability({
    required String token,
    required int areaId,
    String? from,
    String? to,
  }) async {
    final response = await _send(
      'GET',
      '/app/reservation-areas/$areaId/availability',
      token: token,
      query: <String, String>{
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
      timeout: _readTimeout,
    );
    return ReservationAvailability.fromJson(_object(response));
  }

  /// `POST /app/reservations` (201).
  Future<ReservationCreateResult> createReservation({
    required String token,
    required ReservationCreateRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/app/reservations',
      token: token,
      body: request.toJson(idempotencyKey),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    final result = ReservationCreateResult.fromJson(_object(response));
    if (result.reservation.id <= 0) throw _unexpected(response);
    return result;
  }

  /// `GET /app/reservations`. [scope]: `upcoming|past|all`.
  Future<ReservationPage> listMine({
    required String token,
    int? siteCode,
    String scope = 'all',
    int limit = 30,
    int? beforeId,
  }) async {
    final response = await _send(
      'GET',
      '/app/reservations',
      token: token,
      query: <String, String>{
        if (siteCode != null) 'site_code': '$siteCode',
        'scope': scope,
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return ReservationPage.fromJson(_object(response));
  }

  /// `GET /app/reservations/:id`.
  Future<ReservationRecord> getMine({
    required String token,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      '/app/reservations/$id',
      token: token,
      timeout: _readTimeout,
    );
    return _reservation(response);
  }

  /// `POST /app/reservations/:id/cancel` -> `{ reservation }`.
  Future<ReservationRecord> cancelMine({
    required String token,
    required int id,
  }) async {
    final response = await _send(
      'POST',
      '/app/reservations/$id/cancel',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
    return _reservation(response);
  }

  /// `POST /app/reservations/:id/seen` -> `{ id, unread:false }` (idempotent).
  Future<void> markMineSeen({required String token, required int id}) async {
    await _send(
      'POST',
      '/app/reservations/$id/seen',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
  }

  // --- Sakin: konsiyerj ---------------------------------------------------------------------

  /// `GET /app/concierge-requests`. [status]: `open|closed|all`.
  Future<ConciergePage> listMyRequests({
    required String token,
    int? siteCode,
    String status = 'all',
    int limit = 30,
    int? beforeId,
  }) async {
    final response = await _send(
      'GET',
      '/app/concierge-requests',
      token: token,
      query: <String, String>{
        if (siteCode != null) 'site_code': '$siteCode',
        'status': status,
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return ConciergePage.fromJson(_object(response));
  }

  /// `POST /app/concierge-requests` (201).
  Future<ConciergeCreateResult> createRequest({
    required String token,
    required ConciergeCreateRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/app/concierge-requests',
      token: token,
      body: request.toJson(idempotencyKey),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    final result = ConciergeCreateResult.fromJson(_object(response));
    if (result.request.id <= 0) throw _unexpected(response);
    return result;
  }

  /// `POST /app/concierge-requests/:id/cancel` -> `{ request }` (yalnız `yeni`).
  Future<ConciergeRecord> cancelMyRequest({
    required String token,
    required int id,
  }) async {
    final response = await _send(
      'POST',
      '/app/concierge-requests/$id/cancel',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
    return _concierge(response);
  }

  /// `GET /app/concierge-requests/:id` -> `{ request }` (`unread` dahil; yazmaz).
  Future<ConciergeRecord> getMyRequest({
    required String token,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      '/app/concierge-requests/$id',
      token: token,
      timeout: _readTimeout,
    );
    return _concierge(response);
  }

  /// `POST /app/concierge-requests/:id/seen` -> `{ id, unread:false }` (idempotent).
  Future<void> markMyRequestSeen({required String token, required int id}) async {
    await _send(
      'POST',
      '/app/concierge-requests/$id/seen',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
  }

  // --- Yönetim: alanlar ---------------------------------------------------------------------

  /// `GET /manager/sites/:siteCode/reservation-areas` (pasifler dahil).
  Future<ReservationAreaList> listManagedAreas({
    required String token,
    required int siteCode,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'reservation-areas'),
      token: token,
      timeout: _readTimeout,
    );
    return ReservationAreaList.fromJson(_object(response));
  }

  /// `POST .../reservation-areas` (201): [fields] sözleşmedeki alan gövdesidir.
  Future<ReservationArea> createArea({
    required String token,
    required int siteCode,
    required Map<String, Object?> fields,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode, 'reservation-areas'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _area(response);
  }

  /// `PATCH .../reservation-areas/:id`: yalnız [fields] içindekiler gönderilir.
  Future<ReservationArea> updateArea({
    required String token,
    required int siteCode,
    required int id,
    required Map<String, Object?> fields,
  }) async {
    final response = await _send(
      'PATCH',
      _managerPath(siteCode, 'reservation-areas/$id'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      timeout: _writeTimeout,
    );
    return _area(response);
  }

  // --- Yönetim: takvim ve kararlar ----------------------------------------------------------

  /// `GET .../reservations`. [status]: virgüllü durumlar; null = hepsi. [from] / [to]: "YYYY-MM-DD".
  Future<ReservationPage> listManaged({
    required String token,
    required int siteCode,
    int? areaId,
    String? status,
    String? from,
    String? to,
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'reservations'),
      token: token,
      query: <String, String>{
        if (areaId != null) 'area_id': '$areaId',
        if (status != null && status.isNotEmpty) 'status': status,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
      timeout: _readTimeout,
    );
    return ReservationPage.fromJson(_object(response));
  }

  /// `GET .../reservations/:id`.
  Future<ReservationRecord> getManaged({
    required String token,
    required int siteCode,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'reservations/$id'),
      token: token,
      timeout: _readTimeout,
    );
    return _reservation(response);
  }

  /// `POST .../reservations/:id/decision`. [action]: `approve|reject|cancel`; reject / cancel için [note] zorunlu.
  Future<ReservationDecisionResult> decide({
    required String token,
    required int siteCode,
    required int id,
    required String action,
    String? note,
  }) async {
    final trimmed = note?.trim() ?? '';
    final response = await _send(
      'POST',
      _managerPath(siteCode, 'reservations/$id/decision'),
      token: token,
      body: <String, dynamic>{
        'action': action,
        if (trimmed.isNotEmpty) 'note': trimmed,
      },
      timeout: _writeTimeout,
    );
    final result = ReservationDecisionResult.fromJson(_object(response));
    if (result.reservation.id <= 0) throw _unexpected(response);
    return result;
  }

  // --- Yönetim: konsiyerj -------------------------------------------------------------------

  /// `GET .../concierge-requests`. [status]: `open|closed|all` ya da virgüllü durumlar.
  Future<ConciergePage> listManagedRequests({
    required String token,
    required int siteCode,
    String? status,
    String? category,
    int limit = 30,
    int? beforeId,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'concierge-requests'),
      token: token,
      query: <String, String>{
        if (status != null && status.isNotEmpty) 'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return ConciergePage.fromJson(_object(response));
  }

  /// `GET .../concierge-requests/:id`.
  Future<ConciergeDetail> getManagedRequest({
    required String token,
    required int siteCode,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'concierge-requests/$id'),
      token: token,
      timeout: _readTimeout,
    );
    return _conciergeDetail(response);
  }

  /// `PATCH .../concierge-requests/:id`: [fields] `status` ve / veya `note` (sakine görünür kısa not; `null` siler).
  Future<ConciergeDetail> updateManagedRequest({
    required String token,
    required int siteCode,
    required int id,
    required Map<String, Object?> fields,
  }) async {
    final response = await _send(
      'PATCH',
      _managerPath(siteCode, 'concierge-requests/$id'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      timeout: _writeTimeout,
    );
    return _conciergeDetail(response);
  }

  // --- Gövde yardımcıları -------------------------------------------------------------------

  ReservationRecord _reservation(http.Response response) {
    final record = ReservationRecord.fromJson(_object(response));
    if (record.id <= 0) throw _unexpected(response);
    return record;
  }

  ConciergeRecord _concierge(http.Response response) {
    final record = ConciergeRecord.fromJson(_object(response));
    if (record.id <= 0) throw _unexpected(response);
    return record;
  }

  ConciergeDetail _conciergeDetail(http.Response response) {
    final detail = ConciergeDetail.fromJson(_object(response));
    if (detail.request.id <= 0) throw _unexpected(response);
    return detail;
  }

  ReservationArea _area(http.Response response) {
    final area = ReservationArea.fromJson(_object(response));
    if (area.id <= 0) throw _unexpected(response);
    return area;
  }

  ApiException _unexpected(http.Response response) => ApiException(
    'Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin.',
    statusCode: response.statusCode,
  );

  // --- JSON taşıma katmanı ------------------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? query]) {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
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
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        method == 'GET'
            ? 'Sunucu yanıt vermedi, tekrar deneyin.'
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; ekranı yenileyip kontrol edin.',
      );
    } on http.ClientException {
      throw ApiException(_transportMessage);
    } on Exception {
      // SocketException, TlsException, ... (ayrıntı kullanıcıya gösterilmez). Programlama hataları (Error)
      // bilerek yakalanmaz.
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

  static const String _transportMessage =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  // --- Hata çevirisi ------------------------------------------------------------------------

  ApiException _failure(http.Response response) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
      if (status == 413) {
        return ApiException(
          reservationErrorMessage('BODY_TOO_LARGE')!,
          statusCode: 413,
          code: 'BODY_TOO_LARGE',
        );
      }
      if ((status == 401 || status == 403) && !empty) {
        // JSON olmayan 401/403: proxy / WAF / captive portal; oturum sonu DEĞİL.
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
    final code = rawCode is String && rawCode.trim().isNotEmpty
        ? rawCode.trim()
        : null;
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

    final mapped = reservationErrorMessage(
      code,
      retryAfterSeconds: retryAfter,
      payload: body,
      serverText: serverText,
    );
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    final fallback = mapped == null && serverText == null && generic == null;
    var message =
        mapped ?? serverText ?? generic ?? 'İşlem başarısız ($status)';
    if (status == 429 && mapped == null) {
      message = _withRetryHint(message, retryAfter);
    }
    if (status >= 500) {
      final errorId = body['errorId'] ?? body['error_id'];
      if (errorId is String && errorId.isNotEmpty) {
        message = '$message (Hata kodu: $errorId)';
      }
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

  static int? _payloadInt(Map<String, dynamic>? payload, String key) {
    final value = payload?[key];
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Rezervasyon ve Konsiyerj hata kodları için düz Türkçe metin (sözleşme "Hata kodları"); bilinmiyorsa genel
  /// kodlar ([AuthApi.messageForErrorCode]) ya da null (sunucunun kendi `error` metni kullanılır). `INVALID_BODY` /
  /// `INVALID_LOCATION` sunucunun alan etiketli metnini taşır ([serverText]). Sınırlar yanıt gövdesinden okunur.
  static String? reservationErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
    String? serverText,
  }) {
    if (code == null) return null;
    String wait(String base) => retryAfterSeconds == null
        ? '$base Biraz sonra tekrar deneyin.'
        : '$base ${AuthApi.formatWait(retryAfterSeconds)} sonra tekrar deneyin.';
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Rezervasyon ve Konsiyerj bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'NOT_A_RESIDENT':
        return 'Rezervasyon ve talep için sitede aktif daire sakini olmalısınız.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'AREA_NOT_FOUND':
        return 'Alan bulunamadı ya da artık kullanılamıyor. Listeyi yenileyin.';
      case 'RESERVATION_NOT_FOUND':
        return 'Rezervasyon bulunamadı ya da erişiminiz yok.';
      case 'CONCIERGE_NOT_FOUND':
        return 'Talep bulunamadı ya da erişiminiz yok.';
      case 'INVALID_SITE_CODE':
        return 'Site geçersiz. Siteyi yeniden seçin.';
      case 'INVALID_LOCATION':
        return serverText ?? 'Daire bilgisi geçersiz. Seçimi kontrol edin.';
      case 'INVALID_BODY':
        return serverText ??
            'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.';
      case 'INVALID_QUERY':
        return 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.';
      case 'AREA_NAME_TAKEN':
        return 'Bu sitede aynı adlı bir alan zaten var. Başka bir ad seçin.';
      case 'AREA_LIMIT':
        final areaLimit = _payloadInt(payload, 'area_limit') ?? 50;
        return 'Sitede en çok $areaLimit alan tanımlanabilir.';
      case 'AREA_INACTIVE':
        return 'Bu alan şu anda rezervasyona kapalı.';
      case 'OUTSIDE_BOOKING_WINDOW':
        final days = _payloadInt(payload, 'max_days_ahead');
        return days == null
            ? 'Rezervasyon yalnızca şimdiden sonrası ve izin verilen gün sayısı içinde yapılabilir.'
            : 'Rezervasyon yalnızca şimdiden sonrası ve en çok $days gün sonrası için yapılabilir.';
      case 'OUTSIDE_OPEN_HOURS':
        return 'Seçilen saat alanın açık saatlerine uymuyor. Boş saatleri yenileyip başka bir saat seçin.';
      case 'INVALID_SLOT_COUNT':
        final min = _payloadInt(payload, 'min_slots');
        final max = _payloadInt(payload, 'max_slots');
        return min == null || max == null
            ? 'Seçilen süre bu alan için uygun değil.'
            : 'Rezervasyon en az $min, en çok $max dilim olabilir.';
      case 'SLOT_FULL':
        return 'Seçtiğiniz saat bu arada doldu. Boş saatleri yenileyip başka bir saat seçin.';
      case 'ALREADY_BOOKED':
        return 'Bu alanda aynı saatlerde zaten rezervasyonunuz var.';
      case 'RESERVATION_DAILY_LIMIT':
        final daily = _payloadInt(payload, 'daily_limit');
        return daily == null
            ? 'Bu alanda aynı gün için günlük rezervasyon sınırına ulaştınız.'
            : 'Bu alanda aynı gün için en çok $daily rezervasyon yapabilirsiniz.';
      case 'RESERVATION_WEEKLY_LIMIT':
        final weekly = _payloadInt(payload, 'weekly_limit');
        return weekly == null
            ? 'Bu alanda aynı hafta için haftalık rezervasyon sınırına ulaştınız.'
            : 'Bu alanda aynı hafta için en çok $weekly rezervasyon yapabilirsiniz.';
      case 'RESERVATION_USER_LIMIT':
        final active = _payloadInt(payload, 'active_limit');
        return active == null
            ? 'Bu sitede aynı anda geçerli rezervasyon sınırına ulaştınız.'
            : 'Bu sitede aynı anda en çok $active geçerli rezervasyonunuz olabilir.';
      case 'RESERVATION_SITE_LIMIT':
        return 'Sitede geçerli rezervasyon üst sınırına ulaşıldı. Yönetimle iletişime geçin.';
      case 'CANCEL_WINDOW_CLOSED':
        final hours = _payloadInt(payload, 'cancel_cutoff_hours');
        return hours == null || hours <= 0
            ? 'İptal süresi doldu. Yönetimle iletişime geçin.'
            : 'Başlangıca $hours saatten az kaldığı için iptal edilemez. Yönetimle iletişime geçin.';
      case 'RESERVATION_PAST':
        return 'Başlangıç zamanı geçmiş rezervasyon onaylanamaz.';
      case 'INVALID_TRANSITION':
        return 'Kayıt bu durumdan istenen duruma geçirilemez. Başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin.';
      case 'CONCIERGE_CLOSED':
        return 'Tamamlanmış ya da iptal edilmiş talepte değişiklik yapılamaz.';
      case 'CONCIERGE_USER_LIMIT':
        final openLimit = _payloadInt(payload, 'user_open_limit');
        return openLimit == null
            ? 'Açık talep sınırına ulaştınız. Önce mevcut taleplerinizin sonuçlanmasını bekleyin.'
            : 'Bu sitede aynı anda en çok $openLimit açık talebiniz olabilir. Önce mevcut taleplerinizin sonuçlanmasını bekleyin.';
      case 'CONCIERGE_SITE_LIMIT':
        return 'Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin.';
      case 'IDEMPOTENCY_CONFLICT':
        return 'Bu işlem daha önce başka bilgilerle gönderilmiş. Lütfen bilgileri kontrol edip tekrar deneyin.';
      case 'RESERVATION_RATE_LIMITED':
        return wait('Bir saat içinde çok fazla rezervasyon yaptınız.');
      case 'CONCIERGE_RATE_LIMITED':
        return wait('Bir saat içinde çok fazla talep açtınız.');
      case 'BODY_TOO_LARGE':
        return 'Gönderilen içerik çok büyük. Metni kısaltın.';
    }
    return AuthApi.messageForErrorCode(
      code,
      retryAfterSeconds: retryAfterSeconds,
      payload: payload,
    );
  }

  static String _withRetryHint(String base, int? retryAfter) {
    if (retryAfter == null) return base;
    if (base.toLowerCase().contains('sonra')) return base;
    final trimmed = base.endsWith('.') ? base : '$base.';
    return '$trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin.';
  }

  static int? _retryAfterSeconds(
    http.Response response,
    Map<String, dynamic>? payload,
  ) {
    final body =
        payload?['retry_after_seconds'] ?? payload?['retryAfterSeconds'];
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

  // --- Gövde çözümleme ----------------------------------------------------------------------

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map<String, dynamic>
          ? raw
          : (raw is Map ? Map<String, dynamic>.from(raw) : null);
    } on FormatException {
      return null;
    }
  }

  /// Başarılı yanıt gövdesi JSON nesnesi olmak ZORUNDA (yoksa kullanıcıya anlaşılır hata).
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
}

/// Oturum belirtecini [AuthService]'ten alan, oturum hatalarını merkezi çıkışa bağlayan ve yazan uçların
/// `idempotency_key` değerini oturum boyu saklayan katman. Ekranlar bunu kullanır (testlerde sahte
/// [ReservationService] kurulur).
class ReservationService {
  ReservationService({required this.authService, ReservationApi? api})
    : api =
          api ??
          debugApiFactory?.call(authService) ??
          ReservationApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [ReservationApi] vermek için.
  @visibleForTesting
  static ReservationApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final ReservationApi api;

  /// Oturum boyu anahtar haritası: imza (veri) aynıysa AYNI anahtar, veri değişince YENİ anahtar. Yanıtı kaybolan
  /// gönderim, pencere kapatılıp açılsa bile çift kayıt yaratmaz; başarıda (ve sunucu anahtarı reddedince) anahtar
  /// atılır.
  IdempotencyKeys get _keys => sessionIdempotencyKeys(authService, 'rz');

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

  Future<T> _idempotent<T>(
    String signature,
    Future<T> Function(String token, String key) call,
  ) async {
    final key = _keys.keyFor(signature);
    try {
      final result = await _guard((token) => call(token, key));
      _keys.clear(signature);
      return result;
    } on ApiException catch (e) {
      if (e.code == 'IDEMPOTENCY_CONFLICT') _keys.clear(signature);
      rethrow;
    }
  }

  // --- Sakin ---

  Future<List<ReservationArea>> listAreas({int? siteCode}) =>
      _guard((token) => api.listAreas(token: token, siteCode: siteCode));

  Future<ReservationAvailability> availability(
    int areaId, {
    String? from,
    String? to,
  }) => _guard(
    (token) => api.availability(token: token, areaId: areaId, from: from, to: to),
  );

  Future<ReservationCreateResult> createReservation(
    ReservationCreateRequest request,
  ) => _idempotent(
    'reservation|${request.signature}',
    (token, key) => api.createReservation(
      token: token,
      request: request,
      idempotencyKey: key,
    ),
  );

  Future<ReservationPage> listMine({
    int? siteCode,
    String scope = 'all',
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listMine(
      token: token,
      siteCode: siteCode,
      scope: scope,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<ReservationRecord> getMine(int id) =>
      _guard((token) => api.getMine(token: token, id: id));

  Future<ReservationRecord> cancelMine(int id) =>
      _guard((token) => api.cancelMine(token: token, id: id));

  Future<void> markMineSeen(int id) =>
      _guard((token) => api.markMineSeen(token: token, id: id));

  Future<ConciergePage> listMyRequests({
    int? siteCode,
    String status = 'all',
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listMyRequests(
      token: token,
      siteCode: siteCode,
      status: status,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<ConciergeCreateResult> createRequest(ConciergeCreateRequest request) =>
      _idempotent(
        'concierge|${request.signature}',
        (token, key) => api.createRequest(
          token: token,
          request: request,
          idempotencyKey: key,
        ),
      );

  Future<ConciergeRecord> cancelMyRequest(int id) =>
      _guard((token) => api.cancelMyRequest(token: token, id: id));

  Future<ConciergeRecord> getMyRequest(int id) =>
      _guard((token) => api.getMyRequest(token: token, id: id));

  Future<void> markMyRequestSeen(int id) =>
      _guard((token) => api.markMyRequestSeen(token: token, id: id));

  /// Sekme rozetleri için okunmamış sayıları: iki hafif liste isteği (`limit=1`, tüm kapsam / durum; [siteCode]
  /// verilirse o site) paralel atılır ve yalnız `unread_count` okunur. Eski sunucu (alan yok) 0 verir.
  Future<ReservationUnreadCounts> unreadCounts({int? siteCode}) async {
    final (reservations, concierge) = await (
      listMine(siteCode: siteCode, scope: 'all', limit: 1),
      listMyRequests(siteCode: siteCode, status: 'all', limit: 1),
    ).wait;
    return (
      reservations: reservations.unreadCount,
      concierge: concierge.unreadCount,
    );
  }

  // --- Yönetim ---

  Future<ReservationAreaList> listManagedAreas(int siteCode) => _guard(
    (token) => api.listManagedAreas(token: token, siteCode: siteCode),
  );

  Future<ReservationArea> createArea(
    int siteCode,
    Map<String, Object?> fields,
  ) => _guard(
    (token) => api.createArea(token: token, siteCode: siteCode, fields: fields),
  );

  Future<ReservationArea> updateArea(
    int siteCode,
    int id,
    Map<String, Object?> fields,
  ) => _guard(
    (token) => api.updateArea(
      token: token,
      siteCode: siteCode,
      id: id,
      fields: fields,
    ),
  );

  Future<ReservationPage> listManaged(
    int siteCode, {
    int? areaId,
    String? status,
    String? from,
    String? to,
    String? cursor,
    int limit = 30,
  }) => _guard(
    (token) => api.listManaged(
      token: token,
      siteCode: siteCode,
      areaId: areaId,
      status: status,
      from: from,
      to: to,
      cursor: cursor,
      limit: limit,
    ),
  );

  Future<ReservationRecord> getManaged(int siteCode, int id) => _guard(
    (token) => api.getManaged(token: token, siteCode: siteCode, id: id),
  );

  Future<ReservationDecisionResult> decide(
    int siteCode,
    int id, {
    required String action,
    String? note,
  }) => _guard(
    (token) => api.decide(
      token: token,
      siteCode: siteCode,
      id: id,
      action: action,
      note: note,
    ),
  );

  Future<ConciergePage> listManagedRequests(
    int siteCode, {
    String? status,
    String? category,
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listManagedRequests(
      token: token,
      siteCode: siteCode,
      status: status,
      category: category,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<ConciergeDetail> getManagedRequest(int siteCode, int id) => _guard(
    (token) => api.getManagedRequest(token: token, siteCode: siteCode, id: id),
  );

  Future<ConciergeDetail> updateManagedRequest(
    int siteCode,
    int id,
    Map<String, Object?> fields,
  ) => _guard(
    (token) => api.updateManagedRequest(
      token: token,
      siteCode: siteCode,
      id: id,
      fields: fields,
    ),
  );
}
