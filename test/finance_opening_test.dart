// Devir bakiyesi (F4) ve hepsi bir arada (N6) istemci tarafı: tür özellikleri, seçenekler, onay toplamı, şablon, modeller.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/finance_opening.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';

import 'bulk_fakes.dart';
import 'bulk_test_support.dart';

Map<String, dynamic> _col(String key, String label, {bool required = false}) => <String, dynamic>{
  'key': key,
  'label': label,
  'required': required,
  'type': 'text',
  'aliases': <String>[],
};

ImportSpec _specWithNewKinds() {
  final json = specJson();
  final kinds = Map<String, dynamic>.from(json['kinds'] as Map);
  kinds['opening_balances'] = <String, dynamic>{
    'columns': <Map<String, dynamic>>[
      _col('blok', 'Blok', required: true),
      _col('daire_no', 'Daire No', required: true),
      _col('tutar', 'Tutar', required: true),
    ],
  };
  kinds['all_in_one'] = <String, dynamic>{
    'columns': <Map<String, dynamic>>[
      _col('blok', 'Blok', required: true),
      _col('daire_no', 'Daire No', required: true),
      _col('ad_soyad', 'Ad Soyad'),
    ],
  };
  json['kinds'] = kinds;
  return ImportSpec.fromJson(json);
}

const String _openingCsv = 'Blok;Daire No;Tutar\r\nA;1;1.250,50\r\nA;2;300\r\n';

void main() {
  group('tür özellikleri', () {
    test('ayrıştırma ve bayraklar', () {
      expect(ImportKind.tryParse('all_in_one'), ImportKind.allInOne);
      expect(ImportKind.tryParse('opening_balances'), ImportKind.openingBalances);
      expect(ImportKind.openingBalances.needsAcknowledgement, isFalse);
      expect(ImportKind.allInOne.needsAcknowledgement, isTrue);
      expect(ImportKind.allInOne.supportsOverwrite, isTrue);
      expect(ImportKind.openingBalances.supportsOverwrite, isFalse);
      expect(ImportKind.openingBalances.isOpening, isTrue);
    });

    test('çipler yeni türlerde anlamlı', () {
      final opening = ImportPreview.fromJson(
        previewJson(kind: 'opening_balances', plan: <String, dynamic>{'opening_add': 2, 'total_minor': 155050}),
      );
      expect(opening.chips().first.label, 'Yazılacak');
      expect(opening.chips().first.count, 2);
      expect(opening.plan['total_minor'], 155050);
      final aio = ImportPreview.fromJson(previewJson(kind: 'all_in_one', plan: <String, dynamic>{'people_create': 3}));
      expect(aio.chips().first.count, 3);
    });
  });

  group('denetleyici: devir bakiyesi', () {
    test('önizleme devir tarihini, onay toplam tutarı gönderir; hatalı satırda aktarma varsayılan açık', () async {
      final auth = FakeBulkAuth();
      final api = FakeBulkApi()..spec = _specWithNewKinds();
      api.previewBuilder = (kind, rows, allowOverwrite) => ImportPreview.fromJson(
        previewJson(
          kind: kind.apiValue,
          rows: rows.length,
          plan: <String, dynamic>{'opening_add': 2, 'total_minor': 155050},
        ),
      );
      final c = BulkImportController(
        service: BulkService(authService: auth, api: api),
        siteCode: 12,
        parseRunner: inlineParse,
        picker: fakePicker('devir.csv', Uint8List.fromList(utf8Bytes(_openingCsv))),
        allowedKinds: kOpeningImportKinds,
      );
      await c.loadSpec();
      c.selectKind(ImportKind.openingBalances);
      expect(c.strict, isTrue);
      c.setCutoverDate('2026-10-01');
      c.goToFileStep();
      await c.pickAndParse();
      await c.confirmMapping();
      expect(api.lastPreviewOptions, <String, Object?>{'cutover_date': '2026-10-01'});
      expect(c.openingTotalMinor, 155050);
      await c.commit(acknowledged: true);
      expect(api.lastCommitOptions, <String, Object?>{'cutover_date': '2026-10-01', 'expected_total_minor': 155050});
      expect(api.commitCalls.single.kind, ImportKind.openingBalances);
      expect(c.suggestedNextKind, isNull);
      c.dispose();
    });
  });

  group('şablon', () {
    test('devir ve hepsi bir arada ayrı dosyadır; klasik kitapta yoktur', () {
      final spec = _specWithNewKinds();
      final opening = buildImportTemplate(spec: spec, kind: ImportKind.openingBalances, format: ExportFormat.csv);
      expect(opening.fileName, contains('devir_bakiyesi'));
      final aio = buildImportTemplate(spec: spec, kind: ImportKind.allInOne, format: ExportFormat.csv);
      expect(aio.fileName, contains('hepsi_bir_arada'));
      final classic = buildImportTemplate(spec: spec, kind: ImportKind.people, format: ExportFormat.xlsx);
      expect(classic.fileName, endsWith('.xlsx'));
    });
  });

  group('modeller', () {
    test('devir yüklemesi ve geri alma önizlemesi çözülür', () {
      final run = OpeningRun.fromJson(<String, dynamic>{
        'id': 7,
        'created_at': '2026-10-21T10:00:00.000Z',
        'cutover_date': '2026-10-01',
        'entry_count': 2,
        'total_minor': 155050,
        'reverted': false,
      });
      expect(run.id, 7);
      expect(run.totalMinor, 155050);
      final detail = OpeningRevertPreview.fromJson(<String, dynamic>{
        'run': <String, dynamic>{'id': 7, 'entry_count': 2, 'total_minor': 155050},
        'revert': <String, dynamic>{
          'entries_to_reverse': 2,
          'total_minor': 155050,
          'individually_cancelled': 1,
          'apartments_with_later_payments': 1,
          'late_fee_entries_after': 0,
        },
      });
      expect(detail.entriesToReverse, 2);
      expect(detail.apartmentsWithLaterPayments, 1);
      expect(() => OpeningRevertPreview.fromJson(<String, dynamic>{}), throwsFormatException);
    });
  });
}
