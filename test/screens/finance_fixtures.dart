// Platform Faz 4a (Aidat ve Finans): ekran / pencere testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (server/src/modules/finance_*.js): defter bellekte tutulur (eklemeli),
// bakiye satırların işaretli toplamıdır, yanıtlar sunucunun gerçek JSON biçiminde üretilip modellerle ayrıştırılır;
// yazmalar sunucu kurallarını aynı hata kodlarıyla uygular (PERIOD_CLOSED, PREVIEW_STALE, ENTRY_ALREADY_REVERSED,
// idempotency_key tekrarı = aynı kayıt, ...). Yarış testleri için çağrılar kuyruktaki bir kapıyı bekleyebilir
// (yanıt çağrı ANINDA hesaplanır, kapı açılınca teslim edilir).
import 'dart:async';

import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

import 'people_fixtures.dart';

/// Sunucudaki bir tanım satırı (`mapDefinitionRow`).
Map<String, dynamic> finDefinition(
  int id, {
  String name = 'Aylık aidat',
  String kind = 'recurring',
  String distribution = 'fixed',
  int? amount = 50000,
  Map<String, int>? categories,
  String? areaBasis,
  int? dueDay = 15,
  String start = '2026-01',
  String? end,
  String targetType = 'site',
  List<int> blockIds = const <int>[],
  List<int> apartmentIds = const <int>[],
  bool active = true,
  String? lastPosted,
  bool? hasRuns,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'kind': kind,
  'distribution': distribution,
  'area_basis': areaBasis,
  'amount_minor': distribution == 'category' ? null : amount,
  'category_amounts': distribution == 'category' ? (categories ?? <String, int>{'3+1': 75000}) : null,
  'due_day': kind == 'recurring' ? dueDay : null,
  'start_period': start,
  'end_period': end,
  'target_type': targetType,
  'target_block_ids': List<int>.of(blockIds),
  'target_apartment_ids': List<int>.of(apartmentIds),
  'target': <String, dynamic>{
    'type': targetType,
    'block_ids': List<int>.of(blockIds),
    'apartment_ids': List<int>.of(apartmentIds),
    'blocks': <Map<String, dynamic>>[],
    'apartments': <Map<String, dynamic>>[],
  },
  'is_active': active,
  'has_runs': hasRuns ?? (lastPosted != null),
  'last_posted_period': lastPosted,
  'currency': 'TRY',
};

/// Defterdeki bir satır (sunucudaki `ledger_entries`; JSON'a [FinanceFakeAuth] çevirir).
Map<String, dynamic> finEntry(
  int id,
  int apartmentId, {
  String kind = 'charge',
  required int amount,
  String period = '2026-10',
  String entryDate = '2026-10-01',
  String? dueDate,
  String? description,
  String? method,
  String payer = 'both',
  String? definitionName,
  int? reverses,
  String? reason,
  String by = 'Site Yöneticisi',
  String createdAt = '2026-10-01T09:00:00.000Z',
}) => <String, dynamic>{
  'id': id,
  'apartment_id': apartmentId,
  'kind': kind,
  'amount_minor': amount,
  'period': period,
  'entry_date': entryDate,
  'due_date': dueDate,
  'description': description,
  'method': method,
  'payer_party': payer,
  'definition_name': definitionName,
  'reverses_entry_id': reverses,
  'reversal_reason': reason,
  'created_by_name': by,
  'created_at': createdAt,
};

/// Aidat ve Finans uçları için sahte servis (Kişi ve Daire Kayıtları sahtesinin üstüne kurulur: site listesi,
/// blok yapısı, daire seçici ve oturum oradan gelir).
class FinanceFakeAuth extends PeopleFakeAuth {
  FinanceFakeAuth({super.role, super.sites, super.blocks, super.apartments}) {
    clock = () => DateTime.utc(2026, 10, 16, 9);
  }

  /// Standart veri: 3 daire (301: 3+1, 120,5 m², 35/1000; 302: kategorisiz; 303: B blok), 2 tanım, birkaç hareket.
  factory FinanceFakeAuth.seeded({UserRole role = UserRole.siteManager}) {
    final auth = FinanceFakeAuth(role: role);
    auth.apartmentsJson[301] = pplApartmentJson(
      301,
      'A Blok - 5',
      floor: 2,
      category: '3+1',
      gross: 120.5,
      net: 100,
      shareN: 35,
      shareD: 1000,
      party: 'owner',
      owner: <String, dynamic>{'person_id': 1, 'full_name': 'Ayşe Yılmaz'},
    );
    auth.apartmentsJson[302] = pplApartmentJson(
      302,
      'A Blok - 6',
      category: '2+1',
      gross: 90,
      net: 75,
      shareN: 25,
      shareD: 1000,
      party: 'tenant',
      owner: <String, dynamic>{'person_id': 4, 'full_name': 'Veli Çelik'},
      tenant: <String, dynamic>{'person_id': 2, 'full_name': 'Mehmet Demir'},
    );
    auth.apartmentsJson[303] = pplApartmentJson(303, 'B Blok - 2', blockId: 2);
    auth.definitions[1] = finDefinition(1, lastPosted: '2026-09');
    auth.definitions[2] = finDefinition(
      2,
      name: 'Yönetim gideri',
      distribution: 'equal',
      amount: 90000,
      dueDay: 10,
      active: false,
    );
    // 301: eylül aidatı (vadesi geçmiş, ödenmemiş) + ekim aidatı (vadesi gelmemiş); 302: eylül ödendi + fazla ödeme.
    auth.ledger.addAll(<Map<String, dynamic>>[
      finEntry(
        1,
        301,
        amount: 50000,
        period: '2026-09',
        entryDate: '2026-09-01',
        dueDate: '2026-09-15',
        definitionName: 'Aylık aidat',
        payer: 'owner',
      ),
      finEntry(
        2,
        301,
        amount: 50000,
        entryDate: '2026-10-01',
        dueDate: '2026-10-25',
        definitionName: 'Aylık aidat',
        payer: 'owner',
      ),
      finEntry(
        3,
        302,
        amount: 50000,
        period: '2026-09',
        entryDate: '2026-09-01',
        dueDate: '2026-09-15',
        definitionName: 'Aylık aidat',
        payer: 'tenant',
      ),
      finEntry(
        4,
        302,
        kind: 'payment',
        amount: -80000,
        period: '2026-09',
        entryDate: '2026-09-20',
        method: 'cash',
        description: 'Fazla ödeme',
        payer: 'tenant',
      ),
    ]);
    return auth;
  }

  final Map<int, Map<String, dynamic>> definitions = <int, Map<String, dynamic>>{};
  final List<Map<String, dynamic>> ledger = <Map<String, dynamic>>[];
  final List<String> closedPeriods = <String>[];
  late DateTime Function() clock;

  /// false: modül kapalı; yönetici uçları 403 `MODULE_DISABLED` döner, `my-finance` boş liste verir.
  bool moduleEnabled = true;

  /// Sakin ucunun yanıtı (`/app/my-finance` JSON'u).
  List<Map<String, dynamic>> myFinanceItems = <Map<String, dynamic>>[];

  // --- Kancalar ------------------------------------------------------------------------------
  Object? finError;
  Object? summaryError;
  Object? balancesError;
  Object? definitionsError;
  Object? periodsError;
  Object? accountError;
  Object? myFinanceError;
  Object? paymentError;
  Object? previewError;
  Object? postError;
  Completer<void>? paymentGate;
  Completer<void>? postGate;
  Completer<void>? previewGate;
  Completer<void>? summaryGate;
  Completer<void>? myFinanceGate;
  final List<Completer<void>> balanceGates = <Completer<void>>[];
  final List<Completer<void>> accountGates = <Completer<void>>[];
  final List<Completer<void>> previewGates = <Completer<void>>[];

  /// Sıradaki önizleme / onay yanıtlarını bozmak için: ilk onayda `PREVIEW_STALE` döner ve araya yeni bir daire
  /// borç girer (toplam değişir).
  bool staleOnFirstPost = false;
  bool _staleConsumed = false;

  // --- Çağrı kayıtları -------------------------------------------------------------------------
  final List<({int site, String status, String? query, int limit, int offset})> balanceCalls =
      <({int site, String status, String? query, int limit, int offset})>[];
  final List<({int apartment, int? before})> accountCalls = <({int apartment, int? before})>[];
  final List<Map<String, Object?>> paymentCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> correctCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> reverseCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> previewCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> postCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> chargePreviewCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> chargePostCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> definitionCreateCalls = <Map<String, Object?>>[];
  final List<({int id, Map<String, Object?> fields})> definitionUpdateCalls =
      <({int id, Map<String, Object?> fields})>[];
  final List<({int site, FeeKind? kind, bool? active})> definitionListCalls =
      <({int site, FeeKind? kind, bool? active})>[];
  final List<String> periodCalls = <String>[];
  int summaryCalls = 0;
  int periodsGetCalls = 0;
  int myFinanceCalls = 0;

  // İşlem anahtarı -> kayıt kimliği (tekrar = aynı kayıt, 200).
  final Map<String, int> _keys = <String, int>{};
  final Map<String, FeePostResult> _runKeys = <String, FeePostResult>{};

  int _nextEntryId = 100;
  int _nextDefinitionId = 50;
  int _nextRunId = 900;

  ApiException _coded(String code, int status, [String? text]) => ApiException(
    AuthApi.messageForErrorCode(code) ?? text ?? code,
    statusCode: status,
    code: code,
  );

  ApiException _invalid(String text) => ApiException(text, statusCode: 400, code: 'INVALID_BODY');

  void _guard() {
    if (!moduleEnabled) throw _coded('MODULE_DISABLED', 403);
    final error = finError;
    if (error != null) throw error;
  }

  Future<void> _gateOf(List<Completer<void>> queue) async {
    if (queue.isEmpty) return;
    await queue.removeAt(0).future;
  }

  // --- Tarih ve dönem yardımcıları -----------------------------------------------------------
  String get todayIso {
    final w = clock().toUtc().add(const Duration(hours: 3));
    return '${w.year.toString().padLeft(4, '0')}-${w.month.toString().padLeft(2, '0')}-${w.day.toString().padLeft(2, '0')}';
  }

  String get currentPeriod => todayIso.substring(0, 7);

  String get openPeriod {
    var period = currentPeriod;
    while (closedPeriods.contains(period)) {
      period = FinancePeriod.tryParse(period)!.next.toApi();
    }
    return period;
  }

  // --- Defter ------------------------------------------------------------------------------------
  Iterable<Map<String, dynamic>> _entriesOf(int apartmentId) =>
      ledger.where((e) => e['apartment_id'] == apartmentId);

  int balanceOf(int apartmentId) =>
      _entriesOf(apartmentId).fold<int>(0, (sum, e) => sum + (e['amount_minor'] as int));

  int overdueOf(int apartmentId) {
    final notDue = _entriesOf(apartmentId)
        .where((e) => e['due_date'] != null && (e['due_date'] as String).compareTo(todayIso) > 0)
        .fold<int>(0, (sum, e) => sum + (e['amount_minor'] as int));
    final value = balanceOf(apartmentId) - notDue;
    return value > 0 ? value : 0;
  }

  Map<String, dynamic> _entryJson(Map<String, dynamic> row, {bool resident = false}) {
    final reversedBy = ledger.where((e) => e['reverses_entry_id'] == row['id']).toList();
    return <String, dynamic>{
      'id': row['id'],
      'kind': row['kind'],
      'amount_minor': row['amount_minor'],
      'period': row['period'],
      'entry_date': row['entry_date'],
      'due_date': row['due_date'],
      'description': resident ? null : row['description'],
      'method': row['method'],
      'payer_party': row['payer_party'],
      'definition_name': row['definition_name'],
      'reverses_entry_id': row['reverses_entry_id'],
      'reversed_by_entry_id': reversedBy.isEmpty ? null : reversedBy.first['id'],
      'reversal_reason': resident ? null : row['reversal_reason'],
      'created_by_name': resident ? null : row['created_by_name'],
      'created_at': row['created_at'],
    };
  }

  static int _compareEntries(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byDate = (b['entry_date'] as String).compareTo(a['entry_date'] as String);
    return byDate != 0 ? byDate : (b['id'] as int).compareTo(a['id'] as int);
  }

  String _labelOf(int apartmentId) =>
      (apartmentsJson[apartmentId]?['label'] as String?) ?? 'Daire $apartmentId';

  String? _blockOf(int apartmentId) => apartmentsJson[apartmentId]?['block_name'] as String?;

  // --- Tanımlar ----------------------------------------------------------------------------------

  @override
  Future<List<FeeDefinition>> listFeeDefinitions(int siteCode, {FeeKind? kind, bool? active}) async {
    definitionListCalls.add((site: siteCode, kind: kind, active: active));
    _guard();
    final error = definitionsError;
    if (error != null) throw error;
    final rows = definitions.values.where((d) {
      if (kind != null && d['kind'] != kind.apiValue) return false;
      if (active != null && d['is_active'] != active) return false;
      return true;
    }).toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return [for (final row in rows) FeeDefinition.fromJson(row)];
  }

  void _validateSpec(Map<String, dynamic> body) {
    final distribution = body['distribution'];
    if (distribution == 'category') {
      final map = body['category_amounts'];
      if (map is! Map || map.isEmpty) throw _invalid('En az bir kategori tutarı girin.');
    } else {
      final amount = body['amount_minor'];
      if (amount is! int || amount <= 0) throw _invalid('Tutar kuruş cinsinden tamsayı olmalıdır.');
      if (body['category_amounts'] != null) {
        throw _invalid('Kategori tutarları yalnızca kategori dağıtımında girilir.');
      }
    }
    if (distribution == 'area' && body['area_basis'] == null) {
      throw _invalid('Alan esası (brüt veya net) zorunludur.');
    }
  }

  @override
  Future<FeeDefinition> createFeeDefinition(int siteCode, FeeDefinitionInput input) async {
    final body = input.toJson();
    definitionCreateCalls.add(Map<String, Object?>.of(body));
    _guard();
    await _writeGate();
    _validateSpec(body);
    if ((body['name'] as String).isEmpty) throw _invalid('Ad boş olamaz.');
    if (input.kind == FeeKind.recurring && input.dueDay == null) {
      throw _invalid('Aylık tanım için vade günü zorunludur.');
    }
    final id = _nextDefinitionId++;
    final target = body['target'] as Map<String, dynamic>;
    definitions[id] = finDefinition(
      id,
      name: body['name'] as String,
      kind: input.kind.apiValue,
      distribution: input.distribution.apiValue,
      amount: body['amount_minor'] as int?,
      categories: (body['category_amounts'] as Map?)?.cast<String, int>(),
      areaBasis: body['area_basis'] as String?,
      dueDay: input.dueDay,
      start: body['start_period'] as String,
      end: body['end_period'] as String?,
      targetType: target['type'] as String,
      blockIds: ((target['block_ids'] as List?) ?? const <int>[]).cast<int>(),
      apartmentIds: ((target['apartment_ids'] as List?) ?? const <int>[]).cast<int>(),
    );
    return FeeDefinition.fromJson(definitions[id]!);
  }

  @override
  Future<FeeDefinition> updateFeeDefinition(
    int siteCode,
    int definitionId,
    Map<String, Object?> fields,
  ) async {
    definitionUpdateCalls.add((id: definitionId, fields: Map<String, Object?>.of(fields)));
    _guard();
    await _writeGate();
    final row = definitions[definitionId];
    if (row == null) throw _coded('DEFINITION_NOT_FOUND', 404);
    const postedKeys = <String>{'name', 'end_period', 'is_active', 'due_day'};
    if (row['has_runs'] == true && fields.keys.any((k) => !postedKeys.contains(k))) {
      throw _coded('DEFINITION_LOCKED', 409);
    }
    fields.forEach((key, value) {
      if (key == 'target') {
        final target = value! as Map<String, dynamic>;
        row['target_type'] = target['type'];
        row['target_block_ids'] = ((target['block_ids'] as List?) ?? const <int>[]).cast<int>();
        row['target_apartment_ids'] = ((target['apartment_ids'] as List?) ?? const <int>[]).cast<int>();
        row['target'] = <String, dynamic>{
          'type': target['type'],
          'block_ids': row['target_block_ids'],
          'apartment_ids': row['target_apartment_ids'],
          'blocks': <Map<String, dynamic>>[],
          'apartments': <Map<String, dynamic>>[],
        };
      } else {
        row[key] = value;
      }
    });
    if (fields['distribution'] == 'category') row['amount_minor'] = null;
    if (fields.containsKey('distribution') && fields['distribution'] != 'category') {
      row['category_amounts'] = null;
    }
    return FeeDefinition.fromJson(row);
  }

  Future<void> _writeGate() async {
    final gate = paymentGate;
    if (gate != null) await gate.future;
  }

  // --- Dağıtım (sunucudaki "en büyük kalan" yöntemi) ---------------------------------------------

  List<int> _targetIds(Map<String, dynamic> target) {
    final type = target['type'];
    final all = apartmentsJson.keys.toList()..sort();
    if (type == 'blocks') {
      final blocks = ((target['block_ids'] as List?) ?? const <int>[]).cast<int>().toSet();
      return all.where((id) => blocks.contains(apartmentsJson[id]!['block_id'])).toList();
    }
    if (type == 'apartments') {
      final ids = ((target['apartment_ids'] as List?) ?? const <int>[]).cast<int>().toSet();
      return all.where(ids.contains).toList();
    }
    return all;
  }

  /// (id -> pay) ve eksik veri listesi. [weights] pozitif tamsayı ağırlıklar, [total] bölünecek kuruş.
  Map<int, int> _split(int total, Map<int, int> weights) {
    final sum = weights.values.fold<int>(0, (a, b) => a + b);
    final result = <int, int>{};
    final remainders = <int, int>{};
    var assigned = 0;
    weights.forEach((id, w) {
      final share = total * w ~/ sum;
      result[id] = share;
      remainders[id] = total * w % sum;
      assigned += share;
    });
    var left = total - assigned;
    final order = remainders.keys.toList()
      ..sort((a, b) {
        final byRemainder = remainders[b]!.compareTo(remainders[a]!);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (final id in order) {
      if (left <= 0) break;
      result[id] = result[id]! + 1;
      left--;
    }
    return result;
  }

  Map<String, dynamic> _plan({
    required String distribution,
    required String? areaBasis,
    required int? amount,
    required Map<String, int>? categories,
    required Map<String, dynamic> target,
  }) {
    final ids = _targetIds(target);
    final lines = <int, int>{};
    final missing = <Map<String, dynamic>>[];
    void miss(int id, String code, String text) => missing.add(<String, dynamic>{
      'apartment_id': id,
      'label': _labelOf(id),
      'reason': text,
      'reason_code': code,
    });
    if (distribution == 'fixed') {
      for (final id in ids) {
        lines[id] = amount!;
      }
    } else if (distribution == 'category') {
      for (final id in ids) {
        final category = apartmentsJson[id]!['category'] as String?;
        if (category == null) {
          miss(id, 'category_missing', 'Kategori tanımsız');
        } else if (!categories!.containsKey(category)) {
          miss(id, 'category_amount_missing', 'Kategori için tutar tanımlı değil');
        } else {
          lines[id] = categories[category]!;
        }
      }
    } else if (distribution == 'equal') {
      if (ids.isNotEmpty) lines.addAll(_split(amount!, {for (final id in ids) id: 1}));
    } else {
      final weights = <int, int>{};
      for (final id in ids) {
        final json = apartmentsJson[id]!;
        if (distribution == 'land_share') {
          final share = json['land_share'] as Map?;
          if (share == null) {
            miss(id, 'land_share_missing', 'Arsa payı tanımsız');
          } else {
            // Ortak payda 1000'e indirgenmiş basit ağırlık (testlerde paydalar 1000).
            weights[id] = (share['numerator'] as int) * (1000 ~/ (share['denominator'] as int));
          }
        } else {
          final area = areaBasis == 'net' ? json['net_area_m2'] : json['gross_area_m2'];
          if (area == null) {
            miss(id, 'area_missing', 'Alan (m²) tanımsız');
          } else {
            weights[id] = ((area as num) * 100).round();
          }
        }
      }
      if (weights.isNotEmpty) lines.addAll(_split(amount!, weights));
    }
    return <String, dynamic>{'lines': lines, 'missing': missing};
  }

  Map<String, dynamic> _previewJson({
    required Map<String, dynamic> plan,
    required String? period,
    required int? definitionId,
    required bool alreadyPosted,
    required bool closed,
  }) {
    final lines = plan['lines'] as Map<int, int>;
    final ordered = lines.keys.toList()..sort();
    return <String, dynamic>{
      'period': period,
      'definition_id': definitionId,
      'currency': 'TRY',
      'total_minor': lines.values.fold<int>(0, (a, b) => a + b),
      'apartment_count': lines.length,
      'lines': [
        for (final id in ordered)
          <String, dynamic>{
            'apartment_id': id,
            'label': _labelOf(id),
            'block_name': _blockOf(id),
            'payer_party': apartmentsJson[id]!['responsible_party'],
            'amount_minor': lines[id],
          },
      ],
      'missing_data': plan['missing'],
      'zero_amount_count': 0,
      'already_posted': alreadyPosted,
      'closed': closed,
    };
  }

  Map<String, dynamic> _definitionPlan(Map<String, dynamic> row) => _plan(
    distribution: row['distribution'] as String,
    areaBasis: row['area_basis'] as String?,
    amount: row['amount_minor'] as int?,
    categories: (row['category_amounts'] as Map?)?.cast<String, int>(),
    target: row['target'] as Map<String, dynamic>,
  );

  String? _periodOf(Map<String, dynamic> row, FinancePeriod? period) =>
      row['kind'] == 'recurring' ? period?.toApi() : currentPeriod;

  bool _posted(int definitionId, String? period) =>
      ledger.any((e) => e['run_definition'] == definitionId && e['run_period'] == period);

  @override
  Future<FeePreview> previewFeeRun(
    int siteCode,
    int definitionId, {
    FinancePeriod? period,
    DateTime? dueDate,
  }) async {
    previewCalls.add(<String, Object?>{
      'id': definitionId,
      'period': period?.toApi(),
      'due_date': dueDate,
    });
    _guard();
    final gate = previewGate;
    final row = definitions[definitionId];
    if (row == null) throw _coded('DEFINITION_NOT_FOUND', 404);
    final p = _periodOf(row, period);
    final json = _previewJson(
      plan: _definitionPlan(row),
      period: p,
      definitionId: definitionId,
      alreadyPosted: _posted(definitionId, p) ||
          (row['last_posted_period'] != null && row['last_posted_period'] == p) ||
          (row['kind'] == 'one_time' && row['has_runs'] == true),
      closed: p != null && closedPeriods.contains(p),
    );
    await _gateOf(previewGates);
    if (gate != null) await gate.future;
    final error = previewError;
    if (error != null) throw error;
    return FeePreview.fromJson(json);
  }

  FeePostResult _writeRun({
    required String? period,
    required int? definitionId,
    required String definitionName,
    required Map<String, dynamic> plan,
    required String payerSource,
    String? dueDate,
    int? dueDay,
  }) {
    final lines = plan['lines'] as Map<int, int>;
    final runId = _nextRunId++;
    final effectivePeriod = period ?? currentPeriod;
    final entryDate = period != null ? '$period-01' : todayIso;
    for (final id in lines.keys.toList()..sort()) {
      ledger.add(
        finEntry(
          _nextEntryId++,
          id,
          amount: lines[id]!,
          period: effectivePeriod,
          entryDate: entryDate,
          dueDate: dueDate ??
              (dueDay != null
                  ? '$effectivePeriod-${dueDay.toString().padLeft(2, '0')}'
                  : todayIso),
          definitionName: definitionName,
          payer: apartmentsJson[id]!['responsible_party'] as String,
        )..addAll(<String, dynamic>{'run_definition': definitionId, 'run_period': period}),
      );
    }
    return FeePostResult(
      runId: runId,
      totalMinor: lines.values.fold<int>(0, (a, b) => a + b),
      apartmentCount: lines.length,
      entriesCount: lines.length,
    );
  }

  /// Ortak onay denetimleri: eksik veri, önizleme güncelliği.
  void _verifyPlan(
    Map<String, dynamic> plan, {
    required bool skipMissing,
    required int expectedTotal,
    required int expectedCount,
  }) {
    final missing = plan['missing'] as List;
    if (missing.isNotEmpty && !skipMissing) throw _coded('PREVIEW_INCOMPLETE', 409);
    final lines = plan['lines'] as Map<int, int>;
    if (lines.isEmpty) throw _coded('NOTHING_TO_POST', 409);
    if (staleOnFirstPost && !_staleConsumed) {
      _staleConsumed = true;
      // Araya yeni bir daire girdi: toplam ve sayı değişir.
      apartmentsJson[399] = pplApartmentJson(399, 'C Blok - 1', blockId: 3);
      throw _coded('PREVIEW_STALE', 409);
    }
    final total = lines.values.fold<int>(0, (a, b) => a + b);
    if (total != expectedTotal || lines.length != expectedCount) throw _coded('PREVIEW_STALE', 409);
  }

  @override
  Future<FeePostResult> postFeeRun(
    int siteCode,
    int definitionId, {
    FinancePeriod? period,
    DateTime? dueDate,
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    bool skipMissing = false,
    String? idempotencyKey,
  }) async {
    postCalls.add(<String, Object?>{
      'id': definitionId,
      'period': period?.toApi(),
      'due_date': dueDate,
      'expected_total_minor': expectedTotalMinor,
      'expected_apartment_count': expectedApartmentCount,
      'skip_missing': skipMissing,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = postGate;
    if (gate != null) await gate.future;
    final error = postError;
    if (error != null) throw error;
    if (idempotencyKey != null && _runKeys.containsKey(idempotencyKey)) {
      return _runKeys[idempotencyKey]!;
    }
    final row = definitions[definitionId];
    if (row == null) throw _coded('DEFINITION_NOT_FOUND', 404);
    if (row['is_active'] != true) throw _coded('DEFINITION_INACTIVE', 409);
    final p = _periodOf(row, period);
    if (_posted(definitionId, p) ||
        (row['last_posted_period'] != null && row['last_posted_period'] == p)) {
      throw _coded('PERIOD_ALREADY_POSTED', 409);
    }
    if (p != null && closedPeriods.contains(p)) throw _coded('PERIOD_CLOSED', 409);
    final plan = _definitionPlan(row);
    _verifyPlan(
      plan,
      skipMissing: skipMissing,
      expectedTotal: expectedTotalMinor,
      expectedCount: expectedApartmentCount,
    );
    final result = _writeRun(
      period: row['kind'] == 'recurring' ? p : null,
      definitionId: definitionId,
      definitionName: row['name'] as String,
      plan: plan,
      payerSource: 'apartment',
      dueDay: row['due_day'] as int?,
      dueDate: dueDate == null ? null : _dateString(dueDate),
    );
    row['has_runs'] = true;
    if (p != null) row['last_posted_period'] = p;
    if (idempotencyKey != null) _runKeys[idempotencyKey] = result;
    return result;
  }

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // --- Ek borç -------------------------------------------------------------------------------

  Map<String, dynamic> _chargePlan(ExtraChargeInput input) {
    final body = input.toJson();
    _validateSpec(body);
    return _plan(
      distribution: input.distribution.apiValue,
      areaBasis: input.areaBasis?.apiValue,
      amount: input.amountMinor,
      categories: input.categoryAmounts.isEmpty ? null : input.categoryAmounts,
      target: body['target'] as Map<String, dynamic>,
    );
  }

  @override
  Future<FeePreview> previewExtraCharge(int siteCode, ExtraChargeInput input) async {
    chargePreviewCalls.add(Map<String, Object?>.of(input.toJson()));
    _guard();
    final gate = previewGate;
    final json = _previewJson(
      plan: _chargePlan(input),
      period: currentPeriod,
      definitionId: null,
      alreadyPosted: false,
      closed: closedPeriods.contains(currentPeriod),
    );
    await _gateOf(previewGates);
    if (gate != null) await gate.future;
    final error = previewError;
    if (error != null) throw error;
    return FeePreview.fromJson(json);
  }

  @override
  Future<FeePostResult> postExtraCharge(
    int siteCode,
    ExtraChargeInput input, {
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    bool skipMissing = false,
    String? idempotencyKey,
  }) async {
    chargePostCalls.add(<String, Object?>{
      ...input.toJson(),
      'expected_total_minor': expectedTotalMinor,
      'expected_apartment_count': expectedApartmentCount,
      'skip_missing': skipMissing,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = postGate;
    if (gate != null) await gate.future;
    final error = postError;
    if (error != null) throw error;
    if (idempotencyKey != null && _runKeys.containsKey(idempotencyKey)) {
      return _runKeys[idempotencyKey]!;
    }
    if (closedPeriods.contains(currentPeriod)) throw _coded('PERIOD_CLOSED', 409);
    final plan = _chargePlan(input);
    _verifyPlan(
      plan,
      skipMissing: skipMissing,
      expectedTotal: expectedTotalMinor,
      expectedCount: expectedApartmentCount,
    );
    final result = _writeRun(
      period: null,
      definitionId: null,
      definitionName: input.name.trim(),
      plan: plan,
      payerSource: 'apartment',
      dueDate: input.dueDate == null ? null : _dateString(input.dueDate!),
    );
    if (idempotencyKey != null) _runKeys[idempotencyKey] = result;
    return result;
  }

  // --- Hesaplar ----------------------------------------------------------------------------------

  @override
  Future<BalancePage> listFinanceBalances(
    int siteCode, {
    String status = 'all',
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    balanceCalls.add((site: siteCode, status: status, query: query, limit: limit, offset: offset));
    _guard();
    final q = (query ?? '').trim().toLowerCase();
    final ids = apartmentsJson.keys.toList()..sort();
    final rows = <Map<String, dynamic>>[];
    for (final id in ids) {
      final json = apartmentsJson[id]!;
      final balance = balanceOf(id);
      if (status == 'debtor' && balance <= 0) continue;
      if (status == 'credit' && balance >= 0) continue;
      final owner = (json['owner'] as Map?)?['full_name'] as String?;
      final tenant = (json['tenant'] as Map?)?['full_name'] as String?;
      if (q.isNotEmpty &&
          !(json['label'] as String).toLowerCase().contains(q) &&
          !(owner ?? '').toLowerCase().contains(q) &&
          !(tenant ?? '').toLowerCase().contains(q)) {
        continue;
      }
      rows.add(<String, dynamic>{
        'apartment_id': id,
        'label': json['label'],
        'block_name': json['block_name'],
        'balance_minor': balance,
        'overdue_minor': overdueOf(id),
        'owner_name': owner,
        'tenant_name': tenant,
      });
    }
    final cap = maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!);
    final page = rows.skip(offset).take(cap).toList();
    var debt = 0;
    var credit = 0;
    for (final id in ids) {
      final b = balanceOf(id);
      if (b > 0) debt += b;
      if (b < 0) credit += -b;
    }
    final result = BalancePage.fromJson(<String, dynamic>{
      'items': page,
      'total': totalOverride ?? rows.length,
      'totals': <String, dynamic>{'debt_minor': debt, 'credit_minor': credit},
    });
    await _gateOf(balanceGates);
    final error = balancesError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<AccountView> getFinanceAccount(
    int siteCode,
    int apartmentId, {
    int limit = 50,
    int? beforeId,
  }) async {
    accountCalls.add((apartment: apartmentId, before: beforeId));
    _guard();
    final json = apartmentsJson[apartmentId];
    if (json == null) throw _coded('APARTMENT_NOT_FOUND', 404);
    var rows = _entriesOf(apartmentId).toList()..sort(_compareEntries);
    if (beforeId != null) {
      final at = rows.indexWhere((e) => e['id'] == beforeId);
      rows = at < 0 ? <Map<String, dynamic>>[] : rows.sublist(at + 1);
    }
    final cap = maxPage == null ? limit : (limit < maxPage! ? limit : maxPage!);
    final page = rows.take(cap).toList();
    final view = AccountView.fromJson(<String, dynamic>{
      'apartment': <String, dynamic>{
        'id': apartmentId,
        'label': json['label'],
        'block_name': json['block_name'],
        'responsible_party': json['responsible_party'],
      },
      'currency': 'TRY',
      'balance_minor': balanceOf(apartmentId),
      'overdue_minor': overdueOf(apartmentId),
      'items': [for (final row in page) _entryJson(row)],
      'next_before_id': rows.length > cap && page.isNotEmpty ? page.last['id'] : null,
    });
    await _gateOf(accountGates);
    final error = accountError;
    if (error != null) throw error;
    return view;
  }

  @override
  Future<FinanceSummary> getFinanceSummary(int siteCode) async {
    summaryCalls++;
    _guard();
    final gate = summaryGate;
    var debt = 0;
    var credit = 0;
    var debtors = 0;
    for (final id in apartmentsJson.keys) {
      final b = balanceOf(id);
      if (b > 0) {
        debt += b;
        debtors++;
      }
      if (b < 0) credit += -b;
    }
    final period = openPeriod;
    final inPeriod = ledger.where((e) => e['period'] == period);
    final charged = inPeriod
        .where((e) => e['kind'] == 'charge' || (e['kind'] == 'reversal' && (e['amount_minor'] as int) < 0))
        .fold<int>(0, (a, e) => a + (e['amount_minor'] as int));
    final collected = inPeriod
        .where((e) => e['kind'] == 'payment' || (e['kind'] == 'reversal' && (e['amount_minor'] as int) > 0))
        .fold<int>(0, (a, e) => a - (e['amount_minor'] as int));
    final result = FinanceSummary.fromJson(<String, dynamic>{
      'currency': 'TRY',
      'open_period': period,
      'balance_total_minor': debt - credit,
      'debt_total_minor': debt,
      'credit_total_minor': credit,
      'debtor_count': debtors,
      'this_period': <String, dynamic>{'charged_minor': charged, 'collected_minor': collected},
    });
    if (gate != null) await gate.future;
    final error = summaryError;
    if (error != null) throw error;
    return result;
  }

  // --- Tahsilat ve düzeltme ----------------------------------------------------------------

  LedgerWriteResult _result(Map<String, dynamic> row, int apartmentId, {Map<String, dynamic>? reversal}) =>
      LedgerWriteResult.fromJson(<String, dynamic>{
        if (reversal != null) 'reversal': _entryJson(reversal),
        'entry': _entryJson(row),
        'balance_minor': balanceOf(apartmentId),
      });

  Map<String, dynamic> _addPayment({
    required int apartmentId,
    required int amount,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String key,
  }) {
    final date = _dateString(entryDate);
    if (date.compareTo(todayIso) > 0) throw _invalid('Gelecek tarihli tahsilat girilemez.');
    final period = date.substring(0, 7);
    if (closedPeriods.contains(period)) throw _coded('PERIOD_CLOSED', 409);
    final row = finEntry(
      _nextEntryId++,
      apartmentId,
      kind: 'payment',
      amount: -amount,
      period: period,
      entryDate: date,
      method: method.apiValue,
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
      payer: apartmentsJson[apartmentId]!['responsible_party'] as String,
    );
    ledger.add(row);
    _keys[key] = row['id'] as int;
    return row;
  }

  Map<String, dynamic>? _byKey(String key) {
    final id = _keys[key];
    if (id == null) return null;
    return ledger.firstWhere((e) => e['id'] == id);
  }

  @override
  Future<LedgerWriteResult> recordFeePayment(
    int siteCode, {
    required int apartmentId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String idempotencyKey,
  }) async {
    paymentCalls.add(<String, Object?>{
      'apartment_id': apartmentId,
      'amount_minor': amountMinor,
      'entry_date': _dateString(entryDate),
      'method': method.apiValue,
      'description': description,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = paymentGate;
    if (gate != null) await gate.future;
    final error = paymentError;
    if (error != null) throw error;
    final existing = _byKey(idempotencyKey);
    if (existing != null) return _result(existing, apartmentId);
    if (!apartmentsJson.containsKey(apartmentId)) throw _coded('APARTMENT_NOT_FOUND', 404);
    final row = _addPayment(
      apartmentId: apartmentId,
      amount: amountMinor,
      entryDate: entryDate,
      method: method,
      description: description,
      key: idempotencyKey,
    );
    return _result(row, apartmentId);
  }

  Map<String, dynamic> _reverseRow(Map<String, dynamic> original, String? reason, String key) {
    if (original['kind'] == 'reversal') throw _coded('ENTRY_NOT_REVERSIBLE', 409);
    if (ledger.any((e) => e['reverses_entry_id'] == original['id'])) {
      throw _coded('ENTRY_ALREADY_REVERSED', 409);
    }
    final period = openPeriod;
    final reversal = finEntry(
      _nextEntryId++,
      original['apartment_id'] as int,
      kind: 'reversal',
      amount: -(original['amount_minor'] as int),
      period: period,
      entryDate: todayIso,
      dueDate: original['due_date'] as String?,
      reverses: original['id'] as int,
      reason: (reason ?? '').trim().isEmpty ? null : reason!.trim(),
      payer: original['payer_party'] as String,
      definitionName: original['definition_name'] as String?,
    );
    ledger.add(reversal);
    _keys[key] = reversal['id'] as int;
    return reversal;
  }

  @override
  Future<LedgerWriteResult> reverseFinanceEntry(
    int siteCode,
    int entryId, {
    String? reason,
    String? idempotencyKey,
  }) async {
    reverseCalls.add(<String, Object?>{
      'entry_id': entryId,
      'reason': reason,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = paymentGate;
    if (gate != null) await gate.future;
    final error = paymentError;
    if (error != null) throw error;
    final key = idempotencyKey ?? 'rev-$entryId';
    final existing = _byKey(key);
    if (existing != null) return _result(existing, existing['apartment_id'] as int);
    final original = ledger.where((e) => e['id'] == entryId).toList();
    if (original.isEmpty) throw _coded('ENTRY_NOT_FOUND', 404);
    final reversal = _reverseRow(original.first, reason, key);
    return _result(reversal, reversal['apartment_id'] as int);
  }

  @override
  Future<LedgerWriteResult> correctFinancePayment(
    int siteCode,
    int entryId, {
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String idempotencyKey,
  }) async {
    correctCalls.add(<String, Object?>{
      'entry_id': entryId,
      'amount_minor': amountMinor,
      'entry_date': _dateString(entryDate),
      'method': method.apiValue,
      'description': description,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = paymentGate;
    if (gate != null) await gate.future;
    final error = paymentError;
    if (error != null) throw error;
    final existing = _byKey(idempotencyKey);
    if (existing != null) return _result(existing, existing['apartment_id'] as int);
    final original = ledger.where((e) => e['id'] == entryId).toList();
    if (original.isEmpty) throw _coded('ENTRY_NOT_FOUND', 404);
    if (original.first['kind'] != 'payment') throw _coded('ENTRY_NOT_CORRECTABLE', 409);
    final apartmentId = original.first['apartment_id'] as int;
    // Tek işlem: ters kayıt + yeni tahsilat; ikisinden biri başarısız olursa hiçbiri yazılmaz.
    final snapshot = List<Map<String, dynamic>>.of(ledger);
    try {
      final reversal = _reverseRow(original.first, 'Düzeltme', '$idempotencyKey-r');
      final row = _addPayment(
        apartmentId: apartmentId,
        amount: amountMinor,
        entryDate: entryDate,
        method: method,
        description: description,
        key: idempotencyKey,
      );
      return _result(row, apartmentId, reversal: reversal);
    } catch (_) {
      ledger
        ..clear()
        ..addAll(snapshot);
      rethrow;
    }
  }

  // --- Dönemler ----------------------------------------------------------------------------------

  Map<String, dynamic> _periodsJson() {
    final sorted = List<String>.of(closedPeriods)..sort();
    return <String, dynamic>{
      'closed_through': sorted.isEmpty ? null : sorted.last,
      'items': [
        for (final p in sorted)
          <String, dynamic>{
            'period': p,
            'closed_at': '2026-10-01T10:00:00.000Z',
            'closed_by_name': 'Site Yöneticisi',
          },
      ],
      'open_period': openPeriod,
    };
  }

  @override
  Future<FinancePeriods> getFinancePeriods(int siteCode) async {
    periodsGetCalls++;
    _guard();
    final error = periodsError;
    if (error != null) throw error;
    return FinancePeriods.fromJson(_periodsJson());
  }

  @override
  Future<void> closeFinancePeriod(int siteCode, FinancePeriod period) async {
    periodCalls.add('close ${period.toApi()}');
    _guard();
    await _writeGate();
    final error = paymentError;
    if (error != null) throw error;
    final p = period.toApi();
    if (p.compareTo(currentPeriod) > 0) {
      throw _coded('PERIOD_NOT_CLOSABLE', 409, 'Gelecek dönem kapatılamaz.');
    }
    if (closedPeriods.contains(p)) throw _coded('PERIOD_NOT_CLOSABLE', 409, 'Bu dönem zaten kapalı.');
    closedPeriods.add(p);
  }

  @override
  Future<void> reopenFinancePeriod(int siteCode, FinancePeriod period) async {
    periodCalls.add('reopen ${period.toApi()}');
    _guard();
    await _writeGate();
    if (role != UserRole.superUser) throw _coded('FORBIDDEN_ROLE', 403);
    final sorted = List<String>.of(closedPeriods)..sort();
    if (sorted.isEmpty || sorted.last != period.toApi()) {
      throw _coded('PERIOD_NOT_REOPENABLE', 409);
    }
    closedPeriods.remove(period.toApi());
  }

  // --- Sakin -------------------------------------------------------------------------------------

  @override
  Future<MyFinance> getMyFinance() async {
    myFinanceCalls++;
    final gate = myFinanceGate;
    final result = MyFinance.fromJson(<String, dynamic>{
      'items': moduleEnabled ? myFinanceItems : <Map<String, dynamic>>[],
    });
    if (gate != null) await gate.future;
    final error = myFinanceError;
    if (error != null) throw error;
    return result;
  }
}

/// Sakin "Borcum" satırı (sunucudaki `getMyFinance` öğesi).
Map<String, dynamic> finMyItem({
  int siteCode = 11,
  String siteName = 'Gül Sitesi',
  int apartmentId = 301,
  String label = 'A Blok - 5',
  int balance = 100000,
  int overdue = 50000,
  String? nextDueDate = '2026-10-25',
  int? nextDueMinor = 50000,
  String payer = 'owner',
  List<Map<String, dynamic>>? recent,
}) => <String, dynamic>{
  'site_code': siteCode,
  'site_name': siteName,
  'apartment_id': apartmentId,
  'label': label,
  'block_name': label.split(' - ').first,
  'currency': 'TRY',
  'balance_minor': balance,
  'overdue_minor': overdue,
  'next_due_date': nextDueDate,
  'next_due_minor': nextDueMinor,
  'payer_party': payer,
  'recent': recent ??
      <Map<String, dynamic>>[
        <String, dynamic>{
          ...finEntry(
            2,
            apartmentId,
            amount: 50000,
            dueDate: '2026-10-25',
            definitionName: 'Aylık aidat',
          ),
          'description': null,
          'reversal_reason': null,
          'created_by_name': null,
          'reversed_by_entry_id': null,
        },
      ],
};
