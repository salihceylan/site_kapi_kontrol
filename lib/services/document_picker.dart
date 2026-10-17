// Yüklenecek dosyanın kaynağı ve dosya seçici sarmalayıcısı (docs/PLATFORM_BELGELER.md A13).
//
// Dosya BELLEĞE okunmaz: [DocumentUploadSource.open] diskten akış verir (en çok birkaç yüz KB bellekte), HTTP
// katmanı bu akışı soket hızında çeker. Testlerde [MemoryDocumentSource] ve sahte [DocumentPicker] kullanılır.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';

/// Yüklenecek dosya: ad, boyut ve (tekrar açılabilir) bayt akışı.
abstract class DocumentUploadSource {
  String get name;

  /// Bayt cinsinden boyut. Okunamıyorsa 0 ya da negatif (ön doğrulama "boş / okunamadı" der).
  int get size;

  /// Her çağrıda baştan okur (yeniden deneme için).
  Stream<List<int>> open();
}

/// Bellekteki baytlar (web yedeği ve testler).
@immutable
class MemoryDocumentSource implements DocumentUploadSource {
  const MemoryDocumentSource(
    this.name,
    this.bytes, {
    this.chunkSize = 64 * 1024,
  });

  @override
  final String name;
  final Uint8List bytes;
  final int chunkSize;

  @override
  int get size => bytes.length;

  @override
  Stream<List<int>> open() async* {
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = offset + chunkSize > bytes.length
          ? bytes.length
          : offset + chunkSize;
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }
}

/// `file_picker` ile seçilen dosya: diskten akış okur.
class PlatformDocumentSource implements DocumentUploadSource {
  PlatformDocumentSource(this._file, this.size);

  final PlatformFile _file;

  @override
  String get name => _file.name;

  @override
  final int size;

  @override
  Stream<List<int>> open() => _file.readAsByteStream();
}

/// Dosya seçici (sahte uygulaması testlerde kullanılır).
abstract class DocumentPicker {
  /// Kullanıcı vazgeçerse null; seçilemezse hata fırlatır (arayüz Türkçe ileti gösterir).
  Future<DocumentUploadSource?> pick();

  /// Seçilen dosyaların eklentinin uygulama önbelleğine bıraktığı KOPYALARI siler. Android'de `file_picker` seçilen
  /// dosyayı `<önbellek>/file_picker/...` altına kopyalar ve kendiliğinden silmez; belge (T.C. / IBAN içerebilir)
  /// kalıcı kalmasın. Yalnız seçilen kaynaklarla işi BİTİNCE (yükleme tamamlandı ya da pencere kapandı) çağrılır:
  /// önce çağrılırsa yüklenecek dosya silinir. Hata fırlatmaz.
  Future<void> release() async {}
}

/// Gerçek seçici: izinli uzantılarla sınırlıdır; DOCX/XLSX dahil (sunucu içerik imzasını yine doğrular).
class FilePickerDocumentPicker implements DocumentPicker {
  const FilePickerDocumentPicker({this.clearCache});

  /// Önbellek temizleyici (testler içindir; verilmezse [purgeLocalSharedCaches] yalnız picker önbelleğini siler).
  final Future<void> Function()? clearCache;

  @override
  Future<DocumentUploadSource?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Yüklenecek belgeyi seçin',
      type: FileType.custom,
      allowedExtensions: DocumentFileRules.pickerExtensions,
    );
    if (file == null) return null;
    final size = await file.length() ?? file.lengthSync() ?? 0;
    return PlatformDocumentSource(file, size);
  }

  @override
  Future<void> release() async {
    try {
      final clear = clearCache;
      if (clear != null) {
        await clear();
      } else {
        // Yalnız picker önbelleği: share_plus kopyası süren bir paylaşımın olabilir (gecikmeli silme siler).
        await purgeLocalSharedCaches(shareCache: false);
      }
    } catch (_) {
      // En iyi çaba.
    }
  }
}
