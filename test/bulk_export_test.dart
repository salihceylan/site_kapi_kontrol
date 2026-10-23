// Toplu yükleme: dışa aktarma üreticisi, formül kaçışı ve şablon (Platform Faz 2b).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_cell_safety.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_formatting.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';
import 'package:site_kapi_kontrol/services/bulk_text_decoder.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';

import 'bulk_test_support.dart';

List<List<String>> _csvRows(RenderedFile f) {
  final decoded = decodeSpreadsheetText(f.bytes);
  return <List<String>>[
    for (final r in parseCsvText(decoded.text).rows) <String>[for (final c in r.cells) c == null ? '' : '$c'],
  ];
}

ExportEnvelope _envelope([List<List<Object?>>? rows]) => ExportEnvelope.fromJson(envelopeJson(rows: rows));

void main() {
  group('formül kaçışı (CSV)', () {
    test('= + - @ TAB CR ile başlayan metin \' öneki alır', () {
      for (final bad in <String>['=1+1', '+SUM(A1)', '-cmd', '@x', '\tx', '\rx', '=HYPERLINK("http://k")']) {
        expect(escapeCsvFormula(bad), "'$bad", reason: bad);
      }
    });

    test('baştaki boşluklar atlanarak denetlenir', () {
      expect(escapeCsvFormula('  =1+1'), "'  =1+1");
      expect(escapeCsvFormula(' @x'), "' @x");
      expect(escapeCsvFormula('   düz'), '   düz');
    });

    test('saf sayı istisnası: kat -1, +90 telefonu, ondalık', () {
      for (final ok in <String>['-1', '+5', '12', '-3,5', '+0.25', ' -7 ']) {
        expect(escapeCsvFormula(ok), ok, reason: ok);
      }
      // Sayı gibi görünüp formül olabilenler kaçışlanır.
      for (final bad in <String>['-1+1', '+1e3', '-A1', '=5', '-5-5', '+90 555']) {
        expect(escapeCsvFormula(bad), startsWith("'"), reason: bad);
      }
    });

    test('düz metin ve boş metin değişmez', () {
      expect(escapeCsvFormula(''), '');
      expect(escapeCsvFormula('Ahmet'), 'Ahmet');
      expect(escapeCsvFormula("'=x"), "'=x");
      expect(escapeCsvFormula('a=b'), 'a=b');
    });

    test('özellik testi: rastgele metinde tehlikeli başlangıç ASLA kaçışsız kalmaz', () {
      final rnd = Random(42);
      const alphabet = <String>['=', '+', '-', '@', '\t', '\r', ' ', ' ', 'a', '1', ',', '.', ';', '"', 'İ', '\n'];
      for (var i = 0; i < 5000; i++) {
        final s = List<String>.generate(rnd.nextInt(8), (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
        final out = escapeCsvFormula(s);
        final trimmed = out.replaceFirst(RegExp(r'^[  ]+'), '');
        if (trimmed.isEmpty) continue;
        final first = trimmed[0];
        final dangerous = '=+-@\t\r'.contains(first);
        final pureNumber = RegExp(r'^[+-]?\d+([.,]\d+)?$').hasMatch(out.trim());
        expect(!dangerous || pureNumber, isTrue, reason: 'kaçışsız tehlikeli başlangıç: ${jsonEncode(s)} -> ${jsonEncode(out)}');
      }
    });

    test('XML geçersiz karakter temizleme ve kaçış', () {
      expect(stripInvalidXmlChars('a\u0000b\u0001c'), 'abc');
      expect(stripInvalidXmlChars('t\tn\nr\r'), 't\tn\nr\r');
      expect(stripInvalidXmlChars('😀'), '😀');
      expect(stripInvalidXmlChars('\uDC00x'), 'x');
      expect(escapeXml('<a href="x">&</a>'), '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;');
    });

    test('sayfa adı kuralları', () {
      expect(sanitizeSheetName('A/B:C*D?E[F]G\\H'), 'A B C D E F G H');
      expect(sanitizeSheetName(''), 'Sayfa1');
      expect(sanitizeSheetName("'adı'"), 'adı');
      expect(sanitizeSheetName('x' * 50).length, 31);
    });
  });

  group('biçimlendirme', () {
    test('para: tamsayı kuruştan metin aritmetiği, kayan nokta yok', () {
      expect(formatMoneyMinor(125050), '1250,50');
      expect(formatMoneyMinor(5), '0,05');
      expect(formatMoneyMinor(-5), '-0,05');
      expect(formatMoneyMinor(0), '0,00');
      expect(formatMoneyMinor(100), '1,00');
      expect(formatMoneyMinor('9007199254740993'), '90071992547409,93');
      expect(formatMoneyMinor(-199, separator: '.'), '-1.99');
      expect(formatMoneyMinor('12.5'), isNull);
      expect(formatMoneyMinor(1.5), isNull);
      expect(formatMoneyMinor(null), isNull);
    });

    test('sayı: ondalık virgül, binlik yok, ölçek', () {
      expect(formatPlainNumber(1250.5, scale: 2), '1250,50');
      expect(formatPlainNumber(3, scale: 2), '3,00');
      expect(formatPlainNumber(125.5), '125,5');
      expect(formatPlainNumber(100.0), '100');
      expect(formatPlainNumber(-1), '-1');
      expect(formatPlainNumber('1,5'), '1,5');
      expect(formatPlainNumber(double.nan), '');
      expect(formatPlainNumber(0.1 + 0.2, scale: 2), '0,30');
      expect(formatPlainNumber(1e-7), isNot(contains('e')));
    });

    test('tarih', () {
      expect(formatTurkishDate('2021-03-15'), '15.03.2021');
      expect(formatTurkishDate('2021-03-15T10:00:00.000Z'), '15.03.2021');
      expect(formatTurkishDate('2021-02-30'), isNull);
      expect(formatTurkishDate('x'), isNull);
      expect(excelSerialOf('2021-03-15'), 44270);
      expect(excelSerialOf('1899-01-01'), isNull);
    });
  });

  group('zarf modeli', () {
    test('çözümleme ve yapısal bozukluklar', () {
      final e = _envelope();
      expect(e.columns.map((c) => c.type), <ExportColumnType>[
        ExportColumnType.text,
        ExportColumnType.text,
        ExportColumnType.date,
        ExportColumnType.number,
        ExportColumnType.money,
      ]);
      expect(e.columns[3].scale, 2);
      expect(e.rowCount, 2);
      expect(() => ExportEnvelope.fromJson(<String, dynamic>{'columns': <Object>[], 'rows': <Object>[]}), throwsFormatException);
      final bad = envelopeJson();
      (bad['rows'] as List).add(<Object?>['kısa']);
      expect(() => ExportEnvelope.fromJson(bad), throwsFormatException);
      final wrongCount = envelopeJson()..['row_count'] = 99;
      expect(() => ExportEnvelope.fromJson(wrongCount), throwsFormatException);
    });

    test('bilinmeyen sütun tipi metne düşer', () {
      final j = envelopeJson();
      (j['columns'] as List<Map<String, dynamic>>)[0]['type'] = 'garip';
      expect(ExportEnvelope.fromJson(j).columns.first.type, ExportColumnType.text);
    });
  });

  group('CSV çıktısı', () {
    test('BOM, başlık, Türkçe biçimler, null boş hücre', () {
      final f = renderExport(_envelope(), ExportFormat.csv);
      expect(f.fileName, 'kisiler_gul-sitesi_20261016.csv');
      expect(f.bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(f.bytes.sublist(3)).contains('\r\n'), isTrue);
      final rows = _csvRows(f);
      expect(rows[0], <String>['Ad Soyad', 'Telefon', 'Giriş Tarihi', 'Brüt m²', 'Borç']);
      expect(rows[1], <String>['Ahmet Yılmaz', '0 (555) 123 45 67', '15.03.2021', '125,50', '1250,50']);
      expect(rows[2][1], '');
      expect(rows[2][2], '');
      expect(rows[2][3], '100,00');
      expect(rows[2][4], '-0,05');
    });

    test('enjeksiyon: = ile başlayan ad kaçışlanır', () {
      final f = renderExport(_envelope(), ExportFormat.csv);
      expect(_csvRows(f)[2][0], '\'=HYPERLINK("x")');
    });

    test('metin hücrelerde saf sayı istisnası; sayı sütununda eksi işaretli değer kaçışlanmaz', () {
      final env = ExportEnvelope.fromJson(<String, dynamic>{
        'kind': 'apartments',
        'filename_base': 'daireler',
        'columns': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'kat', 'label': 'Kat', 'type': 'text'},
          <String, dynamic>{'key': 'sayi', 'label': 'Sayı', 'type': 'number'},
          <String, dynamic>{'key': 'tip', 'label': 'Tip', 'type': 'text'},
        ],
        'rows': <List<Object?>>[
          <Object?>['-1', -3, '+1+1'],
        ],
        'row_count': 1,
      });
      final rows = _csvRows(renderExport(env, ExportFormat.csv));
      expect(rows[1], <String>['-1', '-3', "'+1+1"]);
    });

    test('hücre içinde ; " satır sonu: tırnaklanır ve geri okunur', () {
      final env = _envelope(<List<Object?>>[
        <Object?>['Ali; "Veli"\nSon', '1', '2021-01-01', 1, 1],
      ]);
      final rows = _csvRows(renderExport(env, ExportFormat.csv));
      expect(rows[1][0], 'Ali; "Veli"\nSon');
    });

    test('dosya adı güvenli ASCII olur', () {
      expect(safeFileBase('Kişiler Çağlar/Site: ŞİŞLİ?'), 'Kisiler_Caglar_Site_SISLI');
      expect(safeFileBase('../../etc/passwd'), 'etc_passwd');
      expect(safeFileBase('***'), 'dosya');
      expect(safeFileBase('a' * 200).length, 80);
    });
  });

  group('XLSX çıktısı', () {
    test('gerçek tarih, gerçek sayı, para; metin sütunları metin; formül metni kaçışsız', () {
      final f = renderExport(_envelope(), ExportFormat.xlsx, sheetName: 'Kişiler');
      expect(f.fileName, 'kisiler_gul-sitesi_20261016.xlsx');
      final reader = XlsxReader.open(f.bytes);
      expect(reader.sheets.single.name, 'Kişiler');
      final t = reader.readSheet(reader.sheets.single);
      expect(t.rows[0].cells.first, 'Ad Soyad');
      expect(t.rows[1].cells[1], '0 (555) 123 45 67', reason: 'telefon metin kalır');
      expect(t.rows[1].cells[2].toString(), contains('SheetDateCell'));
      expect(t.rows[1].cells[3], 125.5);
      expect(t.rows[1].cells[4], 1250.5);
      expect(t.rows[2].cells[0], '=HYPERLINK("x")', reason: "XLSX'te ' eklenmez");
      final xml = utf8.decode(ZipDecoder().decodeBytes(f.bytes).find('xl/worksheets/sheet1.xml')!.readBytes()!);
      expect(xml, isNot(contains('<f>')));
    });

    test('20.000 satırlık zarf 2 sn altında üretilir', () {
      final rows = <List<Object?>>[
        for (var i = 0; i < 20000; i++) <Object?>['Kişi $i', '0 (555) 000 0000', '2021-03-15', i * 0.5, i],
      ];
      final env = _envelope(rows);
      final (xlsxMs, xlsx) = bestOfMillis(() => renderExport(env, ExportFormat.xlsx));
      final (csvMs, csv) = bestOfMillis(() => renderExport(env, ExportFormat.csv));
      expect(xlsx.bytes.length, greaterThan(1000));
      expect(csv.bytes.length, greaterThan(1000));
      expect(xlsxMs, lessThan(2000), reason: 'xlsx $xlsxMs ms');
      expect(csvMs, lessThan(2000), reason: 'csv $csvMs ms');
    });
  });

  group('gidiş-dönüş: dışa aktarılan dosya yeniden yüklenebilir', () {
    final spec = testSpec();
    ExportEnvelope peopleEnvelope() => ExportEnvelope.fromJson(<String, dynamic>{
      'kind': 'people',
      'filename_base': 'kisiler',
      'columns': <Map<String, dynamic>>[
        <String, dynamic>{'key': 'ad_soyad', 'label': 'Ad Soyad', 'type': 'text'},
        <String, dynamic>{'key': 'telefon', 'label': 'Telefon', 'type': 'text'},
        <String, dynamic>{'key': 'e_posta', 'label': 'E-posta', 'type': 'text'},
        <String, dynamic>{'key': 'blok', 'label': 'Blok', 'type': 'text'},
        <String, dynamic>{'key': 'daire_no', 'label': 'Daire No', 'type': 'text'},
        <String, dynamic>{'key': 'iliski', 'label': 'İlişki', 'type': 'text'},
        <String, dynamic>{'key': 'giris_tarihi', 'label': 'Giriş Tarihi', 'type': 'date'},
        <String, dynamic>{'key': 'plaka', 'label': 'Plaka', 'type': 'text'},
        <String, dynamic>{'key': 'hesap', 'label': 'Hesap', 'type': 'text'},
        <String, dynamic>{'key': 'durum', 'label': 'Durum', 'type': 'text'},
      ],
      'rows': <List<Object?>>[
        <Object?>['Çağlar Öztürk', '0 (555) 123 45 67', 'caglar@x.com', 'A Blok', '5', 'Malik', '2021-03-15', '34 ABC 123, 06 XY 789', 'Var', 'Aktif'],
        <Object?>['=evil()', null, null, null, null, null, null, null, 'Yok', 'Pasif'],
      ],
      'row_count': 2,
    });

    for (final format in ExportFormat.values) {
      test('${format.apiValue}: başlıklar tanınır, salt okunur sütunlar yok sayılır', () {
        final file = renderExport(peopleEnvelope(), format);
        final out = runParse(
          ParseRequest(bytes: file.bytes, fileName: file.fileName, kind: ImportKind.people, spec: spec),
        );
        expect(out, isA<ParseDone>(), reason: out is ParseFailed ? out.message : '');
        final done = out as ParseDone;
        final people = spec.of(ImportKind.people)!;
        expect(done.header.mapping.canProceed(people), isTrue);
        final ignored = done.header.mapping.ignoredColumns().map((i) => done.header.mapping.headers[i]).toList();
        expect(ignored, <String>['Hesap', 'Durum']);
        final rows = extractImportRows(done.table, done.header.mapping, people).rows;
        expect(rows.length, 2);
        expect(rows[0].cells['ad_soyad'], 'Çağlar Öztürk');
        expect(rows[0].cells['telefon'], '0 (555) 123 45 67');
        expect(rows[0].cells['plaka'], '34 ABC 123, 06 XY 789');
        expect(rows[0].cells['giris_tarihi'], format == ExportFormat.xlsx ? '2021-03-15' : '15.03.2021');
        // CSV'de kaçış öneki geri okunur: sunucu bunu ad olarak görür (kaçış yalnız Excel'de görünmez bir koruma).
        expect(rows[1].cells['ad_soyad'], format == ExportFormat.csv ? "'=evil()" : '=evil()');
      });
    }
  });

  group('şablon', () {
    final spec = testSpec();
    final apartments = ExportEnvelope.fromJson(apartmentsEnvelopeJson());

    test('XLSX: seçilen tür ilk sayfa, daireler ön dolu, kişiler ve araçlar yalnız başlık, Açıklama sayfası', () {
      final f = buildImportTemplate(
        spec: spec,
        kind: ImportKind.people,
        format: ExportFormat.xlsx,
        apartments: apartments,
        siteName: 'Gül Sitesi',
      );
      expect(f.fileName, 'toplu_yukleme_sablonu.xlsx');
      final reader = XlsxReader.open(f.bytes);
      expect(reader.sheets.map((s) => s.name), <String>['Kişiler', 'Daireler', 'Araçlar', 'Açıklama']);
      final people = reader.readSheet(reader.sheets[0]);
      expect(people.rows.length, 1, reason: 'örnek satır KONMAZ');
      expect(people.rows.first.cells, <Object?>[
        'Ad Soyad*', 'Telefon', 'E-posta', 'Blok', 'Daire No', 'İlişki', 'Giriş Tarihi', 'Plaka',
      ]);
      final apt = reader.readSheet(reader.sheets[1]);
      expect(apt.rows.length, 4);
      expect(apt.rows[1].cells.take(4), <Object?>['A Blok', '1', 0, '2+1']);
      expect(apt.rows[3].cells[0], 'B Blok');
      final vehicles = reader.readSheet(reader.sheets[2]);
      expect(vehicles.rows.length, 1);
      final info = reader.readSheet(reader.sheets[3]);
      final text = info.rows.map((r) => r.cells.join(' ')).join('\n');
      expect(text, contains('İlişki sözlüğü'));
      expect(text, contains('mal sahibi'));
      expect(text, contains('Gül Sitesi'));
    });

    test('şablon kendi okuyucumuzla yüklenebilir (daireler sayfası otomatik seçilir)', () {
      final f = buildImportTemplate(
        spec: spec,
        kind: ImportKind.apartments,
        format: ExportFormat.xlsx,
        apartments: apartments,
      );
      final out = runParse(
        ParseRequest(bytes: f.bytes, fileName: f.fileName, kind: ImportKind.apartments, spec: spec),
      ) as ParseDone;
      expect(out.table.sheetName, 'Daireler');
      final rows = extractImportRows(out.table, out.header.mapping, spec.of(ImportKind.apartments)!).rows;
      expect(rows.length, 3);
      expect(rows.first.cells['blok'], 'A Blok');
      expect(rows.first.cells['daire_no'], '1');
      expect(rows.first.cells['kat'], 0);
    });

    test('daire zarfı yoksa daire sayfası yalnız başlık', () {
      final f = buildImportTemplate(spec: spec, kind: ImportKind.apartments, format: ExportFormat.xlsx);
      final reader = XlsxReader.open(f.bytes);
      expect(reader.readSheet(reader.sheets.first).rows.length, 1);
    });

    test('zarf blok / daire no içermiyorsa ön doldurma yapılmaz', () {
      final other = ExportEnvelope.fromJson(envelopeJson());
      final f = buildImportTemplate(
        spec: spec,
        kind: ImportKind.apartments,
        format: ExportFormat.xlsx,
        apartments: other,
      );
      final reader = XlsxReader.open(f.bytes);
      expect(reader.readSheet(reader.sheets.first).rows.length, 1);
    });

    test('CSV: başlık satırı, ; + BOM; daire şablonu ön dolu', () {
      final people = buildImportTemplate(spec: spec, kind: ImportKind.people, format: ExportFormat.csv);
      expect(people.fileName, 'toplu_yukleme_sablonu_kisiler.csv');
      expect(people.bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      final rows = _csvRows(people);
      expect(rows.length, 1);
      expect(rows.first.first, 'Ad Soyad*');
      final apt = buildImportTemplate(
        spec: spec,
        kind: ImportKind.apartments,
        format: ExportFormat.csv,
        apartments: apartments,
      );
      final aptRows = _csvRows(apt);
      expect(aptRows.length, 4);
      expect(aptRows[1].take(4), <String>['A Blok', '1', '0', '2+1']);
    });
  });

  group('hata raporu', () {
    test('satır;alan;kod;ileti — hücre değeri yok, iletiler kaçışlı', () {
      final f = renderIssueReport(
        const <ImportIssue>[
          ImportIssue(n: 3, severity: ImportSeverity.error, field: 'e_posta', code: 'EMAIL_INVALID', message: 'E-posta geçersiz.'),
          ImportIssue(n: 9, severity: ImportSeverity.warning, code: 'PLATE_INVALID', message: '=cmd| «34 ABC»'),
        ],
        ImportKind.people,
        fieldLabels: const <String, String>{'e_posta': 'E-posta'},
        now: DateTime.utc(2026, 10, 16, 12),
      );
      expect(f.fileName, 'hata_raporu_people_20261016.csv');
      final rows = _csvRows(f);
      expect(rows[0], <String>['Satır', 'Alan', 'Kod', 'İleti']);
      expect(rows[1], <String>['3', 'E-posta', 'EMAIL_INVALID', 'E-posta geçersiz.']);
      expect(rows[2], <String>['9', '', 'PLATE_INVALID', "'=cmd| «34 ABC»"]);
    });
  });

  test('ExportFormat sabitleri', () {
    expect(ExportFormat.xlsx.extension, 'xlsx');
    expect(ExportFormat.csv.mimeType, 'text/csv');
    expect(Uint8List(0), isEmpty);
  });
}
