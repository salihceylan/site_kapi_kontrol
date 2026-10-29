// Platform Faz 4b (Finans devamı): ekran / pencere testlerinin ortak örnek verisi ve sahte API'si.
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz.
//
// [FakeFinance4bApi] SUNUCUYU taklit eder (docs/PLATFORM_FINANS_4B.md): bellekte tutulan hesap / makbuz / gider /
// tazminat / hatırlatma verisi, sunucunun hata kodları (PREVIEW_STALE, ACCOUNT_REQUIRED, PERIOD_CLOSED,
// IDEMPOTENCY_CONFLICT ...) ve "yanıtı bekleten" kapılar (Completer). Her çağrı kaydedilir. Yanıtlar sunucunun
// gerçek JSON biçiminde üretilip modellerle ayrıştırılır.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:site_kapi_kontrol/models/bulk_import.dart' show ExportEnvelope;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/finance_charts.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/finance_liability.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';
import 'package:site_kapi_kontrol/services/finance_4b_errors.dart';

/// Sunucu hata kodu -> [ApiException] (Türkçe metin eşlemesiyle, 4b istemcisindeki gibi).
ApiException f4Coded(String code, int status, {Map<String, dynamic>? payload}) => ApiException(
  finance4bErrorMessage(code, payload: payload) ?? code,
  statusCode: status,
  code: code,
  payload: <String, dynamic>{'code': code, ...?payload},
);

/// Hazır ayar yanıtı (varsayılan: makbuz otomatik, tazminat + hatırlatma KAPALI).
Map<String, dynamic> f4SettingsJson({
  int version = 1,
  bool autoReceipt = true,
  bool lateFee = false,
  bool? legalOk,
  bool reminders = false,
  bool smtp = true,
  String? startPeriod,
  String? nextPeriod,
  int rateBp = 500,
  int? voidableRunId,
}) => <String, dynamic>{
  'settings_version': version,
  'legal_ok': ?legalOk,
  'receipts': <String, dynamic>{'auto_issue': autoReceipt},
  'late_fee': <String, dynamic>{
    'enabled': lateFee,
    'rate_bp': rateBp,
    'max_rate_bp': 500,
    'method': 'daily_30',
    'grace_days': 0,
    'start_period': startPeriod,
    'next_period': nextPeriod,
    'voidable_run_id': voidableRunId,
  },
  'reminders': <String, dynamic>{
    'enabled': reminders,
    'min_overdue_minor': 5000,
    'min_days_overdue': 5,
    'min_interval_days': 14,
    'max_consecutive': 3,
    'smtp_configured': smtp,
  },
};

/// Hazır makbuz (tam snapshot).
Map<String, dynamic> f4ReceiptJson(
  int id, {
  String? number,
  String kind = 'collection',
  String status = 'active',
  int amount = 123456,
  String apartment = 'A Blok - 5',
  String? payerName = 'Ayşe Yılmaz',
  int copyCount = 0,
  String? cancelsNumber,
  String? cancelledByNumber,
  String site = 'Gül Sitesi',
  int ledgerEntryId = 55,
}) {
  final no = number ?? 'MK-2026-${id.toString().padLeft(6, '0')}';
  return <String, dynamic>{
    'id': id,
    'status': kind == 'cancellation' ? null : status,
    'copy_count': copyCount,
    'ledger_entry_id': ledgerEntryId,
    'snapshot': <String, dynamic>{
      'number': no,
      'kind': kind,
      'amount_minor': amount,
      'currency': 'TRY',
      'issued_on': '2026-10-16',
      'paid_on': '2026-10-14',
      'method': 'cash',
      'site': <String, dynamic>{'name': site},
      'apartment': <String, dynamic>{'label': apartment},
      'payer': <String, dynamic>{'party': 'owner', 'name': payerName},
      'issuer': <String, dynamic>{'name': 'Site Yöneticisi'},
      'cancels_number': cancelsNumber,
      'cancelled_by_number': cancelledByNumber,
      'cancel_reason_code': kind == 'cancellation' ? 'issued_in_error' : null,
      'mahsup': 'oldest_due_first',
      'cekince': true,
      'template_version': 1,
      'verification_code': 'AB12CD34EF56',
    },
  };
}

Map<String, dynamic> f4ReceiptSummaryJson(Map<String, dynamic> full) {
  final snap = full['snapshot'] as Map<String, dynamic>;
  return <String, dynamic>{
    'id': full['id'],
    'number': snap['number'],
    'kind': snap['kind'],
    'status': full['status'],
    'paid_on': snap['paid_on'],
    'issued_on': snap['issued_on'],
    'amount_minor': snap['amount_minor'],
    'apartment': <String, dynamic>{'id': 301, 'label': (snap['apartment'] as Map)['label']},
    'payer_name': (snap['payer'] as Map)['name'],
  };
}

Map<String, dynamic> f4AccountJson(
  int id,
  String name, {
  String kind = 'cash',
  int balance = 100000,
  bool active = true,
  String? note,
  Map<String, dynamic>? lastReconciliation,
  int opening = 0,
  String openingDate = '2026-01-01',
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'kind': kind,
  'note': note,
  'opening_balance_minor': opening,
  'opening_date': openingDate,
  'balance_minor': balance,
  'is_active': active,
  'sort_order': id,
  'last_reconciliation': lastReconciliation,
};

/// Bir çağrının yanıtını bekletmek için kapı: `gate = Completer<void>()`; açmak için `gate.complete()`.
typedef F4Gate = Completer<void>;

/// 4b uçları için sahte API. Her uç ya veriyle ya da `...Error` ile yanıtlar; `...Gate` verilirse yanıt, kapı
/// açılana kadar bekler (yanıt çağrı ANINDA hesaplanır).
class FakeFinance4bApi extends Finance4bApi {
  FakeFinance4bApi() : super(baseUrl: 'http://localhost');

  /// Her çağrının önünde atılan hata (modül kapalı vb. testleri için).
  Object? commonError;

  final List<String> calls = <String>[];
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];

  Future<void> _enter(String name, [Map<String, Object?>? write]) async {
    calls.add(name);
    if (write != null) writes.add(<String, Object?>{'op': name, ...write});
    final error = commonError;
    if (error != null) throw error;
  }

  int callCount(String name) => calls.where((c) => c == name).length;

  // --- Ayarlar ------------------------------------------------------------------------------
  Map<String, dynamic> settingsJson = f4SettingsJson();
  Object? settingsError;
  F4Gate? settingsGate;
  Object? settingsUpdateError;
  final List<Map<String, dynamic>> settingsUpdates = <Map<String, dynamic>>[];

  @override
  Future<FinanceSettings> getSettings({required String token, required int siteCode}) async {
    await _enter('getSettings');
    final result = FinanceSettings.fromJson(settingsJson);
    await settingsGate?.future;
    final error = settingsError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<FinanceSettings?> updateSettings({
    required String token,
    required int siteCode,
    required FinanceSettingsPatch patch,
    required int expectedVersion,
  }) async {
    final body = patch.toJson(expectedVersion);
    await _enter('updateSettings', <String, Object?>{'body': body});
    settingsUpdates.add(body);
    final error = settingsUpdateError;
    if (error != null) throw error;
    final current = settingsJson['settings_version'] as int;
    if (expectedVersion != current) throw f4Coded('SETTINGS_STALE', 409);
    final next = Map<String, dynamic>.from(settingsJson);
    next['settings_version'] = current + 1;
    if (body['receipts'] is Map) {
      next['receipts'] = <String, dynamic>{...(next['receipts'] as Map).cast<String, dynamic>(), ...(body['receipts'] as Map).cast<String, dynamic>()};
    }
    if (body['late_fee'] is Map) {
      next['late_fee'] = <String, dynamic>{...(next['late_fee'] as Map).cast<String, dynamic>(), ...(body['late_fee'] as Map).cast<String, dynamic>()};
    }
    if (body['reminders'] is Map) {
      next['reminders'] = <String, dynamic>{...(next['reminders'] as Map).cast<String, dynamic>(), ...(body['reminders'] as Map).cast<String, dynamic>()};
    }
    settingsJson = next;
    return FinanceSettings.fromJson(next);
  }

  // --- Makbuz -------------------------------------------------------------------------------
  final Map<int, Map<String, dynamic>> receipts = <int, Map<String, dynamic>>{};
  Object? receiptError;
  Object? receiptListError;
  Object? printError;
  Object? cancelError;
  F4Gate? receiptGate;
  F4Gate? printGate;
  F4Gate? receiptListGate;
  int printCounter = 0;
  final List<Map<String, Object?>> receiptListCalls = <Map<String, Object?>>[];
  final List<int> issueCalls = <int>[];
  Map<String, dynamic>? issueResult;
  Object? issueError;
  bool verifyValid = true;
  String? verifyStatus = 'active';
  Object? verifyError;
  final List<Map<String, String>> verifyCalls = <Map<String, String>>[];

  @override
  Future<Receipt> getReceipt({required String token, required int siteCode, required int receiptId}) async {
    await _enter('getReceipt');
    final json = receipts[receiptId];
    final gate = receiptGate;
    if (json == null) throw f4Coded('RECEIPT_NOT_FOUND', 404);
    final result = Receipt.fromJson(json);
    await gate?.future;
    final error = receiptError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<Receipt> getMyReceipt({required String token, required int receiptId}) async {
    await _enter('getMyReceipt');
    final json = receipts[receiptId];
    if (json == null) throw f4Coded('RECEIPT_NOT_FOUND', 404);
    final stripped = Map<String, dynamic>.from(json)
      ..remove('copy_count')
      ..remove('ledger_entry_id');
    final result = Receipt.fromJson(stripped);
    await receiptGate?.future;
    final error = receiptError;
    if (error != null) throw error;
    return result;
  }

  ReceiptPage _page(Iterable<Map<String, dynamic>> all, int? beforeId, {int pageSize = 50}) {
    var rows = all.toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    if (beforeId != null) rows = rows.where((r) => (r['id'] as int) < beforeId).toList();
    final page = rows.take(pageSize).toList();
    return ReceiptPage.fromJson(<String, dynamic>{
      'items': [for (final r in page) f4ReceiptSummaryJson(r)],
      'next_before_id': rows.length > pageSize && page.isNotEmpty ? page.last['id'] : null,
    });
  }

  @override
  Future<ReceiptPage> listReceipts({
    required String token,
    required int siteCode,
    int? apartmentId,
    int? year,
    ReceiptKind? kind,
    String? query,
    int limit = 50,
    int? beforeId,
  }) async {
    await _enter('listReceipts');
    receiptListCalls.add(<String, Object?>{'apartment_id': apartmentId, 'year': year, 'q': query, 'before_id': beforeId});
    final q = (query ?? '').trim().toLowerCase();
    final rows = receipts.values.where((r) {
      if (q.isEmpty) return true;
      final snap = r['snapshot'] as Map;
      return (snap['number'] as String).toLowerCase().contains(q) ||
          ((snap['apartment'] as Map)['label'] as String).toLowerCase().contains(q) ||
          (((snap['payer'] as Map)['name'] as String?) ?? '').toLowerCase().contains(q);
    });
    final result = _page(rows, beforeId, pageSize: receiptPageSize);
    await receiptListGate?.future;
    final error = receiptListError;
    if (error != null) throw error;
    return result;
  }

  int receiptPageSize = 50;

  @override
  Future<ReceiptPage> listMyReceipts({
    required String token,
    int? apartmentId,
    int limit = 50,
    int? beforeId,
    AccountParty? accountParty,
  }) async {
    await _enter('listMyReceipts');
    receiptListCalls.add(<String, Object?>{
      'resident': true,
      'apartment_id': apartmentId,
      'before_id': beforeId,
      'account_party': ?accountParty?.apiValue,
    });
    final result = _page(receipts.values, beforeId, pageSize: receiptPageSize);
    await receiptListGate?.future;
    final error = receiptListError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<ReceiptIssueResult> issueReceipt({required String token, required int siteCode, required int entryId}) async {
    await _enter('issueReceipt', <String, Object?>{'entry_id': entryId});
    issueCalls.add(entryId);
    final error = issueError;
    if (error != null) throw error;
    final json = issueResult ?? f4ReceiptJson(900 + issueCalls.length, ledgerEntryId: entryId);
    receipts[json['id'] as int] = json;
    return ReceiptIssueResult(receipt: Receipt.fromJson(json), created: true);
  }

  @override
  Future<int> recordReceiptPrint({
    required String token,
    required int siteCode,
    required int receiptId,
    String? idempotencyKey,
  }) async {
    await _enter('recordReceiptPrint', <String, Object?>{'receipt_id': receiptId, 'key': idempotencyKey});
    await printGate?.future;
    final error = printError;
    if (error != null) throw error;
    final json = receipts[receiptId]!;
    final copy = (json['copy_count'] as int) + 1;
    json['copy_count'] = copy;
    printCounter++;
    return copy;
  }

  @override
  Future<ReceiptCancelResult> cancelReceipt({
    required String token,
    required int siteCode,
    required int receiptId,
    String? note,
    required String idempotencyKey,
  }) async {
    await _enter('cancelReceipt', <String, Object?>{'receipt_id': receiptId, 'note': note, 'key': idempotencyKey});
    final error = cancelError;
    if (error != null) throw error;
    final json = receipts[receiptId];
    if (json == null) throw f4Coded('RECEIPT_NOT_FOUND', 404);
    if (json['status'] == 'cancelled') throw f4Coded('RECEIPT_ALREADY_CANCELLED', 409);
    final newId = receipts.keys.fold<int>(0, (a, b) => a > b ? a : b) + 1;
    final number = 'MK-2026-${newId.toString().padLeft(6, '0')}';
    json['status'] = 'cancelled';
    (json['snapshot'] as Map<String, dynamic>)['cancelled_by_number'] = number;
    final cancellation = f4ReceiptJson(
      newId,
      number: number,
      kind: 'cancellation',
      cancelsNumber: (json['snapshot'] as Map)['number'] as String,
    );
    receipts[newId] = cancellation;
    return ReceiptCancelResult(
      cancellation: Receipt.fromJson(cancellation),
      receipt: Receipt.fromJson(json),
    );
  }

  @override
  Future<ReceiptVerifyResult> verifyReceipt({
    required String token,
    required int siteCode,
    required String number,
    required String code,
  }) async {
    await _enter('verifyReceipt');
    verifyCalls.add(<String, String>{'number': number, 'code': code});
    final error = verifyError;
    if (error != null) throw error;
    if (!verifyValid) return const ReceiptVerifyResult(valid: false);
    // Sunucu (R10): geçerliyse eşleşen makbuzun özeti de gelir.
    return ReceiptVerifyResult(
      valid: true,
      status: verifyStatus,
      number: number,
      amountMinor: 123456,
      paidOn: DateTime(2026, 10, 14),
      issuedOn: DateTime(2026, 10, 16),
      apartmentLabel: 'A Blok - 5',
    );
  }

  // --- İki kasa -------------------------------------------------------------------------------
  /// Her kasanın sabit rakamları (açılış, tahsilat, gider, düzeltme); aktarımlar [fundTransfers]'tan hesaplanır.
  final Map<String, Map<String, int>> fundBase = <String, Map<String, int>>{
    'operating': <String, int>{'opening': 1000000, 'collections': 500000, 'expenses': 200000, 'adjustments': 0},
    'capital': <String, int>{'opening': 0, 'collections': 300000, 'expenses': 0, 'adjustments': 0},
  };
  int fundAdvanceMinor = 25000;
  bool fundsBalanced = true;
  int fundsDifferenceMinor = 0;
  bool fundsHasAccounts = true;
  int fundsUnassignedCount = 0;
  int fundsUnassignedTotal = 0;
  Object? fundSummaryError;
  F4Gate? fundSummaryGate;
  Object? fundMovementsError;
  Object? fundTransferWriteError;
  Object? fundTransferListError;
  final List<Map<String, dynamic>> fundTransfers = <Map<String, dynamic>>[];
  final List<Map<String, Object?>> fundSummaryCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> fundMovementCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> fundTransferCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> fundReverseCalls = <Map<String, Object?>>[];
  final Map<String, Map<String, dynamic>> _fundTransferKeys = <String, Map<String, dynamic>>{};
  final Map<String, String> _fundTransferFingerprints = <String, String>{};
  int _nextFundTransferId = 10;

  /// Bir kasanın hareket satırları (yeni -> eski sırası sunucuda sıralanır; burada her biri `key`li ham JSON).
  final Map<String, List<Map<String, dynamic>>> fundMovementRows = <String, List<Map<String, dynamic>>>{
    'operating': <Map<String, dynamic>>[],
    'capital': <Map<String, dynamic>>[],
  };

  int _transferSum(String fund, {required bool incoming}) {
    var total = 0;
    for (final t in fundTransfers) {
      if (incoming && t['to_fund'] == fund) total += t['amount_minor'] as int;
      if (!incoming && t['from_fund'] == fund) total += t['amount_minor'] as int;
    }
    return total;
  }

  Map<String, dynamic> _fundJson(String fund) {
    final base = fundBase[fund]!;
    final incoming = _transferSum(fund, incoming: true);
    final outgoing = _transferSum(fund, incoming: false);
    final balance = base['opening']! + base['collections']! - base['expenses']! + incoming - outgoing + base['adjustments']!;
    return <String, dynamic>{
      'fund': fund,
      'fund_label': fund == 'operating' ? kFundOperatingName : kFundCapitalName,
      'fund_short_label': fund == 'operating' ? kFundOperatingShortName : kFundCapitalShortName,
      'opening_minor': base['opening'],
      'collections_minor': base['collections'],
      'expenses_minor': base['expenses'],
      'transfers_in_minor': incoming,
      'transfers_out_minor': outgoing,
      'adjustments_minor': base['adjustments'],
      'balance_minor': balance,
      'negative_balance': balance < 0,
    };
  }

  /// Şu anki kasa özeti JSON'u (sunucu biçimi).
  Map<String, dynamic> fundSummaryJson({DateTime? from, DateTime? to}) {
    final operating = _fundJson('operating');
    final capital = _fundJson('capital');
    final total = (operating['balance_minor'] as int) + (capital['balance_minor'] as int) + fundAdvanceMinor;
    return <String, dynamic>{
      'currency': 'TRY',
      'from': from == null ? null : _iso(from),
      'to': _iso(to ?? DateTime(2026, 10, 16)),
      'has_accounts': fundsHasAccounts,
      'funds': <String, dynamic>{'operating': operating, 'capital': capital},
      'advance_minor': fundAdvanceMinor,
      'accounts_total_minor': total - fundsDifferenceMinor,
      'difference_minor': fundsDifferenceMinor,
      'balanced': fundsBalanced,
      'unassigned_payments': <String, dynamic>{'count': fundsUnassignedCount, 'total_minor': fundsUnassignedTotal},
    };
  }

  @override
  Future<FundSummary> getFundSummary({required String token, required int siteCode, DateTime? from, DateTime? to}) async {
    await _enter('getFundSummary');
    fundSummaryCalls.add(<String, Object?>{'from': from == null ? null : _iso(from), 'to': to == null ? null : _iso(to)});
    final result = FundSummary.fromJson(fundSummaryJson(from: from, to: to));
    await fundSummaryGate?.future;
    final error = fundSummaryError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<FundMovementPage> listFundMovements({
    required String token,
    required int siteCode,
    required FinanceFund fund,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    await _enter('listFundMovements');
    fundMovementCalls.add(<String, Object?>{'fund': fund.apiValue, 'limit': limit, 'offset': offset, 'from': from == null ? null : _iso(from)});
    final error = fundMovementsError;
    if (error != null) throw error;
    final rows = fundMovementRows[fund.apiValue]!;
    final page = rows.skip(offset).take(limit).toList();
    return FundMovementPage.fromJson(<String, dynamic>{
      'fund': fund.apiValue,
      'balance_minor': _fundJson(fund.apiValue)['balance_minor'],
      'total': rows.length,
      'limit': limit,
      'offset': offset,
      'items': page,
    }, fund);
  }

  @override
  Future<FundTransferPage> listFundTransfers({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int? beforeId,
  }) async {
    await _enter('listFundTransfers');
    final error = fundTransferListError;
    if (error != null) throw error;
    var rows = List<Map<String, dynamic>>.of(fundTransfers)..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    if (beforeId != null) rows = rows.where((r) => (r['id'] as int) < beforeId).toList();
    final page = rows.take(fundTransferPageSize).toList();
    return FundTransferPage.fromJson(<String, dynamic>{
      'items': page,
      'next_before_id': rows.length > fundTransferPageSize && page.isNotEmpty ? page.last['id'] : null,
    });
  }

  int fundTransferPageSize = 50;

  Map<String, dynamic> _transferJson({
    required String from,
    required String to,
    required int amount,
    required String date,
    String? description,
    int? reverses,
    String? reason,
  }) => <String, dynamic>{
    'id': _nextFundTransferId++,
    'from_fund': from,
    'to_fund': to,
    'amount_minor': amount,
    'transfer_date': date,
    'period': date.substring(0, 7),
    'description': description,
    'reverses_transfer_id': reverses,
    'reversed_by_transfer_id': null,
    'reversal_reason': reason,
    'created_by_name': 'Site Yöneticisi',
    'created_at': '2026-10-16T09:00:00Z',
  };

  @override
  Future<FundTransfer> createFundTransfer({
    required String token,
    required int siteCode,
    required FinanceFund fromFund,
    required FinanceFund toFund,
    required int amountMinor,
    required DateTime transferDate,
    String? description,
    required String idempotencyKey,
  }) async {
    await _enter('createFundTransfer');
    fundTransferCalls.add(<String, Object?>{
      'from_fund': fromFund.apiValue,
      'to_fund': toFund.apiValue,
      'amount_minor': amountMinor,
      'transfer_date': _iso(transferDate),
      'description': description,
      'key': idempotencyKey,
    });
    final error = fundTransferWriteError;
    if (error != null) throw error;
    final fingerprint = '${fromFund.apiValue}|${toFund.apiValue}|$amountMinor|${_iso(transferDate)}|${description ?? ''}';
    final replay = _fundTransferKeys[idempotencyKey];
    if (replay != null) {
      if (_fundTransferFingerprints[idempotencyKey] != fingerprint) throw f4Coded('IDEMPOTENCY_CONFLICT', 409);
      return FundTransfer.fromJson(replay);
    }
    if (fromFund == toFund) throw f4Coded('INVALID_BODY', 400);
    _requireOpen(transferDate);
    final json = _transferJson(
      from: fromFund.apiValue,
      to: toFund.apiValue,
      amount: amountMinor,
      date: _iso(transferDate),
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
    );
    fundTransfers.add(json);
    _fundTransferKeys[idempotencyKey] = json;
    _fundTransferFingerprints[idempotencyKey] = fingerprint;
    return FundTransfer.fromJson(json);
  }

  @override
  Future<FundTransferReverseResult> reverseFundTransfer({
    required String token,
    required int siteCode,
    required int transferId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _enter('reverseFundTransfer');
    fundReverseCalls.add(<String, Object?>{'id': transferId, 'reason': reason, 'key': idempotencyKey});
    final error = fundTransferWriteError;
    if (error != null) throw error;
    final original = fundTransfers.where((t) => t['id'] == transferId).toList();
    if (original.isEmpty) throw f4Coded('FUND_TRANSFER_NOT_FOUND', 404);
    final row = original.first;
    if (row['reverses_transfer_id'] != null) throw f4Coded('FUND_TRANSFER_NOT_REVERSIBLE', 409);
    if (row['reversed_by_transfer_id'] != null) throw f4Coded('FUND_TRANSFER_ALREADY_REVERSED', 409);
    final reversal = _transferJson(
      from: row['to_fund'] as String,
      to: row['from_fund'] as String,
      amount: row['amount_minor'] as int,
      date: '2026-10-16',
      reverses: transferId,
      reason: reason.trim(),
    );
    row['reversed_by_transfer_id'] = reversal['id'];
    fundTransfers.add(reversal);
    return FundTransferReverseResult(transfer: FundTransfer.fromJson(reversal), original: FundTransfer.fromJson(row));
  }

  // --- Kasa / banka -------------------------------------------------------------------------
  final List<Map<String, dynamic>> accounts = <Map<String, dynamic>>[];
  int unassignedCount = 0;
  int unassignedTotal = 0;
  Object? accountsError;
  F4Gate? accountsGate;
  final Map<int, List<Map<String, dynamic>>> movements = <int, List<Map<String, dynamic>>>{};
  Object? movementsError;
  F4Gate? movementsGate;
  Object? accountWriteError;
  F4Gate? accountWriteGate;
  int _nextAccountId = 50;
  int _nextMovementId = 500;
  final Map<String, Map<String, dynamic>> _accountKeys = <String, Map<String, dynamic>>{};

  int get totalBalance => accounts.fold<int>(0, (a, b) => a + (b['balance_minor'] as int));

  Map<String, dynamic>? _account(int id) {
    for (final a in accounts) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  @override
  Future<CashOverview> listAccounts({required String token, required int siteCode}) async {
    await _enter('listAccounts');
    final result = CashOverview.fromJson(<String, dynamic>{
      'items': accounts,
      'total_balance_minor': totalBalance,
      'unassigned_payments': <String, dynamic>{'count': unassignedCount, 'total_minor': unassignedTotal},
    });
    await accountsGate?.future;
    final error = accountsError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<CashAccount> createAccount({
    required String token,
    required int siteCode,
    required String name,
    required CashAccountKind kind,
    String? note,
    required int openingBalanceMinor,
    required DateTime openingDate,
    required String idempotencyKey,
  }) async {
    await _enter('createAccount', <String, Object?>{
      'name': name,
      'kind': kind.apiValue,
      'note': note,
      'opening_balance_minor': openingBalanceMinor,
      'key': idempotencyKey,
    });
    await accountWriteGate?.future;
    final error = accountWriteError;
    if (error != null) throw error;
    final replay = _accountKeys[idempotencyKey];
    if (replay != null) return CashAccount.fromJson(replay);
    if (accounts.length >= 20) throw f4Coded('ACCOUNT_LIMIT', 409);
    if (accounts.any((a) => (a['name'] as String).toLowerCase() == name.trim().toLowerCase())) {
      throw f4Coded('ACCOUNT_NAME_TAKEN', 409);
    }
    final json = f4AccountJson(
      _nextAccountId++,
      name.trim(),
      kind: kind.apiValue,
      balance: openingBalanceMinor,
      note: note,
      opening: openingBalanceMinor,
    );
    accounts.add(json);
    _accountKeys[idempotencyKey] = json;
    return CashAccount.fromJson(json);
  }

  @override
  Future<CashAccount> updateAccount({
    required String token,
    required int siteCode,
    required int accountId,
    required Map<String, Object?> fields,
  }) async {
    await _enter('updateAccount', <String, Object?>{'account_id': accountId, ...fields});
    await accountWriteGate?.future;
    final error = accountWriteError;
    if (error != null) throw error;
    final json = _account(accountId);
    if (json == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
    fields.forEach((k, v) => json[k] = v);
    return CashAccount.fromJson(json);
  }

  @override
  Future<MovementPage> listMovements({
    required String token,
    required int siteCode,
    required int accountId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int? beforeId,
  }) async {
    await _enter('listMovements');
    final account = _account(accountId);
    if (account == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
    var rows = List<Map<String, dynamic>>.of(movements[accountId] ?? const <Map<String, dynamic>>[])
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    if (beforeId != null) rows = rows.where((r) => (r['id'] as int) < beforeId).toList();
    final page = rows.take(movementPageSize).toList();
    final result = MovementPage.fromJson(<String, dynamic>{
      'account': <String, dynamic>{'id': accountId, 'name': account['name'], 'kind': account['kind']},
      'balance_minor': account['balance_minor'],
      'negative_balance': (account['balance_minor'] as int) < 0,
      'items': page,
      'next_before_id': rows.length > movementPageSize && page.isNotEmpty ? page.last['id'] : null,
    });
    await movementsGate?.future;
    final error = movementsError;
    if (error != null) throw error;
    return result;
  }

  int movementPageSize = 50;

  Map<String, dynamic> _addMovement(int accountId, String kind, int amount, String date, {String? label, String? reason, String? note}) {
    final account = _account(accountId)!;
    final json = <String, dynamic>{
      'id': _nextMovementId++,
      'kind': kind,
      'amount_minor': amount,
      'movement_date': date,
      'period': date.substring(0, 7),
      'label': label,
      'reason_code': reason,
      'note': note,
    };
    (movements[accountId] ??= <Map<String, dynamic>>[]).add(json);
    account['balance_minor'] = (account['balance_minor'] as int) + amount;
    return json;
  }

  final Set<String> closedMonths = <String>{};

  void _requireOpen(DateTime date) {
    final period = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    if (closedMonths.any((m) => period.compareTo(m) <= 0)) throw f4Coded('PERIOD_CLOSED', 409);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<AccountMovement> adjustAccount({
    required String token,
    required int siteCode,
    required int accountId,
    required int amountMinor,
    required DateTime movementDate,
    required AdjustmentReason reason,
    String? note,
    required String idempotencyKey,
  }) async {
    await _enter('adjustAccount', <String, Object?>{
      'account_id': accountId,
      'amount_minor': amountMinor,
      'date': _iso(movementDate),
      'reason': reason.apiValue,
      'note': note,
      'key': idempotencyKey,
    });
    await accountWriteGate?.future;
    final error = accountWriteError;
    if (error != null) throw error;
    final account = _account(accountId);
    if (account == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
    if (account['is_active'] != true) throw f4Coded('ACCOUNT_INACTIVE', 409);
    _requireOpen(movementDate);
    return AccountMovement.fromJson(
      _addMovement(accountId, 'adjustment', amountMinor, _iso(movementDate), reason: reason.apiValue, note: note),
    );
  }

  final List<Map<String, dynamic>> transfers = <Map<String, dynamic>>[];
  Object? transfersError;
  F4Gate? transfersGate;
  final Map<String, Map<String, dynamic>> _transferKeys = <String, Map<String, dynamic>>{};

  @override
  Future<TransferPage> listTransfers({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int? beforeId,
  }) async {
    await _enter('listTransfers');
    final rows = List<Map<String, dynamic>>.of(transfers)..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final result = TransferPage.fromJson(<String, dynamic>{'items': rows, 'next_before_id': null});
    await transfersGate?.future;
    final error = transfersError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<TransferWriteResult> createTransfer({
    required String token,
    required int siteCode,
    required int fromAccountId,
    required int toAccountId,
    required int amountMinor,
    required DateTime transferDate,
    String? description,
    required String idempotencyKey,
  }) async {
    await _enter('createTransfer', <String, Object?>{
      'from': fromAccountId,
      'to': toAccountId,
      'amount_minor': amountMinor,
      'date': _iso(transferDate),
      'description': description,
      'key': idempotencyKey,
    });
    await accountWriteGate?.future;
    final error = accountWriteError;
    if (error != null) throw error;
    final replay = _transferKeys[idempotencyKey];
    if (replay != null) {
      return TransferWriteResult(transfer: AccountTransfer.fromJson(replay));
    }
    final from = _account(fromAccountId);
    final to = _account(toAccountId);
    if (from == null || to == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
    if (from['is_active'] != true || to['is_active'] != true) throw f4Coded('ACCOUNT_INACTIVE', 409);
    _requireOpen(transferDate);
    final out = _addMovement(fromAccountId, 'transfer_out', -amountMinor, _iso(transferDate), label: to['name'] as String);
    final inn = _addMovement(toAccountId, 'transfer_in', amountMinor, _iso(transferDate), label: from['name'] as String);
    final json = <String, dynamic>{
      'id': 700 + transfers.length,
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'from_account_name': from['name'],
      'to_account_name': to['name'],
      'amount_minor': amountMinor,
      'transfer_date': _iso(transferDate),
      'description': description,
      'voided': null,
    };
    transfers.add(json);
    _transferKeys[idempotencyKey] = json;
    return TransferWriteResult(
      transfer: AccountTransfer.fromJson(json),
      movements: [AccountMovement.fromJson(out), AccountMovement.fromJson(inn)],
    );
  }

  @override
  Future<void> voidTransfer({
    required String token,
    required int siteCode,
    required int transferId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _enter('voidTransfer', <String, Object?>{'transfer_id': transferId, 'reason': reason, 'key': idempotencyKey});
    await accountWriteGate?.future;
    final error = accountWriteError;
    if (error != null) throw error;
    final json = transfers.where((t) => t['id'] == transferId).toList();
    if (json.isEmpty) throw f4Coded('TRANSFER_NOT_FOUND', 404);
    if (json.first['voided'] != null) throw f4Coded('TRANSFER_ALREADY_VOIDED', 409);
    final t = json.first;
    final amount = t['amount_minor'] as int;
    _addMovement(t['from_account_id'] as int, 'reversal', amount, '2026-10-16');
    _addMovement(t['to_account_id'] as int, 'reversal', -amount, '2026-10-16');
    t['voided'] = <String, dynamic>{'at': '2026-10-16T09:00:00Z', 'reason': reason};
  }

  // Toplu eşleme
  AssignPreview assignPreviewResult = const AssignPreview(count: 0, totalMinor: 0, previewHash: 'a0');
  Object? assignPreviewError;
  Object? assignCommitError;
  F4Gate? assignGate;
  bool assignStaleOnce = false;
  final List<Map<String, Object?>> assignCommits = <Map<String, Object?>>[];

  @override
  Future<AssignPreview> previewAssignPayments({
    required String token,
    required int siteCode,
    required Map<String, int> accountByMethod,
  }) async {
    await _enter('previewAssignPayments', <String, Object?>{'map': accountByMethod});
    await assignGate?.future;
    final error = assignPreviewError;
    if (error != null) throw error;
    return assignPreviewResult;
  }

  @override
  Future<AssignResult> commitAssignPayments({
    required String token,
    required int siteCode,
    required Map<String, int> accountByMethod,
    required int expectedCount,
    required int expectedTotalMinor,
    required String expectedHash,
    required String idempotencyKey,
  }) async {
    await _enter('commitAssignPayments', <String, Object?>{
      'map': accountByMethod,
      'count': expectedCount,
      'total': expectedTotalMinor,
      'hash': expectedHash,
      'key': idempotencyKey,
    });
    assignCommits.add(<String, Object?>{'hash': expectedHash, 'key': idempotencyKey});
    await assignGate?.future;
    final error = assignCommitError;
    if (error != null) throw error;
    if (assignStaleOnce) {
      assignStaleOnce = false;
      assignPreviewResult = AssignPreview(
        count: assignPreviewResult.count + 1,
        totalMinor: assignPreviewResult.totalMinor + 1000,
        previewHash: '${assignPreviewResult.previewHash}x',
        byMethod: assignPreviewResult.byMethod,
      );
      throw f4Coded('PREVIEW_STALE', 409, payload: <String, dynamic>{
        'count': assignPreviewResult.count,
        'total_minor': assignPreviewResult.totalMinor,
        'preview_hash': assignPreviewResult.previewHash,
      });
    }
    unassignedCount = 0;
    unassignedTotal = 0;
    return AssignResult(count: expectedCount, totalMinor: expectedTotalMinor);
  }

  // Mutabakat
  final Map<int, List<Map<String, dynamic>>> reconciliations = <int, List<Map<String, dynamic>>>{};
  Object? reconcileError;
  bool reconcileStaleOnce = false;

  /// STALE yanıtındaki yeni hesaplanan bakiye farkı (varsayılan +25,00 ₺: "araya yeni hareket girdi"). Tarih sırasıyla girilen
  /// ekstrelerde sunucu önceki mutabakatın DÜZELTMESİNİ de hesaplanan bakiyeye katar; test bunu büyük bir farkla taklit eder.
  int reconcileStaleDeltaMinor = 2500;

  /// true iken düzeltmeli (adjust) mutabakat 409 RECONCILIATION_ORDER alır (daha yeni tarihli düzeltmeli mutabakat var).
  bool reconcileOrderConflict = false;
  final List<Map<String, Object?>> reconcileCalls = <Map<String, Object?>>[];

  @override
  Future<List<Reconciliation>> listReconciliations({
    required String token,
    required int siteCode,
    required int accountId,
  }) async {
    await _enter('listReconciliations');
    return [for (final j in reconciliations[accountId] ?? const <Map<String, dynamic>>[]) Reconciliation.fromJson(j)];
  }

  @override
  Future<ReconciliationResult> reconcileAccount({
    required String token,
    required int siteCode,
    required int accountId,
    required DateTime asOfDate,
    required int statementBalanceMinor,
    required int expectedComputedMinor,
    String? note,
    AdjustmentReason? adjustReason,
    String? adjustNote,
    required String idempotencyKey,
  }) async {
    await _enter('reconcileAccount');
    reconcileCalls.add(<String, Object?>{
      'account_id': accountId,
      'statement': statementBalanceMinor,
      'expected': expectedComputedMinor,
      'adjust': adjustReason?.apiValue,
      'adjust_note': adjustNote,
      'note': note,
      'key': idempotencyKey,
    });
    await accountWriteGate?.future;
    final error = reconcileError;
    if (error != null) throw error;
    final account = _account(accountId);
    if (account == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
    final computed = account['balance_minor'] as int;
    if (reconcileStaleOnce || computed != expectedComputedMinor) {
      reconcileStaleOnce = false;
      account['balance_minor'] = computed + reconcileStaleDeltaMinor; // araya yeni hareket / önceki mutabakatın düzeltmesi girdi
      // Sunucunun gerçek anahtarı: computed_balance_minor.
      throw f4Coded('RECONCILIATION_STALE', 409, payload: <String, dynamic>{'computed_balance_minor': account['balance_minor']});
    }
    final difference = statementBalanceMinor - computed;
    if (reconcileOrderConflict && adjustReason != null && difference != 0) throw f4Coded('RECONCILIATION_ORDER', 409);
    int? adjustmentId;
    if (adjustReason != null && difference != 0) {
      adjustmentId = _addMovement(accountId, 'adjustment', difference, _iso(asOfDate), reason: adjustReason.apiValue, note: adjustNote)['id'] as int;
    }
    final json = <String, dynamic>{
      'id': 900 + (reconciliations[accountId]?.length ?? 0),
      'as_of_date': _iso(asOfDate),
      'statement_balance_minor': statementBalanceMinor,
      'computed_balance_minor': computed,
      'difference_minor': difference,
      'adjustment_movement_id': adjustmentId,
      'note': note,
    };
    (reconciliations[accountId] ??= <Map<String, dynamic>>[]).add(json);
    account['last_reconciliation'] = <String, dynamic>{
      'as_of_date': _iso(asOfDate),
      'difference_minor': adjustmentId != null ? 0 : difference,
    };
    return ReconciliationResult(
      reconciliation: Reconciliation.fromJson(json),
      accountBalanceMinor: account['balance_minor'] as int,
    );
  }

  // --- Hesap (İşletme / Fon) seçimi (K3) ------------------------------------------------------
  final List<Map<String, Object?>> fundChoiceCalls = <Map<String, Object?>>[];

  /// Daire kimliği -> `GET payments/fund-choice` yanıtı (sunucu biçimi, bkz. [fundChoiceBody]). Yoksa borçsuz yanıt.
  final Map<int, Map<String, dynamic>> fundChoiceBodies = <int, Map<String, dynamic>>{};

  /// Sunucunun KAYIT anında gördüğü durum (GET'in söylediğinden farklıysa: bayat bilgi). Yoksa [fundChoiceBodies] geçerli.
  final Map<int, Map<String, dynamic>> serverFundChoice = <int, Map<String, dynamic>>{};

  /// Düzeltme (asıl kayıt hâlâ defterde, okunan durum yanıltır): doluysa `fund` verilmeyen düzeltme 400 FUND_CHOICE_REQUIRED alır.
  Map<String, dynamic>? correctionFundChoice;
  Object? fundChoiceError;
  F4Gate? fundChoiceGate;

  /// Sunucu `GET payments/fund-choice` yanıtı: [operating] / [capital] açık borç (kuruş). İkisi de > 0 ise seçim zorunlu; yalnız biri > 0 ise öneri o.
  static Map<String, dynamic> fundChoiceBody({int operating = 0, int capital = 0, String party = 'owner', Map<String, dynamic>? proposal}) => <String, dynamic>{
    'apartment_id': 0,
    'account_party': party,
    'open': <String, dynamic>{'operating_minor': operating, 'capital_minor': capital},
    'advance_minor': 0,
    'choice_required': operating > 0 && capital > 0,
    'suggested_fund': operating > 0 && capital == 0 ? 'operating' : (capital > 0 && operating == 0 ? 'capital' : null),
    'proposal': proposal,
  };

  @override
  Future<FundChoiceInfo> getFundChoice({
    required String token,
    required int siteCode,
    required int apartmentId,
    AccountParty? accountParty,
    int? amountMinor,
    DateTime? paidOn,
  }) async {
    await _enter('getFundChoice');
    fundChoiceCalls.add(<String, Object?>{'apartment_id': apartmentId, 'account_party': accountParty?.apiValue, 'amount_minor': amountMinor});
    await fundChoiceGate?.future;
    final error = fundChoiceError;
    if (error != null) throw error;
    return FundChoiceInfo.tryParse(fundChoiceBodies[apartmentId] ?? fundChoiceBody())!;
  }

  /// Sunucunun K3 kuralı: hesap (fund) verilmediyse ve iki türün de açık borcu varsa 400 FUND_CHOICE_REQUIRED.
  void _enforceFundChoice(int apartmentId, FinanceFund? fund) {
    final body = serverFundChoice[apartmentId] ?? fundChoiceBodies[apartmentId];
    if (fund == null && body != null && body['choice_required'] == true) {
      throw f4Coded('FUND_CHOICE_REQUIRED', 400, payload: <String, dynamic>{'fund_choice': body});
    }
  }

  // --- Hesap seçimli tahsilat ---------------------------------------------------------------
  final List<Map<String, Object?>> paymentCalls = <Map<String, Object?>>[];
  Object? paymentError;
  F4Gate? paymentGate;
  Map<String, dynamic>? paymentReceipt = <String, dynamic>{'id': 77, 'number': 'MK-2026-000077'};

  /// Tahsilat / düzeltme yanıtındaki `fund_split` (null: eski sunucu, alan yok).
  Map<String, dynamic>? paymentFundSplit;
  final Map<String, LedgerWriteResult> _paymentKeys = <String, LedgerWriteResult>{};

  @override
  Future<LedgerWriteResult> recordPayment({
    required String token,
    required int siteCode,
    required int apartmentId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    int? accountId,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) async {
    await _enter('recordPayment');
    paymentCalls.add(<String, Object?>{
      'apartment_id': apartmentId,
      'amount_minor': amountMinor,
      'method': method.apiValue,
      'account_id': accountId,
      'description': description,
      'key': idempotencyKey,
      'account_party': ?accountParty?.apiValue,
      'fund': ?fund?.apiValue,
    });
    await paymentGate?.future;
    final error = paymentError;
    if (error != null) throw error;
    final replay = _paymentKeys[idempotencyKey];
    if (replay != null) return replay;
    final active = accounts.where((a) => a['is_active'] == true).toList();
    if (active.isNotEmpty && accountId == null) throw f4Coded('ACCOUNT_REQUIRED', 409);
    if (accountId != null) {
      final account = _account(accountId);
      if (account == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
      if (account['is_active'] != true) throw f4Coded('ACCOUNT_INACTIVE', 409);
    }
    _enforceFundChoice(apartmentId, fund);
    if (accountId != null) {
      _addMovement(accountId, 'collection', amountMinor, _iso(entryDate), label: 'A Blok - 5');
    }
    final result = LedgerWriteResult.fromJson(<String, dynamic>{
      'entry': <String, dynamic>{
        'id': 9000 + paymentCalls.length,
        'kind': 'payment',
        'amount_minor': -amountMinor,
        'entry_date': _iso(entryDate),
        'method': method.apiValue,
        'account_party': ?accountParty?.apiValue,
        'fund': ?fund?.apiValue,
      },
      'balance_minor': 0,
      'receipt': paymentReceipt,
      'movement_id': accountId == null ? null : 1,
      'fund_split': ?paymentFundSplit,
    });
    _paymentKeys[idempotencyKey] = result;
    return result;
  }

  /// Hesap seçimli düzeltme çağrıları (4a düzeltme yolu hesapsızdır; hesap seçilince bu uç kullanılır).
  final List<Map<String, Object?>> correctPaymentCalls = <Map<String, Object?>>[];

  @override
  Future<LedgerWriteResult> correctPayment({
    required String token,
    required int siteCode,
    required int entryId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    int? accountId,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) async {
    await _enter('correctPayment');
    correctPaymentCalls.add(<String, Object?>{
      'entry_id': entryId,
      'amount_minor': amountMinor,
      'method': method.apiValue,
      'account_id': accountId,
      'key': idempotencyKey,
      'account_party': ?accountParty?.apiValue,
      'fund': ?fund?.apiValue,
    });
    await paymentGate?.future;
    final error = paymentError;
    if (error != null) throw error;
    final required = correctionFundChoice;
    if (fund == null && required != null && required['choice_required'] == true) {
      throw f4Coded('FUND_CHOICE_REQUIRED', 400, payload: <String, dynamic>{'fund_choice': required});
    }
    return LedgerWriteResult.fromJson(<String, dynamic>{
      'entry': <String, dynamic>{
        'id': 9500 + correctPaymentCalls.length,
        'kind': 'payment',
        'amount_minor': -amountMinor,
        'entry_date': _iso(entryDate),
        'method': method.apiValue,
        'fund': ?fund?.apiValue,
      },
      'balance_minor': 0,
      'receipt': paymentReceipt,
      'movement_id': accountId,
      'fund_split': ?paymentFundSplit,
    });
  }

  // --- Gider ---------------------------------------------------------------------------------
  final List<Map<String, dynamic>> categories = <Map<String, dynamic>>[
    <String, dynamic>{'id': 1, 'name': 'Elektrik', 'is_system': true, 'is_active': true, 'sort_order': 1, 'fund': 'operating'},
    <String, dynamic>{'id': 2, 'name': 'Asansör bakım', 'is_system': true, 'is_active': true, 'sort_order': 2, 'fund': 'operating'},
    <String, dynamic>{'id': 3, 'name': 'Eski kategori', 'is_system': false, 'is_active': false, 'sort_order': 3, 'fund': 'operating'},
  ];
  final List<Map<String, dynamic>> suppliers = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> expenses = <Map<String, dynamic>>[];
  Object? categoriesError;
  Object? suppliersError;
  Object? expensesError;
  Object? expenseWriteError;
  Object? catalogWriteError;
  F4Gate? expensesGate;
  F4Gate? expenseWriteGate;
  int expensePageSize = 50;
  int _nextExpenseId = 300;
  int _nextCategoryId = 40;
  int _nextSupplierId = 60;
  final Map<String, Map<String, dynamic>> _expenseKeys = <String, Map<String, dynamic>>{};
  final Map<String, String> _expenseFingerprints = <String, String>{};
  final List<Map<String, Object?>> expenseCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> expenseListCalls = <Map<String, Object?>>[];
  final Map<int, List<Map<String, dynamic>>> expenseDocuments = <int, List<Map<String, dynamic>>>{};
  Object? documentError;
  int uploads = 0;

  @override
  Future<List<ExpenseCategory>> listExpenseCategories({required String token, required int siteCode, bool? active}) async {
    await _enter('listExpenseCategories');
    final rows = categories.where((c) => active == null || c['is_active'] == active).toList();
    final result = [for (final r in rows) ExpenseCategory.fromJson(r)];
    final error = categoriesError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<ExpenseCategory> createExpenseCategory({
    required String token,
    required int siteCode,
    required String name,
    FinanceFund? fund,
  }) async {
    await _enter('createExpenseCategory', <String, Object?>{'name': name, 'fund': ?fund?.apiValue});
    final error = catalogWriteError;
    if (error != null) throw error;
    if (categories.any((c) => (c['name'] as String).toLowerCase() == name.trim().toLowerCase())) {
      throw ApiException('Bu adla başka bir kategori var.', statusCode: 409, code: 'CATEGORY_NAME_TAKEN');
    }
    final json = <String, dynamic>{
      'id': _nextCategoryId++,
      'name': name.trim(),
      'is_system': false,
      'is_active': true,
      'sort_order': 99,
      'fund': (fund ?? FinanceFund.operating).apiValue,
    };
    categories.add(json);
    return ExpenseCategory.fromJson(json);
  }

  @override
  Future<ExpenseCategory> updateExpenseCategory({
    required String token,
    required int siteCode,
    required int categoryId,
    required Map<String, Object?> fields,
  }) async {
    await _enter('updateExpenseCategory', <String, Object?>{'id': categoryId, ...fields});
    final error = catalogWriteError;
    if (error != null) throw error;
    final json = categories.firstWhere((c) => c['id'] == categoryId, orElse: () => throw f4Coded('CATEGORY_NOT_FOUND', 404));
    // Sunucu: sistem kategorisinin ya da eski gideri olan kategorinin kasası değiştirilemez (409 CATEGORY_FUND_LOCKED).
    if (fields.containsKey('fund') && fields['fund'] != json['fund']) {
      final used = expenses.any((e) => e['category_id'] == categoryId);
      if (json['is_system'] == true || used) throw f4Coded('CATEGORY_FUND_LOCKED', 409);
    }
    fields.forEach((k, v) => json[k] = v);
    return ExpenseCategory.fromJson(json);
  }

  @override
  Future<SupplierPage> listSuppliers({
    required String token,
    required int siteCode,
    String? query,
    bool? active,
    int limit = 50,
    int offset = 0,
  }) async {
    await _enter('listSuppliers');
    final q = (query ?? '').trim().toLowerCase();
    final rows = suppliers.where((s) {
      if (active != null && s['is_active'] != active) return false;
      return q.isEmpty || (s['name'] as String).toLowerCase().contains(q);
    }).toList();
    final page = rows.skip(offset).take(limit).toList();
    final result = SupplierPage.fromJson(<String, dynamic>{'items': page, 'total': rows.length});
    final error = suppliersError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<Supplier> createSupplier({
    required String token,
    required int siteCode,
    required String name,
    String? taxId,
    String? phone,
    String? note,
  }) async {
    await _enter('createSupplier', <String, Object?>{'name': name, 'tax_id': taxId, 'phone': phone, 'note': note});
    final error = catalogWriteError;
    if (error != null) throw error;
    if (suppliers.any((s) => (s['name'] as String).toLowerCase() == name.trim().toLowerCase())) {
      throw ApiException('Bu adla başka bir tedarikçi var.', statusCode: 409, code: 'SUPPLIER_NAME_TAKEN');
    }
    final json = <String, dynamic>{
      'id': _nextSupplierId++,
      'name': name.trim(),
      'tax_id': (taxId ?? '').trim().isEmpty ? null : taxId!.trim(),
      'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
      'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      'is_active': true,
    };
    suppliers.add(json);
    return Supplier.fromJson(json);
  }

  @override
  Future<Supplier> updateSupplier({
    required String token,
    required int siteCode,
    required int supplierId,
    required Map<String, Object?> fields,
  }) async {
    await _enter('updateSupplier', <String, Object?>{'id': supplierId, ...fields});
    final error = catalogWriteError;
    if (error != null) throw error;
    final json = suppliers.firstWhere((s) => s['id'] == supplierId, orElse: () => throw f4Coded('SUPPLIER_NOT_FOUND', 404));
    fields.forEach((k, v) => json[k] = v);
    return Supplier.fromJson(json);
  }

  Map<String, dynamic> _expenseJson(Map<String, dynamic> row, {bool detail = false}) {
    final account = _account(row['account_id'] as int);
    final docs = expenseDocuments[row['id']] ?? const <Map<String, dynamic>>[];
    return <String, dynamic>{
      'id': row['id'],
      'category_id': row['category_id'],
      'category_name': row['category_name'],
      'supplier_id': row['supplier_id'],
      'supplier_name': row['supplier_name'],
      'description': row['description'],
      'amount_minor': row['amount_minor'],
      'vat_minor': row['vat_minor'],
      'expense_date': row['expense_date'],
      'account': <String, dynamic>{'id': row['account_id'], 'name': account?['name'] ?? 'Hesap'},
      'document_kind': row['document_kind'],
      'document_no': row['document_no'],
      'voided': row['voided'],
      'corrects_expense_id': row['corrects_expense_id'],
      'documents_count': docs.length,
      'fund': ?row['fund'],
      if (detail) 'documents': docs,
      'created_by_name': 'Site Yöneticisi',
      'created_at': '2026-10-16T09:00:00Z',
    };
  }

  @override
  Future<ExpensePage> listExpenses({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
    int? categoryId,
    int? supplierId,
    int? accountId,
    String status = 'active',
    String? query,
    int limit = 50,
    int? beforeId,
  }) async {
    await _enter('listExpenses');
    expenseListCalls.add(<String, Object?>{
      'from': from == null ? null : _iso(from),
      'to': to == null ? null : _iso(to),
      'category_id': categoryId,
      'account_id': accountId,
      'status': status,
      'q': query,
      'before_id': beforeId,
    });
    final q = (query ?? '').trim().toLowerCase();
    final rows = expenses.where((e) {
      final voided = e['voided'] != null;
      if (status == 'active' && voided) return false;
      if (status == 'voided' && !voided) return false;
      final date = e['expense_date'] as String;
      if (from != null && date.compareTo(_iso(from)) < 0) return false;
      if (to != null && date.compareTo(_iso(to)) > 0) return false;
      if (categoryId != null && e['category_id'] != categoryId) return false;
      if (accountId != null && e['account_id'] != accountId) return false;
      if (q.isNotEmpty &&
          !(e['description'] as String).toLowerCase().contains(q) &&
          !((e['supplier_name'] as String?) ?? '').toLowerCase().contains(q) &&
          !((e['document_no'] as String?) ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    var active = 0;
    var voidedTotal = 0;
    for (final e in rows) {
      if (e['voided'] == null) {
        active += e['amount_minor'] as int;
      } else {
        voidedTotal += e['amount_minor'] as int;
      }
    }
    final after = beforeId == null ? rows : rows.where((e) => (e['id'] as int) < beforeId).toList();
    final page = after.take(expensePageSize).toList();
    final result = ExpensePage.fromJson(<String, dynamic>{
      'items': [for (final r in page) _expenseJson(r)],
      'next_before_id': after.length > expensePageSize && page.isNotEmpty ? page.last['id'] : null,
      'totals': <String, dynamic>{'active_minor': active, 'voided_minor': voidedTotal},
    });
    await expensesGate?.future;
    final error = expensesError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<Expense> getExpense({required String token, required int siteCode, required int expenseId}) async {
    await _enter('getExpense');
    final row = expenses.where((e) => e['id'] == expenseId).toList();
    if (row.isEmpty) throw f4Coded('EXPENSE_NOT_FOUND', 404);
    final result = Expense.fromJson(_expenseJson(row.first, detail: true));
    await expensesGate?.future;
    final error = expensesError;
    if (error != null) throw error;
    return result;
  }

  Map<String, dynamic> _writeExpense(ExpenseInput input, {int? corrects}) {
    final category = categories.firstWhere((c) => c['id'] == input.categoryId, orElse: () => throw f4Coded('CATEGORY_NOT_FOUND', 404));
    if (category['is_active'] != true) throw f4Coded('CATEGORY_INACTIVE', 409);
    final account = _account(input.accountId);
    if (account == null) throw f4Coded('ACCOUNT_NOT_FOUND', 404);
    if (account['is_active'] != true) throw f4Coded('ACCOUNT_INACTIVE', 409);
    _requireOpen(input.expenseDate);
    final supplier = input.supplierId == null ? null : suppliers.firstWhere((s) => s['id'] == input.supplierId, orElse: () => throw f4Coded('SUPPLIER_NOT_FOUND', 404));
    final no = (input.documentNo ?? '').trim();
    if (no.isNotEmpty && supplier != null) {
      final norm = no.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final existing = expenses.where((e) => e['voided'] == null && e['supplier_id'] == supplier['id'] && e['doc_norm'] == norm).toList();
      if (existing.isNotEmpty) {
        throw f4Coded('DUPLICATE_DOCUMENT_NO', 409, payload: <String, dynamic>{'existing_expense_id': existing.first['id']});
      }
    }
    if (!input.allowDuplicate) {
      final date = _iso(input.expenseDate);
      final dup = expenses.where((e) =>
          e['voided'] == null &&
          e['amount_minor'] == input.amountMinor &&
          e['expense_date'] == date &&
          e['category_id'] == input.categoryId &&
          e['supplier_id'] == input.supplierId &&
          e['corrects_expense_id'] == null).toList();
      if (dup.isNotEmpty) {
        throw f4Coded('DUPLICATE_EXPENSE', 409, payload: <String, dynamic>{'existing_expense_id': dup.first['id']});
      }
    }
    final row = <String, dynamic>{
      'id': _nextExpenseId++,
      'category_id': input.categoryId,
      'category_name': category['name'],
      'supplier_id': input.supplierId,
      'supplier_name': supplier?['name'],
      'description': input.description,
      'amount_minor': input.amountMinor,
      'vat_minor': input.vatMinor,
      'expense_date': _iso(input.expenseDate),
      'account_id': input.accountId,
      'document_kind': input.documentKind.apiValue,
      'document_no': no.isEmpty ? null : no,
      'doc_norm': no.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
      'voided': null,
      'corrects_expense_id': corrects,
      // Sunucu: giderin kasası satıra HER ZAMAN yazılır (verilmediyse kategorinin kasası).
      'fund': input.fund?.apiValue ?? category['fund'],
    };
    expenses.add(row);
    _addMovement(input.accountId, 'expense', -input.amountMinor, _iso(input.expenseDate), label: input.description);
    return row;
  }

  @override
  Future<ExpenseWriteResult> createExpense({
    required String token,
    required int siteCode,
    required ExpenseInput input,
    required String idempotencyKey,
  }) async {
    await _enter('createExpense');
    expenseCalls.add(<String, Object?>{'op': 'create', ...input.toJson(), 'key': idempotencyKey});
    await expenseWriteGate?.future;
    final error = expenseWriteError;
    if (error != null) throw error;
    final fingerprint = jsonEncode(<String, dynamic>{...input.toJson()}..remove('allow_duplicate'));
    final replay = _expenseKeys[idempotencyKey];
    if (replay != null) {
      if (_expenseFingerprints[idempotencyKey] != fingerprint) throw f4Coded('IDEMPOTENCY_CONFLICT', 409);
      return ExpenseWriteResult.fromJson(<String, dynamic>{'expense': _expenseJson(replay)});
    }
    if (accounts.where((a) => a['is_active'] == true).isEmpty) throw f4Coded('NO_ACCOUNT', 409);
    final row = _writeExpense(input);
    _expenseKeys[idempotencyKey] = row;
    _expenseFingerprints[idempotencyKey] = fingerprint;
    return ExpenseWriteResult.fromJson(<String, dynamic>{
      'expense': _expenseJson(row),
      'account_balance_minor': _account(input.accountId)!['balance_minor'],
    });
  }

  @override
  Future<Expense> voidExpense({
    required String token,
    required int siteCode,
    required int expenseId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _enter('voidExpense', <String, Object?>{'id': expenseId, 'reason': reason, 'key': idempotencyKey});
    await expenseWriteGate?.future;
    final error = expenseWriteError;
    if (error != null) throw error;
    final row = expenses.firstWhere((e) => e['id'] == expenseId, orElse: () => throw f4Coded('EXPENSE_NOT_FOUND', 404));
    if (row['voided'] != null) throw f4Coded('EXPENSE_ALREADY_VOIDED', 409);
    row['voided'] = <String, dynamic>{'at': '2026-10-16T09:30:00Z', 'reason': reason, 'period': '2026-10'};
    _addMovement(row['account_id'] as int, 'reversal', row['amount_minor'] as int, '2026-10-16');
    return Expense.fromJson(_expenseJson(row));
  }

  @override
  Future<ExpenseCorrectResult> correctExpense({
    required String token,
    required int siteCode,
    required int expenseId,
    required ExpenseInput input,
    required String idempotencyKey,
  }) async {
    await _enter('correctExpense');
    expenseCalls.add(<String, Object?>{'op': 'correct', 'id': expenseId, ...input.toJson(), 'key': idempotencyKey});
    await expenseWriteGate?.future;
    final error = expenseWriteError;
    if (error != null) throw error;
    final old = expenses.firstWhere((e) => e['id'] == expenseId, orElse: () => throw f4Coded('EXPENSE_NOT_FOUND', 404));
    if (old['voided'] != null) throw f4Coded('EXPENSE_ALREADY_VOIDED', 409);
    // Tek işlem: iptal + yeni gider; yeni gider reddedilirse iptal de geri alınır.
    final snapshotExpenses = expenses.map((e) => Map<String, dynamic>.of(e)).toList();
    final snapshotAccounts = accounts.map((a) => Map<String, dynamic>.of(a)).toList();
    final snapshotMovements = <int, List<Map<String, dynamic>>>{
      for (final e in movements.entries) e.key: e.value.map((m) => Map<String, dynamic>.of(m)).toList(),
    };
    try {
      old['voided'] = <String, dynamic>{'at': '2026-10-16T09:30:00Z', 'reason': 'Düzeltme', 'period': '2026-10'};
      _addMovement(old['account_id'] as int, 'reversal', old['amount_minor'] as int, '2026-10-16');
      final row = _writeExpense(input.allowDuplicate ? input : ExpenseInput(
        categoryId: input.categoryId,
        supplierId: input.supplierId,
        description: input.description,
        amountMinor: input.amountMinor,
        vatMinor: input.vatMinor,
        expenseDate: input.expenseDate,
        accountId: input.accountId,
        documentKind: input.documentKind,
        documentNo: input.documentNo,
        allowDuplicate: true,
        fund: input.fund,
      ), corrects: expenseId);
      return ExpenseCorrectResult(voided: Expense.fromJson(_expenseJson(old)), expense: Expense.fromJson(_expenseJson(row)));
    } catch (_) {
      expenses
        ..clear()
        ..addAll(snapshotExpenses);
      accounts
        ..clear()
        ..addAll(snapshotAccounts);
      movements
        ..clear()
        ..addAll(snapshotMovements);
      rethrow;
    }
  }

  @override
  Future<ExpenseUploadTicket> createExpenseDocument({
    required String token,
    required int siteCode,
    required int expenseId,
    required String fileName,
    required int size,
    String? contentType,
    required ExpenseAttachmentKind kind,
    required String idempotencyKey,
  }) async {
    await _enter('createExpenseDocument', <String, Object?>{'id': expenseId, 'name': fileName, 'size': size, 'key': idempotencyKey});
    final error = documentError;
    if (error != null) throw error;
    final id = 1000 + uploads;
    return ExpenseUploadTicket.fromJson(<String, dynamic>{
      'document': <String, dynamic>{'id': id, 'status': 'uploading', 'display_name': fileName, 'kind': kind.apiValue, 'size_bytes': 0},
      'upload': <String, dynamic>{
        'method': 'PUT',
        'path': '/manager/sites/$siteCode/finance/expenses/$expenseId/documents/$id/content',
        'content_type': 'application/octet-stream',
        'size': size,
        'max_bytes': 10 * 1024 * 1024,
      },
    });
  }

  @override
  Future<ExpenseAttachment> uploadExpenseDocument({
    required String token,
    required ExpenseUploadTicket ticket,
    required Uint8List bytes,
  }) async {
    await _enter('uploadExpenseDocument', <String, Object?>{'size': bytes.length});
    final error = documentError;
    if (error != null) throw error;
    uploads++;
    final expenseId = int.parse(RegExp(r'expenses/(\d+)/').firstMatch(ticket.path)!.group(1)!);
    final json = <String, dynamic>{
      'id': ticket.document.id,
      'status': 'ready',
      'display_name': ticket.document.displayName,
      'kind': ticket.document.kind.apiValue,
      'size_bytes': bytes.length,
      'mime_type': 'application/pdf',
    };
    (expenseDocuments[expenseId] ??= <Map<String, dynamic>>[]).add(json);
    return ExpenseAttachment.fromJson(json);
  }

  // --- Raporlar ------------------------------------------------------------------------------
  Map<String, dynamic> agingJson = f4AgingJson();
  Map<String, dynamic> incomeExpenseJson = f4IncomeExpenseJson();
  Map<String, dynamic> cashPositionJson = f4CashPositionJson();
  Map<String, dynamic> chartsJson = f4ChartsJson();
  Map<String, dynamic> statementJson = f4StatementJson();
  Map<String, dynamic> boardJson = f4BoardJson();
  Object? reportError;
  F4Gate? reportGate;
  final List<Map<String, Object?>> reportCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> exportCalls = <Map<String, Object?>>[];
  Object? exportError;

  Future<T> _report<T>(String name, Map<String, Object?> args, T Function() build) async {
    await _enter(name);
    reportCalls.add(<String, Object?>{'name': name, ...args});
    final result = build();
    await reportGate?.future;
    final error = reportError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<AgingReport> getAgingReport({
    required String token,
    required int siteCode,
    DateTime? asOf,
    String status = 'all',
    int limit = 200,
    int offset = 0,
    AccountParty? accountParty,
  }) {
    return _report('getAgingReport', <String, Object?>{
      'as_of': asOf == null ? null : _iso(asOf),
      'status': status,
      'limit': limit,
      'offset': offset,
      'account_party': accountParty?.apiValue,
    }, () {
      final all = (agingJson['all_items'] as List?) ?? (agingJson['items'] as List);
      final page = all.skip(offset).take(limit).toList();
      return AgingReport.fromJson(<String, dynamic>{...agingJson, 'items': page, 'total': all.length});
    });
  }

  @override
  Future<IncomeExpenseReport> getIncomeExpenseReport({
    required String token,
    required int siteCode,
    required FinancePeriod from,
    required FinancePeriod to,
  }) {
    return _report('getIncomeExpenseReport', <String, Object?>{'from': from.toApi(), 'to': to.toApi()}, () {
      return IncomeExpenseReport.fromJson(<String, dynamic>{...incomeExpenseJson, 'from': from.toApi(), 'to': to.toApi()});
    });
  }

  @override
  Future<FinanceCharts> getFinanceCharts({required String token, required int siteCode, int months = 12}) {
    return _report('getFinanceCharts', <String, Object?>{'months': months}, () => FinanceCharts.fromJson(chartsJson));
  }

  @override
  Future<CashPositionReport> getCashPositionReport({required String token, required int siteCode, DateTime? asOf}) {
    return _report('getCashPositionReport', <String, Object?>{'as_of': asOf == null ? null : _iso(asOf)}, () => CashPositionReport.fromJson(cashPositionJson));
  }

  @override
  Future<ApartmentStatement> getApartmentStatement({
    required String token,
    required int siteCode,
    required int apartmentId,
    DateTime? from,
    DateTime? to,
    AccountParty? accountParty,
  }) {
    return _report(
      'getApartmentStatement',
      <String, Object?>{
        'apartment_id': apartmentId,
        'from': from == null ? null : _iso(from),
        'to': to == null ? null : _iso(to),
        'account_party': accountParty?.apiValue,
      },
      () => ApartmentStatement.fromJson(statementJson),
    );
  }

  @override
  Future<BoardSummaryReport> getBoardSummary({
    required String token,
    required int siteCode,
    required FinancePeriod from,
    required FinancePeriod to,
    bool includeDebtorList = false,
  }) {
    return _report('getBoardSummary', <String, Object?>{'from': from.toApi(), 'to': to.toApi(), 'debtors': includeDebtorList}, () {
      final json = Map<String, dynamic>.from(boardJson);
      if (!includeDebtorList) json.remove('debtor_list');
      return BoardSummaryReport.fromJson(json);
    });
  }

  @override
  Future<ExportEnvelope> getExport({
    required String token,
    required int siteCode,
    required String kind,
    Map<String, String> query = const <String, String>{},
  }) async {
    await _enter('getExport');
    exportCalls.add(<String, Object?>{'kind': kind, ...query});
    final error = exportError;
    if (error != null) throw error;
    return f4Envelope(kind);
  }

  // --- Gecikme tazminatı ---------------------------------------------------------------------
  Map<String, dynamic> latePreviewJson = f4LatePreviewJson();
  final List<Map<String, dynamic>> lateRuns = <Map<String, dynamic>>[];
  Object? latePreviewError;
  Object? latePostError;
  Object? lateRunsError;
  F4Gate? latePreviewGate;
  F4Gate? latePostGate;
  F4Gate? lateRunsGate;
  bool latePostStaleOnce = false;
  final List<Map<String, Object?>> latePreviewCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> latePostCalls = <Map<String, Object?>>[];
  final Map<String, Map<String, dynamic>> _lateKeys = <String, Map<String, dynamic>>{};
  int lateRunLinesTotal = 0;
  Object? lateLinesError;

  /// Sunucunun yerine getirdiği önizleme: muaf kümesi hesaba katılır (muaf daire satırdan düşer, `waived`e geçer).
  Map<String, dynamic> _latePreviewFor(FinancePeriod? period, List<int> excluded) {
    final json = Map<String, dynamic>.from(latePreviewJson);
    if (period != null) json['period'] = period.toApi();
    final lines = (json['lines'] as List).cast<Map<String, dynamic>>();
    final kept = lines.where((l) => !excluded.contains(l['apartment_id'])).toList();
    final waived = [
      for (final l in lines)
        if (excluded.contains(l['apartment_id']))
          <String, dynamic>{
            'apartment_id': l['apartment_id'],
            'label': l['label'],
            // İP-1A: sunucu muaf dairenin her hesabını ayrı öğe olarak verir (hesap adıyla)
            if (l['account_party'] != null) 'account_party': l['account_party'],
            'computed_minor': l['amount_minor'],
          },
    ];
    json['lines'] = kept;
    json['waived'] = waived;
    json['total_minor'] = kept.fold<int>(0, (a, l) => a + (l['amount_minor'] as int));
    json['apartment_count'] = kept.length;
    // Sunucu: satır yoksa `empty: true` (NOTHING_TO_POST engeli YOK; can_post yalnız diğer engellere bağlı).
    json['empty'] = kept.isEmpty;
    json['preview_hash'] = 'lf-${kept.map((l) => '${l['apartment_id']}:${l['amount_minor']}').join('|')}-${excluded.join(',')}';
    return json;
  }

  @override
  Future<LateFeePreview> previewLateFee({
    required String token,
    required int siteCode,
    FinancePeriod? period,
    List<int> excludedApartmentIds = const <int>[],
  }) async {
    await _enter('previewLateFee');
    latePreviewCalls.add(<String, Object?>{'period': period?.toApi(), 'excluded': excludedApartmentIds});
    final result = LateFeePreview.fromJson(_latePreviewFor(period, excludedApartmentIds));
    await latePreviewGate?.future;
    final error = latePreviewError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<LateFeePostResult> postLateFee({
    required String token,
    required int siteCode,
    required FinancePeriod period,
    List<int> excludedApartmentIds = const <int>[],
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    required String expectedHash,
    required String idempotencyKey,
    bool recordEmpty = false,
  }) async {
    await _enter('postLateFee');
    latePostCalls.add(<String, Object?>{
      'period': period.toApi(),
      'excluded': excludedApartmentIds,
      'total': expectedTotalMinor,
      'count': expectedApartmentCount,
      'hash': expectedHash,
      'key': idempotencyKey,
      'record_empty': recordEmpty,
    });
    await latePostGate?.future;
    final error = latePostError;
    if (error != null) throw error;
    final replay = _lateKeys[idempotencyKey];
    if (replay != null) {
      // Aynı anahtar farklı record_empty ile: sunucu 409 IDEMPOTENCY_CONFLICT.
      if ((replay['empty'] == true) != recordEmpty) throw f4Coded('IDEMPOTENCY_CONFLICT', 409);
      return LateFeePostResult.fromJson(<String, dynamic>{'run': replay, 'entries_count': replay['apartment_count']});
    }
    if (latePostStaleOnce) {
      latePostStaleOnce = false;
      // Araya ödeme girdi: tazminat tutarları değişti.
      final lines = (latePreviewJson['lines'] as List).cast<Map<String, dynamic>>();
      lines.first['amount_minor'] = (lines.first['amount_minor'] as int) + 700;
      final now = _latePreviewFor(period, excludedApartmentIds);
      throw f4Coded('PREVIEW_STALE', 409, payload: <String, dynamic>{
        'total_minor': now['total_minor'],
        'apartment_count': now['apartment_count'],
        'preview_hash': now['preview_hash'],
      });
    }
    final current = _latePreviewFor(period, excludedApartmentIds);
    if (recordEmpty) {
      // Satır çıkan aya record_empty gönderilirse 409 PREVIEW_STALE (önizlemeyi yenile).
      if (current['empty'] != true) {
        throw f4Coded('PREVIEW_STALE', 409, payload: <String, dynamic>{
          'total_minor': current['total_minor'],
          'apartment_count': current['apartment_count'],
          'preview_hash': current['preview_hash'],
        });
      }
      if (current['can_post'] != true) throw f4Coded('LATE_FEE_PERIOD_NOT_CLOSED', 409);
      final marker = <String, dynamic>{
        'id': 40 + lateRuns.length,
        'period': period.toApi(),
        'status': 'active',
        'total_minor': 0,
        'net_total_minor': 0,
        'apartment_count': 0,
        'waived_count': excludedApartmentIds.length,
        'empty': true,
        'params': current['settings'],
        'posted_at': '2026-10-16T09:00:00Z',
        'posted_by_name': 'Site Yöneticisi',
      };
      lateRuns.add(marker);
      _lateKeys[idempotencyKey] = marker;
      return LateFeePostResult.fromJson(<String, dynamic>{'run': marker, 'entries_count': 0});
    }
    if (current['empty'] == true) throw f4Coded('NOTHING_TO_POST', 409);
    if (current['can_post'] != true) {
      final blockers = (current['blockers'] as List).cast<String>();
      throw f4Coded(blockers.isEmpty ? 'LATE_FEE_PERIOD_NOT_CLOSED' : blockers.first, 409);
    }
    if (current['preview_hash'] != expectedHash || current['total_minor'] != expectedTotalMinor || current['apartment_count'] != expectedApartmentCount) {
      throw f4Coded('PREVIEW_STALE', 409, payload: <String, dynamic>{
        'total_minor': current['total_minor'],
        'apartment_count': current['apartment_count'],
        'preview_hash': current['preview_hash'],
      });
    }
    final run = <String, dynamic>{
      'id': 40 + lateRuns.length,
      'period': period.toApi(),
      'status': 'active',
      'total_minor': current['total_minor'],
      'net_total_minor': current['total_minor'],
      'apartment_count': current['apartment_count'],
      'waived_count': excludedApartmentIds.length,
      'params': current['settings'],
      'posted_at': '2026-10-16T09:00:00Z',
      'posted_by_name': 'Site Yöneticisi',
    };
    lateRuns.add(run);
    _lateKeys[idempotencyKey] = run;
    return LateFeePostResult.fromJson(<String, dynamic>{'run': run, 'entries_count': run['apartment_count']});
  }

  @override
  Future<LateFeeRunPage> listLateFeeRuns({required String token, required int siteCode, int limit = 24, int offset = 0}) async {
    await _enter('listLateFeeRuns');
    final rows = List<Map<String, dynamic>>.of(lateRuns)..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    Map<String, dynamic>? voidable;
    for (final r in rows) {
      if (r['status'] == 'active') {
        voidable = r;
        break;
      }
    }
    final next = rows.isEmpty
        ? '2026-09'
        : FinancePeriod.tryParse(rows.first['period'])!.next.toApi();
    final result = LateFeeRunPage.fromJson(<String, dynamic>{
      'items': rows.skip(offset).take(limit).toList(),
      'total': rows.length,
      'next_period': next,
      'voidable_run_id': voidable?['id'],
    });
    await lateRunsGate?.future;
    final error = lateRunsError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<LateFeeLinePage> listLateFeeRunLines({
    required String token,
    required int siteCode,
    required int runId,
    int limit = 50,
    int offset = 0,
  }) async {
    await _enter('listLateFeeRunLines');
    final lines = (latePreviewJson['lines'] as List).cast<Map<String, dynamic>>();
    final result = LateFeeLinePage.fromJson(<String, dynamic>{'items': lines.skip(offset).take(limit).toList(), 'total': lines.length});
    final error = lateLinesError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<LateFeeVoidResult> voidLateFeeRun({
    required String token,
    required int siteCode,
    required int runId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _enter('voidLateFeeRun', <String, Object?>{'run_id': runId, 'reason': reason, 'key': idempotencyKey});
    await latePostGate?.future;
    final error = latePostError;
    if (error != null) throw error;
    final run = lateRuns.firstWhere((r) => r['id'] == runId, orElse: () => throw f4Coded('LATE_FEE_RUN_NOT_FOUND', 404));
    final rows = List<Map<String, dynamic>>.of(lateRuns)..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final last = rows.firstWhere((r) => r['status'] == 'active', orElse: () => <String, dynamic>{});
    if (run['status'] != 'active' || last['id'] != runId) throw f4Coded('LATE_FEE_RUN_NOT_VOIDABLE', 409);
    run['status'] = 'voided';
    run['voided_at'] = '2026-10-16T10:00:00Z';
    return LateFeeVoidResult.fromJson(<String, dynamic>{
      'run': run,
      'reversed_count': run['apartment_count'],
      'reversed_total_minor': run['total_minor'],
    });
  }

  // --- Sakin: tazminat açıklaması ve ekstre --------------------------------------------------
  Object? myLateFeeError;
  F4Gate? myLateFeeGate;
  final List<int> myLateFeeCalls = <int>[];
  Map<String, dynamic> myLateFeeJson = <String, dynamic>{
    'period': '2026-09',
    'rate_bp': 500,
    'method': 'daily_30',
    'grace_days': 0,
    'amount_minor': 10000,
    'base_day_minor': 1200000,
    'segments': <Map<String, dynamic>>[
      <String, dynamic>{'from': '2026-09-01', 'to': '2026-09-10', 'overdue_minor': 50000},
      <String, dynamic>{'from': '2026-09-11', 'to': '2026-09-30', 'overdue_minor': 100000},
    ],
  };

  @override
  Future<LateFeeExplanation> getMyLateFeeExplanation({required String token, required int entryId}) async {
    await _enter('getMyLateFeeExplanation');
    myLateFeeCalls.add(entryId);
    final result = LateFeeExplanation.fromJson(myLateFeeJson);
    await myLateFeeGate?.future;
    final error = myLateFeeError;
    if (error != null) throw error;
    return result;
  }

  Object? myStatementError;
  F4Gate? myStatementGate;
  final List<Map<String, Object?>> myStatementCalls = <Map<String, Object?>>[];

  @override
  Future<ApartmentStatement> getMyStatement({
    required String token,
    required int apartmentId,
    DateTime? from,
    DateTime? to,
    AccountParty? accountParty,
  }) async {
    await _enter('getMyStatement');
    myStatementCalls.add(<String, Object?>{
      'apartment_id': apartmentId,
      'from': from == null ? null : _iso(from),
      'to': to == null ? null : _iso(to),
      'account_party': accountParty?.apiValue,
    });
    final result = ApartmentStatement.fromJson(statementJson);
    await myStatementGate?.future;
    final error = myStatementError;
    if (error != null) throw error;
    return result;
  }

  // --- Hatırlatma ----------------------------------------------------------------------------
  Map<String, dynamic> reminderPreviewJson = f4ReminderPreviewJson();
  final List<Map<String, dynamic>> reminderRuns = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> reminderExclusions = <Map<String, dynamic>>[];
  Object? reminderPreviewError;
  Object? reminderSendError;
  Object? reminderRunsError;
  Object? reminderExclusionError;
  F4Gate? reminderPreviewGate;
  F4Gate? reminderSendGate;
  bool reminderSendStaleOnce = false;
  bool reminderSendLoseResponse = false;
  final List<Map<String, Object?>> reminderSends = <Map<String, Object?>>[];
  final Map<String, Map<String, dynamic>> _reminderKeys = <String, Map<String, dynamic>>{};

  @override
  Future<List<ReminderExclusion>> listReminderExclusions({required String token, required int siteCode}) async {
    await _enter('listReminderExclusions');
    final result = [for (final e in reminderExclusions) ReminderExclusion.fromJson(e)];
    final error = reminderExclusionError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<void> addReminderExclusion({
    required String token,
    required int siteCode,
    required int apartmentId,
    String? reason,
  }) async {
    await _enter('addReminderExclusion', <String, Object?>{'apartment_id': apartmentId, 'reason': reason});
    final error = reminderExclusionError;
    if (error != null) throw error;
    reminderExclusions.removeWhere((e) => e['apartment_id'] == apartmentId);
    reminderExclusions.add(<String, dynamic>{
      'apartment_id': apartmentId,
      'label': 'Daire $apartmentId',
      'block_name': null,
      'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });
  }

  @override
  Future<void> removeReminderExclusion({required String token, required int siteCode, required int apartmentId}) async {
    await _enter('removeReminderExclusion', <String, Object?>{'apartment_id': apartmentId});
    final error = reminderExclusionError;
    if (error != null) throw error;
    reminderExclusions.removeWhere((e) => e['apartment_id'] == apartmentId);
  }

  @override
  Future<ReminderPreview> previewReminders({required String token, required int siteCode, required ReminderTone tone}) async {
    await _enter('previewReminders', <String, Object?>{'tone': tone.apiValue});
    final result = ReminderPreview.fromJson(<String, dynamic>{...reminderPreviewJson, 'preview_hash': '${reminderPreviewJson['preview_hash']}-${tone.apiValue}'});
    await reminderPreviewGate?.future;
    final error = reminderPreviewError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<ReminderSendResult> sendReminders({
    required String token,
    required int siteCode,
    required ReminderTone tone,
    String? note,
    required String expectedHash,
    required int expectedApartmentCount,
    required int expectedPersonCount,
    required String idempotencyKey,
  }) async {
    await _enter('sendReminders');
    reminderSends.add(<String, Object?>{
      'tone': tone.apiValue,
      'note': note,
      'hash': expectedHash,
      'apartments': expectedApartmentCount,
      'people': expectedPersonCount,
      'key': idempotencyKey,
    });
    await reminderSendGate?.future;
    final error = reminderSendError;
    if (error != null) throw error;
    final replay = _reminderKeys[idempotencyKey];
    if (replay != null) return ReminderSendResult(run: ReminderRun.fromJson(replay), created: false);
    if (reminderSendStaleOnce) {
      reminderSendStaleOnce = false;
      reminderPreviewJson = <String, dynamic>{
        ...reminderPreviewJson,
        'person_count': (reminderPreviewJson['person_count'] as int) + 1,
        'preview_hash': '${reminderPreviewJson['preview_hash']}x',
      };
      throw f4Coded('PREVIEW_STALE', 409);
    }
    final run = <String, dynamic>{
      'id': 70 + reminderRuns.length,
      'status': 'active',
      'tone': tone.apiValue,
      'note': note,
      'apartment_count': expectedApartmentCount,
      'person_count': expectedPersonCount,
      'with_amount_count': reminderPreviewJson['with_amount_count'],
      'stats': <String, dynamic>{'pending': expectedPersonCount},
      'created_at': '2026-10-16T09:00:00Z',
    };
    reminderRuns.add(run);
    _reminderKeys[idempotencyKey] = run;
    if (reminderSendLoseResponse) {
      reminderSendLoseResponse = false;
      // Sunucu işlemi yaptı ama yanıt istemciye ulaşmadı (ağ koptu).
      throw ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
    }
    return ReminderSendResult(run: ReminderRun.fromJson(run), created: true);
  }

  @override
  Future<ReminderRunPage> listReminderRuns({required String token, required int siteCode, int limit = 20, int offset = 0}) async {
    await _enter('listReminderRuns');
    final rows = List<Map<String, dynamic>>.of(reminderRuns)..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final result = ReminderRunPage.fromJson(<String, dynamic>{'items': rows.skip(offset).take(limit).toList(), 'total': rows.length});
    final error = reminderRunsError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<ReminderRun> cancelReminderRun({
    required String token,
    required int siteCode,
    required int runId,
    String? idempotencyKey,
  }) async {
    await _enter('cancelReminderRun', <String, Object?>{'run_id': runId, 'key': idempotencyKey});
    final error = reminderRunsError;
    if (error != null) throw error;
    final run = reminderRuns.firstWhere((r) => r['id'] == runId, orElse: () => throw f4Coded('REMINDER_RUN_NOT_FOUND', 404));
    if (run['status'] == 'cancelled') throw f4Coded('REMINDER_RUN_NOT_CANCELLABLE', 409);
    run['status'] = 'cancelled';
    final stats = Map<String, dynamic>.from(run['stats'] as Map);
    stats['cancelled'] = stats['pending'];
    stats['pending'] = 0;
    run['stats'] = stats;
    return ReminderRun.fromJson(run);
  }

  // --- Kiracı borcunun malike devri (K1) ve gecikmede öneri (K17) ----------------------------
  // Sunucuyu taklit eder (docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri"): aday listesi, daire başına önizleme + geçmiş; devir listeden düşürür,
  // geri alma geçmişi işaretler; önizleme özeti bayatsa 409 LIABILITY_TRANSFER_CHANGED.
  Map<String, dynamic> liabilityCandidatesJson = <String, dynamic>{
    'items': <Map<String, dynamic>>[],
    'count': 0,
    'total_minor': 0,
    'truncated': false,
  };
  Object? liabilityCandidatesError;
  F4Gate? liabilityCandidatesGate;
  final Map<int, Map<String, dynamic>> liabilityPreviews = <int, Map<String, dynamic>>{};
  final Map<int, List<Map<String, dynamic>>> liabilityHistory = <int, List<Map<String, dynamic>>>{};
  Object? liabilityPreviewError;
  Object? liabilityCreateError;
  Object? liabilityReverseError;
  int _liabilityNextId = 1;

  @override
  Future<LiabilityCandidatePage> listLiabilityCandidates({required String token, required int siteCode}) async {
    await _enter('listLiabilityCandidates');
    final result = LiabilityCandidatePage.fromJson(liabilityCandidatesJson);
    await liabilityCandidatesGate?.future;
    final error = liabilityCandidatesError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<LiabilityPreview> previewLiabilityTransfer({required String token, required int siteCode, required int apartmentId}) async {
    await _enter('previewLiabilityTransfer');
    final error = liabilityPreviewError;
    if (error != null) throw error;
    return LiabilityPreview.fromJson(
      liabilityPreviews[apartmentId] ??
          <String, dynamic>{
            'apartment_id': apartmentId,
            'has_owner': true,
            'can_transfer': false,
            'items': <dynamic>[],
            'excluded_late_fee': <dynamic>[],
            'item_count': 0,
            'total_minor': 0,
            'preview_hash': 'a' * 64,
            'tenant_balance_minor': 0,
            'owner_balance_minor': 0,
          },
    );
  }

  @override
  Future<List<LiabilityTransfer>> listLiabilityTransfers({required String token, required int siteCode, required int apartmentId}) async {
    await _enter('listLiabilityTransfers');
    return <LiabilityTransfer>[for (final row in liabilityHistory[apartmentId] ?? const <Map<String, dynamic>>[]) LiabilityTransfer.fromJson(row)];
  }

  @override
  Future<LiabilityTransferResult> createLiabilityTransfer({
    required String token,
    required int siteCode,
    required int apartmentId,
    required int expectedTotalMinor,
    required String expectedHash,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _enter('createLiabilityTransfer', <String, Object?>{
      'apartment_id': apartmentId,
      'expected_total_minor': expectedTotalMinor,
      'expected_hash': expectedHash,
      'reason': reason,
      'key': idempotencyKey,
    });
    final error = liabilityCreateError;
    if (error != null) {
      liabilityCreateError = null;
      throw error;
    }
    final preview = liabilityPreviews[apartmentId];
    if (preview == null || preview['preview_hash'] != expectedHash || preview['total_minor'] != expectedTotalMinor) {
      throw ApiException(
        'Kiracı borçları önizlemeden sonra değişti. Önizlemeyi yenileyip tekrar inceleyin.',
        statusCode: 409,
        code: 'LIABILITY_TRANSFER_CHANGED',
      );
    }
    final id = _liabilityNextId++;
    final row = <String, dynamic>{
      'id': id,
      'apartment_id': apartmentId,
      'kind': 'transfer',
      'from_party': 'tenant',
      'to_party': 'owner',
      'total_minor': expectedTotalMinor,
      'item_count': (preview['items'] as List).length,
      'reason': reason,
      'reverses_transfer_id': null,
      'reversed_by_transfer_id': null,
      'created_by_name': 'Yönetici',
      'created_at': '2026-10-29T09:00:00.000Z',
      'reversible': true,
    };
    liabilityHistory.putIfAbsent(apartmentId, () => <Map<String, dynamic>>[]).insert(0, row);
    // devirden sonra daire öneri listesinden ve önizlemeden düşer
    liabilityPreviews[apartmentId] = <String, dynamic>{
      ...preview,
      'items': <dynamic>[],
      'item_count': 0,
      'total_minor': 0,
      'can_transfer': false,
      'preview_hash': 'b' * 64,
      'tenant_balance_minor': 0,
      'owner_balance_minor': expectedTotalMinor,
    };
    final candidates = (liabilityCandidatesJson['items'] as List).cast<Map<String, dynamic>>().where((c) => c['apartment_id'] != apartmentId).toList();
    liabilityCandidatesJson = <String, dynamic>{
      'items': candidates,
      'count': candidates.length,
      'total_minor': candidates.fold<int>(0, (sum, c) => sum + (c['total_minor'] as int)),
      'truncated': false,
    };
    return LiabilityTransferResult.fromJson(
      <String, dynamic>{'transfer': row, 'tenant_balance_minor': 0, 'owner_balance_minor': expectedTotalMinor},
      replayed: false,
    );
  }

  @override
  Future<LiabilityTransferResult> reverseLiabilityTransfer({
    required String token,
    required int siteCode,
    required int transferId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _enter('reverseLiabilityTransfer', <String, Object?>{'transfer_id': transferId, 'reason': reason, 'key': idempotencyKey});
    final error = liabilityReverseError;
    if (error != null) {
      liabilityReverseError = null;
      throw error;
    }
    for (final entry in liabilityHistory.entries) {
      for (final row in entry.value) {
        if (row['id'] != transferId) continue;
        final reverseId = _liabilityNextId++;
        row['reversed_by_transfer_id'] = reverseId;
        row['reversible'] = false;
        final reversal = <String, dynamic>{
          ...row,
          'id': reverseId,
          'kind': 'reversal',
          'from_party': 'owner',
          'to_party': 'tenant',
          'reason': reason,
          'reverses_transfer_id': transferId,
          'reversed_by_transfer_id': null,
          'reversible': false,
        };
        entry.value.insert(0, reversal);
        return LiabilityTransferResult.fromJson(
          <String, dynamic>{'transfer': reversal, 'tenant_balance_minor': row['total_minor'], 'owner_balance_minor': 0},
          replayed: false,
        );
      }
    }
    throw ApiException('Devir kaydı bulunamadı.', statusCode: 404, code: 'LIABILITY_TRANSFER_NOT_FOUND');
  }
}

/// Test için servis kurar ve [auth]'a kaydeder; sahte API'yi döndürür.
FakeFinance4bApi registerFakeFinance4b(AuthService auth, {FakeFinance4bApi? api}) {
  final fake = api ?? FakeFinance4bApi();
  Finance4bService.register(auth, Finance4bService(authService: auth, api: fake, tokenProvider: () => 'test-token'));
  return fake;
}

/// ExportEnvelope üretici (rapor testleri).
ExportEnvelope f4Envelope(String kind) => ExportEnvelope.fromJson(<String, dynamic>{
  'kind': kind,
  'spec_version': 1,
  'generated_at': '2026-10-16T09:00:00Z',
  'filename_base': kind,
  'columns': <Map<String, dynamic>>[
    <String, dynamic>{'key': 'a', 'label': 'A', 'type': 'text'},
  ],
  'rows': <List<Object?>>[
    <Object?>['x'],
  ],
  'row_count': 1,
});

// --- Rapor yanıtı üreticileri (sunucunun JSON biçiminde) ---------------------------------------

Map<String, dynamic> _f4Buckets(Map<String, int> values) => <String, dynamic>{
  'not_due_minor': values['not_due'] ?? 0,
  'd0_30_minor': values['d0_30'] ?? 0,
  'd31_60_minor': values['d31_60'] ?? 0,
  'd61_90_minor': values['d61_90'] ?? 0,
  'd91_180_minor': values['d91_180'] ?? 0,
  'd181_365_minor': values['d181_365'] ?? 0,
  'd366_plus_minor': values['d366_plus'] ?? 0,
};

Map<String, dynamic> f4AgingJson({int items = 2, String? closedThrough = '2026-09'}) {
  final rows = <Map<String, dynamic>>[
    for (var i = 1; i <= items; i++)
      <String, dynamic>{
        'apartment_id': 300 + i,
        'label': 'A Blok - $i',
        'block_name': 'A Blok',
        'payer_party': 'owner',
        'owner_name': 'Malik $i',
        'tenant_name': null,
        ..._f4Buckets(<String, int>{'d0_30': 50000 * i, 'd31_60': 25000}),
        'credit_minor': 0,
        'late_fee_outstanding_minor': 1000,
        'total_overdue_minor': 50000 * i + 25000,
      },
  ];
  var d030 = 0;
  var d3160 = 0;
  var total = 0;
  for (final r in rows) {
    d030 += r['d0_30_minor'] as int;
    d3160 += r['d31_60_minor'] as int;
    total += r['total_overdue_minor'] as int;
  }
  return <String, dynamic>{
    'site': <String, dynamic>{'name': 'Gül Sitesi'},
    'generated_at': '2026-10-16T09:00:00Z',
    'closed_through': closedThrough,
    'currency': 'TRY',
    'as_of': '2026-10-16',
    'totals': <String, dynamic>{
      ..._f4Buckets(<String, int>{'d0_30': d030, 'd31_60': d3160}),
      'credit_minor': 5000,
      'late_fee_outstanding_minor': 1000 * items,
      'total_overdue_minor': total,
    },
    'items': rows,
    'total': rows.length,
  };
}

Map<String, dynamic> f4IncomeExpenseJson({String? closedThrough = '2026-09'}) => <String, dynamic>{
  'site': <String, dynamic>{'name': 'Gül Sitesi'},
  'generated_at': '2026-10-16T09:00:00Z',
  'closed_through': closedThrough,
  'months': <Map<String, dynamic>>[
    <String, dynamic>{
      'period': '2026-09',
      'charged_minor': 1000000,
      'late_fee_minor': 20000,
      'collected_minor': 800000,
      'expense_minor': 300000,
      'net_cash_minor': 500000,
      'collection_rate_bp': 8000,
      'expense_by_category': <Map<String, dynamic>>[
        <String, dynamic>{'category_name': 'Elektrik', 'total_minor': 200000},
        <String, dynamic>{'category_name': 'Asansör bakım', 'total_minor': 100000},
      ],
    },
    <String, dynamic>{
      'period': '2026-10',
      'charged_minor': 0,
      'late_fee_minor': 0,
      'collected_minor': 50000,
      'expense_minor': 0,
      'net_cash_minor': 50000,
      'collection_rate_bp': null,
      'expense_by_category': <Map<String, dynamic>>[],
    },
  ],
};

/// Finans > Grafikler yanıtı: 12 ay (2025-11 .. 2026-10). [empty] true: hiç kayıt yok (hesap yok, borç yok).
Map<String, dynamic> f4ChartsJson({bool empty = false}) {
  const periods = <String>[
    '2025-11', '2025-12', '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10', //
  ];
  return <String, dynamic>{
    'site': <String, dynamic>{'name': 'Gül Sitesi'},
    'generated_at': '2026-10-21T09:00:00Z',
    'closed_through': '2026-09',
    'currency': 'TRY',
    'from': periods.first,
    'to': periods.last,
    'months': <Map<String, dynamic>>[
      for (final (i, period) in periods.indexed)
        <String, dynamic>{
          'period': period,
          'charged_minor': empty ? 0 : (i < 11 ? 1000000 + i * 10000 : 0),
          'late_fee_minor': empty ? 0 : (i == 9 ? 20000 : 0),
          'collected_minor': empty ? 0 : (i < 11 ? 800000 + i * 20000 : 50000),
          'expense_minor': empty ? 0 : (i % 3 == 0 ? 300000 : 150000),
          'collection_rate_bp': empty || i == 11 ? null : 8000 + i * 100,
          'cash_balance_minor': empty || i < 2 ? null : 1000000 + i * 100000,
          'cash_account_count': empty || i < 2 ? 0 : 2,
        },
    ],
    'totals': <String, dynamic>{
      'charged_minor': empty ? 0 : 11550000,
      'late_fee_minor': empty ? 0 : 20000,
      'collected_minor': empty ? 0 : 9950000,
      'expense_minor': empty ? 0 : 2400000,
      'collection_rate_bp': empty ? null : 8600,
    },
    'expense_by_category': empty
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            <String, dynamic>{'category_name': 'Elektrik', 'total_minor': 900000},
            <String, dynamic>{'category_name': 'Asansör bakım', 'total_minor': 700000},
            <String, dynamic>{'category_name': 'Temizlik', 'total_minor': 500000},
            <String, dynamic>{'category_name': 'Su', 'total_minor': 200000},
            <String, dynamic>{'category_name': 'Bahçe', 'total_minor': 100000},
            <String, dynamic>{'category_name': 'Sigorta', 'total_minor': 60000},
            <String, dynamic>{'category_name': 'Küçük onarım', 'total_minor': 30000},
            <String, dynamic>{'category_name': 'Kırtasiye', 'total_minor': 10000},
          ],
    'aging': <String, dynamic>{
      'as_of': '2026-10-21',
      'd0_30_minor': empty ? 0 : 400000,
      'd31_60_minor': empty ? 0 : 250000,
      'd61_90_minor': empty ? 0 : 100000,
      'd91_plus_minor': empty ? 0 : 50000,
      'total_overdue_minor': empty ? 0 : 800000,
      'debtor_count': empty ? 0 : 6,
    },
  };
}

Map<String, dynamic> f4CashPositionJson({int unassignedCount = 0}) => <String, dynamic>{
  'site': <String, dynamic>{'name': 'Gül Sitesi'},
  'generated_at': '2026-10-16T09:00:00Z',
  'closed_through': '2026-09',
  'as_of': '2026-10-16',
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'account_id': 1,
      'name': 'Nakit Kasa',
      'kind': 'cash',
      'opening_minor': 100000,
      'collections_minor': 400000,
      'expenses_minor': -150000,
      'transfers_in_minor': 0,
      'transfers_out_minor': -100000,
      'adjustments_minor': -500,
      'reversals_minor': 0,
      'balance_minor': 249500,
      'last_reconciliation': <String, dynamic>{'as_of_date': '2026-10-01', 'difference_minor': -500},
    },
  ],
  'totals': <String, dynamic>{'balance_minor': 249500},
  'unassigned_payments': <String, dynamic>{'count': unassignedCount, 'total_minor': unassignedCount * 50000},
};

Map<String, dynamic> f4StatementJson({int rows = 3}) {
  var running = 0;
  final items = <Map<String, dynamic>>[];
  for (var i = 0; i < rows; i++) {
    final payment = i % 3 == 2;
    final amount = payment ? -50000 : 90000;
    running += amount;
    items.add(<String, dynamic>{
      'id': i + 1,
      'kind': payment ? 'payment' : 'charge',
      'amount_minor': amount,
      'entry_date': '2026-0${1 + i % 9}-01',
      'definition_name': payment ? null : 'Aylık aidat',
      'method': payment ? 'cash' : null,
      'running_balance_minor': running,
    });
  }
  return <String, dynamic>{
    'site': <String, dynamic>{'name': 'Gül Sitesi'},
    'generated_at': '2026-10-16T09:00:00Z',
    'closed_through': '2026-09',
    'apartment': <String, dynamic>{'id': 301, 'label': 'A Blok - 5', 'block_name': 'A Blok', 'responsible_party': 'owner'},
    'from': '2026-01-01',
    'to': '2026-10-16',
    'opening_balance_minor': 0,
    'closing_balance_minor': running,
    'items': items,
    'totals': <String, dynamic>{'charged_minor': 90000 * (rows - rows ~/ 3), 'late_fee_minor': 0, 'paid_minor': 50000 * (rows ~/ 3), 'reversed_minor': 0},
    'overdue_minor': running > 0 ? running : 0,
  };
}

Map<String, dynamic> f4BoardJson() => <String, dynamic>{
  'site': <String, dynamic>{'name': 'Gül Sitesi'},
  'generated_at': '2026-10-16T09:00:00Z',
  'closed_through': '2026-09',
  'from': '2026-01',
  'to': '2026-10',
  'collection': <String, dynamic>{
    'charged_minor': 10000000,
    'late_fee_minor': 100000,
    'collected_minor': 9000000,
    'collection_rate_bp': 9000,
  },
  'receivables': <String, dynamic>{
    'total_overdue_minor': 1100000,
    'debtor_count': 7,
    'debtor_ratio_bp': 1750,
    'aging': <Map<String, dynamic>>[
      <String, dynamic>{'bucket': 'not_due', 'count': 3, 'total_minor': 400000},
      <String, dynamic>{'bucket': 'd0_30', 'count': 5, 'total_minor': 600000},
      <String, dynamic>{'bucket': 'd31_60', 'count': 2, 'total_minor': 500000},
    ],
  },
  'expenses': <String, dynamic>{
    'total_minor': 3000000,
    'by_category': <Map<String, dynamic>>[
      <String, dynamic>{'category_name': 'Elektrik', 'total_minor': 2000000},
    ],
    'top_items': <Map<String, dynamic>>[
      <String, dynamic>{'category_name': 'Elektrik', 'expense_date': '2026-03-05', 'amount_minor': 500000},
    ],
  },
  'cash': <String, dynamic>{
    'accounts': <Map<String, dynamic>>[
      // Sunucunun kurul özeti hesap satırı (finance_reports.js): yalnız bu alanlar (hareket kırılımı YOK).
      <String, dynamic>{
        'id': 1,
        'name': 'Nakit Kasa',
        'kind': 'cash',
        'balance_minor': 249500,
        'last_reconciliation': <String, dynamic>{'as_of_date': '2026-09-30', 'difference_minor': -2500},
      },
    ],
    'total_balance_minor': 249500,
    'unassigned_payments': <String, dynamic>{'count': 2, 'total_minor': 100000},
  },
  'late_fee': <String, dynamic>{'total_minor': 100000, 'waived_count': 1},
  'reminders': <String, dynamic>{'sent_count': 12},
  'warnings': <Map<String, dynamic>>[
    <String, dynamic>{'code': 'UNASSIGNED_PAYMENTS'},
  ],
  'debtor_list': <Map<String, dynamic>>[
    <String, dynamic>{'label': 'A Blok - 5', 'total_overdue_minor': 150000},
  ],
};

// --- Gecikme tazminatı / hatırlatma yanıt üreticileri -----------------------------------------

Map<String, dynamic> f4LatePreviewJson({bool canPost = true, List<String> blockers = const <String>[]}) => <String, dynamic>{
  'period': '2026-09',
  'expected_period': '2026-09',
  'window': <String, dynamic>{'from': '2026-09-01', 'to': '2026-09-30', 'days': 30},
  'settings': <String, dynamic>{'rate_bp': 500, 'method': 'daily_30', 'grace_days': 0, 'settings_version': 2},
  'total_minor': 12345,
  'apartment_count': 2,
  'lines': <Map<String, dynamic>>[
    <String, dynamic>{
      'apartment_id': 301,
      'label': 'A Blok - 5',
      'block_name': 'A Blok',
      'payer_party': 'owner',
      'amount_minor': 10000,
      'base_day_minor': 1200000,
      'peak_overdue_minor': 50000,
    },
    <String, dynamic>{
      'apartment_id': 302,
      'label': 'A Blok - 6',
      'block_name': 'A Blok',
      'payer_party': 'tenant',
      'amount_minor': 2345,
      'base_day_minor': 281400,
      'peak_overdue_minor': 20000,
    },
  ],
  'waived': <Map<String, dynamic>>[],
  'inactive_skipped': <Map<String, dynamic>>[],
  'zero_amount_count': 0,
  'preview_hash': 'lf-base',
  'can_post': canPost,
  'blockers': blockers,
};

Map<String, dynamic> f4ReminderPreviewJson({int people = 5, bool smtp = true}) => <String, dynamic>{
  'apartment_count': 4,
  'person_count': people,
  'with_amount_count': 3,
  'without_amount_count': people - 3,
  'no_address_count': 1,
  'skipped_pref_count': 0,
  'duplicate_count': 0,
  'capped_count': 0,
  'total_overdue_minor': 456700,
  'excluded': <String, dynamic>{'amount': 2, 'days': 1, 'interval': 0, 'consecutive': 0, 'exclusion': 1, 'no_recipient': 0},
  'hand_follow_up_count': 2,
  'hand_follow_up_apartments': <String>['A Blok - 7', 'B Blok - 1'],
  'sample_apartments': <String>['A Blok - 5', 'A Blok - 6'],
  'smtp_configured': smtp,
  'preview_hash': 'rm-base',
  'blockers': <String>[],
};
