// P1-13 (karşılaştırma raporu, Arayüz): iç ekranlardan tek dokunuşla ana sayfaya (Panel) dönüş.
//
// - Üst çubukta menü düğmesinin yanında "Ana sayfa" düğmesi: yalnız iç ekranlarda ve sakin alt çubuğu (Özet sekmesi)
//   YOKKEN çıkar (yönetici, süper kullanıcı, bireysel, ikiden az sekmeli sakin hesabı, yatay telefon). Çubuk varken ikinci
//   bir yol üretilmez; Panel'in kendisinde düğme yoktur.
// - Dokununca Panel'e döner (çekmeceden "Panel"i seçmekle aynı korumalı gezinme); donanım geri tuşu, çekmece ve alt çubuk
//   davranışı değişmez. Ekran okuyucu ve ipucu adı "Ana sayfa"; dokunma hedefi >= 44 dp.
// - Derin (yeni sayfa olarak açılan) ekranlar: `HomeShortcutButton` açık ekranların hepsini kapatıp Panel'i seçtirir.
// - Taşma yok: 320x640 x2,0 dahil boyut x yazı ölçeği x tema matrisinde düğmeler üst üste binmez. En kalabalık üst çubukta
//   (çift modlu hesap + tema düğmesi) sağdaki eylemlerle sığmayan dar telefonlarda (348 dp altı) düğme çizilmez; öteki
//   hesaplarda 320 dp'de de vardır. Ana sayfa varken mod hapı 480 dp altında yalnız ikondur (etiket "Sakin Mo…" kesilmesin).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/bank_import.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
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
import 'package:site_kapi_kontrol/services/bank_import_api.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/panel_return_requests.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/theme_toggle_button.dart';
import 'package:site_kapi_kontrol/ui/helpers/home_shortcut.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/resident_tabs.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/bank_lines_view.dart';
import 'package:site_kapi_kontrol/ui/views/help_content.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/home_shortcut_button.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

SiteRecord _siteRecord(int id, String name) => SiteRecord(
      id: id,
      name: name,
      address: null,
      city: null,
      district: null,
      blockCount: 1,
      apartmentCount: 4,
      doorCount: 1,
      approvalStatus: 'approved',
      approvedAt: DateTime(2026, 1, 1),
      mqttSiteId: id,
      managerUserCode: 5,
      managerName: 'Yönetici',
      createdAt: DateTime(2026, 1, 1),
    );

DoorRecord _door(int site) => DoorRecord(
      id: site * 10 + 1,
      siteCode: site,
      siteName: 'Site $site',
      doorName: 'Ana Kapı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'AABBCC0$site',
      mqttSiteId: site,
      createdAt: DateTime(2026, 1, 1),
    );

UserSession _session(UserRole role) => UserSession(
      id: role == UserRole.superUser ? 1 : 5,
      fullName: 'Ayşe Yılmaz',
      email: 'ayse@example.com',
      loginName: null,
      role: role,
      isActive: true,
      token: 'tok',
    );

/// HomePage sahte servisi: siteler / kapılar sabit, kapı komutları sayılır (Ana sayfa düğmesi hiçbir yerde kapı açmamalı).
class _ShortcutAuth extends AuthService {
  _ShortcutAuth(this.role, {List<DoorRecord>? doors})
      : doors = doors ?? (role == UserRole.apartmentOwner || role == UserRole.individual ? <DoorRecord>[_door(1)] : <DoorRecord>[]),
        super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;
  final List<DoorRecord> doors;
  int openDoorCalls = 0;

  @override
  UserSession? get session => _session(role);

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
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: <SiteRecord>[_siteRecord(1, 'Güneş Sitesi')], total: 1, page: 1, pageSize: 100);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async => (
        SiteStructureRecord(
          site: _siteRecord(siteCode, 'Güneş Sitesi'),
          blocks: const <SiteBlockRecord>[],
          apartments: const <ApartmentRecord>[],
          doors: <DoorRecord>[_door(siteCode)],
        ),
        null,
      );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (List<DoorRecord>.of(doors), null);

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
}

/// Banka satırları ekranı için boş liste dönen sahte API (ağ yok).
class _EmptyBankApi extends BankImportApi {
  _EmptyBankApi() : super(baseUrl: 'http://localhost');

  @override
  Future<List<BankLineItem>> listLinesByStatus({
    required String token,
    required int siteCode,
    required String status,
  }) async =>
      const <BankLineItem>[];
}

MySiteModules _my(String role, {Map<String, bool> modules = const <String, bool>{}}) => MySiteModules(
      siteCode: 1,
      siteName: 'Güneş Sitesi',
      role: role,
      modules: <String, bool>{'door_control': true, ...modules},
      doorAccess: !(role == 'staff' || role == 'board_member'),
    );

Future<ModuleAccess> _access(List<MySiteModules> sites, {bool superUser = false}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites),
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
  _ShortcutAuth auth, {
  required ModuleAccess access,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
  bool themeToggle = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier();
  addTearDown(notifier.dispose);
  final app = MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier),
  );
  // themeToggle: uygulama kökündeki gibi ThemeScope var -> üst çubukta aydınlık/karanlık geçiş düğmesi çizilir.
  await t.pumpWidget(themeToggle ? ThemeScope(service: ThemeService(), child: app) : app);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

/// Ana kabuğun üst çubuğundaki "Ana sayfa" düğmesi (derin ekranlarınki ayrı bir AppBar'dadır).
final Finder _home = _inAppBar(find.byKey(const ValueKey<String>('ana_sayfa_dugmesi')));
final Finder _gear = _inAppBar(find.byTooltip('Ayarlar'));
final Finder _bar = find.byKey(const ValueKey<String>('sakin_alt_cubuk'));
Finder _tab(ResidentTab tab) => find.byKey(ValueKey<String>('sakin_sekme_${tab.name}'));
Finder _drawerTile(SirketMenuItem item) =>
    find.descendant(of: find.byType(YanMenu), matching: find.byKey(ValueKey<SirketMenuItem>(item)));
Finder _settingsTile(SirketMenuItem item) =>
    find.descendant(of: find.byType(YanMenuAyarlar), matching: find.byKey(ValueKey<SirketMenuItem>(item)));

Future<void> _settle(WidgetTester t, [int ms = 700]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Sağ üstteki dişliden Ayarlar panelini açar ve Profilim'i seçer (her rolde vardır).
Future<void> _openProfile(WidgetTester t) async {
  await t.tap(_gear);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
  await t.tap(_settingsTile(SirketMenuItem.profilim));
  await _settle(t, 600);
  expect(_inAppBar(find.text('Profilim')), findsOneWidget);
}

/// Çekmeceden bir menü öğesini açar.
Future<void> _openFromDrawer(WidgetTester t, SirketMenuItem item) async {
  await _openDrawer(t);
  final tile = _drawerTile(item);
  await t.ensureVisible(tile);
  await t.pump();
  await t.tap(tile);
  await _settle(t);
}

/// Android geri tuşu; dönüş: olay karşılandı mı (false = uygulamadan çıkılır).
Future<bool> _back(WidgetTester t) async {
  final handled = await t.binding.handlePopRoute();
  await _settle(t, 600);
  return handled;
}

List<String> _capturePlatform(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

void main() {
  group('görünürlük kuralı (showsHomeShortcut)', () {
    test('Panel\'de yok; iç ekranda yalnız sakin alt çubuğu yokken ve sağdaki eylemlerle sığıyorsa var', () {
      const actions = 250.0; // yenile + çıkış + dişli + tema + mod hapı + kenar (çift modlu hesap, tema düğmesiyle)
      final edge = homeShortcutLeadingWidth + actions + homeShortcutSlack; // 348 dp
      for (final item in SirketMenuItem.values) {
        for (final bar in const <bool>[false, true]) {
          for (final width in <double>[280, edge - 0.1, edge, 400, 1366]) {
            final expected = item != SirketMenuItem.dashboard && !bar && width >= edge;
            expect(
              showsHomeShortcut(page: item, residentBarVisible: bar, width: width, actionsWidth: actions),
              expected,
              reason: '${item.name} çubuk=$bar genişlik=$width',
            );
          }
        }
      }
      expect(homeShortcutLeadingWidth, 96, reason: 'menü düğmesi 48 + Ana sayfa 48');
      expect(edge, 348);
    });

    test('360 dp ve üstünde en kalabalık üst çubukta (çift modlu hesap + tema düğmesi) bile sığar', () {
      expect(showsHomeShortcut(page: SirketMenuItem.profilim, residentBarVisible: false, width: 360, actionsWidth: 250), isTrue);
      // Mod hapsız (bireysel) hesap 320 dp'de de sığar.
      expect(showsHomeShortcut(page: SirketMenuItem.profilim, residentBarVisible: false, width: 320, actionsWidth: 198), isTrue);
    });

    test('simge Panel\'in menüdeki ve alt çubuktaki simgesidir; ipucu "Ana sayfa"', () {
      expect(HomeShortcutButton.icon, ResidentTab.ozet.icon, reason: 'aynı hedef, aynı simge');
      expect(HomeShortcutButton.icon, ResidentTab.ozet.selectedIcon);
      expect(HomeShortcutButton.label, 'Ana sayfa');
    });
  });

  group('ana kabuk: Ana sayfa düğmesi', () {
    testWidgets('site yöneticisi: Panel\'de düğme yok; iç ekranda menü düğmesinin yanında çıkar, dokununca Panel\'e döner',
        (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access, width: 360);

      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_home, findsNothing, reason: 'Panel zaten ana sayfadır');

      await _openProfile(t);
      expect(_inAppBar(find.text('Profilim')), findsOneWidget);
      expect(_bar, findsNothing, reason: 'yöneticide sakin alt çubuğu yoktur');
      expect(_home, findsOneWidget);

      // Yerleşim: menü düğmesinin hemen sağında, 44 dp hedef, sağdaki eylemlerle çakışmaz.
      final menu = t.getRect(_inAppBar(find.byType(DrawerButton)));
      final home = t.getRect(_home);
      expect(home.left, greaterThanOrEqualTo(menu.right - 0.01), reason: 'menü düğmesine binmez');
      expect(home.width, greaterThanOrEqualTo(44));
      expect(home.height, greaterThanOrEqualTo(44));
      expect(home.right, lessThanOrEqualTo(t.getRect(_inAppBar(find.byTooltip('Sakin Modu'))).left + 0.01));
      expect(t.widget<IconButton>(_home).tooltip, 'Ana sayfa');

      await t.tap(_home);
      await _settle(t);
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'Panel vitrini');
      expect(find.byType(ProfileView), findsNothing);
      expect(_inAppBar(find.text('Panel')), findsOneWidget);
      expect(_home, findsNothing, reason: 'Panel\'e dönünce düğme kalkar');
      expect(auth.openDoorCalls, 0, reason: 'Ana sayfa kapı açmaz');
      await _disposeHome(t);
    });

    testWidgets('Kapılar sayfasında da çıkar; menü düğmesi hâlâ çekmeceyi açar', (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      final card = find.byKey(const ValueKey<String>('panel_kart_kapilar'));
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await _settle(t);
      expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
      expect(_home, findsOneWidget);

      // Menü düğmesi hâlâ çekmeceyi açar (AppBar'ın kendi düğmesiyle aynı).
      await t.tap(_inAppBar(find.byType(DrawerButton)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      expect(find.byType(YanMenu), findsOneWidget);
      await _disposeHome(t);
    });

    for (final (label, role, superUser) in <(String, UserRole, bool)>[
      ('süper kullanıcı', UserRole.superUser, true),
      ('bireysel kullanıcı', UserRole.individual, false),
    ]) {
      testWidgets('$label: iç ekranda düğme var, Panel\'e döner', (t) async {
        final auth = _ShortcutAuth(role);
        final access = await _access(const <MySiteModules>[], superUser: superUser);
        await _pumpHome(t, auth, access: access);
        expect(_home, findsNothing);
        await _openProfile(t);
        expect(_home, findsOneWidget);
        await t.tap(_home);
        await _settle(t);
        expect(find.byType(ModuleShowcaseView), findsOneWidget);
        expect(_home, findsNothing);
        await _disposeHome(t);
      });
    }

    testWidgets('sakin alt çubuğu varken ikinci yol üretilmez: çubuktaki Özet sekmesi Panel\'e döndürür, üst çubukta düğme yok',
        (t) async {
      final auth = _ShortcutAuth(UserRole.apartmentOwner);
      final access = await _access(<MySiteModules>[_my('resident', modules: {'work_tracking': true, 'drive_storage': true})]);
      await _pumpHome(t, auth, access: access);
      expect(_bar, findsOneWidget);
      await t.tap(_tab(ResidentTab.duyuru));
      await _settle(t);
      expect(_inAppBar(find.text('Duyurular')), findsOneWidget);
      expect(_home, findsNothing, reason: 'çubuk varken üst çubukta Ana sayfa yok');
      expect(find.byTooltip('Ana sayfa'), findsNothing);
      // Sekmesi olmayan sayfada (Profilim) da çubuk Özet\'i gösterir; düğme yine yok.
      await _openProfile(t);
      expect(_bar, findsOneWidget);
      expect(_home, findsNothing);
      await t.tap(_tab(ResidentTab.ozet));
      await _settle(t);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi (üç sekme: çubuk var) düğmesiz; yalnız görevli bağı (tek sekme: çubuk yok) düğmeli', (t) async {
      // Kurul üyesi: Özet, Duyuru, Dosyalar -> alt çubuk.
      var auth = _ShortcutAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      var access = await _access(<MySiteModules>[_my('board_member', modules: {'drive_storage': true})]);
      await _pumpHome(t, auth, access: access);
      expect(_bar, findsOneWidget);
      await t.tap(_tab(ResidentTab.duyuru));
      await _settle(t);
      expect(_home, findsNothing);
      await _disposeHome(t);

      // Yalnız görevli bağı: ikiden az sekme -> çubuk çizilmez; Panel\'e dönüş üst çubuktaki düğmeyle.
      auth = _ShortcutAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      access = await _access(<MySiteModules>[_my('staff', modules: {'work_tracking': true})]);
      await _pumpHome(t, auth, access: access);
      expect(_bar, findsNothing, reason: 'tek sekme: çubuk yok');
      expect(_home, findsNothing, reason: 'Panel\'de düğme yok');
      await _openFromDrawer(t, SirketMenuItem.talepler);
      expect(_inAppBar(find.text('Talepler')), findsOneWidget);
      expect(_home, findsOneWidget, reason: 'çubuk yokken Panel\'e dönüş üst çubukta');
      await t.tap(_home);
      await _settle(t);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('yatay telefon (< 480 dp): alt çubuk çizilmez, düğme çıkar; 480 dp\'de çubuk var, düğme yok', (t) async {
      for (final (h, hasBar) in const <(double, bool)>[(479, false), (480, true)]) {
        final auth = _ShortcutAuth(UserRole.apartmentOwner);
        final access = await _access(<MySiteModules>[_my('resident', modules: {'drive_storage': true})]);
        await _pumpHome(t, auth, access: access, width: 800, height: h);
        await _openFromDrawer(t, SirketMenuItem.duyurular);
        expect(_bar, hasBar ? findsOneWidget : findsNothing, reason: 'yükseklik ${h.toInt()}');
        expect(_home, hasBar ? findsNothing : findsOneWidget, reason: 'yükseklik ${h.toInt()}');
        expect(t.takeException(), isNull);
        await _disposeHome(t);
      }
      expect(HomePage.residentBarMinHeight, 480);
    });

    testWidgets('sakin modundaki yönetici: çubuk varken düğme yok; Yönetici Paneli\'ne dönünce iç ekranda düğme var', (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager, doors: <DoorRecord>[_door(1)]);
      final access = await _access(<MySiteModules>[_my('manager', modules: {'drive_storage': true})]);
      await _pumpHome(t, auth, access: access, width: 820, height: 1180);
      await _openProfile(t);
      expect(_home, findsOneWidget, reason: 'yönetici panelinde alt çubuk yok');
      await t.tap(_inAppBar(find.text('Sakin Modu')));
      await _settle(t, 600);
      expect(_bar, findsOneWidget, reason: 'sakin modunda çubuk gelir');
      await t.tap(_tab(ResidentTab.duyuru));
      await _settle(t);
      expect(_home, findsNothing, reason: 'çubuk varken düğme yok');
      await _disposeHome(t);
    });

    testWidgets('geri tuşu davranışı değişmez: iç ekranda geri Panel\'e döner (uygulamadan çıkmaz), Panel\'de çıkar', (t) async {
      final calls = _capturePlatform(t);
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openProfile(t);
      expect(_home, findsOneWidget);
      expect(await _back(t), isTrue, reason: 'geri uygulamadan çıkmaz');
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_home, findsNothing);
      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(await _back(t), isFalse, reason: 'Panel\'de geri bugünkü gibi uygulamadan çıkar');
      expect(calls, contains('SystemNavigator.pop'));
      await _disposeHome(t);
    });

    testWidgets('ekran okuyucu: "Ana sayfa" adlı tek bir düğme (dokunulabilir)', (t) async {
      final handle = t.ensureSemantics();
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openProfile(t);
      expect(find.bySemanticsLabel('Ana sayfa'), findsOneWidget);
      expect(
        t.getSemantics(_home),
        isSemantics(label: 'Ana sayfa', isButton: true, hasTapAction: true),
      );
      handle.dispose();
      await _disposeHome(t);
    });

    testWidgets('en kalabalık çubukta (çift modlu + tema) 348 dp altında düğme çizilmez: taşma ya da üst üste binme yok', (t) async {
      for (final (w, shown) in const <(double, bool)>[(320, false), (347, false), (348, true)]) {
        final auth = _ShortcutAuth(UserRole.siteManager);
        final access = await _access(<MySiteModules>[_my('manager')]);
        await _pumpHome(t, auth, access: access, width: w, height: 800, themeToggle: true);
        await _openProfile(t);
        expect(_home, shown ? findsOneWidget : findsNothing, reason: '${w.toInt()} dp');
        expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
        final menu = t.getRect(_inAppBar(find.byType(DrawerButton)));
        final pill = t.getRect(_inAppBar(find.byTooltip('Sakin Modu')));
        expect(pill.left, greaterThanOrEqualTo(menu.right - 0.01), reason: '${w.toInt()} dp: hap menü düğmesine binmez');
        if (shown) {
          expect(pill.left, greaterThanOrEqualTo(t.getRect(_home).right - 0.01), reason: '348 dp: hap Ana sayfa\'ya binmez');
        }
        await _disposeHome(t);
      }
    });
  });

  group('üst çubuk taşmaz: boyut x yazı ölçeği x tema, iç ekran (Profilim)', () {
    const cells = <({double width, double height, double scale})>[
      (width: 320, height: 640, scale: 2.0), // en dar + en büyük yazı
      (width: 340, height: 640, scale: 1.5),
      (width: 360, height: 640, scale: 1.0),
      (width: 400, height: 800, scale: 1.0), // etiketli hap eşiği
      (width: 412, height: 915, scale: 1.0), // etiketli hap, yaygın telefon
      (width: 412, height: 915, scale: 1.5),
      (width: 820, height: 1180, scale: 1.0),
    ];
    // Ana sayfa için gereken en dar genişlik (dp): 96 + sağdaki eylemler + 2.
    //   çift modlu + tema: 96 + (3x48 + 48 + 52 + 6) + 2 = 348; çift modlu, temasız: 300; hapsız + tema: 296.
    final cases = <({String label, UserRole role, bool theme, bool pill, double minWidth})>[
      (label: 'çift modlu yönetici + tema düğmesi', role: UserRole.siteManager, theme: true, pill: true, minWidth: 348),
      (label: 'çift modlu yönetici, tema düğmesi yok', role: UserRole.siteManager, theme: false, pill: true, minWidth: 300),
      (label: 'bireysel kullanıcı + tema düğmesi (hapsız)', role: UserRole.individual, theme: true, pill: false, minWidth: 296),
    ];
    for (final k in cases) {
      for (final c in cells) {
        for (final dark in const <bool>[false, true]) {
          // Koyu temayı yalnız ilk hesap türünde tüm hücrelerde, öbürlerinde en dar ve en geniş hücrede dene.
          if (dark && k != cases.first && c != cells.first && c != cells.last) continue;
          testWidgets('${k.label}: ${c.width.toInt()}x${c.height.toInt()} x${c.scale} ${dark ? 'koyu' : 'açık'}', (t) async {
            final auth = _ShortcutAuth(k.role);
            final access = await _access(k.role == UserRole.individual ? const <MySiteModules>[] : <MySiteModules>[_my('manager')]);
            await _pumpHome(t, auth, access: access, width: c.width, height: c.height, scale: c.scale, dark: dark, themeToggle: k.theme);
            await _openProfile(t);
            expect(t.takeException(), isNull);
            final homeShown = c.width >= k.minWidth;
            expect(_home, homeShown ? findsOneWidget : findsNothing, reason: 'Ana sayfa ${homeShown ? 'sığar' : 'sığmaz'}');

            // Soldan sağa: menü, [Ana sayfa], [hap], [tema], yenile, çıkış, dişli. Hiçbiri öbürüne binmez, hepsi ekranın içinde.
            // Hap: 400 dp altında, 1,3x üstü yazıda ve Ana sayfa varken 480 dp altında yalnız ikon (Tooltip), değilse etiketli.
            final pillFinder = c.width < 400 || c.scale > 1.3 || (homeShown && c.width < 480)
                ? _inAppBar(find.byTooltip('Sakin Modu'))
                : find.ancestor(of: _inAppBar(find.text('Sakin Modu')), matching: find.byType(InkWell)).first;
            final ordered = <(String, Finder)>[
              ('menü', _inAppBar(find.byType(DrawerButton))),
              if (homeShown) ('Ana sayfa', _home),
              if (k.pill) ('hap', pillFinder),
              if (k.theme) ('tema', _inAppBar(find.widgetWithIcon(IconButton, dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded))),
              ('yenile', _inAppBar(find.widgetWithIcon(IconButton, Icons.refresh_rounded))),
              ('çıkış', _inAppBar(find.widgetWithIcon(IconButton, Icons.logout_rounded))),
              ('dişli', _inAppBar(find.widgetWithIcon(IconButton, Icons.settings_rounded))),
            ];
            Rect? previous;
            String? previousName;
            for (final (name, finder) in ordered) {
              expect(finder, findsOneWidget, reason: name);
              final r = t.getRect(finder);
              expect(r.height, greaterThanOrEqualTo(44), reason: '$name yükseklik');
              expect(r.width, greaterThanOrEqualTo(44), reason: '$name genişlik');
              expect(r.left, greaterThanOrEqualTo(-0.01), reason: '$name ekranın içinde (sol)');
              expect(r.right, lessThanOrEqualTo(c.width + 0.01), reason: '$name ekranın içinde (sağ)');
              if (previous != null) {
                expect(r.left, greaterThanOrEqualTo(previous.right - 0.01), reason: '$name, $previousName düğmesine binmez');
              }
              previous = r;
              previousName = name;
            }

            // Yükseklik sözleşmesi değişmedi: araç çubuğu 56 dp + yazı ölçeğiyle büyüyen alt başlık bloğu.
            final scaler = TextScaler.linear(c.scale);
            final bottom = 16 + 1.2 * (scaler.scale(18) + scaler.scale(12));
            expect(t.getRect(find.byType(AppBar)).height, closeTo(kToolbarHeight + bottom, 0.01));
            expect(t.getRect(_inAppBar(find.byType(NavigationToolbar))).height, closeTo(kToolbarHeight, 0.01));
            await _disposeHome(t);
          });
        }
      }
    }

    testWidgets('Ana sayfa varken hap 480 dp altında yalnız ikon ("Sakin Mo…" diye kesilmez), 480 dp ve üstünde etiketli; Panel\'de eskisi gibi',
        (t) async {
      for (final (w, labeledInner) in const <(double, bool)>[(412, false), (479, false), (480, true), (820, true)]) {
        final auth = _ShortcutAuth(UserRole.siteManager);
        final access = await _access(<MySiteModules>[_my('manager')]);
        await _pumpHome(t, auth, access: access, width: w, height: 915, themeToggle: true);
        // Panel (Ana sayfa yok): etiketli hap eşiği değişmedi (>= 400 dp).
        expect(_inAppBar(find.text('Sakin Modu')), findsOneWidget, reason: 'Panel ${w.toInt()} dp: etiketli');
        await _openProfile(t);
        expect(_inAppBar(find.text('Sakin Modu')), labeledInner ? findsOneWidget : findsNothing, reason: 'iç ekran ${w.toInt()} dp');
        expect(_inAppBar(find.byTooltip('Sakin Modu')), labeledInner ? findsNothing : findsOneWidget, reason: 'iç ekran ${w.toInt()} dp');
        expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
        // Hap iki durumda da çalışır: dokununca mod değişir (Sakin Modu -> Yönetici Paneli).
        await t.tap(labeledInner ? _inAppBar(find.text('Sakin Modu')) : _inAppBar(find.byTooltip('Sakin Modu')));
        await _settle(t, 600);
        final switched = _inAppBar(find.byTooltip('Yönetici Paneli')).evaluate().isNotEmpty ||
            _inAppBar(find.text('Yönetici Paneli')).evaluate().isNotEmpty;
        expect(switched, isTrue, reason: '${w.toInt()} dp: mod değişti');
        await _disposeHome(t);
      }
    });
  });

  group('derin (itilmiş) ekranlar: HomeShortcutButton Panel\'e döndürür', () {
    /// HomePage'in üstüne [depth] kadar iç içe sayfa iter; her sayfanın üst çubuğunda HomeShortcutButton vardır.
    Future<void> pushDeep(WidgetTester t, int depth) async {
      Route<void> route(int level) => MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text('Derin $level'), actions: const <Widget>[HomeShortcutButton()]),
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(route(level + 1)),
                  child: Text('Daha derin $level'),
                ),
              ),
            ),
          );
      unawaited(Navigator.of(t.element(find.byType(HomePage))).push(route(1)));
      await _settle(t);
      for (var level = 1; level < depth; level++) {
        await t.tap(find.text('Daha derin $level'));
        await _settle(t);
      }
    }

    final deepHome = find.descendant(of: find.byType(AppBar).last, matching: find.byType(HomeShortcutButton));

    testWidgets('üç sayfa derinde tek dokunuşla ana kabuğa dönülür ve Panel seçilir; kapı açılmaz', (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openProfile(t);
      await pushDeep(t, 3);
      expect(find.text('Derin 3'), findsOneWidget);
      expect(deepHome, findsOneWidget);
      expect(t.getRect(deepHome).height, greaterThanOrEqualTo(44));
      expect(t.getRect(deepHome).width, greaterThanOrEqualTo(44));

      await t.tap(deepHome);
      await _settle(t);
      expect(find.textContaining('Derin'), findsNothing, reason: 'açık ekranların hepsi kapandı');
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'ana kabukta Panel seçildi');
      expect(_inAppBar(find.text('Panel')), findsOneWidget);
      expect(auth.openDoorCalls, 0);
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });

    testWidgets('gerçek derin ekran (Banka Ödemeleri ve Daire Onayları): üst çubukta düğme var; dokununca ana kabukta Panel açılır',
        (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager);
      BankImportService.register(auth, BankImportService(authService: auth, api: _EmptyBankApi()));
      final access = await _access(<MySiteModules>[_my('manager', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);
      await _openProfile(t);
      unawaited(
        Navigator.of(t.element(find.byType(HomePage))).push(
          MaterialPageRoute<void>(builder: (_) => BankLinesView(scope: PeopleScope(authService: auth, siteCode: 1))),
        ),
      );
      await _settle(t);
      expect(find.byType(BankLinesView), findsOneWidget);
      expect(find.text('Banka Ödemeleri ve Daire Onayları'), findsOneWidget);
      expect(deepHome, findsOneWidget, reason: 'gerçek ekranın üst çubuğunda Ana sayfa düğmesi');
      expect(find.byTooltip('Ana sayfa'), findsOneWidget);

      await t.tap(deepHome);
      await _settle(t);
      expect(find.byType(BankLinesView), findsNothing, reason: 'ekran kapandı');
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'Profilim değil, Panel');
      expect(find.byType(ProfileView), findsNothing);
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });

    testWidgets('derin ekranda geri (üst çubuk oku) hâlâ bir adım geri gider; Ana sayfa yalnız ek yoldur', (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openProfile(t);
      await pushDeep(t, 2);
      expect(find.text('Derin 2'), findsOneWidget);
      await t.tap(find.byType(BackButton).last);
      await _settle(t);
      expect(find.text('Derin 1'), findsOneWidget, reason: 'geri bir adım geri götürür');
      expect(find.text('Derin 2'), findsNothing);
      await t.tap(find.byType(BackButton).last);
      await _settle(t);
      expect(find.byType(ProfileView), findsOneWidget, reason: 'ana kabukta bulunulan sayfa korunur');
      await _disposeHome(t);
    });

    testWidgets('kabuk kapanınca dinleyici temizlenir; kabuk yokken gelen istek zararsızdır', (t) async {
      final auth = _ShortcutAuth(UserRole.siteManager);
      final access = await _access(<MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      // ignore: invalid_use_of_protected_member
      expect(PanelReturnRequests.instance.hasListeners, isTrue, reason: 'kabuk dinler');
      await _disposeHome(t);
      // ignore: invalid_use_of_protected_member
      expect(PanelReturnRequests.instance.hasListeners, isFalse, reason: 'kabuk kapanınca dinleyici kalkar');
      PanelReturnRequests.instance.request();
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  group('kaynak sözleşmesi: derin ekranlar ve yardım', () {
    // Dosya içeriği CRLF ya da LF olabilir (Windows çalışma ağacı); desenler satır sonundan bağımsızdır.
    String source(String path) => File(path).readAsStringSync();

    test('derin finans ekranlarının (banka dosyası / banka satırları) üst çubuğunda HomeShortcutButton var', () {
      for (final path in const <String>[
        'lib/ui/views/bank_import_view.dart',
        'lib/ui/views/bank_lines_view.dart',
      ]) {
        final text = source(path);
        expect(text, contains("package:site_kapi_kontrol/ui/widgets/home_shortcut_button.dart"), reason: path);
        expect(RegExp(r'appBar:\s*AppBar\([\s\S]*?actions:\s*const\s*<Widget>\[\s*HomeShortcutButton\(\)\s*\]').hasMatch(text), isTrue,
            reason: '$path: AppBar actions içinde HomeShortcutButton');
      }
    });

    test('İşletme Projesi ayrıntısı form taşır: düğme kendi onayını verir (varsayılan HomeShortcutButton() değil)', () {
      final text = source('lib/ui/views/budget_view.dart');
      expect(text, contains("package:site_kapi_kontrol/ui/widgets/home_shortcut_button.dart"));
      expect(text, contains('HomeShortcutButton(onPressed: () => unawaited(_goHome()))'));
      expect(text, isNot(contains('HomeShortcutButton()')),
          reason: 'varsayılan düğme popUntil ile yazılmış kalem tutarını sormadan atardı (docs/TASARIM_DILI.md)');
      expect(text, contains('Future<void> _goHome() async'));
      expect(text, contains('_hasUnsavedAmounts'));
    });

    test('yardım: her grubun "navigation" konusu “Ana sayfa” düğmesini anlatır', () {
      for (final audience in HelpAudience.values) {
        final topic = HelpContent.howToFor(audience).firstWhere((t) => t.id == 'navigation');
        final text = <String>[topic.title, ...topic.steps, if (topic.note != null) topic.note!].join('\n');
        expect(text, contains('“Ana sayfa” düğmesi'), reason: '$audience');
        expect(text, contains('“Panel”'), reason: '$audience');
      }
      // Sakin: düğme alt çubuk YOKKEN çıkar, çubuk varken işi "Özet" sekmesi görür; metin ikisini de söyler.
      final resident = HelpContent.howToFor(HelpAudience.resident).firstWhere((t) => t.id == 'navigation').steps.join('\n');
      expect(resident, contains('Alt çubuk görünmediğinde'));
      expect(resident, contains('“Özet” sekmesi'));
    });

    test('kaydedilmemiş veri koruması (PopScope) olan ekranlara Ana sayfa düğmesi konmaz (popUntil korumayı atlar)', () {
      // Toplu yükleme sihirbazının kendi geri koruması vardır; HomeShortcutButton onu atlardı.
      expect(source('lib/ui/views/bulk_import_view.dart'), isNot(contains('HomeShortcutButton')));
    });
  });
}
