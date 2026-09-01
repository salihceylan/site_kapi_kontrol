import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';

class PdfDeviceFirmwareService {
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  /// Cihaz firmware ve güncelleme durum raporunu PDF olarak derler ve yazdırma/indirme önizlemesini açar.
  static Future<void> printOrShareFirmwareReportPdf({
    required List<DeviceRecord> devices,
    String? userEmail,
    String? latestTargetVersion,
  }) async {
    final pdfBytes = await generateFirmwareReportPdf(
      devices: devices,
      userEmail: userEmail,
      latestTargetVersion: latestTargetVersion,
    );

    final title = 'Cihaz_Firmware_Guncelleme_Raporu_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: title,
    );
  }

  /// PDF dökümanını Uint8List bayt dizisi olarak oluşturur.
  static Future<Uint8List> generateFirmwareReportPdf({
    required List<DeviceRecord> devices,
    String? userEmail,
    String? latestTargetVersion,
  }) async {
    final doc = pw.Document();

    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    final primaryColor = PdfColor.fromHex('#1A237E'); // Deep Indigo
    final secondaryBg = PdfColor.fromHex('#F5F7FA');
    final borderGray = PdfColor.fromHex('#E0E0E0');
    final textDark = PdfColor.fromHex('#212121');
    final textMuted = PdfColor.fromHex('#616161');

    final totalDevices = devices.length;
    final onlineDevices = devices.where((d) => d.mqttConnected == true).length;

    // Hedef sürüm belirlenmemişse listedeki en yüksek/yaygın sürümü tespit et
    final targetVer = latestTargetVersion ?? '2.0.0';
    final upToDateCount = devices.where((d) => d.firmwareVersion == targetVer).length;
    final outdatedCount = totalDevices - upToDateCount;

    // Sürüm gruplaması
    final Map<String, int> versionCounts = {};
    for (final dev in devices) {
      final ver = (dev.firmwareVersion ?? 'Bilinmiyor').trim();
      versionCounts[ver] = (versionCounts[ver] ?? 0) + 1;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _buildHeader(
          fontBold: fontBold,
          fontRegular: fontRegular,
          primaryColor: primaryColor,
          textMuted: textMuted,
          userEmail: userEmail,
        ),
        footer: (context) => _buildFooter(
          context: context,
          fontRegular: fontRegular,
          borderGray: borderGray,
          textMuted: textMuted,
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          // 1. KPI İstatistik Kartları
          _buildKpiSummary(
            fontBold: fontBold,
            fontMedium: fontMedium,
            fontRegular: fontRegular,
            totalDevices: totalDevices,
            onlineDevices: onlineDevices,
            upToDateCount: upToDateCount,
            outdatedCount: outdatedCount,
            targetVersion: targetVer,
            primaryColor: primaryColor,
            secondaryBg: secondaryBg,
            borderGray: borderGray,
            textDark: textDark,
            textMuted: textMuted,
          ),
          pw.SizedBox(height: 16),

          // 2. Sürüm Dağılımı Özeti Tablosu
          _buildVersionDistributionTable(
            versionCounts: versionCounts,
            totalDevices: totalDevices,
            targetVersion: targetVer,
            fontBold: fontBold,
            fontRegular: fontRegular,
            primaryColor: primaryColor,
            secondaryBg: secondaryBg,
            borderGray: borderGray,
            textDark: textDark,
          ),
          pw.SizedBox(height: 20),

          // 3. Başlık
          pw.Text(
            'Tüm Cihazların Detaylı Firmware ve OTA Durum Listesi',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 13,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 8),

          // 4. Detaylı Cihaz Tablosu
          _buildDeviceTable(
            devices: devices,
            targetVersion: targetVer,
            fontBold: fontBold,
            fontMedium: fontMedium,
            fontRegular: fontRegular,
            primaryColor: primaryColor,
            secondaryBg: secondaryBg,
            borderGray: borderGray,
            textDark: textDark,
            textMuted: textMuted,
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader({
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required PdfColor primaryColor,
    required PdfColor textMuted,
    String? userEmail,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'AHBU AKILLI KAPI KONTROL SİSTEMİ',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 14,
                  color: primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Cihaz Filosu & Firmware Güncelleme Durum Raporu',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 11,
                  color: PdfColors.grey800,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Rapor Tarihi: ${_dateFormat.format(DateTime.now())}',
                style: pw.TextStyle(font: fontRegular, fontSize: 9, color: textMuted),
              ),
              if (userEmail != null && userEmail.isNotEmpty)
                pw.Text(
                  'Yetkili: $userEmail',
                  style: pw.TextStyle(font: fontRegular, fontSize: 9, color: textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiSummary({
    required pw.Font fontBold,
    required pw.Font fontMedium,
    required pw.Font fontRegular,
    required int totalDevices,
    required int onlineDevices,
    required int upToDateCount,
    required int outdatedCount,
    required String targetVersion,
    required PdfColor primaryColor,
    required PdfColor secondaryBg,
    required PdfColor borderGray,
    required PdfColor textDark,
    required PdfColor textMuted,
  }) {
    final onlinePercent = totalDevices > 0 ? ((onlineDevices / totalDevices) * 100).toStringAsFixed(1) : '0';
    final upToDatePercent = totalDevices > 0 ? ((upToDateCount / totalDevices) * 100).toStringAsFixed(1) : '0';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: secondaryBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: borderGray),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildKpiItem(
            title: 'Toplam Cihaz',
            value: '$totalDevices Adet',
            sub: 'Sistemde Kayıtlı',
            fontBold: fontBold,
            fontRegular: fontRegular,
            color: primaryColor,
          ),
          _buildKpiItem(
            title: 'Çevrimiçi (Online)',
            value: '$onlineDevices ($onlinePercent%)',
            sub: 'MQTT Bağlı',
            fontBold: fontBold,
            fontRegular: fontRegular,
            color: PdfColor.fromHex('#2E7D32'),
          ),
          _buildKpiItem(
            title: 'Güncel Cihazlar',
            value: '$upToDateCount ($upToDatePercent%)',
            sub: 'v$targetVersion Sürümünde',
            fontBold: fontBold,
            fontRegular: fontRegular,
            color: PdfColor.fromHex('#1565C0'),
          ),
          _buildKpiItem(
            title: 'Güncelleme Bekleyen',
            value: '$outdatedCount Adet',
            sub: 'Eski Sürüm / Beklemede',
            fontBold: fontBold,
            fontRegular: fontRegular,
            color: outdatedCount > 0 ? PdfColor.fromHex('#C62828') : PdfColor.fromHex('#2E7D32'),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiItem({
    required String title,
    required String value,
    required String sub,
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required PdfColor color,
  }) {
    return pw.Column(
      children: [
        pw.Text(title, style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 3),
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 13, color: color)),
        pw.SizedBox(height: 2),
        pw.Text(sub, style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.grey600)),
      ],
    );
  }

  static pw.Widget _buildVersionDistributionTable({
    required Map<String, int> versionCounts,
    required int totalDevices,
    required String targetVersion,
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required PdfColor primaryColor,
    required PdfColor secondaryBg,
    required PdfColor borderGray,
    required PdfColor textDark,
  }) {
    final sortedVersions = versionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderGray),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Table(
        border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(2),
          3: pw.FlexColumnWidth(3),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: primaryColor),
            children: [
              _buildTh('Firmware Sürümü', fontBold, PdfColors.white),
              _buildTh('Cihaz Sayısı', fontBold, PdfColors.white),
              _buildTh('Oran (%)', fontBold, PdfColors.white),
              _buildTh('Durum', fontBold, PdfColors.white),
            ],
          ),
          ...sortedVersions.map((entry) {
            final isTarget = entry.key == targetVersion || entry.key == 'v$targetVersion';
            final percent = totalDevices > 0 ? ((entry.value / totalDevices) * 100).toStringAsFixed(1) : '0';

            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: isTarget ? PdfColor.fromHex('#E8F5E9') : secondaryBg,
              ),
              children: [
                _buildTd(entry.key, fontBold, textDark),
                _buildTd('${entry.value} Cihaz', fontRegular, textDark),
                _buildTd('%$percent', fontRegular, textDark),
                _buildTd(
                  isTarget ? 'EN GÜNCEL SÜRÜM' : 'GÜNCELLEME GEREKLİ',
                  fontBold,
                  isTarget ? PdfColor.fromHex('#2E7D32') : PdfColor.fromHex('#C62828'),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _buildDeviceTable({
    required List<DeviceRecord> devices,
    required String targetVersion,
    required pw.Font fontBold,
    required pw.Font fontMedium,
    required pw.Font fontRegular,
    required PdfColor primaryColor,
    required PdfColor secondaryBg,
    required PdfColor borderGray,
    required PdfColor textDark,
    required PdfColor textMuted,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: borderGray, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(22),  // #
        1: pw.FlexColumnWidth(2.2), // UID
        2: pw.FlexColumnWidth(3.0), // Site & Kapı
        3: pw.FlexColumnWidth(1.6), // Sürüm
        4: pw.FlexColumnWidth(2.2), // OTA Durumu
        5: pw.FlexColumnWidth(1.6), // Wi-Fi
        6: pw.FlexColumnWidth(1.5), // Bağlantı
        7: pw.FlexColumnWidth(2.5), // Son Görülme
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: primaryColor),
          children: [
            _buildTh('#', fontBold, PdfColors.white),
            _buildTh('Cihaz UID', fontBold, PdfColors.white),
            _buildTh('Site / Kapı', fontBold, PdfColors.white),
            _buildTh('Sürüm', fontBold, PdfColors.white),
            _buildTh('OTA Durumu', fontBold, PdfColors.white),
            _buildTh('Wi-Fi', fontBold, PdfColors.white),
            _buildTh('Bağlantı', fontBold, PdfColors.white),
            _buildTh('Son Görülme', fontBold, PdfColors.white),
          ],
        ),
        ...devices.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final dev = entry.value;
          final isEven = index % 2 == 0;
          final isUpToDate = dev.firmwareVersion == targetVersion || dev.firmwareVersion == 'v$targetVersion';
          final isOnline = dev.mqttConnected == true;

          final siteText = [
            if (dev.siteName != null && dev.siteName!.isNotEmpty) dev.siteName!,
            if (dev.assignedDoorName != null && dev.assignedDoorName!.isNotEmpty) dev.assignedDoorName!
            else if (dev.gateName != null && dev.gateName!.isNotEmpty) dev.gateName!,
          ].join(' / ');

          final lastSeenFormatted = dev.lastSeenAt != null
              ? _dateFormat.format(dev.lastSeenAt!)
              : '-';

          final wifiText = dev.wifiSignalPercent != null
              ? '%${dev.wifiSignalPercent}'
              : (dev.wifiRssi != null ? '${dev.wifiRssi} dBm' : '-');

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? secondaryBg : PdfColors.white,
            ),
            children: [
              _buildTd('$index', fontRegular, textMuted, align: pw.TextAlign.center),
              _buildTd(dev.deviceUid, fontBold, textDark),
              _buildTd(siteText.isEmpty ? '(Atanmamış)' : siteText, fontRegular, textDark),
              _buildTd(
                dev.firmwareVersion ?? '-',
                fontBold,
                isUpToDate ? PdfColor.fromHex('#2E7D32') : PdfColor.fromHex('#C62828'),
              ),
              _buildTd(
                dev.otaStatus ?? 'beklemede',
                fontRegular,
                dev.otaStatus == 'guncel' || dev.otaStatus == 'guncelleme tamam'
                    ? PdfColor.fromHex('#2E7D32')
                    : (dev.otaStatus?.contains('hata') == true || dev.otaStatus?.contains('basarisiz') == true
                        ? PdfColor.fromHex('#C62828')
                        : textDark),
              ),
              _buildTd(wifiText, fontRegular, textDark, align: pw.TextAlign.center),
              _buildTd(
                isOnline ? 'ONLINE' : 'OFFLINE',
                fontBold,
                isOnline ? PdfColor.fromHex('#2E7D32') : PdfColors.grey600,
                align: pw.TextAlign.center,
              ),
              _buildTd(lastSeenFormatted, fontRegular, textDark),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTh(String text, pw.Font font, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8.5, color: color),
        textAlign: pw.TextAlign.left,
      ),
    );
  }

  static pw.Widget _buildTd(
    String text,
    pw.Font font,
    PdfColor color, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8, color: color),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _buildFooter({
    required pw.Context context,
    required pw.Font fontRegular,
    required PdfColor borderGray,
    required PdfColor textMuted,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: borderGray, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'AHBU IoT Akıllı Kapı Sistemleri - Gizli & Kurumsal Yönetici Raporudur',
            style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textMuted),
          ),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textMuted),
          ),
        ],
      ),
    );
  }
}
