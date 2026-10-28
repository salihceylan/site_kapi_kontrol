// Panel = modül vitrini: ana kabuk (HomePage) entegrasyonu.
//
// Sözleşmeler:
// - Kartlar çekmecenin AYNI öğe listesinden türer: kapalı / yetkisiz modülün kartı vitrinde de çekmecede de yoktur
//   (fail-closed); modül sonradan kapanınca kart da kalkar.
// - Karta dokunmak çekmecede o öğeyi seçmekle aynı gezinmedir; geri tuşu modül sayfasından vitrine döner; çekmece
//   açıkken geri tuşu önce çekmeceyi kapatır; sayfa değişince kaydırma en üstten başlar.
// - Kapı paneli "Kapılar" kartının arkasındadır (bir dokunuş); Geçiş Kontrol kapalıyken ya da daire sakini rolünde kapı
//   erişimi / kapısı olmayan hesapta (yalnız görevli / kurul / site üyeliği) kart, hızlı "Kapıyı aç" ve Eller Serbest yoktur.
// - Vitrinde hiçbir dokunuş kapı komutu GÖNDERMEZ (sahte serviste openDoor sayılır); Kapılar sayfasına girişte kısa süre
//   dokunuş yutulur (hızlı çift dokunuş KAPIYI AÇ düğmesine düşmez).
// - Dar ekran + büyük yazıda taşma yok (320 dp'de yazı 1,0 / 1,15 iki sütun; borç kartı çizili sakin dahil).
// - Açık temada Panel zemini kaydırılan gövdenin KABINDA düz #F8FAFC'dir: kap acil duyuru şeridinin altından ekranın altına
//   uzanır, vitrin kendi sınırının dışına boyamaz; içerik ekrana sığarken de şerit örtülmez. Koyu temada ve öteki
//   sayfalarda kap boyanmaz. Kart rozeti çekmece rozetiyle aynı renktedir.
// - İP-1D (G2 + G3): çekmece başlıklar altında, ayar öğeleri sağ üstteki dişliden açılan Ayarlar panelinde; vitrin kartları
//   çekmece + Ayarlar panelinin BİRLEŞİMİYLE aynı kümedir. Sakin kitlesinde alt çubuk vardır: gövdenin kabı çubuğun
//   üstünde biter.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
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
import 'package:site_kapi_kontrol/services/door_panel_requests.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/visitor_log_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/views/help_view.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/my_finance_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/unread_announcement_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/paint_extent.dart';
import '../support/menu_nav.dart';

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

/// Misafir geçişine izin verilmeyen kapı ("Ziyaretçi kodu" çıkmamalı).
final DoorRecord _doorNoGuestPass = DoorRecord(
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
  featureGuestPassEnabled: false,
);

/// Çevrimiçi kapı durumu: KAPIYI AÇ düğmesi "hazır" olur (dokunuş komut gönderir).
DoorRuntimeStatus _onlineStatus() => DoorRuntimeStatus.fromJson({
  'door': {'id': 11, 'site_code': 1, 'door_name': 'Ana Kapı', 'door_index': 1},
  'device_status': {
    'device_uid': 'AABBCCDD',
    'mqtt_connected': true,
    'mqtt_bridge_connected': true,
    'wifi_rssi': -50,
    'firmware_version': '1.0.0',
  },
});

UserSession _sessionFor(UserRole role) => UserSession(
  id: role == UserRole.superUser ? 1 : 5,
  fullName: role == UserRole.superUser ? 'Süper Yönetici' : 'Ayşe Yılmaz',
  email: 'kullanici@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 'tok',
);

/// HomePage için sahte servis: kapı / site uçları sabit, borç özeti testten sürülür. Kapı komutları SAYILIR (bulut ve
/// yerel ağ yolu `openDoor` içindedir; karekodla açma ayrıca): vitrinde hiçbiri çağrılmamalıdır.
class _ShowcaseAuth extends AuthService {
  _ShowcaseAuth(this.role, {this.finance, List<DoorRecord>? doors, this.online = false})
    : doors =
          doors ??
          (role == UserRole.individual || role == UserRole.apartmentOwner ? <DoorRecord>[_door] : <DoorRecord>[]),
      super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;
  Future<MyFinance> Function()? finance;
  int financeCalls = 0;

  /// Sakin yolunda (`listMyDoors`) dönen kapılar. Kapı erişimi olmayan (yalnız görevli / kurul / site üyeliği) hesapta
  /// sunucu boş liste verir: testler bunu `doors: const []` ile kurar (sahte her sakine kapı vermesin).
  List<DoorRecord> doors;

  /// Kapı durumu çevrimiçi mi (KAPIYI AÇ düğmesi hazır olsun diye).
  bool online;

  int openDoorCalls = 0;
  int qrOpenCalls = 0;
  int listMyDoorsCalls = 0;
  int listSitesCalls = 0;

  @override
  UserSession? get session => _sessionFor(role);

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(DoorRuntimeStatus?, String?)> openDoor({required int doorId, DoorRecord? door}) async {
    openDoorCalls++;
    return (null, null);
  }

  @override
  Future<(Map<String, dynamic>?, String?)> openDoorWithScannedQr({
    required String qrPayload,
    bool requireLocation = false,
  }) async {
    qrOpenCalls++;
    return (null, 'test');
  }

  @override
  Future<SitePage> listSites({required int page, int pageSize = 10, String? approvalStatus}) async {
    listSitesCalls++;
    return SitePage(sites: [_site], total: 1, page: 1, pageSize: 100);
  }

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
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    listMyDoorsCalls++;
    return (List<DoorRecord>.of(doors), null);
  }

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async =>
      (online ? _onlineStatus() : null, null);

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

MyFinanceApartment _apt(int siteCode, String siteName, int balance) => MyFinanceApartment(
  siteCode: siteCode,
  siteName: siteName,
  apartmentId: siteCode * 10,
  label: 'D:$siteCode',
  blockName: 'A Blok',
  balanceMinor: balance,
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

/// Okunmamış ACİL duyurusu olan sakin ("Gaz kaçağı"): kırmızı şerit gövdenin üstünde çıkar.
AnnouncementNotifier _urgentNotifier() {
  const urgent = ResidentAnnouncement(
    id: 20,
    siteCode: 1,
    siteName: 'Güneş Sitesi',
    title: 'Gaz kaçağı',
    importance: AnnouncementImportance.urgent,
  );
  final notifier = AnnouncementNotifier(
    fetchSummary: () async =>
        const NotificationSummary(unreadAnnouncements: 1, unreadUrgent: 1, latestAnnouncementId: 20),
    fetchInbox: () async => const ResidentAnnouncementPage(items: <ResidentAnnouncement>[urgent]),
    fetchAnnouncement: (id) async => urgent,
    isEligible: () => true,
  );
  addTearDown(notifier.dispose);
  return notifier;
}

/// Ziyaretçi ve Kargo sakin rozeti (`/app/visitor-entries/summary`): istekler sayılır, okunmamış sayısı testten.
class _VisitorServer {
  int unread = 0;
  int summaryCalls = 0;

  http.Response handle(http.Request request) {
    final Map<String, dynamic> body;
    if (request.url.path.endsWith('/visitor-entries/summary')) {
      summaryCalls++;
      body = <String, dynamic>{'unread': unread};
    } else {
      body = <String, dynamic>{'items': <Object>[], 'next_before_id': null, 'total': 0};
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
    );
  }
}

/// Ziyaretçi rozet ucunu sahte sunucuya bağlar (gerçek ağ isteği yok).
_VisitorServer _fakeVisitorServer() {
  final server = _VisitorServer();
  VisitorLogService.debugApiFactory = (auth) => VisitorLogApi(
    baseUrl: 'http://localhost',
    client: MockClient((request) async => server.handle(request)),
  );
  addTearDown(() => VisitorLogService.debugApiFactory = null);
  return server;
}

Future<void> _pumpHome(
  WidgetTester t,
  _ShowcaseAuth auth, {
  ModuleAccess? access,
  double width = 400,
  double height = 1800,
  double scale = 1.0,
  bool dark = false,
  AnnouncementNotifier? notifier,
  DoorPanelRequests? doorPanelRequests,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final announcements = notifier ?? _quietNotifier();
  if (notifier == null) addTearDown(announcements.dispose);
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
        announcementNotifier: announcements,
        doorPanelRequests: doorPanelRequests,
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

Future<void> _closeDrawer(WidgetTester t) async {
  Navigator.of(t.element(find.byType(Drawer))).pop();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Android geri tuşu; dönüş: gezgin olayı karşıladı mı (false = uygulamadan çıkılır, `SystemNavigator.pop`).
Future<bool> _back(WidgetTester t) async {
  final handled = await t.binding.handlePopRoute();
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  return handled;
}

/// Platform kanalını yakalar (uygulamadan çıkış `SystemNavigator.pop` çağrısı sayılabilsin, gerçek kanal çağrılmasın).
List<String> _capturePlatform(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

/// Çekmecede olup sayfa seçmeyen / vitrine kart olmayan satırlar: vitrinin kendisi, geçiş, yardım, çıkış ve sakin
/// kapı komutları (ek eylemler).
const Set<String> _drawerOnlyTitles = <String>{
  'Panel',
  'Yönetim Firması',
  'Yardım ve Destek',
  // P1-14 (K11): çekmecedeki "Geri bildirim" ve Ayarlar panelindeki sayfa seçmeyen geri bildirim eylemleri.
  'Geri bildirim',
  'Geri bildirim gönder',
  'Gelen geri bildirimler',
  'Çıkış Yap',
  'Sakin Moduna Geç',
  'Yönetici Paneline Geç',
  'Sesli Kapı Açma',
  'Kapıya QR Göster',
  'Kapı Ekranından QR Oku',
  'Kurye / Misafir Geçiş Linki Oluştur',
  // İP-1D: Ayarlar panelindeki sayfa seçmeyen eylem.
  'Masaüstüne Widget Ekle',
  // K8 (P1-16): çekmecedeki "Tüm işlemler" girişi sayfa seçmez, ayrı ekran açar (Panel'deki kartı yalnız kompakt menü bir şeyi öne
  // çıkarmadığında çıkar).
  'Tüm işlemler',
};

/// Çekmecedeki başlıklar (sıralı); "Yardım ve Destek" / "Çıkış Yap" dahil.
List<String> _drawerTitles(WidgetTester t) => <String>[
  for (final tile in t.widgetList<ListTile>(find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile))))
    (tile.title! as Text).data!,
];

Finder _card(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_kart_${item.name}'));
Finder _quick(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_hizli_${item.name}'));
final Finder _guestPassQuick = find.byKey(const ValueKey<String>('panel_hizli_ziyaretciKodu'));
Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

/// Gövdenin kaydırma alanı (aşağı çek yenile içindeki).
Finder _bodyScrollable() =>
    find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;

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

/// Kartın rozetindeki sayı (rozet yoksa null).
String? _badgeOf(WidgetTester t, SirketMenuItem item) {
  final badge = find.descendant(of: _card(item), matching: find.byKey(const ValueKey<String>('panel_kart_rozet')));
  if (badge.evaluate().isEmpty) return null;
  return t.widget<Text>(find.descendant(of: badge, matching: find.byType(Text))).data;
}

/// Kapı yokluğu (Kapılar kartı, hızlı "Kapıyı aç", Eller Serbest, çekmecede Kapılar).
Future<void> _expectNoDoorEntries(WidgetTester t, {required String reason}) async {
  expect(_card(SirketMenuItem.kapilar), findsNothing, reason: reason);
  expect(_quick(SirketMenuItem.kapilar), findsNothing, reason: reason);
  expect(find.text('Kapıyı aç'), findsNothing, reason: reason);
  expect(find.byKey(const ValueKey<String>('panel_ikincil_ellerSerbest')), findsNothing, reason: reason);
  await _openDrawer(t);
  expect(_drawerTitles(t), isNot(contains('Kapılar')), reason: reason);
  expect(_drawerTitles(t), isNot(contains('Eller Serbest & Kestirmeler')), reason: reason);
  await _closeDrawer(t);
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

    testWidgets('menü listesinde "Kapılar" "Panel"in hemen altında; çekmecede "Site hizmetleri" başlığında', (t) async {
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _openDrawer(t);
      final titles = _drawerTitles(t).where((title) => title != 'Sakin Moduna Geç').toList();
      expect(titles.first, 'Panel');
      final list = menuListTitles(t);
      expect(list.first, 'Panel');
      expect(list[1], 'Kapılar', reason: 'vitrin sırası: Kapılar kartı ilk kart');
      expectUnderDrawerHeader(t, 'Kapılar', 'Site hizmetleri');
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
      // İP-1D: çekmece + Ayarlar paneli (dişli) birlikte görünür öğelerdir.
      final drawer = (await menuAndSettingsTitles(t))
          .where((title) => !_drawerOnlyTitles.contains(title))
          .toList();
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
      // tasarim-4: anahtar süper kullanıcıdadır; kart bunu söyler.
      expect(
        find.descendant(of: _card(SirketMenuItem.moduller), matching: find.text('Site modüllerini açın ve kapatın')),
        findsOneWidget,
      );
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
          _my('manager', modules: {'announcements': true, 'finance': true, 'work_tracking': true, 'drive_storage': false}),
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
      // tasarim-4: site yöneticisi modülü kendi açıp kapatmaz (talep eder): kart açma / kapama VAAT ETMEZ.
      expect(
        find.descendant(of: _card(SirketMenuItem.moduller), matching: find.text('Tanımlı modüller ve modül talebi')),
        findsOneWidget,
      );
      expect(find.text('Site modüllerini açın ve kapatın'), findsNothing);
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('daire sakini: hero + hızlı işlemler + açık modüller; yönetim kartları yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', modules: {'announcements': true, 'finance': true, 'drive_storage': true, 'work_tracking': true}),
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

    testWidgets('kurul üyesi (salt okunur, dairesiz): Kişiler / Finans / Duyurular kartları; yönetim yazma kartları ve kapı yok',
        (t) async {
      // Dairesiz kurul üyesinde (door_access=false) sunucu kapı listesini BOŞ verir.
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
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
      await _expectNoDoorEntries(t, reason: 'yetki-1: kapı erişimi olmayan kurul üyesine kapı vaat edilmez');
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('görevli (staff): yalnız açık yönetim modülleri; Borcum / Duyurular / Finans ve kapı kartı yok', (t) async {
      // Yalnız görevli bağı (door_access=false): sunucu kapı listesini BOŞ verir.
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
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
      await _expectNoDoorEntries(t, reason: 'yetki-1: yalnız görevli bağı olan hesapta kapı yok');
      expect(find.text('Hızlı işlemler'), findsNothing, reason: 'tek hızlı işlem "Kapıyı aç" idi; o da yok');
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('bireysel kullanıcı: Kapılar + Daireye Katıl; hero ve hızlı işlem yok', (t) async {
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
      // tasarim-4: bireysel kullanıcıda Kapılar sayfası bireysel ana ekrandır.
      expect(
        find.descendant(of: _card(SirketMenuItem.kapilar), matching: find.text('Kapılar, daireleriniz ve cihazlarınız')),
        findsOneWidget,
      );
      await expectSameAsDrawer(t);
      await _disposeHome(t);
    });
  });

  group('yetki-1: daire sakini rolünde kapı erişimi / kapısı olmayan hesapta kapı öğeleri yok', () {
    for (final (role, label) in <(String, String)>[
      ('board_member', 'dış kurul üyesi'),
      ('staff', 'görevli'),
      ('resident', 'yalnız site üyeliği olan sakin'),
    ]) {
      for (final doorOpen in <bool>[true, false]) {
        testWidgets('$label, Geçiş Kontrol ${doorOpen ? 'AÇIK' : 'KAPALI'}: Kapılar kartı, "Kapıyı aç", Eller Serbest yok',
            (t) async {
          final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
          final access = await _access(
            () => <MySiteModules>[_my(role, doorOpen: doorOpen, doorAccess: false, modules: {'drive_storage': true})],
          );
          await _pumpHome(t, auth, access: access);
          expect(find.byType(ModuleShowcaseView), findsOneWidget);
          await _expectNoDoorEntries(t, reason: '$label / ${doorOpen ? 'açık' : 'kapalı'}');
          expect(_guestPassQuick, findsNothing);
          expect(_card(SirketMenuItem.katilimVeKurulum), findsOneWidget, reason: 'öteki kartlar durur');
          await _disposeHome(t);
        });
      }
    }

    testWidgets('kapı listesi doluysa (sunucu kapı verdi) Kapılar kalır', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: <DoorRecord>[_door]);
      final access = await _access(() => <MySiteModules>[_my('board_member', doorAccess: false)]);
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kapilar), findsOneWidget);
      expect(_quick(SirketMenuItem.kapilar), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('modül verisi hiç gelmezse (fail-open) Kapılar eskisi gibi durur', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      final access = ModuleAccess(fetch: () async => throw StateError('ağ yok'));
      addTearDown(access.dispose);
      await access.refresh();
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kapilar), findsOneWidget);
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
          _my('resident', modules: {'announcements': true, 'finance': finance, 'drive_storage': documents}),
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
      expect(_drawerTitles(t), isNot(contains('Dosya Deposu')));
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

  // test-14: gerçek fail-closed tablosu. Modül verisi -> HomePage ek öğe / gizleme kuralları -> çekmece listesi -> vitrin
  // yolunun TAMAMI sınanır: kod kapalıyken ilgili kart (ve sakinde hızlı işlem) yok, açıkken var. Çekirdek modüller
  // (`people`, `announcements`) her sitede açıktır, kapatılamaz: tabloda yoktur.
  group('fail-closed tablosu: her modül kodu kapalıyken kart / hızlı işlem yok, açıkken var', () {
    const table = <(String, SirketMenuItem, SirketMenuItem?, bool)>[
      // (kod, yönetici kartı, sakin kartı, sakinde hızlı işlem var mı)
      ('finance', SirketMenuItem.finans, SirketMenuItem.borcum, false),
      ('drive_storage', SirketMenuItem.belgeler, SirketMenuItem.belgeler, true),
      ('work_tracking', SirketMenuItem.talepler, SirketMenuItem.taleplerim, true),
      ('reservation', SirketMenuItem.rezervasyonlar, SirketMenuItem.rezervasyon, false),
      ('survey', SirketMenuItem.anketler, SirketMenuItem.anket, false),
      ('decision_book', SirketMenuItem.kararDefteri, SirketMenuItem.kararlar, false),
      ('visitor_log', SirketMenuItem.ziyaretciKayitlari, SirketMenuItem.ziyaretcilerim, true),
      ('contracts', SirketMenuItem.sozlesmeler, null, false),
      ('door_control', SirketMenuItem.kapilar, SirketMenuItem.kapilar, true),
    ];

    for (final (code, managerItem, residentItem, residentQuick) in table) {
      testWidgets('$code (yönetici): kapalıyken ${managerItem.name} kartı yok, açıkken var', (t) async {
        _fakeVisitorServer();
        for (final on in <bool>[false, true]) {
          final auth = _ShowcaseAuth(UserRole.siteManager);
          final access = await _access(() => <MySiteModules>[_my('manager', modules: {code: on})]);
          await _pumpHome(t, auth, access: access);
          expect(_card(managerItem), on ? findsOneWidget : findsNothing, reason: '$code=${on ? 'açık' : 'kapalı'}');
          await _disposeHome(t);
        }
      });

      testWidgets('$code (sakin): kapalıyken ${residentItem?.name ?? 'sakin öğesi'} kartı / hızlı işlemi yok, açıkken var',
          (t) async {
        _fakeVisitorServer();
        for (final on in <bool>[false, true]) {
          final auth = _ShowcaseAuth(UserRole.apartmentOwner);
          final access = await _access(() => <MySiteModules>[_my('resident', modules: {code: on})]);
          await _pumpHome(t, auth, access: access);
          final reason = '$code=${on ? 'açık' : 'kapalı'}';
          if (residentItem == null) {
            expect(_card(managerItem), findsNothing, reason: '$reason: sakin bu modülü görmez');
          } else {
            expect(_card(residentItem), on ? findsOneWidget : findsNothing, reason: reason);
            if (residentQuick) {
              expect(_quick(residentItem), on ? findsOneWidget : findsNothing, reason: '$reason (hızlı işlem)');
            }
          }
          await _disposeHome(t);
        }
      });
    }
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
      expect(auth.openDoorCalls, 0, reason: 'kısayol yalnız sayfa açar');
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
          _my('resident', doorOpen: false, modules: {'announcements': true, 'work_tracking': true, 'drive_storage': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_card(SirketMenuItem.kapilar), findsNothing);
      expect(_quick(SirketMenuItem.kapilar), findsNothing);
      expect(find.text('Kapıyı aç'), findsNothing);
      expect(_guestPassQuick, findsNothing, reason: 'kapı modülü kapalıyken misafir geçişi de yok');
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

  // test-1: "vitrinde kapı AÇILMAZ" iddiası sayaçla korunur. Sahte servis openDoor'u (bulut + yerel ağ yolu) ve karekodla
  // açmayı sayar; pozitif kontrol (Kapılar sayfasındaki düğme) sayacın gerçekten bağlı olduğunu kanıtlar.
  group('vitrinde hiçbir dokunuş kapı komutu göndermez', () {
    final roles = <(String, UserRole, List<MySiteModules> Function(), bool, String?)>[
      ('süper kullanıcı', UserRole.superUser, () => const <MySiteModules>[], true, 'admin_door_open_button'),
      (
        'site yöneticisi',
        UserRole.siteManager,
        () => <MySiteModules>[_my('manager', modules: {'finance': true})],
        false,
        'admin_door_open_button',
      ),
      (
        'daire sakini',
        UserRole.apartmentOwner,
        () => <MySiteModules>[_my('resident', modules: {'finance': true, 'drive_storage': true, 'work_tracking': true})],
        false,
        'resident_door_open_button',
      ),
      ('bireysel', UserRole.individual, () => const <MySiteModules>[], false, null),
    ];

    for (final (label, role, sites, isSuper, doorButton) in roles) {
      testWidgets('$label: açılış, yenileme, kartlar, hızlı işlemler ve odak / borç düğmeleri kapıyı açmaz', (t) async {
        final auth = _ShowcaseAuth(role, online: true);
        final access = await _access(sites, superUser: isSuper, pendingModules: 2);
        await _pumpHome(t, auth, access: access, height: 1400);

        // (a) Açılıştan 3 sn sonra.
        await t.pump(const Duration(seconds: 3));
        expect(auth.openDoorCalls, 0, reason: 'açılış');

        // (c) Aşağı çek yenile: yenileme GERÇEKTEN çalıştı (kapı verisi yeniden okundu) ama kapı açılmadı.
        final doorsBefore = auth.listMyDoorsCalls + auth.listSitesCalls;
        await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, 600));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        expect(auth.listMyDoorsCalls + auth.listSitesCalls, greaterThan(doorsBefore), reason: 'yenileme çalıştı');
        expect(auth.openDoorCalls, 0, reason: 'aşağı çek yenile');

        // (d) Odak barı (süper kullanıcı) ve hero "Borcum'a git" (sakin): yalnız sayfa açar.
        final focus = find.byKey(const ValueKey<String>('panel_odak_modulTalepleri'));
        if (focus.evaluate().isNotEmpty) {
          await t.ensureVisible(focus);
          await t.tap(focus);
          await t.pump();
          await t.pump(const Duration(milliseconds: 700));
          expect(await _back(t), isTrue);
        }
        final debt = find.byKey(const ValueKey<String>('panel_hero_borcuma_git'));
        if (debt.evaluate().isNotEmpty) {
          await t.ensureVisible(debt);
          await t.tap(debt);
          await t.pump();
          await t.pump(const Duration(milliseconds: 700));
          expect(find.byType(MyFinanceView), findsOneWidget);
          expect(await _back(t), isTrue);
        }
        expect(auth.openDoorCalls, 0, reason: 'odak / borç düğmeleri');

        // (b) Hızlı "Kapıyı aç" (sakin) ve "Kapılar" kartı: yalnız Kapılar sayfasını açar.
        if (_quick(SirketMenuItem.kapilar).evaluate().isNotEmpty) {
          await t.ensureVisible(_quick(SirketMenuItem.kapilar));
          await t.tap(_quick(SirketMenuItem.kapilar));
          await t.pump();
          await t.pump(const Duration(milliseconds: 700));
          expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
          expect(await _back(t), isTrue);
        }
        await _tapCard(t, SirketMenuItem.kapilar);
        expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
        await t.pump(const Duration(seconds: 3));
        expect(auth.openDoorCalls, 0, reason: 'Kapılar kartı / hızlı işlem yalnız sayfa açar');
        expect(auth.qrOpenCalls, 0);

        // Pozitif kontrol: Kapılar sayfasındaki düğmeye dokununca komut BİR kez gider (sayaç bağlı).
        if (doorButton != null) {
          final button = find.byKey(ValueKey<String>(doorButton));
          await t.ensureVisible(button);
          await t.pump();
          await t.tap(button);
          await t.pump();
          await t.pump(const Duration(milliseconds: 100));
          expect(auth.openDoorCalls, 1, reason: 'Kapılar sayfasında kapı düğmesi çalışır');
          await t.pump(const Duration(seconds: 2));
        }
        await _disposeHome(t);
      });
    }
  });

  // kapi-2: vitrindeki kutuya hızlı çift dokunuşun ikincisi, geçiş sürerken henüz görünmeyen KAPIYI AÇ düğmesine düşmez.
  group('Kapılar sayfasına girişte kısa süre dokunuş yutulur (kazara kapı açılmaz)', () {
    final cases = <(String, UserRole, MySiteModules, Finder, String)>[
      (
        'sakin, hızlı "Kapıyı aç"',
        UserRole.apartmentOwner,
        _my('resident'),
        _quick(SirketMenuItem.kapilar),
        'resident_door_open_button',
      ),
      (
        'yönetici, "Kapılar" kartı',
        UserRole.siteManager,
        _my('manager'),
        _card(SirketMenuItem.kapilar),
        'admin_door_open_button',
      ),
    ];

    for (final (label, role, site, entry, doorButton) in cases) {
      testWidgets('$label: ikinci dokunuş düğmeye düşse de komut SIFIR; koruma bitince tek dokunuş açar', (t) async {
        final auth = _ShowcaseAuth(role, online: true);
        final access = await _access(() => <MySiteModules>[site]);
        await _pumpHome(t, auth, access: access, height: 900);
        await t.ensureVisible(entry);
        await t.pump();

        // İlk dokunuş: Kapılar sayfasına geçiş başlar.
        await t.tap(entry);
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        final button = find.byKey(ValueKey<String>(doorButton));
        expect(button, findsOneWidget);
        expect(
          t.widget<DoorOpenButton>(button).state,
          DoorOpenState.ready,
          reason: 'düğme hazır: koruma olmasa bu dokunuş kapıyı açardı',
        );

        // Çift dokunuşun ikincisi ve hemen ardından bir dokunuş daha (geçiş 200 ms'de bitti, koruma sürüyor).
        await t.tapAt(t.getCenter(button));
        await t.pump();
        await t.pump(const Duration(milliseconds: 150));
        await t.tapAt(t.getCenter(button));
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));
        expect(auth.openDoorCalls, 0, reason: 'giriş sırasında kapı komutu gitmez');

        // Koruma bitti: normal tek dokunuş kapıyı açar.
        await t.pump(HomePage.doorEntryGuard);
        await t.tap(button);
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(auth.openDoorCalls, 1);
        await t.pump(const Duration(seconds: 2));
        await _disposeHome(t);
      });
    }

    testWidgets('koruma yalnız Kapılar sayfasındadır: öteki sayfalar girişte hemen dokunuş alır', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access);
      final chip = find.byKey(const ValueKey<String>('panel_ikincil_profilim'));
      await t.ensureVisible(chip);
      await t.tap(chip);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final guard = t.widget<IgnorePointer>(find.byKey(const ValueKey<String>('kapilar_giris_korumasi')));
      expect(guard.ignoring, isFalse);
      await _disposeHome(t);
    });
  });

  group('karta dokununca doğru sayfa (çekmecede seçmekle aynı gezinme)', () {
    testWidgets('Borcum kartı -> Borcum sayfası; geri tuşu ve çekmeceden "Panel" vitrine döner', (t) async {
      final calls = _capturePlatform(t);
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
      expect(await _back(t), isTrue);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_inAppBar(find.text('Panel')), findsOneWidget);
      expect(calls, isNot(contains('SystemNavigator.pop')));

      // Vitrindeyken geri tuşu uygulamadan çıkar (eski davranış).
      expect(await _back(t), isFalse);
      expect(calls, contains('SystemNavigator.pop'));

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
      expect(find.byType(HelpView), findsOneWidget, reason: 'açılan sayfa yardım ekranıdır (yalnız metin değil)');
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

  // kapi-4 / gezinme-1 / test-2 / yetki-4 / gezinme-5: geri tuşu kararı.
  group('geri tuşu: çekmece açıkken önce çekmece kapanır; erişimi düşen sayfada ilk geri boşa gitmez', () {
    testWidgets('modül sayfasında (Borcum, Kapılar) çekmece açıkken geri: çekmece kapanır, sayfa DEĞİŞMEZ', (t) async {
      final calls = _capturePlatform(t);
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);

      for (final (item, page) in <(SirketMenuItem, Type)>[
        (SirketMenuItem.borcum, MyFinanceView),
        (SirketMenuItem.kapilar, DashboardView),
      ]) {
        await _tapCard(t, item);
        expect(find.byType(page), findsOneWidget);
        await _openDrawer(t);
        expect(find.byType(Drawer), findsOneWidget);

        expect(await _back(t), isTrue, reason: '$item: geri olayı karşılandı (uygulamadan çıkılmadı)');
        expect(find.byType(Drawer), findsNothing, reason: '$item: çekmece kapandı');
        expect(find.byType(page), findsOneWidget, reason: '$item: arkadaki sayfa değişmedi');
        expect(find.byType(ModuleShowcaseView), findsNothing);

        // İkinci geri: vitrine döner.
        expect(await _back(t), isTrue);
        expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: '$item: ikinci geri vitrine döner');
      }
      // Vitrinde çekmece açıkken geri de yalnız çekmeceyi kapatır; sonraki geri uygulamadan çıkar.
      await _openDrawer(t);
      expect(await _back(t), isTrue);
      expect(find.byType(Drawer), findsNothing);
      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(await _back(t), isFalse);
      expect(calls, contains('SystemNavigator.pop'));
      await _disposeHome(t);
    });

    testWidgets('açık sayfanın modülü kapanınca vitrine düşülür; İLK geri uygulamadan çıkar, çekmecede "Panel" seçili', (t) async {
      final calls = _capturePlatform(t);
      var finance = true;
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': finance})]);
      await _pumpHome(t, auth, access: access);
      await _tapCard(t, SirketMenuItem.borcum);
      expect(find.byType(MyFinanceView), findsOneWidget);

      finance = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_inAppBar(find.text('Panel')), findsOneWidget);

      // Araya başka yeniden kurulum (çekmece aç / kapa) GİRMEDEN ilk geri: karar ekrandaki sayfayla verilmeli.
      expect(await _back(t), isFalse, reason: 'vitrindeyken ilk geri uygulamadan çıkar');
      expect(calls, contains('SystemNavigator.pop'));

      await _openDrawer(t);
      expect(t.widget<YanMenu>(find.byType(YanMenu)).selectedItem, SirketMenuItem.dashboard);
      await _closeDrawer(t);
      await _disposeHome(t);
    });

    testWidgets('yönetici "Modüller"deyken Sakin Modu: vitrine düşülür; İLK geri uygulamadan çıkar', (t) async {
      final calls = _capturePlatform(t);
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      await _tapCard(t, SirketMenuItem.moduller);
      expect(_inAppBar(find.text('Modüller')), findsOneWidget);

      // P1-13: iç ekranda ("Ana sayfa" düğmesi varken, 480 dp altında) mod hapı yalnız ikondur; ipucu "Sakin Modu".
      await t.tap(_inAppBar(find.byTooltip('Sakin Modu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(_inAppBar(find.text('Panel')), findsOneWidget);

      expect(await _back(t), isFalse, reason: 'sakin modunda Modüller erişilemez: ekrandaki sayfa vitrindir');
      expect(calls, contains('SystemNavigator.pop'));
      await _disposeHome(t);
    });
  });

  // gezinme-2: sayfa değişince kaydırma en üstten.
  group('sayfa değişince kaydırma en üstten başlar', () {
    testWidgets('vitrinde aşağı kaydırıp karta dokununca sayfa EN ÜSTTEN açılır; dönülen vitrin de baştan', (t) async {
      final auth = _ShowcaseAuth(UserRole.superUser);
      final access = await _access(() => const <MySiteModules>[], superUser: true);
      await _pumpHome(t, auth, access: access, width: 400, height: 520);

      final chip = find.byKey(const ValueKey<String>('panel_ikincil_profilim'));
      await t.ensureVisible(chip);
      await t.pump();
      expect(t.state<ScrollableState>(_bodyScrollable()).position.pixels, greaterThan(200), reason: 'vitrin kaydırıldı');

      await t.tap(chip);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Profilim')), findsOneWidget);
      final page = t.state<ScrollableState>(_bodyScrollable()).position;
      expect(page.maxScrollExtent, greaterThan(0), reason: 'sayfa uzun: eski konum kıstırılıp korunabilirdi');
      expect(page.pixels, 0, reason: 'yeni sayfa en üstten açılır');

      expect(await _back(t), isTrue);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(t.state<ScrollableState>(_bodyScrollable()).position.pixels, 0, reason: 'vitrin de baştan');
      await _disposeHome(t);
    });

    testWidgets('mod çekmeceden değişince (Sakin Moduna Geç) de kaydırma en üstten; anlam ağacı / GlobalKey hatası yok', (t) async {
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(
        () => <MySiteModules>[
          _my('manager', modules: {'announcements': true, 'finance': true, 'work_tracking': true, 'drive_storage': true}),
        ],
      );
      await _pumpHome(t, auth, access: access, width: 400, height: 520);
      await t.drag(_bodyScrollable(), const Offset(0, -400));
      await t.pump();
      expect(t.state<ScrollableState>(_bodyScrollable()).position.pixels, greaterThan(0));

      // Çekmece kapanırken mod değişir (vitrin GlobalKey'iyle yeni sayfaya taşınır): aynı karede ikisi birden.
      await _openDrawer(t);
      await t.tap(find.text('Sakin Moduna Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull);
      ShowcaseAudience audience() => t.widget<ModuleShowcaseView>(find.byType(ModuleShowcaseView)).audience;
      expect(audience(), ShowcaseAudience.resident, reason: 'sakin vitrini');
      expect(t.state<ScrollableState>(_bodyScrollable()).position.pixels, 0);

      await _openDrawer(t);
      await t.tap(find.text('Yönetici Paneline Geç'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull);
      expect(audience(), ShowcaseAudience.admin);
      await _disposeHome(t);
    });
  });

  // gezinme-6 + tasarim-11: vitrinde Yenile rozetleri ve "Yeni duyuru" kartını hemen tazeler; kart vitrinde düzdür.
  group('vitrinde Yenile: duyuru / ziyaretçi rozetleri ve "Yeni duyuru" kartı', () {
    testWidgets('Yenile yoklama aralığını beklemeden rozetleri ve kartı tazeler; kart hero kartının üstünde, gölgesiz ve 3 turla biter', (t) async {
      final visitors = _fakeVisitorServer();
      var unread = 0;
      var summaryCalls = 0;
      const item = ResidentAnnouncement(
        id: 5,
        siteCode: 1,
        siteName: 'Güneş Sitesi',
        title: 'Su kesintisi',
        bodyPreview: 'Yarın 10:00-12:00 arası su verilmeyecek.',
      );
      final notifier = AnnouncementNotifier(
        fetchSummary: () async {
          summaryCalls++;
          return NotificationSummary(unreadAnnouncements: unread, latestAnnouncementId: unread > 0 ? 5 : null);
        },
        fetchInbox: () async => ResidentAnnouncementPage(items: unread > 0 ? const [item] : const <ResidentAnnouncement>[]),
        fetchAnnouncement: (id) async => item,
        isEligible: () => true,
      );
      addTearDown(notifier.dispose);
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[_my('resident', modules: {'announcements': true, 'visitor_log': true})],
      );
      await _pumpHome(t, auth, access: access, notifier: notifier);
      expect(find.byType(UnreadAnnouncementCard), findsNothing);
      expect(_badgeOf(t, SirketMenuItem.duyurular), isNull);
      expect(_badgeOf(t, SirketMenuItem.ziyaretcilerim), isNull);

      // Sunucuda yeni duyuru ve ziyaretçi kaydı var; yoklamalar (20 / 60 sn) henüz dönmedi.
      unread = 1;
      visitors.unread = 2;
      final summaryBefore = summaryCalls;
      final visitorBefore = visitors.summaryCalls;
      await t.tap(_inAppBar(find.byTooltip('Yenile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(summaryCalls, greaterThan(summaryBefore), reason: 'duyuru özeti yenilendi');
      expect(visitors.summaryCalls, greaterThan(visitorBefore), reason: 'ziyaretçi rozeti yenilendi');
      expect(_badgeOf(t, SirketMenuItem.duyurular), '1');
      expect(_badgeOf(t, SirketMenuItem.ziyaretcilerim), '2');
      expect(find.byType(UnreadAnnouncementCard), findsOneWidget);
      expect(find.text('Su kesintisi'), findsOneWidget);

      // N1: kart Panel'in en üstünde (selam / borç kartının ÜSTÜNDE); gölgesiz sade yüzey; 3 tur sonra durur.
      final card = find.byType(UnreadAnnouncementCard);
      final hero = find.byKey(const ValueKey<String>('panel_hero_selam'));
      if (hero.evaluate().isNotEmpty) {
        expect(t.getTopLeft(card).dy, lessThan(t.getTopLeft(hero).dy), reason: 'okunmamış duyuru kartı hero kartının üstünde');
      }
      final shadows = <BoxShadow>[
        for (final box in t.widgetList<DecoratedBox>(find.descendant(of: card, matching: find.byType(DecoratedBox))))
          if (box.decoration is BoxDecoration) ...?(box.decoration as BoxDecoration).boxShadow,
      ];
      expect(shadows, isEmpty, reason: 'vitrinde gölgeli / parlayan kart yok');
      await _disposeHome(t);
    });
  });

  // yetki-2: çok siteli sakinde bir sitenin Finans'ı kapanınca hero eski tutarla kalmaz.
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

    // İP-1A (G12): vitrin yalnız kişinin KENDİ hesabını sayar; malike salt okunur gösterilen kiracı hesabı borcu vitrine girmez.
    testWidgets('iki hesap: kendi (ev sahibi) hesabı borçsuz, salt okunur kiracı hesabı borçlu -> "Borcunuz yok", kiracı tutarı yok',
        (t) async {
      final auth = _ShowcaseAuth(
        UserRole.apartmentOwner,
        finance: () async => const MyFinance(
          items: [
            MyFinanceApartment(
              siteCode: 1,
              siteName: 'Güneş Sitesi',
              apartmentId: 5,
              label: 'D:3',
              blockName: 'A Blok',
              balanceMinor: 0,
              accountParty: AccountParty.owner,
              accounts: [
                MyFinanceAccount(accountParty: AccountParty.owner, balanceMinor: 0),
                MyFinanceAccount(accountParty: AccountParty.tenant, role: MyFinanceAccountRole.readOnly, balanceMinor: 168000, overdueMinor: 156000),
              ],
            ),
          ],
        ),
      );
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);
      expect(find.byKey(const ValueKey<String>('panel_hero_borc')), findsOneWidget);
      expect(find.text('Borcunuz yok'), findsOneWidget);
      expect(find.text('Güncel borcunuz'), findsNothing);
      expect(find.text('1.680,00 ₺'), findsNothing, reason: 'salt okunur kiracı hesabı vitrine eklenmez');
      expect(find.textContaining('Ev sahibi hesabı'), findsOneWidget, reason: 'tek dairede kendi hesabının adı yazılır');
      await _disposeHome(t);
    });

    testWidgets('iki hesap: kiracının kendi hesabı borçlu -> "Güncel borcunuz" kendi tutarı ve "Kiracı hesabı"', (t) async {
      final auth = _ShowcaseAuth(
        UserRole.apartmentOwner,
        finance: () async => const MyFinance(
          items: [
            MyFinanceApartment(
              siteCode: 1,
              siteName: 'Güneş Sitesi',
              apartmentId: 5,
              label: 'D:3',
              blockName: 'A Blok',
              balanceMinor: 168000,
              overdueMinor: 156000,
              accountParty: AccountParty.tenant,
              accounts: [MyFinanceAccount(accountParty: AccountParty.tenant, balanceMinor: 168000, overdueMinor: 156000)],
            ),
          ],
        ),
      );
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'finance': true})]);
      await _pumpHome(t, auth, access: access);
      expect(find.text('Güncel borcunuz'), findsOneWidget);
      expect(find.text('1.680,00 ₺'), findsOneWidget);
      expect(find.text('Vadesi geçen: 1.560,00 ₺'), findsOneWidget);
      expect(find.textContaining('Kiracı hesabı'), findsOneWidget);
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

    MySiteModules second({required bool finance}) => MySiteModules(
      siteCode: 2,
      siteName: 'Ay Sitesi',
      role: 'resident',
      doorAccess: true,
      modules: <String, bool>{'door_control': true, 'finance': finance},
    );

    testWidgets('çok siteli: bir sitede Finans kapanınca (Borcum menüde kalır) kapanan sitenin tutarı GÖSTERİLMEZ, özet yeniden okunur',
        (t) async {
      var bOpen = true;
      final auth = _ShowcaseAuth(
        UserRole.apartmentOwner,
        // Sunucu gibi: yalnız Finans'ı açık sitelerin daireleri.
        finance: () async => MyFinance(
          items: [_apt(1, 'Güneş Sitesi', 0), if (bOpen) _apt(2, 'Ay Sitesi', 450000)],
        ),
      );
      final access = await _access(
        () => <MySiteModules>[_my('resident', modules: {'finance': true}), second(finance: bOpen)],
      );
      await _pumpHome(t, auth, access: access);
      expect(find.text('4.500,00 ₺'), findsOneWidget);
      final calls = auth.financeCalls;

      bOpen = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(_card(SirketMenuItem.borcum), findsOneWidget, reason: 'öteki sitede Finans açık: Borcum menüde kalır');
      expect(auth.financeCalls, greaterThan(calls), reason: 'site kümesi değişti: özet yeniden okundu');
      expect(find.text('4.500,00 ₺'), findsNothing, reason: 'kapanan sitenin tutarı vitrinde kalmaz');
      await _disposeHome(t);
    });

    testWidgets('sunucu yanıtı kapanan sitenin dairesini hâlâ içerse de vitrin onu göstermez (istemci süzgeci)', (t) async {
      var bOpen = true;
      final auth = _ShowcaseAuth(
        UserRole.apartmentOwner,
        // Bayat sunucu: kapanan sitenin dairesini de döndürür.
        finance: () async => MyFinance(items: [_apt(1, 'Güneş Sitesi', 0), _apt(2, 'Ay Sitesi', 450000)]),
      );
      final access = await _access(
        () => <MySiteModules>[_my('resident', modules: {'finance': true}), second(finance: bOpen)],
      );
      await _pumpHome(t, auth, access: access);
      expect(find.text('4.500,00 ₺'), findsOneWidget);

      bOpen = false;
      await access.refresh();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('4.500,00 ₺'), findsNothing);
      expect(find.text('Borcunuz yok'), findsOneWidget, reason: 'yalnız açık sitenin (sıfır bakiye) özeti');
      await _disposeHome(t);
    });
  });

  // yetki-3 + tasarim-5 + tasarim-7 + tasarim-13: hızlı işlemler ve başlıklar.
  group('hızlı işlemler: daire bağı, "Ziyaretçi kodu", erişilebilir ipuçları', () {
    testWidgets('dairesi olmayan kurul üyesine "Arıza bildir" ve "Ziyaretçi ve kargo" kısayolu çıkmaz (kart ve çekmece durur)',
        (t) async {
      _fakeVisitorServer();
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      final access = await _access(
        () => <MySiteModules>[
          _my('board_member', doorAccess: false, modules: {'work_tracking': true, 'visitor_log': true, 'drive_storage': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_quick(SirketMenuItem.taleplerim), findsNothing);
      expect(_quick(SirketMenuItem.ziyaretcilerim), findsNothing);
      expect(find.text('Arıza bildir'), findsNothing);
      expect(_card(SirketMenuItem.taleplerim), findsOneWidget, reason: 'kart çekmeceyle tutarlı (eski kural)');
      expect(_card(SirketMenuItem.ziyaretcilerim), findsOneWidget);
      expect(_quick(SirketMenuItem.belgeler), findsOneWidget, reason: 'site belgeleri daire bağı istemez');
      await _disposeHome(t);
    });

    testWidgets('yalnız site üyeliği olan sakine (door_access yok) de bu iki kısayol çıkmaz', (t) async {
      _fakeVisitorServer();
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: const <DoorRecord>[]);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', doorAccess: false, modules: {'work_tracking': true, 'visitor_log': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_quick(SirketMenuItem.taleplerim), findsNothing);
      expect(_quick(SirketMenuItem.ziyaretcilerim), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('dairesi olan kurul üyesi (door_access): kısayollar görünür; iki ziyaretçi kartı AYRI başlıklı', (t) async {
      _fakeVisitorServer();
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('board_member', doorAccess: true, modules: {'work_tracking': true, 'visitor_log': true}),
        ],
      );
      await _pumpHome(t, auth, access: access);
      expect(_quick(SirketMenuItem.taleplerim), findsOneWidget);
      expect(_quick(SirketMenuItem.ziyaretcilerim), findsOneWidget);

      // tasarim-13: yönetim (salt okunur) kaydı ve sakin ekranı aynı adla iki kart DEĞİL.
      expect(
        find.descendant(of: _card(SirketMenuItem.ziyaretciKayitlari), matching: find.text('Ziyaretçi ve Kargo')),
        findsOneWidget,
      );
      expect(find.descendant(of: _card(SirketMenuItem.ziyaretcilerim), matching: find.text('Ziyaretçilerim')), findsOneWidget);
      final titles = _showcaseTitles(t);
      expect(titles.toSet().length, titles.length, reason: 'vitrinde aynı başlıklı iki kart yok');
      await _openDrawer(t);
      final drawer = _drawerTitles(t);
      expect(drawer, containsAll(<String>['Ziyaretçi ve Kargo', 'Ziyaretçilerim']));
      expect(drawer.toSet().length, drawer.length, reason: 'çekmecede de aynı adlı iki öğe yok');
      await _closeDrawer(t);
      await t.tap(_card(SirketMenuItem.ziyaretcilerim));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_inAppBar(find.text('Ziyaretçilerim')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('"Ziyaretçi kodu": misafir / kurye geçiş linki penceresini açar, kapı AÇMAZ', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, online: true);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'work_tracking': true})]);
      await _pumpHome(t, auth, access: access);
      expect(_guestPassQuick, findsOneWidget);
      // Sıra: Kapıyı aç, Arıza bildir, Ziyaretçi kodu.
      final quickDx = <double>[
        for (final f in [_quick(SirketMenuItem.kapilar), _quick(SirketMenuItem.taleplerim), _guestPassQuick])
          t.getTopLeft(f).dy * 10000 + t.getTopLeft(f).dx,
      ];
      expect(quickDx, equals([...quickDx]..sort()), reason: 'işverenin sırası: Arıza bildir, Ziyaretçi kodu');

      await t.ensureVisible(_guestPassQuick);
      await t.tap(_guestPassQuick);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(CreateGuestPassDialog), findsOneWidget);
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'sayfa değişmedi');
      expect(auth.openDoorCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('misafir geçişine izin olmayan kapıda ve kapısı olmayan hesapta "Ziyaretçi kodu" yok', (t) async {
      for (final doors in <List<DoorRecord>>[
        <DoorRecord>[_doorNoGuestPass],
        const <DoorRecord>[],
      ]) {
        final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: doors);
        final access = await _access(() => <MySiteModules>[_my('resident')]);
        await _pumpHome(t, auth, access: access);
        expect(_guestPassQuick, findsNothing, reason: 'kapı sayısı ${doors.length}');
        await _disposeHome(t);
      }
    });

    testWidgets('erişilebilir ipucu dokununca olanı söyler ("Kapıyı aç" Kapılar sayfasını açar, kapıyı açmaz)', (t) async {
      final handle = t.ensureSemantics();
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident', modules: {'work_tracking': true})]);
      await _pumpHome(t, auth, access: access);
      expect(
        t.getSemantics(_quick(SirketMenuItem.kapilar)),
        isSemantics(
          label: 'Kapıyı aç',
          hint: 'Kapılar sayfasını açar; kapı orada açılır',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        t.getSemantics(_quick(SirketMenuItem.taleplerim)),
        isSemantics(
          label: 'Arıza bildir',
          hint: 'Taleplerim sayfasını açar; yeni talep oradan bildirilir',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        t.getSemantics(_guestPassQuick),
        isSemantics(
          label: 'Ziyaretçi kodu',
          hint: 'Misafir ve kurye için süreli geçiş linki oluşturur; kapıyı açmaz',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
      await _disposeHome(t);
    });
  });

  // kapi-3: widget gövdesi / kısayol / derin bağlantı Kapılar sayfasını açar (Panel değil).
  group('dışarıdan "Kapılar sayfasını aç" isteği (Android kapı widget\'ı, kısayollar)', () {
    testWidgets('soğuk açılış: bekleyen istek varsa uygulama Kapılar sayfasında açılır; kapı AÇILMAZ', (t) async {
      final requests = DoorPanelRequests()..request();
      addTearDown(requests.dispose);
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, online: true);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access, doorPanelRequests: requests);
      expect(find.byType(DashboardView), findsOneWidget);
      expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
      expect(requests.isPending, isFalse, reason: 'istek bir kez uygulandı');
      await t.pump(const Duration(seconds: 1));
      expect(auth.openDoorCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('uygulama açıkken gelen istek vitrinden Kapılar sayfasına geçer', (t) async {
      final requests = DoorPanelRequests();
      addTearDown(requests.dispose);
      final auth = _ShowcaseAuth(UserRole.siteManager);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access, doorPanelRequests: requests);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);

      requests.request();
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(DashboardView), findsOneWidget);
      expect(_inAppBar(find.text('Kapılar')), findsOneWidget);
      expect(auth.openDoorCalls, 0);
      await _disposeHome(t);
    });

    testWidgets('Geçiş Kontrol kapalıyken ya da kapı erişimi yokken vitrinde kalınır (istek tüketilir)', (t) async {
      for (final (site, doors) in <(MySiteModules, List<DoorRecord>?)>[
        (_my('resident', doorOpen: false), null),
        (_my('staff', doorAccess: false), const <DoorRecord>[]),
      ]) {
        final requests = DoorPanelRequests();
        final auth = _ShowcaseAuth(UserRole.apartmentOwner, doors: doors);
        final access = await _access(() => <MySiteModules>[site]);
        await _pumpHome(t, auth, access: access, doorPanelRequests: requests);
        requests.request();
        await t.pump();
        await t.pump(const Duration(milliseconds: 700));
        expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: site.role);
        expect(find.byType(DashboardView), findsNothing);
        expect(requests.isPending, isFalse);
        await _disposeHome(t);
        requests.dispose();
      }
    });
  });

  // tasarim-10 gerileme düzeltmesi: eski düz zemin vitrinin içinden, vitrinin bir ekran boyu üstüne / altına boyanıyordu;
  // kaydırma görünümü içerik sığınca kırpmadığından üstteki acil duyuru şeridi ÖRTÜLÜYORDU (yalnız görünmez dokunma alanı
  // kalıyordu). Artık zemin kaydırılan gövdenin kabındadır: şeridin altından ekranın altına. Kanıt golden değil: geometri,
  // gerçek boya kaydı (kabın ve vitrinin hiçbir boyası kendi sınırını aşmaz) ve isabet testi.
  group('Panel zemini: kaydırılan gövdenin kabında düz #F8FAFC; acil duyuru şeridi örtülmez', () {
    final zemin = find.byKey(const ValueKey<String>('panel_vitrin_zemin'));
    final banner = find.byKey(const ValueKey<String>('urgent_announcement_banner'));
    final vitrin = find.byKey(const ValueKey<String>('panel_vitrin'));

    /// Kabın ilk boyası kendi dikdörtgeninin tamamı, düz #F8FAFC mi?
    void expectFlatFill(WidgetTester t, {required String reason}) {
      final box = t.renderObject<RenderBox>(zemin);
      final first = paintedShapes(box).first;
      expect(first.method, #drawRect, reason: reason);
      expect(first.bounds, Offset.zero & box.size, reason: reason);
      // Paint rengi kayan nokta (float32) saklar: 8 bitlik ARGB değeriyle karşılaştırılır.
      expect(first.color.toARGB32(), AppShowcaseColors.background.toARGB32(), reason: reason);
    }

    /// Kap kendi dikdörtgenini kaplayan bir boya yapıyor mu?
    bool fillsZemin(WidgetTester t) {
      final box = t.renderObject<RenderBox>(zemin);
      return paintedShapes(box).any((s) => rectCovers(s.bounds, Offset.zero & box.size));
    }

    testWidgets('içerik ekrana sığarken (az kart, büyük ekran) acil duyuru şeridi görünür ve üstü örtülmez', (t) async {
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access, width: 1280, height: 1600, notifier: _urgentNotifier());
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(banner, findsOneWidget);
      expect(find.text('Okunmamış acil duyuru: Gaz kaçağı'), findsOneWidget);
      // Hatanın koşulu: içerik kaydırma alanına sığıyor (kaydırma yok), kaydırma görünümü kırpmıyor.
      expect(t.state<ScrollableState>(_bodyScrollable()).position.maxScrollExtent, 0);

      // Geometri: kap şeridin ve uygulama çubuğunun ALTINDAN başlar; ekranın iki kenarına ve altına uzanır.
      final bannerRect = t.getRect(banner);
      final zeminRect = t.getRect(zemin);
      expect(zeminRect.top, greaterThanOrEqualTo(bannerRect.bottom), reason: 'kap şeridin bölgesine girmez');
      expect(zeminRect.top, greaterThanOrEqualTo(t.getRect(find.byType(AppBar)).bottom), reason: 'uygulama çubuğu etkilenmez');
      expect(zeminRect.left, 0);
      expect(zeminRect.right, 1280);
      // İP-1D: sakinde alt çubuk vardır; kap onun üstüne kadar uzanır (çubuk yoksa ekranın altına).
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget, reason: 'sakin alt çubuğu');
      expect(zeminRect.bottom, t.getRect(bar).top);
      expect(t.getRect(bar).bottom, 1600);

      // Gerçek boya: kap kendi dikdörtgenini düz #F8FAFC boyar; gövdenin (vitrin dahil) hiçbir boyası kabın dışına, yani
      // şeridin bölgesine düşmez. Vitrin de kendi sınırının dışına boyamaz.
      expectFlatFill(t, reason: 'Panel açık tema');
      expect(paintedOutside(t.renderObject<RenderBox>(zemin)), isEmpty, reason: 'gövdenin boyası şeride taşmaz');
      expect(
        paintedOutside(t.renderObject<RenderBox>(find.byType(ModuleShowcaseView))),
        isEmpty,
        reason: 'vitrin (kökünden) sınırı dışına boya yok',
      );

      // İsabet: şeridin ortası şeridi bulur; gövdenin kabı orada değildir.
      final targets = <Object>[for (final entry in t.hitTestOnBinding(bannerRect.center).path) entry.target];
      expect(targets, contains(t.renderObject(banner)));
      expect(targets, isNot(contains(t.renderObject(zemin))));

      // Kartlar beyaz + ince #E2E8F0 çerçeve (düz zeminde seçilir; kontrast oranı vitrin testinde).
      final card = t.widget<Material>(_card(SirketMenuItem.duyurular));
      expect(card.color, AppShowcaseColors.card);
      expect((card.shape! as RoundedRectangleBorder).side.color, AppShowcaseColors.cardBorder);
      await _disposeHome(t);
    });

    testWidgets(
        'kap görünen gövdenin tamamını kaplar: kenar boşlukları ve alttaki sistem gezinme çubuğu payı dahil; kaydırılan '
        'içerik payın üstünde kalır (yerleşim değişmedi)', (t) async {
      t.view.padding = const FakeViewPadding(bottom: 34);
      t.view.viewPadding = const FakeViewPadding(bottom: 34);
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      await _pumpHome(t, auth, access: access, width: 360, height: 740);
      expect(banner, findsNothing);
      final zeminRect = t.getRect(zemin);
      expect(zeminRect.top, t.getRect(find.byType(AppBar)).bottom, reason: 'şerit yokken uygulama çubuğunun hemen altı');
      expect(zeminRect.left, 0);
      expect(zeminRect.right, 360);
      // İP-1D: sakin alt çubuğu sistem gezinme çubuğu payını kendi içinde (SafeArea) karşılar; kap ve kaydırma alanı
      // çubuğun ÜSTÜNDE biter, çubuk ekranın altına kadar uzanır (pay çubukta, içerik payın üstünde).
      final bar = t.getRect(find.byType(NavigationBar));
      expect(bar.bottom, 740, reason: 'çubuk sistem çubuğu payının altına kadar');
      expect(zeminRect.bottom, bar.top, reason: 'kap çubuğun üstüne kadar');
      expect(t.getRect(_bodyScrollable()).bottom, bar.top);
      expect(t.getRect(vitrin).left, 16);
      expect(t.getRect(vitrin).right, 360 - 16);
      expectFlatFill(t, reason: 'sistem çubuğu payı');
      await _disposeHome(t);
    });

    testWidgets(
        'Geçiş Kontrol kapalı bireysel: vitrinin altındaki ana ekran da düz zeminde; aşağı kaydırınca zemin gradyana '
        'dönmez (kap kaydırılmaz)', (t) async {
      final auth = _ShowcaseAuth(UserRole.individual);
      final access = await _access(() => <MySiteModules>[_my('resident', doorOpen: false)]);
      await _pumpHome(t, auth, access: access, width: 360, height: 640);
      final home = find.byType(IndividualHomeView);
      expect(home, findsOneWidget, reason: 'ana ekran vitrinin altında');
      expect(find.descendant(of: zemin, matching: home), findsOneWidget, reason: 'ana ekran da kabın içinde');
      final position = t.state<ScrollableState>(_bodyScrollable()).position;
      final viewport = t.getRect(_bodyScrollable());
      // Ön koşul (eski hatanın koşulu): ana ekranın sonu vitrinin bir ekran boyundan da aşağıda.
      expect(t.getRect(home).bottom, greaterThan(t.getRect(vitrin).bottom + 640));
      final before = t.getRect(zemin);
      position.jumpTo(position.maxScrollExtent);
      await t.pump();
      expect(t.getRect(zemin), before, reason: 'kap kaydırılmaz');
      final visibleHome = t.getRect(home).intersect(viewport);
      expect(visibleHome.height, greaterThan(0), reason: 'ana ekranın sonu görünür');
      expect(rectCovers(before, visibleHome), isTrue, reason: 'görünen ana ekranın tamamı düz zeminin üstünde');
      expectFlatFill(t, reason: 'kaydırılmış bireysel ana ekran');
      expect(paintedOutside(t.renderObject<RenderBox>(zemin)), isEmpty, reason: 'kaydırılmışken de taşma yok');
      await _disposeHome(t);
    });

    testWidgets('koyu temada ve öteki sayfalarda kap boyanmaz; tema / sayfa değişince gövde alt ağacı yeniden kurulmaz',
        (t) async {
      final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
      addTearDown(mode.dispose);
      final auth = _ShowcaseAuth(UserRole.apartmentOwner);
      final access = await _access(() => <MySiteModules>[_my('resident')]);
      final notifier = _quietNotifier();
      addTearDown(notifier.dispose);
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (context, value, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: value,
            home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      Color? color() => (t.widget<DecoratedBox>(zemin).decoration as BoxDecoration).color;

      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(color(), AppShowcaseColors.background);
      expectFlatFill(t, reason: 'açık tema');
      final zeminElement = t.element(zemin);
      final scroll = t.state<ScrollableState>(_bodyScrollable());

      mode.value = ThemeMode.dark;
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(color(), isNull, reason: 'koyu temada boyama yok');
      expect(fillsZemin(t), isFalse, reason: 'koyu temada kap boyamaz (koyu zemin olduğu gibi)');
      expect(identical(t.element(zemin), zeminElement), isTrue, reason: 'kap yeniden kurulmadı');
      expect(identical(t.state<ScrollableState>(_bodyScrollable()), scroll), isTrue, reason: 'kaydırma görünümü korunur');

      mode.value = ThemeMode.light;
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(color(), AppShowcaseColors.background);

      // Öteki sayfa (Profilim): kap boyanmaz, uygulama zemini görünür; Panel'e dönünce yine düz.
      final profil = find.byKey(const ValueKey<String>('panel_ikincil_profilim'));
      await t.ensureVisible(profil);
      await t.tap(profil);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModuleShowcaseView), findsNothing);
      expect(color(), isNull, reason: 'Panel dışında kap boyanmaz');
      expect(fillsZemin(t), isFalse);
      expect(identical(t.state<ScrollableState>(_bodyScrollable()), scroll), isTrue, reason: 'sayfa değişince de korunur');
      expect(await _back(t), isTrue);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expectFlatFill(t, reason: 'Panel’e dönüş');
      await _disposeHome(t);
    });
  });

  // tasarim-12: aynı bekleyen sayı çekmecede ve Panel kartında aynı renkte (aynı belirteç).
  testWidgets('rozet rengi: vitrin kart rozetinin noktası çekmece rozetinin dolgusuyla aynı belirteç (AppTone.danger.a)',
      (t) async {
    final auth = _ShowcaseAuth(UserRole.superUser);
    final access = await _access(() => const <MySiteModules>[], superUser: true, pendingModules: 3);
    await _pumpHome(t, auth, access: access);
    Color? colorOf(Finder f) => (t.widget<DecoratedBox>(f).decoration as BoxDecoration).color;
    final cardBadge = find.descendant(
      of: _card(SirketMenuItem.modulTalepleri),
      matching: find.byKey(const ValueKey<String>('panel_kart_rozet')),
    );
    expect(find.descendant(of: cardBadge, matching: find.text('3')), findsOneWidget);
    final cardColor = colorOf(find.descendant(of: cardBadge, matching: find.byKey(const ValueKey<String>('panel_durum_noktasi'))));

    // İP-1D: Modül Talepleri sağ üstteki dişliden açılan Ayarlar panelindedir (aynı öğe bileşeni ve rozet).
    await openSettingsPanel(t);
    final drawerBadge = find.descendant(
      of: find.widgetWithText(ListTile, YanMenu.titleFor(SirketMenuItem.modulTalepleri, UserRole.superUser)),
      matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
    );
    expect(find.descendant(of: drawerBadge, matching: find.text('3')), findsOneWidget);
    expect(cardColor, colorOf(drawerBadge), reason: 'aynı sayı Ayarlar panelinde ve Panel kartında aynı renk');
    expect(cardColor, AppTone.danger.a);
    await closeMenuPanels(t);
    await _disposeHome(t);
  });

  group('taşma yok: dar ekran + yazı ölçeği 2,0 ve geniş ekran', () {
    // Borç bilgisi BAŞARIYLA dönen sakin (test-13): hero borç kartı (vadesi geçen + sıradaki vade satırlarıyla) çizilir.
    Future<MyFinance> debt() async => MyFinance(
          items: [
            MyFinanceApartment(
              siteCode: 1,
              siteName: 'Güneş Sitesi',
              apartmentId: 5,
              label: 'D:3',
              blockName: 'A Blok',
              balanceMinor: 32500000,
              overdueMinor: 100000,
              nextDueDate: DateTime(2026, 11, 10),
            ),
          ],
        );
    List<MySiteModules> residentSites() => <MySiteModules>[
          _my('resident', modules: {'announcements': true, 'finance': true, 'drive_storage': true, 'work_tracking': true}),
        ];
    // (etiket, rol, my-modules, süper mi, borç özeti: null = ağ hatası, hero selamlamadır)
    final roles = <(String, UserRole, List<MySiteModules> Function(), bool, Future<MyFinance> Function()?)>[
      (
        'süper kullanıcı',
        UserRole.superUser,
        () => const <MySiteModules>[],
        true,
        null,
      ),
      (
        'site yöneticisi',
        UserRole.siteManager,
        () => <MySiteModules>[
          _my('manager', modules: {'announcements': true, 'finance': true, 'work_tracking': true, 'drive_storage': true}),
        ],
        false,
        null,
      ),
      ('daire sakini', UserRole.apartmentOwner, residentSites, false, null),
      ('daire sakini (borç kartı)', UserRole.apartmentOwner, residentSites, false, debt),
      (
        'bireysel',
        UserRole.individual,
        () => const <MySiteModules>[],
        false,
        null,
      ),
    ];
    const cells = <(double, double, double, bool)>[
      // test-13: 320 dp telefonda normal ve biraz büyük yazı da GERÇEK sayfada (vitrin 288 dp, iki sütun) sınanır.
      (320, 640, 1.0, false),
      (320, 640, 1.15, true),
      (320, 640, 2.0, false),
      (320, 640, 2.0, true),
      (360, 740, 1.5, false),
      (1366, 768, 1.0, false),
      (1366, 768, 1.0, true),
    ];

    for (final (label, role, sites, isSuper, finance) in roles) {
      for (final (w, h, scale, dark) in cells) {
        testWidgets('$label: ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}', (t) async {
          final auth = _ShowcaseAuth(role, finance: finance ?? () async => throw StateError('ağ'));
          final access = await _access(sites, superUser: isSuper, pendingModules: 12, pendingApplications: 3);
          await _pumpHome(t, auth, access: access, width: w, height: h, scale: scale, dark: dark);
          final showcase = find.byType(ModuleShowcaseView);
          expect(showcase, findsOneWidget);
          expect(t.takeException(), isNull, reason: 'RenderFlex taşması yok');
          if (finance != null) {
            expect(find.byKey(const ValueKey<String>('panel_hero_borc')), findsOneWidget, reason: 'borç kartı çizildi');
          }
          // Gerçek sayfa genişliği (16 / 20 dp kenar boşluğu, en çok 1100 dp) ve bu genişlikteki sütun kuralı: 320 dp'de
          // vitrin 288 dp, yazı 1,0 / 1,15 iki sütun, daha büyük yazı tek sütun.
          final width = t.getSize(find.byKey(const ValueKey<String>('panel_vitrin'))).width;
          expect(width, math.min(w - 2 * (w < 600 ? 16 : 20), 1100.0), reason: 'vitrin genişliği');
          final grid = buildShowcaseModel(menuItems: t.widget<ModuleShowcaseView>(showcase).menuItems, role: role).grid;
          if (grid.length >= 2) {
            final a = t.getTopLeft(_card(grid[0].item)).dy;
            final b = t.getTopLeft(_card(grid[1].item)).dy;
            if (showcaseColumns(width, scale) >= 2) {
              expect(b, a, reason: 'ilk iki kart aynı satırda');
            } else {
              expect(b, greaterThan(a), reason: 'tek sütun');
            }
          }
          if (w == 320 && scale <= 1.15) expect(showcaseColumns(width, scale), 2, reason: '320 dp normal yazı: iki sütun');
          // Sayfanın tamamı kaydırılarak gezilir: alt uçta da taşma/hata yok.
          final scroll = find.byType(SingleChildScrollView).first;
          await t.drag(scroll, const Offset(0, -3000));
          await t.pump();
          expect(t.takeException(), isNull);
          await _disposeHome(t);
        });
      }
    }

    testWidgets('daire sakini, "Ziyaretçi kodu" dahil tüm hızlı işlemler: 320x640 x2,0 taşma yok', (t) async {
      _fakeVisitorServer();
      final auth = _ShowcaseAuth(UserRole.apartmentOwner, finance: () async => throw StateError('ağ'));
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', modules: {'work_tracking': true, 'visitor_log': true, 'drive_storage': true}),
        ],
      );
      await _pumpHome(t, auth, access: access, width: 320, height: 640, scale: 2.0);
      expect(_guestPassQuick, findsOneWidget);
      expect(t.takeException(), isNull);
      await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await t.pump();
      expect(t.takeException(), isNull);
      await _disposeHome(t);
    });
  });

  // test-12: yoklama testi ön koşullu; Kapılar'da 3 sn ritmi tek seferlik okumadan ayrılır; vitrine dönünce durur.
  group('kapı panelinin yoklaması yalnız Kapılar sayfasında', () {
    testWidgets('vitrindeyken durum yoklaması yok; Kapılar\'da 3 sn ritmiyle sürer; vitrine dönünce DURUR', (t) async {
      final calls = <int>[];
      final auth = _CountingAuth(UserRole.siteManager, calls);
      final access = await _access(() => <MySiteModules>[_my('manager')]);
      await _pumpHome(t, auth, access: access);
      // Ön koşul: kapı seçildi ve ilk durum bir kez okundu (seçili kapı yoksa yoklama zaten hiç çalışmaz).
      final afterLoad = calls.length;
      expect(afterLoad, greaterThanOrEqualTo(1), reason: 'kapı seçildi, ilk durum okundu');
      await t.pump(const Duration(seconds: 7));
      expect(calls.length, afterLoad, reason: 'vitrin görünürken kapı durumu yoklanmaz');

      await _tapCard(t, SirketMenuItem.kapilar);
      // Girişteki tek seferlik okuma bu noktaya kadardır; bundan sonrası yalnız yoklamadır.
      await t.pump(const Duration(milliseconds: 100));
      final atDoors = calls.length;
      await t.pump(const Duration(seconds: 7));
      expect(calls.length - atDoors, greaterThanOrEqualTo(2), reason: 'Kapılar sayfasında 3 sn ritmiyle yoklanır');

      // Geri tuşuyla vitrine dönünce yoklama durur.
      expect(await _back(t), isTrue);
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      final back = calls.length;
      await t.pump(const Duration(seconds: 10));
      expect(calls.length, back, reason: 'vitrine dönünce yoklama durur');
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
