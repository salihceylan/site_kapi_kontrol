// Ekipman, bakım ve teklif uçları (`equipment` modülü). Sözleşme: docs/PLATFORM_EKIPMAN.md.
//
// Para tamsayı kuruştur. Bakım kaydı yalnız eklenir. Hatırlatma bildirimi (telefon/e-posta) "Yakında…": yaklaşan ve geciken
// bakımlar bu ekranda listelenir. Teklife belge yükleme "Yakında…": şimdilik belge notu yazılır.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/document_models.dart' show documentInstant;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart' show WorkCategory, WorkStatus;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

/// Ekrandaki bir site: yazma yetkisi ve gider / sözleşme modüllerinin durumu.
class EquipmentSite {
  const EquipmentSite({required this.code, required this.name, this.canWrite = true, this.financeOn = false, this.contractsOn = false});

  final int code;
  final String name;
  final bool canWrite;
  final bool financeOn;
  final bool contractsOn;

  String get label => name.trim().isEmpty ? 'Site $code' : name;
}

class EquipmentKind {
  const EquipmentKind(this.code, this.name, {this.legalMonths, this.legalTitle});

  final String code;
  final String name;
  final int? legalMonths;
  final String? legalTitle;
}

/// Varsayılan ekipman türleri (sunucudaki liste ile aynı); tür serbest metin de olabilir.
const List<EquipmentKind> equipmentKinds = <EquipmentKind>[
  EquipmentKind('asansor', 'Asansör', legalMonths: 12, legalTitle: 'Yıllık asansör periyodik kontrolü'),
  EquipmentKind('interkom', 'İnterkom'),
  EquipmentKind('kamera', 'Kamera'),
  EquipmentKind('bariyer', 'Bariyer'),
  EquipmentKind('yangin_algilama', 'Yangın algılama', legalMonths: 12, legalTitle: 'Yıllık yangın sistemi kontrolü'),
  EquipmentKind('hidrofor', 'Hidrofor'),
  EquipmentKind('jenerator', 'Jeneratör'),
  EquipmentKind('kazan', 'Kazan', legalMonths: 12, legalTitle: 'Yıllık kazan periyodik kontrolü'),
  EquipmentKind('havuz', 'Havuz'),
];

String equipmentKindLabel(String code) {
  for (final k in equipmentKinds) {
    if (k.code == code) return k.name;
  }
  return code;
}

const List<int> maintenanceIntervals = <int>[1, 3, 6, 12];

String intervalLabel(int months) => months == 12 ? 'Yılda bir' : (months == 1 ? 'Aylık' : '$months ayda bir');

/// Kuruşu "1.234,50 TL" olarak yazar.
String formatKurus(int kurus) {
  final negative = kurus < 0;
  final abs = kurus.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$grouped,$cents TL';
}

/// "1250,5" / "1.250,50" yazımını kuruşa çevirir; geçersizse null.
int? parseKurus(String input) {
  final text = input.trim().replaceAll('.', '').replaceAll(' ', '').replaceAll(',', '.');
  final match = RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final cents = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + (cents.isEmpty ? 0 : int.parse(cents));
}

String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class EquipmentItem {
  const EquipmentItem({
    required this.id,
    required this.kind,
    required this.name,
    this.location,
    this.serialNo,
    this.note,
    this.isActive = true,
    this.nextDue,
    this.overdue = false,
  });

  factory EquipmentItem.fromJson(Map<String, dynamic> j) => EquipmentItem(
    id: _i(j['id']),
    kind: '${j['kind'] ?? ''}',
    name: '${j['name'] ?? ''}',
    location: _s(j['location']),
    serialNo: _s(j['serial_no']),
    note: _s(j['note']),
    isActive: j['is_active'] != false,
    nextDue: _s(j['next_due']),
    overdue: j['overdue'] == true,
  );

  final int id;
  final String kind;
  final String name;
  final String? location;
  final String? serialNo;
  final String? note;
  final bool isActive;
  final String? nextDue;
  final bool overdue;
}

class MaintenancePlan {
  const MaintenancePlan({
    required this.id,
    required this.title,
    required this.intervalMonths,
    required this.legal,
    required this.nextDue,
    this.lastDone,
    this.isActive = true,
    this.daysLeft,
    this.equipmentName,
    this.state,
  });

  factory MaintenancePlan.fromJson(Map<String, dynamic> j) => MaintenancePlan(
    id: _i(j['id']),
    title: '${j['title'] ?? ''}',
    intervalMonths: _i(j['interval_months']),
    legal: j['legal'] == true,
    nextDue: '${j['next_due'] ?? ''}',
    lastDone: _s(j['last_done']),
    isActive: j['is_active'] != false,
    daysLeft: (j['days_left'] as num?)?.toInt(),
    equipmentName: _s(j['equipment_name']),
    state: _s(j['state']),
  );

  final int id;
  final String title;
  final int intervalMonths;
  final bool legal;
  final String nextDue;
  final String? lastDone;
  final bool isActive;
  final int? daysLeft;
  final String? equipmentName;
  final String? state;
}

class MaintenanceLog {
  const MaintenanceLog({required this.id, required this.doneOn, this.vendorName, this.costKurus, this.note, this.planId});

  factory MaintenanceLog.fromJson(Map<String, dynamic> j) => MaintenanceLog(
    id: _i(j['id']),
    doneOn: '${j['done_on'] ?? ''}',
    vendorName: _s(j['vendor_name']),
    costKurus: (j['cost_kurus'] as num?)?.toInt(),
    note: _s(j['note']),
    planId: (j['plan_id'] as num?)?.toInt(),
  );

  final int id;
  final String doneOn;
  final String? vendorName;
  final int? costKurus;
  final String? note;
  final int? planId;
}

class EquipmentDetail {
  const EquipmentDetail({required this.item, required this.plans, required this.logs, required this.expenseIds});

  final EquipmentItem item;
  final List<MaintenancePlan> plans;
  final List<MaintenanceLog> logs;
  final List<int> expenseIds;
}

/// Ekipmana bağlı bir iş kaydı (servis geçmişi satırı; `GET .../equipment/:id/work-history`). Talebi açanın bilgisi
/// sunucudan hiç gelmez; fotoğraflar yalnız SAYI olarak gelir (önce / sonra / toplam, hazır olanlar).
class EquipmentWorkItem {
  const EquipmentWorkItem({
    required this.id,
    this.title = '',
    this.category = WorkCategory.diger,
    this.status = WorkStatus.unknown,
    this.createdAt,
    this.resolvedAt,
    this.closedAt,
    this.attachmentCount = 0,
    this.beforeCount = 0,
    this.afterCount = 0,
  });

  factory EquipmentWorkItem.fromJson(Map<String, dynamic> j) => EquipmentWorkItem(
    id: _i(j['id']),
    title: '${j['title'] ?? ''}'.trim(),
    category: WorkCategory.fromApi(j['category']),
    status: WorkStatus.fromApi(j['status']),
    createdAt: documentInstant(j['created_at']),
    resolvedAt: documentInstant(j['resolved_at']),
    closedAt: documentInstant(j['closed_at']),
    attachmentCount: _i(j['attachment_count']),
    beforeCount: _i(j['before_count']),
    afterCount: _i(j['after_count']),
  );

  final int id;
  final String title;
  final WorkCategory category;
  final WorkStatus status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final int attachmentCount;
  final int beforeCount;
  final int afterCount;

  /// "Önce 1 · Sonra 2 · 3 fotoğraf" gibi fotoğraf özeti; fotoğraf yoksa null.
  String? get photoSummary {
    if (attachmentCount <= 0) return null;
    final parts = <String>[
      if (beforeCount > 0) 'Önce $beforeCount',
      if (afterCount > 0) 'Sonra $afterCount',
      '$attachmentCount fotoğraf',
    ];
    return parts.join(' · ');
  }
}

/// Ekipmanın servis geçmişi sayfası. [workTrackingEnabled] false: İş Takibi modülü kapalı (liste boş, ekipman kartı yine açılır).
class EquipmentWorkHistory {
  const EquipmentWorkHistory({
    this.workTrackingEnabled = true,
    this.items = const <EquipmentWorkItem>[],
    this.nextBeforeId,
    this.total = 0,
    this.open = 0,
  });

  factory EquipmentWorkHistory.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'];
    return EquipmentWorkHistory(
      workTrackingEnabled: j['work_tracking_enabled'] != false,
      items: <EquipmentWorkItem>[
        for (final r in (j['items'] as List? ?? const [])) if (r is Map) EquipmentWorkItem.fromJson(Map<String, dynamic>.from(r)),
      ].where((item) => item.id > 0).toList(growable: false),
      nextBeforeId: (j['next_before_id'] as num?)?.toInt(),
      total: counts is Map ? _i(counts['total']) : 0,
      open: counts is Map ? _i(counts['open']) : 0,
    );
  }

  final bool workTrackingEnabled;
  final List<EquipmentWorkItem> items;

  /// Sonraki sayfanın imleci (`before_id`); son sayfada null.
  final int? nextBeforeId;

  /// Bu ekipmana bağlı toplam / açık (çözülmemiş) iş sayısı (kapsam içi).
  final int total;
  final int open;

  /// Sonraki sayfayı sona ekler (aynı kimlik iki kez girmez); sayaçlar ve imleç yeni sayfadandır.
  EquipmentWorkHistory append(EquipmentWorkHistory next) {
    final known = items.map((e) => e.id).toSet();
    return EquipmentWorkHistory(
      workTrackingEnabled: next.workTrackingEnabled,
      items: <EquipmentWorkItem>[...items, ...next.items.where((e) => !known.contains(e.id))],
      nextBeforeId: next.nextBeforeId,
      total: next.total,
      open: next.open,
    );
  }
}

/// Bir teklif zincirindeki ONAYLI sürümün özeti (liste yanıtında, en son sürüm onaylı değilse).
class QuoteVersionRef {
  const QuoteVersionRef({required this.id, required this.revisionNo, required this.amountKurus, this.decidedAt, this.acceptedAs, this.expenseId, this.contractId});

  factory QuoteVersionRef.fromJson(Map<String, dynamic> j) => QuoteVersionRef(
    id: _i(j['id']),
    revisionNo: _i(j['revision_no']) == 0 ? 1 : _i(j['revision_no']),
    amountKurus: _i(j['amount_kurus']),
    decidedAt: _s(j['decided_at']),
    acceptedAs: _s(j['accepted_as']),
    expenseId: (j['expense_id'] as num?)?.toInt(),
    contractId: (j['contract_id'] as num?)?.toInt(),
  );

  final int id;
  final int revisionNo;
  final int amountKurus;
  final String? decidedAt;
  final String? acceptedAs;
  final int? expenseId;
  final int? contractId;

  /// Bu sürüm gider ya da sözleşmeye dönüşmüş mü (yeni sürümün kabulünde çift kayıt uyarısı için).
  bool get hasRecord => expenseId != null || contractId != null;

  /// "gider" / "sözleşme" (kayıt yoksa null).
  String? get recordLabel => expenseId != null ? 'gider' : (contractId != null ? 'sözleşme' : null);
}

class EquipmentQuote {
  const EquipmentQuote({
    required this.id,
    required this.topic,
    required this.vendorName,
    required this.amountKurus,
    required this.status,
    this.validUntil,
    this.expired = false,
    this.documentNote,
    this.acceptedAs,
    this.lowest = false,
    this.equipmentId,
    this.deliveryDays,
    this.note,
    this.vatIncluded,
    this.fastest = false,
    this.basisMixed = false,
    this.revisionNo = 1,
    this.previousId,
    this.revisionReason,
    this.versionCount = 1,
    this.approvedVersion,
    this.editable = false,
    this.revisable = false,
    this.expenseId,
    this.contractId,
    this.decidedAt,
  });

  factory EquipmentQuote.fromJson(Map<String, dynamic> j) {
    final status = '${j['status'] ?? 'open'}';
    final approved = j['approved_version'];
    final revisionNo = _i(j['revision_no']) == 0 ? 1 : _i(j['revision_no']);
    return EquipmentQuote(
      id: _i(j['id']),
      topic: '${j['topic'] ?? ''}',
      vendorName: '${j['vendor_name'] ?? ''}',
      amountKurus: _i(j['amount_kurus']),
      status: status,
      validUntil: _s(j['valid_until']),
      expired: j['expired'] == true,
      documentNote: _s(j['document_note']),
      acceptedAs: _s(j['accepted_as']),
      lowest: j['lowest'] == true,
      equipmentId: (j['equipment_id'] as num?)?.toInt(),
      deliveryDays: (j['delivery_days'] as num?)?.toInt(),
      note: _s(j['note']),
      vatIncluded: j['vat_included'] is bool ? j['vat_included'] as bool : null,
      fastest: j['fastest'] == true,
      basisMixed: j['basis_mixed'] == true,
      revisionNo: revisionNo,
      previousId: (j['previous_id'] as num?)?.toInt(),
      revisionReason: _s(j['revision_reason']),
      versionCount: _i(j['version_count']) == 0 ? revisionNo : _i(j['version_count']),
      approvedVersion: approved is Map ? QuoteVersionRef.fromJson(Map<String, dynamic>.from(approved)) : null,
      // Eski sunucu bu bayrakları göndermez: açık teklif yine düzenlenebilir, revizyon yok.
      editable: j['editable'] is bool ? j['editable'] as bool : status == 'open',
      revisable: j['revisable'] == true,
      expenseId: (j['expense_id'] as num?)?.toInt(),
      contractId: (j['contract_id'] as num?)?.toInt(),
      decidedAt: _s(j['decided_at']),
    );
  }

  final int id;
  final String topic;
  final String vendorName;
  final int amountKurus;
  final String status;
  final String? validUntil;
  final bool expired;
  final String? documentNote;
  final String? acceptedAs;
  final bool lowest;
  final int? equipmentId;

  /// Teslim süresi (gün); girilmediyse null.
  final int? deliveryDays;

  /// Kapsam / not (en çok 500 karakter).
  final String? note;

  /// KDV esası: true dahil, false hariç, null belirtilmedi.
  final bool? vatIncluded;

  /// Aynı konuda en kısa teslim süresi (en az iki tekliften süre girilmişse).
  final bool fastest;

  /// Aynı konudaki teklifler farklı KDV esasında: tutarlar kıyaslanamaz, "en düşük" işaretlenmez.
  final bool basisMixed;

  /// Sürüm numarası (1 = ilk sürüm) ve önceki sürüme bağ (K14 revizyon modeli).
  final int revisionNo;
  final int? previousId;
  final String? revisionReason;
  final int versionCount;

  /// Son sürüm onaylı değilse zincirdeki en yakın onaylı sürüm.
  final QuoteVersionRef? approvedVersion;

  /// Açık teklif yerinde düzenlenir; onaylı teklif için [revisable] ile yeni sürüm açılır.
  final bool editable;
  final bool revisable;
  final int? expenseId;
  final int? contractId;
  final String? decidedAt;

  bool get isRevision => revisionNo > 1;

  bool get hasHistory => revisionNo > 1;

  /// "KDV dahil" / "KDV hariç" / "KDV belirtilmedi".
  String get vatLabel => vatIncluded == null ? 'KDV belirtilmedi' : (vatIncluded! ? 'KDV dahil' : 'KDV hariç');

  /// "14 gün" (girilmediyse null).
  String? get deliveryLabel => deliveryDays == null ? null : '$deliveryDays gün';
}

/// Bir teklifin tüm sürümleri (eskiden yeniye) ve en son / onaylı sürümün kimliği.
class QuoteHistory {
  const QuoteHistory({required this.items, required this.latestId, this.approvedId});

  factory QuoteHistory.fromJson(Map<String, dynamic> j) => QuoteHistory(
    items: <EquipmentQuote>[
      for (final r in (j['items'] as List? ?? const [])) if (r is Map) EquipmentQuote.fromJson(Map<String, dynamic>.from(r)),
    ],
    latestId: _i(j['latest_id']),
    approvedId: (j['approved_id'] as num?)?.toInt(),
  );

  final List<EquipmentQuote> items;
  final int latestId;
  final int? approvedId;
}

/// Açılır listede seçilecek { id, ad } (kategori, hesap, firma).
class PickOption {
  const PickOption(this.id, this.name);

  factory PickOption.fromJson(Map<String, dynamic> j) => PickOption(_i(j['id']), '${j['name'] ?? ''}');

  final int id;
  final String name;
}

class BreakdownRow {
  const BreakdownRow({required this.equipmentId, required this.name, required this.kind, required this.expenseMinor});

  final int equipmentId;
  final String name;
  final String kind;
  final int expenseMinor;
}

class EquipmentBreakdown {
  const EquipmentBreakdown({required this.from, required this.to, required this.items, required this.linkedMinor, required this.unlinkedMinor, required this.totalMinor});

  factory EquipmentBreakdown.fromJson(Map<String, dynamic> j) => EquipmentBreakdown(
    from: '${j['from'] ?? ''}',
    to: '${j['to'] ?? ''}',
    items: <BreakdownRow>[
      for (final r in (j['items'] as List? ?? const []))
        if (r is Map) BreakdownRow(equipmentId: _i(r['equipment_id']), name: '${r['name']}', kind: '${r['kind']}', expenseMinor: _i(r['expense_minor'])),
    ],
    linkedMinor: _i(j['linked_minor']),
    unlinkedMinor: _i(j['unlinked_minor']),
    totalMinor: _i(j['total_minor']),
  );

  final String from;
  final String to;
  final List<BreakdownRow> items;
  final int linkedMinor;
  final int unlinkedMinor;
  final int totalMinor;
}

class EquipmentApi {
  EquipmentApi({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _p(int site, String tail) => '/manager/sites/$site/$tail';

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) => <T>[
    for (final r in (raw as List? ?? const [])) if (r is Map) f(Map<String, dynamic>.from(r)),
  ];

  Future<List<EquipmentItem>> list(String token, int site) async =>
      _list((await _send('GET', _p(site, 'equipment'), token, query: const {'active': 'all'}))['items'], EquipmentItem.fromJson);

  Future<EquipmentDetail> detail(String token, int site, int id) async => _detail(await _send('GET', _p(site, 'equipment/$id'), token));

  EquipmentDetail _detail(Map<String, dynamic> j) => EquipmentDetail(
    item: EquipmentItem.fromJson(Map<String, dynamic>.from(j['equipment'] as Map)),
    plans: _list(j['plans'], MaintenancePlan.fromJson),
    logs: _list(j['logs'], MaintenanceLog.fromJson),
    expenseIds: <int>[for (final e in (j['expense_ids'] as List? ?? const [])) _i(e)],
  );

  /// Servis geçmişi: ekipmana bağlı iş kayıtları (`before_id` imleciyle sayfalı). İş Takibi modülü kapalıysa boş liste gelir.
  Future<EquipmentWorkHistory> workHistory(String token, int site, int id, {int? beforeId, int limit = 20}) async =>
      EquipmentWorkHistory.fromJson(
        await _send('GET', _p(site, 'equipment/$id/work-history'), token, query: <String, String>{'limit': '$limit', if (beforeId != null) 'before_id': '$beforeId'}),
      );

  Future<void> create(String token, int site, Map<String, Object?> body) async => _send('POST', _p(site, 'equipment'), token, body: body, ok: const {201});

  Future<void> update(String token, int site, int id, Map<String, Object?> body) async => _send('PATCH', _p(site, 'equipment/$id'), token, body: body);

  Future<void> addPlan(String token, int site, int id, Map<String, Object?> body) async => _send('POST', _p(site, 'equipment/$id/plans'), token, body: body, ok: const {201});

  Future<void> updatePlan(String token, int site, int planId, Map<String, Object?> body) async => _send('PATCH', _p(site, 'equipment/plans/$planId'), token, body: body);

  Future<EquipmentDetail> addLog(String token, int site, int id, Map<String, Object?> body) async =>
      _detail(await _send('POST', _p(site, 'equipment/$id/logs'), token, body: body, ok: const {201}));

  Future<EquipmentDetail> linkExpense(String token, int site, int id, int expenseId) async =>
      _detail(await _send('POST', _p(site, 'equipment/$id/expense-links'), token, body: <String, Object?>{'expense_id': expenseId}));

  Future<List<MaintenancePlan>> due(String token, int site, {int days = 60}) async =>
      _list((await _send('GET', _p(site, 'equipment/due'), token, query: {'days': '$days'}))['items'], MaintenancePlan.fromJson);

  Future<EquipmentBreakdown> breakdown(String token, int site) async =>
      EquipmentBreakdown.fromJson(await _send('GET', _p(site, 'equipment/expense-breakdown'), token));

  Future<List<EquipmentQuote>> quotes(String token, int site) async =>
      _list((await _send('GET', _p(site, 'quotes'), token))['items'], EquipmentQuote.fromJson);

  /// Gidere dönüştürmek için kategori ve hesap seçenekleri (finans uçları; yalnız `finance` modülü açıksa çağrılır).
  Future<(List<PickOption>, List<PickOption>)> financeChoices(String token, int site) async {
    final cats = await _send('GET', _p(site, 'finance/expense-categories'), token, query: const {'active': '1'});
    final accs = await _send('GET', _p(site, 'finance/accounts'), token);
    return (_list(cats['items'], PickOption.fromJson), _list(accs['items'], PickOption.fromJson));
  }

  /// Sözleşmeye dönüştürmek için firma seçenekleri (`contracts` modülü).
  Future<List<PickOption>> vendors(String token, int site) async =>
      _list((await _send('GET', _p(site, 'contract-vendors'), token, query: const {'active': '1'}))['items'], PickOption.fromJson);

  Future<void> createQuote(String token, int site, Map<String, Object?> body) async => _send('POST', _p(site, 'quotes'), token, body: body, ok: const {201});

  Future<void> rejectQuote(String token, int site, int id) async => _send('POST', _p(site, 'quotes/$id/reject'), token, body: const <String, Object?>{});

  Future<void> acceptQuote(String token, int site, int id, Map<String, Object?> body) async => _send('POST', _p(site, 'quotes/$id/accept'), token, body: body);

  /// Açık teklifi yerinde düzenler (onaylı teklif 409 QUOTE_LOCKED: revizyon kullanın).
  Future<void> updateQuote(String token, int site, int id, Map<String, Object?> body) async => _send('PATCH', _p(site, 'quotes/$id'), token, body: body);

  /// Onaylı teklifte değişiklik = yeni sürüm (K14): `reason` zorunlu, önceki sürüm değişmez.
  Future<void> reviseQuote(String token, int site, int id, Map<String, Object?> body) async =>
      _send('POST', _p(site, 'quotes/$id/revise'), token, body: body, ok: const {201});

  /// Teklifin tüm sürümleri (eskiden yeniye).
  Future<QuoteHistory> quoteHistory(String token, int site, int id) async => QuoteHistory.fromJson(await _send('GET', _p(site, 'quotes/$id/history'), token));

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String token, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    Set<int> ok = const <int>{200},
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
    } on Exception {
      throw ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    }
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      final raw = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (raw is Map) payload = Map<String, dynamic>.from(raw);
    } on FormatException {
      // Gövde JSON değil.
    }
    if (ok.contains(response.statusCode)) return payload;
    final code = payload['code'] is String ? payload['code'] as String : null;
    if (response.statusCode == 401) throw SessionExpiredException('Oturum süreniz doldu. Lütfen tekrar giriş yapın.', code);
    throw ApiException(_message(code, payload['error'], response.statusCode), statusCode: response.statusCode, code: code, payload: payload);
  }

  static String _message(String? code, Object? serverText, int status) {
    switch (code) {
      case 'MODULE_DISABLED':
        return 'Bu modül bu site için kapalı.';
      case 'FORBIDDEN_ROLE':
        return 'Bu işlem için yetkiniz yok.';
      case 'FORBIDDEN_SITE':
        return 'Bu siteye erişim yetkiniz yok.';
      case 'QUOTE_EXPIRED':
        return 'Teklifin geçerlilik süresi dolmuş.';
      case 'QUOTE_NOT_OPEN':
        return 'Teklif zaten karara bağlanmış.';
      case 'QUOTE_LOCKED':
        return 'Karara bağlanmış teklif düzenlenemez. Onaylı teklifte değişiklik için revizyon oluşturun.';
      case 'QUOTE_NOT_LATEST':
        return 'Bu teklifin daha yeni bir sürümü var. Listeyi yenileyip en son sürümle devam edin.';
      case 'QUOTE_NOT_REVISABLE':
        return 'Bu teklif için revizyon açılamaz.';
      case 'NO_CHANGE':
        return 'Revizyon için en az bir alan değişmeli.';
    }
    if (serverText is String && serverText.trim().isNotEmpty && (status == 400 || status == 409)) {
      return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    }
    final mapped = code == null ? null : AuthApi.messageForErrorCode(code);
    if (mapped != null) return mapped;
    if (serverText is String && serverText.trim().isNotEmpty) return AuthApi.sanitizeServerMessage(serverText.trim()) ?? 'İşlem başarısız ($status)';
    return 'İşlem başarısız ($status)';
  }
}

/// Oturum belirtecini [AuthService]'ten alan katman.
class EquipmentService {
  EquipmentService({required this.authService, EquipmentApi? api}) : api = api ?? EquipmentApi(baseUrl: authService.api.baseUrl);

  final AuthService authService;
  final EquipmentApi api;

  Future<T> _guard<T>(Future<T> Function(String token) call) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }

  Future<List<EquipmentItem>> list(int site) => _guard((t) => api.list(t, site));
  Future<EquipmentDetail> detail(int site, int id) => _guard((t) => api.detail(t, site, id));
  Future<EquipmentWorkHistory> workHistory(int site, int id, {int? beforeId}) => _guard((t) => api.workHistory(t, site, id, beforeId: beforeId));
  Future<void> create(int site, Map<String, Object?> body) => _guard((t) => api.create(t, site, body));
  Future<void> update(int site, int id, Map<String, Object?> body) => _guard((t) => api.update(t, site, id, body));
  Future<void> addPlan(int site, int id, Map<String, Object?> body) => _guard((t) => api.addPlan(t, site, id, body));
  Future<void> updatePlan(int site, int planId, Map<String, Object?> body) => _guard((t) => api.updatePlan(t, site, planId, body));
  Future<EquipmentDetail> addLog(int site, int id, Map<String, Object?> body) => _guard((t) => api.addLog(t, site, id, body));
  Future<EquipmentDetail> linkExpense(int site, int id, int expenseId) => _guard((t) => api.linkExpense(t, site, id, expenseId));
  Future<List<MaintenancePlan>> due(int site) => _guard((t) => api.due(t, site));
  Future<EquipmentBreakdown> breakdown(int site) => _guard((t) => api.breakdown(t, site));
  Future<List<EquipmentQuote>> quotes(int site) => _guard((t) => api.quotes(t, site));
  Future<(List<PickOption>, List<PickOption>)> financeChoices(int site) => _guard((t) => api.financeChoices(t, site));
  Future<List<PickOption>> vendors(int site) => _guard((t) => api.vendors(t, site));
  Future<void> createQuote(int site, Map<String, Object?> body) => _guard((t) => api.createQuote(t, site, body));
  Future<void> rejectQuote(int site, int id) => _guard((t) => api.rejectQuote(t, site, id));
  Future<void> acceptQuote(int site, int id, Map<String, Object?> body) => _guard((t) => api.acceptQuote(t, site, id, body));
  Future<void> updateQuote(int site, int id, Map<String, Object?> body) => _guard((t) => api.updateQuote(t, site, id, body));
  Future<void> reviseQuote(int site, int id, Map<String, Object?> body) => _guard((t) => api.reviseQuote(t, site, id, body));
  Future<QuoteHistory> quoteHistory(int site, int id) => _guard((t) => api.quoteHistory(t, site, id));
}
