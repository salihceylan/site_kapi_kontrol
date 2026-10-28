// Rezervasyon ve Konsiyerj: ana kabuk (HomePage) entegrasyonu — "Rezervasyonlar" (yönetim) ve "Rezervasyon" (sakin) menü
// öğeleri.
//
// Kapı kuralları (güvenlik, FAIL-CLOSED): menü YALNIZ `reservation` modülü AÇIK siteye bağlı kullanıcıya görünür; modül
// kapalıyken ya da modül verisi hiç gelmemişken (fail-open durumu) AÇILMAZ. Yönetici = alan tanımlar + karar verir; görevli
// = karar verir (alan tanımlayamaz); kurul = salt okur; sakin yalnız "Rezervasyon" görür; bireysel kullanıcı hiçbirini göremez.
// Çekmece yerleşimi: "Rezervasyonlar" Taleplerim / Talepler / Belgeler / Borcum / Finans / Duyurular / Kişiler sırasıyla ilk
// bulunanın altında, "Rezervasyon" varsa "Rezervasyonlar"ın altında.
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
import 'package:site_kapi_kontrol/models/reservation_models.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/reservation_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/reservation_resident_view.dart';

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

/// Sahte rezervasyon sunucusu: istek yollarını kaydeder; listeler boş döner.
class _Server {
  final List<String> paths = <String>[];

  http.Response handle(http.Request request) {
    paths.add(request.url.path);
    final path = request.url.path;
    final Map<String, dynamic> body;
    if (path.endsWith('/reservation-areas')) {
      body = <String, dynamic>{'items': <Object>[], 'active_count': 0};
    } else if (path.endsWith('/reservations')) {
      body = <String, dynamic>{'items': <Object>[], 'next_cursor': null, 'pending_count': 0};
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

MySiteModules _my(String role, {bool reservation = true, bool work = false, bool documents = false, int code = 11}) =>
    MySiteModules(
      siteCode: code,
      siteName: 'Gül Sitesi',
      role: role,
      modules: <String, bool>{
        'door_control': true,
        'reservation': reservation,
        'work_tracking': work,
        'drive_storage': documents,
      },
      doorAccess: !(role == 'staff' || role == 'board_member'),
    );

Future<ModuleAccess> _access(List<MySiteModules> Function() sites, {bool superUser = false}) async {
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

Finder _tileTitle(String title) => find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D (G2): menü LİSTESİNİN sırası (vitrin sırası; `YanMenu.visibleItems`: çekmece + Ayarlar paneli). Çekmece öğeleri
/// başlıklar altında gruplar ([expectUnderDrawerHeader]); ayar öğeleri sağ üstteki dişlidedir.
List<String> _drawerTitles(WidgetTester t) => menuListTitles(t);

void main() {
  setUp(() {
    _server = _Server();
    ReservationService.debugApiFactory = (auth) => ReservationApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() => ReservationService.debugApiFactory = null);

  group('Rezervasyonlar (yönetim)', () {
    testWidgets('site yöneticisi + modül AÇIK: "Duyurular"ın altında; seçilince yönetim ekranı, yönetici erişimi', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Rezervasyonlar'));
      expect(titles, isNot(contains('Rezervasyon')), reason: 'yönetici modunda sakin ekranı yok');
      expect(titles.indexOf('Rezervasyonlar'), titles.indexOf('Duyurular') + 1);
      expectUnderDrawerHeader(t, 'Rezervasyonlar', 'Site hizmetleri');
      await t.tap(_tileTitle('Rezervasyonlar'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(ReservationManagerView), findsOneWidget);
      final view = t.widget<ReservationManagerView>(find.byType(ReservationManagerView));
      expect(view.manageAllSites, isFalse);
      expect(view.sites, <ReservationSite>[const ReservationSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/manager/sites/11/reservations'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Rezervasyonlar')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('rezm_tab_areas')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Talepler de açıksa Rezervasyonlar onun altında', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager', work: true)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Rezervasyonlar'), titles.indexOf('Talepler') + 1);
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: iki menü öğesi de YOK ve rezervasyon ucu çağrılmaz', (t) async {
      for (final role in <String>['manager', 'resident', 'board_member', 'staff']) {
        final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role, reservation: false)]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle('Rezervasyonlar'), findsNothing, reason: role);
        expect(_tileTitle('Rezervasyon'), findsNothing, reason: role);
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse hiçbiri AÇILMAZ (yönetici ve sakin)', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await _openDrawer(t);
        expect(_tileTitle('Rezervasyonlar'), findsNothing, reason: '$role');
        expect(_tileTitle('Rezervasyon'), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
    });

    testWidgets('görevli (STAFF): yalnız Rezervasyonlar (görevli erişimi, alan tanımı yok); Rezervasyon yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('staff')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Rezervasyonlar');
      expect(find.byType(ReservationManagerView), findsOneWidget);
      final view = t.widget<ReservationManagerView>(find.byType(ReservationManagerView));
      expect(view.sites.single.access, ReservationSiteAccess.staff);
      expect(view.sites.single.canWrite, isTrue);
      expect(view.sites.single.canDefineAreas, isFalse);
      await _openDrawer(t);
      expect(_tileTitle('Rezervasyon'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: SALT OKUR (not var); aynı zamanda alıcı sakin: Rezervasyon "Rezervasyonlar"ın altında', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Rezervasyon'), titles.indexOf('Rezervasyonlar') + 1);
      await t.tap(_tileTitle('Rezervasyonlar'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      final view = t.widget<ReservationManagerView>(find.byType(ReservationManagerView));
      expect(view.sites.single.access, ReservationSiteAccess.board);
      expect(view.sites.single.canWrite, isFalse);
      expect(find.byKey(const ValueKey<String>('reservation_read_only_note')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Rezervasyonlar var (tüm siteler, yönetici yetkisi); Rezervasyon yok', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Rezervasyonlar');
      final view = t.widget<ReservationManagerView>(find.byType(ReservationManagerView));
      expect(view.manageAllSites, isTrue);
      await _openDrawer(t);
      expect(_tileTitle('Rezervasyon'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Rezervasyon (sakin)', () {
    testWidgets('daire sakini + modül AÇIK: Rezervasyon var, Rezervasyonlar yok; ekran yalnız o siteyi alır', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Rezervasyonlar'), findsNothing);
      await t.tap(_tileTitle('Rezervasyon'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(ReservationResidentView), findsOneWidget);
      final view = t.widget<ReservationResidentView>(find.byType(ReservationResidentView));
      expect(view.sites, <PeopleSite>[const PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/app/reservation-areas'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Rezervasyon')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('rez_tab_concierge')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: ikisi de yok', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      await _pumpHome(t, auth, access: await _access(() => const <MySiteModules>[]));
      await _openDrawer(t);
      expect(_tileTitle('Rezervasyonlar'), findsNothing);
      expect(_tileTitle('Rezervasyon'), findsNothing);
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
      expect(site.isEnabled(PlatformModuleCodes.reservation), isFalse);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Rezervasyon'), findsNothing);
      await _disposeHome(t);
    });
  });
}
