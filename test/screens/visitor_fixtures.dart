// Ziyaretçi ve Kargo (`visitor_log`): ekran / pencere testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (docs/PLATFORM_ZIYARETCI_KARGO.md): satırlar bellekte sunucunun gerçek JSON
// biçiminde tutulur ve modellerle ayrıştırılır; sakin listesi yalnız kendi dairelerinin kayıtlarını `before_id`
// imleciyle verir ve görevli adlarını GÖSTERMEZ; yönetim listesi tür / durum / arama süzgeci + `limit/offset` uygular;
// kurulda `next_statuses` boştur ve yazma 403 FORBIDDEN_ROLE; geçişler sunucu tablosundan gelir (409
// INVALID_TRANSITION). Hata ve yarış testleri için her çağrı kuyruktaki bir hataya ya da kapıya takılabilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';

import 'people_fixtures.dart';

/// Sahte kimlik doğrulama (servise `authService` olarak verilir; daire seçici `listApartments` ile çalışır).
class VisitorFakeAuth extends PeopleFakeAuth {
  VisitorFakeAuth({super.role});
}

/// Sunucu geçiş tablosu (sözleşme "Kurallar").
const Map<String, List<String>> kVisitorTransitions = <String, List<String>>{
  'bekliyor': <String>['teslim_edildi', 'iptal'],
  'iceride': <String>['ayrildi', 'iptal'],
  'teslim_edildi': <String>[],
  'ayrildi': <String>[],
  'iptal': <String>[],
};

bool _terminal(Object? status) =>
    status == 'teslim_edildi' || status == 'ayrildi' || status == 'iptal';

/// Sunucu `Entry` gövdesi (yönetim biçimi; sakin çıktısında görevli adları düşer, site alanları eklenir).
Map<String, dynamic> vkEntry(
  int id, {
  String kind = 'cargo',
  String name = 'Aras Kargo',
  String? company,
  String? note,
  String? status,
  int? apartmentId = 301,
  String? apartmentLabel = 'A Blok / 5',
  String? blockName = 'A Blok',
  int site = 11,
  String siteName = 'Gül Sitesi',
  String arrivedAt = '2026-10-18T09:15:00Z',
  String? completedAt,
  String? recordedBy = 'Kapıcı Hasan',
  String? completedBy,
  String? seenAt,
}) {
  final resolved = status ?? (kind == 'cargo' ? 'bekliyor' : 'iceride');
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'site_name': siteName,
    'kind': kind,
    'apartment_id': apartmentId,
    'apartment_label': apartmentLabel,
    'block_name': blockName,
    'visitor_name': name,
    'company': company,
    'note': note,
    'status': resolved,
    'next_statuses': kVisitorTransitions[resolved] ?? const <String>[],
    'arrived_at': arrivedAt,
    'completed_at': completedAt ?? (_terminal(resolved) ? '2026-10-18T11:00:00Z' : null),
    'recorded_by_name': recordedBy,
    'completed_by_name': completedBy ?? (_terminal(resolved) ? 'Kapıcı Hasan' : null),
    'resident_seen_at': seenAt,
  };
}

/// Daire seçici ucunun (`GET .../visitor-entries/apartments`) öğesi: YALNIZ kimlik + etiket (malik / kiracı adı yok).
Map<String, dynamic> vkApartment(int id, String block, String unit) => <String, dynamic>{
  'id': id,
  'apartment_label': '$block - $unit',
  'block_name': block,
  'label': unit,
};

/// Hata ya da yarış için kuyruğa konan sahte servis.
class FakeVisitorService extends VisitorLogService {
  FakeVisitorService({required super.authService, this.kind = VisitorSiteAccess.manager})
    : super(api: VisitorLogApi(baseUrl: 'http://localhost'));

  /// Yönetim görünümündeki rol: manager | staff | board.
  VisitorSiteAccess kind;

  /// Sunucu satırları (yönetim biçimi). Sakin listesinde yalnız [residentApartments] daireleri görünür.
  final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  Set<int> residentApartments = <int>{301};

  // --- Çağrı kayıtları ---
  final List<({int? site, int? before, int limit})> listMineCalls = [];
  final List<({int site, String? kind, String? status, String? query, int limit, int offset})>
  listManagedCalls = [];
  final List<({int site, VisitorCreateRequest request})> createCalls = [];
  final List<({int site, int id, VisitorStatus? status, String? note})> updateCalls = [];
  final List<int> seenCalls = [];
  int summaryCalls = 0;
  final List<({int site, String? query, int limit, int offset})> listApartmentsCalls = [];

  /// Daire seçici ucunun (`GET .../visitor-entries/apartments`) satırları: sunucu biçimi, YALNIZ kimlik + etiket ([vkApartment]).
  final List<Map<String, dynamic>> apartments = <Map<String, dynamic>>[];

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

  static ApiException notFound() => ApiException(
    'Kayıt bulunamadı ya da erişiminiz yok.',
    statusCode: 404,
    code: 'VISITOR_ENTRY_NOT_FOUND',
  );

  static ApiException moduleOff() => ApiException(
    'Ziyaretçi ve kargo kaydı bu site için kapalı.',
    statusCode: 403,
    code: 'MODULE_DISABLED',
  );

  static ApiException invalidTransition() => ApiException(
    'Kaydın durumu bu şekilde değiştirilemez. Kayıt başka biri tarafından kapatılmış olabilir; yenileyip tekrar deneyin.',
    statusCode: 409,
    code: 'INVALID_TRANSITION',
  );

  Map<String, dynamic>? _row(int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  int _nextId() {
    var max = 100;
    for (final row in rows) {
      if ((row['id'] as int) > max) max = row['id'] as int;
    }
    return max + 1;
  }

  Map<String, dynamic> _managerView(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row);
    if (kind == VisitorSiteAccess.board) copy['next_statuses'] = const <String>[];
    copy.remove('site_code');
    copy.remove('site_name');
    return copy;
  }

  Map<String, dynamic> _residentView(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.of(row);
    copy.remove('recorded_by_name');
    copy.remove('completed_by_name');
    copy.remove('next_statuses');
    return copy;
  }

  // --- Sakin ---

  @override
  Future<VisitorResidentPage> listMine({int? siteCode, int limit = 30, int? beforeId}) async {
    listMineCalls.add((site: siteCode, before: beforeId, limit: limit));
    await _enter('listMine');
    final scoped = rows
        .where((r) => residentApartments.contains(r['apartment_id']))
        .where((r) => siteCode == null || r['site_code'] == siteCode)
        .toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final from = beforeId == null ? scoped : scoped.where((r) => (r['id'] as int) < beforeId).toList();
    final page = from.take(limit).toList();
    return VisitorResidentPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _residentView(r)],
      'next_before_id': from.length > limit ? page.last['id'] : null,
    });
  }

  @override
  Future<int> unreadCount() async {
    summaryCalls++;
    await _enter('summary');
    return rows
        .where((r) => residentApartments.contains(r['apartment_id']) && r['resident_seen_at'] == null)
        .length;
  }

  @override
  Future<void> markSeen(int id) async {
    seenCalls.add(id);
    await _enter('seen');
    final row = _row(id);
    if (row == null || !residentApartments.contains(row['apartment_id'])) throw notFound();
    row['resident_seen_at'] ??= '2026-10-18T12:00:00Z';
  }

  // --- Yönetim ---

  @override
  Future<VisitorApartmentPage> listApartments(
    int siteCode, {
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    listApartmentsCalls.add((site: siteCode, query: query, limit: limit, offset: offset));
    await _enter('listApartments');
    final q = (query ?? '').trim().toLowerCase();
    final filtered = apartments
        .where((a) => q.isEmpty || '${a['apartment_label']}'.toLowerCase().contains(q))
        .toList();
    return VisitorApartmentPage.fromJson(<String, dynamic>{
      'items': filtered.skip(offset).take(limit).toList(),
      'total': filtered.length,
    });
  }

  @override
  Future<VisitorManagedPage> listManaged(
    int siteCode, {
    String? kind,
    String? status,
    int? apartmentId,
    String? query,
    String? from,
    String? to,
    int limit = 50,
    int offset = 0,
  }) async {
    listManagedCalls.add((site: siteCode, kind: kind, status: status, query: query, limit: limit, offset: offset));
    await _enter('listManaged');
    final q = (query ?? '').trim().toLowerCase();
    final filtered =
        rows.where((r) {
          if (r['site_code'] != siteCode) return false;
          if (kind != null && kind.isNotEmpty && r['kind'] != kind) return false;
          if (status != null && status.isNotEmpty && r['status'] != status) return false;
          if (apartmentId != null && r['apartment_id'] != apartmentId) return false;
          if (q.isNotEmpty &&
              !'${r['visitor_name']} ${r['company'] ?? ''} ${r['apartment_label'] ?? ''}'
                  .toLowerCase()
                  .contains(q)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final page = filtered.skip(offset).take(limit).toList();
    return VisitorManagedPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _managerView(r)],
      'total': filtered.length,
    });
  }

  @override
  Future<VisitorEntry> create(int siteCode, VisitorCreateRequest request) async {
    createCalls.add((site: siteCode, request: request));
    await _enter('create');
    if (kind == VisitorSiteAccess.board) {
      throw ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
    }
    final body = request.toJson();
    final id = _nextId();
    final row = vkEntry(
      id,
      kind: request.kind.apiValue,
      name: body['visitor_name'] as String,
      company: body['company'] as String?,
      note: body['note'] as String?,
      apartmentId: request.apartmentId,
      apartmentLabel: request.apartmentId == null ? null : 'A Blok / 5',
      blockName: request.apartmentId == null ? null : 'A Blok',
      site: siteCode,
      recordedBy: 'Ben Görevli',
    );
    rows.add(row);
    return VisitorEntry.fromJson(_managerView(row));
  }

  @override
  Future<VisitorEntry> update(int siteCode, int id, {VisitorStatus? status, String? note}) async {
    updateCalls.add((site: siteCode, id: id, status: status, note: note));
    await _enter('update');
    final row = _row(id);
    if (row == null || row['site_code'] != siteCode) throw notFound();
    if (kind == VisitorSiteAccess.board) {
      throw ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');
    }
    if (status != null) {
      final allowed = kVisitorTransitions[row['status']] ?? const <String>[];
      if (!allowed.contains(status.apiValue)) throw invalidTransition();
      row
        ..['status'] = status.apiValue
        ..['next_statuses'] = const <String>[]
        ..['completed_at'] = '2026-10-18T11:00:00Z'
        ..['completed_by_name'] = 'Ben Görevli';
    }
    if (note != null) row['note'] = note.trim().isEmpty ? null : note.trim();
    return VisitorEntry.fromJson(_managerView(row));
  }
}

/// Dört kayıt: bekleyen kargo (sakin görmedi), içerideki ziyaretçi (notlu, görüldü), teslim edilen kargo, ortak
/// alan ziyaretçisi (dairesiz; sakin listesinde görünmez).
FakeVisitorService seededVisitor(VisitorFakeAuth auth, {VisitorSiteAccess kind = VisitorSiteAccess.manager}) {
  final service = FakeVisitorService(authService: auth, kind: kind);
  service.rows.addAll(<Map<String, dynamic>>[
    vkEntry(1, kind: 'cargo', name: 'Aras Kargo', company: 'Takip 12345', status: 'teslim_edildi', seenAt: '2026-10-17T10:00:00Z', arrivedAt: '2026-10-17T09:00:00Z'),
    vkEntry(2, kind: 'visitor', name: 'Ayşe Yılmaz', company: 'Temizlik A.Ş.', note: 'Haftalık temizlik için geldi.', seenAt: '2026-10-18T09:40:00Z'),
    vkEntry(3, kind: 'cargo', name: 'Yurtiçi Kargo', note: 'Büyük koli, kapıcı dairesinde.'),
    vkEntry(4, kind: 'visitor', name: 'Elektrikçi Mehmet', apartmentId: null, apartmentLabel: null, blockName: null, arrivedAt: '2026-10-18T10:05:00Z'),
  ]);
  return service;
}

/// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024@1.0).
const List<(double, double, double)> kVisitorCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalıdır.
void visitorMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kVisitorCells) {
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
Finder vkKey(String key) => find.byKey(ValueKey<String>(key));
