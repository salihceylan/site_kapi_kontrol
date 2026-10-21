import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';

/// Finans raporları modelleri (Platform Faz 4b, Ö5; sözleşme: docs/PLATFORM_FINANS_4B.md "Ö5").
///
/// Raporlar tek `REPEATABLE READ` işleminde hesaplanır; bir bölüm başarısızsa BÜTÜN yanıt 5xx'tir. İstemci
/// hata durumunda ASLA "0 / veri yok" göstermez. Bozuk zorunlu tutar [FormatException] olur ("veri işlenemedi").

/// Raporların ortak üstverisi.
@immutable
class ReportMeta {
  const ReportMeta({this.siteName = '', this.generatedAt, this.closedThrough, this.footer});

  final String siteName;
  final DateTime? generatedAt;

  /// Sunucunun rapor altbilgisi (yasal defter uyarısı); yoksa PDF paketlenmiş metni kullanır.
  final String? footer;

  /// Bu ay (dahil) ve öncesi kapalı; sonrası "kesinleşmemiş". Hiç kapanış yoksa null.
  final FinancePeriod? closedThrough;

  factory ReportMeta.fromJson(Map<String, dynamic> json) => ReportMeta(
    siteName: f4Str(f4Map(json['site'])['name']),
    generatedAt: announcementInstant(json['generated_at']),
    closedThrough: FinancePeriod.tryParse(json['closed_through']),
    footer: f4Text(json['footer']),
  );

  /// [period] kapalı bir ayda mı (kesinleşmiş)?
  bool isFinal(FinancePeriod period) => closedThrough != null && period <= closedThrough!;
}

// --- Yaşlandırma ------------------------------------------------------------------------------

/// Vade gecikme kovaları (sunucu anahtarlarıyla birebir).
enum AgingBucket {
  notDue('not_due', 'Vadesi gelmemiş'),
  d0to30('d0_30', '0-30 gün'),
  d31to60('d31_60', '31-60 gün'),
  d61to90('d61_90', '61-90 gün'),
  d91to180('d91_180', '91-180 gün'),
  d181to365('d181_365', '181-365 gün'),
  d366plus('d366_plus', '366 gün ve üzeri');

  const AgingBucket(this.key, this.label);

  final String key;
  final String label;

  /// Vadesi geçmiş kovalar (toplamı `total_overdue_minor` eder; `not_due` hariç).
  bool get isOverdue => this != notDue;
}

int _bucketMinor(Map<String, dynamic> json, AgingBucket bucket) {
  final value = financeMinor(json['${bucket.key}_minor'] ?? json[bucket.key]);
  if (value == null) throw FormatException('Tutar alanı okunamadı: ${bucket.key}_minor');
  return value;
}

/// Bir dairenin TEK hesabının yaşlandırma tutarları (`items[].accounts.owner|tenant`; İP-1A: mahsup hesap başınadır).
@immutable
class AgingAccountPart {
  const AgingAccountPart({required this.totalOverdueMinor, required this.creditMinor});

  final int totalOverdueMinor;
  final int creditMinor;

  bool get isZero => totalOverdueMinor == 0 && creditMinor == 0;

  /// Okunamazsa null (eski sunucu ya da bozuk alan; ekran kırılımı göstermez).
  static AgingAccountPart? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final overdue = financeMinor(json['total_overdue_minor']);
    final credit = financeMinor(json['credit_minor']);
    if (overdue == null || credit == null) return null;
    return AgingAccountPart(totalOverdueMinor: overdue, creditMinor: credit);
  }
}

/// Yaşlandırma satırı (daire).
@immutable
class AgingItem {
  const AgingItem({
    required this.apartmentId,
    this.label = '',
    this.blockName,
    this.payerParty,
    this.ownerName,
    this.tenantName,
    required this.buckets,
    required this.creditMinor,
    this.lateFeeOutstandingMinor,
    required this.totalOverdueMinor,
    this.accountParty,
    this.accounts = const <AccountParty, AgingAccountPart>{},
  });

  final int apartmentId;
  final String label;
  final String? blockName;
  final ResponsibleParty? payerParty;
  final String? ownerName;
  final String? tenantName;
  final Map<AgingBucket, int> buckets;
  final int creditMinor;
  final int? lateFeeOutstandingMinor;
  final int totalOverdueMinor;

  /// Hesap süzgeci (`?account_party=`): satır yalnız bu hesabın tutarlarıdır; süzgeçsizse null (iki hesabın toplamı).
  final AccountParty? accountParty;

  /// Hesap kırılımı (İP-1A); eski sunucuda boş.
  final Map<AccountParty, AgingAccountPart> accounts;

  factory AgingItem.fromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'];
    return AgingItem(
      apartmentId: f4Int(json['apartment_id']),
      label: f4Str(json['label']),
      blockName: f4Text(json['block_name']),
      payerParty: json['payer_party'] == null ? null : ResponsibleParty.fromApi(json['payer_party']),
      ownerName: f4Text(json['owner_name']),
      tenantName: f4Text(json['tenant_name']),
      buckets: <AgingBucket, int>{for (final b in AgingBucket.values) b: _bucketMinor(json, b)},
      creditMinor: f4MinorOrNull(json, 'credit_minor') ?? 0,
      lateFeeOutstandingMinor: f4MinorOrNull(json, 'late_fee_outstanding_minor'),
      totalOverdueMinor: f4Minor(json, 'total_overdue_minor'),
      accountParty: AccountParty.tryParse(json['account_party']),
      accounts: <AccountParty, AgingAccountPart>{
        if (rawAccounts is Map)
          for (final party in AccountParty.values) party: ?AgingAccountPart.tryParse(rawAccounts[party.apiValue]),
      },
    );
  }
}

/// `GET reports/aging`.
@immutable
class AgingReport {
  const AgingReport({
    required this.meta,
    this.asOf,
    required this.totals,
    required this.creditMinor,
    this.lateFeeOutstandingMinor,
    required this.totalOverdueMinor,
    this.items = const <AgingItem>[],
    this.total = 0,
    this.accountParty,
  });

  final ReportMeta meta;
  final DateTime? asOf;

  /// Kova toplamları (sunucu `totals`).
  final Map<AgingBucket, int> totals;
  final int creditMinor;
  final int? lateFeeOutstandingMinor;
  final int totalOverdueMinor;
  final List<AgingItem> items;
  final int total;

  /// Raporun hesap süzgeci (İP-1A; yanıt yankısı); süzgeçsizse null.
  final AccountParty? accountParty;

  factory AgingReport.fromJson(Map<String, dynamic> json) {
    final totals = f4Map(json['totals']);
    return AgingReport(
      meta: ReportMeta.fromJson(json),
      asOf: f4Date(json['as_of']),
      totals: <AgingBucket, int>{for (final b in AgingBucket.values) b: _bucketMinor(totals, b)},
      creditMinor: f4MinorOrNull(totals, 'credit_minor') ?? 0,
      lateFeeOutstandingMinor: f4MinorOrNull(totals, 'late_fee_outstanding_minor'),
      totalOverdueMinor: f4Minor(totals, 'total_overdue_minor'),
      items: f4List(json['items'], AgingItem.fromJson),
      total: f4Int(json['total']),
      accountParty: AccountParty.tryParse(json['account_party']),
    );
  }
}

// --- Aylık gelir-gider -------------------------------------------------------------------------

@immutable
class CategoryTotal {
  const CategoryTotal({required this.categoryName, required this.totalMinor});

  final String categoryName;
  final int totalMinor;

  factory CategoryTotal.fromJson(Map<String, dynamic> json) =>
      CategoryTotal(categoryName: f4Str(json['category_name']), totalMinor: f4Minor(json, 'total_minor'));
}

@immutable
class IncomeExpenseMonth {
  const IncomeExpenseMonth({
    required this.period,
    required this.chargedMinor,
    this.lateFeeMinor = 0,
    required this.collectedMinor,
    required this.expenseMinor,
    required this.netCashMinor,
    this.collectionRateBp,
    this.expenseByCategory = const <CategoryTotal>[],
  });

  final FinancePeriod period;
  final int chargedMinor;
  final int lateFeeMinor;
  final int collectedMinor;
  final int expenseMinor;
  final int netCashMinor;

  /// Tahsilat / tahakkuk x 10000; tahakkuk 0 ise null ("-").
  final int? collectionRateBp;
  final List<CategoryTotal> expenseByCategory;

  factory IncomeExpenseMonth.fromJson(Map<String, dynamic> json) {
    final period = FinancePeriod.tryParse(json['period']);
    if (period == null) throw const FormatException('Dönem okunamadı: period');
    return IncomeExpenseMonth(
      period: period,
      chargedMinor: f4Minor(json, 'charged_minor'),
      lateFeeMinor: f4MinorOrNull(json, 'late_fee_minor') ?? 0,
      collectedMinor: f4Minor(json, 'collected_minor'),
      expenseMinor: f4Minor(json, 'expense_minor'),
      netCashMinor: f4Minor(json, 'net_cash_minor'),
      collectionRateBp: f4IntOrNull(json['collection_rate_bp']),
      expenseByCategory: f4List(json['expense_by_category'], CategoryTotal.fromJson),
    );
  }
}

/// `GET reports/income-expense`.
@immutable
class IncomeExpenseReport {
  const IncomeExpenseReport({
    required this.meta,
    this.from,
    this.to,
    this.months = const <IncomeExpenseMonth>[],
    this.expenseByCategory = const <CategoryTotal>[],
  });

  final ReportMeta meta;
  final FinancePeriod? from;
  final FinancePeriod? to;
  final List<IncomeExpenseMonth> months;

  /// Dönem boyunca kategori toplamları.
  final List<CategoryTotal> expenseByCategory;

  int get chargedMinor => months.fold<int>(0, (a, m) => a + m.chargedMinor);
  int get collectedMinor => months.fold<int>(0, (a, m) => a + m.collectedMinor);
  int get expenseMinor => months.fold<int>(0, (a, m) => a + m.expenseMinor);
  int get netCashMinor => months.fold<int>(0, (a, m) => a + m.netCashMinor);

  factory IncomeExpenseReport.fromJson(Map<String, dynamic> json) {
    final rawMonths = json['months'] ?? json['items'] ?? json['rows'];
    final months = f4List(rawMonths, IncomeExpenseMonth.fromJson);
    var categories = f4List(json['expense_by_category'], CategoryTotal.fromJson);
    if (categories.isEmpty) {
      // Sunucu kategori kırılımını aylara gömdüyse dönem toplamı buradan türetilir (tamsayı toplam).
      final byName = <String, int>{};
      for (final month in months) {
        for (final c in month.expenseByCategory) {
          byName[c.categoryName] = (byName[c.categoryName] ?? 0) + c.totalMinor;
        }
      }
      categories = List<CategoryTotal>.unmodifiable(
        byName.entries.map((e) => CategoryTotal(categoryName: e.key, totalMinor: e.value)),
      );
    }
    return IncomeExpenseReport(
      meta: ReportMeta.fromJson(json),
      from: FinancePeriod.tryParse(json['from']),
      to: FinancePeriod.tryParse(json['to']),
      months: months,
      expenseByCategory: categories,
    );
  }
}

// --- Kasa durumu -------------------------------------------------------------------------------

/// Hesap başına kasa durumu satırı.
@immutable
class CashPositionRow {
  const CashPositionRow({
    this.accountId,
    this.name = '',
    this.kind = CashAccountKind.cash,
    required this.openingMinor,
    required this.collectionsMinor,
    required this.expensesMinor,
    required this.transfersInMinor,
    required this.transfersOutMinor,
    required this.adjustmentsMinor,
    required this.reversalsMinor,
    required this.balanceMinor,
    this.lastReconciliation,
  });

  final int? accountId;
  final String name;
  final CashAccountKind kind;
  final int openingMinor;
  final int collectionsMinor;
  final int expensesMinor;
  final int transfersInMinor;
  final int transfersOutMinor;

  /// Düzeltme hareketleri (banka masrafı / faiz / sayım farkı) AYRI satırdır; gizlenmez.
  final int adjustmentsMinor;
  final int reversalsMinor;
  final int balanceMinor;
  final LastReconciliation? lastReconciliation;

  factory CashPositionRow.fromJson(Map<String, dynamic> json) {
    final account = f4Map(json['account']);
    return CashPositionRow(
      accountId: f4IntOrNull(json['account_id'] ?? account['id'] ?? json['id']),
      name: f4Str(json['name'] ?? account['name']),
      kind: CashAccountKind.fromApi(json['kind'] ?? account['kind']),
      openingMinor: f4Minor(json, 'opening_minor'),
      collectionsMinor: f4Minor(json, 'collections_minor'),
      expensesMinor: f4Minor(json, 'expenses_minor'),
      transfersInMinor: f4Minor(json, 'transfers_in_minor'),
      transfersOutMinor: f4Minor(json, 'transfers_out_minor'),
      adjustmentsMinor: f4Minor(json, 'adjustments_minor'),
      reversalsMinor: f4Minor(json, 'reversals_minor'),
      balanceMinor: f4Minor(json, 'balance_minor'),
      lastReconciliation: LastReconciliation.tryParse(json['last_reconciliation']),
    );
  }
}

/// `GET reports/cash-position`.
@immutable
class CashPositionReport {
  const CashPositionReport({
    required this.meta,
    this.asOf,
    this.items = const <CashPositionRow>[],
    required this.totalBalanceMinor,
    this.unassigned = const UnassignedPayments(),
  });

  final ReportMeta meta;
  final DateTime? asOf;
  final List<CashPositionRow> items;
  final int totalBalanceMinor;
  final UnassignedPayments unassigned;

  factory CashPositionReport.fromJson(Map<String, dynamic> json) {
    final items = f4List(json['items'] ?? json['accounts'], CashPositionRow.fromJson);
    final totals = f4Map(json['totals']);
    final total = f4MinorOrNull(totals, 'balance_minor') ?? f4MinorOrNull(json, 'total_balance_minor');
    if (total == null) throw const FormatException('Tutar alanı okunamadı: balance_minor');
    return CashPositionReport(
      meta: ReportMeta.fromJson(json),
      asOf: f4Date(json['as_of']),
      items: items,
      totalBalanceMinor: total,
      unassigned: UnassignedPayments.fromJson(f4Map(json['unassigned_payments'])),
    );
  }
}

// --- Daire ekstresi ----------------------------------------------------------------------------

/// Ekstre satırı: defter kaydı + kayan bakiye.
@immutable
class StatementItem {
  const StatementItem({required this.entry, required this.runningBalanceMinor});

  final LedgerEntry entry;
  final int runningBalanceMinor;

  factory StatementItem.fromJson(Map<String, dynamic> json) =>
      StatementItem(entry: LedgerEntry.fromJson(json), runningBalanceMinor: f4Minor(json, 'running_balance_minor'));
}

@immutable
class StatementTotals {
  const StatementTotals({
    required this.chargedMinor,
    this.lateFeeMinor = 0,
    required this.paidMinor,
    required this.reversedMinor,
  });

  final int chargedMinor;
  final int lateFeeMinor;
  final int paidMinor;
  final int reversedMinor;

  factory StatementTotals.fromJson(Map<String, dynamic> json) => StatementTotals(
    chargedMinor: f4Minor(json, 'charged_minor'),
    lateFeeMinor: f4MinorOrNull(json, 'late_fee_minor') ?? 0,
    paidMinor: f4Minor(json, 'paid_minor'),
    reversedMinor: f4Minor(json, 'reversed_minor'),
  );
}

/// `GET apartments/:id/statement` ve sakin eşleniği.
@immutable
class ApartmentStatement {
  const ApartmentStatement({
    required this.meta,
    required this.apartment,
    this.from,
    this.to,
    required this.openingBalanceMinor,
    required this.closingBalanceMinor,
    this.items = const <StatementItem>[],
    required this.totals,
    this.overdueMinor,
    this.visibleFrom,
    this.offsetNote = false,
    this.accountParty,
    this.readOnly = false,
  });

  final ReportMeta meta;
  final AccountApartment apartment;

  /// Ekstrenin hesabı (İP-1A): yönetici ekstresinde süzgeç (yoksa null = iki hesap birlikte), sakin ekstresinde görünümün hesabı.
  final AccountParty? accountParty;

  /// Yalnız sakin ekstresinde: salt okunur kiracı hesabı görünümü (`role: read_only`).
  final bool readOnly;
  final DateTime? from;
  final DateTime? to;
  final int openingBalanceMinor;
  final int closingBalanceMinor;
  final List<StatementItem> items;
  final StatementTotals totals;
  final int? overdueMinor;

  /// Yalnız sakin ekstresinde ve kapsam dışında kayıt varsa: kayıtların başladığı ay (sakinin taşınma ayı). Bakiyeler bu kapsam içindir.
  final FinancePeriod? visibleFrom;

  /// Yalnız sakin ekstresinde: satır toplamı kapanışa eşit değil (bir tahsilat ya da alacak, ekstrede gösterilmeyen önceki dönem
  /// kayıtlarıyla mahsup edildi). İstemci bunu açıklayan notu yazar.
  final bool offsetNote;

  factory ApartmentStatement.fromJson(Map<String, dynamic> json) {
    final apartment = json['apartment'];
    return ApartmentStatement(
      meta: ReportMeta.fromJson(json),
      apartment: apartment is Map
          ? AccountApartment.fromJson(Map<String, dynamic>.from(apartment))
          : const AccountApartment(id: 0),
      from: f4Date(json['from']),
      to: f4Date(json['to']),
      openingBalanceMinor: f4Minor(json, 'opening_balance_minor'),
      closingBalanceMinor: f4Minor(json, 'closing_balance_minor'),
      items: f4List(json['items'], StatementItem.fromJson),
      totals: StatementTotals.fromJson(f4Map(json['totals'])),
      overdueMinor: f4MinorOrNull(json, 'overdue_minor'),
      visibleFrom: FinancePeriod.tryParse(json['visible_from']),
      offsetNote: json['offset_note'] == true,
      accountParty: AccountParty.tryParse(json['account_party']),
      readOnly: json['role'] == 'read_only',
    );
  }
}

// --- Yönetim kurulu özeti ----------------------------------------------------------------------

@immutable
class BoardWarning {
  const BoardWarning({required this.code, this.count, this.amountMinor});

  final String code;
  final int? count;
  final int? amountMinor;

  factory BoardWarning.fromJson(Map<String, dynamic> json) => BoardWarning(
    code: f4Str(json['code']),
    count: f4IntOrNull(json['count']),
    amountMinor: f4MinorOrNull(json, 'amount_minor') ?? f4MinorOrNull(json, 'total_minor'),
  );

  /// Uyarının Türkçe metni (bilinmeyen kodda genel metin; ham kod gösterilmez).
  String get message {
    switch (code) {
      case 'UNCLOSED_PAST_PERIODS':
        return 'Geçmiş aylardan kapatılmamış dönemler var; rakamlar kesinleşmemiştir.';
      case 'RECONCILIATION_DIFFERENCE':
        return 'Bir ya da daha fazla hesapta mutabakat farkı var.';
      case 'UNASSIGNED_PAYMENTS':
        return 'Hesaba eşlenmemiş tahsilatlar var; kasa rakamları eksik olabilir.';
      case 'NEGATIVE_BALANCE':
        return 'Bir ya da daha fazla hesabın bakiyesi eksiye düşmüş; kayıtlar eksik olabilir.';
      default:
        return 'Raporda dikkat edilmesi gereken bir uyarı var.';
    }
  }
}

/// Kurul özetinde borçlu daire metni: "7 / 40 (%17,50)" (daire sayısı biliniyorsa), "7 (%17,50)" (yalnız oran), "7".
String boardDebtorText(int debtorCount, int? apartmentCount, int? rateBp) {
  final rate = rateBp == null ? '' : ' (${formatPercentBp(rateBp)})';
  return apartmentCount == null ? '$debtorCount$rate' : '$debtorCount / $apartmentCount$rate';
}

@immutable
class AgingSummaryRow {
  const AgingSummaryRow({required this.key, this.count = 0, required this.totalMinor});

  final String key;
  final int count;
  final int totalMinor;

  String get label {
    for (final bucket in AgingBucket.values) {
      if (bucket.key == key) return bucket.label;
    }
    return key;
  }

  factory AgingSummaryRow.fromJson(Map<String, dynamic> json) => AgingSummaryRow(
    key: f4Str(json['bucket'] ?? json['key']),
    count: f4Int(json['count']),
    totalMinor: f4Minor(json, 'total_minor'),
  );
}

@immutable
class BoardExpenseItem {
  const BoardExpenseItem({required this.categoryName, this.expenseDate, required this.amountMinor});

  final String categoryName;
  final DateTime? expenseDate;
  final int amountMinor;

  factory BoardExpenseItem.fromJson(Map<String, dynamic> json) => BoardExpenseItem(
    categoryName: f4Str(json['category_name']),
    expenseDate: f4Date(json['expense_date']),
    amountMinor: f4Minor(json, 'amount_minor'),
  );
}

/// Borçlu daire satırı (kurul özeti `debtor_list`): sunucu `{label, total_overdue_minor}` gönderir (vadesi geçmiş borç).
@immutable
class BoardDebtor {
  const BoardDebtor({required this.label, required this.totalMinor});

  final String label;
  final int totalMinor;

  factory BoardDebtor.fromJson(Map<String, dynamic> json) => BoardDebtor(
    label: f4Str(json['label']),
    totalMinor: f4MinorOrNull(json, 'total_overdue_minor') ?? f4Minor(json, 'total_minor'),
  );
}

/// Kurul özetindeki hesap satırı: sunucu YALNIZ `{id, name, kind, balance_minor, last_reconciliation}` gönderir
/// (kasa durumu raporundaki hareket kırılımı YOKTUR; o alanlar burada zorunlu OLMAMALI).
@immutable
class BoardCashAccount {
  const BoardCashAccount({
    this.id,
    this.name = '',
    this.kind = CashAccountKind.cash,
    required this.balanceMinor,
    this.lastReconciliation,
  });

  final int? id;
  final String name;
  final CashAccountKind kind;
  final int balanceMinor;
  final LastReconciliation? lastReconciliation;

  factory BoardCashAccount.fromJson(Map<String, dynamic> json) => BoardCashAccount(
    id: f4IntOrNull(json['id'] ?? json['account_id']),
    name: f4Str(json['name']),
    kind: CashAccountKind.fromApi(json['kind']),
    balanceMinor: f4Minor(json, 'balance_minor'),
    lastReconciliation: LastReconciliation.tryParse(json['last_reconciliation']),
  );
}

/// `GET reports/board-summary`. KİŞİ ADI İÇERMEZ. Bölümler sunucu yanıtında yoksa null kalır ve ekranda ÇİZİLMEZ
/// (uydurma sıfır gösterilmez).
@immutable
class BoardSummaryReport {
  const BoardSummaryReport({
    required this.meta,
    this.from,
    this.to,
    this.chargedMinor,
    this.lateFeeMinor,
    this.collectedMinor,
    this.collectionRateBp,
    this.debtTotalMinor,
    this.debtorCount,
    this.apartmentCount,
    this.debtorRateBp,
    this.aging = const <AgingSummaryRow>[],
    this.expenseTotalMinor,
    this.expenseByCategory = const <CategoryTotal>[],
    this.topExpenses = const <BoardExpenseItem>[],
    this.cashAccounts = const <BoardCashAccount>[],
    this.cashTotalMinor,
    this.unassigned,
    this.lateFeeTotalMinor,
    this.lateFeeWaivedCount,
    this.remindersSentCount,
    this.warnings = const <BoardWarning>[],
    this.debtors = const <BoardDebtor>[],
  });

  final ReportMeta meta;
  final FinancePeriod? from;
  final FinancePeriod? to;
  final int? chargedMinor;
  final int? lateFeeMinor;
  final int? collectedMinor;
  final int? collectionRateBp;
  final int? debtTotalMinor;
  final int? debtorCount;
  final int? apartmentCount;
  final int? debtorRateBp;
  final List<AgingSummaryRow> aging;
  final int? expenseTotalMinor;
  final List<CategoryTotal> expenseByCategory;
  final List<BoardExpenseItem> topExpenses;
  final List<BoardCashAccount> cashAccounts;
  final int? cashTotalMinor;
  final UnassignedPayments? unassigned;
  final int? lateFeeTotalMinor;
  final int? lateFeeWaivedCount;
  final int? remindersSentCount;
  final List<BoardWarning> warnings;

  /// Yalnız yönetici + `include_debtor_list=true`: en yüksek 10 borçlu daire (etiket + tutar).
  final List<BoardDebtor> debtors;

  /// Vadesi GELMEMİŞ borç kovası (`aging[bucket=not_due]`): `debtTotalMinor` (vadesi GEÇMİŞ borç) toplamına DAHİL DEĞİLDİR.
  AgingSummaryRow? get _notDueRow {
    for (final a in aging) {
      if (a.key == AgingBucket.notDue.key) return a;
    }
    return null;
  }

  int? get notDueMinor => _notDueRow?.totalMinor;
  int? get notDueCount => _notDueRow?.count;

  /// Vadesi geçmiş kovalar (toplamı `debtTotalMinor`); `not_due` hariç.
  List<AgingSummaryRow> get overdueAging => <AgingSummaryRow>[
    for (final a in aging)
      if (a.key != AgingBucket.notDue.key) a,
  ];

  factory BoardSummaryReport.fromJson(Map<String, dynamic> json) {
    final collection = f4Map(json['collection'] ?? json['accrual']);
    final receivables = f4Map(json['receivables'] ?? json['debt']);
    final expenses = f4Map(json['expenses'] ?? json['expense']);
    final cash = f4Map(json['cash']);
    final lateFee = f4Map(json['late_fee']);
    final reminders = f4Map(json['reminders']);
    final hasCollection = collection.isNotEmpty;
    final hasReceivables = receivables.isNotEmpty;
    final hasExpenses = expenses.isNotEmpty;
    final hasCash = cash.isNotEmpty;
    final hasLateFee = lateFee.isNotEmpty;
    return BoardSummaryReport(
      meta: ReportMeta.fromJson(json),
      from: FinancePeriod.tryParse(json['from']),
      to: FinancePeriod.tryParse(json['to']),
      chargedMinor: hasCollection ? f4Minor(collection, 'charged_minor') : null,
      lateFeeMinor: hasCollection ? f4MinorOrNull(collection, 'late_fee_minor') : null,
      collectedMinor: hasCollection ? f4Minor(collection, 'collected_minor') : null,
      collectionRateBp: hasCollection ? f4IntOrNull(collection['collection_rate_bp']) : null,
      // Sunucu anahtarları: total_overdue_minor / debtor_ratio_bp (eski adlar da kabul edilir).
      debtTotalMinor: hasReceivables
          ? (f4MinorOrNull(receivables, 'total_overdue_minor') ?? f4Minor(receivables, 'debt_total_minor'))
          : null,
      debtorCount: hasReceivables ? f4Int(receivables['debtor_count']) : null,
      apartmentCount: hasReceivables ? f4IntOrNull(receivables['apartment_count']) : null,
      debtorRateBp: hasReceivables ? f4IntOrNull(receivables['debtor_ratio_bp'] ?? receivables['debtor_rate_bp']) : null,
      aging: f4List(receivables['aging'], AgingSummaryRow.fromJson),
      expenseTotalMinor: hasExpenses ? f4Minor(expenses, 'total_minor') : null,
      expenseByCategory: f4List(expenses['by_category'], CategoryTotal.fromJson),
      topExpenses: f4List(expenses['top_items'], BoardExpenseItem.fromJson),
      cashAccounts: f4List(cash['accounts'], BoardCashAccount.fromJson),
      cashTotalMinor: hasCash ? f4MinorOrNull(cash, 'total_balance_minor') : null,
      unassigned: cash['unassigned_payments'] is Map
          ? UnassignedPayments.fromJson(f4Map(cash['unassigned_payments']))
          : null,
      lateFeeTotalMinor: hasLateFee ? f4MinorOrNull(lateFee, 'total_minor') : null,
      lateFeeWaivedCount: hasLateFee ? f4IntOrNull(lateFee['waived_count']) : null,
      remindersSentCount: reminders.isEmpty ? null : f4IntOrNull(reminders['sent_count']),
      warnings: f4List(json['warnings'], BoardWarning.fromJson),
      debtors: f4List(json['debtor_list'] ?? json['top_debtors'], BoardDebtor.fromJson),
    );
  }
}
