// Platform Faz 3b-A: ana kabuk (HomePage) entegrasyonu — "Belgeler" menü öğesi.
//
// Kapı kuralları (güvenlik): menü YALNIZ `documents` modülü AÇIK siteye bağlı kullanıcıya görünür; modül kapalıyken
// ya da modül verisi hiç gelmemişken (fail-open durumu) AÇILMAZ. Yazma = yönetici / süper (yönetici modunda);
// kurul üyesi salt okunur; sakin yalnız kendi kitlesindeki belgeleri görür; görevli ve bireysel kullanıcı göremez.
import 'dart:async';
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
import 'package:site_kapi_kontrol/services/document_api.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/document_admin_view.dart';
import 'package:site_kapi_kontrol/ui/views/document_resident_view.dart';
import 'package:site_kapi_kontrol/ui/views/document_view.dart';
import 'package:site_kapi_kontrol/ui/views/modules_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show fxDoors, tapFinder;
import 'people_fixtures.dart';
import '../support/menu_nav.dart';

/// HomePage için sahte servis: ana kabuğun ihtiyaç duyduğu uçlar boş döner.
class _HomeAuth extends PeopleFakeAuth {
  _HomeAuth({super.role});

  @override
  Future<void> refreshSession({bool force = false}) async {}

  List<DoorRecord> doors = <DoorRecord>[];

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async =>
      (List<DoorRecord>.of(doors), null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async =>
      <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({
    required int doorId,
  }) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

/// Sahte belge sunucusu: istek yollarını kaydeder; yönetici listesi boş, sakin listesi boş döner.
class _DocServer {
  final List<String> paths = <String>[];
  bool moduleOff = false;

  http.Response handle(http.Request request) {
    paths.add(request.url.path);
    http.Response json(int status, Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
    if (moduleOff && request.url.path.startsWith('/manager/')) {
      return json(403, <String, dynamic>{
        'error': 'Bu özellik şu an kapalı.',
        'code': 'MODULE_DISABLED',
        'module': 'documents',
      });
    }
    if (request.url.path.startsWith('/app/documents')) {
      return json(200, <String, dynamic>{
        'items': <Object>[],
        'next_before_id': null,
      });
    }
    return json(200, <String, dynamic>{
      'items': <Object>[],
      'total': 0,
      'usage': <String, dynamic>{
        'used_bytes': 0,
        'quota_bytes': 209715200,
        'document_count': 0,
        'document_limit': 2000,
      },
    });
  }
}

late _DocServer _server;

/// `my-modules` satırı: [documents] true ise modül AÇIK. Yalnız kurul / görevli bağında `door_access` FALSE.
MySiteModules _my(
  String role, {
  bool documents = true,
  bool finance = false,
  int code = 11,
  String name = 'Gül Sitesi',
}) => MySiteModules(
  siteCode: code,
  siteName: name,
  role: role,
  modules: <String, bool>{
    'door_control': true,
    'documents': documents,
    'finance': finance,
  },
  doorAccess: !(role == 'staff' || role == 'board_member'),
);

Future<ModuleAccess> _access(
  List<MySiteModules> Function() sites, {
  bool superUser = false,
}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
    isSuperUser: () => superUser,
  );
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
  _HomeAuth auth, {
  ModuleAccess? access,
  double width = 400,
  double height = 900,
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
      home: HomePage(
        authService: auth,
        moduleAccess: access,
        announcementNotifier: notifier,
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

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _tapMenu(WidgetTester t, String label) async {
  await _openDrawer(t);
  final tile = find.descendant(
    of: find.byType(Drawer),
    matching: find.text(label),
  );
  await t.ensureVisible(tile.first);
  await t.pump();
  await t.tap(tile.first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await settleFor(t);
}

Finder _tileTitle(String title) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D (G2): menü LİSTESİNİN sırası (vitrin sırası; `YanMenu.visibleItems`: çekmece + Ayarlar paneli). Çekmece öğeleri
/// başlıklar altında gruplar ([expectUnderDrawerHeader]); ayar öğeleri sağ üstteki dişlidedir.
List<String> _drawerTitles(WidgetTester t) => menuListTitles(t);

Finder _inAppBar(Finder f) =>
    find.descendant(of: find.byType(AppBar), matching: f);

void main() {
  setUp(() {
    _server = _DocServer();
    DocumentService.debugApiFactory = (auth) => DocumentApi(
      baseUrl: 'http://localhost',
      client: MockClient((request) async => _server.handle(request)),
    );
  });

  tearDown(() => DocumentService.debugApiFactory = null);

  group('Belgeler menü öğesi (yönetici / kurul / süper)', () {
    testWidgets(
      'site yöneticisi + modül AÇIK: "Duyurular"ın altında; seçilince Belgeler ekranı, yazma yetkisi, başlık',
      (t) async {
        final auth = _HomeAuth();
        final access = await _access(() => <MySiteModules>[_my('manager')]);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        final titles = _drawerTitles(t);
        expect(titles, contains('Belgeler'));
        expect(titles.indexOf('Belgeler'), titles.indexOf('Duyurular') + 1);
        expectUnderDrawerHeader(t, 'Belgeler', 'Site hizmetleri');
        await t.tap(_tileTitle('Belgeler'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        await settleFor(t);

        expect(find.byType(DocumentsView), findsOneWidget);
        expect(find.byType(DocumentAdminView), findsOneWidget);
        expect(find.byType(DocumentResidentView), findsNothing);
        expect(_inAppBar(find.text('Belgeler')), findsOneWidget);
        final view = t.widget<DocumentsView>(find.byType(DocumentsView));
        expect(view.manageAllSites, isFalse);
        expect(view.manageSites, <PeopleSite>[
          const PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
        ]);
        expect(view.showResident, isFalse);
        expect(_server.paths, contains('/manager/sites/11/documents'));
        expect(find.text('Belge Yükle'), findsOneWidget);
        expect(
          auth.listSitesArgs.any((a) => a.approval == 'approved'),
          isFalse,
          reason:
              'Belgeler site listesini my-modules\'tan alır (tüm onaylı siteleri çekmez)',
        );
        await _disposeHome(t);
      },
    );

    testWidgets('Finans da açıksa Belgeler Finans\'ın altında', (t) async {
      final auth = _HomeAuth();
      final access = await _access(
        () => <MySiteModules>[_my('manager', finance: true)],
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles.indexOf('Belgeler'), titles.indexOf('Finans') + 1);
      await _disposeHome(t);
    });

    testWidgets('modül KAPALI: menü öğesi YOK ve belge ucu çağrılmaz', (
      t,
    ) async {
      final auth = _HomeAuth();
      final access = await _access(
        () => <MySiteModules>[_my('manager', documents: false)],
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Belgeler'), findsNothing);
      expect(_server.paths, isEmpty);
      await _disposeHome(t);
    });

    testWidgets(
      'FAIL-OPEN YOK: modül verisi hiç gelmezse Belgeler AÇILMAZ (yönetici ve sakin)',
      (t) async {
        for (final role in <UserRole>[
          UserRole.siteManager,
          UserRole.apartmentOwner,
        ]) {
          final auth = _HomeAuth(role: role)..doors = fxDoors();
          await _pumpHome(
            t,
            auth,
            access: ModuleAccess(fetch: () async => throw StateError('ağ yok')),
          );
          await _openDrawer(t);
          expect(_tileTitle('Belgeler'), findsNothing, reason: '$role');
          await _disposeHome(t);
        }
      },
    );

    testWidgets(
      'modül verisi yüklenirken menü yok; yüklenince AÇIK sitede görünür',
      (t) async {
        final gate = Completer<MyModulesResult>();
        final auth = _HomeAuth();
        final access = ModuleAccess(
          fetch: () => gate.future,
          isSuperUser: () => false,
        );
        addTearDown(access.dispose);
        await _pumpHome(t, auth, access: access);
        await _openDrawer(t);
        expect(_tileTitle('Belgeler'), findsNothing);
        Navigator.of(t.element(find.byType(Drawer))).pop();
        await t.pump();
        await t.pump(const Duration(milliseconds: 450));
        gate.complete(MyModulesResult(sites: <MySiteModules>[_my('manager')]));
        await access.refresh();
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await _openDrawer(t);
        expect(_tileTitle('Belgeler'), findsOneWidget);
        await _disposeHome(t);
      },
    );

    testWidgets(
      'kurul üyesi: Belgeler SALT OKUNUR (not var, yükleme düğmesi yok, salt okur site)',
      (t) async {
        final auth = _HomeAuth(role: UserRole.apartmentOwner);
        final access = await _access(
          () => <MySiteModules>[_my('board_member')],
        );
        await _pumpHome(t, auth, access: access);
        await _tapMenu(t, 'Belgeler');
        expect(find.byType(DocumentsView), findsOneWidget);
        final view = t.widget<DocumentsView>(find.byType(DocumentsView));
        expect(view.manageSites, <PeopleSite>[
          const PeopleSite(code: 11, name: 'Gül Sitesi'),
        ]);
        expect(
          find.byKey(const ValueKey<String>('documents_read_only_note')),
          findsOneWidget,
        );
        expect(find.text('Belge Yükle'), findsNothing);
        expect(auth.listSitesCalls, 0);
        // Kurul üyesi aynı zamanda alıcı site sakini sayılır: iki görünüm seçeneği çıkar.
        expect(
          find.byKey(const ValueKey<String>('documents_mode_resident')),
          findsOneWidget,
        );
        await _disposeHome(t);
      },
    );

    testWidgets('kurul üyesi ama modül KAPALI: Belgeler yok', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[_my('board_member', documents: false)],
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Belgeler'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('yalnız-görevli (staff) ve bireysel kullanıcı: Belgeler yok', (
      t,
    ) async {
      final staff = _HomeAuth(role: UserRole.apartmentOwner);
      await _pumpHome(
        t,
        staff,
        access: await _access(() => <MySiteModules>[_my('staff')]),
      );
      await _openDrawer(t);
      expect(_tileTitle('Belgeler'), findsNothing);
      await _disposeHome(t);

      final individual = _HomeAuth(role: UserRole.individual);
      await _pumpHome(
        t,
        individual,
        access: await _access(() => const <MySiteModules>[]),
      );
      await _openDrawer(t);
      expect(_tileTitle('Belgeler'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Belgeler var (tüm siteler, yazma yetkisi)', (
      t,
    ) async {
      final auth = _HomeAuth(role: UserRole.superUser);
      final access = await _access(
        () => const <MySiteModules>[],
        superUser: true,
      );
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Belgeler');
      expect(find.byType(DocumentsView), findsOneWidget);
      final view = t.widget<DocumentsView>(find.byType(DocumentsView));
      expect(view.manageAllSites, isTrue);
      expect(
        auth.listSitesArgs.any((a) => a.approval == 'approved'),
        isTrue,
        reason: 'tüm onaylı siteler',
      );
      expect(find.text('Belge Yükle'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets(
      'süper kullanıcı: modülü KAPALI sitede açıklayıcı kart + "Modüller" düğmesi Modüller ekranına gider',
      (t) async {
        final auth = _HomeAuth(role: UserRole.superUser);
        _server.moduleOff = true;
        final access = await _access(
          () => const <MySiteModules>[],
          superUser: true,
        );
        await _pumpHome(t, auth, access: access);
        await _tapMenu(t, 'Belgeler');
        expect(
          find.byKey(const ValueKey<String>('documents_module_off')),
          findsOneWidget,
        );
        await tapFinder(
          t,
          find.byKey(const ValueKey<String>('documents_open_modules')),
        );
        await settleFor(t);
        expect(find.byType(ModulesView), findsOneWidget);
        await _disposeHome(t);
      },
    );

    testWidgets(
      'açıkken modül kapatılırsa (poll) seçili Belgeler ekranı Panel\'e düşer, menü kalkar',
      (t) async {
        final auth = _HomeAuth();
        var on = true;
        final access = await _access(
          () => <MySiteModules>[_my('manager', documents: on)],
        );
        await _pumpHome(t, auth, access: access);
        await _tapMenu(t, 'Belgeler');
        expect(find.byType(DocumentsView), findsOneWidget);
        on = false;
        await access.refresh();
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(find.byType(DocumentsView), findsNothing);
        await _openDrawer(t);
        expect(_tileTitle('Belgeler'), findsNothing);
        await _disposeHome(t);
      },
    );
  });

  group('Belgeler menü öğesi (sakin)', () {
    testWidgets(
      'daire sakini + modül AÇIK: Belgeler var; seçilince sakin görünümü, yönetici uçları çağrılmaz',
      (t) async {
        final auth = _HomeAuth(role: UserRole.apartmentOwner)
          ..doors = fxDoors();
        final access = await _access(() => <MySiteModules>[_my('resident')]);
        await _pumpHome(t, auth, access: access);
        await _tapMenu(t, 'Belgeler');
        expect(find.byType(DocumentsView), findsOneWidget);
        expect(find.byType(DocumentResidentView), findsOneWidget);
        expect(find.byType(DocumentAdminView), findsNothing);
        final view = t.widget<DocumentsView>(find.byType(DocumentsView));
        expect(view.showResident, isTrue);
        expect(view.manageSites, isEmpty);
        expect(view.residentSites, <PeopleSite>[
          const PeopleSite(code: 11, name: 'Gül Sitesi'),
        ]);
        expect(_server.paths.where((p) => p.startsWith('/manager/')), isEmpty);
        expect(_server.paths, contains('/app/documents'));
        expect(
          find.text('Henüz belge yok.'),
          findsOneWidget,
          reason: 'sunucu gerçekten boş döndü',
        );
        expect(find.byType(DocumentResidentCard), findsNothing);
        await _disposeHome(t);
      },
    );

    testWidgets('modül KAPALI sitede sakin: Belgeler YOK', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[_my('resident', documents: false)],
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Belgeler'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('iki siteli sakin: yalnız modülü AÇIK site listelenir', (
      t,
    ) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', documents: false),
          _my('resident', code: 12, name: 'Mavi Park'),
        ],
      );
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Belgeler');
      final view = t.widget<DocumentsView>(find.byType(DocumentsView));
      expect(view.residentSites, <PeopleSite>[
        const PeopleSite(code: 12, name: 'Mavi Park'),
      ]);
      await _disposeHome(t);
    });

    testWidgets(
      'sakin modundaki yönetici: Belgeler (sakin görünümü); yönetici moduna dönünce yönetim görünümü',
      (t) async {
        final auth = _HomeAuth();
        final access = await _access(() => <MySiteModules>[_my('manager')]);
        await _pumpHome(t, auth, access: access);
        await _tapMenu(t, 'Belgeler');
        expect(find.byType(DocumentAdminView), findsOneWidget);
        await _openDrawer(t);
        await t.tap(find.text('Sakin Moduna Geç'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        await _tapMenu(t, 'Belgeler');
        expect(
          find.byType(DocumentResidentView),
          findsOneWidget,
          reason: 'sakin modunda yönetim yazma yetkisi yok',
        );
        expect(find.byType(DocumentAdminView), findsNothing);
        await _disposeHome(t);
      },
    );

    testWidgets('çekip yenileme belge listesini yeniden çeker', (t) async {
      final auth = _HomeAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Belgeler');
      final calls = _server.paths.where((p) => p == '/app/documents').length;
      await t.state<DocumentsViewState>(find.byType(DocumentsView)).reload();
      await settleFor(t);
      expect(
        _server.paths.where((p) => p == '/app/documents').length,
        calls + 1,
      );
      await _disposeHome(t);
    });
  });
}
