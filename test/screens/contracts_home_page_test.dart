// Firma ve Sözleşme Takibi: ana kabuk (HomePage) entegrasyonu — "Sözleşmeler" menü öğesi (SirketMenuItem.sozlesmeler).
//
// Kapı kuralları (güvenlik, FAIL-CLOSED): menü YALNIZ `contracts` modülü AÇIK siteye bağlı yönetici / süper kullanıcı
// (yazar) ve kurul üyesi / görevliye (salt okur) görünür; sakin ve bireysel kullanıcı hiç görmez; modül kapalıyken ya
// da modül verisi hiç gelmemişken (fail-open durumu) AÇILMAZ. Çekmece yerleşimi: Ziyaretçi ve Kargo / Anket / ... /
// Duyurular / Kişiler sırasıyla ilk bulunanın altında.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/contract_api.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/contracts_view.dart';

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

/// Sahte sözleşme sunucusu: istek yollarını kaydeder; listeler boş, özet sıfır döner.
class _Server {
  final List<String> paths = <String>[];

  http.Response handle(http.Request request) {
    final path = request.url.path;
    paths.add(path);
    final Map<String, dynamic> body;
    if (path.endsWith('/contracts/summary')) {
      body = <String, dynamic>{'active': 0, 'expiring_soon': 0, 'expired': 0, 'terminated': 0};
    } else if (path.endsWith('/contracts')) {
      body = <String, dynamic>{'items': <Object>[], 'next_cursor': null};
    } else {
      body = <String, dynamic>{'items': <Object>[]};
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late _Server _server;

MySiteModules _my(String role, {bool contracts = true, bool visitor = false, int code = 11}) => MySiteModules(
  siteCode: code,
  siteName: 'Gül Sitesi',
  role: role,
  modules: <String, bool>{'door_control': true, 'contracts': contracts, 'visitor_log': visitor},
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

const String _label = 'Sözleşmeler';

void main() {
  setUp(() {
    _server = _Server();
    ContractService.debugApiFactory = (auth) => ContractApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() => ContractService.debugApiFactory = null);

  testWidgets('site yöneticisi + modül AÇIK: "Duyurular"ın altında; ekran yazma yetkisiyle açılır', (t) async {
    final auth = _HomeAuth();
    final access = await _access(() => <MySiteModules>[_my('manager')]);
    await _pumpHome(t, auth, access: access);
    await _openDrawer(t);
    final titles = _drawerTitles(t);
    expect(titles.where((x) => x == _label).length, 1);
    expect(titles.indexOf(_label), titles.indexOf('Duyurular') + 1);
    expectUnderDrawerHeader(t, _label, 'Site hizmetleri');
    await _tapTile(t, _tileTitle(_label).first);
    expect(find.byType(ContractsView), findsOneWidget);
    final view = t.widget<ContractsView>(find.byType(ContractsView));
    expect(view.manageAllSites, isFalse);
    expect(view.sites, <ContractSite>[const ContractSite(code: 11, name: 'Gül Sitesi')]);
    expect(view.onOpenModules, isNotNull);
    expect(_server.paths, contains('/manager/sites/11/contracts'));
    expect(_server.paths, contains('/manager/sites/11/contracts/summary'));
    expect(find.byKey(const ValueKey<String>('contract_new')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('contract_read_only_note')), findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text(_label)), findsOneWidget);
    await _disposeHome(t);
  });

  testWidgets('Ziyaretçi ve Kargo da açıksa "Sözleşmeler" onun altında', (t) async {
    final auth = _HomeAuth();
    final access = await _access(() => <MySiteModules>[_my('manager', visitor: true)]);
    await _pumpHome(t, auth, access: access);
    await _openDrawer(t);
    final titles = _drawerTitles(t);
    expect(titles.indexOf(_label), titles.indexOf('Ziyaretçi ve Kargo') + 1);
    await _disposeHome(t);
  });

  testWidgets('modül KAPALI: hiçbir rolde menü öğesi YOK ve uç çağrılmaz', (t) async {
    for (final role in <String>['manager', 'resident', 'board_member', 'staff']) {
      final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my(role, contracts: false)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle(_label), findsNothing, reason: role);
      await _disposeHome(t);
    }
    expect(_server.paths, isEmpty);
  });

  testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse AÇILMAZ', (t) async {
    for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
      final auth = _HomeAuth(role: role)..doors = fxDoors();
      await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
      await _openDrawer(t);
      expect(_tileTitle(_label), findsNothing, reason: '$role');
      await _disposeHome(t);
    }
    expect(_server.paths, isEmpty);
  });

  testWidgets('sakin (modül açık): menü öğesi YOK', (t) async {
    final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
    final access = await _access(() => <MySiteModules>[_my('resident')]);
    await _pumpHome(t, auth, access: access);
    await _openDrawer(t);
    expect(_tileTitle(_label), findsNothing);
    await _disposeHome(t);
    expect(_server.paths, isEmpty);
  });

  testWidgets('görevli (STAFF): menü var, SALT OKUR (yazma düğmesi yok)', (t) async {
    final auth = _HomeAuth(role: UserRole.apartmentOwner);
    final access = await _access(() => <MySiteModules>[_my('staff')]);
    await _pumpHome(t, auth, access: access);
    await _openDrawer(t);
    expect(_drawerTitles(t).where((x) => x == _label).length, 1);
    await _tapTile(t, _tileTitle(_label).first);
    final view = t.widget<ContractsView>(find.byType(ContractsView));
    expect(view.sites.single.access, ContractSiteAccess.staff);
    expect(view.sites.single.canWrite, isFalse);
    expect(view.onOpenModules, isNull);
    expect(find.byKey(const ValueKey<String>('contract_read_only_note')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('contract_new')), findsNothing);
    await _disposeHome(t);
  });

  testWidgets('kurul üyesi: menü var, SALT OKUR', (t) async {
    final auth = _HomeAuth(role: UserRole.apartmentOwner);
    final access = await _access(() => <MySiteModules>[_my('board_member')]);
    await _pumpHome(t, auth, access: access);
    await _openDrawer(t);
    await _tapTile(t, _tileTitle(_label).first);
    final view = t.widget<ContractsView>(find.byType(ContractsView));
    expect(view.sites.single.access, ContractSiteAccess.board);
    expect(find.byKey(const ValueKey<String>('contract_read_only_note')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('contract_new')), findsNothing);
    await _disposeHome(t);
  });

  testWidgets('süper kullanıcı: menü var (tüm siteler, yazar)', (t) async {
    final auth = _HomeAuth(role: UserRole.superUser);
    final access = await _access(() => const <MySiteModules>[], superUser: true);
    await _pumpHome(t, auth, access: access);
    await _openDrawer(t);
    expect(_drawerTitles(t).where((x) => x == _label).length, 1);
    await _tapTile(t, _tileTitle(_label).first);
    final view = t.widget<ContractsView>(find.byType(ContractsView));
    expect(view.manageAllSites, isTrue);
    await _disposeHome(t);
  });

  testWidgets('bireysel kullanıcı ve modül kodu eksik site: menü yok', (t) async {
    final individual = _HomeAuth(role: UserRole.individual);
    await _pumpHome(t, individual, access: await _access(() => const <MySiteModules>[]));
    await _openDrawer(t);
    expect(_tileTitle(_label), findsNothing);
    await _disposeHome(t);

    final manager = _HomeAuth();
    const site = MySiteModules(
      siteCode: 11,
      siteName: 'Gül Sitesi',
      role: 'manager',
      modules: <String, bool>{'door_control': true},
    );
    expect(site.isEnabled(PlatformModuleCodes.contracts), isFalse);
    await _pumpHome(t, manager, access: await _access(() => const <MySiteModules>[site]));
    await _openDrawer(t);
    expect(_tileTitle(_label), findsNothing);
    await _disposeHome(t);
  });
}
