// FAZ 5 / A3: ana panel kabuğu (home_page.dart) — AppBar, PageEntry ve kapı açma başarı sinyali.
//
// Kapsam:
// - AppBar taşmaz: 320x640 x2,0 ve 360x640 x1,5 dahil 7 boyut/ölçek x açık+koyu; çift modlu rolde
//   "hap + 3 ikon" (Android'de widget düğmesi dahil); eylem düğmeleri >= 44 dp; araç çubuğu 56 dp kalır
//   ve alt başlık bloğu yazı ölçeğiyle büyür (50 + ölçek farkı).
// - "Sakin Modu / Yönetici Paneli" hapı: dar ekranda (< 400 dp) ya da büyük yazıda (> 1,3x) yalnız ikon
//   (Tooltip + Semantics etiketi), aksi hâlde etiketli; dokununca mod değişir (davranış korunur).
// - PageEntry: menü (ya da mod) değişince TEK içerik, anahtar `menü-mod`; yoklama yeniden kurması giriş
//   animasyonunu yeniden başlatmaz; hareket azaltmada içerik anında tam.
// - Kapı açma başarı sinyali (_doorOpenOkTick -> DashboardView.successTick -> DoorOpenButton).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/theme_toggle_button.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/admin_door_status_card.dart';

import '../design/harness.dart' show recordHaptics;
import '../support/rebuild_probe.dart';

final SiteRecord _site = SiteRecord(
  id: 1,
  name: 'A Sitesi',
  address: null,
  city: null,
  district: null,
  blockCount: 1,
  apartmentCount: 4,
  doorCount: 1,
  approvalStatus: 'approved',
  approvedAt: DateTime(2026, 1, 1),
  mqttSiteId: 1,
  managerUserCode: 5,
  managerName: 'Yönetici',
  createdAt: DateTime(2026, 1, 1),
);

final DoorRecord _door = DoorRecord(
  id: 11,
  siteCode: 1,
  siteName: 'A Sitesi',
  doorName: 'A Kapısı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'AABBCCDD',
  mqttSiteId: 1,
  createdAt: DateTime(2026, 1, 1),
);

DoorRuntimeStatus _status({bool online = true, int rssi = -50}) =>
    DoorRuntimeStatus.fromJson({
      'door': {
        'id': 11,
        'site_code': 1,
        'door_name': 'A Kapısı',
        'door_index': 1,
      },
      'device_status': {
        'device_uid': 'AABBCCDD',
        'mqtt_connected': online,
        'mqtt_bridge_connected': true,
        'wifi_rssi': rssi,
        'firmware_version': '1.0.0',
      },
    });

UserSession _sessionFor(UserRole role) => UserSession(
  id: role == UserRole.superUser ? 1 : 5,
  fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Site Yöneticisi',
  email: 'kullanici@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 'tok',
);

typedef _OpenHandler = Future<(DoorRuntimeStatus?, String?)> Function(int call);
typedef _StatusHandler =
    Future<(DoorRuntimeStatus?, String?)> Function(int call);

/// HomePage için sahte servis: site yöneticisi / süper kullanıcı / bireysel; kapı açma ve durum
/// yanıtları testten sürülür.
class _ShellAuth extends AuthService {
  _ShellAuth({
    this.role = UserRole.siteManager,
    _OpenHandler? openHandler,
    _StatusHandler? statusHandler,
  }) : openHandler = openHandler ?? ((_) async => (null, null)),
       statusHandler = statusHandler ?? ((_) async => (_status(), null)),
       super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;
  _OpenHandler openHandler;
  _StatusHandler statusHandler;
  int openDoorCalls = 0;
  int statusCalls = 0;

  @override
  UserSession? get session => _sessionFor(role);

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async => SitePage(sites: [_site], total: 1, page: 1, pageSize: 100);

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({
    required int siteCode,
  }) async => (
    SiteStructureRecord(
      site: _site,
      blocks: const <SiteBlockRecord>[],
      apartments: const <ApartmentRecord>[],
      doors: [_door],
    ),
    null,
  );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (
    role == UserRole.individual || role == UserRole.apartmentOwner
        ? <DoorRecord>[_door]
        : <DoorRecord>[],
    null,
  );

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({
    required int doorId,
  }) {
    statusCalls++;
    return statusHandler(statusCalls);
  }

  @override
  Future<(DoorRuntimeStatus?, String?)> openDoor({
    required int doorId,
    DoorRecord? door,
  }) {
    openDoorCalls++;
    return openHandler(openDoorCalls);
  }

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}

  // Resident modu / bireysel ana görünüm (IndividualHomeView) için boş yanıtlar.
  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async =>
      <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);
}

/// HomePage'i verilen boyut/yazı ölçeği/temada kurar. Uygulama kökündeki gibi MaterialApp + AppTheme.
Future<void> _pumpShell(
  WidgetTester tester,
  _ShellAuth auth, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
  bool plainTheme = false,
  bool themeToggle = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final app = MaterialApp(
    // plainTheme: AppTheme'in `standard` yoğunluk/48 dp hedef ayarları OLMADAN (masaüstü varsayılanı).
    theme: plainTheme ? ThemeData(useMaterial3: true) : AppTheme.light(),
    darkTheme: plainTheme ? null : AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduce,
      ),
      child: child!,
    ),
    home: HomePage(authService: auth),
  );
  // themeToggle: uygulama kökündeki gibi ThemeScope var -> AppBar'da aydınlık/karanlık geçiş düğmesi çizilir.
  await tester.pumpWidget(
    themeToggle ? ThemeScope(service: ThemeService(), child: app) : app,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Yoklama zamanlayıcısı ve girişler kalmasın (flutter_test "Timer is still pending" demesin).
Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester, String label) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).first);
  await tester.pump();
}

Finder _inAppBar(Finder f) =>
    find.descendant(of: find.byType(AppBar), matching: f);

/// Hapın kendisi: etiketli hâlde etiket metninin InkWell'i, yalnız ikonda Tooltip.
Finder _pillOf(String label, {required bool iconOnly}) {
  if (iconOnly) return _inAppBar(find.byTooltip(label));
  return find
      .ancestor(of: _inAppBar(find.text(label)), matching: find.byType(InkWell))
      .first;
}

bool _expectedIconOnly(double width, double scale) =>
    width < 400 || scale > 1.3;

/// AppBar'ın taşmadığını, dokunma hedeflerini ve yükseklik sözleşmesini doğrular.
void _expectAppBarFits(
  WidgetTester tester, {
  required double width,
  required double scale,
  required bool widgetAction,
  required bool dual,
  bool resident = false,
  String title = 'AHBU Panel',
  bool themeToggle = false,
  bool dark = false,
}) {
  expect(tester.takeException(), isNull, reason: 'RenderFlex taşması yok');

  final bar = tester.getRect(find.byType(AppBar));
  final toolbar = tester.getRect(_inAppBar(find.byType(NavigationToolbar)));

  // Alt başlık bloğu (18 + 12 punto, satır yüksekliği 1,2) yazı ölçeğiyle büyür: 12 + 2 + 2 (yuvarlama payı)
  // + 1,2 x (ölçekli 18 + ölçekli 12). Araç çubuğu 56 dp kalır (eylem düğmeleri sıkışmaz).
  final scaler = TextScaler.linear(scale);
  final bottom = 16 + 1.2 * (scaler.scale(18) + scaler.scale(12));
  expect(
    bar.height,
    closeTo(kToolbarHeight + bottom, 0.01),
    reason: 'AppBar = araç çubuğu 56 + alt başlık bloğu (ölçekle büyür)',
  );
  expect(
    toolbar.height,
    closeTo(kToolbarHeight, 0.01),
    reason: 'alt başlık bloğu araç çubuğunu sıkıştırmaz',
  );

  // Başlık ve alt satır araç çubuğunun altında, AppBar içinde.
  for (final text in <Finder>[
    _inAppBar(find.text(title)),
    _inAppBar(find.textContaining('•')),
  ]) {
    final r = tester.getRect(text);
    expect(r.top, greaterThanOrEqualTo(toolbar.bottom - 0.01));
    expect(r.bottom, lessThanOrEqualTo(bar.bottom + 0.01));
    expect(r.right, lessThanOrEqualTo(width + 0.01));
  }

  // Eylem düğmeleri: >= 44 dp ve ekranın içinde; menü düğmesiyle (48 dp) çakışmaz.
  final icons = <IconData>[
    Icons.refresh_rounded,
    Icons.logout_rounded,
    if (widgetAction) Icons.widgets_outlined,
    // Tema düğmesi, geçilecek temayı gösterir: aydınlıkta ay, karanlıkta güneş.
    if (themeToggle) dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
  ];
  for (final icon in icons) {
    final button = _inAppBar(find.widgetWithIcon(IconButton, icon));
    expect(button, findsOneWidget, reason: '$icon düğmesi');
    final r = tester.getRect(button);
    expect(r.width, greaterThanOrEqualTo(44), reason: '$icon genişlik');
    expect(r.height, greaterThanOrEqualTo(44), reason: '$icon yükseklik');
    expect(
      r.left,
      greaterThanOrEqualTo(48 - 0.01),
      reason: '$icon menü düğmesine binmez',
    );
    expect(
      r.right,
      lessThanOrEqualTo(width + 0.01),
      reason: '$icon ekran içinde',
    );
  }

  // Hap.
  final label = resident ? 'Yönetici Paneli' : 'Sakin Modu';
  if (!dual) {
    expect(_inAppBar(find.byTooltip(label)), findsNothing);
    expect(_inAppBar(find.text(label)), findsNothing);
    return;
  }
  final iconOnly = _expectedIconOnly(width, scale);
  final pill = _pillOf(label, iconOnly: iconOnly);
  expect(pill, findsOneWidget, reason: 'hap ($label, iconOnly=$iconOnly)');
  if (iconOnly) {
    expect(
      _inAppBar(find.text(label)),
      findsNothing,
      reason: 'yalnız ikon: görünür metin yok',
    );
  } else {
    expect(
      _inAppBar(find.byTooltip(label)),
      findsNothing,
      reason: 'etiketli hap Tooltip taşımaz',
    );
  }
  final pr = tester.getRect(pill);
  expect(pr.height, greaterThanOrEqualTo(44), reason: 'hap yüksekliği');
  expect(pr.width, greaterThanOrEqualTo(44), reason: 'hap genişliği');
  expect(
    pr.left,
    greaterThanOrEqualTo(48 - 0.01),
    reason: 'hap menü düğmesine binmez',
  );
  expect(pr.right, lessThanOrEqualTo(width + 0.01), reason: 'hap ekran içinde');
  // Hap en soldaki eylemdir: yanındaki düğmelerle çakışmaz.
  for (final icon in icons) {
    final ir = tester.getRect(_inAppBar(find.widgetWithIcon(IconButton, icon)));
    expect(
      pr.right,
      lessThanOrEqualTo(ir.left + 0.01),
      reason: 'hap $icon ile çakışmaz',
    );
  }
}

void main() {
  tearDown(RebuildProbe.stop);

  group(
    'AppBar taşmaz: boyut x yazı ölçeği x tema (çift modlu site yöneticisi, Android: hap + 3 ikon)',
    () {
      const cells = <({double width, double height, double scale})>[
        (width: 360, height: 640, scale: 1.5), // spesifikasyon hücresi
        (width: 320, height: 640, scale: 2.0), // en küçük + en büyük yazı
        (width: 360, height: 640, scale: 1.0), // < 400 dp: yalnız ikon
        (width: 412, height: 915, scale: 1.0), // etiketli hap (sınırın üstünde)
        (width: 412, height: 915, scale: 1.3), // sınır: 1,3 hâlâ etiketli
        (width: 412, height: 915, scale: 1.5), // 1,3'ün üstü: yalnız ikon
        (width: 820, height: 1180, scale: 1.0), // tablet
      ];
      for (final c in cells) {
        for (final dark in const <bool>[false, true]) {
          testWidgets(
            '${c.width.toInt()}x${c.height.toInt()} x${c.scale} ${dark ? 'koyu' : 'açık'}',
            (tester) async {
              final auth = _ShellAuth();
              await _pumpShell(
                tester,
                auth,
                width: c.width,
                height: c.height,
                scale: c.scale,
                dark: dark,
              );
              expect(find.byType(AdminDoorStatusCard), findsOneWidget);
              _expectAppBarFits(
                tester,
                width: c.width,
                scale: c.scale,
                widgetAction: true,
                dual: true,
              );
              await _disposeShell(tester);
            },
          );
        }
      }
    },
  );

  group(
    'AppBar + tema düğmesi (ThemeScope var): hap + widget + tema + yenile + çıkış taşmaz, hedefler >= 44 dp',
    () {
      const cells = <({double width, double height, double scale})>[
        (width: 320, height: 640, scale: 2.0), // en kötü: en dar + en büyük yazı
        (width: 360, height: 640, scale: 1.5),
        (width: 412, height: 915, scale: 1.0), // etiketli hap
        (width: 820, height: 1180, scale: 1.0), // tablet
      ];
      for (final c in cells) {
        for (final dark in const <bool>[false, true]) {
          testWidgets(
            '${c.width.toInt()}x${c.height.toInt()} x${c.scale} ${dark ? 'koyu' : 'açık'}',
            (tester) async {
              final auth = _ShellAuth();
              await _pumpShell(
                tester,
                auth,
                width: c.width,
                height: c.height,
                scale: c.scale,
                dark: dark,
                themeToggle: true,
              );
              expect(find.byType(AdminDoorStatusCard), findsOneWidget);
              _expectAppBarFits(
                tester,
                width: c.width,
                scale: c.scale,
                widgetAction: true,
                dual: true,
                themeToggle: true,
                dark: dark,
              );
              await _disposeShell(tester);
            },
          );
        }
      }

      testWidgets('süper kullanıcı (widget düğmesi yok) 320x640 x2,0 tema düğmesiyle taşmaz', (tester) async {
        final auth = _ShellAuth(role: UserRole.superUser);
        await _pumpShell(tester, auth, width: 320, scale: 2.0, themeToggle: true);
        _expectAppBarFits(
          tester,
          width: 320,
          scale: 2.0,
          widgetAction: false,
          dual: true,
          themeToggle: true,
        );
        await _disposeShell(tester);
      });
    },
  );

  group('AppBar: öteki roller ve platformlar', () {
    testWidgets(
      'Sakin Modu (yönetici etiketi, "Yönetici Paneli") 320x640 x2,0 ve 412x915 x1,0 taşmaz',
      (tester) async {
        for (final c in const <({double w, double h, double s})>[
          (w: 320, h: 640, s: 2.0),
          (w: 412, h: 915, s: 1.0),
          (w: 820, h: 1180, s: 1.0),
        ]) {
          final auth = _ShellAuth();
          await _pumpShell(tester, auth, width: c.w, height: c.h, scale: c.s);
          // Hapa dokun: Sakin Moduna geç (IndividualHomeView).
          await tester.tap(
            _pillOf('Sakin Modu', iconOnly: _expectedIconOnly(c.w, c.s)),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(IndividualHomeView), findsOneWidget);
          _expectAppBarFits(
            tester,
            width: c.w,
            scale: c.s,
            widgetAction: true,
            dual: true,
            resident: true,
          );
          await _disposeShell(tester);
        }
      },
    );

    testWidgets(
      'süper kullanıcı (widget düğmesi yok: hap + 2 ikon) 360x640 x1,5 ve 320x640 x2,0 taşmaz',
      (tester) async {
        for (final dark in const <bool>[false, true]) {
          for (final c in const <({double w, double s})>[
            (w: 360, s: 1.5),
            (w: 320, s: 2.0),
          ]) {
            final auth = _ShellAuth(role: UserRole.superUser);
            await _pumpShell(tester, auth, width: c.w, scale: c.s, dark: dark);
            _expectAppBarFits(
              tester,
              width: c.w,
              scale: c.s,
              widgetAction: false,
              dual: true,
            );
            await _disposeShell(tester);
          }
        }
      },
    );

    testWidgets(
      'masaüstü platformu: widget iğneleme düğmesi yok; AppBar yine taşmaz',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final auth = _ShellAuth();
          await _pumpShell(tester, auth, width: 360, scale: 1.5);
          expect(
            _inAppBar(find.byTooltip('Masaüstüne Widget Ekle')),
            findsNothing,
          );
          _expectAppBarFits(
            tester,
            width: 360,
            scale: 1.5,
            widgetAction: false,
            dual: true,
          );
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'masaüstü + varsayılan tema (compact yoğunluk, shrinkWrap hedef): eylem düğmeleri ve hap yine tam 44 dp',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final auth = _ShellAuth();
          await _pumpShell(
            tester,
            auth,
            width: 820,
            height: 1180,
            plainTheme: true,
          );
          // Varsayılan Windows teması: compact yoğunluk + shrinkWrap hedef (düğmeyi 36 dp'ye indirirdi).
          expect(
            Theme.of(tester.element(find.byType(AppBar))).visualDensity,
            VisualDensity.compact,
          );
          for (final icon in <IconData>[
            Icons.refresh_rounded,
            Icons.logout_rounded,
          ]) {
            final r = tester.getRect(
              _inAppBar(find.widgetWithIcon(IconButton, icon)),
            );
            expect(r.width, closeTo(44, 0.01), reason: '$icon genişlik');
            expect(r.height, closeTo(44, 0.01), reason: '$icon yükseklik');
          }
          expect(
            tester.getSize(_pillOf('Sakin Modu', iconOnly: false)).height,
            greaterThanOrEqualTo(44),
          );
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'çift modlu olmayan rol (sitesiz bireysel): hap yok, 3 ikon 44 dp',
      (tester) async {
        final auth = _ShellAuth(role: UserRole.individual);
        await _pumpShell(tester, auth, width: 360, scale: 1.5);
        expect(find.byType(IndividualHomeView), findsOneWidget);
        _expectAppBarFits(
          tester,
          width: 360,
          scale: 1.5,
          widgetAction: true,
          dual: false,
        );
        await _disposeShell(tester);
      },
    );

    testWidgets(
      'eylem düğmeleri çalışır: Yenile ve Çıkış Yap araç ipuçlarını korur',
      (tester) async {
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 360, scale: 1.5);
        expect(_inAppBar(find.byTooltip('Yenile')), findsOneWidget);
        expect(_inAppBar(find.byTooltip('Çıkış Yap')), findsOneWidget);
        expect(
          _inAppBar(find.byTooltip('Masaüstüne Widget Ekle')),
          findsOneWidget,
        );
        final before = auth.statusCalls;
        await tester.tap(_inAppBar(find.byTooltip('Yenile')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          auth.statusCalls,
          greaterThan(before),
          reason: 'Yenile kapı durumunu yeniden yükler',
        );
        await _disposeShell(tester);
      },
    );
  });

  group('mod hapı (Sakin Modu / Yönetici Paneli)', () {
    testWidgets(
      'dar ekranda yalnız ikon: Tooltip + Semantics etiketi; dokununca mod değişir',
      (tester) async {
        final handle = tester.ensureSemantics();
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 360, scale: 1.0);

        expect(find.text('Sakin Modu'), findsNothing);
        expect(_inAppBar(find.byTooltip('Sakin Modu')), findsOneWidget);
        expect(
          find.bySemanticsLabel('Sakin Modu'),
          findsOneWidget,
          reason: 'ekran okuyucu etiketi (Tooltip anlamı çiftlenmez)',
        );
        expect(
          tester.getSemantics(
            find.descendant(
              of: _pillOf('Sakin Modu', iconOnly: true),
              matching: find.byType(InkWell),
            ),
          ),
          isSemantics(label: 'Sakin Modu', isButton: true, hasTapAction: true),
          reason: 'hap kendi düğümüdür (AppBar düğümüne karışmaz)',
        );

        await tester.tap(_pillOf('Sakin Modu', iconOnly: true));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_inAppBar(find.byTooltip('Yönetici Paneli')), findsOneWidget);
        expect(_inAppBar(find.byTooltip('Sakin Modu')), findsNothing);
        expect(find.byType(IndividualHomeView), findsOneWidget);
        expect(find.byType(DashboardView), findsNothing);
        // Alt satır artık "Sakin Modu" der (mevcut davranış).
        expect(find.textContaining('• Sakin Modu'), findsOneWidget);

        await tester.tap(_pillOf('Yönetici Paneli', iconOnly: true));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DashboardView), findsOneWidget);
        expect(find.byType(IndividualHomeView), findsNothing);
        expect(_inAppBar(find.byTooltip('Sakin Modu')), findsOneWidget);
        await _disposeShell(tester);
        handle.dispose();
      },
    );

    testWidgets(
      'geniş ekranda etiketli hap (>= 400 dp, <= 1,3x): metin görünür, 44 dp, dokununca değişir',
      (tester) async {
        final handle = tester.ensureSemantics();
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 820, height: 1180, scale: 1.0);

        expect(_inAppBar(find.text('Sakin Modu')), findsOneWidget);
        final pill = _pillOf('Sakin Modu', iconOnly: false);
        expect(tester.getSize(pill).height, greaterThanOrEqualTo(44));
        expect(
          tester.getSemantics(pill),
          isSemantics(label: 'Sakin Modu', isButton: true, hasTapAction: true),
        );
        await tester.tap(pill);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_inAppBar(find.text('Yönetici Paneli')), findsOneWidget);
        expect(_inAppBar(find.text('Sakin Modu')), findsNothing);
        await _disposeShell(tester);
        handle.dispose();
      },
    );

    testWidgets(
      'eşik: 400 dp ve 1,3x etiketli; 399 dp ya da 1,31x yalnız ikon',
      (tester) async {
        for (final c in const <({double w, double s, bool iconOnly})>[
          (w: 400, s: 1.3, iconOnly: false),
          (w: 399, s: 1.0, iconOnly: true),
          (w: 400, s: 1.31, iconOnly: true),
        ]) {
          final auth = _ShellAuth();
          await _pumpShell(tester, auth, width: c.w, scale: c.s);
          expect(
            _inAppBar(find.text('Sakin Modu')),
            c.iconOnly ? findsNothing : findsOneWidget,
            reason: '${c.w} dp x${c.s}',
          );
          expect(
            _inAppBar(find.byTooltip('Sakin Modu')),
            c.iconOnly ? findsOneWidget : findsNothing,
            reason: '${c.w} dp x${c.s}',
          );
          expect(tester.takeException(), isNull);
          await _disposeShell(tester);
        }
      },
    );

    testWidgets(
      'etiketli hap kalan genişliği aşarsa üç nokta ile kısalır (taşma yok)',
      (tester) async {
        // 400 dp x1,3: test yazı tipinde (Ahem: harf = punto) uzun etiket sığmaz; gerçek yazı tipinde sığar.
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 400, scale: 1.3);
        await tester.tap(_pillOf('Sakin Modu', iconOnly: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final label = _inAppBar(find.text('Yönetici Paneli'));
        expect(label, findsOneWidget);
        final text = tester.widget<Text>(label);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
        final pr = tester.getRect(_pillOf('Yönetici Paneli', iconOnly: false));
        expect(pr.right, lessThanOrEqualTo(400 + 0.01));
        expect(pr.left, greaterThanOrEqualTo(48 - 0.01));
        await _disposeShell(tester);
      },
    );
  });

  group('PageEntry: menü değişince tek içerik (çift widget yok)', () {
    FadeTransition entryFade(WidgetTester t) => t.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(PageEntry),
            matching: find.byType(FadeTransition),
          )
          .first,
    );

    testWidgets('içerik tek PageEntry içinde; anahtar menü-mod', (
      tester,
    ) async {
      final auth = _ShellAuth();
      await _pumpShell(tester, auth);
      expect(find.byType(PageEntry), findsOneWidget);
      expect(
        tester.widget<PageEntry>(find.byType(PageEntry)).key,
        const ValueKey<String>('dashboard-false'),
      );
      expect(find.byType(DashboardView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PageEntry),
          matching: find.byType(DashboardView),
        ),
        findsOneWidget,
        reason: 'panel PageEntry içinde',
      );
      await _disposeShell(tester);
    });

    testWidgets(
      'menü değişince yalnız yeni içerik gelir: eski içerik animasyon sırasında da ağaçta yok, anahtar değişir',
      (tester) async {
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 400, height: 1400);

        await _openMenu(tester, 'Profilim');
        await tester.pump(
          const Duration(milliseconds: 50),
        ); // giriş animasyonu sürüyor
        expect(find.byType(PageEntry), findsOneWidget, reason: 'tek PageEntry');
        expect(
          tester.widget<PageEntry>(find.byType(PageEntry)).key,
          const ValueKey<String>('profilim-false'),
        );
        expect(find.byType(ProfileView), findsOneWidget);
        expect(
          find.byType(DashboardView),
          findsNothing,
          reason: 'eski panel hemen kalkar (AnimatedSwitcher yok)',
        );
        expect(find.byType(AdminDoorStatusCard), findsNothing);
        final mid = entryFade(tester).opacity.value;
        expect(mid, greaterThan(0.0));
        expect(mid, lessThan(1.0), reason: 'yeni içerik solarak gelir');

        await tester.pump(const Duration(milliseconds: 300));
        expect(entryFade(tester).opacity.value, 1.0);
        expect(find.byType(PageEntry), findsOneWidget);

        // Geri: Panel.
        await _openMenu(tester, 'Panel');
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(PageEntry), findsOneWidget);
        expect(
          tester.widget<PageEntry>(find.byType(PageEntry)).key,
          const ValueKey<String>('dashboard-false'),
        );
        expect(find.byType(DashboardView), findsOneWidget);
        expect(find.byType(ProfileView), findsNothing);
        expect(tester.takeException(), isNull);
        await _disposeShell(tester);
      },
    );

    testWidgets(
      'mod değişince de anahtar değişir; GlobalKey çakışması yok (bireysel görünüm tek)',
      (tester) async {
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 820, height: 1180);

        await tester.tap(_pillOf('Sakin Modu', iconOnly: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(PageEntry), findsOneWidget);
        expect(
          tester.widget<PageEntry>(find.byType(PageEntry)).key,
          const ValueKey<String>('dashboard-true'),
        );
        expect(find.byType(IndividualHomeView), findsOneWidget);
        expect(find.byType(DashboardView), findsNothing);

        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(_pillOf('Yönetici Paneli', iconOnly: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.widget<PageEntry>(find.byType(PageEntry)).key,
          const ValueKey<String>('dashboard-false'),
        );
        expect(find.byType(DashboardView), findsOneWidget);
        expect(find.byType(IndividualHomeView), findsNothing);
        expect(
          tester.takeException(),
          isNull,
          reason: 'GlobalKey/çift widget hatası yok',
        );
        await _disposeShell(tester);
      },
    );

    testWidgets('hareket azaltma: içerik anında tam opak (kayma/solma yok)', (
      tester,
    ) async {
      final auth = _ShellAuth();
      await _pumpShell(tester, auth, width: 400, height: 1400, reduce: true);
      expect(entryFade(tester).opacity.value, 1.0);

      await _openMenu(tester, 'Profilim');
      await tester.pump(); // tek kare
      expect(find.byType(ProfileView), findsOneWidget);
      expect(entryFade(tester).opacity.value, 1.0);
      await _disposeShell(tester);
    });

    testWidgets(
      'yoklama sonucu değişince PageEntry yeniden başlamaz (giriş animasyonu tekrarlanmaz, durum korunur)',
      (tester) async {
        final auth = _ShellAuth(
          statusHandler: (i) async =>
              (_status(online: i.isOdd, rssi: -40 - i), null),
        );
        await _pumpShell(tester, auth, width: 400, height: 1400);
        await tester.pump(const Duration(milliseconds: 400)); // giriş bitti
        expect(entryFade(tester).opacity.value, 1.0);
        final stateBefore = tester.state(find.byType(PageEntry));

        RebuildProbe.start();
        for (var t = 0; t < 7000; t += 500) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(
          RebuildProbe.count(AdminDoorStatusCard),
          greaterThanOrEqualTo(2),
          reason: 'yoklama kapı panelini yeniden kurdu (sonuç değişiyor)',
        );
        expect(RebuildProbe.count(Scaffold), 0);
        expect(
          identical(tester.state(find.byType(PageEntry)), stateBefore),
          isTrue,
          reason: 'aynı anahtar: PageEntry yeniden yaratılmaz',
        );
        expect(
          entryFade(tester).opacity.value,
          1.0,
          reason: 'animasyon yeniden başlamadı',
        );
        await _disposeShell(tester);
      },
    );
  });

  group('kapı açma başarı sinyali (_doorOpenOkTick -> successTick)', () {
    Finder openButton() =>
        find.byKey(const ValueKey<String>('admin_door_open_button'));

    int tick(WidgetTester t) =>
        t.widget<DashboardView>(find.byType(DashboardView)).successTick;

    testWidgets(
      'varsayılan 0; başarıda 1 olur ve düğme "Gönderildi" tikini gösterip 1,4 sn sonra geri döner',
      (tester) async {
        final haptics = recordHaptics(tester);
        final completer = Completer<(DoorRuntimeStatus?, String?)>();
        final auth = _ShellAuth(openHandler: (_) => completer.future);
        await _pumpShell(tester, auth, width: 400, height: 1400);

        expect(tick(tester), 0);
        expect(find.text('Kapı Aç'), findsOneWidget);
        expect(find.text('Gönderildi'), findsNothing);

        await tester.tap(openButton());
        await tester.pump();
        expect(auth.openDoorCalls, 1);
        expect(
          find.text('Gönderiliyor...'),
          findsOneWidget,
          reason: 'komut sürerken spinner durumu',
        );
        expect(tick(tester), 0, reason: 'başarı henüz yok');

        completer.complete((null, null)); // başarı
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tick(tester), 1, reason: '_openDoor başarısında sayaç artar');
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(find.text('Gönderiliyor...'), findsNothing);
        expect(
          tester.widget<DoorOpenButton>(openButton()).successTick,
          1,
          reason: 'DashboardView -> AdminDoorStatusCard -> DoorOpenButton',
        );
        expect(haptics, contains('HapticFeedbackType.lightImpact'));
        expect(
          find.text('Kapı açma komutu gönderildi.'),
          findsOneWidget,
          reason: 'mevcut SnackBar korunur',
        );

        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.text('Gönderildi'), findsNothing);
        expect(
          find.text('Kapı Aç'),
          findsOneWidget,
          reason: 'tik 1,4 sn sonra geri döner',
        );
        expect(tick(tester), 1, reason: 'sayaç geri sarılmaz');
        await _disposeShell(tester);
      },
    );

    testWidgets(
      'hata dönerse sayaç artmaz, tik gösterilmez; hata SnackBar\'ı korunur',
      (tester) async {
        recordHaptics(tester);
        final auth = _ShellAuth(
          openHandler: (_) async =>
              (null, 'Bu kapı için uygulamadan açma kapalı.'),
        );
        await _pumpShell(tester, auth, width: 400, height: 1400);

        await tester.tap(openButton());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(auth.openDoorCalls, 1);
        expect(tick(tester), 0);
        expect(find.text('Gönderildi'), findsNothing);
        expect(
          find.text('Bu kapı için uygulamadan açma kapalı.'),
          findsWidgets,
        );
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.text('Gönderildi'), findsNothing);
        await _disposeShell(tester);
      },
    );

    testWidgets('her başarılı açmada sayaç bir artar (1 -> 2)', (tester) async {
      recordHaptics(tester);
      final auth = _ShellAuth();
      await _pumpShell(tester, auth, width: 400, height: 1400);

      await tester.tap(openButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tick(tester), 1);
      await tester.pump(const Duration(milliseconds: 1500)); // tik geri döndü

      await tester.tap(openButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(auth.openDoorCalls, 2);
      expect(tick(tester), 2);
      expect(find.text('Gönderildi'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await _disposeShell(tester);
    });

    testWidgets(
      'daire sakini kartında da (ResidentDoorRemoteCard, daire düğme) başarı tiki gelir',
      (tester) async {
        recordHaptics(tester);
        final completer = Completer<(DoorRuntimeStatus?, String?)>();
        final auth = _ShellAuth(
          role: UserRole.apartmentOwner,
          openHandler: (_) => completer.future,
        );
        await _pumpShell(tester, auth, width: 400, height: 1400);
        final button = find.byKey(
          const ValueKey<String>('resident_door_open_button'),
        );
        expect(button, findsOneWidget);
        expect(tester.widget<DoorOpenButton>(button).successTick, 0);
        expect(tick(tester), 0);

        await tester.tap(button);
        await tester.pump();
        expect(auth.openDoorCalls, 1);
        completer.complete((null, null));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tick(tester), 1);
        expect(tester.widget<DoorOpenButton>(button).successTick, 1);
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        await _disposeShell(tester);
      },
    );

    testWidgets(
      'hareket azaltmada da sinyal gelir (tik anında); taşma yok (320x640 x2,0)',
      (tester) async {
        recordHaptics(tester);
        final auth = _ShellAuth();
        await _pumpShell(tester, auth, width: 320, scale: 2.0, reduce: true);
        await tester.ensureVisible(openButton());
        await tester.pump();
        await tester.tap(openButton());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tick(tester), 1);
        expect(find.text('Gönderildi'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 1500));
        await _disposeShell(tester);
      },
    );
  });
}
