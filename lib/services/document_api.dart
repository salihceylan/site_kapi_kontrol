// Belgeler (dosya deposu) uçları: docs/PLATFORM_BELGELER.md Bölüm A (A3 yükleme, A7 uçlar, A8 başlıklar, A9 hatalar).
//
// [DocumentApi]: yalnız HTTP katmanı (belirteci çağıran verir, hata gövdesini Türkçe [ApiException]'a çevirir).
// [DocumentService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (AuthApi / AccountApi ile aynı):
// - Mutasyonlar (POST/PUT/PATCH/DELETE) ASLA otomatik yeniden denenmez; çift işlem riski. Yeniden deneme
//   kullanıcı kararıdır ve oluşturmada `idempotency_key` ile güvenlidir.
// - 401 yetkili uçlarda "oturum bitti"dir ([SessionExpiredException]); JSON olmayan 401/403 (proxy / captive
//   portal) geçici ağ hatasıdır. JSON olmayan 413 (Nginx) `DOCUMENT_TOO_LARGE` iletisine eşlenir.
// - Yükleme / indirme baytları BELLEKTE toplanmaz: yükleme dosyayı akıştan soketle çeker, indirme parçaları
//   doğrudan hedefe ([DocumentSink]) yazar.
// - Dosya adı, başlık, belirteç ve yanıt gövdeleri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';

/// Kullanıcı yükleme / indirmeyi iptal etti (hata DEĞİL; arayüz sessizce başa döner).
class DocumentTransferCancelled implements Exception {
  const DocumentTransferCancelled();

  @override
  String toString() => 'İşlem iptal edildi.';
}

/// İptal belirteci: [cancel] çağrılınca uçuştaki yükleme / indirme durdurulur.
class DocumentCancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// `PUT .../content` isteği: gövde [_body] akışından çekilir (backpressure korunur; bellek sabit).
class _UploadRequest extends http.BaseRequest with http.Abortable {
  _UploadRequest(
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

class DocumentApi {
  DocumentApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 20),
    Duration writeTimeout = const Duration(seconds: 45),
    Duration uploadStallTimeout = const Duration(seconds: 60),
    Duration uploadResponseTimeout = const Duration(seconds: 120),
    Duration downloadStallTimeout = const Duration(seconds: 60),
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout,
       _uploadStallTimeout = uploadStallTimeout,
       _uploadResponseTimeout = uploadResponseTimeout,
       _downloadStallTimeout = downloadStallTimeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;

  /// Yükleme sırasında bu süre hiç bayt ilerlemezse bağlantı kopmuş sayılır (sözleşme: 120 sn üst süre).
  final Duration _uploadStallTimeout;

  /// Gövde tamamen gönderildikten sonra sunucu yanıtı için üst süre (sözleşme: 120 sn).
  final Duration _uploadResponseTimeout;

  /// İndirmede bu süre hiç bayt gelmezse kopmuş sayılır (sözleşme: 60 sn).
  final Duration _downloadStallTimeout;

  /// Yükleme adresi biçimi (`upload.path`): belirteç yalnız bu yola gönderilir.
  static final RegExp uploadPathPattern = RegExp(
    r'^/manager/sites/\d+/documents/\d+/versions/\d+/content$',
  );

  // --- Yönetici -----------------------------------------------------------------------------

  static String _managerPath(int siteCode, [String tail = '']) =>
      '/manager/sites/$siteCode/documents${tail.isEmpty ? '' : '/$tail'}';

  /// `GET .../documents`. [status]: `active|deleted|all`; [audience] ve [category] isteğe bağlı süzgeç.
  Future<DocumentPage> listManaged({
    required String token,
    required int siteCode,
    String? category,
    String? status,
    String? audience,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    final trimmed = query?.trim();
    final response = await _send(
      'GET',
      _managerPath(siteCode),
      token: token,
      query: <String, String>{
        if (category != null && category.isNotEmpty) 'category': category,
        if (status != null && status.isNotEmpty) 'status': status,
        if (audience != null && audience.isNotEmpty) 'audience': audience,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
      },
      timeout: _readTimeout,
    );
    return DocumentPage.fromJson(_object(response));
  }

  /// `GET .../documents/:id`.
  Future<DocumentDetail> getManaged({
    required String token,
    required int siteCode,
    required int documentId,
  }) async {
    final response = await _send(
      'GET',
      _managerPath(siteCode, '$documentId'),
      token: token,
      timeout: _readTimeout,
    );
    return DocumentDetail.fromJson(_object(response));
  }

  /// `POST .../documents` (201): bekleyen belge + sürüm + yükleme tanımı.
  Future<DocumentUploadTicket> createDocument({
    required String token,
    required int siteCode,
    required DocumentCreateRequest request,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode),
      token: token,
      body: request.toJson(),
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _ticket(response);
  }

  /// `POST .../documents/:id/versions` (201): yeni sürüm için yükleme tanımı.
  Future<DocumentUploadTicket> createVersion({
    required String token,
    required int siteCode,
    required int documentId,
    required DocumentFileInput file,
    String? note,
  }) async {
    final response = await _send(
      'POST',
      _managerPath(siteCode, '$documentId/versions'),
      token: token,
      body: <String, dynamic>{
        'file': file.toJson(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 201},
    );
    return _ticket(response);
  }

  DocumentUploadTicket _ticket(http.Response response) {
    final ticket = DocumentUploadTicket.fromJson(_object(response));
    if (ticket.document.id <= 0 || ticket.upload.path.isEmpty) {
      throw ApiException(
        'Sunucu yanıtı beklenen biçimde değil. Lütfen tekrar deneyin.',
        statusCode: response.statusCode,
      );
    }
    return ticket;
  }

  /// `PUT .../versions/:no/content`: dosya baytlarını `application/octet-stream` olarak gönderir.
  ///
  /// - `Content-Length` = bildirilen boyut (sunucu ZORUNLU tutar; uyuşmazlık 400 `DOCUMENT_SIZE_MISMATCH`).
  /// - Bayt akışı [source]'tan çekilir (bellek sabit); [onProgress] gönderilen / toplam bayt ile çağrılır.
  /// - [cancel] ile iptal: [DocumentTransferCancelled] fırlatılır.
  /// - Bağlantı 60 sn ilerlemezse ya da yanıt 120 sn gelmezse zaman aşımı hatası (mutasyon: otomatik yeniden
  ///   deneme YOK; sürüm sunucuda `uploading` kalır, aynı çağrı yeniden yapılabilir).
  /// - 409 `UPLOAD_ALREADY_COMPLETED` BAŞARI sayılır (önceki deneme tamamlandı); güncel belge yanıttan okunur.
  Future<DocumentSummary> uploadContent({
    required String token,
    required DocumentUploadInfo upload,
    required DocumentUploadSource source,
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    if (upload.method != 'PUT' || !uploadPathPattern.hasMatch(upload.path)) {
      throw ApiException('Yükleme adresi geçersiz. İşlemi baştan başlatın.');
    }
    // Sözleşme `upload.size` verir; eksikse (eski / hatalı yanıt) seçilen dosyanın boyutu geçerlidir.
    final total = upload.size > 0 ? upload.size : source.size;
    if (total <= 0 || source.size != total) {
      // Dosya iki adım arasında değişti (ya da okunamıyor): sunucu da Content-Length uyuşmazlığını reddederdi.
      throw ApiException(
        'Dosya seçildikten sonra değişmiş. Dosyayı yeniden seçip tekrar deneyin.',
      );
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
      // İstek bittikten sonra (gövde akışı geç uyanırsa) yeni sayaç kurulmaz: sahipsiz zamanlayıcı kalmasın.
      if (finished) return;
      watchdog?.cancel();
      watchdog = Timer(duration, () {
        timedOut = true;
        triggerAbort();
      });
    }

    Stream<List<int>> body() async* {
      var sent = 0;
      try {
        arm(_uploadStallTimeout);
        await for (final chunk in source.open()) {
          sent += chunk.length;
          if (sent > total) {
            sourceChanged = true;
            triggerAbort();
            throw StateError('source grew');
          }
          arm(_uploadStallTimeout);
          yield chunk;
          onProgress?.call(sent, total);
        }
        if (sent != total) {
          sourceChanged = true;
          triggerAbort();
          throw StateError('source shrank');
        }
        // Gövde tamam: şimdi sunucu yanıtı beklenir.
        arm(_uploadResponseTimeout);
      } catch (e) {
        if (e is! StateError) {
          // Dosya okunamadı (silindi / izin): sunucuya eksik gövde göndermeyiz.
          sourceChanged = true;
          triggerAbort();
        }
        rethrow;
      }
    }

    final request =
        _UploadRequest(
            'PUT',
            _uri(upload.path),
            body,
            abortTrigger: abort.future,
          )
          ..contentLength = total
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': upload.contentType.isEmpty
                ? 'application/octet-stream'
                : upload.contentType,
            'Accept': 'application/json',
          });

    final http.Response response;
    try {
      // Bağlantı kurulamıyorsa da (gövde hiç çekilmez) takılı kalmaz.
      arm(_uploadStallTimeout);
      final streamed = await _client.send(request);
      watchdog?.cancel();
      response = await _readBody(streamed, abortOnTimeout: _readTimeout);
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

    if (response.statusCode == 200) {
      return _documentOf(response);
    }
    final failure = _failure(response, maxBytes: upload.maxBytes);
    if (failure.code == 'UPLOAD_ALREADY_COMPLETED') {
      final doc = failure.payload?['document'];
      if (doc is Map) {
        return DocumentSummary.fromJson(Map<String, dynamic>.from(doc));
      }
      // Belge yanıtta yoksa tamamlanma yine başarıdır; çağıran listeyi yeniler.
      return const DocumentSummary(id: 0);
    }
    throw failure;
  }

  static const String _uploadTimeoutMessage =
      'Sunucu yanıt vermedi. Yükleme tamamlanmış olabilir; listeyi yenileyip kontrol edin ya da tekrar deneyin.';
  static const String _uploadTransportMessage =
      'Yükleme sırasında bağlantı koptu. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  Object _abortError({
    required bool userCancelled,
    required bool timedOut,
    required bool sourceChanged,
  }) {
    if (userCancelled) return const DocumentTransferCancelled();
    if (sourceChanged) {
      return ApiException(
        'Dosya yükleme sırasında okunamadı ya da değişti. Dosyayı yeniden seçip tekrar deneyin.',
      );
    }
    if (timedOut) {
      return ApiException(
        'Bağlantı çok yavaş ya da kesildi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
    }
    return ApiException(_uploadTransportMessage);
  }

  DocumentSummary _documentOf(http.Response response) {
    final payload = _object(response);
    final raw = payload['document'];
    if (raw is Map) {
      return DocumentSummary.fromJson(Map<String, dynamic>.from(raw));
    }
    return DocumentSummary.fromJson(payload);
  }

  /// `DELETE .../versions/:no`: sürümü kalıcı siler (en az bir hazır sürüm kalmalı).
  Future<void> deleteVersion({
    required String token,
    required int siteCode,
    required int documentId,
    required int versionNo,
  }) async {
    await _send(
      'DELETE',
      _managerPath(siteCode, '$documentId/versions/$versionNo'),
      token: token,
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 204},
    );
  }

  /// `PATCH .../documents/:id`: yalnız [fields] içindekiler gönderilir. Belge `residents` kitlesinden çıkarılırken
  /// YAYINDAKİ bir duyuruya ekliyse sunucu [confirm] olmadan 409 `DOCUMENT_IN_USE` döner (sözleşme dışı ama
  /// sunucuda var); onaylanınca `confirm: true` ile yeniden çağrılır. Taslak / zamanlanmış duyurulardan ek
  /// sunucuda çıkarılır.
  Future<DocumentDetail> updateDocument({
    required String token,
    required int siteCode,
    required int documentId,
    required Map<String, Object?> fields,
    bool confirm = false,
  }) async {
    final response = await _send(
      'PATCH',
      _managerPath(siteCode, '$documentId'),
      token: token,
      body: <String, dynamic>{...fields, if (confirm) 'confirm': true},
      timeout: _writeTimeout,
    );
    return DocumentDetail.fromJson(_objectOrEmpty(response));
  }

  /// `DELETE .../documents/:id` (yumuşak silme). Yayındaki duyuruya ekliyse [confirm] olmadan 409 `DOCUMENT_IN_USE`.
  Future<void> deleteDocument({
    required String token,
    required int siteCode,
    required int documentId,
    bool confirm = false,
  }) async {
    await _send(
      'DELETE',
      _managerPath(siteCode, '$documentId'),
      token: token,
      body: confirm
          ? const <String, dynamic>{'confirm': true}
          : const <String, dynamic>{},
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 204},
    );
  }

  /// `POST .../documents/:id/restore`.
  Future<void> restoreDocument({
    required String token,
    required int siteCode,
    required int documentId,
  }) async {
    await _send(
      'POST',
      _managerPath(siteCode, '$documentId/restore'),
      token: token,
      body: const <String, dynamic>{},
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 204},
    );
  }

  /// `POST .../documents/:id/purge` gövde `{confirm:true}`: yalnız silinmiş belge; fiziksel dosya silinir.
  Future<void> purgeDocument({
    required String token,
    required int siteCode,
    required int documentId,
  }) async {
    await _send(
      'POST',
      _managerPath(siteCode, '$documentId/purge'),
      token: token,
      body: const <String, dynamic>{'confirm': true},
      timeout: _writeTimeout,
      okStatuses: const <int>{200, 204},
    );
  }

  /// `GET .../documents/:id/download?version=` — akışı [openSink] hedefine yazar.
  Future<DownloadedDocument> downloadManaged({
    required String token,
    required int siteCode,
    required int documentId,
    int? version,
    required DocumentSinkFactory openSink,
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) {
    return _download(
      token: token,
      path: _managerPath(siteCode, '$documentId/download'),
      query: <String, String>{if (version != null) 'version': '$version'},
      openSink: openSink,
      fallbackName: fallbackName,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  // --- Sakin --------------------------------------------------------------------------------

  /// `GET /app/documents?site_code=&category=&q=&limit=&before_id=`.
  Future<ResidentDocumentPage> listMine({
    required String token,
    int? siteCode,
    String? category,
    String? query,
    int limit = 30,
    int? beforeId,
  }) async {
    final trimmed = query?.trim();
    final response = await _send(
      'GET',
      '/app/documents',
      token: token,
      query: <String, String>{
        if (siteCode != null) 'site_code': '$siteCode',
        if (category != null && category.isNotEmpty) 'category': category,
        if (trimmed != null && trimmed.isNotEmpty) 'q': trimmed,
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
      timeout: _readTimeout,
    );
    return ResidentDocumentPage.fromJson(_object(response));
  }

  /// `GET /app/documents/:id`.
  Future<ResidentDocument> getMine({
    required String token,
    required int documentId,
  }) async {
    final response = await _send(
      'GET',
      '/app/documents/$documentId',
      token: token,
      timeout: _readTimeout,
    );
    return ResidentDocument.fromJson(_object(response));
  }

  /// `GET /app/documents/:id/download`.
  Future<DownloadedDocument> downloadMine({
    required String token,
    required int documentId,
    required DocumentSinkFactory openSink,
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) {
    return _download(
      token: token,
      path: '/app/documents/$documentId/download',
      openSink: openSink,
      fallbackName: fallbackName,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  /// `GET /app/announcements/:id/attachments/:documentId/download`.
  Future<DownloadedDocument> downloadAnnouncementAttachment({
    required String token,
    required int announcementId,
    required int documentId,
    required DocumentSinkFactory openSink,
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) {
    return _download(
      token: token,
      path:
          '/app/announcements/$announcementId/attachments/$documentId/download',
      openSink: openSink,
      fallbackName: fallbackName,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  // --- İndirme taşıma katmanı ---------------------------------------------------------------

  Future<DownloadedDocument> _download({
    required String token,
    required String path,
    Map<String, String>? query,
    required DocumentSinkFactory openSink,
    required String fallbackName,
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    if (cancel != null && cancel.isCancelled) {
      throw const DocumentTransferCancelled();
    }
    final abort = Completer<void>();
    var userCancelled = false;
    unawaited(
      cancel?.whenCancelled.then((_) {
        userCancelled = true;
        if (!abort.isCompleted) abort.complete();
      }),
    );
    final request =
        http.AbortableRequest(
            'GET',
            _uri(path, query),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            'Authorization': 'Bearer $token',
            'Accept': '*/*',
          });

    DocumentSink? sink;
    try {
      final streamed = await _client
          .send(request)
          .timeout(
            // Başlıkların gelmesi için sözleşmedeki indirme süresi (60 sn); sonra parça başına durma süresi sayılır.
            _downloadStallTimeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException(null);
            },
          );
      if (streamed.statusCode != 200) {
        final response = await _readBody(
          streamed,
          abortOnTimeout: _readTimeout,
        );
        throw _failure(response);
      }
      final type = (streamed.headers['content-type'] ?? '').toLowerCase();
      if (type.startsWith('application/json') || type.startsWith('text/html')) {
        // Dosya yerine hata sayfası / JSON geldi (proxy, captive portal): dosya gibi kaydedilmez.
        unawaited(streamed.stream.listen((_) {}).cancel());
        throw ApiException(
          'Sunucu beklenmeyen bir yanıt verdi. Ağ bağlantınızı kontrol edip tekrar deneyin.',
          statusCode: 200,
          fromIntermediary: true,
        );
      }
      final declared = streamed.contentLength;
      if (declared != null &&
          declared > kDocumentAbsoluteMaxBytes + 1024 * 1024) {
        unawaited(streamed.stream.listen((_) {}).cancel());
        throw ApiException(
          'Belge çok büyük olduğu için indirilemedi.',
          statusCode: 413,
        );
      }
      final fileName = safeDocumentFileName(
        fileNameFromContentDisposition(streamed.headers['content-disposition']),
        fallback: safeDocumentFileName(fallbackName),
      );
      final mime = type.split(';').first.trim();
      sink = await openSink(
        fileName: fileName,
        mimeType: mime.isEmpty ? 'application/octet-stream' : mime,
        expectedLength: declared,
      );
      var received = 0;
      onProgress?.call(0, declared);
      await for (final chunk in streamed.stream.timeout(
        _downloadStallTimeout,
      )) {
        received += chunk.length;
        if (received > kDocumentAbsoluteMaxBytes + 1024 * 1024) {
          throw ApiException(
            'Belge çok büyük olduğu için indirilemedi.',
            statusCode: 413,
          );
        }
        await sink.add(chunk);
        onProgress?.call(received, declared);
      }
      if (declared != null && received != declared) {
        throw ApiException(
          'İndirme yarıda kesildi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      }
      final result = await sink.finish();
      sink = null;
      return result;
    } on http.RequestAbortedException {
      await sink?.abort();
      throw userCancelled
          ? const DocumentTransferCancelled()
          : ApiException(_downloadTransportMessage);
    } on TimeoutException {
      await sink?.abort();
      if (userCancelled) throw const DocumentTransferCancelled();
      throw ApiException(
        'Sunucu yanıt vermedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
    } on ApiException {
      await sink?.abort();
      rethrow;
    } catch (e) {
      await sink?.abort();
      if (userCancelled) throw const DocumentTransferCancelled();
      if (e is Error) rethrow;
      throw ApiException(_downloadTransportMessage);
    }
  }

  static const String _downloadTransportMessage =
      'İndirme sırasında bağlantı koptu. İnternet bağlantınızı kontrol edip tekrar deneyin.';

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
            : 'Sunucu yanıt vermedi. İşlem tamamlanmış olabilir; listeyi yenileyip kontrol edin.',
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

  /// Küçük bir yanıt gövdesini okur (en çok 1 MB; JSON hata / sonuç gövdeleri).
  Future<http.Response> _readBody(
    http.StreamedResponse streamed, {
    required Duration abortOnTimeout,
  }) async {
    const cap = 1024 * 1024;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream.timeout(abortOnTimeout)) {
      builder.add(chunk);
      if (builder.length > cap) break;
    }
    return http.Response.bytes(
      builder.takeBytes(),
      streamed.statusCode,
      headers: streamed.headers,
      request: streamed.request,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  // --- Hata çevirisi ------------------------------------------------------------------------

  ApiException _failure(http.Response response, {int? maxBytes}) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
      if (status == 413) {
        // Nginx 413 (HTML ya da gövdesiz): içerik sınırı aşıldı.
        return ApiException(
          documentErrorMessage('DOCUMENT_TOO_LARGE', maxBytes: maxBytes)!,
          statusCode: 413,
          code: 'DOCUMENT_TOO_LARGE',
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

    final mapped = documentErrorMessage(
      code,
      retryAfterSeconds: retryAfter,
      payload: body,
      maxBytes: maxBytes,
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

  /// Belgeler sözleşmesinin hata kodları için Türkçe metin (A9); bilinmiyorsa genel kodlar
  /// ([AuthApi.messageForErrorCode]) ya da null (sunucunun kendi `error` metni kullanılır).
  ///
  /// [maxBytes] dosya başına sınırdır (öğrenilmişse); bilinmiyorsa metin sayı vermez (sabit YAZILMAZ).
  static String? documentErrorMessage(
    String? code, {
    int? retryAfterSeconds,
    Map<String, dynamic>? payload,
    int? maxBytes,
  }) {
    if (code == null) return null;
    final serverMax = payload?['max_bytes'];
    final limit =
        maxBytes ??
        (serverMax is num && serverMax > 0 ? serverMax.toInt() : null);
    switch (code) {
      case 'DOCUMENT_TOO_LARGE':
        return limit == null
            ? 'Dosya çok büyük. Daha küçük bir dosya seçin.'
            : 'Dosya çok büyük. En fazla ${formatDocumentSize(limit)} yükleyebilirsiniz.';
      case 'DOCUMENT_TYPE_NOT_ALLOWED':
        return 'Bu dosya türü desteklenmiyor. ${DocumentFileRules.allowedLabel} yükleyin.';
      case 'DOCUMENT_CONTENT_MISMATCH':
        return 'Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.';
      case 'DOCUMENT_ACTIVE_CONTENT':
        return 'Etkin içerik (betik) taşıyan PDF yüklenemez.';
      case 'DOCUMENT_MALWARE_DETECTED':
        return 'Dosya zararlı yazılım içerdiği için reddedildi.';
      case 'SCAN_UNAVAILABLE':
        return 'Dosya taraması şu an yapılamıyor. Biraz sonra tekrar deneyin.';
      case 'DOCUMENT_EMPTY':
        return 'Seçilen dosya boş. Başka bir dosya seçin.';
      case 'DOCUMENT_SIZE_MISMATCH':
        return 'Dosya boyutu yükleme sırasında değişti. Dosyayı yeniden seçip tekrar deneyin.';
      case 'LENGTH_REQUIRED':
        return 'Yükleme isteği eksik gönderildi. Tekrar deneyin.';
      case 'DOCUMENT_QUOTA_EXCEEDED':
        return 'Site belge alanı doldu. Eski belgeleri kalıcı olarak silin.';
      case 'DOCUMENT_LIMIT':
        return 'Sitedeki belge sayısı sınırına ulaşıldı. Eski belgeleri kalıcı olarak silin.';
      case 'DOCUMENT_VERSION_LIMIT':
        return 'Bu belgenin sürüm sınırına ulaşıldı. Eski sürümleri silin.';
      case 'DOCUMENT_NOT_FOUND':
        return 'Belge bulunamadı ya da erişiminiz yok.';
      case 'DOCUMENT_VERSION_NOT_FOUND':
        return 'Belge sürümü bulunamadı.';
      case 'DOCUMENT_IN_USE':
        return 'Bu belge yayındaki bir duyuruya ekli.';
      case 'INVALID_TARGET':
        return 'Hedef geçersiz. Seçilen blok ve daireleri kontrol edin.';
      case 'ATTACHMENT_NOT_ALLOWED':
        return 'Bu belge duyuruya eklenemez. Yalnız sakinlere açık, yayındaki belgeler eklenebilir.';
      case 'UPLOAD_ALREADY_COMPLETED':
        return 'Bu yükleme zaten tamamlanmış.';
      case 'UPLOAD_PENDING_LIMIT':
        return 'Tamamlanmamış çok sayıda yüklemeniz var. Birkaç dakika sonra tekrar deneyin.';
      case 'UPLOAD_BUSY':
        return 'Sunucu meşgul. Biraz sonra tekrar deneyin.';
      case 'DOCUMENT_FILE_MISSING':
        return 'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.';
      case 'DOCUMENT_STORAGE_FULL':
      case 'DOCUMENT_STORAGE_NOT_CONFIGURED':
        return 'Belge yükleme şu an kullanılamıyor.';
      case 'INVALID_STATE':
        return 'Belgenin durumu değişmiş. Listeyi yenileyip tekrar deneyin.';
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

  static Map<String, dynamic> _objectOrEmpty(http.Response response) =>
      _tryObject(response.bodyBytes) ?? const <String, dynamic>{};

  @visibleForTesting
  static Map<String, dynamic>? debugTryObject(List<int> bytes) =>
      _tryObject(bytes);
}

/// Oturum belirtecini [AuthService]'ten alan, oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar
/// bunu kullanır (testlerde sahte [DocumentService] ile kurulur).
class DocumentService {
  DocumentService({
    required this.authService,
    DocumentApi? api,
    DocumentSinkFactory? sinkFactory,
  }) : api =
           api ??
           debugApiFactory?.call(authService) ??
           DocumentApi(baseUrl: authService.api.baseUrl),
       sinkFactory = sinkFactory ?? defaultDocumentSink;

  /// Test düzeneği: ekranlar servisi kendileri kurduğunda (ana sayfa içinde) sahte [DocumentApi] vermek için.
  @visibleForTesting
  static DocumentApi Function(AuthService authService)? debugApiFactory;

  final AuthService authService;
  final DocumentApi api;
  final DocumentSinkFactory sinkFactory;

  /// Sunucunun bildirdiği dosya başına sınır (son yükleme yanıtından); bilinmiyorsa null. Ön doğrulamada
  /// kullanılır, sabit YAZILMAZ.
  int? learnedMaxFileBytes;

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

  // --- Yönetici ---

  Future<DocumentPage> listManaged(
    int siteCode, {
    String? category,
    String status = 'active',
    String? audience,
    String? query,
    int limit = 30,
    int offset = 0,
  }) => _guard(
    (token) => api.listManaged(
      token: token,
      siteCode: siteCode,
      category: category,
      status: status,
      audience: audience,
      query: query,
      limit: limit,
      offset: offset,
    ),
  );

  Future<DocumentDetail> getManaged(int siteCode, int documentId) => _guard(
    (token) => api.getManaged(
      token: token,
      siteCode: siteCode,
      documentId: documentId,
    ),
  );

  Future<DocumentUploadTicket> createDocument(
    int siteCode,
    DocumentCreateRequest request,
  ) async {
    final ticket = await _guard(
      (token) => api.createDocument(
        token: token,
        siteCode: siteCode,
        request: request,
      ),
    );
    _learn(ticket);
    return ticket;
  }

  Future<DocumentUploadTicket> createVersion(
    int siteCode,
    int documentId,
    DocumentFileInput file, {
    String? note,
  }) async {
    final ticket = await _guard(
      (token) => api.createVersion(
        token: token,
        siteCode: siteCode,
        documentId: documentId,
        file: file,
        note: note,
      ),
    );
    _learn(ticket);
    return ticket;
  }

  void _learn(DocumentUploadTicket ticket) {
    final max = ticket.upload.maxBytes;
    if (max != null && max > 0) learnedMaxFileBytes = max;
  }

  Future<DocumentSummary> uploadContent(
    DocumentUploadInfo upload,
    DocumentUploadSource source, {
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) => _guard(
    (token) => api.uploadContent(
      token: token,
      upload: upload,
      source: source,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  Future<DocumentDetail> updateDocument(
    int siteCode,
    int documentId,
    Map<String, Object?> fields, {
    bool confirm = false,
  }) => _guard(
    (token) => api.updateDocument(
      token: token,
      siteCode: siteCode,
      documentId: documentId,
      fields: fields,
      confirm: confirm,
    ),
  );

  Future<void> deleteDocument(
    int siteCode,
    int documentId, {
    bool confirm = false,
  }) => _guard(
    (token) => api.deleteDocument(
      token: token,
      siteCode: siteCode,
      documentId: documentId,
      confirm: confirm,
    ),
  );

  Future<void> restoreDocument(int siteCode, int documentId) => _guard(
    (token) => api.restoreDocument(
      token: token,
      siteCode: siteCode,
      documentId: documentId,
    ),
  );

  Future<void> purgeDocument(int siteCode, int documentId) => _guard(
    (token) => api.purgeDocument(
      token: token,
      siteCode: siteCode,
      documentId: documentId,
    ),
  );

  Future<void> deleteVersion(int siteCode, int documentId, int versionNo) =>
      _guard(
        (token) => api.deleteVersion(
          token: token,
          siteCode: siteCode,
          documentId: documentId,
          versionNo: versionNo,
        ),
      );

  Future<DownloadedDocument> downloadManaged(
    int siteCode,
    int documentId, {
    int? version,
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) => _guard(
    (token) => api.downloadManaged(
      token: token,
      siteCode: siteCode,
      documentId: documentId,
      version: version,
      openSink: sinkFactory,
      fallbackName: fallbackName,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  // --- Sakin ---

  Future<ResidentDocumentPage> listMine({
    int? siteCode,
    String? category,
    String? query,
    int limit = 30,
    int? beforeId,
  }) => _guard(
    (token) => api.listMine(
      token: token,
      siteCode: siteCode,
      category: category,
      query: query,
      limit: limit,
      beforeId: beforeId,
    ),
  );

  Future<ResidentDocument> getMine(int documentId) =>
      _guard((token) => api.getMine(token: token, documentId: documentId));

  Future<DownloadedDocument> downloadMine(
    int documentId, {
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) => _guard(
    (token) => api.downloadMine(
      token: token,
      documentId: documentId,
      openSink: sinkFactory,
      fallbackName: fallbackName,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );

  Future<DownloadedDocument> downloadAnnouncementAttachment(
    int announcementId,
    int documentId, {
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) => _guard(
    (token) => api.downloadAnnouncementAttachment(
      token: token,
      announcementId: announcementId,
      documentId: documentId,
      openSink: sinkFactory,
      fallbackName: fallbackName,
      onProgress: onProgress,
      cancel: cancel,
    ),
  );
}
