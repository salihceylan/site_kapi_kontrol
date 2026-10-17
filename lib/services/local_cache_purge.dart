// Eklentilerin (file_picker, share_plus) uygulama önbelleğine bıraktığı KİŞİSEL VERİ kopyalarını siler.
//
// Neden: bizim kendi geçici klasörlerimizi (`toplu_dosya_*`, `kisisel_veri_*`, `kisisel_veri_belge_*`) paylaşım
// sonrası siliyoruz, ama eklentiler ikinci bir kopya tutar:
// - share_plus (Android): dosya yolu paylaşımını her zaman `<önbellek>/share_plus/<ad>` altına KOPYALAR ve bu klasörü
//   yalnız bir sonraki paylaşımın başında temizler. Dışa aktarılan kişi listesi ya da indirilen belge (sözleşme, TC /
//   IBAN içerebilir) başka bir paylaşım yapılana dek orada kalır.
// - file_picker (Android): seçilen dosya `<önbellek>/file_picker/<zaman>/<ad>` altına kopyalanır; yüklenen sakin
//   listesi / belge kopyası kalıcı kalır. `FilePicker.clearTemporaryFiles()` bunu siler.
//
// Her adım bağımsızdır ve hata FIRLATMAZ (en iyi çaba; yol / ayrıntı günlüğe yazılmaz). Web'de iş yoktur.
import 'dart:io' show Directory, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// share_plus'ın Android önbellek alt klasörü (`Directory.systemTemp` = uygulama önbelleği).
const String kSharePlusCacheDirName = 'share_plus';

/// [pickerCache]: file_picker geçici kopyaları; [shareCache]: share_plus önbelleği. [tempRoot] / [clearPicker] testler
/// içindir (verilmezse sistem geçici dizini ve gerçek eklenti).
///
/// Dikkat: [shareCache] o an bir alıcı uygulamayla süren paylaşımın kopyasını da siler; bu yüzden paylaşımın hemen
/// ardından DEĞİL, gecikmeli silme süresi dolunca (ya da hesap silme / çıkışta) çağrılır.
Future<void> purgeLocalSharedCaches({
  bool pickerCache = true,
  bool shareCache = true,
  Directory? tempRoot,
  Future<void> Function()? clearPicker,
}) async {
  if (kIsWeb) return;
  if (pickerCache) {
    try {
      await (clearPicker ?? FilePicker.clearTemporaryFiles)();
    } catch (_) {
      // Eklenti yok / platform desteklemiyor (masaüstü): sorun değil.
    }
  }
  if (shareCache) {
    try {
      final root = tempRoot ?? Directory.systemTemp;
      final dir = Directory('${root.path}${Platform.pathSeparator}$kSharePlusCacheDirName');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Dosya kilitli olabilir: en iyi çaba.
    }
  }
}
