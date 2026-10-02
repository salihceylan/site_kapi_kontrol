import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// PDF raporlarında kullanılan Roboto yazı tiplerinin ham baytları.
///
/// PDF sayfa dizgisi ve kodlaması binlerce satırda UI iş parçacığını saniyelerce bloklayabildiğinden
/// rapor arka plan izolesinde üretilir (bkz. `BackgroundWork`). [pw.Font] nesneleri izolelere
/// gönderilemez; bu yüzden yazı tipleri UI izolesinde (ağ + bellek önbelleği) yüklenip bayt olarak
/// iletilir ve arka planda [pw.Font] olarak yeniden kurulur.
///
/// Bayt `null` ise (indirme başarısız olunca `printing` Helvetica'ya düşer) aynı yedek burada da
/// kullanılır: çıktı eski davranışla aynıdır.
class PdfFontSet {
  const PdfFontSet({this.regular, this.bold, this.medium});

  /// Hepsi Helvetica (çevrimdışı yedek; testler ağsız çalışsın diye de kullanılır).
  static const PdfFontSet helvetica = PdfFontSet();

  final Uint8List? regular;
  final Uint8List? bold;
  final Uint8List? medium;

  /// Üç Roboto yazı tipini eşzamanlı yükler (eskiden ardışık üç ağ beklemesiydi).
  static Future<PdfFontSet> loadRoboto() async {
    final fonts = await Future.wait<pw.Font>(<Future<pw.Font>>[
      PdfGoogleFonts.robotoRegular(),
      PdfGoogleFonts.robotoBold(),
      PdfGoogleFonts.robotoMedium(),
    ]);
    return PdfFontSet(
      regular: _bytesOf(fonts[0]),
      bold: _bytesOf(fonts[1]),
      medium: _bytesOf(fonts[2]),
    );
  }

  /// Yazı tipi TTF ise sıkıştırılmış (ofset 0) bir bayt kopyası; Helvetica yedeğinde null.
  static Uint8List? _bytesOf(pw.Font font) {
    if (font is! pw.TtfFont) return null;
    final data = font.data;
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  /// [pw.Font] nesnelerini kurar. Her çağrı yeni nesneler üretir: belge başına BİR kez çağırın
  /// (aynı belgede aynı yazı tipinin iki nesnesi PDF'e iki kez gömülür).
  ({pw.Font regular, pw.Font bold, pw.Font medium}) resolve() => (
        regular: _fontOf(regular),
        bold: _fontOf(bold),
        medium: _fontOf(medium),
      );

  static pw.Font _fontOf(Uint8List? bytes) {
    if (bytes == null) return pw.Font.helvetica();
    // Ofset 0'lı taze bir tampon: pdf'in TTF ayrıştırıcısı ByteData ofsetini yok sayar.
    final copy = Uint8List.fromList(bytes);
    return pw.Font.ttf(copy.buffer.asByteData());
  }
}
