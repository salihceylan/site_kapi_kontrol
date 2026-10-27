// İstemci modelleri GERÇEK sunucu çıktılarına karşı (Platform Faz 2b). `test/fixtures/bulk/*.json` dosyaları S-2b'nin
// sunucu modüllerinden (buildSpec / computePlan, DB'siz) üretilmiştir; böylece sözleşme okuması ile gerçek yanıt
// arasındaki sapma burada yakalanır.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_file_parser.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_sheet_types.dart';
import 'package:site_kapi_kontrol/services/bulk_template.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/bulk/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late ImportSpec spec;

  setUpAll(() => spec = ImportSpec.fromJson(_fixture('server_spec.json')));

  group('sunucu şeması', () {
    test('çözülür; zorunlu sütunlar, tipler ve sözlükler sözleşmeye uyar', () {
      expect(spec.specVersion, 1);
      expect(spec.maxRows, 5000);
      expect(spec.maxBodyBytes, 5 * 1024 * 1024);
      final apt = spec.of(ImportKind.apartments)!;
      expect(apt.columns.map((c) => c.key), <String>[
        'blok', 'daire_no', 'kat', 'tip', 'arsa_payi_pay', 'arsa_payi_payda', 'sorumlu',
      ]);
      expect(apt.requiredColumns.map((c) => c.key), <String>['blok', 'daire_no']);
      expect(apt.column('arsa_payi_pay')!.type, ImportColumnType.number);
      expect(apt.column('brut_m2'), isNull, reason: 'm² sütunları kaldırıldı');
      expect(apt.column('sorumlu')!.type, ImportColumnType.enumeration);
      final people = spec.of(ImportKind.people)!;
      expect(people.requiredColumns.map((c) => c.key), <String>['ad_soyad']);
      expect(people.column('giris_tarihi')!.type, ImportColumnType.date);
      expect(people.relationWords['owner'], containsAll(<String>['Malik', 'Mal sahibi', 'Ev sahibi']));
      expect(people.relationWords.keys, containsAll(<String>['owner', 'tenant', 'family_member', 'resident']));
      expect(spec.of(ImportKind.vehicles)!.requiredColumns.map((c) => c.key), <String>['plaka']);
      expect(apt.responsibleWords['both'], containsAll(<String>['İkisi', 'Her ikisi']));
    });

    test('hesap sütunu (sifre) YALNIZ kişi türlerinde tanımlıdır; araç, daire ve devir bakiyesi satırına eklenmez; KULLANICI ADI sütunu hiçbir türde YOK (sistem verir)', () {
      for (final kind in <ImportKind>[ImportKind.people, ImportKind.allInOne]) {
        final keys = spec.of(kind)!.columns.map((c) => c.key).toSet();
        expect(keys, contains('sifre'), reason: kind.apiValue);
      }
      for (final kind in <ImportKind>[ImportKind.vehicles, ImportKind.openingBalances, ImportKind.apartments]) {
        final keys = spec.of(kind)!.columns.map((c) => c.key).toSet();
        expect(keys.intersection(<String>{'sifre'}), isEmpty, reason: kind.apiValue);
      }
      for (final kind in ImportKind.values) {
        final keys = spec.of(kind)!.columns.map((c) => c.key).toSet();
        expect(keys, isNot(contains('kullanici_adi')), reason: kind.apiValue);
        expect(keys, isNot(contains('giris_adi')), reason: kind.apiValue);
        expect(spec.of(kind)!.columns.any((c) => c.key == 'brut_m2' || c.key == 'net_m2'), isFalse, reason: kind.apiValue);
      }
    });

    test('SEÇİM LİSTELERİ: sunucu her enum sütununa choices verir; istemci aynısını şablona koyar (Malik, Kiracı, Aile Üyesi, Sakin ...)', () {
      final people = spec.of(ImportKind.people)!;
      expect(people.column('iliski')!.choices, <String>['Malik', 'Kiracı', 'Aile Üyesi', 'Sakin']);
      expect(spec.of(ImportKind.apartments)!.column('sorumlu')!.choices, <String>['Malik', 'Kiracı', 'İkisi']);
      expect(spec.of(ImportKind.allInOne)!.column('sorumlu')!.choices, <String>['Malik', 'Kiracı', 'İkisi']);
      expect(spec.of(ImportKind.openingBalances)!.column('hesap')!.choices, <String>['Ev sahibi', 'Kiracı']);
      for (final kind in ImportKind.values) {
        for (final column in spec.of(kind)!.columns) {
          expect(column.choices.isNotEmpty, column.type == ImportColumnType.enumeration, reason: '${kind.apiValue}.${column.key}');
          if (column.type == ImportColumnType.enumeration) {
            expect(column.hint, startsWith('Listeden seçin'), reason: '${kind.apiValue}.${column.key}');
          }
        }
      }
    });

    test('gerçek takma adlarla tipik Türkçe Excel başlıkları eşlenir', () {
      final people = spec.of(ImportKind.people)!;
      final table = SheetTable(
        rows: <SheetRow>[
          const SheetRow(1, <Object?>[
            'Adı Soyadı', 'Cep Telefonu', 'Email', 'Blok Adı', 'Kapı No', 'İlişki Türü', 'Taşınma Tarihi', 'Araç Plakaları', 'Yönetici Notu', 'Bilinmeyen',
          ]),
          const SheetRow(2, <Object?>['Ali', '5', 'a@b.c', 'A', '1', 'Malik', null, null, null, null]),
        ],
      );
      final found = detectHeader(table, people)!;
      expect(found.mapping.canProceed(people), isTrue);
      expect(found.mapping.conflicts, isEmpty);
      expect(found.mapping.assignment.entries.where((e) => e.value != null).length, 9);
      expect(found.mapping.ignoredColumns(), <int>[9]);
    });

    test('Türkçe büyük harf / İ-ı ve boşluksuz başlıklar tanınır', () {
      final apt = spec.of(ImportKind.apartments)!;
      final table = SheetTable(
        rows: <SheetRow>[
          const SheetRow(1, <Object?>['BLOK', 'DAİRE NO', 'KAT', 'TİP', 'ARSAPAYI(PAY)', 'Arsa Payı Payda', 'SORUMLU', 'BRÜT M2']),
        ],
      );
      final found = detectHeader(table, apt)!;
      final a = found.mapping.assignment;
      expect(a['blok'], 0);
      expect(a['daire_no'], 1);
      expect(a['kat'], 2);
      expect(a['tip'], 3);
      expect(a['arsa_payi_pay'], 4);
      expect(a['arsa_payi_payda'], 5);
      expect(a['sorumlu'], 6);
      expect(found.mapping.ignoredColumns(), <int>[7], reason: 'eski m² sütunu eşlenmez, yok sayılır (sunucuya gitmez)');
    });
  });

  group('sunucu önizlemeleri', () {
    test('kişiler: toplamlar, sorun kodları, örnekler, plan', () {
      final p = ImportPreview.fromJson(_fixture('server_preview_people.json'));
      expect(p.kind, ImportKind.people);
      expect(p.previewHash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(p.totals.rows, 5);
      expect(p.totals.ok, 3);
      expect(p.totals.error, 2);
      expect(p.totals.withWarnings, 1);
      expect(p.issues.where((i) => i.isError).map((i) => i.code), containsAll(<String>['FORMULA_LIKE']));
      expect(p.issues.every((i) => i.n >= 2 && i.message.isNotEmpty), isTrue);
      expect(p.samples.first.action, 'create');
      expect(p.plan['people_create'], 3);
      expect(p.issuesTruncated, isFalse);
      expect(p.landShare, isNull);
      expect(p.chips().first.label, 'Eklenecek');
      expect(p.planStats().map((s) => s.label), contains('Yeni kişi'));
    });

    test('daireler: plan anahtarları ve arsa payı kontrolü alanı', () {
      final p = ImportPreview.fromJson(_fixture('server_preview_apartments.json'));
      expect(p.kind, ImportKind.apartments);
      expect(p.plan.keys, containsAll(<String>['apartment_update', 'cells_set', 'overwritten_cells', 'cells_kept']));
      expect(p.chips().first.label, 'Güncellenecek');
      expect(p.issues.map((i) => i.code), contains('BLOCK_NOT_FOUND'));
    });

    test('sunucunun land_share nesnesi {sum, denominator, complete, message} okunur', () {
      final c = LandShareCheck.tryParse(<String, dynamic>{
        'sum': 987,
        'denominator': 1000,
        'complete': false,
        'message': '987/1000: eksik olabilir',
      })!;
      expect(c.complete, isFalse);
      expect(c.message, '987/1000: eksik olabilir');
      expect(LandShareCheck.tryParse(<String, dynamic>{'sum': 1000, 'denominator': 1000, 'complete': true, 'message': '1000/1000 ✓'})!.complete, isTrue);
    });
  });

  group('sunucu sınırlarına uyum', () {
    test('|değer| ≥ 1e15 sayı METİN olarak gider (sunucu aksi halde TÜM isteği 400 yapar)', () {
      const column = ImportColumn(key: 'telefon', label: 'Telefon');
      expect(normalizeImportCell(1e20, column), '100000000000000000000');
      expect(normalizeImportCell(3000000000000000, column), '3000000000000000');
      expect(normalizeImportCell(999999999999999, column), 999999999999999);
      expect(normalizeImportCell(1e30, column), isA<String>());
      expect(normalizeImportCell(5551234567, column), 5551234567);
    });

    test('uzun hücre 601 karakterde kesilir (sunucu TOO_LONG üretir; 5000 üstü gövde hatası olurdu)', () {
      final out = runParse(
        ParseRequest(
          bytes: Uint8List.fromList(utf8.encode('Ad Soyad;Not\nAli;${'x' * 9000}\n')),
          fileName: 'a.csv',
          kind: ImportKind.people,
          spec: spec,
        ),
      ) as ParseDone;
      final rows = extractImportRows(out.table, out.header.mapping, spec.of(ImportKind.people)!).rows;
      expect((rows.single.cells['not']! as String).length, 601);
    });
  });

  group('şablon', () {
    test('gerçek şemadan XLSX ve CSV şablonu üretilir; Açıklama sayfası ilişki ve borç sözlüğünü içerir', () {
      final xlsx = buildImportTemplate(spec: spec, kind: ImportKind.people, format: ExportFormat.xlsx);
      expect(xlsx.bytes.length, greaterThan(2000));
      final reader = XlsxReader.open(xlsx.bytes);
      final info = reader.readSheet(reader.sheets.last);
      final text0 = info.rows.map((r) => r.cells.join(' ')).join('\n');
      expect(text0, contains('İlişki sözlüğü'));
      expect(text0, contains('Borç sorumlusu sözlüğü'));
      expect(text0, contains('Her ikisi'));
      expect(text0, contains('Mal sahibi'));
      final csv = buildImportTemplate(spec: spec, kind: ImportKind.vehicles, format: ExportFormat.csv);
      final text = utf8.decode(csv.bytes.sublist(3));
      // Zorunlu sütun «*» ile işaretlenir; isteğe bağlı «Not» şablonda gizlidir (kExcludedTemplateKeys).
      expect(text, startsWith('Plaka*;E-posta;Blok;Daire No;Ad Soyad\r\n'));
    });
  });
}
