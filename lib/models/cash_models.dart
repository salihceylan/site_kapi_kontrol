import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';

/// Kasa / banka hesapları, hareketler, aktarım, mutabakat ve toplu eşleme modelleri (Platform Faz 4b, Ö4).
///
/// Hesap bakiyesi YALNIZ hareket toplamıdır (sunucuda tek doğruluk kaynağı); istemci bakiye HESAPLAMAZ, sunucunun
/// verdiği `balance_minor` gösterilir. Tutarlar KURUŞ, hareket tutarı İŞARETLİDİR (+ giriş, - çıkış).

enum CashAccountKind {
  cash('cash', 'Kasa'),
  bank('bank', 'Banka'),
  unknown('', 'Hesap');

  const CashAccountKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CashAccountKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind != unknown && kind.apiValue == normalized) return kind;
      }
    }
    return unknown;
  }
}

/// Son mutabakat özeti (hesap kartında).
@immutable
class LastReconciliation {
  const LastReconciliation({this.asOfDate, required this.differenceMinor, this.adjusted});

  final DateTime? asOfDate;

  /// ekstre - hesaplanan; 0 = tutuyor.
  final int differenceMinor;

  /// Fark mutabakat anında düzeltme hareketiyle giderildi mi? Sunucu hesap listesinde bu alanı göndermeyebilir (null =
  /// bilinmiyor: fark "açık" varsayılır, uyarı gösterilir); rapor uçlarında gelir.
  final bool? adjusted;

  /// Giderilmemiş fark var mı (uyarı rengiyle gösterilir)?
  bool get hasOpenDifference => differenceMinor != 0 && adjusted != true;

  static LastReconciliation? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return LastReconciliation(
      asOfDate: f4Date(map['as_of_date']),
      differenceMinor: f4Minor(map, 'difference_minor'),
      adjusted: f4BoolOrNull(map['adjusted']),
    );
  }
}

/// Kasa / banka hesabı (`GET accounts` -> `items[]`).
@immutable
class CashAccount {
  const CashAccount({
    required this.id,
    this.name = '',
    this.kind = CashAccountKind.cash,
    this.note,
    this.openingBalanceMinor = 0,
    this.openingDate,
    required this.balanceMinor,
    this.isActive = true,
    this.sortOrder = 0,
    this.lastReconciliation,
    this.negativeBalance = false,
  });

  final int id;
  final String name;
  final CashAccountKind kind;
  final String? note;
  final int openingBalanceMinor;
  final DateTime? openingDate;
  final int balanceMinor;
  final bool isActive;
  final int sortOrder;
  final LastReconciliation? lastReconciliation;

  /// Sunucu `negative_balance: true` dedi ya da bakiye negatif: UYARI (engellenmez; veri eksik olabilir).
  final bool negativeBalance;

  bool get isNegative => negativeBalance || balanceMinor < 0;

  factory CashAccount.fromJson(Map<String, dynamic> json) => CashAccount(
    id: f4Int(json['id']),
    name: f4Str(json['name']),
    kind: CashAccountKind.fromApi(json['kind']),
    note: f4Text(json['note']),
    openingBalanceMinor: f4MinorOrNull(json, 'opening_balance_minor') ?? 0,
    openingDate: f4Date(json['opening_date']),
    balanceMinor: f4Minor(json, 'balance_minor'),
    isActive: f4Bool(json['is_active'], fallback: true),
    sortOrder: f4Int(json['sort_order']),
    lastReconciliation: LastReconciliation.tryParse(json['last_reconciliation']),
    negativeBalance: f4Bool(json['negative_balance']),
  );
}

/// Hesaba eşlenmemiş tahsilatlar (`unassigned_payments`).
@immutable
class UnassignedPayments {
  const UnassignedPayments({this.count = 0, this.totalMinor = 0});

  final int count;
  final int totalMinor;

  bool get any => count > 0;

  factory UnassignedPayments.fromJson(Map<String, dynamic> json) =>
      UnassignedPayments(count: f4Int(json['count']), totalMinor: f4MinorOrNull(json, 'total_minor') ?? 0);
}

/// `GET accounts`.
@immutable
class CashOverview {
  const CashOverview({
    this.items = const <CashAccount>[],
    required this.totalBalanceMinor,
    this.unassigned = const UnassignedPayments(),
  });

  final List<CashAccount> items;
  final int totalBalanceMinor;
  final UnassignedPayments unassigned;

  List<CashAccount> get activeAccounts => items.where((a) => a.isActive).toList();

  factory CashOverview.fromJson(Map<String, dynamic> json) => CashOverview(
    items: f4List(json['items'], CashAccount.fromJson),
    totalBalanceMinor: f4Minor(json, 'total_balance_minor'),
    unassigned: UnassignedPayments.fromJson(f4Map(json['unassigned_payments'])),
  );
}

/// Düzeltme hareketi nedenleri.
enum AdjustmentReason {
  bankFee('bank_fee', 'Banka masrafı'),
  bankInterest('bank_interest', 'Banka faizi'),
  cashCount('cash_count', 'Sayım farkı'),
  other('other', 'Diğer');

  const AdjustmentReason(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AdjustmentReason? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final reason in values) {
      if (reason.apiValue == normalized) return reason;
    }
    return null;
  }
}

enum MovementKind {
  opening('opening', 'Açılış'),
  collection('collection', 'Tahsilat'),
  expense('expense', 'Gider'),
  transferOut('transfer_out', 'Aktarım (çıkış)'),
  transferIn('transfer_in', 'Aktarım (giriş)'),
  adjustment('adjustment', 'Düzeltme'),
  reversal('reversal', 'Ters kayıt'),
  unknown('', 'Hareket');

  const MovementKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MovementKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind != unknown && kind.apiValue == normalized) return kind;
      }
    }
    return unknown;
  }
}

/// Hesap hareketi. [amountMinor] İŞARETLİ: + giriş, - çıkış.
@immutable
class AccountMovement {
  const AccountMovement({
    required this.id,
    this.kind = MovementKind.unknown,
    required this.amountMinor,
    this.movementDate,
    this.period,
    this.label,
    this.reversesMovementId,
    this.reversedByMovementId,
    this.reasonCode,
    this.note,
  });

  final int id;
  final MovementKind kind;
  final int amountMinor;
  final DateTime? movementDate;
  final FinancePeriod? period;

  /// Tahsilat: daire etiketi; gider: açıklama; aktarım: karşı hesap.
  final String? label;
  final int? reversesMovementId;
  final int? reversedByMovementId;
  final String? reasonCode;
  final String? note;

  bool get isReversal => kind == MovementKind.reversal || reversesMovementId != null;
  bool get isReversed => reversedByMovementId != null;

  factory AccountMovement.fromJson(Map<String, dynamic> json) => AccountMovement(
    id: f4Int(json['id']),
    kind: MovementKind.fromApi(json['kind']),
    amountMinor: f4Minor(json, 'amount_minor'),
    movementDate: f4Date(json['movement_date']),
    period: FinancePeriod.tryParse(json['period']),
    label: f4Text(json['label']),
    reversesMovementId: f4IntOrNull(json['reverses_movement_id']),
    reversedByMovementId: f4IntOrNull(json['reversed_by_movement_id']),
    reasonCode: f4Text(json['reason_code']),
    note: f4Text(json['note']),
  );
}

/// `GET accounts/:id/movements`.
@immutable
class MovementPage {
  const MovementPage({
    this.account,
    required this.balanceMinor,
    this.items = const <AccountMovement>[],
    this.nextBeforeId,
    this.negativeBalance = false,
  });

  final CashAccount? account;
  final int balanceMinor;
  final List<AccountMovement> items;
  final int? nextBeforeId;
  final bool negativeBalance;

  factory MovementPage.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    return MovementPage(
      account: account is Map ? CashAccount.fromJson(_withBalance(account, json)) : null,
      balanceMinor: f4Minor(json, 'balance_minor'),
      items: f4List(json['items'], AccountMovement.fromJson),
      nextBeforeId: f4IntOrNull(json['next_before_id']),
      negativeBalance: f4Bool(json['negative_balance']),
    );
  }

  /// `account` üstverisinde bakiye yoksa üst düzey `balance_minor` kullanılır.
  static Map<String, dynamic> _withBalance(Map<dynamic, dynamic> account, Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(account);
    map.putIfAbsent('balance_minor', () => json['balance_minor']);
    return map;
  }
}

/// Hesaplar arası aktarım. Durum hareketlerden türetilir ([voided]).
@immutable
class AccountTransfer {
  const AccountTransfer({
    required this.id,
    this.fromAccountId,
    this.toAccountId,
    this.fromName,
    this.toName,
    required this.amountMinor,
    this.transferDate,
    this.description,
    this.voided = false,
  });

  final int id;
  final int? fromAccountId;
  final int? toAccountId;
  final String? fromName;
  final String? toName;
  final int amountMinor;
  final DateTime? transferDate;
  final String? description;
  final bool voided;

  factory AccountTransfer.fromJson(Map<String, dynamic> json) {
    final from = f4Map(json['from_account']);
    final to = f4Map(json['to_account']);
    final voidInfo = json['voided'];
    return AccountTransfer(
      id: f4Int(json['id']),
      fromAccountId: f4IntOrNull(json['from_account_id'] ?? from['id']),
      toAccountId: f4IntOrNull(json['to_account_id'] ?? to['id']),
      fromName: f4Text(json['from_account_name'] ?? from['name']),
      toName: f4Text(json['to_account_name'] ?? to['name']),
      amountMinor: f4Minor(json, 'amount_minor'),
      transferDate: f4Date(json['transfer_date']),
      description: f4Text(json['description']),
      voided: voidInfo is Map || voidInfo == true || f4Text(json['status']) == 'voided',
    );
  }
}

@immutable
class TransferPage {
  const TransferPage({this.items = const <AccountTransfer>[], this.nextBeforeId});

  final List<AccountTransfer> items;
  final int? nextBeforeId;

  factory TransferPage.fromJson(Map<String, dynamic> json) => TransferPage(
    items: f4List(json['items'], AccountTransfer.fromJson),
    nextBeforeId: f4IntOrNull(json['next_before_id']),
  );
}

/// `POST transfers` yanıtı.
@immutable
class TransferWriteResult {
  const TransferWriteResult({required this.transfer, this.movements = const <AccountMovement>[]});

  final AccountTransfer transfer;
  final List<AccountMovement> movements;

  factory TransferWriteResult.fromJson(Map<String, dynamic> json) {
    final transfer = json['transfer'];
    if (transfer is! Map) throw const FormatException('Aktarım okunamadı: transfer');
    return TransferWriteResult(
      transfer: AccountTransfer.fromJson(Map<String, dynamic>.from(transfer)),
      movements: f4List(json['movements'], AccountMovement.fromJson),
    );
  }
}

/// Mutabakat kaydı.
@immutable
class Reconciliation {
  const Reconciliation({
    required this.id,
    this.asOfDate,
    required this.statementBalanceMinor,
    required this.computedBalanceMinor,
    required this.differenceMinor,
    this.adjustmentMovementId,
    this.note,
    this.reconciledAt,
    this.reconciledByName,
  });

  final int id;
  final DateTime? asOfDate;
  final int statementBalanceMinor;
  final int computedBalanceMinor;

  /// ekstre - hesaplanan.
  final int differenceMinor;
  final int? adjustmentMovementId;
  final String? note;
  final DateTime? reconciledAt;
  final String? reconciledByName;

  bool get adjusted => adjustmentMovementId != null;

  factory Reconciliation.fromJson(Map<String, dynamic> json) => Reconciliation(
    id: f4Int(json['id']),
    asOfDate: f4Date(json['as_of_date']),
    statementBalanceMinor: f4Minor(json, 'statement_balance_minor'),
    computedBalanceMinor: f4Minor(json, 'computed_balance_minor'),
    differenceMinor: f4Minor(json, 'difference_minor'),
    adjustmentMovementId: f4IntOrNull(json['adjustment_movement_id']),
    note: f4Text(json['note']),
    reconciledAt: announcementInstant(json['reconciled_at']),
    reconciledByName: f4Text(json['reconciled_by_name']),
  );
}

/// `POST accounts/:id/reconciliations` yanıtı: mutabakat + (varsa) düzeltme sonrası güncel bakiye.
@immutable
class ReconciliationResult {
  const ReconciliationResult({required this.reconciliation, this.accountBalanceMinor});

  final Reconciliation reconciliation;
  final int? accountBalanceMinor;

  factory ReconciliationResult.fromJson(Map<String, dynamic> json) {
    final raw = json['reconciliation'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : json;
    return ReconciliationResult(
      reconciliation: Reconciliation.fromJson(map),
      accountBalanceMinor: f4MinorOrNull(json, 'account_balance_minor'),
    );
  }
}

/// 409 `RECONCILIATION_STALE` yanıtındaki güncel hesaplanan bakiye.
@immutable
class ReconciliationStaleInfo {
  const ReconciliationStaleInfo({this.computedMinor});

  final int? computedMinor;

  factory ReconciliationStaleInfo.fromPayload(Map<String, dynamic>? payload) {
    final map = payload ?? const <String, dynamic>{};
    final raw = map['computed_minor'] ?? map['computed_balance_minor'] ?? map['current_computed_minor'];
    return ReconciliationStaleInfo(computedMinor: financeMinor(raw));
  }
}

/// Toplu eşleme önizlemesinde yönteme göre kırılım.
@immutable
class AssignMethodRow {
  const AssignMethodRow({required this.method, this.count = 0, this.totalMinor = 0});

  final String method;
  final int count;
  final int totalMinor;

  factory AssignMethodRow.fromJson(Map<String, dynamic> json) => AssignMethodRow(
    method: f4Str(json['method']),
    count: f4Int(json['count']),
    totalMinor: f4MinorOrNull(json, 'total_minor') ?? 0,
  );
}

/// `POST accounts/assign-payments/preview` (YAZMAZ).
@immutable
class AssignPreview {
  const AssignPreview({
    required this.count,
    required this.totalMinor,
    this.byMethod = const <AssignMethodRow>[],
    this.previewHash,
    this.skippedBeforeOpening = 0,
    this.skippedClosedPeriod = 0,
    this.skippedNoAccount = 0,
  });

  final int count;
  final int totalMinor;
  final List<AssignMethodRow> byMethod;
  final String? previewHash;

  /// Eşlenmeyecek tahsilatlar (sunucu `skipped`): hesabın açılış tarihinden önce / kapalı ayda / yöntemi için hesap seçilmemiş.
  final int skippedBeforeOpening;
  final int skippedClosedPeriod;
  final int skippedNoAccount;

  int get skippedTotal => skippedBeforeOpening + skippedClosedPeriod + skippedNoAccount;

  factory AssignPreview.fromJson(Map<String, dynamic> json) {
    final skipped = f4Map(json['skipped']);
    return AssignPreview(
      count: f4Int(json['count']),
      totalMinor: f4Minor(json, 'total_minor'),
      byMethod: f4List(json['by_method'], AssignMethodRow.fromJson),
      previewHash: f4Text(json['preview_hash']),
      skippedBeforeOpening: f4Int(skipped['before_opening']),
      skippedClosedPeriod: f4Int(skipped['closed_period']),
      skippedNoAccount: f4Int(skipped['no_account']),
    );
  }
}

/// `POST accounts/assign-payments/commit` yanıtı.
@immutable
class AssignResult {
  const AssignResult({this.count = 0, this.totalMinor = 0, this.skippedClosedCount = 0});

  final int count;
  final int totalMinor;

  /// Kapalı aydaki, eşlenemeyen tahsilat sayısı (varsa).
  final int skippedClosedCount;

  factory AssignResult.fromJson(Map<String, dynamic> json) {
    final result = json['result'] is Map ? Map<String, dynamic>.from(json['result'] as Map) : json;
    return AssignResult(
      count: f4Int(result['count'] ?? result['assigned_count']),
      totalMinor: f4MinorOrNull(result, 'total_minor') ?? 0,
      skippedClosedCount: f4Int(result['skipped_closed_count']),
    );
  }
}
