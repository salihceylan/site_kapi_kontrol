// Talep fotoğrafı seçimi (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri").
//
// Fotoğraf BELLEĞE okunur (en çok 5 MB x 4): küçük görseli ve yüklemeyi aynı baytlar besler. Boyut sınırını aşan dosya
// okunmaz (yalnız adı ve boyutu taşınır; ön doğrulama reddeder). Tür içerik imzasından anlaşılır (uzantıdan önce);
// okunan fotoğrafın piksel boyutu çözülmeden ölçülür ([probeImageSize]) ve sunucu sınırını aşan fotoğraf daha
// seçimde reddedilir. Geçersiz seçimler sınırdaki yerleri DOLDURMAZ, ayrıca bildirilir ([WorkPhotoSelection.rejected]).
//
// iOS: fotoğraf arşivi seçicisi (PHPicker, `FileType.image`) "uyumlu" gösterimle açılır: HEIC fotoğraf JPEG'e
// dönüştürülerek gelir. Diğer platformlar uzantı süzgeçli dosya seçicisini kullanır. Testlerde sahte [WorkPhotoPicker]
// kullanılır. Dosya adı günlüğe yazılmaz.
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';

/// Görselin piksel boyutu ÇÖZMEDEN (yalnız başlıktan): `ui.ImmutableBuffer` + `ui.ImageDescriptor.encoded`. Okunamazsa
/// (tanınmayan biçim, desteklenmeyen platform) null. Hata fırlatmaz.
Future<({int width, int height})?> probeImageSize(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Seçilen bir fotoğraf: ad + baytlar (+ ölçüldüyse piksel boyutu).
@immutable
class WorkPhotoPick {
  const WorkPhotoPick({
    required this.name,
    required this.bytes,
    String? mimeType,
    int? declaredSize,
    this.width,
    this.height,
  }) : _mimeType = mimeType,
       _declaredSize = declaredSize;

  /// Boyut sınırını aşan dosya: baytlar OKUNMAZ, yalnız ad ve boyut taşınır (ön doğrulama "çok büyük" der).
  factory WorkPhotoPick.oversized({required String name, required int size}) =>
      WorkPhotoPick(name: name, bytes: Uint8List(0), declaredSize: size);

  final String name;
  final Uint8List bytes;
  final String? _mimeType;
  final int? _declaredSize;

  /// Ölçülen piksel boyutu (ölçülemediyse null: çözünürlük denetimi sunucuya kalır).
  final int? width;
  final int? height;

  /// Bayt cinsinden boyut (okunmayan dosyada bildirilen boyut).
  int get size => _declaredSize ?? bytes.length;

  /// İçerik imzasından tür (JPEG / PNG / WebP); okunmadıysa ya da tanınmazsa null.
  String? get sniffedMimeType =>
      bytes.isEmpty ? null : WorkAttachmentRules.sniffMimeType(bytes);

  /// Sunucuya bildirilen içerik türü: önce içerik imzası, sonra uzantı, sonra seçicinin verdiği; o da yoksa ikili.
  String get mimeType =>
      sniffedMimeType ??
      WorkAttachmentRules.mimeTypeOf(name) ??
      _mimeType ??
      'application/octet-stream';

  /// Ön doğrulama hatası (boyut / boş / tür / çözünürlük); sorun yoksa null.
  String? get validationError => WorkAttachmentRules.validate(
    fileName: name,
    size: size,
    content: bytes.isEmpty ? null : bytes,
    width: width,
    height: height,
  );

  bool get isValid => validationError == null;

  /// Yükleme kaynağı (bellekten akış; yeniden denemede baştan okunur).
  DocumentUploadSource get source => MemoryDocumentSource(name, bytes);
}

/// Seçim sonucu: geçerli fotoğraflar (en çok istenen sayıda), geçersizler (ayrıca bildirilir, yer DOLDURMAZ) ve sınır
/// yüzünden alınmayan geçerli dosya sayısı.
@immutable
class WorkPhotoSelection {
  const WorkPhotoSelection({
    this.picks = const <WorkPhotoPick>[],
    this.rejected = const <WorkPhotoPick>[],
    this.droppedCount = 0,
  });

  final List<WorkPhotoPick> picks;

  /// Ön doğrulamadan geçemeyen seçimler (neden: [WorkPhotoPick.validationError]).
  final List<WorkPhotoPick> rejected;

  /// Kullanıcı yerden fazla dosya seçti: fazlası alınmadı (arayüz sınır uyarısı gösterir).
  final int droppedCount;

  bool get isEmpty => picks.isEmpty && rejected.isEmpty && droppedCount == 0;
}

/// Fotoğraf seçici (sahte uygulaması testlerde kullanılır).
abstract class WorkPhotoPicker {
  /// En çok [maxCount] GEÇERLİ fotoğraf okur; kullanıcı vazgeçerse boş seçim; seçilemezse hata fırlatır (arayüz Türkçe
  /// ileti gösterir).
  Future<WorkPhotoSelection> pick({required int maxCount});

  /// Eklentinin uygulama önbelleğine bıraktığı KOPYALARI siler (Android `file_picker` kopyalar ve silmez). Yalnız
  /// seçilen fotoğraflarla iş BİTİNCE çağrılır. Hata fırlatmaz.
  Future<void> release() async {}
}

/// Gerçek seçici: `file_picker`; dosyalar belleğe okunur, türü içerikten anlaşılır, piksel boyutu ölçülür.
class FilePickerWorkPhotoPicker implements WorkPhotoPicker {
  const FilePickerWorkPhotoPicker({this.clearCache});

  /// Önbellek temizleyici (testler içindir; verilmezse yalnız picker önbelleği silinir).
  final Future<void> Function()? clearCache;

  /// iOS'ta fotoğraf arşivi seçicisi (PHPicker) kullanılır.
  static bool get _iosPhotoLibrary =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<WorkPhotoSelection> pick({required int maxCount}) async {
    if (maxCount <= 0) return const WorkPhotoSelection();
    // file_picker 13: `pickFiles` her zaman çoklu seçimdir (`allowMultiple` parametresi yok).
    final files = _iosPhotoLibrary
        ? await FilePicker.pickFiles(
            dialogTitle: 'Fotoğraf seçin',
            type: FileType.image,
            // HEIC gibi biçimler uyumlu gösterime (JPEG) dönüştürülür; compressionQuality 0 kalmalı.
            darwinOptions: const DarwinOptions(
              assetRepresentationMode: DarwinAssetRepresentationMode.compatible,
            ),
          )
        : await FilePicker.pickFiles(
            dialogTitle: 'Fotoğraf seçin',
            type: FileType.custom,
            allowedExtensions: WorkAttachmentRules.pickerExtensions,
          );
    final picks = <WorkPhotoPick>[];
    final rejected = <WorkPhotoPick>[];
    var dropped = 0;
    for (final file in files) {
      if (picks.length >= maxCount) {
        // Yer kalmadı: dosya okunmaz (bellek), yalnız sayılır.
        dropped++;
        continue;
      }
      final size = file.lengthSync() ?? await file.length() ?? 0;
      final WorkPhotoPick pick;
      if (size > kWorkAttachmentMaxBytes) {
        // Sınırı aşan dosya belleğe alınmaz.
        pick = WorkPhotoPick.oversized(name: file.name, size: size);
      } else {
        final bytes = await file.readAsBytes();
        final dimensions = await probeImageSize(bytes);
        pick = WorkPhotoPick(
          name: file.name,
          bytes: bytes,
          width: dimensions?.width,
          height: dimensions?.height,
        );
      }
      // Geçersiz seçim sınırdaki yeri DOLDURMAZ; ayrıca bildirilir.
      if (pick.isValid) {
        picks.add(pick);
      } else {
        rejected.add(pick);
      }
    }
    return WorkPhotoSelection(picks: picks, rejected: rejected, droppedCount: dropped);
  }

  @override
  Future<void> release() async {
    try {
      final clear = clearCache;
      if (clear != null) {
        await clear();
      } else {
        await purgeLocalSharedCaches(shareCache: false);
      }
    } catch (_) {
      // En iyi çaba.
    }
  }
}
