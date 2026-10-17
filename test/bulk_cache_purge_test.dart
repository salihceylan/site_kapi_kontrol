// Yerel geçici kopyaların temizliği (R12 P1-2): lib/services/local_cache_purge.dart ve LocalDataWiper.
// Hesap silinince toplu yükleme dışa aktarma / belge / hesap dışa aktarma klasörleri ve eklenti önbellekleri gider.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';

import 'bulk_fakes.dart' show utf8Bytes;

String _p(Directory d, String name) => '${d.path}${Platform.pathSeparator}$name';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bulk_purge_test_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('purgeLocalSharedCaches', () {
    test('share_plus önbelleği ve file_picker kopyaları silinir; ilgisiz klasöre dokunulmaz', () async {
      final share = await Directory(_p(root, 'share_plus')).create();
      await File(_p(share, 'kisiler.csv')).writeAsString('Ad;Tel\nAli;555');
      final other = await Directory(_p(root, 'baska_onbellek')).create();
      var pickerCleared = 0;
      await purgeLocalSharedCaches(tempRoot: root, clearPicker: () async => pickerCleared++);
      expect(share.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect(pickerCleared, 1);
    });

    test('bayraklar: yalnız seçilen önbellek temizlenir', () async {
      final share = await Directory(_p(root, 'share_plus')).create();
      var pickerCleared = 0;
      await purgeLocalSharedCaches(tempRoot: root, shareCache: false, clearPicker: () async => pickerCleared++);
      expect(share.existsSync(), isTrue, reason: 'paylaşım önbelleği korunur');
      expect(pickerCleared, 1);
      await purgeLocalSharedCaches(tempRoot: root, pickerCache: false, clearPicker: () async => pickerCleared++);
      expect(share.existsSync(), isFalse);
      expect(pickerCleared, 1, reason: 'seçici önbelleği bu çağrıda temizlenmez');
    });

    test('eklenti hata verse de fırlatmaz ve paylaşım önbelleği yine silinir; klasör yoksa sorun değil', () async {
      final share = await Directory(_p(root, 'share_plus')).create();
      await purgeLocalSharedCaches(tempRoot: root, clearPicker: () async => throw StateError('eklenti yok'));
      expect(share.existsSync(), isFalse);
      await purgeLocalSharedCaches(tempRoot: root, clearPicker: () async {});
    });
  });

  group('LocalDataWiper.wipe', () {
    test('toplu_dosya_*, belge ve hesap dışa aktarma kalıntıları + share_plus silinir (R12 P1-2 PoC senaryosu)', () async {
      final bulk = await Directory(_p(root, 'toplu_dosya_abc')).create();
      await File(_p(bulk, 'kisiler.csv')).writeAsString('Ad Soyad;Telefon\nAli;5551234567');
      final doc = await Directory(_p(root, 'kisisel_veri_belge_xyz')).create();
      await File(_p(doc, 'sozlesme.pdf')).writeAsString('%PDF-');
      final exp = await Directory(_p(root, 'kisisel_veri_def')).create();
      await File(_p(exp, 'x.json')).writeAsString('{}');
      final other = await Directory(_p(root, 'baska')).create();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      var purged = 0;

      final report = await LocalDataWiper(
        clearShortcuts: () async {},
        exportTempRoot: root,
        purgeCaches: () async => purged++,
      ).wipe();

      expect(bulk.existsSync(), isFalse, reason: 'toplu yükleme dışa aktarma kalıntısı');
      expect(doc.existsSync(), isFalse);
      expect(exp.existsSync(), isFalse);
      expect(other.existsSync(), isTrue, reason: 'ilgisiz klasöre dokunulmaz');
      expect(purged, 1, reason: 'eklenti önbellekleri süpürüldü');
      expect(report.complete, isTrue);
    });

    test('paylaşımı az önce yapılmış (gecikmeli silinecek) CANLI toplu dosya klasörü de silinir, zamanlayıcı iptal edilir', () async {
      final sharer = BulkFileSharer(
        shareFn: (_) async => const ShareResult('ok', ShareResultStatus.success),
        tempRoot: () async => root,
        cleanupDelay: const Duration(minutes: 2),
        useSaveDialog: false,
        useTempFile: true,
        purgeCaches: () async {},
      );
      await sharer.deliver(
        RenderedFile(
          bytes: utf8Bytes('Ad;Not\r\nAli;x\r\n'),
          fileName: 'kisiler.csv',
          mimeType: 'text/csv',
          format: ExportFormat.csv,
        ),
      );
      final live = root.listSync().whereType<Directory>().where((d) => d.path.contains('toplu_dosya_')).toList();
      expect(live, hasLength(1));
      expect(BulkFileSharer.pendingCleanupCount, greaterThan(0));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});

      await LocalDataWiper(clearShortcuts: () async {}, exportTempRoot: root, purgeCaches: () async {}).wipe();

      expect(live.single.existsSync(), isFalse);
      expect(BulkFileSharer.pendingCleanupCount, 0);
    });

    test('sweepSharedFiles (çıkış yolu) wipe olmadan da aynı süpürmeyi yapar ve hata fırlatmaz', () async {
      final bulk = await Directory(_p(root, 'toplu_dosya_cikis')).create();
      await File(_p(bulk, 'a.csv')).writeAsString('x');
      await LocalDataWiper.sweepSharedFiles(root: root, purgeCaches: () async => throw StateError('hata'));
      expect(bulk.existsSync(), isFalse);
    });
  });
}
