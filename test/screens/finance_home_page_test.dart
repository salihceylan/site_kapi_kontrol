// Platform Faz 4a: ana kabuk (HomePage) entegrasyonu — "Finans" ve "Borcum" menü öğeleri.
//
// Kapı kuralları (güvenlik): menü YALNIZ `finance` modülü AÇIK siteye bağlı kullanıcıya görünür; modül kapalıyken
// ya da modül verisi hiç gelmemişken (fail-open durumu) AÇILMAZ. Yazma = yönetici / süper (yönetici modunda);
// kurul üyesi salt okunur; görevli, bireysel kullanıcı ve (Finans için) sakin göremez; sakin yalnız "Borcum".
import 'dart:async';

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
import 'package:site_kapi_kontrol/ui/views/finance_view.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show fxDoors, tapFinder;

/// HomePage için sahte servis: finans uçlarına ek olarak ana kabuğun ihtiyaç duyduğu uçlar boş döner.
class _HomeFinanceAuth extends FinanceFakeAuth {
  _HomeFinanceAuth({super.role, bool seeded = true}) {
    if (seeded) {
      final seed = FinanceFakeAuth.seeded();
      apartmentsJson.addAll(seed.apartmentsJson);
      definitions.addAll(seed.definitions);
      ledger.addAll(seed.ledger);
    }
  }

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

/// `my-modules` satırı: [finance] true ise modül AÇIK. Yalnız kurul / görevli bağında `door_access` FALSE.
MySiteModules _my(
  String role, {
  bool finance = true,
  int code = 11,
  String name = 'Gül Sitesi',
  bool? doorAccess,
}) => MySiteModules(
  siteCode: code,
  siteName: name,
  role: role,
  modules: <String, bool>{'door_control': true, 'finance': finance},
  doorAccess: doorAccess ?? !(role == 'staff' || role == 'board_member'),
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

/// Hiç bildirim yoklaması yapmayan duyuru izleyicisi (bu testler duyuruları sınamaz).
AnnouncementNotifier _quietNotifier(FinanceFakeAuth auth) => AnnouncementNotifier(
  fetchSummary: () async => throw StateError('yok'),
  fetchInbox: () async => throw StateError('yok'),
  fetchAnnouncement: (id) async => throw StateError('yok'),
  isEligible: () => false,
);

Future<void> _pumpHome(
  WidgetTester t,
  _HomeFinanceAuth auth, {
  ModuleAccess? access,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier(auth);
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

Future<void> _closeDrawer(WidgetTester t) async {
  Navigator.of(t.element(find.byType(Drawer))).pop();
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

List<String> _drawerTitles(WidgetTester t) => <String>[
  for (final tile in t.widgetList<ListTile>(find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile))))
    (tile.title! as Text).data!,
];

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

void main() {
  group('Finans menü öğesi (yönetici / kurul / süper)', () {
    testWidgets('site yöneticisi + modül AÇIK: "Duyurular"ın altında; seçilince Finans ekranı, yazma yetkisi, başlık', (t) async {
      final auth = _HomeFinanceAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Finans'));
      expect(titles.indexOf('Finans'), titles.indexOf('Duyurular') + 1);
      expect(titles, isNot(contains('Borcum')), reason: 'yönetici modunda Borcum yok');
      await t.tap(_tileTitle('Finans'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      expect(find.byType(FinanceView), findsOneWidget);
      expect(_inAppBar(find.text('Finans')), findsOneWidget);
      expect(auth.summaryCalls, greaterThan(0));
      expect(find.byType(FinanceSummaryCard), findsOneWidget);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
      expect(find.text('Tahsilat Ekle'), findsOneWidget);
      expect(find.text('Ek Borç Ekle'), findsOneWidget);
      expect(
        auth.listSitesArgs.any((a) => a.approval == 'approved'),
        isFalse,
        reason: 'Finans site listesini my-modules\'tan alır (tüm onaylı siteleri çekmez)',
      );
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: menü öğesi YOK', (t) async {
      final auth = _HomeFinanceAuth();
      final access = await _access(() => <MySiteModules>[_my('manager', finance: false)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing);
      expect(_tileTitle('Borcum'), findsNothing);
      expect(auth.summaryCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse Finans / Borcum AÇILMAZ (yönetici ve sakin)', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeFinanceAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await _openDrawer(t);
        expect(_tileTitle('Finans'), findsNothing, reason: '$role');
        expect(_tileTitle('Borcum'), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
    });

    testWidgets('modül verisi yüklenirken menü yok; yüklenince AÇIK sitede görünür', (t) async {
      final gate = Completer<MyModulesResult>();
      final auth = _HomeFinanceAuth();
      final access = ModuleAccess(fetch: () => gate.future, isSuperUser: () => false);
      addTearDown(access.dispose);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing);
      await _closeDrawer(t);
      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('manager')]));
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: Finans SALT OKUNUR (not var, yazma düğmesi yok; ekstrede de yok)', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Finans');
      expect(find.byType(FinanceView), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_read_only_note')), findsOneWidget);
      expect(find.text('Tahsilat Ekle'), findsNothing);
      expect(find.text('Ek Borç Ekle'), findsNothing);
      expect(find.byType(BalanceRowCard), findsNWidgets(3));
      expect(auth.listSitesCalls, 0);
      await tapFinder(t, find.widgetWithText(BalanceRowCard, 'A Blok - 5'));
      await settleFor(t);
      expect(find.text('Hesap Ekstresi'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_account_add_payment')), findsNothing);
      expect(find.byKey(const ValueKey<String>('ledger_reverse_1')), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi ama modül KAPALI: Finans yok', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member', finance: false)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('yalnız-görevli (staff) ve bireysel kullanıcı: ne Finans ne Borcum', (t) async {
      final staff = _HomeFinanceAuth(role: UserRole.apartmentOwner);
      await _pumpHome(t, staff, access: await _access(() => <MySiteModules>[_my('staff')]));
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing);
      expect(_tileTitle('Borcum'), findsNothing);
      await _disposeHome(t);

      final individual = _HomeFinanceAuth(role: UserRole.individual);
      await _pumpHome(t, individual, access: await _access(() => const <MySiteModules>[]));
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing);
      expect(_tileTitle('Borcum'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Finans var (tüm siteler, yazma yetkisi); Borcum YOK', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Borcum'), findsNothing);
      await t.tap(_tileTitle('Finans'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(FinanceView), findsOneWidget);
      expect(auth.listSitesArgs.any((a) => a.approval == 'approved'), isTrue, reason: 'tüm onaylı siteler');
      expect(find.text('Tahsilat Ekle'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: modülü KAPALI sitede açıklayıcı bilgi + "Modüller" düğmesi Modüller ekranına gider', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.superUser)..moduleEnabled = false;
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Finans');
      expect(find.byKey(const ValueKey<String>('finance_module_off')), findsOneWidget);
      await tapFinder(t, find.byKey(const ValueKey<String>('finance_open_modules')));
      await settleFor(t);
      expect(find.byType(ModulesView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('açıkken modül kapatılırsa (poll) seçili Finans ekranı Panel\'e düşer, menü kalkar', (t) async {
      final auth = _HomeFinanceAuth();
      var financeOn = true;
      final access = await _access(() => <MySiteModules>[_my('manager', finance: financeOn)]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Finans');
      expect(find.byType(FinanceView), findsOneWidget);
      financeOn = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(FinanceView), findsNothing);
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Borcum menü öğesi (sakin)', () {
    testWidgets('daire sakini + modül AÇIK: Borcum var, Finans YOK; seçilince Borcum ekranı, başlık, yalnız görüntüleme', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner)
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Borcum'));
      expect(titles, isNot(contains('Finans')));
      await t.tap(_tileTitle('Borcum'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      expect(find.byType(MyFinanceView), findsOneWidget);
      expect(_inAppBar(find.text('Borcum')), findsOneWidget);
      expect(auth.myFinanceCalls, 1);
      expect(find.byType(MyFinanceCard), findsOneWidget);
      expect(find.text('Tahsilat Ekle'), findsNothing);
      expect(auth.summaryCalls, 0, reason: 'sakin yönetici uçlarını çağırmaz');
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI sitede sakin: Borcum YOK', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', finance: false)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Borcum'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('iki siteli sakin: yalnız modülü AÇIK site yeterli; kapalı sitenin daireleri sunucudan gelmez', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', finance: false),
          _my('resident', code: 12, name: 'Mavi Park'),
        ],
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Borcum'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('sakin modundaki yönetici: Borcum var, Finans YOK; yönetici moduna dönünce tersi', (t) async {
      final auth = _HomeFinanceAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsOneWidget);
      expect(_tileTitle('Borcum'), findsNothing);
      await t.tap(find.text('Sakin Moduna Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsNothing, reason: 'sakin modunda yönetim yazma yetkisi yok');
      expect(_tileTitle('Borcum'), findsOneWidget);
      await t.tap(find.text('Yönetici Paneline Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await _openDrawer(t);
      expect(_tileTitle('Finans'), findsOneWidget);
      expect(_tileTitle('Borcum'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('çekip yenileme Borcum verisini yeniden çeker', (t) async {
      final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner)
        ..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Borcum');
      final calls = auth.myFinanceCalls;
      await t.state<MyFinanceViewState>(find.byType(MyFinanceView)).reload();
      await settleFor(t);
      expect(auth.myFinanceCalls, calls + 1);
      await _disposeHome(t);
    });
  });

  group('taşma: ana kabuk içinde', () {
    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('Finans (yönetici) ve çekmece: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}', (t) async {
          final auth = _HomeFinanceAuth();
          final access = await _access(() => <MySiteModules>[_my('manager')]);
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: s, dark: dark);
          await _tapMenu(t, 'Finans');
          expect(find.byType(FinanceView), findsOneWidget);
          await _openDrawer(t);
          expect(_tileTitle('Finans'), findsOneWidget);
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });

        testWidgets('Borcum (sakin) ve çekmece: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}', (t) async {
          final auth = _HomeFinanceAuth(role: UserRole.apartmentOwner)
            ..myFinanceItems = <Map<String, dynamic>>[finMyItem()];
          final access = await _access(() => <MySiteModules>[_my('resident')]);
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: s, dark: dark);
          await _tapMenu(t, 'Borcum');
          expect(find.byType(MyFinanceView), findsOneWidget);
          await _openDrawer(t);
          expect(_tileTitle('Borcum'), findsOneWidget);
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });
      }
    }
  });
}
