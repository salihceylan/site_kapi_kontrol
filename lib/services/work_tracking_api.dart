// İş Takibi (arıza, bakım, talep) uçları: docs/PLATFORM_IS_TAKIBI.md.
//
// [WorkTrackingApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [WorkTrackingService]: oturum belirtecini [AuthService]'ten alır, oturum hatasını merkezi çıkışa bağlar ve yazan
// uçların `idempotency_key` değerini oturum boyu saklar.
//
// Kurallar (DocumentApi / AuthApi ile aynı):
// - Mutasyonlar (POST/PATCH) ASLA otomatik yeniden denenmez; çift işlem riski. Yeniden deneme kullanıcı kararıdır
//   ve talep açma / yorum eklemede `idempotency_key` ile güvenlidir.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive
//   portal) geçici ağ hatasıdır.
// - Başlık, açıklama, yorum, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
// - Fotoğraf ekleri (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri"): iki adım (üstveri `POST`, ham gövde `PUT`
//   `application/octet-stream`, `Content-Length` = bildirilen boyut); içerik `GET` ile belirteçli indirilir
//   (`Image.memory`), `DELETE` ile silinir. Sakin `/app/work-items/:id/attachments`, yönetim
//   `/manager/sites/:siteCode/work-items/:id/attachments` yolunu kullanır.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_api.dart'
    show DocumentCancelToken, DocumentTransferCancelled;
import 'package:site_kapi_kontrol/services/document_picker.dart'
    show DocumentUploadSource;
import 'package:site_kapi_kontrol/ui/helpers/idempotency.dart';

/// Fotoğraf eki uç türü: hata metni işleme göre seçilir (ör. 409 `INVALID_STATE` eklemede "eklenemez", silmede
/// "silinemez").
enum WorkAttachmentOp { create, upload, download, delete }

/// Ham gövdeli `PUT` isteği: gövde [_body] akışından çekilir (backpressure korunur), [abortTrigger] ile kesilir.
class _RawBodyRequest extends http.BaseRequest with http.Abortable {
  _RawBodyRequest(
    super.method,
    super.url,
    this._body, {
    required this.abortTrigger,
  });

  final Stream<List<int>> Function() _body;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body());
  }
}

class WorkTrackingApi {
  WorkTrackingApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 20),
    Duration writeTimeout = const Duration(seconds: 45),
    Duration uploadStallTimeout = const Duration(seconds: 60),
    Duration uploadResponseTimeout = const Duration(seconds: 120),
    bool? web,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout,
       _uploadStallTimeout = uploadStallTimeout,
       _uploadResponseTimeout = uploadResponseTimeout,
       _web = web ?? kIsWeb;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;

  /// Fotoğraf yüklemede bu süre hiç bayt ilerlemezse bağlantı kopmuş sayılır.
  final Duration _uploadStallTimeout;

  /// Gövde tamamen gönderildikten sonra sunucu yanıtı için üst süre.
  final Duration _uploadResponseTimeout;

  /// Web: tarayıcı (XHR) gövdeyi tek parça gönderir; akıştan okunan bayt ağdaki ilerlemeyi göstermez. Bu yüzden bayt
  /// ilerlemesi bildirilmez ve tek, boyuta göre süre ([uploadDeadlineFor]) uygulanır.
  final bool _web;

  /// Web'de tüm yükleme (gövde + yanıt) için üst süre: 120 sn + her 16 KB için 1 sn (5 MB ≈ 440 sn). Yavaş bağlantıda
  /// ilerleyen yükleme sabit 120 sn'de kesilmesin.
  static Duration uploadDeadlineFor(int bytes) =>
      Duration(seconds: 120 + (bytes <= 0 ? 0 : (bytes + 16383) ~/ 16384));

  static String _managerPath(int siteCode, [String tail = '']) =>
      '/manager/sites/$siteCode/work-items${tail.isEmpty ? '' : '/$tail'}';

  /// Ek yolu: [siteCode] null ise sakin (`/app/work-items/:id/attachments[/tail]`), doluysa yönetim
  /// (`/manager/sites/:siteCode/work-items/:id/attachments[/tail]`).
  static String attachmentsPath(int? siteCode, int id, [String tail = '']) {
    final base = siteCode == null
        ? '/app/work-items/$id/attachments'
        : _managerPath(siteCode, '$id/attachments');
    return tail.isEmpty ? base : '$base/$tail';
  }

  // --- Sakin --------------------------------------------------------------------------------

  /// `GET /app/work-items`. [status]: `open|closed|all`.
  Future<WorkResidentPage> listMine({
    required String token,
    int? siteCode,
    String status = 'all',
    int limit = 30,
    int? beforeId,
  }) async {
    final response = await _send(
      'GET',
      '/app/work-items',
      token: token,
      query: <String, String>{
        if (siteCode != null) 'site_code': '$siteCode',
        'status': status,
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return WorkResidentPage.fromJson(_object(response));
  }

  /// `POST /app/work-items` (201).
  Future<WorkCreateResult> create({
    required String token,
    required WorkCreateRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/app/work-items',
      token: token,
      body: request.toJson(idempotencyKey),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    final result = WorkCreateResult.fromJson(_object(response));
    if (result.item.id <= 0) throw _unexpected(response);
    return result;
  }

  /// `GET /app/work-items/:id`.
  Future<WorkResidentDetail> getMine({
    required String token,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      '/app/work-items/$id',
      token: token,
      timeout: _readTimeout,
    );
    final detail = WorkResidentDetail.fromJson(_object(response));
    if (detail.item.id <= 0) throw _unexpected(response);
    return detail;
  }

  /// `POST /app/work-items/:id/cancel` -> `{ item }`.
  Future<WorkResidentItem> cancelMine({
    required String token,
    required int id,
  }) async {
    final response = await _send(
      'POST',
      '/app/work-items/$id/cancel',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
    final item = WorkResidentItem.fromJson(_object(response));
    if (item.id <= 0) throw _unexpected(response);
    return item;
  }

  /// `POST /app/work-items/:id/comments` (201, public).
  Future<WorkEvent> commentMine({
    required String token,
    required int id,
    required String body,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/app/work-items/$id/comments',
      token: token,
      body: <String, dynamic>{
        'body': body.trim(),
        'idempotency_key': idempotencyKey,
      },
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _eventOf(response);
  }

  /// `POST /app/work-items/:id/seen`.
  Future<void> markSeen({required String token, required int id}) async {
    await _send(
      'POST',
      '/app/work-items/$id/seen',
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
    );
  }

  // --- Yönetim ------------------------------------------------------------------------------

  /// `GET /manager/sites/:siteCode/work-items`. [status]: `open` ya da virgüllü durumlar; null = hepsi.
  /// [assigned]: `me | none | <user_code>`.
  Future<WorkManagedPage> listManaged({
    required String token,
    required int siteCode,
    String? status,
    String? category,
    String? priority,
    String? assigned,
    String? query,
    int limit = 30,
    int? beforeId,
  }) async {
    final trimmed = query?.trim();
    final response = await _send(
      'GET',
      _managerPath(siteCode),
      token: token,
      query: <String, String>{
        if (status != null && status.isNotEmpty) 'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (assigned != null && assigned.isNotEmpty) 'assigned': assigned,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return WorkManagedPage.fromJson(_object(response));
  }

  /// `GET .../work-items/:id`.
  Future<WorkManagedDetail> getManaged({
    required String token,
    required int siteCode,
    required int id,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, '$id'),
      token: token,
      timeout: _readTimeout,
    );
    return _managedDetail(response);
  }

  /// `PATCH .../work-items/:id`: yalnız [fields] içindekiler gönderilir (`status`, `priority`, `assigned_to`
  /// [user_code | "me" | null], `due_date` ["YYYY-MM-DD" | null]).
  Future<WorkManagedDetail> updateManaged({
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
    return _managedDetail(response);
  }

  /// `POST .../work-items/:id/comments` (201). [internal] true: iç not, false: sakine görünen yorum.
  Future<WorkEvent> commentManaged({
    required String token,
    required int siteCode,
    required int id,
    required String body,
    required bool internal,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode, '$id/comments'),
      token: token,
      body: <String, dynamic>{
        'body': body.trim(),
        'visibility': internal ? 'internal' : 'public',
        'idempotency_key': idempotencyKey,
      },
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _eventOf(response);
  }

  /// `GET .../work-items/assignees`.
  Future<List<WorkAssignee>> assignees({
    required String token,
    required int siteCode,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'assignees'),
      token: token,
      timeout: _readTimeout,
    );
    return WorkAssignee.listFrom(_object(response)['items']);
  }

  WorkManagedDetail _managedDetail(http.Response response) {
    final detail = WorkManagedDetail.fromJson(_object(response));
    if (detail.item.id <= 0) throw _unexpected(response);
    return detail;
  }

  // --- Fotoğraf ekleri ----------------------------------------------------------------------

  /// `POST .../attachments` (201): ek kaydı `uploading` durumuyla açılır; içerik [uploadAttachmentContent] ile gider.
  Future<WorkAttachment> createAttachment({
    required String token,
    int? siteCode,
    required int id,
    required WorkAttachmentCreateRequest request,
  }) async {
    final response = await _send(
      'POST',
      attachmentsPath(siteCode, id),
      token: token,
      body: request.toJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
      attachmentOp: WorkAttachmentOp.create,
    );
    return _attachmentOf(response);
  }

  /// `PUT .../attachments/:attId/content`: baytlar `application/octet-stream` olarak, `Content-Length` =
  /// [source].size ile gönderilir. [onProgress] gönderilen / toplam bayt; [cancel] ile [DocumentTransferCancelled].
  /// Mutasyon: otomatik yeniden deneme YOK (kayıt sunucuda `uploading` kalır, aynı çağrı yeniden yapılabilir).
  Future<WorkAttachment> uploadAttachmentContent({
    required String token,
    int? siteCode,
    required int id,
    required int attachmentId,
    required DocumentUploadSource source,
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    final total = source.size;
    if (total <= 0) {
      throw ApiException('Fotoğraf okunamadı. Yeniden seçip tekrar deneyin.');
    }
    if (cancel != null && cancel.isCancelled) {
      throw const DocumentTransferCancelled();
    }

    final abort = Completer<void>();
    var userCancelled = false;
    var timedOut = false;
    var sourceChanged = false;
    void triggerAbort() {
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(
      cancel?.whenCancelled.then((_) {
        userCancelled = true;
        triggerAbort();
      }),
    );

    Timer? watchdog;
    var finished = false;
    void arm(Duration duration) {
      if (finished) return;
      watchdog?.cancel();
      watchdog = Timer(duration, () {
        timedOut = true;
        triggerAbort();
      });
    }

    // Web: tek süre (gövde + yanıt); bayt ilerlemesi bildirilmez (bkz. [_web]).
    final webDeadline = _web ? uploadDeadlineFor(total) : null;

    Stream<List<int>> body() async* {
      var sent = 0;
      try {
        if (webDeadline == null) arm(_uploadStallTimeout);
        await for (final chunk in source.open()) {
          sent += chunk.length;
          if (sent > total) {
            sourceChanged = true;
            triggerAbort();
            throw StateError('source grew');
          }
          if (webDeadline == null) arm(_uploadStallTimeout);
          yield chunk;
          if (webDeadline == null) onProgress?.call(sent, total);
        }
        if (sent != total) {
          sourceChanged = true;
          triggerAbort();
          throw StateError('source shrank');
        }
        if (webDeadline == null) arm(_uploadResponseTimeout);
      } catch (e) {
        if (e is! StateError) {
          sourceChanged = true;
          triggerAbort();
        }
        rethrow;
      }
    }

    final request =
        _RawBodyRequest(
            'PUT',
            _uri(attachmentsPath(siteCode, id, '$attachmentId/content')),
            body,
            abortTrigger: abort.future,
          )
          ..contentLength = total
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
            'Accept': 'application/json',
          });

    final http.Response response;
    try {
      arm(webDeadline ?? _uploadStallTimeout);
      final streamed = await _client.send(request);
      watchdog?.cancel();
      response = await http.Response.fromStream(streamed).timeout(_readTimeout);
    } on http.RequestAbortedException {
      throw _abortError(
        userCancelled: userCancelled,
        timedOut: timedOut,
        sourceChanged: sourceChanged,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(_uploadTimeoutMessage);
    } catch (e) {
      if (userCancelled || timedOut || sourceChanged) {
        throw _abortError(
          userCancelled: userCancelled,
          timedOut: timedOut,
          sourceChanged: sourceChanged,
        );
      }
      if (e is Error) rethrow;
      throw ApiException(_uploadTransportMessage);
    } finally {
      finished = true;
      watchdog?.cancel();
    }
    if (response.statusCode == 200 || response.statusCode == 201) {
      return _attachmentOf(response);
    }
    // 409 UPLOAD_ALREADY_COMPLETED: önceki deneme sunucuda tamamlanmıştı (yanıtı kaybolmuştu); çağıran BAŞARI sayar.
    throw _failure(response, attachmentOp: WorkAttachmentOp.upload);
  }

  /// `GET .../attachments/:attId/content`: resim baytları (belirteç başlıkta gider; `Image.memory` ile çizilir).
  /// Resim dışı yanıt (JSON / HTML hata sayfası) resim gibi kullanılmaz.
  Future<Uint8List> downloadAttachment({
    required String token,
    int? siteCode,
    required int id,
    required int attachmentId,
  }) async {
    final request =
        http.Request(
            'GET',
            _uri(attachmentsPath(siteCode, id, '$attachmentId/content')),
          )
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'image/*, application/json',
          });
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_readTimeout);
    } on TimeoutException {
      throw ApiException('Fotoğraf alınamadı. Sunucu yanıt vermedi, tekrar deneyin.');
    } catch (e) {
      if (e is Error) rethrow;
      throw ApiException(_transportMessage);
    }
    if (streamed.statusCode != 200) {
      final http.Response response;
      try {
        response = await http.Response.fromStream(streamed).timeout(_readTimeout);
      } catch (e) {
        if (e is Error) rethrow;
        throw ApiException(_transportMessage);
      }
      throw _failure(response, attachmentOp: WorkAttachmentOp.download);
    }
    final type = (streamed.headers['content-type'] ?? '').toLowerCase();
    if (!type.startsWith('image/')) {
      unawaited(streamed.stream.listen((_) {}).cancel());
      throw ApiException(
        'Sunucu beklenmeyen bir yanıt verdi. Ağ bağlantınızı kontrol edip tekrar deneyin.',
        statusCode: 200,
        fromIntermediary: true,
      );
    }
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in streamed.stream.timeout(_uploadStallTimeout)) {
        builder.add(chunk);
        if (builder.length > kWorkAttachmentMaxBytes + 1024 * 1024) {
          throw ApiException('Fotoğraf çok büyük olduğu için açılamadı.', statusCode: 413);
        }
      }
    } on TimeoutException {
      throw ApiException('Fotoğraf alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    } on ApiException {
      rethrow;
    } catch (e) {
      if (e is Error) rethrow;
      throw ApiException(_transportMessage);
    }
    final declared = streamed.contentLength;
    if (declared != null && declared != builder.length) {
      throw ApiException('Fotoğraf eksik indi. Tekrar deneyin.');
    }
    if (builder.isEmpty) {
      throw ApiException('Fotoğraf içeriği boş geldi. Tekrar deneyin.');
    }
    return builder.takeBytes();
  }

  /// `DELETE .../attachments/:attId` -> `{ deleted: true }`.
  Future<void> deleteAttachment({
    required String token,
    int? siteCode,
    required int id,
    required int attachmentId,
  }) async {
    await _send(
      'DELETE',
      attachmentsPath(siteCode, id, '$attachmentId'),
      token: token,
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 204},
      attachmentOp: WorkAttachmentOp.delete,
    );
  }

  // --- Rapor --------------------------------------------------------------------------------

  /// `GET .../work-items/report?from=YYYY-MM-DD&to=YYYY-MM-DD` (yönetici + kurul; görevli 403).
  Future<WorkReport> report({
    required String token,
    required int siteCode,
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, 'report'),
      token: token,
      query: <String, String>{'from': crmDateParam(from), 'to': crmDateParam(to)},
      timeout: _readTimeout,
    );
    return WorkReport.fromJson(_object(response));
  }

  WorkAttachment _attachmentOf(http.Response response) {
    final attachment = WorkAttachment.fromJson(_object(response));
    if (attachment == null) throw _unexpected(response);
    return attachment;
  }

  Object _abortError({
    required bool userCancelled,
    required bool timedOut,
    required bool sourceChanged,
  }) {
    if (userCancelled) return const DocumentTransferCancelled();
    if (sourceChanged) {
      return ApiException(
        'Fotoğraf seçildikten sonra değişmiş ya da okunamadı. Yeniden seçip tekrar deneyin.',
      );
    }
    if (timedOut) return ApiException(_uploadTimeoutMessage);
    return ApiException(_uploadTransportMessage);
  }

  static const String _uploadTimeoutMessage =
      'Fotoğraf yüklenirken bağlantı yanıt vermedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
  static const String _uploadTransportMessage =
      'Fotoğraf yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  WorkEvent _eventOf(http.Response response) {
    final payload = _object(response);
    final raw = payload['event'];
    if (raw is! Map) throw _unexpected(response);
    return WorkEvent.fromJson(Map<String, dynamic>.from(raw));
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
    WorkAttachmentOp? attachmentOp,
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
    throw _failure(response, attachmentOp: attachmentOp);
  }

  static const String _transportMessage =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  // --- Hata çevirisi ------------------------------------------------------------------------

  ApiException _failure(
    http.Response response, {
    WorkAttachmentOp? attachmentOp,
  }) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (attachmentOp != null &&
        payload == null &&
        (status == 413 || status == 415)) {
      // JSON olmayan 413 / 415 (Nginx / ara katman): tür ya da boyut reddi.
      return ApiException(
        WorkAttachmentRules.typeAndSizeMessage,
        statusCode: status,
        code: status == 413 ? 'BODY_TOO_LARGE' : 'UNSUPPORTED_MEDIA_TYPE',
      );
    }

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
      if (status == 413) {
        return ApiException(
          workTrackingErrorMessage('BODY_TOO_LARGE')!,
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

    final mapped =
        (attachmentOp != null
            ? workAttachmentErrorMessage(
                status,
                code,
                retryAfterSeconds: retryAfter,
                op: attachmentOp,
                payload: body,
              )
            : null) ??
        workTrackingErrorMessage(
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

  /// İş Takibi hata kodları için düz Türkçe metin (sözleşme "Hata kodları"); bilinmiyorsa genel kodlar
  /// ([AuthApi.messageForErrorCode]) ya da null (sunucunun kendi `error` metni kullanılır). `INVALID_BODY` /
  /// `INVALID_LOCATION` sunucunun alan etiketli metnini taşır ([serverText]).
  static String? workTrackingErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
    String? serverText,
  }) {
    if (code == null) return null;
    switch (code) {
      case 'MODULE_DISABLED':
        return 'İş takibi bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'NOT_A_RESIDENT':
        return 'Bu sitede talep açabilmek için daire sakini olmalısınız.';
      case 'WORK_ITEM_NOT_FOUND':
        return 'Talep bulunamadı ya da erişiminiz yok.';
      case 'SITE_NOT_FOUND':
        return 'Site bulunamadı.';
      case 'INVALID_SITE_CODE':
        return 'Site geçersiz. Siteyi yeniden seçin.';
      case 'INVALID_ASSIGNEE':
        return 'Seçilen kişi bu talebe atanamaz. Listeyi yenileyip tekrar deneyin.';
      case 'INVALID_LOCATION':
        return serverText ?? 'Konum bilgisi geçersiz. Seçimi kontrol edin.';
      case 'INVALID_BODY':
        return serverText ??
            'Girilen bilgiler geçersiz. Alanları kontrol edip tekrar deneyin.';
      case 'INVALID_QUERY':
        return 'Süzgeç geçersiz. Süzgeçleri temizleyip tekrar deneyin.';
      case 'INVALID_TRANSITION':
        return 'Talebin durumu bu şekilde değiştirilemez. Talep başka biri tarafından güncellenmiş olabilir; yenileyip tekrar deneyin.';
      case 'WORK_ITEM_CLOSED':
        return 'Bu talep kapandığı ya da iptal edildiği için değiştirilemez.';
      case 'WORK_ITEM_LIMIT':
        return 'Sitedeki açık talep sınırına ulaşıldı. Yönetimle iletişime geçin.';
      case 'WORK_ITEM_COMMENT_LIMIT':
        return 'Bu talebe daha fazla yorum eklenemez.';
      case 'WORK_ITEM_RATE_LIMITED':
        return retryAfterSeconds == null
            ? 'Bu saat içinde çok fazla talep açtınız. Biraz sonra tekrar deneyin.'
            : 'Bu saat içinde çok fazla talep açtınız. ${AuthApi.formatWait(retryAfterSeconds)} sonra tekrar deneyin.';
      case 'BODY_TOO_LARGE':
        return 'Gönderilen içerik çok büyük. Metni kısaltın.';
    }
    return AuthApi.messageForErrorCode(
      code,
      retryAfterSeconds: retryAfterSeconds,
      payload: payload,
    );
  }

  /// Fotoğraf eki uçlarının hata kodları için düz Türkçe metin (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri" ve
  /// "Hata kodları"); eşleşme yoksa null (genel İş Takibi eşlemesine ve sunucunun kendi metnine düşer). [op] aynı
  /// kodun işleme göre anlamını seçer (409 `INVALID_STATE`: eklemede "eklenemez", silmede "silinemez").
  static String? workAttachmentErrorMessage(
    int status,
    String? code, {
    int? retryAfterSeconds,
    WorkAttachmentOp op = WorkAttachmentOp.create,
    Map<String, dynamic>? payload,
  }) {
    final c = (code ?? '').trim().toUpperCase();
    switch (c) {
      case 'LIMIT_REACHED':
        return WorkAttachmentRules.limitMessage;
      case 'ATTACHMENT_QUOTA_EXCEEDED':
        final quota = payload?['quota'];
        final quotaBytes = payload?['quota_bytes'];
        return WorkAttachmentRules.quotaMessage(
          site: quota is String && quota.trim().toLowerCase() == 'site',
          quotaBytes: quotaBytes is num ? quotaBytes.toInt() : null,
        );
      case 'ATTACHMENT_DIMENSIONS_TOO_LARGE':
        return WorkAttachmentRules.dimensionsMessage;
      case 'INVALID_STATE':
      case 'WORK_ITEM_CLOSED':
        return op == WorkAttachmentOp.delete
            ? 'Kapanmış talepteki fotoğraf silinemez.'
            : WorkAttachmentRules.closedMessage;
      case 'WORK_ATTACHMENT_NOT_FOUND':
        return op == WorkAttachmentOp.upload
            ? 'Yükleme kaydı bulunamadı. Tekrar deneyin.'
            : 'Fotoğraf bulunamadı. Silinmiş olabilir; ekranı yenileyin.';
      case 'UPLOAD_EXPIRED':
        return 'Yükleme süresi doldu. Tekrar deneyin.';
      case 'UPLOAD_IN_PROGRESS':
        return 'Bu fotoğrafın yüklemesi zaten sürüyor. Biraz sonra tekrar deneyin.';
      case 'UPLOAD_ALREADY_COMPLETED':
        return 'Fotoğraf zaten yüklenmiş.';
      case 'UPLOAD_BUSY':
        return _withRetryHint(
          'Sunucu şu anda çok sayıda yükleme alıyor.',
          retryAfterSeconds,
        );
      case 'DOWNLOAD_BUSY':
        return 'Sunucu şu anda yoğun. Biraz sonra tekrar deneyin.';
      case 'ATTACHMENT_STORAGE_UNAVAILABLE':
        return 'Fotoğraf deposu şu anda kullanılamıyor. Biraz sonra tekrar deneyin.';
      case 'ATTACHMENT_FILE_MISSING':
        return 'Fotoğraf dosyası sunucuda bulunamadı.';
      case 'ATTACHMENT_CONTENT_MISMATCH':
        return 'Fotoğraf bozuk ya da türü dosya uzantısıyla uyuşmuyor. Başka bir fotoğraf seçin.';
      case 'ATTACHMENT_SIZE_MISMATCH':
        return 'Fotoğraf gönderilirken boyutu değişti. Yeniden seçip tekrar deneyin.';
      case 'ATTACHMENT_TOO_LARGE':
      case 'ATTACHMENT_TYPE_NOT_ALLOWED':
      case 'INVALID_CONTENT_TYPE':
      case 'BODY_TOO_LARGE':
        return WorkAttachmentRules.typeAndSizeMessage;
      case 'WORK_ATTACHMENT_RATE_LIMITED':
        return _withRetryHint(
          'Bir saat içinde çok fazla fotoğraf eklediniz.',
          retryAfterSeconds,
        );
      case 'FORBIDDEN_ROLE':
        if (op == WorkAttachmentOp.delete) {
          return 'Bu fotoğrafı yalnız ekleyen kişi ya da yönetici silebilir.';
        }
      case 'NOT_A_RESIDENT':
        return 'Fotoğraf eklemek ya da silmek için bu sitede daire sakini olmalısınız.';
    }
    if (status == 413 || status == 415) return WorkAttachmentRules.typeAndSizeMessage;
    if (status == 429) {
      return _withRetryHint('Çok fazla fotoğraf işlemi yapıldı.', retryAfterSeconds);
    }
    return null;
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
/// [WorkTrackingService] kurulur).
class WorkTrackingService {
  WorkTrackingService({required this.authService, WorkTrackingApi? api})
    : api =
          api ??
          debugApiFactory?.call(authService) ??
          WorkTrackingApi(baseUrl: authService.api.baseUrl);

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda sahte [WorkTrackingApi] vermek için.
  @visibleForTesting
  static WorkTrackingApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final WorkTrackingApi api;

  /// Oturum boyu anahtar haritası: imza (veri) aynıysa AYNI anahtar, veri değişince YENİ anahtar. Yanıtı kaybolan
  /// gönderim, ekran kapatılıp açılsa bile çift kayıt yaratmaz; başarıda anahtar atılır.
  IdempotencyKeys get _keys => sessionIdempotencyKeys(authService, 'wk');

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

  // --- Sakin ---

  Future<WorkResidentPage> listMine({
    int? siteCode,
    String status = 'all',
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listMine(
      token: token,
      siteCode: siteCode,
      status: status,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<WorkCreateResult> createItem(WorkCreateRequest request) async {
    final signature = 'create|${request.signature}';
    final key = _keys.keyFor(signature);
    final result = await _guard(
      (token) =>
          api.create(token: token, request: request, idempotencyKey: key),
    );
    _keys.clear(signature);
    return result;
  }

  Future<WorkResidentDetail> getMine(int id) =>
      _guard((token) => api.getMine(token: token, id: id));

  Future<WorkResidentItem> cancelMine(int id) =>
      _guard((token) => api.cancelMine(token: token, id: id));

  Future<WorkEvent> commentMine(int id, String body) async {
    final signature = 'comment|mine|$id|${body.trim()}';
    final key = _keys.keyFor(signature);
    final event = await _guard(
      (token) => api.commentMine(
        token: token,
        id: id,
        body: body,
        idempotencyKey: key,
      ),
    );
    _keys.clear(signature);
    return event;
  }

  Future<void> markSeen(int id) =>
      _guard((token) => api.markSeen(token: token, id: id));

  /// Sakinin bu sitedeki daireleri (talep formunda "Dairem" seçimi). Alınamazsa [ApiException].
  Future<List<WorkApartmentChoice>> myApartments(int siteCode) async {
    final (list, error) = await authService.getMyApartments();
    if (list == null) {
      throw ApiException(
        (error ?? '').trim().isEmpty
            ? 'Daireleriniz yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.'
            : error!,
      );
    }
    return List<WorkApartmentChoice>.unmodifiable(<WorkApartmentChoice>[
      for (final apartment in list)
        if (apartment.siteCode == siteCode && apartment.apartmentId > 0)
          WorkApartmentChoice(
            id: apartment.apartmentId,
            label: apartment.blockName.trim().isEmpty
                ? apartment.unitLabel
                : '${apartment.blockName.trim()} / ${apartment.unitLabel}',
          ),
    ]);
  }

  // --- Yönetim ---

  Future<WorkManagedPage> listManaged(
    int siteCode, {
    String? status,
    String? category,
    String? priority,
    String? assigned,
    String? query,
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listManaged(
      token: token,
      siteCode: siteCode,
      status: status,
      category: category,
      priority: priority,
      assigned: assigned,
      query: query,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<WorkManagedDetail> getManaged(int siteCode, int id) => _guard(
    (token) => api.getManaged(token: token, siteCode: siteCode, id: id),
  );

  Future<WorkManagedDetail> updateManaged(
    int siteCode,
    int id,
    Map<String, Object?> fields,
  ) => _guard(
    (token) => api.updateManaged(
      token: token,
      siteCode: siteCode,
      id: id,
      fields: fields,
    ),
  );

  Future<WorkEvent> commentManaged(
    int siteCode,
    int id,
    String body, {
    required bool internal,
  }) async {
    final signature =
        'comment|manager|$siteCode|$id|${internal ? 'i' : 'p'}|${body.trim()}';
    final key = _keys.keyFor(signature);
    final event = await _guard(
      (token) => api.commentManaged(
        token: token,
        siteCode: siteCode,
        id: id,
        body: body,
        internal: internal,
        idempotencyKey: key,
      ),
    );
    _keys.clear(signature);
    return event;
  }

  Future<List<WorkAssignee>> assignees(int siteCode) =>
      _guard((token) => api.assignees(token: token, siteCode: siteCode));

  // --- Fotoğraf ekleri ([siteCode] null: sakin yolu; dolu: yönetim yolu) ---

  Future<WorkAttachment> createAttachment({
    int? siteCode,
    required int id,
    required WorkAttachmentCreateRequest request,
  }) => _guard(
    (token) => api.createAttachment(
      token: token,
      siteCode: siteCode,
      id: id,
      request: request,
    ),
  );

  Future<WorkAttachment> uploadAttachment({
    int? siteCode,
    required int id,
    required int attachmentId,
    required DocumentUploadSource source,
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) => _guard(
    (token) => api.uploadAttachmentContent(
      token: token,
      siteCode: siteCode,
      id: id,
      attachmentId: attachmentId,
      source: source,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  Future<Uint8List> downloadAttachment({
    int? siteCode,
    required int id,
    required int attachmentId,
  }) => _guard(
    (token) => api.downloadAttachment(
      token: token,
      siteCode: siteCode,
      id: id,
      attachmentId: attachmentId,
    ),
  );

  Future<void> deleteAttachment({
    int? siteCode,
    required int id,
    required int attachmentId,
  }) => _guard(
    (token) => api.deleteAttachment(
      token: token,
      siteCode: siteCode,
      id: id,
      attachmentId: attachmentId,
    ),
  );

  // --- Rapor ---

  Future<WorkReport> report(
    int siteCode, {
    required DateTime from,
    required DateTime to,
  }) => _guard(
    (token) => api.report(token: token, siteCode: siteCode, from: from, to: to),
  );
}
