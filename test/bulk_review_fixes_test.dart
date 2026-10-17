// Bağımsız inceleme (R12) düzeltmeleri: XLSX paylaşılan dize bellek çoğaltması (P2-4), bozuk satır numaraları (P2-7),
// önbelleksiz formül hücreleri (P2-8), gövde boyutu ön denetimi (P2-10).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';

import 'bulk_fakes.dart';
import 'bulk_test_support.dart';

SheetTable _read(Uint8List bytes) {
  final reader = XlsxReader.open(bytes);
  return reader.readSheet(reader.sheets.first);
}

void main() {
  group('P2-4: paylaşılan dizeler bir kez kırpılır ve nesne paylaşılır', () {
    test('aynı dizeye başvuran hücreler AYNI String nesnesidir; uzun dize 601 karaktere kesilir', () {
      final long = 'Ş' * 700;
      final bytes = handMadeXlsx(
        sharedStrings: sharedStringsOf(<String>[long, '  kısa  ', '   ']),
        rows: [
          row(1, [sCell('A1', 0), sCell('B1', 0), sCell('C1', 1), sCell('D1', 2)]),
          row(2, [sCell('A2', 0), sCell('B2', 0), sCell('C2', 1)]),
        ],
      );
      final t = _read(bytes);
      final a1 = t.rows[0].cells[0]! as String;
      final b1 = t.rows[0].cells[1]! as String;
      final a2 = t.rows[1].cells[0]! as String;
      expect(a1.length, SheetLimits.cellTextCap);
      expect(identical(a1, b1), isTrue, reason: 'her başvuruda yeni kopya üretilmez');
      expect(identical(a1, a2), isTrue);
      expect(t.rows[0].cells[2], 'kısa');
      expect(t.rows[0].cells.length, 3, reason: 'yalnız boşluktan oluşan dize boş hücredir');
    });

    test('1000 farklı uzun dizeye 5000 satır x 38 hücre rastgele başvuru 2 sn altında okunur (PoC shared_amp2 yeniden kuruldu)', () {
      final strings = <String>[
        for (var i = 0; i < 1000; i++) List<String>.generate(60, (j) => 'şehir$i-$j').join(' '),
      ];
      final sb = StringBuffer();
      sb.write(row(1, [sCell('A1', 0), sCell('B1', 1)]));
      for (var r = 2; r <= 5010; r++) {
        final cells = <String>[];
        for (var c = 2; c < 40; c++) {
          final col = c < 26 ? String.fromCharCode(65 + c) : 'A${String.fromCharCode(65 + c - 26)}';
          cells.add(sCell('$col$r', 2 + (r * 31 + c * 7) % 998));
        }
        sb.write(row(r, cells));
      }
      final bytes = handMadeXlsx(
        sharedStrings: sharedStringsOf(<String>['Blok', 'Daire No', ...strings]),
        rows: sb.toString(),
      );
      final (ms, t) = bestOfMillis(() => _read(bytes));
      expect(t.rows.length, greaterThan(5000));
      expect(ms, lessThan(2000), reason: '$ms ms');
    });
  });

  group('P2-7: satır numaraları artan ve tekil olmalı (sunucu aksi halde tüm isteği 400 yapar)', () {
    test('sırasız / yinelenen satır açık Türkçe iletiyle reddedilir', () {
      final bad = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'Blok'), iCell('B1', 'Daire No')]),
          row(5, [iCell('A5', 'A'), iCell('B5', '1')]),
          row(3, [iCell('A3', 'A'), iCell('B3', '2')]),
        ],
      );
      expect(
        () => _read(bad),
        throwsA(isA<SpreadsheetException>().having((e) => e.message, 'ileti', contains('satır numaraları bozuk'))),
      );
      final dup = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'Blok')]),
          row(3, [iCell('A3', 'A')]),
          row(3, [iCell('A3', 'B')]),
        ],
      );
      expect(() => _read(dup), throwsA(isA<SpreadsheetException>()));
      final outcome = runParse(
        ParseRequest(bytes: bad, fileName: 'x.xlsx', kind: ImportKind.apartments, spec: testSpec()),
      );
      expect(outcome, isA<ParseFailed>());
      expect((outcome as ParseFailed).message, contains('Farklı Kaydet'));
    });

    test('boş satırlar sırayı bozmaz; artan boşluklu numaralar geçerlidir', () {
      final ok = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'a')]),
          row(2, []),
          row(2, []),
          row(7, [iCell('A7', 'b')]),
        ],
      );
      expect(_read(ok).rows.map((r) => r.n), <int>[1, 7]);
    });

    test('satır dışı hücre (bozuk dosya) çökmez', () {
      final stray = handMadeXlsx(rows: '<c r="A1" t="inlineStr"><is><t>x</t></is></c>${row(2, [iCell('A2', 'y')])}');
      expect(_read(stray).rows.single.cells.single, 'y');
    });
  });

  group('P2-8: sonucu kayıtlı olmayan formül hücreleri sayılır', () {
    test('yalnız <f> olan hücre sayılır; <v> olan, hata sonuçlu ve boş dize sonuçlu sayılmaz', () {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'Blok'), iCell('B1', 'Daire No')]),
          row(2, [iCell('A2', 'A'), '<c r="B2"><f>ROW()-1</f></c>']),
          row(3, [iCell('A3', 'A'), '<c r="B3"><f>ROW()-1</f></c>']),
          row(4, [iCell('A4', 'A'), '<c r="B4"><f>ROW()-1</f><v>3</v></c>']),
          row(5, [iCell('A5', 'A'), '<c r="B5" t="e"><f>1/0</f><v>#DIV/0!</v></c>']),
          row(6, [iCell('A6', 'A'), '<c r="B6" t="str"><f>""</f><v></v></c>']),
          row(7, [iCell('A7', 'A'), '<c r="B7"><f t="shared" si="0"/><v>7</v></c>']),
          row(8, [iCell('A8', 'A'), '<c r="B8"><f t="shared" si="0"/></c>']),
        ],
      );
      final t = _read(bytes);
      expect(t.uncachedFormulaColumns, <int, int>{1: 3}, reason: 'B2, B3 ve B8');
    });

    test('hat: eşlenen sütundaki sayı denetleyiciden okunur (eşlenmeyen sütun sayılmaz)', () async {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'Blok'), iCell('B1', 'Daire No'), iCell('C1', 'Bilinmeyen')]),
          row(2, [iCell('A2', 'A'), '<c r="B2"><f>ROW()-1</f></c>', '<c r="C2"><f>1+1</f></c>']),
          row(3, [iCell('A3', 'A'), '<c r="B3"><f>ROW()-1</f></c>', '<c r="C3"><f>1+1</f></c>']),
        ],
      );
      final auth = FakeBulkAuth();
      final api = FakeBulkApi();
      final c = BulkImportController(
        service: BulkService(authService: auth, api: api),
        siteCode: 1,
        parseRunner: inlineParse,
        picker: fakePicker('d.xlsx', bytes),
        purgePickerCache: () async {},
      );
      await c.loadSpec();
      c.selectKind(ImportKind.apartments);
      c.goToFileStep();
      await c.pickAndParse();
      expect(c.step, BulkStep.mapping);
      expect(c.uncachedFormulaCells, 2, reason: 'yalnız eşlenen «Daire No» sütunu');
      c.dispose();
    });
  });

  group('P2-10: gövde boyutu gönderilmeden denetlenir', () {
    test('max_body_bytes aşılırsa önizleme İSTENMEZ ve açık ileti verilir', () async {
      final auth = FakeBulkAuth();
      final api = FakeBulkApi();
      final json = specJson()..['max_body_bytes'] = 2000;
      api.spec = ImportSpec.fromJson(json);
      final sb = StringBuffer('Ad Soyad;Telefon\n');
      for (var i = 0; i < 200; i++) {
        sb.write('Kişi numarası $i;0555 123 45 67\n');
      }
      final c = BulkImportController(
        service: BulkService(authService: auth, api: api),
        siteCode: 1,
        parseRunner: inlineParse,
        picker: fakePicker('k.csv', Uint8List.fromList(utf8.encode(sb.toString()))),
        purgePickerCache: () async {},
      );
      await c.loadSpec();
      c.selectKind(ImportKind.people);
      c.goToFileStep();
      await c.pickAndParse();
      await c.confirmMapping();
      expect(c.step, BulkStep.mapping, reason: 'önizlemeye geçilmez');
      expect(api.previewCalls, isEmpty);
      expect(c.mappingError, contains('gönderilemeyecek kadar büyük'));
      expect(c.mappingError, contains('parça'));
      c.dispose();
    });

    test('sınır içindeki dosya etkilenmez', () async {
      final auth = FakeBulkAuth();
      final api = FakeBulkApi();
      final c = BulkImportController(
        service: BulkService(authService: auth, api: api),
        siteCode: 1,
        parseRunner: inlineParse,
        picker: fakePicker('k.csv', utf8Bytes(kPeopleCsv)),
        purgePickerCache: () async {},
      );
      await c.loadSpec();
      c.selectKind(ImportKind.people);
      c.goToFileStep();
      await c.pickAndParse();
      await c.confirmMapping();
      expect(c.step, BulkStep.preview);
      expect(api.previewCalls.length, 1);
      c.dispose();
    });
  });
}
