// Talep fotoğrafının yüklemeden ÖNCE hazırlanması (docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri").
//
// Telefon fotoğrafları (iOS "uyumlu" gösterimle JPEG'e dönüşen 24 / 48 MP fotoğraflar, çoğu Android fotoğrafı) 5 MB
// sınırını aşar. Bu yüzden SEÇİLEN HER fotoğraf, doğrulama ve yüklemeden önce yeniden kodlanır: uzun kenar en çok
// 2560 piksel (zaten küçükse boyut korunur), JPEG kalite 85; dosya adı `.jpg`, tür `image/jpeg` olur.
//
// Gizlilik (KVKK): çıktı, çözülmüş piksellerden SIFIRDAN kodlanır; EXIF dahil HİÇBİR üstveri taşımaz. Fotoğrafın
// çekildiği yerin GPS konumu, cihaz bilgisi ve çekim zamanı böylece silinir (arayüz bunu kullanıcıya söyler).
// EXIF yönü (orientation) uygulanır: çıktı her zaman diktir ve yön etiketi taşımaz. Motorun (dart:ui) yönü uygulayıp
// uygulamadığı bir kez, 2x1 piksellik yönlü bir JPEG ile denenir; uygulamıyorsa yön `package:image` ile döndürülür.
//
// Bellek bombası koruması (çözmeden ÖNCE, yalnız başlıktan): sunucu sınırını aşan görsel (40 milyon piksel ya da kenar
// 12.000) çözülmez. Tek ayrık durum yerel platformlarda JPEG'dir: motor JPEG'i hedef boyuta yakın, 1/8 adımlarla
// küçültülmüş çözer (DCT ölçekleme), bu yüzden bellek hedef boyuta göre ayrılır; 48 MP fotoğraf (~49 milyon piksel)
// böylece hazırlanabilir. JPEG için mutlak üst sınır 64 milyon kaynak pikseldir (web'de ölçekli çözme varsayılmaz).
//
// Kodlama UI iş parçacığında yapılmaz (`compute`, ayrı isolate). Web'de isolate yoktur: çözme eşzamansızdır, piksel
// dönüşümü parça parça yapılır ve aralarda beklenir (çerçeve çizilir), arayüz "Fotoğraf hazırlanıyor..." gösterir; son
// JPEG kodlaması tek adımdır (`package:image` parçalı kodlama sunmaz).
//
// Hazırlama yapılamazsa (tanınmayan biçim, sınırı aşan görsel, çözme hatası) ÖZGÜN baytlar döner; olağan doğrulama
// karar verir. Dosya adı ve içerik günlüğe yazılmaz.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';

/// Hazırlanan fotoğrafın en uzun kenarı (piksel).
const int kWorkPhotoMaxEdge = 2560;

/// Hazırlanan fotoğrafın JPEG kalitesi.
const int kWorkPhotoJpegQuality = 85;

/// Hazırlanmak üzere belleğe okunacak en büyük kaynak dosya; üstündeki dosya okunmaz, "çok büyük" diye reddedilir.
const int kWorkPhotoReadMaxBytes = 50 * 1024 * 1024;

/// Yerel platformlarda JPEG kaynağın çözülebileceği en çok piksel (ölçekli çözme; bkz. dosya başı).
const int kWorkPhotoJpegMaxSourcePixels = 64000000;

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

/// Hazırlama sonucu: hazırlandıysa yeni ad (`.jpg`) + JPEG baytları ([prepared] true); aksi hâlde özgün ad ve baytlar.
/// [width] / [height] biliniyorsa piksel boyutudur (doğrulama çözünürlüğü denetler).
@immutable
class WorkPreparedPhoto {
  const WorkPreparedPhoto({
    required this.name,
    required this.bytes,
    this.width,
    this.height,
    this.prepared = false,
  });

  final String name;
  final Uint8List bytes;
  final int? width;
  final int? height;
  final bool prepared;
}

/// `IMG_1.HEIC` -> `IMG_1.jpg`; uzantısız ad `.jpg` alır; yol parçaları atılır; boşsa `fotograf.jpg`.
String workJpegName(String name) {
  var base = name.trim();
  final slash = base.lastIndexOf(RegExp(r'[\\/]'));
  if (slash >= 0) base = base.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  if (dot >= 0) base = base.substring(0, dot);
  base = base.trim();
  if (base.isEmpty) base = 'fotograf';
  return '$base.jpg';
}

/// Fotoğrafı hazırlar (bkz. dosya başı). [web] testler içindir (varsayılan `kIsWeb`). Hata fırlatmaz: hazırlanamazsa
/// özgün baytlar döner.
Future<WorkPreparedPhoto> prepareWorkPhoto(
  String name,
  Uint8List bytes, {
  bool? web,
}) async {
  final isWeb = web ?? kIsWeb;
  if (bytes.isEmpty) return WorkPreparedPhoto(name: name, bytes: bytes);
  final size = await probeImageSize(bytes);
  // Başlığı okunamayan içerik çözülemez: doğrulama (tür / boyut) karar verir.
  if (size == null) return WorkPreparedPhoto(name: name, bytes: bytes);
  final original = WorkPreparedPhoto(
    name: name,
    bytes: bytes,
    width: size.width,
    height: size.height,
  );
  final jpeg = WorkAttachmentRules.sniffMimeType(bytes) == 'image/jpeg';
  if (!workPhotoDecodeAllowed(size.width, size.height, jpeg: jpeg, web: isWeb)) {
    // Bellek bombası koruması: çözülmez; doğrulama çözünürlük iletisini verir.
    return original;
  }
  try {
    // EXIF yönü yalnız JPEG'de; motor uygulamıyorsa kodlamada uygulanır.
    var orientation = 1;
    if (jpeg) {
      final exifOrientation = _exifOrientation(bytes);
      if (exifOrientation > 1 && !await _platformAppliesExifOrientation()) {
        orientation = exifOrientation;
      }
    }
    if (isWeb) await _yieldFrame();
    final image = await _decode(bytes, _targetSize);
    final width = image.width;
    final height = image.height;
    final ByteData? rgba;
    try {
      rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
    if (rgba == null) return original;
    final job = WorkJpegJob(
      rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      width: width,
      height: height,
      orientation: orientation,
      quality: kWorkPhotoJpegQuality,
    );
    final encoded = isWeb
        ? await _encodeChunked(job)
        : await compute(encodeWorkJpeg, job, debugLabel: 'work_photo_jpeg');
    final swapped = orientation >= 5 && orientation <= 8;
    return WorkPreparedPhoto(
      name: workJpegName(name),
      bytes: encoded,
      width: swapped ? height : width,
      height: swapped ? width : height,
      prepared: true,
    );
  } catch (_) {
    return original;
  }
}

/// Çözme izni, ÇÖZMEDEN ÖNCE yalnız başlıktaki boyuta göre (bkz. dosya başı): yerel platformda JPEG en çok
/// [kWorkPhotoJpegMaxSourcePixels] (ölçekli çözme), diğerleri sunucu sınırı (40 milyon piksel / kenar 12.000).
@visibleForTesting
bool workPhotoDecodeAllowed(
  int width,
  int height, {
  required bool jpeg,
  required bool web,
}) {
  if (width <= 0 || height <= 0) return false;
  if (jpeg && !web) return width * height <= kWorkPhotoJpegMaxSourcePixels;
  return !WorkAttachmentRules.dimensionsTooLarge(width, height);
}

/// Uzun kenar [kWorkPhotoMaxEdge]'i aşıyorsa yalnız uzun kenar verilir (oran korunur); küçükse özgün boyut.
ui.TargetImageSize _targetSize(int intrinsicWidth, int intrinsicHeight) {
  if (math.max(intrinsicWidth, intrinsicHeight) <= kWorkPhotoMaxEdge) {
    return const ui.TargetImageSize();
  }
  return intrinsicWidth >= intrinsicHeight
      ? const ui.TargetImageSize(width: kWorkPhotoMaxEdge)
      : const ui.TargetImageSize(height: kWorkPhotoMaxEdge);
}

Future<ui.Image> _decode(
  Uint8List bytes,
  ui.TargetImageSizeCallback? getTargetSize,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  // Arabellek bu çağrıda bırakılır (dart:ui sözleşmesi).
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: getTargetSize,
  );
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// JPEG'in EXIF yön değeri (1..8); yoksa / okunamazsa 1. Yalnız üstveri bölümü okunur (görsel çözülmez).
int _exifOrientation(Uint8List jpeg) {
  try {
    final value = img.decodeJpgExif(jpeg)?.imageIfd.orientation;
    return value != null && value >= 1 && value <= 8 ? value : 1;
  } catch (_) {
    return 1;
  }
}

Future<bool>? _orientationProbe;

/// Motor (dart:ui) EXIF yönünü çözerken uyguluyor mu? Bir kez denenir: yönü 6 olan 2x1 JPEG, uygulanıyorsa 1x2 çözülür.
/// Denenemezse uygulandığı varsayılır (yerel platformların hepsi uygular).
@visibleForTesting
Future<bool> debugPlatformAppliesExifOrientation() =>
    _platformAppliesExifOrientation();

Future<bool> _platformAppliesExifOrientation() =>
    _orientationProbe ??= _probeOrientation();

Future<bool> _probeOrientation() async {
  try {
    final probe = img.Image(width: 2, height: 1);
    probe.exif.imageIfd.orientation = 6;
    final image = await _decode(img.encodeJpg(probe), null);
    final applied = image.width == 1 && image.height == 2;
    image.dispose();
    return applied;
  } catch (_) {
    return true;
  }
}

/// Web: tarayıcıya bir çerçevelik süre bırakır (arayüz "Fotoğraf hazırlanıyor..." çizebilsin).
Future<void> _yieldFrame() =>
    Future<void>.delayed(const Duration(milliseconds: 16));

/// Ayrı isolate'e giden kodlama işi: önceden çarpılmış (premultiplied) RGBA pikseller, boyut, uygulanacak EXIF yönü
/// (1 = yok) ve kalite.
@immutable
class WorkJpegJob {
  const WorkJpegJob({
    required this.rgba,
    required this.width,
    required this.height,
    this.orientation = 1,
    this.quality = kWorkPhotoJpegQuality,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int orientation;
  final int quality;
}

/// [WorkJpegJob]'u JPEG'e kodlar (isolate içinde çalışır; üst düzey işlev). Saydam alan BEYAZ zemine oturtulur (JPEG'de
/// saydamlık yok; siyah görünmesin); EXIF dahil hiçbir üstveri yazılmaz.
Uint8List encodeWorkJpeg(WorkJpegJob job) {
  final pixels = job.width * job.height;
  final rgb = Uint8List(pixels * 3);
  _flattenOnWhite(job.rgba, rgb, 0, pixels);
  return _encodeRgb(rgb, job);
}

/// Web (isolate yok): aynı iş, piksel dönüşümü parça parça ve aralarda beklenerek (arayüz çizilebilsin). Son JPEG
/// kodlaması tek adımdır (`package:image` parçalı kodlama sunmaz).
Future<Uint8List> _encodeChunked(WorkJpegJob job) async {
  final pixels = job.width * job.height;
  final rgb = Uint8List(pixels * 3);
  const chunk = 1 << 20;
  for (var start = 0; start < pixels; start += chunk) {
    _flattenOnWhite(job.rgba, rgb, start, math.min(pixels, start + chunk));
    await _yieldFrame();
  }
  return _encodeRgb(rgb, job);
}

/// Önceden çarpılmış RGBA -> beyaz zeminde RGB: `c + (255 - a)`.
void _flattenOnWhite(Uint8List rgba, Uint8List rgb, int from, int to) {
  for (var i = from; i < to; i++) {
    final o = i * 4;
    final j = i * 3;
    final cover = 255 - rgba[o + 3];
    if (cover == 0) {
      rgb[j] = rgba[o];
      rgb[j + 1] = rgba[o + 1];
      rgb[j + 2] = rgba[o + 2];
    } else {
      rgb[j] = math.min(255, rgba[o] + cover);
      rgb[j + 1] = math.min(255, rgba[o + 1] + cover);
      rgb[j + 2] = math.min(255, rgba[o + 2] + cover);
    }
  }
}

Uint8List _encodeRgb(Uint8List rgb, WorkJpegJob job) {
  var image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  if (job.orientation > 1) {
    image.exif.imageIfd.orientation = job.orientation;
    image = img.bakeOrientation(image);
  }
  // Üstveri YOK: EXIF (GPS konumu, cihaz, tarih) yazılmaz.
  image.exif = img.ExifData();
  return img.encodeJpg(image, quality: job.quality);
}
