// Platform Faz 2a: ana kabuk (HomePage) entegrasyonu — "Kişiler" menü öğesi.
//
// - Site yöneticisi (yönetici modu) ve süper kullanıcı: "Kişiler" çekmecede; seçilince PeopleView açılır,
//   AppBar başlığı "Kişiler", genel yenileme (Yenile) ekranı tazeler.
// - Kurul üyesi (my-modules rolü board_member): "Kişiler" çekmecede, ekran SALT OKUNUR; yönetim site
//   listesi çağrılmaz.
// - Görevli (staff) ve sıradan sakin: "Kişiler" YOK.
// - Sakin profili: "Kayıtlarım" bölümü.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_crm.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'people_fixtures.dart';

/// HomePage için sahte servis: Kişi ve Daire Kayıtları uçlarına ek olarak ana kabuğun ihtiyaç duyduğu
/// uçlar (kapılar, modül durumu) boş döner.
class _HomePeopleAuth extends PeopleFakeAuth {
  _HomePeopleAuth({super.role, bool seeded = true}) {
    if (seeded) {
      final seed = PeopleFakeAuth.seeded();
      peopleJson.addAll(seed.peopleJson);
      apartmentsJson.addAll(seed.apartmentsJson);
      vehiclesJson.addAll(seed.vehiclesJson);
    }
  }

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async =>
      (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

MySiteModules _my(String role, {int code = 11, bool access = true}) => MySiteModules(
  siteCode: code,
  siteName: 'Gül Sitesi',
  role: role,
  doorAccess: access,
  modules: const <String, bool>{'door_control': true},
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

Future<void> _pumpHome(
  WidgetTester t,
  PeopleFakeAuth auth, {
  ModuleAccess? access,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HomePage(authService: auth, moduleAccess: access),
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

/// Çekmecedeki öğeye dokunur. Bulucu çekmeceyle SINIRLIDIR: Panel modül vitrininde de aynı adlı kartlar vardır.
Future<void> _tapMenu(WidgetTester t, String label) async {
  await _openDrawer(t);
  final tile = find.descendant(of: find.byType(Drawer), matching: find.text(label)).first;
  await t.ensureVisible(tile);
  await t.pump();
  await t.tap(tile);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await settleFor(t);
}

Finder _tileTitle(String title) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(title));

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

void main() {
  group('Kişiler menü öğesi', () {
    testWidgets('site yöneticisi: "Kişiler" çekmecede; seçilince PeopleView açılır, başlık "Kişiler", yazma yetkisi var', (t) async {
      final auth = _HomePeopleAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);

      await _openDrawer(t);
      expect(_tileTitle('Kişiler'), findsOneWidget);
      await t.tap(_tileTitle('Kişiler'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      expect(find.byType(PeopleView), findsOneWidget);
      expect(_inAppBar(find.text('Kişiler')), findsOneWidget);
      expect(auth.peopleCalls, isNotEmpty);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Kişi Ekle'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('genel yenileme (AppBar Yenile) Kişiler ekranını tazeler', (t) async {
      final auth = _HomePeopleAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Kişiler');
      final sitesBefore = auth.listSitesCalls;
      final peopleBefore = auth.peopleCalls.length;

      auth.peopleJson[9] = pplPersonJson(9, 'Yenileme Sonrası');
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      expect(auth.listSitesCalls, greaterThan(sitesBefore));
      expect(auth.peopleCalls.length, greaterThan(peopleBefore));
      expect(find.text('Yenileme Sonrası'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: "Kişiler" var ve yazma yetkisi var', (t) async {
      final auth = _HomePeopleAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Kişiler');
      expect(find.byType(PeopleView), findsOneWidget);
      expect(find.text('Kişi Ekle'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi (my-modules rolü board_member): "Kişiler" var, SALT OKUNUR, yönetim site listesi çağrılmaz', (t) async {
      final auth = _HomePeopleAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);

      await _openDrawer(t);
      expect(_tileTitle('Kişiler'), findsOneWidget);
      await t.tap(_tileTitle('Kişiler'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      expect(find.byType(PeopleView), findsOneWidget);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Kişi Ekle'), findsNothing);
      expect(find.text('Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.'), findsOneWidget);
      expect(auth.listSitesCalls, 0);
      expect(auth.peopleCalls.first.site, 11);
      await _disposeHome(t);
    });

    testWidgets('görevli (staff) ve sıradan sakin: "Kişiler" YOK', (t) async {
      for (final role in const <String>['staff', 'resident']) {
        final auth = _HomePeopleAuth(role: UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role)]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle('Kişiler'), findsNothing, reason: role);
        expect(_tileTitle('Profilim'), findsOneWidget);
        await _disposeHome(t);
      }
    });

    testWidgets('modül verisi gelmediyse (fail-open) kurul üyeliği varsayılmaz: "Kişiler" yok', (t) async {
      final auth = _HomePeopleAuth(role: UserRole.apartmentOwner);
      await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
      await _openDrawer(t);
      expect(_tileTitle('Kişiler'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyeliği kalkınca açık Kişiler ekranı Panel\'e döner', (t) async {
      final auth = _HomePeopleAuth(role: UserRole.apartmentOwner);
      var sites = <MySiteModules>[_my('board_member')];
      final access = await _access(() => sites);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Kişiler');
      expect(find.byType(PeopleView), findsOneWidget);

      sites = <MySiteModules>[_my('resident')];
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(PeopleView), findsNothing);
      expect(_inAppBar(find.text('Kişiler')), findsNothing, reason: 'başlık Kişiler değil');
      await _disposeHome(t);
    });

    testWidgets('hem yönetici hem başka sitede kurul üyesi: yönetilen sitede yazma, kurul sitesinde salt okunur', (t) async {
      final auth = _HomePeopleAuth();
      final access = await _access(
        () => <MySiteModules>[_my('manager'), _my('board_member', code: 12)],
      );
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Kişiler');
      expect(find.text('Kişi Ekle'), findsOneWidget);
      expect(find.text('Site'), findsOneWidget, reason: 'iki site: seçici');
      await _disposeHome(t);
    });
  });

  group('Sakin profilinde "Kayıtlarım"', () {
    testWidgets('daire sakini: Profilim → Hesap Bilgilerim + Kayıtlarım (GET /app/my-records)', (t) async {
      final auth = _HomePeopleAuth(role: UserRole.apartmentOwner, seeded: false)
        ..myRecords = <MyRecord>[pplMyRecord()];
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Profilim');
      expect(find.text('Hesap Bilgilerim'), findsOneWidget);
      expect(find.text('Kayıtlarım'), findsOneWidget);
      expect(find.text('A Blok - 5'), findsOneWidget);
      expect(auth.myRecordsCalls, greaterThanOrEqualTo(1));
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: Profilim formu + (kayıt varsa) Kayıtlarım; kayıt yoksa bölüm gizli', (t) async {
      final auth = _HomePeopleAuth(role: UserRole.individual, seeded: false);
      final access = await _access(() => const <MySiteModules>[]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Profilim');
      expect(find.text('Profili Kaydet'), findsOneWidget);
      expect(find.text('Kayıtlarım'), findsNothing);
      await _disposeHome(t);
    });
  });
}
