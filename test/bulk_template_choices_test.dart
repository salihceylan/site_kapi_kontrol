// Toplu yükleme şablonu: SEÇİM LİSTELERİ (Excel veri doğrulaması: İlişki, Borç Sorumlusu, Hesap) ve KALDIRILAN «Kullanıcı Adı» sütunu.
//
// XLSX yazıcının `<dataValidations>` öğesi OOXML şemasındaki yerinde olmalı (Excel onarım penceresi açmasın): CT_Worksheet sırası
// sheetViews, sheetFormatPr, cols, sheetData, dataValidations, pageMargins. Ek olarak dosya, scratchpad'de `openpyxl` ile yüklenerek doğrulanmıştır
// (bu test dosyası kendi başına şemayı eleman sırası ve nitelikleriyle denetler).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_choices.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';
import 'package:xml/xml.dart';

import 'bulk_test_support.dart';

ImportSpec _serverSpec() =>
    ImportSpec.fromJson(jsonDecode(File('test/fixtures/bulk/server_spec.json').readAsStringSync()) as Map<String, dynamic>);

/// XLSX içindeki sayfa XML'leri: sayfa adı -> belge.
Map<String, XmlDocument> _sheets(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String textOf(String name) => utf8.decode(archive.findFile(name)!.content as List<int>);
  final workbook = XmlDocument.parse(textOf('xl/workbook.xml'));
  final out = <String, XmlDocument>{};
  var index = 1;
  for (final sheet in workbook.findAllElements('sheet')) {
    out[sheet.getAttribute('name')!] = XmlDocument.parse(textOf('xl/worksheets/sheet$index.xml'));
    index++;
  }
  return out;
}

List<String> _childOrder(XmlDocument sheet) => <String>[for (final e in sheet.rootElement.childElements) e.name.local];

/// Yalnız giriş ipucu olan (türsüz) doğrulamalar: sqref -> nitelikler.
List<({String sqref, Map<String, String> attrs})> _prompts(XmlDocument sheet) => <({String sqref, Map<String, String> attrs})>[
  for (final v in sheet.findAllElements('dataValidation').where((e) => e.getAttribute('type') == null))
    (sqref: v.getAttribute('sqref')!, attrs: <String, String>{for (final a in v.attributes) a.name.local: a.value}),
];

/// Sayfadaki liste doğrulamaları: sqref -> (liste sabiti, nitelikler).
List<({String sqref, String list, Map<String, String> attrs})> _validations(XmlDocument sheet) => <({String sqref, String list, Map<String, String> attrs})>[
  for (final v in sheet.findAllElements('dataValidation').where((e) => e.getAttribute('type') == 'list'))
    (
      sqref: v.getAttribute('sqref')!,
      list: v.getElement('formula1')!.innerText,
      attrs: <String, String>{for (final a in v.attributes) a.name.local: a.value},
    ),
];

String _letters(int index) => String.fromCharCode(0x41 + index);

void main() {
  group('XLSX yazıcı: <dataValidations>', () {
    final sheet = XlsxSheet(
      name: 'Kişiler',
      columns: <XlsxColumn>[
        const XlsxColumn('Ad Soyad*'),
        XlsxColumn(
          'İlişki',
          listValidation: XlsxListValidation(
            choices: const <String>['Malik', 'Kiracı', 'Aile Üyesi', 'Sakin'],
            promptTitle: 'İlişki',
            prompt: 'Açılır listeden seçin.',
            error: 'Yalnız listedeki değerler & "tırnaklı" <deneme>.',
          ),
        ),
        const XlsxColumn('Telefon'),
        XlsxColumn('Sorumlu', listValidation: XlsxListValidation(choices: const <String>['Malik', 'Kiracı', 'İkisi'])),
      ],
      rows: const <List<Object?>>[
        <Object?>['Ali', 'Malik', '555', null],
      ],
    );

    test('öğe sırası OOXML şemasındadır: sheetData -> dataValidations -> pageMargins; dimension / sheetViews / cols önce', () {
      final doc = _sheets(buildXlsx(<XlsxSheet>[sheet]))['Kişiler']!;
      final order = _childOrder(doc);
      expect(order, <String>['dimension', 'sheetViews', 'sheetFormatPr', 'cols', 'sheetData', 'dataValidations', 'pageMargins']);
    });

    test('her liste sütunu için TEK dataValidation: tür list, durdur stili, boş izinli, ipucu + hata gösterilir; sqref 2..5001; liste sabiti virgüllü', () {
      final doc = _sheets(buildXlsx(<XlsxSheet>[sheet]))['Kişiler']!;
      expect(doc.findAllElements('dataValidations').single.getAttribute('count'), '2');
      final v = _validations(doc);
      expect(v.map((e) => e.sqref), <String>['B2:B5001', 'D2:D5001']);
      expect(v[0].list, '"Malik,Kiracı,Aile Üyesi,Sakin"');
      expect(v[1].list, '"Malik,Kiracı,İkisi"');
      for (final e in v) {
        expect(e.attrs['type'], 'list');
        expect(e.attrs['errorStyle'], 'stop');
        expect(e.attrs['allowBlank'], '1');
        expect(e.attrs['showInputMessage'], '1');
        expect(e.attrs['showErrorMessage'], '1');
        expect(e.attrs.containsKey('showDropDown'), isFalse, reason: 'showDropDown=1 oku GİZLER (ters anlamlı): hiç yazılmaz');
      }
      expect(v[0].attrs['promptTitle'], 'İlişki');
      expect(v[0].attrs['prompt'], 'Açılır listeden seçin.');
      expect(v[0].attrs['errorTitle'], 'Geçersiz değer');
      expect(v[0].attrs['error'], 'Yalnız listedeki değerler & "tırnaklı" <deneme>.', reason: 'nitelik değerleri XML kaçışlıdır ve geri okununca aynıdır');
    });

    test('liste doğrulaması yoksa <dataValidations> yazılmaz; liste son satırı veri satırı sayısına uyar (5000 satırdan fazlada genişler)', () {
      final plain = XlsxSheet(name: 'A', columns: const <XlsxColumn>[XlsxColumn('X')], rows: const <List<Object?>>[]);
      expect(_childOrder(_sheets(buildXlsx(<XlsxSheet>[plain]))['A']!), isNot(contains('dataValidations')));
      final big = XlsxSheet(
        name: 'B',
        columns: <XlsxColumn>[XlsxColumn('L', listValidation: XlsxListValidation(choices: const <String>['a', 'b']))],
        rows: List<List<Object?>>.generate(6000, (i) => <Object?>['a']),
      );
      expect(_validations(_sheets(buildXlsx(<XlsxSheet>[big]))['B']!).single.sqref, 'A2:A6001');
      final small = XlsxSheet(
        name: 'C',
        columns: <XlsxColumn>[XlsxColumn('L', listValidation: XlsxListValidation(choices: const <String>['a', 'b']))],
        rows: const <List<Object?>>[],
        validationLastRow: 301,
      );
      expect(_validations(_sheets(buildXlsx(<XlsxSheet>[small]))['C']!).single.sqref, 'A2:A301');
    });

    test('Excel sınırları: virgül / tırnak / boş öğe, 255 karakteri aşan liste, uzun başlık / ileti ArgumentError (şablon bozuk üretilemez)', () {
      expect(() => XlsxListValidation(choices: const <String>['a,b']), throwsArgumentError);
      expect(() => XlsxListValidation(choices: const <String>['a"b']), throwsArgumentError);
      expect(() => XlsxListValidation(choices: const <String>[' ']), throwsArgumentError);
      expect(() => XlsxListValidation(choices: const <String>[]), throwsArgumentError);
      expect(() => XlsxListValidation(choices: <String>['x' * 128, 'y' * 128]), throwsArgumentError);
      expect(() => XlsxListValidation(choices: <String>['x' * 127, 'y' * 127]), returnsNormally);
      expect(() => XlsxListValidation(choices: const <String>['a'], promptTitle: 'x' * 33), throwsArgumentError);
      expect(() => XlsxListValidation(choices: const <String>['a'], error: 'x' * 256), throwsArgumentError);
    });

    test('dosya kendi okuyucumuzla da açılır (doğrulama veri okumayı bozmaz)', () {
      final reader = XlsxReader.open(buildXlsx(<XlsxSheet>[sheet]));
      final table = reader.readSheet(reader.sheets.first);
      expect(table.rows.first.cells, <Object?>['Ad Soyad*', 'İlişki', 'Telefon', 'Sorumlu']);
      expect(table.rows[1].cells.take(3), <Object?>['Ali', 'Malik', '555']);
    });
  });

  group('şablon: seçim listeleri', () {
    final spec = _serverSpec();
    final apartments = ExportEnvelope.fromJson(apartmentsEnvelopeJson());

    test('KLASİK şablon: Kişiler.İlişki ve Daireler.Borç Sorumlusu açılır liste; araçlar sayfasında yok', () {
      final f = buildImportTemplate(spec: spec, kind: ImportKind.people, format: ExportFormat.xlsx, apartments: apartments);
      final sheets = _sheets(f.bytes);
      expect(sheets.keys, <String>['Kişiler', 'Daireler', 'Araçlar', 'Açıklama']);

      final people = spec.of(ImportKind.people)!.columns.where((c) => !kExcludedTemplateKeys.contains(c.key)).toList();
      final iliskiIndex = people.indexWhere((c) => c.key == 'iliski');
      final peopleV = _validations(sheets['Kişiler']!);
      expect(peopleV, hasLength(1));
      expect(peopleV.single.sqref, '${_letters(iliskiIndex)}2:${_letters(iliskiIndex)}5001');
      expect(peopleV.single.list, '"Malik,Kiracı,Aile Üyesi,Sakin"');
      expect(peopleV.single.attrs['prompt'], contains('Açılır listeden seçin'));
      expect(peopleV.single.attrs['error'], contains('Malik, Kiracı, Aile Üyesi, Sakin'));

      final apt = spec.of(ImportKind.apartments)!.columns.where((c) => !kExcludedTemplateKeys.contains(c.key)).toList();
      final sorumluIndex = apt.indexWhere((c) => c.key == 'sorumlu');
      final aptV = _validations(sheets['Daireler']!);
      expect(aptV.single.sqref, '${_letters(sorumluIndex)}2:${_letters(sorumluIndex)}5001');
      expect(aptV.single.list, '"Malik,Kiracı,İkisi"');

      expect(_validations(sheets['Araçlar']!), isEmpty);
      expect(_validations(sheets['Açıklama']!), isEmpty);
      for (final doc in sheets.values) {
        final order = _childOrder(doc);
        if (order.contains('dataValidations')) {
          expect(order.indexOf('sheetData') < order.indexOf('dataValidations') && order.indexOf('dataValidations') < order.indexOf('pageMargins'), isTrue);
        }
      }
    });

    test('HEPSİ BİR ARADA şablonu: İlişki ve Borç Sorumlusu ikisi de açılır liste', () {
      final f = buildImportTemplate(spec: spec, kind: ImportKind.allInOne, format: ExportFormat.xlsx, apartments: apartments);
      final sheets = _sheets(f.bytes);
      expect(sheets.keys, <String>['Hepsi bir arada', 'Açıklama']);
      final v = _validations(sheets['Hepsi bir arada']!);
      expect(v.map((e) => e.list), <String>['"Malik,Kiracı,İkisi"', '"Malik,Kiracı,Aile Üyesi,Sakin"']);
      final cols = spec.of(ImportKind.allInOne)!.columns.where((c) => !kExcludedTemplateKeys.contains(c.key)).toList();
      final expected = <String>[
        for (final c in cols)
          if (choicesFor(c).isNotEmpty) '${_letters(cols.indexOf(c))}2:${_letters(cols.indexOf(c))}5001',
      ];
      expect(v.map((e) => e.sqref).toList(), expected);
    });

    test('DEVİR BAKİYESİ şablonu: Hesap sütunu açılır liste (Ev sahibi, Kiracı)', () {
      final f = buildImportTemplate(spec: spec, kind: ImportKind.openingBalances, format: ExportFormat.xlsx, apartments: apartments);
      final v = _validations(_sheets(f.bytes).values.first);
      expect(v.single.list, '"Ev sahibi,Kiracı"');
    });

    test('her şablon türünde TÜM enum sütunları kapsanır (spec\'ten hesaplanır: listesi olan sütun sayısı = doğrulama sayısı)', () {
      for (final kind in ImportKind.values) {
        final f = buildImportTemplate(spec: spec, kind: kind, format: ExportFormat.xlsx, apartments: apartments);
        final sheets = _sheets(f.bytes);
        final reader = XlsxReader.open(f.bytes);
        for (final ref in reader.sheets) {
          final sheetKind = ImportKind.values.where((k) => k.sheetName == ref.name).firstOrNull;
          if (sheetKind == null) continue; // Açıklama
          final columns = spec.of(sheetKind)!.columns.where((c) => !kExcludedTemplateKeys.contains(c.key));
          final enumCount = columns.where((c) => c.type == ImportColumnType.enumeration).length;
          expect(_validations(sheets[ref.name]!), hasLength(enumCount), reason: '${kind.apiValue}/${ref.name}');
        }
      }
    });

    test('PLAKA sütunları (Kişiler, Araçlar, Hepsi bir arada) biçim ipucu taşır; değeri kısıtlamaz (tür yok), liste doğrulamasıyla karışmaz', () {
      for (final entry in <(ImportKind, String)>[(ImportKind.people, 'Kişiler'), (ImportKind.allInOne, 'Hepsi bir arada')]) {
        final f = buildImportTemplate(spec: spec, kind: entry.$1, format: ExportFormat.xlsx, apartments: apartments);
        final sheets = _sheets(f.bytes);
        final cols = spec.of(entry.$1)!.columns.where((c) => !kExcludedTemplateKeys.contains(c.key)).toList();
        final plateIndex = cols.indexWhere((c) => c.key == 'plaka');
        final prompts = _prompts(sheets[entry.$2]!);
        expect(prompts, hasLength(1), reason: entry.$2);
        expect(prompts.single.sqref, '${_letters(plateIndex)}2:${_letters(plateIndex)}5001');
        expect(prompts.single.attrs['prompt'], '34 ABC 123; il kodu 01-81, 1-3 harf, 2-4 rakam; birden çok plaka virgülle, en çok 5');
        expect(prompts.single.attrs['showInputMessage'], '1');
        expect(prompts.single.attrs.containsKey('showErrorMessage'), isFalse);
        final order = _childOrder(sheets[entry.$2]!);
        expect(order.indexOf('sheetData') < order.indexOf('dataValidations') && order.indexOf('dataValidations') < order.indexOf('pageMargins'), isTrue);
      }
      final vehicles = _sheets(buildImportTemplate(spec: spec, kind: ImportKind.vehicles, format: ExportFormat.xlsx, apartments: apartments).bytes);
      expect(_prompts(vehicles['Araçlar']!), hasLength(1));
      expect(_validations(vehicles['Araçlar']!), isEmpty);
      // Açıklama sayfası biçimi anlatır.
      final text = vehicles['Açıklama']!.toXmlString();
      expect(text, contains('Türk plakası biçiminde'));
    });

    test('doğrulama sınırı spec.maxRows + 1 satırdır (sunucu satır sınırı küçültülmüşse liste de o kadar)', () {
      final small = ImportSpec.fromJson(<String, dynamic>{
        ...(jsonDecode(File('test/fixtures/bulk/server_spec.json').readAsStringSync()) as Map<String, dynamic>),
        'max_rows': 300,
      });
      final f = buildImportTemplate(spec: small, kind: ImportKind.people, format: ExportFormat.xlsx);
      expect(_validations(_sheets(f.bytes)['Kişiler']!).single.sqref, endsWith('301'));
    });

    test('ESKİ sunucu (choices göndermez): istemci yedek listeleri kullanılır; liste yine açılır liste olur', () {
      final f = buildImportTemplate(spec: testSpec(), kind: ImportKind.people, format: ExportFormat.xlsx);
      final v = _validations(_sheets(f.bytes)['Kişiler']!);
      expect(v.single.list, '"Malik,Kiracı,Aile Üyesi,Sakin"');
    });

    test('CSV şablonunda açılır liste YOKTUR (düz metin başlık satırı); Açıklama sayfası bunu söyler', () {
      final csv = buildImportTemplate(spec: spec, kind: ImportKind.people, format: ExportFormat.csv);
      final text = utf8.decode(csv.bytes);
      expect(text, isNot(contains('dataValidation')));
      expect(text.trim().split('\r\n').first, contains('İlişki'));
      final xlsx = buildImportTemplate(spec: spec, kind: ImportKind.people, format: ExportFormat.xlsx);
      final reader = XlsxReader.open(xlsx.bytes);
      final info = reader.readSheet(reader.sheets.last).rows.map((r) => r.cells.join(' ')).join('\n');
      expect(info, contains('Listeden seçin'));
      expect(info, contains('«İlişki»'));
      expect(info, contains('«Borç Sorumlusu»'));
      expect(info, contains('CSV dosyalarında açılır liste olmaz'));
    });
  });

  group('şablon: «Kullanıcı Adı» sütunu kaldırıldı (sistem verir)', () {
    final spec = _serverSpec();

    test('hiçbir şablon türünde başlık, örnek ya da ipucu olarak «Kullanıcı Adı» sütunu yok; Açıklama sayfası sistemin verdiğini anlatır', () {
      for (final kind in ImportKind.values) {
        for (final format in ExportFormat.values) {
          final f = buildImportTemplate(spec: spec, kind: kind, format: format);
          if (format == ExportFormat.csv) {
            expect(utf8.decode(f.bytes), isNot(contains('Kullanıcı Adı')), reason: '${kind.apiValue} csv');
            continue;
          }
          final reader = XlsxReader.open(f.bytes);
          for (final ref in reader.sheets) {
            final table = reader.readSheet(ref);
            if (ref.name == 'Açıklama') {
              final info = table.rows.map((r) => r.cells.join(' ')).join('\n');
              expect(info, isNot(contains('ahmet.yilmaz')), reason: 'örnek kullanıcı adı artık yok');
              expect(info, isNot(contains('Kullanıcı Adı*')));
              if (kind == ImportKind.people || kind == ImportKind.allInOne || kind == ImportKind.apartments) {
                // klasik grup: kişiler dahil; hepsi bir arada: kişi bölümü dahil
                expect(info, contains('Şablonda Kullanıcı Adı sütunu yoktur'), reason: kind.apiValue);
                expect(info, contains('ad_2, ad_3'));
              }
            } else {
              expect(table.rows.first.cells.whereType<String>().any((h) => h.contains('Kullanıcı')), isFalse, reason: '${kind.apiValue}/${ref.name}');
            }
          }
        }
      }
    });
  });

  group('seçim listesi yardımcıları', () {
    final spec = _serverSpec();
    ImportColumn col(ImportKind kind, String key) => spec.of(kind)!.column(key)!;

    test('choicesFor: yalnız enum sütunlar; sunucu listesi öncelikli, yoksa yedek', () {
      expect(choicesFor(col(ImportKind.people, 'iliski')), <String>['Malik', 'Kiracı', 'Aile Üyesi', 'Sakin']);
      expect(choicesFor(col(ImportKind.people, 'ad_soyad')), isEmpty);
      const bare = ImportColumn(key: 'sorumlu', label: 'Borç Sorumlusu', type: ImportColumnType.enumeration);
      expect(choicesFor(bare), <String>['Malik', 'Kiracı', 'İkisi']);
      const unknown = ImportColumn(key: 'baska', label: 'Başka', type: ImportColumnType.enumeration);
      expect(choicesFor(unknown), isEmpty);
    });

    test('matchChoice: listedeki etiket (Türkçe katlamalı) ve sunucunun kabul ettiği eşanlamlılar listedeki seçeneğe eşlenir', () {
      final people = spec.of(ImportKind.people);
      final iliski = col(ImportKind.people, 'iliski');
      expect(matchChoice(people, iliski, 'KİRACI'), 'Kiracı');
      expect(matchChoice(people, iliski, 'aile uyesi'), 'Aile Üyesi');
      expect(matchChoice(people, iliski, 'Eş'), 'Aile Üyesi');
      expect(matchChoice(people, iliski, 'Çocuk'), 'Aile Üyesi');
      expect(matchChoice(people, iliski, 'Mal sahibi'), 'Malik');
      expect(matchChoice(people, iliski, 'oturan'), 'Sakin');
      expect(matchChoice(people, iliski, 'Komşu'), isNull);
      expect(matchChoice(people, iliski, '  '), isNull);
      final apt = spec.of(ImportKind.apartments);
      final sorumlu = col(ImportKind.apartments, 'sorumlu');
      expect(matchChoice(apt, sorumlu, 'İkisi de'), 'İkisi');
      expect(matchChoice(apt, sorumlu, 'her ikisi'), 'İkisi');
      final hesap = col(ImportKind.openingBalances, 'hesap');
      final opening = spec.of(ImportKind.openingBalances);
      expect(matchChoice(opening, hesap, 'Malik'), 'Ev sahibi');
      expect(matchChoice(opening, hesap, 'mal sahibi'), 'Ev sahibi');
      expect(matchChoice(opening, hesap, 'kiraci'), 'Kiracı');
    });
  });
}
