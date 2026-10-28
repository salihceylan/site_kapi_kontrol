// Site kurulum sihirbazı ekranı (P2-15): adım geçişleri, yarım kalma / devam, MEVCUT ekranlara giden eylemler,
// dürüst hata durumu ve taşma matrisi (AGENTS.md kural 6: 320x640 x2,0 · 360x640 x1,5 · yatay · tablet; açık + koyu).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_controller.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_wizard_view.dart';

import '../bulk_fakes.dart';
import '../bulk_test_support.dart' show specJson;
import 'finance_fixtures.dart' show finDefinition;
import 'people_fixtures.dart';
import 'site_setup_fixtures.dart';

const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
  (640, 360, 1.0),
  (820, 1180, 1.0),
];

const String _longSite = 'Çok Uzun Adlı Konut Yapı Kooperatifi Gül Bahçesi Sitesi Yönetimi Kurulu Sitesi';

class _Run {
  _Run({SetupWizardFakeAuth? auth, SiteSetupProgressStore? store, this.useController = false, this.siteName = 'Gül Sitesi'})
    : auth = auth ?? SetupWizardFakeAuth(),
      store = store ?? SiteSetupProgressStore();

  final SetupWizardFakeAuth auth;
  final SiteSetupProgressStore store;
  final bool useController;
  final String siteName;
  SiteSetupController? controller;
  SiteSetupOutcome? outcome;
  bool closed = false;

  SiteSetupController buildController() => SiteSetupController(
    authService: auth,
    siteCode: auth.siteCode,
    userId: auth.session!.id,
    siteName: siteName,
    store: store,
  );
}

class _Host extends StatelessWidget {
  const _Host(this.run);

  final _Run run;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            run.closed = false;
            final controller = run.useController ? (run.controller ??= run.buildController()) : null;
            final result = await Navigator.of(context).push<SiteSetupOutcome>(
              MaterialPageRoute<SiteSetupOutcome>(
                builder: (_) => SiteSetupWizardView(
                  authService: run.auth,
                  siteCode: run.auth.siteCode,
                  siteName: run.siteName,
                  store: run.store,
                  controller: controller,
                ),
              ),
            );
            run.outcome = result;
            run.closed = true;
          },
          child: const Text('Aç'),
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester t, [int ms = 450]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Future<void> _launch(
  WidgetTester t,
  _Run run, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: _Host(run),
    ),
  );
  await t.pump();
  await t.tap(find.text('Aç'));
  await _settle(t);
  await _settle(t, 100);
}

/// Anahtarlı öğeye (gerekirse kaydırarak) dokunur.
Future<void> _tap(WidgetTester t, String key, [int ms = 450]) async {
  final finder = find.byKey(ValueKey<String>(key));
  expect(finder, findsOneWidget, reason: key);
  await t.ensureVisible(finder);
  await t.pump();
  await t.tap(finder);
  await _settle(t, ms);
}

String _title(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey<String>('site_setup_step_title'))).data ?? '';

/// Düğmenin etkin olup olmadığı (PrimaryActionButton -> InkWell onTap).
bool _enabled(WidgetTester t, String key) {
  final finder = find.descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(InkWell));
  expect(finder, findsWidgets, reason: key);
  return t.widget<InkWell>(finder.first).onTap != null;
}

void _noError(WidgetTester t, [String? where]) {
  final e = t.takeException();
  expect(e, isNull, reason: 'taşma / hata: $where ($e)');
}

/// Sahte toplu yükleme düzeneği (Kişiler ekranı testlerindeki kalıp).
class _Bulk {
  final FakeBulkApi api = FakeBulkApi();
  final FakeDelivery delivery = FakeDelivery();
  int controllersBuilt = 0;

  void install() {
    final json = specJson();
    final kinds = Map<String, dynamic>.from(json['kinds'] as Map);
    kinds['all_in_one'] = Map<String, dynamic>.from(kinds['people'] as Map);
    json['kinds'] = kinds;
    api.spec = ImportSpec.fromJson(json);
    BulkService.debugApiFactory = (_) => api;
    BulkImportViewState.debugControllerFactory = (PeopleScope scope) {
      controllersBuilt++;
      return BulkImportController(
        service: BulkService(authService: scope.authService, api: api),
        siteCode: scope.siteCode,
        siteName: scope.siteName,
        delivery: delivery,
        purgePickerCache: () async {},
        picker: () async => PickedBulkFile(name: 'kisiler.csv', size: 0, readBytes: () async => Uint8List(0)),
      );
    };
    addTearDown(() {
      BulkService.debugApiFactory = null;
      BulkImportViewState.debugControllerFactory = null;
    });
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('adım geçişleri', () {
    testWidgets('yeni kurulmuş site: Kişiler adımından açılır; ilk üç adım tamam, Devam kapalı, Atla var', (t) async {
      final run = _Run();
      await _launch(t, run);
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      expect(find.byKey(const ValueKey<String>('site_setup_card_people')), findsOneWidget);
      expect(find.text('Henüz kişi yok'), findsOneWidget);
      expect(find.text('Yapılmadı'), findsOneWidget, reason: 'kişiler adımı henüz yapılmadı');
      expect(_enabled(t, 'site_setup_next'), isFalse, reason: 'tamamlanmamış adımda Devam yok');
      expect(find.byKey(const ValueKey<String>('site_setup_skip')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_setup_back')), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsOneWidget, reason: 'hangi site kuruluyor');
      _noError(t);
    });

    testWidgets('Atla -> Modüller; Devam -> Finans (son adım); Atla -> özet; durumlar özette doğru', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      expect(_title(t), 'Adım 5 / 6 · Modüller');
      expect(_enabled(t, 'site_setup_next'), isTrue, reason: 'modül adımı yalnız onay ister');
      await _tap(t, 'site_setup_next');
      expect(_title(t), 'Adım 6 / 6 · Finans açılışı');
      expect(find.text('Özeti gör'), findsOneWidget, reason: 'son adımda Devam yerine Özeti gör');
      await _tap(t, 'site_setup_skip');
      expect(find.text('Kurulum özeti'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('site_setup_summary_people')), findsOneWidget);
      final people = find.descendant(of: find.byKey(const ValueKey<String>('site_setup_summary_people')), matching: find.text('Atlandı'));
      expect(people, findsOneWidget);
      final blocks = find.descendant(of: find.byKey(const ValueKey<String>('site_setup_summary_blocks')), matching: find.text('Tamam'));
      expect(blocks, findsOneWidget);
      final modules = find.descendant(of: find.byKey(const ValueKey<String>('site_setup_summary_modules')), matching: find.text('Tamam'));
      expect(modules, findsOneWidget, reason: 'modül adımı onaylandı');
      expect(find.byKey(const ValueKey<String>('site_setup_summary_pending')), findsOneWidget);
      _noError(t);
    });

    testWidgets('Geri önceki adıma döner; tamamlanmış adımda Devam etkin, Atla yok', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 3 / 6 · Daireler');
      expect(_enabled(t, 'site_setup_next'), isTrue);
      expect(find.byKey(const ValueKey<String>('site_setup_skip')), findsNothing, reason: 'tamamlanmış adım atlanmaz');
      await _tap(t, 'site_setup_next');
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      _noError(t);
    });

    testWidgets('özetten bir adıma dönülür ("Kişiler adımını tamamla") ve Geri özetten son adıma döner', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_skip');
      expect(find.text('Kurulum özeti'), findsWidgets);
      await _tap(t, 'site_setup_summary_open_people');
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_skip');
      expect(find.text('Kurulum özeti'), findsWidgets);
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 6 / 6 · Finans açılışı');
      _noError(t);
    });

    testWidgets('Kurulumu bitir: sonuç finished=true, ilerleme kayıtlı ve Panel hatırlatması kalkar', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_finish');
      expect(run.closed, isTrue);
      expect(run.outcome?.finished, isTrue);
      final saved = await run.store.load(5, 11);
      expect(saved?.finished, isTrue);
      expect(await run.store.nextUnfinished(5), isNull);
      _noError(t);
    });

    testWidgets('sihirbaz hiçbir kayıt değiştirmeden kapanırsa changed=false (çağıran listeleri tazelemez)', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_close');
      expect(run.closed, isTrue);
      expect(run.outcome?.changed, isFalse);
      expect(run.outcome?.finished, isFalse);
      _noError(t);
    });
  });

  group('yarım kalma ve devam', () {
    testWidgets('kapatılıp yeniden açılan sihirbaz kalınan adımdan, atlananlarla birlikte sürer', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip'); // Kişiler atlandı -> Modüller
      expect(_title(t), 'Adım 5 / 6 · Modüller');
      await _tap(t, 'site_setup_close');
      expect(run.closed, isTrue);

      // Aynı kullanıcı, aynı cihaz: sihirbazı yeniden aç.
      await t.tap(find.text('Aç'));
      await _settle(t);
      await _settle(t, 100);
      expect(_title(t), 'Adım 5 / 6 · Modüller', reason: 'kalınan adımdan devam');
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      expect(find.text('Atlandı'), findsOneWidget, reason: 'atlanan adım atlanmış kalır');
      _noError(t);
    });

    testWidgets('kayıtlı ilerleme olmadan başka bir kullanıcı sihirbazı kendi başından açar', (t) async {
      final store = SiteSetupProgressStore();
      await store.save(
        1,
        const SiteSetupProgress(siteCode: 11, current: SiteSetupStep.finance, started: true, done: {SiteSetupStep.people}),
      );
      final run = _Run(store: store); // yönetici (kullanıcı 5): kayıt süper kullanıcıya (1) ait
      await _launch(t, run);
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      _noError(t);
    });

    testWidgets('kişi eklenince (yenile) atlanan adım tamama döner ve Devam açılır', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_back');
      expect(find.text('Atlandı'), findsOneWidget);
      run.auth.peopleJson[1] = pplPersonJson(1, 'Ayşe Yılmaz');
      await _tap(t, 'site_setup_refresh');
      expect(find.text('Atlandı'), findsNothing);
      expect(find.text('Tamam'), findsOneWidget);
      expect(find.text('1 kişi kayıtlı'), findsOneWidget);
      expect(_enabled(t, 'site_setup_next'), isTrue);
      _noError(t);
    });
  });

  group('adımlar MEVCUT ekranları açar', () {
    testWidgets('Kişiler: «Excel\'den yükle» toplu yükleme sihirbazını «Hepsi bir arada» önseçili açar', (t) async {
      final bulk = _Bulk()..install();
      final run = _Run();
      await _launch(t, run);
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      await _tap(t, 'site_setup_people_excel');
      expect(bulk.controllersBuilt, 1);
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget, reason: 'tür önceden seçildi');
      expect(find.text('Seçili'), findsOneWidget);
      // Hiçbir şey yüklenmeden geri dön: sihirbaz yerinde.
      await _tap(t, 'bulk_back');
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      _noError(t);
    });

    testWidgets('Kişiler: «Kişileri tek tek ekle» Kişiler ekranını bu site ve Kişiler sekmesiyle açar', (t) async {
      final run = _Run(auth: SetupWizardFakeAuth(sites: [pplSite(10, 'Başka Site'), pplSite(11, 'Gül Sitesi')]));
      await _launch(t, run);
      await _tap(t, 'site_setup_people_manual');
      expect(find.text('Kişi Ekle'), findsOneWidget);
      final tab = t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('people_tab_0')));
      expect(tab.selected, isTrue);
      final dropdown = t.widget<DropdownButtonFormField<int>>(find.byType(DropdownButtonFormField<int>).first);
      expect(dropdown.initialValue, 11, reason: 'ilk site değil, sihirbazın sitesi seçili açılır');
      _noError(t);
    });

    testWidgets('Daireler: «Daireler listesini aç» Kişiler ekranını Daireler sekmesinde açar', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 3 / 6 · Daireler');
      await _tap(t, 'site_setup_apartments_list');
      final tab = t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('people_tab_1')));
      expect(tab.selected, isTrue);
      _noError(t);
    });

    testWidgets('Daireler: «Excel\'den yükle» toplu yükleme sihirbazını açar', (t) async {
      final bulk = _Bulk()..install();
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_back');
      await _tap(t, 'site_setup_apartments_excel');
      expect(bulk.controllersBuilt, 1);
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget);
      _noError(t);
    });

    testWidgets('Modüller: «Modülleri seç / talep et» Modüller ekranını bu sitenin modülleriyle açar', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      expect(_title(t), 'Adım 5 / 6 · Modüller');
      expect(find.text('Modülleri seç / talep et'), findsOneWidget, reason: 'yönetici modül TALEP eder');
      await _tap(t, 'site_setup_modules_open');
      expect(find.text('Site Modülleri'), findsOneWidget);
      expect(find.text('Her sitede açık'), findsWidgets, reason: 'temel modüller her sitede açık');
      _noError(t);
    });

    testWidgets('Finans: «Aidat tanımı ekle» mevcut tanım formunu açar; tanım eklenince adım tamama döner', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      expect(_title(t), 'Adım 6 / 6 · Finans açılışı');
      expect(find.text('Henüz tanım yok'), findsOneWidget);
      await _tap(t, 'site_setup_finance_definition');
      expect(find.text('Yeni Tanım'), findsWidgets, reason: 'mevcut aidat / ek borç tanımı penceresi');
      // Pencereyi kapat (vazgeç) ve tanımın başka yerde eklendiğini taklit et.
      await t.tap(find.text('Vazgeç').first);
      await _settle(t);
      run.auth.definitions[1] = finDefinition(1);
      await _tap(t, 'site_setup_refresh');
      expect(find.text('1 aidat tanımı'), findsOneWidget);
      expect(find.text('Tamam'), findsOneWidget);
      _noError(t);
    });

    testWidgets('Finans: «Finans ekranını aç» Finans ekranını bu site ve Tanımlar sekmesiyle açar', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_finance_open');
      final tab = t.widget<ChoiceChip>(find.byKey(const ValueKey<String>('finance_tab_1')));
      expect(tab.selected, isTrue, reason: 'Tanımlar sekmesi');
      _noError(t);
    });

    testWidgets('Finans: «Devir bakiyesi yükle» mevcut devir penceresini açar', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_finance_opening');
      expect(find.textContaining('Devir'), findsWidgets);
      _noError(t);
    });

    testWidgets('Site bilgileri: süper kullanıcı düzenleyebilir (mevcut site formu); kaydedince durum yenilenir', (t) async {
      final run = _Run(auth: SetupWizardFakeAuth.superUser());
      await _launch(t, run);
      await _tap(t, 'site_setup_back');
      await _tap(t, 'site_setup_back');
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 1 / 6 · Site bilgileri');
      expect(find.byKey(const ValueKey<String>('site_setup_manager_readonly')), findsNothing);
      await _tap(t, 'site_setup_edit_site');
      expect(find.text('Site Düzenle'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'Gül Sitesi'), 'Yeni Ad Sitesi');
      await t.tap(find.text('Güncelle'));
      await _settle(t);
      await _settle(t, 100);
      expect(run.auth.updateSiteCalls, hasLength(1));
      expect(run.auth.updateSiteCalls.single['name'], 'Yeni Ad Sitesi');
      expect(find.text('Yeni Ad Sitesi'), findsWidgets, reason: 'durum sunucudan yeniden okundu');
      _noError(t);
    });

    testWidgets('Site bilgileri: site yöneticisi DÜZENLEYEMEZ (sunucu yalnız süper kullanıcıya izin verir); neden yazılıdır', (t) async {
      final run = _Run();
      await _launch(t, run);
      await _tap(t, 'site_setup_back');
      await _tap(t, 'site_setup_back');
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 1 / 6 · Site bilgileri');
      expect(find.byKey(const ValueKey<String>('site_setup_edit_site')), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_setup_manager_readonly')), findsOneWidget);
      await _tap(t, 'site_setup_next');
      expect(_title(t), 'Adım 2 / 6 · Bloklar');
      expect(find.byKey(const ValueKey<String>('site_setup_edit_blocks')), findsNothing);
      expect(find.text('A Blok · 3 daire'), findsOneWidget);
      expect(find.text('2 blok'), findsOneWidget);
      _noError(t);
    });
  });

  group('yönetim türü terimleri', () {
    testWidgets('iş merkezi: Blok -> Kat, Daire -> Ofis, Aidat -> Ortak gider', (t) async {
      final run = _Run(
        auth: SetupWizardFakeAuth(
          managementType: 'business_center',
          typeLabel: 'İş Merkezi',
          managementTerms: <String, dynamic>{
            'unit': 'Ofis',
            'unit_plural': 'Ofisler',
            'block': 'Kat',
            'block_plural': 'Katlar',
            'fee': 'Ortak gider',
          },
        ),
      );
      await _launch(t, run);
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 3 / 6 · Ofisler');
      await _tap(t, 'site_setup_back');
      expect(_title(t), 'Adım 2 / 6 · Katlar');
      expect(find.text('2 kat'), findsOneWidget);
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_skip');
      await _tap(t, 'site_setup_next');
      expect(find.text('Ortak gider tanımı ekle'), findsOneWidget);
      _noError(t);
    });
  });

  group('dürüst hata durumu', () {
    testWidgets('site yapısı okunamazsa "durum alınamadı" + Tekrar Dene; sayı UYDURULMAZ; düzelince adım tamama döner', (t) async {
      final auth = SetupWizardFakeAuth()..structureError = 'Bu islem icin site yonetim yetkisi gerekir.';
      final run = _Run(auth: auth);
      await _launch(t, run);
      // Yapı okunamadığından hiçbir adım tamam sayılmaz: sihirbaz ilk adımdan açılır.
      expect(_title(t), 'Adım 1 / 6 · Site bilgileri');
      expect(find.byKey(const ValueKey<String>('site_setup_error_siteInfo')), findsOneWidget);
      expect(_enabled(t, 'site_setup_next'), isTrue, reason: 'kullanıcı kilitlenmez');
      await _tap(t, 'site_setup_next');
      await _tap(t, 'site_setup_next');
      expect(_title(t), 'Adım 3 / 6 · Daireler');
      expect(find.text('Durum alınamadı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_setup_error_apartments')), findsOneWidget);
      expect(find.textContaining('0 daire'), findsNothing, reason: 'hata "yok" demez');
      auth.structureError = null;
      await t.tap(find.text('Tekrar Dene'));
      await _settle(t);
      await _settle(t, 100);
      expect(find.text('Durum alınamadı'), findsNothing);
      expect(find.text('Tamam'), findsOneWidget);
      expect(find.text('6 daire'), findsOneWidget);
      _noError(t);
    });

    testWidgets('kişi sayısı okunamazsa kişiler adımı hata gösterir ("Henüz kişi yok" DENMEZ)', (t) async {
      final auth = SetupWizardFakeAuth()..peopleError = ApiException('Kişiler alınamadı.', statusCode: 500);
      final run = _Run(auth: auth);
      await _launch(t, run);
      expect(find.text('Henüz kişi yok'), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_setup_error_people')), findsOneWidget);
      expect(find.text('Kişiler alınamadı.'), findsOneWidget);
      _noError(t);
    });

    testWidgets('yönetici olmayan rol sihirbazı kullanamaz', (t) async {
      final run = _Run(auth: SetupWizardFakeAuth(role: UserRole.apartmentOwner));
      await _launch(t, run);
      expect(find.byKey(const ValueKey<String>('site_setup_forbidden')), findsOneWidget);
      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('site_setup_step_title')), findsNothing);
      _noError(t);
    });

    testWidgets('yükleme sürerken iskelet gösterilir, adım düğmeleri yoktur', (t) async {
      final auth = SetupWizardFakeAuth()..structureGate = Completer<void>();
      final run = _Run(auth: auth);
      await _launch(t, run);
      expect(find.byKey(const ValueKey<String>('site_setup_step_title')), findsNothing);
      expect(find.byKey(const ValueKey<String>('site_setup_next')), findsNothing);
      auth.structureGate!.complete();
      await _settle(t);
      await _settle(t, 100);
      expect(_title(t), 'Adım 4 / 6 · Kişiler');
      _noError(t);
    });
  });

  group('taşma matrisi', () {
    for (final (w, h, scale) in _cells) {
      for (final dark in const <bool>[false, true]) {
        final label = '${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}';

        testWidgets('altı adım ve özet taşmaz: $label', (t) async {
          final auth = SetupWizardFakeAuth(siteName: _longSite, address: 'Çok Uzun Mahalle Adı Mahallesi, Gül Bahçesi Caddesi No: 12/4 Kadıköy / İstanbul');
          final run = _Run(auth: auth, useController: true, siteName: _longSite);
          await _launch(t, run, width: w, height: h, scale: scale, dark: dark);
          final c = run.controller!;
          for (final step in SiteSetupStep.values) {
            c.goTo(step);
            await _settle(t, 100);
            _noError(t, step.name);
            expect(find.byKey(ValueKey<String>('site_setup_card_${step.name}')), findsOneWidget, reason: step.name);
          }
          c.skip();
          await _settle(t, 100);
          expect(find.text('Kurulum özeti'), findsWidgets);
          _noError(t, 'özet');
          c.dispose();
        });

        testWidgets('hata durumu ve süper kullanıcı düzenleme düğmesi taşmaz: $label', (t) async {
          final auth = SetupWizardFakeAuth.superUser()
            ..siteName = _longSite
            ..modulesError = ApiException('Modüller alınamadı.', statusCode: 500)
            ..peopleError = ApiException('Kişiler alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.', statusCode: 500);
          final run = _Run(auth: auth, useController: true, siteName: _longSite);
          await _launch(t, run, width: w, height: h, scale: scale, dark: dark);
          final c = run.controller!;
          for (final step in SiteSetupStep.values) {
            c.goTo(step);
            await _settle(t, 100);
            _noError(t, step.name);
          }
          c.dispose();
        });
      }
    }
  });
}
