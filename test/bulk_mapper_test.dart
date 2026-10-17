// Toplu yükleme: başlık eşleme, satır çıkarma ve dosya hattı (Platform Faz 2b).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';

import 'bulk_test_support.dart';

SheetTable _csv(String text) => parseCsvText(text);

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

ParseOutcome _run(String text, ImportKind kind, {String name = 'dosya.csv'}) =>
    runParse(ParseRequest(bytes: _utf8(text), fileName: name, kind: kind, spec: testSpec()));

void main() {
  final spec = testSpec();

  group('foldHeader', () {
    test('Türkçe katlama, küçük harf ve noktalama sadeleştirme', () {
      expect(foldHeader('Ad Soyad'), 'ad soyad');
      expect(foldHeader('ad_soyad'), 'ad soyad');
      expect(foldHeader('  İLİŞKİ  '), 'iliski');
      expect(foldHeader('Iliski'), 'iliski');
      expect(foldHeader('Çağrı Öğüt Şu'), 'cagri ogut su');
      expect(foldHeader('E-posta'), 'e posta');
      expect(foldHeader('Arsa Payı (Pay)'), 'arsa payi pay');
      expect(foldHeader('Brüt m²'), 'brut m2');
      expect(foldHeader('Brüt m2'), 'brut m2');
      expect(foldHeader('Brüt ㎡'), 'brut m2');
      expect(foldHeader('***'), '');
    });
  });

  group('başlık bulma', () {
    test('ilk 10 dolu satırda ≥ 2 tanınan sütunlu ilk satır', () {
      final t = _csv('Site Listesi\n\nÖrnek Site;\nAd Soyad;Telefon;Bilinmeyen\nAli;555;x\n');
      final h = detectHeader(t, spec.of(ImportKind.people)!)!;
      expect(h.mapping.headerN, 4, reason: 'boş satır sayılır: Excel\'deki satır numarası');
      expect(h.mapping.assignment['ad_soyad'], 0);
      expect(h.mapping.assignment['telefon'], 1);
      expect(h.mapping.ignoredColumns(), <int>[2]);
    });

    test('tek tanınan sütun başlık sayılmaz', () {
      expect(detectHeader(_csv('Ad Soyad;Bilinmeyen\nAli;x\n'), spec.of(ImportKind.people)!), isNull);
    });

    test('11. dolu satırdaki başlık bulunmaz', () {
      final junk = List<String>.generate(10, (i) => 'x$i').join('\n');
      expect(detectHeader(_csv('$junk\nAd Soyad;Telefon\nAli;555\n'), spec.of(ImportKind.people)!), isNull);
    });

    test('anahtar, etiket, takma ad ve boşluksuz biçim tanınır', () {
      final t = _csv('adi soyadi;GSM;E-Mail;daireno;İsim\nx;1;a@b.c;1;y\n');
      final a = detectHeader(t, spec.of(ImportKind.people)!)!.mapping.assignment;
      expect(a['telefon'], 1);
      expect(a['e_posta'], 2);
      expect(a['daire_no'], 3);
    });

    test('iki sütun aynı alana düşerse çakışma olarak işaretlenir, alan ATANMAZ', () {
      final t = _csv('Ad Soyad;Telefon;Tel;Cep Telefonu\nAli;1;2;3\n');
      final m = detectHeader(t, spec.of(ImportKind.people)!)!.mapping;
      expect(m.conflicts.keys, <String>['telefon']);
      expect(m.conflicts['telefon'], <int>[1, 2, 3]);
      expect(m.assignment['telefon'], isNull);
      expect(m.canProceed(spec.of(ImportKind.people)!), isFalse);
      final fixed = m.assign('telefon', 2);
      expect(fixed.conflicts, isEmpty);
      expect(fixed.assignment['telefon'], 2);
      expect(fixed.canProceed(spec.of(ImportKind.people)!), isTrue);
      expect(fixed.ignoredColumns(), <int>[1, 3]);
    });

    test('zorunlu sütun eksikse ilerlenemez; elle atama düzeltir', () {
      final people = spec.of(ImportKind.people)!;
      final t = _csv('Telefon;E-posta;Blok\n5;a@b.c;A\n');
      var m = detectHeader(t, people)!.mapping;
      expect(m.missingRequired(people).map((c) => c.key), <String>['ad_soyad']);
      expect(m.canProceed(people), isFalse);
      m = m.assign('ad_soyad', 2); // yanlış ama kullanıcının seçimi
      expect(m.assignment['blok'], isNull, reason: 'aynı kaynak sütun tek alana bağlanır');
      expect(m.canProceed(people), isTrue);
    });

    test('yanlış tür: başka türün başlıkları daha çok uyuyorsa önerilir', () {
      final t = _csv('Plaka;E-posta;Blok;Daire No\n34ABC123;a@b.c;A;1\n');
      expect(suggestBetterKind(t, spec, ImportKind.apartments), ImportKind.vehicles);
      expect(suggestBetterKind(t, spec, ImportKind.vehicles), isNull);
    });
  });

  group('satır çıkarma', () {
    test('yalnız eşlenen sütunlar, kırpılmış metin, sayı ve null; boş satırlar atılır; n korunur', () {
      final people = spec.of(ImportKind.people)!;
      final t = _csv('Ad Soyad;Telefon;Bilinmeyen\nAli;;x\n;;\nVeli;555;y\n   ;  ;z\n');
      final m = detectHeader(t, people)!.mapping;
      final r = extractImportRows(t, m, people);
      expect(r.rows.map((e) => e.n), <int>[2, 4]);
      expect(r.rows[0].cells, <String, Object?>{'ad_soyad': 'Ali', 'telefon': null});
      expect(r.rows[1].cells, <String, Object?>{'ad_soyad': 'Veli', 'telefon': '555'});
      expect(r.blankRows, 1, reason: '«   ;  ;z» satırı eşlenmeyen sütunda dolu: eşlenenlere göre boş');
      expect(r.rows[0].cells.containsKey('bilinmeyen'), isFalse);
    });

    test('Excel seri tarihi yalnız tarih sütununda ISO\'ya çevrilir', () {
      final people = spec.of(ImportKind.people)!;
      final table = SheetTable(
        rows: <SheetRow>[
          const SheetRow(1, <Object?>['Ad Soyad', 'Giriş Tarihi', 'Telefon']),
          const SheetRow(2, <Object?>['Ali', SheetDateCell(44270), SheetDateCell(44270)]),
        ],
      );
      final m = detectHeader(table, people)!.mapping;
      final r = extractImportRows(table, m, people).rows.single;
      expect(r.cells['giris_tarihi'], '2021-03-15');
      expect(r.cells['telefon'], 44270, reason: 'tarih olmayan sütunda sayı olarak gider');
    });

    test('tarih sütununda tarih biçimsiz sayı SAYI olarak gider (sessizce tarihe çevrilmez)', () {
      final people = spec.of(ImportKind.people)!;
      final table = SheetTable(
        rows: <SheetRow>[
          const SheetRow(1, <Object?>['Ad Soyad', 'Giriş Tarihi']),
          const SheetRow(2, <Object?>['Ali', 2021]),
        ],
      );
      final m = detectHeader(table, people)!.mapping;
      expect(extractImportRows(table, m, people).rows.single.cells['giris_tarihi'], 2021);
    });

    test('tam sayı değerli ondalık sayı int olur; NaN/Infinity null olur', () {
      const column = ImportColumn(key: 'k', label: 'K', type: ImportColumnType.number);
      expect(normalizeImportCell(5.0, column), 5);
      expect(normalizeImportCell(5.5, column), 5.5);
      expect(normalizeImportCell(double.nan, column), isNull);
      expect(normalizeImportCell(double.infinity, column), isNull);
      expect(normalizeImportCell('  ', column), isNull);
    });

    test('5000\'den fazla veri satırı açık hata verir', () {
      final people = spec.of(ImportKind.people)!;
      final sb = StringBuffer('Ad Soyad;Telefon\n');
      for (var i = 0; i < 5001; i++) {
        sb.write('Kişi $i;5\n');
      }
      final t = _csv(sb.toString());
      final m = detectHeader(t, people)!.mapping;
      expect(() => extractImportRows(t, m, people), throwsA(isA<SpreadsheetException>()));
    });
  });

  group('Excel seri tarihi', () {
    test('1900 ve 1904 sistemleri', () {
      expect(excelSerialToIso(44270), '2021-03-15');
      expect(excelSerialToIso(44270.75), '2021-03-15', reason: 'saat atılır');
      expect(excelSerialToIso(61), '1900-03-01');
      expect(excelSerialToIso(59), '1900-02-28');
      expect(excelSerialToIso(60), isNull, reason: '1900-02-29 diye gün yok');
      expect(excelSerialToIso(0), isNull);
      expect(excelSerialToIso(-1), isNull);
      expect(excelSerialToIso(3000000), isNull);
      expect(excelSerialToIso(41000, date1904: true), '2016-04-02');
    });
  });

  group('dosya hattı (runParse)', () {
    test('Türkçe CSV uçtan uca: başlık, eşleme, satırlar', () {
      final out = _run(
        'sep=;\r\nAd Soyad;Telefon;E-posta;Blok;Daire No;İlişki;Giriş Tarihi;Plaka\r\n'
        'Ahmet Yılmaz;0 (555) 123 45 67;ahmet@x.com;A;3;Malik;15.03.2021;34 ABC 123, 06 XY 789\r\n',
        ImportKind.people,
      );
      expect(out, isA<ParseDone>());
      final done = out as ParseDone;
      expect(done.table.encodingNote, 'UTF-8 olarak okundu');
      final people = spec.of(ImportKind.people)!;
      expect(done.header.mapping.canProceed(people), isTrue);
      final rows = extractImportRows(done.table, done.header.mapping, people).rows;
      expect(rows.single.n, 2);
      expect(rows.single.cells['plaka'], '34 ABC 123, 06 XY 789');
      expect(rows.single.cells['giris_tarihi'], '15.03.2021');
    });

    test('Windows-1254 dosya Türkçe karakterlerle okunur ve not düşer', () {
      final bytes = Uint8List.fromList(<int>[
        ...latin('Ad Soyad;Telefon\n'),
        ...<int>[0xDD, 0x62, 0x72, 0x61, 0x68, 0x69, 0x6D, 0x20, 0xDE, 0x65, 0x6E], // İbrahim Şen
        ...latin(';555\n'),
      ]);
      final out = runParse(ParseRequest(bytes: bytes, fileName: 'x.csv', kind: ImportKind.people, spec: spec));
      final done = out as ParseDone;
      expect(done.table.encodingNote, 'Windows-1254 olarak okundu');
      expect(done.table.rows[1].cells.first, 'İbrahim Şen');
    });

    test('başlıksız dosya: dürüst ileti', () {
      final out = _run('a;b\n1;2\n', ImportKind.people);
      expect(out, isA<ParseFailed>());
      expect((out as ParseFailed).code, 'NO_HEADER');
      expect(out.message, contains('Başlık satırı bulunamadı'));
    });

    test('yanlış tür seçimi: engellenmez, ama hangi türe benzediği bildirilir', () {
      final out = _run('Plaka;E-posta;Blok;Daire No\n34ABC123;a@b.c;A;1\n', ImportKind.apartments);
      expect((out as ParseDone).suggestedKind, ImportKind.vehicles);
    });

    test('hiçbir başlığı seçilen türe uymayan ama başka türe uyan dosya reddedilir ve yönlendirir', () {
      final out = _run('Plaka;E-posta\n34ABC123;a@b.c\n', ImportKind.apartments);
      expect((out as ParseFailed).message, contains('«Araçlar»'));
    });

    test('.xls / .xlsm / .xlsb / .ods / .pdf uzantıları erken reddedilir', () {
      for (final name in <String>['a.xls', 'a.xlsm', 'a.xlsb', 'a.ods', 'a.pdf', 'a.txt']) {
        final out = _run('Ad Soyad;Telefon\nA;1\n', ImportKind.people, name: name);
        expect(out, isA<ParseFailed>(), reason: name);
        expect((out as ParseFailed).code, 'FILE_TYPE', reason: name);
      }
      expect(_run('Ad Soyad;Telefon\nA;1\n', ImportKind.people, name: 'ADLI.CSV'), isA<ParseDone>());
      expect(_run('Ad Soyad;Telefon\nA;1\n', ImportKind.people, name: 'uzantisiz'), isA<ParseDone>());
    });

    test('OLE içerikli dosya (uzantı .csv olsa da) .xls iletisi verir', () {
      final out = runParse(
        ParseRequest(
          bytes: Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0]),
          fileName: 'gizli.csv',
          kind: ImportKind.people,
          spec: spec,
        ),
      );
      expect((out as ParseFailed).message, contains('.xls'));
    });

    test('5 MB üstü CSV hızlı reddedilir', () {
      final big = Uint8List(SheetLimits.maxCsvBytes + 1)..fillRange(0, SheetLimits.maxCsvBytes + 1, 0x61);
      final sw = Stopwatch()..start();
      final out = runParse(ParseRequest(bytes: big, fileName: 'b.csv', kind: ImportKind.people, spec: spec));
      expect((out as ParseFailed).code, 'FILE_TOO_LARGE');
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('5.000 satırdan uzun CSV (5 MB altı) satır sınırı iletisiyle reddedilir, 2 sn altında', () {
      final sb = StringBuffer('Ad Soyad;Telefon\n');
      for (var i = 0; i < 20000; i++) {
        sb.write('K$i;5\n');
      }
      final sw = Stopwatch()..start();
      final out = _run(sb.toString(), ImportKind.people);
      expect((out as ParseFailed).code, 'FILE_LIMIT');
      expect(out.message, contains('5000'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('kapanmamış tırnaklı CSV: ParseFailed (istisna fırlatılmaz)', () {
      final out = _run('Ad Soyad;Telefon\nAli;"5\nVeli;6\n', ImportKind.people);
      expect(out, isA<ParseFailed>());
      expect((out as ParseFailed).message, contains('kapanmamış tırnak'));
    });

    test('formül hücreleri CSV\'de olduğu gibi taşınır (kaçışsız, sunucu reddeder)', () {
      final out = _run('Ad Soyad;Not\n=cmd|calc;@x\n', ImportKind.people) as ParseDone;
      final people = spec.of(ImportKind.people)!;
      final r = extractImportRows(out.table, out.header.mapping, people).rows.single;
      expect(r.cells['ad_soyad'], '=cmd|calc');
      expect(r.cells['not'], '@x');
    });

    test('birden çok sayfalı XLSX: adı tutan sayfa seçilir, yoksa kullanıcıya liste', () {
      final bytes = handMadeXlsx(
        sheetName: 'Açıklama',
        rows: [row(1, [iCell('A1', 'bilgi')])],
        extraSheets: [
          ('Kişiler', [row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Telefon')]), row(2, [iCell('A2', 'Ali'), iCell('B2', '1')])]),
          ('Diğer', [row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Telefon')])]),
        ],
      );
      final ok = runParse(ParseRequest(bytes: bytes, fileName: 'a.xlsx', kind: ImportKind.people, spec: spec));
      expect((ok as ParseDone).table.sheetName, 'Kişiler');
      expect(ok.sheetNames, <String>['Açıklama', 'Kişiler', 'Diğer']);

      final ask = runParse(ParseRequest(bytes: bytes, fileName: 'a.xlsx', kind: ImportKind.vehicles, spec: spec));
      expect(ask, isA<ParseNeedsSheet>());
      expect((ask as ParseNeedsSheet).sheetNames, <String>['Açıklama', 'Kişiler', 'Diğer']);

      final chosen = runParse(
        ParseRequest(bytes: bytes, fileName: 'a.xlsx', kind: ImportKind.people, spec: spec, sheetName: 'Diğer'),
      );
      expect(chosen, isA<ParseDone>());
      final missing = runParse(
        ParseRequest(bytes: bytes, fileName: 'a.xlsx', kind: ImportKind.people, spec: spec, sheetName: 'Yok'),
      );
      expect(missing, isA<ParseFailed>());
    });

    test('XLSX içeriği .csv adıyla gelse de içerik kazanır', () {
      final bytes = handMadeXlsx(
        rows: [row(1, [iCell('A1', 'Ad Soyad'), iCell('B1', 'Telefon')]), row(2, [iCell('A2', 'Ali'), iCell('B2', '5')])],
      );
      final out = runParse(ParseRequest(bytes: bytes, fileName: 'x.csv', kind: ImportKind.people, spec: spec));
      expect((out as ParseDone).isXlsx, isTrue);
    });

    test('boş sayfa dürüst hata verir', () {
      final bytes = handMadeXlsx(rows: <String>[]);
      final out = runParse(ParseRequest(bytes: bytes, fileName: 'x.xlsx', kind: ImportKind.people, spec: spec));
      expect((out as ParseFailed).code, 'FILE_EMPTY');
    });

    test('bozuk zip ParseFailed döner (istisna fırlatmaz)', () {
      final out = runParse(
        ParseRequest(
          bytes: Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5, 6]),
          fileName: 'x.xlsx',
          kind: ImportKind.people,
          spec: spec,
        ),
      );
      expect(out, isA<ParseFailed>());
    });
  });
}

List<int> latin(String s) => s.codeUnits;
