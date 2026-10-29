// Komşu Panosu: ana kabuk (HomePage) menü KAPISI — kimin "Komşu Panosu" öğesini görebileceği (yetkisiz kullanıcı sınırı).
//
// Kapı kuralı (güvenlik, FAIL-CLOSED): menü YALNIZ `neighbor_board` modülü AÇIK siteye bağlı, sakin ya da yönetici olabilen
// kullanıcıya görünür. Modül kapalıyken, modül kodu hiç gelmemişken (katalog varsayılanı KAPALI) ya da modül verisi hiç
// yüklenememişken AÇILMAZ. Yönetici ve sakin (kurul üyesi dahil) görür; kapı erişimi olmayan görevli (STAFF) GÖRMEZ;
// süper kullanıcı (site listesi boş) ve bireysel kullanıcı GÖRMEZ.
//
// Not: sayfanın kendisi bu dosyada AÇILMAZ — `NeighborBoardView` servisini kendi kurar ve HomePage'in sahte HTTP istemcisi
// vermesini sağlayan bir kanca yoktur (Anket / Karar Defteri'ndeki `debugApiFactory` gibi); açılsa gerçek ağa çıkardı.
// Ekranın kendi davranışı: neighbor_board_boundary_*_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';

import '../support/menu_nav.dart';
import 'list_fixtures.dart' show fxDoors;
import 'people_fixtures.dart';

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

/// Bir sitedeki rol ve modül durumu. [doorAccess]: kapı erişimi (görevlide yoksa duyuru / pano alıcısı sayılmaz).
MySiteModules _my(String role, {bool board = true, bool? doorAccess, int code = 11, String name = 'Gül Sitesi'}) => MySiteModules(
  siteCode: code,
  siteName: name,
  role: role,
  modules: <String, bool>{'door_control': true, 'neighbor_board': board},
  doorAccess: doorAccess ?? !(role == 'staff' || role == 'board_member'),
);

Future<ModuleAccess> _access(List<MySiteModules> sites, {bool superUser = false}) async {
  final access = ModuleAccess(fetch: () async => MyModulesResult(sites: sites), isSuperUser: () => superUser);
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

Finder _boardTile() => find.descendant(of: find.byType(Drawer), matching: find.text('Komşu Panosu'));

/// Verilen kullanıcı ve sitelerle ana kabuğu kurar, çekmeceyi açar ve "Komşu Panosu" öğesi var mı döner.
Future<bool> _hasBoardMenu(WidgetTester t, _HomeAuth auth, List<MySiteModules> sites, {bool superUser = false}) async {
  await _pumpHome(t, auth, access: await _access(sites, superUser: superUser));
  await openMenuDrawer(t);
  final present = _boardTile().evaluate().isNotEmpty;
  await _disposeHome(t);
  return present;
}

void main() {
  group('menüde görünür (kapı açık)', () {
    testWidgets('site yöneticisi + modül AÇIK: "Komşu Panosu" "İletişim" başlığının altında', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth, access: await _access(<MySiteModules>[_my('manager')]));
      await openMenuDrawer(t);
      expect(_boardTile(), findsOneWidget);
      expect(menuListTitles(t), contains('Komşu Panosu'));
      expectUnderDrawerHeader(t, 'Komşu Panosu', 'İletişim');
      await _disposeHome(t);
    });

    testWidgets('daire sakini + modül AÇIK: görür', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      expect(await _hasBoardMenu(t, auth, <MySiteModules>[_my('resident')]), isTrue);
    });

    testWidgets('kurul üyesi + modül AÇIK: sakin olarak görür (yönetim denetimi yok, sakin ekranı)', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      expect(await _hasBoardMenu(t, auth, <MySiteModules>[_my('board_member')]), isTrue);
    });

    testWidgets('kapı erişimi olan görevli (STAFF) sakin gibi görür', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      expect(await _hasBoardMenu(t, auth, <MySiteModules>[_my('staff', doorAccess: true)]), isTrue);
    });

    testWidgets('iki site: biri kapalı, biri açık -> menü var; ikisi de kapalı -> yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      expect(
        await _hasBoardMenu(t, auth, <MySiteModules>[_my('resident', board: false), _my('resident', code: 12, name: 'Mavi Park')]),
        isTrue,
      );
      expect(
        await _hasBoardMenu(t, auth, <MySiteModules>[_my('resident', board: false), _my('resident', board: false, code: 12, name: 'Mavi Park')]),
        isFalse,
      );
    });
  });

  group('menüde YOK (yetkisiz / kapalı)', () {
    testWidgets('modül KAPALI: hiçbir rolde görünmez', (t) async {
      for (final role in const <String>['manager', 'resident', 'board_member', 'staff']) {
        final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner)..doors = fxDoors();
        expect(await _hasBoardMenu(t, auth, <MySiteModules>[_my(role, board: false)]), isFalse, reason: role);
      }
    });

    testWidgets('kapı erişimi olmayan görevli (STAFF) göremez (duyuru / pano alıcısı değil)', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      expect(await _hasBoardMenu(t, auth, <MySiteModules>[_my('staff', doorAccess: false)]), isFalse);
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
      expect(await _hasBoardMenu(t, auth, <MySiteModules>[site]), isFalse);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse (ağ hatası) yönetici ve sakin için açılmaz', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await openMenuDrawer(t);
        expect(_boardTile(), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
    });

    testWidgets('süper kullanıcı: göremez (site listesi boş)', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      expect(await _hasBoardMenu(t, auth, const <MySiteModules>[], superUser: true), isFalse);
    });

    testWidgets('bireysel kullanıcı: göremez', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      expect(await _hasBoardMenu(t, auth, const <MySiteModules>[]), isFalse);
    });
  });
}
