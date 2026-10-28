// K8 (P1-16): yetenek / menü katman ayrımı — ana kabuk (HomePage) entegrasyonu.
//
// Sözleşmeler:
// - Sunucu katalogu YETENEKLERİ belirler (temel modüller her sitede açık); MENÜ YERLEŞİMİ ayrı katmandır: site başına kompakt menü kümesi
//   çekmeceyi ve Panel vitrinini değiştirir, kümede olmayan işlem KAYBOLMAZ ve "Tüm işlemler"den açılır.
// - "Tüm işlemler" çekmecede HER ZAMAN vardır ve kompakt kümeden bağımsız TAM listedir.
// - Küme değişince (yönetici ayarı) menü hemen değişir, "Tüm işlemler" tam kalır; temel modüller yine açıktır.
// - Eski sunucu (menu_layout alanı yok) ve süper kullanıcıda kompakt menü yoktur: menü eskisi gibidir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/menu_layout.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/all_actions_view.dart';
import 'package:site_kapi_kontrol/ui/views/menu_layout_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../support/menu_nav.dart';

final SiteRecord _site = SiteRecord(
  id: 1,
  name: 'Güneş Sitesi',
  address: null,
  city: null,
  district: null,
  blockCount: 1,
  apartmentCount: 4,
  doorCount: 1,
  approvalStatus: 'approved',
  approvedAt: DateTime(2026, 1, 1),
  mqttSiteId: 1,
  managerUserCode: 5,
  managerName: 'Yönetici',
  createdAt: DateTime(2026, 1, 1),
);

final DoorRecord _door = DoorRecord(
  id: 11,
  siteCode: 1,
  siteName: 'Güneş Sitesi',
  doorName: 'Ana Kapı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'AABBCCDD',
  mqttSiteId: 1,
  createdAt: DateTime(2026, 1, 1),
);

UserSession _sessionFor(UserRole role) => UserSession(
      id: role == UserRole.superUser ? 1 : 5,
      fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Ayşe Yılmaz',
      email: 'kullanici@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: 'tok',
    );

class _Auth extends AuthService {
  _Auth(this.role) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;
  int openDoorCalls = 0;
  final List<({int site, String code, bool enabled})> moduleToggles = <({int site, String code, bool enabled})>[];

  @override
  UserSession? get session => _sessionFor(role);

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(DoorRuntimeStatus?, String?)> openDoor({required int doorId, DoorRecord? door}) async {
    openDoorCalls++;
    return (null, null);
  }

  @override
  Future<SiteModulesState> setSiteModule(int siteCode, String moduleCode, bool enabled, {bool confirm = false}) async {
    moduleToggles.add((site: siteCode, code: moduleCode, enabled: enabled));
    throw StateError('menü yerleşimi modül açıp kapatmamalı');
  }

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: [_site], total: 1, page: 1, pageSize: 100);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async => (
        SiteStructureRecord(
          site: _site,
          blocks: const <SiteBlockRecord>[],
          apartments: const <ApartmentRecord>[],
          doors: [_door],
        ),
        null,
      );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (
        role == UserRole.individual || role == UserRole.apartmentOwner ? <DoorRecord>[_door] : <DoorRecord>[],
        null,
      );

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<MySiteApplications> getMySiteApplications() async => const MySiteApplications();

  @override
  Future<MyFinance> getMyFinance() async => const MyFinance(items: <MyFinanceApartment>[]);
}

const List<String> _coreCodes = <String>[
  'people',
  'announcements',
  'finance',
  'survey',
  'neighbor_board',
  'equipment',
  'annual_report',
  'drive_storage',
];

/// Sunucunun yanıtı: 8 temel modül her sitede AÇIK + kapı modülü açık; [layout] null ise eski sunucu (alan yok).
MySiteModules _my(String role, {SiteMenuLayout? layout, Set<String> open = const <String>{}}) => MySiteModules(
      siteCode: 1,
      siteName: 'Güneş Sitesi',
      role: role,
      modules: <String, bool>{
        for (final c in _coreCodes) c: true,
        'door_control': true,
        for (final c in open) c: true,
      },
      doorAccess: role != 'staff' && role != 'board_member',
      menuLayout: layout,
    );

const SiteMenuLayout _compact = SiteMenuLayout(compactModules: <String>['people', 'announcements', 'finance']);

Future<ModuleAccess> _access(List<MySiteModules> Function() sites, {bool superUser = false}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(scope: superUser ? 'all' : 'sites', sites: sites()),
    isSuperUser: () => superUser,
  );
  await access.refresh();
  addTearDown(access.dispose);
  return access;
}

AnnouncementNotifier _quietNotifier() => AnnouncementNotifier(
      fetchSummary: () async => throw StateError('yok'),
      fetchInbox: () async => throw StateError('yok'),
      fetchAnnouncement: (id) async => throw StateError('yok'),
      isEligible: () => false,
    );

Future<void> _pumpHome(
  WidgetTester t,
  _Auth auth,
  ModuleAccess access, {
  double width = 400,
  double height = 2400,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final announcements = _quietNotifier();
  addTearDown(announcements.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: announcements),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Finder _tile(SirketMenuItem item) => find.byKey(ValueKey<SirketMenuItem>(item));
Finder _card(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_kart_${item.name}'));
final Finder _allActionsTile = find.byKey(const ValueKey<String>('yan_menu_tum_islemler'));
final Finder _allActionsCard = find.byKey(const ValueKey<String>('panel_kart_tumIslemler'));
Finder _row(SirketMenuItem item) => find.byKey(ValueKey<String>('tum_islemler_${item.name}'));
Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

/// Çekmeceden "Tüm işlemler"i açar.
Future<void> _openAllActionsFromDrawer(WidgetTester t) async {
  await openMenuDrawer(t);
  await t.ensureVisible(_allActionsTile);
  await t.pump();
  await t.tap(_allActionsTile);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  group('yönetici: kompakt menü çekmeceyi ve Panel\'i değiştirir, "Tüm işlemler" tam kalır', () {
    testWidgets('çekmece: öne çıkanlar + sabit öğeler + "Tüm işlemler"; kümede olmayan temel modül öğeleri çekmecede YOK', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
      await _pumpHome(t, auth, access);
      final titles = await drawerTitlesOnly(t);
      for (final shown in <String>['Panel', 'Kapılar', 'Site Yönetimi', 'Kişiler', 'Duyurular', 'Finans', 'Daireye Katıl', 'Tüm işlemler', 'Yardım ve Destek']) {
        expect(titles, contains(shown), reason: shown);
      }
      for (final hidden in <String>['Anket ve Oylama', 'Komşu Panosu', 'Dosya Deposu', 'Faaliyet Raporu', 'Ekipman ve Bakım']) {
        expect(titles, isNot(contains(hidden)), reason: '$hidden yalnız "Tüm işlemler"de');
      }
      expect(await settingsTitlesOnly(t), contains('Modüller'), reason: 'Ayarlar paneli kompakt menüden etkilenmez');
      await _disposeHome(t);
    });

    testWidgets('Panel vitrini: çekmeceyle aynı küme + "Tüm işlemler" kartı; hızlı erişim kaybolmaz', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
      await _pumpHome(t, auth, access);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_card(SirketMenuItem.finans), findsOneWidget);
      expect(_card(SirketMenuItem.kisiler), findsOneWidget);
      expect(_card(SirketMenuItem.kapilar), findsOneWidget);
      for (final hidden in <SirketMenuItem>[SirketMenuItem.anketler, SirketMenuItem.komsuPanosu, SirketMenuItem.belgeler, SirketMenuItem.faaliyetRaporu, SirketMenuItem.ekipmanBakim]) {
        expect(_card(hidden), findsNothing, reason: '${hidden.name} kartı yok');
      }
      await t.ensureVisible(_allActionsCard);
      expect(_allActionsCard, findsOneWidget);
      expect(find.descendant(of: _allActionsCard, matching: find.text('Tüm işlemler')), findsOneWidget);
      // "Hesap ve ayarlar" satırı kompakt menüden etkilenmez.
      expect(find.byKey(const ValueKey<String>('panel_ikincil_profilim')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('çekmeceden "Tüm işlemler": kümede olmayanlar DAHİL görünür TÜM işlemler, kategorili; "Ana menüde" işareti yalnız küme üyelerinde', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
      await _pumpHome(t, auth, access);
      await _openAllActionsFromDrawer(t);
      expect(find.byType(AllActionsView), findsOneWidget);
      for (final item in <SirketMenuItem>[
        SirketMenuItem.kapilar,
        SirketMenuItem.kisiler,
        SirketMenuItem.duyurular,
        SirketMenuItem.finans,
        SirketMenuItem.anketler,
        SirketMenuItem.komsuPanosu,
        SirketMenuItem.belgeler,
        SirketMenuItem.faaliyetRaporu,
        SirketMenuItem.ekipmanBakim,
        SirketMenuItem.siteler,
        SirketMenuItem.profilim,
        SirketMenuItem.moduller,
      ]) {
        await t.ensureVisible(_row(item));
        expect(_row(item), findsOneWidget, reason: '${item.name} tam listede');
      }
      expect(find.descendant(of: _row(SirketMenuItem.finans), matching: find.text('Ana menüde')), findsOneWidget);
      expect(find.descendant(of: _row(SirketMenuItem.anketler), matching: find.text('Ana menüde')), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('"Tüm işlemler"den kümede olmayan işlem açılır (çekmeceden seçmekle aynı gezinme)', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
      await _pumpHome(t, auth, access);
      await _openAllActionsFromDrawer(t);
      await t.ensureVisible(_row(SirketMenuItem.belgeler));
      await t.pump();
      await t.tap(_row(SirketMenuItem.belgeler));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(AllActionsView), findsNothing, reason: 'ekran kapandı');
      expect(_inAppBar(find.text('Dosya Deposu')), findsOneWidget, reason: 'sayfa açıldı');
      await _disposeHome(t);
    });

    testWidgets('Panel\'deki "Tüm işlemler" kartı da tam listeyi açar', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
      await _pumpHome(t, auth, access);
      await t.ensureVisible(_allActionsCard);
      await t.pump();
      await t.tap(_allActionsCard);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(AllActionsView), findsOneWidget);
      await t.ensureVisible(_row(SirketMenuItem.anketler));
      expect(_row(SirketMenuItem.anketler), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('KÜME DEĞİŞİNCE menü değişir ama "Tüm işlemler" tam kalır; temel modüller açık kalır, modül çağrısı yok', (t) async {
      final auth = _Auth(UserRole.siteManager);
      var layout = _compact;
      final access = await _access(() => <MySiteModules>[_my('manager', layout: layout)]);
      await _pumpHome(t, auth, access);

      await openMenuDrawer(t);
      expect(_tile(SirketMenuItem.anketler), findsNothing);
      expect(_tile(SirketMenuItem.finans), findsOneWidget);
      await closeMenuPanels(t);
      await _openAllActionsFromDrawer(t);
      final fullBefore = <SirketMenuItem>[
        for (final item in SirketMenuItem.values)
          if (_row(item).evaluate().isNotEmpty) item,
      ];
      expect(fullBefore, contains(SirketMenuItem.anketler));

      // Yönetici ana menüyü değiştirir: anket öne çıkar, finans çıkar. (Sunucu yanıtı bir sonraki yenilemede gelir.)
      layout = const SiteMenuLayout(compactModules: <String>['people', 'announcements', 'survey'], customized: true);
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final fullAfter = <SirketMenuItem>[
        for (final item in SirketMenuItem.values)
          if (_row(item).evaluate().isNotEmpty) item,
      ];
      expect(fullAfter, fullBefore, reason: '"Tüm işlemler" kümeden bağımsız tam kalır');
      expect(find.descendant(of: _row(SirketMenuItem.anketler), matching: find.text('Ana menüde')), findsOneWidget, reason: 'işaret yenilendi');
      expect(find.descendant(of: _row(SirketMenuItem.finans), matching: find.text('Ana menüde')), findsNothing);

      Navigator.of(t.element(find.byType(AllActionsView))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await openMenuDrawer(t);
      expect(_tile(SirketMenuItem.anketler), findsOneWidget, reason: 'çekmece yeni küme');
      expect(_tile(SirketMenuItem.finans), findsNothing);
      await closeMenuPanels(t);

      // Yetenek katmanı: 8 temel modül hâlâ AÇIK; yerleşim hiçbir modülü açıp kapatmadı.
      for (final code in _coreCodes) {
        expect(access.isEnabled(1, code), isTrue, reason: '$code (temel) açık');
      }
      expect(auth.moduleToggles, isEmpty);
      await _disposeHome(t);
    });

    testWidgets('yönetici "Tüm işlemler"de "Ana menüyü düzenle" düğmesini görür; dokununca düzen ekranı açılır', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
      await _pumpHome(t, auth, access);
      await _openAllActionsFromDrawer(t);
      final edit = find.byKey(const ValueKey<String>('tum_islemler_menu_duzenle'));
      expect(edit, findsOneWidget);
      await t.tap(edit);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(MenuLayoutView), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('kompakt menü uygulanmayan durumlar: menü eskisi gibi, "Tüm işlemler" yine var', () {
    testWidgets('eski sunucu (menu_layout alanı yok): tüm öğeler çekmecede, Panel\'de "Tüm işlemler" kartı yok; çekmecede giriş var', (t) async {
      final auth = _Auth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access);
      final titles = await drawerTitlesOnly(t);
      for (final shown in <String>['Anket ve Oylama', 'Komşu Panosu', 'Dosya Deposu', 'Faaliyet Raporu', 'Ekipman ve Bakım', 'Tüm işlemler']) {
        expect(titles, contains(shown), reason: shown);
      }
      expect(_allActionsCard, findsNothing, reason: 'hiçbir şey gizli değil: ayrı kart gereksiz');
      await _openAllActionsFromDrawer(t);
      expect(find.text('Ana menüde'), findsNothing, reason: 'kompakt menü yok: işaret de yok');
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: kompakt menü yok (tüm yönetim öğeleri çekmecede); "Tüm işlemler" var', (t) async {
      final auth = _Auth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access);
      final titles = await drawerTitlesOnly(t);
      expect(titles, containsAll(<String>['Kapılar', 'Site Yönetimi', 'Kişiler', 'Tüm işlemler']));
      expect(_allActionsCard, findsNothing);
      await _disposeHome(t);
    });
  });

  group('daire sakini', () {
    testWidgets('kompakt menü sakinin çekmecesini de kısaltır; "Tüm işlemler" sakin işlemlerinin tamamını listeler; düzenleme düğmesi yok', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', layout: _compact)]);
      await _pumpHome(t, auth, access);
      final titles = await drawerTitlesOnly(t);
      expect(titles, containsAll(<String>['Borcum', 'Duyurular', 'Kapılar', 'Tüm işlemler']));
      for (final hidden in <String>['Anketler', 'Komşu Panosu', 'Dosya Deposu']) {
        expect(titles, isNot(contains(hidden)), reason: hidden);
      }
      await closeMenuPanels(t);
      await _openAllActionsFromDrawer(t);
      for (final item in <SirketMenuItem>[SirketMenuItem.borcum, SirketMenuItem.anket, SirketMenuItem.komsuPanosu, SirketMenuItem.belgeler]) {
        await t.ensureVisible(_row(item));
        expect(_row(item), findsOneWidget, reason: item.name);
      }
      expect(find.byKey(const ValueKey<String>('tum_islemler_menu_duzenle')), findsNothing, reason: 'yalnız yönetici düzenler');
      await _disposeHome(t);
    });

    testWidgets('kompakt menü sakin hızlı eylemlerini ve borç kartını GİZLEMEZ (yalnız modül ızgarası kısalır)', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', layout: const SiteMenuLayout(customized: true))]);
      await _pumpHome(t, auth, access);
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsOneWidget, reason: 'Kapıyı aç hızlı eylemi');
      expect(find.byKey(const ValueKey<String>('panel_hizli_belgeler')), findsOneWidget, reason: 'Dosya Deposu hızlı eylemi');
      await _disposeHome(t);
    });
  });

  group('taşma yok', () {
    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      testWidgets('${w.toInt()}x${h.toInt()} x$s: kompakt Panel + çekmece + Tüm işlemler', (t) async {
        final auth = _Auth(UserRole.siteManager);
        final access = await _access(() => <MySiteModules>[_my('manager', layout: _compact)]);
        await _pumpHome(t, auth, access, width: w, height: h, scale: s);
        expect(t.takeException(), isNull);
        await openMenuDrawer(t);
        await t.ensureVisible(_allActionsTile);
        await t.pump();
        expect(t.takeException(), isNull);
        await t.tap(_allActionsTile);
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(t.takeException(), isNull);
        await _disposeHome(t);
      });
    }
  });
}
