// Platform Faz 3a: ana kabuk (HomePage) entegrasyonu — "Duyurular" menü öğesi, çekmece rozeti, yeni duyuru
// bildirimi, Panel'deki kalıcı acil şerit ve Profil -> Bildirim Tercihleri.
//
// - Site yöneticisi (yönetici modu) ve süper kullanıcı: "Duyurular" yönetim ekranı (yazma yetkisi).
// - Daire sakini: gelen kutusu; kurul üyesi: gelen kutusu + salt okunur yönetim görünümü.
// - Yalnız-görevli (staff) ve bireysel kullanıcı: menü YOK, bildirim yoklaması YOK.
// - Yoklama ~20 sn, arka planda durur; yeni duyuru SnackBar'ı; okunmamış acil duyuru Panel'in üstünde şerit.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_manage_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/announcement_read_dialog.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/announcements_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/notification_prefs_section.dart';

import 'announcement_fixtures.dart';
import 'list_fixtures.dart' show fxDoors, tapFinder;
import 'dialog_layout_harness.dart' show settleFor;

/// HomePage için sahte servis: duyuru uçlarına ek olarak ana kabuğun ihtiyaç duyduğu uçlar boş döner.
class _HomeAnnouncementAuth extends AnnouncementFakeAuth {
  _HomeAnnouncementAuth({super.role, bool seeded = true}) {
    if (seeded) {
      final seed = AnnouncementFakeAuth.seeded();
      rows.addAll(seed.rows);
    }
  }

  @override
  Future<void> refreshSession({bool force = false}) async {}

  /// `listMyDoors` yanıtı: dolu liste, kullanıcının kapı erişimi (sakin sinyali) olduğunu gösterir.
  List<DoorRecord> doors = <DoorRecord>[];

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (List<DoorRecord>.of(doors), null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);

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

/// Sunucunun `my-modules` satırı: yalnız kurul (board_member) / görevli (staff) bağı olan sitede `door_access`
/// FALSE gelir; aynı sitede ayrıca sakin de ise sitenin en yüksek rolü "staff" kalır ama `door_access` TRUE olur.
MySiteModules _my(String role, {int code = 11, String name = 'Gül Sitesi', bool? doorAccess}) => MySiteModules(
  siteCode: code,
  siteName: name,
  role: role,
  modules: const <String, bool>{'door_control': true},
  doorAccess: doorAccess ?? !(role == 'staff' || role == 'board_member'),
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

Future<void> _pumpHome(
  WidgetTester t,
  _HomeAnnouncementAuth auth, {
  ModuleAccess? access,
  AnnouncementNotifier? notifier,
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
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

Future<void> _tapMenu(WidgetTester t, String label) async {
  await _openDrawer(t);
  await t.ensureVisible(find.text(label).first);
  await t.pump();
  await t.tap(find.text(label).first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await settleFor(t);
}

Finder _tileTitle(String title) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(title));

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

List<String> _drawerTitles(WidgetTester t) => [
  for (final tile in t.widgetList<ListTile>(find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile))))
    (tile.title! as Text).data!,
];

/// Yoklamayı bir tur ilerletir (ön plan aralığı 20 sn).
Future<void> _poll(WidgetTester t, {int seconds = 20}) async {
  await t.pump(Duration(seconds: seconds));
  await t.pump();
  await t.pump();
}

void main() {
  group('Duyurular menü öğesi', () {
    testWidgets('site yöneticisi: "Kişiler"in hemen altında; seçilince yönetim ekranı, başlık, yazma yetkisi', (t) async {
      final auth = _HomeAnnouncementAuth();
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);

      await _openDrawer(t);
      final titles = _drawerTitles(t);
      expect(titles, contains('Duyurular'));
      expect(titles.indexOf('Duyurular'), titles.indexOf('Kişiler') + 1);
      await t.tap(_tileTitle('Duyurular'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      expect(find.byType(AnnouncementsView), findsOneWidget);
      expect(_inAppBar(find.text('Duyurular')), findsOneWidget);
      expect(auth.announcementListCalls, isNotEmpty);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
      expect(find.text('Yeni Duyuru'), findsOneWidget);
      expect(find.text('Gelen kutusu'), findsNothing, reason: 'yönetici modunda gelen kutusu yok');
      await _disposeHome(t);
    });

    testWidgets('süper kullanıcı: menüde var, yönetim ekranı ve yazma yetkisi; bildirim yoklaması YOK', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access);
      await _poll(t);
      expect(auth.summaryCalls, 0, reason: 'süper kullanıcı alıcı olamaz');
      await _tapMenu(t, 'Duyurular');
      expect(find.byType(AnnouncementsView), findsOneWidget);
      expect(find.text('Yeni Duyuru'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('daire sakini: gelen kutusu açılır; yönetim düğmesi yok; sayfa açıklaması 20 sn yoklamayı anlatır', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);

      await _tapMenu(t, 'Duyurular');
      expect(find.byType(AnnouncementsView), findsOneWidget);
      expect(find.byType(AnnouncementInboxCard), findsOneWidget);
      expect(find.text('Yeni Duyuru'), findsNothing);
      expect(
        find.textContaining('yaklaşık 20 saniyede bir kontrol edilir'),
        findsOneWidget,
        reason: 'bu bir anlık itme değil; kullanıcıya böyle anlatılır',
      );
      expect(find.textContaining('telefon bildirimi gelmez'), findsOneWidget);
      expect(auth.announcementListCalls, isEmpty, reason: 'sakin yönetici uçlarını çağırmaz');
      await _disposeHome(t);
    });

    testWidgets('G19: yoklama hatalıyken bilgi metni "yaklaşık 20 saniyede bir" DEMEZ; düzelince geri döner', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi'))
        ..summaryError = ApiException('Sunucu yanıt vermedi.');
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      await _tapMenu(t, 'Duyurular');
      expect(find.textContaining('yaklaşık 20 saniyede bir'), findsNothing);
      expect(find.textContaining('Bağlantı sorunu: yeni duyurular daha seyrek kontrol ediliyor'), findsOneWidget);

      auth.summaryError = null;
      await _poll(t, seconds: 40);
      await settleFor(t);
      expect(find.textContaining('yaklaşık 20 saniyede bir kontrol edilir'), findsOneWidget);
      expect(find.textContaining('Bağlantı sorunu'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('kurul üyesi: gelen kutusu + SALT OKUNUR yönetim görünümü (yazma ve alıcı uçları çağrılmaz)', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner)..boardReadOnly = true;
      auth.inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);

      await _tapMenu(t, 'Duyurular');
      expect(find.text('Gelen kutusu'), findsOneWidget);
      expect(find.text('Yönetim görünümü'), findsOneWidget);
      expect(find.byType(AnnouncementInboxCard), findsOneWidget);

      await t.tap(find.byKey(const ValueKey<String>('announcements_mode_manage')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(AnnouncementAdminCard), findsNWidgets(4));
      expect(find.text('Yeni Duyuru'), findsNothing);
      expect(auth.listSitesCalls, 0, reason: 'kurul üyesi yönetim site listesini çağırmaz');

      // Ayrıntı penceresini GERÇEKTEN aç: yazma düğmesi / alıcılar sekmesi yok, alıcı ve önizleme uçları çağrılmaz.
      await tapFinder(t, find.widgetWithText(AnnouncementAdminCard, 'Asansör bakımı'));
      await settleFor(t);
      expect(find.byType(AnnouncementManageDialog), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('announcement_action_publish')), findsNothing);
      expect(find.byKey(const ValueKey<String>('announcement_tab_recipients')), findsNothing);
      // Gerçek sunucu davranışı: kurul + 3 alıcı (< 5) -> okunma sayıları gizli.
      expect(find.byKey(const ValueKey<String>('announcement_read_hidden')), findsOneWidget);
      expect(auth.recipientCalls, isEmpty);
      expect(auth.previewCalls, isEmpty);
      await _disposeHome(t);
    });

    testWidgets('yalnız-görevli (staff) hesapta menü YOK ve bildirim yoklaması yapılmaz', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('staff')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t);
      await _poll(t);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsNothing);
      expect(_tileTitle('Profilim'), findsOneWidget);
      expect(auth.summaryCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: menü YOK, yoklama yok, profilde bildirim tercihleri yok', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.individual, seeded: false);
      final access = await _access(() => const <MySiteModules>[]);
      await _pumpHome(t, auth, access: access);
      await _poll(t);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsNothing);
      expect(auth.summaryCalls, 0);
      await t.tap(_tileTitle('Profilim'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(NotificationPrefsSection), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('G5: modül verisi gelmezse sakin sinyali (kapı erişimi) VARSA daire sakini sayılır: menü ve yoklama var', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)..doors = fxDoors();
      await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
      await _poll(t, seconds: 1);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsOneWidget);
      expect(auth.summaryCalls, greaterThan(0));
      await _disposeHome(t);
    });

    testWidgets('G5: modül verisi gelmezse ve sakin sinyali de yoksa menü YOK, yoklama YOK (yalnız-görevli ilk turda atmaz)', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false);
      await _pumpHome(t, auth, access: ModuleAccess(fetch: () async => throw StateError('ağ yok')));
      await _poll(t);
      await _poll(t);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsNothing);
      expect(auth.summaryCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('G5: modül verisi YÜKLENİRKEN (önceden yüklenmemiş) menü ve yoklama yok; sakin çıkınca hemen başlar', (t) async {
      final gate = Completer<MyModulesResult>();
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = ModuleAccess(fetch: () => gate.future, isSuperUser: () => false);
      addTearDown(access.dispose);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 25);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsNothing, reason: 'rol çözümlenmeden menü yok');
      expect(auth.summaryCalls, 0, reason: 'rol çözümlenmeden yoklama yok');
      await t.tapAt(const Offset(390, 400)); // çekmeceyi kapat
      await t.pump(const Duration(milliseconds: 450));

      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('resident')]));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.summaryCalls, greaterThan(0), reason: 'rol çözümlenince 20 sn beklemeden ilk yoklama');
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('G5: modül verisi YÜKLENİRKEN gelen yalnız-görevli hesap hiçbir zaman Duyurular görmez', (t) async {
      final gate = Completer<MyModulesResult>();
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false);
      final access = ModuleAccess(fetch: () => gate.future, isSuperUser: () => false);
      addTearDown(access.dispose);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 25);
      gate.complete(MyModulesResult(sites: <MySiteModules>[_my('staff')]));
      await t.pump();
      await t.pump();
      await _poll(t);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsNothing);
      expect(auth.summaryCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('G4: aynı sitede hem görevli hem sakin (role "staff" + door_access TRUE): menü, rozet ve yoklama VAR', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.addAll(<Map<String, dynamic>>[
          inboxRow(12, title: 'Su kesintisi'),
          inboxRow(11, title: 'Asansör bakımı'),
        ]);
      final access = await _access(() => <MySiteModules>[_my('staff', doorAccess: true)]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      expect(auth.summaryCalls, greaterThan(0));
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsOneWidget);
      final badge = find.descendant(
        of: find.widgetWithText(ListTile, 'Duyurular'),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);
      await t.tap(_tileTitle('Duyurular'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2), reason: 'gelen kutusu açılır');
      await _disposeHome(t);
    });

    testWidgets('G4: görevli bağı olan site süzgecte DIŞLANIR; görevli + sakin site süzgeçte kalır', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = await _access(
        () => <MySiteModules>[
          _my('staff', code: 11, name: 'Gül Sitesi', doorAccess: true),
          _my('staff', code: 12, name: 'Yalnız Görevli Sitesi'),
          _my('resident', code: 13, name: 'Mavi Park'),
        ],
      );
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Duyurular');
      final view = t.widget<AnnouncementsView>(find.byType(AnnouncementsView));
      expect(view.inboxSites.map((s) => s.code), <int>[11, 13]);
      await _disposeHome(t);
    });

    testWidgets('yalnız görevli olduğu sitelerde sakin olmayan hesap + başka sitede sakin: menü var', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false);
      final access = await _access(
        () => <MySiteModules>[_my('staff'), _my('resident', code: 12, name: 'Mavi Park')],
      );
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      expect(_tileTitle('Duyurular'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('çıkış / erişim kaybı: menü artık erişilemezse açık Duyurular ekranı Panel\'e döner', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false);
      var sites = <MySiteModules>[_my('resident')];
      final access = await _access(() => sites);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Duyurular');
      expect(find.byType(AnnouncementsView), findsOneWidget);

      sites = <MySiteModules>[_my('staff')];
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(AnnouncementsView), findsNothing);
      expect(_inAppBar(find.text('Duyurular')), findsNothing);
      await _disposeHome(t);
    });
  });

  group('rozet, yeni duyuru bildirimi ve acil şerit', () {
    testWidgets('çekmece öğesinde okunmamış sayısı rozeti ("2 okunmamış"); okununca düşer', (t) async {
      final semantics = t.ensureSemantics();
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.addAll(<Map<String, dynamic>>[
          inboxRow(12, title: 'Su kesintisi'),
          inboxRow(11, title: 'Asansör bakımı'),
          inboxRow(10, title: 'Eski', read: true),
        ]);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);

      await _openDrawer(t);
      final badge = find.descendant(
        of: find.widgetWithText(ListTile, 'Duyurular'),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);
      // Ekran okuyucu: öğe başlığı ve rozet birleşik okunur ("Duyurular ... 2 okunmamış").
      expect(
        t.getSemantics(find.widgetWithText(ListTile, 'Duyurular')).getSemanticsData().label,
        allOf(contains('Duyurular'), contains('2 okunmamış')),
      );
      await t.tap(_tileTitle('Duyurular'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);

      await tapDuyuru(t, 'Su kesintisi');
      await _openDrawer(t);
      final after = find.descendant(
        of: find.widgetWithText(ListTile, 'Duyurular'),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(find.descendant(of: after, matching: find.text('1')), findsOneWidget);
      semantics.dispose();
      await _disposeHome(t);
    });

    testWidgets('yeni duyuru ≤ 20 sn içinde SnackBar ile bildirilir ("Yeni duyuru: ..."); "Aç" duyuruyu açar', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(10, title: 'Eski duyuru', read: true));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1); // taban çizgisi
      expect(find.textContaining('Yeni duyuru'), findsNothing, reason: 'açılışta eski duyuru için bildirim yok');
      final before = auth.summaryCalls;

      auth.inboxRows.add(inboxRow(20, title: 'Çatı onarımı'));
      await _poll(t, seconds: 20);
      await settleFor(t);
      expect(auth.summaryCalls, greaterThan(before));
      expect(find.text('Yeni duyuru: Çatı onarımı'), findsOneWidget);

      await t.tap(find.text('Aç'));
      await t.pump();
      await settleFor(t);
      expect(find.byType(AnnouncementReadDialog), findsOneWidget);
      expect(auth.readCalls, <int>[20]);
      expect(find.text('Çatı onarımı'), findsWidgets);
      await _disposeHome(t);
    });

    testWidgets('G2: okunmamış ACİL duyuru gövdenin üstüne SABİT kırmızı şerit: kaydırılmaz, TÜM menülerde (Duyurular hariç) görünür; dokununca gelen kutusu + duyuru açılır; okununca kalkar', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.addAll(<Map<String, dynamic>>[
          inboxRow(12, title: 'Su kesintisi', importance: 'urgent'),
          inboxRow(11, title: 'Asansör bakımı'),
        ]);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      await settleFor(t);

      final banner = find.byKey(const ValueKey<String>('urgent_announcement_banner'));
      expect(banner, findsOneWidget);
      expect(find.text('Okunmamış acil duyuru: Su kesintisi'), findsOneWidget);
      // Şerit kaydırılan içeriğin DIŞINDA: hiçbir kaydırıcının içinde değil, içeriğin (PageEntry) üstünde.
      expect(find.ancestor(of: banner, matching: find.byType(Scrollable)), findsNothing);
      expect(t.getBottomLeft(banner).dy, lessThanOrEqualTo(t.getTopLeft(find.byType(PageEntry)).dy + 0.5));

      // Başka sayfalarda da görünür; Panel'e dönünce yine.
      await _tapMenu(t, 'Profilim');
      expect(banner, findsOneWidget, reason: 'şerit tüm menülerde kalır');
      await _tapMenu(t, 'Panel');
      expect(banner, findsOneWidget);

      await t.tap(banner);
      await t.pump();
      await settleFor(t);
      expect(find.byType(AnnouncementReadDialog), findsOneWidget);
      expect(find.byType(AnnouncementsView), findsOneWidget, reason: 'G8: doğrudan Duyurular gelen kutusu açılır');
      expect(find.byType(AnnouncementInboxCard), findsWidgets);
      expect(auth.readCalls, <int>[12]);
      await t.tap(find.text('Kapat'));
      await settleFor(t);
      expect(banner, findsNothing, reason: 'okununca şerit kalkar');
      await _disposeHome(t);
    });

    testWidgets('G2: şerit Duyurular ekranının KENDİSİNDE yok (liste zaten orada); başka menüye geçince geri gelir', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi', importance: 'urgent'));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      await settleFor(t);
      final banner = find.byKey(const ValueKey<String>('urgent_announcement_banner'));
      expect(banner, findsOneWidget);
      await _tapMenu(t, 'Duyurular');
      expect(find.byType(AnnouncementsView), findsOneWidget);
      expect(banner, findsNothing);
      await _tapMenu(t, 'Profilim');
      expect(banner, findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('G2: şerit KAYDIRMADAN etkilenmez (aynı yerde kalır) ve gelip giderken sayfa alt ağacı yeniden kurulmaz (durum korunur)', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(11, title: 'Asansör bakımı'));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access, width: 400, height: 500);
      await _poll(t, seconds: 1);
      await _tapMenu(t, 'Profilim');
      final before = t.element(find.byType(PageEntry));
      final banner = find.byKey(const ValueKey<String>('urgent_announcement_banner'));
      expect(banner, findsNothing);

      // Acil duyuru yoklamayla gelir: şerit belirir, sayfa öğesi AYNI kalır (alt ağaç yeniden kurulmadı).
      auth.inboxRows.add(inboxRow(20, title: 'Gaz kaçağı', importance: 'urgent'));
      await _poll(t, seconds: 20);
      await settleFor(t);
      expect(banner, findsOneWidget);
      expect(identical(t.element(find.byType(PageEntry)), before), isTrue, reason: 'sayfa durumu korunur');

      // Kaydırınca şerit yerinde kalır.
      final top = t.getTopLeft(banner).dy;
      await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(banner, findsOneWidget);
      expect(t.getTopLeft(banner).dy, top, reason: 'sabit şerit kaydırılmaz');
      await _disposeHome(t);
    });

    testWidgets('G8: kurul üyesi "Yönetim görünümü"ndeyken bildirimin "Aç"ına dokunursa GELEN KUTUSUNA geçer ve duyuru açılır', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner)..boardReadOnly = true;
      auth.inboxRows.add(inboxRow(10, title: 'Eski duyuru', read: true));
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      await _tapMenu(t, 'Duyurular');
      await t.tap(find.byKey(const ValueKey<String>('announcements_mode_manage')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(AnnouncementAdminCard), findsWidgets);

      auth.inboxRows.add(inboxRow(20, title: 'Gaz kaçağı', importance: 'urgent'));
      await _poll(t, seconds: 20);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Aç'));
      await t.pump();
      await settleFor(t);
      expect(find.byType(AnnouncementReadDialog), findsOneWidget);
      expect(auth.readCalls, <int>[20]);
      await t.tap(find.text('Kapat'));
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsWidgets, reason: 'gelen kutusuna geçildi');
      expect(find.byType(AnnouncementAdminCard), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('G8: çekmeceden "Duyurular" seçmek (şeritten değil) kurul üyesini yine gelen kutusuyla açar', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner)..boardReadOnly = true;
      auth.inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = await _access(() => <MySiteModules>[_my('board_member')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Duyurular');
      expect(find.byType(AnnouncementInboxCard), findsOneWidget);
      expect(find.byType(AnnouncementAdminCard), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('G6: yeni duyuru bildirimi ekrandaki başka bildirimi SİLMEZ (kuyruğa girer)', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(10, title: 'Eski duyuru', read: true));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);

      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first)).showSnackBar(
        const SnackBar(content: Text('Kapı açılamadı'), duration: Duration(seconds: 60)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Kapı açılamadı'), findsOneWidget);

      auth.inboxRows.add(inboxRow(20, title: 'Çatı onarımı'));
      await _poll(t, seconds: 20);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Kapı açılamadı'), findsOneWidget, reason: 'ekrandaki mesaj silinmedi');
      expect(find.text('Yeni duyuru: Çatı onarımı'), findsNothing, reason: 'sıraya girdi, öncekinin üstüne binmedi');
      // İlki kapanınca sıradaki gelir.
      await t.pump(const Duration(seconds: 45));
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Kapı açılamadı'), findsNothing);
      expect(find.text('Yeni duyuru: Çatı onarımı'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('G2/G6: ACİL yeni duyuru bildirimi 8 sn\'de kapanmaz (20 sn, "Aç" eylemiyle); normal olan 8 sn\'de kapanır', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(10, title: 'Eski duyuru', read: true));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);

      auth.inboxRows.add(inboxRow(21, title: 'Normal duyuru'));
      await _poll(t, seconds: 20);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Yeni duyuru: Normal duyuru'), findsOneWidget);
      await t.pump(const Duration(seconds: 9));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Yeni duyuru: Normal duyuru'), findsNothing, reason: 'normal bildirim 8 sn');

      auth.inboxRows.add(inboxRow(22, title: 'Gaz kaçağı', importance: 'urgent'));
      await _poll(t, seconds: 20);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Yeni duyuru: Gaz kaçağı'), findsOneWidget);
      await t.pump(const Duration(seconds: 12));
      expect(find.text('Yeni duyuru: Gaz kaçağı'), findsOneWidget, reason: 'acil bildirim kendiliğinden hemen kapanmaz');
      expect(find.text('Aç'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('acil şerit bilinen başlık yokken genel metin yazar ve Duyurular ekranını açar', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi', importance: 'urgent'))
        ..inboxError = ApiException('Gelen kutusu alınamadı.');
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      await settleFor(t);
      expect(find.text('Okunmamış acil duyurunuz var'), findsOneWidget);
      auth.inboxError = null;
      await t.tap(find.byKey(const ValueKey<String>('urgent_announcement_banner')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(AnnouncementsView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('uygulama arka plana gidince yoklama durur; ön plana dönünce hemen çeker', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _poll(t, seconds: 1);
      final active = auth.summaryCalls;
      expect(active, greaterThan(0));

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _poll(t, seconds: 90);
      expect(auth.summaryCalls, active, reason: 'arka planda ağ isteği yok');

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump();
      expect(auth.summaryCalls, greaterThan(active), reason: 'ön plana dönüşte hemen çekilir');
      await _disposeHome(t);
    });

    testWidgets('yenile (AppBar) Duyurular ekranında hem listeyi hem bildirim özetini tazeler', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.add(inboxRow(12, title: 'Su kesintisi'));
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Duyurular');
      final lists = auth.inboxCalls.length;
      final summaries = auth.summaryCalls;
      auth.inboxRows.add(inboxRow(13, title: 'Yenileme sonrası'));
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(auth.inboxCalls.length, greaterThan(lists));
      expect(auth.summaryCalls, greaterThan(summaries));
      expect(find.text('Yenileme sonrası'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('320x640 x2,0 koyu tema: çekmece rozeti + acil şerit + Duyurular taşmaz', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)
        ..inboxRows.addAll(<Map<String, dynamic>>[
          inboxRow(12, title: 'Çok uzun başlıklı acil su kesintisi ve güvenlik duyurusu ' * 2, importance: 'urgent'),
          inboxRow(11, title: 'Asansör bakımı'),
        ]);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access, width: 320, height: 640, scale: 2.0, dark: true);
      await _poll(t, seconds: 1);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('urgent_announcement_banner')), findsOneWidget);
      await _openDrawer(t);
      expect(t.takeException(), isNull);
      await t.tap(_tileTitle('Duyurular'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await settleFor(t);
      expect(find.byType(AnnouncementInboxCard), findsNWidgets(2));
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });
  });

  group('Profil -> Bildirim Tercihleri', () {
    testWidgets('daire sakini profilinde bölüm var; anahtar sunucudaki değeri gösterir', (t) async {
      final auth = _HomeAnnouncementAuth(role: UserRole.apartmentOwner, seeded: false)..prefsEmail = false;
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      await _tapMenu(t, 'Profilim');
      await t.ensureVisible(find.byType(NotificationPrefsSection));
      await t.pump();
      expect(find.text('Bildirim Tercihleri'), findsOneWidget);
      expect(find.text('E-posta ile duyuru al'), findsOneWidget);
      expect(
        t
            .widget<Switch>(
              find.descendant(
                of: find.byKey(const ValueKey<String>('notification_email_switch')),
                matching: find.byType(Switch),
              ),
            )
            .value,
        isFalse,
      );
      // Profilde ikinci anahtar da var (Faz 4b): aidat borç hatırlatma e-postaları.
      expect(find.text('Borç hatırlatma e-postaları'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('notification_finance_reminders_switch')), findsOneWidget);
      expect(find.text('Telefon bildirimi'), findsOneWidget);
      expect(find.text('Yakında…'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('site yöneticisi profilinde (form + bölüm) bildirim tercihleri var; süper kullanıcıda yok', (t) async {
      final manager = _HomeAnnouncementAuth(seeded: false);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, manager, access: access);
      await _tapMenu(t, 'Profilim');
      await t.ensureVisible(find.byType(NotificationPrefsSection));
      await t.pump();
      expect(find.byType(NotificationPrefsSection), findsOneWidget);
      await _disposeHome(t);

      final superUser = _HomeAnnouncementAuth(role: UserRole.superUser, seeded: false);
      final superAccess = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, superUser, access: superAccess);
      await _tapMenu(t, 'Profilim');
      expect(find.byType(NotificationPrefsSection), findsNothing);
      await _disposeHome(t);
    });
  });
}

/// Gelen kutusundaki kartı açar (okuma penceresi) ve kapatır.
Future<void> tapDuyuru(WidgetTester t, String title) async {
  final card = find.widgetWithText(AnnouncementInboxCard, title);
  await t.ensureVisible(card);
  await t.pump();
  await t.tap(card);
  await t.pump();
  await settleFor(t);
  await t.tap(find.text('Kapat'));
  await settleFor(t);
}
