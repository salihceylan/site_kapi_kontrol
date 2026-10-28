// KOLAY GÖRÜNÜM (P2-25): sadeleşmiş ana ekran (büyük düğmeler) ve Ayarlar panelindeki anahtar.
//
// Sözleşmeler:
// - Kolay görünüm KAPALIyken (varsayılan) Panel eskisi gibidir; açıkken Panel vitrini tek sütun büyük düğmelerdir (en az 72 dp,
//   tam genişlik, açıklama yok, hızlı işlemler yok); görünürlük kuralı AYNIDIR (yalnız menü listesindeki modüller).
// - Dokunmak çekmecede o öğeyi seçmekle aynı gezinmedir; rozet ve ekran okuyucu etiketi (başlık + sayı + sözcük) korunur.
// - Anahtar Ayarlar panelinin en üstündedir, paneli kapatmaz, tercihi saklar; kapsam yoksa panel eskisi gibidir.
// - AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema, yüksek karşıtlık temasıyla taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
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
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/easy_view_service.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/styles/easy_view_theme.dart';
import 'package:site_kapi_kontrol/ui/design/easy_view_switch.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/showcase_layouts.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../support/menu_nav.dart';
import 'list_fixtures.dart' show listMatrix;

// ---------------------------------------------------------------------------
// Ortak düzenek
// ---------------------------------------------------------------------------

UserSession _session(UserRole role) => UserSession(
  id: 7,
  fullName: 'Ayşe Yılmaz',
  email: 'a@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 't',
);

final Set<SirketMenuItem> _managerExtras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
  SirketMenuItem.rezervasyonlar,
  SirketMenuItem.anketler,
};

final Set<SirketMenuItem> _residentExtras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.borcum,
  SirketMenuItem.belgeler,
  SirketMenuItem.taleplerim,
  SirketMenuItem.ziyaretcilerim,
};

List<SirketMenuItem> _menu(UserRole role, Set<SirketMenuItem> extras, {bool resident = false}) => YanMenu.visibleItems(
  role: role,
  isResidentMode: resident,
  canToggleMode: false,
  additionalItems: extras,
  hiddenItems: const <SirketMenuItem>{},
);

Widget _page(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: SizedBox(width: double.infinity, child: child),
);

/// Uygulama kökünün kolay görünüm bağlantısının aynısı (lib/app.dart): kapsamlar + tema + en az 1,3 yazı ölçeği. Gerçek
/// bağ `easy_view_theme_test.dart` içinde MyApp ile sınanır.
Widget _app(
  EasyViewService easy,
  Widget home, {
  ViewModeService? modes,
  bool dark = false,
  double systemScale = 1.0,
}) {
  return EasyViewScope(
    service: easy,
    child: ViewModeScope(
      service: modes ?? ViewModeService(),
      child: AnimatedBuilder(
        animation: easy,
        builder: (context, _) => MaterialApp(
          theme: easy.enabled ? easyViewLightTheme : AppTheme.light(),
          darkTheme: easy.enabled ? easyViewDarkTheme : AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(systemScale)),
            child: MediaQuery.withClampedTextScaling(
              minScaleFactor: easy.enabled ? EasyViewService.minTextScale : 0.0,
              maxScaleFactor: 2.0,
              child: child!,
            ),
          ),
          home: Scaffold(body: SingleChildScrollView(child: home)),
        ),
      ),
    ),
  );
}

Future<EasyViewService> _easyOn() async {
  final easy = EasyViewService();
  await easy.setEnabled(true);
  return easy;
}

Widget _showcase({
  required UserRole role,
  required ShowcaseAudience audience,
  required Set<SirketMenuItem> extras,
  bool residentMode = false,
  ValueChanged<SirketMenuItem>? onOpen,
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  Map<SirketMenuItem, String> nouns = const <SirketMenuItem, String>{},
  VoidCallback? onHelp,
  VoidCallback? onGuestPass,
}) => _page(
  ModuleShowcaseView(
    session: _session(role),
    audience: audience,
    menuItems: _menu(role, extras, resident: residentMode),
    badgeCounts: badges,
    badgeNouns: nouns,
    onOpen: onOpen ?? (_) {},
    onOpenHelp: onHelp,
    onCreateGuestPass: onGuestPass,
  ),
);

Finder _easyButton(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_kolay_${item.name}'));

Future<void> _pumpApp(
  WidgetTester t,
  Widget app, {
  double width = 400,
  double height = 1800,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await t.pump(const Duration(milliseconds: 450));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('sadeleşmiş ana ekran: büyük düğmeler (ModuleShowcaseView)', () {
    testWidgets('KAPALI (varsayılan): Panel eskisi gibi kutucuk ızgarası + ikincil satır; büyük düğme yok', (t) async {
      final easy = EasyViewService();
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(
            role: UserRole.siteManager,
            audience: ShowcaseAudience.admin,
            extras: _managerExtras,
            onHelp: () {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsNothing);
      expect(find.byType(ShowcaseEasyButton), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_ikincil')), findsOneWidget);
    });

    testWidgets('AÇIK (yönetici): her modül tek sütunda büyük düğme; ızgara, ikincil çipler ve hızlı işlemler yok', (t) async {
      final easy = await _easyOn();
      final opened = <SirketMenuItem>[];
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(
            role: UserRole.siteManager,
            audience: ShowcaseAudience.admin,
            extras: _managerExtras,
            onOpen: opened.add,
            onHelp: () {},
          ),
        ),
      );

      final model = buildShowcaseModel(
        menuItems: _menu(UserRole.siteManager, _managerExtras),
        role: UserRole.siteManager,
      );
      expect(model.grid, isNotEmpty);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_ikincil')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_izgara')), findsNothing);
      expect(find.byType(ShowcaseModuleRow), findsNothing);
      // Liste ↔ kutucuk anahtarı kolay görünümde yoktur (ana ekran zaten büyük düğmeler).
      expect(find.byKey(const ValueKey<String>('gorunum_anahtari_modules')), findsNothing);

      final content = t.getSize(find.byKey(const ValueKey<String>('panel_vitrin_kolay'))).width;
      for (final e in model.grid) {
        final button = _easyButton(e.item);
        expect(button, findsOneWidget, reason: '${e.item} düğmesi');
        final size = t.getSize(button);
        expect(size.height, greaterThanOrEqualTo(ShowcaseEasyButton.minHeight), reason: '${e.item} en az 72 dp');
        expect(size.width, closeTo(content, 0.01), reason: '${e.item} tam genişlik (tek sütun)');
        expect(find.descendant(of: button, matching: find.text(e.title)), findsOneWidget);
        expect(find.descendant(of: button, matching: find.text(e.description)), findsNothing, reason: 'açıklama yok (sade)');
        expect(find.descendant(of: button, matching: find.byType(ModuleArt)), findsOneWidget);
      }
      // Düğmeler alt alta: her biri bir öncekinin altında.
      var previousBottom = double.negativeInfinity;
      for (final e in model.grid) {
        final rect = t.getRect(_easyButton(e.item));
        expect(rect.top, greaterThanOrEqualTo(previousBottom), reason: '${e.item} alt alta');
        previousBottom = rect.bottom;
      }

      await t.tap(_easyButton(SirketMenuItem.duyurular));
      await t.pump();
      expect(opened, <SirketMenuItem>[SirketMenuItem.duyurular]);
      expect(t.takeException(), isNull);
    });

    testWidgets('AÇIK: hesap / ayar öğeleri ve Yardım da büyük düğme ("Hesap ve ayarlar" başlığı altında)', (t) async {
      final easy = await _easyOn();
      final opened = <SirketMenuItem>[];
      var helpTaps = 0;
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(
            role: UserRole.siteManager,
            audience: ShowcaseAudience.admin,
            extras: _managerExtras,
            onOpen: opened.add,
            onHelp: () => helpTaps++,
          ),
        ),
      );
      expect(find.text('Hesap ve ayarlar'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay_ikincil')), findsOneWidget);
      final profile = _easyButton(SirketMenuItem.profilim);
      expect(profile, findsOneWidget);
      expect(t.getSize(profile).height, greaterThanOrEqualTo(ShowcaseEasyButton.minHeight));
      expect(find.descendant(of: profile, matching: find.byType(ModuleArt)), findsNothing, reason: 'ayar öğesi simgeli');

      await t.tap(profile);
      await t.pump();
      expect(opened, <SirketMenuItem>[SirketMenuItem.profilim]);

      final help = find.byKey(const ValueKey<String>('panel_kolay_yardim'));
      expect(help, findsOneWidget);
      await t.tap(help);
      await t.pump();
      expect(helpTaps, 1);
    });

    testWidgets('rozet: sayı + sözcük büyük düğmede yazılır; ekran okuyucu etiketi başlık + sayı + sözcüktür', (t) async {
      final handle = t.ensureSemantics();
      final easy = await _easyOn();
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(
            role: UserRole.siteManager,
            audience: ShowcaseAudience.admin,
            extras: _managerExtras,
            badges: <SirketMenuItem, int>{SirketMenuItem.duyurular: 3, SirketMenuItem.talepler: 120},
            nouns: <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
          ),
        ),
      );
      expect(find.descendant(of: _easyButton(SirketMenuItem.duyurular), matching: find.text('3 okunmamış')), findsOneWidget);
      expect(find.descendant(of: _easyButton(SirketMenuItem.talepler), matching: find.text('99+ bekleyen')), findsOneWidget);
      expect(find.descendant(of: _easyButton(SirketMenuItem.finans), matching: find.byKey(const ValueKey<String>('panel_kolay_rozet'))), findsNothing);
      expect(find.bySemanticsLabel('Duyurular, 3 okunmamış'), findsOneWidget);
      // Her büyük düğme tek erişilebilir düğümdür (etiket = başlık); açıklama ipucu olarak okunur.
      expect(find.bySemanticsLabel('Finans'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('sakin: selamlama / borç kartı KALIR, hızlı işlemler kalkar, "Ziyaretçi kodu" Kapılar düğmesinin altındadır', (t) async {
      final easy = await _easyOn();
      var guestPass = 0;
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(
            role: UserRole.apartmentOwner,
            audience: ShowcaseAudience.resident,
            extras: _residentExtras,
            onGuestPass: () => guestPass++,
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsOneWidget, reason: 'hero kalır');
      expect(find.text('Hızlı işlemler'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_izgara')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_kapilar')), findsNothing);

      final guest = find.byKey(const ValueKey<String>('panel_kolay_ziyaretciKodu'));
      expect(guest, findsOneWidget);
      expect(t.getRect(guest).top, greaterThanOrEqualTo(t.getRect(_easyButton(SirketMenuItem.kapilar)).bottom));
      expect(t.getRect(guest).bottom, lessThanOrEqualTo(t.getRect(_easyButton(SirketMenuItem.duyurular)).top));
      await t.tap(guest);
      await t.pump();
      expect(guestPass, 1);

      for (final item in <SirketMenuItem>[
        SirketMenuItem.kapilar,
        SirketMenuItem.duyurular,
        SirketMenuItem.borcum,
        SirketMenuItem.belgeler,
        SirketMenuItem.taleplerim,
        SirketMenuItem.ziyaretcilerim,
      ]) {
        expect(_easyButton(item), findsOneWidget, reason: '$item düğmesi');
      }
      for (final hidden in <SirketMenuItem>[SirketMenuItem.finans, SirketMenuItem.kisiler, SirketMenuItem.siteler]) {
        expect(_easyButton(hidden), findsNothing, reason: '$hidden sakine görünmez (menü listesinde yok)');
      }
    });

    testWidgets('sakin: ziyaretçi kodu eylemi verilmediyse düğmesi de yok (koşul aynı)', (t) async {
      final easy = await _easyOn();
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, extras: _residentExtras),
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_kolay_ziyaretciKodu')), findsNothing);
    });

    testWidgets('açıkken yazı en az 1,3x; düğme yüksekliği yazıyla büyür; kalın çerçeve palet kenarıdır', (t) async {
      final easy = await _easyOn();
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin, extras: _managerExtras),
        ),
      );
      final element = t.element(_easyButton(SirketMenuItem.duyurular));
      expect(MediaQuery.textScalerOf(element).scale(10), closeTo(13, 1e-9));
      expect(Theme.of(element).extension<AppPalette>(), same(kEasyLightPalette));
      final material = t.widget<Material>(
        find.descendant(of: _easyButton(SirketMenuItem.duyurular), matching: find.byType(Material)).first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side.width, 2);
      expect(shape.side.color, kEasyLightPalette.border);
      expect(material.color, kEasyLightPalette.surface);
    });

    testWidgets('anahtar kapanınca Panel eski görünümüne döner (ızgara geri gelir)', (t) async {
      final easy = await _easyOn();
      await _pumpApp(
        t,
        _app(
          easy,
          _showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin, extras: _managerExtras),
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsOneWidget);

      await easy.setEnabled(false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsOneWidget);
    });

    for (final audience in <(String, UserRole, ShowcaseAudience, Set<SirketMenuItem>)>[
      ('yönetici', UserRole.siteManager, ShowcaseAudience.admin, _managerExtras),
      ('sakin', UserRole.apartmentOwner, ShowcaseAudience.resident, _residentExtras),
    ]) {
      listMatrix('${audience.$1}: büyük düğmeler, rozetli', (t, w, h, s, dark) async {
        final easy = await _easyOn();
        await _pumpApp(
          t,
          _app(
            easy,
            _showcase(
              role: audience.$2,
              audience: audience.$3,
              extras: audience.$4,
              badges: <SirketMenuItem, int>{SirketMenuItem.duyurular: 12, SirketMenuItem.belgeler: 100},
              nouns: <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
              onHelp: () {},
              onGuestPass: audience.$3 == ShowcaseAudience.resident ? () {} : null,
            ),
            dark: dark,
            // Cihaz yazı ölçeği matrisin ölçeği; kolay görünüm en az 1,3 uygular.
            systemScale: s,
          ),
          width: w,
          height: h,
        );
        expect(find.byType(ShowcaseEasyButton), findsWidgets);
        expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsOneWidget);
      });
    }
  });

  group('Ayarlar panelindeki "Kolay görünüm" anahtarı', () {
    Widget settings(EasyViewService? easy, {double systemScale = 1.0}) {
      final key = GlobalKey<ScaffoldState>(debugLabel: 'ayarlar');
      final panel = YanMenuAyarlar(
        role: UserRole.siteManager,
        selectedItem: SirketMenuItem.dashboard,
        onSelect: (_) {},
      );
      final scaffold = Scaffold(key: key, endDrawer: panel, body: const SizedBox.expand());
      return easy == null
          ? MaterialApp(theme: AppTheme.light(), home: scaffold)
          : EasyViewScope(
              service: easy,
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(systemScale)),
                  child: child!,
                ),
                home: scaffold,
              ),
            );
    }

    Future<void> openPanel(WidgetTester t) async {
      t.state<ScaffoldState>(find.byType(Scaffold).first).openEndDrawer();
      await t.pump();
      await t.pump(const Duration(milliseconds: 450));
    }

    testWidgets('kapsam yok: panel eskisi gibi, anahtar hiç görünmez', (t) async {
      await _pumpApp(t, settings(null));
      await openPanel(t);
      expect(find.byType(YanMenuAyarlar), findsOneWidget);
      expect(find.text('Kolay görünüm'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('kapsam var: anahtar panelin en üstünde; kapalı başlar; dokununca açılır, saklanır, panel kapanmaz', (t) async {
      final easy = EasyViewService();
      await _pumpApp(t, settings(easy));
      await openPanel(t);

      final tile = find.byKey(const ValueKey<String>('kolay_gorunum_anahtari'));
      expect(tile, findsOneWidget);
      expect(find.text('Kolay görünüm'), findsOneWidget);
      expect(find.text(EasyViewSwitchTile.subtitle), findsOneWidget);
      expect(t.widget<SwitchListTile>(tile).value, isFalse);
      // En üstte: başlıktan sonraki ilk öğe (öteki ayar öğelerinin üstünde).
      final firstMenu = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.byType(ListTile)).first;
      expect(t.getRect(tile).top, lessThanOrEqualTo(t.getRect(firstMenu).top));
      expect(t.getSize(tile).height, greaterThanOrEqualTo(56));

      await t.tap(tile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(easy.enabled, isTrue);
      expect(t.widget<SwitchListTile>(tile).value, isTrue);
      expect(find.byType(YanMenuAyarlar), findsOneWidget, reason: 'panel açık kalır: etki hemen görülür');
      expect((await SharedPreferences.getInstance()).getBool(EasyViewService.storageKey), isTrue);

      await t.tap(find.byType(Switch));
      await t.pump();
      expect(easy.enabled, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(EasyViewService.storageKey), isFalse);
    });

    testWidgets('erişilebilirlik: tek düğüm, etiket "Kolay görünüm", durum açık/kapalı bilgisi taşır', (t) async {
      final handle = t.ensureSemantics();
      final easy = EasyViewService();
      await _pumpApp(t, settings(easy));
      await openPanel(t);

      final node = t.getSemantics(find.byKey(const ValueKey<String>('kolay_gorunum_anahtari')));
      expect(node, isSemantics(hasToggledState: true, isToggled: false));
      final label = node.getSemanticsData().label;
      expect(label, contains('Kolay görünüm'));
      expect(label, contains(EasyViewSwitchTile.subtitle));

      await easy.setEnabled(true);
      await t.pump();
      expect(
        t.getSemantics(find.byKey(const ValueKey<String>('kolay_gorunum_anahtari'))),
        isSemantics(hasToggledState: true, isToggled: true),
      );
      handle.dispose();
    });

    for (final cell in <(double, double)>[(320, 2.0), (360, 1.5)]) {
      testWidgets('${cell.$1.toInt()} dp x${cell.$2}: anahtar satırı taşmadan kurulur (panel dolu, kolay görünüm açık)', (t) async {
        final easy = await _easyOn();
        await _pumpApp(t, settings(easy, systemScale: cell.$2), width: cell.$1, height: 640);
        await openPanel(t);
        expect(find.byKey(const ValueKey<String>('kolay_gorunum_anahtari')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('HomePage: kolay görünümde gerçek ana ekran', () {
    testWidgets('sakin: Panel büyük düğmelerle açılır; Ayarlar\'daki anahtarla kapatılıp açılabilir; Borcum düğmesi sayfayı açar', (t) async {
      final auth = _EasyAuth(UserRole.apartmentOwner);
      final access = await _access(
        () => <MySiteModules>[
          _my('resident', modules: {'announcements': true, 'finance': true, 'drive_storage': true, 'work_tracking': true}),
        ],
      );
      final easy = await _easyOn();
      final notifier = _quietNotifier();
      addTearDown(notifier.dispose);

      t.view.physicalSize = const Size(400, 1800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        EasyViewScope(
          service: easy,
          child: ViewModeScope(
            service: ViewModeService(),
            child: AnimatedBuilder(
              animation: easy,
              builder: (context, _) => MaterialApp(
                theme: easy.enabled ? easyViewLightTheme : AppTheme.light(),
                darkTheme: easy.enabled ? easyViewDarkTheme : AppTheme.dark(),
                builder: (c, child) => MediaQuery.withClampedTextScaling(
                  minScaleFactor: easy.enabled ? EasyViewService.minTextScale : 0.0,
                  maxScaleFactor: 2.0,
                  child: child!,
                ),
                home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      // Büyük düğme modu: Kapılar, Duyurular, Borcum, Belgeler, Taleplerim hepsi büyük düğme; hızlı işlemler yok.
      expect(find.byType(ModuleShowcaseView), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hizli_izgara')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_borc')), findsOneWidget, reason: 'borç kartı korunur');
      for (final item in <SirketMenuItem>[
        SirketMenuItem.kapilar,
        SirketMenuItem.duyurular,
        SirketMenuItem.borcum,
        SirketMenuItem.belgeler,
        SirketMenuItem.taleplerim,
      ]) {
        final button = _easyButton(item);
        await t.ensureVisible(button);
        await t.pump();
        expect(button, findsOneWidget, reason: '$item büyük düğmesi');
        expect(t.getSize(button).height, greaterThanOrEqualTo(ShowcaseEasyButton.minHeight));
      }
      expect(MediaQuery.textScalerOf(t.element(find.byType(ModuleShowcaseView))).scale(10), closeTo(13, 1e-9));

      // Ayarlar panelinde anahtar açık; kapatınca ızgara geri gelir.
      await openSettingsPanel(t);
      final tile = find.byKey(const ValueKey<String>('kolay_gorunum_anahtari'));
      expect(tile, findsOneWidget);
      expect(t.widget<SwitchListTile>(tile).value, isTrue);
      await t.tap(tile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(easy.enabled, isFalse);
      await closeMenuPanels(t);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_kolay')), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsOneWidget);
      expect(MediaQuery.textScalerOf(t.element(find.byType(ModuleShowcaseView))).scale(10), closeTo(10, 1e-9));

      // Yeniden aç: büyük düğmeler; Borcum düğmesine dokunmak Borcum sayfasını açar (kapıyı açan hiçbir dokunuş yok).
      await openSettingsPanel(t);
      await t.tap(find.byKey(const ValueKey<String>('kolay_gorunum_anahtari')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await closeMenuPanels(t);
      expect(easy.enabled, isTrue);
      final borcum = _easyButton(SirketMenuItem.borcum);
      await t.ensureVisible(borcum);
      await t.pump();
      await t.tap(borcum);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(ModuleShowcaseView), findsNothing, reason: 'Borcum sayfası açıldı');
      expect(auth.openDoorCalls, 0, reason: 'vitrinde hiçbir dokunuş kapı komutu göndermez');

      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  });
}

// ---------------------------------------------------------------------------
// HomePage için sahte servis ve veri (module_showcase_home_page_test.dart'ın yalın kopyası)
// ---------------------------------------------------------------------------

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

class _EasyAuth extends AuthService {
  _EasyAuth(this.role) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole role;
  int openDoorCalls = 0;

  @override
  UserSession? get session => UserSession(
    id: 5,
    fullName: 'Ayşe Yılmaz',
    email: 'kullanici@example.com',
    loginName: null,
    role: role,
    isActive: true,
    token: 'tok',
  );

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
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[_door], null);

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
  Future<MyFinance> getMyFinance() async => const MyFinance(
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
  );
}

MySiteModules _my(String role, {Map<String, bool> modules = const <String, bool>{}}) => MySiteModules(
  siteCode: 1,
  siteName: 'Güneş Sitesi',
  role: role,
  modules: <String, bool>{'door_control': true, ...modules},
  doorAccess: true,
);

Future<ModuleAccess> _access(List<MySiteModules> Function() sites) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
    isSuperUser: () => false,
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
