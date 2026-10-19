// Fotoğrafın yüklemeden önce hazırlanması (lib/services/work_photo_prepare.dart):
// - R2-3: uzun kenar en çok 2560 piksel, JPEG kalite 85, EXIF (GPS konumu) silinir, EXIF yönü uygulanır, bellek bombası
//   koruması çözmeden önce; seçim kaydı adı `.jpg`, türü `image/jpeg`;
// - R3-1: web'de motor ölçeri (ImageDescriptor) çalışmaz: bayt düzeyinde başlık okuyucu ([readImageHeaderSize]) devreye
//   girer, fotoğraf yine küçültülür ve GPS silinir; yeniden kodlanamayan JPEG / PNG / WebP'nin üstverisi ayıklanır,
//   ayıklanamazsa fotoğraf yüklenmez (gizlilik için kapalı).
import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_photo_prepare.dart';

import 'screens/work_fixtures.dart';

/// JPEG bölüm işaretleri (SOS'a dek): APP1 = 0xE1 (EXIF), APP2 = 0xE2 (ICC), APP13 = 0xED (IPTC), COM = 0xFE.
List<int> _segments(Uint8List jpeg) {
  final markers = <int>[];
  var i = 2;
  while (i + 3 < jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    if (marker == 0xDA) break;
    markers.add(marker);
    i += 2 + ((jpeg[i + 2] << 8) | jpeg[i + 3]);
  }
  return markers;
}

/// SOS işaretinden itibaren (tarama başlığı + veri + EOI).
Uint8List _fromSos(Uint8List jpeg) {
  var i = 2;
  while (i + 3 < jpeg.length && jpeg[i] == 0xFF) {
    if (jpeg[i + 1] == 0xDA) return Uint8List.sublistView(jpeg, i);
    i += 2 + ((jpeg[i + 2] << 8) | jpeg[i + 3]);
  }
  throw StateError('SOS yok');
}

bool _contains(Uint8List bytes, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

bool _hasExifSignature(Uint8List bytes) => _contains(bytes, const <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);

/// JPEG bölütü: FF [marker] uzunluk (2) + yük.
List<int> _segment(int marker, List<int> payload) =>
    <int>[0xFF, marker, (payload.length + 2) >> 8, (payload.length + 2) & 0xFF, ...payload];

/// [jpeg]'in SOI'sinden hemen sonra bölütler ekler.
Uint8List _afterSoi(Uint8List jpeg, List<List<int>> segments) => Uint8List.fromList(<int>[
  0xFF, 0xD8,
  for (final s in segments) ...s,
  ...jpeg.sublist(2),
]);

/// [marker] bölütlerini (SOS'tan önce) çıkarır.
Uint8List _withoutMarker(Uint8List jpeg, int marker) {
  final out = <int>[0xFF, 0xD8];
  var p = 2;
  while (p + 4 <= jpeg.length) {
    final m = jpeg[p + 1];
    final length = (jpeg[p + 2] << 8) | jpeg[p + 3];
    if (m == 0xDA) {
      out.addAll(jpeg.sublist(p));
      break;
    }
    if (m != marker) out.addAll(jpeg.sublist(p, p + 2 + length));
    p += 2 + length;
  }
  return Uint8List.fromList(out);
}

/// SOF0 genişliğini değiştirir (çözülemeyen ama başlığı okunan "dev" görsel).
Uint8List _patchSofWidth(Uint8List jpeg, int width) {
  final out = Uint8List.fromList(jpeg);
  var p = 2;
  while (p + 4 <= out.length) {
    final m = out[p + 1];
    if (m == 0xC0) {
      out[p + 7] = width >> 8;
      out[p + 8] = width & 0xFF;
      return out;
    }
    p += 2 + ((out[p + 2] << 8) | out[p + 3]);
  }
  throw StateError('SOF0 yok');
}

/// GPS konumlu, cihaz bilgili küçük JPEG (APP0 JFIF + APP1 EXIF).
Uint8List _gpsJpeg({int width = 64, int height = 32}) {
  final photo = _halves(width, height);
  photo.exif.gpsIfd.setGpsLocation(latitude: 41.0082, longitude: 28.9784);
  photo.exif.imageIfd.make = 'Deneme';
  photo.exif.imageIfd.model = 'Kamera 1';
  return img.encodeJpg(photo, quality: 90);
}

/// Sol yarısı kırmızı, sağ yarısı mavi görsel.
img.Image _halves(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x < width ~/ 2) {
        image.setPixelRgb(x, y, 255, 0, 0);
      } else {
        image.setPixelRgb(x, y, 0, 0, 255);
      }
    }
  }
  return image;
}

bool _reddish(img.Pixel p) => p.r > 180 && p.g < 90 && p.b < 90;
bool _bluish(img.Pixel p) => p.b > 180 && p.r < 90 && p.g < 90;

/// Telefon fotoğrafı benzeri büyük JPEG (4032 x 3024, 5 MB üstü): yumuşak geçiş + gürültü (sıkışmasın diye), kalite
/// 100, GPS konumlu EXIF. Bir kez üretilir.
final Uint8List _bigPhoto = _bigNoisyJpeg(4032, 3024);

Uint8List _bigNoisyJpeg(int width, int height) {
  final random = math.Random(7);
  final rgb = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 3;
      final n = random.nextInt(97) - 48;
      rgb[o] = ((x * 255) ~/ width + n).clamp(0, 255);
      rgb[o + 1] = ((y * 255) ~/ height + n).clamp(0, 255);
      rgb[o + 2] = (128 + n).clamp(0, 255);
    }
  }
  final image = img.Image.fromBytes(width: width, height: height, bytes: rgb.buffer, numChannels: 3);
  image.exif.gpsIfd.setGpsLocation(latitude: 41.0082, longitude: 28.9784);
  return img.encodeJpg(image, quality: 100);
}

/// Web'deki motor ölçerini taklit eder: `ImageDescriptor` boyutu okunamaz.
Future<({int width, int height})?> _noEngineProbe(Uint8List _) async => null;

// --- PNG / WebP yardımcıları ---

List<int> _u32be(int v) => <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _u32le(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> _pngChunk(String type, List<int> data) {
  final typed = <int>[...type.codeUnits, ...data];
  return <int>[..._u32be(data.length), ...typed, ..._u32be(getCrc32(typed))];
}

List<String> _pngChunkTypes(Uint8List png) {
  final types = <String>[];
  var p = 8;
  while (p + 12 <= png.length) {
    final length = (png[p] << 24) | (png[p + 1] << 16) | (png[p + 2] << 8) | png[p + 3];
    types.add(String.fromCharCodes(png.sublist(p + 4, p + 8)));
    p += 12 + length;
  }
  return types;
}

/// IHDR'den hemen sonra öbekler ekler; dosya sonuna [trailer] eklenir.
Uint8List _pngWith(Uint8List png, List<List<int>> chunks, {List<int> trailer = const <int>[]}) {
  const afterIhdr = 8 + 12 + 13;
  return Uint8List.fromList(<int>[
    ...png.sublist(0, afterIhdr),
    for (final c in chunks) ...c,
    ...png.sublist(afterIhdr),
    ...trailer,
  ]);
}

List<int> _webpChunk(String fourcc, List<int> payload) =>
    <int>[...fourcc.codeUnits, ..._u32le(payload.length), ...payload, if (payload.length.isOdd) 0];

Uint8List _riff(List<List<int>> chunks, {List<int> trailer = const <int>[]}) {
  final body = <int>[...'WEBP'.codeUnits, for (final c in chunks) ...c];
  return Uint8List.fromList(<int>[...'RIFF'.codeUnits, ..._u32le(body.length), ...body, ...trailer]);
}

List<String> _webpChunkTypes(Uint8List webp) {
  final types = <String>[];
  var p = 12;
  while (p + 8 <= webp.length) {
    types.add(String.fromCharCodes(webp.sublist(p, p + 4)));
    final size = webp[p + 4] | (webp[p + 5] << 8) | (webp[p + 6] << 16) | (webp[p + 7] << 24);
    p += 8 + size + (size & 1);
  }
  return types;
}

/// 1x1 kayıpsız WebP (VP8L): gerçek kod çözücüler açar.
final Uint8List _webp1x1 = base64Decode('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==');

/// [_webp1x1]'in VP8L öbeği (başlık + yük + doldurma).
List<int> get _vp8lChunk => _webp1x1.sublist(12);

void main() {
  group('workJpegName', () {
    test('uzantı .jpg olur; yol parçası atılır; boş / yalnız uzantı "fotograf.jpg"', () {
      expect(workJpegName('IMG_1.HEIC'), 'IMG_1.jpg');
      expect(workJpegName('ekran.png'), 'ekran.jpg');
      expect(workJpegName('foto.jpeg'), 'foto.jpg');
      expect(workJpegName('uzantisiz'), 'uzantisiz.jpg');
      expect(workJpegName('a/b\\kat.webp'), 'kat.jpg');
      expect(workJpegName('nokta.li.ad.png'), 'nokta.li.ad.jpg');
      expect(workJpegName(''), 'fotograf.jpg');
      expect(workJpegName('.png'), 'fotograf.jpg');
    });
  });

  group('bellek bombası koruması (çözmeden önce)', () {
    test('yerelde JPEG 64 milyon piksele dek (48 MP fotoğraf ölçekli çözülür); web\'de ve diğer türlerde sunucu sınırı',
        () {
      // 48 MP (8064 x 6048 = 48,8 milyon piksel) iOS / Android fotoğrafı.
      expect(workPhotoDecodeAllowed(8064, 6048, jpeg: true, web: false), isTrue);
      expect(workPhotoDecodeAllowed(8064, 6048, jpeg: true, web: true), isFalse, reason: 'web ölçekli çözmez');
      expect(workPhotoDecodeAllowed(8064, 6048, jpeg: false, web: false), isFalse, reason: 'PNG / WebP: 40 milyon');
      expect(workPhotoDecodeAllowed(9000, 8000, jpeg: true, web: false), isFalse, reason: '72 milyon > 64 milyon');
      expect(workPhotoDecodeAllowed(8000, 5000, jpeg: false, web: false), isTrue, reason: 'tam 40 milyon');
      expect(workPhotoDecodeAllowed(12001, 10, jpeg: false, web: true), isFalse, reason: 'kenar 12.000');
      expect(workPhotoDecodeAllowed(0, 10, jpeg: true, web: false), isFalse);
    });

    test('sınırı aşan PNG başlığı ÇÖZÜLMEZ: özgün içerik ve boyut döner; doğrulama çözünürlük iletisini verir', () async {
      final header = wkPngHeader(width: 10000, height: 5000);
      final out = await prepareWorkPhoto('dev.png', header);
      expect(out.prepared, isFalse);
      expect(out.error, isNull);
      expect(out.bytes, header, reason: 'üstverisiz PNG ayıklamada değişmez');
      expect(out.name, 'dev.png');
      expect((out.width, out.height), (10000, 5000));
      final pick = await prepareWorkPhotoPick('dev.png', header);
      expect(pick.validationError, WorkAttachmentRules.dimensionsMessage);
    });
  });

  group('readImageHeaderSize (bellek ayırmayan başlık okuyucu)', () {
    test('gerçek JPEG / PNG / WebP: motor ölçeriyle aynı sonuç', () async {
      final jpeg = _gpsJpeg(width: 320, height: 240);
      final png = img.encodePng(img.Image(width: 33, height: 17));
      for (final bytes in <Uint8List>[jpeg, png, _webp1x1, kWkPng]) {
        final fromEngine = await probeImageSizeWithDescriptor(bytes);
        expect(fromEngine, isNotNull);
        expect(readImageHeaderSize(bytes), fromEngine);
      }
      expect(readImageHeaderSize(jpeg), (width: 320, height: 240));
      expect(readImageHeaderSize(wkPngHeader(width: 10000, height: 5000)), (width: 10000, height: 5000));
    });

    test('WebP: VP8 (14 bit, ölçek bitleri atılır), VP8L (değer + 1), VP8X (24 bit, değer + 1)', () {
      final vp8 = Uint8List.fromList(<int>[
        ...'RIFF'.codeUnits, ..._u32le(22), ...'WEBP'.codeUnits, ...'VP8 '.codeUnits, ..._u32le(10),
        0x10, 0x02, 0x00, // kare etiketi
        0x9D, 0x01, 0x2A, // başlangıç kodu
        640 & 0xFF, (640 >> 8) | 0xC0, // genişlik + ölçek bitleri
        480 & 0xFF, 480 >> 8,
      ]);
      expect(readImageHeaderSize(vp8), (width: 640, height: 480));
      final bits = (4000 - 1) | ((3000 - 1) << 14) | (1 << 28);
      final vp8l = Uint8List.fromList(<int>[
        ...'RIFF'.codeUnits, ..._u32le(22), ...'WEBP'.codeUnits, ...'VP8L'.codeUnits, ..._u32le(10),
        0x2F, ..._u32le(bits), 0, 0, 0, 0, 0,
      ]);
      expect(readImageHeaderSize(vp8l), (width: 4000, height: 3000));
      final vp8x = Uint8List.fromList(<int>[
        ...'RIFF'.codeUnits, ..._u32le(22), ...'WEBP'.codeUnits, ...'VP8X'.codeUnits, ..._u32le(10),
        0x0C, 0, 0, 0, // bayraklar
        (16384 - 1) & 0xFF, ((16384 - 1) >> 8) & 0xFF, 0, // genişlik - 1
        (9000 - 1) & 0xFF, ((9000 - 1) >> 8) & 0xFF, 0, // yükseklik - 1
      ]);
      expect(readImageHeaderSize(vp8x), (width: 16384, height: 9000));
      final badStart = Uint8List.fromList(vp8)..[23] = 0;
      expect(readImageHeaderSize(badStart), isNull, reason: 'VP8 başlangıç kodu yok');
      final badLossless = Uint8List.fromList(vp8l)..[20] = 0;
      expect(readImageHeaderSize(badLossless), isNull, reason: 'VP8L imzası yok');
      expect(readImageHeaderSize(Uint8List.sublistView(vp8, 0, 29)), isNull, reason: 'kısa');
    });

    test('JPEG: DHT (C4) SOF sayılmaz, SOF2 okunur; dolgu baytı; SOF öncesi SOS / EOI / ikinci SOI, kısa ya da sıfır boyut '
        'bozuk', () {
      final sof2 = <int>[0xFF, 0xC2, 0, 11, 8, 1000 >> 8, 1000 & 0xFF, 1500 >> 8, 1500 & 0xFF, 1, 1, 0x11, 0];
      final progressive = Uint8List.fromList(<int>[
        0xFF, 0xD8,
        ..._segment(0xE1, 'Exif\u0000\u0000xyz'.codeUnits),
        ..._segment(0xC4, const <int>[0x00, 1, 2, 3]),
        0xFF, // dolgu
        ...sof2,
      ]);
      expect(readImageHeaderSize(progressive), (width: 1500, height: 1000));
      List<int> soi(List<int> rest) => <int>[0xFF, 0xD8, ...rest];
      expect(readImageHeaderSize(Uint8List.fromList(soi(<int>[..._segment(0xDA, const <int>[1, 2]), ...sof2]))), isNull);
      expect(readImageHeaderSize(Uint8List.fromList(soi(<int>[0xFF, 0xD9, ...sof2]))), isNull);
      expect(readImageHeaderSize(Uint8List.fromList(soi(<int>[0xFF, 0xD8, ...sof2]))), isNull);
      expect(readImageHeaderSize(Uint8List.fromList(soi(<int>[0xFF, 0xE1, 0x00, 0x01, ...sof2]))), isNull, reason: 'boy < 2');
      expect(readImageHeaderSize(Uint8List.fromList(soi(<int>[0xFF, 0xC0, 0, 11, 8, 0, 0, 0, 10]))), isNull, reason: '0');
      expect(readImageHeaderSize(Uint8List.fromList(soi(sof2.sublist(0, 7)))), isNull, reason: 'kısa SOF');
      expect(readImageHeaderSize(Uint8List.fromList(soi(<int>[0x00, ...sof2]))), isNull, reason: 'işaret değil');
      expect(readImageHeaderSize(wkImageBytes('a.gif')), isNull);
      expect(readImageHeaderSize(Uint8List(0)), isNull);
    });

    test('motor ölçeri null dönerse (web) probeImageSize başlık okuyucuya düşer', () async {
      final jpeg = _gpsJpeg(width: 300, height: 200);
      expect(await probeImageSize(jpeg, descriptorProbe: _noEngineProbe), (width: 300, height: 200));
      expect(await probeImageSize(_webp1x1, descriptorProbe: _noEngineProbe), (width: 1, height: 1));
      expect(await probeImageSize(wkImageBytes('a.gif'), descriptorProbe: _noEngineProbe), isNull);
    });
  });

  group('stripImageMetadata (yeniden kodlamadan üstveri ayıklama)', () {
    test('JPEG: APP1 (EXIF / GPS), APP2, APP13 (IPTC), COM ve EOI sonrası kuyruk atılır; JFIF APP0 ve Adobe APP14 kalır; '
        'tarama verisi aynen', () {
      final base = _gpsJpeg();
      expect(_segments(base), containsAllInOrder(<int>[0xE0, 0xE1]), reason: 'kaynakta JFIF + EXIF');
      final adobe = _segment(0xEE, <int>[...'Adobe'.codeUnits, 0, 100, 0, 0, 0, 0, 1]);
      final source = Uint8List.fromList(<int>[
        ..._afterSoi(base, <List<int>>[
          _segment(0xE2, <int>[...'ICC_PROFILE'.codeUnits, 0, 1, 1, 9, 9]),
          _segment(0xED, <int>[...'Photoshop 3.0'.codeUnits, 0, 1, 2]),
          _segment(0xFE, 'Konum: Kadıköy'.codeUnits.map((c) => c & 0xFF).toList()),
          adobe,
        ]),
        ...'HAREKETLI_FOTOGRAF_VIDEOSU'.codeUnits, // EOI sonrası kuyruk
      ]);
      final out = stripJpegMetadata(source)!;
      final markers = _segments(out);
      expect(markers, isNot(contains(0xE1)));
      expect(markers, isNot(contains(0xE2)));
      expect(markers, isNot(contains(0xED)));
      expect(markers, isNot(contains(0xFE)));
      expect(markers, containsAll(<int>[0xE0, 0xEE, 0xDB, 0xC0, 0xC4]));
      expect(_hasExifSignature(out), isFalse);
      expect(_contains(out, 'Photoshop'.codeUnits), isFalse);
      expect(_contains(out, 'HAREKETLI'.codeUnits), isFalse, reason: 'kuyruk kesildi');
      expect(out.sublist(out.length - 2), <int>[0xFF, 0xD9]);
      expect(_fromSos(out), _fromSos(base), reason: 'tarama verisi yeniden kodlanmadı');
      final a = img.decodeJpg(base)!;
      final b = img.decodeJpg(out)!;
      expect((b.width, b.height), (a.width, a.height));
      expect(b.getPixel(5, 5), a.getPixel(5, 5));
      expect(b.getPixel(60, 30), a.getPixel(60, 30));
      expect(img.decodeJpgExif(out)?.gpsIfd.gpsLatitude, isNull);
    });

    test('JPEG: taramalar arasındaki / EOI öncesi COM ve APP1 de atılır; RST ve FF 00 tarama verisidir', () {
      final crafted = Uint8List.fromList(<int>[
        0xFF, 0xD8,
        ..._segment(0xC0, <int>[8, 0, 8, 0, 8, 1, 1, 0x11, 0]),
        ..._segment(0xDA, <int>[1, 1, 0, 0, 63, 0]),
        0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD3, 0x56, // veri (doldurulmuş FF, RST3)
        ..._segment(0xFE, 'gizli'.codeUnits),
        ..._segment(0xE1, 'Exif\u0000\u0000gps'.codeUnits),
        ..._segment(0xC4, <int>[0x10, 1, 2]),
        ..._segment(0xDA, <int>[1, 1, 0, 0, 63, 0]),
        0x78, 0x9A,
        0xFF, 0xD9,
      ]);
      final out = stripJpegMetadata(crafted)!;
      expect(_contains(out, 'gizli'.codeUnits), isFalse);
      expect(_hasExifSignature(out), isFalse);
      expect(_contains(out, const <int>[0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD3, 0x56]), isTrue);
      expect(_contains(out, const <int>[0xFF, 0xC4, 0, 5, 0x10, 1, 2]), isTrue, reason: 'DHT korunur');
      expect(out.sublist(out.length - 4), <int>[0x78, 0x9A, 0xFF, 0xD9]);
    });

    test('JPEG yapısı bozuksa null: SOS yok, SOS öncesi EOI / ikinci SOI, bölüt boyu taşar, işaret yerinde değil', () {
      final base = _gpsJpeg();
      final cut = Uint8List.sublistView(base, 0, 2 + 4 + 10); // APP0 içinde biter
      expect(stripJpegMetadata(cut), isNull);
      expect(stripJpegMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9])), isNull);
      expect(stripJpegMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD8, 0xFF, 0xD9])), isNull);
      expect(stripJpegMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE1, 0x40, 0x00, 1, 2])), isNull);
      expect(stripJpegMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, 0x00, 0xFF, 0xD9])), isNull);
      expect(stripJpegMetadata(wkImageBytes('bozuk.jpg')), isNull);
    });

    test('PNG: eXIf / tEXt / zTXt / iTXt / tIME öbekleri ve IEND sonrası atılır; görsel aynı; bozuksa null', () {
      final base = img.encodePng(_halves(20, 10));
      final source = _pngWith(base, <List<int>>[
        _pngChunk('eXIf', <int>[0x4D, 0x4D, 0, 42, 1, 2, 3]),
        _pngChunk('tEXt', <int>[...'Location'.codeUnits, 0, ...'41.0,29.0'.codeUnits]),
        _pngChunk('zTXt', <int>[...'Comment'.codeUnits, 0, 0, 1, 2]),
        _pngChunk('iTXt', <int>[...'XML:com.adobe.xmp'.codeUnits, 0, 0, 0, 0, 0, ...'<x/>'.codeUnits]),
        _pngChunk('tIME', <int>[0x07, 0xEA, 10, 19, 12, 0, 0]),
      ], trailer: 'EKLENMIS'.codeUnits);
      expect(_pngChunkTypes(source), containsAll(<String>['eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME']));
      final out = stripImageMetadata(source)!;
      expect(_pngChunkTypes(out), _pngChunkTypes(base));
      expect(out, base, reason: 'üstveri öbekleri ve kuyruk gitti; gerisi aynen');
      expect(img.decodePng(out)!.getPixel(2, 5), img.decodePng(base)!.getPixel(2, 5));
      expect(stripImageMetadata(Uint8List.sublistView(source, 0, source.length - 30)), isNull, reason: 'IEND yok');
    });

    test('WebP: EXIF ve XMP öbekleri atılır, VP8X bayrakları temizlenir, RIFF boyu yeniden yazılır; görsel açılır', () async {
      final vp8x = _webpChunk('VP8X', <int>[0x0C, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final source = _riff(<List<int>>[
        vp8x,
        _vp8lChunk,
        _webpChunk('EXIF', <int>[...'MM'.codeUnits, 0, 42, ...'GPS'.codeUnits]),
        _webpChunk('XMP ', '<x:xmpmeta/>'.codeUnits),
      ], trailer: 'KUYRUK'.codeUnits);
      expect(_webpChunkTypes(source), containsAll(<String>['VP8X', 'VP8L', 'EXIF', 'XMP ']));
      final out = stripImageMetadata(source)!;
      expect(_webpChunkTypes(out), <String>['VP8X', 'VP8L']);
      expect(out[20] & 0x0C, 0, reason: 'EXIF / XMP bayrakları silindi');
      final riffSize = out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] << 24);
      expect(riffSize, out.length - 8);
      expect(_contains(out, 'GPS'.codeUnits), isFalse);
      expect(_contains(out, 'KUYRUK'.codeUnits), isFalse);
      expect(await probeImageSizeWithDescriptor(out), (width: 1, height: 1));
      expect(stripImageMetadata(Uint8List.sublistView(source, 0, 20)), isNull, reason: 'RIFF dosyayı aşıyor');
    });

    test('tanınmayan içerik olduğu gibi döner (doğrulama reddeder)', () {
      final gif = wkImageBytes('a.gif');
      expect(identical(stripImageMetadata(gif), gif), isTrue);
    });
  });

  group('hazırlama', () {
    test('büyük fotoğraf (4032x3024, 5 MB üstü) -> uzun kenar 2560, oran korunur, JPEG, 5 MB altı; seçim geçerli',
        () async {
      final source = _bigPhoto;
      expect(source.length, greaterThan(kWorkAttachmentMaxBytes), reason: 'özgün fotoğraf sınırı aşıyor');
      expect(WorkPhotoPick(name: 'IMG_0001.JPG', bytes: source).isValid, isFalse, reason: 'hazırlanmadan reddedilirdi');

      final out = await prepareWorkPhoto('IMG_0001.JPG', source);
      expect(out.prepared, isTrue);
      expect(out.name, 'IMG_0001.jpg');
      expect((out.width, out.height), (2560, 1920));
      expect(out.bytes.length, lessThan(kWorkAttachmentMaxBytes));
      expect(WorkAttachmentRules.sniffMimeType(out.bytes), 'image/jpeg');
      final decoded = img.decodeJpg(out.bytes)!;
      expect((decoded.width, decoded.height), (2560, 1920));

      final pick = await prepareWorkPhotoPick('IMG_0001.JPG', source);
      expect(pick.isValid, isTrue);
      expect(pick.mimeType, 'image/jpeg');
      expect(pick.name, 'IMG_0001.jpg');
      expect(pick.size, lessThan(kWorkAttachmentMaxBytes));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('dikey büyük fotoğraf: uzun kenar (yükseklik) 2560', () async {
      final source = img.encodeJpg(img.Image(width: 1500, height: 3000), quality: 80);
      final out = await prepareWorkPhoto('dikey.jpg', source);
      expect(out.prepared, isTrue);
      expect((out.width, out.height), (1280, 2560));
    });

    test('küçük PNG (saydam) -> aynı boyutta JPEG; saydam alan beyaz; ad .jpg, tür image/jpeg', () async {
      final png = img.Image(width: 64, height: 48, numChannels: 4);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 64; x++) {
          if (x < 32) {
            png.setPixelRgba(x, y, 255, 0, 0, 255);
          } else {
            png.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }
      }
      final source = img.encodePng(png);
      final out = await prepareWorkPhoto('ekran goruntusu.png', source);
      expect(out.prepared, isTrue);
      expect(out.name, 'ekran goruntusu.jpg');
      expect((out.width, out.height), (64, 48), reason: 'küçük görsel büyütülmez');
      expect(WorkAttachmentRules.sniffMimeType(out.bytes), 'image/jpeg');
      final decoded = img.decodeJpg(out.bytes)!;
      expect(_reddish(decoded.getPixel(8, 24)), isTrue);
      final white = decoded.getPixel(56, 24);
      expect(white.r > 240 && white.g > 240 && white.b > 240, isTrue, reason: 'saydam alan siyah değil beyaz');

      final pick = await prepareWorkPhotoPick('ekran goruntusu.png', source);
      expect(pick.mimeType, 'image/jpeg');
      expect(pick.isValid, isTrue);
    });

    test('EXIF silinir: GPS konumlu fotoğrafın çıktısında APP1 / "Exif" yok, konum okunamaz', () async {
      final source = _gpsJpeg(width: 320, height: 240);
      // Sağlama: özgün dosyada konum VAR.
      expect(_segments(source), contains(0xE1));
      expect(img.decodeJpgExif(source)!.gpsIfd.gpsLatitude, closeTo(41.0082, 0.001));

      final out = await prepareWorkPhoto('konum.jpg', source);
      expect(out.prepared, isTrue);
      expect(_segments(out.bytes), isNot(contains(0xE1)), reason: 'APP1 (EXIF) bölümü yok');
      expect(_hasExifSignature(out.bytes), isFalse);
      final exif = img.decodeJpgExif(out.bytes);
      expect(exif == null || exif.isEmpty, isTrue);
      expect(exif?.gpsIfd.gpsLatitude, isNull);
    });

    test('EXIF yönü (6: 90 derece saat yönü) uygulanır: çıktı dik, yön etiketi yok', () async {
      // Saklanan görsel 64x32: sol kırmızı, sağ mavi. Yön 6 ile gösterim 32x64: üst kırmızı, alt mavi.
      final stored = _halves(64, 32);
      stored.exif.imageIfd.orientation = 6;
      final source = img.encodeJpg(stored, quality: 95);
      expect(img.decodeJpgExif(source)!.imageIfd.orientation, 6);

      final out = await prepareWorkPhoto('yan.jpg', source);
      expect(out.prepared, isTrue);
      expect((out.width, out.height), (32, 64));
      expect(_segments(out.bytes), isNot(contains(0xE1)), reason: 'yön etiketi (EXIF) yazılmaz');
      final decoded = img.decodeJpg(out.bytes)!;
      expect((decoded.width, decoded.height), (32, 64));
      expect(_reddish(decoded.getPixel(16, 6)), isTrue, reason: 'üst kırmızı');
      expect(_bluish(decoded.getPixel(16, 57)), isTrue, reason: 'alt mavi');
      // Motor yönü uyguluyor mu (bilgi): uygulamıyorsa yukarıdaki sonuç package:image döndürmesiyle elde edilir.
      expect(await debugPlatformAppliesExifOrientation(), isA<bool>());
    });

    test('yedek yol: motor yönü uygulamazsa kodlayıcı döndürür (6 ve 8)', () {
      Uint8List rgba(img.Image image) {
        final out = Uint8List(image.width * image.height * 4);
        var o = 0;
        for (final p in image) {
          out[o++] = p.r.toInt();
          out[o++] = p.g.toInt();
          out[o++] = p.b.toInt();
          out[o++] = 255;
        }
        return out;
      }

      final stored = _halves(64, 32);
      final six = img.decodeJpg(encodeWorkJpeg(WorkJpegJob(rgba: rgba(stored), width: 64, height: 32, orientation: 6)))!;
      expect((six.width, six.height), (32, 64));
      expect(_reddish(six.getPixel(16, 6)), isTrue);
      expect(_bluish(six.getPixel(16, 57)), isTrue);
      final eight = img.decodeJpg(encodeWorkJpeg(WorkJpegJob(rgba: rgba(stored), width: 64, height: 32, orientation: 8)))!;
      expect((eight.width, eight.height), (32, 64));
      expect(_bluish(eight.getPixel(16, 6)), isTrue, reason: 'yön 8: sağ kenar üste');
      expect(_reddish(eight.getPixel(16, 57)), isTrue);
      final plain = encodeWorkJpeg(WorkJpegJob(rgba: rgba(stored), width: 64, height: 32));
      expect(_segments(plain), isNot(contains(0xE1)));
    });

    test('web yolu (isolate yok, parçalı): aynı sonuç', () async {
      final source = img.encodePng(_halves(3000, 100));
      final out = await prepareWorkPhoto('genis.png', source, web: true);
      expect(out.prepared, isTrue);
      expect(out.name, 'genis.jpg');
      expect(out.width, 2560);
      expect(WorkAttachmentRules.sniffMimeType(out.bytes), 'image/jpeg');
      final decoded = img.decodeJpg(out.bytes)!;
      expect(decoded.width, 2560);
      expect(_reddish(decoded.getPixel(100, decoded.height ~/ 2)), isTrue);
      expect(_bluish(decoded.getPixel(2400, decoded.height ~/ 2)), isTrue);
    });

    test('hazırlanamazsa: bozuk JPEG ayıklanamaz -> YÜKLENMEZ; tanınmayan içerik ve boş içerik doğrulamaya kalır',
        () async {
      final broken = wkImageBytes('bozuk.jpg', size: 4096);
      final out = await prepareWorkPhoto('bozuk.jpg', broken);
      expect(out.prepared, isFalse);
      expect(out.error, WorkAttachmentRules.metadataMessage);
      expect(out.name, 'bozuk.jpg');
      final brokenPick = await prepareWorkPhotoPick('bozuk.jpg', broken);
      expect(brokenPick.validationError, WorkAttachmentRules.metadataMessage);

      final gif = wkImageBytes('a.gif');
      final pick = await prepareWorkPhotoPick('a.gif', gif);
      expect(pick.name, 'a.gif');
      expect(pick.validationError, WorkAttachmentRules.typeAndSizeMessage);

      final empty = await prepareWorkPhoto('bos.jpg', Uint8List(0));
      expect(empty.prepared, isFalse);
      expect(empty.bytes, isEmpty);
    });
  });

  group('web: motor ölçeri yok (ImageDescriptor boyutu okunamaz) — başlık okuyucu devrede', () {
    test('büyük GPS konumlu fotoğraf küçültülür (2560), 5 MB altı JPEG, GPS / EXIF yok', () async {
      final source = _bigPhoto;
      expect(source.length, greaterThan(kWorkAttachmentMaxBytes));
      expect(img.decodeJpgExif(source)!.gpsIfd.gpsLatitude, closeTo(41.0082, 0.001), reason: 'kaynakta konum VAR');

      final out = await prepareWorkPhoto('IMG_0002.JPG', source, web: true, descriptorProbe: _noEngineProbe);
      expect(out.prepared, isTrue);
      expect(out.name, 'IMG_0002.jpg');
      expect((out.width, out.height), (2560, 1920));
      expect(out.bytes.length, lessThan(kWorkAttachmentMaxBytes));
      expect(_segments(out.bytes), isNot(contains(0xE1)));
      expect(_hasExifSignature(out.bytes), isFalse);
      expect(img.decodeJpgExif(out.bytes)?.gpsIfd.gpsLatitude, isNull);

      final pick = await prepareWorkPhotoPick(
        'IMG_0002.JPG',
        source,
        web: true,
        descriptorProbe: _noEngineProbe,
      );
      expect(pick.isValid, isTrue);
      expect(pick.mimeType, 'image/jpeg');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('küçük GPS konumlu JPEG ve PNG de yeniden kodlanır', () async {
      final jpeg = await prepareWorkPhoto('k.jpg', _gpsJpeg(), web: true, descriptorProbe: _noEngineProbe);
      expect(jpeg.prepared, isTrue);
      expect((jpeg.width, jpeg.height), (64, 32));
      expect(_segments(jpeg.bytes), isNot(contains(0xE1)));
      final png = await prepareWorkPhoto('e.png', img.encodePng(_halves(40, 20)), web: true, descriptorProbe: _noEngineProbe);
      expect(png.prepared, isTrue);
      expect(png.name, 'e.jpg');
    });

    test('yeniden kodlanamayan JPEG (çözme hatası): APP1 / GPS ve kuyruk atılır, piksel verisi aynen; seçim geçerli',
        () async {
      // DQT'siz JPEG: başlık okunur ama motor çözemez.
      final source = Uint8List.fromList(<int>[
        ..._afterSoi(_withoutMarker(_gpsJpeg(), 0xDB), <List<int>>[_segment(0xFE, 'not'.codeUnits)]),
        ...'KUYRUK'.codeUnits,
      ]);
      expect(_segments(source), contains(0xE1));
      final out = await prepareWorkPhoto('cozulmez.jpg', source, web: true, descriptorProbe: _noEngineProbe);
      expect(out.prepared, isFalse, reason: 'çözülemedi: yeniden kodlanmadı');
      expect(out.error, isNull);
      expect(out.name, 'cozulmez.jpg');
      expect((out.width, out.height), (64, 32));
      expect(_segments(out.bytes), isNot(contains(0xE1)));
      expect(_segments(out.bytes), isNot(contains(0xFE)));
      expect(_hasExifSignature(out.bytes), isFalse);
      expect(_contains(out.bytes, 'KUYRUK'.codeUnits), isFalse);
      expect(_fromSos(out.bytes), _fromSos(_withoutMarker(_gpsJpeg(), 0xDB)));

      final pick = await prepareWorkPhotoPick('cozulmez.jpg', source, web: true, descriptorProbe: _noEngineProbe);
      expect(pick.isValid, isTrue, reason: 'ayıklanmış baytlar yüklenebilir');
      expect(_segments(pick.bytes), isNot(contains(0xE1)));
    });

    test('web koruması (kenar 12.000) çözmeyi engeller: APP1 yine atılır, doğrulama çözünürlük iletisini verir', () async {
      final source = _patchSofWidth(_gpsJpeg(), 13000);
      expect(readImageHeaderSize(source), (width: 13000, height: 32));
      final out = await prepareWorkPhoto('genis.jpg', source, web: true, descriptorProbe: _noEngineProbe);
      expect(out.prepared, isFalse);
      expect((out.width, out.height), (13000, 32));
      expect(_segments(out.bytes), isNot(contains(0xE1)));
      expect(_hasExifSignature(out.bytes), isFalse);
      final pick = await prepareWorkPhotoPick('genis.jpg', source, web: true, descriptorProbe: _noEngineProbe);
      expect(pick.validationError, WorkAttachmentRules.dimensionsMessage);
    });

    test('ayıklanamayan JPEG (APP1 sonrası kesik) YÜKLENMEZ: gizlilik için kapalı', () async {
      final full = _gpsJpeg();
      // SOI + APP0 + APP1 ile biter (SOF / SOS yok).
      var end = 2;
      for (var i = 0; i < 2; i++) {
        end += 2 + ((full[end + 2] << 8) | full[end + 3]);
      }
      final cut = Uint8List.fromList(full.sublist(0, end));
      expect(_segments(cut), <int>[0xE0, 0xE1]);
      final out = await prepareWorkPhoto('kesik.jpg', cut, web: true, descriptorProbe: _noEngineProbe);
      expect(out.prepared, isFalse);
      expect(out.error, WorkAttachmentRules.metadataMessage);
      final pick = await prepareWorkPhotoPick('kesik.jpg', cut, web: true, descriptorProbe: _noEngineProbe);
      expect(pick.isValid, isFalse);
      expect(pick.validationError, WorkAttachmentRules.metadataMessage);
    });
  });
}
