// İş Takibi (arıza, bakım, talep) modelleri. Sözleşme: docs/PLATFORM_IS_TAKIBI.md.
//
// Kurallar: alan yok / bozuk ise güvenli varsayılan (uygulama çökmez); bilinmeyen sabit değerler enum'lara
// "unknown" ya da en zararsız değere düşer; zaman damgaları evrensel an (UTC) okunur ve ekranda İstanbul saatiyle
// gösterilir; `due_date` takvim günüdür (saat dilimi uygulanmaz). Başlık / açıklama / yorum metni HİÇBİR YERDE
// günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart'
    show documentInstant;
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmDate, crmInt, crmIntOrNull, crmText;

const int kWorkTitleMax = 120;
const int kWorkDescriptionMax = 2000;
const int kWorkCommentMax = 1000;

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

/// Olay türü (sunucu `type`).
enum WorkEventType {
  created('created'),
  statusChanged('status_changed'),
  assigned('assigned'),
  priorityChanged('priority_changed'),
  dueDateChanged('due_date_changed'),
  comment('comment'),
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

  String get locationText => workLocationSummary(locationType, apartment, block);

  WorkResidentItem copyWith({bool? unread}) => WorkResidentItem(
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
    );
  }
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

/// `GET /app/work-items/:id` ve `POST .../cancel` sonrası ayrıntı (yalnız public olaylar).
@immutable
class WorkResidentDetail {
  const WorkResidentDetail({required this.item, this.events = const <WorkEvent>[]});

  final WorkResidentItem item;
  final List<WorkEvent> events;

  factory WorkResidentDetail.fromJson(Map<String, dynamic> json) =>
      WorkResidentDetail(
        item: WorkResidentItem.fromJson(json),
        events: WorkEvent.listFrom(json['events']),
      );
}

/// `POST /app/work-items` yanıtı.
@immutable
class WorkCreateResult {
  const WorkCreateResult({required this.item, this.replayed = false});

  final WorkResidentItem item;

  /// Aynı `idempotency_key` ile önceden açılmış kayıt döndü (yeni satır açılmadı).
  final bool replayed;

  factory WorkCreateResult.fromJson(Map<String, dynamic> json) =>
      WorkCreateResult(
        item: WorkResidentItem.fromJson(json),
        replayed: json['replayed'] == true,
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

/// Yönetim ayrıntısı: talep + tüm olaylar (iç dahil; kurulda yalnız public) + izin verilen geçişler.
@immutable
class WorkManagedDetail {
  const WorkManagedDetail({
    required this.item,
    this.events = const <WorkEvent>[],
    this.nextStatuses = const <WorkStatus>[],
  });

  final WorkManagedItem item;
  final List<WorkEvent> events;

  /// Sunucunun izin verdiği geçişler (kurulda boş). İstemci kendi başına geçiş kuralı üretmez.
  final List<WorkStatus> nextStatuses;

  factory WorkManagedDetail.fromJson(Map<String, dynamic> json) {
    final rawNext = json['next_statuses'];
    final next = <WorkStatus>[
      if (rawNext is List)
        for (final value in rawNext)
          if (WorkStatus.fromApi(value) != WorkStatus.unknown)
            WorkStatus.fromApi(value),
    ];
    return WorkManagedDetail(
      item: WorkManagedItem.fromJson(json),
      events: WorkEvent.listFrom(json['events']),
      nextStatuses: List<WorkStatus>.unmodifiable(next),
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
