// Platform: site başvurusu (site yöneticisi olma) — ana kabuk (HomePage) entegrasyonu.
//
// - Süper kullanıcı: çekmecede "Site Başvuruları" + bekleyen sayısı rozeti (hafif `summary` ucu); seçilince ekran
//   açılır; karardan sonra rozet tazelenir. Diğer roller menüyü GÖRMEZ (fail-open durumlarında da).
// - Bireysel / daire kullanıcısı: başvuru durumu kartı, başvuru formu, yoklama yaşam döngüsü, onaylanınca
//   oturum/rol sunucudan yenilenir ve kullanıcı sayfa yenilenmeden yönetici görünümüne geçer.
// - Cihaz sahiplenmek kullanıcıyı yönetici YAPMAZ (rol değişmez): bilgi + "Site Kur" eylemi.
//
// Panel artık MODÜL VİTRİNİDİR: başvuru durumu kartı vitrinde de görünür; başvuru / cihaz eylemleri taşıyan bireysel ana ekran
// (IndividualHomeView) "Kapılar" kartının arkasındadır (`doors: true`); yönetici görünümü = yönetici vitrini.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
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
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/join_and_setup_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/site_applications_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';

import 'dialog_layout_harness.dart';
import 'site_application_fixtures.dart';
import '../legal_fixtures.dart';
import '../support/menu_nav.dart';

SiteRecord _site(int id, String name) => SiteRecord.fromJson(<String, dynamic>{
  'id': id,
  'name': name,
  'approval_status': 'approved',
  'created_at': '2026-10-01T12:30:00Z',
});

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

/// HomePage için sahte servis: site başvurusu uçları [SiteApplicationFakeAuth]tan, kabuk uçları burada.
class _HomeApp extends SiteApplicationFakeAuth {
  _HomeApp({super.role, super.myUserCode});

  /// Yönetici görünümünde listelenen siteler (onaydan sonra sunucu siteyi kurar).
  List<SiteRecord> sites = <SiteRecord>[];
  int listSitesCalls = 0;
  int structureCalls = 0;
  List<MyApartmentRecord> apartments = <MyApartmentRecord>[];

  @override
  Future<MyModulesResult> getMyModules() async => const MyModulesResult(scope: 'all');

  @override
  Future<ModuleRequestPage> listAdminModuleRequests({String? status, int limit = 50, int? beforeId}) async =>
      const ModuleRequestPage();

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async {
    listSitesCalls++;
    return SitePage(sites: List<SiteRecord>.of(sites), total: sites.length, page: page, pageSize: pageSize);
  }

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    structureCalls++;
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
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

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

Future<void> _pumpHome(
  WidgetTester t,
  _HomeApp auth, {
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
  bool doors = false,
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
      home: HomePage(authService: auth),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  if (doors) await _openDoorPanel(t);
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

Finder _tileTitle(String title) => find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D: ayar öğeleri (Site Başvuruları, Modül Talepleri, Platform Ayarları, İstemci Hataları, Denetim Kaydı ...) sağ
/// üstteki dişliden açılan Ayarlar panelindedir; panel de bir `Drawer` olduğundan çekmece bulucuları orada da çalışır.
Future<void> _openSettings(WidgetTester t) => openSettingsPanel(t);

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

/// Panel vitrinindeki "Kapılar" kartına dokunur: bireysel ana ekran (başvuru / cihaz eylemleri) onun arkasındadır.
Future<void> _openDoorPanel(WidgetTester t) async {
  final card = find.byKey(const ValueKey<String>('panel_kart_kapilar'));
  await t.ensureVisible(card);
  await t.pump();
  await t.tap(card);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

Future<void> _elapse(WidgetTester t, Duration d) async {
  await t.pump(d);
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  // Yasal belge uçları sahte: başvuruda onay gerektiren belge yok (DPA kutusu çıkmaz, gönderme açık kalır).
  setUp(() {
    LegalApi.debugDefaultFactory = () => FakeLegalServer(documents: <Map<String, dynamic>>[]).api;
  });
  tearDown(() => LegalApi.debugDefaultFactory = null);

  group('süper kullanıcı: menü ve rozet', () {
    _HomeApp superAuth() {
      final auth = _HomeApp(role: UserRole.superUser, myUserCode: 999);
      auth.seed([
        saRow(41, siteName: 'Gül Sitesi'),
        saRow(40, siteName: 'Mavi Park', applicantCode: 6, applicantName: 'Mehmet Demir'),
        saRow(39, status: 'approved', siteName: 'Yeşil Vadi', applicantCode: 7),
      ]);
      return auth;
    }

    testWidgets('çekmecede "Site Başvuruları" ve bekleyen sayısı rozeti (summary ucu); seçilince ekran açılır', (t) async {
      final auth = superAuth();
      await _pumpHome(t, auth);
      expect(auth.summaryCalls, greaterThan(0));

      await _openSettings(t);
      expect(_tileTitle('Site Başvuruları'), findsOneWidget);
      expect(_tileTitle('Modül Talepleri'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'2 bekleyen')), findsWidgets);
      final badge = find.descendant(
        of: find.widgetWithText(ListTile, 'Site Başvuruları'),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);

      // Süper kullanıcının çekmecesi uzundur (Belgeler vb. eklendikçe uzar): öğe görünür alana kaydırılır.
      await t.ensureVisible(find.text('Site Başvuruları').last);
      await t.pump();
      await t.tap(find.text('Site Başvuruları').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(SiteApplicationsView), findsOneWidget);
      expect(_inAppBar(find.text('Site Başvuruları')), findsOneWidget);
      expect(auth.adminListCalls.first.status, 'pending');
      expect(find.text('Gül Sitesi'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('onay sonrası çekmece rozeti sunucudan yeniden okunur (2 -> 1)', (t) async {
      final auth = superAuth();
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Site Başvuruları');
      final before = auth.summaryCalls;

      await t.tap(find.widgetWithText(InkWell, 'Gül Sitesi').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      final approve = find.byKey(const ValueKey<String>('site_application_action_approve'));
      await t.ensureVisible(approve);
      await t.tap(approve);
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
      await settleFor(t, 800);
      expect(auth.approveCalls, <int>[41]);
      expect(auth.summaryCalls, greaterThan(before), reason: 'karardan sonra rozet tazelenir');

      await _openSettings(t);
      final badge = find.descendant(
        of: find.widgetWithText(ListTile, 'Site Başvuruları'),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(find.descendant(of: badge, matching: find.text('1')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bekleyen başvuru yoksa rozet yok; summary hatasında menü yine görünür ve çökme yok', (t) async {
      final empty = _HomeApp(role: UserRole.superUser, myUserCode: 999);
      await _pumpHome(t, empty);
      await _openSettings(t);
      expect(_tileTitle('Site Başvuruları'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Site Başvuruları'),
          matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
        ),
        findsNothing,
      );
      await _disposeHome(t);

      final failing = superAuth()..summaryError = ApiException('Sunucu yanıt vermedi.');
      await _pumpHome(t, failing);
      await _openSettings(t);
      expect(_tileTitle('Site Başvuruları'), findsOneWidget);
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });

    testWidgets('genel yenileme (Yenile) Site Başvuruları listesini tazeler', (t) async {
      final auth = superAuth();
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Site Başvuruları');
      final calls = auth.adminListCalls.length;
      await t.tap(find.byTooltip('Yenile').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(auth.adminListCalls.length, greaterThan(calls));
      await _disposeHome(t);
    });
  });

  group('rol kapısı: diğer roller menüyü GÖRMEZ', () {
    testWidgets('site yöneticisi, daire kullanıcısı ve bireysel kullanıcı: "Site Başvuruları" yok, başvuru ucu çağrılmaz', (t) async {
      for (final role in const [UserRole.siteManager, UserRole.apartmentOwner, UserRole.individual]) {
        final auth = _HomeApp(role: role)..sites = [_site(11, 'Gül Sitesi')];
        await _pumpHome(t, auth);
        await _openSettings(t);
        expect(_tileTitle('Site Başvuruları'), findsNothing, reason: '$role');
        expect(auth.summaryCalls, 0, reason: '$role: yönetici özeti istenmez');
        expect(auth.adminListCalls, isEmpty);
        await _disposeHome(t);
      }
    });

    testWidgets('süper kullanıcı: kendi başvuru uçları (mine) HİÇ çağrılmaz; site yöneticisi: oturum açılırken BİR kez (requires_application), başvuru kartı yok', (t) async {
      // Süper kullanıcı başvuramaz: sunucuya sormak da gereksiz.
      final superAuth = _HomeApp(role: UserRole.superUser)..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, superAuth);
      expect(superAuth.mineCalls, 0);
      expect(find.byType(SiteApplicationStatusCard), findsNothing);
      await _disposeHome(t);

      // Site yöneticisi: `requires_application` (sahip bağı yok -> başvuru) yalnız `mine` ile bilinir; alan gelmezse
      // (eski sunucu) hiçbir kart / etiket değişmez.
      final manager = _HomeApp(role: UserRole.siteManager)..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, manager);
      expect(manager.mineCalls, 1);
      expect(find.byType(SiteApplicationStatusCard), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('başvuru durumu alınamayınca (fail) yetki / menü AÇILMAZ: bireysel kullanıcı bireysel kalır', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..mineError = ApiException('Sunucu yanıt vermedi.');
      await _pumpHome(t, auth);
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'bireysel kullanıcı bireysel vitrinini görür');
      // Vitrin her rolde çizilir: "yetki açılmadı" ayrımı yönetici kartlarının YOKLUĞUYLA sınanır.
      expect(find.byKey(const ValueKey<String>('panel_kart_siteler')), findsNothing, reason: 'yetki yerelde yükseltilmez');
      expect(find.byKey(const ValueKey<String>('panel_kart_moduller')), findsNothing);
      expect(find.text('Sunucu yanıt vermedi.'), findsOneWidget, reason: 'hata görünür');
      await _openDrawer(t);
      expect(_tileTitle('Site Yönetimi'), findsNothing);
      await _openSettings(t);
      expect(_tileTitle('Site Başvuruları'), findsNothing);
      expect(_tileTitle('Modül Talepleri'), findsNothing);
      expect(auth.role, UserRole.individual);
      await _disposeHome(t);
    });
  });

  group('bireysel kullanıcı: başvuru akışı (durum kartı vitrinde; başvuru eylemleri Kapılar sayfasındaki bireysel ana ekranda)', () {
    testWidgets('başvuru yokken: "Site Kurmak İçin Başvur" birincil eylem, cihaz şart değil, pasif abonelik satırı', (t) async {
      final auth = _HomeApp(role: UserRole.individual);
      await _pumpHome(t, auth, doors: true);
      expect(auth.mineCalls, 1, reason: 'vitrin + bireysel ana ekran aynı taze durumu paylaşır: tek istek');
      expect(find.text('Site Kurmak İçin Başvur'), findsOneWidget);
      expect(find.text('Cihaz Ekle'), findsOneWidget);
      expect(find.text('Abonelikle hemen site aç — Yakında…'), findsOneWidget);
      expect(find.text('Site başvurunuz inceleniyor'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('form -> gönderim -> başarı iletisi -> kart "inceleniyor"; düğme "Başvurunuz İnceleniyor" pasif', (t) async {
      final auth = _HomeApp(role: UserRole.individual);
      await _pumpHome(t, auth, height: 1400, doors: true);
      await t.tap(find.byKey(const ValueKey<String>('site_application_apply')));
      await settleFor(t, 500);
      expect(find.text('Site Başvurusu'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'Site Adı *'), 'Gül Sitesi');
      final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await settleFor(t, 800);
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('setup_site_done')));
      await settleFor(t, 600);

      expect(auth.createCalls, hasLength(1));
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(auth.role, UserRole.individual, reason: 'onaya kadar bireysel kullanıcı');
      final apply = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('site_application_apply')));
      expect(apply.onPressed, isNull);
      expect(find.text('Başvurunuz İnceleniyor'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bekleyen başvuru: ~30 sn yoklanır; arka planda durur, öne gelince hemen okunur; dispose zamanlayıcıyı iptal eder', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7)]);
      await _pumpHome(t, auth);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      final base = auth.mineCalls;

      await _elapse(t, const Duration(seconds: 30));
      expect(auth.mineCalls, base + 1);
      await _elapse(t, const Duration(seconds: 30));
      expect(auth.mineCalls, base + 2);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _elapse(t, const Duration(minutes: 3));
      expect(auth.mineCalls, base + 2, reason: 'arka planda ağ isteği yok');

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.mineCalls, base + 3, reason: 'öne dönünce bekleyen başvuru hemen okunur');

      await _disposeHome(t);
      final after = auth.mineCalls;
      await t.pump(const Duration(minutes: 2));
      expect(auth.mineCalls, after, reason: 'dispose sonrası yoklama yok');
    });

    testWidgets('bekleyen yokken yoklama YOK', (t) async {
      final auth = _HomeApp(role: UserRole.individual);
      await _pumpHome(t, auth);
      final base = auth.mineCalls;
      await _elapse(t, const Duration(minutes: 5));
      expect(auth.mineCalls, base);
      await _disposeHome(t);
    });

    testWidgets('ONAYLANINCA: oturum/rol sunucudan yenilenir, kullanıcı sayfa yenilenmeden yönetici görünümüne geçer', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7, siteName: 'Gül Sitesi')]);
      await _pumpHome(t, auth);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_siteler')), findsNothing, reason: 'henüz yönetici değil');
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(auth.refreshSessionForcedCalls, 0);

      // Süper kullanıcı onaylar: sunucu siteyi kurar ve kullanıcıyı site yöneticisi yapar.
      auth.serverDecide(7, 'approved');
      auth.sites = [_site(11, 'Gül Sitesi')];
      await _elapse(t, const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 600));

      expect(auth.refreshSessionForcedCalls, greaterThanOrEqualTo(1), reason: 'rol yerelde tahmin edilmez');
      expect(auth.role, UserRole.siteManager);
      expect(find.byType(SiteApplicationStatusCard), findsNothing, reason: 'yönetici artık başvuru kartı görmez');
      expect(find.byKey(const ValueKey<String>('panel_kart_siteler')), findsOneWidget, reason: 'yönetici vitrini (Site Yönetimi kartı)');
      expect(find.text('Site başvurunuz onaylandı. Artık site yöneticisisiniz.'), findsOneWidget);
      expect(auth.listSitesCalls, greaterThan(0), reason: 'Panel verisi yeniden okundu');

      await _openDrawer(t);
      expect(_tileTitle('Site Yönetimi'), findsOneWidget, reason: 'yönetici menüsü');
      await _openSettings(t);
      expect(_tileTitle('Site Başvuruları'), findsNothing, reason: 'süper kullanıcı menüsü açılmaz');
      final base = auth.mineCalls;
      await _elapse(t, const Duration(minutes: 2));
      expect(auth.mineCalls, base, reason: 'rol değişince başvuru yoklaması durur');
      await _disposeHome(t);
    });

    testWidgets('onay yenilemesi başarısız: rol yerelde DEĞİŞMEZ, "Hesabı yenile" ile elle denenir', (t) async {
      final auth = _HomeApp(role: UserRole.individual)
        ..seed([saRow(7)])
        ..refreshSessionError = ApiException('Bağlantı yok.');
      await _pumpHome(t, auth);
      auth.serverDecide(7, 'approved');
      auth.sites = [_site(11, 'Gül Sitesi')];
      await _elapse(t, const Duration(seconds: 31));
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.role, UserRole.individual, reason: 'yenileme başarısız: yetki yükseltilmedi');
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      // Arayüzde de yetki yükselmedi: yönetici vitrininin kartları (Site Yönetimi, Modüller) yok.
      expect(find.byKey(const ValueKey<String>('panel_kart_siteler')), findsNothing, reason: 'yetki yerelde yükseltilmez');
      expect(find.byKey(const ValueKey<String>('panel_kart_moduller')), findsNothing);
      expect(find.text('Site başvurunuz onaylandı'), findsOneWidget);
      expect(find.text('Hesabı yenile'), findsOneWidget);

      auth.refreshSessionError = null;
      await t.tap(find.byKey(const ValueKey<String>('site_application_refresh_account')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.role, UserRole.siteManager);
      expect(find.byKey(const ValueKey<String>('panel_kart_siteler')), findsOneWidget, reason: 'yönetici vitrini');
      await _disposeHome(t);
    });

    testWidgets('reddedildi: gerekçe + Yeniden başvur formu önceki değerlerle açar', (t) async {
      final auth = _HomeApp(role: UserRole.individual)
        ..seed([
          saRow(
            7,
            status: 'rejected',
            siteName: 'Eski Sitesi',
            decisionNote: 'Adres eksik',
            decidedAt: DateTime.utc(2026, 10, 16, 8),
          ),
        ]);
      await _pumpHome(t, auth, height: 1400);
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      expect(find.text('Gerekçe: Adres eksik'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('site_application_reapply')));
      await settleFor(t, 500);
      final name = t.widget<EditableText>(
        find.descendant(of: find.widgetWithText(TextFormField, 'Site Adı *'), matching: find.byType(EditableText)),
      );
      expect(name.controller.text, 'Eski Sitesi');
      await _disposeHome(t);
    });

    testWidgets('bekleyen başvuruyu iptal et: onaylı; iptalden sonra yoklama durur ve başvuru düğmesi yeniden açılır', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7)]);
      await _pumpHome(t, auth, height: 1400, doors: true);
      await t.tap(find.byKey(const ValueKey<String>('site_application_cancel')));
      await settleFor(t, 400);
      await t.tap(find.widgetWithText(ElevatedButton, 'Başvuruyu İptal Et'));
      await settleFor(t, 600);
      expect(auth.cancelCalls, <int>[7]);
      expect(find.text('Site başvurunuzu iptal ettiniz'), findsOneWidget);
      final apply = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('site_application_apply')));
      expect(apply.onPressed, isNotNull);
      final base = auth.mineCalls;
      await _elapse(t, const Duration(minutes: 3));
      expect(auth.mineCalls, base);
      await _disposeHome(t);
    });
  });

  group('daire kullanıcısı: Daireye Katıl & Cihaz Ekle ekranı', () {
    testWidgets('başvuru kartı ve "Site Kurmak İçin Başvur" burada da vardır (cihazsız başvuru)', (t) async {
      final auth = _HomeApp(role: UserRole.apartmentOwner)..seed([saRow(7, status: 'rejected', decisionNote: 'Eksik')]);
      await _pumpHome(t, auth, height: 1400);
      await _tapMenu(t, 'Daireye Katıl & Cihaz Ekle');
      expect(find.byType(JoinAndSetupView), findsOneWidget);
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      expect(find.text('Site Kurmak İçin Başvur'), findsOneWidget);
      expect(find.text('Cihaz Ekle'), findsOneWidget);
      expect(find.text('Cihaz Ekleyerek Site Yöneticisi Ol'), findsNothing);

      final apply = find.byKey(const ValueKey<String>('site_application_apply'));
      await t.ensureVisible(apply);
      await t.pump();
      await t.tap(apply);
      await settleFor(t, 500);
      expect(find.text('Site Başvurusu'), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('cihaz sahiplenme: rol DEĞİŞMEZ, bilgi + Site Kur (bireysel ana ekran Kapılar sayfasında)', () {
    Future<void> claim(WidgetTester t, String uid) async {
      await t.tap(find.text('Seri No / UID ile Elle Ekle'));
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.widgetWithText(TextField, 'Cihaz UID / Seri Numarası'), uid);
      final bind = find.text('Cihazı Hesaba Bağla');
      await scrollTo(t, bind);
      await t.tap(bind);
      await settleFor(t, 900);
    }

    testWidgets('bireysel ana ekran: cihaz eklenince bilgi metni; rol değişmez, yönetici görünümüne geçilmez', (t) async {
      final auth = _HomeApp(role: UserRole.individual);
      await _pumpHome(t, auth, height: 1400, doors: true);
      await t.tap(find.byKey(const ValueKey<String>('site_application_claim_device')));
      await settleFor(t, 500);
      await claim(t, 'ESP32_NEW');

      expect(auth.claimCalls, <String>['ESP32_NEW']);
      expect(find.text('Cihaz Eklendi'), findsOneWidget);
      expect(
        find.text('Cihaz hesabınıza eklendi. Site yöneticisi olmak için Site Kur ile başvuru yapabilirsiniz.'),
        findsOneWidget,
      );
      expect(auth.role, UserRole.individual, reason: 'cihaz sahiplenmek yönetici yapmaz');
      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(find.text('Site Kurulum Sihirbazı'), findsNothing, reason: 'anlık kurulum sihirbazı açılmaz');

      await t.tap(find.byKey(const ValueKey<String>('device_added_later')));
      await settleFor(t, 500);
      expect(find.text('Cihaz Eklendi'), findsNothing);
      expect(auth.createCalls, isEmpty);
      // Cihaz sahibi bireysel kullanıcı hâlâ başvuru yapabilir: hızlı işlemler gizlenmez.
      expect(find.text('Site Kurmak İçin Başvur'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('"Site Kur": başvuru formu eklenen cihaz SEÇİLİ olarak açılır ve cihazla gönderilir', (t) async {
      final auth = _HomeApp(role: UserRole.individual);
      await _pumpHome(t, auth, height: 1600, doors: true);
      await t.tap(find.byKey(const ValueKey<String>('site_application_claim_device')));
      await settleFor(t, 500);
      await claim(t, 'ESP32_NEW');
      await t.tap(find.byKey(const ValueKey<String>('device_added_site_setup')));
      await settleFor(t, 700);

      expect(find.text('Site Başvurusu'), findsOneWidget);
      expect(find.text('ESP32_NEW'), findsWidgets);
      await t.enterText(find.widgetWithText(TextFormField, 'Site Adı *'), 'Gül Sitesi');
      final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await settleFor(t, 800);
      expect(auth.createCalls.single['deviceUid'], 'ESP32_NEW');
      expect(auth.setupCalls, isEmpty);
      expect(auth.role, UserRole.individual);
      await _disposeHome(t);
    });

    testWidgets('Daireye Katıl & Cihaz Ekle ekranından (daire kullanıcısı) aynı bilgi + Site Kur', (t) async {
      final auth = _HomeApp(role: UserRole.apartmentOwner);
      await _pumpHome(t, auth, height: 1600);
      await _tapMenu(t, 'Daireye Katıl & Cihaz Ekle');
      await t.ensureVisible(find.text('Cihaz Ekle'));
      await t.tap(find.text('Cihaz Ekle'));
      await settleFor(t, 500);
      await claim(t, 'ESP32_N2');
      expect(find.text('Cihaz Eklendi'), findsOneWidget);
      expect(auth.role, UserRole.apartmentOwner);
      expect(find.byType(DashboardView), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('device_added_site_setup')));
      await settleFor(t, 700);
      expect(find.text('Site Başvurusu'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('zaten bekleyen başvuru varsa form önerilmez: kısa bilgi', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7)]);
      await _pumpHome(t, auth, height: 1600, doors: true);
      await t.tap(find.byKey(const ValueKey<String>('site_application_claim_device')));
      await settleFor(t, 500);
      await claim(t, 'ESP32_NEW');
      expect(find.text('Cihaz Eklendi'), findsNothing);
      expect(find.text('Cihaz hesabınıza eklendi.'), findsWidgets);
      await _disposeHome(t);
    });

    testWidgets('site yöneticisinin "Site Ekle" (Yeni Site) akışı ANLIK kalır (başvuru formu açılmaz)', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, auth, height: 1600);
      await _tapMenu(t, 'Site Yönetimi');
      await t.pump(const Duration(milliseconds: 600));
      final add = find.text('Yeni Site');
      expect(add, findsWidgets);
      await t.ensureVisible(add.first);
      await t.tap(add.first);
      await settleFor(t, 600);
      expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
      expect(find.text('Site Başvurusu'), findsNothing);
      await t.enterText(find.widgetWithText(TextFormField, 'Site Adı *'), 'İkinci Site');
      final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await settleFor(t, 900);
      expect(auth.setupCalls, hasLength(1));
      expect(auth.createCalls, isEmpty);
      await _disposeHome(t);
    });
  });

  group('B1: site yöneticisi - sahip bağı yoksa başvuru (requires_application; Panel = yönetici vitrini)', () {
    Future<void> openSites(WidgetTester t) async {
      await _tapMenu(t, 'Site Yönetimi');
      await t.pump(const Duration(milliseconds: 600));
    }

    Future<void> tapAddSite(WidgetTester t, String label) async {
      final add = find.text(label);
      expect(add, findsWidgets);
      await t.ensureVisible(add.first);
      await t.pump();
      await t.tap(add.first);
      await settleFor(t, 600);
    }

    Future<void> fillAndSubmit(WidgetTester t, String name) async {
      await t.enterText(find.widgetWithText(TextFormField, 'Site Adı *'), name);
      final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await settleFor(t, 900);
    }

    testWidgets('sahip bağı OLMAYAN yönetici: `mine` oturum açılırken BİR kez; düğme "Site Başvurusu", form BAŞVURU kipinde açılır', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = true
        ..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, auth, height: 1600);
      expect(auth.mineCalls, 1);
      await openSites(t);
      expect(find.text('Yeni Site'), findsNothing);

      await tapAddSite(t, 'Site Başvurusu');
      expect(auth.mineCalls, 1, reason: 'durum zaten biliniyor: tekrar okunmaz');
      expect(find.text('Onaydan sonra site yöneticisi olursunuz'), findsOneWidget, reason: 'başvuru kipi');
      expect(find.text('Site Kurulum Sihirbazı'), findsNothing);

      await fillAndSubmit(t, 'İkinci Site');
      expect(auth.createCalls, hasLength(1));
      expect(auth.setupCalls, isEmpty, reason: 'anlık kurulum denenmedi');
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('setup_site_done')));
      await settleFor(t, 600);

      expect(auth.role, UserRole.siteManager, reason: 'onaya kadar rol aynı');
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget, reason: 'yönetici panosunda durum kartı');
      expect(find.byKey(const ValueKey<String>('site_application_cancel')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('başvurusu bekleyen yöneticinin panosunda (Panel) aynı durum kartı görünür', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = true
        ..sites = [_site(11, 'Gül Sitesi')]
        ..seed([saRow(7, siteName: 'Ek Site')]);
      await _pumpHome(t, auth, height: 1600);
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'yönetici vitrini (Panel)');
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('sahip bağı olan yönetici (requires_application: false): "Yeni Site" ANLIK kalır, başvuru kartı yok', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = false
        ..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, auth, height: 1600);
      expect(auth.mineCalls, 1);
      expect(find.byType(SiteApplicationStatusCard), findsNothing);
      await openSites(t);
      expect(find.text('Site Başvurusu'), findsNothing);
      await tapAddSite(t, 'Yeni Site');
      expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
      await fillAndSubmit(t, 'İkinci Site');
      expect(auth.setupCalls, hasLength(1));
      expect(auth.createCalls, isEmpty);
      expect(auth.mineCalls, 1);
      await _disposeHome(t);
    });

    testWidgets('alan HİÇ gelmezse (eski sunucu) eski davranış: anlık "Yeni Site"; durum alınamasa da yönetici panosu hata göstermez', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..mineError = ApiException('Bağlantı yok.')
        ..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, auth, height: 1600);
      expect(find.text('Bağlantı yok.'), findsNothing, reason: 'yönetici panosu başvuru yükleme hatasıyla rahatsız edilmez');
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      await openSites(t);
      await tapAddSite(t, 'Yeni Site');
      expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
      expect(find.text('Site Başvurusu'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('çıkmaz YOK: durum eskiydi (requires false) ama sunucu 409 APPLICATION_REQUIRED verdi -> form başvuru kipine geçer, bilgiler korunur', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = false
        ..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, auth, height: 1600);
      await openSites(t);
      // Sunucuda sahip bağı bu arada kalktı (istemcinin bilgisi eski).
      auth.serverRequiresApplication = true;
      await tapAddSite(t, 'Yeni Site');
      expect(find.text('Site Kurulum Sihirbazı'), findsOneWidget);
      await fillAndSubmit(t, 'İkinci Site');
      expect(auth.setupCalls, hasLength(1));
      expect(find.textContaining('Site eklemek için başvuru yapmanız gerekiyor'), findsOneWidget);
      expect(find.text('Onaydan sonra site yöneticisi olursunuz'), findsOneWidget);
      final name = t.widget<EditableText>(
        find.descendant(of: find.widgetWithText(TextFormField, 'Site Adı *'), matching: find.byType(EditableText)),
      );
      expect(name.controller.text, 'İkinci Site', reason: 'girilen bilgiler korundu');

      // Aynı pencereden başvuru gönderilir.
      final submit = find.byKey(const ValueKey<String>('setup_site_submit'));
      await scrollTo(t, submit);
      await t.tap(submit);
      await settleFor(t, 900);
      expect(auth.createCalls, hasLength(1));
      expect(find.text('Başvurunuz alındı.'), findsOneWidget);
      final mineBefore = auth.mineCalls;
      await t.tap(find.byKey(const ValueKey<String>('setup_site_done')));
      await settleFor(t, 700);
      expect(auth.mineCalls, greaterThan(mineBefore), reason: 'form kapanınca durum sunucudan okundu');
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      expect(find.text('Site Başvurusu'), findsOneWidget, reason: 'düğme artık başvuru etiketli');
      await _disposeHome(t);
    });

    testWidgets('çıkmaz YOK: 409 APPLICATION_REQUIRED sonrası form başvurusuz kapatılsa da durum yeniden okunur ve düğme "Site Başvurusu" olur', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = false
        ..sites = [_site(11, 'Gül Sitesi')];
      await _pumpHome(t, auth, height: 1600);
      await openSites(t);
      auth.serverRequiresApplication = true;
      await tapAddSite(t, 'Yeni Site');
      await fillAndSubmit(t, 'İkinci Site');
      expect(find.text('Onaydan sonra site yöneticisi olursunuz'), findsOneWidget);
      final mineBefore = auth.mineCalls;
      await t.tap(find.byTooltip('Kapat'));
      await settleFor(t, 700);
      expect(auth.mineCalls, greaterThan(mineBefore));
      expect(auth.createCalls, isEmpty);
      expect(find.text('Site Başvurusu'), findsWidgets);
      expect(find.text('Yeni Site'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('başvurusu ONAYLANAN yöneticide sahip bağı oluşur: kart kalkar, düğme yeniden "Yeni Site" (anlık)', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = true
        ..sites = [_site(11, 'Gül Sitesi')]
        ..seed([saRow(7, siteName: 'Ek Site')]);
      await _pumpHome(t, auth, height: 1600);
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);

      auth.serverDecide(7, 'approved');
      await _elapse(t, const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.role, UserRole.siteManager);
      expect(find.text('Site başvurunuz inceleniyor'), findsNothing);
      expect(find.text('Site başvurunuz onaylandı'), findsNothing, reason: 'yönetici panosunda onaylı kart yok');
      await openSites(t);
      expect(find.text('Yeni Site'), findsWidgets);
      expect(find.text('Site Başvurusu'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('sahip bağı olmayan, sitesiz yönetici: ana ekranda başvuru durumu kartı; "Site Yönetimi"nde "Site Başvurusu" düğmesi', (t) async {
      final auth = _HomeApp(role: UserRole.siteManager)
        ..serverRequiresApplication = true
        ..seed([saRow(7, siteName: 'Ek Site')]);
      await _pumpHome(t, auth, height: 1600);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_kart_siteler')), findsOneWidget, reason: 'yönetici vitrini');
      expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
      // Sitesiz yöneticinin bireysel ana ekranı (başvuru düğmesini çizebilecek TEK ekran) Kapılar'ın arkasındadır:
      // yokluk orada sınanır (vitrin bu düğmeyi hiç çizmez; vitrinde aramak her koşulda geçerdi).
      await _openDoorPanel(t);
      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(find.text('Site Kurmak İçin Başvur'), findsNothing, reason: 'yöneticide başvuru eylemi "Site Yönetimi" ekranındadır');
      await _tapMenu(t, 'Site Yönetimi');
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Site Başvurusu'), findsWidgets);
      expect(find.text('Yeni Site'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('B9: başvuru durumu bilinmiyor / kontrol ediliyor / bekleyen: eylemler pasif ve nedeni yazılı (Kapılar sayfasındaki bireysel ana ekran)', () {
    testWidgets('durum ALINAMADI: "Site Kurmak İçin Başvur" pasif (neden ipucunda), "Siteyi Kur" pasif; durum gelince ikisi de etkin', (t) async {
      final auth = _HomeApp(role: UserRole.individual)
        ..devices = [saDevice('ESP32_C3_ABC')]
        ..mineError = ApiException('Bağlantı yok.');
      await _pumpHome(t, auth, height: 1800, doors: true);
      expect(find.text('Başvuru Durumu Alınamadı'), findsOneWidget);
      var apply = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('site_application_apply')));
      expect(apply.onPressed, isNull);
      expect(find.byTooltip(RegExp('Başvuru durumu alınamadı')), findsWidgets, reason: 'neden ipucuyla söylenir');
      final setup = find.widgetWithText(ElevatedButton, 'Siteyi Kur');
      await scrollTo(t, setup);
      expect(t.widget<ElevatedButton>(setup).onPressed, isNull);

      auth.mineError = null;
      await t.tap(find.text('Tekrar Dene').first);
      await settleFor(t, 400);
      apply = t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('site_application_apply')));
      expect(apply.onPressed, isNotNull);
      expect(find.text('Site Kurmak İçin Başvur'), findsOneWidget);
      await scrollTo(t, find.widgetWithText(ElevatedButton, 'Siteyi Kur'));
      expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Siteyi Kur')).onPressed, isNotNull);
      await _disposeHome(t);
    });

    testWidgets('durum KONTROL EDİLİYOR (ilk okuma sürerken): "Durum Kontrol Ediliyor..." pasif', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..devices = [saDevice('ESP32_C3_ABC')];
      final gate = Completer<void>();
      auth.mineGates.add(gate);
      await _pumpHome(t, auth, height: 1800, doors: true);
      expect(find.text('Durum Kontrol Ediliyor...'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey<String>('site_application_apply'))).onPressed, isNull);
      final setup = find.widgetWithText(ElevatedButton, 'Siteyi Kur');
      await scrollTo(t, setup);
      expect(t.widget<ElevatedButton>(setup).onPressed, isNull);
      gate.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Site Kurmak İçin Başvur'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('BEKLEYEN başvuru varken "Siteyi Kur" pasif ve neden ipucunda (sunucuya gidip 409 almaz)', (t) async {
      final auth = _HomeApp(role: UserRole.individual)
        ..devices = [saDevice('ESP32_C3_ABC')]
        ..seed([saRow(7)]);
      await _pumpHome(t, auth, height: 1800, doors: true);
      final setup = find.widgetWithText(ElevatedButton, 'Siteyi Kur');
      await scrollTo(t, setup);
      expect(t.widget<ElevatedButton>(setup).onPressed, isNull);
      expect(find.byTooltip(RegExp('Zaten bekleyen bir site başvurunuz var')), findsWidgets);
      expect(find.text('Başvurunuz İnceleniyor'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('durum hazırken "Siteyi Kur" başvuru formunu CİHAZ SEÇİLİ açar', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..devices = [saDevice('ESP32_C3_ABC')];
      await _pumpHome(t, auth, height: 1800, doors: true);
      final setup = find.widgetWithText(ElevatedButton, 'Siteyi Kur');
      await scrollTo(t, setup);
      await t.tap(setup);
      await settleFor(t, 700);
      expect(find.text('Onaydan sonra site yöneticisi olursunuz'), findsOneWidget);
      expect(find.text('ESP32_C3_ABC'), findsWidgets);
      await _disposeHome(t);
    });
  });

  group('B10/B18: rol değişimi, tek yenileme, onay kartı ömrü', () {
    testWidgets('daire kullanıcısı <-> bireysel rol değişimi: açık ekranda başvuru kartı yerinde kalır; taze durum için gereksiz istek yok', (t) async {
      // (Eski durumun yeniden okunması ekran düzeyinde, saat enjekte edilerek sınanır:
      // site_application_screens_sync_test.dart.)
      final auth = _HomeApp(role: UserRole.apartmentOwner)..seed([saRow(7, status: 'rejected', decisionNote: 'Eksik')]);
      await _pumpHome(t, auth, height: 1600);
      await _tapMenu(t, 'Daireye Katıl & Cihaz Ekle');
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      final loaded = auth.mineCalls;

      auth.changeSession(role: UserRole.individual);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.mineCalls, loaded, reason: 'tazelik kuralı: 1 dakikadan taze durum yeniden okunmaz');
      expect(find.text('Site başvurunuz reddedildi'), findsOneWidget);
      expect(auth.role, UserRole.individual);
      await _disposeHome(t);
    });

    testWidgets('onay yenilemesi başarılı ama rol hâlâ başvuran (yöneticilik sonradan alınmış): onaylı kart KALKAR, tekrar gelmez', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7)]);
      await _pumpHome(t, auth);
      // Sunucuda karar verildi ama kullanıcının rolü (başka nedenle) değişmedi.
      auth.serverDecide(7, 'approved');
      auth.serverRole = UserRole.individual;
      await _elapse(t, const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.role, UserRole.individual);
      expect(find.text('Site başvurunuz onaylandı'), findsNothing, reason: 'yenileme başarılı + rol aynı: yanıltıcı kart yok');
      expect(find.byKey(const ValueKey<String>('site_application_refresh_account')), findsNothing);
      // Sonraki yoklamalarda / yeniden okumada kart geri gelmez.
      await _elapse(t, const Duration(minutes: 2));
      expect(find.text('Site başvurunuz onaylandı'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('onayda hesap yenileme TEK kez yapılır (çift yenileme yok): oturum yenilendi, Panel verisi bir kez okundu', (t) async {
      final auth = _HomeApp(role: UserRole.individual)..seed([saRow(7, siteName: 'Gül Sitesi')]);
      await _pumpHome(t, auth);
      auth.serverDecide(7, 'approved');
      auth.sites = [_site(11, 'Gül Sitesi')];
      final sitesBefore = auth.listSitesCalls;
      final forcedBefore = auth.refreshSessionForcedCalls;
      await _elapse(t, const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 600));
      expect(auth.role, UserRole.siteManager);
      expect(auth.refreshSessionForcedCalls - forcedBefore, 1, reason: 'zorla oturum yenileme bir kez');
      expect(auth.listSitesCalls - sitesBefore, lessThanOrEqualTo(2), reason: 'Panel verisi tekrar tekrar okunmaz');
      await _disposeHome(t);
    });

    testWidgets('yenileme (Yenile) bekleyen yokken başvuru durumunu gereksiz YOKLAMAZ; bireysel ana ekran yenilemesi tazeliği korur', (t) async {
      final auth = _HomeApp(role: UserRole.individual);
      await _pumpHome(t, auth, height: 1400);
      final before = auth.mineCalls;
      await t.tap(find.byTooltip('Yenile').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      // Taze bilgi varken (az önce okundu) mine'ın art arda tekrar okunmaması beklenir; en çok 1 ek çağrı kabul.
      expect(auth.mineCalls - before, lessThanOrEqualTo(1));
      await _disposeHome(t);
    });
  });

  group('taşma: bireysel ana ekran başvuru kartları (Kapılar sayfasında)', () {
    for (final (w, h, s) in const [(320.0, 640.0, 2.0), (360.0, 640.0, 1.5)]) {
      for (final dark in const [false, true]) {
        testWidgets('başvuru yok, cihaz sahibi: hızlı işlemler: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
          final auth = _HomeApp(role: UserRole.individual)..devices = [saDevice('ESP32_C3_ABCDEF1234567890')];
          await _pumpHome(t, auth, width: w, height: h, scale: s, dark: dark, doors: true);
          await scrollTo(t, find.byKey(const ValueKey<String>('site_application_apply')));
          await scrollTo(t, find.byKey(const ValueKey<String>('site_application_claim_device')));
          await scrollTo(t, find.text('Abonelikle hemen site aç — Yakında…'));
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });

        testWidgets('daire kullanıcısı, Daireye Katıl & Cihaz Ekle + reddedilmiş başvuru: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
          final auth = _HomeApp(role: UserRole.apartmentOwner)
            ..seed([saRow(7, status: 'rejected', decisionNote: 'Adres bilgisi eksik olduğu için kayıt oluşturulamadı.')]);
          await _pumpHome(t, auth, width: w, height: h, scale: s, dark: dark);
          await _tapMenu(t, 'Daireye Katıl & Cihaz Ekle');
          await scrollTo(t, find.byKey(const ValueKey<String>('site_application_reapply')));
          await scrollTo(t, find.byKey(const ValueKey<String>('site_application_apply')));
          await scrollTo(t, find.text('Abonelikle hemen site aç — Yakında…'));
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });

        testWidgets('bekleyen başvuru + hızlı işlemler: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'} tema, taşma yok', (t) async {
          final auth = _HomeApp(role: UserRole.individual)
            ..seed([saRow(7, siteName: 'Çok Uzun Bir Site Adı Konutları Sitesi')]);
          await _pumpHome(t, auth, width: w, height: h, scale: s, dark: dark, doors: true);
          expect(find.text('Site başvurunuz inceleniyor'), findsOneWidget);
          await scrollTo(t, find.byKey(const ValueKey<String>('site_application_cancel')));
          await scrollTo(t, find.text('Abonelikle hemen site aç — Yakında…'));
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });
      }
    }
  });
}
