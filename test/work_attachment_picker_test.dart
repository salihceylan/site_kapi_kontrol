// Fotoğraf seçimi yardımcıları (lib/services/work_attachment_picker.dart, ui/widgets/work_attachment_parts.dart):
// çözmeden boyut okuma (bellek bombası koruması), tür içerik imzasından (uzantıdan önce), ön doğrulama (boyut / tür /
// çözünürlük), geçersiz seçimin yer doldurmaması ve önizleme sağlayıcılarının ImageCache'ten çıkarılması.
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/work_attachment_picker.dart';
import 'package:site_kapi_kontrol/ui/widgets/work_attachment_parts.dart';

import 'screens/work_fixtures.dart';

void main() {
  group('probeImageSize (çözmeden)', () {
    test('gerçek 1x1 PNG; 10000x5000 bildiren başlık; tanınmayan / boş içerik null', () async {
      expect(await probeImageSize(kWkPng), (width: 1, height: 1));
      expect(await probeImageSize(wkPngHeader(width: 10000, height: 5000)), (width: 10000, height: 5000));
      expect(await probeImageSize(Uint8List.fromList(List<int>.filled(64, 7))), isNull);
      expect(await probeImageSize(Uint8List(0)), isNull);
    });
  });

  group('WorkPhotoPick', () {
    test('tür içerik imzasından (uzantıdan önce); imza yoksa uzantı; o da yoksa ikili', () {
      expect(WorkPhotoPick(name: 'IMG_1.HEIC', bytes: kWkPng).mimeType, 'image/png');
      expect(wkPhoto('foto.jpg').mimeType, 'image/jpeg');
      expect(wkPhoto('foto.webp').mimeType, 'image/webp');
      expect(WorkPhotoPick(name: 'a.jpg', bytes: Uint8List(8)).mimeType, 'image/jpeg', reason: 'imza yok: uzantı');
      expect(WorkPhotoPick(name: 'a', bytes: Uint8List(8)).mimeType, 'application/octet-stream');
    });

    test('ön doğrulama: içerik imzası, boş, sınırı aşan (okunmadan), çözünürlük', () {
      expect(WorkPhotoPick(name: 'IMG_1.HEIC', bytes: kWkPng).isValid, isTrue, reason: 'iOS dönüşümü: içerik PNG/JPEG');
      expect(wkPhoto('a.gif').validationError, WorkAttachmentRules.typeAndSizeMessage);
      expect(
        WorkPhotoPick(name: 'a.jpg', bytes: Uint8List(16)).validationError,
        WorkAttachmentRules.typeAndSizeMessage,
        reason: '.jpg adlı ama JPEG olmayan içerik',
      );
      expect(WorkPhotoPick(name: 'a.jpg', bytes: Uint8List(0)).validationError, contains('boş'));
      final oversized = WorkPhotoPick.oversized(name: 'dev.jpg', size: kWorkAttachmentMaxBytes + 1);
      expect(oversized.validationError, contains('çok büyük'));
      expect(oversized.size, kWorkAttachmentMaxBytes + 1);
      final huge = WorkPhotoPick(name: 'a.png', bytes: kWkPng, width: 10000, height: 5000);
      expect(huge.validationError, WorkAttachmentRules.dimensionsMessage);
      expect(WorkPhotoPick(name: 'a.png', bytes: kWkPng, width: 4000, height: 3000).isValid, isTrue);
    });
  });

  group('workSplitSelection', () {
    test('geçersiz seçim yer DOLDURMAZ ve ayrı satırda bildirilir; sınır aşımı tek uyarı', () {
      final ok1 = wkPhoto('a.jpg');
      final ok2 = wkPhoto('b.png');
      final gif = wkPhoto('c.gif');
      final big = WorkPhotoPick.oversized(name: 'dev.jpg', size: kWorkAttachmentMaxBytes + 1);
      final split = workSplitSelection(
        WorkPhotoSelection(picks: <WorkPhotoPick>[ok1, gif, ok2], rejected: <WorkPhotoPick>[big]),
        remaining: 2,
      );
      expect(split.valid, <WorkPhotoPick>[ok1, ok2]);
      expect(split.notes.length, 2);
      expect(split.notes[0], 'c.gif: ${WorkAttachmentRules.typeAndSizeMessage}');
      expect(split.notes[1], startsWith('dev.jpg: Fotoğraf çok büyük'));

      final over = workSplitSelection(
        WorkPhotoSelection(picks: <WorkPhotoPick>[ok1, ok2]),
        remaining: 1,
      );
      expect(over.valid, <WorkPhotoPick>[ok1]);
      expect(over.notes, <String>[WorkAttachmentRules.limitMessage]);

      final dropped = workSplitSelection(
        WorkPhotoSelection(picks: <WorkPhotoPick>[ok1], droppedCount: 2),
        remaining: 4,
      );
      expect(dropped.valid, <WorkPhotoPick>[ok1]);
      expect(dropped.notes, <String>[WorkAttachmentRules.limitMessage]);
    });
  });

  group('WorkImageProviders', () {
    testWidgets('önizleme sağlayıcıları ImageCache\'ten çıkarılır (fotoğraf kaldırılınca / kapanınca)', (t) async {
      final cache = PaintingBinding.instance.imageCache;
      final images = WorkImageProviders();
      final first = Uint8List.fromList(kWkPng);
      final second = Uint8List.fromList(kWkPng);
      final p1 = images.of(first, cacheWidth: 56);
      final p2 = images.of(second, cacheWidth: 56);
      p1.resolve(ImageConfiguration.empty);
      p2.resolve(ImageConfiguration.empty);
      final k1 = await p1.obtainKey(ImageConfiguration.empty);
      final k2 = await p2.obtainKey(ImageConfiguration.empty);
      expect(cache.containsKey(k1), isTrue);
      expect(cache.containsKey(k2), isTrue);
      images.evictBytes(first);
      await t.pump();
      expect(cache.containsKey(k1), isFalse, reason: 'kaldırılan fotoğrafın önizlemesi çıktı');
      expect(cache.containsKey(k2), isTrue);
      images.dispose();
      await t.pump();
      expect(cache.containsKey(k2), isFalse, reason: 'pencere kapandı: hepsi çıktı');
    });
  });
}
