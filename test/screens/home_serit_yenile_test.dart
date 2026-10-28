// P2-21 + P2-26: ana kabukta bağlam şeridi, belirgin "Yenile" ve onaylı "Çıkış Yap".
//
// - AppBar'da "Çıkış Yap" YOK; "Yenile" yuvarlak + çerçeveli (öteki çıplak simgelerden ayrışır), 44 dp; yenileme sürerken
//   meşguldür ve ikinci tur başlamaz.
// - "Çıkış Yap" çekmecenin dibindedir ve HER ZAMAN onay ister: vazgeçilirse oturum da çekmece de yerinde kalır.
// - Bağlam şeridi yalnız birden çok siteye / daireye bağlı kullanıcıda çıkar; yönetici kitlesinde site seçici, sakin
//   kitlesinde "Dairem"e götürür.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/context_strip.dart';
import 'package:site_kapi_kontrol/ui/widgets/refresh_action_button.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

SiteRecord _siteRecord(int id, String name) => SiteRecord(
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

DoorRecord _door(int site) => DoorRecord(
      id: site * 10 + 1,
      siteCode: site,
      siteName: 'Site $site',
      doorName: 'Ana Kapı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'AABBCC0$site',
      mqttSiteId: site,
      createdAt: DateTime(2026, 1, 1),
    );

/// HomePage sahte servisi: oturum sabit, çıkış sayılır, kapı listesi isteğe bağlı bekletilir (uzun yenileme).
class _Auth extends AuthService {
  _Auth(this.role, {List<SiteRecord>? sites})
      : sites = sites ?? <SiteRecord>[_siteRecord(1, 'Güneş Sitesi')],
        super(api: AuthApi(baseUrl: 'http://localhost'));

  UserRole role;
  List<SiteRecord> sites;
  int logouts = 0;
  int doorListCalls = 0;
  Completer<void>? doorsGate;

  @override
  UserSession? get session => UserSession(
        id: 5,
        fullName: 'Ayşe Yılmaz',
        email: 'ayse@example.com',
        loginName: null,
        role: role,
        isActive: true,
        token: 'tok',
      );

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> logout() async {
    logouts++;
  }

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: sites, total: sites.length, page: 1, pageSize: 100);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async => (
        SiteStructureRecord(
          site: sites.firstWhere((s) => s.id == siteCode, orElse: () => sites.first),
          blocks: const <SiteBlockRecord>[],
          apartments: const <ApartmentRecord>[],
          doors: <DoorRecord>[_door(siteCode)],
        ),
        null,
      );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    doorListCalls++;
    final gate = doorsGate;
    if (gate != null) await gate.future;
    return (<DoorRecord>[_door(1)], null);
  }

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<MySiteApplications> getMySiteApplications() async => const MySiteApplications();

  @override
  Future<MyFinance> getMyFinance() async => const MyFinance(items: <MyFinanceApartment>[]);
}

MySiteModules _my(String role, {int site = 1, Map<String, bool> modules = const <String, bool>{}}) => MySiteModules(
      siteCode: site,
      siteName: site == 1 ? 'Güneş Sitesi' : 'Ay Sitesi',
      role: role,
      modules: <String, bool>{'door_control': true, ...modules},
      doorAccess: !(role == 'staff' || role == 'board_member'),
    );

Future<ModuleAccess> _access(List<MySiteModules> Function() sites) async {
  final access = ModuleAccess(fetch: () async => MyModulesResult(sites: sites()), isSuperUser: () => false);
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

Future<void> _pumpHome(
  WidgetTester t,
  _Auth auth, {
  ModuleAccess? access,
  Future<List<ContextApartment>> Function()? loadApartments,
  double width = 400,
  double height = 1000,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier();
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HomePage(
        authService: auth,
        moduleAccess: access,
        announcementNotifier: notifier,
        loadContextApartments: loadApartments,
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);
final Finder _strip = find.byKey(const ValueKey<String>('baglam_seridi'));
final Finder _refreshButton = _inAppBar(find.widgetWithIcon(IconButton, Icons.refresh_rounded));

String _stripText(WidgetTester t) =>
    t.widget<Text>(find.descendant(of: _strip, matching: find.byType(Text))).textSpan!.toPlainText();

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

void main() {
  group('AppBar: belirgin Yenile, Çıkış Yap yok', () {
    testWidgets('Yenile yuvarlak + çerçeveli düz yüzey, 44 dp; Çıkış Yap AppBar\'da değil', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      await _pumpHome(t, auth);
      expect(_refreshButton, findsOneWidget);
      expect(t.getSize(_refreshButton).width, greaterThanOrEqualTo(44), reason: 'dokunma hedefi >= 44 dp');
      expect(t.getSize(_refreshButton).height, greaterThanOrEqualTo(44));
      final button = t.widget<IconButton>(_refreshButton);
      final p = AppPalette.light;
      final shape = button.style!.shape!.resolve(<WidgetState>{}) as CircleBorder;
      expect(shape.side.color, p.border, reason: 'çerçeve: çıplak simge düğmelerinden ayrışır');
      expect(button.style!.backgroundColor!.resolve(<WidgetState>{}), p.surfaceMuted);
      expect(_inAppBar(find.byTooltip('Yenile')), findsOneWidget);
      expect(_inAppBar(find.byTooltip('Çıkış Yap')), findsNothing);
      expect(_inAppBar(find.byIcon(Icons.logout_rounded)), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('yenileme sürerken düğme meşgul (ilerleme göstergesi, pasif); ikinci dokunuş yeni tur başlatmaz', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      await _pumpHome(t, auth);
      expect(_inAppBar(find.byType(CircularProgressIndicator)), findsNothing);

      auth.doorsGate = Completer<void>();
      final before = auth.doorListCalls;
      await t.tap(_refreshButton);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.doorListCalls, before + 1);
      expect(_inAppBar(find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(_inAppBar(find.widgetWithIcon(IconButton, Icons.refresh_rounded)), findsNothing, reason: 'simge yerine ilerleme');
      final busyButton = find.descendant(of: find.byType(RefreshActionButton), matching: find.byType(IconButton));
      expect(t.widget<IconButton>(busyButton).onPressed, isNull, reason: 'sürerken pasif');
      await t.tap(busyButton, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.doorListCalls, before + 1, reason: 'ikinci dokunuş yeni tur başlatmaz');

      auth.doorsGate!.complete();
      auth.doorsGate = null;
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_inAppBar(find.byType(CircularProgressIndicator)), findsNothing);
      expect(_refreshButton, findsOneWidget);
      expect(t.widget<IconButton>(_refreshButton).onPressed, isNotNull);
      await _disposeHome(t);
    });

    testWidgets('320 dp x2,0: Yenile + dişli sığar, Yenile ekranın içinde ve menü düğmesine binmez', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      await _pumpHome(t, auth, width: 320, height: 640, scale: 2.0);
      final r = t.getRect(_refreshButton);
      expect(r.left, greaterThanOrEqualTo(48));
      expect(r.right, lessThanOrEqualTo(320));
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });
  });

  group('Çıkış Yap: çekmecenin dibinde, onaylı', () {
    final logoutTile = find.byKey(const ValueKey<String>('yan_menu_cikis'));
    final dialog = find.byType(AlertDialog);

    testWidgets('onay penceresi: Vazgeç oturumu da çekmeceyi de yerinde bırakır; onay oturumu kapatır', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      await _pumpHome(t, auth);
      await _openDrawer(t);
      expect(logoutTile, findsOneWidget);
      expect(find.descendant(of: logoutTile, matching: find.text('Çıkış Yap')), findsOneWidget);

      await t.ensureVisible(logoutTile);
      await t.tap(logoutTile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(dialog, findsOneWidget);
      expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
      expect(find.textContaining('oturumunuz kapatılacak'), findsOneWidget);
      expect(auth.logouts, 0, reason: 'onay gelmeden çıkış yok');

      await t.tap(find.descendant(of: dialog, matching: find.text('Vazgeç')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(dialog, findsNothing);
      expect(auth.logouts, 0);
      expect(find.byType(YanMenu), findsOneWidget, reason: 'çekmece açık kalır');

      await t.tap(logoutTile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tapAt(const Offset(390, 990)); // perde: pencere kapanır, çıkış yok
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(dialog, findsNothing);
      expect(auth.logouts, 0, reason: 'dışarı dokunmak onay sayılmaz');

      await t.tap(logoutTile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.descendant(of: dialog, matching: find.text('Çıkış Yap')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(auth.logouts, 1);
      expect(find.byType(YanMenu), findsNothing, reason: 'onaydan sonra çekmece kapanır');
      await _disposeHome(t);
    });

    testWidgets('onay penceresi 320 dp x2,0\'da taşmaz', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      await _pumpHome(t, auth, width: 320, height: 640, scale: 2.0);
      await _openDrawer(t);
      await t.ensureVisible(logoutTile);
      await t.tap(logoutTile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(dialog, findsOneWidget);
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });
  });

  group('bağlam şeridi', () {
    final twoSites = <SiteRecord>[_siteRecord(1, 'Güneş Sitesi'), _siteRecord(2, 'Ay Sitesi')];
    List<MySiteModules> managerSites() => <MySiteModules>[_my('manager', site: 1), _my('manager', site: 2)];
    List<MySiteModules> residentSites() => <MySiteModules>[_my('resident', site: 1), _my('resident', site: 2)];

    testWidgets('tek siteli kullanıcıda şerit yok (ekran eskisi gibi)', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access, loadApartments: () async => const <ContextApartment>[]);
      expect(_strip, findsNothing);
      await _disposeHome(t);
    });

    testWidgets('modül verisi gelmediyse (hata: fail-open) şerit yok', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      final access = ModuleAccess(fetch: () async => throw StateError('yok'), isSuperUser: () => false);
      await access.refresh();
      addTearDown(access.dispose);
      expect(access.isLoaded, isFalse);
      await _pumpHome(t, auth, access: access);
      expect(_strip, findsNothing);
      await _disposeHome(t);
    });

    testWidgets('çok siteli yönetici: AppBar\'ın hemen altında "Tüm siteler (2) · Yönetici"; dokununca site seçici', (t) async {
      final auth = _Auth(UserRole.siteManager, sites: twoSites);
      final access = await _access(managerSites);
      await _pumpHome(t, auth, access: access);
      expect(_strip, findsOneWidget);
      expect(_stripText(t), 'Tüm siteler (2) · Yönetici');
      expect(t.getRect(_strip).top, greaterThanOrEqualTo(t.getRect(find.byType(AppBar)).bottom - 0.01));

      await t.tap(_strip);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      expect(find.text('Site seçin'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('baglam_site_secenek_2')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(access.scopeSiteCode, 2, reason: 'çekmecedeki site seçiciyle AYNI kapsam');
      expect(_stripText(t), 'Ay Sitesi · Yönetici');

      await t.tap(_strip);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      await t.tap(find.byKey(const ValueKey<String>('baglam_site_secenek_tum')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(access.scopeSiteCode, isNull);
      expect(_stripText(t), 'Tüm siteler (2) · Yönetici');
      await _disposeHome(t);
    });

    testWidgets('çekmeceden seçilen site şeride de yansır', (t) async {
      final auth = _Auth(UserRole.siteManager, sites: twoSites);
      final access = await _access(managerSites);
      await _pumpHome(t, auth, access: access);
      access.setScopeSiteCode(1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(_stripText(t), 'Güneş Sitesi · Yönetici');
      await _disposeHome(t);
    });

    testWidgets('sakin, iki site, iki daire: "Güneş Sitesi +1 site · 2 daire · Sakin"; ipucu Dairem\'e götürür; yenilemede daireler yeniden okunur',
        (t) async {
      final handle = t.ensureSemantics();
      final auth = _Auth(UserRole.apartmentOwner);
      final access = await _access(residentSites);
      var loads = 0;
      await _pumpHome(
        t,
        auth,
        access: access,
        loadApartments: () async {
          loads++;
          return const <ContextApartment>[
            ContextApartment(siteCode: 1, label: 'A Blok / 5'),
            ContextApartment(siteCode: 2, label: 'B Blok / 2'),
          ];
        },
      );
      expect(loads, 1);
      expect(_stripText(t), 'Güneş Sitesi +1 site · 2 daire · Sakin');
      expect(
        t.getSemantics(_strip),
        isSemantics(
          label: 'Güneş Sitesi +1 site, 2 daire, Sakin olarak görüntüleniyor',
          hint: 'Dairelerinizi görmek için dokunun',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(loads, 2, reason: 'başarılı genel yenileme daireleri tazeler');
      handle.dispose();
      await _disposeHome(t);
    });

    testWidgets('320 dp x2,0: uzun adlı çok siteli sakin şeridi taşmaz', (t) async {
      final auth = _Auth(UserRole.apartmentOwner);
      final long = 'Çok Uzun İsimli Güzelyalı Yeşilvadi Konutları ${'Doğa ' * 8}Sitesi';
      final access = await _access(
        () => <MySiteModules>[
          MySiteModules(siteCode: 1, siteName: long, role: 'resident', modules: const <String, bool>{'door_control': true}),
          _my('resident', site: 2),
        ],
      );
      await _pumpHome(
        t,
        auth,
        access: access,
        width: 320,
        height: 640,
        scale: 2.0,
        loadApartments: () async => const <ContextApartment>[
          ContextApartment(siteCode: 1, label: 'Çok Uzun Blok Adı / 12345'),
          ContextApartment(siteCode: 2, label: 'B Blok / 2'),
        ],
      );
      expect(_strip, findsOneWidget);
      expect(t.takeException(), isNull);
      expect(t.getRect(_strip).right, lessThanOrEqualTo(320));
      await _disposeHome(t);
    });
  });
}
