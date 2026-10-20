// Platform modül sistemi Faz 1: ana kabuk (HomePage) entegrasyonu.
//
// - Menü: süper kullanıcı "Modüller" + "Denetim Kaydı", site yöneticisi "Modüller"; seçilince ilgili
//   ekran açılır ve AppBar başlığı değişir; genel yenileme (Yenile) modül durumunu ve ekranı tazeler. İP-1D: bu ayar
//   öğeleri (Modüller, Modül Talepleri, Denetim Kaydı, cihaz ekranları, Bluetooth) çekmecede değil, sağ üstteki
//   dişliden açılan Ayarlar panelindedir ([_openSettings]; panel de bir `Drawer` olduğundan [_tileTitle] ikisinde de
//   çalışır).
// - Panel artık MODÜL VİTRİNİDİR; kapı paneli "Kapılar" kartının (menü öğesi) arkasındadır.
// - Geçiş Kontrol bağlı olunan TÜM sitelerde kapalıyken: kapıyla ilgili menü öğeleri ("Kapılar" dahil) gizlenir, vitrinde
//   kapı kartı ve hızlı "Kapıyı aç" eylemi YOKTUR (eski "modül kapalı" bilgi kartı artık çıkmaz); bireysel ana ekranın kapı
//   dışı bölümleri vitrinin altında kalır. Kapı paneli site seçici yalnız modülü açık siteleri listeler. Süper kullanıcıda
//   Kapılar kartı hep vardır; seçili sitesi kapalıysa bilgi kartı Kapılar sayfasında çıkar. Veri yokken (fail-open) hiçbir
//   şey değişmez.
// - Taşma: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/module_request.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_requests_view.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_control_disabled_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/module_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import 'modules_fixtures.dart';
import '../support/menu_nav.dart';

UserSession _sessionFor(UserRole role) => UserSession(
  id: role == UserRole.superUser ? 1 : 5,
  fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Site Yöneticisi',
  email: 'kullanici@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 'tok',
);

DoorRecord _door(int siteCode) => DoorRecord(
  id: siteCode * 10,
  siteCode: siteCode,
  siteName: 'Site $siteCode',
  doorName: 'Kapı $siteCode',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'AABBCC$siteCode',
  mqttSiteId: siteCode,
  createdAt: DateTime(2026, 1, 1),
);

/// HomePage için sahte servis: rol, siteler ve (varsayılan örnek için) `getMyModules` yanıtı testten
/// sürülür. Modül ekranlarının uçları [ModulesFakeAuth]'tan gelir.
class _HomeModAuth extends ModulesFakeAuth {
  _HomeModAuth({
    this.role = UserRole.siteManager,
    super.sites,
    super.states,
    this.myModules,
  });

  UserRole role;
  bool loggedIn = true;
  MyModulesResult? myModules;
  Object? myModulesError;
  Completer<void>? myModulesGate;
  int myModulesCalls = 0;
  int listMyDoorsCalls = 0;
  final List<int> structureCalls = <int>[];

  /// Sakin yolunda (listMyDoors) dönen kapılar.
  List<DoorRecord> residentDoors = <DoorRecord>[];

  /// Bireysel ana ekranın "Kayıtlı Dairem" bölümü için daireler.
  List<MyApartmentRecord> apartments = <MyApartmentRecord>[];

  @override
  UserSession? get session => loggedIn ? _sessionFor(role) : null;

  @override
  bool get isLoggedIn => loggedIn;

  /// Bireysel kullanıcının başvuru durumu (`GET /membership/site-applications/mine`): sunucu gibi "hiç başvuru
  /// yok". Durum alınamazsa "Site Kurmak İçin Başvur" eylemi dürüstçe pasif kalır; bu test dosyası başvuru
  /// akışını değil kapalı modülde ana ekranın erişilebilirliğini sınar, o yüzden sahte sunucu boş durumu döner.
  @override
  Future<MySiteApplications> getMySiteApplications() async => const MySiteApplications();

  /// Oturum değişimi (çıkış / yeni giriş / rol değişimi) ve dinleyicilere bildirim.
  void changeSession({UserRole? role, bool? loggedIn}) {
    if (role != null) this.role = role;
    if (loggedIn != null) this.loggedIn = loggedIn;
    notifyListeners();
  }

  @override
  Future<MyModulesResult> getMyModules() async {
    myModulesCalls++;
    await myModulesGate?.future;
    final error = myModulesError;
    if (error != null) throw error;
    return myModules ?? const MyModulesResult(scope: 'all');
  }

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    structureCalls.add(siteCode);
    final site = sites.firstWhere((s) => s.id == siteCode, orElse: () => sites.first);
    return (
      SiteStructureRecord(
        site: site,
        blocks: const <SiteBlockRecord>[],
        apartments: const <ApartmentRecord>[],
        doors: <DoorRecord>[_door(siteCode)],
      ),
      null,
    );
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    listMyDoorsCalls++;
    return (List<DoorRecord>.of(residentDoors), null);
  }

  // Bireysel ana ekran (IndividualHomeView) uçları.
  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async =>
      <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (List<MyApartmentRecord>.of(apartments), null);

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

/// Sesli komut servisi sahtesi: konuşulanlar, durdurma/başlatma ve aday kapı güncellemeleri kaydedilir.
class _HomeVoice extends ChangeNotifier implements VoiceDoorService {
  bool listening = false;
  final List<String> spoken = <String>[];
  int startCalls = 0;
  int stopCalls = 0;
  final List<List<DoorRecord>?> candidateUpdates = <List<DoorRecord>?>[];

  @override
  VoiceStatus get status => listening ? VoiceStatus.listening : VoiceStatus.idle;

  @override
  String get recognizedWords => '';

  @override
  String get feedbackText => '';

  @override
  bool get isListening => listening;

  @override
  bool get handsFreeAutoListen => true;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> startListening({List<DoorRecord>? candidateDoors}) async {
    startCalls++;
    listening = true;
    notifyListeners();
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    listening = false;
    notifyListeners();
  }

  @override
  void updateCandidateDoors(List<DoorRecord>? doors) => candidateUpdates.add(doors);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MySiteModules _my(
  int code, {
  required bool door,
  String role = 'manager',
  bool access = true,
}) =>
    MySiteModules(
      siteCode: code,
      siteName: 'Site $code',
      role: role,
      doorAccess: access,
      modules: <String, bool>{'door_control': door},
    );

Future<ModuleAccess> _access(
  List<MySiteModules> sites, {
  bool superUser = false,
}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites),
    isSuperUser: () => superUser,
  );
  await access.refresh();
  addTearDown(access.dispose);
  return access;
}

Future<void> _pumpHome(
  WidgetTester t,
  _HomeModAuth auth, {
  ModuleAccess? access,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  VoiceDoorService? voice,
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
      home: HomePage(authService: auth, moduleAccess: access, voiceDoorService: voice),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Yoklama zamanlayıcıları kalmasın.
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
  t.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// İP-1D: sağ üstteki dişliden Ayarlar panelini açar (ayar öğeleri burada).
Future<void> _openSettings(WidgetTester t) => openSettingsPanel(t);

/// Ayarlar panelini kapatır.
Future<void> _closeSettings(WidgetTester t) => closeMenuPanels(t);

/// Çekmecedeki öğeye dokunur. Bulucu çekmeceyle SINIRLIDIR: Panel modül vitrininde de aynı adlı kartlar vardır.
Future<void> _tapMenu(WidgetTester t, String label) async {
  // İP-1D: öğe çekmecede yoksa (ayar öğesi) sağ üstteki dişliden açılan Ayarlar panelinde aranır.
  final tile = await findMenuEntry(t, label);
  await t.ensureVisible(tile);
  await t.pump();
  await t.tap(tile);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Panel vitrinindeki "Kapılar" kartına dokunur: kapı paneli (DashboardView / bireysel ana ekran) bir dokunuş uzaktadır.
Future<void> _openDoorPanel(WidgetTester t) async {
  final card = find.byKey(const ValueKey<String>('panel_kart_kapilar'));
  await t.ensureVisible(card);
  await t.pump();
  await t.tap(card);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _inAppBar(Finder f) =>
    find.descendant(of: find.byType(AppBar), matching: f);

Finder _tileTitle(String title) => find.descendant(
  of: find.byType(Drawer),
  matching: find.text(title),
);

void main() {
  group('Menü: Modüller / Denetim Kaydı', () {
    testWidgets('süper kullanıcı: "Modüller" ve "Denetim Kaydı" Ayarlar panelinde (dişli); seçilince ekranlar açılır', (t) async {
      final auth = _HomeModAuth(role: UserRole.superUser);
      await _pumpHome(t, auth);

      await _openDrawer(t);
      expect(_tileTitle('Modüller'), findsNothing, reason: 'ayar öğesi çekmecede değil');
      await _openSettings(t);
      expect(_tileTitle('Modüller'), findsOneWidget);
      expect(_tileTitle('Denetim Kaydı'), findsOneWidget);
      expect(_tileTitle('Kayıtlı Cihazlar').evaluate().isEmpty, isTrue,
          reason: 'süper kullanıcıda öğe adı "Şirket Cihaz Envanteri"dir');
      expect(_tileTitle('Şirket Cihaz Envanteri'), findsOneWidget);
      // Süper kullanıcının çekmecesi uzundur (Finans, Belgeler ... eklendikçe uzar): öğe görünür alana kaydırılır.
      await t.ensureVisible(find.text('Modüller').last);
      await t.pump();
      await t.tap(find.text('Modüller').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModulesView), findsOneWidget);
      expect(_inAppBar(find.text('Modüller')), findsOneWidget);
      expect(auth.getModulesCalls, isNotEmpty);

      await _tapMenu(t, 'Denetim Kaydı');
      expect(find.byType(AuditLogView), findsOneWidget);
      expect(_inAppBar(find.text('Denetim Kaydı')), findsOneWidget);
      expect(auth.auditCalls, isNotEmpty);
      await _disposeHome(t);
    });

    testWidgets('site yöneticisi: yalnız "Modüller" (Denetim Kaydı YOK); çekmece sırası Site Yönetimi, Modüller', (t) async {
      final auth = _HomeModAuth();
      await _pumpHome(t, auth);

      await _openSettings(t);
      expect(_tileTitle('Modüller'), findsOneWidget);
      expect(_tileTitle('Denetim Kaydı'), findsNothing);
      await _closeSettings(t);
      // Sıra kuralı menü LİSTESİNDE (vitrin sırası); çekmece öğeleri başlıklar altında gruplar.
      await _openDrawer(t);
      final titles = menuListTitles(t);
      expectUnderDrawerHeader(t, 'Kişiler', 'Daireler');
      expect(
        titles.indexOf('Kişiler'),
        titles.indexOf('Site Yönetimi') + 1,
      );
      // Platform Faz 3a: "Duyurular" "Kişiler"in hemen altına eklenir, "Modüller" onun altındadır.
      expect(
        titles.indexOf('Duyurular'),
        titles.indexOf('Kişiler') + 1,
      );
      expect(
        titles.indexOf('Modüller'),
        titles.indexOf('Duyurular') + 1,
      );
      await _disposeHome(t);
    });

    testWidgets('Modüller ekranında genel yenileme (AppBar Yenile) ekranı ve modül durumunu tazeler', (t) async {
      final auth = _HomeModAuth();
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Modüller');
      final sitesBefore = auth.listSitesCalls;
      final modulesBefore = auth.getModulesCalls.length;
      final myBefore = auth.myModulesCalls;

      // AppBar'daki genel "Yenile" (gövdedeki ekran içi yenile düğmesi DEĞİL).
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(auth.listSitesCalls, greaterThan(sitesBefore));
      expect(auth.getModulesCalls.length, greaterThan(modulesBefore));
      expect(auth.myModulesCalls, greaterThan(myBefore),
          reason: 'her genel yenilemede getMyModules çekilir');
      await _disposeHome(t);
    });

    testWidgets('Denetim Kaydı ekranında genel yenileme kayıtları yeniden çeker', (t) async {
      final auth = _HomeModAuth(role: UserRole.superUser);
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Denetim Kaydı');
      final before = auth.auditCalls.length;

      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.auditCalls.length, greaterThan(before));
      await _disposeHome(t);
    });

    testWidgets('varsayılan örnek (enjeksiyonsuz): sunucu "kapalı" derse vitrinde Kapılar kartı çıkmaz', (t) async {
      final auth = _HomeModAuth(
        myModules: MyModulesResult(sites: <MySiteModules>[_my(11, door: false)]),
      );
      await _pumpHome(t, auth);
      expect(auth.myModulesCalls, greaterThanOrEqualTo(1));
      // Panel = modül vitrini: Geçiş Kontrol kapalıyken kapı kartı hiç çıkmaz (bilgi kartı artık yok).
      expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      await _openDrawer(t);
      expect(_tileTitle('Kapılar'), findsNothing);
      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('varsayılan örnek: sayfa girişte getMyModules çeker; yoklama aralığında tazeler; kapanınca durur', (t) async {
      final auth = _HomeModAuth();
      await _pumpHome(t, auth);
      expect(auth.myModulesCalls, greaterThanOrEqualTo(1));
      final afterOpen = auth.myModulesCalls;

      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(auth.myModulesCalls, greaterThan(afterOpen),
          reason: 'AdaptivePoller kısa aralıkla tazeler');

      await _disposeHome(t);
      final afterClose = auth.myModulesCalls;
      await t.pump(const Duration(seconds: 120));
      expect(auth.myModulesCalls, afterClose, reason: 'sayfa kapanınca yoklama durur');
    });
  });

  group('Geçiş Kontrol kapalı (tüm bağlı sitelerde)', () {
    // Panel = modül vitrini: Geçiş Kontrol kapalıyken (bağlı TÜM sitelerde) "Kapılar" öğesi çekmecede de vitrinde de yoktur;
    // eski "modül kapalı" bilgi kartı yerine kart hiç çizilmez (fail-closed). Modüller ekranına vitrindeki "Modüller" kartı götürür.
    testWidgets('site yöneticisi: Kapılar kartı yok + gizli menüler; Modüller kartı Modüller ekranını açar', (t) async {
      final auth = _HomeModAuth();
      final access = await _access(<MySiteModules>[_my(11, door: false), _my(12, door: false)]);
      await _pumpHome(t, auth, access: access);

      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byType(DashboardView), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_kart_moduller')), findsOneWidget);

      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsNothing);
      expect(_tileTitle('Bluetooth ile Wi-Fi Kur'), findsNothing);
      expect(_tileTitle('Modüller'), findsOneWidget);
      await _closeSettings(t);
      await _openDrawer(t);
      expect(_tileTitle('Panel'), findsOneWidget, reason: 'Panel kalır');
      expect(_tileTitle('Kapılar'), findsNothing);
      expect(_tileTitle('Site Yönetimi'), findsOneWidget);
      expect(_tileTitle('Daireye Katıl & Cihaz Ekle'), findsOneWidget);
      expect(
        t.widget<YanMenu>(find.byType(YanMenu)).hiddenItems,
        <SirketMenuItem>{
          SirketMenuItem.kapilar,
          SirketMenuItem.kayitliCihazlar,
          SirketMenuItem.bluetoothWifiKur,
          SirketMenuItem.ellerSerbest,
        },
      );
      await t.tap(_tileTitle('Panel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      // Vitrindeki Modüller kartı: Modüller ekranı açılır.
      final card = find.byKey(const ValueKey<String>('panel_kart_moduller'));
      await t.ensureVisible(card);
      await t.tap(card);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModulesView), findsOneWidget);
      expect(_inAppBar(find.text('Modüller')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('daire sakini: Kapılar kartı ve hızlı "Kapıyı aç" yok; Eller Serbest gizli; öteki hızlı işlemler durur', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      final access = await _access(<MySiteModules>[
        MySiteModules(
          siteCode: 11,
          siteName: 'Site 11',
          role: 'resident',
          modules: const <String, bool>{'door_control': false, 'work_tracking': true},
        ),
      ]);
      await _pumpHome(t, auth, access: access);

      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsNothing);
      expect(find.text('Kapıyı aç'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_taleplerim')), findsOneWidget);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_ikincil_ellerSerbest')), findsNothing);

      await _openDrawer(t);
      expect(_tileTitle('Panel'), findsOneWidget);
      expect(_tileTitle('Kapılar'), findsNothing);
      expect(_tileTitle('Daireye Katıl & Cihaz Ekle'), findsOneWidget);
      await _openSettings(t);
      expect(_tileTitle('Eller Serbest & Kestirmeler'), findsNothing);
      expect(_tileTitle('Profilim'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bir site bile açıksa: normal Panel; site seçici yalnız modülü AÇIK siteleri listeler', (t) async {
      final auth = _HomeModAuth(
        sites: <SiteRecord>[mdSite(11, 'Kapalı Site'), mdSite(12, 'Açık Site')],
      );
      final access = await _access(<MySiteModules>[_my(11, door: false), _my(12, door: true)]);
      await _pumpHome(t, auth, access: access);

      expect(find.byType(DoorControlDisabledCard), findsNothing);
      await _openDoorPanel(t);
      final dashboard = t.widget<DashboardView>(find.byType(DashboardView));
      expect(dashboard.sites.map((s) => s.id), <int>[12]);
      expect(dashboard.selectedSite?.id, 12);
      expect(dashboard.doors.map((d) => d.siteCode), everyElement(12),
          reason: 'Panel kapıları yalnız modülü açık sitenin kapılarıdır');
      expect(dashboard.doors, isNotEmpty);

      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsOneWidget);
      expect(_tileTitle('Bluetooth ile Wi-Fi Kur'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı modüllerden etkilenmez (Panel + tüm menüler)', (t) async {
      final auth = _HomeModAuth(role: UserRole.superUser);
      final access = await _access(<MySiteModules>[_my(11, door: false)], superUser: true);
      await _pumpHome(t, auth, access: access);

      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget,
          reason: 'süper kullanıcıda Kapılar kartı her zaman vardır');
      await _openDrawer(t);
      expect(_tileTitle('Kapılar'), findsOneWidget);
      expect(t.widget<YanMenu>(find.byType(YanMenu)).hiddenItems, isEmpty);
      await _openSettings(t);
      expect(_tileTitle('Şirket Cihaz Envanteri'), findsOneWidget);
      expect(_tileTitle('Bluetooth ile Wi-Fi Kur'), findsOneWidget);
      expect(t.widget<YanMenuAyarlar>(find.byType(YanMenuAyarlar)).hiddenItems, isEmpty);
      await _disposeHome(t);
    });

    testWidgets('fail-open: modül verisi alınamazsa her şey açık (Kapılar kartı var, kapı paneli açılır, menüler tam)', (t) async {
      final auth = _HomeModAuth()..myModulesError = ApiException('Sunucuya ulaşılamadı.');
      await _pumpHome(t, auth);

      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      expect(find.byType(DashboardView), findsOneWidget);
      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsOneWidget);
      expect(_tileTitle('Bluetooth ile Wi-Fi Kur'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('canlı: yönetici kapatınca Kapılar kartı kalkar (kapı panelindeyken vitrine düşer), açınca geri gelir', (t) async {
      var door = true;
      final access = ModuleAccess(
        fetch: () async => MyModulesResult(sites: <MySiteModules>[_my(11, door: door)]),
      );
      addTearDown(access.dispose);
      await access.refresh();
      final auth = _HomeModAuth(sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')]);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      expect(find.byType(DashboardView), findsOneWidget);

      // Kapı panelindeyken modül kapanır: erişimi kalkan sayfa kare bile kalmadan vitrine düşer (bilgi kartı da yok).
      door = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(DashboardView), findsNothing);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(t.takeException(), isNull);

      door = true;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byType(DashboardView), findsOneWidget);
      expect(
        t.widget<DashboardView>(find.byType(DashboardView)).sites.map((s) => s.id),
        <int>[11],
        reason: 'yeniden açılan site kapı paneli listesine geri döner',
      );
      await _disposeHome(t);
    });

    testWidgets('site yöneticisi Modüller ekranında anahtar görmez (Faz 1.1); süper kullanıcı kapatınca menü yöneticide sunucudan okunur', (t) async {
      // Gerçek ModuleAccess, sahte sunucu durumunu okur: süper kullanıcı kapatınca states güncellenir.
      late final _HomeModAuth auth;
      auth = _HomeModAuth(sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')]);
      final access = ModuleAccess(
        fetch: () async {
          final door = auth.states[11]!.module('door_control')!.enabled;
          return MyModulesResult(sites: <MySiteModules>[_my(11, door: door)]);
        },
      );
      addTearDown(access.dispose);
      await access.refresh();
      await _pumpHome(t, auth, access: access);
      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsOneWidget);
      await _closeSettings(t);

      await _tapMenu(t, 'Modüller');
      expect(doorModuleSwitch, findsNothing, reason: 'site yöneticisi modülü kendi kapatamaz');
      expect(auth.setCalls, isEmpty);

      // Süper kullanıcı başka yerden kapattı: yönetici yenileyince menü güncellenir.
      auth.states[11] = mdState(11, 'Gül Sitesi', door: false, superView: false);
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsNothing,
          reason: 'kapıyla ilgili öğeler genel yenilemeyle gizlenir');
      expect(_tileTitle('Modüller'), findsOneWidget);
      await _closeSettings(t);
      expect(find.text('Modül Talep Et'), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('Modül Talepleri (süper kullanıcı, Faz 1.1)', () {
    _HomeModAuth superAuth({int pending = 2}) {
      final auth = _HomeModAuth(role: UserRole.superUser, sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')]);
      auth.adminRequests = <ModuleRequest>[
        for (var i = 1; i <= pending; i++) mdRequest(i),
        mdRequest(50, status: 'approved', decidedBy: 'Süper Yönetici'),
      ];
      return auth;
    }

    final badge = find.byKey(const ValueKey<String>('yan_menu_rozet'));

    testWidgets('Ayarlar panelinde yalnız süper kullanıcıda; Modüller\'in altında, bekleyen sayısı rozetle (pending_count)', (t) async {
      final auth = superAuth(pending: 2);
      await _pumpHome(t, auth);

      await _openSettings(t);
      expect(_tileTitle('Modül Talepleri'), findsOneWidget);
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('2')),
        findsOneWidget,
      );
      // Sayı pending_count ile çekilir (limit 1: yalnız sayaç için).
      expect(auth.adminCalls.first.status, 'pending');
      expect(auth.adminCalls.first.limit, 1);
      final tiles = find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile));
      final titles = <String>[
        for (var i = 0; i < tiles.evaluate().length; i++)
          ((t.widget<ListTile>(tiles.at(i))).title! as Text).data!,
      ];
      expect(titles.indexOf('Modül Talepleri'), titles.indexOf('Modüller') + 1);
      await _disposeHome(t);
    });

    testWidgets('Modüller ekranında anahtar işleminden sonra rozet de tazelenir (sunucu bekleyen talebi otomatik onayladı)', (t) async {
      final auth = superAuth(pending: 2);
      await _pumpHome(t, auth);
      await _openSettings(t);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('2')),
        findsOneWidget,
      );
      await _closeSettings(t);

      await _tapMenu(t, 'Modüller');
      final callsBefore = auth.adminCalls.length;
      // Süper kullanıcı modülü doğrudan açınca sunucu o sitedeki bekleyen talebi "onaylandı"ya çevirir.
      auth.adminRequests = <ModuleRequest>[
        mdRequest(1),
        mdRequest(2, status: 'approved', decidedBy: 'Süper Yönetici'),
      ];
      await t.ensureVisible(doorModuleSwitch);
      await t.tap(doorModuleSwitch);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await t.tap(find.text('Kapat'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));

      expect(auth.setCalls, hasLength(1));
      expect(auth.adminCalls.length, greaterThan(callsBefore),
          reason: 'anahtar işleminden sonra bekleyen talep sayısı yeniden çekilir');
      await _openSettings(t);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('1')),
        findsOneWidget,
      );
      await _disposeHome(t);
    });

    testWidgets('bekleyen yoksa rozet yok; site yöneticisinde öğe hiç yok', (t) async {
      final none = superAuth(pending: 0);
      await _pumpHome(t, none);
      await _openSettings(t);
      expect(_tileTitle('Modül Talepleri'), findsOneWidget);
      expect(badge, findsNothing);
      await _disposeHome(t);

      final manager = _HomeModAuth();
      await _pumpHome(t, manager);
      await _openSettings(t);
      expect(_tileTitle('Modül Talepleri'), findsNothing);
      expect(manager.adminCalls, isEmpty, reason: 'yönetici için talep sayacı çekilmez');
      await _disposeHome(t);
    });

    testWidgets('öğeye dokununca ekran açılır; AppBar başlığı; Onayla -> liste ve ROZET hemen güncellenir', (t) async {
      final auth = superAuth(pending: 2);
      await _pumpHome(t, auth);

      await _tapMenu(t, 'Modül Talepleri');
      expect(find.byType(ModuleRequestsView), findsOneWidget);
      expect(_inAppBar(find.text('Modül Talepleri')), findsOneWidget);
      expect(find.byType(ModuleRequestCard), findsNWidgets(2));

      await t.ensureVisible(find.text('Onayla').first);
      await t.tap(find.text('Onayla').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await t.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Onayla')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      expect(auth.decideCalls.single.approve, isTrue);
      expect(find.byType(ModuleRequestCard), findsNWidgets(1));

      await _openSettings(t);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('1')),
        findsOneWidget,
        reason: 'karardan sonra çekmece rozeti sunucudan hemen yeniden okunur',
      );
      await _disposeHome(t);
    });

    testWidgets('genel yenileme (AppBar Yenile) listeyi ve rozeti tazeler', (t) async {
      final auth = superAuth(pending: 1);
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Modül Talepleri');
      final before = auth.adminCalls.length;

      auth.adminRequests = <ModuleRequest>[mdRequest(1), mdRequest(2), mdRequest(3)];
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      expect(auth.adminCalls.length, greaterThan(before));
      expect(find.byType(ModuleRequestCard), findsNWidgets(3));
      await _openSettings(t);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('3')),
        findsOneWidget,
      );
      await _disposeHome(t);
    });

    testWidgets('rozet arka planda AdaptivePoller ile tazelenir (yeni talep gelir)', (t) async {
      final auth = superAuth(pending: 1);
      await _pumpHome(t, auth);
      await _openSettings(t);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('1')),
        findsOneWidget,
      );
      await _closeSettings(t);

      auth.adminRequests = <ModuleRequest>[mdRequest(1), mdRequest(2), mdRequest(3), mdRequest(4)];
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      await _openSettings(t);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Modül Talepleri'), matching: find.text('4')),
        findsOneWidget,
      );
      await _disposeHome(t);
    });

    testWidgets('talep sayacı çekilemezse rozet gösterilmez ve menü/Panel bozulmaz', (t) async {
      final auth = superAuth(pending: 3)..adminError = ApiException('Sunucuya ulaşılamadı.');
      await _pumpHome(t, auth);
      expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_odak_bar')), findsNothing,
          reason: 'sayaç alınamadıysa odak barı (bekleyen sayı) çizilmez');
      await _openSettings(t);
      expect(_tileTitle('Modül Talepleri'), findsOneWidget);
      expect(badge, findsNothing);
      await _disposeHome(t);
    });

    testWidgets('çıkışta rozet sayısı temizlenir (yeni kullanıcıya sızmaz)', (t) async {
      final auth = superAuth(pending: 2);
      late ModuleAccess access;
      access = ModuleAccess(
        fetch: () => auth.getMyModules(),
        isSuperUser: () => auth.session?.role == UserRole.superUser,
        fetchPendingCount: () async =>
            (await auth.listAdminModuleRequests(status: 'pending', limit: 1)).pendingCount,
      );
      addTearDown(access.dispose);
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AnimatedBuilder(
            animation: auth,
            builder: (context, _) => auth.session == null
                ? const Scaffold(body: Text('Giriş Ekranı'))
                : HomePage(authService: auth, moduleAccess: access),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(access.pendingRequestCount, 2);

      auth.changeSession(loggedIn: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Giriş Ekranı'), findsOneWidget);
      expect(access.pendingRequestCount, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  });

  group('door_access: yalnız kurul/görevli bağı olan kullanıcı', () {
    testWidgets('yönetici rolünde Geçiş Kontrol kapalı olsa bile kapalı SAYILMAZ: Kapılar kartı, kapı paneli ve menüler değişmez', (t) async {
      // Yönetici rolü yeni kuraldan (daire sakini rolünde kapı erişimi yoksa kapı öğeleri gizlenir) ETKİLENMEZ.
      final auth = _HomeModAuth();
      final access = await _access(<MySiteModules>[
        _my(11, door: false, role: 'board_member', access: false),
      ]);
      await _pumpHome(t, auth, access: access);

      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      expect(find.byType(DashboardView), findsOneWidget);
      await _openDrawer(t);
      expect(t.widget<YanMenu>(find.byType(YanMenu)).hiddenItems, isEmpty);
      await _openSettings(t);
      expect(_tileTitle('Kayıtlı Cihazlar'), findsOneWidget);
      expect(_tileTitle('Bluetooth ile Wi-Fi Kur'), findsOneWidget);
      await _disposeHome(t);
    });

    // yetki-1 / kapi-1 / tasarim-1: daire sakini rolünde kapı erişimi olan sitesi yok VE sunucu kapı vermedi (kapı listesi
    // boş): kapı açamayan görevliye / dış kurul üyesine "Kapılar", "Kapıyı aç", Eller Serbest ve sesli kapı açma vaat
    // edilmez (Geçiş Kontrol açık da kapalı da olsa). Sahte listMyDoors bu hesaplara sunucu gibi BOŞ liste verir.
    for (final (role, label) in <(String, String)>[('board_member', 'kurul üyesi'), ('staff', 'görevli')]) {
      for (final door in <bool>[true, false]) {
        testWidgets('daire sakini rolünde yalnız $label bağı, Geçiş Kontrol ${door ? 'AÇIK' : 'KAPALI'}: kapı öğeleri YOK', (t) async {
          final auth = _HomeModAuth(role: UserRole.apartmentOwner);
          expect(auth.residentDoors, isEmpty, reason: 'ön koşul: sunucu bu hesaba kapı vermez');
          final access = await _access(<MySiteModules>[_my(11, door: door, role: role, access: false)]);
          final voice = _HomeVoice();
          await _pumpHome(t, auth, access: access, voice: voice);

          expect(auth.listMyDoorsCalls, greaterThanOrEqualTo(1), reason: 'kapı listesi okundu (boş)');
          expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
          expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
          expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsNothing);
          expect(find.text('Kapıyı aç'), findsNothing);
          expect(find.byKey(const ValueKey<String>('panel_ikincil_ellerSerbest')), findsNothing);
          expect(find.byType(DashboardView), findsNothing);
          await _openDrawer(t);
          expect(_tileTitle('Kapılar'), findsNothing);
          expect(_tileTitle('Eller Serbest & Kestirmeler'), findsNothing);
          expect(_tileTitle('Sesli Kapı Açma'), findsNothing, reason: 'kapı komutları da yok');
          expect(_tileTitle('Daireye Katıl & Cihaz Ekle'), findsOneWidget, reason: 'öteki öğeler durur');
          // Sesli asistan da susar: otomatik dinlemeyi kapatacak "Eller Serbest" gizliyken "Tanımlı bir kapı
          // bulunamadı." denmez, dinleme başlamaz.
          expect(voice.spoken, isEmpty, reason: 'kapı öğeleri gizliyken sesli asistan konuşmaz');
          expect(voice.startCalls, 0);
          await _disposeHome(t);
        });
      }
    }

    testWidgets('daire sakini rolünde kurul bağı var ama sunucu kapı verdi (kapı listesi dolu): Kapılar kalır', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner)..residentDoors = <DoorRecord>[_door(11)];
      final access = await _access(<MySiteModules>[_my(11, door: true, role: 'board_member', access: false)]);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('daire sakini rolünde modül verisi hiç gelmezse (fail-open) Kapılar eskisi gibi durur', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner)..myModulesError = ApiException('Sunucuya ulaşılamadı.');
      await _pumpHome(t, auth);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kapı erişimli site kapalı + kurul sitesi açık: kapalı kararı kapı erişimli siteden gelir (Kapılar kartı yok)', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      final access = await _access(<MySiteModules>[
        _my(11, door: false, role: 'resident'),
        _my(12, door: true, role: 'board_member', access: false),
      ]);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Sesli asistan: kapalı modülde ve kapı erişimi yokken (Kapılar gizli) sessiz (kapı yok uyarısı yok)', () {
    testWidgets('daire sakini, modül kapalı (Kapılar kartı yok): uyarı konuşulmaz, dinleme durdurulur, aday kapılar temizlenir; yenilemede de sessiz', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      final access = await _access(<MySiteModules>[_my(11, door: false, role: 'resident')]);
      final voice = _HomeVoice()..listening = true;
      await _pumpHome(t, auth, access: access, voice: voice);

      expect(auth.listMyDoorsCalls, greaterThanOrEqualTo(1));
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing, reason: 'modül kapalı: Kapılar kartı yok');
      expect(voice.spoken, isEmpty, reason: '"Tanımlı bir kapı bulunamadı." söylenmemeli');
      expect(voice.stopCalls, greaterThanOrEqualTo(1), reason: 'sürmekte olan dinleme durdurulur');
      expect(voice.startCalls, 0);
      expect(voice.candidateUpdates.any((l) => l != null && l.isEmpty), isTrue,
          reason: 'sesli komut servisindeki eski kapı listesi boş listeyle temizlenir');

      final callsBefore = auth.listMyDoorsCalls;
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.listMyDoorsCalls, greaterThan(callsBefore));
      expect(voice.spoken, isEmpty);
      await _disposeHome(t);
    });

    // Kapı erişimi olmayan daire sakini hesabında (yalnız kurul / site üyeliği bağı; sunucu kapı vermez) "Kapılar" ve
    // otomatik dinlemeyi kapatacak tek yol olan "Eller Serbest" gizlidir: asistan da kapalı modüldeki gibi susar.
    for (final (role, label) in <(String, String)>[('board_member', 'kurul üyesi'), ('resident', 'yalnız site üyeliği')]) {
      testWidgets(
          'daire sakini rolünde kapı erişimi yok ($label, Geçiş Kontrol AÇIK, Kapılar gizli): uyarı konuşulmaz, dinleme '
          'durdurulur, aday kapılar temizlenir; yenilemede de sessiz', (t) async {
        final auth = _HomeModAuth(role: UserRole.apartmentOwner);
        expect(auth.residentDoors, isEmpty, reason: 'ön koşul: sunucu bu hesaba kapı vermez');
        final access = await _access(<MySiteModules>[_my(11, door: true, role: role, access: false)]);
        final voice = _HomeVoice()..listening = true;
        await _pumpHome(t, auth, access: access, voice: voice);

        expect(auth.listMyDoorsCalls, greaterThanOrEqualTo(1));
        expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing, reason: 'Kapılar gizli');
        expect(find.byKey(const ValueKey<String>('panel_ikincil_ellerSerbest')), findsNothing, reason: 'Eller Serbest gizli');
        expect(voice.spoken, isEmpty, reason: '"Tanımlı bir kapı bulunamadı." söylenmemeli');
        expect(voice.stopCalls, greaterThanOrEqualTo(1), reason: 'sürmekte olan dinleme durdurulur');
        expect(voice.startCalls, 0);
        expect(voice.candidateUpdates.any((l) => l != null && l.isEmpty), isTrue,
            reason: 'sesli komut servisindeki eski kapı listesi boş listeyle temizlenir');

        final callsBefore = auth.listMyDoorsCalls;
        await t.tap(_inAppBar(find.byTooltip('Yenile')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(auth.listMyDoorsCalls, greaterThan(callsBefore));
        expect(voice.spoken, isEmpty);
        expect(voice.startCalls, 0);
        await _disposeHome(t);
      });
    }

    testWidgets('açılış yarışı: modül verisi sonradan gelir ve kapı erişimi yok çıkarsa (Kapılar gizli) hiç konuşulmaz',
        (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      final gate = Completer<MyModulesResult>();
      final access = ModuleAccess(fetch: () => gate.future);
      addTearDown(access.dispose);
      final voice = _HomeVoice();
      await _pumpHome(t, auth, access: access, voice: voice);
      expect(voice.spoken, isEmpty, reason: 'modül durumu beklenirken konuşulmaz');

      gate.complete(MyModulesResult(sites: <MySiteModules>[_my(11, door: true, role: 'board_member', access: false)]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(voice.spoken, isEmpty);
      expect(voice.startCalls, 0);
      await _disposeHome(t);
    });

    // Vitrin son doğrulamasından (c): olumlu yol. Kapısı ve kapıya atanmış cihazı olan sakinde (Geçiş Kontrol açık, kapı
    // erişimi var) otomatik sesli dinleme BAŞLAR, aday kapılar verilir ve hiçbir uyarı konuşulmaz.
    testWidgets('kapısı ve cihazı olan sakinde sesli dinleme başlar (aday kapılarla); uyarı konuşulmaz', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner)..residentDoors = <DoorRecord>[_door(11)];
      expect(auth.residentDoors.single.assignedDeviceUid, isNotEmpty, reason: 'ön koşul: kapıya cihaz atanmış');
      final access = await _access(<MySiteModules>[_my(11, door: true, role: 'resident')]);
      final voice = _HomeVoice();
      await _pumpHome(t, auth, access: access, voice: voice);

      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget, reason: 'Kapılar erişilebilir');
      expect(voice.startCalls, 1, reason: 'otomatik dinleme bir kez başlatılır');
      expect(voice.listening, isTrue);
      expect(voice.spoken, isEmpty, reason: '"kapı bulunamadı" / "cihaz atanmamış" uyarısı yok');
      expect(voice.stopCalls, 0);

      // Yenileme dinlemeyi ikinci kez başlatmaz (zaten dinliyor).
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(voice.startCalls, 1);
      expect(voice.spoken, isEmpty);
      await _disposeHome(t);
    });

    testWidgets('modül AÇIK ve kapı yok: uyarı eskisi gibi konuşulur (kontrol)', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      final access = await _access(<MySiteModules>[_my(11, door: true, role: 'resident')]);
      final voice = _HomeVoice();
      await _pumpHome(t, auth, access: access, voice: voice);
      expect(voice.spoken, contains('Tanımlı bir kapı bulunamadı.'));
      await _disposeHome(t);
    });

    testWidgets('açılış yarışı: modül durumu henüz gelmediyse önce beklenir; kapalı çıkarsa hiç konuşulmaz (Kapılar kartı yok)', (t) async {
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      final gate = Completer<MyModulesResult>();
      final access = ModuleAccess(fetch: () => gate.future);
      addTearDown(access.dispose);
      final voice = _HomeVoice();
      await _pumpHome(t, auth, access: access, voice: voice);
      expect(voice.spoken, isEmpty, reason: 'modül durumu beklenirken konuşulmaz');

      gate.complete(MyModulesResult(sites: <MySiteModules>[_my(11, door: false, role: 'resident')]));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(voice.spoken, isEmpty);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Kapalı modül: kapı dışı bölümler erişilebilir kalır (AGENTS kural 2)', () {
    MyApartmentRecord apartment() => const MyApartmentRecord(
      apartmentId: 1,
      unitLabel: 'Daire 5',
      blockName: 'A Blok',
      siteCode: 11,
      siteName: 'Gül Sitesi',
      apartmentRole: 'APARTMENT_ADMIN',
    );

    // Panel = modül vitrini: Geçiş Kontrol kapalıyken "Kapılar" öğesi yoktur; bireysel ana ekranın kapı dışı bölümleri
    // (dairelerim, başvurular, cihazlar, hızlı işlemler) kaybolmasın diye vitrinin ALTINDA gösterilir (kapı kartı olmadan).
    testWidgets('bireysel kullanıcı (dairesiz): vitrin + karşılama ve hızlı işlemler erişilebilir; Kapılar kartı yok', (t) async {
      final auth = _HomeModAuth(role: UserRole.individual);
      final access = await _access(<MySiteModules>[_my(11, door: false, role: 'resident')]);
      await _pumpHome(t, auth, access: access);
      await t.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(find.text('Site Sakini Olarak Devam Et'), findsOneWidget);
      // Site başvurusu akışı: cihaz sahiplenmek yönetici yapmaz; "Site Kurmak İçin Başvur" birincil eylemdir.
      expect(find.text('Site Kurmak İçin Başvur'), findsOneWidget);
      expect(find.text('Cihaz Ekle'), findsOneWidget);
      expect(find.byType(DoorControlDisabledCard), findsOneWidget);
      expect(find.text('Modüller Ekranını Aç'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: Kayıtlı Dairem görünür; üstte kısa bilgi, tam kart yok', (t) async {
      final auth = _HomeModAuth(role: UserRole.individual)..apartments = [apartment()];
      final access = await _access(<MySiteModules>[_my(11, door: false, role: 'resident')]);
      await _pumpHome(t, auth, access: access);
      await t.pump(const Duration(milliseconds: 600));

      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(find.text('Kayıtlı Dairem'), findsOneWidget);
      expect(find.byType(DoorControlDisabledCard), findsOneWidget);
      expect(find.textContaining('Geçiş Kontrol modülü kapalı'), findsOneWidget);
      expect(find.text('Modüller Ekranını Aç'), findsNothing);
      expect(find.byType(DashboardView), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('modül AÇIK: vitrinde Kapılar kartı var, bireysel ana ekran onun arkasında; bilgi kutusu yok', (t) async {
      final auth = _HomeModAuth(role: UserRole.individual)..apartments = [apartment()];
      final access = await _access(<MySiteModules>[_my(11, door: true, role: 'resident')]);
      await _pumpHome(t, auth, access: access);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(IndividualHomeView), findsNothing, reason: 'vitrinde bireysel ana ekran yok');
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(find.text('Kayıtlı Dairem'), findsOneWidget);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('çift modlu site yöneticisi: Yönetici Paneli kartı (Modüller kısayoluyla), Sakin Modu bireysel ana ekran + kısa bilgi', (t) async {
      final auth = _HomeModAuth()..apartments = [apartment()];
      final access = await _access(<MySiteModules>[_my(11, door: false)]);
      await _pumpHome(t, auth, access: access);

      // Yönetici paneli: Kapılar kartı yok (bilgi kartı da yok); Modüller kartı kapıdan bağımsız duruyor.
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_kart_moduller')), findsOneWidget);

      // Sakin modu: vitrin (sakin kitlesi) + altında bireysel ana ekran (dairelerim vb.) + kısa bilgi; Modüller kartı YOK.
      await t.tap(_inAppBar(find.text('Sakin Modu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(find.text('Kayıtlı Dairem'), findsOneWidget);
      expect(find.textContaining('Geçiş Kontrol modülü kapalı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_moduller')), findsNothing);
      await _openDrawer(t);
      expect(_tileTitle('Modüller'), findsNothing, reason: 'sakin modunda Modüller menüsü yok');
      await _closeDrawer(t);

      // Yönetici paneline dönüş.
      await t.tap(_inAppBar(find.text('Yönetici Paneli')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey<String>('panel_kart_moduller')), findsOneWidget);
      expect(find.byType(IndividualHomeView), findsNothing);
      await _disposeHome(t);
    });
  });

  group('Modül yeniden açılınca Panel verisi yeniden çekilir (home_page _loadDoorControlSites)', () {
    testWidgets('site yöneticisi: Kapılar kartı gelir, kapı paneli seçili site ve kapılarla açılır, yapı yeniden çekilir', (t) async {
      var door = false;
      final access = ModuleAccess(
        fetch: () async => MyModulesResult(sites: <MySiteModules>[_my(11, door: door)]),
      );
      addTearDown(access.dispose);
      await access.refresh();
      final auth = _HomeModAuth(sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')]);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      final structureBefore = auth.structureCalls.length;
      final sitesBefore = auth.listSitesCalls;

      door = true;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      final dashboard = t.widget<DashboardView>(find.byType(DashboardView));
      expect(dashboard.selectedSite?.id, 11);
      expect(dashboard.doors, isNotEmpty);
      expect(dashboard.selectedDoor, isNotNull);
      expect(auth.listSitesCalls, greaterThan(sitesBefore),
          reason: 'yeniden açılınca Panel site listesi yeniden çekilir');
      expect(auth.structureCalls.length, greaterThan(structureBefore),
          reason: 'seçili sitenin kapı yapısı yeniden çekilir');
      await _disposeHome(t);
    });

    testWidgets('daire sakini: Kapılar kartı ve hızlı eylem gelir, listMyDoors yeniden çekilir ve kapılar gelir', (t) async {
      var door = false;
      final access = ModuleAccess(
        fetch: () async => MyModulesResult(
          sites: <MySiteModules>[_my(11, door: door, role: 'resident')],
        ),
      );
      addTearDown(access.dispose);
      await access.refresh();
      final auth = _HomeModAuth(role: UserRole.apartmentOwner);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsNothing);
      final callsBefore = auth.listMyDoorsCalls;

      door = true;
      auth.residentDoors = <DoorRecord>[_door(11)];
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(auth.listMyDoorsCalls, greaterThan(callsBefore));
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsOneWidget);
      await _openDoorPanel(t);
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      final dashboard = t.widget<DashboardView>(find.byType(DashboardView));
      expect(dashboard.doors.map((d) => d.siteCode), <int>[11]);
      expect(dashboard.selectedDoor, isNotNull);
      await _disposeHome(t);
    });
  });

  group('Süper kullanıcı: Panel\'de seçili sitenin Geçiş Kontrol durumu', () {
    // Süper kullanıcıda Kapılar kartı her zaman vardır (menü süzgeci yok); seçili sitenin Geçiş Kontrol'ü kapalıysa kapı
    // kartları yerine bilgi kartı KAPILAR sayfasında çıkar.
    testWidgets('kapalı site: Kapılar sayfasında kapı kartları yerine bilgi kartı (Modüller kısayoluyla); açılınca yenilemeyle geri gelir', (t) async {
      final auth = _HomeModAuth(
        role: UserRole.superUser,
        sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')],
        states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
      );
      await _pumpHome(t, auth);
      await _openDoorPanel(t);

      expect(auth.getModulesCalls, contains(11));
      expect(find.byType(DoorControlDisabledCard), findsOneWidget);
      expect(find.byType(DashboardView), findsNothing);
      expect(find.text('Modüller Ekranını Aç'), findsOneWidget);
      expect(auth.myModulesCalls, 0, reason: 'süper kullanıcı için my-modules çekilmez');

      auth.states[11] = mdState(11, 'Gül Sitesi', door: true);
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byType(DashboardView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('açık site: normal kapı paneli; Modüller ekranında kapatınca Kapılar sayfası bilgi kartına döner', (t) async {
      final auth = _HomeModAuth(
        role: UserRole.superUser,
        sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')],
      );
      await _pumpHome(t, auth);
      await _openDoorPanel(t);
      expect(find.byType(DashboardView), findsOneWidget);

      await _tapMenu(t, 'Modüller');
      await t.ensureVisible(doorModuleSwitch);
      await t.tap(doorModuleSwitch);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await t.tap(find.text('Kapat'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      expect(auth.setCalls.single.confirm, isTrue);

      await _tapMenu(t, 'Kapılar');
      expect(find.byType(DoorControlDisabledCard), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('Çekip yenileme modül isteğini BEKLEMEZ', () {
    testWidgets('getMyModules yanıtı gelmese de yenileme göstergesi kapanır', (t) async {
      final auth = _HomeModAuth()..myModulesGate = Completer<void>();
      await _pumpHome(t, auth);
      final callsBefore = auth.myModulesCalls;

      await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, 400));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));

      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(auth.myModulesCalls, greaterThanOrEqualTo(callsBefore),
          reason: 'modül isteği başlatılmış olabilir ama gösterge onu beklemez');
      await _disposeHome(t);
    });
  });

  group('Hesap değişimi: eski kullanıcının modül durumu sızmaz', () {
    testWidgets('çıkışta ModuleAccess temizlenir; yeni kullanıcı kendi durumunu görür', (t) async {
      final auth = _HomeModAuth(
        role: UserRole.apartmentOwner,
        myModules: MyModulesResult(sites: <MySiteModules>[_my(11, door: false, role: 'resident')]),
      );
      final access = ModuleAccess(fetch: () => auth.getMyModules());
      addTearDown(access.dispose);
      await access.refresh();

      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      // Uygulama kökü gibi: oturum yoksa giriş ekranı, varsa HomePage.
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AnimatedBuilder(
            animation: auth,
            builder: (context, _) => auth.session == null
                ? const Scaffold(body: Text('Giriş Ekranı'))
                : HomePage(authService: auth, moduleAccess: access),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing, reason: 'kapalı sitenin kullanıcısı');
      expect(access.isLoaded, isTrue);

      auth.changeSession(loggedIn: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Giriş Ekranı'), findsOneWidget);
      expect(access.isLoaded, isFalse, reason: 'çıkışta modül durumu temizlenir');
      expect(access.isDisabledEverywhere(PlatformModuleCodes.doorControl), isFalse);

      // Yeni kullanıcı: kendi sitesinde Geçiş Kontrol açık.
      auth.myModules = MyModulesResult(
        sites: <MySiteModules>[_my(12, door: true, role: 'resident')],
      );
      auth.residentDoors = <DoorRecord>[_door(12)];
      auth.changeSession(role: UserRole.apartmentOwner, loggedIn: true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(DoorControlDisabledCard), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsOneWidget,
          reason: 'yeni kullanıcının sitesinde Geçiş Kontrol açık: Kapılar kartı var');
      await _openDoorPanel(t);
      expect(find.byType(DashboardView), findsOneWidget);
      expect(access.isEnabled(11, PlatformModuleCodes.doorControl), isTrue,
          reason: 'eski kullanıcının kapalı sitesi sızmaz (bilinmeyen site: varsayılan açık)');
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });

    testWidgets('rol değişimi (örn. cihaz sahiplenip yönetici olma) modül durumunu yeniden çeker', (t) async {
      var fetches = 0;
      final auth = _HomeModAuth(role: UserRole.individual);
      final access = ModuleAccess(
        fetch: () async {
          fetches++;
          return const MyModulesResult();
        },
      );
      addTearDown(access.dispose);
      await _pumpHome(t, auth, access: access);
      final before = fetches;

      auth.changeSession(role: UserRole.siteManager);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(fetches, greaterThan(before));
      await _disposeHome(t);
    });
  });

  group('Taşma: kapalı modül görünümü', () {
    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      for (final dark in const <bool>[false, true]) {
        final label = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

        testWidgets('site yöneticisi kapalı modül vitrini + çekmece: $label', (t) async {
          final auth = _HomeModAuth();
          final access = await _access(<MySiteModules>[_my(11, door: false)]);
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: s, dark: dark);
          expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
          expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
          expect(t.takeException(), isNull);

          await _openDrawer(t);
          expect(_tileTitle('Kayıtlı Cihazlar'), findsNothing);
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });

        testWidgets('daire sakini kapalı modül vitrini: $label', (t) async {
          final auth = _HomeModAuth(role: UserRole.apartmentOwner);
          final access = await _access(<MySiteModules>[_my(11, door: false, role: 'resident')]);
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: s, dark: dark);
          expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
          expect(find.byKey(const ValueKey<String>('panel_kart_kapilar')), findsNothing);
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });

        testWidgets('süper kullanıcı: kapalı sitenin Kapılar sayfası bilgi kartı: $label', (t) async {
          final auth = _HomeModAuth(
            role: UserRole.superUser,
            sites: <SiteRecord>[mdSite(11, 'Gül Sitesi')],
            states: <int, SiteModulesState>{11: mdState(11, 'Gül Sitesi', door: false)},
          );
          await _pumpHome(t, auth, width: w, height: h, scale: s, dark: dark);
          await _openDoorPanel(t);
          expect(find.byType(DoorControlDisabledCard), findsOneWidget);
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });
      }
    }
  });
}
