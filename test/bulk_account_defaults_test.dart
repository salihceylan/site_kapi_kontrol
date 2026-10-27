// Toplu yükleme: başlangıç şifresi zenginleştirmesi, KULLANICI ADI ataması (şablonda sütun YOK; sistem verir, yönetici tabloda değiştirir),
// «hepsi bir arada» yalnız daire satırının korunması, atlanan satır sayısı ve sonuçta nihai kullanıcı adları (Platform Faz 2b).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_login_name.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';

import 'bulk_fakes.dart';
import 'bulk_test_support.dart';

/// Gerçek sunucu şeması (test/fixtures/bulk/server_spec.json; sunucudaki buildSpec çıktısı).
ImportSpec _serverSpec() =>
    ImportSpec.fromJson(jsonDecode(File('test/fixtures/bulk/server_spec.json').readAsStringSync()) as Map<String, dynamic>);

class _Harness {
  _Harness(String fileName, String csv, {List<ImportKind> kinds = const <ImportKind>[], Duration proposalDelay = Duration.zero}) {
    api.spec = _serverSpec();
    controller = BulkImportController(
      service: BulkService(authService: auth, api: api),
      siteCode: 12,
      delivery: delivery,
      parseRunner: inlineParse,
      picker: fakePicker(fileName, utf8Bytes(csv)),
      purgePickerCache: () async {},
      allowedKinds: kinds,
      proposalDelay: proposalDelay,
    );
  }

  final FakeBulkAuth auth = FakeBulkAuth();
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  late final BulkImportController controller;

  /// Dosyayı okutup eşleme adımına getirir (önizleme istenmez).
  Future<void> toMapping(ImportKind kind) async {
    await controller.loadSpec();
    controller.selectKind(kind);
    controller.goToFileStep();
    await controller.pickAndParse();
    await controller.proposalsSettled;
  }

  Future<List<ImportRow>> toPreview(ImportKind kind) async {
    await toMapping(kind);
    await controller.confirmMapping();
    return api.previewCalls.last.rows;
  }
}

Set<String> _keys(Iterable<ImportRow> rows) => <String>{for (final row in rows) ...row.cells.keys};

const String _peopleCsv =
    'Ad Soyad;Blok;Daire No;İlişki\r\n'
    'Ali Veli;A;1;Malik\r\n'
    'Ali Veli;A;2;Kiracı\r\n'
    'Dairesiz Kişi;;;\r\n';

void main() {
  group('enrichImportRowsWithDefaults', () {
    const person = <String>{'ad_soyad', 'sifre'};
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
        expect(_keys(out), isNot(contains('giris_adi')));
        expect(out.map((r) => r.cells), input.map((r) => r.cells));
      }
    });

    test('kişi türü: yalnız boş şifre 1234 olur; İSTEMCİ KULLANICI ADI ÜRETMEZ (sistem verir); ad soyadsız satıra dokunulmaz', () {
      final out = enrichImportRowsWithDefaults(
        rows(<Map<String, Object?>>[
          <String, Object?>{'ad_soyad': 'Çağrı Öztürk'},
          <String, Object?>{'ad_soyad': 'Çağrı Öztürk', 'sifre': 'özel'},
          <String, Object?>{'blok': 'A', 'daire_no': '1'}, // yalnız daire bilgisi: kişi değil
        ]),
        columnKeys: person,
      );
      expect(out.map((r) => r.cells['sifre']).take(2), <Object?>['1234', 'özel']);
      expect(out[2].cells.containsKey('sifre'), isFalse);
      expect(_keys(out), isNot(contains('kullanici_adi')));
      expect(_keys(out), isNot(contains('giris_adi')));
    });
  });

  group('kullanıcı adı kuralları (sunucu bulk_import_login_names.js ile AYNI vektörler)', () {
    test('generateUsernameFromFullName == slugifyLoginName; denetleyici dosyasından da içe aktarılabilir (kişi hesabı penceresi)', () {
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

    test('normalizeTypedLoginName: kırp, Türkçe sadeleşir, küçük harf, boşluk nokta; _ ve - KORUNUR; 3-40 karakter [a-z0-9._-]', () {
      expect(normalizeTypedLoginName('  Ahmet Yılmaz_2 '), (value: 'ahmet.yilmaz_2', error: null));
      expect(normalizeTypedLoginName('ali-veli'), (value: 'ali-veli', error: null));
      expect(normalizeTypedLoginName('ab').error, LoginNameFormatError.tooShort);
      expect(normalizeTypedLoginName('a' * 41).error, LoginNameFormatError.tooLong);
      expect(normalizeTypedLoginName('a' * 40).error, isNull);
      expect(normalizeTypedLoginName('ali@veli').error, LoginNameFormatError.chars);
      expect(normalizeTypedLoginName('ali/veli').error, LoginNameFormatError.chars);
      expect(normalizeTypedLoginName('   ').error, LoginNameFormatError.empty);
      for (final error in LoginNameFormatError.values) {
        expect(loginNameFormatMessage(error), isNotEmpty);
      }
    });
  });

  group('denetleyici: tür başına satır içeriği', () {
    test('ARAÇLAR: önizleme satırlarında sifre / kullanici_adi / giris_adi YOK ve kullanıcı adı önerisi istenmez', () async {
      final h = _Harness(
        'araclar.csv',
        'Plaka;E-posta;Blok;Daire No\r\n34 ABC 123;a@b.com;A;1\r\n06 XY 789;;A;2\r\n',
        kinds: const <ImportKind>[ImportKind.vehicles],
      );
      final sent = await h.toPreview(ImportKind.vehicles);
      expect(sent, hasLength(2));
      expect(_keys(sent), isNot(contains('sifre')));
      expect(_keys(sent), isNot(contains('kullanici_adi')));
      expect(_keys(sent), isNot(contains('giris_adi')));
      expect(h.api.accountsCalls, isEmpty, reason: 'araç yüklemesi hesap açmaz');
      expect(h.controller.hasLoginColumn, isFalse);
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
      expect(h.api.accountsCalls, isEmpty);
      h.controller.dispose();
    });

    test('HEPSİ BİR ARADA: kişi satırı yalnız şifre alır (kullanıcı adı sistemden gelir); yalnız daire bilgisi dolu satır KORUNUR; boş satır sayılır', () async {
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
      expect(sent[0].cells['kat'], '2');
      expect(sent[1].cells['sifre'], '1234');
      expect(sent[1].cells.containsKey('kullanici_adi'), isFalse);
      expect(sent[1].cells.containsKey('giris_adi'), isFalse, reason: 'yönetici değiştirmedikçe istemci ad göndermez');
      expect(h.controller.blankRows, 1, reason: 'atlanan satır sayısı önizlemede gösterilir');
      h.controller.dispose();
    });

    test('hücre düzenleme: ad soyad değişince / satır eklenince istemci kullanıcı adı ÜRETMEZ; şifre varsayılanı eklenir; araçta eklenmez', () async {
      final h = _Harness(
        'hepsi.csv',
        'Blok;Daire No;Ad Soyad\r\nA;1;Ali Veli\r\nA;2;Ayşe Kaya\r\n',
        kinds: const <ImportKind>[ImportKind.allInOne],
      );
      await h.toMapping(ImportKind.allInOne);
      h.controller.updateCell(0, 'ad_soyad', 'Ali Yılmaz');
      expect(h.controller.rows[0].cells.containsKey('giris_adi'), isFalse);
      expect(h.controller.rows[0].cells.containsKey('kullanici_adi'), isFalse);
      h.controller.addRow(initialCells: <String, Object?>{'ad_soyad': 'Ali Veli', 'blok': 'A', 'daire_no': '3'});
      expect(h.controller.rows.last.cells.containsKey('kullanici_adi'), isFalse);
      expect(h.controller.rows.last.cells.containsKey('giris_adi'), isFalse);
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

  group('kullanıcı adı önerileri ve düzenleme (tablodaki «Kullanıcı Adı» sütunu)', () {
    test('dosya okununca sunucudan öneri alınır: aynı adlar dosyada _2 alır; hesap açılmayan satırda öneri yok; ad hücreleri satır sırasıyla', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      expect(h.api.accountsCalls, hasLength(1));
      expect(h.api.accountsCalls.single.kind, ImportKind.people);
      expect(c.hasLoginColumn, isTrue);
      expect(c.rows.map(c.loginNameOf), <String?>['ali.veli', 'ali.veli_2', null]);
      expect(c.isLoginEditable(c.rows[0]), isTrue);
      expect(c.isLoginEditable(c.rows[2]), isFalse, reason: 'daire yok: hesap açılmaz');
      expect(c.proposalsLoading, isFalse);
      expect(c.proposalsStale, isFalse);
      c.dispose();
    });

    test('sistemde başka yerde alınmış ad önerilmez (sunucu varyasyon seçer)', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      h.api.takenLoginNames.addAll(<String>{'ali.veli', 'ali.veli_2'});
      await h.toMapping(ImportKind.people);
      expect(h.controller.rows.map(h.controller.loginNameOf), <String?>['ali.veli_3', 'ali.veli_4', null]);
      h.controller.dispose();
    });

    test('yönetici adı değiştirir: giris_adi hücresi satıra yazılır, öneriler yenilenir ve diğer satırlar o adı kullanmaz; önizleme/onay AYNI satırları gönderir', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      c.updateCell(1, 'giris_adi', 'Ali.Veli_Ozel');
      await c.flushProposals();
      expect(c.rows[1].cells['giris_adi'], 'Ali.Veli_Ozel', reason: 'ham metin saklanır, sunucu normalleştirir');
      expect(h.api.accountsCalls.last.rows[1].cells['giris_adi'], 'Ali.Veli_Ozel');
      expect(c.proposalOf(c.rows[1])!.custom, isTrue);
      expect(c.loginNameOf(c.rows[1]), 'ali.veli_ozel');
      expect(c.rows.map(c.loginNameOf).first, 'ali.veli');

      await c.confirmMapping();
      final previewed = h.api.previewCalls.last.rows;
      expect(previewed[1].cells['giris_adi'], 'Ali.Veli_Ozel');
      expect(previewed[0].cells.containsKey('giris_adi'), isFalse);
      await c.commit(acknowledged: true);
      expect(h.api.commitCalls.single.rows[1].cells['giris_adi'], 'Ali.Veli_Ozel', reason: 'onay, önizlemede gönderilen satırların aynısıdır');
      c.dispose();
    });

    test('yönetici «sistem önerisine dön» der (hücre boşaltılır): giris_adi satırdan kalkar', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      await h.toMapping(ImportKind.people);
      h.controller.updateCell(0, 'giris_adi', 'ozel.ad');
      expect(h.controller.overrideOf(h.controller.rows[0]), 'ozel.ad');
      h.controller.updateCell(0, 'giris_adi', null);
      expect(h.controller.rows[0].cells.containsKey('giris_adi'), isFalse);
      expect(h.controller.overrideOf(h.controller.rows[0]), isNull);
      h.controller.dispose();
    });

    test('sunucu seçilen adı REDDEDERSE (sistemde kayıtlı) satır sorunlu sayılır: «Önizlemeyi Hazırla» çalışmaz, neden satırda gösterilir', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      h.api.takenLoginNames.add('baskasinin.adi');
      c.updateCell(0, 'giris_adi', 'baskasinin.adi');
      await c.flushProposals();
      expect(c.proposalOf(c.rows[0])!.status, AccountProposalStatus.rejected);
      expect(c.hasLoginProblems, isTrue);
      expect(c.loginProblems[c.rows[0].n], contains('sistemde başka bir hesapta kayıtlı'));
      final callsBefore = h.api.previewCalls.length;
      await c.confirmMapping();
      expect(h.api.previewCalls.length, callsBefore, reason: 'sorun giderilmeden önizleme/yükleme istenmez');
      expect(c.mappingError, contains('Kullanıcı adı sorunu'));
      expect(c.step, BulkStep.mapping);
      // düzeltilince devam eder
      c.updateCell(0, 'giris_adi', null);
      await c.flushProposals();
      expect(c.hasLoginProblems, isFalse);
      await c.confirmMapping();
      expect(c.step, BulkStep.preview);
      c.dispose();
    });

    test('önizlemede sunucu LOGIN_NAME_* satır hatası dönerse onay KAPALI (katı mod kapalı olsa da)', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      h.api.previewScript.add(
        ImportPreview.fromJson(
          previewJson(
            ok: 1,
            error: 1,
            issues: <Map<String, dynamic>>[
              <String, dynamic>{'n': 2, 'severity': 'error', 'field': 'giris_adi', 'code': 'LOGIN_NAME_TAKEN', 'message': 'Kullanıcı adı «x.y.z» sistemde başka bir hesapta kayıtlı. Başka bir ad seçin.'},
            ],
          ),
        ),
      );
      await h.toPreview(ImportKind.people);
      final c = h.controller;
      expect(c.strict, isFalse);
      expect(c.canCommit, isFalse);
      expect(c.commitBlockedReason, contains('Kullanıcı adı kabul edilmeyen satırlar'));
      expect(c.fieldLabels['giris_adi'], 'Kullanıcı Adı', reason: 'sorun listesi alan adını Türkçe gösterir');
      c.dispose();
    });

    test('yerel denetim: biçim hatası ve dosyadaki başka satırın adıyla çakışma hemen söylenir (sunucuya gitmeden)', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      expect(c.localLoginNameProblem('a@b', rowN: 2), contains('harf, rakam'));
      expect(c.localLoginNameProblem('ab', rowN: 2), contains('en az 3'));
      expect(c.localLoginNameProblem('Ali.Veli_2', rowN: 2), contains('satır 3'), reason: 'satır 3 zaten ali.veli_2 adını alıyor');
      expect(c.localLoginNameProblem('Ali.Veli_2', rowN: 3), isNull, reason: 'kendi adı sorun değil');
      expect(c.localLoginNameProblem('yeni.ad', rowN: 2), isNull);
      expect(h.api.checkCalls, isEmpty);
      final check = await c.checkLoginName('Yeni Ad');
      expect(check.ok, isTrue);
      expect(check.loginName, 'yeni.ad');
      h.api.takenLoginNames.add('dolu.ad');
      final taken = await c.checkLoginName('dolu.ad');
      expect([taken.ok, taken.code, taken.suggestion], [false, 'TAKEN', 'dolu.ad_2']);
      c.dispose();
    });

    test('mevcut hesaba bağlanan satırda ad SALT OKUNUR; eski kullanıcı adı seçimi isteğe konmaz', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      h.api.accountsBuilder = (kind, rows) => <AccountProposal>[
        const AccountProposal(n: 2, status: AccountProposalStatus.existing, loginName: 'mevcut.hesap'),
        const AccountProposal(n: 3, status: AccountProposalStatus.create, loginName: 'ali.veli', editable: true),
      ];
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      expect(c.isLoginEditable(c.rows[0]), isFalse);
      expect(c.loginNameOf(c.rows[0]), 'mevcut.hesap');
      c.updateCell(0, 'giris_adi', 'eski.secim'); // satır artık mevcut hesaba bağlanıyor: seçim anlamsız
      await c.flushProposals();
      final sentToAccounts = h.api.accountsCalls.last.rows;
      expect(sentToAccounts[0].cells.containsKey('giris_adi'), isFalse);
      await c.confirmMapping();
      expect(h.api.previewCalls.last.rows[0].cells.containsKey('giris_adi'), isFalse);
      c.dispose();
    });

    test('satırlar art arda değişirse öneri isteği BEKLETİLİR (tek istek); eski yanıt yenisini ezmez', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people], proposalDelay: const Duration(milliseconds: 40));
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      final before = h.api.accountsCalls.length;
      c.updateCell(0, 'ad_soyad', 'Ali Yılmaz');
      c.updateCell(0, 'ad_soyad', 'Ali Yıldız');
      c.updateCell(1, 'ad_soyad', 'Veli Yıldız');
      expect(h.api.accountsCalls.length, before, reason: 'bekleme süresi dolmadan istek yok');
      expect(c.proposalsStale, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.api.accountsCalls.length, before + 1);
      expect(c.proposalsStale, isFalse);
      expect(c.rows.map(c.loginNameOf).take(2), <String?>['ali.yildiz', 'veli.yildiz']);

      // yavaş (eski) yanıt, sonradan değişen satırlar için gelirse atılır
      final gate = Completer<void>();
      h.api.accountsGate = gate;
      final slow = c.flushProposals(); // eski satırlarla istek, kapıda bekler
      await Future<void>.delayed(const Duration(milliseconds: 5));
      h.api.accountsGate = null;
      c.updateCell(0, 'ad_soyad', 'Yeni Kisi');
      await c.flushProposals();
      expect(c.loginNameOf(c.rows[0]), 'yeni.kisi');
      gate.complete();
      await slow;
      expect(c.loginNameOf(c.rows[0]), 'yeni.kisi', reason: 'geç gelen eski yanıt yenisini ezmez');
      expect(c.proposalsLoading, isFalse);
      c.dispose();
    });

    test('öneri hatası ENGELLEMEZ: tabloda hata gösterilir, «Önizlemeyi Hazırla» yine çalışır ve önizleme adları getirir', () async {
      final h = _Harness('kisiler.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      h.api.accountsScript.add(StateError('x'));
      h.api.previewScript.add(
        ImportPreview.fromJson(<String, dynamic>{
          ...previewJson(),
          'accounts': <Map<String, dynamic>>[
            <String, dynamic>{'n': 2, 'status': 'new', 'login_name': 'ali.veli', 'editable': true, 'custom': false},
            <String, dynamic>{'n': 3, 'status': 'new', 'login_name': 'ali.veli_2', 'editable': true, 'custom': false},
          ],
        }),
      );
      await h.toMapping(ImportKind.people);
      final c = h.controller;
      expect(c.proposalsError, isNotNull);
      expect(c.accountProposals, isEmpty);
      expect(c.hasLoginProblems, isFalse);
      await c.confirmMapping();
      expect(c.step, BulkStep.preview);
      expect(c.rows.map(c.loginNameOf).take(2), <String?>['ali.veli', 'ali.veli_2'], reason: 'önizleme yanıtı (kesin sonuç) tablodaki önerilerin yerini alır');
      c.dispose();
    });

    test('ESKİ dosyadaki «Kullanıcı Adı» sütunu yok sayılır ve yönetici bilgilendirilir; satırlara kullanici_adi girmez', () async {
      final h = _Harness(
        'eski.csv',
        'Ad Soyad;Kullanıcı Adı;Blok;Daire No\r\nAli Veli;eski.ad;A;1\r\n',
        kinds: const <ImportKind>[ImportKind.people],
      );
      final sent = await h.toPreview(ImportKind.people);
      expect(h.controller.fileHasLegacyLoginColumn, isTrue);
      expect(_keys(sent), isNot(contains('kullanici_adi')));
      expect(_keys(sent), isNot(contains('giris_adi')));
      expect(h.controller.mapping!.ignoredColumns().map((i) => h.controller.mapping!.headers[i]), contains('Kullanıcı Adı'));
      h.controller.dispose();
      // sütun yoksa bildirim de yok
      final clean = _Harness('yeni.csv', _peopleCsv, kinds: const <ImportKind>[ImportKind.people]);
      await clean.toMapping(ImportKind.people);
      expect(clean.controller.fileHasLegacyLoginColumn, isFalse);
      clean.controller.dispose();
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
    test('commit yanıtındaki hesaplar okunur: satır no + nihai kullanıcı adı, bağlanan, atlanan neden iletisiyle, yarışta değişen ad', () {
      final json = commitJson();
      (json['result'] as Map<String, dynamic>)['accounts'] = <String, dynamic>{
        'created': 2,
        'linked': 1,
        'skipped': 1,
        'renamed': 1,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'n': 2, 'login_name': 'ali.veli', 'status': 'created'},
          <String, dynamic>{'n': 3, 'login_name': 'ali.veli_3', 'status': 'created', 'requested_login_name': 'ali.veli_2'},
          <String, dynamic>{'n': 4, 'login_name': 'komsu', 'status': 'linked'},
        ],
        'skipped_items': <Map<String, dynamic>>[
          <String, dynamic>{'n': 5, 'code': 'EMAIL_IN_USE', 'message': 'Bu e-posta başka bir hesaba ait; hesap açılmadı.'},
        ],
      };
      final result = ImportResult.fromJson(json);
      final accounts = result.accounts!;
      expect([accounts.created, accounts.linked, accounts.skipped, accounts.renamed], <int>[2, 1, 1, 1]);
      expect(accounts.items.map((i) => i.loginName), <String>['ali.veli', 'ali.veli_3', 'komsu']);
      expect(accounts.items.map((i) => i.linked), <bool>[false, false, true]);
      expect(accounts.items.map((i) => i.requestedLoginName), <String?>[null, 'ali.veli_2', null]);
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
