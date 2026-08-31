import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';

class PdfCredentialsService {
  static const PdfColor _primaryColor = PdfColor.fromInt(0xFF1E3A8A); // Deep Blue
  static const PdfColor _accentColor = PdfColor.fromInt(0xFF2563EB); // Royal Blue
  static const PdfColor _darkText = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor _mutedText = PdfColor.fromInt(0xFF64748B);
  static const PdfColor _lightBg = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _rowAltBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor _border = PdfColor.fromInt(0xFFCBD5E1);

  /// Tek bir sitenin tüm kullanıcı ve daire giriş bilgilerini içeren PDF üretir
  static Future<Uint8List> generateSiteCredentialsPdf({
    required SiteStructureRecord structure,
    String? companyName,
  }) async {
    final pdf = pw.Document(
      title: '${structure.site.name} - Kullanıcı Giriş Bilgileri',
      author: companyName ?? 'AHBU Akıllı Kapı Sistemleri',
    );

    final site = structure.site;
    final apartments = structure.apartments;
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
          fontFallback: [font, fontMedium],
        ),
        header: (context) => _buildHeader(
          site: site,
          companyName: companyName,
          context: context,
          fontBold: fontBold,
          fontRegular: font,
        ),
        footer: (context) => _buildFooter(context: context, fontRegular: font),
        build: (context) => [
          _buildSiteSummaryCard(site: site, structure: structure, fontBold: fontBold, fontRegular: font),
          pw.SizedBox(height: 16),
          _buildApartmentsTable(apartments: apartments, fontBold: fontBold, fontRegular: font),
        ],
      ),
    );

    return pdf.save();
  }

  /// Birden fazla sitenin giriş bilgilerini içeren toplu PDF üretir
  static Future<Uint8List> generateMultiSiteCredentialsPdf({
    required List<SiteStructureRecord> structures,
    String? companyName,
  }) async {
    final pdf = pw.Document(
      title: 'Toplu Site Kullanıcı Giriş Bilgileri Raporu',
      author: companyName ?? 'AHBU Akıllı Kapı Sistemleri',
    );

    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    for (final structure in structures) {
      final site = structure.site;
      final apartments = structure.apartments;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
            fontFallback: [font, fontMedium],
          ),
          header: (context) => _buildHeader(
            site: site,
            companyName: companyName,
            context: context,
            fontBold: fontBold,
            fontRegular: font,
          ),
          footer: (context) => _buildFooter(context: context, fontRegular: font),
          build: (context) => [
            _buildSiteSummaryCard(site: site, structure: structure, fontBold: fontBold, fontRegular: font),
            pw.SizedBox(height: 16),
            _buildApartmentsTable(apartments: apartments, fontBold: fontBold, fontRegular: font),
          ],
        ),
      );
    }

    return pdf.save();
  }

  /// PDF'i doğrudan yazdır veya kaydet / paylaş diyalogunu açar
  static Future<void> printOrShareSitePdf({
    required SiteStructureRecord structure,
    String? companyName,
  }) async {
    final bytes = await generateSiteCredentialsPdf(
      structure: structure,
      companyName: companyName,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: '${structure.site.name}_Giris_Bilgileri.pdf',
    );
  }

  /// PDF'i doğrudan paylaşır (WhatsApp, E-posta, Dosya vb.)
  static Future<void> shareSitePdf({
    required SiteStructureRecord structure,
    String? companyName,
  }) async {
    final bytes = await generateSiteCredentialsPdf(
      structure: structure,
      companyName: companyName,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${structure.site.name}_Giris_Bilgileri.pdf',
    );
  }

  // --- Yardımcı PDF Bileşenleri ---

  static pw.Widget _buildHeader({
    required SiteRecord site,
    String? companyName,
    required pw.Context context,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _primaryColor, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'AHBU AKILLI KAPI SİSTEMİ',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 16,
                  color: _primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Kullanıcı & Daire Giriş Bilgileri Raporu',
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 12,
                  color: _mutedText,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                companyName ?? 'GÜDE TEKNOLOJİ',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 11,
                  color: _darkText,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Tarih: $dateStr',
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 9.5,
                  color: _mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSiteSummaryCard({
    required SiteRecord site,
    required SiteStructureRecord structure,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  site.name,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 15,
                    color: _primaryColor,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _accentColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'Site Kodu: ${site.id}',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 10,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: _border, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoItem(
                  label: 'Site Yöneticisi',
                  value: site.managerName ?? 'Atanmamış',
                  subValue: site.managerUserCode != null
                      ? 'Kullanıcı Kodu: ${site.managerUserCode}'
                      : null,
                  fontBold: fontBold,
                  fontRegular: fontRegular,
                ),
              ),
              pw.Expanded(
                child: _buildInfoItem(
                  label: 'Konum / Adres',
                  value: '${site.city ?? '-'} / ${site.district ?? '-'}',
                  subValue: site.address,
                  fontBold: fontBold,
                  fontRegular: fontRegular,
                ),
              ),
              pw.Expanded(
                child: _buildInfoItem(
                  label: 'Kapasite',
                  value: '${structure.blocks.length} Blok / ${structure.apartments.length} Daire',
                  subValue: '${structure.doors.length} Tanımlı Kapı',
                  fontBold: fontBold,
                  fontRegular: fontRegular,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoItem({
    required String label,
    required String value,
    String? subValue,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: fontRegular, fontSize: 9, color: _mutedText),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(font: fontBold, fontSize: 11, color: _darkText),
        ),
        if (subValue != null && subValue.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(
            subValue,
            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _mutedText),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildApartmentsTable({
    required List<ApartmentRecord> apartments,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    if (apartments.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        alignment: pw.Alignment.center,
        child: pw.Text(
          'Bu siteye ait tanımlı daire kaydı bulunamadı.',
          style: pw.TextStyle(font: fontRegular, fontSize: 11, color: _mutedText),
        ),
      );
    }

    final headers = [
      '#',
      'Blok',
      'Daire No',
      'Kullanıcı Adı (Giriş)',
      'Şifre / PIN',
      'Sakin Adı',
      'Durum',
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      headerStyle: pw.TextStyle(
        font: fontBold,
        fontSize: 10,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: _primaryColor,
      ),
      headerHeight: 24,
      cellHeight: 22,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.centerLeft,
        6: pw.Alignment.center,
      },
      cellStyle: pw.TextStyle(
        font: fontRegular,
        fontSize: 9.5,
        color: _darkText,
      ),
      oddRowDecoration: const pw.BoxDecoration(
        color: _rowAltBg,
      ),
      border: pw.TableBorder.all(
        color: _border,
        width: 0.5,
      ),
      data: List<List<String>>.generate(apartments.length, (index) {
        final apt = apartments[index];
        final isRowActive = apt.isActive && (apt.residentIsActive ?? true);
        return [
          '${index + 1}',
          apt.blockName,
          apt.unitLabel,
          apt.residentLoginName ?? (apt.residentEmail ?? '-'),
          apt.residentPinCode ?? '-',
          apt.residentFullName ?? '-',
          isRowActive ? 'Aktif' : 'Pasif',
        ];
      }),
    );
  }

  static pw.Widget _buildFooter({
    required pw.Context context,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _border, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '⚠️ Gizlilik Bildirimi: Bu belge site sakinlerinin özel giriş şifrelerini içerir. Yalnızca yetkili kişilerce saklanmalıdır.',
            style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _mutedText),
          ),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _darkText),
          ),
        ],
      ),
    );
  }
}

