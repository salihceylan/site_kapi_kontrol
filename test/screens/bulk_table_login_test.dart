// Toplu yükleme önizleme tablosu: SEÇİM LİSTESİ hücreleri açılır listeyle düzenlenir (serbest metin YOK), «Kullanıcı Adı» sütunu sistemin seçtiği adı
// gösterir ve yönetici adı yalnız sunucu denetimini geçince değiştirebilir; mali kayıt özeti önizlemenin üstünde TEK bilgi notu.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_editable_table.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_mapping_step.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_preview_step.dart';

import '../bulk_fakes.dart';
import '../bulk_test_support.dart';

ImportSpec _serverSpec() =>
    ImportSpec.fromJson(jsonDecode(File('test/fixtures/bulk/server_spec.json').readAsStringSync()) as Map<String, dynamic>);

const String _peopleCsv =
    'Ad Soyad;Telefon;Blok;Daire No;İlişki\r\n'
    'Ali Veli;5551112233;A;1;Malik\r\n'
    'Ayşe Kaya;;A;2;Eş\r\n'
    'Cemal Demir;;A;3;Komşu\r\n'
    'Dairesiz Kişi;;;;\r\n';

class _Env {
  _Env({String csv = _peopleCsv, ImportKind kind = ImportKind.people}) : _kind = kind {
    api.spec = _serverSpec();
    controller = BulkImportController(
      service: BulkService(authService: auth, api: api),
      siteCode: 12,
      delivery: delivery,
      parseRunner: inlineParse,
      picker: fakePicker('kisiler.csv', utf8Bytes(csv)),
      purgePickerCache: () async {},
      allowedKinds: <ImportKind>[kind],
      proposalDelay: Duration.zero,
    );
  }

  final ImportKind _kind;
  final FakeBulkAuth auth = FakeBulkAuth();
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  late final BulkImportController controller;

  Future<void> toMapping() async {
    await controller.loadSpec();
    controller.selectKind(_kind);
    controller.goToFileStep();
    await controller.pickAndParse();
    await controller.proposalsSettled;
  }
}

Future<void> _pump(
  WidgetTester t,
  Widget Function() build, {
  required BulkImportController controller,
  double width = 1600,
  double height = 1400,
  double scale = 1.0,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      // gerçek sayfa (BulkImportView) denetleyiciyi dinleyip yeniden çizer; burada aynısı
      home: Scaffold(body: SingleChildScrollView(child: ListenableBuilder(listenable: controller, builder: (context, _) => build()))),
    ),
  );
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void _noError(WidgetTester t, [String? where]) {
  final e = t.takeException();
  expect(e, isNull, reason: 'taşma / hata: $where ($e)');
}

void main() {
  group('seçim listesi hücreleri açılır listeyle düzenlenir', () {
    testWidgets('İlişki hücresine dokununca SERBEST METİN alanı DEĞİL açılır liste açılır; seçim satıra yazılır', (t) async {
      final env = _Env();
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('Malik').first);
      await _settle(t);
      expect(find.textContaining('Listeden seçin: İlişki'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_enum_dropdown')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), findsNothing, reason: 'serbest metin yok');

      await t.tap(find.byKey(const ValueKey<String>('bulk_enum_dropdown')));
      await _settle(t);
      for (final choice in <String>['Malik', 'Kiracı', 'Aile Üyesi', 'Sakin', '(Boş bırak)']) {
        expect(find.text(choice), findsWidgets, reason: choice);
      }
      await t.tap(find.text('Kiracı').last);
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('bulk_enum_apply')));
      await _settle(t);
      expect(env.controller.rows[0].cells['iliski'], 'Kiracı');
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('dosyadaki eski sözcük («Eş») listedeki karşılığı «Aile Üyesi» seçili gelir; listede olmayan değer («Komşu») uyarıyla açılır, İptal değeri değiştirmez', (t) async {
      final env = _Env();
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('Eş'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_enum_unknown')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey<String>('bulk_enum_dropdown')), matching: find.text('Aile Üyesi')), findsOneWidget);
      await t.tap(find.text('İptal'));
      await _settle(t);
      expect(env.controller.rows[1].cells['iliski'], 'Eş', reason: 'iptal değeri olduğu gibi bırakır');

      await t.tap(find.text('Komşu'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_enum_unknown')), findsOneWidget);
      expect(find.textContaining('«Komşu» listede yok'), findsOneWidget);
      await t.tap(find.text('İptal'));
      await _settle(t);
      expect(env.controller.rows[2].cells['iliski'], 'Komşu');
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('İsteğe bağlı sütunda «(Boş bırak)» hücreyi temizler; metin sütunları (Telefon) hâlâ metin alanıyla düzenlenir', (t) async {
      final env = _Env();
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('Malik').first);
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('bulk_enum_dropdown')));
      await _settle(t);
      await t.tap(find.text('(Boş bırak)').last);
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('bulk_enum_apply')));
      await _settle(t);
      expect(env.controller.rows[0].cells.containsKey('iliski'), isFalse);

      await t.tap(find.text('5551112233'));
      await _settle(t);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_enum_dropdown')), findsNothing);
      await t.tap(find.text('İptal'));
      await _settle(t);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('PLAKA hücresi: yazarken Türk plakası biçimi süzülür (34abc123 -> 34 ABC 123), geçersiz plaka satır içinde gösterilir ve «Uygula» kapanır; düzeltince biçimli yazılır', (t) async {
      final env = _Env(csv: 'Ad Soyad;Plaka\r\nAli Veli;34 ABC 123\r\n');
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('34 ABC 123'));
      await _settle(t);
      final field = find.byKey(const ValueKey<String>('bulk_cell_field'));
      expect(field, findsOneWidget);
      await t.enterText(field, '34 ABC 1');
      await t.pump();
      expect(find.textContaining('Plaka biçimi geçersiz: 34 ABC 1'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Uygula')).onPressed, isNull);
      await t.enterText(field, '06xy789, 34abc123');
      await t.pump();
      expect(find.textContaining('Plaka biçimi geçersiz: 34 ABC 1'), findsNothing);
      await t.tap(find.widgetWithText(ElevatedButton, 'Uygula'));
      await _settle(t);
      expect(env.controller.rows[0].cells['plaka'], '06 XY 789, 34 ABC 123');
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('Satır Ekle penceresinde İlişki açılır listedir; kullanıcı adı alanı yoktur (sistem verir)', (t) async {
      final env = _Env();
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('Satır Ekle'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_add_enum_iliski')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Kullanıcı Adı'), findsNothing);
      await t.enterText(find.widgetWithText(TextField, 'Ad Soyad *'), 'Yeni Kişi');
      await t.tap(find.byKey(const ValueKey<String>('bulk_add_enum_iliski')));
      await _settle(t);
      await t.tap(find.text('Sakin').last);
      await _settle(t);
      await t.tap(find.text('Ekle'));
      await _settle(t);
      expect(env.controller.rows.last.cells['ad_soyad'], 'Yeni Kişi');
      expect(env.controller.rows.last.cells['iliski'], 'Sakin');
      _noError(t);
      env.controller.dispose();
    });
  });

  group('«Kullanıcı Adı» sütunu', () {
    testWidgets('sistemin seçtiği adlar tabloda görünür (aynı adlar _2); hesap açılmayan satırda ad yok; sütun başlığı Ad Soyad\'ın yanında', (t) async {
      final env = _Env();
      env.api.takenLoginNames.add('ali.veli');
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      expect(find.text('Kullanıcı Adı'), findsOneWidget);
      expect(find.text('ali.veli_2'), findsOneWidget);
      expect(find.text('ayse.kaya'), findsOneWidget);
      expect(find.text('cemal.demir'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_login_name_5')), findsNothing, reason: 'dairesiz satırda öneri yok');
      final table = t.widget<DataTable>(find.byType(DataTable));
      final labels = <String>[
        for (final c in table.columns)
          if (c.label is Row) ((c.label as Row).children.first as Text).data ?? '' else (c.label as Text).data ?? '',
      ];
      expect(labels.indexOf('Kullanıcı Adı'), labels.indexOf('Ad Soyad') + 1);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('öneri gelene kadar «Hazırlanıyor…» ve üstte ilerleme çubuğu; sonra kaybolur', (t) async {
      final env = _Env();
      env.api.accountsGate = Completer<void>();
      await env.controller.loadSpec();
      env.controller.selectKind(ImportKind.people);
      env.controller.goToFileStep();
      await env.controller.pickAndParse();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      expect(find.byKey(const ValueKey<String>('bulk_login_loading')), findsOneWidget);
      expect(find.text('Hazırlanıyor…'), findsWidgets);
      env.api.accountsGate!.complete();
      await env.controller.proposalsSettled;
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_login_loading')), findsNothing);
      expect(find.text('ali.veli'), findsOneWidget);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('adı değiştirme: alınmış ad sunucuda reddedilir (neden + boştaki ad önerisi), «Uygula» KAPALI; öneriyi kullanınca açılır ve ad satıra yazılır', (t) async {
      final env = _Env();
      env.api.takenLoginNames.add('dolu.ad');
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('ali.veli'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_login_field')), findsOneWidget);
      // değişmedi: Uygula açık (kapatır, satıra bir şey yazmaz)
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNotNull);

      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'Dolu Ad');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_login_status')), findsOneWidget, reason: 'denetleniyor');
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNull, reason: 'denetim bitmeden kabul edilmez');
      await t.pump(const Duration(milliseconds: 600));
      expect(env.api.checkCalls, <String>['Dolu Ad']);
      expect(find.textContaining('sistemde başka bir hesapta kayıtlı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_login_suggestion')), findsOneWidget);
      expect(find.text('Boştaki ad: dolu.ad_2'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNull);

      await t.tap(find.byKey(const ValueKey<String>('bulk_login_suggestion')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Kullanılabilir.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNotNull);
      await t.tap(find.byKey(const ValueKey<String>('bulk_login_apply')));
      await _settle(t);
      expect(env.controller.rows[0].cells['giris_adi'], 'dolu.ad_2');
      await env.controller.proposalsSettled;
      await t.pump();
      expect(find.text('dolu.ad_2'), findsOneWidget);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('biçim hatası ve dosyadaki başka satırın adı sunucuya GİTMEDEN hemen reddedilir; art arda yazma tek denetim yapar (bekletme)', (t) async {
      final env = _Env();
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      await t.tap(find.text('ali.veli'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'a@b');
      await t.pump();
      expect(find.textContaining('boşluk ve @ kullanılamaz'), findsOneWidget);
      expect(env.api.checkCalls, isEmpty);
      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'ayse.kaya');
      await t.pump();
      expect(find.textContaining('satır 3'), findsOneWidget, reason: 'satır 3 zaten ayse.kaya adını alıyor');
      expect(env.api.checkCalls, isEmpty);
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNull);

      // art arda yazma: yalnız son metin için TEK sunucu denetimi
      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'yeni');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'yeni.a');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'yeni.ad');
      await t.pump(const Duration(milliseconds: 600));
      expect(env.api.checkCalls, <String>['yeni.ad']);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('denetim ağ hatası verirse ad KABUL EDİLMEZ (Uygula kapalı), «Yeniden denetle» ile tekrar denenir', (t) async {
      final env = _Env();
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      env.api.checkError = ApiException('Sunucuya bağlanılamadı.');
      await t.tap(find.text('ali.veli'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey<String>('bulk_login_field')), 'yeni.ad');
      await t.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('şu an denetlenemedi'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNull);
      env.api.checkError = null;
      await t.tap(find.byKey(const ValueKey<String>('bulk_login_recheck')));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Kullanılabilir.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('bulk_login_apply'))).onPressed, isNotNull);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('«Sistem önerisine dön»: seçilmiş ad varsa görünür ve hücreyi temizler', (t) async {
      final env = _Env();
      await env.toMapping();
      env.controller.updateCell(0, 'giris_adi', 'ozel.ad');
      await env.controller.flushProposals();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      expect(find.text('ozel.ad'), findsOneWidget);
      await t.tap(find.text('ozel.ad'));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('bulk_login_reset')));
      await _settle(t);
      expect(env.controller.rows[0].cells.containsKey('giris_adi'), isFalse);
      await env.controller.proposalsSettled;
      await t.pump();
      expect(find.text('ali.veli'), findsOneWidget);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('mevcut hesaba bağlanan satır: ad kilit simgesiyle SALT OKUNUR (dokununca pencere açılmaz); hesabı açılmayan e-posta: «Hesap açılmaz»', (t) async {
      final env = _Env();
      env.api.accountsBuilder = (kind, rows) => const <AccountProposal>[
        AccountProposal(n: 2, status: AccountProposalStatus.existing, loginName: 'mevcut.hesap'),
        AccountProposal(n: 3, status: AccountProposalStatus.emailInUse),
        AccountProposal(n: 4, status: AccountProposalStatus.create, loginName: 'cemal.demir', editable: true),
      ];
      await env.toMapping();
      await _pump(t, () => BulkEditableTable(controller: env.controller), controller: env.controller);
      expect(find.byKey(const ValueKey<String>('bulk_login_existing_2')), findsOneWidget);
      expect(find.text('mevcut.hesap'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Hesap açılmaz'), findsOneWidget);
      await t.tap(find.text('mevcut.hesap'));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('bulk_login_field')), findsNothing);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('reddedilen seçim satırda KIRMIZI neden olarak görünür ve üstte sorun çubuğu çıkar; mapping adımında «Önizlemeyi Hazırla» KAPALI', (t) async {
      final env = _Env();
      await env.toMapping();
      env.api.takenLoginNames.add('baskasi');
      env.controller.updateCell(0, 'giris_adi', 'baskasi');
      await env.controller.flushProposals();
      await _pump(t, () => BulkMappingStep(controller: env.controller, onBack: () {}), controller: env.controller);
      expect(find.byKey(const ValueKey<String>('bulk_login_problem_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_login_problems')), findsOneWidget);
      expect(find.textContaining('sistemde başka bir hesapta kayıtlı'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('bulk_mapping_blockers')), findsOneWidget);
      expect(find.textContaining('kullanıcı adı sorunlarını düzeltin'), findsOneWidget);
      final button = t.widget<InkWell>(find.descendant(of: find.byKey(const ValueKey<String>('bulk_mapping_continue')), matching: find.byType(InkWell)));
      expect(button.onTap, isNull);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('öneri hatası: uyarı + «Yeniden dene»; engellemez', (t) async {
      final env = _Env();
      env.api.accountsScript.add(ApiException('Sunucuya bağlanılamadı.'));
      await env.toMapping();
      await _pump(t, () => BulkMappingStep(controller: env.controller, onBack: () {}), controller: env.controller);
      expect(find.byKey(const ValueKey<String>('bulk_login_error')), findsOneWidget);
      final button = t.widget<InkWell>(find.descendant(of: find.byKey(const ValueKey<String>('bulk_mapping_continue')), matching: find.byType(InkWell)));
      expect(button.onTap, isNotNull, reason: 'öneri hatası ilerlemeyi engellemez');
      await t.ensureVisible(find.byKey(const ValueKey<String>('bulk_login_retry')));
      await t.tap(find.byKey(const ValueKey<String>('bulk_login_retry')));
      await t.pump();
      await env.controller.proposalsSettled;
      await t.pump();
      expect(find.byKey(const ValueKey<String>('bulk_login_error')), findsNothing);
      expect(find.text('ali.veli'), findsOneWidget);
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('ESKİ dosyadaki «Kullanıcı Adı» sütunu: eşleme adımında bilgi notu; araç yüklemesinde sütun ve not yok', (t) async {
      final env = _Env(csv: 'Ad Soyad;Kullanıcı Adı;Blok;Daire No\r\nAli Veli;eski.ad;A;1\r\n');
      await env.toMapping();
      await _pump(t, () => BulkMappingStep(controller: env.controller, onBack: () {}), controller: env.controller);
      expect(find.byKey(const ValueKey<String>('bulk_legacy_login_column')), findsOneWidget);
      expect(find.textContaining('artık kullanılmıyor, yok sayıldı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bulk_ignored_columns')), findsOneWidget);
      _noError(t);
      env.controller.dispose();

      final vehicles = _Env(csv: 'Plaka;Blok;Daire No\r\n34 ABC 123;A;1\r\n', kind: ImportKind.vehicles);
      await vehicles.toMapping();
      await _pump(t, () => BulkEditableTable(controller: vehicles.controller), controller: vehicles.controller);
      expect(find.text('Kullanıcı Adı'), findsNothing);
      expect(find.byKey(const ValueKey<String>('bulk_login_loading')), findsNothing);
      vehicles.controller.dispose();
    });

    for (final cell in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (640, 360, 2.0)]) {
      testWidgets('taşma yok: tablo + durum çubuğu + pencereler ${cell.$1.toInt()}x${cell.$2.toInt()} x${cell.$3}', (t) async {
        final env = _Env();
        env.api.takenLoginNames.add('dolu.ad');
        await env.toMapping();
        await _pump(t, () => BulkMappingStep(controller: env.controller, onBack: () {}), controller: env.controller, width: cell.$1, height: cell.$2, scale: cell.$3);
        _noError(t, 'tablo');
        env.api.accountsScript.add(ApiException('Sunucuya bağlanılamadı.'));
        await env.controller.flushProposals();
        await t.pump();
        _noError(t, 'hata çubuğu');
        env.controller.updateCell(0, 'giris_adi', 'dolu.ad');
        await env.controller.flushProposals();
        await t.pump();
        _noError(t, 'sorun çubuğu');
        env.controller.dispose();
      });
    }
  });

  group('önizleme: mali kayıt özeti', () {
    Future<_Env> previewEnv(Map<String, dynamic> checks) async {
      final env = _Env(csv: 'Blok;Daire No;Borç Sorumlusu\r\nA;1;Kiracı\r\nA;2;Malik\r\n', kind: ImportKind.apartments);
      env.api.previewScript.add(
        ImportPreview.fromJson(<String, dynamic>{
          ...previewJson(kind: 'apartments', ok: 2, unchanged: 0, error: 0, warnings: 0, issues: <Map<String, dynamic>>[], plan: <String, dynamic>{'apartment_update': 2}),
          'checks': checks,
        }),
      );
      await env.controller.loadSpec();
      env.controller.selectKind(ImportKind.apartments);
      env.controller.goToFileStep();
      await env.controller.pickAndParse();
      await env.controller.confirmMapping();
      return env;
    }

    testWidgets('satır uyarısı yerine TEK bilgi notu önizlemenin üstünde; yüklemeyi ENGELLEMEZ', (t) async {
      final env = await previewEnv(<String, dynamic>{
        'land_share': null,
        'finance_records': <String, dynamic>{
          'apartments': 2,
          'message': '2 dairenin mali kaydı var; Borç Sorumlusu / Tip / Arsa Payı değişiklikleri mevcut borçları değiştirmez, yalnız sonraki borçlandırmadan itibaren geçerlidir.',
        },
      });
      expect(env.controller.preview!.financeRecords!.apartments, 2);
      await _pump(t, () => BulkPreviewStep(controller: env.controller, onConfirm: () {}, onBack: () {}), controller: env.controller, width: 400, height: 1200);
      expect(find.byKey(const ValueKey<String>('bulk_finance_records')), findsOneWidget);
      expect(find.textContaining('2 dairenin mali kaydı var'), findsOneWidget);
      // satır uyarısı listesinde mali kayıt satırı yok
      expect(find.byKey(const ValueKey<String>('bulk_no_issues')), findsOneWidget);
      expect(env.controller.canCommit, isTrue, reason: 'bilgi notu engellemez');
      // not, çiplerden ve plan kartından ÖNCE (üstte)
      final note = t.getTopLeft(find.byKey(const ValueKey<String>('bulk_finance_records'))).dy;
      expect(note, lessThan(t.getTopLeft(find.byKey(const ValueKey<String>('bulk_preview_chips'))).dy));
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('kişi türünde önizleme: kullanıcı adlarını sistem verdi notu (yeni / bağlanan sayısı) ve e-postası başka hesapta olanlar uyarısı; ad listesi önizleme yanıtından tabloya yansır', (t) async {
      final env = _Env();
      env.api.previewScript.add(
        ImportPreview.fromJson(<String, dynamic>{
          ...previewJson(),
          'accounts': <Map<String, dynamic>>[
            <String, dynamic>{'n': 2, 'status': 'new', 'login_name': 'ali.veli', 'editable': true},
            <String, dynamic>{'n': 3, 'status': 'existing', 'login_name': 'komsu', 'editable': false},
            <String, dynamic>{'n': 4, 'status': 'email_in_use', 'editable': false},
          ],
        }),
      );
      await env.toMapping();
      await env.controller.confirmMapping();
      await _pump(t, () => BulkPreviewStep(controller: env.controller, onConfirm: () {}, onBack: () {}), controller: env.controller, width: 400, height: 1400);
      final note = find.byKey(const ValueKey<String>('bulk_preview_login_note'));
      expect(note, findsOneWidget);
      expect(find.textContaining('1 yeni hesap için kullanıcı adlarını sistem verdi (1 kişi mevcut hesabına bağlanır)'), findsOneWidget);
      expect(find.textContaining('1 kişinin e-postası başka bir hesaba ait'), findsOneWidget);
      expect(env.controller.loginNameOf(env.controller.rows[1]), 'komsu');
      _noError(t);
      env.controller.dispose();
    });

    testWidgets('mali kayıt yoksa not çıkmaz', (t) async {
      final env = await previewEnv(<String, dynamic>{'land_share': null, 'finance_records': null});
      expect(env.controller.preview!.financeRecords, isNull);
      await _pump(t, () => BulkPreviewStep(controller: env.controller, onConfirm: () {}, onBack: () {}), controller: env.controller, width: 400, height: 1200);
      expect(find.byKey(const ValueKey<String>('bulk_finance_records')), findsNothing);
      env.controller.dispose();
    });
  });
}
