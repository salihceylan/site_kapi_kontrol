// İkinci tur bağımsız inceleme düzeltmeleri (istemci): toplu yükleme (eski dosya verisi, paylaşım önbelleği yarışı) ve
// belge kitle seçeneğinin ekran okuyucuyla etkinleştirilebilmesi.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_form_fields.dart';

import 'bulk_fakes.dart';

void main() {
  test('10 MB üstü dosya seçilince önceki dosyanın okunmuş verisi yeni adın altında KALMAZ', () async {
    final auth = FakeBulkAuth();
    final api = FakeBulkApi();
    var call = 0;
    final controller = BulkImportController(
      service: BulkService(authService: auth, api: api),
      siteCode: 12,
      delivery: FakeDelivery(),
      parseRunner: inlineParse,
      picker: () async {
        call++;
        if (call == 1) {
          final bytes = utf8Bytes(kPeopleCsv);
          return PickedBulkFile(name: 'A_kucuk.csv', size: bytes.length, readBytes: () async => bytes);
        }
        if (call == 2) {
          return PickedBulkFile(
            name: 'B_dev.xlsx',
            size: SheetLimits.maxXlsxBytes + 1,
            readBytes: () async => Uint8List(0),
          );
        }
        return null; // 3. çağrı: kullanıcı seçiciden vazgeçer
      },
      purgePickerCache: () async {},
    );
    await controller.loadSpec();
    controller.selectKind(ImportKind.people);
    controller.goToFileStep();
    await controller.pickAndParse(); // A
    expect(controller.parsed, isNotNull);
    expect(controller.fileName, 'A_kucuk.csv');

    controller.goToFileStep();
    await controller.pickAndParse(); // B (çok büyük)
    expect(controller.parseError, contains('çok büyük'));
    expect(controller.parsed, isNull, reason: 'A verisi B adıyla görünmemeli');
    expect(controller.mapping, isNull);

    await controller.pickAndParse(); // vazgeç
    expect(controller.parsed, isNull, reason: 'vazgeçmek eski dosya verisini geri getirmemeli');
    expect(controller.fileName, 'B_dev.xlsx');
    controller.dispose();
  });

  test('BulkFileSharer: ilk paylaşımın zamanlayıcısı, daha yeni paylaşım sürerken eklenti önbelleğini SİLMEZ', () async {
    final root = await Directory.systemTemp.createTemp('r17_root_');
    var purges = 0;
    final sharer = BulkFileSharer(
      shareFn: (ShareParams p) async => const ShareResult('', ShareResultStatus.unavailable),
      tempRoot: () async => root,
      cleanupDelay: const Duration(milliseconds: 300),
      useSaveDialog: false,
      useTempFile: true,
      purgeCaches: () async => purges++,
      isWeb: false,
    );
    final file = RenderedFile(
      fileName: 'a.csv',
      mimeType: 'text/csv',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      format: ExportFormat.csv,
    );
    await sharer.deliver(file);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sharer.deliver(file); // ikinci paylaşım: alıcı uygulama hâlâ okuyor sayılır
    await Future<void>.delayed(const Duration(milliseconds: 250)); // ilk zamanlayıcı doldu, ikincisi dolmadı
    expect(BulkFileSharer.pendingCleanupCount, 1);
    expect(purges, 0, reason: 'başka bekleyen silme varken eklenti önbelleği silinmemeli');
    await Future<void>.delayed(const Duration(milliseconds: 500)); // ikinci zamanlayıcı da doldu
    expect(BulkFileSharer.pendingCleanupCount, 0);
    expect(purges, 1, reason: 'son bekleyen silme bitince eklenti önbelleği bir kez temizlenir');
    await root.delete(recursive: true);
  });

  testWidgets('DocumentAudienceOption: anlam ağacında dokunma eylemi var; ekran okuyucu eylemi seçeneği etkinleştirir', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentAudienceOption(
            audience: DocumentAudience.managers,
            selected: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    final data = tester.getSemantics(find.byType(DocumentAudienceOption)).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel(RegExp(DocumentAudience.managers.label)));
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('DocumentAudienceOption: devre dışıyken dokunma eylemi yok', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocumentAudienceOption(audience: DocumentAudience.managers, selected: false, onTap: null),
        ),
      ),
    );
    final data = tester.getSemantics(find.byType(DocumentAudienceOption)).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });
}
