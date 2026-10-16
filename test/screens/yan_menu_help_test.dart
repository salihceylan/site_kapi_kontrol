// Çekmecede "Yardım ve Destek" girişi (YanMenu.onOpenHelp) ve HomePage bağlantısı.
//
// onOpenHelp verilmezse menü ESKİSİ GİBİDİR (öğe sayıları değişmez); verilirse "Çıkış Yap"ın hemen üstüne bir
// ListTile eklenir, sayfa seçimi YAPMAZ (ayrı ekran açar). HomePage: dokununca HelpView rolle açılır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/help_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';
import '../legal_fixtures.dart';

Future<List<String>> _pumpMenu(
  WidgetTester t,
  UserRole role, {
  VoidCallback? onOpenHelp,
  ValueChanged<SirketMenuItem>? onSelect,
  double width = 360,
  double height = 1400,
  double scale = 1.0,
  bool toggle = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    harnessApp(
      SizedBox(
        height: height,
        child: YanMenu(
          fullName: 'Ali Veli',
          userEmail: 'ali@example.com',
          role: role,
          selectedItem: SirketMenuItem.dashboard,
          onSelect: onSelect ?? (_) {},
          onLogout: () {},
          onOpenHelp: onOpenHelp,
          canToggleMode: toggle,
          onToggleMode: toggle ? () {} : null,
        ),
      ),
      scale: scale,
    ),
  );
  await t.pump(const Duration(milliseconds: 450));
  final tiles = find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile));
  return <String>[
    for (var i = 0; i < tiles.evaluate().length; i++) ((t.widget<ListTile>(tiles.at(i))).title! as Text).data!,
  ];
}

class _HomeAuth extends AuthService {
  _HomeAuth(this._role) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole _role;

  @override
  UserSession? get session => UserSession(
    id: 5,
    fullName: 'Test Kullanıcı',
    email: 'test@example.com',
    loginName: null,
    role: _role,
    isActive: true,
    token: 'tok',
  );

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async =>
      SitePage(sites: const <SiteRecord>[], total: 0, page: 1, pageSize: pageSize);

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;
}

void main() {
  group('YanMenu.onOpenHelp', () {
    testWidgets('verilmezse menü ESKİSİ GİBİ: hiçbir rolde "Yardım ve Destek" yok', (t) async {
      for (final role in UserRole.values) {
        expect(await _pumpMenu(t, role), isNot(contains('Yardım ve Destek')), reason: role.name);
      }
      expect(await _pumpMenu(t, UserRole.apartmentOwner), <String>[
        'Panel',
        'Daireye Katıl & Cihaz Ekle',
        'Eller Serbest & Kestirmeler',
        'Profilim',
        'Çıkış Yap',
      ]);
    });

    testWidgets('verilince "Çıkış Yap"ın hemen üstüne eklenir; diğer öğeler değişmez', (t) async {
      for (final role in UserRole.values) {
        final without = await _pumpMenu(t, role);
        final withHelp = await _pumpMenu(t, role, onOpenHelp: () {});
        expect(withHelp.length, without.length + 1, reason: role.name);
        expect(withHelp[withHelp.length - 2], 'Yardım ve Destek', reason: role.name);
        expect(withHelp.last, 'Çıkış Yap');
        expect([...withHelp]..remove('Yardım ve Destek'), without, reason: role.name);
      }
    });

    testWidgets('dokununca YALNIZ onOpenHelp çalışır (sayfa seçilmez); dokunma hedefi >= 48 dp; düğme anlamı', (t) async {
      final semantics = t.ensureSemantics();
      try {
        var opened = 0;
        final selected = <SirketMenuItem>[];
        await _pumpMenu(t, UserRole.individual, onOpenHelp: () => opened++, onSelect: selected.add);
        final tile = find.widgetWithText(ListTile, 'Yardım ve Destek');
        expect(t.getSize(tile).height, greaterThanOrEqualTo(48));
        expect(t.getSemantics(tile).flagsCollection.isButton, isTrue);
        await t.tap(tile);
        await t.pump();
        expect(opened, 1);
        expect(selected, isEmpty);
      } finally {
        semantics.dispose();
      }
    });

    for (final (w, h, s) in const <(double, double, double)>[
      (320, 640, 2.0),
      (360, 640, 1.5),
      (640, 360, 1.5),
      (640, 360, 2.0), // yatay + büyük yazı
    ]) {
      testWidgets('taşma yok ve öğe görünür/kaydırılabilir (${w.toInt()}x${h.toInt()} x$s)', (t) async {
        for (final role in UserRole.values) {
          await _pumpMenu(t, role, onOpenHelp: () {}, width: w, height: h, scale: s, toggle: role == UserRole.siteManager);
          expect(t.takeException(), isNull, reason: role.name);
          await t.ensureVisible(find.widgetWithText(ListTile, 'Yardım ve Destek'));
          await t.pump();
          expect(t.takeException(), isNull, reason: role.name);
        }
      });
    }
  });

  group('HomePage bağlantısı', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      LegalApi.debugDefaultFactory = () => FakeLegalServer().api;
    });
    tearDown(() => LegalApi.debugDefaultFactory = null);

    testWidgets('çekmece -> "Yardım ve Destek": çekmece kapanır, HelpView rolle açılır; geri dönünce panel', (t) async {
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final auth = _HomeAuth(UserRole.individual);
      await t.pumpWidget(MaterialApp(home: HomePage(authService: auth)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      final scaffold = t.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffold.openDrawer();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.widgetWithText(ListTile, 'Yardım ve Destek'), findsOneWidget);

      await t.tap(find.widgetWithText(ListTile, 'Yardım ve Destek'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      final help = t.widget<HelpView>(find.byType(HelpView));
      expect(help.role, UserRole.individual);
      expect(help.residentMode, isFalse);
      expect(help.userId, 5);
      expect(help.onOpenProfile, isNotNull);
      expect(find.text('Cihazımı hesabıma nasıl eklerim?'), findsOneWidget, reason: 'bireysel yardımı');

      // "Profilim ekranına git": yardım kapanır, menü Profilim'e geçer.
      await t.ensureVisible(find.text('Profilim ekranına git'));
      await t.pump(const Duration(milliseconds: 250));
      await t.tap(find.text('Profilim ekranına git'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(HelpView), findsNothing);
      expect(find.text('Kendi Bilgilerini Düzenle'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  });
}
