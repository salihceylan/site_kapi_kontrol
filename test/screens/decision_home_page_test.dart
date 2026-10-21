// Karar Defteri: ana kabuk (HomePage) entegrasyonu — "Karar Defteri" (yönetim) ve "Kararlar" (sakin) menü öğeleri.
//
// Kapı kuralları (güvenlik, FAIL-CLOSED): menü YALNIZ `decision_book` modülü AÇIK siteye bağlı kullanıcıya görünür; modül
// kapalıyken ya da modül verisi hiç gelmemişken AÇILMAZ. Yönetici yazar; kurul salt okur (taslaklar dahil); görevli
// GÖREMEZ; sakin yalnız "Kararlar" görür; bireysel kullanıcı hiçbirini göremez.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/decision_book_api.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/decision_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/decision_resident_view.dart';

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

/// Sahte karar sunucusu: istek yollarını kaydeder; listeler boş döner.
class _Server {
  final List<String> paths = <String>[];

  http.Response handle(http.Request request) {
    paths.add(request.url.path);
    return http.Response.bytes(
      utf8.encode(jsonEncode(<String, dynamic>{'items': <Object>[], 'next_cursor': null, 'next_before_id': null, 'years': <int>[]})),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late _Server _server;

MySiteModules _my(String role, {bool decisions = true, bool survey = false, int code = 11}) => MySiteModules(
  siteCode: code,
  siteName: 'Gül Sitesi',
  role: role,
  modules: <String, bool>{'door_control': true, 'decision_book': decisions, 'survey': survey},
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

Future<void> _selectTile(WidgetTester t, String title) async {
  final tile = _tileTitle(title);
  await t.ensureVisible(tile.first);
  await t.pump();
  await t.tap(tile.first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await settleFor(t);
}

Finder _tileTitle(String title) => find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D (G2): menü LİSTESİNİN sırası (vitrin sırası; `YanMenu.visibleItems`: çekmece + Ayarlar paneli). Çekmece öğeleri
/// başlıklar altında gruplar ([expectUnderDrawerHeader]); ayar öğeleri sağ üstteki dişlidedir.
List<String> _drawerTitles(WidgetTester t) => menuListTitles(t);

void main() {
  setUp(() {
    _server = _Server();
    DecisionBookService.debugApiFactory = (auth) =>
        DecisionBookApi(baseUrl: 'http://localhost', client: MockClient((request) async => _server.handle(request)));
  });

  tearDown(() => DecisionBookService.debugApiFactory = null);

  group('Karar Defteri (yönetim)', () {
    testWidgets('site yöneticisi + modül AÇIK: menüde var (Kararlar yok); seçilince yazabilen yönetim ekranı', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Karar Defteri'));
      expect(titles, isNot(contains('Kararlar')), reason: 'yönetici modunda sakin ekranı yok');
      expect(titles.indexOf('Karar Defteri'), titles.indexOf('Duyurular') + 1);
      expectUnderDrawerHeader(t, 'Karar Defteri', 'Site hizmetleri');
      await _selectTile(t, 'Karar Defteri');
      final view = t.widget<DecisionManagerView>(find.byType(DecisionManagerView));
      expect(view.manageAllSites, isFalse);
      expect(view.sites, <DecisionSite>[const DecisionSite(code: 11, name: 'Gül Sitesi')]);
      expect(view.sites.single.canWrite, isTrue);
      expect(_server.paths, contains('/manager/sites/11/decisions'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Karar Defteri')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('decision_new')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('decision_legal_notice')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Anket de açıksa Karar Defteri onun altında', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager', survey: true)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Karar Defteri'), titles.indexOf('Anket ve Oylama') + 1);
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: iki menü öğesi de YOK ve karar ucu çağrılmaz', (t) async {
      for (final role in <String>['manager', 'resident', 'board_member', 'staff']) {
        final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role, decisions: false)]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle('Karar Defteri'), findsNothing, reason: role);
        expect(_tileTitle('Kararlar'), findsNothing, reason: role);
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse hiçbiri AÇILMAZ', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await _openDrawer(t);
        expect(_tileTitle('Karar Defteri'), findsNothing, reason: '$role');
        expect(_tileTitle('Kararlar'), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('görevli (STAFF): hiçbiri yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('staff')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Karar Defteri'), findsNothing);
      expect(_tileTitle('Kararlar'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: Karar Defteri SALT OKUR; alıcı sakin olarak Kararlar onun altında', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Kararlar'), titles.indexOf('Karar Defteri') + 1);
      await _selectTile(t, 'Karar Defteri');
      final view = t.widget<DecisionManagerView>(find.byType(DecisionManagerView));
      expect(view.sites.single.access, DecisionSiteAccess.board);
      expect(view.sites.single.canWrite, isFalse);
      expect(find.byKey(const ValueKey<String>('decision_read_only_note')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('decision_new')), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('sakin modundaki yönetici: Kararlar var, Karar Defteri YOK; yönetici moduna dönünce tersi', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Karar Defteri'), findsOneWidget);
      expect(_tileTitle('Kararlar'), findsNothing);
      await t.tap(find.text('Sakin Moduna Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await _openDrawer(t);
      expect(_tileTitle('Karar Defteri'), findsNothing, reason: 'sakin modunda yönetim yazma yetkisi yok');
      expect(_tileTitle('Kararlar'), findsOneWidget);
      await t.tap(find.text('Yönetici Paneline Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await _openDrawer(t);
      expect(_tileTitle('Karar Defteri'), findsOneWidget);
      expect(_tileTitle('Kararlar'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Karar Defteri var (tüm siteler); Kararlar yok', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      await _selectTile(t, 'Karar Defteri');
      final view = t.widget<DecisionManagerView>(find.byType(DecisionManagerView));
      expect(view.manageAllSites, isTrue);
      await _openDrawer(t);
      expect(_tileTitle('Kararlar'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Kararlar (sakin)', () {
    testWidgets('daire sakini + modül AÇIK: Kararlar var, yönetim yok; ekran yalnız o siteyi alır', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Karar Defteri'), findsNothing);
      await _selectTile(t, 'Kararlar');
      final view = t.widget<DecisionResidentView>(find.byType(DecisionResidentView));
      expect(view.sites, <PeopleSite>[const PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/app/decisions'));
      expect(_server.paths.where((p) => p.startsWith('/manager/')), isEmpty);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Kararlar')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('decision_legal_notice')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: ikisi de yok', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      await _pumpHome(t, auth, access: await _access(() => const <MySiteModules>[]));
      await _openDrawer(t);
      expect(_tileTitle('Karar Defteri'), findsNothing);
      expect(_tileTitle('Kararlar'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('modül kodu eksik site (katalog varsayılanı KAPALI): menü açılmaz', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final site = MySiteModules(
        siteCode: 11,
        siteName: 'Gül Sitesi',
        role: 'resident',
        modules: const <String, bool>{'door_control': true},
        doorAccess: true,
      );
      expect(site.isEnabled(PlatformModuleCodes.decisionBook), isFalse);
      await _pumpHome(t, auth, access: await _access(() => <MySiteModules>[site]));
      await _openDrawer(t);
      expect(_tileTitle('Kararlar'), findsNothing);
      await _disposeHome(t);
    });
  });
}
