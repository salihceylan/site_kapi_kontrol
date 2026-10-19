// İş Takibi (arıza, bakım, talep) modelleri. Sözleşme: docs/PLATFORM_IS_TAKIBI.md.
//
// Kurallar: alan yok / bozuk ise güvenli varsayılan (uygulama çökmez); bilinmeyen sabit değerler enum'lara
// "unknown" ya da en zararsız değere düşer; zaman damgaları evrensel an (UTC) okunur ve ekranda İstanbul saatiyle
// gösterilir; `due_date` takvim günüdür (saat dilimi uygulanmaz). Başlık / açıklama / yorum metni HİÇBİR YERDE
// günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart'
    show documentInstant, formatDocumentSize;
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmDate, crmDoubleOrNull, crmInt, crmIntOrNull, crmText;

const int kWorkTitleMax = 120;
const int kWorkDescriptionMax = 2000;
const int kWorkCommentMax = 1000;

/// Talep başına en çok fotoğraf eki.
const int kWorkAttachmentMax = 4;

/// Fotoğraf eki başına en büyük boyut (5 MB).
const int kWorkAttachmentMaxBytes = 5 * 1024 * 1024;

String _text(Object? raw) => raw?.toString().trim() ?? '';

Map<String, dynamic>? _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : null;

/// "2026-10-20" -> "20.10.2026"; bozuk / boşsa null.
String? workDateText(Object? raw) {
  final date = crmDate(raw);
  if (date == null) return null;
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year.toString().padLeft(4, '0')}';
}

/// Talep kategorisi (sunucu `category`).
enum WorkCategory {
  ariza('ariza', 'Arıza'),
  bakim('bakim', 'Bakım'),
  sikayetOneri('sikayet_oneri', 'Şikayet / Öneri'),
  diger('diger', 'Diğer');

  const WorkCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static WorkCategory fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final category in values) {
      if (category.apiValue == normalized) return category;
    }
    return WorkCategory.diger;
  }
}

/// Konum türü (sunucu `location_type`).
enum WorkLocationType {
  ortakAlan('ortak_alan', 'Ortak alan'),
  daire('daire', 'Daire');

  const WorkLocationType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static WorkLocationType fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final type in values) {
      if (type.apiValue == normalized) return type;
    }
    return WorkLocationType.ortakAlan;
  }
}

/// Talep durumu (sunucu `status`). `kapandi` ve `iptal` SONDUR.
enum WorkStatus {
  yeni('yeni', 'Yeni'),
  islemde('islemde', 'İşlemde'),
  beklemede('beklemede', 'Beklemede'),
  cozuldu('cozuldu', 'Çözüldü'),
  kapandi('kapandi', 'Kapandı'),
  iptal('iptal', 'İptal'),
  unknown('', 'Durum bilinmiyor');

  const WorkStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isTerminal => this == kapandi || this == iptal;

  /// Süzgeçte listelenen bilinen durumlar (sunucu sırası).
  static const List<WorkStatus> known = <WorkStatus>[
    yeni,
    islemde,
    beklemede,
    cozuldu,
    kapandi,
    iptal,
  ];

  static WorkStatus fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.apiValue.isNotEmpty && status.apiValue == normalized) {
        return status;
      }
    }
    return WorkStatus.unknown;
  }
}

/// Öncelik (yalnız yönetim görünümü).
enum WorkPriority {
  dusuk('dusuk', 'Düşük'),
  normal('normal', 'Normal'),
  acil('acil', 'Acil');

  const WorkPriority(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static WorkPriority fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final priority in values) {
      if (priority.apiValue == normalized) return priority;
    }
    return WorkPriority.normal;
  }
}

/// Konumdaki daire / blok (etiketiyle).
@immutable
class WorkPlace {
  const WorkPlace({required this.id, this.label = ''});

  final int id;
  final String label;

  static WorkPlace? fromJson(Object? raw, {String labelKey = 'label'}) {
    final json = _map(raw);
    if (json == null) return null;
    final id = crmIntOrNull(json['id']);
    if (id == null) return null;
    return WorkPlace(
      id: id,
      label: _text(json[labelKey] ?? json['label'] ?? json['name']),
    );
  }
}

/// "Ortak alan · A Blok" / "A Blok - 5" gibi tek satırlık konum özeti.
String workLocationSummary(
  WorkLocationType type,
  WorkPlace? apartment,
  WorkPlace? block,
) {
  final apartmentLabel = apartment?.label.trim() ?? '';
  final blockLabel = block?.label.trim() ?? '';
  if (type == WorkLocationType.daire) {
    if (apartmentLabel.isNotEmpty) return apartmentLabel;
    return blockLabel.isEmpty ? 'Daire' : 'Daire · $blockLabel';
  }
  return blockLabel.isEmpty ? 'Ortak alan' : 'Ortak alan · $blockLabel';
}

/// Olay türü (sunucu `type`). `attachment_added` (to = ek kimliği) ve `attachment_removed` (from = ek kimliği)
/// herkese açıktır (sakin de görür).
enum WorkEventType {
  created('created'),
  statusChanged('status_changed'),
  assigned('assigned'),
  priorityChanged('priority_changed'),
  dueDateChanged('due_date_changed'),
  comment('comment'),
  attachmentAdded('attachment_added'),
  attachmentRemoved('attachment_removed'),
  unknown('');

  const WorkEventType(this.apiValue);

  final String apiValue;

  static WorkEventType fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final type in values) {
      if (type.apiValue.isNotEmpty && type.apiValue == normalized) return type;
    }
    return WorkEventType.unknown;
  }
}

/// Talep günlüğündeki bir olay. Sakin / kurul görünümünde `actorKind` yalnız `resident|management`, iç olay
/// yoktur; yönetim görünümünde `actorName` ve `fromLabel/toLabel` (atamada) dolu gelir.
@immutable
class WorkEvent {
  const WorkEvent({
    required this.id,
    this.type = WorkEventType.unknown,
    this.internal = false,
    this.actorKind = '',
    this.actorName,
    this.from,
    this.to,
    this.fromLabel,
    this.toLabel,
    this.body,
    this.createdAt,
  });

  final int id;
  final WorkEventType type;

  /// `visibility == internal` (yalnız yönetim görür).
  final bool internal;

  /// `resident | staff | manager | management`.
  final String actorKind;
  final String? actorName;
  final String? from;
  final String? to;
  final String? fromLabel;
  final String? toLabel;
  final String? body;
  final DateTime? createdAt;

  bool get byResident => actorKind == 'resident';

  factory WorkEvent.fromJson(Map<String, dynamic> json) {
    final actor = _map(json['actor']);
    return WorkEvent(
      id: crmInt(json['id']),
      type: WorkEventType.fromApi(json['type']),
      internal: _text(json['visibility']).toLowerCase() == 'internal',
      actorKind: _text(json['actor_kind']).toLowerCase(),
      actorName: crmText(actor?['name']),
      from: crmText(json['from']),
      to: crmText(json['to']),
      fromLabel: crmText(json['from_label']),
      toLabel: crmText(json['to_label']),
      body: crmText(json['body']),
      createdAt: documentInstant(json['created_at']),
    );
  }

  static List<WorkEvent> listFrom(Object? raw) {
    if (raw is! List) return const <WorkEvent>[];
    final events = <WorkEvent>[];
    for (final item in raw.whereType<Map>()) {
      events.add(WorkEvent.fromJson(Map<String, dynamic>.from(item)));
    }
    // Eskiden yeniye (kimlik artan): sunucu sırası bozuksa da çizgi tutarlı kalır.
    events.sort((a, b) => a.id.compareTo(b.id));
    return List<WorkEvent>.unmodifiable(events);
  }
}

/// Sakin görünümündeki talep (`MyItem`). Öncelik, atanan adı ve iç olaylar sakine GÖSTERİLMEZ.
@immutable
class WorkResidentItem {
  const WorkResidentItem({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.category = WorkCategory.diger,
    this.locationType = WorkLocationType.ortakAlan,
    this.title = '',
    this.description = '',
    this.status = WorkStatus.unknown,
    this.urgent = false,
    this.apartment,
    this.block,
    this.hasAssignee = false,
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.unread = false,
    this.canCancel = false,
    this.canComment = false,
    this.attachmentCount = 0,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final WorkCategory category;
  final WorkLocationType locationType;
  final String title;
  final String description;
  final WorkStatus status;
  final bool urgent;
  final WorkPlace? apartment;
  final WorkPlace? block;
  final bool hasAssignee;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;
  final bool unread;
  final bool canCancel;
  final bool canComment;

  /// Liste satırındaki fotoğraf sayısı (`attachment_count`); yoksa 0.
  final int attachmentCount;

  String get locationText => workLocationSummary(locationType, apartment, block);

  WorkResidentItem copyWith({bool? unread, int? attachmentCount}) => WorkResidentItem(
    id: id,
    siteCode: siteCode,
    siteName: siteName,
    category: category,
    locationType: locationType,
    title: title,
    description: description,
    status: status,
    urgent: urgent,
    apartment: apartment,
    block: block,
    hasAssignee: hasAssignee,
    dueDate: dueDate,
    createdAt: createdAt,
    updatedAt: updatedAt,
    closedAt: closedAt,
    unread: unread ?? this.unread,
    canCancel: canCancel,
    canComment: canComment,
    attachmentCount: attachmentCount ?? this.attachmentCount,
  );

  factory WorkResidentItem.fromJson(Map<String, dynamic> raw) {
    final inner = raw['item'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    return WorkResidentItem(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      category: WorkCategory.fromApi(json['category']),
      locationType: WorkLocationType.fromApi(json['location_type']),
      title: _text(json['title']),
      description: _text(json['description']),
      status: WorkStatus.fromApi(json['status']),
      urgent: json['urgent'] == true,
      apartment: WorkPlace.fromJson(json['apartment']),
      block: WorkPlace.fromJson(json['block'], labelKey: 'name'),
      hasAssignee: json['has_assignee'] == true,
      dueDate: crmDate(json['due_date']),
      createdAt: documentInstant(json['created_at']),
      updatedAt: documentInstant(json['updated_at']),
      closedAt: documentInstant(json['closed_at']),
      unread: json['unread'] == true,
      canCancel: json['can_cancel'] == true,
      canComment: json['can_comment'] == true,
      attachmentCount: _attachmentCount(json),
    );
  }
}

/// `attachment_count` (liste satırı); yoksa ayrıntıdaki `attachments` listesinin uzunluğu; o da yoksa 0.
int _attachmentCount(Map<String, dynamic> json) {
  final count = crmIntOrNull(json['attachment_count']);
  if (count != null) return count < 0 ? 0 : count;
  final list = json['attachments'];
  return list is List ? list.whereType<Map>().length : 0;
}

/// Ayrıntı gövdesinden ek listesi: sözleşmede `attachments` talep nesnesinin yanındadır (`{ item, events,
/// attachments }`); `item` içinde gelirse de okunur.
List<WorkAttachment> _detailAttachments(Map<String, dynamic> raw) {
  final top = raw['attachments'];
  if (top is List) return WorkAttachment.listFrom(top);
  return WorkAttachment.listFrom(_map(raw['item'])?['attachments']);
}

/// Ayrıntı gövdesinde `attachment_count` yoksa talep nesnesine ek listesinin uzunluğu yazılır (kopya üzerinde).
Map<String, dynamic> _withAttachmentCount(
  Map<String, dynamic> raw,
  List<WorkAttachment> attachments,
) {
  final inner = raw['item'];
  if (inner is! Map) return raw;
  final item = Map<String, dynamic>.from(inner);
  if (item['attachment_count'] == null && raw['attachments'] is List) {
    item['attachment_count'] = attachments.length;
  }
  return <String, dynamic>{...raw, 'item': item};
}

/// `GET /app/work-items`: `id DESC`; sonraki sayfa `before_id`; `unread_updates` görmediğiniz güncellemesi olan
/// talep sayısı.
@immutable
class WorkResidentPage {
  const WorkResidentPage({
    this.items = const <WorkResidentItem>[],
    this.nextBeforeId,
    this.unreadUpdates = 0,
  });

  final List<WorkResidentItem> items;
  final int? nextBeforeId;
  final int unreadUpdates;

  factory WorkResidentPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return WorkResidentPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => WorkResidentItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((item) => item.id > 0)
                .toList(growable: false)
          : const <WorkResidentItem>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
      unreadUpdates: crmInt(json['unread_updates']),
    );
  }
}

/// `GET /app/work-items/:id` ve `POST .../cancel` sonrası ayrıntı (yalnız public olaylar) + fotoğraf ekleri.
@immutable
class WorkResidentDetail {
  const WorkResidentDetail({
    required this.item,
    this.events = const <WorkEvent>[],
    this.attachments = const <WorkAttachment>[],
  });

  final WorkResidentItem item;
  final List<WorkEvent> events;
  final List<WorkAttachment> attachments;

  factory WorkResidentDetail.fromJson(Map<String, dynamic> json) {
    final attachments = _detailAttachments(json);
    return WorkResidentDetail(
      item: WorkResidentItem.fromJson(_withAttachmentCount(json, attachments)),
      events: WorkEvent.listFrom(json['events']),
      attachments: attachments,
    );
  }
}

/// `POST /app/work-items` yanıtı (+ formun ardından yüklenen fotoğrafların sonucu).
@immutable
class WorkCreateResult {
  const WorkCreateResult({
    required this.item,
    this.replayed = false,
    this.photosUploaded = 0,
    this.photosFailed = 0,
    this.photosCancelled = false,
  });

  final WorkResidentItem item;

  /// Aynı `idempotency_key` ile önceden açılmış kayıt döndü (yeni satır açılmadı).
  final bool replayed;

  /// Talep açıldıktan sonra başarıyla yüklenen fotoğraf sayısı.
  final int photosUploaded;

  /// Talep açıldı ama yüklenemeyen (ya da iptalle eklenmeyen) fotoğraf sayısı: kullanıcıya DÜRÜSTÇE söylenir.
  final int photosFailed;

  /// Kullanıcı fotoğraf yüklemeyi yarıda kesti (talep yine de açık).
  final bool photosCancelled;

  factory WorkCreateResult.fromJson(Map<String, dynamic> json) =>
      WorkCreateResult(
        item: WorkResidentItem.fromJson(json),
        replayed: json['replayed'] == true,
      );

  WorkCreateResult withPhotoOutcome({
    required int uploaded,
    required int failed,
    bool cancelled = false,
  }) => WorkCreateResult(
    item: item,
    replayed: replayed,
    photosUploaded: uploaded,
    photosFailed: failed,
    photosCancelled: cancelled,
  );
}

/// Yeni talep gövdesi (`POST /app/work-items`). `idempotency_key` servis katmanında eklenir.
@immutable
class WorkCreateRequest {
  const WorkCreateRequest({
    required this.siteCode,
    required this.category,
    required this.locationType,
    required this.title,
    required this.description,
    this.apartmentId,
    this.urgent = false,
  });

  final int siteCode;
  final WorkCategory category;
  final WorkLocationType locationType;
  final String title;
  final String description;
  final int? apartmentId;
  final bool urgent;

  /// Aynı veri = aynı imza (idempotency anahtarı bu imzaya bağlanır; veri değişince anahtar yenilenir).
  String get signature => <Object?>[
    siteCode,
    category.apiValue,
    locationType.apiValue,
    title.trim(),
    description.trim(),
    locationType == WorkLocationType.daire ? apartmentId : null,
    urgent,
  ].join('|');

  Map<String, dynamic> toJson(String idempotencyKey) => <String, dynamic>{
    'site_code': siteCode,
    'category': category.apiValue,
    'location_type': locationType.apiValue,
    'title': title.trim(),
    'description': description.trim(),
    // Ortak alan talebinde daire gönderilemez (sunucu 400 verir).
    if (locationType == WorkLocationType.daire && apartmentId != null)
      'apartment_id': apartmentId,
    if (urgent) 'urgent': true,
    'idempotency_key': idempotencyKey,
  };
}

/// Atanabilir kişi (`assignees`) ya da talepteki atanan (`assigned_to`: rol yok).
@immutable
class WorkAssignee {
  const WorkAssignee({required this.userCode, this.name = '', this.role = ''});

  final int userCode;
  final String name;

  /// `manager | staff` (yalnız `assignees` ucunda).
  final String role;

  String get label {
    final base = name.trim().isEmpty ? 'İsimsiz kişi' : name.trim();
    return switch (role) {
      'manager' => '$base (Yönetici)',
      'staff' => '$base (Görevli)',
      _ => base,
    };
  }

  static WorkAssignee? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final code = crmIntOrNull(json['user_code']);
    if (code == null) return null;
    return WorkAssignee(
      userCode: code,
      name: _text(json['name']),
      role: _text(json['role']),
    );
  }

  static List<WorkAssignee> listFrom(Object? raw) {
    if (raw is! List) return const <WorkAssignee>[];
    return List<WorkAssignee>.unmodifiable(<WorkAssignee>[
      for (final item in raw) ?WorkAssignee.fromJson(item),
    ]);
  }
}

/// Talebi açan kişi. Kurul görünümünde yalnız `name` gelir (telefon ve kullanıcı kodu YOK).
@immutable
class WorkRequester {
  const WorkRequester({this.name = '', this.userCode, this.phone});

  final String name;
  final int? userCode;
  final String? phone;

  factory WorkRequester.fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return const WorkRequester();
    return WorkRequester(
      name: _text(json['name']),
      userCode: crmIntOrNull(json['user_code']),
      phone: crmText(json['phone']),
    );
  }
}

/// Yönetim görünümündeki talep (`Item`): sakin görünümünden FARKLI alanlar.
@immutable
class WorkManagedItem {
  const WorkManagedItem({
    required this.id,
    this.siteCode = 0,
    this.category = WorkCategory.diger,
    this.locationType = WorkLocationType.ortakAlan,
    this.title = '',
    this.description = '',
    this.status = WorkStatus.unknown,
    this.priority = WorkPriority.normal,
    this.residentUrgent = false,
    this.apartment,
    this.block,
    this.requester = const WorkRequester(),
    this.assignedTo,
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.attachmentCount = 0,
  });

  final int id;
  final int siteCode;
  final WorkCategory category;
  final WorkLocationType locationType;
  final String title;
  final String description;
  final WorkStatus status;
  final WorkPriority priority;
  final bool residentUrgent;
  final WorkPlace? apartment;
  final WorkPlace? block;
  final WorkRequester requester;
  final WorkAssignee? assignedTo;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  /// Liste satırındaki fotoğraf sayısı (`attachment_count`); yoksa 0.
  final int attachmentCount;

  String get locationText => workLocationSummary(locationType, apartment, block);

  factory WorkManagedItem.fromJson(Map<String, dynamic> raw) {
    final inner = raw['item'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    return WorkManagedItem(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      category: WorkCategory.fromApi(json['category']),
      locationType: WorkLocationType.fromApi(json['location_type']),
      title: _text(json['title']),
      description: _text(json['description']),
      status: WorkStatus.fromApi(json['status']),
      priority: WorkPriority.fromApi(json['priority']),
      residentUrgent: json['resident_urgent'] == true,
      apartment: WorkPlace.fromJson(json['apartment']),
      block: WorkPlace.fromJson(json['block'], labelKey: 'name'),
      requester: WorkRequester.fromJson(json['requester']),
      assignedTo: WorkAssignee.fromJson(json['assigned_to']),
      dueDate: crmDate(json['due_date']),
      createdAt: documentInstant(json['created_at']),
      updatedAt: documentInstant(json['updated_at']),
      closedAt: documentInstant(json['closed_at']),
      attachmentCount: _attachmentCount(json),
    );
  }
}

/// `GET /manager/sites/:siteCode/work-items`: kayıtlar + durum sayaçları (süzgeçten bağımsız, kapsam içi).
@immutable
class WorkManagedPage {
  const WorkManagedPage({
    this.items = const <WorkManagedItem>[],
    this.nextBeforeId,
    this.counts = const <WorkStatus, int>{},
  });

  final List<WorkManagedItem> items;
  final int? nextBeforeId;
  final Map<WorkStatus, int> counts;

  factory WorkManagedPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final counts = <WorkStatus, int>{};
    final rawCounts = _map(json['counts']);
    if (rawCounts != null) {
      for (final status in WorkStatus.known) {
        final value = crmIntOrNull(rawCounts[status.apiValue]);
        if (value != null) counts[status] = value;
      }
    }
    return WorkManagedPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => WorkManagedItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((item) => item.id > 0)
                .toList(growable: false)
          : const <WorkManagedItem>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
      counts: Map<WorkStatus, int>.unmodifiable(counts),
    );
  }
}

/// Yönetim ayrıntısı: talep + tüm olaylar (iç dahil; kurulda yalnız public) + izin verilen geçişler + fotoğraf
/// ekleri.
@immutable
class WorkManagedDetail {
  const WorkManagedDetail({
    required this.item,
    this.events = const <WorkEvent>[],
    this.nextStatuses = const <WorkStatus>[],
    this.attachments = const <WorkAttachment>[],
  });

  final WorkManagedItem item;
  final List<WorkEvent> events;

  /// Sunucunun izin verdiği geçişler (kurulda boş). İstemci kendi başına geçiş kuralı üretmez.
  final List<WorkStatus> nextStatuses;
  final List<WorkAttachment> attachments;

  factory WorkManagedDetail.fromJson(Map<String, dynamic> json) {
    final rawNext = json['next_statuses'];
    final next = <WorkStatus>[
      if (rawNext is List)
        for (final value in rawNext)
          if (WorkStatus.fromApi(value) != WorkStatus.unknown)
            WorkStatus.fromApi(value),
    ];
    final attachments = _detailAttachments(json);
    return WorkManagedDetail(
      item: WorkManagedItem.fromJson(_withAttachmentCount(json, attachments)),
      events: WorkEvent.listFrom(json['events']),
      nextStatuses: List<WorkStatus>.unmodifiable(next),
      attachments: attachments,
    );
  }
}

/// Menü / ekran kapısı için site erişim türü.
enum WorkSiteAccess {
  /// Yönetici (yazar).
  manager,

  /// Görevli (kendine atanmış ya da atanmamış talepleri yazar).
  staff,

  /// Yönetim kurulu (salt okur).
  board,
}

/// Yönetim ekranında listelenen site ve erişim türü.
@immutable
class WorkTrackingSite {
  const WorkTrackingSite({
    required this.code,
    required this.name,
    this.access = WorkSiteAccess.manager,
  });

  final int code;
  final String name;
  final WorkSiteAccess access;

  bool get canWrite => access != WorkSiteAccess.board;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is WorkTrackingSite &&
      other.code == code &&
      other.name == name &&
      other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}

/// Talep formunda seçilebilen kendi dairesi.
@immutable
class WorkApartmentChoice {
  const WorkApartmentChoice({required this.id, required this.label});

  final int id;
  final String label;
}

// --- Fotoğraf ekleri ------------------------------------------------------------------------------

/// Fotoğraf eki kuralları: yalnız JPEG / PNG / WebP, dosya başına 5 MB, talep başına 4. İstemci ön doğrulaması
/// kullanıcıyı bant genişliği harcamadan uyarmak içindir; SUNUCU esastır (içerik imzasına bakar).
abstract final class WorkAttachmentRules {
  /// Dosya seçicide gösterilecek uzantılar (noktasız, küçük harf).
  static const List<String> pickerExtensions = <String>['jpg', 'jpeg', 'png', 'webp'];

  /// Sunucunun kabul ettiği içerik türleri.
  static const Set<String> allowedMimeTypes = <String>{'image/jpeg', 'image/png', 'image/webp'};

  /// Tür / boyut reddi (istemci ön doğrulaması ve sunucunun 413 / 415 yanıtı).
  static const String typeAndSizeMessage = 'Yalnız JPEG, PNG veya WebP; en fazla 5 MB.';

  /// 409 `LIMIT_REACHED`.
  static const String limitMessage = 'En fazla $kWorkAttachmentMax fotoğraf eklenebilir.';

  /// 409 `INVALID_STATE` (talep kapandı / iptal edildi).
  static const String closedMessage = 'Kapanmış talebe fotoğraf eklenemez.';

  /// 409 `LIMIT_REACHED` ama ekranda 4'ten az fotoğraf var: başka biri (ya da başka cihaz) şu an yüklüyor olabilir.
  static const String limitBusyMessage =
      'Bu talebe başka bir fotoğraf yükleniyor olabilir; biraz sonra tekrar deneyin.';

  /// 415 `ATTACHMENT_DIMENSIONS_TOO_LARGE` ve istemcinin aynı ön denetimi.
  static const String dimensionsMessage =
      'Fotoğrafın çözünürlüğü çok yüksek; daha küçük bir fotoğraf seçin.';

  /// İstemci: fotoğraf yeniden kodlanamadı ve üstverisi (konum / cihaz) de ayıklanamadı (yapısı bozuk); gizlilik için
  /// yüklenmez.
  static const String metadataMessage =
      'Fotoğraf işlenemedi; konum ve cihaz bilgileri silinemediği için eklenmedi.';

  /// Sunucu sınırı (bellek bombası koruması): kenar 12.000 pikseli ya da toplam 40 milyon pikseli aşan görsel reddedilir;
  /// istemci de böyle görseli çözmeden ÖNCE durdurur.
  static const int maxEdgePixels = 12000;
  static const int maxPixels = 40000000;

  static bool dimensionsTooLarge(int width, int height) =>
      width > maxEdgePixels ||
      height > maxEdgePixels ||
      width * height > maxPixels;

  /// 409 `ATTACHMENT_QUOTA_EXCEEDED`. `quota: site`: sitenin toplam fotoğraf alanı doldu. `quota: user`: YALNIZ sakinler
  /// için KAYAN pencere: bu sitede son [windowDays] günde (gövdede `window_days`, yoksa 30) yüklenebilecek toplam
  /// [quotaBytes] (gövdede `quota_bytes`, yoksa 200 MB) doldu; süre geçince kendiliğinden açılır (eski fotoğrafı silmek
  /// gerekmez, sakin kapanmış talepteki fotoğrafını zaten silemez).
  static String quotaMessage({required bool site, int? quotaBytes, int? windowDays}) {
    if (site) return 'Sitenin fotoğraf depolama alanı doldu; yönetime başvurun.';
    final mb = quotaBytes != null && quotaBytes > 0 ? _formatMb(quotaBytes) : '200';
    final days = windowDays != null && windowDays > 0 ? windowDays : 30;
    return 'Son $days günde bu sitede yükleyebileceğiniz fotoğraf sınırına ulaştınız (en çok $mb MB); '
        'daha sonra yeniden deneyin ya da yönetime başvurun.';
  }

  /// Sunucuyla aynı biçim: tam MB ise tam sayı, değilse tek ondalık (virgülle).
  static String _formatMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb == mb.truncateToDouble() ? mb.toInt().toString() : mb.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// `foto.JPG` -> `jpg`; uzantı yoksa null.
  static String? extensionOf(String fileName) {
    final name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }

  /// Uzantıdan içerik türü; desteklenmeyen / uzantısız dosyada null.
  static String? mimeTypeOf(String fileName) => switch (extensionOf(fileName)) {
    'jpg' || 'jpeg' || 'jpe' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };

  static const List<int> _pngSignature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// İçerik imzasından tür: JPEG `FF D8 FF`, PNG imzası, `RIFF....WEBP`; tanınmazsa null. Uzantıdan ÖNCE gelir (iOS'ta
  /// dönüştürülen fotoğrafın adı / uzantısı içerikle uyuşmayabilir; sunucu da içerik imzasına bakar).
  static String? sniffMimeType(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= _pngSignature.length) {
      var png = true;
      for (var i = 0; i < _pngSignature.length; i++) {
        if (bytes[i] != _pngSignature[i]) {
          png = false;
          break;
        }
      }
      if (png) return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return 'image/webp';
    }
    return null;
  }

  /// Seçilen dosyanın ön denetimi; sorun yoksa null, varsa Türkçe kullanıcı metni. [content] okunduysa tür içerik
  /// imzasından, okunmadıysa (sınırı aşan dosya) uzantıdan anlaşılır; [width] / [height] ölçüldüyse çözünürlük de
  /// denetlenir.
  static String? validate({
    required String fileName,
    required int size,
    List<int>? content,
    int? width,
    int? height,
  }) {
    if (size > kWorkAttachmentMaxBytes) {
      return 'Fotoğraf çok büyük (${formatDocumentSize(size)}). $typeAndSizeMessage';
    }
    if (size <= 0) return 'Seçilen dosya boş. Başka bir fotoğraf seçin.';
    final type = content != null && content.isNotEmpty
        ? sniffMimeType(content)
        : mimeTypeOf(fileName);
    if (type == null) return typeAndSizeMessage;
    if (width != null && height != null && dimensionsTooLarge(width, height)) {
      return dimensionsMessage;
    }
    return null;
  }
}

/// Ek durumu (sunucu `status`): `uploading` içerik henüz gelmedi, `ready` görüntülenebilir.
enum WorkAttachmentStatus {
  uploading('uploading'),
  ready('ready'),
  unknown('');

  const WorkAttachmentStatus(this.apiValue);

  final String apiValue;

  static WorkAttachmentStatus fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.apiValue.isNotEmpty && status.apiValue == normalized) return status;
    }
    return WorkAttachmentStatus.unknown;
  }
}

/// Talebin fotoğraf eki. Yönetim görünümünde [uploadedByName] gerçek addır; SAKİN görünümünde yalnız kendi eklediği
/// fotoğrafta gerçek ad, diğerlerinde sunucu "Yönetim" yazar (arayüz yine de adı göstermez: "Siz" / "Yönetim").
/// [uploadedByMe] silme yetkisinin ekrandaki ipucudur (yetkinin tek kaynağı yine sunucudur).
@immutable
class WorkAttachment {
  const WorkAttachment({
    required this.id,
    this.workItemId = 0,
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.status = WorkAttachmentStatus.unknown,
    this.uploadedByName,
    this.uploadedByKind = '',
    this.uploadedByMe = false,
    this.createdAt,
  });

  final int id;
  final int workItemId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final WorkAttachmentStatus status;
  final String? uploadedByName;

  /// `resident` (talebi açan sakin yükledi) | `management` (yönetici / görevli); bilinmiyorsa boş.
  final String uploadedByKind;
  final bool uploadedByMe;
  final DateTime? createdAt;

  /// İçerik indirilebilir (yükleme tamamlanmış).
  bool get isReady => status == WorkAttachmentStatus.ready;

  /// Yönetim (yönetici / görevli) yükledi.
  bool get byManagement => uploadedByKind == 'management';

  /// Ekranda gösterilen ad; boşsa "Fotoğraf".
  String get label => fileName.trim().isEmpty ? 'Fotoğraf' : fileName.trim();

  static WorkAttachment? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final inner = _map(json['attachment']);
    final body = inner ?? json;
    final id = crmIntOrNull(body['id']);
    if (id == null || id <= 0) return null;
    return WorkAttachment(
      id: id,
      workItemId: crmInt(body['work_item_id']),
      fileName: _text(body['file_name']),
      mimeType: _text(body['mime_type']).toLowerCase(),
      sizeBytes: crmInt(body['size_bytes']),
      status: WorkAttachmentStatus.fromApi(body['status']),
      uploadedByName: crmText(body['uploaded_by_name']),
      uploadedByKind: switch (_text(body['uploaded_by_kind']).toLowerCase()) {
        'resident' => 'resident',
        'management' => 'management',
        _ => '',
      },
      uploadedByMe: body['uploaded_by_me'] == true,
      createdAt: documentInstant(body['created_at']),
    );
  }

  /// Kimliksiz / bozuk satırlar atılır; kimlik artan sırada (sunucu sırası bozuksa da tutarlı).
  static List<WorkAttachment> listFrom(Object? raw) {
    if (raw is! List) return const <WorkAttachment>[];
    final list = <WorkAttachment>[for (final item in raw) ?WorkAttachment.fromJson(item)]
      ..sort((a, b) => a.id.compareTo(b.id));
    return List<WorkAttachment>.unmodifiable(list);
  }
}

/// Yeni ek bildirimi gövdesi (`POST .../attachments`, adım 1).
@immutable
class WorkAttachmentCreateRequest {
  const WorkAttachmentCreateRequest({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String fileName;
  final String mimeType;
  final int sizeBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'file_name': fileName.trim(),
    'mime_type': mimeType.trim().toLowerCase(),
    'size_bytes': sizeBytes,
  };
}

// --- Rapor --------------------------------------------------------------------------------------

double? _finiteOrNull(Object? raw) {
  final value = crmDoubleOrNull(raw);
  if (value == null || !value.isFinite || value < 0) return null;
  return value;
}

/// Saat cinsinden süreyi "x sa" ya da "x gün y sa" olarak yazar; yoksa "-".
String workHoursText(double? hours) {
  if (hours == null) return '-';
  final total = hours.round();
  if (total <= 0) return hours > 0 ? '1 saatten az' : '0 sa';
  if (total < 24) return '$total sa';
  final days = total ~/ 24;
  final rest = total % 24;
  return rest == 0 ? '$days gün' : '$days gün $rest sa';
}

/// Oranı yüzde olarak yazar ("%85"); yoksa "-". Sunucu 0..1 kesir verir; 1'i aşan değer zaten yüzdedir.
String workRateText(double? rate) {
  if (rate == null) return '-';
  final percent = rate <= 1 ? rate * 100 : rate;
  return '%${percent.round().clamp(0, 100)}';
}

/// Rapor toplamları (`totals`).
@immutable
class WorkReportTotals {
  const WorkReportTotals({
    this.opened = 0,
    this.resolved = 0,
    this.closed = 0,
    this.cancelled = 0,
    this.openNow = 0,
    this.overdueNow = 0,
    this.avgResolutionHours,
    this.medianResolutionHours,
  });

  final int opened;
  final int resolved;
  final int closed;
  final int cancelled;
  final int openNow;
  final int overdueNow;
  final double? avgResolutionHours;
  final double? medianResolutionHours;

  bool get isEmpty =>
      opened == 0 && resolved == 0 && closed == 0 && cancelled == 0 && openNow == 0 && overdueNow == 0;

  factory WorkReportTotals.fromJson(Object? raw) {
    final json = _map(raw) ?? const <String, dynamic>{};
    return WorkReportTotals(
      opened: crmInt(json['opened']),
      resolved: crmInt(json['resolved']),
      closed: crmInt(json['closed']),
      cancelled: crmInt(json['cancelled']),
      openNow: crmInt(json['open_now']),
      overdueNow: crmInt(json['overdue_now']),
      avgResolutionHours: _finiteOrNull(json['avg_resolution_hours']),
      medianResolutionHours: _finiteOrNull(json['median_resolution_hours']),
    );
  }
}

/// Görevliye göre satır (`by_assignee[]`); `user_code` null = atanmamış talepler.
@immutable
class WorkReportAssignee {
  const WorkReportAssignee({
    this.userCode,
    this.name = '',
    this.openNow = 0,
    this.overdueNow = 0,
    this.resolved = 0,
    this.avgResolutionHours,
    this.onTimeRate,
  });

  final int? userCode;
  final String name;
  final int openNow;
  final int overdueNow;
  final int resolved;
  final double? avgResolutionHours;
  final double? onTimeRate;

  String get label {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return userCode == null ? 'Atanmamış' : 'İsimsiz kişi';
  }

  static WorkReportAssignee? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    return WorkReportAssignee(
      userCode: crmIntOrNull(json['user_code']),
      name: _text(json['name']),
      openNow: crmInt(json['open_now']),
      overdueNow: crmInt(json['overdue_now']),
      resolved: crmInt(json['resolved']),
      avgResolutionHours: _finiteOrNull(json['avg_resolution_hours']),
      onTimeRate: _finiteOrNull(json['on_time_rate']),
    );
  }
}

/// Kategoriye göre satır (`by_category[]`).
@immutable
class WorkReportCategory {
  const WorkReportCategory({
    required this.category,
    this.rawCategory = '',
    this.opened = 0,
    this.resolved = 0,
  });

  final WorkCategory category;

  /// Sunucunun gönderdiği ham değer (bilinmeyen kategori etikette olduğu gibi gösterilir).
  final String rawCategory;
  final int opened;
  final int resolved;

  String get label {
    final known = WorkCategory.values.any((c) => c.apiValue == rawCategory.toLowerCase());
    if (known || rawCategory.trim().isEmpty) return category.label;
    return rawCategory.trim();
  }

  static WorkReportCategory? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final rawCategory = _text(json['category']);
    return WorkReportCategory(
      category: WorkCategory.fromApi(rawCategory),
      rawCategory: rawCategory,
      opened: crmInt(json['opened']),
      resolved: crmInt(json['resolved']),
    );
  }
}

/// `GET /manager/sites/:siteCode/work-items/report?from&to` yanıtı.
@immutable
class WorkReport {
  const WorkReport({
    this.from,
    this.to,
    this.generatedAt,
    this.totals = const WorkReportTotals(),
    this.byAssignee = const <WorkReportAssignee>[],
    this.byCategory = const <WorkReportCategory>[],
  });

  final DateTime? from;
  final DateTime? to;
  final DateTime? generatedAt;
  final WorkReportTotals totals;
  final List<WorkReportAssignee> byAssignee;
  final List<WorkReportCategory> byCategory;

  /// Aralıkta hiç hareket yok (boş durum).
  bool get isEmpty =>
      totals.isEmpty &&
      byAssignee.every((a) => a.openNow == 0 && a.overdueNow == 0 && a.resolved == 0) &&
      byCategory.every((c) => c.opened == 0 && c.resolved == 0);

  factory WorkReport.fromJson(Map<String, dynamic> json) {
    final assignees = json['by_assignee'];
    final categories = json['by_category'];
    return WorkReport(
      from: crmDate(json['from']),
      to: crmDate(json['to']),
      generatedAt: documentInstant(json['generated_at']),
      totals: WorkReportTotals.fromJson(json['totals']),
      byAssignee: assignees is List
          ? List<WorkReportAssignee>.unmodifiable(<WorkReportAssignee>[
              for (final item in assignees) ?WorkReportAssignee.fromJson(item),
            ])
          : const <WorkReportAssignee>[],
      byCategory: categories is List
          ? List<WorkReportCategory>.unmodifiable(<WorkReportCategory>[
              for (final item in categories) ?WorkReportCategory.fromJson(item),
            ])
          : const <WorkReportCategory>[],
    );
  }
}
