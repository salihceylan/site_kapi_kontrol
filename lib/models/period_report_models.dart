import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/cash_models.dart' show UnassignedPayments;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/report_models.dart' show AgingSummaryRow, BoardWarning, CategoryTotal, ReportMeta;

/// Dönemsel finans raporu (`GET …/finance/reports/period`; sözleşme: docs/PLATFORM_FINANS_KASALAR.md §8.4a).
///
/// Kurallar finans modelleriyle aynıdır: PARA tamsayı KURUŞTUR; zorunlu tutar alanı okunamazsa [FormatException] fırlar
/// (ekran "veri işlenemedi" der, asla uydurma "0" göstermez). İstemci bakiye HESAPLAMAZ: sunucunun verdiği değerler gösterilir.

/// Bir Hesabın (İşletme / Fon) dönem özeti: dönem sonu = dönem başı + tahsilat − gider + aktarım giriş − aktarım çıkış + düzeltme.
@immutable
class PeriodFundSection {
  const PeriodFundSection({
    required this.fund,
    required this.openingMinor,
    required this.collectionsMinor,
    required this.expensesMinor,
    required this.transfersInMinor,
    required this.transfersOutMinor,
    required this.adjustmentsMinor,
    required this.closingMinor,
    required this.changeMinor,
    this.negativeBalance = false,
    this.expenseByCategory = const <CategoryTotal>[],
  });

  final FinanceFund fund;
  final int openingMinor;
  final int collectionsMinor;
  final int expensesMinor;
  final int transfersInMinor;
  final int transfersOutMinor;
  final int adjustmentsMinor;
  final int closingMinor;

  /// Dönem sonu − dönem başı.
  final int changeMinor;
  final bool negativeBalance;

  /// Gider kalemleri (kategori), büyükten küçüğe.
  final List<CategoryTotal> expenseByCategory;

  factory PeriodFundSection.fromJson(Map<String, dynamic> json, FinanceFund fund) => PeriodFundSection(
    fund: FinanceFund.tryParse(json['fund']) ?? fund,
    openingMinor: f4Minor(json, 'opening_minor'),
    collectionsMinor: f4Minor(json, 'collections_minor'),
    expensesMinor: f4Minor(json, 'expenses_minor'),
    transfersInMinor: f4Minor(json, 'transfers_in_minor'),
    transfersOutMinor: f4Minor(json, 'transfers_out_minor'),
    adjustmentsMinor: f4Minor(json, 'adjustments_minor'),
    closingMinor: f4Minor(json, 'closing_minor'),
    changeMinor: f4Minor(json, 'change_minor'),
    negativeBalance: f4Bool(json['negative_balance']),
    expenseByCategory: f4List(json['expense_by_category'], CategoryTotal.fromJson),
  );
}

/// İki Hesabın toplamı.
@immutable
class PeriodTotals {
  const PeriodTotals({
    required this.openingMinor,
    required this.collectionsMinor,
    required this.expensesMinor,
    required this.closingMinor,
    required this.changeMinor,
  });

  final int openingMinor;
  final int collectionsMinor;
  final int expensesMinor;
  final int closingMinor;
  final int changeMinor;

  factory PeriodTotals.fromJson(Map<String, dynamic> json) => PeriodTotals(
    openingMinor: f4Minor(json, 'opening_minor'),
    collectionsMinor: f4Minor(json, 'collections_minor'),
    expensesMinor: f4Minor(json, 'expenses_minor'),
    closingMinor: f4Minor(json, 'closing_minor'),
    changeMinor: f4Minor(json, 'change_minor'),
  );
}

/// Aylık kırılım satırı (toplam ve her Hesap için tahsilat / gider / net).
@immutable
class PeriodMonthRow {
  const PeriodMonthRow({
    required this.period,
    required this.collectionsMinor,
    required this.expensesMinor,
    required this.netMinor,
    required this.operatingCollectionsMinor,
    required this.operatingExpensesMinor,
    required this.capitalCollectionsMinor,
    required this.capitalExpensesMinor,
  });

  final FinancePeriod period;
  final int collectionsMinor;
  final int expensesMinor;
  final int netMinor;
  final int operatingCollectionsMinor;
  final int operatingExpensesMinor;
  final int capitalCollectionsMinor;
  final int capitalExpensesMinor;

  factory PeriodMonthRow.fromJson(Map<String, dynamic> json) {
    final period = FinancePeriod.tryParse(json['period']);
    if (period == null) throw const FormatException('Dönem raporu okunamadı: ay');
    final operating = f4Map(json['operating']);
    final capital = f4Map(json['capital']);
    return PeriodMonthRow(
      period: period,
      collectionsMinor: f4Minor(json, 'collections_minor'),
      expensesMinor: f4Minor(json, 'expenses_minor'),
      netMinor: f4Minor(json, 'net_minor'),
      operatingCollectionsMinor: f4Minor(operating, 'collections_minor'),
      operatingExpensesMinor: f4Minor(operating, 'expenses_minor'),
      capitalCollectionsMinor: f4Minor(capital, 'collections_minor'),
      capitalExpensesMinor: f4Minor(capital, 'expenses_minor'),
    );
  }
}

/// Dönem sonu borçlu özeti: yalnız adet ve tutar (kişi / daire bilgisi yok).
@immutable
class PeriodDebtors {
  const PeriodDebtors({
    this.asOf,
    this.apartmentCount = 0,
    this.debtorCount = 0,
    required this.totalOverdueMinor,
    this.aging = const <AgingSummaryRow>[],
  });

  final DateTime? asOf;
  final int apartmentCount;
  final int debtorCount;
  final int totalOverdueMinor;
  final List<AgingSummaryRow> aging;

  factory PeriodDebtors.fromJson(Map<String, dynamic> json) => PeriodDebtors(
    asOf: f4Date(json['as_of']),
    apartmentCount: f4Int(json['apartment_count']),
    debtorCount: f4Int(json['debtor_count']),
    totalOverdueMinor: f4Minor(json, 'total_overdue_minor'),
    aging: f4List(json['aging'], AgingSummaryRow.fromJson),
  );
}

@immutable
class PeriodReport {
  const PeriodReport({
    required this.meta,
    required this.from,
    required this.to,
    required this.periodTitle,
    this.hasAccounts = true,
    required this.operating,
    required this.capital,
    required this.totals,
    this.months = const <PeriodMonthRow>[],
    this.advanceMinor = 0,
    this.differenceMinor = 0,
    this.balanced = true,
    this.unassigned = const UnassignedPayments(),
    required this.debtors,
    this.warnings = const <BoardWarning>[],
  });

  final ReportMeta meta;
  final FinancePeriod from;
  final FinancePeriod to;
  final String periodTitle;
  final bool hasAccounts;
  final PeriodFundSection operating;
  final PeriodFundSection capital;
  final PeriodTotals totals;
  final List<PeriodMonthRow> months;

  /// Henüz borca dağıtılmamış ödemeler (iki Hesaba da yazılmaz).
  final int advanceMinor;

  /// Hesap toplamı − (Aidat + Fon + avans); geçmiş dönemlerde sıfırdan farklı olabilir (dağıtım güncel durumdan türer).
  final int differenceMinor;
  final bool balanced;
  final UnassignedPayments unassigned;
  final PeriodDebtors debtors;
  final List<BoardWarning> warnings;

  PeriodFundSection of(FinanceFund fund) => fund == FinanceFund.operating ? operating : capital;

  /// Her iki Hesapta da tahsilat ve gider kalemi yok mu (boş dönem)?
  bool get isEmpty =>
      totals.collectionsMinor == 0 &&
      totals.expensesMinor == 0 &&
      totals.openingMinor == 0 &&
      totals.closingMinor == 0 &&
      debtors.debtorCount == 0;

  factory PeriodReport.fromJson(Map<String, dynamic> json) {
    final funds = f4Map(json['funds']);
    final operating = funds[FinanceFund.operating.apiValue];
    final capital = funds[FinanceFund.capital.apiValue];
    final from = FinancePeriod.tryParse(json['from']);
    final to = FinancePeriod.tryParse(json['to']);
    if (operating is! Map || capital is! Map || from == null || to == null) {
      throw const FormatException('Dönem raporu okunamadı');
    }
    final reconciliation = f4Map(json['reconciliation']);
    final difference = f4MinorOrNull(reconciliation, 'difference_minor') ?? 0;
    return PeriodReport(
      meta: ReportMeta.fromJson(json),
      from: from,
      to: to,
      periodTitle: f4Str(json['period_title']),
      hasAccounts: f4Bool(json['has_accounts'], fallback: true),
      operating: PeriodFundSection.fromJson(Map<String, dynamic>.from(operating), FinanceFund.operating),
      capital: PeriodFundSection.fromJson(Map<String, dynamic>.from(capital), FinanceFund.capital),
      totals: PeriodTotals.fromJson(f4Map(json['totals'])),
      months: f4List(json['months'], PeriodMonthRow.fromJson),
      advanceMinor: f4MinorOrNull(json, 'advance_minor') ?? 0,
      differenceMinor: difference,
      balanced: f4Bool(reconciliation['balanced'], fallback: difference == 0),
      unassigned: UnassignedPayments.fromJson(f4Map(json['unassigned_payments'])),
      debtors: PeriodDebtors.fromJson(f4Map(json['debtors'])),
      warnings: f4List(json['warnings'], BoardWarning.fromJson),
    );
  }
}
