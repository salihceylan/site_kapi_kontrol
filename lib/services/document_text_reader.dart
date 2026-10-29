// Belge görselinden metin okuma (P2-13, karar K15): YALNIZ cihaz içi (ML Kit; Android/iOS). Görüntü ve çıkan metin ASLA ağa gönderilmez, dış yapay zekâ yoktur.
//
// İnce sarmalayıcı: ML Kit dosya yolu ister; baytlar geçici bir klasöre yazılır, okunur ve HER DURUMDA silinir. Web ve masaüstünde [supported] false'tur
// (arayüz düğmeyi göstermez, akış eski haliyle çalışır). Ayrıştırma saf Dart'ta ayrıdır: `document_text_parser.dart`.
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:site_kapi_kontrol/services/meter_ocr.dart' show MeterOcr, MlKitMeterOcr;

/// Görsel baytlarından ham metin okuyucu (testlerde sahte).
abstract class DocumentTextReader {
  /// Bu platformda okuma var mı (false ise düğme gösterilmez).
  bool get supported;

  /// Ham metin; desteklenmiyorsa, okunamadıysa ya da görselde metin yoksa null. Hata fırlatmaz.
  Future<String?> read(Uint8List imageBytes);
}

/// ML Kit (Latin) ile; [MlKitMeterOcr] sarmalayıcısını yeniden kullanır.
class MlKitDocumentTextReader implements DocumentTextReader {
  MlKitDocumentTextReader({MeterOcr? ocr, bool? supported}) : _ocr = ocr, _supported = supported;

  final MeterOcr? _ocr;
  final bool? _supported;

  @override
  bool get supported => _supported ?? MlKitMeterOcr.supported;

  @override
  Future<String?> read(Uint8List imageBytes) async {
    if (!supported || imageBytes.isEmpty) return null;
    final ocr = _ocr ?? MlKitMeterOcr();
    Directory? dir;
    try {
      dir = await Directory.systemTemp.createTemp('belge_oku_');
      final isPng = imageBytes.length > 3 && imageBytes[0] == 0x89 && imageBytes[1] == 0x50;
      final file = File('${dir.path}${Platform.pathSeparator}belge.${isPng ? 'png' : 'jpg'}');
      await file.writeAsBytes(imageBytes, flush: true);
      return await ocr.recognize(file.path);
    } on Object {
      return null;
    } finally {
      try {
        await ocr.close();
      } on Object {
        // kapatma hatası okuma sonucunu etkilemez
      }
      try {
        await dir?.delete(recursive: true);
      } on Object {
        // geçici klasör silinemezse sistem önbellek temizliğine kalır
      }
    }
  }
}

/// Platformun varsayılan okuyucusu.
DocumentTextReader platformDocumentTextReader() => MlKitDocumentTextReader();
