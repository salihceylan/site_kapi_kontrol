// Karar Defteri: ekran / pencere testlerinin ortak örnek verisi ve sahte servisi (`_test.dart` ile bitmediği için kendi
// başına test olarak çalışmaz).
//
// Sahte servis SUNUCUYU taklit eder: satırlar sunucunun JSON biçiminde tutulur; taslak -> kesin geçişi (numara yıl
// içinde sırayla verilir), kesin kayıtta yazma 409 DECISION_FINAL, kurulda yazma 403 FORBIDDEN_ROLE, düzeltme kararı
// kesinleşince eski kararın `superseded_by` alanı dolar; sakin yalnız KESİN + `sakinler` kararları görür (status /
// visibility / created_by_name alanları olmadan). Her çağrı kuyruktaki bir hataya ya da kapıya takılabilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';

import 'people_fixtures.dart';

class DecisionFakeAuth extends PeopleFakeAuth {
  DecisionFakeAuth({super.role});
}

/// Testlerde "bugün": 19.10.2026 (İstanbul).
DateTime decisionTestClock() => DateTime.utc(2026, 10, 19, 9);

/// Yönetim görünümündeki karar (sunucu `mapDecision` biçimi).
Map<String, dynamic> dcJson(
  int id, {
  int site = 11,
  String date = '2026-03-05',
  int? no,
  String type = 'yonetim_kurulu',
  String title = 'Asansör bakım sözleşmesinin yenilenmesi',
  String body = 'Asansör bakım firmasıyla sözleşmenin bir yıl uzatılmasına karar verildi.\nÖdeme aylık yapılacaktır.',
  String? attendees = 'Ayşe Yılmaz (Başkan), Mehmet Demir, Zeynep Kaya',
  String vote = 'kabul',
  int? votesFor = 3,
  int? votesAgainst = 0,
  int? votesAbstain = 1,
  String visibility = 'yonetim',
  String status = 'taslak',
  int? supersedesId,
  String? supersedesLabel,
  List<Map<String, dynamic>> supersededBy = const <Map<String, dynamic>>[],
  String? createdBy = 'Mehmet Kaya',
}) {
  final year = int.parse(date.substring(0, 4));
  final number = status == 'kesin' ? (no ?? id) : null;
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'year': year,
    'decision_no': number,
    'number_label': number == null ? null : '$year/$number',
    'meeting_type': type,
    'meeting_date': date,
    'title': title,
    'body': body,
    'attendees': attendees,
    'vote_result': vote,
    'votes_for': votesFor,
    'votes_against': votesAgainst,
    'votes_abstain': votesAbstain,
    'visibility': visibility,
    'status': status,
    'supersedes_id': supersedesId,
    'supersedes_label': supersedesLabel,
    'superseded_by': supersededBy,
    'created_by_name': createdBy,
    'finalized_by_name': status == 'kesin' ? 'Ayşe Yılmaz' : null,
    'finalized_at': status == 'kesin' ? '2026-03-06T10:30:00Z' : null,
    'created_at': '2026-03-05T18:00:00Z',
    'updated_at': '2026-03-06T10:30:00Z',
  };
}

/// Sakin görünümü: yönetime özel alanlar çıkarılır.
Map<String, dynamic> dcResident(Map<String, dynamic> row) => Map<String, dynamic>.of(row)
  ..remove('status')
  ..remove('visibility')
  ..remove('created_by_name');

class FakeDecisionService extends DecisionBookService {
  FakeDecisionService({required super.authService, this.kind = DecisionSiteAccess.manager})
    : super(api: DecisionBookApi(baseUrl: 'http://localhost'));

  DecisionSiteAccess kind;
  final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

  /// Verilirse sayfa boyu (kaydırma / "Daha fazla" testleri için); null ise istekteki `limit`.
  int? pageLimit;

  /// true: imleç `next_cursor` (opak) olarak döner; false: `next_before_id`.
  bool opaqueCursor = false;

  // --- Çağrı kayıtları ---
  final List<({int site, int? year, String status, String? type, String? query, DecisionCursor? cursor, int limit})>
  listManagedCalls = [];
  final List<({int site, DecisionInput input})> createCalls = [];
  final List<({int id, Map<String, Object?> fields})> updateCalls = [];
  final List<int> getManagedCalls = [];
  final List<int> deleteCalls = [];
  final List<int> finalizeCalls = [];
  final List<({int? site, int? year, DecisionCursor? cursor})> listMineCalls = [];
  final List<int> getMineCalls = [];

  final Map<String, List<Object>> failures = <String, List<Object>>{};
  final Map<String, List<Completer<void>>> gates = <String, List<Completer<void>>>{};

  Future<void> _enter(String op) async {
    final gate = gates[op];
    if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
    final failure = failures[op];
    if (failure != null && failure.isNotEmpty) throw failure.removeAt(0);
  }

  static ApiException error(int status, String code, {String? field, String? text}) => ApiException(
    DecisionBookApi.decisionErrorMessage(code, field: field, serverText: text) ?? 'Hata',
    statusCode: status,
    code: code,
    payload: <String, dynamic>{'code': code, 'field': ?field, 'error': ?text},
  );

  static ApiException moduleOff() => error(403, 'MODULE_DISABLED');

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

  void _requireWrite() {
    if (kind != DecisionSiteAccess.manager) throw error(403, 'FORBIDDEN_ROLE');
  }

  String? _label(Map<String, dynamic> row) => row['number_label'] as String?;

  /// Sunucu sırası (sözleşme "Sıralama ve sayfalama"): önce taslaklar (yıl azalan, sonra en yeni), ardından kesin
  /// kararlar (yıl ve karar numarası azalan).
  List<Map<String, dynamic>> _sorted(Iterable<Map<String, dynamic>> source) => source.toList()
    ..sort((a, b) {
      final aDraft = a['status'] == 'taslak';
      final bDraft = b['status'] == 'taslak';
      if (aDraft != bDraft) return aDraft ? -1 : 1;
      final byYear = (b['year'] as int).compareTo(a['year'] as int);
      if (byYear != 0) return byYear;
      if (aDraft) return (b['id'] as int).compareTo(a['id'] as int);
      return (b['decision_no'] as int).compareTo(a['decision_no'] as int);
    });

  Map<String, dynamic> _page(List<Map<String, dynamic>> filtered, DecisionCursor? cursor, int limit, List<int> years, {bool resident = false}) {
    var start = 0;
    if (cursor != null) {
      if (cursor.param == 'cursor') {
        start = int.parse(cursor.value.replaceFirst('c', ''));
      } else {
        // Sahte: imleç, önceki sayfanın son kaydının kimliğidir; sayfa ondan sonra başlar.
        final before = int.parse(cursor.value);
        final at = filtered.indexWhere((r) => r['id'] == before);
        start = at < 0 ? filtered.length : at + 1;
      }
    }
    final size = pageLimit ?? limit;
    final page = filtered.skip(start).take(size).toList();
    final more = start + page.length < filtered.length;
    return <String, dynamic>{
      'items': [for (final r in page) resident ? dcResident(r) : r],
      if (opaqueCursor) 'next_cursor': more ? 'c${start + page.length}' : null,
      if (!opaqueCursor) 'next_before_id': more ? page.last['id'] : null,
      'years': years,
    };
  }

  List<int> _years(Iterable<Map<String, dynamic>> source) =>
      (<int>{for (final r in source) r['year'] as int}.toList()..sort((a, b) => b.compareTo(a)));

  @override
  Future<DecisionPage> listManaged(
    int siteCode, {
    int? year,
    String status = 'all',
    String? meetingType,
    String? query,
    DecisionCursor? cursor,
    int limit = 30,
  }) async {
    listManagedCalls.add((site: siteCode, year: year, status: status, type: meetingType, query: query, cursor: cursor, limit: limit));
    await _enter('listManaged');
    final siteRows = rows.where((r) => r['site_code'] == siteCode);
    final q = (query ?? '').trim().toLowerCase();
    final filtered = _sorted(
      siteRows.where(
        (r) =>
            (year == null || r['year'] == year) &&
            (status == 'all' || r['status'] == status) &&
            (meetingType == null || r['meeting_type'] == meetingType) &&
            (q.isEmpty ||
                (r['title'] as String).toLowerCase().contains(q) ||
                (r['body'] as String).toLowerCase().contains(q) ||
                (r['number_label'] ?? '') == q),
      ),
    );
    return DecisionPage.fromJson(_page(filtered, cursor, limit, _years(siteRows)));
  }

  @override
  Future<Decision> getManaged(int siteCode, int id) async {
    getManagedCalls.add(id);
    await _enter('getManaged');
    final row = _row(id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'DECISION_NOT_FOUND');
    return Decision.fromResponse(<String, dynamic>{'decision': row})!;
  }

  @override
  Future<Decision> create(int siteCode, DecisionInput input) async {
    createCalls.add((site: siteCode, input: input));
    await _enter('create');
    _requireWrite();
    final json = input.toJson();
    final supersedes = input.supersedesId == null ? null : _row(input.supersedesId!);
    if (input.supersedesId != null && (supersedes == null || supersedes['status'] != 'kesin')) {
      throw error(400, 'INVALID_FIELD', field: 'supersedes_id', text: 'Değiştirilen karar kesinleşmiş olmalıdır.');
    }
    final row = dcJson(
      _nextId(),
      site: siteCode,
      date: json['meeting_date'] as String,
      type: json['meeting_type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      attendees: json['attendees'] as String?,
      vote: json['vote_result'] as String,
      votesFor: json['votes_for'] as int?,
      votesAgainst: json['votes_against'] as int?,
      votesAbstain: json['votes_abstain'] as int?,
      visibility: json['visibility'] as String,
      supersedesId: supersedes?['id'] as int?,
      supersedesLabel: supersedes == null ? null : _label(supersedes),
    );
    rows.add(row);
    return Decision.fromResponse(<String, dynamic>{'decision': row})!;
  }

  @override
  Future<Decision> update(int siteCode, int id, Map<String, Object?> fields) async {
    updateCalls.add((id: id, fields: fields));
    await _enter('update');
    _requireWrite();
    final row = _row(id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'DECISION_NOT_FOUND');
    if (row['status'] != 'taslak') throw error(409, 'DECISION_FINAL');
    row.addAll(fields);
    if (fields['meeting_date'] is String) row['year'] = int.parse((fields['meeting_date'] as String).substring(0, 4));
    return Decision.fromResponse(row)!;
  }

  @override
  Future<void> delete(int siteCode, int id) async {
    deleteCalls.add(id);
    await _enter('delete');
    _requireWrite();
    final row = _row(id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'DECISION_NOT_FOUND');
    if (row['status'] != 'taslak') throw error(409, 'DECISION_FINAL');
    rows.remove(row);
  }

  @override
  Future<Decision> finalize(int siteCode, int id) async {
    finalizeCalls.add(id);
    await _enter('finalize');
    _requireWrite();
    final row = _row(id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'DECISION_NOT_FOUND');
    if (row['status'] != 'taslak') throw error(409, 'DECISION_FINAL');
    final year = row['year'] as int;
    var max = 0;
    for (final r in rows) {
      if (r['site_code'] == siteCode && r['year'] == year && r['decision_no'] is int && (r['decision_no'] as int) > max) {
        max = r['decision_no'] as int;
      }
    }
    row['status'] = 'kesin';
    row['decision_no'] = max + 1;
    row['number_label'] = '$year/${max + 1}';
    row['finalized_by_name'] = 'Mehmet Kaya';
    row['finalized_at'] = '2026-10-19T08:00:00Z';
    final old = row['supersedes_id'] == null ? null : _row(row['supersedes_id'] as int);
    if (old != null) {
      old['superseded_by'] = <Map<String, dynamic>>[
        ...(old['superseded_by'] as List).cast<Map<String, dynamic>>(),
        <String, dynamic>{'id': row['id'], 'number_label': row['number_label']},
      ];
    }
    return Decision.fromResponse(<String, dynamic>{'decision': row})!;
  }

  bool _residentVisible(Map<String, dynamic> r) => r['status'] == 'kesin' && r['visibility'] == 'sakinler';

  @override
  Future<DecisionPage> listMine({int? siteCode, int? year, DecisionCursor? cursor, int limit = 30}) async {
    listMineCalls.add((site: siteCode, year: year, cursor: cursor));
    await _enter('listMine');
    final visible = rows.where((r) => _residentVisible(r) && (siteCode == null || r['site_code'] == siteCode));
    final filtered = _sorted(visible.where((r) => year == null || r['year'] == year));
    return DecisionPage.fromJson(_page(filtered, cursor, limit, _years(visible), resident: true), resident: true);
  }

  @override
  Future<Decision> getMine(int id) async {
    getMineCalls.add(id);
    await _enter('getMine');
    final row = _row(id);
    if (row == null || !_residentVisible(row)) throw error(404, 'DECISION_NOT_FOUND');
    return Decision.fromResponse(<String, dynamic>{'decision': dcResident(row)}, resident: true)!;
  }
}

/// Örnek veri (site 11): 1 kesin 2026/1 (sakinlere açık, 3 numaralı kararla değiştirildi), 2 taslak, 3 kesin 2026/2
/// (1'i değiştirir, sakinlere açık), 4 kesin 2025/1 (genel kurul, yalnız yönetim). Site 12: 5 kesin 2026/1 (sakinlere
/// açık).
FakeDecisionService seededDecisions(DecisionFakeAuth auth, {DecisionSiteAccess kind = DecisionSiteAccess.manager}) {
  final service = FakeDecisionService(authService: auth, kind: kind);
  service.rows.addAll(<Map<String, dynamic>>[
    dcJson(
      1,
      no: 1,
      status: 'kesin',
      visibility: 'sakinler',
      supersededBy: <Map<String, dynamic>>[
        <String, dynamic>{'id': 3, 'number_label': '2026/2'},
      ],
    ),
    dcJson(2, date: '2026-09-12', title: 'Bahçe aydınlatmasının yenilenmesi', vote: 'ertelendi', votesFor: null, votesAgainst: null, votesAbstain: null),
    dcJson(
      3,
      no: 2,
      date: '2026-06-20',
      status: 'kesin',
      visibility: 'sakinler',
      title: 'Asansör bakım sözleşmesinin düzeltilmesi',
      supersedesId: 1,
      supersedesLabel: '2026/1',
    ),
    dcJson(
      4,
      no: 1,
      date: '2025-11-02',
      status: 'kesin',
      type: 'genel_kurul',
      title: 'Aidat artışının onaylanması',
      vote: 'ret',
      votesFor: 12,
      votesAgainst: 30,
      votesAbstain: 4,
    ),
    dcJson(5, site: 12, no: 1, status: 'kesin', visibility: 'sakinler', title: 'Otopark çizgilerinin yenilenmesi'),
  ]);
  return service;
}

/// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024@1.0).
const List<(double, double, double)> kDecisionCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

void decisionMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kDecisionCells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
        await body(t, width, height, scale, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

Finder dcKey(String key) => find.byKey(ValueKey<String>(key));
