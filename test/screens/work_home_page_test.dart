// İş Takibi: ana kabuk (HomePage) entegrasyonu — "Talepler" (yönetim) ve "Taleplerim" (sakin) menü öğeleri.
//
// Kapı kuralları (güvenlik): menü YALNIZ `work_tracking` modülü AÇIK siteye bağlı kullanıcıya görünür; modül kapalıyken
// ya da modül verisi hiç gelmemişken (fail-open durumu) AÇILMAZ. Yönetici = yazar; görevli = kendine atanmış ya da
// atanmamış talepleri yazar; kurul = salt okur; sakin yalnız "Taleplerim" görür; bireysel kullanıcı hiçbirini göremez.
// Çekmece yerleşimi: "Talepler" Belgeler / Borcum / Finans / Duyurular / Kişiler sırasıyla ilk bulunanın altında,
// "Taleplerim" varsa "Talepler"in altında.
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
import 'package:site_kapi_kontrol/models/work_tracking_models.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/work_tracking_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/work_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/work_resident_view.dart';

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
  Future<(List<DoorRecord>?, String?)> listMyDoors() async =>
      (List<DoorRecord>.of(doors), null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async =>
      <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({
    required int doorId,
  }) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

/// Sahte iş takibi sunucusu: istek yollarını kaydeder; listeler boş döner.
class _WorkServer {
  final List<String> paths = <String>[];

  http.Response handle(http.Request request) {
    paths.add(request.url.path);
    final body = request.url.path.startsWith('/manager/')
        ? <String, dynamic>{'items': <Object>[], 'next_before_id': null, 'counts': <String, dynamic>{}}
        : <String, dynamic>{'items': <Object>[], 'next_before_id': null, 'unread_updates': 0};
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late _WorkServer _server;

MySiteModules _my(String role, {bool work = true, bool documents = false, int code = 11}) => MySiteModules(
  siteCode: code,
  siteName: 'Gül Sitesi',
  role: role,
  modules: <String, bool>{
    'door_control': true,
    'work_tracking': work,
    'drive_storage': documents,
  },
  doorAccess: !(role == 'staff' || role == 'board_member'),
);

Future<ModuleAccess> _access(
  List<MySiteModules> Function() sites, {
  bool superUser = false,
}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
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

Future<void> _tapMenu(WidgetTester t, String label) async {
  await _openDrawer(t);
  final tile = find.descendant(of: find.byType(Drawer), matching: find.text(label));
  await t.ensureVisible(tile.first);
  await t.pump();
  await t.tap(tile.first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await settleFor(t);
}

Finder _tileTitle(String title) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D (G2): menü LİSTESİNİN sırası (vitrin sırası; `YanMenu.visibleItems`: çekmece + Ayarlar paneli). Çekmece öğeleri
/// başlıklar altında gruplar ([expectUnderDrawerHeader]); ayar öğeleri sağ üstteki dişlidedir.
List<String> _drawerTitles(WidgetTester t) => menuListTitles(t);

void main() {
  setUp(() {
    _server = _WorkServer();
    WorkTrackingService.debugApiFactory = (auth) => WorkTrackingApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() => WorkTrackingService.debugApiFactory = null);

  group('Talepler (yönetim)', () {
    testWidgets('site yöneticisi + modül AÇIK: "Duyurular"ın altında; seçilince yönetim ekranı, yazma erişimi', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Talepler'));
      expect(titles, isNot(contains('Taleplerim')), reason: 'yönetici modunda sakin ekranı yok');
      expect(titles.indexOf('Talepler'), titles.indexOf('Duyurular') + 1);
      expectUnderDrawerHeader(t, 'Talepler', 'İletişim');
      await t.tap(_tileTitle('Talepler'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(WorkManagerView), findsOneWidget);
      final view = t.widget<WorkManagerView>(find.byType(WorkManagerView));
      expect(view.manageAllSites, isFalse);
      expect(view.sites, <WorkTrackingSite>[const WorkTrackingSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/manager/sites/11/work-items'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Talepler')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Belgeler de açıksa Talepler Belgeler\'in altında', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager', documents: true)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Talepler'), titles.indexOf('Dosya Deposu') + 1);
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: iki menü öğesi de YOK ve iş takibi ucu çağrılmaz', (t) async {
      for (final role in <String>['manager', 'resident', 'board_member', 'staff']) {
        final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role, work: false)]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle('Talepler'), findsNothing, reason: role);
        expect(_tileTitle('Taleplerim'), findsNothing, reason: role);
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse hiçbiri AÇILMAZ (yönetici ve sakin)', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await _openDrawer(t);
        expect(_tileTitle('Talepler'), findsNothing, reason: '$role');
        expect(_tileTitle('Taleplerim'), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
    });

    testWidgets('görevli (STAFF): yalnız Talepler (görevli erişimi); Taleplerim yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('staff')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Talepler');
      expect(find.byType(WorkManagerView), findsOneWidget);
      final view = t.widget<WorkManagerView>(find.byType(WorkManagerView));
      expect(view.sites.single.access, WorkSiteAccess.staff);
      expect(view.sites.single.canWrite, isTrue);
      await _openDrawer(t);
      expect(_tileTitle('Taleplerim'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: Talepler SALT OKUR (not var); aynı zamanda alıcı sakin: Taleplerim "Talepler"in altında', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Taleplerim'), titles.indexOf('Talepler') + 1);
      await t.tap(_tileTitle('Talepler'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      final view = t.widget<WorkManagerView>(find.byType(WorkManagerView));
      expect(view.sites.single.access, WorkSiteAccess.board);
      expect(view.sites.single.canWrite, isFalse);
      expect(find.byKey(const ValueKey<String>('work_read_only_note')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Talepler var (tüm siteler, yazma); Taleplerim yok', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Talepler');
      final view = t.widget<WorkManagerView>(find.byType(WorkManagerView));
      expect(view.manageAllSites, isTrue);
      await _openDrawer(t);
      expect(_tileTitle('Taleplerim'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Taleplerim (sakin)', () {
    testWidgets('daire sakini + modül AÇIK: Taleplerim var, Talepler yok; ekran yalnız o siteyi alır', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Talepler'), findsNothing);
      await t.tap(_tileTitle('Taleplerim'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(WorkResidentView), findsOneWidget);
      final view = t.widget<WorkResidentView>(find.byType(WorkResidentView));
      expect(view.sites, <PeopleSite>[const PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/app/work-items'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Taleplerim')), findsOneWidget);
      expect(find.text('Yeni Talep'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: ikisi de yok', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      await _pumpHome(t, auth, access: await _access(() => const <MySiteModules>[]));
      await _openDrawer(t);
      expect(_tileTitle('Talepler'), findsNothing);
      expect(_tileTitle('Taleplerim'), findsNothing);
      await _disposeHome(t);
    });
  });
}
