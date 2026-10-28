// İP-1D (G2 + G3): ana kabukta yeni gezinme.
//
// - Gruplu çekmece: başlıklar yalnız dolu gruplar; Ayarlar öğeleri çekmecede DEĞİL, sağ üstteki dişliden açılan
//   "Ayarlar" panelinde (dişlide panelin rozet toplamı); "Masaüstüne Widget Ekle" panelde.
// - Site seçici çekmecenin en üstünde: çok siteli yöneticide site seçilince menü ve vitrin o siteye daralır.
// - Sakin alt çubuğu (Material 3 NavigationBar): sekmeler görünür öğelerden türer (rol × modül × kapı yetkisi);
//   yönetici / süper / bireyselde yok; sekmeye dokunma = çekmeceden seçme; geri tuşu sekmeden Özet'e, Özet'ten çıkış.
// - Dışarıdan "Kapılar sayfasını aç" isteği (Android widget'ı): modül verisi gelene dek BEKLER (veri gelmeden Kapılar
//   bir kare bile açılmaz); veri kapıya izin verirse Kapı sekmesi seçilir.
// - Taşma yok: 320x640 x2,0 (alt çubuklu sakin, Ayarlar paneli) ve 1366x768.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
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
import 'package:site_kapi_kontrol/services/door_panel_requests.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/resident_tabs.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
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

/// HomePage sahte servisi: siteler / kapılar sabit, kapı komutları sayılır (yeni gezinme hiçbir yerde kapı açmamalı).
class _NavAuth extends AuthService {
  _NavAuth(this.role, {List<DoorRecord>? doors, List<SiteRecord>? sites})
      : doors = doors ?? (role == UserRole.apartmentOwner || role == UserRole.individual ? <DoorRecord>[_door(1)] : <DoorRecord>[]),
        sites = sites ?? <SiteRecord>[_siteRecord(1, 'Güneş Sitesi')],
        super(api: AuthApi(baseUrl: 'http://localhost'));

  UserRole role;
  List<DoorRecord> doors;
  List<SiteRecord> sites;
  int openDoorCalls = 0;

  /// Oturumdaki rol sunucuda değişti (örn. yöneticilik kaldırıldı): HomePage'in oturum dinleyicisi uyarılır.
  void changeRole(UserRole next) {
    role = next;
    notifyListeners();
  }

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
      SitePage(sites: sites, total: sites.length, page: 1, pageSize: 100);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async => (
        SiteStructureRecord(
          site: sites.firstWhere((s) => s.id == siteCode, orElse: () => sites.first),
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

  @override
  Future<MyFinance> getMyFinance() async => const MyFinance(items: <MyFinanceApartment>[]);
}

MySiteModules _my(
  String role, {
  int site = 1,
  String? name,
  Map<String, bool> modules = const <String, bool>{},
  bool door = true,
  bool? doorAccess,
}) =>
    MySiteModules(
      siteCode: site,
      siteName: name ?? (site == 1 ? 'Güneş Sitesi' : 'Ay Sitesi'),
      role: role,
      modules: <String, bool>{'door_control': door, ...modules},
      doorAccess: doorAccess ?? !(role == 'staff' || role == 'board_member'),
    );

Future<ModuleAccess> _access(
  List<MySiteModules> Function() sites, {
  bool superUser = false,
  int pendingModules = 0,
  int pendingApplications = 0,
}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
    isSuperUser: () => superUser,
    fetchPendingCount: superUser ? () async => pendingModules : null,
    fetchPendingApplicationCount: superUser ? () async => pendingApplications : null,
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
  _NavAuth auth, {
  ModuleAccess? access,
  DoorPanelRequests? requests,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
  bool settle = true,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier();
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HomePage(
        authService: auth,
        moduleAccess: access,
        announcementNotifier: notifier,
        doorPanelRequests: requests,
      ),
    ),
  );
  if (!settle) return;
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);
final Finder _gear = _inAppBar(find.byTooltip('Ayarlar'));
final Finder _bar = find.byKey(const ValueKey<String>('sakin_alt_cubuk'));
Finder _tab(ResidentTab tab) => find.byKey(ValueKey<String>('sakin_sekme_${tab.name}'));
Finder _drawerTile(SirketMenuItem item) =>
    find.descendant(of: find.byType(YanMenu), matching: find.byKey(ValueKey<SirketMenuItem>(item)));
Finder _settingsTile(SirketMenuItem item) =>
    find.descendant(of: find.byType(YanMenuAyarlar), matching: find.byKey(ValueKey<SirketMenuItem>(item)));

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _openSettings(WidgetTester t) async {
  await t.tap(_gear);
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Android geri tuşu; dönüş: olay karşılandı mı (false = uygulamadan çıkılır).
Future<bool> _back(WidgetTester t) async {
  final handled = await t.binding.handlePopRoute();
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
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

List<ResidentTab> _tabsOnScreen() => <ResidentTab>[
      for (final tab in ResidentTab.values)
        if (_tab(tab).evaluate().isNotEmpty) tab,
    ];

ResidentTab _selectedTab(WidgetTester t) {
  final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
  return _tabsOnScreen()[bar.selectedIndex];
}

void main() {
  group('dişli: Ayarlar paneli', () {
    testWidgets('site yöneticisi: dişli en sağda; ayar öğeleri panelde, çekmecede değil; Profilim panelden açılır',
        (t) async {
      final auth = _NavAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);

      expect(_gear, findsOneWidget);
      final gear = t.getRect(_gear);
      expect(gear.width, greaterThanOrEqualTo(44));
      expect(gear.height, greaterThanOrEqualTo(44));
      for (final tooltip in <String>['Yenile', 'Çıkış Yap']) {
        expect(t.getRect(_inAppBar(find.byTooltip(tooltip))).right, lessThanOrEqualTo(gear.left + 0.01),
            reason: 'dişli sağ üstte (en sağda)');
      }

      await _openDrawer(t);
      for (final item in <SirketMenuItem>[SirketMenuItem.profilim, SirketMenuItem.moduller, SirketMenuItem.kayitliCihazlar]) {
        expect(_drawerTile(item), findsNothing, reason: '${item.name} çekmecede değil');
      }
      expect(_drawerTile(SirketMenuItem.finans), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('yan_menu_grup_borclar')), findsOneWidget);
      Navigator.of(t.element(find.byType(YanMenu))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));

      await _openSettings(t);
      expect(find.byType(YanMenuAyarlar), findsOneWidget);
      for (final item in <SirketMenuItem>[
        SirketMenuItem.profilim,
        SirketMenuItem.moduller,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ]) {
        expect(_settingsTile(item), findsOneWidget, reason: '${item.name} Ayarlar panelinde');
      }
      await t.tap(_settingsTile(SirketMenuItem.profilim));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(YanMenuAyarlar), findsNothing, reason: 'panel kapandı');
      expect(_inAppBar(find.text('Profilim')), findsOneWidget);
      expect(find.byType(ProfileView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: bekleyen sayılar dişlide rozet (toplam) ve panelde öğe başına', (t) async {
      final handle = t.ensureSemantics();
      final auth = _NavAuth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true, pendingModules: 3, pendingApplications: 1);
      await _pumpHome(t, auth, access: access);
      final badge = find.descendant(of: find.byType(AppBar), matching: find.byKey(const ValueKey<String>('ayarlar_rozet')));
      expect(find.descendant(of: badge, matching: find.text('4')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('4 bekleyen')), findsOneWidget);
      await _openSettings(t);
      String? countOf(SirketMenuItem item) {
        final f = find.descendant(of: _settingsTile(item), matching: find.byKey(const ValueKey<String>('yan_menu_rozet')));
        if (f.evaluate().isEmpty) return null;
        return t.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data;
      }

      expect(countOf(SirketMenuItem.modulTalepleri), '3');
      expect(countOf(SirketMenuItem.siteBasvurulari), '1');
      handle.dispose();
      await _disposeHome(t);
    });

    testWidgets('bekleyen yoksa dişlide rozet yok', (t) async {
      final auth = _NavAuth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('ayarlar_rozet')), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('"Masaüstüne Widget Ekle" AppBar\'da değil, Ayarlar panelinde (mobil, süper olmayan)', (t) async {
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      expect(_inAppBar(find.byTooltip('Masaüstüne Widget Ekle')), findsNothing);
      await _openSettings(t);
      expect(
        find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Masaüstüne Widget Ekle')),
        findsOneWidget,
      );
      await _disposeHome(t);
    });

    testWidgets('panel açıkken geri tuşu önce paneli kapatır, sayfa değişmez', (t) async {
      final calls = _capturePlatform(t);
      final auth = _NavAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openSettings(t);
      expect(await _back(t), isTrue);
      expect(find.byType(YanMenuAyarlar), findsNothing);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(calls, isNot(contains('SystemNavigator.pop')));
      await _disposeHome(t);
    });
  });

  group('çekmece başlıkları: rol × modül × kapı yetkisi matrisi (öğesi olmayan başlık görünmez)', () {
    List<SirketMenuGroup> headersOnScreen() => <SirketMenuGroup>[
          for (final group in SirketMenuGroup.values)
            if (find.byKey(ValueKey<String>('yan_menu_grup_${group.name}')).evaluate().isNotEmpty) group,
        ];

    const a = SirketMenuGroup.anaSayfa;
    const d = SirketMenuGroup.daireler;
    const b = SirketMenuGroup.borclar;
    const i = SirketMenuGroup.iletisim;
    // "Yeni Site Oluştur" her rolde Site hizmetleri başlığındadır: kapı / modül kapalı olsa da başlık görünür.
    const h = SirketMenuGroup.siteHizmetleri;

    final cases = <(String, UserRole, List<MySiteModules> Function(), bool, List<DoorRecord>?, List<SirketMenuGroup>)>[
      ('süper kullanıcı', UserRole.superUser, () => const <MySiteModules>[], true, null, <SirketMenuGroup>[a, d, b, i, h]),
      ('site yöneticisi, yalnız çekirdek modüller', UserRole.siteManager, () => <MySiteModules>[_my('manager')], false, null,
          <SirketMenuGroup>[a, d, i, h]),
      ('site yöneticisi, Finans açık', UserRole.siteManager, () => <MySiteModules>[_my('manager', modules: {'finance': true})],
          false, null, <SirketMenuGroup>[a, d, b, i, h]),
      ('site yöneticisi, Geçiş Kontrol kapalı ve modül yok', UserRole.siteManager,
          () => <MySiteModules>[_my('manager', door: false)], false, null, <SirketMenuGroup>[a, d, i, h]),
      ('daire sakini, kapı + Finans + Belgeler + İş Takibi', UserRole.apartmentOwner,
          () => <MySiteModules>[_my('resident', modules: {'finance': true, 'drive_storage': true, 'work_tracking': true})], false,
          null, <SirketMenuGroup>[a, d, b, i, h]),
      ('daire sakini, Geçiş Kontrol kapalı, modül yok', UserRole.apartmentOwner,
          () => <MySiteModules>[_my('resident', door: false)], false, null, <SirketMenuGroup>[a, d, i, h]),
      ('yalnız görevli bağı (kapısız), İş Takibi açık', UserRole.apartmentOwner,
          () => <MySiteModules>[_my('staff', modules: {'work_tracking': true})], false, const <DoorRecord>[],
          <SirketMenuGroup>[a, d, i, h]),
      ('bireysel kullanıcı', UserRole.individual, () => const <MySiteModules>[], false, null, <SirketMenuGroup>[a, d, h]),
    ];
    for (final (label, role, sites, superUser, doors, expected) in cases) {
      testWidgets(label, (t) async {
        final auth = _NavAuth(role, doors: doors);
        final access = await _access(sites, superUser: superUser);
        await _pumpHome(t, auth, access: access, height: 1600);
        await _openDrawer(t);
        expect(headersOnScreen(), expected, reason: label);
        expect(headersOnScreen(), isNot(contains(SirketMenuGroup.ayarlar)), reason: 'Ayarlar çekmece başlığı değil');
        for (final empty in const <SirketMenuGroup>[SirketMenuGroup.tahsilat, SirketMenuGroup.giderler, SirketMenuGroup.raporlar]) {
          expect(headersOnScreen(), isNot(contains(empty)), reason: '${empty.title}: bugün öğesi yok');
        }
        await _disposeHome(t);
      });
    }
  });

  group('sakin alt çubuğu: rol × modül × kapı yetkisi matrisi', () {
    final cases = <(String, UserRole, List<MySiteModules> Function(), List<DoorRecord>?, List<ResidentTab>)>[
      (
        'daire sakini, kapı + İş Takibi + Belgeler açık: beş sekme',
        UserRole.apartmentOwner,
        () => <MySiteModules>[_my('resident', modules: {'work_tracking': true, 'drive_storage': true})],
        null,
        ResidentTab.values,
      ),
      (
        'daire sakini, Geçiş Kontrol kapalı: Kapı yok (PDF\'teki dört sekme)',
        UserRole.apartmentOwner,
        () => <MySiteModules>[_my('resident', door: false, modules: {'work_tracking': true, 'drive_storage': true})],
        null,
        <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.ariza, ResidentTab.belgeler],
      ),
      (
        'daire sakini, İş Takibi ve Belgeler kapalı: Özet, Duyuru, Kapı',
        UserRole.apartmentOwner,
        () => <MySiteModules>[_my('resident')],
        null,
        <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.kapi],
      ),
      (
        'dairesiz kurul üyesi (kapı yetkisi yok), Belgeler açık: Kapı yok',
        UserRole.apartmentOwner,
        () => <MySiteModules>[_my('board_member', modules: {'drive_storage': true})],
        const <DoorRecord>[],
        <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.belgeler],
      ),
    ];
    for (final (label, role, sites, doors, expected) in cases) {
      testWidgets(label, (t) async {
        final auth = _NavAuth(role, doors: doors);
        final access = await _access(sites);
        await _pumpHome(t, auth, access: access);
        expect(_bar, findsOneWidget);
        expect(_tabsOnScreen(), expected);
        expect(_selectedTab(t), ResidentTab.ozet, reason: 'uygulama Özet\'te (Panel vitrini) açılır');
        expect(find.byType(ModuleShowcaseView), findsOneWidget);
        await _disposeHome(t);
      });
    }

    testWidgets('kısa pencere (yatay telefon, < 480 dp): alt çubuk yok, gezinme çekmeceyle; 480 dp\'de var', (t) async {
      for (final (w, h, bar) in const <(double, double, bool)>[(640, 360, false), (800, 479, false), (800, 480, true)]) {
        final auth = _NavAuth(UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my('resident', modules: {'drive_storage': true})]);
        await _pumpHome(t, auth, access: access, width: w, height: h, scale: 2.0);
        expect(_bar, bar ? findsOneWidget : findsNothing, reason: '${w.toInt()}x${h.toInt()}');
        expect(t.takeException(), isNull);
        await _disposeHome(t);
      }
      expect(HomePage.residentBarMinHeight, 480);
    });

    testWidgets('yalnız görevli bağı: tek sekme kalır, çubuk yok', (t) async {
      final auth = _NavAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      final access = await _access(() => <MySiteModules>[_my('staff', modules: {'work_tracking': true})]);
      await _pumpHome(t, auth, access: access);
      expect(_bar, findsNothing);
      await _disposeHome(t);
    });

    // Kapı sekmesi menüdeki "Kapılar"dan ayrıca kapı yetkisinin OLUMLU kanıtını ister: modül verisi alınamadığında
    // (fail-open) "Kapılar" menüde kalır, ama kapı listesi de boşsa Kapı sekmesi çizilmez.
    testWidgets('modül verisi alınamadı (fail-open), kapı listesi boş: Kapılar menüde olsa da Kapı sekmesi yok', (t) async {
      final access = ModuleAccess(fetch: () async => throw StateError('ağ yok'));
      addTearDown(access.dispose);
      await access.refresh();
      final auth = _NavAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      await _pumpHome(t, auth, access: access);
      expect(_bar, findsNothing, reason: 'kapı yetkisinin olumlu kanıtı yok: yalnız Özet kalır, çubuk çizilmez');
      await _openDrawer(t);
      expect(_drawerTile(SirketMenuItem.kapilar), findsOneWidget, reason: 'fail-open: Kapılar öğesi menüde kalır');
      await _disposeHome(t);
    });

    testWidgets('modül verisi alınamadı ama kapı listesi geldi: Kapı sekmesi kapı listesinden (olumlu kanıt)', (t) async {
      final access = ModuleAccess(fetch: () async => throw StateError('ağ yok'));
      addTearDown(access.dispose);
      await access.refresh();
      final auth = _NavAuth(UserRole.apartmentOwner);
      await _pumpHome(t, auth, access: access);
      expect(_bar, findsOneWidget);
      expect(_tabsOnScreen(), <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.kapi]);
      await _disposeHome(t);
    });

    for (final (label, role, superUser) in <(String, UserRole, bool)>[
      ('site yöneticisi (yönetici modu)', UserRole.siteManager, false),
      ('süper kullanıcı', UserRole.superUser, true),
      ('bireysel', UserRole.individual, false),
    ]) {
      testWidgets('$label: alt çubuk yok', (t) async {
        final auth = _NavAuth(role);
        final access = await _access(
          () => role == UserRole.siteManager ? <MySiteModules>[_my('manager')] : const <MySiteModules>[],
          superUser: superUser,
        );
        await _pumpHome(t, auth, access: access);
        expect(_bar, findsNothing);
        await _disposeHome(t);
      });
    }

    testWidgets('sakin modundaki yönetici: alt çubuk gelir; yönetici paneline dönünce kalkar', (t) async {
      final auth = _NavAuth(UserRole.siteManager, doors: <DoorRecord>[_door(1)]);
      final access = await _access(() => <MySiteModules>[_my('manager', modules: {'drive_storage': true})]);
      await _pumpHome(t, auth, access: access, width: 820, height: 1180);
      expect(_bar, findsNothing);
      await t.tap(_inAppBar(find.text('Sakin Modu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_bar, findsOneWidget);
      expect(_tabsOnScreen(), containsAll(<ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru]));
      await t.tap(_inAppBar(find.text('Yönetici Paneli')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_bar, findsNothing);
      await _disposeHome(t);
    });
  });

  group('sekmeler: gezinme ve geri tuşu', () {
    testWidgets('sekmeye dokunma o sayfayı açar; geri: sekmeden Özet\'e, Özet\'ten uygulamadan çıkış', (t) async {
      final calls = _capturePlatform(t);
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'work_tracking': true, 'drive_storage': true})]);
      await _pumpHome(t, auth, access: access);

      for (final (tab, title) in <(ResidentTab, String)>[
        (ResidentTab.duyuru, 'Duyurular'),
        (ResidentTab.ariza, 'Taleplerim'),
        (ResidentTab.belgeler, 'Dosya Deposu'),
        (ResidentTab.kapi, 'Kapılar'),
      ]) {
        await t.tap(_tab(tab));
        await t.pump();
        await t.pump(const Duration(milliseconds: 700));
        expect(_inAppBar(find.text(title)), findsOneWidget, reason: tab.label);
        expect(_selectedTab(t), tab);
        expect(await _back(t), isTrue, reason: '${tab.label}: geri uygulamadan çıkmaz');
        expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: '${tab.label}: geri Özet\'e döner');
        expect(_selectedTab(t), ResidentTab.ozet);
      }
      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(await _back(t), isFalse, reason: 'Özet\'te geri uygulamadan çıkar (bugünkü kural)');
      expect(calls, contains('SystemNavigator.pop'));
      expect(auth.openDoorCalls, 0, reason: 'Kapı sekmesi kapıyı açmaz, sayfayı açar');
      await _disposeHome(t);
    });

    testWidgets('sekme olmayan sayfa (Borcum) Özet altında; Özet sekmesi vitrine döndürür', (t) async {
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);
      final card = find.byKey(const ValueKey<String>('panel_kart_borcum'));
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Borcum')), findsOneWidget);
      expect(_selectedTab(t), ResidentTab.ozet);
      await t.tap(_tab(ResidentTab.ozet));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('çekmeceden seçilen sekme sayfası çubukta da seçili görünür', (t) async {
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'drive_storage': true})]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      await t.tap(_drawerTile(SirketMenuItem.belgeler));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_selectedTab(t), ResidentTab.belgeler);
      await _disposeHome(t);
    });

    testWidgets('modül sonradan kapanınca sekme kalkar; o sekmedeyken Özet\'e düşülür', (t) async {
      var documents = true;
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'drive_storage': documents})]);
      await _pumpHome(t, auth, access: access);
      await t.tap(_tab(ResidentTab.belgeler));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_selectedTab(t), ResidentTab.belgeler);
      documents = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_tab(ResidentTab.belgeler), findsNothing, reason: 'fail-closed: kapalı modülün sekmesi yok');
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_selectedTab(t), ResidentTab.ozet);
      await _disposeHome(t);
    });
  });

  group('Android widget / kısayol: "Kapılar sayfasını aç" isteği', () {
    testWidgets('modül verisi gelmeden karar verilmez: Kapılar bir kare bile açılmaz; veri izin verince Kapı sekmesi',
        (t) async {
      final gate = Completer<MyModulesResult>();
      final access = ModuleAccess(fetch: () => gate.future);
      addTearDown(access.dispose);
      final requests = DoorPanelRequests()..request();
      addTearDown(requests.dispose);
      final auth = _NavAuth(UserRole.apartmentOwner);
      await _pumpHome(t, auth, access: access, requests: requests, settle: false);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(DashboardView), findsNothing, reason: 'veri yokken Kapılar açılmaz (kare $i)');
      }
      expect(requests.isPending, isTrue, reason: 'istek tüketilmedi, bekliyor');

      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('resident')]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(DashboardView), findsOneWidget);
      expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
      expect(_selectedTab(t), ResidentTab.kapi, reason: 'derin bağlantı Kapı sekmesini seçer');
      expect(requests.isPending, isFalse);
      expect(auth.openDoorCalls, 0, reason: 'istek kapı AÇMAZ');
      await _disposeHome(t);
    });

    testWidgets('veri kapıya izin vermezse (yalnız kurul bağı) vitrinde kalınır; arada Kapılar görünmez', (t) async {
      final gate = Completer<MyModulesResult>();
      final access = ModuleAccess(fetch: () => gate.future);
      addTearDown(access.dispose);
      final requests = DoorPanelRequests()..request();
      addTearDown(requests.dispose);
      final auth = _NavAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      await _pumpHome(t, auth, access: access, requests: requests, settle: false);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(DashboardView), findsNothing);
        expect(_inAppBar(find.text('Kapılar')), findsNothing);
      }
      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('board_member', doorAccess: false)]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(DashboardView), findsNothing);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(requests.isPending, isFalse, reason: 'istek tüketildi');
      await _disposeHome(t);
    });

    testWidgets('beklerken kullanıcı kendisi başka sayfa açarsa istek düşer: veri gelince sayfa değişmez', (t) async {
      final gate = Completer<MyModulesResult>();
      final access = ModuleAccess(fetch: () => gate.future);
      addTearDown(access.dispose);
      final requests = DoorPanelRequests()..request();
      addTearDown(requests.dispose);
      final auth = _NavAuth(UserRole.apartmentOwner);
      await _pumpHome(t, auth, access: access, requests: requests);
      expect(requests.isPending, isTrue);
      await _openSettings(t);
      await t.tap(_settingsTile(SirketMenuItem.profilim));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_inAppBar(find.text('Profilim')), findsOneWidget);
      expect(requests.isPending, isFalse, reason: 'kullanıcının seçimi bekleyen kapı isteğini düşürür');

      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('resident')]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Profilim')), findsOneWidget, reason: 'geç gelen veri sayfayı Kapılar\'a çevirmez');
      expect(find.byType(DashboardView), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('beklerken mod geçişi (AppBar\'daki "Sakin Modu") de kullanıcının seçimidir: istek düşer, Kapılar açılmaz',
        (t) async {
      final gate = Completer<MyModulesResult>();
      final access = ModuleAccess(fetch: () => gate.future);
      addTearDown(access.dispose);
      final requests = DoorPanelRequests()..request();
      addTearDown(requests.dispose);
      final auth = _NavAuth(UserRole.siteManager, doors: <DoorRecord>[_door(1)]);
      await _pumpHome(t, auth, access: access, requests: requests, width: 820, height: 1180);
      expect(requests.isPending, isTrue);
      await t.tap(_inAppBar(find.text('Sakin Modu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(requests.isPending, isFalse, reason: 'mod geçişi bekleyen kapı isteğini düşürür');

      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('manager')]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Kapılar')), findsNothing, reason: 'geç gelen veri sayfayı Kapılar\'a çevirmez');
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('ilk yükleme hata verirse (fail-open) istek uygulanır: Kapılar açılır', (t) async {
      final access = ModuleAccess(fetch: () async => throw StateError('ağ yok'));
      addTearDown(access.dispose);
      final requests = DoorPanelRequests()..request();
      addTearDown(requests.dispose);
      final auth = _NavAuth(UserRole.apartmentOwner);
      await _pumpHome(t, auth, access: access, requests: requests);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(DashboardView), findsOneWidget);
      expect(requests.isPending, isFalse);
      await _disposeHome(t);
    });

    testWidgets('uygulama açıkken gelen istek Kapı sekmesini seçer', (t) async {
      final requests = DoorPanelRequests();
      addTearDown(requests.dispose);
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'drive_storage': true})]);
      await _pumpHome(t, auth, access: access, requests: requests);
      await t.tap(_tab(ResidentTab.belgeler));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      requests.request();
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_selectedTab(t), ResidentTab.kapi);
      expect(find.byType(DashboardView), findsOneWidget);
      expect(await _back(t), isTrue);
      expect(_selectedTab(t), ResidentTab.ozet, reason: 'Kapı sekmesinden geri Özet\'e');
      await _disposeHome(t);
    });
  });

  group('site seçici (çekmecenin en üstü)', () {
    final siteRow = find.byKey(const ValueKey<String>('yan_menu_site'));
    final twoSites = <SiteRecord>[_siteRecord(1, 'Güneş Sitesi'), _siteRecord(2, 'Ay Sitesi')];

    List<MySiteModules> managerSites() => <MySiteModules>[
          _my('manager', site: 1, modules: {'finance': true}),
          _my('manager', site: 2, modules: {'drive_storage': true}),
        ];

    Future<void> pick(WidgetTester t, String key) async {
      await t.tap(siteRow);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await t.tap(find.byKey(ValueKey<String>('yan_menu_site_secenek_$key')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('çok siteli yönetici: site seçilince menü ve vitrin o sitenin modülleriyle daralır; Tüm siteler geri getirir',
        (t) async {
      final auth = _NavAuth(UserRole.siteManager, sites: twoSites);
      final access = await _access(managerSites);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_kart_finans')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_belgeler')), findsOneWidget);

      await _openDrawer(t);
      expect(find.descendant(of: siteRow, matching: find.text('Tüm siteler (2)')), findsOneWidget);
      expect(t.getRect(siteRow).bottom, lessThanOrEqualTo(t.getRect(find.text('Sakin Moduna Geç')).top + 0.01),
          reason: 'site seçici en üstte');
      await pick(t, '2');
      expect(find.descendant(of: siteRow, matching: find.text('Ay Sitesi')), findsOneWidget);
      expect(_drawerTile(SirketMenuItem.finans), findsNothing, reason: 'Ay Sitesi\'nde Finans kapalı');
      expect(_drawerTile(SirketMenuItem.belgeler), findsOneWidget);
      Navigator.of(t.element(find.byType(YanMenu))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      expect(find.byKey(const ValueKey<String>('panel_kart_finans')), findsNothing, reason: 'vitrin de daralır');
      expect(access.scopeSiteCode, 2);

      await _openDrawer(t);
      await pick(t, 'tum');
      expect(_drawerTile(SirketMenuItem.finans), findsOneWidget);
      expect(_drawerTile(SirketMenuItem.belgeler), findsOneWidget);
      expect(access.scopeSiteCode, isNull);
      await _disposeHome(t);
    });

    testWidgets('site seçimi Kapılar panelini de o siteye çeker (seçili site + liste); Tüm siteler geri getirir', (t) async {
      final auth = _NavAuth(UserRole.siteManager, sites: twoSites);
      final access = await _access(managerSites);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      await pick(t, '2');
      Navigator.of(t.element(find.byType(YanMenu))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      final card = find.byKey(const ValueKey<String>('panel_kart_kapilar'));
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      var dashboard = t.widget<DashboardView>(find.byType(DashboardView));
      expect(dashboard.sites.map((s) => s.id), <int>[2], reason: 'kapsam: yalnız Ay Sitesi');
      expect(dashboard.selectedSite?.id, 2, reason: 'seçili site de kapsamdaki site');

      await _openDrawer(t);
      await pick(t, 'tum');
      dashboard = t.widget<DashboardView>(find.byType(DashboardView));
      expect(dashboard.sites.map((s) => s.id), <int>[1, 2]);

      // Kapılar sayfasındayken (Güneş Sitesi seçiliyken) Ay Sitesi seçilir: panel de hemen o siteye geçer.
      final switcher = t.widget<DashboardView>(find.byType(DashboardView));
      switcher.onSelectSite(1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.widget<DashboardView>(find.byType(DashboardView)).selectedSite?.id, 1);
      await _openDrawer(t);
      await pick(t, '2');
      dashboard = t.widget<DashboardView>(find.byType(DashboardView));
      expect(dashboard.sites.map((s) => s.id), <int>[2]);
      expect(dashboard.selectedSite?.id, 2, reason: 'açık Kapılar paneli de kapsamdaki siteye geçer');
      expect(auth.openDoorCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('Sakin Moduna geçiş site kapsamını sıfırlar; sakin modunda seçici yok', (t) async {
      final handle = t.ensureSemantics();
      final auth = _NavAuth(UserRole.siteManager, sites: twoSites, doors: <DoorRecord>[_door(1)]);
      final access = await _access(managerSites);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      await pick(t, '1');
      expect(access.scopeSiteCode, 1);
      await t.tap(find.text('Sakin Moduna Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(access.scopeSiteCode, isNull);
      await _openDrawer(t);
      expect(t.getSemantics(siteRow), isSemantics(isButton: false, hasTapAction: false));
      handle.dispose();
      await _disposeHome(t);
    });

    testWidgets('rol değişince (yöneticilik kalktı) site kapsamı sıfırlanır: sakin görünümünde değiştirilemeyen kapsam kalmaz',
        (t) async {
      // Yönettiği site listesi boş yönetici (ör. başvurusu süren): yöneticilik kalkınca çift mod da yoktur, kitle sakindir.
      var demoted = false;
      final auth = _NavAuth(UserRole.siteManager, sites: const <SiteRecord>[], doors: <DoorRecord>[_door(1)]);
      final access = await _access(
        () => demoted
            ? <MySiteModules>[_my('resident', site: 1, modules: {'finance': true}), _my('resident', site: 2)]
            : managerSites(),
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      await pick(t, '2');
      expect(access.scopeSiteCode, 2);
      Navigator.of(t.element(find.byType(YanMenu))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));

      demoted = true;
      auth.changeRole(UserRole.apartmentOwner);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(access.scopeSiteCode, isNull, reason: 'kapsam yönetici görünümünde seçilmişti; sakin onu değiştiremez');
      await _openDrawer(t);
      expect(find.descendant(of: siteRow, matching: find.text('Güneş Sitesi +1 site')), findsOneWidget);
      expect(_drawerTile(SirketMenuItem.borcum), findsOneWidget, reason: 'Güneş Sitesi\'nin Borcum\'u kapsam dışında kalmaz');
      await _disposeHome(t);
    });

    testWidgets('tek siteli kullanıcı: site adı en üstte, seçici değil', (t) async {
      final auth = _NavAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(find.descendant(of: siteRow, matching: find.text('Güneş Sitesi')), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('taşma yok', () {
    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (1366, 768, 1.0)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('sakin (alt çubuk + Ayarlar paneli + çekmece) ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}',
            (t) async {
          final auth = _NavAuth(UserRole.apartmentOwner);
          final access = await _access(
            () => <MySiteModules>[_my('resident', modules: {'work_tracking': true, 'drive_storage': true, 'finance': true})],
          );
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: s, dark: dark);
          expect(t.takeException(), isNull);
          expect(_bar, findsOneWidget);
          final body = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;
          expect(t.getRect(body).bottom, lessThanOrEqualTo(t.getRect(_bar).top + 0.01), reason: 'gövde çubuğun üstünde');
          await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
          await t.pump();
          expect(t.takeException(), isNull);
          await _openSettings(t);
          expect(t.takeException(), isNull);
          Navigator.of(t.element(find.byType(YanMenuAyarlar))).pop();
          await t.pump();
          await t.pump(const Duration(milliseconds: 450));
          await _openDrawer(t);
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });
      }
    }
  });
}
