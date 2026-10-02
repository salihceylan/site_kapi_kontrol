import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';

SiteRecord _site(int id, String name) => SiteRecord(
      id: id,
      name: name,
      address: null,
      city: null,
      district: null,
      blockCount: 1,
      apartmentCount: 4,
      doorCount: 1,
      approvalStatus: 'approved',
      approvedAt: DateTime(2026, 1, 1),
      mqttSiteId: id,
      managerUserCode: 5,
      managerName: 'Yönetici',
      createdAt: DateTime(2026, 1, 1),
    );

DoorRecord _door(int id, int siteCode, String name) => DoorRecord(
      id: id,
      siteCode: siteCode,
      siteName: 'Site $siteCode',
      doorName: name,
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: null,
      assignedDeviceUid: null,
      mqttSiteId: siteCode,
      createdAt: DateTime(2026, 1, 1),
    );

SiteStructureRecord _structure(SiteRecord site, List<DoorRecord> doors) =>
    SiteStructureRecord(
      site: site,
      blocks: const <SiteBlockRecord>[],
      apartments: const <ApartmentRecord>[],
      doors: doors,
    );

/// Çok-siteli yarışları ve yaşam döngüsü davranışını gözlemlemek için sahte servis.
class _HomeAuth extends AuthService {
  _HomeAuth({required this.sites}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  List<SiteRecord> sites;
  final Map<int, Completer<(SiteStructureRecord?, String?)>> structureGates = {};
  final Map<int, SiteStructureRecord> structures = {};
  final List<int> structureRequests = <int>[];
  int refreshCalls = 0;
  int listMyDoorsCalls = 0;
  final List<int> widgetSelections = <int>[];

  final UserSession _fixedSession = const UserSession(
    id: 5,
    fullName: 'Site Yöneticisi',
    email: 'yonetici@example.com',
    loginName: null,
    role: UserRole.siteManager,
    isActive: true,
    token: 'tok',
  );

  @override
  UserSession? get session => _fixedSession;

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {
    refreshCalls++;
  }

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async {
    return SitePage(sites: sites, total: sites.length, page: 1, pageSize: 100);
  }

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) {
    structureRequests.add(siteCode);
    final gate = structureGates[siteCode];
    if (gate != null) return gate.future;
    return Future.value((structures[siteCode], null));
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    listMyDoorsCalls++;
    return (<DoorRecord>[], null);
  }

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async {
    return (null, null);
  }

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {
    widgetSelections.add(door.id);
  }
}

Future<void> _pumpHome(WidgetTester tester, _HomeAuth auth) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(MaterialApp(home: HomePage(authService: auth)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _disposeHome(WidgetTester tester) async {
  // Periyodik zamanlayıcıları ve gecikmiş çağrıları temizle.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> _selectSite(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('geç gelen eski site yapısı yeni seçimi ezmez (istek jetonu)', (tester) async {
    final siteA = _site(1, 'A Sitesi');
    final siteB = _site(2, 'B Sitesi');
    final auth = _HomeAuth(sites: [siteA, siteB])
      ..structures[1] = _structure(siteA, [_door(11, 1, 'A Kapısı')])
      ..structures[2] = _structure(siteB, [_door(22, 2, 'B Kapısı')])
      ..structureGates[1] = Completer<(SiteStructureRecord?, String?)>();

    await _pumpHome(tester, auth);

    // Başlangıçta A sitesi seçildi ve yapısı (yavaş) bekleniyor.
    expect(auth.structureRequests, contains(1));

    // Kullanıcı bu arada B sitesini seçer; yapısı hemen gelir.
    await _selectSite(tester, 'B Sitesi (2)');
    expect(auth.structureRequests, contains(2));
    expect(find.textContaining('B Kapısı'), findsWidgets);

    // Şimdi A'nın GEÇ gelen yanıtı tamamlanır: ekran B'de kalmalı.
    auth.structureGates[1]!.complete((auth.structures[1], null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('B Kapısı'), findsWidgets);
    expect(find.textContaining('A Kapısı'), findsNothing,
        reason: 'eski sitenin kapıları yeni seçimin üstüne yazılmamalı');
    expect(tester.takeException(), isNull);

    await _disposeHome(tester);
  });

  testWidgets('ön plana dönüşte /me doğrulaması tetiklenir (C11)', (tester) async {
    final siteA = _site(1, 'A Sitesi');
    final auth = _HomeAuth(sites: [siteA])
      ..structures[1] = _structure(siteA, [_door(11, 1, 'A Kapısı')]);

    await _pumpHome(tester, auth);
    final before = auth.refreshCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(auth.refreshCalls, before + 1);
    await _disposeHome(tester);
  });

  testWidgets('widget senkronu: yönetici panelinde listMyDoors tek kaynak olarak çağrılır', (tester) async {
    final siteA = _site(1, 'A Sitesi');
    final auth = _HomeAuth(sites: [siteA])
      ..structures[1] = _structure(siteA, [_door(11, 1, 'A Kapısı')]);

    await _pumpHome(tester, auth);

    expect(auth.listMyDoorsCalls, greaterThanOrEqualTo(1));
    // Otomatik yüklemede widget'ın aktif kapısı zorlanmaz.
    expect(auth.widgetSelections, isEmpty);
    await _disposeHome(tester);
  });

  testWidgets('kullanıcı kapıyı açıkça seçince widget aktif kapısı da güncellenir', (tester) async {
    final siteA = _site(1, 'A Sitesi');
    final auth = _HomeAuth(sites: [siteA])
      ..structures[1] = _structure(
        siteA,
        [_door(11, 1, 'A Kapısı'), _door(12, 1, 'Garaj Kapısı')],
      );

    await _pumpHome(tester, auth);
    expect(auth.widgetSelections, isEmpty);

    // İkinci dropdown: kapı seçimi
    await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Garaj Kapısı').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(auth.widgetSelections, [12]);
    await _disposeHome(tester);
  });
}
