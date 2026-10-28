// K8 (P1-16): "Ana menü düzeni" ekranı (site yöneticisi). YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır: ekran HİÇBİR modülü açıp kapatmaz;
// temel modüller her sitede açık kalır, yalnız ana menüde öne çıkıp çıkmayacakları seçilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/menu_layout.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/menu_layout_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/menu_layout_view.dart';

import 'modules_fixtures.dart';

MenuLayoutModule _m(
  String code,
  String name, {
  bool core = false,
  bool enabled = true,
  bool compact = false,
  bool recommended = false,
}) =>
    MenuLayoutModule(
      code: code,
      name: name,
      description: '$name açıklaması',
      core: core,
      enabled: enabled,
      compact: compact,
      recommended: recommended,
    );

SiteMenuLayoutState _state(int site, {bool customized = false, List<String>? compact, List<MenuLayoutModule>? modules}) {
  final list = modules ??
      <MenuLayoutModule>[
        _m('door_control', 'Geçiş Kontrol (SmartKeyPass)', compact: true, recommended: true),
        _m('people', 'Kişi ve Daire Kayıtları', core: true, compact: true),
        _m('announcements', 'Duyuru ve Bildirim', core: true, compact: true),
        _m('finance', 'Aidat ve Finans', core: true, compact: true, recommended: true),
        _m('reservation', 'Rezervasyon ve Konsiyerj', enabled: false),
        _m('work_tracking', 'İş Takibi', compact: true),
        _m('survey', 'Anket ve Oylama', core: true),
        _m('drive_storage', 'Dosya Deposu', core: true, compact: true, recommended: true),
        _m('neighbor_board', 'Komşu Panosu', core: true),
      ];
  final codes = compact ?? <String>[for (final m in list) if (m.compact) m.code];
  return SiteMenuLayoutState(
    siteCode: site,
    siteName: 'Site $site',
    managementTypeLabel: 'Apartman ve Site',
    customized: customized,
    compactModules: codes,
    defaultCompactModules: codes,
    modules: <MenuLayoutModule>[for (final m in list) _m2(m, codes.contains(m.code))],
  );
}

MenuLayoutModule _m2(MenuLayoutModule m, bool compact) => MenuLayoutModule(
      code: m.code,
      name: m.name,
      description: m.description,
      core: m.core,
      enabled: m.enabled,
      compact: compact,
      recommended: m.recommended,
    );

class _FakeLayoutService extends MenuLayoutService {
  _FakeLayoutService(ModulesFakeAuth auth, {Map<int, SiteMenuLayoutState>? states})
      : states = states ?? <int, SiteMenuLayoutState>{11: _state(11), 12: _state(12, customized: true, compact: <String>['finance'])},
        super(authService: auth);

  final Map<int, SiteMenuLayoutState> states;
  final List<int> loads = <int>[];
  final List<({int site, List<String> modules})> saves = <({int site, List<String> modules})>[];
  final List<int> resets = <int>[];
  Object? loadError;
  Object? saveError;

  @override
  Future<SiteMenuLayoutState> load(int siteCode) async {
    loads.add(siteCode);
    final error = loadError;
    if (error != null) throw error;
    return states[siteCode]!;
  }

  @override
  Future<SiteMenuLayoutState> save(int siteCode, List<String> compactModules) async {
    saves.add((site: siteCode, modules: List<String>.of(compactModules)));
    final error = saveError;
    if (error != null) throw error;
    final current = states[siteCode]!;
    final chosen = compactModules.toSet();
    return states[siteCode] = SiteMenuLayoutState(
      siteCode: siteCode,
      siteName: current.siteName,
      managementTypeLabel: current.managementTypeLabel,
      customized: true,
      compactModules: <String>[for (final m in current.modules) if (chosen.contains(m.code)) m.code],
      defaultCompactModules: current.defaultCompactModules,
      modules: <MenuLayoutModule>[for (final m in current.modules) _m2(m, chosen.contains(m.code))],
    );
  }

  @override
  Future<SiteMenuLayoutState> reset(int siteCode) async {
    resets.add(siteCode);
    final current = states[siteCode]!;
    final defaults = current.defaultCompactModules.toSet();
    return states[siteCode] = SiteMenuLayoutState(
      siteCode: siteCode,
      siteName: current.siteName,
      managementTypeLabel: current.managementTypeLabel,
      customized: false,
      compactModules: current.defaultCompactModules,
      defaultCompactModules: current.defaultCompactModules,
      modules: <MenuLayoutModule>[for (final m in current.modules) _m2(m, defaults.contains(m.code))],
    );
  }
}

Finder _row(String code) => find.byKey(ValueKey<String>('menu_duzeni_modul_$code'));
Finder _switchOf(String code) => find.descendant(of: _row(code), matching: find.byType(Switch));
final Finder _save = find.byKey(const ValueKey<String>('menu_duzeni_kaydet'));
final Finder _all = find.byKey(const ValueKey<String>('menu_duzeni_hepsi'));
final Finder _defaults = find.byKey(const ValueKey<String>('menu_duzeni_varsayilan'));
final Finder _status = find.byKey(const ValueKey<String>('menu_duzeni_durum'));

bool _on(WidgetTester t, String code) => t.widget<Switch>(_switchOf(code)).value;
/// [PrimaryActionButton] etkin mi? (devre dışı düğmenin InkWell'i dokunma almaz)
bool _enabled(WidgetTester t, Finder button) =>
    t.widget<InkWell>(find.descendant(of: button, matching: find.byType(InkWell)).first).onTap != null;

/// Ekranı bir açıcı sayfanın üstünde kurar (geri tuşu / PopScope çalışsın diye).
Future<void> _pump(
  WidgetTester t,
  ModulesFakeAuth auth,
  _FakeLayoutService service, {
  VoidCallback? onChanged,
  int? initialSite,
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey<String>('ac'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => MenuLayoutView(
                    authService: auth,
                    service: service,
                    initialSiteCode: initialSite,
                    onChanged: onChanged,
                  ),
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const ValueKey<String>('ac')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump();
}

void main() {
  late ModulesFakeAuth auth;
  late _FakeLayoutService service;

  setUp(() {
    auth = ModulesFakeAuth(fixtureRole: UserRole.siteManager);
    service = _FakeLayoutService(auth);
  });

  group('yükleme ve görünüm', () {
    testWidgets('yalnız menü yüzeyi olan ve AÇIK modüller listelenir; anahtarlar yerleşimi gösterir; kapı ve kapalı modül yok', (t) async {
      await _pump(t, auth, service);
      expect(service.loads, <int>[11]);
      expect(find.text('Ana menü düzeni'), findsWidgets);
      for (final code in <String>['people', 'announcements', 'finance', 'work_tracking', 'survey', 'drive_storage', 'neighbor_board']) {
        expect(_row(code), findsOneWidget, reason: code);
      }
      expect(_row('reservation'), findsNothing, reason: 'kapalı modülün ekranı yok');
      expect(_row('door_control'), findsNothing, reason: 'Kapılar hep ana menüde: kümeye bağlı değil');
      expect(_on(t, 'finance'), isTrue);
      expect(_on(t, 'survey'), isFalse);
      expect(find.byKey(const ValueKey<String>('menu_duzeni_sabit_not')), findsOneWidget);
      expect(find.text('Panel, Kapılar ve hesap işlemleri her zaman ana menüdedir.'), findsOneWidget);
    });

    testWidgets('temel modül satırı "Her sitede açık" der (yetenek değişmez); önerilen modül "Önerilen" rozeti taşır', (t) async {
      await _pump(t, auth, service);
      expect(find.descendant(of: _row('survey'), matching: find.text('Her sitede açık')), findsOneWidget);
      expect(find.descendant(of: _row('work_tracking'), matching: find.text('Her sitede açık')), findsNothing, reason: 'temel değil');
      expect(find.descendant(of: _row('finance'), matching: find.text('Önerilen')), findsOneWidget);
      expect(find.descendant(of: _row('survey'), matching: find.text('Önerilen')), findsNothing);
    });

    testWidgets('durum çipi: önerilen düzen / özel düzen; "Önerilen düzene dön" yalnız özel düzende etkin', (t) async {
      await _pump(t, auth, service);
      expect(find.descendant(of: _status, matching: find.text('Önerilen düzen')), findsOneWidget);
      expect(_enabled(t, _defaults), isFalse);
      await _pump(t, auth, service, initialSite: 12);
      expect(service.loads.last, 12);
      expect(find.descendant(of: _status, matching: find.text('Özel düzen')), findsOneWidget);
      expect(_enabled(t, _defaults), isTrue);
    });

    testWidgets('yükleme hatası: neden + "Tekrar Dene"; tekrar deneyince liste gelir', (t) async {
      service.loadError = ApiException('Menü düzeni yüklenemedi (deneme).', statusCode: 500);
      await _pump(t, auth, service);
      expect(find.text('Menü düzeni yüklenemedi (deneme).'), findsOneWidget);
      service.loadError = null;
      await t.tap(find.text('Tekrar Dene'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(_row('finance'), findsOneWidget);
    });
  });

  group('düzenleme ve kaydetme', () {
    testWidgets('değişiklik yoksa Kaydet pasif; anahtar değişince etkin; geri alınca yine pasif', (t) async {
      await _pump(t, auth, service);
      expect(_enabled(t, _save), isFalse);
      await t.tap(_switchOf('survey'));
      await t.pump();
      expect(_on(t, 'survey'), isTrue);
      expect(_enabled(t, _save), isTrue);
      await t.tap(_switchOf('survey'));
      await t.pump();
      expect(_enabled(t, _save), isFalse);
    });

    testWidgets('kaydet: sunucuya yalnız modül kodları gider; sonuç ekrana yansır, onChanged çağrılır; HİÇBİR modül açılıp kapatılmaz', (t) async {
      var changed = 0;
      await _pump(t, auth, service, onChanged: () => changed++);
      await t.tap(_switchOf('survey'));
      await t.tap(_switchOf('finance'));
      await t.pump();
      await t.tap(_save);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(service.saves.single.site, 11);
      expect(service.saves.single.modules.toSet(), <String>{'door_control', 'people', 'announcements', 'work_tracking', 'survey', 'drive_storage'},
          reason: 'finance çıkarıldı, survey eklendi; menü yüzeyi olmayan door_control olduğu gibi korunur');
      expect(changed, 1, reason: 'menü sunucudan yeniden okunur');
      expect(auth.setCalls, isEmpty, reason: 'yetenek (modül açık/kapalı) değişmez');
      expect(find.text('Ana menü düzeni kaydedildi.'), findsOneWidget);
      expect(find.descendant(of: _status, matching: find.text('Özel düzen')), findsOneWidget);
      expect(_enabled(t, _save), isFalse, reason: 'kaydedildi: temiz');
    });

    testWidgets('TEMEL modül ana menüden çıkarılabilir ama kapatılamaz: payload\'ta yok, yetenek (enabled) korunur, modül çağrısı yok', (t) async {
      await _pump(t, auth, service);
      await t.tap(_switchOf('people'));
      await t.pump();
      await t.tap(_save);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(service.saves.single.modules, isNot(contains('people')));
      expect(auth.setCalls, isEmpty);
      // Sunucu yanıtında modül hâlâ AÇIK; satır listede durur ve anahtar yalnız yerleşimi gösterir.
      final saved = service.states[11]!.modules.firstWhere((m) => m.code == 'people');
      expect([saved.core, saved.enabled, saved.compact], [true, true, false]);
      expect(_row('people'), findsOneWidget);
      expect(_on(t, 'people'), isFalse);
    });

    testWidgets('kapalı modül kodu kümedeyse kaydederken KORUNUR (modül sonradan açılınca menüde kalır)', (t) async {
      final state = _state(11, customized: true, compact: <String>['finance', 'reservation']);
      service.states[11] = state;
      await _pump(t, auth, service);
      await t.tap(_switchOf('survey'));
      await t.pump();
      await t.tap(_save);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(service.saves.single.modules, containsAll(<String>['reservation', 'finance', 'survey']));
    });

    testWidgets('"Hepsini göster" listelenen her modülü seçer (tam menü)', (t) async {
      await _pump(t, auth, service);
      await t.tap(_all);
      await t.pump();
      for (final code in <String>['people', 'announcements', 'finance', 'work_tracking', 'survey', 'drive_storage', 'neighbor_board']) {
        expect(_on(t, code), isTrue, reason: code);
      }
      expect(_enabled(t, _save), isTrue);
    });

    testWidgets('"Önerilen düzene dön": sunucuya sıfırlama gider, ekran önerilen düzene geçer, onChanged çağrılır', (t) async {
      var changed = 0;
      await _pump(t, auth, service, initialSite: 12, onChanged: () => changed++);
      expect(_on(t, 'survey'), isFalse);
      service.states[12] = SiteMenuLayoutState(
        siteCode: 12,
        siteName: 'Site 12',
        managementTypeLabel: 'Apartman ve Site',
        customized: true,
        compactModules: const <String>['finance'],
        defaultCompactModules: const <String>['finance', 'people'],
        modules: _state(12, compact: <String>['finance']).modules,
      );
      await t.tap(_defaults);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(service.resets, <int>[12]);
      expect(changed, 1);
      expect(find.text('Önerilen düzene dönüldü.'), findsOneWidget);
      expect(find.descendant(of: _status, matching: find.text('Önerilen düzen')), findsOneWidget);
      expect(_on(t, 'people'), isTrue);
    });

    testWidgets('kaydetme hatası: ileti gösterilir, seçim korunur (kaydet yeniden denenebilir); menü yine de yenilenir', (t) async {
      var changed = 0;
      service.saveError = ApiException('Çok fazla menü değişikliği. Biraz sonra tekrar deneyin.', statusCode: 429);
      await _pump(t, auth, service, onChanged: () => changed++);
      await t.tap(_switchOf('survey'));
      await t.pump();
      await t.tap(_save);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Çok fazla menü değişikliği. Biraz sonra tekrar deneyin.'), findsOneWidget);
      expect(_on(t, 'survey'), isTrue);
      expect(_enabled(t, _save), isTrue);
      expect(changed, 1);
    });
  });

  group('kaydedilmemiş değişiklik koruması', () {
    testWidgets('değişiklik varken geri: onay penceresi; "Düzenlemeye devam" ekranda tutar, "Değişiklikleri at" kapatır', (t) async {
      await _pump(t, auth, service);
      await t.tap(_switchOf('survey'));
      await t.pump();
      await t.tap(find.byType(BackButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await t.tap(find.text('Düzenlemeye devam'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(MenuLayoutView), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Değişiklikleri at'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(MenuLayoutView), findsNothing);
    });

    testWidgets('değişiklik yokken geri doğrudan kapatır', (t) async {
      await _pump(t, auth, service);
      await t.tap(find.byType(BackButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(MenuLayoutView), findsNothing);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('yenilemede değişiklik varsa önce sorulur (seçim sessizce ezilmez); atılırsa sunucudan yeniden okunur', (t) async {
      await _pump(t, auth, service);
      expect(service.loads, <int>[11]);
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(service.loads, <int>[11, 11], reason: 'değişiklik yok: doğrudan yenilenir');
      await t.tap(_switchOf('survey'));
      await t.pump();
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await t.tap(find.text('Düzenlemeye devam'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(service.loads, <int>[11, 11], reason: 'vazgeçildi: yeniden okuma yok');
      expect(_on(t, 'survey'), isTrue, reason: 'seçim korunur');
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Değişiklikleri at'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(service.loads, <int>[11, 11, 11]);
      expect(_on(t, 'survey'), isFalse, reason: 'sunucudaki düzene dönüldü');
    });

    testWidgets('site değiştirirken değişiklik varsa onay istenir; atılırsa yeni sitenin düzeni yüklenir', (t) async {
      await _pump(t, auth, service);
      await t.tap(_switchOf('survey'));
      await t.pump();
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Mavi Park (12)').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await t.tap(find.text('Değişiklikleri at'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(service.loads, <int>[11, 12]);
      expect(find.descendant(of: _status, matching: find.text('Özel düzen')), findsOneWidget);
    });
  });

  group('taşma yok', () {
    const cells = <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (640, 320, 2.0)];
    for (final (w, h, s) in cells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}: liste, rozetler, düğmeler', (t) async {
          await _pump(t, auth, service, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);
          await t.tap(_switchOf('finance').first, warnIfMissed: false);
          for (final code in <String>['people', 'finance', 'survey', 'neighbor_board']) {
            await t.ensureVisible(_row(code));
            await t.pump();
          }
          await t.ensureVisible(_save);
          await t.pump();
          await t.ensureVisible(_defaults);
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}
