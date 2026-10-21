// Platform Faz 4a (Aidat ve Finans): ekran / pencere testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (server/src/modules/finance_*.js): defter bellekte tutulur (eklemeli),
// bakiye satırların işaretli toplamıdır, yanıtlar sunucunun gerçek JSON biçiminde üretilip modellerle ayrıştırılır;
// yazmalar sunucu kurallarını aynı hata kodlarıyla uygular (PERIOD_CLOSED, PREVIEW_STALE, ENTRY_ALREADY_REVERSED,
// idempotency_key tekrarı = aynı kayıt, ...). Yarış testleri için çağrılar kuyruktaki bir kapıyı bekleyebilir
// (yanıt çağrı ANINDA hesaplanır, kapı açılınca teslim edilir).
//
// Faz 4a inceleme düzeltmeleri sonrası sunucu davranışı (docs/PLATFORM_FINANS.md eki):
// - Aylar SIRAYLA kapanır ve bir ay kapanınca ondan önceki TÜM aylar kapalı sayılır ([isClosed]); `periods`
//   yanıtı `closable` listesini verir ([omitClosable] eski sunucuyu taklit eder).
// - Önizleme `preview_hash` / `redistributed` / `skipped_count` (ek borçta `duplicate_of_run_id`) döner; onay
//   `expected_hash`i doğrular (uyuşmazsa 409 PREVIEW_STALE + güncel toplam / sayı / özet).
// - Aynı anahtar + farklı gövde = 409 IDEMPOTENCY_CONFLICT; aynı ek borç 24 saat içinde 409 DUPLICATE_CHARGE
//   (`allowDuplicate` ile aşılır).
// - [errorsAfterWrite]: yazma BAŞARILI olduktan SONRA fırlatılan hatalar ("yazıldı ama yanıt kayboldu").
import 'dart:async';
import 'dart:convert';

import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

import 'finance_4b_fixtures.dart';
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
  String? account,
}) => <String, dynamic>{
  'id': id,
  'apartment_id': apartmentId,
  // İP-1A: satırın hesabı (owner | tenant); verilmezse sunucu gibi payer_party'den türetilir ([FinanceFakeAuth.accountOfRow])
  'account_party': ?account,
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
    // Faz 4b uçları (hesaplar, makbuz, ayarlar ...) ağa çıkmasın: sahte 4b API'si kayıtlıdır.
    f4 = registerFakeFinance4b(this);
  }

  /// Faz 4b sahte API'si (kasa / banka, makbuz, gider, tazminat, hatırlatma).
  late final FakeFinance4bApi f4;

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

  /// İP-1A: iki hesaplı daireler: ekstre yanıtı hesap alanlarını (`accounts`, `show_tenant_account`, `default_payment_account`)
  /// taşır ve `?account_party=` süzgecini uygular. Listede OLMAYAN daireler ESKİ sunucu biçimindedir (tek hesap).
  final Set<int> twoAccountApartments = <int>{};

  /// İP-1A: güncel kiracısı olan daireler (`has_current_tenant`).
  final Set<int> currentTenantApartments = <int>{};

  /// İP-1A: dairenin sabit varsayılan tahsilat hesabı (yoksa [defaultPaymentAccountOf] hesaplar).
  final Map<int, String> defaultPaymentAccounts = <int, String>{};

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

  /// true: eski sunucu; `periods` yanıtında `closable` alanı YOKTUR.
  bool omitClosable = false;

  /// Yazma BAŞARILI olduktan SONRA sırayla fırlatılacak hatalar (tek seferlik): istek sunucuda işlenir ama yanıt
  /// kaybolur (ağ kopması / 5xx). Tekrar edilen (yeniden oynatılan) istekler bunu tüketmez.
  final List<Object> errorsAfterWrite = <Object>[];

  /// Önizleme sonrası araya girip verileri değiştiren bir kanca (sıradaki ONAYDAN önce bir kez çalışır):
  /// `preview_hash`in değiştiği ama toplam ve sayının AYNI kaldığı yarışları kurmak içindir.
  void Function()? beforeNextPost;

  // --- Çağrı kayıtları -------------------------------------------------------------------------
  final List<({int site, String status, String? query, int limit, int offset})> balanceCalls =
      <({int site, String status, String? query, int limit, int offset})>[];
  final List<({int apartment, int? before, String? party})> accountCalls = <({int apartment, int? before, String? party})>[];
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

  // İşlem anahtarı -> kayıt kimliği (tekrar = aynı kayıt, 200) ve istek parmak izi (farklı gövde = 409).
  final Map<String, int> _keys = <String, int>{};
  final Map<String, String> _keyFingerprints = <String, String>{};
  final Map<String, FeePostResult> _runKeys = <String, FeePostResult>{};
  final Map<String, String> _runFingerprints = <String, String>{};

  // Son yazılan ek borçlar (24 saat içinde aynısı 409 DUPLICATE_CHARGE).
  final List<({String naturalKey, int runId, DateTime at})> _chargeLog =
      <({String naturalKey, int runId, DateTime at})>[];

  int _nextEntryId = 100;
  int _nextDefinitionId = 50;
  int _nextRunId = 900;

  ApiException _coded(String code, int status, [String? text, Map<String, dynamic>? payload]) => ApiException(
    AuthApi.messageForErrorCode(code) ?? text ?? code,
    statusCode: status,
    code: code,
    payload: payload == null ? null : <String, dynamic>{'code': code, ...payload},
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

  /// En son kapatılan ay (kapalı ay yoksa null). Bu ay ve ÖNCESİ kapalıdır.
  String? get closedThrough =>
      closedPeriods.isEmpty ? null : (List<String>.of(closedPeriods)..sort()).last;

  /// [period] ('YYYY-AA') kapalı mı? Bir ay kapatılınca ondan önceki tüm aylar da kapalı sayılır.
  bool isClosed(String period) {
    final through = closedThrough;
    return through != null && period.compareTo(through) <= 0;
  }

  String get openPeriod {
    var period = currentPeriod;
    while (isClosed(period)) {
      period = FinancePeriod.tryParse(period)!.next.toApi();
    }
    return period;
  }

  /// Şu an kapatılabilecek aylar (yeni -> eski, en çok 12): kapalı ay yoksa bu ay ve önceki 11 ay; varsa yalnız
  /// kapalı ayın sonraki ayı (bu ay ya da öncesiyse).
  List<String> get closableMonths {
    final through = closedThrough;
    final current = FinancePeriod.tryParse(currentPeriod)!;
    if (through == null) {
      return [for (var i = 0; i < 12; i++) current.addMonths(-i).toApi()];
    }
    final next = FinancePeriod.tryParse(through)!.next.toApi();
    return next.compareTo(currentPeriod) <= 0 ? <String>[next] : <String>[];
  }

  /// Yazma sonrası fırlatılacak hata varsa fırlatır (istek işlendi ama yanıt kayboldu).
  void _throwAfterWrite() {
    if (errorsAfterWrite.isNotEmpty) throw errorsAfterWrite.removeAt(0);
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

  /// İP-1A: satırın hesabı (sunucu kuralı: `account_party` yoksa payer_party tenant -> kiracı, diğerleri ev sahibi).
  static String accountOfRow(Map<String, dynamic> e) =>
      (e['account_party'] as String?) ?? (e['payer_party'] == 'tenant' ? 'tenant' : 'owner');

  Iterable<Map<String, dynamic>> _accountEntries(int apartmentId, String party) =>
      _entriesOf(apartmentId).where((e) => accountOfRow(e) == party);

  int accountBalanceOf(int apartmentId, String party) =>
      _accountEntries(apartmentId, party).fold<int>(0, (sum, e) => sum + (e['amount_minor'] as int));

  int accountOverdueOf(int apartmentId, String party) {
    final notDue = _accountEntries(apartmentId, party)
        .where((e) => e['due_date'] != null && (e['due_date'] as String).compareTo(todayIso) > 0)
        .fold<int>(0, (sum, e) => sum + (e['amount_minor'] as int));
    final value = accountBalanceOf(apartmentId, party) - notDue;
    return value > 0 ? value : 0;
  }

  /// Varsayılan tahsilat hesabı (sabit değer yoksa: vadesi geçeni büyük olan hesap; ikisi de sıfırsa kiracı varsa kiracı).
  String defaultPaymentAccountOf(int apartmentId) {
    final fixed = defaultPaymentAccounts[apartmentId];
    if (fixed != null) return fixed;
    final owner = accountOverdueOf(apartmentId, 'owner');
    final tenant = accountOverdueOf(apartmentId, 'tenant');
    if (owner > 0 || tenant > 0) return tenant > owner ? 'tenant' : 'owner';
    return currentTenantApartments.contains(apartmentId) ? 'tenant' : 'owner';
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
      // Faz 4b: makbuz bağlantısı ve tazminat çalıştırması (satırda yoksa null).
      'receipt': row['receipt'],
      'late_fee_run_id': row['late_fee_run_id'],
      // İP-1A: iki hesaplı dairede (ya da satırda hesap varsa) satırın hesabı; eski sunucu biçiminde alan yok
      if (twoAccountApartments.contains(row['apartment_id']) || row['account_party'] != null) 'account_party': accountOfRow(row),
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
      'block_name': _blockOf(id),
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

  /// Önizlemenin içerik özeti (sunucudaki `preview_hash`): satırlar + eksik veri kümesi.
  String _planHash(Map<String, dynamic> plan) {
    final lines = plan['lines'] as Map<int, int>;
    final ids = lines.keys.toList()..sort();
    final parts = <String>[
      for (final id in ids) '$id:${lines[id]}',
      for (final m in plan['missing'] as List) 'm:${(m as Map)['apartment_id']}:${m['reason_code']}',
    ];
    return 'hash-${parts.join('|').hashCode.toRadixString(16)}';
  }

  /// Eksik veri atlanınca payın kalanlara yeniden dağıtıldığı yöntemler (sabit / kategori: dağıtılmaz).
  static const Set<String> _redistributing = <String>{'equal', 'land_share', 'area'};

  /// true: eski sunucu; önizleme yanıtında `preview_hash` / `redistributed` / `skipped_count` YOKTUR ve onay
  /// `expected_hash` doğrulamaz.
  bool omitPreviewHash = false;

  /// true: ek borç önizlemesi `duplicate_of_run_id` BİLDİRMEZ (yakın zamanda yazılmış aynı ek borcu yalnız onay
  /// anında 409 `DUPLICATE_CHARGE` ile yakalar).
  bool omitDuplicateHint = false;

  Map<String, dynamic> _previewJson({
    required Map<String, dynamic> plan,
    required String? period,
    required int? definitionId,
    required bool alreadyPosted,
    required bool closed,
    required String distribution,
    int? duplicateOfRunId,
  }) {
    final lines = plan['lines'] as Map<int, int>;
    final ordered = lines.keys.toList()..sort();
    final missing = plan['missing'] as List;
    return <String, dynamic>{
      'period': period,
      'definition_id': definitionId,
      'currency': 'TRY',
      'total_minor': lines.values.fold<int>(0, (a, b) => a + b),
      'apartment_count': lines.length,
      if (!omitPreviewHash) 'preview_hash': _planHash(plan),
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
      if (!omitPreviewHash) 'skipped_count': missing.length,
      if (!omitPreviewHash)
        'redistributed': missing.isNotEmpty && _redistributing.contains(distribution),
      'already_posted': alreadyPosted,
      'duplicate_of_run_id': duplicateOfRunId,
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
      closed: p != null && isClosed(p),
      distribution: row['distribution'] as String,
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

  ApiException _staleError(Map<String, dynamic> plan) {
    final lines = plan['lines'] as Map<int, int>;
    return _coded('PREVIEW_STALE', 409, null, <String, dynamic>{
      'total_minor': lines.values.fold<int>(0, (a, b) => a + b),
      'apartment_count': lines.length,
      'preview_hash': _planHash(plan),
    });
  }

  /// Ortak onay denetimleri: eksik veri, önizleme güncelliği (toplam, daire sayısı, içerik özeti). Plan ONAY
  /// ANINDA yeniden hesaplanır ([computePlan]); verileri araya sokan kancalar ([beforeNextPost],
  /// [staleOnFirstPost]) önce çalışır. Geçerli (güncel) planı döndürür.
  Map<String, dynamic> _verifyPlan({
    required Map<String, dynamic> Function() computePlan,
    required bool skipMissing,
    required int expectedTotal,
    required int expectedCount,
    String? expectedHash,
  }) {
    final hook = beforeNextPost;
    if (hook != null) {
      beforeNextPost = null;
      hook();
    }
    final plan = computePlan();
    final missing = plan['missing'] as List;
    if (missing.isNotEmpty && !skipMissing) throw _coded('PREVIEW_INCOMPLETE', 409);
    final lines = plan['lines'] as Map<int, int>;
    if (lines.isEmpty) throw _coded('NOTHING_TO_POST', 409);
    if (staleOnFirstPost && !_staleConsumed) {
      _staleConsumed = true;
      // Araya yeni bir daire girdi: toplam ve sayı değişir.
      apartmentsJson[399] = pplApartmentJson(399, 'C Blok - 1', blockId: 3);
      throw _staleError(computePlan());
    }
    final total = lines.values.fold<int>(0, (a, b) => a + b);
    if (total != expectedTotal ||
        lines.length != expectedCount ||
        (expectedHash != null && expectedHash != _planHash(plan))) {
      throw _staleError(plan);
    }
    return plan;
  }

  @override
  Future<FeePostResult> postFeeRun(
    int siteCode,
    int definitionId, {
    FinancePeriod? period,
    DateTime? dueDate,
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    String? expectedHash,
    bool skipMissing = false,
    String? idempotencyKey,
  }) async {
    postCalls.add(<String, Object?>{
      'id': definitionId,
      'period': period?.toApi(),
      'due_date': dueDate,
      'expected_total_minor': expectedTotalMinor,
      'expected_apartment_count': expectedApartmentCount,
      'expected_hash': expectedHash,
      'skip_missing': skipMissing,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = postGate;
    if (gate != null) await gate.future;
    final error = postError;
    if (error != null) throw error;
    final fingerprint =
        'def:$definitionId|${period?.toApi()}|${dueDate == null ? '' : _dateString(dueDate)}|$skipMissing';
    if (idempotencyKey != null && _runKeys.containsKey(idempotencyKey)) {
      // Aynı anahtar: aynı istekse kayıt döner (200), farklı istekse 409.
      if (_runFingerprints[idempotencyKey] != fingerprint) throw _coded('IDEMPOTENCY_CONFLICT', 409);
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
    if (p != null && isClosed(p)) throw _coded('PERIOD_CLOSED', 409);
    final plan = _verifyPlan(
      computePlan: () => _definitionPlan(row),
      skipMissing: skipMissing,
      expectedTotal: expectedTotalMinor,
      expectedCount: expectedApartmentCount,
      expectedHash: expectedHash,
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
    if (idempotencyKey != null) {
      _runKeys[idempotencyKey] = result;
      _runFingerprints[idempotencyKey] = fingerprint;
    }
    _throwAfterWrite();
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

  /// Ek borcun doğal özeti: ad (küçük harf) + tutar + dağıtım + hedef + ETKİN vade (sunucudaki `chargeNaturalKey`).
  String _naturalKey(ExtraChargeInput input) {
    final json = Map<String, dynamic>.of(input.toJson())..remove('due_date');
    json['name'] = (json['name'] as String).toLowerCase();
    json['effective_due'] = input.dueDate == null ? todayIso : _dateString(input.dueDate!);
    return jsonEncode(json);
  }

  /// Son 24 saatteki aynı ek borç; yoksa null.
  ({String naturalKey, int runId, DateTime at})? _recentDuplicate(String naturalKey) {
    for (final entry in _chargeLog.reversed) {
      if (entry.naturalKey == naturalKey && clock().difference(entry.at) < const Duration(hours: 24)) {
        return entry;
      }
    }
    return null;
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
      closed: isClosed(currentPeriod),
      distribution: input.distribution.apiValue,
      duplicateOfRunId: omitDuplicateHint ? null : _recentDuplicate(_naturalKey(input))?.runId,
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
    String? expectedHash,
    bool skipMissing = false,
    bool allowDuplicate = false,
    required String idempotencyKey,
  }) async {
    chargePostCalls.add(<String, Object?>{
      ...input.toJson(),
      'expected_total_minor': expectedTotalMinor,
      'expected_apartment_count': expectedApartmentCount,
      'expected_hash': expectedHash,
      'skip_missing': skipMissing,
      'allow_duplicate': allowDuplicate,
      'idempotency_key': idempotencyKey,
    });
    _guard();
    final gate = postGate;
    if (gate != null) await gate.future;
    final error = postError;
    if (error != null) throw error;
    final fingerprint = 'charge:${jsonEncode(input.toJson())}|$skipMissing';
    if (_runKeys.containsKey(idempotencyKey)) {
      // Aynı anahtar: aynı istekse kayıt döner (200), farklı istekse 409.
      if (_runFingerprints[idempotencyKey] != fingerprint) throw _coded('IDEMPOTENCY_CONFLICT', 409);
      return _runKeys[idempotencyKey]!;
    }
    if (isClosed(currentPeriod)) throw _coded('PERIOD_CLOSED', 409);
    final naturalKey = _naturalKey(input);
    if (!allowDuplicate) {
      final duplicate = _recentDuplicate(naturalKey);
      if (duplicate != null) {
        throw _coded('DUPLICATE_CHARGE', 409, null, <String, dynamic>{
          'existing_run_id': duplicate.runId,
          'posted_at': duplicate.at.toUtc().toIso8601String(),
        });
      }
    }
    final plan = _verifyPlan(
      computePlan: () => _chargePlan(input),
      skipMissing: skipMissing,
      expectedTotal: expectedTotalMinor,
      expectedCount: expectedApartmentCount,
      expectedHash: expectedHash,
    );
    final result = _writeRun(
      period: null,
      definitionId: null,
      definitionName: input.name.trim(),
      plan: plan,
      payerSource: 'apartment',
      dueDate: input.dueDate == null ? null : _dateString(input.dueDate!),
    );
    _runKeys[idempotencyKey] = result;
    _runFingerprints[idempotencyKey] = fingerprint;
    _chargeLog.add((naturalKey: naturalKey, runId: result.runId!, at: clock()));
    _throwAfterWrite();
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
    AccountParty? accountParty,
  }) async {
    accountCalls.add((apartment: apartmentId, before: beforeId, party: accountParty?.apiValue));
    _guard();
    final json = apartmentsJson[apartmentId];
    if (json == null) throw _coded('APARTMENT_NOT_FOUND', 404);
    final two = twoAccountApartments.contains(apartmentId);
    // İP-1A: süzgeç yalnız iki hesaplı dairede uygulanır (eski sunucu süzgeci bilmez, tüm satırları verir).
    final party = two ? accountParty?.apiValue : null;
    var rows = (party == null ? _entriesOf(apartmentId) : _accountEntries(apartmentId, party)).toList()..sort(_compareEntries);
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
      'balance_minor': party == null ? balanceOf(apartmentId) : accountBalanceOf(apartmentId, party),
      'overdue_minor': party != null
          ? accountOverdueOf(apartmentId, party)
          : (two ? accountOverdueOf(apartmentId, 'owner') + accountOverdueOf(apartmentId, 'tenant') : overdueOf(apartmentId)),
      'items': [for (final row in page) _entryJson(row)],
      'next_before_id': rows.length > cap && page.isNotEmpty ? page.last['id'] : null,
      if (two) ...<String, dynamic>{
        'account_party': party,
        'accounts': <String, dynamic>{
          for (final p in const <String>['owner', 'tenant'])
            p: <String, dynamic>{
              'balance_minor': accountBalanceOf(apartmentId, p),
              'overdue_minor': accountOverdueOf(apartmentId, p),
              'entry_count': _accountEntries(apartmentId, p).length,
            },
        },
        'show_tenant_account': true,
        'has_current_tenant': currentTenantApartments.contains(apartmentId),
        'default_payment_account': defaultPaymentAccountOf(apartmentId),
      },
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
        if (row['account_party'] != null) 'account_balance_minor': accountBalanceOf(apartmentId, row['account_party'] as String),
      });

  Map<String, dynamic> _addPayment({
    required int apartmentId,
    required int amount,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    required String key,
    String? account,
  }) {
    final date = _dateString(entryDate);
    if (date.compareTo(todayIso) > 0) throw _invalid('Gelecek tarihli tahsilat girilemez.');
    // Sunucu: tarih bugünden en fazla 5 yıl öncesi olabilir.
    final today = DateTime.parse(todayIso);
    final limit = '${(today.year - 5).toString().padLeft(4, '0')}${todayIso.substring(4)}';
    if (date.compareTo(limit) < 0) {
      throw _invalid('Tahsilat tarihi bugünden en fazla 5 yıl öncesi olabilir.');
    }
    final period = date.substring(0, 7);
    if (isClosed(period)) throw _coded('PERIOD_CLOSED', 409);
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
      // İP-1A: iki hesaplı dairede hesap verilmezse sunucu varsayılan hesabı seçer
      account: account ?? (twoAccountApartments.contains(apartmentId) ? defaultPaymentAccountOf(apartmentId) : null),
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
    AccountParty? accountParty,
  }) async {
    paymentCalls.add(<String, Object?>{
      'apartment_id': apartmentId,
      'amount_minor': amountMinor,
      'entry_date': _dateString(entryDate),
      'method': method.apiValue,
      'description': description,
      'idempotency_key': idempotencyKey,
      'account_party': ?accountParty?.apiValue,
    });
    _guard();
    final gate = paymentGate;
    if (gate != null) await gate.future;
    final error = paymentError;
    if (error != null) throw error;
    // Sunucu: aynı anahtar + AYNI daire / tutar / tarih / yöntem = kayıt döner; açıklama karşılaştırılmaz.
    final fingerprint = 'pay|$apartmentId|$amountMinor|${_dateString(entryDate)}|${method.apiValue}';
    final existing = _byKey(idempotencyKey);
    if (existing != null) {
      if (_keyFingerprints[idempotencyKey] != fingerprint) throw _coded('IDEMPOTENCY_CONFLICT', 409);
      // Sunucu: gövdede hesap verildiyse kayıt O hesapta olmalı (aksi 409)
      if (accountParty != null && accountOfRow(existing) != accountParty.apiValue) throw _coded('IDEMPOTENCY_CONFLICT', 409);
      return _result(existing, apartmentId);
    }
    if (!apartmentsJson.containsKey(apartmentId)) throw _coded('APARTMENT_NOT_FOUND', 404);
    final row = _addPayment(
      apartmentId: apartmentId,
      amount: amountMinor,
      entryDate: entryDate,
      method: method,
      description: description,
      key: idempotencyKey,
      account: accountParty?.apiValue,
    );
    _keyFingerprints[idempotencyKey] = fingerprint;
    _throwAfterWrite();
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
      // İP-1A: ters kayıt asılın hesabındadır
      account: original['account_party'] as String?,
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
    if (existing != null) {
      // Sunucu: aynı anahtar AYNI kaydın ters kaydı için kullanıldıysa kayıt döner, değilse 409.
      if (existing['kind'] != 'reversal' || existing['reverses_entry_id'] != entryId) {
        throw _coded('IDEMPOTENCY_CONFLICT', 409);
      }
      return _result(existing, existing['apartment_id'] as int);
    }
    final original = ledger.where((e) => e['id'] == entryId).toList();
    if (original.isEmpty) throw _coded('ENTRY_NOT_FOUND', 404);
    final reversal = _reverseRow(original.first, reason, key);
    _throwAfterWrite();
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
    AccountParty? accountParty,
  }) async {
    correctCalls.add(<String, Object?>{
      'entry_id': entryId,
      'amount_minor': amountMinor,
      'entry_date': _dateString(entryDate),
      'method': method.apiValue,
      'description': description,
      'idempotency_key': idempotencyKey,
      'account_party': ?accountParty?.apiValue,
    });
    _guard();
    final gate = paymentGate;
    if (gate != null) await gate.future;
    final error = paymentError;
    if (error != null) throw error;
    final fingerprint = 'cor|$entryId|$amountMinor|${_dateString(entryDate)}|${method.apiValue}';
    final existing = _byKey(idempotencyKey);
    if (existing != null) {
      if (_keyFingerprints[idempotencyKey] != fingerprint) throw _coded('IDEMPOTENCY_CONFLICT', 409);
      return _result(existing, existing['apartment_id'] as int);
    }
    final original = ledger.where((e) => e['id'] == entryId).toList();
    if (original.isEmpty) throw _coded('ENTRY_NOT_FOUND', 404);
    if (original.first['kind'] != 'payment') throw _coded('ENTRY_NOT_CORRECTABLE', 409);
    final apartmentId = original.first['apartment_id'] as int;
    // Tek işlem: ters kayıt + yeni tahsilat; ikisinden biri başarısız olursa hiçbiri yazılmaz.
    final snapshot = List<Map<String, dynamic>>.of(ledger);
    final LedgerWriteResult result;
    try {
      final reversal = _reverseRow(original.first, 'Düzeltme', '$idempotencyKey-r');
      final row = _addPayment(
        apartmentId: apartmentId,
        amount: amountMinor,
        entryDate: entryDate,
        method: method,
        description: description,
        key: idempotencyKey,
        // İP-1A: hesap verilmezse asılın hesabı korunur
        account: accountParty?.apiValue ?? (original.first['account_party'] as String?),
      );
      _keyFingerprints[idempotencyKey] = fingerprint;
      result = _result(row, apartmentId, reversal: reversal);
    } catch (_) {
      ledger
        ..clear()
        ..addAll(snapshot);
      rethrow;
    }
    // İşlem tamamlandı (kalıcı); yanıtın kaybolduğu senaryoda hata ŞİMDİ fırlar.
    _throwAfterWrite();
    return result;
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
      if (!omitClosable) 'closable': closableMonths,
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
    // Sunucu: yalnız `closable` listesindeki aylar kapatılabilir (sıralı kapatma; gelecek ay ve kapalı ay yok).
    if (!closableMonths.contains(p)) {
      throw _coded('PERIOD_NOT_CLOSABLE', 409, 'Bu ay şu an kapatılamaz.');
    }
    closedPeriods.add(p);
    _throwAfterWrite();
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
    _throwAfterWrite();
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
  String? account,
  List<Map<String, dynamic>>? accounts,
}) => <String, dynamic>{
  'site_code': siteCode,
  'site_name': siteName,
  'apartment_id': apartmentId,
  // İP-1A: kişinin kendi hesabı ve görünümleri (eski sunucu biçiminde yok)
  'account_party': ?account,
  'accounts': ?accounts,
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

/// İP-1A: sakin "Borcum" görünümü (`items[].accounts[]`): kendi hesabı (`own`) ya da salt okunur kiracı hesabı (`read_only`).
Map<String, dynamic> finMyAccount({
  required String party,
  String role = 'own',
  int balance = 0,
  int overdue = 0,
  String? nextDueDate,
  int? nextDueMinor,
  List<Map<String, dynamic>> recent = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'account_party': party,
  'role': role,
  'balance_minor': balance,
  'overdue_minor': overdue,
  'next_due_date': nextDueDate,
  'next_due_minor': nextDueMinor,
  'visible_from': null,
  'offset_note': false,
  'recent': recent,
};
