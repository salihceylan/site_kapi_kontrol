import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/door_access_log_record.dart';

class PdfLogsService {
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm:ss');
  static final DateFormat _reportDateFormat = DateFormat('dd.MM.yyyy HH:mm');

  /// Kapı geçiş loglarını A4 PDF olarak derler ve yazdırma/paylaşma/indirme önizlemesini açar.
  static Future<void> printOrShareLogsPdf({
    required List<DoorAccessLogRecord> logs,
    String? siteName,
    String? doorNameFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdfBytes = await generateLogsPdf(
      logs: logs,
      siteName: siteName,
      doorNameFilter: doorNameFilter,
      startDate: startDate,
      endDate: endDate,
    );

    final title = 'Kapi_Gecis_Log_Raporu_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: title,
    );
  }

  /// PDF dökümanını Uint8List bayt dizisi olarak oluşturur.
  static Future<Uint8List> generateLogsPdf({
    required List<DoorAccessLogRecord> logs,
    String? siteName,
    String? doorNameFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final doc = pw.Document();

    // Türkçe karakterleri destekleyen fontları yükle
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    // İstatistikler
    final totalCount = logs.length;
    final cloudCount = logs.where((l) => l.triggerType == 'cloud_app').length;
    final localCount = logs.where((l) => l.triggerType == 'local_wifi').length;
    final guestCount = logs.where((l) => l.triggerType == 'guest_pass').length;
    final voiceCount = logs.where((l) => l.triggerType == 'voice').length;
    final offlineCount = logs.where((l) => l.triggerType == 'offline_sync').length;

    final primaryColor = PdfColor.fromHex('#1A237E'); // Deep Indigo
    final accentColor = PdfColor.fromHex('#0D47A1');
    final secondaryBg = PdfColor.fromHex('#F5F7FA');
    final borderGray = PdfColor.fromHex('#E0E0E0');
    final textDark = PdfColor.fromHex('#212121');
    final textMuted = PdfColor.fromHex('#616161');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
          fontFallback: [fontMedium, fontRegular],
        ),
        header: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColor.fromHex('#3F51B5'), width: 1.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 24,
                      height: 24,
                      decoration: pw.BoxDecoration(
                        color: primaryColor,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        'A',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      'AHBU AKILLI KAPI & GEÇİŞ SİSTEMİ',
                      style: pw.TextStyle(
                        color: primaryColor,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'KAPI GEÇİŞ & ERİŞİM LOG RAPORU',
                  style: pw.TextStyle(
                    color: textMuted,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: borderGray, width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Rapor Oluşturma: ${_reportDateFormat.format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 8, color: textMuted),
                ),
                pw.Text(
                  'Sayfa ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: textDark,
                  ),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // BAŞLIK VE FİLTRE BİLGİ KARTI
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              margin: const pw.EdgeInsets.only(bottom: 12),
              decoration: pw.BoxDecoration(
                color: secondaryBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: borderGray),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        siteName != null && siteName.isNotEmpty
                            ? siteName.toUpperCase()
                            : 'TÜM SİTELER / KAPI GEÇİŞ RAPORU',
                        style: pw.TextStyle(
                          color: primaryColor,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: accentColor,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                        ),
                        child: pw.Text(
                          'Toplam $totalCount Geçiş',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      if (doorNameFilter != null && doorNameFilter.isNotEmpty) ...[
                        pw.Text(
                          'Kapı: ',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textDark),
                        ),
                        pw.Text(
                          '$doorNameFilter  |  ',
                          style: pw.TextStyle(fontSize: 9, color: textMuted),
                        ),
                      ],
                      pw.Text(
                        'Tarih Aralığı: ',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textDark),
                      ),
                      pw.Text(
                        startDate != null && endDate != null
                            ? '${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}'
                            : 'Tüm Zamanlar',
                        style: pw.TextStyle(fontSize: 9, color: textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ÖZET İSTATİSTİK KARTLARI
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Row(
                children: [
                  _buildStatBox('Mobil Bulut', cloudCount.toString(), PdfColor.fromHex('#1E88E5'), fontBold),
                  pw.SizedBox(width: 6),
                  _buildStatBox('Yerel Wi-Fi', localCount.toString(), PdfColor.fromHex('#43A047'), fontBold),
                  pw.SizedBox(width: 6),
                  _buildStatBox('Misafir Linki', guestCount.toString(), PdfColor.fromHex('#FB8C00'), fontBold),
                  pw.SizedBox(width: 6),
                  _buildStatBox('Sesli Komut', voiceCount.toString(), PdfColor.fromHex('#8E24AA'), fontBold),
                  if (offlineCount > 0) ...[
                    pw.SizedBox(width: 6),
                    _buildStatBox('Çevrimdışı', offlineCount.toString(), PdfColor.fromHex('#6D4C41'), fontBold),
                  ],
                ],
              ),
            ),

            // LOG TABLOSU
            if (logs.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Seçilen filtrelere uygun kapı geçiş kaydı bulunamadı.',
                  style: pw.TextStyle(fontSize: 10, color: textMuted),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: borderGray, width: 0.5),
                headerDecoration: pw.BoxDecoration(
                  color: primaryColor,
                ),
                headerHeight: 22,
                cellHeight: 18,
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 7.5,
                ),
                cellStyle: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.black,
                ),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: const {
                  0: pw.FixedColumnWidth(20),  // #
                  1: pw.FixedColumnWidth(70),  // Tarih Saat
                  2: pw.FixedColumnWidth(65),  // Kapı
                  3: pw.FlexColumnWidth(2.2),  // Açan Kişi
                  4: pw.FlexColumnWidth(1.8),  // Daire / Blok
                  5: pw.FixedColumnWidth(55),  // Rol
                  6: pw.FixedColumnWidth(65),  // Yöntem
                },
                headers: [
                  '#',
                  'Tarih & Saat',
                  'Kapı',
                  'Açan Kişi',
                  'Daire / Blok',
                  'Rol',
                  'Açma Yöntemi',
                ],
                data: List<List<String>>.generate(
                  logs.length,
                  (index) {
                    final log = logs[index];
                    return [
                      (index + 1).toString(),
                      _dateFormat.format(log.openedAt),
                      log.doorName,
                      log.userName,
                      log.apartmentLabel ?? '-',
                      log.userRoleDisplay,
                      log.triggerTypeDisplay,
                    ];
                  },
                ),
              ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildStatBox(
    String label,
    String value,
    PdfColor color,
    pw.Font fontBold,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#FAFAFA'),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
