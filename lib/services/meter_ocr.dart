// Sayaç fotoğrafı: küçültme (gizlilik için pikselden yeniden kodlama) ve telefonda metin tanıma (ML Kit; yalnız Android/iOS).
//
// Okuma telefonda yapılır (internetsiz de çalışsın diye). Tanınan metin yalnız ADAY değerdir: görevli onaylar ya da düzeltir.
// Fotoğraf ve tanınan metin günlüğe YAZILMAZ. Yeniden kodlama EXIF/GPS dahil tüm üstverileri atar.
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Sunucu fotoğraf sınırı 600 KB; uzun kenar 1280 px, JPEG kalite 70 bunun çok altında kalır.
const int kMeterPhotoMaxEdge = 1280;
const int kMeterPhotoQuality = 70;

/// Fotoğrafı küçültüp EXIF'siz JPEG'e çevirir; çözülemezse null.
Uint8List? shrinkMeterPhoto(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final longest = oriented.width > oriented.height ? oriented.width : oriented.height;
    final resized = longest > kMeterPhotoMaxEdge
        ? img.copyResize(oriented, width: oriented.width >= oriented.height ? kMeterPhotoMaxEdge : null, height: oriented.height > oriented.width ? kMeterPhotoMaxEdge : null)
        : oriented;
    return Uint8List.fromList(img.encodeJpg(resized, quality: kMeterPhotoQuality));
  } on Object {
    return null;
  }
}

Future<Uint8List?> shrinkMeterPhotoAsync(Uint8List bytes) => kIsWeb ? Future<Uint8List?>.value(shrinkMeterPhoto(bytes)) : compute(shrinkMeterPhoto, bytes);

/// Metin tanıyıcı (testlerde sahte).
abstract class MeterOcr {
  /// Tanınan ham metin; desteklenmiyorsa ya da tanınamadıysa null.
  Future<String?> recognize(String imagePath);
  Future<void> close();
}

/// ML Kit (Latin) ile; web ve masaüstünde desteklenmez (null döner, görevli elle yazar).
class MlKitMeterOcr implements MeterOcr {
  TextRecognizer? _recognizer;

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<String?> recognize(String imagePath) async {
    if (!supported || !File(imagePath).existsSync()) return null;
    try {
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result = await _recognizer!.processImage(InputImage.fromFilePath(imagePath));
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() async {
    final r = _recognizer;
    _recognizer = null;
    if (r != null) await r.close();
  }
}
