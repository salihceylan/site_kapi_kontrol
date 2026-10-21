import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:site_kapi_kontrol/models/budget_models.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart' show DecisionPdfActions, DecisionPdfOutcome;
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/money.dart' show formatMinor, formatSignedMinor;

/// İşletme projesi (bütçe) PDF'i: proje bilgisi (durum, tebliğ ve itiraz tarihleri, geçici proje süresi) ve kategori bazlı
/// planlanan - gerçekleşen tablosu. Yazı tipi uygulamaya gömülü Roboto'dur (ağ yok). Dosya adı ASCII'dir.
class PdfBudgetService {
  PdfBudgetService._();

  static const String legalNotice =
      'Bu belge bilgilendirme amaçlıdır; işletme projesinin kabulü, tebliği ve itiraz süreleri Kat Mülkiyeti Kanunu ve karar defteri '
      'kayıtlarına göre yönetimin sorumluluğundadır.';

  static String fileName(String siteName, int year) {
    final site = PdfFinanceService.asciiName(siteName);
    return 'Isletme_Projesi_${site.isEmpty ? 'Site' : site}_$year.pdf';
  }

  static Future<Uint8List> generate({
    required String siteName,
    required BudgetComparison comparison,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    final f = set.resolve();
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, fontFallback: <pw.Font>[f.regular]);
    final p = comparison.project;
    final site = siteName.trim().isEmpty ? 'Site yönetimi' : siteName.trim();
    final doc = pw.Document(title: 'İşletme Projesi ${p.year}', author: site, creator: 'İşletme Projesi');
    String day(DateTime? d) => d == null ? '-' : formatDateField(d);

    final info = <String>[
      'Durum: ${p.status.label}',
      if (p.isProvisional) 'Geçici proje; bitiş: ${day(p.provisionalUntil)}${p.remainingDays == null ? '' : ' (kalan ${p.remainingDays} gün)'}',
      if (p.notifiedAt != null) 'Tebliğ tarihi: ${day(p.notifiedAt)}',
      if (p.objectionEnds != null) 'İtiraz süresi sonu: ${day(p.objectionEnds)}',
    ];
    final stamp = printedAt ?? DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), theme: theme),
        header: (pw.Context c) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(site, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('İşletme Projesi ${p.year}', style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
        footer: (pw.Context c) => pw.Text(
          '${formatDateField(stamp)}  •  Sayfa ${c.pageNumber}/${c.pagesCount}  •  $legalNotice',
          style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF52606D)),
        ),
        build: (pw.Context c) => <pw.Widget>[
          pw.Text(p.title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final line in info) pw.Text(line, style: const pw.TextStyle(fontSize: 10.5)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Kategori', 'Planlanan', 'Gerçekleşen', 'Fark', '%'],
            data: <List<String>>[
              for (final r in <BudgetCompareRow>[...comparison.rows, comparison.totals])
                <String>[
                  r.categoryName,
                  formatMinor(r.plannedMinor),
                  formatMinor(r.actualMinor),
                  formatSignedMinor(r.varianceMinor),
                  r.usedPct == null ? '-' : r.usedPct!.toStringAsFixed(1).replaceAll('.', ','),
                ],
            ],
            headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
            cellAlignments: const <int, pw.Alignment>{
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 8),
          pw.Text('Fark = gerçekleşen - planlanan; artı değer bütçe aşımıdır. Gerçekleşen, yılın iptal edilmemiş gider kayıtlarıdır.', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return doc.save();
  }

  /// PDF'i üretir ve platforma uygun yolla verir (karar defteri PDF'i ile aynı teslim yolu).
  static Future<DecisionPdfOutcome> download({required String siteName, required BudgetComparison comparison}) async {
    final bytes = await generate(siteName: siteName, comparison: comparison);
    return DecisionPdfActions.deliver(bytes, fileName: fileName(siteName, comparison.project.year), subject: 'İşletme Projesi ${comparison.project.year}');
  }
}
