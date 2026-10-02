// FAZ 5 / P-e: uzun sayfalarda kaydırma. HomePage içeriği SingleChildScrollView içindedir; sınır
// (RepaintBoundary) yoksa her kaydırma karesinde yüzlerce kartın tümü baştan boyanır.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:site_kapi_kontrol/ui/widgets/apartment_card.dart';

final SiteRecord _site = SiteRecord(
  id: 1,
  name: 'Büyük Site',
  address: null,
  city: null,
  district: null,
  blockCount: 1,
  apartmentCount: 150,
  doorCount: 1,
  approvalStatus: 'approved',
  approvedAt: DateTime(2026, 1, 1),
  mqttSiteId: 1,
  managerUserCode: 5,
  managerName: 'Yönetici',
  createdAt: DateTime(2026, 1, 1),
);

ApartmentRecord _apartment(int i) => ApartmentRecord.fromJson({
      'id': i + 1,
      'site_code': 1,
      'block_id': 1,
      'block_name': 'A Blok',
      'unit_label': 'Daire ${i + 1}',
      'resident_full_name': 'Sakin Adı $i',
      'resident_login_name': 'sakin$i',
      'resident_pin_code': '1234',
      'resident_is_active': true,
    });

class _BigSiteAuth extends AuthService {
  _BigSiteAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserSession _session = const UserSession(
    id: 5,
    fullName: 'Site Yöneticisi',
    email: 'yonetici@example.com',
    loginName: null,
    role: UserRole.siteManager,
    isActive: true,
    token: 'tok',
  );

  @override
  UserSession? get session => _session;

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: [_site], total: 1, page: 1, pageSize: 100);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async => (
        SiteStructureRecord(
          site: _site,
          blocks: const <SiteBlockRecord>[],
          apartments: [for (var i = 0; i < 150; i++) _apartment(i)],
          doors: const <DoorRecord>[],
        ),
        null,
      );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;
}

void main() {
  testWidgets('ÖLÇÜM: 150 daire kartlı sayfa kaydırılırken kare başına boyama işi', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: HomePage(authService: _BigSiteAuth())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Menü -> Site Yönetimi -> "Daireler" akordiyonunu aç.
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Site Yönetimi').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Daireler').first);
    await tester.tap(find.text('Daireler').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ApartmentCard, skipOffstage: false), findsNWidgets(150));
    // Akordiyon açılış animasyonu bitsin (animasyon sürerken içerik zaten her kare boyanır).
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.maxScrollExtent, greaterThan(5000));

    var paintCalls = 0;
    debugOnProfilePaint = (RenderObject renderObject) => paintCalls++;
    addTearDown(() => debugOnProfilePaint = null);
    for (var i = 0; i < 20; i++) {
      scrollable.position.jumpTo(100.0 + i * 60);
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnProfilePaint = null;
    print('ÖLÇÜM HomePage 20 kaydırma karesi: paintChild çağrısı=$paintCalls (kare başına ${(paintCalls / 20).toStringAsFixed(0)})');

    // Sınır varsa içerik önbellekteki katman olarak kaydırılır: kare başına yalnız birkaç boyama.
    expect(paintCalls, lessThan(20 * 60), reason: 'kaydırma kartları baştan boyatmamalı');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
