// Rezervasyon ve Konsiyerj: ekran / pencere / denetleyici testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (docs/PLATFORM_REZERVASYON.md): satırlar bellekte sunucunun gerçek JSON biçiminde
// tutulur ve modellerle ayrıştırılır; sakin listeleri `before_id` imleci, yönetim takvimi opak `cursor` uygular;
// kurul telefonu ve kullanıcı kodunu GÖRMEZ, karar / yazma uçları kurulda 403 verir; kapasite, dilim sayısı,
// iptal süresi ve geçişler sunucu kurallarıyla aynı hata kodlarını üretir; sakin satırlarında `unread`, sakin
// sayfalarında `unread_count` taşır ve `seen` uçları bayrağı siler (`unreadFields = false` eski sunucuyu taklit eder).
// Hata ve yarış testleri için her çağrı kuyruktaki bir hataya ya da kapıya takılabilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';

import 'people_fixtures.dart';

/// Sahte kimlik doğrulama (yalnız servise `authService` olarak verilir).
class ReservationFakeAuth extends PeopleFakeAuth {
  ReservationFakeAuth({super.role});
}

const Map<String, List<String>> kConciergeTransitions = <String, List<String>>{
  'yeni': <String>['hazirlaniyor', 'tamamlandi', 'iptal'],
  'hazirlaniyor': <String>['tamamlandi', 'iptal'],
  'tamamlandi': <String>[],
  'iptal': <String>[],
};

bool _activeStatus(Object? status) => status == 'beklemede' || status == 'onaylandi';

/// İstanbul yerel gün + saat -> UTC ISO ("2026-10-20", "18:00" -> "2026-10-20T15:00:00.000Z").
String rzInstant(String date, String hhmm) {
  final d = date.split('-').map(int.parse).toList();
  final t = hhmm.split(':').map(int.parse).toList();
  return DateTime.utc(d[0], d[1], d[2], t[0], t[1]).subtract(const Duration(hours: 3)).toIso8601String();
}

/// Ortak alan (`Area`).
Map<String, dynamic> rzArea(
  int id, {
  String name = 'Spor Salonu',
  String? description = 'Koşu bandı ve ağırlıklar.',
  int site = 11,
  String siteName = 'Gül Sitesi',
  int capacity = 1,
  int slotMinutes = 60,
  int minSlots = 1,
  int maxSlots = 3,
  int maxDaysAhead = 14,
  String approval = 'otomatik',
  int cutoff = 2,
  int daily = 2,
  int weekly = 5,
  List<Map<String, dynamic>>? hours,
  bool active = true,
}) {
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'site_name': siteName,
    'name': name,
    'description': description,
    'capacity': capacity,
    'slot_minutes': slotMinutes,
    'min_slots': minSlots,
    'max_slots': maxSlots,
    'max_days_ahead': maxDaysAhead,
    'approval_mode': approval,
    'cancel_cutoff_hours': cutoff,
    'per_user_daily_limit': daily,
    'per_user_weekly_limit': weekly,
    'weekly_hours':
        hours ??
        <Map<String, dynamic>>[
          for (var day = 1; day <= 5; day++) <String, dynamic>{'weekday': day, 'start': '09:00', 'end': '22:00'},
          <String, dynamic>{'weekday': 6, 'start': '10:00', 'end': '18:00'},
        ],
    'is_active': active,
    'created_at': '2026-10-01T09:00:00Z',
    'updated_at': '2026-10-01T09:00:00Z',
  };
}

/// Rezervasyon (sakin ve yönetim alanlarının ÜST KÜMESİ; sahte servis görünüme göre sadeleştirir).
Map<String, dynamic> rzReservation(
  int id, {
  int area = 1,
  String areaName = 'Spor Salonu',
  String status = 'onaylandi',
  String date = '2026-10-20',
  String start = '18:00',
  String end = '19:00',
  int slots = 1,
  String? note,
  String? decisionNote,
  String? cancelledBy,
  bool canCancel = true,
  String? cancelDeadline = '2026-10-20T13:00:00Z',
  String requester = 'Ayşe Yılmaz',
  String? phone = '+905551112233',
  int site = 11,
  String siteName = 'Gül Sitesi',
  String? apartment = 'A Blok / 5',
  bool unread = false,
}) {
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'site_name': siteName,
    'area': <String, dynamic>{'id': area, 'name': areaName},
    'starts_at': rzInstant(date, start),
    'ends_at': rzInstant(date, end == '24:00' ? '23:59' : end),
    'date': date,
    'start': start,
    'end': end,
    'slot_count': slots,
    'status': status,
    'note': note,
    'decision_note': decisionNote,
    'cancelled_by': cancelledBy,
    'apartment': apartment == null ? null : <String, dynamic>{'id': 301, 'label': apartment},
    'can_cancel': canCancel,
    'cancel_deadline': cancelDeadline,
    'created_at': '2026-10-15T09:00:00Z',
    'requester': <String, dynamic>{'user_code': 4001, 'name': requester, 'phone': phone},
    'decided_by': null,
    'can_decide': false,
    'unread': unread,
  };
}

/// Konsiyerj talebi (sakin ve yönetim alanlarının ÜST KÜMESİ).
Map<String, dynamic> rzRequest(
  int id, {
  String category = 'paket_teslim',
  String? note = 'Kapıdaki paketi 3. kata çıkarın.',
  String status = 'yeni',
  String? staffNote,
  String? requestedFor,
  String requester = 'Ayşe Yılmaz',
  String? phone = '+905551112233',
  int site = 11,
  String siteName = 'Gül Sitesi',
  bool unread = false,
}) {
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'site_name': siteName,
    'category': category,
    'note': note,
    'requested_for': requestedFor,
    'status': status,
    'staff_note': staffNote,
    'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok / 5'},
    'can_cancel': status == 'yeni',
    'created_at': '2026-10-15T09:00:00Z',
    'updated_at': '2026-10-16T10:30:00Z',
    'closed_at': (status == 'tamamlandi' || status == 'iptal') ? '2026-10-16T10:30:00Z' : null,
    'requester': <String, dynamic>{'user_code': 4001, 'name': requester, 'phone': phone},
    'unread': unread,
  };
}

/// Boş saat yanıtı için üç gün: 20 Ekim (1. dilim boş, 2. dolu, 3. boş), 21 Ekim (üçü de boş), 22 Ekim (kapalı).
List<Map<String, dynamic>> rzDefaultDays({int capacity = 1}) {
  Map<String, dynamic> slot(String start, String end, int booked) => <String, dynamic>{
    'start': start,
    'end': end,
    'starts_at': rzInstant('2026-10-20', start),
    'ends_at': rzInstant('2026-10-20', end),
    'booked': booked,
    'capacity': capacity,
    'available': booked < capacity,
  };
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'date': '2026-10-20',
      'weekday': 2,
      'slots': <Map<String, dynamic>>[
        slot('09:00', '10:00', capacity > 1 ? 1 : 0),
        slot('10:00', '11:00', capacity),
        slot('11:00', '12:00', 0),
      ],
    },
    <String, dynamic>{
      'date': '2026-10-21',
      'weekday': 3,
      'slots': <Map<String, dynamic>>[
        slot('09:00', '10:00', 0),
        slot('10:00', '11:00', 0),
        slot('11:00', '12:00', 0),
      ],
    },
    <String, dynamic>{'date': '2026-10-22', 'weekday': 4, 'slots': <Map<String, dynamic>>[]},
  ];
}

/// Hata ya da yarış için kuyruğa konan sahte servis.
class FakeReservationService extends ReservationService {
  FakeReservationService({required super.authService, this.kind = ReservationSiteAccess.manager})
    : super(api: ReservationApi(baseUrl: 'http://localhost'));

  /// Yönetim görünümündeki rol: manager | staff | board.
  ReservationSiteAccess kind;

  final List<Map<String, dynamic>> areas = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> reservations = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<int, List<Map<String, dynamic>>> availabilityDays = <int, List<Map<String, dynamic>>>{};

  // --- Çağrı kayıtları ---
  final List<int?> listAreasCalls = <int?>[];
  final List<({int area, String? from})> availabilityCalls = [];
  final List<ReservationCreateRequest> createCalls = [];
  final List<({int? site, String scope, int? before})> listMineCalls = [];
  final List<int> cancelCalls = [];
  final List<({int? site, String status, int? before})> listMyRequestsCalls = [];
  final List<ConciergeCreateRequest> createRequestCalls = [];
  final List<int> cancelRequestCalls = [];
  int listManagedAreasCalls = 0;
  final List<Map<String, Object?>> createAreaCalls = [];
  final List<({int id, Map<String, Object?> fields})> updateAreaCalls = [];
  final List<({int site, int? area, String? status, String? from, String? to, String? cursor})> listManagedCalls = [];
  final List<({int site, int id, String action, String? note})> decideCalls = [];
  final List<({int site, String? status, String? category, int? before})> listManagedRequestsCalls = [];
  final List<int> getManagedRequestCalls = [];
  final List<({int site, int id, Map<String, Object?> fields})> updateRequestCalls = [];
  final List<int> getMineCalls = [];
  final List<int> seenCalls = [];
  final List<int> getMyRequestCalls = [];
  final List<int> seenRequestCalls = [];
  final List<int?> unreadCountsCalls = [];

  // --- Okunmamış (sakin rozeti) ---
  /// false: eski sunucu (satırlarda `unread`, sayfalarda `unread_count` yok; sayaç ucu 0 verir).
  bool unreadFields = true;

  Map<String, dynamic> _residentRow(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row);
    if (!unreadFields) copy.remove('unread');
    return copy;
  }

  int _unreadOf(List<Map<String, dynamic>> rows, int? siteCode) =>
      rows.where((r) => (siteCode == null || r['site_code'] == siteCode) && r['unread'] == true).length;

  // --- Sürücüler ---
  /// İşlem adı -> sıradaki hatalar (her çağrı birini fırlatır).
  final Map<String, List<Object>> failures = <String, List<Object>>{};

  /// İşlem adı -> sıradaki kapılar (çağrı kapı açılana dek bekler).
  final Map<String, List<Completer<void>>> gates = <String, List<Completer<void>>>{};

  Future<void> _enter(String op) async {
    final gate = gates[op];
    if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
    final failure = failures[op];
    if (failure != null && failure.isNotEmpty) throw failure.removeAt(0);
  }

  static ApiException error(int status, String code, {Map<String, dynamic>? payload, String? text}) => ApiException(
    ReservationApi.reservationErrorMessage(code, payload: payload, serverText: text) ?? 'Hata',
    statusCode: status,
    code: code,
    payload: payload,
  );

  static ApiException moduleOff() => error(403, 'MODULE_DISABLED');

  Map<String, dynamic>? _row(List<Map<String, dynamic>> rows, int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  int _nextId() {
    var max = 100;
    for (final row in [...reservations, ...requests, ...areas]) {
      if ((row['id'] as int) > max) max = row['id'] as int;
    }
    return max + 1;
  }

  bool get _board => kind == ReservationSiteAccess.board;

  // --- Sakin: alanlar ve rezervasyon ---

  @override
  Future<List<ReservationArea>> listAreas({int? siteCode}) async {
    listAreasCalls.add(siteCode);
    await _enter('listAreas');
    return ReservationArea.listFrom(<Map<String, dynamic>>[
      for (final a in areas)
        if (a['is_active'] == true && (siteCode == null || a['site_code'] == siteCode)) Map<String, dynamic>.of(a),
    ]);
  }

  List<Map<String, dynamic>> _days(int areaId) {
    final area = _row(areas, areaId);
    return availabilityDays.putIfAbsent(
      areaId,
      () => rzDefaultDays(capacity: (area?['capacity'] as int?) ?? 1),
    );
  }

  @override
  Future<ReservationAvailability> availability(int areaId, {String? from, String? to}) async {
    availabilityCalls.add((area: areaId, from: from));
    await _enter('availability');
    final area = _row(areas, areaId);
    if (area == null) throw error(404, 'AREA_NOT_FOUND');
    if (area['is_active'] != true) throw error(409, 'AREA_INACTIVE');
    return ReservationAvailability.fromJson(<String, dynamic>{
      'area': Map<String, dynamic>.of(area),
      'days': [for (final d in _days(areaId)) Map<String, dynamic>.of(d)],
      'bookable_until': '2026-11-03',
    });
  }

  @override
  Future<ReservationCreateResult> createReservation(ReservationCreateRequest request) async {
    createCalls.add(request);
    await _enter('create');
    final area = _row(areas, request.areaId);
    if (area == null) throw error(404, 'AREA_NOT_FOUND');
    final min = area['min_slots'] as int;
    final max = area['max_slots'] as int;
    if (request.slots < min || request.slots > max) {
      throw error(409, 'INVALID_SLOT_COUNT', payload: <String, dynamic>{'min_slots': min, 'max_slots': max});
    }
    final days = _days(request.areaId);
    final day = days.where((d) => d['date'] == request.date).firstOrNull;
    final slots = (day?['slots'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    final first = slots.indexWhere((s) => s['start'] == request.start);
    if (first < 0) throw error(409, 'OUTSIDE_OPEN_HOURS');
    if (first + request.slots > slots.length) throw error(409, 'OUTSIDE_OPEN_HOURS');
    for (var i = first; i < first + request.slots; i++) {
      if (slots[i]['available'] != true) throw error(409, 'SLOT_FULL');
    }
    for (var i = first; i < first + request.slots; i++) {
      final booked = (slots[i]['booked'] as int) + 1;
      slots[i]['booked'] = booked;
      slots[i]['available'] = booked < (slots[i]['capacity'] as int);
    }
    final id = _nextId();
    final row = rzReservation(
      id,
      area: request.areaId,
      areaName: area['name'] as String,
      status: area['approval_mode'] == 'otomatik' ? 'onaylandi' : 'beklemede',
      date: request.date,
      start: request.start,
      end: slots[first + request.slots - 1]['end'] as String,
      slots: request.slots,
      note: request.note.trim().isEmpty ? null : request.note.trim(),
      requester: 'Ben Sakin',
      site: area['site_code'] as int,
    );
    reservations.add(row);
    return ReservationCreateResult.fromJson(<String, dynamic>{
      'reservation': Map<String, dynamic>.of(row),
      'replayed': false,
    });
  }

  @override
  Future<ReservationPage> listMine({int? siteCode, String scope = 'all', int limit = 30, int? beforeId}) async {
    listMineCalls.add((site: siteCode, scope: scope, before: beforeId));
    await _enter('listMine');
    final scoped = reservations.where((r) => siteCode == null || r['site_code'] == siteCode).toList();
    final filtered =
        scoped.where((r) {
          if (scope == 'all') return true;
          return scope == 'upcoming' ? _activeStatus(r['status']) : !_activeStatus(r['status']);
        }).toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final from = beforeId == null ? filtered : filtered.where((r) => (r['id'] as int) < beforeId).toList();
    final page = from.take(limit).toList();
    return ReservationPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _residentRow(r)],
      'next_before_id': from.length > limit ? page.last['id'] : null,
      if (unreadFields) 'unread_count': _unreadOf(reservations, siteCode),
    });
  }

  @override
  Future<ReservationRecord> getMine(int id) async {
    getMineCalls.add(id);
    await _enter('getMine');
    final row = _row(reservations, id);
    if (row == null) throw error(404, 'RESERVATION_NOT_FOUND');
    return ReservationRecord.fromJson(<String, dynamic>{'reservation': _residentRow(row)});
  }

  @override
  Future<void> markMineSeen(int id) async {
    seenCalls.add(id);
    await _enter('markMineSeen');
    final row = _row(reservations, id);
    if (row == null) throw error(404, 'RESERVATION_NOT_FOUND');
    row['unread'] = false;
  }

  @override
  Future<ReservationRecord> cancelMine(int id) async {
    cancelCalls.add(id);
    await _enter('cancelMine');
    final row = _row(reservations, id);
    if (row == null) throw error(404, 'RESERVATION_NOT_FOUND');
    if (!_activeStatus(row['status']) || row['can_cancel'] != true) {
      throw error(409, 'CANCEL_WINDOW_CLOSED', payload: <String, dynamic>{'cancel_cutoff_hours': 2});
    }
    row
      ..['status'] = 'iptal'
      ..['can_cancel'] = false
      ..['cancelled_by'] = 'resident';
    return ReservationRecord.fromJson(Map<String, dynamic>.of(row));
  }

  // --- Sakin: konsiyerj ---

  @override
  Future<ConciergePage> listMyRequests({int? siteCode, String status = 'all', int limit = 30, int? beforeId}) async {
    listMyRequestsCalls.add((site: siteCode, status: status, before: beforeId));
    await _enter('listMyRequests');
    final scoped = requests.where((r) => siteCode == null || r['site_code'] == siteCode).toList();
    final filtered =
        scoped.where((r) {
          if (status == 'all') return true;
          final open = r['status'] == 'yeni' || r['status'] == 'hazirlaniyor';
          return status == 'open' ? open : !open;
        }).toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final from = beforeId == null ? filtered : filtered.where((r) => (r['id'] as int) < beforeId).toList();
    final page = from.take(limit).toList();
    return ConciergePage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _residentRow(r)],
      'next_before_id': from.length > limit ? page.last['id'] : null,
      if (unreadFields) 'unread_count': _unreadOf(requests, siteCode),
    });
  }

  @override
  Future<ConciergeRecord> getMyRequest(int id) async {
    getMyRequestCalls.add(id);
    await _enter('getMyRequest');
    final row = _row(requests, id);
    if (row == null) throw error(404, 'CONCIERGE_NOT_FOUND');
    return ConciergeRecord.fromJson(<String, dynamic>{'request': _residentRow(row)});
  }

  @override
  Future<void> markMyRequestSeen(int id) async {
    seenRequestCalls.add(id);
    await _enter('markMyRequestSeen');
    final row = _row(requests, id);
    if (row == null) throw error(404, 'CONCIERGE_NOT_FOUND');
    row['unread'] = false;
  }

  @override
  Future<ReservationUnreadCounts> unreadCounts({int? siteCode}) async {
    unreadCountsCalls.add(siteCode);
    await _enter('unreadCounts');
    if (!unreadFields) return (reservations: 0, concierge: 0);
    return (reservations: _unreadOf(reservations, siteCode), concierge: _unreadOf(requests, siteCode));
  }

  @override
  Future<ConciergeCreateResult> createRequest(ConciergeCreateRequest request) async {
    createRequestCalls.add(request);
    await _enter('createRequest');
    final id = _nextId();
    final row = rzRequest(
      id,
      category: request.category.apiValue,
      note: request.note.trim().isEmpty ? null : request.note.trim(),
      requestedFor: request.requestedFor?.toUtc().toIso8601String(),
      site: request.siteCode,
      requester: 'Ben Sakin',
    );
    requests.add(row);
    return ConciergeCreateResult.fromJson(<String, dynamic>{
      'request': Map<String, dynamic>.of(row),
      'replayed': false,
    });
  }

  @override
  Future<ConciergeRecord> cancelMyRequest(int id) async {
    cancelRequestCalls.add(id);
    await _enter('cancelRequest');
    final row = _row(requests, id);
    if (row == null) throw error(404, 'CONCIERGE_NOT_FOUND');
    if (row['status'] != 'yeni') throw error(409, 'CONCIERGE_CLOSED');
    row
      ..['status'] = 'iptal'
      ..['can_cancel'] = false;
    return ConciergeRecord.fromJson(Map<String, dynamic>.of(row));
  }

  // --- Yönetim: alanlar ---

  @override
  Future<ReservationAreaList> listManagedAreas(int siteCode) async {
    listManagedAreasCalls++;
    await _enter('listManagedAreas');
    final items = [for (final a in areas) if (a['site_code'] == siteCode) Map<String, dynamic>.of(a)];
    return ReservationAreaList.fromJson(<String, dynamic>{
      'items': items,
      'active_count': items.where((a) => a['is_active'] == true).length,
    });
  }

  @override
  Future<ReservationArea> createArea(int siteCode, Map<String, Object?> fields) async {
    createAreaCalls.add(Map<String, Object?>.of(fields));
    await _enter('createArea');
    if (kind != ReservationSiteAccess.manager) throw error(403, 'FORBIDDEN_ROLE');
    final name = (fields['name'] as String).toLowerCase();
    if (areas.any((a) => a['site_code'] == siteCode && (a['name'] as String).toLowerCase() == name)) {
      throw error(409, 'AREA_NAME_TAKEN');
    }
    final row = rzArea(
      _nextId(),
      name: fields['name'] as String,
      description: fields['description'] as String?,
      site: siteCode,
      capacity: fields['capacity'] as int,
      slotMinutes: fields['slot_minutes'] as int,
      minSlots: fields['min_slots'] as int,
      maxSlots: fields['max_slots'] as int,
      maxDaysAhead: fields['max_days_ahead'] as int,
      approval: fields['approval_mode'] as String,
      cutoff: fields['cancel_cutoff_hours'] as int,
      daily: fields['per_user_daily_limit'] as int,
      weekly: fields['per_user_weekly_limit'] as int,
      hours: [for (final h in fields['weekly_hours'] as List) Map<String, dynamic>.from(h as Map)],
    );
    areas.add(row);
    return ReservationArea.fromJson(Map<String, dynamic>.of(row));
  }

  @override
  Future<ReservationArea> updateArea(int siteCode, int id, Map<String, Object?> fields) async {
    updateAreaCalls.add((id: id, fields: Map<String, Object?>.of(fields)));
    await _enter('updateArea');
    if (kind != ReservationSiteAccess.manager) throw error(403, 'FORBIDDEN_ROLE');
    final row = _row(areas, id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'AREA_NOT_FOUND');
    fields.forEach((key, value) => row[key] = value);
    return ReservationArea.fromJson(Map<String, dynamic>.of(row));
  }

  // --- Yönetim: takvim ve kararlar ---

  Map<String, dynamic> _managerView(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row)..remove('cancel_deadline');
    final active = _activeStatus(row['status']);
    copy['can_cancel'] = !_board && active;
    copy['can_decide'] = !_board && row['status'] == 'beklemede';
    if (_board) {
      copy['requester'] = <String, dynamic>{'name': (row['requester'] as Map)['name']};
      final decider = row['decided_by'];
      if (decider is Map) copy['decided_by'] = <String, dynamic>{'name': decider['name']};
    }
    return copy;
  }

  @override
  Future<ReservationPage> listManaged(
    int siteCode, {
    int? areaId,
    String? status,
    String? from,
    String? to,
    String? cursor,
    int limit = 30,
  }) async {
    listManagedCalls.add((site: siteCode, area: areaId, status: status, from: from, to: to, cursor: cursor));
    await _enter('listManaged');
    final scoped = reservations.where((r) => r['site_code'] == siteCode).toList();
    final statuses = status == null || status.isEmpty ? null : status.split(',');
    final filtered =
        scoped.where((r) {
          if (areaId != null && (r['area'] as Map)['id'] != areaId) return false;
          if (statuses != null && !statuses.contains(r['status'])) return false;
          return true;
        }).toList()..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    final lastId = cursor == null ? 0 : int.parse(cursor.substring(1));
    final rest = filtered.where((r) => (r['id'] as int) > lastId).toList();
    final page = rest.take(limit).toList();
    return ReservationPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _managerView(r)],
      'next_cursor': rest.length > limit ? 'c${page.last['id']}' : null,
      'pending_count': scoped.where((r) => r['status'] == 'beklemede').length,
    });
  }

  @override
  Future<ReservationDecisionResult> decide(int siteCode, int id, {required String action, String? note}) async {
    decideCalls.add((site: siteCode, id: id, action: action, note: note));
    await _enter('decide');
    final row = _row(reservations, id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'RESERVATION_NOT_FOUND');
    if (_board) throw error(403, 'FORBIDDEN_ROLE');
    if (action != 'approve' && (note == null || note.trim().isEmpty)) {
      throw error(400, 'INVALID_BODY', text: 'Gerekçe zorunludur.');
    }
    final status = row['status'] as String;
    final target = switch (action) {
      'approve' => 'onaylandi',
      'reject' => 'reddedildi',
      _ => 'iptal',
    };
    if (status == target) {
      return ReservationDecisionResult.fromJson(<String, dynamic>{'reservation': _managerView(row), 'changed': false});
    }
    final allowed = switch (action) {
      'approve' || 'reject' => status == 'beklemede',
      _ => _activeStatus(status),
    };
    if (!allowed) {
      throw error(409, 'INVALID_TRANSITION', payload: <String, dynamic>{'from': status, 'to': target});
    }
    row
      ..['status'] = target
      ..['decision_note'] = note?.trim().isEmpty ?? true ? null : note!.trim()
      ..['decided_by'] = <String, dynamic>{'user_code': 7, 'name': 'Ben Yönetici'}
      ..['can_cancel'] = false;
    if (action == 'cancel') row['cancelled_by'] = 'management';
    return ReservationDecisionResult.fromJson(<String, dynamic>{'reservation': _managerView(row), 'changed': true});
  }

  // --- Yönetim: konsiyerj ---

  Map<String, dynamic> _requestView(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row);
    if (_board) {
      copy['requester'] = <String, dynamic>{'name': (row['requester'] as Map)['name']};
    }
    return copy;
  }

  @override
  Future<ConciergePage> listManagedRequests(
    int siteCode, {
    String? status,
    String? category,
    int limit = 30,
    int? beforeId,
  }) async {
    listManagedRequestsCalls.add((site: siteCode, status: status, category: category, before: beforeId));
    await _enter('listManagedRequests');
    final scoped = requests.where((r) => r['site_code'] == siteCode).toList();
    final filtered =
        scoped.where((r) {
          if (category != null && r['category'] != category) return false;
          if (status == null || status.isEmpty || status == 'all') return true;
          final open = r['status'] == 'yeni' || r['status'] == 'hazirlaniyor';
          if (status == 'open') return open;
          if (status == 'closed') return !open;
          return status.split(',').contains(r['status']);
        }).toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final from = beforeId == null ? filtered : filtered.where((r) => (r['id'] as int) < beforeId).toList();
    final page = from.take(limit).toList();
    return ConciergePage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _requestView(r)],
      'next_before_id': from.length > limit ? page.last['id'] : null,
      'counts': <String, int>{
        for (final s in kConciergeTransitions.keys) s: scoped.where((r) => r['status'] == s).length,
      },
    });
  }

  @override
  Future<ConciergeDetail> getManagedRequest(int siteCode, int id) async {
    getManagedRequestCalls.add(id);
    await _enter('getManagedRequest');
    final row = _row(requests, id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'CONCIERGE_NOT_FOUND');
    return ConciergeDetail.fromJson(<String, dynamic>{
      'request': _requestView(row),
      'next_statuses': _board ? const <String>[] : kConciergeTransitions[row['status']] ?? const <String>[],
    });
  }

  @override
  Future<ConciergeDetail> updateManagedRequest(int siteCode, int id, Map<String, Object?> fields) async {
    updateRequestCalls.add((site: siteCode, id: id, fields: Map<String, Object?>.of(fields)));
    await _enter('updateRequest');
    final row = _row(requests, id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'CONCIERGE_NOT_FOUND');
    if (_board) throw error(403, 'FORBIDDEN_ROLE');
    if (kConciergeTransitions[row['status']]!.isEmpty) throw error(409, 'CONCIERGE_CLOSED');
    final status = fields['status'];
    if (status != null) {
      if (!kConciergeTransitions[row['status']]!.contains(status)) {
        throw error(409, 'INVALID_TRANSITION', payload: <String, dynamic>{'from': row['status'], 'to': status});
      }
      row
        ..['status'] = status
        ..['can_cancel'] = false;
    }
    if (fields.containsKey('note')) row['staff_note'] = fields['note'];
    return ConciergeDetail.fromJson(<String, dynamic>{
      'request': _requestView(row),
      'next_statuses': kConciergeTransitions[row['status']] ?? const <String>[],
      'changed': true,
    });
  }
}

/// Alanlar (aktif x2, pasif x1), rezervasyonlar ve konsiyerj talepleri ile kurulmuş sahte servis.
///
/// Rezervasyonlar: 1 onaylı (iptal edilebilir), 2 onay bekleyen (iptal süresi dolmuş), 3 tamamlanmış, 4 yönetimce iptal
/// edilmiş (gerekçeli). Talepler: 1 yeni, 2 hazırlanıyor (yönetim notlu), 3 tamamlanmış.
FakeReservationService seededReservation(
  ReservationFakeAuth auth, {
  ReservationSiteAccess kind = ReservationSiteAccess.manager,
}) {
  final service = FakeReservationService(authService: auth, kind: kind);
  service.areas.addAll(<Map<String, dynamic>>[
    rzArea(1),
    rzArea(2, name: 'Toplantı Odası', description: null, capacity: 3, slotMinutes: 30, maxSlots: 4, approval: 'yonetici_onayli'),
    rzArea(3, name: 'Eski Sauna', active: false),
  ]);
  service.reservations.addAll(<Map<String, dynamic>>[
    rzReservation(1, note: 'Antrenman'),
    rzReservation(2, area: 2, areaName: 'Toplantı Odası', status: 'beklemede', date: '2026-10-21', start: '10:00', end: '11:00', canCancel: false, cancelDeadline: '2026-10-20T20:00:00Z', requester: 'Veli Kaya', phone: '+905559998877'),
    rzReservation(3, status: 'tamamlandi', date: '2026-10-10', canCancel: false, cancelDeadline: null),
    rzReservation(4, status: 'iptal', date: '2026-10-22', cancelledBy: 'management', decisionNote: 'Bakım nedeniyle kapalı.', canCancel: false, cancelDeadline: null),
  ]);
  for (final row in service.reservations) {
    if (row['status'] == 'beklemede') row['can_decide'] = true;
  }
  service.requests.addAll(<Map<String, dynamic>>[
    rzRequest(1),
    rzRequest(2, category: 'temizlik', note: 'Misafir öncesi temizlik.', status: 'hazirlaniyor', staffNote: 'Ekip öğleden sonra gelecek.', requestedFor: '2026-10-21T12:00:00Z', requester: 'Veli Kaya'),
    rzRequest(3, category: 'tasima', note: 'Koltuk taşınacak.', status: 'tamamlandi'),
  ]);
  return service;
}

/// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024@1.0).
const List<(double, double, double)> kReservationCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalıdır.
void reservationMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kReservationCells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        '$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok',
        (t) async {
          await body(t, width, height, scale, dark);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

/// [Key] ile kısa bulucu.
Finder rzKey(String key) => find.byKey(ValueKey<String>(key));
