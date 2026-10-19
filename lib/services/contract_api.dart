// Firma ve Sözleşme Takibi (`contracts`) uçları.
//
// [ContractApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [ContractService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (diğer modül uçlarıyla aynı):
// - Mutasyonlar (POST/PATCH) ASLA otomatik yeniden denenmez; çift işlem riski. Yeniden deneme kullanıcı kararıdır.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive
//   portal) geçici ağ hatasıdır.
// - Firma adı, yetkili, telefon, e-posta, not, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Firma listesi süzgeci (`active`).
enum ContractVendorFilter {
  all('all'),
  active('1'),
  passive('0');

  const ContractVendorFilter(this.apiValue);

  final String apiValue;
}

class ContractApi {
  ContractApi({
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

  static String _vendorsPath(int siteCode, [String tail = '']) =>
      '/manager/sites/$siteCode/contract-vendors${tail.isEmpty ? '' : '/$tail'}';

  static String _contractsPath(int siteCode, [String tail = '']) =>
      '/manager/sites/$siteCode/contracts${tail.isEmpty ? '' : '/$tail'}';

  // --- Firmalar -----------------------------------------------------------------------------

  /// `GET .../contract-vendors?active=all|1|0&q=` -> `{items}`.
  Future<List<ContractVendor>> listVendors({
    required String token,
    required int siteCode,
    ContractVendorFilter active = ContractVendorFilter.all,
    String? query,
  }) async {
    final trimmed = query?.trim();
    final response = await _send(
      'GET',
      _vendorsPath(siteCode),
      token: token,
      query: <String, String>{
        'active': active.apiValue,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
      },
      timeout: _readTimeout,
    );
    return ContractVendor.listFrom(_object(response));
  }

  /// `POST .../contract-vendors` -> 201 `{vendor}`.
  Future<ContractVendor> createVendor({
    required String token,
    required int siteCode,
    required ContractVendorDraft draft,
  }) async {
    final response = await _send(
      'POST',
      _vendorsPath(siteCode),
      token: token,
      body: draft.toCreateJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _vendor(response);
  }

  /// `PATCH .../contract-vendors/:id` (değişen alanlar ve/veya `is_active`) -> `{vendor}`.
  Future<ContractVendor> updateVendor({
    required String token,
    required int siteCode,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await _send(
      'PATCH',
      _vendorsPath(siteCode, '$id'),
      token: token,
      body: body,
      timeout: _writeTimeout,
    );
    return _vendor(response);
  }

  // --- Sözleşmeler --------------------------------------------------------------------------

  /// `GET .../contracts?state=&vendor_id=&category=&q=&cursor=&limit=` -> `{items, next_cursor}`. Sonraki sayfa
  /// önceki yanıtın `next_cursor`ı ile istenir (`before_id` GÖNDERİLMEZ: sunucu 400 döner).
  Future<ContractPage> listContracts({
    required String token,
    required int siteCode,
    String state = 'all',
    int? vendorId,
    String? category,
    String? query,
    String? cursor,
    int limit = 30,
  }) async {
    final trimmed = query?.trim();
    final response = await _send(
      'GET',
      _contractsPath(siteCode),
      token: token,
      query: <String, String>{
        'state': state.isEmpty ? 'all' : state,
        if (vendorId != null) 'vendor_id': '$vendorId',
        if (category != null && category.isNotEmpty) 'category': category,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
      timeout: _readTimeout,
    );
    return ContractPage.fromJson(_object(response));
  }

  /// `GET .../contracts/summary` -> `{active, expiring_soon, expired, terminated}`.
  Future<ContractSummary> summary({
    required String token,
    required int siteCode,
  }) async {
    final response = await _send(
      'GET',
      _contractsPath(siteCode, 'summary'),
      token: token,
      timeout: _readTimeout,
    );
    return ContractSummary.fromJson(_object(response));
  }

  /// `GET .../contracts/:id` -> Contract.
  Future<Contract> getContract({
    required String token,
    required int siteCode,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      _contractsPath(siteCode, '$id'),
      token: token,
      timeout: _readTimeout,
    );
    return _contract(response);
  }

  /// `POST .../contracts` -> 201 Contract.
  Future<Contract> createContract({
    required String token,
    required int siteCode,
    required ContractDraft draft,
  }) async {
    final response = await _send(
      'POST',
      _contractsPath(siteCode),
      token: token,
      body: draft.toCreateJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _contract(response);
  }

  /// `PATCH .../contracts/:id` (değişen alanlar ve/veya `status: feshedildi|aktif`) -> Contract.
  Future<Contract> updateContract({
    required String token,
    required int siteCode,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await _send(
      'PATCH',
      _contractsPath(siteCode, '$id'),
      token: token,
      body: body,
      timeout: _writeTimeout,
    );
    return _contract(response);
  }

  ContractVendor _vendor(http.Response response) {
    final vendor = ContractVendor.fromJson(_object(response));
    if (vendor.id <= 0) throw _unexpected(response);
    return vendor;
  }

  Contract _contract(http.Response response) {
    final contract = Contract.fromJson(_object(response));
    if (contract.id <= 0) throw _unexpected(response);
    return contract;
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
      // SocketException, TlsException, ... (ayrıntı kullanıcıya gösterilmez).
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
          contractErrorMessage('BODY_TOO_LARGE')!,
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

    final mapped = contractErrorMessage(
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

  /// Sözleşme / firma alan adlarının Türkçe etiketi (`INVALID_FIELD {field}`); bilinmeyen alanda null.
  static String? fieldLabel(Object? field) => switch (field?.toString().trim()) {
    'name' => 'Firma adı',
    'category' => 'Kategori',
    'contact_name' => 'Yetkili kişi',
    'phone' => 'Telefon',
    'email' => 'E-posta',
    'tax_no' => 'Vergi numarası',
    'note' => 'Not',
    'is_active' => 'Firma durumu',
    'vendor_id' => 'Firma',
    'title' => 'Sözleşme başlığı',
    'start_date' => 'Başlangıç tarihi',
    'end_date' => 'Bitiş tarihi',
    'notice_days' => 'Fesih bildirim süresi',
    'remind_before_days' => 'Hatırlatma süresi',
    'amount' => 'Tutar',
    'currency' => 'Para birimi',
    'period' => 'Ödeme dönemi',
    'auto_renew' => 'Otomatik yenileme',
    'status' => 'Sözleşme durumu',
    _ => null,
  };

  /// Firma ve Sözleşme Takibi hata kodları için düz Türkçe metin; bilinmiyorsa genel kodlar
  /// ([AuthApi.messageForErrorCode]) ya da null (sunucunun kendi `error` metni kullanılır).
  static String? contractErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
    String? serverText,
  }) {
    if (code == null) return null;
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Firma ve sözleşme takibi bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok. Sözleşmeleri yalnızca site yöneticisi düzenleyebilir.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'CONTRACT_NOT_FOUND':
        return 'Sözleşme bulunamadı ya da erişiminiz yok. Listeyi yenileyin.';
      case 'VENDOR_NOT_FOUND':
        return 'Firma bulunamadı ya da erişiminiz yok. Listeyi yenileyin.';
      case 'VENDOR_NAME_TAKEN':
        return 'Bu adla kayıtlı bir firma zaten var. Farklı bir ad girin ya da mevcut firmayı kullanın.';
      case 'VENDOR_INACTIVE':
        return 'Seçilen firma pasif. Başka bir firma seçin ya da firmayı Firmalar sekmesinden etkinleştirin.';
      case 'LIMIT_REACHED':
        // Sunucu metni sınırı söyler ("Bir sitede en fazla 500 firma kaydedilebilir.").
        return serverText ?? 'Bu site için kayıt sınırına ulaşıldı.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'INVALID_SITE_CODE':
        return 'Site geçersiz. Siteyi yeniden seçin.';
      case 'INVALID_FIELD':
        // Sorgu parametresi hatası (liste süzgeci / sayfa imleci): kullanıcıya yapılacak iş söylenir.
        final field = payload?['field']?.toString();
        if (field == 'cursor') {
          return 'Sayfa bilgisi geçersiz. Listeyi yenileyip tekrar deneyin.';
        }
        if (field == 'state' || field == 'active' || field == 'limit') {
          return 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.';
        }
        // Sunucunun alan metni Türkçe ve özeldir ("Bitiş tarihi başlangıç tarihinden önce olamaz."); yoksa alan etiketi.
        if (serverText != null) return serverText;
        final label = fieldLabel(payload?['field']);
        if (label == null) {
          return 'Girilen bilgilerden biri geçersiz. Alanları kontrol edip tekrar deneyin.';
        }
        return '"$label" alanı geçersiz. Kontrol edip tekrar deneyin.';
      case 'INVALID_BODY':
        return serverText ??
            'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.';
      case 'INVALID_QUERY':
        return 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.';
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

/// Oturum belirtecini [AuthService]'ten alan ve oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar bunu
/// kullanır (testlerde sahte [ContractService] kurulur).
class ContractService {
  ContractService({required this.authService, ContractApi? api})
    : api =
          api ??
          debugApiFactory?.call(authService) ??
          ContractApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [ContractApi] vermek için.
  @visibleForTesting
  static ContractApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final ContractApi api;

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

  Future<List<ContractVendor>> listVendors(
    int siteCode, {
    ContractVendorFilter active = ContractVendorFilter.all,
    String? query,
  }) => _guard(
    (token) => api.listVendors(
      token: token,
      siteCode: siteCode,
      active: active,
      query: query,
    ),
  );

  Future<ContractVendor> createVendor(int siteCode, ContractVendorDraft draft) =>
      _guard(
        (token) =>
            api.createVendor(token: token, siteCode: siteCode, draft: draft),
      );

  Future<ContractVendor> updateVendor(
    int siteCode,
    int id,
    Map<String, dynamic> body,
  ) => _guard(
    (token) =>
        api.updateVendor(token: token, siteCode: siteCode, id: id, body: body),
  );

  /// Firmayı pasife alır ya da etkinleştirir (`PATCH {is_active}`).
  Future<ContractVendor> setVendorActive(int siteCode, int id, bool active) =>
      updateVendor(siteCode, id, <String, dynamic>{'is_active': active});

  Future<ContractPage> listContracts(
    int siteCode, {
    String state = 'all',
    int? vendorId,
    String? category,
    String? query,
    String? cursor,
    int limit = 30,
  }) => _guard(
    (token) => api.listContracts(
      token: token,
      siteCode: siteCode,
      state: state,
      vendorId: vendorId,
      category: category,
      query: query,
      cursor: cursor,
      limit: limit,
    ),
  );

  Future<ContractSummary> summary(int siteCode) =>
      _guard((token) => api.summary(token: token, siteCode: siteCode));

  Future<Contract> getContract(int siteCode, int id) =>
      _guard((token) => api.getContract(token: token, siteCode: siteCode, id: id));

  Future<Contract> createContract(int siteCode, ContractDraft draft) => _guard(
    (token) =>
        api.createContract(token: token, siteCode: siteCode, draft: draft),
  );

  Future<Contract> updateContract(
    int siteCode,
    int id,
    Map<String, dynamic> body,
  ) => _guard(
    (token) => api.updateContract(
      token: token,
      siteCode: siteCode,
      id: id,
      body: body,
    ),
  );

  /// Sözleşmeyi feshedilmiş (`feshedildi`) ya da yeniden yürürlükte (`aktif`) işaretler.
  Future<Contract> setContractStatus(
    int siteCode,
    int id,
    ContractStatus status,
  ) => updateContract(siteCode, id, <String, dynamic>{'status': status.apiValue});
}
