// Rezervasyon ve Konsiyerj modelleri. Sözleşme: docs/PLATFORM_REZERVASYON.md.
//
// Kurallar: alan yok / bozuk ise güvenli varsayılan (uygulama çökmez); bilinmeyen sabit değerler `unknown`'a ya da en
// zararsız değere düşer; zaman damgaları evrensel an (UTC) okunur, gün / saat alanları (`date`, `start`, `end`)
// sunucunun İstanbul takvimiyle verdiği YEREL metindir ve olduğu gibi gösterilir (saat dilimi uygulanmaz). Not,
// gerekçe ve talep metinleri HİÇBİR YERDE günlüğe yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_models.dart'
    show documentInstant;
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmDate, crmInt, crmIntOrNull, crmText;

const int kAreaNameMax = 80;
const int kAreaDescriptionMax = 500;
const int kReservationNoteMax = 200;
const int kReservationDecisionNoteMax = 300;
const int kConciergeNoteMax = 500;
const int kConciergeStaffNoteMax = 300;

String _text(Object? raw) => raw?.toString().trim() ?? '';

Map<String, dynamic>? _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : null;

const List<String> _weekdayShort = <String>[
  'Pzt',
  'Sal',
  'Çar',
  'Per',
  'Cum',
  'Cmt',
  'Paz',
];
const List<String> _weekdayLong = <String>[
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

/// `weekday` 1 = Pazartesi ... 7 = Pazar; geçersizse boş metin.
String reservationWeekdayLabel(int weekday, {bool long = false}) {
  if (weekday < 1 || weekday > 7) return '';
  return (long ? _weekdayLong : _weekdayShort)[weekday - 1];
}

/// "2026-10-20" -> "20.10.2026"; bozuk / boşsa null.
String? reservationDateText(Object? raw) {
  final date = crmDate(raw);
  if (date == null) return null;
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year.toString().padLeft(4, '0')}';
}

/// "18:30" -> 1110; [allow24] true iken "24:00" -> 1440. Bozuksa null.
int? hhmmToMinutes(Object? raw, {bool allow24 = false}) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_text(raw));
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (minute > 59) return null;
  if (hour == 24 && minute == 0 && allow24) return 1440;
  if (hour > 23) return null;
  return hour * 60 + minute;
}

/// 570 -> "09:30"; 1440 -> "24:00".
String minutesToHhmm(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// 45 -> "45 dk"; 60 -> "1 saat"; 90 -> "1 saat 30 dk".
String reservationDurationText(int minutes) {
  if (minutes < 60) return '$minutes dk';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours saat' : '$hours saat $rest dk';
}

/// Rezervasyon durumu (yanıtta TÜRETİLMİŞ: `onaylandi` ve bitişi geçmişse `tamamlandi`). `reddedildi`, `iptal` ve
/// `tamamlandi` SONDUR.
enum ReservationStatus {
  beklemede('beklemede', 'Onay bekliyor'),
  onaylandi('onaylandi', 'Onaylandı'),
  reddedildi('reddedildi', 'Reddedildi'),
  iptal('iptal', 'İptal edildi'),
  tamamlandi('tamamlandi', 'Tamamlandı'),
  unknown('', 'Durum bilinmiyor');

  const ReservationStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Yer tutan (kapasiteyi kullanan) ve iptal edilebilen durumlar.
  bool get isActive => this == beklemede || this == onaylandi;

  bool get isTerminal => this == reddedildi || this == iptal || this == tamamlandi;

  /// Süzgeçte listelenen bilinen durumlar (sunucu sırası).
  static const List<ReservationStatus> known = <ReservationStatus>[
    beklemede,
    onaylandi,
    reddedildi,
    iptal,
    tamamlandi,
  ];

  static ReservationStatus fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.apiValue.isNotEmpty && status.apiValue == normalized) {
        return status;
      }
    }
    return ReservationStatus.unknown;
  }
}

/// Alanın onay modu. Bilinmeyen değer "yönetici onaylı" sayılır (anında onay vaat edilmez).
enum ReservationApproval {
  otomatik('otomatik', 'Otomatik onay'),
  yoneticiOnayli('yonetici_onayli', 'Yönetici onaylı');

  const ReservationApproval(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ReservationApproval fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final mode in values) {
      if (mode.apiValue == normalized) return mode;
    }
    return ReservationApproval.yoneticiOnayli;
  }
}

/// Rezervasyonu kimin iptal ettiği (sunucu `cancelled_by`) için okunur metin; iptal değilse null.
String? reservationCancelledByText(String? kind, {bool selfView = false}) {
  switch (kind) {
    case 'resident':
      return selfView ? 'Siz iptal ettiniz.' : 'Sakin iptal etti.';
    case 'management':
      return 'Yönetim iptal etti.';
    case 'system':
      return 'Hesap silindiği için sistem iptal etti.';
  }
  return null;
}

/// Haftalık açık saat aralığı (`weekly_hours` öğesi). `end` en çok "24:00".
@immutable
class ReservationHours {
  const ReservationHours({
    required this.weekday,
    required this.start,
    required this.end,
  });

  final int weekday;
  final String start;
  final String end;

  String get rangeText => '$start-$end';

  static ReservationHours? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final weekday = crmIntOrNull(json['weekday']);
    final start = hhmmToMinutes(json['start']);
    final end = hhmmToMinutes(json['end'], allow24: true);
    if (weekday == null || weekday < 1 || weekday > 7) return null;
    if (start == null || end == null) return null;
    return ReservationHours(
      weekday: weekday,
      start: minutesToHhmm(start),
      end: minutesToHhmm(end),
    );
  }

  static List<ReservationHours> listFrom(Object? raw) {
    if (raw is! List) return const <ReservationHours>[];
    final list = <ReservationHours>[
      for (final item in raw) ?ReservationHours.fromJson(item),
    ]..sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        return byDay != 0 ? byDay : a.start.compareTo(b.start);
      });
    return List<ReservationHours>.unmodifiable(list);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'weekday': weekday,
    'start': start,
    'end': end,
  };

  @override
  bool operator ==(Object other) =>
      other is ReservationHours &&
      other.weekday == weekday &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(weekday, start, end);
}

/// Konumdaki daire (etiketiyle).
@immutable
class ReservationPlace {
  const ReservationPlace({required this.id, this.label = ''});

  final int id;
  final String label;

  static ReservationPlace? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final id = crmIntOrNull(json['id']);
    if (id == null) return null;
    return ReservationPlace(id: id, label: _text(json['label']));
  }
}

/// Ortak alan (`Area`). Yönetim görünümünde pasifler de gelir; sakin listesinde yalnız aktifler ve `site_name` vardır.
@immutable
class ReservationArea {
  const ReservationArea({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.name = '',
    this.description,
    this.capacity = 1,
    this.slotMinutes = 60,
    this.minSlots = 1,
    this.maxSlots = 1,
    this.maxDaysAhead = 14,
    this.approvalMode = ReservationApproval.yoneticiOnayli,
    this.cancelCutoffHours = 0,
    this.perUserDailyLimit = 1,
    this.perUserWeeklyLimit = 1,
    this.weeklyHours = const <ReservationHours>[],
    this.isActive = true,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final String name;
  final String? description;
  final int capacity;
  final int slotMinutes;
  final int minSlots;
  final int maxSlots;
  final int maxDaysAhead;
  final ReservationApproval approvalMode;
  final int cancelCutoffHours;
  final int perUserDailyLimit;
  final int perUserWeeklyLimit;
  final List<ReservationHours> weeklyHours;
  final bool isActive;

  String get label => name.isEmpty ? 'İsimsiz alan' : name;

  /// "Pazartesi: 09:00-12:00, 14:00-22:00" satırları (yalnız açık günler).
  List<String> get hoursLines {
    final lines = <String>[];
    for (var day = 1; day <= 7; day++) {
      final ranges = <String>[
        for (final hours in weeklyHours)
          if (hours.weekday == day) hours.rangeText,
      ];
      if (ranges.isNotEmpty) {
        lines.add('${reservationWeekdayLabel(day, long: true)}: ${ranges.join(', ')}');
      }
    }
    return lines;
  }

  factory ReservationArea.fromJson(Map<String, dynamic> raw) {
    final inner = raw['area'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    return ReservationArea(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      name: _text(json['name']),
      description: crmText(json['description']),
      capacity: crmInt(json['capacity'], 1),
      slotMinutes: crmInt(json['slot_minutes'], 60),
      minSlots: crmInt(json['min_slots'], 1),
      maxSlots: crmInt(json['max_slots'], 1),
      maxDaysAhead: crmInt(json['max_days_ahead'], 14),
      approvalMode: ReservationApproval.fromApi(json['approval_mode']),
      cancelCutoffHours: crmInt(json['cancel_cutoff_hours']),
      perUserDailyLimit: crmInt(json['per_user_daily_limit'], 1),
      perUserWeeklyLimit: crmInt(json['per_user_weekly_limit'], 1),
      weeklyHours: ReservationHours.listFrom(json['weekly_hours']),
      isActive: json['is_active'] == true,
    );
  }

  static List<ReservationArea> listFrom(Object? raw) {
    if (raw is! List) return const <ReservationArea>[];
    return List<ReservationArea>.unmodifiable(<ReservationArea>[
      for (final item in raw.whereType<Map>())
        ReservationArea.fromJson(Map<String, dynamic>.from(item)),
    ].where((area) => area.id > 0));
  }
}

/// `GET /manager/sites/:siteCode/reservation-areas`: pasifler dahil alanlar + aktif sayısı.
@immutable
class ReservationAreaList {
  const ReservationAreaList({this.items = const <ReservationArea>[], this.activeCount = 0});

  final List<ReservationArea> items;
  final int activeCount;

  factory ReservationAreaList.fromJson(Map<String, dynamic> json) {
    final items = ReservationArea.listFrom(json['items']);
    return ReservationAreaList(
      items: items,
      activeCount: crmIntOrNull(json['active_count']) ??
          items.where((area) => area.isActive).length,
    );
  }
}

/// Kişi (talebi / rezervasyonu yapan, kararı veren). Kurul görünümünde yalnız `name` gelir (telefon ve kullanıcı
/// kodu YOK).
@immutable
class ReservationPerson {
  const ReservationPerson({this.name = '', this.userCode, this.phone});

  final String name;
  final int? userCode;
  final String? phone;

  static ReservationPerson? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    return ReservationPerson(
      name: _text(json['name']),
      userCode: crmIntOrNull(json['user_code']),
      phone: crmText(json['phone']),
    );
  }
}

/// Rezervasyon: sakin görünümü (`MyReservation`: `siteName`, `canCancel`, `cancelDeadline`) ve yönetim görünümü
/// (`Reservation`: `requester`, `decidedBy`, `canDecide`) tek sınıfta; olmayan alanlar boş / false kalır.
@immutable
class ReservationRecord {
  const ReservationRecord({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.areaId = 0,
    this.areaName = '',
    this.startsAt,
    this.endsAt,
    this.date = '',
    this.start = '',
    this.end = '',
    this.slotCount = 1,
    this.status = ReservationStatus.unknown,
    this.note,
    this.decisionNote,
    this.cancelledBy,
    this.apartment,
    this.canCancel = false,
    this.cancelDeadline,
    this.createdAt,
    this.requester,
    this.decidedBy,
    this.canDecide = false,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final int areaId;
  final String areaName;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// İstanbul takvim günü ("2026-10-20") ve yerel saatler ("18:00", "19:00" / "24:00").
  final String date;
  final String start;
  final String end;
  final int slotCount;
  final ReservationStatus status;
  final String? note;
  final String? decisionNote;

  /// `resident | management | system`.
  final String? cancelledBy;
  final ReservationPlace? apartment;
  final bool canCancel;

  /// Sakin görünümü: son iptal zamanı (UTC); yoksa null.
  final DateTime? cancelDeadline;
  final DateTime? createdAt;
  final ReservationPerson? requester;
  final ReservationPerson? decidedBy;
  final bool canDecide;

  String get areaLabel => areaName.isEmpty ? 'İsimsiz alan' : areaName;

  factory ReservationRecord.fromJson(Map<String, dynamic> raw) {
    final inner = raw['reservation'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    final area = _map(json['area']);
    return ReservationRecord(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      areaId: crmInt(area?['id']),
      areaName: _text(area?['name']),
      startsAt: documentInstant(json['starts_at']),
      endsAt: documentInstant(json['ends_at']),
      date: _text(json['date']),
      start: _text(json['start']),
      end: _text(json['end']),
      slotCount: crmInt(json['slot_count'], 1),
      status: ReservationStatus.fromApi(json['status']),
      note: crmText(json['note']),
      decisionNote: crmText(json['decision_note']),
      cancelledBy: crmText(json['cancelled_by']),
      apartment: ReservationPlace.fromJson(json['apartment']),
      canCancel: json['can_cancel'] == true,
      cancelDeadline: documentInstant(json['cancel_deadline']),
      createdAt: documentInstant(json['created_at']),
      requester: ReservationPerson.fromJson(json['requester']),
      decidedBy: ReservationPerson.fromJson(json['decided_by']),
      canDecide: json['can_decide'] == true,
    );
  }
}

/// Rezervasyon sayfası. Sakin listesi `before_id` (id azalan), yönetim takvimi opak `cursor` (başlangıç artan)
/// kullanır; `pendingCount` yalnız yönetim yanıtındadır.
@immutable
class ReservationPage {
  const ReservationPage({
    this.items = const <ReservationRecord>[],
    this.nextBeforeId,
    this.nextCursor,
    this.pendingCount = 0,
  });

  final List<ReservationRecord> items;
  final int? nextBeforeId;
  final String? nextCursor;
  final int pendingCount;

  factory ReservationPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return ReservationPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => ReservationRecord.fromJson(Map<String, dynamic>.from(e)))
                .where((item) => item.id > 0)
                .toList(growable: false)
          : const <ReservationRecord>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
      nextCursor: crmText(json['next_cursor']),
      pendingCount: crmInt(json['pending_count']),
    );
  }
}

/// `POST /app/reservations` yanıtı.
@immutable
class ReservationCreateResult {
  const ReservationCreateResult({required this.reservation, this.replayed = false});

  final ReservationRecord reservation;

  /// Aynı `idempotency_key` ile önceden açılmış kayıt döndü (yeni satır açılmadı).
  final bool replayed;

  factory ReservationCreateResult.fromJson(Map<String, dynamic> json) =>
      ReservationCreateResult(
        reservation: ReservationRecord.fromJson(json),
        replayed: json['replayed'] == true,
      );
}

/// `POST .../reservations/:id/decision` yanıtı.
@immutable
class ReservationDecisionResult {
  const ReservationDecisionResult({required this.reservation, this.changed = true});

  final ReservationRecord reservation;

  /// false: aynı karar zaten verilmişti (200, değişiklik yok).
  final bool changed;

  factory ReservationDecisionResult.fromJson(Map<String, dynamic> json) =>
      ReservationDecisionResult(
        reservation: ReservationRecord.fromJson(json),
        changed: json['changed'] != false,
      );
}

/// Boş dilim sorgusundaki bir dilim.
@immutable
class AvailabilitySlot {
  const AvailabilitySlot({
    required this.start,
    required this.end,
    this.startsAt,
    this.endsAt,
    this.booked = 0,
    this.capacity = 1,
    this.available = false,
  });

  /// Yerel saat ("18:00", "19:00" / "24:00").
  final String start;
  final String end;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int booked;
  final int capacity;
  final bool available;

  String get rangeText => '$start - $end';

  static AvailabilitySlot? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final start = hhmmToMinutes(json['start']);
    final end = hhmmToMinutes(json['end'], allow24: true);
    if (start == null || end == null) return null;
    return AvailabilitySlot(
      start: minutesToHhmm(start),
      end: minutesToHhmm(end),
      startsAt: documentInstant(json['starts_at']),
      endsAt: documentInstant(json['ends_at']),
      booked: crmInt(json['booked']),
      capacity: crmInt(json['capacity'], 1),
      available: json['available'] == true,
    );
  }
}

/// Bir günün dilimleri (`days[]`). Dilimi olmayan gün "kapalı ya da dolu / geçmiş"tir.
@immutable
class AvailabilityDay {
  const AvailabilityDay({
    required this.date,
    this.weekday = 0,
    this.slots = const <AvailabilitySlot>[],
  });

  /// "2026-10-20".
  final String date;
  final int weekday;
  final List<AvailabilitySlot> slots;

  String get shortLabel {
    final text = reservationDateText(date);
    if (text == null) return date;
    final day = reservationWeekdayLabel(weekday);
    final short = text.substring(0, 5);
    return day.isEmpty ? short : '$day $short';
  }

  String get longLabel {
    final text = reservationDateText(date) ?? date;
    final day = reservationWeekdayLabel(weekday, long: true);
    return day.isEmpty ? text : '$text $day';
  }

  static AvailabilityDay? fromJson(Object? raw) {
    final json = _map(raw);
    if (json == null) return null;
    final date = _text(json['date']);
    if (crmDate(date) == null) return null;
    final slots = json['slots'];
    final list = <AvailabilitySlot>[
      if (slots is List)
        for (final item in slots) ?AvailabilitySlot.fromJson(item),
    ]..sort((a, b) => (hhmmToMinutes(a.start) ?? 0).compareTo(hhmmToMinutes(b.start) ?? 0));
    return AvailabilityDay(
      date: date,
      weekday: crmInt(json['weekday']),
      slots: List<AvailabilitySlot>.unmodifiable(list),
    );
  }
}

/// `GET /app/reservation-areas/:id/availability`.
@immutable
class ReservationAvailability {
  const ReservationAvailability({
    required this.area,
    this.days = const <AvailabilityDay>[],
    this.bookableUntil,
  });

  final ReservationArea area;
  final List<AvailabilityDay> days;

  /// Rezerve edilebilen son gün ("2026-11-03"); yoksa null.
  final String? bookableUntil;

  factory ReservationAvailability.fromJson(Map<String, dynamic> json) {
    final area = _map(json['area']);
    final days = json['days'];
    return ReservationAvailability(
      area: area == null
          ? const ReservationArea(id: 0)
          : ReservationArea.fromJson(area),
      days: List<AvailabilityDay>.unmodifiable(<AvailabilityDay>[
        if (days is List)
          for (final item in days) ?AvailabilityDay.fromJson(item),
      ]),
      bookableUntil: crmText(json['bookable_until']),
    );
  }
}

/// Yeni rezervasyon gövdesi (`POST /app/reservations`). `idempotency_key` servis katmanında eklenir.
@immutable
class ReservationCreateRequest {
  const ReservationCreateRequest({
    required this.siteCode,
    required this.areaId,
    required this.date,
    required this.start,
    required this.slots,
    this.note = '',
    this.apartmentId,
  });

  final int siteCode;
  final int areaId;

  /// "YYYY-MM-DD" (İstanbul günü) ve "HH:MM".
  final String date;
  final String start;
  final int slots;
  final String note;
  final int? apartmentId;

  /// Aynı veri = aynı imza (idempotency anahtarı bu imzaya bağlanır; veri değişince anahtar yenilenir).
  String get signature => <Object?>[
    siteCode,
    areaId,
    date,
    start,
    slots,
    note.trim(),
    apartmentId,
  ].join('|');

  Map<String, dynamic> toJson(String idempotencyKey) => <String, dynamic>{
    'site_code': siteCode,
    'area_id': areaId,
    'date': date,
    'start': start,
    'slots': slots,
    if (note.trim().isNotEmpty) 'note': note.trim(),
    if (apartmentId != null) 'apartment_id': apartmentId,
    'idempotency_key': idempotencyKey,
  };
}

/// Konsiyerj kategorisi (sunucu `category`).
enum ConciergeCategory {
  paketTeslim('paket_teslim', 'Paket teslim'),
  misafirHazirlik('misafir_hazirlik', 'Misafir hazırlığı'),
  temizlik('temizlik', 'Temizlik'),
  tasima('tasima', 'Taşıma'),
  diger('diger', 'Diğer');

  const ConciergeCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ConciergeCategory fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final category in values) {
      if (category.apiValue == normalized) return category;
    }
    return ConciergeCategory.diger;
  }
}

/// Konsiyerj talep durumu. `tamamlandi` ve `iptal` SONDUR.
enum ConciergeStatus {
  yeni('yeni', 'Yeni'),
  hazirlaniyor('hazirlaniyor', 'Hazırlanıyor'),
  tamamlandi('tamamlandi', 'Tamamlandı'),
  iptal('iptal', 'İptal edildi'),
  unknown('', 'Durum bilinmiyor');

  const ConciergeStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isTerminal => this == tamamlandi || this == iptal;

  static const List<ConciergeStatus> known = <ConciergeStatus>[
    yeni,
    hazirlaniyor,
    tamamlandi,
    iptal,
  ];

  static ConciergeStatus fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.apiValue.isNotEmpty && status.apiValue == normalized) {
        return status;
      }
    }
    return ConciergeStatus.unknown;
  }
}

/// Konsiyerj talebi: sakin görünümü (`MyRequest`: `siteName`, `canCancel`) ve yönetim görünümü (`Request`:
/// `requester`) tek sınıfta.
@immutable
class ConciergeRecord {
  const ConciergeRecord({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.category = ConciergeCategory.diger,
    this.note,
    this.requestedFor,
    this.status = ConciergeStatus.unknown,
    this.staffNote,
    this.apartment,
    this.canCancel = false,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.requester,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final ConciergeCategory category;
  final String? note;
  final DateTime? requestedFor;
  final ConciergeStatus status;

  /// Sakine görünür kısa not.
  final String? staffNote;
  final ReservationPlace? apartment;
  final bool canCancel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;
  final ReservationPerson? requester;

  factory ConciergeRecord.fromJson(Map<String, dynamic> raw) {
    final inner = raw['request'];
    final json = inner is Map ? Map<String, dynamic>.from(inner) : raw;
    return ConciergeRecord(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      category: ConciergeCategory.fromApi(json['category']),
      note: crmText(json['note']),
      requestedFor: documentInstant(json['requested_for']),
      status: ConciergeStatus.fromApi(json['status']),
      staffNote: crmText(json['staff_note']),
      apartment: ReservationPlace.fromJson(json['apartment']),
      canCancel: json['can_cancel'] == true,
      createdAt: documentInstant(json['created_at']),
      updatedAt: documentInstant(json['updated_at']),
      closedAt: documentInstant(json['closed_at']),
      requester: ReservationPerson.fromJson(json['requester']),
    );
  }
}

/// Konsiyerj talep sayfası (`before_id` imleci, id azalan). `counts` yalnız yönetim yanıtındadır.
@immutable
class ConciergePage {
  const ConciergePage({
    this.items = const <ConciergeRecord>[],
    this.nextBeforeId,
    this.counts = const <ConciergeStatus, int>{},
  });

  final List<ConciergeRecord> items;
  final int? nextBeforeId;
  final Map<ConciergeStatus, int> counts;

  factory ConciergePage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final counts = <ConciergeStatus, int>{};
    final rawCounts = _map(json['counts']);
    if (rawCounts != null) {
      for (final status in ConciergeStatus.known) {
        final value = crmIntOrNull(rawCounts[status.apiValue]);
        if (value != null) counts[status] = value;
      }
    }
    return ConciergePage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => ConciergeRecord.fromJson(Map<String, dynamic>.from(e)))
                .where((item) => item.id > 0)
                .toList(growable: false)
          : const <ConciergeRecord>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
      counts: Map<ConciergeStatus, int>.unmodifiable(counts),
    );
  }
}

/// `POST /app/concierge-requests` yanıtı.
@immutable
class ConciergeCreateResult {
  const ConciergeCreateResult({required this.request, this.replayed = false});

  final ConciergeRecord request;
  final bool replayed;

  factory ConciergeCreateResult.fromJson(Map<String, dynamic> json) =>
      ConciergeCreateResult(
        request: ConciergeRecord.fromJson(json),
        replayed: json['replayed'] == true,
      );
}

/// Yönetim ayrıntısı: talep + sunucunun izin verdiği geçişler (kurulda boş). İstemci kendi geçiş kuralı üretmez.
@immutable
class ConciergeDetail {
  const ConciergeDetail({
    required this.request,
    this.nextStatuses = const <ConciergeStatus>[],
    this.changed = false,
  });

  final ConciergeRecord request;
  final List<ConciergeStatus> nextStatuses;

  /// `PATCH` yanıtında: gerçekten değişiklik oldu mu.
  final bool changed;

  factory ConciergeDetail.fromJson(Map<String, dynamic> json) {
    final rawNext = json['next_statuses'];
    return ConciergeDetail(
      request: ConciergeRecord.fromJson(json),
      nextStatuses: List<ConciergeStatus>.unmodifiable(<ConciergeStatus>[
        if (rawNext is List)
          for (final value in rawNext)
            if (ConciergeStatus.fromApi(value) != ConciergeStatus.unknown)
              ConciergeStatus.fromApi(value),
      ]),
      changed: json['changed'] == true,
    );
  }
}

/// Yeni konsiyerj talebi gövdesi. `requestedFor` UTC an (ekranda İstanbul saatiyle seçilir).
@immutable
class ConciergeCreateRequest {
  const ConciergeCreateRequest({
    required this.siteCode,
    required this.category,
    this.note = '',
    this.requestedFor,
    this.apartmentId,
  });

  final int siteCode;
  final ConciergeCategory category;
  final String note;
  final DateTime? requestedFor;
  final int? apartmentId;

  String get signature => <Object?>[
    siteCode,
    category.apiValue,
    note.trim(),
    requestedFor?.toUtc().millisecondsSinceEpoch,
    apartmentId,
  ].join('|');

  Map<String, dynamic> toJson(String idempotencyKey) => <String, dynamic>{
    'site_code': siteCode,
    'category': category.apiValue,
    if (note.trim().isNotEmpty) 'note': note.trim(),
    if (requestedFor != null) 'requested_for': requestedFor!.toUtc().toIso8601String(),
    if (apartmentId != null) 'apartment_id': apartmentId,
    'idempotency_key': idempotencyKey,
  };
}

/// Menü / ekran kapısı için site erişim türü.
enum ReservationSiteAccess {
  /// Yönetici / süper kullanıcı (alan tanımlar, karar verir).
  manager,

  /// Görevli (karar verir, konsiyerj durumunu ilerletir; alan tanımlayamaz).
  staff,

  /// Yönetim kurulu (salt okur).
  board,
}

/// Yönetim ekranında listelenen site ve erişim türü.
@immutable
class ReservationSite {
  const ReservationSite({
    required this.code,
    required this.name,
    this.access = ReservationSiteAccess.manager,
  });

  final int code;
  final String name;
  final ReservationSiteAccess access;

  /// Karar / durum güncelleme düğmeleri çizilir mi (kurul: hayır). Yetkinin tek kaynağı sunucudur.
  bool get canWrite => access != ReservationSiteAccess.board;

  /// Alan ekleme / düzenleme / pasifleştirme (yalnız yönetici ve süper kullanıcı).
  bool get canDefineAreas => access == ReservationSiteAccess.manager;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is ReservationSite &&
      other.code == code &&
      other.name == name &&
      other.access == access;

  @override
  int get hashCode => Object.hash(code, name, access);
}
