// Platform Faz 3b-A (Belgeler / dosya deposu) modelleri. Sözleşme: docs/PLATFORM_BELGELER.md Bölüm A.
//
// Kurallar: alan yok / bozuk ise güvenli varsayılan (uygulama çökmez); bilinmeyen sayım değeri enum'lara
// düşmez (`unknown`); zaman damgaları evrensel an (UTC) okunur ve ekranda İstanbul saatiyle gösterilir.
// Kişisel veri en aza: bu modeller dosya adı / başlık taşır, ama HİÇBİR YERDE günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmInt, crmIntOrNull, crmText;

/// ISO 8601 zaman damgası -> UTC an. Saat dilimi OLMAYAN metin UTC sayılır. Bozuk değerde null.
DateTime? documentInstant(Object? raw) {
  if (raw == null) return null;
  var text = raw.toString().trim();
  if (text.isEmpty) return null;
  final hasZone = RegExp(
    r'(Z|[+-]\d{2}(?::?\d{2})?)$',
    caseSensitive: false,
  ).hasMatch(text);
  if (!hasZone) text = '${text.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(text)?.toUtc();
}

String _text(Object? raw) => raw?.toString().trim() ?? '';

bool _flag(Object? raw, {bool fallback = false}) =>
    raw is bool ? raw : fallback;

List<int> _intList(Object? raw) {
  if (raw is! List) return const <int>[];
  final result = <int>[];
  for (final item in raw) {
    final value = crmIntOrNull(item);
    if (value != null) result.add(value);
  }
  return List<int>.unmodifiable(result);
}

Map<String, dynamic>? _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : null;

/// "512 B", "12 KB", "2,4 MB" (ondalık ayırıcı Türkçe virgül).
String formatDocumentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return kb < 10 ? '${_oneDecimal(kb)} KB' : '${kb.round()} KB';
  }
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${_oneDecimal(mb)} MB' : '${mb.round()} MB';
}

String _oneDecimal(double value) =>
    value.toStringAsFixed(1).replaceFirst('.', ',');

/// Belge kategorisi (sunucu `category`).
enum DocumentCategory {
  regulation('regulation', 'Yönetmelik', 'Yönetmelik'),
  minutes('minutes', 'Toplantı Tutanağı / Karar', 'Tutanak / Karar'),
  contract('contract', 'Sözleşme', 'Sözleşme'),
  notice('notice', 'Bilgilendirme', 'Bilgilendirme'),
  other('other', 'Diğer', 'Diğer');

  const DocumentCategory(this.apiValue, this.label, this.shortLabel);

  final String apiValue;

  /// Tam ad (form ve ayrıntı).
  final String label;

  /// Süzgeç çipi ve kart çipi için kısa ad.
  final String shortLabel;

  static DocumentCategory fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final category in values) {
      if (category.apiValue == normalized) return category;
    }
    return DocumentCategory.other;
  }
}

/// Belgeyi kimlerin görebileceği (sunucu `audience`). Varsayılan YOKTUR: yükleyen açıkça seçer.
enum DocumentAudience {
  residents(
    'residents',
    'Sakinler',
    'Sakinlere açık; hedef olarak tüm site, bloklar ya da daireler seçilebilir.',
  ),
  board(
    'board',
    'Yönetim kurulu',
    'Yalnız yönetim kurulu ve yöneticiler görür.',
  ),
  managers(
    'managers',
    'Yalnız yöneticiler',
    'Yalnızca site yöneticileri görür.',
  ),
  unknown('', 'Kitle bilinmiyor', '');

  const DocumentAudience(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;

  /// Formda seçeneğin altındaki açıklama.
  final String description;

  /// Formda seçilebilen kitleler (`unknown` hariç).
  static const List<DocumentAudience> choices = <DocumentAudience>[
    residents,
    board,
    managers,
  ];

  static DocumentAudience fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final audience in values) {
      if (audience.apiValue.isNotEmpty && audience.apiValue == normalized) {
        return audience;
      }
    }
    return DocumentAudience.unknown;
  }
}

/// Sakin kitlesinin hedefi (yalnız `audience == residents` iken anlamlı).
enum DocumentTargetType {
  site('site', 'Tüm site'),
  blocks('blocks', 'Bloklar'),
  apartments('apartments', 'Daireler');

  const DocumentTargetType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DocumentTargetType fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final type in values) {
      if (type.apiValue == normalized) return type;
    }
    return DocumentTargetType.site;
  }
}

/// Belgenin yaşam döngüsü durumu. `pending`: ilk sürüm henüz yüklenmedi (listede görünmez).
enum DocumentStatus {
  pending('pending', 'Yükleniyor'),
  active('active', 'Yayında'),
  deleted('deleted', 'Silindi'),
  unknown('', 'Durum bilinmiyor');

  const DocumentStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DocumentStatus fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.apiValue.isNotEmpty && status.apiValue == normalized) {
        return status;
      }
    }
    return DocumentStatus.unknown;
  }
}

/// Dosya türü (kanonik MIME'a göre). Kart ikonu ve "PDF, 2,4 MB" etiketi için.
enum DocumentFileKind {
  pdf('PDF'),
  image('Görsel'),
  word('Word'),
  excel('Excel'),
  other('Dosya');

  const DocumentFileKind(this.label);

  final String label;

  static DocumentFileKind fromMime(String mime, [String fileName = '']) {
    final m = mime.trim().toLowerCase();
    if (m == 'application/pdf') return DocumentFileKind.pdf;
    if (m.startsWith('image/')) return DocumentFileKind.image;
    if (m.contains('wordprocessingml')) return DocumentFileKind.word;
    if (m.contains('spreadsheetml')) return DocumentFileKind.excel;
    final name = fileName.trim().toLowerCase();
    if (name.endsWith('.pdf')) return DocumentFileKind.pdf;
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg')) {
      return DocumentFileKind.image;
    }
    if (name.endsWith('.docx')) return DocumentFileKind.word;
    if (name.endsWith('.xlsx')) return DocumentFileKind.excel;
    return DocumentFileKind.other;
  }
}

/// Ekran okuyucu ve kartlar için "PDF, 2,4 MB" biçimi.
String documentFileLabel(
  String mimeType,
  int sizeBytes, [
  String fileName = '',
]) =>
    '${DocumentFileKind.fromMime(mimeType, fileName).label}, ${formatDocumentSize(sizeBytes)}';

/// Güncel sürümün özeti (liste kartı).
@immutable
class DocumentCurrentVersion {
  const DocumentCurrentVersion({
    required this.versionNo,
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.completedAt,
  });

  final int versionNo;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DateTime? completedAt;

  DocumentFileKind get kind => DocumentFileKind.fromMime(mimeType, fileName);

  static DocumentCurrentVersion? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final no = crmIntOrNull(json['version_no']);
    if (no == null) return null;
    return DocumentCurrentVersion(
      versionNo: no,
      fileName: _text(json['file_name']),
      mimeType: _text(json['mime_type']),
      sizeBytes: crmInt(json['size_bytes']),
      completedAt: documentInstant(json['completed_at']),
    );
  }
}

/// Bloklar / daireler hedef ayrıntısı.
@immutable
class DocumentTarget {
  const DocumentTarget({
    this.type = DocumentTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
    this.blocks = const <DocumentTargetItem>[],
    this.apartments = const <DocumentTargetItem>[],
  });

  final DocumentTargetType type;
  final List<int> blockIds;
  final List<int> apartmentIds;
  final List<DocumentTargetItem> blocks;
  final List<DocumentTargetItem> apartments;

  factory DocumentTarget.fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return const DocumentTarget();
    List<DocumentTargetItem> items(Object? list, String labelKey) {
      if (list is! List) return const <DocumentTargetItem>[];
      final result = <DocumentTargetItem>[];
      for (final item in list.whereType<Map>()) {
        final id = crmIntOrNull(item['id']);
        final label =
            crmText(item[labelKey]) ??
            crmText(item['label']) ??
            crmText(item['name']);
        if (id != null) {
          result.add(DocumentTargetItem(id: id, label: label ?? ''));
        }
      }
      return List<DocumentTargetItem>.unmodifiable(result);
    }

    return DocumentTarget(
      type: DocumentTargetType.fromApi(json['type']),
      blockIds: _intList(json['block_ids']),
      apartmentIds: _intList(json['apartment_ids']),
      blocks: items(json['blocks'], 'name'),
      apartments: items(json['apartments'], 'label'),
    );
  }
}

/// Hedefteki bir blok ya da daire (etiketiyle).
@immutable
class DocumentTargetItem {
  const DocumentTargetItem({required this.id, required this.label});

  final int id;
  final String label;
}

/// Sunucuya giden hedef (`audience: residents` iken).
@immutable
class DocumentTargetInput {
  const DocumentTargetInput({
    this.type = DocumentTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
  });

  final DocumentTargetType type;
  final List<int> blockIds;
  final List<int> apartmentIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.apiValue,
    if (type == DocumentTargetType.blocks) 'block_ids': blockIds,
    if (type == DocumentTargetType.apartments) 'apartment_ids': apartmentIds,
  };
}

/// Yönetici listesi satırı (`GET /manager/sites/:siteCode/documents` -> `items[]`).
@immutable
class DocumentSummary {
  const DocumentSummary({
    required this.id,
    this.title = '',
    this.category = DocumentCategory.other,
    this.audience = DocumentAudience.unknown,
    this.targetType = DocumentTargetType.site,
    this.status = DocumentStatus.unknown,
    this.versionCount = 0,
    this.downloadCount = 0,
    this.currentVersion,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.daysUntilPurge,
    this.uploadedByName,
    this.targetLabels = const <String>[],
  });

  final int id;
  final String title;
  final DocumentCategory category;
  final DocumentAudience audience;
  final DocumentTargetType targetType;
  final DocumentStatus status;
  final int versionCount;
  final int downloadCount;
  final DocumentCurrentVersion? currentVersion;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Silinmiş belge için kalıcı silinmeye kalan gün (yalnız `deleted`); yoksa null.
  final int? daysUntilPurge;

  /// Yükleyen adı. Kurul yanıtlarında YOKTUR (null): arayüz göstermez.
  final String? uploadedByName;

  /// Sunucu hedef etiketleri verdiyse ("A Blok"...); yoksa boş.
  final List<String> targetLabels;

  bool get isDeleted => status == DocumentStatus.deleted;

  /// Kart üzerindeki kitle özeti: "Tüm sakinler", "Yönetim kurulu", "Yalnız yöneticiler", "A, B Blok".
  String get audienceSummary =>
      documentAudienceSummary(audience, targetType, targetLabels);

  factory DocumentSummary.fromJson(Map<String, dynamic> raw) {
    final json = _unwrap(raw);
    final target = json['target'];
    final targetMap = _map(target);
    final directType = json['target_type'] ?? targetMap?['type'];
    final labels = <String>[];
    final rawLabels = json['target_labels'] ?? targetMap?['labels'];
    if (rawLabels is List) {
      for (final label in rawLabels) {
        final text = crmText(label);
        if (text != null) labels.add(text);
      }
    }
    return DocumentSummary(
      id: crmInt(json['id']),
      title: _text(json['title']),
      category: DocumentCategory.fromApi(json['category']),
      audience: DocumentAudience.fromApi(json['audience']),
      targetType: DocumentTargetType.fromApi(directType),
      status: DocumentStatus.fromApi(json['status']),
      versionCount: crmInt(json['version_count']),
      downloadCount: crmInt(json['download_count']),
      currentVersion: DocumentCurrentVersion.fromJson(json['current_version']),
      createdAt: documentInstant(json['created_at']),
      updatedAt: documentInstant(json['updated_at']),
      deletedAt: documentInstant(json['deleted_at']),
      daysUntilPurge: crmIntOrNull(json['days_until_purge']),
      uploadedByName: crmText(json['uploaded_by_name']),
      targetLabels: List<String>.unmodifiable(labels),
    );
  }

  /// `{ "document": {...} }` sarmalını açar; yoksa gövdenin kendisi.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final inner = json['document'];
    return inner is Map ? Map<String, dynamic>.from(inner) : json;
  }
}

/// Kitle özeti metni (liste kartı ve ayrıntı). Bloklar için etiket varsa "A, B Blok" biçimi.
String documentAudienceSummary(
  DocumentAudience audience,
  DocumentTargetType targetType,
  List<String> labels,
) {
  switch (audience) {
    case DocumentAudience.managers:
      return 'Yalnız yöneticiler';
    case DocumentAudience.board:
      return 'Yönetim kurulu';
    case DocumentAudience.unknown:
      return 'Kitle bilinmiyor';
    case DocumentAudience.residents:
      switch (targetType) {
        case DocumentTargetType.site:
          return 'Tüm sakinler';
        case DocumentTargetType.blocks:
          if (labels.isEmpty) return 'Seçili bloklar';
          return _joinLabels(labels, suffix: ' Blok');
        case DocumentTargetType.apartments:
          if (labels.isEmpty) return 'Seçili daireler';
          return _joinLabels(labels);
      }
  }
}

String _joinLabels(List<String> labels, {String suffix = ''}) {
  const maxShown = 3;
  final shown = labels.take(maxShown).map((l) {
    // "A Blok" gibi etiketlerde sonek tekrarlanmasın: "A, B Blok" için yalnız ad kısmı.
    final trimmed = l.trim();
    if (suffix.isNotEmpty &&
        trimmed.toLowerCase().endsWith(suffix.toLowerCase())) {
      return trimmed.substring(0, trimmed.length - suffix.length).trim();
    }
    return trimmed;
  }).toList();
  final rest = labels.length - shown.length;
  final body = shown.join(', ');
  final tail = rest > 0 ? ' ve $rest daha' : '';
  return '$body$suffix$tail';
}

/// Bir belgenin sürümü (`versions[]`).
@immutable
class DocumentVersion {
  const DocumentVersion({
    required this.versionNo,
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.sha256,
    this.note,
    this.completedAt,
    this.uploadedByName,
    this.isCurrent = false,
  });

  final int versionNo;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? sha256;
  final String? note;
  final DateTime? completedAt;
  final String? uploadedByName;
  final bool isCurrent;

  factory DocumentVersion.fromJson(Map<String, dynamic> json) =>
      DocumentVersion(
        versionNo: crmInt(json['version_no']),
        fileName: _text(json['file_name'] ?? json['display_name']),
        mimeType: _text(json['mime_type']),
        sizeBytes: crmInt(json['size_bytes']),
        sha256: crmText(json['sha256']),
        note: crmText(json['note']),
        completedAt: documentInstant(json['completed_at']),
        uploadedByName: crmText(json['uploaded_by_name']),
        isCurrent: _flag(json['is_current']),
      );
}

/// Belgeye ekli duyuru (yalnız yazma yetkilisine).
@immutable
class DocumentAttachedAnnouncement {
  const DocumentAttachedAnnouncement({required this.id, this.status = ''});

  final int id;
  final String status;
}

/// Yönetici belge ayrıntısı (`GET .../documents/:id`).
@immutable
class DocumentDetail extends DocumentSummary {
  const DocumentDetail({
    required super.id,
    super.title,
    super.category,
    super.audience,
    super.targetType,
    super.status,
    super.versionCount,
    super.downloadCount,
    super.currentVersion,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.daysUntilPurge,
    super.uploadedByName,
    super.targetLabels,
    this.description = '',
    this.target = const DocumentTarget(),
    this.versions = const <DocumentVersion>[],
    this.attachedAnnouncements = const <DocumentAttachedAnnouncement>[],
  });

  final String description;
  final DocumentTarget target;
  final List<DocumentVersion> versions;
  final List<DocumentAttachedAnnouncement> attachedAnnouncements;

  factory DocumentDetail.fromJson(Map<String, dynamic> raw) {
    final json = DocumentSummary._unwrap(raw);
    final base = DocumentSummary.fromJson(json);
    final target = DocumentTarget.fromJson(json['target']);
    final versions = <DocumentVersion>[];
    final rawVersions = json['versions'];
    if (rawVersions is List) {
      for (final item in rawVersions.whereType<Map>()) {
        versions.add(DocumentVersion.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    // Sürümler yeniden eskiye.
    versions.sort((a, b) => b.versionNo.compareTo(a.versionNo));
    final attached = <DocumentAttachedAnnouncement>[];
    final rawAttached = json['attached_announcements'];
    if (rawAttached is List) {
      for (final item in rawAttached.whereType<Map>()) {
        final id = crmIntOrNull(item['id']);
        if (id != null) {
          attached.add(
            DocumentAttachedAnnouncement(id: id, status: _text(item['status'])),
          );
        }
      }
    }
    final labels = <String>[
      ...base.targetLabels,
      if (base.targetLabels.isEmpty && target.type == DocumentTargetType.blocks)
        for (final b in target.blocks)
          if (b.label.isNotEmpty) b.label,
      if (base.targetLabels.isEmpty &&
          target.type == DocumentTargetType.apartments)
        for (final a in target.apartments)
          if (a.label.isNotEmpty) a.label,
    ];
    return DocumentDetail(
      id: base.id,
      title: base.title,
      category: base.category,
      audience: base.audience,
      targetType: json['target'] is Map ? target.type : base.targetType,
      status: base.status,
      versionCount: base.versionCount == 0
          ? versions.length
          : base.versionCount,
      downloadCount: base.downloadCount,
      currentVersion: base.currentVersion ?? _currentOf(versions),
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      deletedAt: base.deletedAt,
      daysUntilPurge: base.daysUntilPurge,
      uploadedByName: base.uploadedByName,
      targetLabels: List<String>.unmodifiable(labels),
      description: _text(json['description']),
      target: target,
      versions: List<DocumentVersion>.unmodifiable(versions),
      attachedAnnouncements: List<DocumentAttachedAnnouncement>.unmodifiable(
        attached,
      ),
    );
  }

  static DocumentCurrentVersion? _currentOf(List<DocumentVersion> versions) {
    for (final v in versions) {
      if (v.isCurrent) {
        return DocumentCurrentVersion(
          versionNo: v.versionNo,
          fileName: v.fileName,
          mimeType: v.mimeType,
          sizeBytes: v.sizeBytes,
          completedAt: v.completedAt,
        );
      }
    }
    return null;
  }
}

/// Site belge kullanımı (kota çubuğu).
@immutable
class DocumentUsage {
  const DocumentUsage({
    this.usedBytes = 0,
    this.quotaBytes = 0,
    this.documentCount = 0,
    this.documentLimit = 0,
  });

  final int usedBytes;
  final int quotaBytes;
  final int documentCount;
  final int documentLimit;

  /// Kota bilgisi sunucudan geldi mi? (0 = bilinmiyor; çubuk çizilmez.)
  bool get hasQuota => quotaBytes > 0;

  /// 0..1 doluluk.
  double get fraction =>
      hasQuota ? (usedBytes / quotaBytes).clamp(0.0, 1.0) : 0.0;

  int get remainingBytes =>
      hasQuota ? (quotaBytes - usedBytes).clamp(0, quotaBytes) : 0;

  /// "42 MB / 200 MB".
  String get label =>
      '${formatDocumentSize(usedBytes)} / ${formatDocumentSize(quotaBytes)}';

  factory DocumentUsage.fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return const DocumentUsage();
    return DocumentUsage(
      usedBytes: crmInt(json['used_bytes']),
      quotaBytes: crmInt(json['quota_bytes']),
      documentCount: crmInt(json['document_count']),
      documentLimit: crmInt(json['document_limit']),
    );
  }
}

/// Yönetici liste sayfası (`limit/offset`): kayıtlar, süzgece uyan toplam ve kota kullanımı.
@immutable
class DocumentPage {
  const DocumentPage({
    this.items = const <DocumentSummary>[],
    this.total = 0,
    this.usage,
  });

  final List<DocumentSummary> items;
  final int total;

  /// Yanıtta `usage` yoksa null.
  final DocumentUsage? usage;

  factory DocumentPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map(
                (e) => DocumentSummary.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false)
        : const <DocumentSummary>[];
    return DocumentPage(
      items: items,
      total: crmInt(json['total'], items.length),
      usage: json['usage'] is Map
          ? DocumentUsage.fromJson(json['usage'])
          : null,
    );
  }
}

/// Sakin belge satırı / ayrıntısı (`GET /app/documents[/:id]`).
@immutable
class ResidentDocument {
  const ResidentDocument({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.title = '',
    this.category = DocumentCategory.other,
    this.description = '',
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.versionNo = 1,
    this.isUpdated = false,
    this.updatedAt,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final String title;
  final DocumentCategory category;
  final String description;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int versionNo;

  /// `version_no > 1`: belge güncellendi ("Güncellendi" çipi).
  final bool isUpdated;
  final DateTime? updatedAt;

  DocumentFileKind get kind => DocumentFileKind.fromMime(mimeType, fileName);

  factory ResidentDocument.fromJson(Map<String, dynamic> raw) {
    final inner = raw['document'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    final versionNo = crmInt(json['version_no'], 1);
    return ResidentDocument(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      title: _text(json['title']),
      category: DocumentCategory.fromApi(json['category']),
      description: _text(json['description']),
      fileName: _text(json['file_name']),
      mimeType: _text(json['mime_type']),
      sizeBytes: crmInt(json['size_bytes']),
      versionNo: versionNo,
      isUpdated: json['is_updated'] is bool
          ? json['is_updated'] as bool
          : versionNo > 1,
      updatedAt: documentInstant(json['updated_at']),
    );
  }
}

/// `GET /app/documents` sayfası: `id DESC`; sonraki sayfa `before_id` (saf anahtar-kümesi imleci).
@immutable
class ResidentDocumentPage {
  const ResidentDocumentPage({
    this.items = const <ResidentDocument>[],
    this.nextBeforeId,
  });

  final List<ResidentDocument> items;
  final int? nextBeforeId;

  bool get hasMore => nextBeforeId != null;

  factory ResidentDocumentPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return ResidentDocumentPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      ResidentDocument.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const <ResidentDocument>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
    );
  }
}

/// Duyuruya ekli belge (`attachments[]`; sözleşme A12). `available == false`: belge silinmiş ya da modül kapalı.
@immutable
class DocumentAttachment {
  const DocumentAttachment({
    required this.documentId,
    this.title = '',
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.available = true,
  });

  final int documentId;
  final String title;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final bool available;

  DocumentFileKind get kind => DocumentFileKind.fromMime(mimeType, fileName);

  /// "PDF, 2,4 MB".
  String get fileLabel => documentFileLabel(mimeType, sizeBytes, fileName);

  factory DocumentAttachment.fromJson(Map<String, dynamic> json) =>
      DocumentAttachment(
        documentId: crmInt(json['document_id'] ?? json['id']),
        title: _text(json['title']),
        fileName: _text(json['file_name']),
        mimeType: _text(json['mime_type']),
        sizeBytes: crmInt(json['size_bytes']),
        available: json['available'] is bool ? json['available'] as bool : true,
      );

  /// `attachments` listesi; yok / bozuksa boş.
  static List<DocumentAttachment> listFrom(Object? raw) {
    if (raw is! List) return const <DocumentAttachment>[];
    final result = <DocumentAttachment>[];
    for (final item in raw.whereType<Map>()) {
      final attachment = DocumentAttachment.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (attachment.documentId > 0) result.add(attachment);
    }
    return List<DocumentAttachment>.unmodifiable(result);
  }
}

/// Denetim kaydında belge eylemlerinin kısa Türkçe başlığı (sözleşme A10); bilinmeyen eylemde null.
String? documentActionLabel(String action) {
  switch (action) {
    case 'document.created':
      return 'Belge yüklendi';
    case 'document.version_added':
      return 'Belge sürümü eklendi';
    case 'document.updated':
      return 'Belge düzenlendi';
    case 'document.deleted':
      return 'Belge silindi';
    case 'document.restored':
      return 'Belge geri yüklendi';
    case 'document.purged':
      return 'Belge kalıcı silindi';
    case 'document.version_deleted':
      return 'Belge sürümü silindi';
    case 'document.attached':
      return 'Belge duyuruya eklendi';
    case 'document.detached':
      return 'Belge duyurudan çıkarıldı';
    default:
      return null;
  }
}
