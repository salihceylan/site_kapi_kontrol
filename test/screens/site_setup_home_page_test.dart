// Site kurulum sihirbazı (P2-15) — ana kabuk (HomePage) girişleri.
//
// - Panel (yönetici / süper kullanıcı görünümü): cihazda KAYDI olan ve bitmemiş kurulum için "Site kurulumunuz yarım kaldı"
//   kartı; "Kuruluma devam et" sihirbazı açar, "Şimdilik gizle" kartı kapatır. Kayıt yoksa ya da başka kullanıcınınsa hiçbir
//   şey çizilmez (kimseye "site kur" diye davet edilmez; AGENTS.md kural 16).
// - Site Yönetimi: seçili sitenin özetinde «Kurulum Sihirbazı» düğmesi.
// - Site başvurusu ONAYLANINCA (P2-16): ilk girişte hatırlatma kaydı açılır, Panel kartı çıkar, ileti "Kuruluma başla" eylemi taşır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_setup_progress.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/site_setup_progress_store.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/site_setup_wizard_view.dart';

import '../support/menu_nav.dart';
import 'site_setup_fixtures.dart';

const int _managerId = 5;

/// HomePage için sahte servis: kurulum sihirbazının okuduğu uçlar [SetupWizardFakeAuth]tan, kabuk uçları burada.
class _HomeAuth extends SetupWizardFakeAuth {
  _HomeAuth({super.role});

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

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

Future<ModuleAccess> _access({bool superUser = false}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(
      sites: superUser
          ? const <MySiteModules>[]
          : const <MySiteModules>[
              MySiteModules(
                siteCode: 11,
                siteName: 'Gül Sitesi',
                role: 'manager',
                doorAccess: true,
                modules: <String, bool>{'door_control': true},
              ),
            ],
    ),
    isSuperUser: () => superUser,
  );
  await access.refresh();
  addTearDown(access.dispose);
  return access;
}

Future<void> _pumpHome(WidgetTester t, SetupWizardFakeAuth auth, ModuleAccess access, {double width = 400, double height = 1000}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomePage(authService: auth, moduleAccess: access),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Future<void> _seed(int userId, SiteSetupProgress progress) async {
  await SiteSetupProgressStore.shared.save(userId, progress);
}

final Finder _card = find.byKey(const ValueKey<String>('site_setup_resume_card'));

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Ortak depo sıraya bağlıdır: önceki testin sahte-zamanlı bölgesinde yarım kalan işlem bu testi bekletmesin.
    SiteSetupProgressStore.shared = SiteSetupProgressStore();
  });

  group('Panel hatırlatma kartı', () {
    testWidgets('kayıtlı bitmemiş kurulum: kart ilerlemeyi söyler; "Kuruluma devam et" sihirbazı kaldığı adımdan açar', (t) async {
      await _seed(
        _managerId,
        const SiteSetupProgress(
          siteCode: 11,
          siteName: 'Gül Sitesi',
          current: SiteSetupStep.modules,
          done: {SiteSetupStep.siteInfo, SiteSetupStep.blocks, SiteSetupStep.apartments},
          skipped: {SiteSetupStep.people},
          started: true,
        ),
      );
      final auth = _HomeAuth();
      await _pumpHome(t, auth, await _access());
      expect(_card, findsOneWidget);
      expect(find.text('Site kurulumunuz yarım kaldı'), findsOneWidget);
      expect(find.text('Gül Sitesi · 3 / 6 adım tamam'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey<String>('site_setup_resume_open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(SiteSetupWizardView), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey<String>('site_setup_step_title'))).data,
        'Adım 5 / 6 · Modüller',
        reason: 'kalınan adımdan devam',
      );

      // Sihirbazı kapat: Panel'e dönülür, kurulum bitmediği için kart durur.
      await t.tap(find.byKey(const ValueKey<String>('site_setup_close')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(SiteSetupWizardView), findsNothing);
      expect(_card, findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('site yeni kuruldu / başvuru onaylandı (kayıt açıldı ama sihirbaz hiç açılmadı): "Kuruluma başla"', (t) async {
      await SiteSetupProgressStore.shared.ensure(_managerId, 11, siteName: 'Gül Sitesi');
      await _pumpHome(t, _HomeAuth(), await _access());
      expect(find.text('Site kurulumunu tamamlayın'), findsOneWidget);
      expect(find.text('Kuruluma başla'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kayıt yoksa kart ÇİZİLMEZ (kimseye site kur diye davet edilmez)', (t) async {
      await _pumpHome(t, _HomeAuth(), await _access());
      expect(_card, findsNothing);
      expect(find.text('Site kurulumunuz yarım kaldı'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('başka kullanıcının kaydı görünmez', (t) async {
      await _seed(99, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true));
      await _pumpHome(t, _HomeAuth(), await _access());
      expect(_card, findsNothing);
      await _disposeHome(t);
    });

    testWidgets('bitirilmiş ya da kapatılmış kurulum hatırlatılmaz', (t) async {
      await _seed(_managerId, const SiteSetupProgress(siteCode: 11, siteName: 'Bitti', finished: true));
      await _seed(_managerId, const SiteSetupProgress(siteCode: 12, siteName: 'Kapalı', dismissed: true));
      await _pumpHome(t, _HomeAuth(), await _access());
      expect(_card, findsNothing);
      await _disposeHome(t);
    });

    testWidgets('"Şimdilik gizle" kartı kapatır ve kayıt kalıcıdır', (t) async {
      await _seed(_managerId, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true));
      await _pumpHome(t, _HomeAuth(), await _access());
      expect(_card, findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('site_setup_resume_dismiss')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(_card, findsNothing);
      expect(await SiteSetupProgressStore.shared.nextUnfinished(_managerId), isNull);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı kendi kaydını görür', (t) async {
      await _seed(1, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true));
      await _pumpHome(t, _HomeAuth(role: UserRole.superUser), await _access(superUser: true));
      expect(_card, findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('daire sakini Panel\'inde kurulum kartı YOKTUR (kayıt olsa bile)', (t) async {
      await _seed(5, const SiteSetupProgress(siteCode: 11, siteName: 'Gül Sitesi', started: true));
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = ModuleAccess(
        fetch: () async => const MyModulesResult(
          sites: <MySiteModules>[
            MySiteModules(siteCode: 11, siteName: 'Gül Sitesi', role: 'resident', doorAccess: true, modules: <String, bool>{'door_control': true}),
          ],
        ),
      );
      await access.refresh();
      addTearDown(access.dispose);
      await _pumpHome(t, auth, access);
      expect(_card, findsNothing);
      await _disposeHome(t);
    });
  });

  group('Site Yönetimi', () {
    testWidgets('seçili sitenin özetinde «Kurulum Sihirbazı» düğmesi sihirbazı o site için açar', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth, await _access());
      await tapMenuEntry(t, 'Site Yönetimi');
      await t.pump(const Duration(milliseconds: 600));
      final button = find.byKey(const ValueKey<String>('sites_setup_wizard'));
      expect(button, findsOneWidget);
      await t.ensureVisible(button);
      await t.pump();
      await t.tap(button);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(SiteSetupWizardView), findsOneWidget);
      expect(find.text('Gül Sitesi'), findsWidgets);
      expect(auth.setupStructureCalls, greaterThan(0));
      expect(_inAppBar(find.text('Site Kurulum Sihirbazı')), findsOneWidget);
      await _disposeHome(t);
    });
  });
}
