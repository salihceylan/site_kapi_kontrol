import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart' show BulkFileSharer;
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/services/pdf_font_set.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart' show formatDateField;
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';

/// Karar Defteri PDF'i: seçilen yılın KESİN kararları (numara, tarih, tür, başlık, metin, oylama, katılanlar,
/// kesinleştirme bilgisi); üstbilgi (site adı, yıl) ve altbilgi notu ([kDecisionLegalNotice]).
///
/// Kurallar (finans PDF'leriyle aynı):
/// - Yazı tipi uygulamaya GÖMÜLÜ Roboto'dur ([PdfFontSet.loadBundled]); ağdan indirilmez, çevrimdışıyken de Türkçe
///   harfler kaybolmaz.
/// - Uzun karar metni sayfalara bölünür (her paragraf ayrı, sayfaya sığmayan paragraf da bölünür).
/// - [isolateDecisionThreshold]'dan çok karar arka plan izolesinde üretilir ([BackgroundWork]).
/// - Dosya adı ASCII'dir (`Karar_Defteri_Gul_Sitesi_2026.pdf`).
class PdfDecisionService {
  PdfDecisionService._();

  /// Bu sayıdan çok karar arka plan izolesinde üretilir (metinler 10.000 karaktere kadar uzun olabilir).
  static const int isolateDecisionThreshold = 20;

  /// Test düzeneği: false iken PDF akışları sıkıştırılmaz (üretilen metin / yazı tipi eşlemesi denetlenebilsin).
  @visibleForTesting
  static bool debugCompress = true;

  /// `Karar_Defteri_<site>_<yıl>.pdf`.
  static String fileName(String siteName, int year) {
    final site = PdfFinanceService.asciiName(siteName);
    return 'Karar_Defteri_${site.isEmpty ? 'Site' : site}_$year.pdf';
  }

  /// [decisions] içinden yalnız [year] yılının KESİN kararlarını numara sırasıyla yazar. [fonts] verilmezse gömülü
  /// Roboto yüklenir.
  static Future<Uint8List> generateYearPdf({
    required String siteName,
    required int year,
    required List<Decision> decisions,
    DateTime? printedAt,
    PdfFontSet? fonts,
  }) async {
    final set = fonts ?? await PdfFontSet.loadBundled();
    final finals = decisions.where((d) => d.isFinal && d.effectiveYear == year).toList()..sort(compareDecisionsByNumber);
    final job = _DecisionJob(
      compress: debugCompress,
      fonts: set,
      siteName: siteName,
      year: year,
      decisions: finals,
      printedAt: printedAt ?? DateTime.now(),
    );
    if (finals.length > isolateDecisionThreshold) {
      return BackgroundWork.run<_DecisionJob, Uint8List>(_buildDecisionBook, job, debugLabel: 'pdf.decisions');
    }
    return _buildDecisionBook(job);
  }
}

class _DecisionJob {
  const _DecisionJob({
    required this.compress,
    required this.fonts,
    required this.siteName,
    required this.year,
    required this.decisions,
    required this.printedAt,
  });

  final bool compress;
  final PdfFontSet fonts;
  final String siteName;
  final int year;
  final List<Decision> decisions;
  final DateTime printedAt;
}

const PdfColor _muted = PdfColor.fromInt(0xFF52606D);
const PdfColor _ink = PdfColor.fromInt(0xFF1F2933);
const PdfColor _line = PdfColor.fromInt(0xFFCBD2D9);
const PdfColor _soft = PdfColor.fromInt(0xFFF1F5F9);

String _day(DateTime? d) => d == null ? '-' : formatDateField(d);

/// Karar metni paragraflara bölünür: her biri sayfa sınırında bölünebilen ayrı bir öğedir (tek dev blok sayfaya
/// sığmazsa PDF üretimi hata verirdi).
List<pw.Widget> _paragraphs(String text, pw.TextStyle style) {
  final out = <pw.Widget>[];
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trim().isEmpty) {
      out.add(pw.SizedBox(height: 6));
    } else {
      out.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 2), child: pw.Text(line, style: style)));
    }
  }
  return out;
}

Future<Uint8List> _buildDecisionBook(_DecisionJob job) async {
  final f = job.fonts.resolve();
  final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, fontFallback: <pw.Font>[f.regular]);
  final site = job.siteName.trim().isEmpty ? 'Site yönetimi' : job.siteName.trim();
  final doc = pw.Document(
    title: 'Karar Defteri ${job.year}',
    author: site,
    creator: 'Karar Defteri',
    compress: job.compress,
  );

  pw.Widget meta(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        children: <pw.InlineSpan>[
          pw.TextSpan(text: '$label: ', style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9.5)),
        ],
      ),
    ),
  );

  final body = <pw.Widget>[];
  if (job.decisions.isEmpty) {
    body.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Text('${job.year} yılında kesinleşmiş karar yok.', style: const pw.TextStyle(fontSize: 11)),
      ),
    );
  }
  for (var i = 0; i < job.decisions.length; i++) {
    final d = job.decisions[i];
    if (i > 0) body.add(pw.Divider(color: _line, height: 22));
    body.add(
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const pw.BoxDecoration(color: _soft),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                'Karar No: ${d.displayNumber}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              '${_day(d.meetingDate)}  •  ${d.meetingType.label}',
              style: const pw.TextStyle(fontSize: 10, color: _ink),
            ),
          ],
        ),
      ),
    );
    body.add(pw.SizedBox(height: 6));
    body.add(pw.Text(d.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)));
    body.add(pw.SizedBox(height: 4));
    body.addAll(_paragraphs(d.body, const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.5)));
    body.add(pw.SizedBox(height: 6));
    final counts = d.voteCountsText;
    body.add(meta('Oylama', counts == null ? d.voteResult.label : '${d.voteResult.label} (${counts.replaceAll(' · ', ', ')})'));
    if (d.attendees != null) body.add(meta('Katılanlar', d.attendees!));
    final supersedes = d.supersedes;
    if (supersedes != null) {
      body.add(meta('Değiştirdiği karar', supersedes.numberLabel ?? 'Önceki karar'));
    }
    final superseded = d.supersededText;
    if (superseded != null) body.add(meta('Durum', superseded));
    final finalizedBy = d.finalizedByName;
    final finalizedAt = d.finalizedAt;
    if (finalizedBy != null || finalizedAt != null) {
      body.add(
        meta(
          'Kesinleştiren',
          <String>[?finalizedBy, if (finalizedAt != null) formatIstanbulDateTime(finalizedAt)].join('  •  '),
        ),
      );
    }
  }

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), theme: theme),
      header: (pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.2))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text('Karar Defteri — ${job.year}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(site, style: const pw.TextStyle(fontSize: 11)),
            pw.Text(
              '${job.year} yılının kesinleşmiş kararları (${job.decisions.length} karar)',
              style: const pw.TextStyle(fontSize: 9.5, color: _muted),
            ),
          ],
        ),
      ),
      footer: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Divider(color: _line),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  '$kDecisionLegalNotice  Basım: ${formatIstanbulDateTime(job.printedAt)}',
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '${context.pageNumber}/${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8.5, color: _muted),
              ),
            ],
          ),
        ],
      ),
      build: (pw.Context context) => body,
    ),
  );
  return doc.save();
}

/// Teslim sonucu (arayüz için).
enum DecisionPdfOutcome {
  /// Dosya kaydedildi / indirildi ya da paylaşım menüsü açıldı.
  delivered,

  /// Kullanıcı kaydetme penceresini kapattı (masaüstü).
  cancelled,
}

/// "PDF olarak indir" için tek geçiş noktası. Web'de dosya tarayıcı indirmesiyle, masaüstünde "Kaydet" penceresiyle
/// verilir (`FilePicker.saveFile`; web'de Blob indirmesine düşer); mobilde paylaşım menüsü açılır (finans PDF'leri
/// gibi `share_plus`, oradan "Dosyalara kaydet"). Widget testleri [debugOverride] ile platform eklentilerine
/// dokunmadan sürer; PDF'in kendisi `pdf_decision_service_test.dart` ile sınanır.
class DecisionPdfActions {
  DecisionPdfActions._();

  /// Test düzeneği: verilirse PDF üretilmez / teslim edilmez; istek bilgisiyle çağrılır.
  static Future<DecisionPdfOutcome> Function(DecisionPdfRequest request)? debugOverride;

  static Future<DecisionPdfOutcome> downloadYear({
    required String siteName,
    required int year,
    required List<Decision> decisions,
  }) async {
    final override = debugOverride;
    if (override != null) {
      return override(DecisionPdfRequest(siteName: siteName, year: year, decisions: decisions));
    }
    final bytes = await PdfDecisionService.generateYearPdf(siteName: siteName, year: year, decisions: decisions);
    return deliver(bytes, fileName: PdfDecisionService.fileName(siteName, year), subject: 'Karar Defteri $year');
  }

  /// Baytları platforma uygun yolla verir (bkz. sınıf açıklaması).
  static Future<DecisionPdfOutcome> deliver(Uint8List bytes, {required String fileName, required String subject}) async {
    if (BulkFileSharer.platformUsesSaveDialog) {
      final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: 'application/pdf');
      // Web'de `saveFile` Blob indirmesi yapar ve HER ZAMAN null döner (kullanıcı vazgeçmiş olamaz).
      if (uri == null && !kIsWeb) return DecisionPdfOutcome.cancelled;
      return DecisionPdfOutcome.delivered;
    }
    await PdfFinanceService.sharePdf(bytes, fileName: fileName, subject: subject);
    return DecisionPdfOutcome.delivered;
  }
}

/// [DecisionPdfActions.debugOverride] çağrısının içeriği.
class DecisionPdfRequest {
  const DecisionPdfRequest({required this.siteName, required this.year, required this.decisions});

  final String siteName;
  final int year;
  final List<Decision> decisions;
}
