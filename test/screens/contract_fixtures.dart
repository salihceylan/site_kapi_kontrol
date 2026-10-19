// Firma ve Sözleşme Takibi (`contracts`): ekran / pencere testlerinin ortak örnek verisi ve sahte servisi.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// Sahte servis SUNUCUYU taklit eder (server/src/modules/contracts_common.js): satırlar bellekte sunucunun gerçek JSON
// biçiminde tutulur ve modellerle ayrıştırılır; sözleşme listesi state / firma / kategori / arama süzgeci uygular,
// `end_date ARTAN (bitişsizler sonda), id` sırasıyla ve YALNIZ opak `next_cursor` imleciyle sayfalar (`before_id` yok);
// özet ayrık state sayılarıdır; kurul ve görevlide yazma 403 FORBIDDEN_ROLE; aynı adlı firma 409 VENDOR_NAME_TAKEN;
// pasif firmaya sözleşme 409 VENDOR_INACTIVE. "Bugün" sabittir: 19.10.2026. Hata ve yarış testleri için her çağrı
// kuyruktaki bir hataya ya da kapıya takılabilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDate, crmDateParam;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';

import 'people_fixtures.dart';

/// Sahte kimlik doğrulama (servise `authService` olarak verilir).
class ContractFakeAuth extends PeopleFakeAuth {
  ContractFakeAuth({super.role});
}

/// Sabit "bugün" (İstanbul takvim günü).
final DateTime kContractToday = DateTime(2026, 10, 19);

int _days(String? end) {
  final date = crmDate(end);
  if (date == null) return 0;
  return DateTime.utc(date.year, date.month, date.day)
      .difference(DateTime.utc(kContractToday.year, kContractToday.month, kContractToday.day))
      .inDays;
}

/// Sunucu kuralı: feshedildi > sona_erdi > yaklasiyor > aktif.
String ctState(String status, String? end, int remind) {
  if (status == 'feshedildi') return 'feshedildi';
  if (end == null) return 'aktif';
  final left = _days(end);
  if (left < 0) return 'sona_erdi';
  if (left <= remind) return 'yaklasiyor';
  return 'aktif';
}

/// Sunucu `Vendor` gövdesi.
Map<String, dynamic> ctVendor(
  int id, {
  String name = 'Yıldız Asansör Bakım Ltd. Şti.',
  String category = 'asansor',
  String? contact,
  String? phone,
  String? email,
  String? taxNo,
  String? note,
  bool active = true,
  int count = 0,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'category': category,
  'contact_name': contact,
  'phone': phone,
  'email': email,
  'tax_no': taxNo,
  'note': note,
  'is_active': active,
  'contract_count': count,
  'created_at': '2026-09-01T08:00:00.000Z',
  'updated_at': '2026-09-02T08:00:00.000Z',
};

/// Sunucu `Contract` gövdesi (state / days_left / notice_deadline sunucu kuralıyla hesaplanır).
Map<String, dynamic> ctContract(
  int id, {
  int vendorId = 1,
  String vendorName = 'Yıldız Asansör Bakım Ltd. Şti.',
  String title = 'Asansör yıllık bakım sözleşmesi',
  String category = 'asansor',
  String start = '2026-01-01',
  String? end = '2026-12-31',
  int notice = 30,
  int remind = 30,
  String? amount = '1250.00',
  String? period = 'aylik',
  bool autoRenew = false,
  String status = 'aktif',
  String? note,
  String? terminatedAt,
}) {
  final state = ctState(status, end, remind);
  final endDate = crmDate(end);
  return <String, dynamic>{
    'id': id,
    'vendor_id': vendorId,
    'vendor_name': vendorName,
    'title': title,
    'category': category,
    'start_date': start,
    'end_date': end,
    'notice_days': notice,
    'remind_before_days': remind,
    'amount': amount,
    'currency': 'TRY',
    'period': period,
    'auto_renew': autoRenew,
    'status': status,
    'state': state,
    'days_left': end == null ? null : _days(end),
    'notice_deadline': autoRenew && endDate != null
        ? crmDateParam(endDate.subtract(Duration(days: notice)))
        : null,
    'terminated_at': status == 'feshedildi' ? (terminatedAt ?? '2026-10-10T09:30:00.000Z') : null,
    'note': note,
    'created_by_name': 'Site Yöneticisi',
    'created_at': '2026-09-05T08:00:00.000Z',
    'updated_at': '2026-09-06T08:00:00.000Z',
  };
}

/// Sahte servis (sunucu kuralları; çağrı kayıtları; hata / kapı kuyrukları).
class FakeContractService extends ContractService {
  FakeContractService({
    required super.authService,
    this.kind = ContractSiteAccess.manager,
  }) : super(api: ContractApi(baseUrl: 'http://localhost'));

  /// Sitedeki rol: manager (yazar) | board | staff (salt okur).
  ContractSiteAccess kind;

  final List<Map<String, dynamic>> vendors = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> contracts = <Map<String, dynamic>>[];

  // --- Çağrı kayıtları ---
  final List<({int site, ContractVendorFilter active, String? query})> listVendorsCalls = [];
  final List<({int site, String state, int? vendorId, String? category, String? query, String? cursor, int limit})>
  listContractsCalls = [];
  final List<int> summaryCalls = <int>[];
  final List<({int site, ContractVendorDraft draft})> createVendorCalls = [];
  final List<({int site, int id, Map<String, dynamic> body})> updateVendorCalls = [];
  final List<({int site, ContractDraft draft})> createContractCalls = [];
  final List<({int site, int id, Map<String, dynamic> body})> updateContractCalls = [];

  // --- Sürücüler ---
  final Map<String, List<Object>> failures = <String, List<Object>>{};
  final Map<String, List<Completer<void>>> gates = <String, List<Completer<void>>>{};

  Future<void> _enter(String op) async {
    final gate = gates[op];
    if (gate != null && gate.isNotEmpty) await gate.removeAt(0).future;
    final failure = failures[op];
    if (failure != null && failure.isNotEmpty) throw failure.removeAt(0);
  }

  static ApiException forbidden() =>
      ApiException('Bu işlem için yetkiniz yok.', statusCode: 403, code: 'FORBIDDEN_ROLE');

  static ApiException moduleOff() => ApiException(
    'Firma ve sözleşme takibi bu site için kapalı.',
    statusCode: 403,
    code: 'MODULE_DISABLED',
  );

  static ApiException nameTaken() => ApiException(
    'Bu adla kayıtlı bir firma zaten var. Farklı bir ad girin ya da mevcut firmayı kullanın.',
    statusCode: 409,
    code: 'VENDOR_NAME_TAKEN',
  );

  void _requireWrite() {
    if (kind != ContractSiteAccess.manager) throw forbidden();
  }

  Map<String, dynamic>? _vendor(int id) {
    for (final row in vendors) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  Map<String, dynamic>? _contract(int id) {
    for (final row in contracts) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  int _nextId(List<Map<String, dynamic>> rows, int floor) {
    var max = floor;
    for (final row in rows) {
      if ((row['id'] as int) > max) max = row['id'] as int;
    }
    return max + 1;
  }

  void _recount() {
    for (final vendor in vendors) {
      vendor['contract_count'] = contracts.where((c) => c['vendor_id'] == vendor['id']).length;
    }
  }

  void _recompute(Map<String, dynamic> row) {
    final fresh = ctContract(
      row['id'] as int,
      vendorId: row['vendor_id'] as int,
      vendorName: row['vendor_name'] as String,
      title: row['title'] as String,
      category: row['category'] as String,
      start: row['start_date'] as String,
      end: row['end_date'] as String?,
      notice: row['notice_days'] as int,
      remind: row['remind_before_days'] as int,
      amount: row['amount'] as String?,
      period: row['period'] as String?,
      autoRenew: row['auto_renew'] as bool,
      status: row['status'] as String,
      note: row['note'] as String?,
      terminatedAt: row['terminated_at'] as String?,
    );
    row
      ..['state'] = fresh['state']
      ..['days_left'] = fresh['days_left']
      ..['notice_deadline'] = fresh['notice_deadline']
      ..['terminated_at'] = fresh['terminated_at'];
  }

  // --- Firmalar ---

  @override
  Future<List<ContractVendor>> listVendors(
    int siteCode, {
    ContractVendorFilter active = ContractVendorFilter.all,
    String? query,
  }) async {
    listVendorsCalls.add((site: siteCode, active: active, query: query));
    await _enter('listVendors');
    final q = (query ?? '').trim().toLowerCase();
    final rows = vendors.where((v) {
      if (active == ContractVendorFilter.active && v['is_active'] != true) return false;
      if (active == ContractVendorFilter.passive && v['is_active'] == true) return false;
      if (q.isNotEmpty && !'${v['name']} ${v['contact_name'] ?? ''}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return ContractVendor.listFrom(<String, dynamic>{'items': rows});
  }

  @override
  Future<ContractVendor> createVendor(int siteCode, ContractVendorDraft draft) async {
    createVendorCalls.add((site: siteCode, draft: draft));
    await _enter('createVendor');
    _requireWrite();
    final body = draft.toCreateJson();
    final name = (body['name'] as String).toLowerCase();
    if (vendors.any((v) => '${v['name']}'.toLowerCase() == name)) throw nameTaken();
    final row = ctVendor(
      _nextId(vendors, 0),
      name: body['name'] as String,
      category: body['category'] as String,
      contact: body['contact_name'] as String?,
      phone: body['phone'] as String?,
      email: body['email'] as String?,
      taxNo: body['tax_no'] as String?,
      note: body['note'] as String?,
    );
    vendors.add(row);
    return ContractVendor.fromJson(<String, dynamic>{'vendor': row});
  }

  @override
  Future<ContractVendor> updateVendor(int siteCode, int id, Map<String, dynamic> body) async {
    updateVendorCalls.add((site: siteCode, id: id, body: body));
    await _enter('updateVendor');
    _requireWrite();
    final row = _vendor(id);
    if (row == null) {
      throw ApiException('Firma bulunamadı.', statusCode: 404, code: 'VENDOR_NOT_FOUND');
    }
    row.addAll(body);
    return ContractVendor.fromJson(<String, dynamic>{'vendor': row});
  }

  // --- Sözleşmeler ---

  @override
  Future<ContractPage> listContracts(
    int siteCode, {
    String state = 'all',
    int? vendorId,
    String? category,
    String? query,
    String? cursor,
    int limit = 30,
  }) async {
    listContractsCalls.add(
      (site: siteCode, state: state, vendorId: vendorId, category: category, query: query, cursor: cursor, limit: limit),
    );
    await _enter('listContracts');
    final q = (query ?? '').trim().toLowerCase();
    final rows = contracts.where((c) {
      if (state != 'all' && c['state'] != state) return false;
      if (vendorId != null && c['vendor_id'] != vendorId) return false;
      if (category != null && c['category'] != category) return false;
      if (q.isNotEmpty && !'${c['title']} ${c['vendor_name']}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final ea = a['end_date'] as String?;
        final eb = b['end_date'] as String?;
        if (ea != eb) {
          if (ea == null) return 1;
          if (eb == null) return -1;
          return ea.compareTo(eb);
        }
        return (a['id'] as int).compareTo(b['id'] as int);
      });
    // Opak imleç "c<başlangıç>|<state>|<arama>": hangi süzgeçle üretildiği testte görünür (yanlış süzgecin imleci
    // gönderilirse sunucuda satırlar sessizce kaybolurdu).
    final start = cursor == null ? 0 : int.parse(cursor.substring(1).split('|').first);
    final page = rows.skip(start).take(limit).toList();
    final more = rows.length > start + limit;
    return ContractPage.fromJson(<String, dynamic>{
      'items': page,
      'next_cursor': more ? 'c${start + limit}|$state|$q' : null,
    });
  }

  @override
  Future<ContractSummary> summary(int siteCode) async {
    summaryCalls.add(siteCode);
    await _enter('summary');
    int count(String state) => contracts.where((c) => c['state'] == state).length;
    return ContractSummary.fromJson(<String, dynamic>{
      'active': count('aktif'),
      'expiring_soon': count('yaklasiyor'),
      'expired': count('sona_erdi'),
      'terminated': count('feshedildi'),
    });
  }

  @override
  Future<Contract> getContract(int siteCode, int id) async {
    await _enter('getContract');
    final row = _contract(id);
    if (row == null) {
      throw ApiException('Sözleşme bulunamadı.', statusCode: 404, code: 'CONTRACT_NOT_FOUND');
    }
    return Contract.fromJson(<String, dynamic>{'contract': row});
  }

  @override
  Future<Contract> createContract(int siteCode, ContractDraft draft) async {
    createContractCalls.add((site: siteCode, draft: draft));
    await _enter('createContract');
    _requireWrite();
    final body = draft.toCreateJson();
    final vendor = _vendor(body['vendor_id'] as int);
    if (vendor == null) {
      throw ApiException('Firma bulunamadı.', statusCode: 404, code: 'VENDOR_NOT_FOUND');
    }
    if (vendor['is_active'] != true) {
      throw ApiException(
        'Seçilen firma pasif. Başka bir firma seçin ya da firmayı Firmalar sekmesinden etkinleştirin.',
        statusCode: 409,
        code: 'VENDOR_INACTIVE',
      );
    }
    final row = ctContract(
      _nextId(contracts, 100),
      vendorId: vendor['id'] as int,
      vendorName: vendor['name'] as String,
      title: body['title'] as String,
      category: body['category'] as String,
      start: body['start_date'] as String,
      end: body['end_date'] as String?,
      notice: body['notice_days'] as int,
      remind: body['remind_before_days'] as int,
      amount: body['amount'] as String?,
      period: body['period'] as String?,
      autoRenew: body['auto_renew'] as bool,
      note: body['note'] as String?,
    );
    contracts.add(row);
    _recount();
    return Contract.fromJson(<String, dynamic>{'contract': row});
  }

  @override
  Future<Contract> updateContract(int siteCode, int id, Map<String, dynamic> body) async {
    updateContractCalls.add((site: siteCode, id: id, body: body));
    await _enter('updateContract');
    _requireWrite();
    final row = _contract(id);
    if (row == null) {
      throw ApiException('Sözleşme bulunamadı.', statusCode: 404, code: 'CONTRACT_NOT_FOUND');
    }
    final next = Map<String, dynamic>.of(body);
    if (next['status'] == 'feshedildi') next['terminated_at'] = '2026-10-19T10:00:00.000Z';
    if (next['status'] == 'aktif') next['terminated_at'] = null;
    if (next.containsKey('vendor_id')) {
      final vendor = _vendor(next['vendor_id'] as int);
      if (vendor == null) {
        throw ApiException('Firma bulunamadı.', statusCode: 404, code: 'VENDOR_NOT_FOUND');
      }
      next['vendor_name'] = vendor['name'];
    }
    row.addAll(next);
    _recompute(row);
    _recount();
    return Contract.fromJson(<String, dynamic>{'contract': row});
  }
}

/// Üç firma (ikisi aktif, biri pasif) ve beş sözleşme: yürürlükte + otomatik yenilenen (fesih son günü 01.12.2026),
/// bitişi yaklaşan (17 gün), süresi dolmuş (19 gün önce), süresiz, feshedilmiş.
FakeContractService seededContracts(
  ContractFakeAuth auth, {
  ContractSiteAccess kind = ContractSiteAccess.manager,
}) {
  final service = FakeContractService(authService: auth, kind: kind);
  service.vendors.addAll(<Map<String, dynamic>>[
    ctVendor(
      1,
      contact: 'Murat Yıldız',
      phone: '0212 555 12 34',
      email: 'destek.cok.uzun.adres@yildizasansor-bakim.com.tr',
      taxNo: '1234567890',
      note: 'Arıza hattı 7/24 açık.',
    ),
    ctVendor(
      2,
      name: 'Kale Güvenlik Hizmetleri A.Ş.',
      category: 'guvenlik',
      contact: 'Ayşe Kale',
      phone: '+90 532 111 22 33',
    ),
    ctVendor(3, name: 'Parlak Temizlik', category: 'temizlik', active: false),
  ]);
  service.contracts.addAll(<Map<String, dynamic>>[
    ctContract(11, autoRenew: true, note: 'Aylık periyodik bakım ve yıllık muayene dahil.'),
    ctContract(
      12,
      vendorId: 2,
      vendorName: 'Kale Güvenlik Hizmetleri A.Ş.',
      title: 'Güvenlik görevlisi hizmet alımı',
      category: 'guvenlik',
      end: '2026-11-05',
      amount: '48000.50',
      period: 'yillik',
    ),
    ctContract(
      13,
      title: 'Asansör modernizasyon garantisi',
      start: '2024-09-30',
      end: '2026-09-30',
      amount: null,
      period: null,
    ),
    ctContract(
      14,
      vendorId: 3,
      vendorName: 'Parlak Temizlik',
      title: 'Ortak alan temizliği',
      category: 'temizlik',
      end: null,
      amount: '0.00',
      period: 'tek_sefer',
    ),
    ctContract(
      15,
      vendorId: 2,
      vendorName: 'Kale Güvenlik Hizmetleri A.Ş.',
      title: 'Kamera sistemi bakım sözleşmesi',
      category: 'guvenlik',
      end: '2027-03-01',
      status: 'feshedildi',
    ),
  ]);
  service._recount();
  return service;
}

/// Taşma matrisi: AGENTS.md kural 6 (320x640@2.0, 360x640@1.5, yatay 640x360@2.0, tablet 768x1024@1.0).
const List<(double, double, double)> kContractCells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 2.0),
  (768, 1024, 1.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalıdır.
void contractMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kContractCells) {
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
Finder ctKey(String key) => find.byKey(ValueKey<String>(key));
