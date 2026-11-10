import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/join_and_setup_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';

import 'site_application_fixtures.dart';

class _UnaffiliatedMockAuth extends SiteApplicationFakeAuth {
  _UnaffiliatedMockAuth({super.role = UserRole.individual, super.myUserCode = 5});

  List<SiteRecord> sites = <SiteRecord>[];
  List<MyApartmentRecord> apartments = <MyApartmentRecord>[];
  List<DoorRecord> doors = <DoorRecord>[];

  @override
  Future<MyModulesResult> getMyModules() async => const MyModulesResult(scope: 'all');

  @override
  Future<ModuleRequestPage> listAdminModuleRequests({String? status, int limit = 50, int? beforeId}) async =>
      const ModuleRequestPage();

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: List<SiteRecord>.of(sites), total: sites.length, page: page, pageSize: pageSize);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async => (
        SiteStructureRecord(
          site: sites.firstWhere((s) => s.id == siteCode, orElse: () => SiteRecord.fromJson({'id': siteCode, 'name': 'Site'})),
          blocks: const <SiteBlockRecord>[],
          apartments: const <ApartmentRecord>[],
          doors: doors,
        ),
        null,
      );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (List<DoorRecord>.of(doors), null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (const <JoinRequestRecord>[], null);

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (List<MyApartmentRecord>.of(apartments), null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

Future<void> _pumpApp(WidgetTester t, _UnaffiliatedMockAuth auth) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  t.view.physicalSize = const Size(400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: HomePage(authService: auth),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bağımsız / Bağsız Kullanıcı Arayüzü (Unaffiliated User UX)', () {
    testWidgets(
      'hiçbir siteye, daireye veya kapıya bağlı olmayan kullanıcı: Kapılar, Acil Durum, Dairem kartları ve menüler gizlenir, doğrudan JoinAndSetupView açılır',
      (t) async {
        final auth = _UnaffiliatedMockAuth(role: UserRole.individual);
        auth.sites = [];
        auth.doors = [];
        auth.apartments = [];

        await _pumpApp(t, auth);

        // 1. Dashboard doğrudan JoinAndSetupView olarak açılmalı
        expect(find.byType(JoinAndSetupView), findsOneWidget);
        expect(find.byType(ModuleShowcaseView), findsNothing);

        // 2. Kapılar, Acil Durum ve Dairem kartları görünmemeli
        expect(find.text('Kapılar'), findsNothing);
        expect(find.text('Acil durum'), findsNothing);
        expect(find.text('Dairem'), findsNothing);

        // 3. Sol çekmece düğmesi (hamburger) bulunmamalı
        expect(find.byType(DrawerButton), findsNothing);

        // 4. Sağdaki ayarlar dişli ikonu bulunmamalı
        expect(find.byIcon(Icons.settings_rounded), findsNothing);

        // 5. Scaffold çekmeceleri (drawer ve endDrawer) null olmalı
        final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.drawer, isNull);
        expect(scaffold.endDrawer, isNull);

        // 6. AppBar içinde hesap popup menüsü olmalı
        expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);

        // 7. JoinAndSetupView içerisindeki gerekli onboarding butonları görünmeli
        expect(find.text('Site Sakini Girişi'), findsOneWidget);
      },
    );

    testWidgets(
      'site yöneticisi rolündeki kullanıcı: çekmece, ayarlar ve vitrin kartları normal gösterilir',
      (t) async {
        final auth = _UnaffiliatedMockAuth(role: UserRole.siteManager);
        auth.sites = [
          SiteRecord.fromJson({'id': 1, 'name': 'Örnek Site', 'approval_status': 'approved'}),
        ];

        await _pumpApp(t, auth);

        // Site yöneticisi vitrinini (ModuleShowcaseView) görmeli
        expect(find.byType(ModuleShowcaseView), findsOneWidget);

        // Sol çekmece (drawer) ve sağ ayarlar (endDrawer) mevcut olmalı
        final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.drawer, isNotNull);
        expect(scaffold.endDrawer, isNotNull);
        expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
      },
    );
  });
}
