// Acil durum: ana kabuk (HomePage) entegrasyonu. Menü öğesi MODÜL DEĞİL çekirdek özelliktir: süper kullanıcı dışında herkeste ve modül verisi
// hiç gelmese bile (acil durumda ağ ya da modül durumuna bağlı olmasın) "Ana sayfa" başlığı altında görünür; seçilince Acil durum ekranı açılır.
// Çekmecedeki site seçimi ekrana taşınır; bakım firması düzenleme yetkisi yalnız yönetici modundaki yöneticidedir.
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
import 'package:site_kapi_kontrol/ui/views/emergency_view.dart';

import '../support/menu_nav.dart';
import 'dialog_layout_harness.dart' show settleFor;
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

MySiteModules _my(String role, {int code = 11, String name = 'Gül Sitesi'}) => MySiteModules(
  siteCode: code,
  siteName: name,
  role: role,
  modules: const <String, bool>{'door_control': true},
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

Finder _tile(String title) => find.descendant(of: find.byType(Drawer), matching: find.text(title));

void main() {
  group('menü öğesi', () {
    testWidgets('site yöneticisi (yönetici modu): "Ana sayfa" başlığı altında, Panel\'in yanında; seçilince ekran açılır, düzenleme AÇIK', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await openMenuDrawer(t);
      expectUnderDrawerHeader(t, 'Acil durum', 'Ana sayfa');
      expect(menuListTitles(t), contains('Acil durum'));

      await tapMenuEntry(t, 'Acil durum');
      await settleFor(t);
      final view = t.widget<EmergencyView>(find.byType(EmergencyView));
      expect(view.allowEdit, isTrue);
      expect(view.preferredSiteCode, isNull);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Acil durum')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_quick_fire')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('emergency_quick_elevator')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('daire sakini: öğe var, düzenleme KAPALI', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await openMenuDrawer(t);
      expectUnderDrawerHeader(t, 'Acil durum', 'Ana sayfa');
      await tapMenuEntry(t, 'Acil durum');
      await settleFor(t);
      expect(t.widget<EmergencyView>(find.byType(EmergencyView)).allowEdit, isFalse);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi ve görevli de görür (bilgi herkese), düzenleyemez', (t) async {
      for (final role in <String>['board_member', 'staff']) {
        final auth = _HomeAuth(role: UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role)]);
        await _pumpHome(t, auth, access: access);
        await openMenuDrawer(t);
        expect(_tile('Acil durum'), findsOneWidget, reason: role);
        await tapMenuEntry(t, 'Acil durum');
        await settleFor(t);
        expect(t.widget<EmergencyView>(find.byType(EmergencyView)).allowEdit, isFalse, reason: role);
        await _disposeHome(t);
      }
    });

    testWidgets('sakin modundaki yönetici: öğe var ama düzenleme KAPALI; yönetici moduna dönünce açık', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await openMenuDrawer(t);
      await t.tap(find.text('Sakin Moduna Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await openMenuDrawer(t);
      expect(_tile('Acil durum'), findsOneWidget);
      await tapMenuEntry(t, 'Acil durum');
      await settleFor(t);
      expect(t.widget<EmergencyView>(find.byType(EmergencyView)).allowEdit, isFalse);

      await openMenuDrawer(t);
      await t.tap(find.text('Yönetici Paneline Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await tapMenuEntry(t, 'Acil durum');
      await settleFor(t);
      expect(t.widget<EmergencyView>(find.byType(EmergencyView)).allowEdit, isTrue);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı (sitesiz): öğe var; ekran 112 ile çalışır', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      final access = await _access(() => const <MySiteModules>[]);
      await _pumpHome(t, auth, access: access);
      await openMenuDrawer(t);
      expect(_tile('Acil durum'), findsOneWidget);
      await tapMenuEntry(t, 'Acil durum');
      await settleFor(t);
      expect(find.byType(EmergencyView), findsOneWidget);
      expect(find.text('112 Acil Çağrı Merkezi'), findsWidgets);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: öğe YOK (site bağı yoktur)', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await openMenuDrawer(t);
      expect(_tile('Acil durum'), findsNothing);
      expect(menuListTitles(t), isNot(contains('Acil durum')));
      await _disposeHome(t);
    });

    testWidgets('modül verisi hiç gelmese bile öğe VAR (modül değil çekirdek özellik; fail-open)', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await openMenuDrawer(t);
        expect(_tile('Acil durum'), findsOneWidget, reason: '$role');
        await _disposeHome(t);
      }
    });
  });

  testWidgets('çekmecedeki site seçimi ekrana taşınır (adres doğru siteden)', (t) async {
    final auth = _HomeAuth();
    final access = await _access(() => <MySiteModules>[_my('manager'), _my('resident', code: 22, name: 'Lale Sitesi')]);
    access.setScopeSiteCode(22);
    await _pumpHome(t, auth, access: access);
    await openMenuDrawer(t);
    await tapMenuEntry(t, 'Acil durum');
    await settleFor(t);
    final view = t.widget<EmergencyView>(find.byType(EmergencyView));
    expect(view.preferredSiteCode, 22);
    await _disposeHome(t);
  });

  testWidgets('Panel vitrininde "Acil durum" kartı vardır ve dokununca ekranı açar', (t) async {
    final auth = _HomeAuth(role: UserRole.apartmentOwner);
    final access = await _access(() => <MySiteModules>[_my('resident')]);
    await _pumpHome(t, auth, access: access);
    final card = find.text('112, yangın ve asansör arızası');
    expect(card, findsOneWidget);
    await t.ensureVisible(card);
    await t.pump();
    await t.tap(card);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await settleFor(t);
    expect(find.byType(EmergencyView), findsOneWidget);
    await _disposeHome(t);
  });
}
