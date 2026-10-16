// Hesap, gizlilik ve platform yönetimi uçları (docs/PLATFORM_SATISA_HAZIRLIK.md §1.2, §1.3, §1.5, §1.6).
//
// [AccountApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [AccountService]: oturum belirtecini [AuthService]'ten alır, oturum hatasını merkezi çıkışa bağlar ve hesap
// silme başarısında yerel durumu temizler.
//
// Kurallar (AuthApi ile aynı):
// - Mutasyonlar (POST/PUT) ASLA otomatik yeniden denenmez; çift işlem riski.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); yanlış parola 400 `CURRENT_PASSWORD_*`
//   döner ve oturumu KAPATMAZ. JSON olmayan 401/403 (proxy / captive portal) geçici ağ hatasıdır.
// - Parola, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/account_client_error.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';
import 'package:site_kapi_kontrol/models/account_deletion.dart';
import 'package:site_kapi_kontrol/models/account_platform_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// `409 ACCOUNT_DELETE_BLOCKED`: silme sırasında engel çıktı (önizlemeden sonra durum değişmiş olabilir).
class AccountDeleteBlockedException extends ApiException {
  AccountDeleteBlockedException(super.message, {required this.blockers})
    : super(statusCode: 409, code: 'ACCOUNT_DELETE_BLOCKED');

  final List<AccountDeletionBlocker> blockers;
}

class AccountApi {
  AccountApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 20),
    Duration writeTimeout = const Duration(seconds: 45),
    Duration exportTimeout = const Duration(seconds: 90),
    this.maxExportBytes = defaultMaxExportBytes,
    DateTime Function()? now,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout,
       _exportTimeout = exportTimeout,
       _now = now ?? DateTime.now;

  /// Dışa aktarma dosyası için bellek üst sınırı (25 MB). Aşılırsa indirme durdurulur.
  static const int defaultMaxExportBytes = 25 * 1024 * 1024;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;
  final Duration _exportTimeout;
  final DateTime Function() _now;
  final int maxExportBytes;

  // --- Hesap silme -----------------------------------------------------------------------------

  /// `POST /me/account-deletion/preview`: ne silinecek / ne kalacak / engeller.
  Future<AccountDeletionPreview> previewDeletion({required String token}) async {
    final response = await _send(
      'POST',
      '/me/account-deletion/preview',
      token: token,
      body: const <String, dynamic>{},
      timeout: _readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return AccountDeletionPreview.fromJson(_object(response));
  }

  /// `POST /me/account-deletion`: hesabı kimliksizleştirir. Başarı = `200 {"deleted":true}`; başka hiçbir
  /// yanıt başarı sayılmaz. Engel varsa [AccountDeleteBlockedException].
  Future<void> deleteAccount({
    required String token,
    required String currentPassword,
  }) async {
    final response = await _send(
      'POST',
      '/me/account-deletion',
      token: token,
      body: <String, dynamic>{'current_password': currentPassword, 'confirm': true},
      timeout: _writeTimeout,
      timeoutMessage: _deleteAmbiguousMessage,
      transportMessage: _deleteAmbiguousMessage,
      unexpectedMessage: _deleteUnexpectedMessage,
    );
    final payload = _object(response);
    if (payload['deleted'] != true) {
      throw ApiException(
        'Sunucu yanıtı beklenen biçimde değil. Oturumunuz kapanırsa hesabınız silinmiştir; '
        'kapanmazsa işlemi tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
  }

  static const String _deleteUnexpectedMessage =
      'Sunucu beklenmeyen bir yanıt verdi. Silme işlemi tamamlanmış olabilir: oturumunuz kapanırsa hesabınız '
      'silinmiştir, kapanmazsa tekrar deneyin.';

  static const String _deleteAmbiguousMessage =
      'Sunucudan yanıt alınamadı. Silme işlemi tamamlanmış olabilir: oturumunuz kapanırsa hesabınız '
      'silinmiştir, kapanmazsa tekrar deneyin.';

  // --- Veri dışa aktarma -----------------------------------------------------------------------

  /// `POST /me/data-export`: kişisel veri JSON'u (baytlar). Gövde [maxExportBytes]'ı aşarsa akış kesilir.
  Future<AccountDataExport> exportData({
    required String token,
    required String currentPassword,
  }) async {
    final response = await _send(
      'POST',
      '/me/data-export',
      token: token,
      body: <String, dynamic>{'current_password': currentPassword},
      timeout: _exportTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi. Veri hazırlanamadı, biraz sonra tekrar deneyin.',
      maxBytes: maxExportBytes,
    );
    final bytes = response.bodyBytes;
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    if (bytes.isEmpty || (type.isNotEmpty && !type.contains('json')) || !_startsWithJsonObject(bytes)) {
      throw ApiException(
        'Sunucu beklenmeyen bir dosya döndürdü. Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    return AccountDataExport(
      bytes: bytes,
      fileName: exportFileNameFrom(
        response.headers['content-disposition'],
        fallback: fallbackExportFileName(_now()),
      ),
    );
  }

  // --- Platform ayarları (süper kullanıcı) -----------------------------------------------------

  Future<PlatformConfig> getPlatformConfig({required String token}) async {
    final response = await _send(
      'GET',
      '/admin/platform-config',
      token: token,
      timeout: _readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return PlatformConfig.fromJson(_object(response));
  }

  /// `PUT /admin/platform-config`: KISMİ güncelleme ([patch] yalnız değişen alanlar). Yanıt güncel ayarları
  /// taşıyorsa döner, taşımıyorsa null (çağıran GET ile tazeler).
  Future<PlatformConfig?> updatePlatformConfig({
    required String token,
    required Map<String, Map<String, Object>> patch,
  }) async {
    if (patch.isEmpty) {
      throw ArgumentError.value(patch, 'patch', 'Değişiklik yok');
    }
    final response = await _send(
      'PUT',
      '/admin/platform-config',
      token: token,
      body: patch,
      timeout: _writeTimeout,
      timeoutMessage:
          'Sunucu zaman aşımına uğradı. Ayarlar kaydedilmiş olabilir; sayfayı yenileyip kontrol edin.',
    );
    final payload = _objectOrEmpty(response);
    return PlatformConfig.looksLikeConfig(payload) ? PlatformConfig.fromJson(payload) : null;
  }

  // --- İstemci hataları (süper kullanıcı) ------------------------------------------------------

  Future<ClientErrorPage> listClientErrors({
    required String token,
    int limit = 50,
    String? cursor,
  }) async {
    final response = await _send(
      'GET',
      '/admin/client-errors',
      token: token,
      query: <String, String>{
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
      timeout: _readTimeout,
      timeoutMessage: 'Sunucu yanıt vermedi, tekrar deneyin.',
    );
    return ClientErrorPage.fromJson(_object(response));
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
    String? unexpectedMessage,
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
      response = await _exchange(request, maxBytes: maxBytes, isCancelled: () => timedOut).timeout(
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
    } on Exception catch (_) {
      // SocketException, TlsException, ... (ayrıntı kullanıcıya gösterilmez). Programlama hataları (Error)
      // bilerek yakalanmaz: ağ sorunu gibi gösterilip gizlenmesin.
      throw ApiException(transportMessage);
    }
    // Sözleşme tüm başarılı yanıtlar için YALNIZ 200 verir: 201 / 202 / 204 başarı sayılmaz (silme "kabul edildi"
    // ama tamamlanmadı olabilir; dışa aktarma dosya değildir).
    if (response.statusCode == 200) return response;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw ApiException(
        unexpectedMessage ??
            'Sunucu beklenmeyen bir yanıt verdi (${response.statusCode}). Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    throw _failure(response);
  }

  Future<http.Response> _exchange(
    http.Request request, {
    int? maxBytes,
    required bool Function() isCancelled,
  }) async {
    final streamed = await _client.send(request);
    final declared = streamed.contentLength;
    if (maxBytes != null && declared != null && declared > maxBytes) {
      unawaited(streamed.stream.listen((_) {}).cancel());
      throw _tooLarge(maxBytes);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      if (isCancelled()) break;
      builder.add(chunk);
      if (maxBytes != null && builder.length > maxBytes) throw _tooLarge(maxBytes);
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

  ApiException _tooLarge(int maxBytes) => ApiException(
    'Veri dosyası çok büyük (en çok ${formatByteSize(maxBytes)} indirilebilir). '
    'Verilerinizin tamamı için destek ekibiyle iletişime geçin.',
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

    if (status == 409 && code == 'ACCOUNT_DELETE_BLOCKED') {
      return AccountDeleteBlockedException(
        accountErrorMessage(code, retryAfterSeconds: retryAfter)!,
        blockers: AccountDeletionPreview.parseBlockers(body['blockers']),
      );
    }

    final mapped = accountErrorMessage(code, retryAfterSeconds: retryAfter, payload: body);
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

  /// Bu uçlara özgü sunucu kodları için bağlama uygun Türkçe metin; bilinmiyorsa [AuthApi.messageForErrorCode]
  /// (parola kodları BURADA yeniden yazılır: genel metin "Şifrenizi değiştirmek için…" bu akışa uymaz).
  static String? accountErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
  }) {
    if (code == null) return null;
    final wait = retryAfterSeconds != null
        ? ' ${AuthApi.formatWait(retryAfterSeconds)} sonra tekrar deneyin.'
        : ' Lütfen daha sonra tekrar deneyin.';
    switch (code) {
      case 'CURRENT_PASSWORD_REQUIRED':
        return 'Devam etmek için şifrenizi girin.';
      case 'CURRENT_PASSWORD_INVALID':
        return 'Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.';
      case 'CURRENT_PASSWORD_LOCKED':
        return 'Şifre için çok fazla hatalı deneme yapıldı.$wait';
      case 'EXPORT_RATE_LIMITED':
        return 'Kişisel verilerinizi 24 saat içinde en fazla 3 kez indirebilirsiniz.$wait';
      case 'ACCOUNT_DELETE_BLOCKED':
        return 'Hesabınız şu anda silinemez. Nedenleri aşağıda görebilirsiniz.';
      default:
        return AuthApi.messageForErrorCode(
          code,
          retryAfterSeconds: retryAfterSeconds,
          payload: payload,
        );
    }
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

  /// Gövdesi boş olabilen başarılı yanıt (PUT): boşsa boş harita.
  static Map<String, dynamic> _objectOrEmpty(http.Response response) =>
      _tryObject(response.bodyBytes) ?? const <String, dynamic>{};

  static bool _startsWithJsonObject(Uint8List bytes) {
    var i = 0;
    // UTF-8 BOM ve baştaki boşluklar atlanır.
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) i = 3;
    while (i < bytes.length && (bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09)) {
      i++;
    }
    return i < bytes.length && bytes[i] == 0x7B; // '{'
  }
}

/// Oturum belirtecini [AuthService]'ten alan, oturum hatalarını merkezi çıkışa bağlayan ve hesap silmeden
/// sonra yerel durumu temizleyen katman. Ekranlar bunu kullanır (testlerde sahte [AccountApi] ile kurulur).
class AccountService {
  AccountService({
    required this.authService,
    AccountApi? api,
    LocalDataWiper? wiper,
  }) : api = api ?? debugApiFactory?.call(authService) ?? AccountApi(baseUrl: authService.api.baseUrl),
       wiper = wiper ?? LocalDataWiper();

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda (ana sayfa içinde) sahte [AccountApi] vermek için.
  @visibleForTesting
  static AccountApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final AccountApi api;
  final LocalDataWiper wiper;

  /// Oturumun SÜPER KULLANICI olup olmadığı (arayüz kapısı; asıl yetki kontrolü sunucudadır).
  bool get isSuperUser => authService.session?.role == UserRole.superUser;

  Future<T> _guard<T>(Future<T> Function(String token) call) async {
    final token = authService.session?.token;
    if (token == null) {
      throw ApiException('Oturum açmanız gerekmektedir.');
    }
    try {
      return await call(token);
    } on ApiException catch (e) {
      // 401: oturum gerçekten bitmiş olabilir. Çıkışı AuthService'in /me doğrulaması yapar (sebep
      // metniyle giriş ekranına döner); burada yerel olarak çıkış YAPILMAZ. `ACCOUNT_DELETED` hariç:
      // hesap zaten silinmiştir, [deleteAccount] yerel temizliği kendisi yapar.
      if (e.invalidatesSession &&
          e.code != 'ACCOUNT_DELETED' &&
          authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }

  Future<AccountDeletionPreview> previewDeletion() =>
      _guard((token) => api.previewDeletion(token: token));

  Future<AccountDataExport> exportData(String currentPassword) =>
      _guard((token) => api.exportData(token: token, currentPassword: currentPassword));

  /// Hesabı siler. Sunucu başarıyı onaylayınca ÖNCE merkezi çıkış ([AuthService.logout]: oturum, kapı
  /// önbelleği, widget verisi) uygulanır; ardından kalan yerel durum ([LocalDataWiper]) temizlenir. Çıkış
  /// önce yapılır ki silinmiş hesabın belirteciyle süren yoklamalar 401 alıp "oturum süresi doldu" iletisi
  /// bırakmasın. Temizlik adımlarındaki hatalar silmeyi BAŞARISIZ saymaz (hesap sunucuda gitmiştir).
  Future<LocalWipeReport> deleteAccount(String currentPassword) async {
    try {
      await _guard((token) => api.deleteAccount(token: token, currentPassword: currentPassword));
    } on ApiException catch (e) {
      // 401 ACCOUNT_DELETED: hesap zaten silinmiş (çift gönderim / yanıtı kaybolan önceki istek). Hedef
      // durum sağlandı; yerel temizliğe geçilir. Başka her hata çağırana gider.
      if (e.code != 'ACCOUNT_DELETED') rethrow;
    }
    // Kayıtlı giriş adı (e-posta) çıkıştan ÖNCE silinir: çıkış giriş ekranını hemen kurar ve ekran açılışta
    // bu değeri okur; silinmiş hesabın e-postası giriş alanında görünmemeli.
    await wiper.clearSavedLoginIdentifier();
    try {
      await authService.logout();
    } catch (_) {
      // Çıkış temizliği hata verse de aşağıdaki silme sürer.
    }
    return wiper.wipe();
  }

  Future<PlatformConfig> getPlatformConfig() =>
      _guard((token) => api.getPlatformConfig(token: token));

  /// Kısmi güncelleme; yanıt güncel ayarları taşımıyorsa ayarlar yeniden okunur.
  Future<PlatformConfig> updatePlatformConfig(Map<String, Map<String, Object>> patch) async {
    final updated = await _guard((token) => api.updatePlatformConfig(token: token, patch: patch));
    return updated ?? await getPlatformConfig();
  }

  Future<ClientErrorPage> listClientErrors({int limit = 50, String? cursor}) =>
      _guard((token) => api.listClientErrors(token: token, limit: limit, cursor: cursor));
}
