// Telefon bildirimi (Faz 3b-B) — ana sayfa entegrasyonu (B8/B10): bildirime dokununca (soğuk açılış / arka plan)
// duyuru merkezi menü kapısından açılır; geçersiz yük yok sayılır; ön planda gelen bildirim sistemde gösterilmez,
// duyuru özeti ~20 sn'lik yoklamayı beklemeden HEMEN tazelenir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_read_dialog.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_gate.dart' show LegalConsentBlock;

import 'push_fakes.dart';
import 'screens/announcement_fixtures.dart';

/// Ana kabuğun ihtiyaç duyduğu uçlar boş döner (duyuru uçları sahte servisten).
class _HomeAuth extends AnnouncementFakeAuth {
  _HomeAuth() : super(role: UserRole.apartmentOwner);

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

const PushMessage _tap12 = PushMessage(<String, Object?>{'type': 'announcement', 'announcement_id': '12'});

void main() {
  late PushEventLog events;
  late FakePushGateway gateway;
  late FakePushApi api;
  late PushService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    events = <String>[];
    gateway = FakePushGateway(events);
    api = FakePushApi(events);
    service = PushService(apiFactory: (_) => api, appVersion: () async => '1.0.0', observeLifecycle: false);
    PushService.debugInstance = service;
  });

  tearDown(() async {
    LegalConsentBlock.active.value = false;
    PushService.debugInstance = null;
    await service.dispose();
    await gateway.close();
  });

  Future<_HomeAuth> pumpHome(WidgetTester t) async {
    final auth = _HomeAuth()..inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
    final access = ModuleAccess(
      fetch: () async => MyModulesResult(
        sites: const <MySiteModules>[
          MySiteModules(
            siteCode: 11,
            siteName: 'Gül Sitesi',
            role: 'resident',
            modules: <String, bool>{'door_control': true},
            doorAccess: true,
          ),
        ],
      ),
      isSuperUser: () => false,
    );
    await access.refresh();
    addTearDown(access.dispose);
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(authService: auth, moduleAccess: access),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    return auth;
  }

  Future<void> frames(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> disposeHome(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
  }

  testWidgets('SOĞUK açılış: kapalıyken dokunulan bildirim ana sayfa hazır olunca duyuruyu açar (bir kez)', (t) async {
    gateway.initial = _tap12;
    await service.start(gateway);
    final auth = await pumpHome(t);
    await frames(t);
    expect(find.byType(AnnouncementReadDialog), findsOneWidget);
    expect(auth.myDetailCalls, contains(12));
    expect(find.text('Su kesintisi'), findsWidgets);
    await disposeHome(t);
  });

  testWidgets('ARKA PLAN: onMessageOpenedApp duyuruyu merkezi kapıdan açar; rıza yokken cihaz kaydı YOK', (t) async {
    await service.start(gateway);
    final auth = await pumpHome(t);
    expect(find.byType(AnnouncementReadDialog), findsNothing);
    expect(api.registers, isEmpty, reason: 'izin varsayılan açık olsa da açık rıza olmadan kayıt yok');
    expect(gateway.getTokenCalls, 0);
    gateway.openedController.add(_tap12);
    await frames(t);
    expect(find.byType(AnnouncementReadDialog), findsOneWidget);
    expect(auth.myDetailCalls, contains(12));
    await disposeHome(t);
  });

  testWidgets('geçersiz yük hiçbir şey açmaz', (t) async {
    await service.start(gateway);
    final auth = await pumpHome(t);
    gateway.openedController
      ..add(const PushMessage(<String, Object?>{'type': 'payment', 'announcement_id': '12'}))
      ..add(const PushMessage(<String, Object?>{'type': 'announcement', 'announcement_id': '0'}))
      ..add(const PushMessage(<String, Object?>{'type': 'announcement', 'announcement_id': '12; DROP'}));
    await frames(t);
    expect(find.byType(AnnouncementReadDialog), findsNothing);
    expect(auth.myDetailCalls, isEmpty);
    await disposeHome(t);
  });

  testWidgets('ÖN PLAN: sistem bildirimi / pencere yok; özet 20 sn beklemeden HEMEN tazelenir', (t) async {
    await service.start(gateway);
    final auth = await pumpHome(t);
    await frames(t);
    final before = auth.summaryCalls;
    await t.pump(const Duration(milliseconds: 50));
    expect(auth.summaryCalls, before, reason: 'kontrol: bildirim olmadan yoklama 20 sn bekler');
    gateway.messageController.add(_tap12);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(auth.summaryCalls, greaterThan(before), reason: 'push tetikli refresh()');
    expect(find.byType(AnnouncementReadDialog), findsNothing, reason: 'ön planda kendiliğinden açılmaz');
    await disposeHome(t);
  });

  testWidgets('rıza verilmiş hesapta giriş sonrası cihaz kaydı yapılır', (t) async {
    await pushConsent(5);
    await service.start(gateway);
    await pumpHome(t);
    await frames(t);
    expect(api.registers, hasLength(1));
    await disposeHome(t);
  });

  testWidgets('"Güncellenen koşullar" kapısı açıkken dokunma BEKLER; kapı kalkınca duyuru açılır', (t) async {
    await service.start(gateway);
    final auth = await pumpHome(t);
    LegalConsentBlock.active.value = true;
    gateway.openedController.add(_tap12);
    await frames(t);
    expect(find.byType(AnnouncementReadDialog), findsNothing, reason: 'kapı atlanmaz');
    expect(auth.myDetailCalls, isEmpty);
    LegalConsentBlock.active.value = false;
    await frames(t);
    expect(find.byType(AnnouncementReadDialog), findsOneWidget);
    await disposeHome(t);
  });

  testWidgets('ÖN PLANDA test bildirimi: uygulama içinde "Test bildirimi bu cihaza ulaştı." görünür, yönlendirme yok', (t) async {
    await service.start(gateway);
    await pumpHome(t);
    gateway.messageController.add(const PushMessage(<String, Object?>{'type': 'test'}));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Test bildirimi bu cihaza ulaştı.'), findsOneWidget);
    expect(find.byType(AnnouncementReadDialog), findsNothing);
    await t.pump(const Duration(seconds: 10));
    await disposeHome(t);
  });

  testWidgets('ana sayfa kapanınca açıcı ve oturum bağı sökülür (sonraki dokunuş bekletilir)', (t) async {
    await service.start(gateway);
    await pumpHome(t);
    await disposeHome(t);
    final opened = <int>[];
    gateway.openedController.add(_tap12);
    await t.pump();
    service.bindAnnouncementOpener(opened.add);
    expect(opened, isEmpty, reason: 'oturum bağı yok: bekletilir');
  });
}
