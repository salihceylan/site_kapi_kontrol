// Ekipman, bakım ve teklif uçları (`equipment` modülü). Sözleşme: docs/PLATFORM_EKIPMAN.md.
//
// Para tamsayı kuruştur. Bakım kaydı yalnız eklenir. Hatırlatma bildirimi (telefon/e-posta) "Yakında…": yaklaşan ve geciken
// bakımlar bu ekranda listelenir. Teklife belge yükleme "Yakında…": şimdilik belge notu yazılır.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
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
  });

  factory EquipmentQuote.fromJson(Map<String, dynamic> j) => EquipmentQuote(
    id: _i(j['id']),
    topic: '${j['topic'] ?? ''}',
    vendorName: '${j['vendor_name'] ?? ''}',
    amountKurus: _i(j['amount_kurus']),
    status: '${j['status'] ?? 'open'}',
    validUntil: _s(j['valid_until']),
    expired: j['expired'] == true,
    documentNote: _s(j['document_note']),
    acceptedAs: _s(j['accepted_as']),
    lowest: j['lowest'] == true,
    equipmentId: (j['equipment_id'] as num?)?.toInt(),
  );

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
}
