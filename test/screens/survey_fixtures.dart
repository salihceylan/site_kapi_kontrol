// Anket ve Oylama: ekran / pencere testlerinin ortak örnek verisi ve sahte servisi (`_test.dart` ile bitmediği için
// kendi başına test olarak çalışmaz).
//
// Sahte servis SUNUCUYU taklit eder (docs/PLATFORM_ANKET.md): satırlar sunucunun JSON biçiminde tutulur; durum
// geçişleri (draft -> open -> closed), oy kuralları (SURVEY_CLOSED / ALREADY_VOTED / APARTMENT_ALREADY_VOTED) ve kurul
// kısıtı (yazma 403, voters 403) sunucuyla aynı hata kodlarını üretir. Her çağrı kuyruktaki bir hataya takılabilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/survey_api.dart';

import 'people_fixtures.dart';

class SurveyFakeAuth extends PeopleFakeAuth {
  SurveyFakeAuth({super.role});
}

/// Yönetim ayrıntısı (Summary + Detail alanlarının ÜST KÜMESİ; sakin görünümü sadeleştirilir).
Map<String, dynamic> svSurvey(
  int id, {
  String title = 'Otopark düzenlemesi',
  String question = 'Otoparkta numaralı yer uygulamasına geçilsin mi?',
  List<String> options = const <String>['Evet', 'Hayır', 'Kararsızım'],
  String status = 'open',
  String? effectiveStatus,
  String targetType = 'site',
  bool anonymous = true,
  bool oneVote = false,
  String? closesAt = '2026-12-31T20:59:00Z',
  List<int> counts = const <int>[12, 5, 3],
  int eligible = 40,
  int site = 11,
  String siteName = 'Gül Sitesi',
  int? myVote,
  bool resultsVisible = true,
  String? createdBy = 'Mehmet Kaya',
}) {
  final total = counts.fold<int>(0, (a, b) => a + b);
  return <String, dynamic>{
    'id': id,
    'site_code': site,
    'site_name': siteName,
    'title': title,
    'question': question,
    'options': options,
    'status': status,
    'effective_status': effectiveStatus ?? status,
    'target_type': targetType,
    'anonymous': anonymous,
    'one_vote_per_apartment': oneVote,
    'closes_at': closesAt,
    'opened_at': status == 'draft' ? null : '2026-10-10T09:00:00Z',
    'closed_at': status == 'closed' ? '2026-10-15T09:00:00Z' : null,
    'total_votes': total,
    'eligible_count': eligible,
    'created_at': '2026-10-09T09:00:00Z',
    'created_by_name': createdBy,
    'my_vote': myVote,
    'results': resultsVisible
        ? <String, dynamic>{'counts': counts, 'total_votes': total, 'eligible_count': eligible}
        : null,
    'target': <String, dynamic>{'type': targetType, 'block_ids': <int>[], 'apartment_ids': <int>[], 'labels': <String>[]},
  };
}

class FakeSurveyService extends SurveyService {
  FakeSurveyService({required super.authService, this.kind = SurveySiteAccess.manager})
    : super(api: SurveyApi(baseUrl: 'http://localhost'));

  SurveySiteAccess kind;
  final List<Map<String, dynamic>> surveys = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> voterRows = <Map<String, dynamic>>[];

  /// Sakinin dairesinde başka hesap oy verdi (APARTMENT_ALREADY_VOTED taklidi).
  final Set<int> apartmentVoted = <int>{};

  // --- Çağrı kayıtları ---
  final List<({int site, String status, int offset})> listManagedCalls = [];
  final List<SurveyCreateRequest> createCalls = [];
  final List<int> getManagedCalls = [];
  final List<int> openCalls = [];
  final List<int> closeCalls = [];
  final List<int> deleteCalls = [];
  final List<int> votersCalls = [];
  final List<({int? site, int? before})> listMineCalls = [];
  final List<({int id, int option})> voteCalls = [];

  final Map<String, List<Object>> failures = <String, List<Object>>{};
  final Map<String, List<Completer<void>>> gates = <String, List<Completer<void>>>{};

  Future<void> _enter(String op) async {
    final gate = gates[op];
    if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
    final failure = failures[op];
    if (failure != null && failure.isNotEmpty) throw failure.removeAt(0);
  }

  static ApiException error(int status, String code, {String? text}) => ApiException(
    SurveyApi.surveyErrorMessage(code, serverText: text) ?? 'Hata',
    statusCode: status,
    code: code,
  );

  static ApiException moduleOff() => error(403, 'MODULE_DISABLED');

  Map<String, dynamic>? _row(int id) {
    for (final row in surveys) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  int _nextId() {
    var max = 100;
    for (final row in surveys) {
      if ((row['id'] as int) > max) max = row['id'] as int;
    }
    return max + 1;
  }

  void _requireWrite() {
    if (kind != SurveySiteAccess.manager) throw error(403, 'FORBIDDEN_ROLE');
  }

  Map<String, dynamic> _managed(Map<String, dynamic> row) => Map<String, dynamic>.of(row)
    ..remove('my_vote')
    ..['results'] = <String, dynamic>{
      'counts': row['results'] is Map ? (row['results'] as Map)['counts'] : <int>[],
      'total_votes': row['total_votes'],
      'eligible_count': row['eligible_count'],
    };

  @override
  Future<SurveyListPage> listManaged(int siteCode, {String status = 'all', int limit = 30, int offset = 0}) async {
    listManagedCalls.add((site: siteCode, status: status, offset: offset));
    await _enter('listManaged');
    final rows = surveys
        .where((r) => r['site_code'] == siteCode && (status == 'all' || r['status'] == status))
        .toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return SurveyListPage.fromJson(<String, dynamic>{
      'items': rows.skip(offset).take(limit).map(_managed).toList(),
      'total': rows.length,
    });
  }

  @override
  Future<SurveyDetail> create(int siteCode, SurveyCreateRequest request) async {
    createCalls.add(request);
    await _enter('create');
    _requireWrite();
    final json = request.toJson();
    final row = svSurvey(
      _nextId(),
      title: json['title'] as String,
      question: json['question'] as String,
      options: (json['options'] as List).cast<String>(),
      status: request.publishNow ? 'open' : 'draft',
      targetType: request.targetType.apiValue,
      anonymous: request.anonymous,
      oneVote: request.oneVotePerApartment,
      closesAt: json['closes_at'] as String?,
      counts: List<int>.filled(request.options.length, 0),
      site: siteCode,
    );
    surveys.add(row);
    return SurveyDetail.fromJson(_managed(row));
  }

  @override
  Future<SurveyDetail> getManaged(int siteCode, int id) async {
    getManagedCalls.add(id);
    await _enter('getManaged');
    final row = _row(id);
    if (row == null || row['site_code'] != siteCode) throw error(404, 'SURVEY_NOT_FOUND');
    return SurveyDetail.fromJson(_managed(row));
  }

  @override
  Future<SurveyDetail> update(int siteCode, int id, Map<String, Object?> fields) async {
    await _enter('update');
    _requireWrite();
    final row = _row(id);
    if (row == null) throw error(404, 'SURVEY_NOT_FOUND');
    if (row['status'] == 'closed') throw error(409, 'INVALID_STATE');
    row.addAll(fields);
    return SurveyDetail.fromJson(_managed(row));
  }

  @override
  Future<SurveyDetail> open(int siteCode, int id) async {
    openCalls.add(id);
    await _enter('open');
    _requireWrite();
    final row = _row(id);
    if (row == null) throw error(404, 'SURVEY_NOT_FOUND');
    if (row['status'] != 'draft') throw error(409, 'INVALID_STATE');
    row['status'] = 'open';
    row['effective_status'] = 'open';
    row['opened_at'] = '2026-10-18T09:00:00Z';
    return SurveyDetail.fromJson(_managed(row));
  }

  @override
  Future<SurveyDetail> close(int siteCode, int id) async {
    closeCalls.add(id);
    await _enter('close');
    _requireWrite();
    final row = _row(id);
    if (row == null) throw error(404, 'SURVEY_NOT_FOUND');
    if (row['status'] != 'open') throw error(409, 'INVALID_STATE');
    row['status'] = 'closed';
    row['effective_status'] = 'closed';
    row['closed_at'] = '2026-10-18T10:00:00Z';
    return SurveyDetail.fromJson(_managed(row));
  }

  @override
  Future<void> delete(int siteCode, int id) async {
    deleteCalls.add(id);
    await _enter('delete');
    _requireWrite();
    final row = _row(id);
    if (row == null) throw error(404, 'SURVEY_NOT_FOUND');
    if (row['status'] != 'draft') throw error(409, 'INVALID_STATE');
    surveys.remove(row);
  }

  @override
  Future<SurveyVoterPage> voters(int siteCode, int id, {int limit = 50, int offset = 0}) async {
    votersCalls.add(id);
    await _enter('voters');
    if (kind != SurveySiteAccess.manager) throw error(403, 'FORBIDDEN_ROLE');
    final row = _row(id);
    if (row == null) throw error(404, 'SURVEY_NOT_FOUND');
    if (row['anonymous'] == true) throw error(409, 'INVALID_STATE');
    return SurveyVoterPage.fromJson(<String, dynamic>{'items': voterRows.skip(offset).take(limit).toList(), 'total': voterRows.length});
  }

  Map<String, dynamic> _resident(Map<String, dynamic> row) {
    final voted = row['my_vote'] != null;
    final open = row['effective_status'] == 'open';
    final results = row['results'];
    return <String, dynamic>{
      'id': row['id'],
      'site_code': row['site_code'],
      'site_name': row['site_name'],
      'title': row['title'],
      'question': row['question'],
      'options': row['options'],
      'effective_status': row['effective_status'],
      'closes_at': row['closes_at'],
      'my_vote': row['my_vote'],
      'results': (voted || !open) && results is Map
          ? <String, dynamic>{'counts': results['counts'], 'total_votes': row['total_votes']}
          : null,
    };
  }

  @override
  Future<SurveyResidentPage> listMine({int? siteCode, int limit = 30, int? beforeId}) async {
    listMineCalls.add((site: siteCode, before: beforeId));
    await _enter('listMine');
    final rows = surveys
        .where((r) => r['status'] != 'draft' && (siteCode == null || r['site_code'] == siteCode))
        .where((r) => beforeId == null || (r['id'] as int) < beforeId)
        .toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final page = rows.take(limit).toList();
    return SurveyResidentPage.fromJson(<String, dynamic>{
      'items': page.map(_resident).toList(),
      'next_before_id': rows.length > limit ? page.last['id'] : null,
    });
  }

  @override
  Future<SurveyResidentItem> getMine(int id) async {
    await _enter('getMine');
    final row = _row(id);
    if (row == null || row['status'] == 'draft') throw error(404, 'SURVEY_NOT_FOUND');
    return SurveyResidentItem.fromJson(_resident(row));
  }

  @override
  Future<SurveyResidentItem> vote(int id, int optionIndex) async {
    voteCalls.add((id: id, option: optionIndex));
    await _enter('vote');
    final row = _row(id);
    if (row == null || row['status'] == 'draft') throw error(404, 'SURVEY_NOT_FOUND');
    if (row['effective_status'] != 'open') throw error(409, 'SURVEY_CLOSED');
    if (row['my_vote'] != null) throw error(409, 'ALREADY_VOTED');
    if (apartmentVoted.contains(id)) throw error(409, 'APARTMENT_ALREADY_VOTED');
    final options = row['options'] as List;
    if (optionIndex < 0 || optionIndex >= options.length) throw error(400, 'INVALID_BODY', text: 'Seçenek geçersiz.');
    final counts = List<int>.of(((row['results'] as Map)['counts'] as List).cast<int>());
    counts[optionIndex] += 1;
    row['my_vote'] = optionIndex;
    row['total_votes'] = (row['total_votes'] as int) + 1;
    row['results'] = <String, dynamic>{'counts': counts, 'total_votes': row['total_votes'], 'eligible_count': row['eligible_count']};
    return SurveyResidentItem.fromJson(_resident(row));
  }
}

/// Örnek veriyle dolu sahte servis: 1 açık (oy verilmemiş), 2 kapalı, 3 taslak, 4 açık oy verilmiş.
FakeSurveyService seededSurvey(SurveyFakeAuth auth, {SurveySiteAccess kind = SurveySiteAccess.manager}) {
  final service = FakeSurveyService(authService: auth, kind: kind);
  service.surveys.addAll(<Map<String, dynamic>>[
    svSurvey(1),
    svSurvey(2, title: 'Havuz saatleri', status: 'closed', counts: const <int>[7, 7, 0], anonymous: false),
    svSurvey(3, title: 'Aidat artışı', status: 'draft', counts: const <int>[0, 0, 0], closesAt: null),
    svSurvey(4, title: 'Bahçe düzenlemesi', myVote: 1, counts: const <int>[3, 9, 1], site: 12, siteName: 'Mavi Park'),
  ]);
  service.voterRows.addAll(<Map<String, dynamic>>[
    <String, dynamic>{'user_code': 4001, 'full_name': 'Ayşe Yılmaz', 'apartment_label': 'A Blok / 5', 'option_index': 0, 'voted_at': '2026-10-11T09:00:00Z'},
    <String, dynamic>{'user_code': null, 'full_name': '', 'apartment_label': 'B Blok / 2', 'option_index': 1, 'voted_at': '2026-10-11T10:00:00Z'},
  ]);
  return service;
}

/// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024@1.0).
const List<(double, double, double)> kSurveyCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

void surveyMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kSurveyCells) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
        await body(t, width, height, scale, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

Finder svKey(String key) => find.byKey(ValueKey<String>(key));
