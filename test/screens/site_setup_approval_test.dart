// P2-16: onaylanan site başvurusundan sonraki ilk girişte kuruluma yönlendirme.
//
// Süper kullanıcı başvuruyu onaylayınca (yoklama ya da ön plana dönüş) kullanıcı yönetici görünümüne geçer; o anda
// cihazda kurulum hatırlatma kaydı açılır (Panel'de «Site kurulumunu tamamlayın» kartı) ve «Site başvurunuz onaylandı»
// iletisi sihirbazı açan «Kuruluma başla» eylemini taşır. İleti metinleri değişmez (mevcut testler aynı metni bekler).
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
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';

import 'site_application_fixtures.dart';

SiteRecord _site(int id, String name) => SiteRecord.fromJson(<String, dynamic>{
  'id': id,
  'name': name,
  'approval_status': 'approved',
  'created_at': '2026-10-01T12:30:00Z',
});

/// HomePage için sahte servis: başvuru uçları [SiteApplicationFakeAuth]tan, kabuk uçları burada.
class _HomeApp extends SiteApplicationFakeAuth {
  _HomeApp({super.role});

  List<SiteRecord> sites = <SiteRecord>[];

  @override
  Future<MyModulesResult> getMyModules() async => const MyModulesResult(scope: 'all');

  @override
  Future<ModuleRequestPage> listAdminModuleRequests({String? status, int limit = 50, int? beforeId}) async =>
      const ModuleRequestPage();

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: List<SiteRecord>.of(sites), total: sites.length, page: page, pageSize: pageSize);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    final site = sites.firstWhere((s) => s.id == siteCode, orElse: () => sites.first);
    return (
      SiteStructureRecord(
        site: site,
        blocks: const <SiteBlockRecord>[],
        apartments: const <ApartmentRecord>[],
        doors: const <DoorRecord>[],
      ),
      null,
    );
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SiteSetupProgressStore.shared = SiteSetupProgressStore();
  });

  testWidgets('ONAYLANINCA: hatırlatma kaydı açılır, Panel kartı çıkar, ileti «Kuruluma başla» eylemi taşır', (t) async {
    final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7, siteName: 'Gül Sitesi')]);
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), home: HomePage(authService: auth)),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey<String>('site_setup_resume_card')), findsNothing, reason: 'onaydan önce kurulum kartı yok');

    // Süper kullanıcı onaylar: sunucu siteyi kurar ve kullanıcıyı site yöneticisi yapar.
    auth.serverDecide(7, 'approved');
    auth.sites = [_site(907, 'Gül Sitesi')];
    await t.pump(const Duration(seconds: 31));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('Site başvurunuz onaylandı. Artık site yöneticisisiniz.'), findsOneWidget, reason: 'ileti metni değişmez');
    expect(find.widgetWithText(SnackBarAction, 'Kuruluma başla'), findsOneWidget);

    final saved = await SiteSetupProgressStore.shared.load(auth.session!.id, 907);
    expect(saved, isNotNull, reason: 'onaylanan sitenin hatırlatma kaydı açıldı');
    expect(saved!.siteName, 'Gül Sitesi');
    expect(saved.started, isFalse, reason: 'sihirbaz henüz açılmadı: sıradaki yapılacak adımdan başlar');
    expect(saved.needsAttention, isTrue);

    expect(find.byKey(const ValueKey<String>('site_setup_resume_card')), findsOneWidget);
    expect(find.text('Site kurulumunu tamamlayın'), findsOneWidget);
    expect(find.text('Kuruluma başla'), findsWidgets, reason: 'kartın düğmesi + iletinin eylemi');

    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
}
