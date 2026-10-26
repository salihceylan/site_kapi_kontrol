// Toplu yükleme: başlangıç şifresi / kullanıcı adı zenginleştirmesi yalnız bu sütunları tanımlayan türlerde,
// sunucu ile aynı kullanıcı adı kuralı, «hepsi bir arada» yalnız daire satırının korunması, atlanan satır sayısı
// ve sonuçta nihai kullanıcı adları (Platform Faz 2b).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';

import 'bulk_fakes.dart';
import 'bulk_test_support.dart';

/// Gerçek sunucu şeması (test/fixtures/bulk/server_spec.json; sunucudaki buildSpec çıktısı).
ImportSpec _serverSpec() =>
    ImportSpec.fromJson(jsonDecode(File('test/fixtures/bulk/server_spec.json').readAsStringSync()) as Map<String, dynamic>);

class _Harness {
  _Harness(String fileName, String csv, {List<ImportKind> kinds = const <ImportKind>[]}) {
    api.spec = _serverSpec();
    controller = BulkImportController(
      service: BulkService(authService: auth, api: api),
      siteCode: 12,
      delivery: delivery,
      parseRunner: inlineParse,
      picker: fakePicker(fileName, utf8Bytes(csv)),
      purgePickerCache: () async {},
      allowedKinds: kinds,
    );
  }

  final FakeBulkAuth auth = FakeBulkAuth();
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  late final BulkImportController controller;

  Future<List<ImportRow>> toPreview(ImportKind kind) async {
    await controller.loadSpec();
    controller.selectKind(kind);
    controller.goToFileStep();
    await controller.pickAndParse();
    await controller.confirmMapping();
    return api.previewCalls.last.rows;
  }
}

Set<String> _keys(Iterable<ImportRow> rows) => <String>{for (final row in rows) ...row.cells.keys};

void main() {
  group('enrichImportRowsWithDefaults', () {
    const person = <String>{'ad_soyad', 'sifre', 'kullanici_adi'};
    List<ImportRow> rows(List<Map<String, Object?>> cells) => <ImportRow>[
      for (var i = 0; i < cells.length; i++) ImportRow(n: i + 2, cells: cells[i]),
    ];

    test('sütunu tanımlamayan tür (araçlar, devir bakiyesi, daireler): satırlara HİÇBİR anahtar eklenmez', () {
      final input = rows(<Map<String, Object?>>[
        <String, Object?>{'plaka': '34 ABC 123', 'ad_soyad': 'Ali Veli'},
        <String, Object?>{'blok': 'A', 'daire_no': '1', 'tutar': '100'},
      ]);
      for (final keys in <Set<String>>[
        <String>{'plaka', 'ad_soyad', 'blok'},
        <String>{'blok', 'daire_no', 'tutar', 'hesap'},
        <String>{'blok', 'daire_no', 'kat'},
      ]) {
        final out = enrichImportRowsWithDefaults(input, columnKeys: keys);
        expect(_keys(out), isNot(contains('sifre')));
        expect(_keys(out), isNot(contains('kullanici_adi')));
        expect(out.map((r) => r.cells), input.map((r) => r.cells));
      }
    });

    test('kişi türü: boş şifre 1234; ad soyaddan kullanıcı adı; aynı ad _2, _3; ad soyadsız satıra dokunulmaz', () {
      final out = enrichImportRowsWithDefaults(
        rows(<Map<String, Object?>>[
          <String, Object?>{'ad_soyad': 'Çağrı Öztürk'},
          <String, Object?>{'ad_soyad': 'Çağrı Öztürk', 'sifre': 'özel'},
          <String, Object?>{'ad_soyad': 'ÇAĞRI ÖZTÜRK'},
          <String, Object?>{'blok': 'A', 'daire_no': '1'}, // yalnız daire bilgisi: kişi değil
        ]),
        columnKeys: person,
      );
      expect(out[0].cells['kullanici_adi'], 'cagri.ozturk');
      expect(out[1].cells['kullanici_adi'], 'cagri.ozturk_2');
      expect(out[2].cells['kullanici_adi'], 'cagri.ozturk_3');
      expect(out.map((r) => r.cells['sifre']).take(3), <Object?>['1234', 'özel', '1234']);
      expect(out[3].cells.containsKey('sifre'), isFalse);
      expect(out[3].cells.containsKey('kullanici_adi'), isFalse);
    });

    test('dosyada yazılmış ad sunucu kuralıyla sadeleşir; üretilen ad yazılmış başka bir adı EZMEZ; tekrarlayan yazılmış ad _2 alır', () {
      final out = enrichImportRowsWithDefaults(
        rows(<Map<String, Object?>>[
          <String, Object?>{'ad_soyad': 'Ali Veli'}, // üretilecek 'ali.veli' ama 3. satırda yazılmış
          <String, Object?>{'ad_soyad': 'X', 'kullanici_adi': 'Ali.Veli'},
          <String, Object?>{'ad_soyad': 'Y', 'kullanici_adi': 'ali veli'},
        ]),
        columnKeys: person,
      );
      expect(out[1].cells['kullanici_adi'], 'ali.veli', reason: 'yazılan ad korunur (sadeleşmiş)');
      expect(out[0].cells['kullanici_adi'], 'ali.veli_2', reason: 'üretilen ad yazılmış adı ezmez');
      expect(out[2].cells['kullanici_adi'], 'ali.veli_3', reason: 'aynı adı tekrar yazan sonraki satır eki alır');
    });

    test('generateUsernameFromFullName sunucudaki slugifyLoginName ile AYNI vektörler', () {
      expect(generateUsernameFromFullName('Çağrı  Öztürk-Şahin'), 'cagri.ozturk.sahin');
      expect(generateUsernameFromFullName('  İsmail Iğdır '), 'ismail.igdir');
      expect(generateUsernameFromFullName('...'), 'kullanici');
      expect(generateUsernameFromFullName(''), 'kullanici');
      expect(generateUsernameFromFullName('Özel Ad_1'), 'ozel.ad.1');
      final long = generateUsernameFromFullName('${'a' * 30} ${'b' * 30}');
      expect(long.length, lessThanOrEqualTo(kLoginNameBaseMax));
      expect(long.endsWith('.'), isFalse);
      final taken = <String>{'ali.veli'};
      expect(generateUsernameFromFullName('Ali Veli', existing: taken), 'ali.veli_2');
      expect(taken, containsAll(<String>['ali.veli', 'ali.veli_2']));
    });
  });

  group('denetleyici: tür başına satır içeriği', () {
    test('ARAÇLAR: önizleme satırlarında sifre / kullanici_adi YOK (sunucu tanımsız anahtarı 400 ile reddeder)', () async {
      final h = _Harness(
        'araclar.csv',
        'Plaka;E-posta;Blok;Daire No\r\n34 ABC 123;a@b.com;A;1\r\n06 XY 789;;A;2\r\n',
        kinds: const <ImportKind>[ImportKind.vehicles],
      );
      final sent = await h.toPreview(ImportKind.vehicles);
      expect(sent, hasLength(2));
      expect(_keys(sent), isNot(contains('sifre')));
      expect(_keys(sent), isNot(contains('kullanici_adi')));
      h.controller.dispose();
    });

    test('DEVİR BAKİYESİ: satırlarda sifre / kullanici_adi YOK', () async {
      final h = _Harness(
        'devir.csv',
        'Blok;Daire No;Tutar\r\nA;1;1.250,50\r\nA;2;300\r\n',
        kinds: const <ImportKind>[ImportKind.openingBalances],
      );
      final sent = await h.toPreview(ImportKind.openingBalances);
      expect(sent, hasLength(2));
      expect(_keys(sent), isNot(contains('sifre')));
      expect(_keys(sent), isNot(contains('kullanici_adi')));
      h.controller.dispose();
    });

    test('HEPSİ BİR ARADA: kişi satırı şifre + kullanıcı adı alır; yalnız daire bilgisi dolu satır KORUNUR ve kişi anahtarı almaz; boş satır sayılır', () async {
      final h = _Harness(
        'hepsi.csv',
        'Blok;Daire No;Kat;Ad Soyad;Telefon\r\n'
        'A;1;2;;\r\n' // yalnız daire bilgisi (kat): atılmaz
        'A;2;;Ali Veli;5551112233\r\n' // kişi
        'A;3;;;\r\n', // yalnız anahtar sütunlar: atlanır
        kinds: const <ImportKind>[ImportKind.allInOne],
      );
      final sent = await h.toPreview(ImportKind.allInOne);
      expect(sent.map((r) => r.n), <int>[2, 3]);
      expect(sent[0].cells.containsKey('sifre'), isFalse);
      expect(sent[0].cells.containsKey('kullanici_adi'), isFalse);
      expect(sent[0].cells['kat'], '2');
      expect(sent[1].cells['sifre'], '1234');
      expect(sent[1].cells['kullanici_adi'], 'ali.veli');
      expect(h.controller.blankRows, 1, reason: 'atlanan satır sayısı önizlemede gösterilir');
      h.controller.dispose();
    });

    test('hücre düzenleme: yazılan kullanıcı adı sunucu kuralına getirilir; ad soyad girilince boş kullanıcı adı üretilir; araçta eklenmez', () async {
      final h = _Harness(
        'hepsi.csv',
        'Blok;Daire No;Ad Soyad\r\nA;1;Ali Veli\r\nA;2;Ayşe Kaya\r\n',
        kinds: const <ImportKind>[ImportKind.allInOne],
      );
      await h.toPreview(ImportKind.allInOne);
      h.controller.updateCell(1, 'kullanici_adi', 'Ayşe K_aya');
      expect(h.controller.rows[1].cells['kullanici_adi'], 'ayse.k.aya');
      h.controller.updateCell(0, 'ad_soyad', 'Ali Yılmaz');
      expect(h.controller.rows[0].cells['kullanici_adi'], 'ali.veli', reason: 'dolu kullanıcı adı ad değişince değişmez');
      h.controller.addRow(initialCells: <String, Object?>{'ad_soyad': 'Ali Veli', 'blok': 'A', 'daire_no': '3'});
      expect(h.controller.rows.last.cells['kullanici_adi'], 'ali.veli_2');
      expect(h.controller.rows.last.cells['sifre'], '1234');
      h.controller.dispose();

      final v = _Harness('araclar.csv', 'Plaka;Blok;Daire No\r\n34 ABC 123;A;1\r\n', kinds: const <ImportKind>[ImportKind.vehicles]);
      await v.toPreview(ImportKind.vehicles);
      v.controller.addRow(initialCells: <String, Object?>{'plaka': '06 XY 789', 'ad_soyad': 'Veli'});
      expect(v.controller.rows.last.cells.containsKey('sifre'), isFalse);
      expect(v.controller.rows.last.cells.containsKey('kullanici_adi'), isFalse);
      v.controller.dispose();
    });
  });

  group('extractImportRows: hepsi bir arada', () {
    test('kişi verisi olmayan ama daire alanı dolu satır atılmaz; blok + daire no dışında alan yoksa atlanır ve sayılır', () {
      final kind = _serverSpec().of(ImportKind.allInOne)!;
      final table = parseCsvText('Blok;Daire No;Kat;Tip;Sorumlu;Ad Soyad;Telefon\n'
          'A;1;;3+1;;;\n' // yalnız tip
          'A;2;;;Malik;;\n' // yalnız sorumlu
          'A;3;;;;;\n' // yalnız anahtarlar
          ';;;;;;\n' // tamamen boş
          'A;4;;;;Ali;\n');
      final mapping = detectHeader(table, kind)!.mapping;
      final extracted = extractImportRows(table, mapping, kind);
      expect(extracted.rows.map((r) => r.n), <int>[2, 3, 6]);
      expect(extracted.blankRows, 1, reason: 'yalnız blok + daire no dolu satır sayılır (tamamen boş CSV satırı tabloya hiç girmez)');
    });
  });

  group('sonuç modeli', () {
    test('commit yanıtındaki hesaplar okunur: satır no + nihai kullanıcı adı, bağlanan, atlanan neden iletisiyle', () {
      final json = commitJson();
      (json['result'] as Map<String, dynamic>)['accounts'] = <String, dynamic>{
        'created': 2,
        'linked': 1,
        'skipped': 1,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'n': 2, 'login_name': 'ali.veli', 'status': 'created'},
          <String, dynamic>{'n': 3, 'login_name': 'ali.veli_2', 'status': 'created'},
          <String, dynamic>{'n': 4, 'login_name': 'komsu', 'status': 'linked'},
        ],
        'skipped_items': <Map<String, dynamic>>[
          <String, dynamic>{'n': 5, 'code': 'EMAIL_IN_USE', 'message': 'Bu e-posta başka bir hesaba ait; hesap açılmadı.'},
        ],
      };
      final result = ImportResult.fromJson(json);
      final accounts = result.accounts!;
      expect([accounts.created, accounts.linked, accounts.skipped], <int>[2, 1, 1]);
      expect(accounts.items.map((i) => i.loginName), <String>['ali.veli', 'ali.veli_2', 'komsu']);
      expect(accounts.items.map((i) => i.linked), <bool>[false, false, true]);
      expect(accounts.items.first.n, 2);
      expect(accounts.skippedItems.single.code, 'EMAIL_IN_USE');
      expect(accounts.isEmpty, isFalse);
      // yanıtta yoksa (tekrar oynatma, araç/daire yüklemesi) null
      expect(ImportResult.fromJson(commitJson()).accounts, isNull);
    });

    test('önizlemede «Hesap açılacak kişi» satırı plan sayısından gelir (yalnız sıfırdan büyükse)', () {
      final p = ImportPreview.fromJson(
        previewJson(plan: <String, dynamic>{'people_create': 3, 'residency_add': 3, 'account_create': 3}),
      );
      expect(p.planStats().map((s) => '${s.label}:${s.count}'), contains('Hesap açılacak kişi:3'));
      final none = ImportPreview.fromJson(previewJson(plan: <String, dynamic>{'people_create': 1, 'account_create': 0}));
      expect(none.planStats().map((s) => s.label), isNot(contains('Hesap açılacak kişi')));
    });
  });
}
