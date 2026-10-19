// Fotoğrafın yüklemeden önce hazırlanması (lib/services/work_photo_prepare.dart, R2-3): uzun kenar en çok 2560 piksel,
// JPEG kalite 85, EXIF (GPS konumu) silinir, EXIF yönü uygulanır, bellek bombası koruması çözmeden önce, hazırlanamazsa
// özgün baytlar; seçim kaydı adı `.jpg`, türü `image/jpeg`.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/services/work_photo_prepare.dart';

import 'screens/work_fixtures.dart';

/// JPEG bölüm işaretleri (SOS'a dek): APP1 = 0xE1 (EXIF), APP2 = 0xE2 (ICC).
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

bool _hasExifSignature(Uint8List bytes) {
  const signature = <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
  outer:
  for (var i = 0; i + signature.length <= bytes.length; i++) {
    for (var j = 0; j < signature.length; j++) {
      if (bytes[i + j] != signature[j]) continue outer;
    }
    return true;
  }
  return false;
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

/// Telefon fotoğrafı benzeri büyük JPEG: yumuşak geçiş + gürültü (sıkışmasın diye), kalite 100.
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
  return img.encodeJpg(image, quality: 100);
}

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

    test('sınırı aşan PNG başlığı ÇÖZÜLMEZ: özgün baytlar ve boyut döner; doğrulama çözünürlük iletisini verir', () async {
      final header = wkPngHeader(width: 10000, height: 5000);
      final out = await prepareWorkPhoto('dev.png', header);
      expect(out.prepared, isFalse);
      expect(identical(out.bytes, header), isTrue);
      expect(out.name, 'dev.png');
      expect((out.width, out.height), (10000, 5000));
      final pick = await prepareWorkPhotoPick('dev.png', header);
      expect(pick.validationError, WorkAttachmentRules.dimensionsMessage);
    });
  });

  group('hazırlama', () {
    test('büyük fotoğraf (4032x3024, 5 MB üstü) -> uzun kenar 2560, oran korunur, JPEG, 5 MB altı; seçim geçerli',
        () async {
      final source = _bigNoisyJpeg(4032, 3024);
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
      final photo = _halves(320, 240);
      photo.exif.gpsIfd.setGpsLocation(latitude: 41.0082, longitude: 28.9784);
      photo.exif.imageIfd.make = 'Deneme';
      photo.exif.imageIfd.model = 'Kamera 1';
      final source = img.encodeJpg(photo, quality: 90);
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

    test('hazırlanamazsa özgün baytlar: bozuk JPEG ve tanınmayan içerik doğrulamaya kalır', () async {
      final broken = wkImageBytes('bozuk.jpg', size: 4096);
      final out = await prepareWorkPhoto('bozuk.jpg', broken);
      expect(out.prepared, isFalse);
      expect(identical(out.bytes, broken), isTrue);
      expect(out.name, 'bozuk.jpg');

      final gif = wkImageBytes('a.gif');
      final pick = await prepareWorkPhotoPick('a.gif', gif);
      expect(pick.name, 'a.gif');
      expect(pick.validationError, WorkAttachmentRules.typeAndSizeMessage);

      final empty = await prepareWorkPhoto('bos.jpg', Uint8List(0));
      expect(empty.prepared, isFalse);
      expect(empty.bytes, isEmpty);
    });
  });
}
