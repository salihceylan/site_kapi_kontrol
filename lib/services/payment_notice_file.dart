// Dekont dosyası hazırlığı (Dalga 2 / 2B): tür tanıma (içerik imzasından), 10 MB sınırı, fotoğrafın cihazda küçültülmesi ve üstverisinin (EXIF / GPS) silinmesi.
//
// PDF olduğu gibi gider (sunucu etkin içeriği süzer). Fotoğraf [prepareWorkPhoto] ile yeniden kodlanır (en çok 2560 px, JPEG 85; EXIF yok); hazırlanamazsa üstverisi
// ayıklanmış özgün bayt gider, ayıklanamazsa dosya REDDEDİLİR. Dosya adı ve içerik günlüğe yazılmaz.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:site_kapi_kontrol/services/share_inbox.dart';
import 'package:site_kapi_kontrol/services/work_photo_prepare.dart';

/// Sunucu sınırı (bayt).
const int kNoticeMaxBytes = 10 * 1024 * 1024;

/// Seçiciden okunacak en büyük kaynak (bayt): fotoğraf küçültülebilsin; PDF için 10 MB geçerlidir.
const int kNoticeReadMaxBytes = 50 * 1024 * 1024;

class NoticeFileException implements Exception {
  const NoticeFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// İçerik imzasından tür: `application/pdf` | `image/jpeg` | `image/png`; tanınmazsa null.
String? sniffNoticeMime(Uint8List b) {
  if (b.length >= 5 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46 && b[4] == 0x2d) return 'application/pdf';
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return 'image/jpeg';
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47 && b[4] == 0x0d && b[5] == 0x0a && b[6] == 0x1a && b[7] == 0x0a) {
    return 'image/png';
  }
  return null;
}

String _extFor(String mime) => switch (mime) {
  'application/pdf' => 'pdf',
  'image/png' => 'png',
  _ => 'jpg',
};

String _baseName(String name) {
  var base = name.trim();
  final slash = base.lastIndexOf(RegExp(r'[\\/]'));
  if (slash >= 0) base = base.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  return base.trim().isEmpty ? 'dekont' : base.trim();
}

/// Ham baytları yüklemeye hazırlar. Hata: [NoticeFileException] (Türkçe, kullanıcıya gösterilir).
Future<SharedReceipt> prepareNoticeFile(String name, Uint8List bytes) async {
  if (bytes.isEmpty) throw const NoticeFileException('Dosya boş ya da okunamadı.');
  final mime = sniffNoticeMime(bytes);
  if (mime == null) throw const NoticeFileException('Yalnız PDF, JPEG ve PNG dekont yüklenebilir.');
  if (mime == 'application/pdf') {
    if (bytes.length > kNoticeMaxBytes) throw const NoticeFileException('Dosya en fazla 10 MB olabilir.');
    return SharedReceipt(name: '${_baseName(name)}.pdf', mime: mime, bytes: bytes);
  }
  final prepared = await prepareWorkPhoto(name, bytes);
  if (prepared.error != null) throw NoticeFileException(prepared.error!);
  final out = sniffNoticeMime(prepared.bytes) ?? mime;
  if (out == 'application/pdf') throw const NoticeFileException('Dosya geçersiz.');
  if (prepared.bytes.length > kNoticeMaxBytes) throw const NoticeFileException('Fotoğraf küçültüldükten sonra bile 10 MB\'ı aşıyor. Ekran görüntüsü alıp onu yükleyin.');
  return SharedReceipt(name: '${_baseName(prepared.name)}.${_extFor(out)}', mime: out, bytes: prepared.bytes);
}

/// Dosya seçici ("Dosya seç"). İptalde null; geçersiz dosyada [NoticeFileException].
Future<SharedReceipt?> pickNoticeFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Dekont seçin', type: FileType.custom, allowedExtensions: const <String>['pdf', 'jpg', 'jpeg', 'png']);
  if (files.isEmpty) return null;
  final file = files.first;
  final size = file.lengthSync() ?? await file.length() ?? 0;
  if (size > kNoticeReadMaxBytes) throw const NoticeFileException('Dosya çok büyük (en fazla 10 MB).');
  return prepareNoticeFile(file.name, await file.readAsBytes());
}
