// Ziyaretçi ve Kargo: ana kabuk (HomePage) entegrasyonu — "Ziyaretçi ve Kargo" yönetim / görevli ve sakin menü
// öğeleri (SirketMenuItem.ziyaretciKayitlari / ziyaretcilerim).
//
// Kapı kuralları (güvenlik, FAIL-CLOSED): menü YALNIZ `visitor_log` modülü AÇIK siteye bağlı kullanıcıya görünür; modül
// kapalıyken ya da modül verisi hiç gelmemişken (fail-open durumu) AÇILMAZ. Yönetici ve görevli = yazar; kurul = salt
// okur; sakin yalnız kendi ekranını görür (okunmamış rozeti `summary` ile); bireysel kullanıcı hiçbirini göremez.
// Çekmece yerleşimi: yönetim öğesi Rezervasyon / Rezervasyonlar / Taleplerim / Talepler / Belgeler / Borcum / Finans /
// Duyurular / Kişiler sırasıyla ilk bulunanın altında; sakin öğesi varsa yönetim öğesinin altında.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/visitor_log_models.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/visitor_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/visitor_resident_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show fxDoors;
import 'people_fixtures.dart';
import '../support/menu_nav.dart';

class _HomeAuth extends PeopleFakeAuth {
  _HomeAuth({super.role});

  @override
  Future<void> refreshSession({bool force = false}) async {}

  List<DoorRecord> doors = <DoorRecord>[];

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (List<DoorRecord>.of(doors), null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

/// Sahte ziyaretçi sunucusu: istek yollarını kaydeder; listeler boş döner; özet [unread] verir.
class _Server {
  final List<String> paths = <String>[];
  int unread = 0;

  http.Response handle(http.Request request) {
    final path = request.url.path;
    paths.add(path);
    final Map<String, dynamic> body;
    if (path.endsWith('/visitor-entries/summary')) {
      body = <String, dynamic>{'unread': unread};
    } else if (path.startsWith('/manager/')) {
      body = <String, dynamic>{'items': <Object>[], 'total': 0};
    } else {
      body = <String, dynamic>{'items': <Object>[], 'next_before_id': null};
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late _Server _server;

MySiteModules _my(String role, {bool visitor = true, bool reservation = false, int code = 11}) => MySiteModules(
  siteCode: code,
  siteName: 'Gül Sitesi',
  role: role,
  modules: <String, bool>{'door_control': true, 'visitor_log': visitor, 'reservation': reservation},
  doorAccess: !(role == 'staff' || role == 'board_member'),
);

Future<ModuleAccess> _access(List<MySiteModules> Function() sites, {bool superUser = false}) async {
  final access = ModuleAccess(fetch: () async => MyModulesResult(sites: sites()), isSuperUser: () => superUser);
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

Future<void> _pumpHome(WidgetTester t, _HomeAuth auth, {ModuleAccess? access}) async {
  t.view.physicalSize = const Size(400, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier();
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Finder _tileTitle(String title) => find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D (G2): menü LİSTESİNİN sırası (vitrin sırası; `YanMenu.visibleItems`: çekmece + Ayarlar paneli). Çekmece öğeleri
/// başlıklar altında gruplar ([expectUnderDrawerHeader]); ayar öğeleri sağ üstteki dişlidedir.
List<String> _drawerTitles(WidgetTester t) => menuListTitles(t);

Future<void> _tapTile(WidgetTester t, Finder tile) async {
  await t.ensureVisible(tile);
  await t.pump();
  await t.tap(tile);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await settleFor(t);
}

const String _label = 'Ziyaretçi ve Kargo';

/// Sakin öğesinin başlığı yönetim öğesinden AYRIDIR (kurul üyesinde ikisi birden görünür; aynı adlı iki öğe olmasın).
const String _residentLabel = 'Ziyaretçilerim';

void main() {
  setUp(() {
    _server = _Server();
    VisitorLogService.debugApiFactory = (auth) => VisitorLogApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() => VisitorLogService.debugApiFactory = null);

  group('yönetim / görevli', () {
    testWidgets('site yöneticisi + modül AÇIK: "Duyurular"ın altında; seçilince yönetim ekranı, yazma erişimi', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.where((x) => x == _label).length, 1);
      expect(titles, isNot(contains(_residentLabel)), reason: 'yönetici modunda sakin öğesi yok');
      expect(titles.indexOf(_label), titles.indexOf('Duyurular') + 1);
      expectUnderDrawerHeader(t, _label, 'Site hizmetleri');
      await _tapTile(t, _tileTitle(_label).first);
      expect(find.byType(VisitorManagerView), findsOneWidget);
      final view = t.widget<VisitorManagerView>(find.byType(VisitorManagerView));
      expect(view.manageAllSites, isFalse);
      expect(view.sites, <VisitorSite>[const VisitorSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/manager/sites/11/visitor-entries'));
      expect(_server.paths, isNot(contains('/app/visitor-entries/summary')), reason: 'yönetici modunda rozet yoklaması yok');
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(_label)), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Rezervasyonlar da açıksa yönetim öğesi onun altında', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager', reservation: true)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf(_label), titles.indexOf('Rezervasyonlar') + 1);
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: menü öğesi YOK ve ziyaretçi ucu çağrılmaz', (t) async {
      for (final role in <String>['manager', 'resident', 'board_member', 'staff']) {
        final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role, visitor: false)]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle(_label), findsNothing, reason: role);
        expect(_tileTitle(_residentLabel), findsNothing, reason: role);
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse AÇILMAZ (yönetici ve sakin)', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await _openDrawer(t);
        expect(_tileTitle(_label), findsNothing, reason: '$role');
        expect(_tileTitle(_residentLabel), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('görevli (STAFF): yönetim öğesi görevli erişimiyle (yazar); sakin öğesi yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('staff')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_drawerTitles(t).where((x) => x == _label).length, 1);
      expect(_drawerTitles(t), isNot(contains(_residentLabel)), reason: 'yalnız görevli bağı: sakin öğesi yok');
      await _tapTile(t, _tileTitle(_label).first);
      final view = t.widget<VisitorManagerView>(find.byType(VisitorManagerView));
      expect(view.sites.single.access, VisitorSiteAccess.staff);
      expect(view.sites.single.canWrite, isTrue);
      expect(find.byKey(const ValueKey<String>('visitor_new_entry')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: SALT OKUR (not var); aynı zamanda alıcı sakin: sakin öğesi yönetim öğesinin altında', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      final first = titles.indexOf(_label);
      expect(titles.where((x) => x == _label).length, 1, reason: 'aynı adlı iki öğe yok');
      expect(titles.indexOf(_residentLabel), first + 1, reason: 'yönetim ve sakin öğeleri art arda');
      await _tapTile(t, _tileTitle(_label).first);
      final view = t.widget<VisitorManagerView>(find.byType(VisitorManagerView));
      expect(view.sites.single.access, VisitorSiteAccess.board);
      expect(find.byKey(const ValueKey<String>('visitor_read_only_note')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('visitor_new_entry')), findsNothing);
      await _openDrawer(t);
      await _tapTile(t, _tileTitle(_residentLabel).first);
      expect(find.byType(VisitorResidentView), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(_residentLabel)), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: yönetim öğesi var (tüm siteler); sakin öğesi yok', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_drawerTitles(t).where((x) => x == _label).length, 1);
      expect(_drawerTitles(t), isNot(contains(_residentLabel)));
      await _tapTile(t, _tileTitle(_label).first);
      final view = t.widget<VisitorManagerView>(find.byType(VisitorManagerView));
      expect(view.manageAllSites, isTrue);
      await _disposeHome(t);
    });
  });

  group('sakin', () {
    testWidgets('daire sakini + modül AÇIK: sakin öğesi, okunmamış rozeti (summary), ekran yalnız o siteyi alır', (t) async {
      _server.unread = 2;
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await t.pump(const Duration(milliseconds: 300));
      expect(_server.paths, contains('/app/visitor-entries/summary'));
      await _openDrawer(t);
      expect(_drawerTitles(t).where((x) => x == _residentLabel).length, 1);
      expect(_drawerTitles(t), isNot(contains(_label)), reason: 'yönetim öğesi yok');
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.byKey(const ValueKey<String>('yan_menu_rozet'))),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byType(Drawer), matching: find.text('2')), findsOneWidget);
      await _tapTile(t, _tileTitle(_residentLabel).first);
      expect(find.byType(VisitorResidentView), findsOneWidget);
      final view = t.widget<VisitorResidentView>(find.byType(VisitorResidentView));
      expect(view.sites, <PeopleSite>[const PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(view.onUnreadChanged, isNotNull);
      expect(_server.paths, contains('/app/visitor-entries'));
      expect(_server.paths, isNot(contains('/manager/sites/11/visitor-entries')));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(_residentLabel)), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('okunmamış yoksa rozet yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await t.pump(const Duration(milliseconds: 300));
      await _openDrawer(t);
      expect(find.byKey(const ValueKey<String>('yan_menu_rozet')), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: öğe yok', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      await _pumpHome(t, auth, access: await _access(() => const <MySiteModules>[]));
      await _openDrawer(t);
      expect(_tileTitle(_label), findsNothing);
      expect(_tileTitle(_residentLabel), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('yalnız modül kodu eksik site (katalog varsayılanı KAPALI): menü açılmaz', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final site = MySiteModules(
        siteCode: 11,
        siteName: 'Gül Sitesi',
        role: 'resident',
        modules: const <String, bool>{'door_control': true},
        doorAccess: true,
      );
      final access = await _access(() => <MySiteModules>[site]);
      expect(site.isEnabled(PlatformModuleCodes.visitorLog), isFalse);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle(_label), findsNothing);
      expect(_tileTitle(_residentLabel), findsNothing);
      await _disposeHome(t);
    });
  });
}
