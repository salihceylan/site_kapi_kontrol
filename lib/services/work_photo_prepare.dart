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
// Piksel boyutu önce motorun başlık okuyucusundan (`ui.ImageDescriptor`) alınır. WEB'de bu desteklenmez (genişlik /
// yükseklik `UnsupportedError` fırlatır): o zaman bayt düzeyinde, BELLEK AYIRMAYAN başlık okuyucu kullanılır
// ([readImageHeaderSize]: PNG IHDR, WebP 'VP8 ' / 'VP8L' / 'VP8X', JPEG işaret taraması; sunucudaki
// `readImageDimensions` ile aynı kurallar). Böylece web'de de koruma uygulanır ve fotoğraf küçültülür.
//
// Kodlama UI iş parçacığında yapılmaz (`compute`, ayrı isolate). Web'de isolate yoktur: çözme eşzamansızdır, piksel
// dönüşümü parça parça yapılır ve aralarda beklenir (çerçeve çizilir), arayüz "Fotoğraf hazırlanıyor..." gösterir; son
// JPEG kodlaması tek adımdır (`package:image` parçalı kodlama sunmaz).
//
// Hazırlama yapılamazsa (sınırı aşan görsel, çözme / kodlama hatası, başlığı okunamayan içerik) yeniden kodlama olmaz
// ve GİZLİLİK İÇİN KAPALI KALINIR ([stripImageMetadata]): JPEG'in APPn (EXIF / XMP / IPTC, ICC) ve COM bölütleri,
// PNG'nin eXIf / tEXt / zTXt / iTXt / tIME öbekleri, WebP'nin EXIF / XMP öbekleri piksel verisine dokunmadan atılır,
// dosya sonuna eklenmiş veri (ör. hareketli fotoğraf videosu) kesilir. Ayıklanamayan (yapısı bozuk) JPEG / PNG / WebP
// hiç yüklenmez ([WorkPreparedPhoto.error]). Sonra olağan doğrulama karar verir. Dosya adı ve içerik günlüğe yazılmaz.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;
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

/// Piksel boyutu ölçer (çözmeden). Testlerde motor ölçeri yerine verilir (ör. web'i taklit eden, hep null dönen).
typedef WorkImageSizeProbe =
    Future<({int width, int height})?> Function(Uint8List bytes);

/// Motorun başlık okuyucusuyla piksel boyutu (ÇÖZMEDEN): `ui.ImmutableBuffer` + `ui.ImageDescriptor.encoded`. Web'de
/// desteklenmez (null). Okunamazsa null; hata fırlatmaz.
Future<({int width, int height})?> probeImageSizeWithDescriptor(
  Uint8List bytes,
) async {
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

/// Görselin piksel boyutu ÇÖZMEDEN: önce motorun başlık okuyucusu ([descriptorProbe], varsayılan
/// [probeImageSizeWithDescriptor]); o null dönerse (web, tanınmayan biçim) bayt düzeyinde başlık okuyucu
/// ([readImageHeaderSize]). İkisi de okuyamazsa null. Hata fırlatmaz.
Future<({int width, int height})?> probeImageSize(
  Uint8List bytes, {
  WorkImageSizeProbe? descriptorProbe,
}) async {
  if (bytes.isEmpty) return null;
  final fromEngine = await (descriptorProbe ?? probeImageSizeWithDescriptor)(
    bytes,
  );
  return fromEngine ?? readImageHeaderSize(bytes);
}

// --- Başlık okuyucu (bellek ayırmaz) -----------------------------------------------------------------------------

/// JPEG kare başlangıcı (SOFn) işaretleri: C0..CF, DHT (C4), JPG (C8), DAC (CC) HARİÇ.
bool _isJpegSof(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

/// Uzunluk alanı olmayan bağımsız işaretler: TEM (01), RST0..7 (D0..D7).
bool _isJpegStandalone(int marker) =>
    marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7);

const int _jpegMaxHeaderSegments = 1024;

int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u24le(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);

// Üst bayt çarpmayla eklenir: web'de (32 bit bit işlemleri) de işaretsiz sonuç.
int _u32be(Uint8List b, int o) =>
    b[o] * 0x1000000 + ((b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
int _u32le(Uint8List b, int o) =>
    b[o + 3] * 0x1000000 + ((b[o + 2] << 16) | (b[o + 1] << 8) | b[o]);

bool _ascii(Uint8List b, int o, String text) {
  if (o < 0 || o + text.length > b.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (b[o + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

({int width, int height})? _dimensions(int width, int height) =>
    width >= 1 && height >= 1 ? (width: width, height: height) : null;

/// Piksel boyutu YALNIZ başlıktan, hiçbir tampon ayırmadan (sunucudaki `readImageDimensions` ile aynı kurallar):
/// - PNG: IHDR (16: genişlik, 20: yükseklik; büyük uçlu 32 bit);
/// - WebP: 'VP8 ' (26 / 28: 14 bit), 'VP8L' (21: 14 + 14 bit, değer + 1), 'VP8X' (24 / 27: 24 bit, değer + 1);
/// - JPEG: işaret dizisi taranır (en çok 1024 bölüt), ilk SOFn bölütünde yükseklik / genişlik; SOFn'den önce SOS /
///   EOI / ikinci SOI gelirse bozuk.
/// Tanınmayan / bozuk içerikte ya da boyut 0 ise null.
({int width, int height})? readImageHeaderSize(Uint8List b) {
  switch (WorkAttachmentRules.sniffMimeType(b)) {
    case 'image/png':
      if (b.length < 24 || !_ascii(b, 12, 'IHDR')) return null;
      return _dimensions(_u32be(b, 16), _u32be(b, 20));
    case 'image/webp':
      if (b.length < 30) return null;
      if (_ascii(b, 12, 'VP8 ')) {
        if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) return null;
        return _dimensions(_u16le(b, 26) & 0x3FFF, _u16le(b, 28) & 0x3FFF);
      }
      if (_ascii(b, 12, 'VP8L')) {
        if (b[20] != 0x2F) return null;
        final bits = _u32le(b, 21);
        return _dimensions((bits & 0x3FFF) + 1, ((bits ~/ 0x4000) & 0x3FFF) + 1);
      }
      if (_ascii(b, 12, 'VP8X')) {
        return _dimensions(_u24le(b, 24) + 1, _u24le(b, 27) + 1);
      }
      return null;
    case 'image/jpeg':
      return _jpegHeaderSize(b);
  }
  return null;
}

({int width, int height})? _jpegHeaderSize(Uint8List b) {
  var p = 2; // SOI (FF D8) sonrası
  for (
    var segment = 0;
    segment < _jpegMaxHeaderSegments && p + 2 <= b.length;
    segment++
  ) {
    if (b[p] != 0xFF) return null;
    final marker = b[p + 1];
    if (marker == 0xFF) {
      p += 1; // dolgu baytı
      continue;
    }
    if (_isJpegStandalone(marker)) {
      p += 2;
      continue;
    }
    // SOFn'den önce EOI / SOS / ikinci SOI: bozuk.
    if (marker == 0xD9 || marker == 0xDA || marker == 0xD8) return null;
    if (p + 4 > b.length) return null;
    final length = _u16be(b, p + 2);
    if (length < 2) return null;
    if (_isJpegSof(marker)) {
      // kesinlik (1), yükseklik (2), genişlik (2)
      if (length < 7 || p + 9 > b.length) return null;
      return _dimensions(_u16be(b, p + 7), _u16be(b, p + 5));
    }
    p += 2 + length;
  }
  return null;
}

// --- Üstveri ayıklama (yeniden kodlamadan) ------------------------------------------------------------------------

/// Yeniden kodlanmayan görselin üstverisini piksel verisine dokunmadan atar (bkz. dosya başı). JPEG / PNG / WebP
/// dışındaki içerik olduğu gibi döner (sunucu ve ön doğrulama zaten reddeder). Yapısı bozuk JPEG / PNG / WebP'de null:
/// çağıran yüklemez (gizlilik için kapalı kalır).
Uint8List? stripImageMetadata(Uint8List bytes) {
  switch (WorkAttachmentRules.sniffMimeType(bytes)) {
    case 'image/jpeg':
      return stripJpegMetadata(bytes);
    case 'image/png':
      return _stripPngMetadata(bytes);
    case 'image/webp':
      return _stripWebpMetadata(bytes);
  }
  return bytes;
}

const int _jpegMaxSegments = 65536;

/// JPEG'den APPn (E0..EF: EXIF / GPS, XMP, IPTC / APP13, ICC, MPF...) ve COM (FE) bölütlerini atar; bölütler ve tarama
/// verisi YENİDEN KODLANMADAN kopyalanır. Korunanlar: yalnız temel JFIF APP0 (küçük resimsiz, 16 bayt) ve renk dönüşümü
/// için Adobe APP14 (14 bayt; kişisel veri taşımaz). Taramalar arasındaki APPn / COM de atılır; EOI'den sonrası (ekli
/// görseller, hareketli fotoğraf videosu gibi kuyruklar) kesilir. Yapı bozuksa (SOS'tan önce dosya biter, bölüt boyu
/// taşar, SOS'tan önce EOI / ikinci SOI) null.
Uint8List? stripJpegMetadata(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 2));
  var p = 2;
  var segments = 0;
  var inScan = false;
  while (true) {
    if (inScan) {
      // Tarama (entropi) verisi: FF 00 (doldurulmuş bayt), RSTn ve FF dolguları veridir; ilk gerçek işarete dek kopyala.
      final start = p;
      while (p < b.length) {
        if (b[p] == 0xFF && p + 1 < b.length) {
          final next = b[p + 1];
          if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
            p += 2;
            continue;
          }
          if (next == 0xFF) {
            p += 1;
            continue;
          }
          break;
        }
        p += 1;
      }
      if (p > start) out.add(Uint8List.sublistView(b, start, p));
      // EOI'siz kesik dosya: üstverisi zaten atıldı; olduğu gibi biter.
      if (p >= b.length) break;
    }
    if (++segments > _jpegMaxSegments) return null;
    if (p + 2 > b.length) return null; // SOS'tan önce dosya bitti
    if (b[p] != 0xFF) return null;
    final marker = b[p + 1];
    if (marker == 0xFF) {
      p += 1; // dolgu baytı
      continue;
    }
    if (_isJpegStandalone(marker)) {
      out.add(Uint8List.sublistView(b, p, p + 2));
      p += 2;
      continue;
    }
    if (marker == 0xD9) {
      if (!inScan) return null; // taramadan önce EOI
      out.add(Uint8List.sublistView(b, p, p + 2));
      break; // EOI: sonrası (kuyruk) atılır
    }
    if (marker == 0xD8) return null; // ikinci SOI
    if (p + 4 > b.length) return null;
    final length = _u16be(b, p + 2);
    final end = p + 2 + length;
    if (length < 2 || end > b.length) return null;
    if (!_isJpegMetadataSegment(b, p, marker, length)) {
      out.add(Uint8List.sublistView(b, p, end));
    }
    p = end;
    if (marker == 0xDA) inScan = true; // SOS başlığı kopyalandı; tarama verisi başlıyor
  }
  return out.takeBytes();
}

bool _isJpegMetadataSegment(Uint8List b, int p, int marker, int length) {
  if (marker == 0xFE) return true; // COM
  if (marker < 0xE0 || marker > 0xEF) return false;
  // Temel JFIF APP0 (16 bayt: küçük resim yok) ve Adobe APP14 (14 bayt: renk dönüşümü) korunur.
  if (marker == 0xE0 && length == 16 && _ascii(b, p + 4, 'JFIF\u0000')) {
    return false;
  }
  if (marker == 0xEE && length == 14 && _ascii(b, p + 4, 'Adobe')) {
    return false;
  }
  return true;
}

const List<String> _pngMetadataChunks = <String>['eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME'];

/// PNG'den eXIf / tEXt / zTXt / iTXt / tIME öbeklerini atar (diğer öbekler ve CRC'leri aynen); IEND'den sonrası
/// kesilir. Yapı bozuksa (öbek dosyayı aşar, IEND yok) null.
Uint8List? _stripPngMetadata(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var p = 8;
  while (true) {
    if (p + 12 > b.length) return null;
    final length = _u32be(b, p);
    final end = p + 12 + length;
    if (end > b.length) return null;
    final metadata = _pngMetadataChunks.any((type) => _ascii(b, p + 4, type));
    if (!metadata) out.add(Uint8List.sublistView(b, p, end));
    final last = _ascii(b, p + 4, 'IEND');
    p = end;
    if (last) break;
  }
  return out.takeBytes();
}

/// WebP'den EXIF ve 'XMP ' öbeklerini atar, VP8X bayraklarındaki EXIF (0x08) / XMP (0x04) bitlerini siler, RIFF
/// boyunu yeniden yazar; RIFF'ten sonrası kesilir. Yapı bozuksa null.
Uint8List? _stripWebpMetadata(Uint8List b) {
  if (b.length < 12) return null;
  final riffEnd = 8 + _u32le(b, 4);
  if (riffEnd < 12 || riffEnd > b.length) return null;
  final chunks = <Uint8List>[];
  var total = 4; // 'WEBP'
  var p = 12;
  while (p < riffEnd) {
    if (p + 8 > riffEnd) return null;
    final size = _u32le(b, p + 4);
    var end = p + 8 + size + (size & 1);
    // Bazı kodlayıcılar son öbeğin doldurma baytını yazmaz.
    if (end > riffEnd) {
      if (p + 8 + size != riffEnd) return null;
      end = riffEnd;
    }
    if (!_ascii(b, p, 'EXIF') && !_ascii(b, p, 'XMP ')) {
      var chunk = Uint8List.sublistView(b, p, end);
      if (_ascii(b, p, 'VP8X') && size >= 1) {
        chunk = Uint8List.fromList(chunk);
        chunk[8] &= 0xF3; // EXIF (0x08) ve XMP (0x04) bayrakları
      }
      chunks.add(chunk);
      total += chunk.length;
    }
    p = end;
  }
  final header = Uint8List(12)
    ..setRange(0, 4, b)
    ..[4] = total & 0xFF
    ..[5] = (total >> 8) & 0xFF
    ..[6] = (total >> 16) & 0xFF
    ..[7] = (total ~/ 0x1000000) & 0xFF
    ..setRange(8, 12, b, 8);
  final out = BytesBuilder(copy: false)..add(header);
  for (final chunk in chunks) {
    out.add(chunk);
  }
  return out.takeBytes();
}

/// Hazırlama sonucu: hazırlandıysa yeni ad (`.jpg`) + JPEG baytları ([prepared] true); aksi hâlde özgün ad ve
/// üstverisi ayıklanmış baytlar. [width] / [height] biliniyorsa piksel boyutudur (doğrulama çözünürlüğü denetler).
/// [error] doluysa fotoğraf YÜKLENMEZ (üstverisi ayıklanamadı; gizlilik için kapalı kalınır).
@immutable
class WorkPreparedPhoto {
  const WorkPreparedPhoto({
    required this.name,
    required this.bytes,
    this.width,
    this.height,
    this.prepared = false,
    this.error,
  });

  final String name;
  final Uint8List bytes;
  final int? width;
  final int? height;
  final bool prepared;
  final String? error;
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

/// Fotoğrafı hazırlar (bkz. dosya başı). [web] ve [descriptorProbe] testler içindir (varsayılanlar `kIsWeb` ve motor
/// ölçeri; web'de motor ölçeri hep null döner). Hata fırlatmaz: yeniden kodlanamazsa üstverisi ayıklanmış özgün
/// baytlar, ayıklanamazsa [WorkPreparedPhoto.error] döner.
Future<WorkPreparedPhoto> prepareWorkPhoto(
  String name,
  Uint8List bytes, {
  bool? web,
  WorkImageSizeProbe? descriptorProbe,
}) async {
  final isWeb = web ?? kIsWeb;
  if (bytes.isEmpty) return WorkPreparedPhoto(name: name, bytes: bytes);
  final size = await probeImageSize(bytes, descriptorProbe: descriptorProbe);
  // Başlığı okunamayan içerik çözülmez: üstverisi ayıklanır, doğrulama (tür / boyut) karar verir.
  if (size == null) return _notReencoded(name, bytes);
  WorkPreparedPhoto original() =>
      _notReencoded(name, bytes, width: size.width, height: size.height);
  final jpeg = WorkAttachmentRules.sniffMimeType(bytes) == 'image/jpeg';
  if (!workPhotoDecodeAllowed(size.width, size.height, jpeg: jpeg, web: isWeb)) {
    // Bellek bombası koruması: çözülmez; doğrulama çözünürlük iletisini verir.
    return original();
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
    if (rgba == null) return original();
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
    return original();
  }
}

/// Yeniden kodlanmayan fotoğraf: gizlilik için kapalı kalınır. Üstveri ayıklanır ([stripImageMetadata]); yapısı bozuk
/// JPEG / PNG / WebP'de ayıklanamaz ve fotoğraf yüklenmez ([WorkAttachmentRules.metadataMessage]).
WorkPreparedPhoto _notReencoded(
  String name,
  Uint8List bytes, {
  int? width,
  int? height,
}) {
  final stripped = stripImageMetadata(bytes);
  if (stripped == null) {
    return WorkPreparedPhoto(
      name: name,
      bytes: bytes,
      width: width,
      height: height,
      error: WorkAttachmentRules.metadataMessage,
    );
  }
  return WorkPreparedPhoto(
    name: name,
    bytes: stripped,
    width: width,
    height: height,
  );
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
