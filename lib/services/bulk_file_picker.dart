// Dosya seçici soyutlaması (Platform Faz 2b). `file_picker` 13.x: `pickFile` + `PlatformFile.readAsBytes()`.
//
// Ekranlar [BulkFilePicker] alır; testlerde sahte seçici verilir (gerçek işletim sistemi iletişim kutusu açılmaz).
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Seçilen dosya: ad, (biliniyorsa) boyut ve baytları tembel okuyan işlev.
class PickedBulkFile {
  const PickedBulkFile({required this.name, required this.readBytes, this.size});

  final String name;

  /// Bilinmiyorsa null (okunduktan sonra bayt uzunluğu denetlenir).
  final int? size;
  final Future<Uint8List> Function() readBytes;
}

/// Kullanıcı vazgeçerse null.
typedef BulkFilePicker = Future<PickedBulkFile?> Function();

/// Varsayılan seçici: yalnız `.xlsx` ve `.csv`.
Future<PickedBulkFile?> pickBulkFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Yüklenecek dosyayı seçin',
    type: FileType.custom,
    allowedExtensions: const <String>['xlsx', 'csv'],
  );
  if (file == null) return null;
  return pickedFileOf(file);
}

/// Eklenti dosyasını sarar. Windows / Linux seçicileri boyutu bildirmez (`lengthSync` null): `length()` dosyaya
/// bakar, böylece 10 MB üstü dosya baytları okunmadan reddedilir. Boyut yine de bilinemezse null kalır.
Future<PickedBulkFile> pickedFileOf(PlatformFile file) async {
  int? size = file.lengthSync();
  if (size == null) {
    try {
      size = await file.length();
    } catch (_) {
      size = null;
    }
  }
  return PickedBulkFile(name: file.name, size: size, readBytes: file.readAsBytes);
}
