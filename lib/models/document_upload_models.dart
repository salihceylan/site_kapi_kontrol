// Belge yükleme modelleri ve istemci tarafı ön doğrulama (docs/PLATFORM_BELGELER.md A3, A4, A7).
//
// Ön doğrulama YALNIZ kullanıcıyı bant genişliği harcamadan uyarmak içindir; SUNUCU esastır (içerik imzasına
// bakar, istemcinin bildirdiği tür / ad / boyut hiçbir güvenlik kararına girmez).
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmInt, crmText;

/// Sunucunun kabul edebileceği mutlak üst sınır (`DOCUMENTS_MAX_FILE_BYTES` en çok 25 MiB; bunun üstü sunucuda
/// yok sayılır). Yalnız makullük sınırıdır: gerçek dosya başına sınır yükleme yanıtından (`upload.max_bytes`)
/// öğrenilir ve sabit yazılmaz.
const int kDocumentAbsoluteMaxBytes = 26214400;

/// Başlık / açıklama / not uzunluk sınırları (sözleşme A5; sunucu da aynı birimle (kod noktası) sayar).
const int kDocumentTitleMax = 120;
const int kDocumentDescriptionMax = 1000;
const int kDocumentNoteMax = 200;

/// Seçilen dosya için istemci kuralları (tür izin listesi: PDF, JPEG, PNG, DOCX, XLSX).
abstract final class DocumentFileRules {
  /// Dosya seçicide gösterilecek uzantılar (noktasız, küçük harf).
  static const List<String> pickerExtensions = <String>[
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'docx',
    'xlsx',
  ];

  /// Sunucunun kanonik uzantıya eşlediği kabul edilen uzantılar (`jpeg`, `jpe` -> `jpg`).
  static const Set<String> allowedExtensions = <String>{
    'pdf',
    'jpg',
    'jpeg',
    'jpe',
    'png',
    'docx',
    'xlsx',
  };

  /// Kullanıcıya gösterilen tür listesi.
  static const String allowedLabel = 'PDF, JPG, PNG, DOCX veya XLSX';

  /// `rapor.PDF` -> `pdf`; uzantı yoksa null.
  static String? extensionOf(String fileName) {
    final name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }

  /// Seçilen dosyanın ön denetimi; sorun yoksa null, varsa Türkçe kullanıcı metni.
  ///
  /// - uzantı varsa izin listesinde olmalı (uzantısız ad sunucuda kabul edilir: içerik imzasına bakılır),
  /// - boş dosya olmaz,
  /// - [maxBytes] (öğrenildiyse) ve mutlak üst sınır ([kDocumentAbsoluteMaxBytes]) aşılmaz,
  /// - [remainingQuotaBytes] (liste yanıtındaki kullanımdan; 0 ya da null = bilinmiyor) aşılmaz.
  static String? validate({
    required String fileName,
    required int size,
    int? maxBytes,
    int? remainingQuotaBytes,
  }) {
    final ext = extensionOf(fileName);
    if (ext != null && !allowedExtensions.contains(ext)) {
      return 'Bu dosya türü desteklenmiyor. $allowedLabel yükleyin.';
    }
    if (size <= 0) return 'Seçilen dosya boş. Başka bir dosya seçin.';
    final limit =
        (maxBytes != null &&
            maxBytes > 0 &&
            maxBytes < kDocumentAbsoluteMaxBytes)
        ? maxBytes
        : kDocumentAbsoluteMaxBytes;
    if (size > limit) {
      return 'Dosya çok büyük (${formatDocumentSize(size)}). '
          'En fazla ${formatDocumentSize(limit)} yükleyebilirsiniz.';
    }
    if (remainingQuotaBytes != null &&
        remainingQuotaBytes > 0 &&
        size > remainingQuotaBytes) {
      return 'Site belge alanı yetmiyor (kalan ${formatDocumentSize(remainingQuotaBytes)}). '
          'Eski belgeleri kalıcı olarak silin.';
    }
    return null;
  }

  /// Kota ön uyarısı (YUMUŞAK): liste yanıtındaki kullanım bayat olabilir (başka bir yönetici belge silmiş
  /// olabilir); bu yüzden dosyayı REDDETMEZ, yalnız uyarır. Kesin karar sunucudadır (409
  /// `DOCUMENT_QUOTA_EXCEEDED`). Kalan alan bilinmiyorsa (null ya da 0) uyarı yoktur.
  static String? quotaWarning({required int size, int? remainingQuotaBytes}) {
    if (remainingQuotaBytes == null ||
        remainingQuotaBytes <= 0 ||
        size <= remainingQuotaBytes) {
      return null;
    }
    return 'Site belge alanı yetmeyebilir (kalan ${formatDocumentSize(remainingQuotaBytes)}). '
        'Yine de yüklemeyi deneyebilirsiniz; sunucu kesin kararı verir. Olmazsa eski belgeleri kalıcı olarak silin.';
  }

  /// Bilgi amaçlı `content_type` (sunucu YOK SAYAR; yalnız günlük / hata ayıklama için).
  static String? contentTypeOf(String fileName) {
    switch (extensionOf(fileName)) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
      case 'jpe':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return null;
  }
}

/// `file: { name, size, content_type? }` (yükleme adım 1).
@immutable
class DocumentFileInput {
  const DocumentFileInput({
    required this.name,
    required this.size,
    this.contentType,
  });

  final String name;
  final int size;
  final String? contentType;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'size': size,
    if (contentType != null) 'content_type': contentType,
  };
}

/// Yeni belge oluşturma isteği (`POST .../documents`).
@immutable
class DocumentCreateRequest {
  const DocumentCreateRequest({
    required this.title,
    required this.category,
    required this.audience,
    required this.file,
    required this.idempotencyKey,
    this.description,
    this.target,
    this.note,
  });

  final String title;
  final DocumentCategory category;
  final DocumentAudience audience;
  final DocumentFileInput file;
  final String idempotencyKey;
  final String? description;

  /// Yalnız `audience == residents` iken gönderilir.
  final DocumentTargetInput? target;
  final String? note;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title.trim(),
    if ((description ?? '').trim().isNotEmpty)
      'description': description!.trim(),
    'category': category.apiValue,
    'audience': audience.apiValue,
    if (audience == DocumentAudience.residents && target != null)
      'target': target!.toJson(),
    'file': file.toJson(),
    if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
    'idempotency_key': idempotencyKey,
  };
}

/// Yükleme adım 2 tanımı (`upload`): `PUT` + `application/octet-stream`.
@immutable
class DocumentUploadInfo {
  const DocumentUploadInfo({
    required this.path,
    this.method = 'PUT',
    this.contentType = 'application/octet-stream',
    this.size = 0,
    this.maxBytes,
    this.expiresAt,
  });

  /// Sunucu yolu (`/manager/sites/<site>/documents/<id>/versions/<no>/content`).
  final String path;
  final String method;
  final String contentType;

  /// Bildirilen boyut: `Content-Length` bununla BİREBİR aynı olmalıdır.
  final int size;

  /// Sunucunun dosya başına sınırı (öğrenilen değer; sabit yazılmaz).
  final int? maxBytes;
  final DateTime? expiresAt;

  factory DocumentUploadInfo.fromJson(Map<String, dynamic> json) =>
      DocumentUploadInfo(
        path: crmText(json['path']) ?? '',
        method: (crmText(json['method']) ?? 'PUT').toUpperCase(),
        contentType:
            crmText(json['content_type']) ?? 'application/octet-stream',
        size: crmInt(json['size']),
        maxBytes: json['max_bytes'] == null ? null : crmInt(json['max_bytes']),
        expiresAt: documentInstant(json['expires_at']),
      );
}

/// `POST .../documents` ya da `POST .../:id/versions` yanıtı (201): bekleyen belge + sürüm + yükleme tanımı.
@immutable
class DocumentUploadTicket {
  const DocumentUploadTicket({
    required this.document,
    required this.upload,
    this.version,
    this.warnings = const <String>[],
  });

  final DocumentSummary document;
  final DocumentVersion? version;
  final DocumentUploadInfo upload;

  /// Bilgi amaçlı uyarı kodları (örn. `DUPLICATE_CONTENT`); engellemez.
  final List<String> warnings;

  factory DocumentUploadTicket.fromJson(Map<String, dynamic> json) {
    final docRaw = json['document'];
    final verRaw = json['version'];
    final uploadRaw = json['upload'];
    final warnings = <String>[];
    final rawWarnings = json['warnings'];
    if (rawWarnings is List) {
      for (final w in rawWarnings) {
        final text = w is Map ? crmText(w['code']) : crmText(w);
        if (text != null) warnings.add(text);
      }
    }
    return DocumentUploadTicket(
      document: docRaw is Map
          ? DocumentSummary.fromJson(Map<String, dynamic>.from(docRaw))
          : const DocumentSummary(id: 0),
      version: verRaw is Map
          ? DocumentVersion.fromJson(Map<String, dynamic>.from(verRaw))
          : null,
      upload: uploadRaw is Map
          ? DocumentUploadInfo.fromJson(Map<String, dynamic>.from(uploadRaw))
          : const DocumentUploadInfo(path: ''),
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}
