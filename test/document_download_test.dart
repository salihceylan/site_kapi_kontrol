// İndirme hedefleri (TempFileDocumentSink / MemoryDocumentSink) ve paylaşım temizliği (DocumentFileSharer):
// geçici dosya akışla yazılır, iptal / hata kısmi veriyi siler, paylaşımdan sonra klasör silinir, hesap silinince
// (AccountExportSharer süpürmesi) belge kopyaları da gider. Gerçek dosya sistemi kullanılır (düz `test`).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';
import 'package:site_kapi_kontrol/services/document_picker.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('doc_dl_test_');
  });

  tearDown(() async {
    await DocumentFileSharer.sweepAll(root: root, includeLive: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('TempFileDocumentSink', () {
    test(
      'parçalar dosyaya yazılır; klasör öneki kisisel_veri_belge_; finish boyutu ve yolu verir',
      () async {
        final sink = await TempFileDocumentSink.open(
          fileName: 'Yönetmelik.pdf',
          mimeType: 'application/pdf',
          root: root,
        );
        await sink.add(Uint8List.fromList(List<int>.filled(1000, 1)));
        await sink.add(Uint8List.fromList(List<int>.filled(500, 2)));
        final doc = await sink.finish();
        expect(doc.sizeBytes, 1500);
        expect(doc.fileName, 'Yönetmelik.pdf');
        expect(doc.mimeType, 'application/pdf');
        expect(doc.bytes, isNull);
        final file = File(doc.path!);
        expect(await file.length(), 1500);
        expect(file.parent.path, doc.directoryPath);
        expect(Directory(doc.directoryPath!).parent.path, root.path);
        expect(
          file.parent.uri.pathSegments.where((s) => s.isNotEmpty).last,
          startsWith('kisisel_veri_belge_'),
        );
        expect(TempFileDocumentSink.livePaths, contains(doc.directoryPath));
        await TempFileDocumentSink.deleteDirectory(doc.directoryPath);
        expect(await file.exists(), isFalse);
        expect(
          TempFileDocumentSink.livePaths,
          isNot(contains(doc.directoryPath)),
        );
      },
    );

    test(
      'büyük gövde (3 MB) düzenli flush ile yazılır, bayt sayısı doğru',
      () async {
        final sink = await TempFileDocumentSink.open(
          fileName: 'b.pdf',
          mimeType: 'application/pdf',
          root: root,
        );
        final chunk = Uint8List(64 * 1024);
        for (var i = 0; i < 48; i++) {
          await sink.add(chunk);
        }
        final doc = await sink.finish();
        expect(doc.sizeBytes, 48 * 64 * 1024);
        expect(await File(doc.path!).length(), doc.sizeBytes);
        await TempFileDocumentSink.deleteDirectory(doc.directoryPath);
      },
    );

    test('abort: kısmi dosya ve klasör silinir', () async {
      final sink = await TempFileDocumentSink.open(
        fileName: 'k.pdf',
        mimeType: 'application/pdf',
        root: root,
      );
      await sink.add(Uint8List(2048));
      await sink.abort();
      expect(await root.list().toList(), isEmpty);
    });

    test(
      'tehlikeli ad (../ , dizin ayırıcı) yola GİRMEZ: dosya klasörün içinde kalır',
      () async {
        final sink = await TempFileDocumentSink.open(
          fileName: '../../etc/passwd',
          mimeType: 'text/plain',
          root: root,
        );
        await sink.add(Uint8List(10));
        final doc = await sink.finish();
        expect(doc.fileName, 'passwd');
        expect(File(doc.path!).parent.path, doc.directoryPath);
        expect(
          await File(
            '${root.parent.path}${Platform.pathSeparator}passwd',
          ).exists(),
          isFalse,
        );
        await TempFileDocumentSink.deleteDirectory(doc.directoryPath);
      },
    );

    test('MemoryDocumentSink (web): bellekte toplar, dosya yolu yok', () async {
      final sink = MemoryDocumentSink(fileName: 'a.png', mimeType: 'image/png');
      await sink.add(<int>[1, 2, 3]);
      await sink.add(<int>[4]);
      final doc = await sink.finish();
      expect(doc.bytes, <int>[1, 2, 3, 4]);
      expect(doc.path, isNull);
      expect(doc.directoryPath, isNull);
    });
  });

  group('süpürme', () {
    Future<Directory> make(String name) async {
      final dir = await Directory(
        '${root.path}${Platform.pathSeparator}$name',
      ).create();
      await File(
        '${dir.path}${Platform.pathSeparator}x.pdf',
      ).writeAsBytes(<int>[1, 2, 3]);
      return dir;
    }

    test(
      'yalnız kisisel_veri_belge_ önekli klasörler silinir; başka klasöre dokunulmaz',
      () async {
        final mine = await make('kisisel_veri_belge_aaa');
        final other = await make('baska_klasor');
        await DocumentFileSharer.sweepAll(root: root);
        expect(await mine.exists(), isFalse);
        expect(await other.exists(), isTrue);
      },
    );

    test('staleAfter: yeni klasör korunur, süresi geçen silinir', () async {
      final old = await make('kisisel_veri_belge_eski');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final fresh = await make('kisisel_veri_belge_yeni');
      await DocumentFileSharer.sweepAll(
        root: root,
        staleAfter: const Duration(milliseconds: 80),
      );
      expect(await fresh.exists(), isTrue);
      expect(await old.exists(), isFalse);
    });

    test(
      'kullanımdaki (canlı) klasör süpürülmez; includeLive ile silinir ve zamanlayıcı iptal edilir',
      () async {
        final sink = await TempFileDocumentSink.open(
          fileName: 'a.pdf',
          mimeType: 'application/pdf',
          root: root,
        );
        await sink.add(Uint8List(10));
        final doc = await sink.finish();
        await DocumentFileSharer.sweepAll(root: root);
        expect(
          await Directory(doc.directoryPath!).exists(),
          isTrue,
          reason: 'alıcı uygulama okuyor olabilir',
        );

        final sharer = DocumentFileSharer(
          shareFn: (_) async =>
              const ShareResult('', ShareResultStatus.success),
          cleanupDelay: const Duration(minutes: 2),
          sweepStaleOnShare: false,
        );
        await sharer.share(doc);
        expect(DocumentFileSharer.pendingCleanupCount, 1);
        await DocumentFileSharer.sweepAll(root: root, includeLive: true);
        expect(DocumentFileSharer.pendingCleanupCount, 0);
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
      },
    );

    test(
      'HESAP SİLME bağı: AccountExportSharer.sweepAll (LocalDataWiper) belge kopyalarını da siler',
      () async {
        final dir = await make('kisisel_veri_belge_hesap');
        final exportDir = await make('kisisel_veri_disaaktar');
        await AccountExportSharer.sweepAll(root: root);
        expect(
          await dir.exists(),
          isFalse,
          reason: 'belge kopyası hesap silinince kalmaz',
        );
        expect(await exportDir.exists(), isFalse);
      },
    );
  });

  group('yerel önbellek temizliği (R12 P1-2)', () {
    Future<DownloadedDocument> download(String name) async {
      final sink = await TempFileDocumentSink.open(
        fileName: name,
        mimeType: 'application/pdf',
        root: root,
      );
      await sink.add(Uint8List(512));
      return sink.finish();
    }

    DocumentFileSharer sharer({
      required Duration delay,
      required List<String> log,
      Future<void> Function()? purge,
    }) => DocumentFileSharer(
      shareFn: (_) async => const ShareResult('', ShareResultStatus.success),
      cleanupDelay: delay,
      sweepStaleOnShare: false,
      purgeSharedCaches: purge ?? () async => log.add('purge'),
    );

    test(
      'gecikmeli silme dolunca klasör silinir VE share_plus önbelleği temizlenir (bir kez)',
      () async {
        final log = <String>[];
        final doc = await download('a.pdf');
        await sharer(
          delay: const Duration(milliseconds: 60),
          log: log,
        ).share(doc);
        expect(
          log,
          isEmpty,
          reason:
              'paylaşımın hemen ardından DEĞİL: alıcı kopyayı okuyor olabilir',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
        expect(log, <String>['purge']);
      },
    );

    test(
      'başka paylaşım hâlâ bekliyorsa önbellek SON zamanlayıcıda temizlenir (süren paylaşımın kopyası korunur)',
      () async {
        final log = <String>[];
        final first = await download('a.pdf');
        final second = await download('b.pdf');
        final a = sharer(delay: const Duration(milliseconds: 60), log: log);
        final b = sharer(delay: const Duration(milliseconds: 400), log: log);
        await a.share(first);
        await b.share(second);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(await Directory(first.directoryPath!).exists(), isFalse);
        expect(await Directory(second.directoryPath!).exists(), isTrue);
        expect(
          log,
          isEmpty,
          reason: 'ikinci paylaşım sürüyor: share_plus kopyasına dokunulmaz',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(await Directory(second.directoryPath!).exists(), isFalse);
        expect(log, <String>['purge']);
      },
    );

    test(
      'önbellek temizliği hata verse de klasör silinir ve hata sızmaz',
      () async {
        final doc = await download('a.pdf');
        final s = sharer(
          delay: const Duration(milliseconds: 40),
          log: <String>[],
          purge: () async => throw StateError('kilitli'),
        );
        await s.share(doc);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
        expect(DocumentFileSharer.pendingCleanupCount, 0);
      },
    );

    test('gecikmesiz (iOS) yolda eklenti önbelleğine dokunulmaz', () async {
      final log = <String>[];
      final doc = await download('a.pdf');
      await sharer(delay: Duration.zero, log: log).share(doc);
      expect(await Directory(doc.directoryPath!).exists(), isFalse);
      expect(log, isEmpty);
    });

    test(
      'LocalDataWiper.sweepSharedFiles (F-2b) DocumentFileSharer imzasıyla çalışır: canlı belge klasörü + zamanlayıcı gider, eklenti temizliği çağrılır',
      () async {
        final doc = await download('hesap.pdf');
        final s = sharer(delay: const Duration(minutes: 2), log: <String>[]);
        await s.share(doc);
        expect(DocumentFileSharer.pendingCleanupCount, 1);
        var purged = 0;
        await LocalDataWiper.sweepSharedFiles(
          root: root,
          purgeCaches: () async => purged++,
        );
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
        expect(DocumentFileSharer.pendingCleanupCount, 0);
        expect(purged, 1);
      },
    );

    test(
      'FilePickerDocumentPicker.release: verilen temizleyiciyi çağırır, hata sızdırmaz; varsayılan hata vermez',
      () async {
        var calls = 0;
        await FilePickerDocumentPicker(
          clearCache: () async => calls++,
        ).release();
        expect(calls, 1);
        await FilePickerDocumentPicker(
          clearCache: () async => throw StateError('eklenti yok'),
        ).release();
        // Varsayılan: gerçek eklenti bu ortamda yok (MissingPluginException) ama sorun çıkmaz.
        await const FilePickerDocumentPicker().release();
      },
    );
  });

  group('DocumentFileSharer.share', () {
    Future<DownloadedDocument> download() async {
      final sink = await TempFileDocumentSink.open(
        fileName: 'Plan.pdf',
        mimeType: 'application/pdf',
        root: root,
      );
      await sink.add(Uint8List(2048));
      return sink.finish();
    }

    test(
      'dosya yolu paylaşılır (bellekten değil); gecikme sıfırsa paylaşımdan sonra klasör silinir',
      () async {
        final doc = await download();
        ShareParams? seen;
        final sharer = DocumentFileSharer(
          shareFn: (params) async {
            seen = params;
            expect(
              await File(doc.path!).exists(),
              isTrue,
              reason: 'paylaşım sırasında dosya var',
            );
            return const ShareResult('', ShareResultStatus.success);
          },
          cleanupDelay: Duration.zero,
          sweepStaleOnShare: false,
        );
        final outcome = await sharer.share(doc);
        expect(outcome, DocumentShareOutcome.shared);
        expect(seen!.files!.single.path, doc.path);
        expect(seen!.fileNameOverrides, <String>['Plan.pdf']);
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
      },
    );

    test('kullanıcı menüyü kapattı / platform sonucu bilmiyor', () async {
      for (final entry in <ShareResultStatus, DocumentShareOutcome>{
        ShareResultStatus.dismissed: DocumentShareOutcome.dismissed,
        ShareResultStatus.unavailable: DocumentShareOutcome.unknown,
      }.entries) {
        final doc = await download();
        final sharer = DocumentFileSharer(
          shareFn: (_) async => ShareResult('', entry.key),
          cleanupDelay: Duration.zero,
          sweepStaleOnShare: false,
        );
        expect(await sharer.share(doc), entry.value);
      }
    });

    test(
      'paylaşım hata verirse hata iletilir ama geçici kopya YİNE silinir',
      () async {
        final doc = await download();
        final sharer = DocumentFileSharer(
          shareFn: (_) async => throw StateError('paylaşım yok'),
          cleanupDelay: Duration.zero,
          sweepStaleOnShare: false,
        );
        await expectLater(sharer.share(doc), throwsStateError);
        expect(await Directory(doc.directoryPath!).exists(), isFalse);
      },
    );

    test('gecikmeli silme: zamanlanır, süre dolunca silinir', () async {
      final doc = await download();
      final sharer = DocumentFileSharer(
        shareFn: (_) async => const ShareResult('', ShareResultStatus.success),
        cleanupDelay: const Duration(milliseconds: 80),
        sweepStaleOnShare: false,
        purgeSharedCaches: () async {},
      );
      await sharer.share(doc);
      expect(DocumentFileSharer.pendingCleanupCount, 1);
      expect(await Directory(doc.directoryPath!).exists(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(DocumentFileSharer.pendingCleanupCount, 0);
      expect(await Directory(doc.directoryPath!).exists(), isFalse);
    });

    test(
      'bellekteki belge (web): XFile.fromData ile paylaşılır, silinecek klasör yok',
      () async {
        ShareParams? seen;
        final sharer = DocumentFileSharer(
          shareFn: (params) async {
            seen = params;
            return const ShareResult('', ShareResultStatus.success);
          },
          sweepStaleOnShare: false,
        );
        final doc = DownloadedDocument(
          fileName: 'a.png',
          mimeType: 'image/png',
          sizeBytes: 3,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        );
        expect(await sharer.share(doc), DocumentShareOutcome.shared);
        expect(seen!.files!.single.mimeType, 'image/png');
        expect(seen!.fileNameOverrides, <String>['a.png']);
      },
    );
  });
}
