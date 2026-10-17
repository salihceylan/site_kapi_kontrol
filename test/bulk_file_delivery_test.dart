// Üretilen dosyanın teslimi (lib/services/bulk_file_delivery.dart): mobilde geçici kopya paylaşım sonrası SİLİNİR,
// masaüstü / web'de «Kaydet» iletişim kutusu kullanılır, geçici klasör açılamazsa bellekten paylaşılır.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';

RenderedFile _file([String name = 'kisiler_20261016.csv']) => RenderedFile(
  bytes: Uint8List.fromList(utf8.encode('Ad;Not\r\nAli;x\r\n')),
  fileName: name,
  mimeType: 'text/csv',
  format: ExportFormat.csv,
);

Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bulk_delivery_test_');
  });

  tearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  var purges = 0;

  BulkFileSharer sharer(
    Future<ShareResult> Function(ShareParams) fn, {
    Duration cleanupDelay = Duration.zero,
    Duration staleAfter = const Duration(minutes: 10),
  }) => BulkFileSharer(
    purgeCaches: () async => purges++,
    shareFn: fn,
    tempRoot: () async => root,
    cleanupDelay: cleanupDelay,
    staleAfter: staleAfter,
    useSaveDialog: false,
    useTempFile: true,
  );

  group('mobil: paylaşım sayfası', () {
    test('paylaşım anında dosya var ve içerik birebir; sonra klasör silinir (kişisel veri kalmaz)', () async {
      String? path;
      String? content;
      String? mime;
      String? subject;
      List<String>? overrides;
      final outcome = await sharer((params) async {
        final f = params.files!.single;
        path = f.path;
        content = await File(f.path).readAsString();
        mime = f.mimeType;
        subject = params.subject;
        overrides = params.fileNameOverrides;
        return const ShareResult('ok', ShareResultStatus.success);
      }).deliver(_file(), subject: 'Kişiler');
      expect(outcome, ExportShareOutcome.shared);
      expect(content, 'Ad;Not\r\nAli;x\r\n');
      expect(path, endsWith('kisiler_20261016.csv'));
      expect(path!.startsWith(root.path), isTrue);
      expect(mime, 'text/csv');
      expect(subject, 'Kişiler');
      expect(overrides, <String>['kisiler_20261016.csv']);
      await _eventually(() => !File(path!).parent.existsSync());
      expect(root.listSync(), isEmpty);
    });

    test('paylaşım hata fırlatsa da geçici kopya silinir', () async {
      String? path;
      await expectLater(
        sharer((params) async {
          path = params.files!.single.path;
          throw StateError('paylaşım çöktü');
        }).deliver(_file()),
        throwsStateError,
      );
      await _eventually(() => !File(path!).parent.existsSync());
      expect(root.listSync(), isEmpty);
    });

    test('geçici klasör silindikten sonra eklenti önbelleği de (share_plus) süpürülür', () async {
      purges = 0;
      await sharer((_) async => const ShareResult('ok', ShareResultStatus.success)).deliver(_file());
      expect(purges, 1, reason: 'gecikmesiz: paylaşım biter bitmez');
      purges = 0;
      await sharer(
        (_) async => const ShareResult('ok', ShareResultStatus.success),
        cleanupDelay: const Duration(milliseconds: 80),
      ).deliver(_file());
      expect(purges, 0, reason: 'gecikmeli: alıcı uygulama dosyayı okurken önbellek silinmez');
      await _eventually(() => purges > 0);
      expect(purges, 1, reason: 'zamanlayıcı dolunca');
    });

    test('sonuç eşlemesi: dismissed -> dismissed, unavailable -> unknown', () async {
      Future<ExportShareOutcome> run(ShareResultStatus s) => sharer((_) async => ShareResult('', s)).deliver(_file());
      expect(await run(ShareResultStatus.dismissed), ExportShareOutcome.dismissed);
      expect(await run(ShareResultStatus.unavailable), ExportShareOutcome.unknown);
    });

    test('gecikmeli silme: alıcı uygulama okurken dosya durur, süre dolunca silinir', () async {
      String? path;
      await sharer((params) async {
        path = params.files!.single.path;
        return const ShareResult('ok', ShareResultStatus.success);
      }, cleanupDelay: const Duration(milliseconds: 150)).deliver(_file());
      expect(File(path!).existsSync(), isTrue, reason: 'hemen silinmez');
      expect(BulkFileSharer.pendingCleanupCount, greaterThan(0));
      await _eventually(() => !File(path!).existsSync());
      expect(File(path!).existsSync(), isFalse);
    });

    test('geçici klasör açılamazsa bellekten paylaşılır', () async {
      XFile? shared;
      final s = BulkFileSharer(
        shareFn: (params) async {
          shared = params.files!.single;
          return const ShareResult('ok', ShareResultStatus.success);
        },
        tempRoot: () async => throw const FileSystemException('izin yok'),
        cleanupDelay: Duration.zero,
        useSaveDialog: false,
        useTempFile: true,
      );
      expect(await s.deliver(_file()), ExportShareOutcome.shared);
      expect(shared, isNotNull);
      expect(await shared!.readAsString(), 'Ad;Not\r\nAli;x\r\n');
    });

    test('önceki paylaşımlardan kalan eski klasörler süpürülür, yenilere dokunulmaz', () async {
      final old = await Directory('${root.path}${Platform.pathSeparator}toplu_dosya_eski').create();
      await File('${old.path}${Platform.pathSeparator}a.csv').writeAsString('x');
      await old.stat();
      final other = await Directory('${root.path}${Platform.pathSeparator}baska_klasor').create();
      await BulkFileSharer.sweepAll(root: root);
      expect(old.existsSync(), isFalse, reason: 'staleAfter sıfır: hepsi silinir');
      expect(other.existsSync(), isTrue, reason: 'ilgisiz klasöre dokunulmaz');

      final fresh = await Directory('${root.path}${Platform.pathSeparator}toplu_dosya_yeni').create();
      await BulkFileSharer.sweepAll(root: root, staleAfter: const Duration(minutes: 10));
      expect(fresh.existsSync(), isTrue, reason: 'yeni klasör (alıcı okuyor olabilir) korunur');
    });
  });

  group('masaüstü / web: kaydet iletişim kutusu', () {
    test('saveFile çağrılır; başarı = shared, vazgeçme = dismissed; paylaşım ÇAĞRILMAZ', () async {
      var shareCalls = 0;
      String? name;
      Uint8List? bytes;
      String? mime;
      Uri? result = Uri.file('/tmp/x.csv');
      final s = BulkFileSharer(
        shareFn: (_) async {
          shareCalls++;
          return const ShareResult('', ShareResultStatus.success);
        },
        saveFn: ({required String fileName, required Uint8List bytes, required String mimeType}) async {
          name = fileName;
          mime = mimeType;
          return result;
        },
        useSaveDialog: true,
      );
      expect(await s.deliver(_file()), ExportShareOutcome.shared);
      expect(name, 'kisiler_20261016.csv');
      expect(mime, 'text/csv');
      result = null;
      expect(await s.deliver(_file()), ExportShareOutcome.dismissed);
      expect(shareCalls, 0);
      expect(bytes, isNull);
    });

    test('saveFile hatası çağırana iletilir (ekran ileti gösterir)', () async {
      final s = BulkFileSharer(
        saveFn: ({required String fileName, required Uint8List bytes, required String mimeType}) async =>
            throw StateError('yazılamadı'),
        useSaveDialog: true,
      );
      await expectLater(s.deliver(_file()), throwsStateError);
    });
  });

  group('web: saveFile her zaman null döner (Blob indirmesi)', () {
    test('webde null sonuç «kaydedilmedi» DEĞİL başarıdır; masaustunde null = vazgecti', () async {
      Future<Uri?> nullSave({required String fileName, required Uint8List bytes, required String mimeType}) async =>
          null;
      final web = BulkFileSharer(saveFn: nullSave, useSaveDialog: true, isWeb: true);
      expect(await web.deliver(_file()), ExportShareOutcome.shared);
      final desktop = BulkFileSharer(saveFn: nullSave, useSaveDialog: true, isWeb: false);
      expect(await desktop.deliver(_file()), ExportShareOutcome.dismissed);
    });
  });

  group('dosya seçici sarmalayıcısı (R12 P2-3)', () {
    test('lengthSync null ise (Windows / Linux) length() kullanılır', () async {
      final file = _FakePlatformFile(syncLength: null, asyncLength: 18, content: 'Blok;Daire No\nA;1\n');
      final picked = await pickedFileOf(file);
      expect(picked.size, 18);
      expect(picked.name, 'daireler.csv');
      expect(utf8.decode(await picked.readBytes()), 'Blok;Daire No\nA;1\n');
    });

    test('lengthSync biliniyorsa dosyaya hiç bakılmaz; boyut hiç bilinemezse null (okunduktan sonra denetlenir)', () async {
      final known = _FakePlatformFile(syncLength: 7, asyncLength: 99, content: 'x');
      expect((await pickedFileOf(known)).size, 7);
      expect(known.asyncCalls, 0);
      final unknown = _FakePlatformFile(syncLength: null, asyncLength: null, content: 'x');
      expect((await pickedFileOf(unknown)).size, isNull);
      final broken = _FakePlatformFile(syncLength: null, asyncLength: null, content: 'x', throwOnLength: true);
      expect((await pickedFileOf(broken)).size, isNull);
    });
  });
}

base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({
    required this.syncLength,
    required this.asyncLength,
    required this.content,
    this.throwOnLength = false,
  });

  final int? syncLength;
  final int? asyncLength;
  final String content;
  final bool throwOnLength;
  int asyncCalls = 0;

  @override
  String get name => 'daireler.csv';

  @override
  Uri get uri => Uri.file('/tmp/daireler.csv');

  @override
  XFile get xFile => XFile.fromData(Uint8List.fromList(utf8.encode(content)));

  @override
  int? lengthSync() => syncLength;

  @override
  Future<int?> length() async {
    asyncCalls++;
    if (throwOnLength) throw const FileSystemException('okunamadı');
    return asyncLength;
  }

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(utf8.encode(content));

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(content)));
}
