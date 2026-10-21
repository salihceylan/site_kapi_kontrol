// Sade daire sakini ekranı: yalnız kapılar ve yuvarlak "aç" düğmesi; kalan komutlar çekmecede.
//
// Üç düzey: (1) ResidentDoorRemoteCard(minimal: true) içeriği + taşma matrisi, (2) YanMenu.extraActions,
// (3) gerçek HomePage: daire sakini çekmecesinde yetkiye/cihaza göre QR, ekran QR, misafir ve sesli
// komut öğeleri. Varsayılan (minimal: false) kart davranışı `resident_door_remote_card_layout_test`
// ile korunur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_actions.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_remote_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_live_banner.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';
import 'g2_support.dart';

Widget _card({
  DoorRecord? door,
  bool noDoor = false,
  DoorRuntimeStatus? status,
  List<DoorRecord>? doors,
  G2FakeVoice? voice,
  VoidCallback? onOpenDoor,
  ValueChanged<int>? onSelectDoor,
  bool opening = false,
}) {
  final selected = noDoor ? null : (door ?? g2Door(qrReader: true));
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: ResidentDoorRemoteCard(
        minimal: true,
        selectedSite: null,
        selectedDoor: selected,
        doors: doors ?? (selected == null ? <DoorRecord>[] : [selected]),
        runtimeStatus: noDoor ? null : (status ?? g2Runtime()),
        isLoadingStatus: false,
        isOpeningDoor: opening,
        onSelectDoor: onSelectDoor ?? (_) {},
        onOpenDoor: onOpenDoor ?? () {},
        onCreateGuestPass: () {},
        voiceDoorService: voice,
        roleColor: Colors.purple,
      ),
    ),
  );
}

/// Sade kartta bulunmaması gereken, eski kartın açıklama/rozet metinleri.
const List<String> _removedTexts = <String>[
  'SmartKeyPass AKILLI GEÇİŞ',
  'SmartKeyPass YEREL AĞ GEÇİŞ',
  '🟢 Çevrimiçi - Kapıyı açmak için dokunun',
  '🔴 Cihaz Çevrimdışı',
  'Yerel IP: 192.168.100.200',
  'Genel IP: 85.105.20.34',
  '📲 Kapıya QR Göster',
  '📷 Kapı Ekranından QR Oku',
  '📦 Kurye / Misafir Geçiş Linki Oluştur',
];

void main() {
  group('ResidentDoorRemoteCard(minimal): yalnız kapı + yuvarlak düğme', () {
    testWidgets('tek kapı: kapı adı + düğme; açıklama/rozet/IP/banner/eylem düğmesi yok', (
      t,
    ) async {
      await pumpAt(
        t,
        _card(voice: G2FakeVoice()),
        width: 360,
        scale: 1.0,
      );
      expect(find.byType(DoorOpenButton), findsOneWidget);
      expect(find.text('A Blok Ana Giriş Kapısı'), findsOneWidget);
      expect(find.text('KAPIYI AÇ'), findsOneWidget);
      for (final text in _removedTexts) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.byType(StatusChip), findsNothing);
      expect(find.byType(PrimaryActionButton), findsNothing);
      expect(find.byType(VoiceLiveBanner), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing, reason: 'tek kapı: çip yok');
      // Tek kart (hero), içinde yalnız başlık + düğme.
      expect(find.byType(AppCard), findsOneWidget);
    });

    testWidgets('düğme anahtarı, durumu ve dokunma davranışı eskisiyle aynı', (
      t,
    ) async {
      var opened = 0;
      await pumpAt(
        t,
        _card(onOpenDoor: () => opened++),
        width: 360,
        scale: 1.0,
      );
      final button = t.widget<DoorOpenButton>(find.byType(DoorOpenButton));
      expect(button.key, const ValueKey<String>('resident_door_open_button'));
      expect(button.state, DoorOpenState.ready);
      expect(button.variant, DoorOpenVariant.circle);
      await t.tap(find.text('KAPIYI AÇ'));
      await t.pump();
      expect(opened, 1);
    });

    testWidgets('çevrimdışı: düğme ÇEVRİMDIŞI; dokununca uyarı (açıklama yok)', (
      t,
    ) async {
      var opened = 0;
      await pumpAt(
        t,
        _card(status: g2Runtime(online: false), onOpenDoor: () => opened++),
        width: 360,
        scale: 1.0,
      );
      expect(find.text('ÇEVRİMDIŞI'), findsOneWidget);
      await t.tap(find.text('ÇEVRİMDIŞI'));
      await t.pump();
      expect(opened, 0);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('çevrimdışı'), findsWidgets);
    });

    testWidgets('birden çok kapı: yalnız kapı çipleri (ayrı başlık yok); seçim çalışır', (
      t,
    ) async {
      final doors = <DoorRecord>[
        g2Door(),
        g2Door(id: 8, name: 'Otopark Girişi'),
        g2Door(id: 9, name: 'Yaya Kapısı'),
      ];
      final picked = <int>[];
      await pumpAt(
        t,
        _card(doors: doors, onSelectDoor: picked.add),
        width: 360,
        scale: 1.0,
      );
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      await t.tap(find.text('Otopark Girişi'));
      await t.pump();
      expect(picked, <int>[8]);
    });

    testWidgets('kapı seçilmedi: kısa metin + devre dışı düğme', (t) async {
      await pumpAt(t, _card(noDoor: true), width: 360, scale: 1.0);
      expect(find.text('Kapı Seçilmedi'), findsOneWidget);
      expect(find.byType(DoorOpenButton), findsOneWidget);
      expect(find.text('KAPALI'), findsOneWidget, reason: 'cihaz yok: düğme KAPALI');
    });

    testWidgets('kapı açılıyor: düğme AÇILIYOR; durağanken ticker yok', (t) async {
      await t.pumpWidget(
        harnessApp(SingleChildScrollView(child: _card())),
      );
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      await pumpAt(t, _card(opening: true), width: 360, scale: 1.0);
      expect(find.text('AÇILIYOR'), findsOneWidget);
    });

    testWidgets('taşma matrisi: 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (t) async {
      final scenarios = <Widget Function()>[
        () => _card(),
        () => _card(
          doors: <DoorRecord>[
            g2Door(),
            g2Door(id: 8, name: 'Otopark Girişi ve Yaya Kapısı Çok Uzun Ad'),
            g2Door(id: 9, name: 'Daire Sakinleri Kapısı ve Yaya Girişi'),
          ],
        ),
        () => _card(status: g2Runtime(online: false)),
        () => _card(noDoor: true),
        () => _card(
          door: g2Door(
            name: 'Çok Uzun İsimli Ana Giriş Kapısı ve Otopark Bariyeri',
          ),
        ),
      ];
      await forEachHarnessCell((width, scale, dark) async {
        for (final build in scenarios) {
          await pumpAt(t, build(), width: width, scale: scale, dark: dark);
          expect(find.byType(DoorOpenButton), findsOneWidget);
        }
      });
    });
  });

  group('ResidentDoorActions: görünürlük kuralları (eski kartla aynı)', () {
    test('QR / ekran QR / misafir bayrakları kapı kaydından türetilir', () {
      expect(ResidentDoorActions.canShowQr(null), isFalse);
      expect(ResidentDoorActions.canScanScreenQr(null), isFalse);
      expect(ResidentDoorActions.canCreateGuestPass(null), isFalse);
      final full = g2Door(qrReader: true);
      expect(ResidentDoorActions.canShowQr(full), full.canOpenQr);
      expect(ResidentDoorActions.canScanScreenQr(full), full.hasDisplay);
      expect(ResidentDoorActions.canCreateGuestPass(full), full.canCreateGuestPass);
      final bare = g2Door(qr: false, guestPass: false);
      expect(ResidentDoorActions.canShowQr(bare), isFalse);
      expect(ResidentDoorActions.canCreateGuestPass(bare), isFalse);
    });
  });

  group('YanMenu.extraActions: "Panel"in altında ek komutlar', () {
    Future<void> openDrawer(WidgetTester t, YanMenu menu) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(drawer: menu, body: const SizedBox()),
        ),
      );
      t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    }

    YanMenu menu({List<YanMenuAction> extra = const <YanMenuAction>[]}) => YanMenu(
      fullName: 'Mehmet Demir',
      userEmail: 'mehmet@example.com',
      role: UserRole.apartmentOwner,
      selectedItem: SirketMenuItem.dashboard,
      onSelect: (_) {},
      onLogout: () {},
      extraActions: extra,
    );

    List<String> titles(WidgetTester t) => t
        .widgetList<ListTile>(find.byType(ListTile))
        .map((w) => (w.title! as Text).data!)
        .toList();

    testWidgets('varsayılan boş: menü eskisi gibi (İP-1D: Eller Serbest ve Profilim Ayarlar panelinde)', (t) async {
      await openDrawer(t, menu());
      expect(titles(t), <String>[
        'Panel',
        'Daireye Katıl & Cihaz Ekle',
        'Çıkış Yap',
      ]);
    });

    testWidgets('ek komutlar Panel\'den hemen sonra, sırayla gelir ve dokununca çalışır', (
      t,
    ) async {
      final calls = <String>[];
      await openDrawer(
        t,
        menu(
          extra: <YanMenuAction>[
            YanMenuAction(
              icon: Icons.qr_code_2_rounded,
              title: 'Kapıya QR Göster',
              onTap: () => calls.add('qr'),
            ),
            YanMenuAction(
              icon: Icons.share_rounded,
              title: 'Kurye / Misafir Geçiş Linki Oluştur',
              onTap: () => calls.add('guest'),
            ),
          ],
        ),
      );
      expect(titles(t).take(4).toList(), <String>[
        'Panel',
        'Kapıya QR Göster',
        'Kurye / Misafir Geçiş Linki Oluştur',
        'Daireye Katıl & Cihaz Ekle',
      ]);
      await t.tap(find.text('Kurye / Misafir Geçiş Linki Oluştur'));
      await t.pump();
      expect(calls, <String>['guest']);
    });

    testWidgets('"Kapılar" varsa ek komutlar onun, Panel\'in değil, hemen altına gelir', (t) async {
      await openDrawer(
        t,
        YanMenu(
          fullName: 'Mehmet Demir',
          userEmail: 'mehmet@example.com',
          role: UserRole.apartmentOwner,
          selectedItem: SirketMenuItem.dashboard,
          onSelect: (_) {},
          onLogout: () {},
          additionalItems: const <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.duyurular},
          extraActions: <YanMenuAction>[
            YanMenuAction(icon: Icons.qr_code_2_rounded, title: 'Kapıya QR Göster', onTap: () {}),
          ],
        ),
      );
      // İP-1D (G2): Kapılar "Site hizmetleri" başlığındadır; ek komutlar onun hemen altında.
      expect(titles(t), <String>[
        'Panel',
        'Daireye Katıl & Cihaz Ekle',
        'Duyurular',
        'Kapılar',
        'Kapıya QR Göster',
        'Çıkış Yap',
      ]);
      final doors = t.getRect(find.widgetWithText(ListTile, 'Kapılar'));
      expect(t.getRect(find.text('Site hizmetleri')).bottom, lessThanOrEqualTo(doors.top + 0.01));
    });

    testWidgets('320 x 2,0 ve 360 x 1,5 (açık+koyu): taşma yok', (t) async {
      for (final (w, scale) in [(320.0, 2.0), (360.0, 1.5)]) {
        for (final dark in [false, true]) {
          t.view.physicalSize = Size(w, 640);
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
              home: Scaffold(
                drawer: menu(
                  extra: <YanMenuAction>[
                    YanMenuAction(
                      icon: Icons.mic_rounded,
                      title: 'Sesli Kapı Açma',
                      onTap: () {},
                    ),
                    YanMenuAction(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'Kapı Ekranından QR Oku',
                      onTap: () {},
                    ),
                    YanMenuAction(
                      icon: Icons.share_rounded,
                      title: 'Kurye / Misafir Geçiş Linki Oluştur',
                      onTap: () {},
                    ),
                  ],
                ),
                body: const SizedBox(),
              ),
            ),
          );
          t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
          await t.pump();
          await t.pump(const Duration(milliseconds: 500));
          expect(t.takeException(), isNull, reason: '$w x $scale dark=$dark');
        }
      }
    });
  });

  group('HomePage: daire sakini çekmecesi (Panel = vitrin; sade kapı kumandası Kapılar kartının arkasında)', () {
    Future<void> pumpHome(WidgetTester t, _ResidentAuth auth) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: HomePage(authService: auth),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> open(WidgetTester t) async {
      t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    }

    Future<void> dispose(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }

    // Panel artık modül vitrinidir: sade kapı kumandası "Kapılar" kartının arkasındadır (bir dokunuş).
    testWidgets('Panel vitrindir (kapı düğmesi yok); Kapılar kartı SADE kumandayı açar: saat/açıklama/QR/misafir yok, düğme var', (
      t,
    ) async {
      await pumpHome(t, _ResidentAuth(g2Door(qrReader: true)));
      expect(find.byType(DoorOpenButton), findsNothing, reason: 'vitrinde kapı düğmesi yok');
      expect(find.byKey(const ValueKey<String>('panel_vitrin')), findsOneWidget);
      final card = find.byKey(const ValueKey<String>('panel_kart_kapilar'));
      await t.ensureVisible(card);
      await t.tap(card);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(DoorOpenButton), findsOneWidget);
      expect(find.text('KAPIYI AÇ'), findsOneWidget);
      for (final text in _removedTexts) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.byType(VoiceLiveBanner), findsNothing);
      await dispose(t);
    });

    testWidgets('yetkiler tam: çekmecede QR, ekran QR ve misafir öğeleri Kapılar\'ın altında', (
      t,
    ) async {
      await pumpHome(t, _ResidentAuth(g2Door(qrReader: true)));
      await open(t);
      final titles = t
          .widgetList<ListTile>(find.byType(ListTile))
          .map((w) => (w.title! as Text).data!)
          .toList();
      expect(titles.first, 'Panel');
      // İP-1D (G2): Kapılar "Site hizmetleri" başlığında; kapı komutları onun hemen altında.
      final doors = titles.indexOf('Kapılar');
      expect(doors, greaterThan(0));
      expect(titles.sublist(doors + 1, doors + 4), <String>[
        'Kapıya QR Göster',
        'Kapı Ekranından QR Oku',
        'Kurye / Misafir Geçiş Linki Oluştur',
      ]);
      expect(titles, isNot(contains('Profilim')), reason: 'Profilim sağ üstteki Ayarlar panelinde');
      await dispose(t);
    });

    testWidgets('yetkisiz kapı: ilgili çekmece öğeleri görünmez', (t) async {
      await pumpHome(
        t,
        // C3 kartta ekran yok (hasDisplay yalnız WROOM'da).
        _ResidentAuth(
          g2Door(qr: false, guestPass: false, qrReader: false, target: 'esp32-c3'),
        ),
      );
      await open(t);
      expect(find.text('Kapıya QR Göster'), findsNothing);
      expect(find.text('Kapı Ekranından QR Oku'), findsNothing);
      expect(find.text('Kurye / Misafir Geçiş Linki Oluştur'), findsNothing);
      await dispose(t);
    });

    testWidgets('misafir öğesi: çekmece kapanır ve geçiş diyaloğu açılır', (t) async {
      await pumpHome(t, _ResidentAuth(g2Door(qrReader: true)));
      await open(t);
      await t.tap(find.text('Kurye / Misafir Geçiş Linki Oluştur'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(Drawer), findsNothing, reason: 'çekmece kapandı');
      expect(find.byType(AlertDialog), findsOneWidget);
      await dispose(t);
    });
  });
}

/// HomePage için sahte kimlik servisi: tek kapılı daire sakini.
class _ResidentAuth extends AuthService {
  _ResidentAuth(this.door) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final DoorRecord door;

  @override
  UserSession? get session => UserSession(
    id: 5,
    fullName: 'Mehmet Demir',
    email: 'mehmet@example.com',
    loginName: null,
    role: UserRole.apartmentOwner,
    isActive: true,
    token: 'tok',
  );

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  String? takeSessionNotice() => null;

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async => SitePage(sites: const [], total: 0, page: 1, pageSize: 100);

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async =>
      (<DoorRecord>[door], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({
    required int doorId,
  }) async => (g2Runtime(), null);

  @override
  Future<(DoorRuntimeStatus?, String?)> openDoor({
    required int doorId,
    DoorRecord? door,
  }) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}

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
