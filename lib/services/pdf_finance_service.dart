import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/expense_analysis.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/person_record.dart' show crmApartmentTitle;
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// Finans PDF'leri (Platform Faz 4b; sözleşme: docs/PLATFORM_FINANS_4B.md "Ö1" ve "PDF (istemci)"):
/// tahsilat / iptal makbuzu, daire ekstresi ve raporlar.
///
/// Kurallar:
/// - Yazı tipi uygulamaya GÖMÜLÜ Roboto'dur ([PdfFontSet.loadBundled]); ağdan indirilmez, çevrimdışıyken de
///   Türkçe harfler ve "₺" kaybolmaz.
/// - İçerik DEĞİŞMEZ sunucu kaydından üretilir (makbuzda yalnız ad, daire, tutar; TCKN / telefon / e-posta /
///   bakiye YOK). Makbuz metni mahsup bildirimi ve çekince satırını içerir (şablon sürümü 1).
/// - 200 satırdan uzun çıktı arka plan izolesinde üretilir ([BackgroundWork]).
/// - Dosya adı ASCII'dir (`Makbuz_MK-2026-000123.pdf`).
/// - Her rapor ve ekstre altbilgisi "noter onaylı karar defteri / yasal defterlerin yerine geçmez" der.
class PdfFinanceService {
  PdfFinanceService._();

  /// Bu satır sayısından uzun çıktı arka plan izolesinde üretilir.
  static const int isolateRowThreshold = 200;

  /// Test düzeneği: false iken PDF akışları sıkıştırılmaz (üretilen metin / yazı tipi eşlemesi denetlenebilsin).
  @visibleForTesting
  static bool debugCompress = true;

  // --- Sabit makbuz metni (şablon sürümü 1) `[AVUKAT DOĞRULASIN]` ------------------------------------

  static const String mahsupText =
      'Tahsil edilen tutar, kayıtlardaki vadesi en eski borçtan başlayarak mahsup edilir.';
  static const String cekinceText =
      'Bu makbuz yalnızca yukarıda belirtilen tutarın tahsil edildiğini gösterir; önceki dönemlere ait '
      'borçlara, gecikme tazminatına ve diğer hak ve alacaklara ilişkin haklar saklıdır.';
  static const String ledgerDisclaimer =
      'Bu belge noter onaylı karar defteri/yasal defterlerin yerine geçmez.';
  static const String reportDisclaimer =
      'Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez.';

  // --- Dosya adı ----------------------------------------------------------------------------------

  /// Yalnız ASCII harf, rakam, tire ve alt çizgi: Türkçe harfler sadeleştirilir, diğerleri `_` olur.
  static String asciiName(String text) {
    const map = <String, String>{
      'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S',
      'ü': 'u', 'Ü': 'U',
    };
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(map[ch] ?? ch);
    }
    final cleaned = buffer.toString().replaceAll(RegExp(r'[^A-Za-z0-9\-]+'), '_');
    return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// `Makbuz_MK-2026-000123.pdf`.
  static String receiptFileName(Receipt receipt) => 'Makbuz_${asciiName(receipt.number)}.pdf';

  /// `Ekstre_A_Blok_5_20261016.pdf`.
  static String statementFileName(String apartmentLabel, DateTime day) {
    final name = asciiName(apartmentLabel);
    return 'Ekstre_${name.isEmpty ? 'Daire' : name}_${_ymd(day)}.pdf';
  }

  /// `Rapor_<ad>_20261016.pdf`.
  static String reportFileName(String name, DateTime day) => 'Rapor_${asciiName(name)}_${_ymd(day)}.pdf';

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  // --- Üretim: makbuz -----------------------------------------------------------------------------

  /// Makbuz PDF'i (A4 tek sayfa). [stamp]: "ASIL", "KOPYA (2)" ya da sakin cihazında "KOPYA"
  /// ([receiptStampText]). [fonts] verilmezse gömülü Roboto yüklenir (testler Helvetica geçmez: Türkçe harf
  /// kaybolur).
  static Future<Uint8List> generateReceiptPdf({
    required Receipt receipt,
    required String stamp,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _buildReceipt(_ReceiptJob(compress: PdfFinanceService.debugCompress, fonts: set, receipt: receipt, stamp: stamp, printedAt: printedAt ?? DateTime.now()));
  }

  /// Daire ekstresi PDF'i.
  static Future<Uint8List> generateStatementPdf({
    required ApartmentStatement statement,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _run(
      statement.items.length,
      _buildStatement,
      _StatementJob(compress: PdfFinanceService.debugCompress, fonts: set, statement: statement, printedAt: printedAt ?? DateTime.now()),
    );
  }

  static Future<Uint8List> generateAgingPdf({
    required AgingReport report,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _run(report.items.length, _buildAging, _AgingJob(compress: PdfFinanceService.debugCompress, fonts: set, report: report, printedAt: printedAt ?? DateTime.now()));
  }

  static Future<Uint8List> generateIncomeExpensePdf({
    required IncomeExpenseReport report,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _run(
      report.months.length,
      _buildIncomeExpense,
      _IncomeExpenseJob(compress: PdfFinanceService.debugCompress, fonts: set, report: report, printedAt: printedAt ?? DateTime.now()),
    );
  }

  static Future<Uint8List> generateExpenseAnalysisPdf({
    required ExpenseAnalysisReport report,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _run(
      report.categories.length + (report.forecast?.items.length ?? 0),
      _buildExpenseAnalysis,
      _ExpenseAnalysisJob(compress: PdfFinanceService.debugCompress, fonts: set, report: report, printedAt: printedAt ?? DateTime.now()),
    );
  }

  static Future<Uint8List> generateCashPositionPdf({
    required CashPositionReport report,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _run(report.items.length, _buildCashPosition, _CashPositionJob(compress: PdfFinanceService.debugCompress, fonts: set, report: report, printedAt: printedAt ?? DateTime.now()));
  }

  static Future<Uint8List> generateBoardSummaryPdf({
    required BoardSummaryReport report,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    return _run(
      report.expenseByCategory.length + report.topExpenses.length + report.cashAccounts.length,
      _buildBoardSummary,
      _BoardJob(compress: PdfFinanceService.debugCompress, fonts: set, report: report, printedAt: printedAt ?? DateTime.now()),
    );
  }

  static Future<Uint8List> _run<M>(int rows, Future<Uint8List> Function(M job) build, M job) {
    if (rows > isolateRowThreshold) {
      return BackgroundWork.run<M, Uint8List>(build, job, debugLabel: 'pdf.finance');
    }
    return build(job);
  }

  // --- Yazdır / paylaş ----------------------------------------------------------------------------

  /// Yazdırma / "PDF olarak kaydet" önizlemesini açar.
  static Future<void> printPdf(Uint8List bytes, {required String fileName}) async {
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => bytes, name: fileName);
  }

  /// Paylaşım menüsünü açar (share_plus). [shareFn] testler içindir.
  static Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    String? subject,
    Future<ShareResult> Function(ShareParams params)? shareFn,
  }) async {
    final share = shareFn ?? SharePlus.instance.share;
    await share(
      ShareParams(
        files: <XFile>[XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
        fileNameOverrides: <String>[fileName],
        subject: subject,
      ),
    );
  }
}

// --- Ortak biçim yardımcıları -------------------------------------------------------------------

String _date(DateTime? d) {
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year.toString().padLeft(4, '0')}';
}

String _dateTime(DateTime? d) => d == null ? '-' : formatIstanbulDateTime(d);

/// "AB12CD34EF56" -> "AB12-CD34-EF56" (okunaklı); 12 karakter değilse olduğu gibi.
String formatVerificationCode(String code) {
  final clean = code.trim().toUpperCase();
  if (clean.length != 12) return clean;
  return '${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8)}';
}


const PdfColor _ink = PdfColor.fromInt(0xFF1F2933);
const PdfColor _muted = PdfColor.fromInt(0xFF52606D);
const PdfColor _line = PdfColor.fromInt(0xFFCBD2D9);
const PdfColor _soft = PdfColor.fromInt(0xFFF1F5F9);
const PdfColor _danger = PdfColor.fromInt(0xFFB42318);

pw.ThemeData _theme(PdfFontSet fonts) {
  final f = fonts.resolve();
  return pw.ThemeData.withFont(base: f.regular, bold: f.bold, fontFallback: <pw.Font>[f.regular]);
}

// --- Makbuz ----------------------------------------------------------------------------------

class _ReceiptJob {
  const _ReceiptJob({this.compress = true, required this.fonts, required this.receipt, required this.stamp, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final Receipt receipt;
  final String stamp;
  final DateTime printedAt;
}

Future<Uint8List> _buildReceipt(_ReceiptJob job) async {
  final r = job.receipt;
  final doc = pw.Document(title: 'Makbuz ${r.number}', author: r.siteName, creator: 'Aidat ve Finans', compress: job.compress);
  final cancelledOriginal = !r.isCancellation && r.isCancelled;
  final showCancelMark = r.isCancellation || cancelledOriginal;
  final payer = receiptPayerText(r.payerParty, r.payerName);

  pw.Widget field(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.SizedBox(width: 130, child: pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: _muted))),
        pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: _theme(job.fonts),
        buildBackground: showCancelMark
            ? (pw.Context context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.14,
                    child: pw.Transform.rotate(
                      angle: 0.6,
                      child: pw.Text(
                        'İPTAL',
                        style: pw.TextStyle(fontSize: 150, fontWeight: pw.FontWeight.bold, color: _danger),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        r.siteName.isEmpty ? 'Site yönetimi' : r.siteName,
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('Site yönetimi', style: const pw.TextStyle(fontSize: 10, color: _muted)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.5)),
                  child: pw.Text(job.stamp, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
            pw.SizedBox(height: 22),
            pw.Center(
              child: pw.Text(
                r.isCancellation ? 'İPTAL MAKBUZU' : 'TAHSİLAT MAKBUZU',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'Makbuz No: ${r.number}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (cancelledOriginal) ...<pw.Widget>[
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _danger, width: 1.2)),
                child: pw.Text(
                  r.cancelledByNumber == null
                      ? 'İPTAL EDİLMİŞTİR'
                      : 'İPTAL EDİLMİŞTİR — iptal makbuzu No ${r.cancelledByNumber}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _danger),
                ),
              ),
            ],
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), color: _soft),
              child: pw.Column(
                children: <pw.Widget>[
                  field('Düzenleme tarihi', _date(r.issuedOn)),
                  field('Tahsilat tarihi', _date(r.paidOn)),
                  field('Daire', r.apartmentLabel.isEmpty ? '-' : r.apartmentLabel),
                  field('Ödeyen', payer.isEmpty ? '-' : payer),
                  field('Ödeme yöntemi', r.method?.label ?? '-'),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.2)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    r.isCancellation ? 'İptal edilen tutar' : 'Tahsil edilen tutar',
                    style: const pw.TextStyle(fontSize: 10, color: _muted),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    formatMinor(r.amountMinor),
                    style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Yazıyla: ${moneySemanticLabel(r.amountMinor)}', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            if (r.isCancellation) ...<pw.Widget>[
              pw.Text(
                r.cancelsNumber == null
                    ? 'Bu makbuz, daha önce düzenlenmiş bir makbuzu iptal eder.'
                    : 'Bu makbuz ${r.cancelsNumber} numaralı makbuzu iptal eder.',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'İptal nedeni: ${receiptCancelReasonLabel(r.cancelReasonCode)}.',
                style: const pw.TextStyle(fontSize: 10.5),
              ),
              pw.SizedBox(height: 8),
            ],
            // Sabit metinler sunucudan gelirse (şablon) onlar, gelmezse paketlenmiş sürüm 1 metinleri.
            pw.Text(r.template?.mahsupText ?? PdfFinanceService.mahsupText, style: const pw.TextStyle(fontSize: 10)),
            if (r.cekince) ...<pw.Widget>[
              pw.SizedBox(height: 6),
              pw.Text(r.template?.cekinceText ?? PdfFinanceService.cekinceText, style: const pw.TextStyle(fontSize: 10)),
            ],
            pw.SizedBox(height: 6),
            pw.Text(
              r.template?.disclaimerText ?? PdfFinanceService.ledgerDisclaimer,
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
            pw.SizedBox(height: 26),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text('Düzenleyen', style: const pw.TextStyle(fontSize: 10, color: _muted)),
                      pw.Text(
                        r.issuerName ?? '-',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  width: 180,
                  height: 70,
                  alignment: pw.Alignment.topLeft,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
                  child: pw.Text('Kaşe / İmza', style: const pw.TextStyle(fontSize: 9, color: _muted)),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Divider(color: _line),
            pw.Text(
              'Doğrulama kodu: ${formatVerificationCode(r.verificationCode)}  •  Şablon sürümü ${r.templateVersion}  •  '
              'Basım: ${_dateTime(job.printedAt)}',
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

// --- Rapor iskeleti --------------------------------------------------------------------------

pw.Widget _reportHeader(String title, String siteName, String? subtitle) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.2))),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (siteName.isNotEmpty) pw.Text(siteName, style: const pw.TextStyle(fontSize: 11)),
        if (subtitle != null && subtitle.isNotEmpty)
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
      ],
    ),
  );
}

/// [footer]: sunucunun rapor altbilgisi (tek kaynak); yoksa paketlenmiş metin.
pw.Widget _reportFooter(pw.Context context, DateTime printedAt, {String? extra, String? footer}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: <pw.Widget>[
      pw.Divider(color: _line),
      if (extra != null) pw.Text(extra, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              '${footer ?? PdfFinanceService.reportDisclaimer}  Basım: ${_dateTime(printedAt)}',
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          ),
          pw.Text('${context.pageNumber}/${context.pagesCount}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        ],
      ),
    ],
  );
}

String? _closedNote(ReportMeta meta) {
  final through = meta.closedThrough;
  if (through == null) return 'Kapatılmış dönem yok: rakamlar kesinleşmemiştir.';
  return 'Kapalı dönem: ${through.label} ve öncesi. Sonraki aylar kesinleşmemiştir.';
}

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  required Map<int, pw.Alignment> alignments,
  Map<int, pw.TableColumnWidth>? widths,
  double fontSize = 8.5,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold),
    cellStyle: pw.TextStyle(fontSize: fontSize),
    headerDecoration: const pw.BoxDecoration(color: _soft),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line, width: 0.4),
      bottom: pw.BorderSide(color: _line),
      top: pw.BorderSide(color: _line),
    ),
    cellAlignments: alignments,
    columnWidths: widths,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    headerCellDecoration: const pw.BoxDecoration(color: _soft),
  );
}

// --- Ekstre -----------------------------------------------------------------------------------

class _StatementJob {
  const _StatementJob({this.compress = true, required this.fonts, required this.statement, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final ApartmentStatement statement;
  final DateTime printedAt;
}

String _entryTitle(LedgerEntry e) {
  if (e.isReversal) return 'Ters kayıt'; // tazminatın ters kaydı da "Ters kayıt"tır (borç/alacak sütunu tutarı doğru gösterir)
  if (e.isLateFee) return 'Gecikme tazminatı';
  switch (e.kind) {
    case LedgerKind.charge:
      return e.definitionName ?? 'Borç';
    case LedgerKind.payment:
      return e.method == null ? 'Tahsilat' : 'Tahsilat (${e.method!.label})';
    case LedgerKind.reversal:
      return 'Ters kayıt';
    case LedgerKind.unknown:
      return 'Hareket';
  }
}

Future<Uint8List> _buildStatement(_StatementJob job) async {
  final s = job.statement;
  final doc = pw.Document(title: 'Hesap ekstresi', creator: 'Aidat ve Finans', compress: job.compress);
  // Sunucu `label` zaten "A Blok - 5"tir: blok adı tekrarlanmaz (ekranla aynı kural).
  final apartment = crmApartmentTitle(s.apartment.blockName, s.apartment.label);
  final rows = <List<String>>[
    <String>['', 'Önceki bakiye', '', '', formatMinor(s.openingBalanceMinor)],
    for (final item in s.items)
      <String>[
        _date(item.entry.entryDate),
        [
          _entryTitle(item.entry),
          if (item.entry.receipt != null) item.entry.receipt!.number,
        ].join(' • '),
        item.entry.amountMinor > 0 ? formatMinor(item.entry.amountMinor) : '',
        item.entry.amountMinor < 0 ? formatMinor(-item.entry.amountMinor) : '',
        formatMinor(item.runningBalanceMinor),
      ],
    <String>['', 'Dönem sonu bakiye', '', '', formatMinor(s.closingBalanceMinor)],
  ];
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), theme: _theme(job.fonts)),
      header: (pw.Context context) => _reportHeader(
        'Hesap Ekstresi',
        s.meta.siteName,
        // İP-1A: ekstre tek hesabınsa hesabın adı yazılır (salt okunur kiracı hesabı işaretlenir).
        '$apartment'
        '${s.accountParty == null ? '' : '  •  ${s.accountParty!.label}${s.readOnly ? ' (salt okunur)' : ''}'}'
        '  •  ${_date(s.from)} - ${_date(s.to)}',
      ),
      footer: (pw.Context context) => _reportFooter(context, job.printedAt, extra: _closedNote(s.meta), footer: s.meta.footer),
      build: (pw.Context context) => <pw.Widget>[
        if (s.visibleFrom != null) ...[
          pw.Text(myFinanceScopeNote(s.visibleFrom!), style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 6),
        ],
        _table(
          headers: <String>['Tarih', 'Açıklama', 'Borç', 'Alacak', 'Bakiye'],
          rows: rows,
          alignments: <int, pw.Alignment>{
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          widths: <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(58),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.5),
          },
          fontSize: 9,
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Toplamlar — Borçlandırılan: ${formatMinor(s.totals.chargedMinor)}  •  '
          'Gecikme tazminatı: ${formatMinor(s.totals.lateFeeMinor)}  •  '
          'Ödenen: ${formatMinor(s.totals.paidMinor)}  •  İptal edilen: ${formatMinor(s.totals.reversedMinor)}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (s.overdueMinor != null)
          pw.Text('Vadesi geçmiş tutar: ${formatMinor(s.overdueMinor!)}', style: const pw.TextStyle(fontSize: 9)),
        if (s.offsetNote) pw.Text(myFinanceOffsetNote(statement: true), style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );
  return doc.save();
}

// --- Yaşlandırma -------------------------------------------------------------------------------

class _AgingJob {
  const _AgingJob({this.compress = true, required this.fonts, required this.report, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final AgingReport report;
  final DateTime printedAt;
}

Future<Uint8List> _buildAging(_AgingJob job) async {
  final r = job.report;
  final doc = pw.Document(title: 'Borç yaşlandırma raporu', creator: 'Aidat ve Finans', compress: job.compress);
  final headers = <String>[
    'Daire',
    for (final b in AgingBucket.values) b.label,
    'Alacak',
    'Gecikmiş toplam',
  ];
  final rows = <List<String>>[
    for (final item in r.items)
      <String>[
        crmApartmentTitle(item.blockName, item.label),
        for (final b in AgingBucket.values) formatMinor(item.buckets[b] ?? 0, symbol: false),
        formatMinor(item.creditMinor, symbol: false),
        formatMinor(item.totalOverdueMinor, symbol: false),
      ],
    <String>[
      'TOPLAM',
      for (final b in AgingBucket.values) formatMinor(r.totals[b] ?? 0, symbol: false),
      formatMinor(r.creditMinor, symbol: false),
      formatMinor(r.totalOverdueMinor, symbol: false),
    ],
  ];
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4.landscape, margin: const pw.EdgeInsets.all(28), theme: _theme(job.fonts)),
      header: (pw.Context context) => _reportHeader(
        'Borç / Alacak Yaşlandırma Raporu',
        r.meta.siteName,
        'Tarih: ${_date(r.asOf)}  •  Tutarlar ₺, vade gecikmesine göre (en eski borçtan mahsup)',
      ),
      footer: (pw.Context context) => _reportFooter(context, job.printedAt, extra: _closedNote(r.meta), footer: r.meta.footer),
      build: (pw.Context context) => <pw.Widget>[
        _table(
          headers: headers,
          rows: rows,
          alignments: <int, pw.Alignment>{
            0: pw.Alignment.centerLeft,
            for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight,
          },
          widths: <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(2.2)},
          fontSize: 8,
        ),
        if (r.lateFeeOutstandingMinor != null) ...<pw.Widget>[
          pw.SizedBox(height: 8),
          pw.Text(
            'Bilgi: ödenmemiş gecikme tazminatı toplamı ${formatMinor(r.lateFeeOutstandingMinor!)} (kovalara dahildir).',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}


// --- Gider analizi (R1) -------------------------------------------------------------------------

class _ExpenseAnalysisJob {
  const _ExpenseAnalysisJob({this.compress = true, required this.fonts, required this.report, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final ExpenseAnalysisReport report;
  final DateTime printedAt;
}

/// pw.Chart çubuk grafiği (rutin / beklenmedik / gelir). Değerler TL (kuruş / 100); negatif net 0'a sabitlenir.
pw.Widget _analysisChart(ExpenseAnalysisReport r) {
  double y(int minor) => minor <= 0 ? 0 : minor / 100.0;
  var maxY = 1.0;
  for (final m in r.months) {
    for (final v in <int>[m.expenseMinor, m.incomeMinor]) {
      if (y(v) > maxY) maxY = y(v);
    }
  }
  final ticks = <double>[for (var i = 0; i <= 4; i++) (maxY * 1.1 * i / 4).roundToDouble()];
  final labels = <String>[for (final m in r.months) m.period.length >= 7 ? '${m.period.substring(5, 7)}.${m.period.substring(2, 4)}' : m.period];
  List<pw.PointChartValue> points(int Function(AnalysisMonth) pick) => <pw.PointChartValue>[
    for (var i = 0; i < r.months.length; i++) pw.PointChartValue(i.toDouble(), y(pick(r.months[i]))),
  ];
  return pw.SizedBox(
    height: 170,
    child: pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis.fromStrings(labels, marginStart: 24, marginEnd: 24, ticks: true),
        yAxis: pw.FixedAxis(ticks, format: (num v) => v.toStringAsFixed(0), divisions: true),
      ),
      datasets: <pw.Dataset>[
        pw.BarDataSet(color: PdfColors.blue600, legend: 'Rutin gider', width: 9, offset: -11, data: points((m) => m.routineMinor)),
        pw.BarDataSet(color: PdfColors.orange600, legend: 'Beklenmedik gider', width: 9, offset: 0, data: points((m) => m.unexpectedMinor)),
        pw.BarDataSet(color: PdfColors.green600, legend: 'Gelir (net tahsilat)', width: 9, offset: 11, data: points((m) => m.incomeMinor)),
      ],
    ),
  );
}

Future<Uint8List> _buildExpenseAnalysis(_ExpenseAnalysisJob job) async {
  final r = job.report;
  final doc = pw.Document(title: 'Gider analizi', creator: 'Aidat ve Finans', compress: job.compress);
  final forecast = r.forecast;
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(30), theme: _theme(job.fonts)),
      header: (pw.Context context) => _reportHeader(
        'Gider Analizi',
        r.meta.siteName,
        'Son ${r.window} ay, bitiş ${r.to}  •  Tutarlar ₺  •  Grafik değerleri ₺',
      ),
      footer: (pw.Context context) => _reportFooter(context, job.printedAt, extra: _closedNote(r.meta), footer: r.meta.footer),
      build: (pw.Context context) => <pw.Widget>[
        if (r.comparisonSentence != null) pw.Text(r.comparisonSentence!, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        _analysisChart(r),
        pw.SizedBox(height: 10),
        _table(
          headers: <String>['Ay', 'Rutin', 'Beklenmedik', 'Gider', 'Gelir'],
          rows: <List<String>>[
            for (final m in r.months)
              <String>[
                m.period,
                formatMinor(m.routineMinor, symbol: false),
                formatMinor(m.unexpectedMinor, symbol: false),
                formatMinor(m.expenseMinor, symbol: false),
                formatMinor(m.incomeMinor, symbol: false),
              ],
            <String>[
              'TOPLAM',
              formatMinor(r.routineMinor, symbol: false),
              formatMinor(r.unexpectedMinor, symbol: false),
              formatMinor(r.expenseMinor, symbol: false),
              formatMinor(r.incomeMinor, symbol: false),
            ],
          ],
          alignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft, for (var i = 1; i < 5; i++) i: pw.Alignment.centerRight},
        ),
        if (r.categories.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 14),
          pw.Text('Kategori kırılımı', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _table(
            headers: <String>['Kategori', 'Rutin', 'Beklenmedik', 'Toplam', 'Pay', 'Önceki', 'Değişim'],
            rows: <List<String>>[
              for (final c in r.categories)
                <String>[
                  c.name,
                  formatMinor(c.routineMinor, symbol: false),
                  formatMinor(c.unexpectedMinor, symbol: false),
                  formatMinor(c.totalMinor, symbol: false),
                  c.shareBp == null ? '-' : formatPercentBp(c.shareBp!),
                  formatMinor(c.previousTotalMinor, symbol: false),
                  c.changeBp == null ? '-' : formatPercentBp(c.changeBp!),
                ],
            ],
            alignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft, for (var i = 1; i < 7; i++) i: pw.Alignment.centerRight},
            widths: <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(1.8)},
          ),
        ],
        if (forecast != null) ...<pw.Widget>[
          pw.SizedBox(height: 14),
          pw.Text('Gelecek yıl tahmini', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            'Taban: ${forecast.baseFrom} - ${forecast.baseTo} (${forecast.baseMonths} ay)  •  Rutin artış: ${formatPercentBp(forecast.increaseBp)}'
            '${forecast.note == null ? '' : '  •  ${forecast.note}'}',
            style: const pw.TextStyle(fontSize: 8.5),
          ),
          pw.SizedBox(height: 4),
          _table(
            headers: <String>['Kategori', 'Taban rutin', 'Tahmini rutin', 'Beklenmedik (yıllık)', 'Tahmin'],
            rows: <List<String>>[
              for (final i in forecast.items)
                <String>[
                  i.name,
                  formatMinor(i.baseRoutineMinor, symbol: false),
                  formatMinor(i.forecastRoutineMinor, symbol: false),
                  formatMinor(i.annualUnexpectedMinor, symbol: false),
                  formatMinor(i.forecastMinor, symbol: false),
                ],
              <String>['TOPLAM', '', '', '', formatMinor(forecast.totalMinor, symbol: false)],
            ],
            alignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft, for (var i = 1; i < 5; i++) i: pw.Alignment.centerRight},
            widths: <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(1.8)},
          ),
        ],
        pw.SizedBox(height: 8),
        pw.Text(
          'Tür kaydı olmayan ${r.derivedCount} gider kategoriye göre sınıflandırıldı. Tahmin bir öngörüdür, taahhüt değildir.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  return doc.save();
}

// --- Gelir-gider --------------------------------------------------------------------------------

class _IncomeExpenseJob {
  const _IncomeExpenseJob({this.compress = true, required this.fonts, required this.report, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final IncomeExpenseReport report;
  final DateTime printedAt;
}

Future<Uint8List> _buildIncomeExpense(_IncomeExpenseJob job) async {
  final r = job.report;
  final doc = pw.Document(title: 'Aylık gelir-gider raporu', creator: 'Aidat ve Finans', compress: job.compress);
  final rows = <List<String>>[
    for (final m in r.months)
      <String>[
        r.meta.isFinal(m.period) ? m.period.label : '${m.period.label} *',
        formatMinor(m.chargedMinor, symbol: false),
        formatMinor(m.lateFeeMinor, symbol: false),
        formatMinor(m.collectedMinor, symbol: false),
        m.collectionRateBp == null ? '-' : formatPercentBp(m.collectionRateBp!),
        formatMinor(m.expenseMinor, symbol: false),
        formatMinor(m.netCashMinor, symbol: false),
      ],
    <String>[
      'TOPLAM',
      formatMinor(r.chargedMinor, symbol: false),
      formatMinor(r.months.fold<int>(0, (a, m) => a + m.lateFeeMinor), symbol: false),
      formatMinor(r.collectedMinor, symbol: false),
      '',
      formatMinor(r.expenseMinor, symbol: false),
      formatMinor(r.netCashMinor, symbol: false),
    ],
  ];
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(30), theme: _theme(job.fonts)),
      header: (pw.Context context) => _reportHeader(
        'Aylık Gelir-Gider Raporu',
        r.meta.siteName,
        '${r.from?.label ?? '-'} - ${r.to?.label ?? '-'}  •  Tutarlar ₺  •  * kesinleşmemiş ay',
      ),
      footer: (pw.Context context) => _reportFooter(context, job.printedAt, extra: _closedNote(r.meta), footer: r.meta.footer),
      build: (pw.Context context) => <pw.Widget>[
        _table(
          headers: <String>['Ay', 'Tahakkuk', 'Gecikme taz.', 'Tahsilat', 'Oran', 'Gider', 'Net nakit'],
          rows: rows,
          alignments: <int, pw.Alignment>{
            0: pw.Alignment.centerLeft,
            for (var i = 1; i < 7; i++) i: pw.Alignment.centerRight,
          },
          widths: <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(1.6)},
        ),
        if (r.expenseByCategory.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 14),
          pw.Text('Gider kategorileri', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _table(
            headers: <String>['Kategori', 'Toplam'],
            rows: <List<String>>[
              for (final c in r.expenseByCategory) <String>[c.categoryName, formatMinor(c.totalMinor, symbol: false)],
            ],
            alignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

// --- Kasa durumu --------------------------------------------------------------------------------

class _CashPositionJob {
  const _CashPositionJob({this.compress = true, required this.fonts, required this.report, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final CashPositionReport report;
  final DateTime printedAt;
}

Future<Uint8List> _buildCashPosition(_CashPositionJob job) async {
  final r = job.report;
  final doc = pw.Document(title: 'Kasa durumu raporu', creator: 'Aidat ve Finans', compress: job.compress);
  final rows = <List<String>>[
    for (final a in r.items)
      <String>[
        a.name,
        formatMinor(a.openingMinor, symbol: false),
        formatMinor(a.collectionsMinor, symbol: false),
        formatMinor(a.expensesMinor, symbol: false),
        formatMinor(a.transfersInMinor, symbol: false),
        formatMinor(a.transfersOutMinor, symbol: false),
        formatMinor(a.adjustmentsMinor, symbol: false),
        formatMinor(a.reversalsMinor, symbol: false),
        formatMinor(a.balanceMinor, symbol: false),
      ],
    <String>['TOPLAM', '', '', '', '', '', '', '', formatMinor(r.totalBalanceMinor, symbol: false)],
  ];
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4.landscape, margin: const pw.EdgeInsets.all(28), theme: _theme(job.fonts)),
      header: (pw.Context context) => _reportHeader(
        'Kasa / Banka Durumu',
        r.meta.siteName,
        'Tarih: ${_date(r.asOf)}  •  Tutarlar ₺',
      ),
      footer: (pw.Context context) => _reportFooter(context, job.printedAt, extra: _closedNote(r.meta), footer: r.meta.footer),
      build: (pw.Context context) => <pw.Widget>[
        _table(
          headers: <String>[
            'Hesap', 'Açılış', 'Tahsilat', 'Gider', 'Aktarım (giriş)', 'Aktarım (çıkış)', 'Düzeltme', 'Ters kayıt', 'Bakiye',
          ],
          rows: rows,
          alignments: <int, pw.Alignment>{
            0: pw.Alignment.centerLeft,
            for (var i = 1; i < 9; i++) i: pw.Alignment.centerRight,
          },
          widths: <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(2)},
        ),
        pw.SizedBox(height: 8),
        for (final a in r.items)
          if (a.lastReconciliation != null)
            pw.Text(
              '${a.name}: son mutabakat ${_date(a.lastReconciliation!.asOfDate)}, '
              'fark ${formatMinor(a.lastReconciliation!.differenceMinor)}'
              '${a.lastReconciliation!.adjusted == true ? ' (düzeltme hareketiyle giderildi)' : ''}',
              style: const pw.TextStyle(fontSize: 9),
            ),
        if (r.unassigned.any)
          pw.Text(
            'Uyarı: hesaba eşlenmemiş ${r.unassigned.count} tahsilat var (toplam ${formatMinor(r.unassigned.totalMinor)}).',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _danger),
          ),
      ],
    ),
  );
  return doc.save();
}

// --- Yönetim kurulu özeti ------------------------------------------------------------------------

class _BoardJob {
  const _BoardJob({this.compress = true, required this.fonts, required this.report, required this.printedAt});

  final bool compress;
  final PdfFontSet fonts;
  final BoardSummaryReport report;
  final DateTime printedAt;
}

Future<Uint8List> _buildBoardSummary(_BoardJob job) async {
  final r = job.report;
  final doc = pw.Document(title: 'Yönetim kurulu özet raporu', creator: 'Aidat ve Finans', compress: job.compress);

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
  );
  pw.Widget line(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      children: <pw.Widget>[
        pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10))),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), theme: _theme(job.fonts)),
      header: (pw.Context context) => _reportHeader(
        'Yönetim Kurulu Özet Raporu',
        r.meta.siteName,
        '${r.from?.label ?? '-'} - ${r.to?.label ?? '-'}',
      ),
      footer: (pw.Context context) => _reportFooter(context, job.printedAt, extra: _closedNote(r.meta), footer: r.meta.footer),
      build: (pw.Context context) => <pw.Widget>[
        if (r.warnings.isNotEmpty) ...<pw.Widget>[
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _danger)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text('Uyarılar', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _danger)),
                for (final w in r.warnings) pw.Text('• ${w.message}', style: const pw.TextStyle(fontSize: 9.5)),
              ],
            ),
          ),
        ],
        if (r.chargedMinor != null || r.collectedMinor != null) ...<pw.Widget>[
          heading('Tahakkuk ve tahsilat'),
          if (r.chargedMinor != null) line('Tahakkuk', formatMinor(r.chargedMinor!)),
          if (r.lateFeeMinor != null) line('Gecikme tazminatı', formatMinor(r.lateFeeMinor!)),
          if (r.collectedMinor != null) line('Tahsilat', formatMinor(r.collectedMinor!)),
          if (r.collectionRateBp != null) line('Tahsilat oranı', formatPercentBp(r.collectionRateBp!)),
        ],
        if (r.debtTotalMinor != null) ...<pw.Widget>[
          heading('Alacak durumu'),
          line('Vadesi geçmiş borç', formatMinor(r.debtTotalMinor!)),
          if (r.debtorCount != null)
            line(
              'Borçlu daire',
              boardDebtorText(r.debtorCount!, r.apartmentCount, r.debtorRateBp),
            ),
          for (final a in r.overdueAging) line('${a.label} (${a.count} daire)', formatMinor(a.totalMinor)),
          if (r.notDueMinor != null)
            line('Vadesi gelmemiş (bilgi, toplama dahil değil) (${r.notDueCount ?? 0} daire)', formatMinor(r.notDueMinor!)),
        ],
        if (r.expenseTotalMinor != null) ...<pw.Widget>[
          heading('Gider'),
          line('Toplam gider', formatMinor(r.expenseTotalMinor!)),
          for (final c in r.expenseByCategory) line(c.categoryName, formatMinor(c.totalMinor)),
          if (r.topExpenses.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 4),
            pw.Text('En büyük gider kalemleri', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            for (final e in r.topExpenses) line('${e.categoryName} • ${_date(e.expenseDate)}', formatMinor(e.amountMinor)),
          ],
        ],
        if (r.cashAccounts.isNotEmpty || r.cashTotalMinor != null) ...<pw.Widget>[
          heading('Kasa ve banka'),
          for (final a in r.cashAccounts)
            line(
              a.lastReconciliation == null
                  ? a.name
                  : '${a.name} (mutabakat farkı ${formatMinor(a.lastReconciliation!.differenceMinor)})',
              formatMinor(a.balanceMinor),
            ),
          if (r.cashTotalMinor != null) line('Toplam', formatMinor(r.cashTotalMinor!)),
          if (r.unassigned != null && r.unassigned!.any)
            line('Hesaba eşlenmemiş tahsilat (${r.unassigned!.count})', formatMinor(r.unassigned!.totalMinor)),
        ],
        if (r.lateFeeTotalMinor != null) ...<pw.Widget>[
          heading('Gecikme tazminatı'),
          line('Dönem toplamı', formatMinor(r.lateFeeTotalMinor!)),
          if (r.lateFeeWaivedCount != null) line('Muaf tutulan daire', '${r.lateFeeWaivedCount}'),
        ],
        if (r.remindersSentCount != null) ...<pw.Widget>[
          heading('Borç hatırlatma'),
          line('Gönderilen hatırlatma', '${r.remindersSentCount}'),
        ],
        if (r.debtors.isNotEmpty) ...<pw.Widget>[
          heading('En yüksek borçlu daireler'),
          for (final d in r.debtors) line(d.label, formatMinor(d.totalMinor)),
        ],
      ],
    ),
  );
  return doc.save();
}
