// Toplu yükleme sihirbazı durum makinesi (Platform Faz 2b): önizleme, onay, STALE, idempotans, çift dokunma.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';

import 'bulk_fakes.dart';
import 'bulk_test_support.dart';

class _H {
  _H({
    String? fileName = 'kisiler.csv',
    String csv = kPeopleCsv,
    List<ImportKind> allowedKinds = const <ImportKind>[
      ImportKind.allInOne,
      ImportKind.apartments,
      ImportKind.people,
      ImportKind.vehicles,
    ],
  }) {
    controller = BulkImportController(
      service: BulkService(authService: auth, api: api),
      siteCode: 12,
      siteName: 'Gül Sitesi',
      delivery: delivery,
      parseRunner: inlineParse,
      picker: fakePicker(fileName, utf8Bytes(csv)),
      siteSummaryLoader: () async => '3 blok, 120 daire',
      purgePickerCache: () async => pickerPurges++,
      allowedKinds: allowedKinds,
    );
  }

  int pickerPurges = 0;

  final FakeBulkAuth auth = FakeBulkAuth();
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  late final BulkImportController controller;

  /// Tür seç -> dosya adımı -> dosya seç -> eşleme -> önizleme (hazır).
  Future<void> toPreview({ImportKind kind = ImportKind.people}) async {
    await controller.loadSpec();
    controller.selectKind(kind);
    controller.goToFileStep();
    await controller.pickAndParse();
    await controller.confirmMapping();
  }

  void dispose() => controller.dispose();
}

ApiException _api(int status, String code, {Map<String, dynamic>? payload}) =>
    ApiException(bulkErrorMessage(code) ?? code, statusCode: status, code: code, payload: payload);

ImportPreview _preview({String hash = 'a', int ok = 2, int error = 1}) =>
    ImportPreview.fromJson(previewJson(hash: hash * 64, ok: ok, error: error));

void main() {
  group('şema', () {
    test('başarı: tür kartları açılır, site özeti yüklenir', () async {
      final h = _H();
      await h.controller.loadSpec();
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.spec, isNotNull);
      expect(h.controller.specError, isNull);
      expect(h.controller.siteSummary, '3 blok, 120 daire');
      h.dispose();
    });

    test('hata: şema yok, hata iletisi var (boş durum değil); tekrar deneyince düzelir', () async {
      final h = _H();
      h.api.specError = ApiException('Sunucu yanıt vermedi.', statusCode: 503);
      await h.controller.loadSpec();
      expect(h.controller.spec, isNull);
      expect(h.controller.specError, 'Sunucu yanıt vermedi.');
      expect(h.controller.specLoading, isFalse);
      h.api.specError = null;
      await h.controller.loadSpec();
      expect(h.controller.spec, isNotNull);
      expect(h.controller.specError, isNull);
      h.dispose();
    });

    test('sürüm uyuşmazlığı: «Uygulamayı güncelleyin»', () async {
      final h = _H();
      h.api.spec = ImportSpec.fromJson(specJson(version: 2));
      await h.controller.loadSpec();
      expect(h.controller.spec, isNull);
      expect(h.controller.specError, 'Uygulamayı güncelleyin.');
      h.dispose();
    });

    test('yükleme sürerken ikinci çağrı yok sayılır', () async {
      final h = _H();
      h.api.specGate = Completer<void>();
      final first = h.controller.loadSpec();
      await h.controller.loadSpec();
      h.api.specGate!.complete();
      await first;
      expect(h.api.specCalls, 1);
      h.dispose();
    });
  });

  group('dosya ve eşleme', () {
    test('Türkçe CSV okunur, eşleme tamam, satırlar n ile çıkar', () async {
      final h = _H();
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.controller.goToFileStep();
      expect(h.controller.step, BulkStep.file);
      await h.controller.pickAndParse();
      expect(h.controller.step, BulkStep.mapping);
      expect(h.controller.fileName, 'kisiler.csv');
      expect(h.controller.parsed!.table.encodingNote, 'UTF-8 olarak okundu');
      expect(h.controller.mapping!.canProceed(h.controller.kindSpec!), isTrue);
      await h.controller.confirmMapping();
      expect(h.controller.step, BulkStep.preview);
      expect(h.controller.rows.map((r) => r.n), <int>[2, 3]);
      expect(h.controller.rows.first.cells['giris_tarihi'], '15.03.2021');
      expect(h.api.previewCalls.single.kind, ImportKind.people);
      expect(h.api.previewCalls.single.allowOverwrite, isFalse);
      expect(h.controller.preview, isNotNull);
      h.dispose();
    });

    test('dosya okununca eklentinin önbellekteki kopyası silinir (başarıda da hatada da; vazgeçmede değil)', () async {
      final h = _H();
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.controller.goToFileStep();
      await h.controller.pickAndParse();
      expect(h.pickerPurges, 1);

      final bad = _H(csv: 'a;b\n1;"2\n');
      await bad.controller.loadSpec();
      bad.controller.selectKind(ImportKind.people);
      bad.controller.goToFileStep();
      await bad.controller.pickAndParse();
      expect(bad.pickerPurges, 1, reason: 'bozuk dosya da silinir');

      final cancelled = _H(fileName: null);
      await cancelled.controller.loadSpec();
      cancelled.controller.selectKind(ImportKind.people);
      cancelled.controller.goToFileStep();
      await cancelled.controller.pickAndParse();
      expect(cancelled.pickerPurges, 0, reason: 'seçim yok: silinecek kopya yok');
      h.dispose();
      bad.dispose();
      cancelled.dispose();
    });

    test('bozuk dosya: hata iletisi, adım değişmez, boş durum yok', () async {
      final h = _H(csv: 'a;b\n1;"2\n');
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.controller.goToFileStep();
      await h.controller.pickAndParse();
      expect(h.controller.step, BulkStep.file);
      expect(h.controller.parseError, contains('kapanmamış tırnak'));
      expect(h.controller.parsed, isNull);
      expect(h.controller.parsing, isFalse);
      h.dispose();
    });

    test('vazgeçilen seçim hata değildir', () async {
      final h = _H(fileName: null);
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.controller.goToFileStep();
      await h.controller.pickAndParse();
      expect(h.controller.step, BulkStep.file);
      expect(h.controller.parseError, isNull);
      h.dispose();
    });

    test('seçici hata verirse açık ileti', () async {
      final h = _H();
      final c = BulkImportController(
        service: BulkService(authService: h.auth, api: h.api),
        siteCode: 12,
        parseRunner: inlineParse,
        picker: fakePicker('x.csv', null, error: StateError('izin yok')),
      );
      await c.loadSpec();
      c.selectKind(ImportKind.people);
      c.goToFileStep();
      await c.pickAndParse();
      expect(c.parseError, contains('Dosya seçici açılamadı'));
      c.dispose();
      h.dispose();
    });

    test('çok büyük dosya baytlar okunmadan reddedilir', () async {
      final h = _H();
      var read = false;
      final c2 = BulkImportController(
        service: BulkService(authService: h.auth, api: h.api),
        siteCode: 12,
        parseRunner: inlineParse,
        picker: () async => PickedBigFile(onRead: () => read = true),
      );
      await c2.loadSpec();
      c2.selectKind(ImportKind.people);
      c2.goToFileStep();
      await c2.pickAndParse();
      expect(c2.parseError, contains('çok büyük'));
      expect(read, isFalse);
      c2.dispose();
      h.dispose();
    });

    test('çok sayfalı dosyada sayfa seçtirilir', () async {
      final bytes = handMadeXlsx(
        sheetName: 'Açıklama',
        rows: [row(1, [iCell('A1', 'bilgi')])],
        extraSheets: [
          ('Veri1', [row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Telefon')]), row(2, [iCell('A2', 'Ali'), iCell('B2', '5')])]),
          ('Veri2', [row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Telefon')])]),
        ],
      );
      final h = _H();
      final c = BulkImportController(
        service: BulkService(authService: h.auth, api: h.api),
        siteCode: 12,
        parseRunner: inlineParse,
        picker: fakePicker('k.xlsx', bytes),
      );
      await c.loadSpec();
      c.selectKind(ImportKind.people);
      c.goToFileStep();
      await c.pickAndParse();
      expect(c.step, BulkStep.file);
      expect(c.sheetChoices, <String>['Açıklama', 'Veri1', 'Veri2']);
      await c.chooseSheet('Veri1');
      expect(c.step, BulkStep.mapping);
      expect(c.sheetChoices, isNull);
      expect(c.parsed!.table.sheetName, 'Veri1');
      c.dispose();
      h.dispose();
    });

    test('iptal edilen okuma sonucu yok sayılır', () async {
      final gate = Completer<void>();
      final h = _H();
      final c = BulkImportController(
        service: BulkService(authService: h.auth, api: h.api),
        siteCode: 12,
        parseRunner: (r) async {
          await gate.future;
          return inlineParse(r);
        },
        picker: fakePicker('k.csv', utf8Bytes(kPeopleCsv)),
      );
      await c.loadSpec();
      c.selectKind(ImportKind.people);
      c.goToFileStep();
      final pending = c.pickAndParse();
      await Future<void>.delayed(Duration.zero);
      expect(c.parsing, isTrue);
      c.cancelParse();
      expect(c.parsing, isFalse);
      gate.complete();
      await pending;
      expect(c.step, BulkStep.file, reason: 'iptal edilen okuma eşleme adımına geçirmez');
      expect(c.parsed, isNull);
      c.dispose();
      h.dispose();
    });

    test('seçici açıkken «okunuyor» DEĞİL «seçiliyor»; ikinci çağrı yok sayılır; iptal edilirse seçilen dosya yok sayılır', () async {
      final gate = Completer<void>();
      final h = _H();
      final c = BulkImportController(
        service: BulkService(authService: h.auth, api: h.api),
        siteCode: 12,
        parseRunner: inlineParse,
        picker: fakePicker('k.csv', utf8Bytes(kPeopleCsv), gate: gate),
      );
      await c.loadSpec();
      c.selectKind(ImportKind.people);
      c.goToFileStep();
      final pending = c.pickAndParse();
      await Future<void>.delayed(Duration.zero);
      expect(c.picking, isTrue);
      expect(c.parsing, isFalse);
      expect(c.busy, isTrue);
      await c.pickAndParse();
      c.cancelParse();
      expect(c.picking, isFalse);
      gate.complete();
      await pending;
      expect(c.step, BulkStep.file, reason: 'iptal sonrası gelen seçim sütun adımına geçirmez');
      expect(c.fileName, isNull);
      expect(c.parsed, isNull);
      c.dispose();
      h.dispose();
    });

    test('eşleme: çakışma çözülmeden önizlemeye geçilmez', () async {
      final h = _H(csv: 'Ad Soyad;Telefon;Tel\nAli;1;2\n');
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.controller.goToFileStep();
      await h.controller.pickAndParse();
      expect(h.controller.mapping!.conflicts.keys, <String>['telefon']);
      await h.controller.confirmMapping();
      expect(h.controller.step, BulkStep.mapping);
      expect(h.api.previewCalls, isEmpty);
      h.controller.assign('telefon', 1);
      await h.controller.confirmMapping();
      expect(h.controller.step, BulkStep.preview);
      expect(h.controller.rows.single.cells['telefon'], '1');
      h.dispose();
    });

    test('yalnız başlık içeren dosya: dolu satır yok iletisi', () async {
      final h = _H(csv: 'Ad Soyad;Telefon\n');
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.controller.goToFileStep();
      await h.controller.pickAndParse();
      await h.controller.confirmMapping();
      expect(h.controller.mappingError, contains('dolu satır yok'));
      expect(h.controller.step, BulkStep.mapping);
      h.dispose();
    });
  });

  group('önizleme', () {
    test('hata: önizleme yok, ileti var; tekrar denenince gelir', () async {
      final h = _H();
      h.api.previewError = ApiException('Sunucu yanıt vermedi.', statusCode: 503);
      await h.toPreview();
      expect(h.controller.step, BulkStep.preview);
      expect(h.controller.preview, isNull);
      expect(h.controller.previewError, 'Sunucu yanıt vermedi.');
      expect(h.controller.canCommit, isFalse);
      h.api.previewError = null;
      await h.controller.refreshPreview();
      expect(h.controller.preview, isNotNull);
      expect(h.controller.previewError, isNull);
      h.dispose();
    });

    test('çift dokunma: yenileme sürerken ikinci istek gitmez', () async {
      final h = _H();
      await h.toPreview();
      h.api.previewGate = Completer<void>();
      final first = h.controller.refreshPreview();
      await h.controller.refreshPreview();
      expect(h.api.previewCalls.length, 2, reason: 'ilk önizleme + tek yenileme');
      h.api.previewGate!.complete();
      await first;
      h.dispose();
    });

    test('dolu üzerine yaz anahtarı yalnız dairelerde: önizleme yeniden alınır, onay o sürece kapanır', () async {
      final csv = 'Blok;Daire No;Tip\nA;1;3+1\n';
      final h = _H(csv: csv);
      await h.toPreview(kind: ImportKind.apartments);
      expect(h.controller.allowOverwrite, isFalse);
      h.api.previewGate = Completer<void>();
      h.controller.setAllowOverwrite(true);
      expect(h.controller.previewStale, isTrue);
      expect(h.controller.canCommit, isFalse, reason: 'yeni önizleme gelene kadar onay kapalı');
      h.api.previewGate!.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.previewCalls.last.allowOverwrite, isTrue);
      expect(h.controller.previewStale, isFalse);
      expect(h.controller.canCommit, isTrue);
      h.dispose();
    });

    test('kişilerde allow_overwrite hiç gönderilmez / değiştirilemez', () async {
      final h = _H();
      await h.toPreview();
      final calls = h.api.previewCalls.length;
      h.controller.setAllowOverwrite(true);
      expect(h.controller.allowOverwrite, isFalse);
      expect(h.api.previewCalls.length, calls);
      h.dispose();
    });

    test('katı mod + hatalı satır: onay kapalı ve nedeni söylenir', () async {
      final h = _H();
      await h.toPreview();
      expect(h.controller.canCommit, isTrue);
      h.controller.setStrict(true);
      expect(h.controller.canCommit, isFalse);
      expect(h.controller.commitBlockedReason, contains('hiçbirini aktarma'));
      h.dispose();
    });

    test('aktarılacak geçerli satır yoksa onay kapalı', () async {
      final h = _H();
      h.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(previewJson(ok: 0, error: 2, unchanged: 0));
      await h.toPreview();
      expect(h.controller.commitBlockedReason, 'Aktarılacak geçerli satır yok.');
      h.dispose();
    });
  });

  group('onay', () {
    test('başarı: gövde, anahtar, sonuç adımı; anahtar başarıdan sonra atılır', () async {
      final h = _H();
      await h.toPreview();
      await h.controller.commit(acknowledged: true);
      final call = h.api.commitCalls.single;
      expect(call.expectedHash, kTestHash);
      expect(call.acknowledged, isTrue);
      expect(call.strict, isFalse);
      expect(call.key, matches(RegExp(r'^imp-[0-9a-f]{24}$')));
      expect(h.controller.step, BulkStep.result);
      expect(h.controller.result!.applied, 2);
      expect(h.controller.dataChanged, isTrue);
      expect(h.controller.completedKinds, contains(ImportKind.people));

      // Aynı dosya yeniden yüklenince YENİ anahtar (önceki başarıyla bitti).
      h.controller.startNext(ImportKind.people);
      h.controller.goToFileStep();
      await h.controller.pickAndParse();
      await h.controller.confirmMapping();
      await h.controller.commit(acknowledged: true);
      expect(h.api.commitCalls.length, 2);
      expect(h.api.commitCalls[1].key, isNot(h.api.commitCalls[0].key));
      h.dispose();
    });

    test('KVKK onayı olmadan kişi / araç yüklemesi gönderilmez; daire için gerekmez', () async {
      final h = _H();
      await h.toPreview();
      await h.controller.commit(acknowledged: false);
      expect(h.api.commitCalls, isEmpty);

      final g = _H(csv: 'Blok;Daire No;Tip\nA;1;3+1\n');
      await g.toPreview(kind: ImportKind.apartments);
      await g.controller.commit(acknowledged: false);
      expect(g.api.commitCalls.length, 1);
      expect(g.api.commitCalls.single.acknowledged, isFalse);
      h.dispose();
      g.dispose();
    });

    test('çift dokunma: onay sürerken ikinci istek gitmez (tek kayıt)', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitGate = Completer<void>();
      final first = h.controller.commit(acknowledged: true);
      await h.controller.commit(acknowledged: true);
      await h.controller.commit(acknowledged: true);
      expect(h.api.commitCalls.length, 1);
      expect(h.controller.committing, isTrue);
      h.api.commitGate!.complete();
      await first;
      expect(h.api.commitCalls.length, 1);
      h.dispose();
    });

    test('yanıt kaybı (ağ hatası): belirsiz sonuç iletisi, AYNI anahtarla yeniden deneme', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitScript.add(ApiException('Sunucuya bağlanılamadı.'));
      await h.controller.commit(acknowledged: true);
      expect(h.controller.step, BulkStep.preview);
      expect(h.controller.commitError, contains('çift kayıt oluşmaz'));
      expect(h.controller.commitRetryable, isTrue);
      expect(h.controller.dataChanged, isTrue, reason: 'sonuç belirsiz: liste tazelenmeli');
      await h.controller.retryCommit();
      expect(h.api.commitCalls.length, 2);
      expect(h.api.commitCalls[1].key, h.api.commitCalls[0].key);
      expect(h.controller.step, BulkStep.result);
      h.dispose();
    });

    test('IMPORT_IN_PROGRESS / SITE_BUSY: yeniden dene açılır, anahtar korunur', () async {
      for (final code in <String>['IMPORT_IN_PROGRESS', 'SITE_BUSY']) {
        final h = _H();
        await h.toPreview();
        h.api.commitScript.add(_api(409, code));
        await h.controller.commit(acknowledged: true);
        expect(h.controller.commitError, bulkErrorMessage(code));
        expect(h.controller.commitRetryable, isTrue, reason: code);
        expect(h.controller.step, BulkStep.preview);
        await h.controller.retryCommit();
        expect(h.api.commitCalls[1].key, h.api.commitCalls[0].key);
        h.dispose();
      }
    });

    test('IDEMPOTENCY_CONFLICT: anahtar atılır, yeniden dene yok', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitScript.add(_api(409, 'IDEMPOTENCY_CONFLICT'));
      await h.controller.commit(acknowledged: true);
      expect(h.controller.commitRetryable, isFalse);
      await h.controller.commit(acknowledged: true);
      expect(h.api.commitCalls[1].key, isNot(h.api.commitCalls[0].key));
      h.dispose();
    });

    test('IMPORT_HAS_ERRORS: ileti, adım değişmez', () async {
      final h = _H();
      await h.toPreview();
      h.controller.setStrict(true);
      h.api.previewBuilder = (k, r, o) => ImportPreview.fromJson(previewJson(error: 0, warnings: 0));
      await h.controller.refreshPreview();
      h.api.commitScript.add(_api(409, 'IMPORT_HAS_ERRORS'));
      await h.controller.commit(acknowledged: true);
      expect(h.controller.commitError, 'Hatalı satırlar var. Düzeltip yeniden yükleyin.');
      expect(h.controller.commitRetryable, isFalse);
      h.dispose();
    });

    test('429: kilit, yeniden dene açık', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitScript.add(ApiException('Çok fazla istek gönderildi.', statusCode: 429, retryAfterSeconds: 30));
      await h.controller.commit(acknowledged: true);
      expect(h.controller.retryLocked, isTrue);
      expect(h.controller.canCommit, isFalse);
      expect(h.controller.commitError, contains('sonra tekrar deneyin'));
      h.dispose();
    });

    test('PREVIEW_STALE: önizleme otomatik yenilenir, bildirim yazılır, onay yeni özetle yapılır', () async {
      final h = _H();
      await h.toPreview();
      expect(h.controller.preview!.previewHash, kTestHash);
      h.api.commitScript.add(_api(409, 'PREVIEW_STALE'));
      h.api.previewScript.add(_preview(hash: 'b', ok: 1, error: 2));
      await h.controller.commit(acknowledged: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(h.api.previewCalls.length, 2, reason: 'otomatik yenileme');
      expect(h.controller.preview!.previewHash, 'b' * 64);
      expect(h.controller.previewStale, isFalse);
      expect(h.controller.staleNotice, contains('Veriler siz bakarken değişti'));
      expect(h.controller.staleNotice, contains('1'));
      expect(h.controller.step, BulkStep.preview);
      await h.controller.commit(acknowledged: true);
      expect(h.api.commitCalls[1].expectedHash, 'b' * 64);
      expect(h.controller.step, BulkStep.result);
      h.dispose();
    });

    test('PREVIEW_STALE: yenileme sürerken ve BAŞARISIZ olunca eski önizlemeyle onay KAPALI', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitScript.add(_api(409, 'PREVIEW_STALE'));
      h.api.previewGate = Completer<void>();
      h.api.previewScript.add(ApiException('Sunucu yanıt vermedi.', statusCode: 503));
      await h.controller.commit(acknowledged: true);
      expect(h.controller.previewing, isTrue);
      expect(h.controller.canCommit, isFalse);
      await h.controller.commit(acknowledged: true);
      expect(h.api.commitCalls.length, 1, reason: 'yenileme sürerken onay gitmez');
      h.api.previewGate!.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.previewStale, isTrue);
      expect(h.controller.previewError, contains('Önizleme yenilenemedi'));
      expect(h.controller.canCommit, isFalse);
      expect(h.controller.commitBlockedReason, contains('Önizlemeyi Yenile'));
      // Elle yenileme.
      h.api.previewGate = null;
      await h.controller.refreshPreview();
      expect(h.controller.previewStale, isFalse);
      expect(h.controller.canCommit, isTrue);
      h.dispose();
    });

    test('replay (200): sonuç «daha önce tamamlanmıştı» için işaretlenir, rapor önizlemeden gelir', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitScript.add(ImportResult.fromJson(commitJson(replayed: true, withIssues: false)));
      await h.controller.commit(acknowledged: true);
      expect(h.controller.result!.replayed, isTrue);
      expect(h.controller.result!.issues, isNull);
      expect(h.controller.reportIssues.length, 2, reason: 'ayrıntı yoksa önizlemedeki sorunlar kullanılır');
      h.dispose();
    });
  });

  group('şablon ve rapor', () {
    test('şablon: daire zarfı alınır, XLSX üretilir ve teslim edilir', () async {
      final h = _H();
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      final outcome = await h.controller.downloadTemplate(ExportFormat.xlsx);
      expect(outcome, ExportShareOutcome.shared);
      expect(h.api.exportCalls.single.kind, 'apartments');
      expect(h.delivery.files.single.fileName, 'toplu_yukleme_sablonu.xlsx');
      expect(h.controller.templateMessage, contains('Şablon hazır'));
      expect(h.controller.templateBusy, isFalse);
      h.dispose();
    });

    test('daire zarfı alınamazsa şablon yine üretilir ve dürüst not düşülür', () async {
      final h = _H();
      h.api.exportError = ApiException('x', statusCode: 503);
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.apartments);
      await h.controller.downloadTemplate(ExportFormat.csv);
      expect(h.delivery.files.single.fileName, 'toplu_yukleme_sablonu_daireler.csv');
      expect(h.controller.templateMessage, contains('alınamadığı için'));
      h.dispose();
    });

    test('CSV kişi şablonu daire zarfı İSTEMEZ', () async {
      final h = _H();
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      await h.controller.downloadTemplate(ExportFormat.csv);
      expect(h.api.exportCalls, isEmpty);
      h.dispose();
    });

    test('teslim hatası: ileti, kilit açılır; kullanıcı vazgeçerse bilgi', () async {
      final h = _H();
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.delivery.error = StateError('disk dolu');
      await h.controller.downloadTemplate(ExportFormat.xlsx);
      expect(h.controller.templateError, contains('Şablon hazırlanamadı'));
      expect(h.controller.templateBusy, isFalse);
      h.delivery.error = null;
      h.delivery.outcome = ExportShareOutcome.dismissed;
      await h.controller.downloadTemplate(ExportFormat.xlsx);
      expect(h.controller.templateMessage, 'Şablon kaydedilmedi.');
      h.dispose();
    });

    test('çift dokunma: şablon hazırlanırken ikinci istek yok', () async {
      final h = _H();
      await h.controller.loadSpec();
      h.controller.selectKind(ImportKind.people);
      h.delivery.gate = Completer<void>();
      final first = h.controller.downloadTemplate(ExportFormat.xlsx);
      await h.controller.downloadTemplate(ExportFormat.xlsx);
      await Future<void>.delayed(Duration.zero);
      h.delivery.gate!.complete();
      await first;
      expect(h.delivery.files.length, 1);
      h.dispose();
    });

    test('hata raporu: önizleme sorunlarından CSV üretilir', () async {
      final h = _H();
      await h.toPreview();
      await h.controller.downloadReport();
      expect(h.delivery.files.single.fileName, startsWith('hata_raporu_people_'));
      expect(h.controller.reportMessage, contains('Rapor hazır'));
      h.dispose();
    });
  });

  group('gezinme', () {
    test('geri: önizleme -> eşleme -> dosya -> tür', () async {
      final h = _H();
      await h.toPreview();
      expect(h.controller.hasProgress, isTrue);
      expect(h.controller.back(), isTrue);
      expect(h.controller.step, BulkStep.mapping);
      expect(h.controller.back(), isTrue);
      expect(h.controller.step, BulkStep.file);
      expect(h.controller.parsed, isNotNull, reason: 'okunmuş dosya geri dönüşte kaybolmaz');
      expect(h.controller.mapping, isNotNull);
      expect(h.controller.back(), isTrue);
      expect(h.controller.step, BulkStep.kind);
      expect(h.controller.hasProgress, isTrue);
      expect(h.controller.back(), isFalse);
      // Farklı tür seçilince dosya atılır.
      h.controller.selectKind(ImportKind.vehicles);
      expect(h.controller.parsed, isNull);
      expect(h.controller.rows, isEmpty);
      expect(h.controller.hasProgress, isFalse);
      h.dispose();
    });

    test('onay sürerken geri alınamaz', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitGate = Completer<void>();
      final pending = h.controller.commit(acknowledged: true);
      expect(h.controller.back(), isTrue);
      expect(h.controller.step, BulkStep.preview, reason: 'onay sürerken adım değişmez');
      h.api.commitGate!.complete();
      await pending;
      h.dispose();
    });

    test('«Sıradakini yükle»: tamamlanan tür atlanır, durum sıfırlanır', () async {
      final h = _H();
      await h.toPreview();
      await h.controller.commit(acknowledged: true);
      expect(h.controller.suggestedNextKind, ImportKind.apartments);
      h.controller.startNext(h.controller.suggestedNextKind);
      expect(h.controller.step, BulkStep.kind);
      expect(h.controller.kind, ImportKind.apartments);
      expect(h.controller.result, isNull);
      expect(h.controller.preview, isNull);
      expect(h.controller.rows, isEmpty);
      expect(h.controller.completedKinds, contains(ImportKind.people));
      h.dispose();
    });

    test('dispose sonrası gelen yanıt hata vermez', () async {
      final h = _H();
      await h.toPreview();
      h.api.commitGate = Completer<void>();
      final pending = h.controller.commit(acknowledged: true);
      h.controller.dispose();
      h.api.commitGate!.complete();
      await pending;
      expect(h.api.commitCalls.length, 1);
    });
  });
}

/// Baytları okunmaması gereken 20 MB'lık sahte dosya.
class PickedBigFile extends PickedBulkFile {
  PickedBigFile({required void Function() onRead})
    : super(
        name: 'dev.xlsx',
        size: 20 * 1024 * 1024,
        readBytes: () async {
          onRead();
          return Uint8List(0);
        },
      );
}
