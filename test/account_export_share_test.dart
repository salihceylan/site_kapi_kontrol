// Kişisel veri dosyası paylaşımı (lib/services/account_export_share.dart): geçici dosya içeriği doğru yazılır,
// paylaşım sonrası SİLİNİR (hata olsa bile), eski artıklar süpürülür, geçici klasör açılamazsa bellekten paylaşılır.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';

AccountDataExport _export([String json = '{"format_version":1}']) => AccountDataExport(
  bytes: Uint8List.fromList(utf8.encode(json)),
  fileName: 'kisisel-veri-42-20261016.json',
);

Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('export_share_test_');
  });

  tearDown(() async {
    // Silme belirleyici (await edilir) ama yine de bir Windows dosya kilidi yarışı testi kırmasın.
    for (var i = 0; i < 5; i++) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  AccountExportSharer sharer(
    Future<ShareResult> Function(ShareParams) fn, {
    Duration staleAfter = const Duration(minutes: 10),
  }) => AccountExportSharer(
    shareFn: fn,
    tempRoot: () async => root,
    cleanupDelay: Duration.zero,
    staleAfter: staleAfter,
  );

  test('paylaşım anında dosya vardır ve içerik birebir aynıdır; sonra klasör silinir', () async {
    String? seenPath;
    String? seenContent;
    String? seenSubject;
    String? seenMime;
    final result = await sharer((params) async {
      final file = params.files!.single;
      seenPath = file.path;
      seenContent = await File(file.path).readAsString();
      seenSubject = params.subject;
      seenMime = file.mimeType;
      return const ShareResult('ok', ShareResultStatus.success);
    }).share(_export());

    expect(result, ExportShareOutcome.shared);
    expect(seenContent, '{"format_version":1}');
    expect(seenPath, endsWith('kisisel-veri-42-20261016.json'));
    expect(seenSubject, 'Kişisel veri dosyam');
    expect(seenMime, 'application/json');
    expect(seenPath!.startsWith(root.path), isTrue, reason: 'kendi geçici klasörümüzde');
    final dir = File(seenPath!).parent;
    await _eventually(() => !dir.existsSync());
    expect(dir.existsSync(), isFalse, reason: 'kişisel veri geçici kopyası silinir');
    expect(root.listSync(), isEmpty);
  });

  test('sonuç eşlemesi: dismissed -> dismissed, unavailable -> unknown', () async {
    Future<ExportShareOutcome> run(ShareResultStatus status) =>
        sharer((_) async => ShareResult('', status)).share(_export());
    expect(await run(ShareResultStatus.dismissed), ExportShareOutcome.dismissed);
    expect(await run(ShareResultStatus.unavailable), ExportShareOutcome.unknown);
  });

  test('paylaşım hata verse bile geçici dosya silinir ve hata iletilir', () async {
    String? seenPath;
    await expectLater(
      sharer((params) async {
        seenPath = params.files!.single.path;
        throw StateError('paylaşım menüsü açılamadı');
      }).share(_export()),
      throwsStateError,
    );
    final dir = File(seenPath!).parent;
    await _eventually(() => !dir.existsSync());
    expect(dir.existsSync(), isFalse);
  });

  test('geçici klasör açılamazsa bellekten paylaşılır (dosya yolu boş, içerik aynı)', () async {
    String? seenPath;
    List<int>? bytes;
    final s = AccountExportSharer(
      shareFn: (params) async {
        final file = params.files!.single;
        seenPath = file.path;
        bytes = await file.readAsBytes();
        return const ShareResult('', ShareResultStatus.success);
      },
      tempRoot: () async => throw const FileSystemException('izin yok'),
      cleanupDelay: Duration.zero,
    );
    expect(await s.share(_export()), ExportShareOutcome.shared);
    expect(seenPath, isEmpty);
    expect(utf8.decode(bytes!), '{"format_version":1}');
  });

  test('useTempFile:false (web) her zaman bellekten paylaşır', () async {
    String? seenPath;
    final s = AccountExportSharer(
      shareFn: (params) async {
        seenPath = params.files!.single.path;
        return const ShareResult('', ShareResultStatus.success);
      },
      tempRoot: () async => root,
      useTempFile: false,
    );
    await s.share(_export());
    expect(seenPath, isEmpty);
    expect(root.listSync(), isEmpty);
  });

  test('eski artıklar süpürülür: yalnız bizim önekli klasörler, başkalarına dokunulmaz', () async {
    final stale = await Directory('${root.path}${Platform.pathSeparator}kisisel_veri_eski').create();
    final other = await Directory('${root.path}${Platform.pathSeparator}baska_uygulama').create();
    await File('${stale.path}${Platform.pathSeparator}x.json').writeAsString('{}');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    await sharer(
      (_) async => const ShareResult('', ShareResultStatus.success),
      staleAfter: Duration.zero,
    ).share(_export());

    await _eventually(() => !stale.existsSync());
    expect(stale.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
  });

  group('sweepAll (hesap silinince ve bölüm açılınca)', () {
    Future<Directory> mk(String name) => Directory('${root.path}${Platform.pathSeparator}$name').create();

    test('sıfır yaş: bizim önekli TÜM klasörler silinir, başkalarına dokunulmaz', () async {
      final a = await mk('kisisel_veri_a');
      final b = await mk('kisisel_veri_b');
      final other = await mk('baska_uygulama');
      await File('${a.path}${Platform.pathSeparator}x.json').writeAsString('{"kisi":"veri"}');

      await AccountExportSharer.sweepAll(root: root);

      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });

    test('yaş sınırı verilirse yeni klasör kalır', () async {
      final fresh = await mk('kisisel_veri_yeni');
      await AccountExportSharer.sweepAll(staleAfter: const Duration(minutes: 10), root: root);
      expect(fresh.existsSync(), isTrue);
    });

    test('paylaşım SÜRERKEN kullanılan klasör süpürülmez (alıcı okuyor olabilir); bitince silinir', () async {
      Directory? live;
      await sharer((params) async {
        live = File(params.files!.single.path).parent;
        await AccountExportSharer.sweepAll(root: root);
        expect(live!.existsSync(), isTrue, reason: 'bu süreçte kullanılan klasöre dokunulmaz');
        expect(File(params.files!.single.path).existsSync(), isTrue);
        return const ShareResult('', ShareResultStatus.success);
      }).share(_export());
      expect(live!.existsSync(), isFalse, reason: 'paylaşım bitince silindi');
    });

    test('includeLive: gecikmeli silme bekleyen klasör de silinir ve zamanlayıcı İPTAL edilir; includeLive olmadan korunur', () async {
      // Gerçek varsayılan gecikme (2 dk): silme zamanlayıcısı bekler.
      final slow = AccountExportSharer(
        shareFn: (_) async => const ShareResult('', ShareResultStatus.success),
        tempRoot: () async => root,
        cleanupDelay: const Duration(minutes: 2),
      );
      await slow.share(_export());
      final dirs = root.listSync().whereType<Directory>().toList();
      expect(dirs, hasLength(1));
      expect(AccountExportSharer.pendingCleanupCount, 1);

      await AccountExportSharer.sweepAll(root: root);
      expect(dirs.single.existsSync(), isTrue, reason: 'canlı klasör varsayılan süpürmede korunur (alıcı okuyor olabilir)');
      expect(AccountExportSharer.pendingCleanupCount, 1);

      await AccountExportSharer.sweepAll(root: root, includeLive: true);
      expect(dirs.single.existsSync(), isFalse, reason: 'hesap silinince alıcı beklenmez');
      expect(AccountExportSharer.pendingCleanupCount, 0, reason: 'bekleyen zamanlayıcılar iptal edildi');
    });

    test('includeLive: paylaşım SÜRERKEN bile (hesap silindi) klasör silinir', () async {
      late Directory live;
      await sharer((params) async {
        live = File(params.files!.single.path).parent;
        await AccountExportSharer.sweepAll(root: root, includeLive: true);
        expect(live.existsSync(), isFalse);
        return const ShareResult('', ShareResultStatus.success);
      }).share(_export());
      expect(root.listSync(), isEmpty);
    });

    test('includeLive kök dizinden bağımsızdır: bu süreçte bilinen klasör başka kökten çağrıyla da silinir', () async {
      final slow = AccountExportSharer(
        shareFn: (_) async => const ShareResult('', ShareResultStatus.success),
        tempRoot: () async => root,
        cleanupDelay: const Duration(minutes: 2),
      );
      await slow.share(_export());
      final dir = root.listSync().whereType<Directory>().single;
      final elsewhere = await Directory.systemTemp.createTemp('baska_kok_');
      addTearDown(() async {
        if (await elsewhere.exists()) await elsewhere.delete(recursive: true);
      });
      await AccountExportSharer.sweepAll(root: elsewhere, includeLive: true);
      expect(dir.existsSync(), isFalse);
      expect(AccountExportSharer.pendingCleanupCount, 0);
    });

    test('olmayan kök / okunamayan dizin hata fırlatmaz', () async {
      await AccountExportSharer.sweepAll(root: Directory('${root.path}${Platform.pathSeparator}yok'));
    });
  });

  test('yeni (süresi dolmamış) klasör süpürülmez', () async {
    final fresh = await Directory('${root.path}${Platform.pathSeparator}kisisel_veri_yeni').create();
    await sharer((_) async => const ShareResult('', ShareResultStatus.success)).share(_export());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.existsSync(), isTrue);
  });
}
