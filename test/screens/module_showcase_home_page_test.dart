// Panel = modül vitrini: ana kabuk (HomePage) entegrasyonu.
//
// Sözleşmeler:
// - Kartlar çekmecenin AYNI öğe listesinden türer: kapalı / yetkisiz modülün kartı vitrinde de çekmecede de yoktur
//   (fail-closed); modül sonradan kapanınca kart da kalkar.
// - Karta dokunmak çekmecede o öğeyi seçmekle aynı gezinmedir; geri tuşu modül sayfasından vitrine döner.
// - Kapı paneli "Kapılar" kartının arkasındadır (bir dokunuş); Geçiş Kontrol kapalıyken kart ve hızlı "Kapıyı aç" yoktur.
// - Dar ekran + büyük yazıda taşma yok.
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
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

final SiteRecord _site = SiteRecord(
  id: 1,
  name: 'Güneş Sitesi',
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
  siteName: 'Güneş Sitesi',
  doorName: 'Ana Kapı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'AABBCCDD',
  mqttSiteId: 1,
  createdAt: DateTime(2026, 1, 1),
);

UserSession _sessionFor(UserRole role) => UserSession(
  id: role == UserRole.superUser ? 1 : 5,
  fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Ayşe Yılmaz',
  email: 'kullanici@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 'tok',
);

/// HomePage için sahte servis: kapı / site uçları sabit, borç özeti testten sürülür.
class _ShowcaseAuth extends AuthService {
  _ShowcaseAuth(this.role, {this.finance}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;
  Future<MyFinance> Function()? finance;
  int financeCalls = 0;

  @override
  UserSession? get session => _sessionFor(role);

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
      apartments: const <ApartmentRecord>[],
      doors: [_door],
    ),
    null,
  );

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (
    role == UserRole.individual || role == UserRole.apartmentOwner ? <DoorRecord>[_door] : <DoorRecord>[],
    null,
  );

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
  Future<MyFinance> getMyFinance() {
    financeCalls++;
    final handler = finance;
    return handler == null
        ? Future<MyFinance>.value(
            const MyFinance(
              items: [
                MyFinanceApartment(
                  siteCode: 1,
                  siteName: 'Güneş Sitesi',
                  apartmentId: 5,
                  label: 'D:3',
                  blockName: 'A Blok',
                  balanceMinor: 125000,
                ),
              ],
            ),
          )
        : handler();
  }
}

/// `my-modules` satırı. [modules] verilmeyen kodlar katalog varsayılanıdır (yalnız çekirdek modüller açık).
MySiteModules _my(
  String role, {
  Map<String, bool> modules = const <String, bool>{},
  bool doorOpen = true,
  bool? doorAccess,
}) => MySiteModules(
  siteCode: 1,
  siteName: 'Güneş Sitesi',
  role: role,
  modules: <String, bool>{'door_control': doorOpen, ...modules},
  doorAccess: doorAccess ?? !(role == 'staff' || role == 'board_member'),
);

Future<ModuleAccess> _access(
  List<MySiteModules> Function() sites, {
  bool superUser = false,
  int pendingModules = 0,
  int pendingApplications = 0,
}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
    isSuperUser: () => superUser,
    fetchPendingCount: superUser ? () async => pendingModules : null,
    fetchPendingApplicationCount: superUser ? () async => pendingApplications : null,
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
  _ShowcaseAuth auth, {
  ModuleAccess? access,
  double width = 400,
  double height = 1800,
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
      home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier),
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

Future<void> _closeDrawer(WidgetTester t) async {
  Navigator.of(t.element(find.byType(Drawer))).pop();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Çekmecede olup sayfa seçmeyen / vitrine kart olmayan satırlar: vitrinin kendisi, geçiş, yardım, çıkış ve sakin
/// kapı komutları (ek eylemler).
const Set<String> _drawerOnlyTitles = <String>{
  'Panel',
  'Yardım ve Destek',
  'Çıkış Yap',
  'Sakin Moduna Geç',
  'Yönetici Paneline Geç',
  'Sesli Kapı Açma',
  'Kapıya QR Göster',
  'Kapı Ekranından QR Oku',
  'Kurye / Misafir Geçiş Linki Oluştur',
};

/// Çekmecedeki başlıklar (sıralı); "Yardım ve Destek" / "Çıkış Yap" dahil.
List<String> _drawerTitles(WidgetTester t) => <String>[
  for (final tile in t.widgetList<ListTile>(find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile))))
    (tile.title! as Text).data!,
];

Finder _card(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_kart_${item.name}'));
Finder _quick(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_hizli_${item.name}'));
Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

/// Vitrindeki kart başlıkları: ızgara + ikincil satır (Yardım düğmesi hariç).
List<String> _showcaseTitles(WidgetTester t, {bool secondary = true}) {
  final titles = <String>[];
  for (final item in SirketMenuItem.values) {
    if (_card(item).evaluate().isNotEmpty) titles.add(YanMenu.titleFor(item, _sessionRole(t)));
    if (secondary && find.byKey(ValueKey<String>('panel_ikincil_${item.name}')).evaluate().isNotEmpty) {
      titles.add(YanMenu.titleFor(item, _sessionRole(t)));
    }
  }
  return titles;
}

UserRole _sessionRole(WidgetTester t) => t.widget<ModuleShowcaseView>(find.byType(ModuleShowcaseView)).session.role;

Future<void> _tapCard(WidgetTester t, SirketMenuItem item) async {
  await t.ensureVisible(_card(item));
  await t.pump();
  await t.tap(_card(item));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  group('Panel artık modül vitrinidir', () {
    testWidgets('açılışta kapı paneli DEĞİL vitrin gelir; başlık "Panel"', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);

      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(find.byType(DashboardView), findsNothing);
      expect(find.byType(IndividualHomeView), findsNothing);
      expect(find.byType(DoorOpenButton), findsNothing, reason: 'kapı düğmesi artık Kapılar sayfasında');
      expect(_inAppBar(find.text('Panel')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('çekmecede "Kapılar", "Panel"in hemen altındadır', (t) async {
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t).where((title) => title != 'Sakin Moduna Geç').toList();
      expect(titles.first, 'Panel');
      expect(titles[1], 'Kapılar');
      await _disposeHome(t);
    });
  });

  group('rol başına vitrin kartları (kartlar = çekmece öğeleri - Panel - ikincil satır)', () {
    /// Çekmece ve vitrin AYNI listeyi paylaşır: kart başlıkları = çekmece başlıkları - {Panel, Yardım, Çıkış, ikincil}.
    Future<void> expectSameAsDrawer(WidgetTester t) async {
      final showcase = _showcaseTitles(t, secondary: false);
      final secondary = <String>[
        for (final item in showcaseSecondaryItems)
          if (find.byKey(ValueKey<String>('panel_ikincil_${item.name}')).evaluate().isNotEmpty)
            YanMenu.titleFor(item, _sessionRole(t)),
      ];
      await _openDrawer(t);
      final drawer = _drawerTitles(t)
          .where((title) => !_drawerOnlyTitles.contains(title))
          .toList();
      await _closeDrawer(t);
      expect(
        <String>{...showcase, ...secondary},
        drawer.toSet(),
        reason: 'vitrin kartları (ızgara + ikincil) çekmece öğeleriyle birebir aynı küme',
      );
      for (final title in showcase) {
        final item = SirketMenuItem.values.firstWhere((i) => YanMenu.titleFor(i, _sessionRole(t)) == title);
        expect(showcaseSecondaryItems.contains(item), isFalse, reason: '$title ızgarada olmamalı');
      }
    }

    testWidgets('süper kullanıcı: yönetim kartları + odak barı (bekleyen modül talebi / site başvurusu)', (t) async {
      final auth = _ShowcaseAuth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true, pendingModules: 3, pendingApplications: 1);
      await _pumpHome(t, auth, access: access);

      for (final item in [
        SirketMenuItem.kapilar,
        SirketMenuItem.kullaniciYonetimi,
        SirketMenuItem.siteler,
        SirketMenuItem.kisiler,
        SirketMenuItem.moduller,
        SirketMenuItem.modulTalepleri,
        SirketMenuItem.siteBasvurulari,
        SirketMenuItem.kayitliCihazlar,
      ]) {
        expect(_card(item), findsOneWidget, reason: '$item kartı');
      }
      expect(find.byKey(const ValueKey<String>('panel_ikincil_profilim')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_ikincil_platformAyarlari')), findsOneWidget);
      // Odak barı: yalnız var olan bekleyen sayılar.
      expect(find.text('Dikkat edilmesi gereken 2 iş var'), findsOneWidget);
      expect(find.text('3 bekleyen modül talebi'), findsOneWidget);
      expect(find.text('1 bekleyen site başvurusu'), findsOneWidget);
      // Sakin hero kartı / hızlı işlem yok.
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsNothing);
      expect(find.text('Hızlı işlemler'), findsNothing);
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: bekleyen sayı sıfırsa odak barı yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_odak_bar')), findsNothing);
      expect(_card(SirketMenuItem.modulTalepleri), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('site yöneticisi (yönetici modu): açık modüller kart, kapalılar yok; sakin kartları yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(
        () => <MySiteModules>[
          _my('manager', modules: {'announcements': true, 'finance': true, 'work_tracking': true, 'documents': false}),
        ],
      );
      await _pumpHome(t, auth, access: access);

      for (final item in [
        SirketMenuItem.kapilar,
        SirketMenuItem.kisiler,
        SirketMenuItem.duyurular,
        SirketMenuItem.finans,
        SirketMenuItem.talepler,
        SirketMenuItem.siteler,
        SirketMenuItem.moduller,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.katilimVeKurulum,
      ]) {
        expect(_card(item), findsOneWidget, reason: '$item kartı');
      }
      for (final closed in [SirketMenuItem.belgeler, SirketMenuItem.rezervasyonlar, SirketMenuItem.anketler]) {
        expect(_card(closed), findsNothing, reason: '$closed modülü kapalı');
      }
      for (final residentOnly in [SirketMenuItem.borcum, SirketMenuItem.taleplerim, SirketMenuItem.kararlar]) {
        expect(_card(residentOnly), findsNothing, reason: '$residentOnly sakin kartıdır');
      }
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsNothing);
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('daire sakini: hero + hızlı işlemler + açık modüller; yönetim kartları yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', modules: {'announcements': true, 'finance': true, 'documents': true, 'work_tracking': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);

      expect(find.byKey(const ValueKey<String>('panel_hero_borc')), findsOneWidget, reason: 'borç bilgisi alındı');
      for (final item in [
        SirketMenuItem.kapilar,
        SirketMenuItem.duyurular,
        SirketMenuItem.borcum,
        SirketMenuItem.belgeler,
        SirketMenuItem.taleplerim,
        SirketMenuItem.katilimVeKurulum,
      ]) {
        expect(_card(item), findsOneWidget, reason: '$item kartı');
      }
      for (final item in [SirketMenuItem.finans, SirketMenuItem.talepler, SirketMenuItem.siteler, SirketMenuItem.kisiler]) {
        expect(_card(item), findsNothing, reason: '$item sakine görünmez');
      }
      expect(_quick(SirketMenuItem.kapilar), findsOneWidget);
      expect(_quick(SirketMenuItem.taleplerim), findsOneWidget);
      expect(_quick(SirketMenuItem.belgeler), findsOneWidget);
      expect(_quick(SirketMenuItem.ziyaretcilerim), findsNothing, reason: 'visitor_log kapalı');
      expect(find.byKey(const ValueKey<String>('panel_odak_bar')), findsNothing);
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi (salt okunur): Kişiler / Finans / Duyurular kartları; yönetim yazma kartları yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('board_member', modules: {'people': true, 'announcements': true, 'finance': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kisiler), findsOneWidget);
      expect(_card(SirketMenuItem.finans), findsOneWidget, reason: 'kurul üyesi finansı salt okunur görür');
      expect(_card(SirketMenuItem.duyurular), findsOneWidget);
      expect(_card(SirketMenuItem.talepler), findsNothing, reason: 'work_tracking kapalı');
      expect(_card(SirketMenuItem.siteler), findsNothing);
      expect(_card(SirketMenuItem.moduller), findsNothing);
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('görevli (staff): yalnız açık yönetim modülleri; Borcum / Duyurular / Finans kartı yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('staff', modules: {'work_tracking': true, 'finance': true, 'announcements': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.talepler), findsOneWidget);
      for (final item in [SirketMenuItem.borcum, SirketMenuItem.duyurular, SirketMenuItem.finans, SirketMenuItem.belgeler]) {
        expect(_card(item), findsNothing, reason: '$item görevliye görünmez');
      }
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: Kapılar + Daireye Katıl & Cihaz Ekle; hero ve hızlı işlem yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.individual);
      final access = await _access(() => const <MySiteModules>[]);
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kapilar), findsOneWidget);
      expect(_card(SirketMenuItem.katilimVeKurulum), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_ikincil_profilim')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_borc')), findsNothing);
      expect(find.text('Hızlı işlemler'), findsNothing);
      expect(_card(SirketMenuItem.duyurular), findsNothing);
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });
  });

  group('fail-closed: kapalı modülün kartı çekmecede de vitrinde de yok', () {
    testWidgets('finans / belgeler kapalı: Borcum ve Belgeler kartı yok, borç ucu çağrılmaz; modül açılınca kart gelir',
        (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      var finance = false;
      var documents = false;
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', modules: {'announcements': true, 'finance': finance, 'documents': documents}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.borcum), findsNothing);
      expect(_card(SirketMenuItem.belgeler), findsNothing);
      expect(_quick(SirketMenuItem.belgeler), findsNothing);
      expect(auth.financeCalls, 0, reason: 'kapalı modülün ucu çağrılmaz');
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsOneWidget);
      await _openDrawer(t);
      expect(_drawerTitles(t), isNot(contains('Borcum')));
      expect(_drawerTitles(t), isNot(contains('Belgeler')));
      await _closeDrawer(t);

      // Yönetici modülleri açar: kartlar canlı gelir.
      finance = true;
      documents = true;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_card(SirketMenuItem.borcum), findsOneWidget);
      expect(_card(SirketMenuItem.belgeler), findsOneWidget);
      expect(auth.financeCalls, greaterThanOrEqualTo(1), reason: 'Borcum açılınca özet okunur');

      // Yeniden kapanınca kart ve borç özeti kalkar.
      finance = false;
      documents = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_card(SirketMenuItem.borcum), findsNothing);
      expect(_card(SirketMenuItem.belgeler), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_borc')), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('modül verisi hiç gelmediyse (ağ hatası) modül kartları AÇILMAZ (yalnız çekirdek kartlar)', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = ModuleAccess(fetch: () async => throw StateError('ağ yok'));
      addTearDown(access.dispose);
      await access.refresh();
      await _pumpHome(t, auth, access: access);
      for (final item in [SirketMenuItem.borcum, SirketMenuItem.belgeler, SirketMenuItem.taleplerim, SirketMenuItem.rezervasyon]) {
        expect(_card(item), findsNothing, reason: '$item: veri yokken kapalı sayılır');
      }
      expect(auth.financeCalls, 0);
      expect(_card(SirketMenuItem.katilimVeKurulum), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('kapı: "Kapılar" kartı bir dokunuşla kapı panelini açar', () {
    testWidgets('yönetici: Kapılar kartı -> DashboardView (kapı seçici, kapıyı aç); başlık "Kapılar"', (t) async {
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      expect(find.byType(DashboardView), findsNothing);

      await _tapCard(t, SirketMenuItem.kapilar);
      expect(find.byType(DashboardView), findsOneWidget);
      expect(find.byType(ModuleShowcaseView), findsNothing);
      expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
      expect(find.byType(DoorOpenButton), findsWidgets);
      await _disposeHome(t);
    });

    testWidgets('sakin: hızlı "Kapıyı aç" eylemi de kapı paneline götürür (kapı açma mantığı değişmedi)', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      expect(find.byType(DoorOpenButton), findsNothing, reason: 'vitrinde kazara kapı açılamaz: düğme yok');

      await t.ensureVisible(_quick(SirketMenuItem.kapilar));
      await t.tap(_quick(SirketMenuItem.kapilar));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(DashboardView), findsOneWidget);
      expect(find.byType(DoorOpenButton), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: Kapılar kartı -> bireysel ana ekran (kapılar, daireler, cihazlar)', (t) async {
      final auth = _ShowcaseAuth(UserRole.individual);
      final access = await _access(() => const <MySiteModules>[]);
      await _pumpHome(t, auth, access: access);
      await _tapCard(t, SirketMenuItem.kapilar);
      expect(find.byType(IndividualHomeView), findsOneWidget);
      expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Geçiş Kontrol KAPALI: kapı kartı, hızlı "Kapıyı aç" ve çekmecede "Kapılar" yok; öteki kartlar durur',
        (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', doorOpen: false, modules: {'announcements': true, 'work_tracking': true, 'documents': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kapilar), findsNothing);
      expect(_quick(SirketMenuItem.kapilar), findsNothing);
      expect(find.text('Kapıyı aç'), findsNothing);
      expect(_card(SirketMenuItem.belgeler), findsOneWidget);
      expect(_quick(SirketMenuItem.taleplerim), findsOneWidget);
      await _openDrawer(t);
      expect(_drawerTitles(t), isNot(contains('Kapılar')));
      expect(_drawerTitles(t), isNot(contains('Eller Serbest & Kestirmeler')));
      await _disposeHome(t);
    });

    testWidgets('Geçiş Kontrol KAPALI (yönetici): Kapılar kartı yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager', doorOpen: false)]);
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kapilar), findsNothing);
      expect(_card(SirketMenuItem.siteler), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('karta dokununca doğru sayfa (çekmecede seçmekle aynı gezinme)', () {
    testWidgets('Borcum kartı -> Borcum sayfası; geri tuşu ve çekmeceden "Panel" vitrine döner', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[_my('resident', modules: {'finance': true, 'announcements': true})],
      );
      await _pumpHome(t, auth, access: access);

      await _tapCard(t, SirketMenuItem.borcum);
      expect(find.byType(MyFinanceView), findsOneWidget);
      expect(find.byType(ModuleShowcaseView), findsNothing);
      expect(_inAppBar(find.text('Borcum')), findsOneWidget);

      // Geri tuşu uygulamadan çıkmaz, vitrine döner.
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_inAppBar(find.text('Panel')), findsOneWidget);

      // Çekmeceden "Panel" de aynı sonucu verir.
      await _tapCard(t, SirketMenuItem.borcum);
      expect(find.byType(MyFinanceView), findsOneWidget);
      await _openDrawer(t);
      await t.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Panel')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('ikincil satır: "Profilim" düğmesi Profilim sayfasını açar', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      final chip = find.byKey(const ValueKey<String>('panel_ikincil_profilim'));
      await t.ensureVisible(chip);
      await t.tap(chip);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Profilim')), findsOneWidget);
      expect(find.byType(ModuleShowcaseView), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('Yardım ve Destek düğmesi yardım ekranını açar', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      final help = find.byKey(const ValueKey<String>('panel_ikincil_yardim'));
      await t.ensureVisible(help);
      await t.tap(help);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(ModuleShowcaseView), findsNothing, reason: 'yardım yeni sayfa olarak açıldı');
      expect(find.text('Yardım ve Destek'), findsWidgets);
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: Modül Talepleri odak satırı Modül Talepleri sayfasını açar', (t) async {
      final auth = _ShowcaseAuth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true, pendingModules: 2);
      await _pumpHome(t, auth, access: access);
      final button = find.byKey(const ValueKey<String>('panel_odak_modulTalepleri'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Modül Talepleri')), findsOneWidget);
      await _disposeHome(t);
    });
  });

  group('sakin hero kartı: borç bilgisi', () {
    testWidgets('Borcum açık + sunucu borç döndürdü: "Güncel borcunuz" ve "Borcum\'a git" Borcum sayfasını açar', (t) async {
      final auth = _ShowcaseAuth(
        UserRole.apartmentOwner,
        finance: () async => MyFinance(
          items: [
            MyFinanceApartment(
              siteCode: 1,
              siteName: 'Güneş Sitesi',
              apartmentId: 5,
              label: 'D:3',
              blockName: 'A Blok',
              balanceMinor: 325000,
              nextDueDate: DateTime(2026, 11, 10),
            ),
          ],
        ),
      );
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);
      expect(find.text('Güncel borcunuz'), findsOneWidget);
      expect(find.text('3.250,00 ₺'), findsOneWidget);
      expect(find.text('Sıradaki vade: 10.11.2026'), findsOneWidget);

      final go = find.byKey(const ValueKey<String>('panel_hero_borcuma_git'));
      await t.ensureVisible(go);
      await t.tap(go);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(MyFinanceView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('borç bilgisi alınamadı: selamlama + site adı, "Borcunuz yok" denmez', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, finance: () async => throw StateError('ağ yok'));
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);
      expect(find.text('Merhaba, Ayşe'), findsOneWidget);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(find.text('Borcunuz yok'), findsNothing);
      await _disposeHome(t);
    });
  });

  group('taşma yok: dar ekran + yazı ölçeği 2,0 ve geniş ekran', () {
    final roles = <(String, UserRole, List<MySiteModules> Function(), bool)>[
      (
        'süper kullanıcı',
        UserRole.superUser,
        () => const <MySiteModules>[],
        true,
      ),
      (
        'site yöneticisi',
        UserRole.siteManager,
        () => <MySiteModules>[
          _my('manager', modules: {'announcements': true, 'finance': true, 'work_tracking': true, 'documents': true}),
        ],
        false,
      ),
      (
        'daire sakini',
        UserRole.apartmentOwner,
        () => <MySiteModules>[
          _my('resident', modules: {'announcements': true, 'finance': true, 'documents': true, 'work_tracking': true}),
        ],
        false,
      ),
      (
        'bireysel',
        UserRole.individual,
        () => const <MySiteModules>[],
        false,
      ),
    ];
    const cells = <(double, double, double, bool)>[
      (320, 640, 2.0, false),
      (320, 640, 2.0, true),
      (360, 740, 1.5, false),
      (1366, 768, 1.0, false),
      (1366, 768, 1.0, true),
    ];

    for (final (label, role, sites, isSuper) in roles) {
      for (final (w, h, scale, dark) in cells) {
        testWidgets('$label: ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}', (t) async {
          final auth = _ShowcaseAuth(role, finance: () async => throw StateError('ağ'));
          final access = await _access(sites, superUser: isSuper, pendingModules: 12, pendingApplications: 3);
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: scale, dark: dark);
          expect(find.byType(ModuleShowcaseView), findsOneWidget);
          expect(t.takeException(), isNull, reason: 'RenderFlex taşması yok');
          // Sayfanın tamamı kaydırılarak gezilir: alt uçta da taşma/hata yok.
          final scroll = find.byType(SingleChildScrollView).first;
          await t.drag(scroll, const Offset(0, -3000));
          await t.pump();
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });
      }
    }
  });

  group('kapı panelinin yoklaması yalnız Kapılar sayfasında', () {
    testWidgets('vitrindeyken durum yoklaması yok; Kapılar\'a geçince başlar', (t) async {
      final calls = <int>[];
      final auth = _CountingAuth(UserRole.siteManager, calls);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      // İlk yükleme bir kez durum okur; vitrinde 3 sn'lik yoklama turları EKLENMEZ.
      final afterLoad = calls.length;
      await t.pump(const Duration(seconds: 7));
      expect(calls.length, afterLoad, reason: 'vitrin görünürken kapı durumu yoklanmaz');

      await _tapCard(t, SirketMenuItem.kapilar);
      await t.pump(const Duration(seconds: 7));
      expect(calls.length, greaterThan(afterLoad), reason: 'Kapılar sayfasında yoklama sürer');
      await _disposeHome(t);
    });
  });
}

/// Durum çağrılarını sayan sahte servis.
class _CountingAuth extends _ShowcaseAuth {
  _CountingAuth(super.role, this.calls);

  final List<int> calls;

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async {
    calls.add(doorId);
    return (null, null);
  }
}
