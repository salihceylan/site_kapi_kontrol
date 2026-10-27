// Toplu yükleme modelleri (lib/models/bulk_import.dart): savunmacı çözümleme ve türev değerler.
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';

import 'bulk_test_support.dart';

void main() {
  group('ImportSpec', () {
    test('tam örnek çözülür; sütun sırası ve zorunlular korunur', () {
      final spec = ImportSpec.fromJson(specJson());
      expect(spec.specVersion, 1);
      expect(spec.maxRows, 5000);
      expect(spec.of(ImportKind.apartments)!.columns.first.key, 'blok');
      expect(spec.of(ImportKind.apartments)!.requiredColumns.map((c) => c.key), <String>['blok', 'daire_no']);
      expect(spec.of(ImportKind.people)!.column('not')!.maxLength, 500);
      expect(spec.of(ImportKind.vehicles)!.column('plaka')!.required, isTrue);
    });

    test('bilinmeyen tür atlanır; hiç tür yoksa hata', () {
      final json = specJson();
      (json['kinds'] as Map<String, dynamic>)['garip'] = <String, dynamic>{'columns': <Object>[]};
      expect(ImportSpec.fromJson(json).kinds.length, 3);
      expect(() => ImportSpec.fromJson(<String, dynamic>{'spec_version': 1, 'kinds': <String, dynamic>{}}), throwsFormatException);
      expect(() => ImportSpec.fromJson(<String, dynamic>{'kinds': <String, dynamic>{}}), throwsFormatException);
    });

    test('boş sütun listesi ve anahtarsız sütun hata; yinelenen anahtar tekilleşir', () {
      final json = specJson();
      final apt = (json['kinds'] as Map<String, dynamic>)['apartments'] as Map<String, dynamic>;
      (apt['columns'] as List).add(<String, dynamic>{'key': 'blok', 'label': 'Yinelenen'});
      expect(ImportSpec.fromJson(json).of(ImportKind.apartments)!.columns.where((c) => c.key == 'blok').length, 1);
      (apt['columns'] as List).add(<String, dynamic>{'label': 'Anahtarsız'});
      expect(() => ImportSpec.fromJson(json), throwsFormatException);
    });

    test('max_rows sunucu 5000 üstü verirse 5000\'e düşer; geçersiz/eksik varsayılana', () {
      final j = specJson()..['max_rows'] = 99999;
      expect(ImportSpec.fromJson(j).maxRows, 5000);
      final k = specJson()..['max_rows'] = 'x';
      expect(ImportSpec.fromJson(k).maxRows, 5000);
      final l = specJson()..['max_rows'] = 200;
      expect(ImportSpec.fromJson(l).maxRows, 200);
    });

    test('ilişki sözlüğü iki biçimi de kabul eder', () {
      final a = ImportKindSpec.fromJson(<String, dynamic>{
        'columns': <Map<String, dynamic>>[<String, dynamic>{'key': 'k', 'label': 'K'}],
        'relation_words': <String, dynamic>{'malik': 'owner', 'mal sahibi': 'owner', 'kiracı': 'tenant'},
      });
      expect(a.relationWords['owner'], <String>['malik', 'mal sahibi']);
      final b = ImportKindSpec.fromJson(<String, dynamic>{
        'columns': <Map<String, dynamic>>[<String, dynamic>{'key': 'k', 'label': 'K'}],
        'relation_words': 'bozuk',
      });
      expect(b.relationWords, isEmpty);
    });

    test('ImportKind yardımcıları', () {
      expect(ImportKind.people.needsAcknowledgement, isTrue);
      expect(ImportKind.vehicles.needsAcknowledgement, isTrue);
      expect(ImportKind.apartments.needsAcknowledgement, isFalse);
      expect(ImportKind.apartments.supportsOverwrite, isTrue);
      expect(ImportKind.people.supportsOverwrite, isFalse);
      expect(ImportKind.tryParse('people'), ImportKind.people);
      expect(ImportKind.tryParse('x'), isNull);
      expect(ImportKind.tryParse(null), isNull);
    });
  });

  group('ImportPreview', () {
    test('eksik özet / toplamlar / tür yapısal hatadır (boş önizleme üretilmez)', () {
      expect(() => ImportPreview.fromJson(<String, dynamic>{'kind': 'people'}), throwsFormatException);
      expect(
        () => ImportPreview.fromJson(<String, dynamic>{'kind': 'people', 'preview_hash': 'x'}),
        throwsFormatException,
      );
      expect(
        () => ImportPreview.fromJson(<String, dynamic>{
          'kind': 'bilinmeyen',
          'preview_hash': 'x',
          'totals': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });

    test('issues / samples / plan eksik ya da bozuksa boş liste olur', () {
      final p = ImportPreview.fromJson(<String, dynamic>{
        'kind': 'vehicles',
        'preview_hash': 'h',
        'totals': <String, dynamic>{'rows': 1},
        'issues': <Object?>['bozuk', <String, dynamic>{'n': 5, 'code': 'X', 'message': 'm'}],
        'plan': 'bozuk',
      });
      expect(p.issues.length, 1);
      expect(p.issues.single.severity, ImportSeverity.error, reason: 'bilinmeyen önem = hata (güvenli taraf)');
      expect(p.plan, isEmpty);
      expect(p.samples, isEmpty);
      expect(p.landShare, isNull);
    });

    test('issues_truncated bayrağı önizlemede ve sonuçta okunur', () {
      expect(ImportPreview.fromJson(previewJson()).issuesTruncated, isFalse);
      expect(ImportPreview.fromJson(previewJson()..['issues_truncated'] = true).issuesTruncated, isTrue);
      final json = commitJson();
      (json['result'] as Map<String, dynamic>)['issues_truncated'] = true;
      expect(ImportResult.fromJson(json).issuesTruncated, isTrue);
    });

    test('çipler türe göre: daire, kişi, araç', () {
      ImportPreview of(String kind, Map<String, dynamic> plan) =>
          ImportPreview.fromJson(previewJson(kind: kind, plan: plan));
      final apt = of('apartments', <String, dynamic>{'apartment_update': 7});
      expect(apt.chips().map((c) => c.label), <String>['Güncellenecek', 'Değişmeyecek', 'Hatalı', 'Uyarılı']);
      expect(apt.chips().first.count, 7);
      final veh = of('vehicles', <String, dynamic>{'vehicle_add': 3, 'vehicle_unchanged': 4});
      expect(veh.chips().map((c) => c.count).take(2), <int>[3, 4]);
      final ppl = of('people', <String, dynamic>{'people_create': 5, 'people_link': 2, 'people_reactivate': 1});
      expect(ppl.chips()[0].count, 5);
      expect(ppl.chips()[1].count, 3);
    });

    test('plan etiketleri yalnız sıfırdan büyükleri yazar', () {
      final p = ImportPreview.fromJson(
        previewJson(plan: <String, dynamic>{'people_create': 2, 'vehicle_add': 0, 'bilinmeyen_anahtar': 9}),
      );
      expect(p.planStats().map((s) => s.label), <String>['Yeni kişi']);
    });
  });

  group('ImportResult ve zarf', () {
    test('yapısal olarak bozuk sonuç hata', () {
      expect(() => ImportResult.fromJson(<String, dynamic>{'replayed': false}), throwsFormatException);
    });

    test('issues null (replay) ile boş liste ayrı anlamdadır', () {
      final replay = ImportResult.fromJson(commitJson(replayed: true, withIssues: false));
      expect(replay.issues, isNull);
      final json = commitJson();
      ((json['result'] as Map<String, dynamic>))['issues'] = <Object?>[];
      expect(ImportResult.fromJson(json).issues, isEmpty);
    });

    test('ExportColumn ölçeği sınırlı; ad yoksa hata', () {
      expect(ExportColumn.fromJson(<String, dynamic>{'key': 'a', 'label': 'A', 'type': 'number', 'scale': 99}).scale, isNull);
      expect(ExportColumn.fromJson(<String, dynamic>{'key': 'a', 'label': 'A', 'scale': 2}).scale, 2);
      expect(() => ExportColumn.fromJson(<String, dynamic>{'type': 'text'}), throwsFormatException);
      // Anahtar yoksa etiket anahtar olur.
      expect(ExportColumn.fromJson(<String, dynamic>{'label': 'Etiket'}).key, 'Etiket');
    });

    test('süzgeç sorgusu yalnız dolu alanları taşır', () {
      expect(const BulkExportFilters().toQuery(), isEmpty);
      expect(const BulkExportFilters(query: '  ', status: '').toQuery(), isEmpty);
      expect(
        const BulkExportFilters(query: ' ali ', apartmentId: 4, personId: 9).toQuery(),
        <String, String>{'q': 'ali', 'apartment_id': '4', 'person_id': '9'},
      );
    });
  });

  group('seçim listeleri, kullanıcı adı önerileri ve mali kayıt özeti', () {
    test('ImportColumn.choices: sunucu listesi okunur (boşluk kırpılır, boş / metin olmayan öğe atılır); yoksa boş', () {
      final column = ImportColumn.fromJson(<String, dynamic>{
        'key': 'iliski',
        'label': 'İlişki',
        'type': 'enum',
        'choices': <Object?>[' Malik ', 'Kiracı', '', 5, null, 'Sakin'],
      });
      expect(column.choices, <String>['Malik', 'Kiracı', 'Sakin']);
      expect(ImportColumn.fromJson(<String, dynamic>{'key': 'ad_soyad', 'label': 'Ad Soyad'}).choices, isEmpty);
      expect(ImportColumn.fromJson(<String, dynamic>{'key': 'x', 'label': 'X', 'choices': 'Malik'}).choices, isEmpty);
    });

    test('ImportPreview.accounts: durumlar çözülür, accountsProvided alanın varlığını söyler (eski sunucuda yok)', () {
      final withAccounts = ImportPreview.fromJson(<String, dynamic>{
        ...previewJson(),
        'accounts': <Map<String, dynamic>>[
          <String, dynamic>{'n': 2, 'status': 'new', 'login_name': 'ali.veli', 'editable': true, 'custom': true},
          <String, dynamic>{'n': 3, 'status': 'existing', 'login_name': 'mevcut'},
        ],
      });
      expect(withAccounts.accountsProvided, isTrue);
      expect(withAccounts.accounts.map((a) => (a.n, a.status, a.loginName, a.editable, a.custom)), <(int, AccountProposalStatus, String?, bool, bool)>[
        (2, AccountProposalStatus.create, 'ali.veli', true, true),
        (3, AccountProposalStatus.existing, 'mevcut', false, false),
      ]);
      final legacy = ImportPreview.fromJson(previewJson());
      expect(legacy.accountsProvided, isFalse);
      expect(legacy.accounts, isEmpty);
      final empty = ImportPreview.fromJson(<String, dynamic>{...previewJson(), 'accounts': <Object>[]});
      expect(empty.accountsProvided, isTrue, reason: 'boş liste = hesap açılmayacak (eski sunucu değil)');
    });

    test('LoginNameCheck: ok / TAKEN + öneri; eksik alanlarda savunmacı varsayılan', () {
      final taken = LoginNameCheck.fromJson(<String, dynamic>{'ok': false, 'code': 'TAKEN', 'login_name': 'a.b', 'message': 'Kayıtlı.', 'suggestion': 'a.b_2'});
      expect([taken.ok, taken.code, taken.loginName, taken.message, taken.suggestion], [false, 'TAKEN', 'a.b', 'Kayıtlı.', 'a.b_2']);
      final bare = LoginNameCheck.fromJson(<String, dynamic>{'ok': true});
      expect([bare.ok, bare.code, bare.suggestion], [true, 'OK', null]);
      expect(LoginNameCheck.fromJson(<String, dynamic>{}).ok, isFalse);
    });

    test('FinanceRecordsCheck: checks.finance_records okunur; sayı 0 / alan yok / biçim bozuk -> null; ileti yoksa yedek cümle', () {
      ImportPreview preview(Object? value) => ImportPreview.fromJson(<String, dynamic>{
        ...previewJson(),
        'checks': <String, dynamic>{'land_share': null, 'finance_records': value},
      });
      final ok = preview(<String, dynamic>{'apartments': 3, 'message': '3 dairenin mali kaydı var.'}).financeRecords!;
      expect([ok.apartments, ok.message], [3, '3 dairenin mali kaydı var.']);
      expect(preview(<String, dynamic>{'apartments': 2}).financeRecords!.message, startsWith('2 dairenin mali kaydı var;'));
      expect(preview(<String, dynamic>{'apartments': 0}).financeRecords, isNull);
      expect(preview(null).financeRecords, isNull);
      expect(preview('x').financeRecords, isNull);
      expect(ImportPreview.fromJson(previewJson()).financeRecords, isNull);
    });

    test('ImportKind.createsAccounts yalnız kişi türleri', () {
      expect(<ImportKind>[for (final k in ImportKind.values) if (k.createsAccounts) k], <ImportKind>[ImportKind.people, ImportKind.allInOne]);
    });
  });
}
