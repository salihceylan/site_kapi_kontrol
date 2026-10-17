// Toplu yükleme: XLSX okuyucu / yazıcı (Platform Faz 2b).
//
// Fixture'lar kod içinde kurulur (Excel 365 TR, LibreOffice, Google E-Tablolar, Numbers'ın yazdığı biçimleri
// taklit eden elle yazılmış parçalar). Kötü niyetli / bozuk dosyalar HIZLI (2 sn altı) ve açık iletiyle reddedilir.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';

import 'bulk_test_support.dart';

SheetTable _read(Uint8List bytes, {String? sheet}) {
  final reader = XlsxReader.open(bytes);
  final ref = sheet == null ? reader.sheets.first : reader.sheets.firstWhere((s) => s.name == sheet);
  return reader.readSheet(ref);
}

List<List<Object?>> _grid(SheetTable t) => <List<Object?>>[for (final r in t.rows) r.cells];

Matcher _fails(String part, {String? code}) => throwsA(
  isA<SpreadsheetException>()
      .having((e) => e.message, 'ileti', contains(part))
      .having((e) => e.code, 'kod', code ?? isNotEmpty),
);

void main() {
  group('okuyucu: üretici biçimleri', () {
    test('Excel 365 TR: paylaşılan metinler, sayılar, tarih ve ondalık', () {
      final bytes = handMadeXlsx(
        sharedStrings: sharedStringsOf(<String>['Ad Soyad', 'Giriş Tarihi', 'Brüt m²', 'Çağlar Öztürk']),
        styles: dateStyles,
        rows: [
          row(1, [sCell('A1', 0), sCell('B1', 1), sCell('C1', 2)]),
          row(2, [sCell('A2', 3), nCell('B2', 44270, style: 1), nCell('C2', 125.5, style: 2)]),
          row(3, [sCell('A3', 3), nCell('B3', 44271, style: 3), nCell('C3', 100)]),
        ],
      );
      final t = _read(bytes);
      expect(t.rows[0].cells, <Object?>['Ad Soyad', 'Giriş Tarihi', 'Brüt m²']);
      expect(t.rows[1].cells[0], 'Çağlar Öztürk');
      expect(t.rows[1].cells[1], const SheetDateCell(44270));
      expect(t.rows[1].cells[2], 125.5);
      // Yerleşik 14 numaralı biçim de tarih sayılır; tamsayı değer int olur.
      expect(t.rows[2].cells[1], const SheetDateCell(44271));
      expect(t.rows[2].cells[2], 100);
      expect(t.rows[2].cells[2], isA<int>());
    });

    test('LibreOffice / Google: satır içi (inlineStr) metin ve zengin metin', () {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'Ad'), '<c r="B1" t="inlineStr"><is><r><t>Tel</t></r><r><t>efon</t></r></is></c>']),
          row(2, [iCell('A2', 'Ali'), iCell('B2', '0 (555) 123 45 67')]),
        ],
      );
      final t = _read(bytes);
      expect(t.rows[0].cells, <Object?>['Ad', 'Telefon']);
      expect(t.rows[1].cells, <Object?>['Ali', '0 (555) 123 45 67']);
    });

    test('zengin metin paylaşılan dizge: parçalar birleşir, fonetik (rPh) atılır', () {
      final bytes = handMadeXlsx(
        sharedStrings:
            '<si><r><t>Ahmet </t></r><r><rPr><b/></rPr><t>Yılmaz</t></r><rPh sb="0" eb="1"><t>fonetik</t></rPh></si>',
        rows: [
          row(1, [sCell('A1', 0)]),
        ],
      );
      expect(_read(bytes).rows.first.cells, <Object?>['Ahmet Yılmaz']);
    });

    test('Numbers: önekli XML adları (x:) ve self-closing hücreler', () {
      final sheet =
          '<x:row r="1"><x:c r="A1" t="inlineStr"><x:is><x:t>Ad</x:t></x:is></x:c><x:c r="B1"/></x:row>'
          '<x:row r="2"><x:c r="A2" t="inlineStr"><x:is><x:t>Ali</x:t></x:is></x:c></x:row>';
      final bytes = zipOf(<String, String>{
        '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
        'xl/workbook.xml':
            '<x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<x:sheets><x:sheet name="Tablo 1" sheetId="1" r:id="rId9"/></x:sheets></x:workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            'Target="/xl/worksheets/sheet1.xml"/></Relationships>',
        'xl/worksheets/sheet1.xml':
            '<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheetData>$sheet</x:sheetData></x:worksheet>',
      });
      final t = _read(bytes);
      expect(_grid(t), <List<Object?>>[
        <Object?>['Ad'],
        <Object?>['Ali'],
      ]);
    });

    test('formül hücresi: ÖNBELLEKLİ sonuç okunur, formül hiç hesaplanmaz', () {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'Toplam'), iCell('B1', 'Ad')]),
          row(2, [
            '<c r="A2"><f>SUM(1,2)*1000</f><v>3000</v></c>',
            '<c r="B2" t="str"><f>"x"&amp;"y"</f><v>xy</v></c>',
          ]),
          // Önbelleksiz formül: değer yok -> boş.
          row(3, ['<c r="A3"><f>1+1</f></c>', iCell('B3', 'son')]),
        ],
      );
      final t = _read(bytes);
      expect(t.rows[1].cells, <Object?>[3000, 'xy']);
      expect(t.rows[2].cells, <Object?>[null, 'son']);
    });

    test('formül öneki taşıyan METİN olduğu gibi okunur (sunucu FORMULA_LIKE der)', () {
      final bytes = handMadeXlsx(
        sharedStrings: sharedStringsOf(<String>['=cmd|\' /C calc\'!A0', '+1+1', '@SUM(A1)', '-2+3']),
        rows: [
          row(1, [sCell('A1', 0), sCell('B1', 1), sCell('C1', 2), sCell('D1', 3)]),
        ],
      );
      expect(_read(bytes).rows.first.cells, <Object?>["=cmd|' /C calc'!A0", '+1+1', '@SUM(A1)', '-2+3']);
    });

    test('mantıksal ve hata hücreleri; tarih (t="d") hücresi', () {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [
            '<c r="A1" t="b"><v>1</v></c>',
            '<c r="B1" t="b"><v>0</v></c>',
            '<c r="C1" t="e"><v>#DIV/0!</v></c>',
            '<c r="D1" t="d"><v>2021-03-15T00:00:00</v></c>',
          ]),
        ],
      );
      expect(_read(bytes).rows.first.cells, <Object?>['DOĞRU', 'YANLIŞ', null, '2021-03-15']);
    });

    test('1904 tarih sistemi bayrağı hücreye işlenir', () {
      final bytes = handMadeXlsx(
        date1904: true,
        styles: dateStyles,
        rows: [
          row(1, [nCell('A1', 41000, style: 1)]),
        ],
      );
      expect(_read(bytes).rows.first.cells.first, const SheetDateCell(41000, date1904: true));
    });

    test('sütun harfleri (AA), boşluklu hücreler ve boş satırlar; numaralar korunur', () {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [iCell('A1', 'a'), iCell('C1', 'c')]),
          row(2, []),
          row(5, [iCell('B5', 'b')]),
          '<row r="7"/>',
          row(9, [iCell('AA9', 'aa')]),
        ],
      );
      final t = _read(bytes);
      expect(t.rows.map((r) => r.n), <int>[1, 5, 9]);
      expect(t.rows[0].cells, <Object?>['a', null, 'c']);
      expect(t.rows[1].cells, <Object?>[null, 'b']);
      expect(t.rows[2].cells.length, 27);
      expect(t.rows[2].cells[26], 'aa');
    });

    test('birleşik hücre: yalnız sol üst hücre değer taşır', () {
      final bytes = zipOf(<String, String>{
        'xl/workbook.xml':
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            'Target="worksheets/sheet1.xml"/></Relationships>',
        'xl/worksheets/sheet1.xml':
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
            '<row r="1"><c r="A1" t="inlineStr"><is><t>Başlık</t></is></c><c r="B1"/><c r="C1"/></row>'
            '<row r="2"><c r="A2" t="inlineStr"><is><t>x</t></is></c></row></sheetData>'
            '<mergeCells count="1"><mergeCell ref="A1:C1"/></mergeCells></worksheet>',
      });
      expect(_read(bytes).rows.first.cells, <Object?>['Başlık']);
    });

    test('gizli sayfa listelenmez; sayfa adı katlamalı seçilir', () {
      final bytes = handMadeXlsx(
        sheetName: 'Gizli',
        sheetState: ' state="hidden"',
        rows: [row(1, [iCell('A1', 'g')])],
        extraSheets: [
          ('Açıklama', row(1, [iCell('A1', 'a')])),
          ('KİŞİLER', row(1, [iCell('A1', 'k')])),
        ],
      );
      final reader = XlsxReader.open(bytes);
      expect(reader.sheets.map((s) => s.name), <String>['Açıklama', 'KİŞİLER']);
      expect(reader.pickSheet(<String>['Kişiler'])?.name, 'KİŞİLER');
      expect(reader.pickSheet(<String>['Daireler']), isNull, reason: 'iki sayfa, eşleşme yok: kullanıcıya sorulur');
    });

    test('tek sayfa otomatik seçilir', () {
      final bytes = handMadeXlsx(sheetName: 'Veri', rows: [row(1, [iCell('A1', 'x')])]);
      expect(XlsxReader.open(bytes).pickSheet(<String>['Daireler'])?.name, 'Veri');
    });

    test('40\'tan fazla DOLU sütun açık hata verir', () {
      final cells = List<String>.generate(41, (i) {
        final letters = i < 26 ? String.fromCharCode(65 + i) : 'A${String.fromCharCode(65 + i - 26)}';
        return iCell('${letters}1', 'c$i');
      });
      expect(() => _read(handMadeXlsx(rows: [row(1, cells)])), _fails('40', code: 'FILE_LIMIT'));
    });

    test('CDATA ve XML varlıkları çözülür', () {
      final bytes = handMadeXlsx(
        rows: [
          row(1, [
            '<c r="A1" t="inlineStr"><is><t>A &amp; B &lt;C&gt;</t></is></c>',
            '<c r="B1" t="inlineStr"><is><t><![CDATA[x < y]]></t></is></c>',
            '<c r="C1" t="inlineStr"><is><t>&#220;ye &#x15F;</t></is></c>',
          ]),
        ],
      );
      expect(_read(bytes).rows.first.cells, <Object?>['A & B <C>', 'x < y', 'Üye ş']);
    });
  });

  group('okuyucu: dosya türü ve zip koruması', () {
    test('.xls (OLE) açık ileti verir', () {
      final ole = Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, 0, 0]);
      expect(() => XlsxReader.open(ole), _fails('.xls', code: 'FILE_TYPE'));
    });

    test('zip olmayan dosya .xlsx gibi gelirse açık ileti', () {
      expect(
        () => XlsxReader.open(Uint8List.fromList(utf8.encode('Ad;Soyad\nAli;Veli\n'))),
        _fails('Excel (.xlsx) dosyası değil', code: 'FILE_TYPE'),
      );
    });

    test('boş dosya', () {
      expect(() => XlsxReader.open(Uint8List(0)), _fails('boş', code: 'FILE_EMPTY'));
    });

    test('makrolu (.xlsm), ikili (.xlsb), OpenDocument (.ods) içerik reddedilir', () {
      final base = <String, String>{'xl/workbook.xml': '<workbook/>'};
      expect(
        () => XlsxReader.open(zipOf(<String, String>{...base, 'xl/vbaProject.bin': 'x'})),
        _fails('.xlsm'),
      );
      expect(() => XlsxReader.open(zipOf(<String, String>{'xl/workbook.bin': 'x'})), _fails('.xlsb'));
      expect(
        () => XlsxReader.open(
          zipOf(<String, String>{'mimetype': 'application/vnd.oasis.opendocument.spreadsheet', 'content.xml': '<x/>'}),
        ),
        _fails('.ods'),
      );
    });

    test('Excel çalışma kitabı olmayan zip', () {
      expect(() => XlsxReader.open(zipOf(<String, String>{'a.txt': 'merhaba'})), _fails('Excel çalışma kitabı'));
    });

    test('bozuk / kesik zip hızlı ve açık reddedilir', () {
      final good = handMadeXlsx(rows: [row(1, [iCell('A1', 'x')])]);
      final sw = Stopwatch()..start();
      expect(() => XlsxReader.open(Uint8List.sublistView(good, 0, good.length - 40)), _fails('okunamadı'));
      final random = Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04, ...List<int>.generate(500, (i) => (i * 31) & 0xFF)]);
      expect(() => XlsxReader.open(random), _fails('okunamadı'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('girdi sayısı > 300 sayılmadan ÖNCE reddedilir', () {
      final parts = <String, String>{'xl/workbook.xml': '<workbook/>'};
      for (var i = 0; i < 310; i++) {
        parts['junk/$i.txt'] = 'x';
      }
      final sw = Stopwatch()..start();
      expect(() => XlsxReader.open(zipOf(parts)), _fails('çok parça', code: 'FILE_LIMIT'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('zip-bomb: bildirilen açılmış boyut 50 MB\'ı aşarsa AÇILMADAN reddedilir', () {
      final good = handMadeXlsx(rows: [row(1, [iCell('A1', 'x')])]);
      final bomb = forgeUncompressedSize(good, 60 * 1024 * 1024);
      final sw = Stopwatch()..start();
      expect(() => XlsxReader.open(bomb), _fails('50 MB', code: 'FILE_TOO_LARGE'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('zip-bomb: 1000:1 sıkıştırma oranı reddedilir (gerçek sıkıştırılmış veri)', () {
      // 12 MB sıfır baytı birkaç KB'a sıkışır: oran >> 100.
      final zeros = String.fromCharCodes(List<int>.filled(12 * 1024 * 1024, 0x61));
      final bomb = zipOf(<String, String>{
        'xl/workbook.xml': '<workbook/>',
        'xl/worksheets/sheet1.xml': zeros,
      });
      expect(bomb.length, lessThan(100 * 1024));
      final sw = Stopwatch()..start();
      expect(() => XlsxReader.open(bomb), _fails('sıkıştırılmış', code: 'FILE_LIMIT'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('bildirilenden büyük gerçek veri (yalan söyleyen başlık) açılmaz, takılmaz', () {
      final good = handMadeXlsx(
        rows: [for (var i = 1; i <= 200; i++) row(i, [iCell('A$i', 'metin numarası $i')])],
      );
      final liar = forgeUncompressedSize(good, 20);
      final sw = Stopwatch()..start();
      expect(() => XlsxReader.open(liar), _fails('okunamadı'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    group('merkezi dizin ön taraması (R12 P1-1: sembolik bağ bayraklı girdi koruması atlıyordu)', () {
      Uint8List good() => handMadeXlsx(rows: [for (var i = 1; i <= 50; i++) row(i, [iCell('A$i', 'metin $i')])]);

      test('PoC dosyası: 300 MB bildirimli sembolik-bağ-bayraklı deflate bombası, hiçbir şey AÇILMADAN reddedilir', () {
        final bomb = File('test/fixtures/bulk/xlsx_symlink_bomb_300mb.xlsx').readAsBytesSync();
        expect(bomb.length, lessThan(400 * 1024));
        final sw = Stopwatch()..start();
        expect(() => XlsxReader.open(bomb), _fails('güvenli görünmüyor', code: 'FILE_LIMIT'));
        final outcome = runParse(
          ParseRequest(bytes: bomb, fileName: 'b.xlsx', kind: ImportKind.apartments, spec: testSpec()),
        );
        expect(outcome, isA<ParseFailed>());
        expect((outcome as ParseFailed).code, 'FILE_LIMIT');
        expect(sw.elapsedMilliseconds, lessThan(500), reason: 'açılsaydı yüzlerce MB / saniyeler sürerdi');
      });

      test('sembolik bağ bayrağı tek başına yeter (boyut küçük olsa bile) ve boyut denetiminden ÖNCE gelir', () {
        final forged = forgeCentralHeaders(good(), madeBy: 0x031E, externalAttributes: 0xA1FF << 16);
        expect(() => XlsxReader.open(forged), _fails('güvenli görünmüyor', code: 'FILE_LIMIT'));
      });

      test('sembolik bağ + 1 GB bildirim: ZipDecoder çalışmadan reddedilir (bellek / süre patlamaz)', () {
        final forged = forgeCentralHeaders(
          forgeUncompressedSize(good(), 1 << 30),
          madeBy: 0x031E,
          externalAttributes: 0xA1FF << 16,
        );
        final sw = Stopwatch()..start();
        expect(() => XlsxReader.open(forged), throwsA(isA<SpreadsheetException>()));
        expect(sw.elapsedMilliseconds, lessThan(500));
      });

      test('Windows kaynaklı (madeBy 0) normal dosya bayrakları etkilenmez', () {
        final fine = forgeCentralHeaders(good(), madeBy: 0x0014, externalAttributes: 0x20);
        expect(XlsxReader.open(fine).sheets.single.name, 'Sayfa1');
      });

      test('EOCD girdi sayısı yalan söylese de GERÇEK dizin sayılır (300 üstü reddedilir)', () {
        final parts = <String, String>{'xl/workbook.xml': '<workbook/>'};
        for (var i = 0; i < 400; i++) {
          parts['junk/$i.txt'] = 'x';
        }
        final lying = forgeCentralHeaders(zipOf(parts), eocdEntryCount: 1);
        final sw = Stopwatch()..start();
        expect(() => XlsxReader.open(lying), _fails('çok parça', code: 'FILE_LIMIT'));
        expect(sw.elapsedMilliseconds, lessThan(500));
      });

      test('zip64 işaretleri (0xFFFFFFFF boyut) ve desteklenmeyen sıkıştırma (bzip2 / AES) reddedilir', () {
        expect(
          () => XlsxReader.open(forgeCentralHeaders(good(), uncompressedSize: 0xFFFFFFFF)),
          _fails('okunamadı'),
        );
        expect(
          () => XlsxReader.open(forgeCentralHeaders(good(), compressedSize: 0xFFFFFFFF)),
          _fails('okunamadı'),
        );
        expect(() => XlsxReader.open(forgeCentralHeaders(good(), method: 12)), _fails('desteklenmeyen', code: 'FILE_TYPE'));
        expect(() => XlsxReader.open(forgeCentralHeaders(good(), method: 99)), _fails('parola', code: 'FILE_TYPE'));
      });

      test('toplam bildirilen boyut 50 MB üstüne çıkarsa (girdiler tek tek 25 MB altında olsa da) reddedilir', () {
        final parts = <String, String>{'xl/workbook.xml': '<workbook/>'};
        for (var i = 0; i < 4; i++) {
          parts['junk/$i.txt'] = 'x';
        }
        final forged = forgeCentralHeaders(zipOf(parts), uncompressedSize: 20 * 1024 * 1024, compressedSize: 1024 * 1024);
        expect(() => XlsxReader.open(forged), _fails('50 MB', code: 'FILE_TOO_LARGE'));
      });

      test('normal üreticiler (kendi yazıcımız) ön taramadan geçer', () {
        final bytes = buildXlsx(<XlsxSheet>[
          const XlsxSheet(name: 'S', columns: <XlsxColumn>[XlsxColumn('A')], rows: <List<Object?>>[<Object?>['x']]),
        ]);
        expect(() => inspectZipDirectory(bytes), returnsNormally);
        expect(() => inspectZipDirectory(Uint8List(10)), throwsA(isA<SpreadsheetException>()));
      });
    });

    test('girdi başına 25 MB sınırı', () {
      final good = handMadeXlsx(rows: [row(1, [iCell('A1', 'x')])]);
      final big = forgeUncompressedSize(good, 26 * 1024 * 1024);
      expect(() => XlsxReader.open(big), _fails('50 MB'));
    });

    test('DOCTYPE içeren XML reddedilir (varlık genişletme yok)', () {
      final bytes = handMadeXlsx(
        rows: [row(1, [iCell('A1', 'x')])],
        extraParts: <String, String>{
          'xl/sharedStrings.xml':
              '<?xml version="1.0"?><!DOCTYPE sst [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;">]>'
                  '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>&b;</t></si></sst>',
        },
      );
      final reader = XlsxReader.open(bytes);
      expect(() => reader.readSheet(reader.sheets.first), _fails('güvenli görünmüyor'));
    });

    test('sharedStrings öğe sayısı 200.000\'i aşarsa reddedilir', () {
      final sb = StringBuffer();
      for (var i = 0; i < SheetLimits.maxSharedStrings + 1; i++) {
        sb.write('<si><t>metin numarası $i</t></si>');
      }
      final bytes = handMadeXlsx(
        sharedStrings: sb.toString(),
        rows: [row(1, [sCell('A1', 0)])],
      );
      final reader = XlsxReader.open(bytes);
      final sw = Stopwatch()..start();
      expect(() => reader.readSheet(reader.sheets.first), _fails('metin sayısı', code: 'FILE_LIMIT'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('bozuk XML açık hata verir', () {
      final bytes = handMadeXlsx(rows: '<row r="1"><c r="A1" t="inlineStr"><is><t>x</is></c></row><<<');
      final reader = XlsxReader.open(bytes);
      expect(() => reader.readSheet(reader.sheets.first), _fails('okunamadı'));
    });

    test('kapsam dışı: çok satırlı sayfa 5011 dolu satırda DURUR (truncated)', () {
      final rows = <String>[
        for (var i = 1; i <= 8000; i++) row(i, [iCell('A$i', 'k$i'), nCell('B$i', i)]),
      ];
      final bytes = handMadeXlsx(rows: rows.join());
      final sw = Stopwatch()..start();
      final t = _read(bytes);
      expect(t.truncated, isTrue);
      expect(t.rows.length, SheetLimits.maxRecords);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('yazıcı', () {
    test('metin hücreleri inlineStr, formül öneki KAÇIŞSIZ ama formül değil', () {
      final bytes = buildXlsx(<XlsxSheet>[
        const XlsxSheet(
          name: 'Kişiler',
          columns: <XlsxColumn>[XlsxColumn('Ad Soyad'), XlsxColumn('Not')],
          rows: <List<Object?>>[
            <Object?>['=HYPERLINK("http://x")', '@SUM(1)'],
            <Object?>['+90 555', '-5'],
          ],
        ),
      ]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final sheet = utf8.decode(archive.find('xl/worksheets/sheet1.xml')!.readBytes()!);
      expect(sheet, contains('t="inlineStr"'));
      expect(sheet, isNot(contains('<f>')), reason: 'hiç formül hücresi yazılmaz');
      expect(sheet, isNot(contains("'=")), reason: "XLSX'te ' kaçışı eklenmez");
      final t = _read(bytes);
      expect(t.rows[1].cells, <Object?>['=HYPERLINK("http://x")', '@SUM(1)']);
      expect(t.rows[2].cells, <Object?>['+90 555', '-5']);
    });

    test('başlık kalın + dondurulmuş; sayfa adı kurallara uyar', () {
      final bytes = buildXlsx(<XlsxSheet>[
        const XlsxSheet(
          name: "Çok:Uzun*Sayfa/Adı?[x]'ABCDEFGHIJKLMNOP",
          columns: <XlsxColumn>[XlsxColumn('A')],
          rows: <List<Object?>>[],
        ),
      ]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final wb = utf8.decode(archive.find('xl/workbook.xml')!.readBytes()!);
      final name = RegExp(r'<sheet name="([^"]*)"').firstMatch(wb)!.group(1)!;
      expect(name.length, lessThanOrEqualTo(31));
      expect(name, isNot(matches(RegExp(r'[\[\]:*?/\\]'))));
      final sheet = utf8.decode(archive.find('xl/worksheets/sheet1.xml')!.readBytes()!);
      expect(sheet, contains('state="frozen"'));
      final styles = utf8.decode(archive.find('xl/styles.xml')!.readBytes()!);
      expect(styles, contains('<b/>'));
    });

    test('aynı ada düşen sayfalara sayaç eklenir', () {
      final bytes = buildXlsx(<XlsxSheet>[
        const XlsxSheet(name: 'Veri', columns: <XlsxColumn>[XlsxColumn('A')], rows: <List<Object?>>[]),
        const XlsxSheet(name: 'veri', columns: <XlsxColumn>[XlsxColumn('A')], rows: <List<Object?>>[]),
      ]);
      expect(XlsxReader.open(bytes).sheets.map((s) => s.name).toSet().length, 2);
    });

    test('XML\'de geçersiz karakterler atılır, dosya yine açılır', () {
      final bytes = buildXlsx(<XlsxSheet>[
        XlsxSheet(
          name: 'S',
          columns: const <XlsxColumn>[XlsxColumn('Ad')],
          rows: <List<Object?>>[
            <Object?>['A\u0000B\u0008C\u000BD\u000CE\u001FF￾G￿H\uD800I'],
            <Object?>['Sağlam 😀 emoji'],
          ],
        ),
      ]);
      final t = _read(bytes);
      expect(t.rows[1].cells.first, 'ABCDEFGHI');
      expect(t.rows[2].cells.first, 'Sağlam 😀 emoji');
    });

    test('tarih gerçek tarih hücresi; sayı gerçek sayı; para kayan noktasız', () {
      final bytes = buildXlsx(<XlsxSheet>[
        const XlsxSheet(
          name: 'S',
          columns: <XlsxColumn>[
            XlsxColumn('Tarih', format: XlsxFormat.date),
            XlsxColumn('Alan', format: XlsxFormat.decimal),
            XlsxColumn('Tutar', format: XlsxFormat.money),
          ],
          rows: <List<Object?>>[
            <Object?>['2021-03-15', 125.5, XlsxMoney(125050)],
            <Object?>[null, 100, XlsxMoney(-5)],
            <Object?>['1899-01-01', null, XlsxMoney('9007199254740993')],
          ],
        ),
      ]);
      final t = _read(bytes);
      expect(t.rows[1].cells[0], const SheetDateCell(44270));
      expect(t.rows[1].cells[1], 125.5);
      expect(t.rows[1].cells[2], 1250.5);
      expect(t.rows[2].cells[2], -0.05);
      // 1900-03-01 öncesi Excel'de gösterilemez: okunur metin olarak yazılır.
      expect(t.rows[3].cells[0], '01.01.1899');
      final xml = utf8.decode(ZipDecoder().decodeBytes(bytes).find('xl/worksheets/sheet1.xml')!.readBytes()!);
      expect(xml, contains('<v>90071992547409.93</v>'), reason: 'büyük kuruş tamsayı aritmetiğiyle yazılır');
    });

    test('metin biçimli sütunlar (@) için sütun stili tanımlanır', () {
      final bytes = buildXlsx(<XlsxSheet>[
        const XlsxSheet(
          name: 'S',
          columns: <XlsxColumn>[XlsxColumn('Telefon', format: XlsxFormat.text)],
          rows: <List<Object?>>[],
        ),
      ]);
      final xml = utf8.decode(ZipDecoder().decodeBytes(bytes).find('xl/worksheets/sheet1.xml')!.readBytes()!);
      expect(xml, contains('<col min="1" max="1"'));
      expect(xml, contains('style="2"'));
      final styles = utf8.decode(ZipDecoder().decodeBytes(bytes).find('xl/styles.xml')!.readBytes()!);
      expect(styles, contains('numFmtId="49"'));
    });

    test('5000 satır x 10 sütun gidiş-dönüş 2 sn altında ve kayıpsız', () {
      final rows = <List<Object?>>[
        for (var i = 0; i < 5000; i++)
          <Object?>['Kişi $i', '0 (555) 123 ${i.toString().padLeft(4, '0')}', i, i * 1.5, 'A Blok', '${i % 40}', 'x', 'y', null, 'z'],
      ];
      final cols = <XlsxColumn>[for (var i = 0; i < 10; i++) XlsxColumn('S$i')];
      final (writeMs, bytes) = bestOfMillis(
        () => buildXlsx(<XlsxSheet>[XlsxSheet(name: 'S', columns: cols, rows: rows)]),
      );
      final (readMs, t) = bestOfMillis(() => _read(bytes));
      expect(t.rows.length, 5001);
      expect(t.rows[5000].cells[0], 'Kişi 4999');
      expect(t.rows[5000].cells[3], 4999 * 1.5);
      expect(writeMs, lessThan(2000), reason: 'yazma $writeMs ms');
      expect(readMs, lessThan(2000), reason: 'okuma $readMs ms');
    });
  });
}
