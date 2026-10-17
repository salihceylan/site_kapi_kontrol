import 'dart:typed_data';

import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/services/finance_4b_api.dart';
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

/// Faz 4b ekranlarının ortak erişimi: [PeopleScope] (site + yetki) üstünden [Finance4bService].
extension Finance4bScopeAccess on PeopleScope {
  Finance4bService get f4 => Finance4bService.of(authService);

  /// Belirteçle ve bu sitenin kodu ile bir 4b çağrısı yapar.
  Future<T> f4Call<T>(Future<T> Function(Finance4bApi api, String token, int siteCode) call) =>
      f4.run((api, token) => call(api, token, siteCode));
}

/// PDF çıktısı (yazdır / paylaş) için tek geçiş noktası. Üretim ve teslim burada toplanır; widget testleri
/// platform eklentilerine (printing, share_plus) ve gerçek zamanlı varlık yüklemeye dokunmadan
/// [debugOverride] ile sürer. PDF'in kendisi `pdf_finance_service_test.dart` ile sınanır.
class FinancePdfActions {
  FinancePdfActions._();

  /// Test düzeneği: verilirse PDF üretilmez / teslim edilmez; (tür, başlık, paylaş mı) çağrılır.
  static Future<void> Function(FinancePdfRequest request)? debugOverride;

  static Future<void> receipt(Receipt receipt, String stamp, {required bool share}) async {
    final override = debugOverride;
    if (override != null) {
      return override(FinancePdfRequest('receipt', receipt.number, share, stamp: stamp));
    }
    final bytes = await PdfFinanceService.generateReceiptPdf(receipt: receipt, stamp: stamp);
    await _deliver(bytes, PdfFinanceService.receiptFileName(receipt), share, 'Makbuz ${receipt.number}');
  }

  static Future<void> statement(ApartmentStatement statement, {required bool share}) async {
    final override = debugOverride;
    final title = statement.apartment.label;
    if (override != null) return override(FinancePdfRequest('statement', title, share));
    final bytes = await PdfFinanceService.generateStatementPdf(statement: statement);
    await _deliver(bytes, PdfFinanceService.statementFileName(title, DateTime.now()), share, 'Hesap ekstresi');
  }

  static Future<void> aging(AgingReport report, {required bool share}) =>
      _report('aging', 'Yaslandirma', share, () => PdfFinanceService.generateAgingPdf(report: report));

  static Future<void> incomeExpense(IncomeExpenseReport report, {required bool share}) => _report(
    'income_expense',
    'Gelir_Gider',
    share,
    () => PdfFinanceService.generateIncomeExpensePdf(report: report),
  );

  static Future<void> cashPosition(CashPositionReport report, {required bool share}) =>
      _report('cash_position', 'Kasa_Durumu', share, () => PdfFinanceService.generateCashPositionPdf(report: report));

  static Future<void> boardSummary(BoardSummaryReport report, {required bool share}) => _report(
    'board_summary',
    'Yonetim_Kurulu_Ozeti',
    share,
    () => PdfFinanceService.generateBoardSummaryPdf(report: report),
  );

  static Future<void> _report(
    String kind,
    String name,
    bool share,
    Future<Uint8List> Function() build,
  ) async {
    final override = debugOverride;
    if (override != null) return override(FinancePdfRequest(kind, name, share));
    final bytes = await build();
    await _deliver(bytes, PdfFinanceService.reportFileName(name, DateTime.now()), share, name.replaceAll('_', ' '));
  }

  static Future<void> _deliver(Uint8List bytes, String fileName, bool share, String subject) {
    if (share) return PdfFinanceService.sharePdf(bytes, fileName: fileName, subject: subject);
    return PdfFinanceService.printPdf(bytes, fileName: fileName);
  }
}

/// [FinancePdfActions.debugOverride] çağrısının içeriği.
class FinancePdfRequest {
  const FinancePdfRequest(this.kind, this.title, this.share, {this.stamp});

  final String kind;
  final String title;
  final bool share;
  final String? stamp;
}
