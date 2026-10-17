// Platform Faz 3b-A (Belgeler): ekran / pencere testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (docs/PLATFORM_BELGELER.md Bölüm A): belgeler bellekte tutulur, yanıtlar
// sunucunun gerçek JSON biçiminde üretilip modellerle ayrıştırılır; listeler süzgeç / arama / sayfalama
// (limit-offset ve before_id imleci) uygular; kurul `managers` belgesini ve silinenleri görmez; yazmalar kaydı
// değiştirir ve sunucu kurallarını (DOCUMENT_IN_USE, INVALID_STATE, MODULE_DISABLED) aynı Türkçe iletilerle
// uygular. Yarış / ilerleme testleri için her çağrı kuyruktaki bir kapıyı bekleyebilir.
import 'dart:async';
import 'dart:typed_data';

import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';

import 'people_fixtures.dart';

/// Sahte kimlik doğrulama (kişi / daire / blok uçları PeopleFakeAuth'tan gelir).
class DocumentFakeAuth extends PeopleFakeAuth {
  DocumentFakeAuth({super.role, super.sites, super.blocks});
}

/// Bellekteki bir sürüm.
class FakeVersion {
  FakeVersion(
    this.no, {
    this.fileName = 'yonetmelik.pdf',
    this.mime = 'application/pdf',
    this.size = 2516582,
    this.note,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.utc(2026, 10, 16, 10);

  final int no;
  String fileName;
  String mime;
  int size;
  String? note;
  DateTime completedAt;
}

/// Bellekteki bir belge (sunucu satırı).
class FakeDoc {
  FakeDoc(
    this.id, {
    this.title = 'Site Yönetmeliği',
    this.description = '',
    this.category = 'regulation',
    this.audience = 'residents',
    this.targetType = 'site',
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
    this.status = 'active',
    this.downloads = 3,
    this.siteCode = 11,
    this.daysUntilPurge,
    this.attachedAnnouncements = const <int>[],
    List<FakeVersion>? versions,
    DateTime? updatedAt,
  }) : versions = versions ?? <FakeVersion>[FakeVersion(1)],
       updatedAt = updatedAt ?? DateTime.utc(2026, 10, 16, 10);

  final int id;
  String title;
  String description;
  String category;
  String audience;
  String targetType;
  List<int> blockIds;
  List<int> apartmentIds;
  String status;
  int downloads;
  int siteCode;
  int? daysUntilPurge;
  List<int> attachedAnnouncements;
  List<FakeVersion> versions;
  DateTime updatedAt;

  FakeVersion get current => versions.reduce((a, b) => a.no >= b.no ? a : b);
}

/// Belge uçları için sahte servis. Çağrılar kaydedilir; yanıtlar testten sürülür.
class FakeDocumentService extends DocumentService {
  FakeDocumentService({required super.authService, this.board = false})
    : super(api: DocumentApi(baseUrl: 'http://localhost'));

  /// Kurul görünümü: `managers` belgeleri ve silinenler görünmez, yükleyen adı yok.
  bool board;

  final Map<int, FakeDoc> docs = <int, FakeDoc>{};
  int usedBytes = 44040192;
  int quotaBytes = 209715200;
  int documentLimit = 2000;

  /// Sakin görünümünde `site_name` ve görünürlük.
  String siteName = 'Gül Sitesi';
  final Set<int> residentVisible = <int>{};

  // --- Çağrı kayıtları ---
  final List<
    ({
      int site,
      String? category,
      String status,
      String? audience,
      String? query,
      int limit,
      int offset,
    })
  >
  listCalls = [];
  final List<
    ({String? category, String? query, int? site, int? before, int limit})
  >
  mineCalls = [];
  final List<DocumentCreateRequest> createCalls = [];
  final List<({int id, DocumentFileInput file, String? note})> versionCalls =
      [];
  final List<({int id, Map<String, Object?> fields, bool confirm})>
  updateCalls = [];
  final List<({int id, bool confirm})> deleteCalls = [];
  final List<int> restoreCalls = [];
  final List<int> purgeCalls = [];
  final List<({int id, int no})> deleteVersionCalls = [];
  final List<({int id, int? version})> downloadCalls = [];
  final List<int> mineDownloadCalls = [];
  final List<({int announcement, int document})> attachmentDownloadCalls = [];
  int uploadCalls = 0;
  final List<int> uploadSizes = [];

  // --- Sürücüler ---
  final List<Completer<void>> listGates = <Completer<void>>[];
  final List<Completer<void>> detailGates = <Completer<void>>[];
  final List<Completer<void>> uploadGates = <Completer<void>>[];

  /// %100 sonrası (gövde gitti, yanıt bekleniyor) tutan kapılar.
  final List<Completer<void>> uploadFinalGates = <Completer<void>>[];

  /// Geç iptalde (yanıt beklenirken) sunucu isteği yine de işler.
  bool serverCompletesOnLateCancel = false;
  final List<Completer<void>> downloadGates = <Completer<void>>[];
  final List<Completer<void>> writeGates = <Completer<void>>[];
  final List<Completer<void>> createGates = <Completer<void>>[];

  Object? listError;
  Object? detailError;
  Object? createError;
  Object? uploadError;
  Object? downloadError;
  Object? writeError;
  Object? mineError;

  /// Yükleme ilerleme adımı sayısı (her adım sonrası kapı beklenebilir).
  int uploadSteps = 4;

  /// Bir sonraki silmede DOCUMENT_IN_USE (onaysız) döner.
  int inUseAttachments = 0;

  /// Yükleme için indirme baytları (sahte).
  Uint8List downloadBytes = Uint8List.fromList(
    List<int>.generate(3000, (i) => i % 251),
  );

  int _nextId = 1000;
  final Map<String, int> _idempotency = <String, int>{};
  final Map<int, int> _pendingVersionNo = <int, int>{};

  // --- Yardımcılar ---

  Future<void> _gate(List<Completer<void>> queue) async {
    if (queue.isEmpty) return;
    final gate = queue.removeAt(0);
    await gate.future;
  }

  ApiException _coded(String code, int status, [String? message]) =>
      ApiException(
        message ??
            DocumentApi.documentErrorMessage(code) ??
            'İşlem başarısız ($status)',
        statusCode: status,
        code: code,
      );

  FakeDoc _doc(int id) {
    final doc = docs[id];
    if (doc == null) throw _coded('DOCUMENT_NOT_FOUND', 404);
    return doc;
  }

  Map<String, dynamic> _versionJson(FakeVersion v, FakeDoc d) =>
      <String, dynamic>{
        'version_no': v.no,
        'file_name': v.fileName,
        'mime_type': v.mime,
        'size_bytes': v.size,
        'sha256': 'a' * 64,
        'note': v.note,
        'completed_at': v.completedAt.toIso8601String(),
        if (!board) 'uploaded_by_name': 'Site Yöneticisi',
        'is_current': v.no == d.current.no,
      };

  Map<String, dynamic> summaryJson(FakeDoc d) => <String, dynamic>{
    'id': d.id,
    'title': d.title,
    'category': d.category,
    'audience': d.audience,
    'target_type': d.targetType,
    'status': d.status,
    'version_count': d.versions.length,
    'download_count': d.downloads,
    'current_version': <String, dynamic>{
      'version_no': d.current.no,
      'file_name': d.current.fileName,
      'mime_type': d.current.mime,
      'size_bytes': d.current.size,
      'completed_at': d.current.completedAt.toIso8601String(),
    },
    'created_at': '2026-10-15T10:00:00Z',
    'updated_at': d.updatedAt.toIso8601String(),
    'deleted_at': d.status == 'deleted' ? '2026-10-16T08:00:00Z' : null,
    'days_until_purge': d.status == 'deleted' ? (d.daysUntilPurge ?? 30) : null,
    if (!board) 'uploaded_by_name': 'Site Yöneticisi',
    if (d.targetType == 'blocks')
      'target_labels': <String>[for (final b in d.blockIds) _blockName(b)],
  };

  String _blockName(int id) => id == 1 ? 'A' : (id == 2 ? 'B' : 'C');

  Map<String, dynamic> detailJson(FakeDoc d) => <String, dynamic>{
    ...summaryJson(d),
    'description': d.description,
    'target': <String, dynamic>{
      'type': d.targetType,
      'block_ids': d.blockIds,
      'apartment_ids': d.apartmentIds,
      'blocks': <Object>[
        for (final b in d.blockIds)
          <String, dynamic>{'id': b, 'name': _blockName(b)},
      ],
      'apartments': <Object>[
        for (final a in d.apartmentIds)
          <String, dynamic>{'id': a, 'label': 'A Blok - $a'},
      ],
    },
    'versions': <Object>[for (final v in d.versions) _versionJson(v, d)],
    if (!board)
      'attached_announcements': <Object>[
        for (final a in d.attachedAnnouncements)
          <String, dynamic>{'id': a, 'status': 'published'},
      ],
  };

  bool _visibleToBoard(FakeDoc d) =>
      d.status == 'active' && d.audience != 'managers';

  // --- Yönetici uçları ---

  @override
  Future<DocumentPage> listManaged(
    int siteCode, {
    String? category,
    String status = 'active',
    String? audience,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    listCalls.add((
      site: siteCode,
      category: category,
      status: status,
      audience: audience,
      query: query,
      limit: limit,
      offset: offset,
    ));
    final snapshot = _filtered(siteCode, category, status, audience, query);
    final page = snapshot.skip(offset).take(limit).toList();
    final json = <String, dynamic>{
      'items': <Object>[for (final d in page) summaryJson(d)],
      'total': snapshot.length,
      'usage': <String, dynamic>{
        'used_bytes': usedBytes,
        'quota_bytes': quotaBytes,
        'document_count': docs.length,
        'document_limit': documentLimit,
      },
    };
    await _gate(listGates);
    final error = listError;
    if (error != null) throw error;
    return DocumentPage.fromJson(json);
  }

  List<FakeDoc> _filtered(
    int siteCode,
    String? category,
    String status,
    String? audience,
    String? query,
  ) {
    final q = (query ?? '').trim().toLowerCase();
    final rows = docs.values.where((d) {
      if (d.siteCode != siteCode) return false;
      if (board && !_visibleToBoard(d)) return false;
      if (d.status == 'pending') return false;
      if (status != 'all' && d.status != status) return false;
      if (category != null && category.isNotEmpty && d.category != category) {
        return false;
      }
      if (audience != null && audience.isNotEmpty && d.audience != audience) {
        return false;
      }
      if (q.isNotEmpty &&
          !d.title.toLowerCase().contains(q) &&
          !d.description.toLowerCase().contains(q) &&
          !d.current.fileName.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.id.compareTo(a.id));
    return rows;
  }

  @override
  Future<DocumentDetail> getManaged(int siteCode, int documentId) async {
    final doc = docs[documentId];
    final json = doc == null ? null : detailJson(doc);
    await _gate(detailGates);
    final error = detailError;
    if (error != null) throw error;
    if (doc == null ||
        doc.siteCode != siteCode ||
        (board && !_visibleToBoard(doc))) {
      throw _coded('DOCUMENT_NOT_FOUND', 404);
    }
    return DocumentDetail.fromJson(json!);
  }

  @override
  Future<DocumentUploadTicket> createDocument(
    int siteCode,
    DocumentCreateRequest request,
  ) async {
    createCalls.add(request);
    await _gate(createGates);
    final error = createError;
    if (error != null) throw error;
    if (request.title.trim().isEmpty) {
      throw _coded('INVALID_BODY', 400, 'Başlık boş olamaz.');
    }
    final existing = _idempotency[request.idempotencyKey];
    final FakeDoc doc;
    if (existing != null) {
      doc = docs[existing]!;
    } else {
      final id = ++_nextId;
      doc = FakeDoc(
        id,
        title: request.title.trim(),
        description: (request.description ?? '').trim(),
        category: request.category.apiValue,
        audience: request.audience.apiValue,
        targetType: request.target?.type.apiValue ?? 'site',
        blockIds: request.target?.blockIds ?? const <int>[],
        apartmentIds: request.target?.apartmentIds ?? const <int>[],
        status: 'pending',
        downloads: 0,
        siteCode: siteCode,
        versions: <FakeVersion>[
          FakeVersion(1, fileName: request.file.name, size: request.file.size),
        ],
      );
      docs[id] = doc;
      _idempotency[request.idempotencyKey] = id;
    }
    _pendingVersionNo[doc.id] = 1;
    return _ticket(doc, 1, request.file.size);
  }

  DocumentUploadTicket _ticket(FakeDoc doc, int versionNo, int size) {
    final learned = 10485760;
    learnedMaxFileBytes = learned;
    return DocumentUploadTicket.fromJson(<String, dynamic>{
      'document': summaryJson(doc),
      'version': <String, dynamic>{'version_no': versionNo},
      'upload': <String, dynamic>{
        'method': 'PUT',
        'path':
            '/manager/sites/${doc.siteCode}/documents/${doc.id}/versions/$versionNo/content',
        'content_type': 'application/octet-stream',
        'size': size,
        'max_bytes': learned,
        'expires_at': '2099-01-01T00:00:00Z',
      },
    });
  }

  @override
  Future<DocumentUploadTicket> createVersion(
    int siteCode,
    int documentId,
    DocumentFileInput file, {
    String? note,
  }) async {
    versionCalls.add((id: documentId, file: file, note: note));
    await _gate(createGates);
    final error = createError;
    if (error != null) throw error;
    final doc = _doc(documentId);
    if (doc.status != 'active') throw _coded('INVALID_STATE', 409);
    final next =
        doc.versions.map((v) => v.no).reduce((a, b) => a > b ? a : b) + 1;
    _pendingVersionNo[doc.id] = next;
    _pendingVersionFile[doc.id] = (file: file, note: note);
    return _ticket(doc, next, file.size);
  }

  final Map<int, ({DocumentFileInput file, String? note})> _pendingVersionFile =
      {};

  @override
  Future<DocumentSummary> uploadContent(
    DocumentUploadInfo upload,
    DocumentUploadSource source, {
    void Function(int sent, int total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    uploadCalls++;
    uploadSizes.add(source.size);
    final match = RegExp(
      r'/documents/(\d+)/versions/(\d+)/content$',
    ).firstMatch(upload.path)!;
    final id = int.parse(match.group(1)!);
    final no = int.parse(match.group(2)!);
    final total = upload.size;
    for (var step = 1; step <= uploadSteps; step++) {
      if (cancel != null && cancel.isCancelled) {
        throw const DocumentTransferCancelled();
      }
      await _gate(uploadGates);
      if (cancel != null && cancel.isCancelled) {
        throw const DocumentTransferCancelled();
      }
      onProgress?.call(total * step ~/ uploadSteps, total);
    }
    // Gövde tamamen gitti (%100): sunucu yanıtı bekleniyor. Burada iptal gelirse gerçek sunucu isteği yine de
    // işlemiş olabilir ([serverCompletesOnLateCancel]).
    await _gate(uploadFinalGates);
    if (cancel != null && cancel.isCancelled) {
      if (serverCompletesOnLateCancel) _completeUpload(id, no, source);
      throw const DocumentTransferCancelled();
    }
    final error = uploadError;
    if (error != null) throw error;
    return _completeUpload(id, no, source);
  }

  /// Sunucu tarafı tamamlama; aynı sürüm ikinci kez gelirse (409 UPLOAD_ALREADY_COMPLETED) yinelenmez.
  DocumentSummary _completeUpload(int id, int no, DocumentUploadSource source) {
    final doc = _doc(id);
    final alreadyDone =
        (no == 1 && doc.status == 'active') ||
        (doc.status == 'active' && doc.versions.any((v) => v.no == no));
    if (alreadyDone) return DocumentSummary.fromJson(summaryJson(doc));
    if (no == 1 && doc.status == 'pending') {
      doc.status = 'active';
      doc.versions = <FakeVersion>[
        FakeVersion(1, fileName: source.name, size: source.size),
      ];
    } else {
      final pending = _pendingVersionFile[id];
      doc.versions.add(
        FakeVersion(
          no,
          fileName: source.name,
          size: source.size,
          note: pending?.note,
          completedAt: DateTime.utc(2026, 10, 17, 9),
        ),
      );
    }
    usedBytes += source.size;
    doc.updatedAt = DateTime.utc(2026, 10, 17, 9);
    return DocumentSummary.fromJson(summaryJson(doc));
  }

  @override
  Future<DocumentDetail> updateDocument(
    int siteCode,
    int documentId,
    Map<String, Object?> fields, {
    bool confirm = false,
  }) async {
    updateCalls.add((
      id: documentId,
      fields: Map<String, Object?>.of(fields),
      confirm: confirm,
    ));
    await _gate(writeGates);
    final error = writeError;
    if (error != null) throw error;
    final doc = _doc(documentId);
    // Sunucu gibi: sakinlere açık belge başka kitleye çevrilirken YAYINDAKİ duyuruya ekliyse onay ister;
    // onaylanınca duyuru ekleri çıkarılır.
    final nextAudience = fields['audience'] as String?;
    if (nextAudience != null &&
        nextAudience != 'residents' &&
        doc.audience == 'residents' &&
        doc.attachedAnnouncements.isNotEmpty) {
      if (!confirm) {
        throw ApiException(
          'x',
          statusCode: 409,
          code: 'DOCUMENT_IN_USE',
          payload: <String, dynamic>{
            'attachments_count': doc.attachedAnnouncements.length,
          },
        );
      }
      doc.attachedAnnouncements = <int>[];
    }
    if (fields.containsKey('title')) doc.title = fields['title']! as String;
    if (fields.containsKey('description')) {
      doc.description = fields['description']! as String;
    }
    if (fields.containsKey('category')) {
      doc.category = fields['category']! as String;
    }
    if (fields.containsKey('audience')) {
      doc.audience = fields['audience']! as String;
    }
    final target = fields['target'];
    if (target is Map) {
      doc.targetType = target['type'] as String;
      doc.blockIds = List<int>.of(
        (target['block_ids'] as List?)?.cast<int>() ?? const <int>[],
      );
      doc.apartmentIds = List<int>.of(
        (target['apartment_ids'] as List?)?.cast<int>() ?? const <int>[],
      );
    }
    return DocumentDetail.fromJson(detailJson(doc));
  }

  @override
  Future<void> deleteDocument(
    int siteCode,
    int documentId, {
    bool confirm = false,
  }) async {
    deleteCalls.add((id: documentId, confirm: confirm));
    await _gate(writeGates);
    final error = writeError;
    if (error != null) throw error;
    final doc = _doc(documentId);
    if (inUseAttachments > 0 && !confirm) {
      throw ApiException(
        'x',
        statusCode: 409,
        code: 'DOCUMENT_IN_USE',
        payload: <String, dynamic>{'attachments_count': inUseAttachments},
      );
    }
    doc.status = 'deleted';
    doc.daysUntilPurge = 30;
  }

  @override
  Future<void> restoreDocument(int siteCode, int documentId) async {
    restoreCalls.add(documentId);
    await _gate(writeGates);
    final error = writeError;
    if (error != null) throw error;
    final doc = _doc(documentId);
    if (doc.status != 'deleted') throw _coded('INVALID_STATE', 409);
    doc.status = 'active';
  }

  @override
  Future<void> purgeDocument(int siteCode, int documentId) async {
    purgeCalls.add(documentId);
    await _gate(writeGates);
    final error = writeError;
    if (error != null) throw error;
    final doc = _doc(documentId);
    if (doc.status != 'deleted') throw _coded('INVALID_STATE', 409);
    docs.remove(documentId);
  }

  @override
  Future<void> deleteVersion(
    int siteCode,
    int documentId,
    int versionNo,
  ) async {
    deleteVersionCalls.add((id: documentId, no: versionNo));
    await _gate(writeGates);
    final error = writeError;
    if (error != null) throw error;
    final doc = _doc(documentId);
    if (doc.versions.length <= 1) throw _coded('INVALID_STATE', 409);
    doc.versions.removeWhere((v) => v.no == versionNo);
  }

  DownloadedDocument _download(String name, String mime) => DownloadedDocument(
    fileName: name,
    mimeType: mime,
    sizeBytes: downloadBytes.length,
    bytes: downloadBytes,
  );

  Future<DownloadedDocument> _runDownload(
    String name,
    String mime,
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  ) async {
    onProgress?.call(0, downloadBytes.length);
    await _gate(downloadGates);
    if (cancel != null && cancel.isCancelled) {
      throw const DocumentTransferCancelled();
    }
    final error = downloadError;
    if (error != null) throw error;
    onProgress?.call(downloadBytes.length, downloadBytes.length);
    return _download(name, mime);
  }

  @override
  Future<DownloadedDocument> downloadManaged(
    int siteCode,
    int documentId, {
    int? version,
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    downloadCalls.add((id: documentId, version: version));
    final doc = _doc(documentId);
    final v = version == null
        ? doc.current
        : doc.versions.firstWhere((v) => v.no == version);
    return _runDownload(v.fileName, v.mime, onProgress, cancel);
  }

  // --- Sakin uçları ---

  Map<String, dynamic> residentJson(FakeDoc d) => <String, dynamic>{
    'id': d.id,
    'site_code': d.siteCode,
    'site_name': siteName,
    'title': d.title,
    'category': d.category,
    'description': d.description,
    'file_name': d.current.fileName,
    'mime_type': d.current.mime,
    'size_bytes': d.current.size,
    'version_no': d.current.no,
    'is_updated': d.current.no > 1,
    'updated_at': d.updatedAt.toIso8601String(),
  };

  @override
  Future<ResidentDocumentPage> listMine({
    int? siteCode,
    String? category,
    String? query,
    int limit = 30,
    int? beforeId,
  }) async {
    mineCalls.add((
      category: category,
      query: query,
      site: siteCode,
      before: beforeId,
      limit: limit,
    ));
    final q = (query ?? '').trim().toLowerCase();
    final rows = docs.values.where((d) {
      if (d.status != 'active' || d.audience != 'residents') return false;
      if (residentVisible.isNotEmpty && !residentVisible.contains(d.id)) {
        return false;
      }
      if (siteCode != null && d.siteCode != siteCode) return false;
      if (category != null && category.isNotEmpty && d.category != category) {
        return false;
      }
      if (q.isNotEmpty && !d.title.toLowerCase().contains(q)) return false;
      if (beforeId != null && d.id >= beforeId) return false;
      return true;
    }).toList()..sort((a, b) => b.id.compareTo(a.id));
    final page = rows.take(limit).toList();
    final next = rows.length > page.length ? page.last.id : null;
    final json = <String, dynamic>{
      'items': <Object>[for (final d in page) residentJson(d)],
      'next_before_id': next,
    };
    await _gate(listGates);
    final error = mineError ?? listError;
    if (error != null) throw error;
    return ResidentDocumentPage.fromJson(json);
  }

  @override
  Future<ResidentDocument> getMine(int documentId) async {
    final doc = _doc(documentId);
    return ResidentDocument.fromJson(residentJson(doc));
  }

  @override
  Future<DownloadedDocument> downloadMine(
    int documentId, {
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    mineDownloadCalls.add(documentId);
    final doc = docs[documentId];
    if (doc == null) {
      await _gate(downloadGates);
      throw _coded('DOCUMENT_NOT_FOUND', 404);
    }
    return _runDownload(
      doc.current.fileName,
      doc.current.mime,
      onProgress,
      cancel,
    );
  }

  @override
  Future<DownloadedDocument> downloadAnnouncementAttachment(
    int announcementId,
    int documentId, {
    String fallbackName = 'belge',
    void Function(int received, int? total)? onProgress,
    DocumentCancelToken? cancel,
  }) async {
    attachmentDownloadCalls.add((
      announcement: announcementId,
      document: documentId,
    ));
    final doc = docs[documentId];
    return _runDownload(
      doc?.current.fileName ?? fallbackName,
      doc?.current.mime ?? 'application/pdf',
      onProgress,
      cancel,
    );
  }
}

/// Dosya seçici sahtesi: sıradaki kaynağı verir (ya da vazgeçer / hata fırlatır).
class FakeDocumentPicker implements DocumentPicker {
  FakeDocumentPicker([
    List<DocumentUploadSource?> queue = const <DocumentUploadSource?>[],
  ]) : queue = List<DocumentUploadSource?>.of(queue);

  final List<DocumentUploadSource?> queue;
  Object? error;
  int calls = 0;

  /// [release] çağrı sayısı (eklenti önbelleği temizliği).
  int releaseCalls = 0;

  @override
  Future<DocumentUploadSource?> pick() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return queue.isEmpty ? null : queue.removeAt(0);
  }

  @override
  Future<void> release() async => releaseCalls++;
}

/// Test kaynağı: bellekte [size] baytlık dosya.
MemoryDocumentSource fakeSource(String name, {int size = 2048}) =>
    MemoryDocumentSource(name, Uint8List(size));

/// Standart veri: yayında yönetmelik (v2, sakinlere, A blok), kurul belgesi, yöneticilere özel belge, silinmiş.
FakeDocumentService seededDocuments(
  DocumentFakeAuth auth, {
  bool board = false,
}) {
  final service = FakeDocumentService(authService: auth, board: board);
  service.docs[41] = FakeDoc(
    41,
    title: 'Site Yönetmeliği',
    description: 'Güncel site yönetmeliği.',
    category: 'regulation',
    audience: 'residents',
    targetType: 'blocks',
    blockIds: const <int>[1],
    downloads: 12,
    versions: <FakeVersion>[
      FakeVersion(1, fileName: 'yonetmelik-v1.pdf', size: 2000000),
      FakeVersion(
        2,
        fileName: 'yonetmelik-v2.pdf',
        size: 2516582,
        note: 'Madde 4 düzeltildi',
      ),
    ],
  );
  service.docs[40] = FakeDoc(
    40,
    title: 'Kurul Toplantı Tutanağı',
    category: 'minutes',
    audience: 'board',
    downloads: 1,
    versions: <FakeVersion>[
      FakeVersion(
        1,
        fileName: 'tutanak.docx',
        mime:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        size: 51200,
      ),
    ],
  );
  service.docs[39] = FakeDoc(
    39,
    title: 'Yönetici Sözleşmesi',
    category: 'contract',
    audience: 'managers',
    downloads: 0,
    versions: <FakeVersion>[
      FakeVersion(1, fileName: 'sozlesme.pdf', size: 800000),
    ],
  );
  service.docs[38] = FakeDoc(
    38,
    title: 'Eski Duyuru Afişi',
    category: 'notice',
    audience: 'residents',
    status: 'deleted',
    daysUntilPurge: 12,
    versions: <FakeVersion>[
      FakeVersion(1, fileName: 'afis.png', mime: 'image/png', size: 300000),
    ],
  );
  return service;
}

/// Sakin görünümü verisi: `count` belge (id 1..count), hepsi sakinlere açık.
FakeDocumentService residentDocuments(DocumentFakeAuth auth, {int count = 3}) {
  final service = FakeDocumentService(authService: auth);
  for (var i = 1; i <= count; i++) {
    service.docs[i] = FakeDoc(
      i,
      title: 'Belge $i',
      description: i == 1 ? 'Birinci belgenin açıklaması.' : '',
      category: i.isEven ? 'notice' : 'regulation',
      audience: 'residents',
      versions: <FakeVersion>[
        FakeVersion(1, fileName: 'belge-$i.pdf', size: 1024 * 1024 * i),
        if (i == 2)
          FakeVersion(2, fileName: 'belge-2-v2.pdf', size: 1024 * 1024),
      ],
    );
  }
  return service;
}

/// Yönetici oturumu rolü kısayolu.
UserRole get managerRole => UserRole.siteManager;
