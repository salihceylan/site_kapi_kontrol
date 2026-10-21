import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:site_kapi_kontrol/models/annual_report.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart' show DecisionPdfActions, DecisionPdfOutcome;
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;

/// Faaliyet raporu PDF'i: dokuz bölüm; yönetici düzenlediyse onun metni, yoksa sistem taslağı. Yazı tipi uygulamaya gömülü
/// Roboto'dur (ağ yok). Dosya adı ASCII'dir.
class PdfAnnualReportService {
  PdfAnnualReportService._();

  static const String legalNotice =
      'Bu rapor sistem kayıtlarından hazırlanmış taslaktır; yönetim kurulu raporu ve genel kurula sunulacak belgeler yönetimin sorumluluğundadır.';

  static String fileName(String siteName, int year) {
    final site = PdfFinanceService.asciiName(siteName);
    return 'Faaliyet_Raporu_${site.isEmpty ? 'Site' : site}_$year.pdf';
  }

  static Future<Uint8List> generate({required String siteName, required AnnualReport report, DateTime? printedAt, PdfFontSet? fonts}) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    final f = set.resolve();
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, fontFallback: <pw.Font>[f.regular]);
    final site = siteName.trim().isEmpty ? 'Site yönetimi' : siteName.trim();
    final stamp = printedAt ?? DateTime.now();
    final doc = pw.Document(title: 'Faaliyet Raporu ${report.year}', author: site, creator: 'Faaliyet Raporu');
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), theme: theme),
        header: (pw.Context c) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(site, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('Faaliyet Raporu ${report.year}', style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
        footer: (pw.Context c) => pw.Text(
          '${formatDateField(stamp)}  •  Sayfa ${c.pageNumber}/${c.pagesCount}  •  $legalNotice',
          style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF52606D)),
        ),
        build: (pw.Context c) => <pw.Widget>[
          pw.Text('$site ${report.year} Yılı Faaliyet Raporu', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          for (final key in kAnnualReportSections) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            pw.Text(kAnnualReportTitles[key] ?? key, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            for (final line in annualReportFinalLines(report, key)) pw.Text(line, style: const pw.TextStyle(fontSize: 10.5)),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static Future<DecisionPdfOutcome> download({required String siteName, required AnnualReport report}) async {
    final bytes = await generate(siteName: siteName, report: report);
    return DecisionPdfActions.deliver(bytes, fileName: fileName(siteName, report.year), subject: 'Faaliyet Raporu ${report.year}');
  }
}
