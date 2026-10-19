// Anket ve Oylama: ana kabuk (HomePage) entegrasyonu — "Anket ve Oylama" (yönetim) ve "Anketler" (sakin) menü öğeleri.
//
// Kapı kuralları (güvenlik, FAIL-CLOSED): menü YALNIZ `survey` modülü AÇIK siteye bağlı kullanıcıya görünür; modül
// kapalıyken ya da modül verisi hiç gelmemişken AÇILMAZ. Yönetici yazar; kurul salt okur; görevli GÖREMEZ; sakin yalnız
// "Anketler" görür; bireysel kullanıcı hiçbirini göremez. Çekmece: "Anket ve Oylama" Rezervasyon / Rezervasyonlar /
// Taleplerim / Talepler / Belgeler / Borcum / Finans / Duyurular / Kişiler sırasıyla ilk bulunanın altında; "Anketler"
// varsa "Anket ve Oylama"nın altında.
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
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/survey_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/survey_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/survey_resident_view.dart';

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

/// Sahte anket sunucusu: istek yollarını kaydeder; listeler boş döner.
class _Server {
  final List<String> paths = <String>[];

  http.Response handle(http.Request request) {
    paths.add(request.url.path);
    final body = request.url.path.startsWith('/manager/')
        ? <String, dynamic>{'items': <Object>[], 'total': 0}
        : <String, dynamic>{'items': <Object>[], 'next_before_id': null};
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late _Server _server;

MySiteModules _my(String role, {bool survey = true, bool reservation = false, int code = 11}) => MySiteModules(
  siteCode: code,
  siteName: 'Gül Sitesi',
  role: role,
  modules: <String, bool>{'door_control': true, 'survey': survey, 'reservation': reservation},
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

void main() {
  setUp(() {
    _server = _Server();
    SurveyService.debugApiFactory = (auth) =>
        SurveyApi(baseUrl: 'http://localhost', client: MockClient((request) async => _server.handle(request)));
  });

  tearDown(() => SurveyService.debugApiFactory = null);

  group('Anket ve Oylama (yönetim)', () {
    testWidgets('site yöneticisi + modül AÇIK: "Duyurular"ın altında; seçilince yönetim ekranı', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Anket ve Oylama'));
      expect(titles, isNot(contains('Anketler')), reason: 'yönetici modunda sakin ekranı yok');
      expect(titles.indexOf('Anket ve Oylama'), titles.indexOf('Duyurular') + 1);
      await t.tap(_tileTitle('Anket ve Oylama'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      final view = t.widget<SurveyManagerView>(find.byType(SurveyManagerView));
      expect(view.manageAllSites, isFalse);
      expect(view.sites, <SurveySite>[const SurveySite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/manager/sites/11/surveys'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Anket ve Oylama')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('svm_new')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Rezervasyonlar da açıksa Anket ve Oylama onun altında', (t) async {
      final auth = _HomeAuth();
      final access = await _access(() => <MySiteModules>[_my('manager', reservation: true)]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Anket ve Oylama'), titles.indexOf('Rezervasyonlar') + 1);
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: iki menü öğesi de YOK ve anket ucu çağrılmaz', (t) async {
      for (final role in <String>['manager', 'resident', 'board_member', 'staff']) {
        final auth = _HomeAuth(role: role == 'manager' ? UserRole.siteManager : UserRole.apartmentOwner);
        final access = await _access(() => <MySiteModules>[_my(role, survey: false)]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle('Anket ve Oylama'), findsNothing, reason: role);
        expect(_tileTitle('Anketler'), findsNothing, reason: role);
        await _disposeHome(t);
      }
      expect(_server.paths, isEmpty);
    });

    testWidgets('FAIL-OPEN YOK: modül verisi hiç gelmezse hiçbiri AÇILMAZ', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.apartmentOwner]) {
        final auth = _HomeAuth(role: role)..doors = fxDoors();
        await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
        await _openDrawer(t);
        expect(_tileTitle('Anket ve Oylama'), findsNothing, reason: '$role');
        expect(_tileTitle('Anketler'), findsNothing, reason: '$role');
        await _disposeHome(t);
      }
    });

    testWidgets('görevli (STAFF): hiçbiri yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('staff')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Anket ve Oylama'), findsNothing);
      expect(_tileTitle('Anketler'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: SALT OKUR; alıcı sakin olarak Anketler "Anket ve Oylama"nın altında', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Anketler'), titles.indexOf('Anket ve Oylama') + 1);
      await t.tap(_tileTitle('Anket ve Oylama'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      final view = t.widget<SurveyManagerView>(find.byType(SurveyManagerView));
      expect(view.sites.single.access, SurveySiteAccess.board);
      expect(view.sites.single.canWrite, isFalse);
      expect(find.byKey(const ValueKey<String>('survey_read_only_note')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Anket ve Oylama var (tüm siteler); Anketler yok', (t) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Anket ve Oylama');
      final view = t.widget<SurveyManagerView>(find.byType(SurveyManagerView));
      expect(view.manageAllSites, isTrue);
      await _openDrawer(t);
      expect(_tileTitle('Anketler'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Anketler (sakin)', () {
    testWidgets('daire sakini + modül AÇIK: Anketler var, yönetim yok; ekran yalnız o siteyi alır', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Anket ve Oylama'), findsNothing);
      await t.tap(_tileTitle('Anketler'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      final view = t.widget<SurveyResidentView>(find.byType(SurveyResidentView));
      expect(view.sites, <PeopleSite>[const PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(_server.paths, contains('/app/surveys'));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Anketler')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: ikisi de yok', (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      await _pumpHome(t, auth, access: await _access(() => const <MySiteModules>[]));
      await _openDrawer(t);
      expect(_tileTitle('Anket ve Oylama'), findsNothing);
      expect(_tileTitle('Anketler'), findsNothing);
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
      expect(site.isEnabled(PlatformModuleCodes.survey), isFalse);
      await _pumpHome(t, auth, access: await _access(() => <MySiteModules>[site]));
      await _openDrawer(t);
      expect(_tileTitle('Anketler'), findsNothing);
      await _disposeHome(t);
    });
  });
}
