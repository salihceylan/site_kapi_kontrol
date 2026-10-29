// Site yöneticisinin "İşlem Kayıtları" ekranı: ana kabuk (HomePage) entegrasyonu — SirketMenuItem.islemKayitlari (P2-19).
//
// Kapı kuralları (güvenlik, FAIL-CLOSED): menü YALNIZ yönetici modundaki site yöneticisine, yöneticisi olduğu en az bir site
// bilindiğinde görünür; sakin, kurul üyesi, görevli, bireysel kullanıcı ve süper kullanıcı (kendi "Denetim Kaydı"nı kullanır)
// hiç görmez; modül/site verisi hiç gelmemişken AÇILMAZ. Öğe Ayarlar panelindedir ("Modüller"in hemen altında).
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
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/site_audit_log_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/site_audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_audit_log_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

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

/// Sahte sunucu: istek yollarını kaydeder; tek kayıt döner.
class _Server {
  final List<Uri> requests = <Uri>[];

  http.Response handle(http.Request request) {
    requests.add(request.url);
    final body = <String, dynamic>{
      'items': <Object>[
        <String, dynamic>{
          'id': 7,
          'created_at': '2026-10-27T11:20:00.000Z',
          'actor_name': 'Ayşe Yönetici',
          'actor_role': 'site_manager',
          'actor_role_label': 'Site yöneticisi',
          'action': 'module.enabled',
          'action_label': 'Modül açıldı',
          'category': 'modules',
          'category_label': 'Modüller',
          'target_type': 'module',
          'target_id': 'finance',
          'details': <String, dynamic>{'enabled': true},
        },
      ],
      'next_before_id': null,
    };
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late _Server _server;

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

const String _label = 'İşlem Kayıtları';

void main() {
  setUp(() {
    _server = _Server();
    SiteAuditLogService.debugApiFactory = (auth) => SiteAuditLogApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() => SiteAuditLogService.debugApiFactory = null);

  testWidgets('site yöneticisi: Ayarlar panelinde "Modüller"in altında; ekran yöneticisi olduğu siteyle açılır ve kayıtları ister', (t) async {
    final auth = _HomeAuth();
    final access = await _access(() => <MySiteModules>[_my('manager')]);
    await _pumpHome(t, auth, access: access);

    await openMenuDrawer(t);
    final order = menuListTitles(t);
    expect(order.where((x) => x == _label).length, 1);
    expect(order.indexOf(_label), order.indexOf('Modüller') + 1);
    expect(menuGroupOf(SirketMenuItem.islemKayitlari), SirketMenuGroup.ayarlar);
    expect(await settingsTitlesOnly(t), contains(_label));
    expect(await drawerTitlesOnly(t), isNot(contains(_label)), reason: 'ayar öğesi çekmecede değil, Ayarlar panelinde');

    await tapMenuEntry(t, _label);
    await settleFor(t);
    expect(find.byType(SiteAuditLogView), findsOneWidget);
    final view = t.widget<SiteAuditLogView>(find.byType(SiteAuditLogView));
    expect(view.sites, <PeopleSite>[const PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true)]);
    expect(_server.requests, hasLength(1));
    expect(_server.requests.single.path, '/manager/sites/11/audit-log');
    expect(_server.requests.single.queryParameters, <String, String>{'limit': '50'});
    expect(find.byType(SiteAuditLogCard), findsOneWidget);
    expect(find.text('Modül açıldı'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text(_label)), findsOneWidget);
    await _disposeHome(t);
  });

  testWidgets('çok siteli yönetici: yalnız YÖNETİCİSİ olduğu siteler (sakini olduğu site yok) ve site seçici', (t) async {
    final auth = _HomeAuth();
    final access = await _access(
      () => <MySiteModules>[_my('manager'), _my('manager', code: 12, name: 'Mavi Park'), _my('resident', code: 13, name: 'Başka Site')],
    );
    await _pumpHome(t, auth, access: access);
    await tapMenuEntry(t, _label);
    await settleFor(t);
    final view = t.widget<SiteAuditLogView>(find.byType(SiteAuditLogView));
    expect(view.sites.map((s) => s.code), <int>[11, 12]);
    expect(find.text('Site'), findsOneWidget);
    expect(_server.requests.single.path, '/manager/sites/11/audit-log');
    await _disposeHome(t);
  });

  testWidgets('sakin, kurul üyesi, görevli: menü öğesi YOK ve uç çağrılmaz', (t) async {
    for (final role in <String>['resident', 'board_member', 'staff']) {
      final auth = _HomeAuth(role: UserRole.apartmentOwner)..doors = fxDoors();
      final access = await _access(() => <MySiteModules>[_my(role)]);
      await _pumpHome(t, auth, access: access);
      final titles = await menuAndSettingsTitles(t);
      expect(titles, isNot(contains(_label)), reason: role);
      await _disposeHome(t);
    }
    expect(_server.requests, isEmpty);
  });

  testWidgets('FAIL-CLOSED: site/modül verisi hiç gelmezse AÇILMAZ', (t) async {
    final auth = _HomeAuth();
    await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
    expect(await menuAndSettingsTitles(t), isNot(contains(_label)));
    await _disposeHome(t);
    expect(_server.requests, isEmpty);
  });

  testWidgets('süper kullanıcı ve bireysel kullanıcı: menü öğesi YOK (süper kullanıcı kendi "Denetim Kaydı"nı kullanır)', (t) async {
    final superAuth = _HomeAuth(role: UserRole.superUser);
    await _pumpHome(t, superAuth, access: await _access(() => const <MySiteModules>[], superUser: true));
    final superTitles = await menuAndSettingsTitles(t);
    expect(superTitles, isNot(contains(_label)));
    expect(superTitles, contains('Denetim Kaydı'));
    await _disposeHome(t);

    final individual = _HomeAuth(role: UserRole.individual);
    await _pumpHome(t, individual, access: await _access(() => const <MySiteModules>[]));
    expect(await menuAndSettingsTitles(t), isNot(contains(_label)));
    await _disposeHome(t);
    expect(_server.requests, isEmpty);
  });

  testWidgets('yöneticisi olduğu site yoksa (yalnız sakin) yönetici rolünde bile menü öğesi YOK', (t) async {
    final auth = _HomeAuth();
    final access = await _access(() => <MySiteModules>[_my('resident')]);
    await _pumpHome(t, auth, access: access);
    expect(await menuAndSettingsTitles(t), isNot(contains(_label)));
    await _disposeHome(t);
    expect(_server.requests, isEmpty);
  });
}
