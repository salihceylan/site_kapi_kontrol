// Ziyaretçi ve Kargo (`visitor_log`) modelleri. Sözleşme: docs/PLATFORM_ZIYARETCI_KARGO.md (F11.03).
//
// Kurallar (İş Takibi ile aynı): alan yok / bozuk ise güvenli varsayılan (uygulama çökmez); bilinmeyen sabit
// değerler enum'lara "unknown" ya da en zararsız değere düşer; zaman damgaları evrensel an (UTC) okunur ve ekranda
// İstanbul saatiyle gösterilir. Ziyaretçi adı / firma / not HİÇBİR YERDE günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart'
    show documentInstant;
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmInt, crmIntOrNull, crmText;

const int kVisitorNameMax = 120;
const int kVisitorCompanyMax = 120;
const int kVisitorNoteMax = 500;

String _text(Object? raw) => raw?.toString().trim() ?? '';

/// Kayıt türü (sunucu `kind`).
enum VisitorKind {
  visitor('visitor', 'Ziyaretçi'),
  cargo('cargo', 'Kargo');

  const VisitorKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static VisitorKind fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final kind in values) {
      if (kind.apiValue == normalized) return kind;
    }
    return VisitorKind.visitor;
  }
}

/// Kayıt durumu (sunucu `status`). `teslim_edildi`, `ayrildi` ve `iptal` SONDUR.
enum VisitorStatus {
  bekliyor('bekliyor', 'Bekliyor'),
  iceride('iceride', 'İçeride'),
  teslimEdildi('teslim_edildi', 'Teslim edildi'),
  ayrildi('ayrildi', 'Ayrıldı'),
  iptal('iptal', 'İptal'),
  unknown('', 'Durum bilinmiyor');

  const VisitorStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isTerminal =>
      this == teslimEdildi || this == ayrildi || this == iptal;

  /// Açık (sonlanmamış) durumlar.
  bool get isOpen => this == bekliyor || this == iceride;

  /// Süzgeçte listelenen bilinen durumlar (sunucu sırası).
  static const List<VisitorStatus> known = <VisitorStatus>[
    bekliyor,
    iceride,
    teslimEdildi,
    ayrildi,
    iptal,
  ];

  static VisitorStatus fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.apiValue.isNotEmpty && status.apiValue == normalized) {
        return status;
      }
    }
    return VisitorStatus.unknown;
  }

  /// Geçiş eyleminin düğme etiketi ("Teslim edildi" / "Ayrıldı" / "İptal").
  String get actionLabel => switch (this) {
    teslimEdildi => 'Teslim edildi',
    ayrildi => 'Ayrıldı',
    iptal => 'İptal',
    _ => label,
  };
}

/// Ziyaretçi / kargo kaydı (`Entry`). Sakin görünümünde `recorded_by_name` / `completed_by_name` GELMEZ; yönetim
/// görünümünde `site_code` / `site_name` gelmeyebilir.
@immutable
class VisitorEntry {
  const VisitorEntry({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.kind = VisitorKind.visitor,
    this.apartmentId,
    this.apartmentLabel = '',
    this.blockName = '',
    this.visitorName = '',
    this.company,
    this.note,
    this.status = VisitorStatus.unknown,
    this.nextStatuses = const <VisitorStatus>[],
    this.arrivedAt,
    this.completedAt,
    this.recordedByName,
    this.completedByName,
    this.residentSeenAt,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final VisitorKind kind;
  final int? apartmentId;
  final String apartmentLabel;
  final String blockName;
  final String visitorName;
  final String? company;
  final String? note;
  final VisitorStatus status;

  /// Sunucunun izin verdiği geçişler (kurulda boş). İstemci kendi başına geçiş kuralı üretmez.
  final List<VisitorStatus> nextStatuses;
  final DateTime? arrivedAt;
  final DateTime? completedAt;
  final String? recordedByName;
  final String? completedByName;
  final DateTime? residentSeenAt;

  /// Sakin görünümü: görülmemiş kayıt (kalın + rozet).
  bool get unread => residentSeenAt == null;

  /// "A Blok / 5" ya da "Ortak alan".
  String get placeText {
    final apartment = apartmentLabel.trim();
    final block = blockName.trim();
    if (apartment.isEmpty) return 'Ortak alan';
    if (block.isEmpty || apartment.startsWith(block)) return apartment;
    return '$block / $apartment';
  }

  /// Ad boşsa türüne göre yer tutucu.
  String get displayName => visitorName.trim().isEmpty
      ? (kind == VisitorKind.cargo ? 'İsimsiz kargo' : 'İsimsiz ziyaretçi')
      : visitorName.trim();

  VisitorEntry copyWith({DateTime? residentSeenAt}) => VisitorEntry(
    id: id,
    siteCode: siteCode,
    siteName: siteName,
    kind: kind,
    apartmentId: apartmentId,
    apartmentLabel: apartmentLabel,
    blockName: blockName,
    visitorName: visitorName,
    company: company,
    note: note,
    status: status,
    nextStatuses: nextStatuses,
    arrivedAt: arrivedAt,
    completedAt: completedAt,
    recordedByName: recordedByName,
    completedByName: completedByName,
    residentSeenAt: residentSeenAt ?? this.residentSeenAt,
  );

  factory VisitorEntry.fromJson(Map<String, dynamic> raw) {
    final inner = raw['item'] ?? raw['entry'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    final rawNext = json['next_statuses'];
    final next = <VisitorStatus>[
      if (rawNext is List)
        for (final value in rawNext)
          if (VisitorStatus.fromApi(value) != VisitorStatus.unknown)
            VisitorStatus.fromApi(value),
    ];
    return VisitorEntry(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      kind: VisitorKind.fromApi(json['kind']),
      apartmentId: crmIntOrNull(json['apartment_id']),
      apartmentLabel: _text(json['apartment_label']),
      blockName: _text(json['block_name']),
      visitorName: _text(json['visitor_name']),
      company: crmText(json['company']),
      note: crmText(json['note']),
      status: VisitorStatus.fromApi(json['status']),
      nextStatuses: List<VisitorStatus>.unmodifiable(next),
      arrivedAt: documentInstant(json['arrived_at']),
      completedAt: documentInstant(json['completed_at']),
      recordedByName: crmText(json['recorded_by_name']),
      completedByName: crmText(json['completed_by_name']),
      residentSeenAt: documentInstant(json['resident_seen_at']),
    );
  }

  static List<VisitorEntry> listFrom(Object? raw) {
    if (raw is! List) return const <VisitorEntry>[];
    return List<VisitorEntry>.unmodifiable(<VisitorEntry>[
      for (final item in raw.whereType<Map>())
        if (crmInt(item['id']) > 0)
          VisitorEntry.fromJson(Map<String, dynamic>.from(item)),
    ]);
  }
}

/// `GET /manager/sites/:siteCode/visitor-entries`: `{items, total}` (limit / offset).
@immutable
class VisitorManagedPage {
  const VisitorManagedPage({this.items = const <VisitorEntry>[], this.total = 0});

  final List<VisitorEntry> items;
  final int total;

  factory VisitorManagedPage.fromJson(Map<String, dynamic> json) {
    final items = VisitorEntry.listFrom(json['items']);
    final total = crmIntOrNull(json['total']);
    return VisitorManagedPage(
      items: items,
      total: total == null || total < items.length ? items.length : total,
    );
  }
}

/// `GET /app/visitor-entries`: `id DESC`; sonraki sayfa `before_id`.
@immutable
class VisitorResidentPage {
  const VisitorResidentPage({this.items = const <VisitorEntry>[], this.nextBeforeId});

  final List<VisitorEntry> items;
  final int? nextBeforeId;

  factory VisitorResidentPage.fromJson(Map<String, dynamic> json) =>
      VisitorResidentPage(
        items: VisitorEntry.listFrom(json['items']),
        nextBeforeId: crmIntOrNull(json['next_before_id']),
      );
}

/// Yeni kayıt gövdesi (`POST .../visitor-entries`). Başlangıç durumunu SUNUCU hesaplar (kargo -> bekliyor,
/// ziyaretçi -> içeride).
@immutable
class VisitorCreateRequest {
  const VisitorCreateRequest({
    required this.kind,
    required this.visitorName,
    this.apartmentId,
    this.company,
    this.note,
  });

  final VisitorKind kind;
  final String visitorName;
  final int? apartmentId;
  final String? company;
  final String? note;

  Map<String, dynamic> toJson() {
    final company = this.company?.trim() ?? '';
    final note = this.note?.trim() ?? '';
    return <String, dynamic>{
      'kind': kind.apiValue,
      if (apartmentId != null) 'apartment_id': apartmentId,
      'visitor_name': visitorName.trim(),
      if (company.isNotEmpty) 'company': company,
      if (note.isNotEmpty) 'note': note,
    };
  }
}

/// Menü / ekran kapısı için site erişim türü.
enum VisitorSiteAccess {
  /// Yönetici (yazar).
  manager,

  /// Görevli (kapıcı / güvenlik; kayıt girer ve kapatır).
  staff,

  /// Yönetim kurulu (salt okur).
  board,
}

/// Yönetim ekranında listelenen site ve erişim türü.
@immutable
class VisitorSite {
  const VisitorSite({
    required this.code,
    required this.name,
    this.access = VisitorSiteAccess.manager,
  });

  final int code;
  final String name;
  final VisitorSiteAccess access;

  bool get canWrite => access != VisitorSiteAccess.board;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is VisitorSite &&
      other.code == code &&
      other.name == name &&
      other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}
