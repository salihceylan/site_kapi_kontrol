// Uçtan uca (integration_test) yürüyüşlerin Panel vitrini yardımcıları ve rol ekran listeleri. E2E cihaz / emülatör
// ister ve burada koşulamaz; bu test yardımcıların GERÇEK vitrin (ModuleShowcaseView) ve çekmece (YanMenu)
// anahtarlarıyla çalıştığını, başlık doğrulamasının yalnız AppBar'a baktığını, vitrin / çekmece eşlik kuralını ve her
// rolde Panel'in vitrin turu, kapı turlarının "Kapılar" kartıyla açılan ekranda koştuğunu doğrular. Vitrin anahtarı
// ya da ekran listesi bozulursa e2e turları sessizce boşa düşmesin diye burada kırılır.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../integration_test/support/e2e_driver.dart';
import '../integration_test/support/screens_common.dart' show showcaseTour;
import '../integration_test/support/screens_individual.dart' show individualPanelTour, individualScreens;
import '../integration_test/support/screens_resident.dart' show residentRemoteTour, residentScreens;
import '../integration_test/support/screens_site_manager.dart'
    show siteManagerResidentModeScreens, siteManagerScreens;
import '../integration_test/support/screens_super_user.dart' show superUserScreens;
import 'design/harness.dart';

UserSession _session(UserRole role) => UserSession(
  id: 7,
  fullName: 'Ayşe Yılmaz',
  email: 'a@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 't',
);

/// Panel kabuğu: AppBar başlığı "Panel", çekmece = gerçek YanMenu, gövde = gerçek ModuleShowcaseView (aynı öğe listesi).
Future<List<SirketMenuItem>> _pumpPanel(
  WidgetTester t, {
  required UserRole role,
  required ShowcaseAudience audience,
  required Set<SirketMenuItem> extras,
  bool resident = false,
}) async {
  t.view.physicalSize = const Size(412, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final items = YanMenu.visibleItems(role: role, isResidentMode: resident, additionalItems: extras);
  final base = harnessApp(const SizedBox.shrink()) as MaterialApp;
  await t.pumpWidget(
    MaterialApp(
      theme: base.theme,
      darkTheme: base.darkTheme,
      themeMode: base.themeMode,
      builder: base.builder,
      home: Scaffold(
        appBar: AppBar(title: const Text('Panel')),
        drawer: YanMenu(
          fullName: 'Ayşe Yılmaz',
          userEmail: 'a@example.com',
          role: role,
          isResidentMode: resident,
          selectedItem: SirketMenuItem.dashboard,
          onSelect: (_) {},
          onLogout: () {},
          additionalItems: extras,
        ),
        body: SingleChildScrollView(
          child: ModuleShowcaseView(
            session: _session(role),
            audience: audience,
            menuItems: items,
            onOpen: (_) {},
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 600));
  return items;
}

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  group('vitrin yardımcıları gerçek vitrin ve çekmeceyle', () {
    testWidgets('yönetici: kartlar / ikincil satır / çekmece anahtarla okunur; eşlik kuralı tutar; başlık yalnız AppBar', (
      t,
    ) async {
      const extras = <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.duyurular, SirketMenuItem.kisiler};
      final items = await _pumpPanel(
        t,
        role: UserRole.superUser,
        audience: ShowcaseAudience.admin,
        extras: extras,
      );
      expect(find.byKey(kShowcaseKey), findsOneWidget);
      final grid = showcaseCardItems();
      final secondary = showcaseChipItems();
      expect(grid.first, SirketMenuItem.kapilar, reason: 'Kapılar ızgarada ilk kart');
      expect(grid, containsAll(<SirketMenuItem>[SirketMenuItem.duyurular, SirketMenuItem.kisiler]));
      expect(grid, isNot(contains(SirketMenuItem.dashboard)));
      expect(secondary, contains(SirketMenuItem.profilim));
      expect(showcaseCardFinder(SirketMenuItem.kapilar), findsOneWidget);
      expect(doorCommandButtonsOnScreen(), isEmpty, reason: 'vitrinde kapı komutu düğmesi yok');

      // Vitrin kartı "Kapılar" yazar ama sayfa hâlâ Panel'dir: tüm ekranda aramak yanıltır, AppBar araması yanıltmaz.
      expect(findText('Kapılar', exact: true), findsWidgets);
      expect(appBarTitle('Kapılar'), findsNothing);
      expect(appBarTitle('Panel'), findsOneWidget);

      await _openDrawer(t);
      final drawer = drawerMenuItems();
      expect(drawer, items, reason: 'çekmece = YanMenu.visibleItems (ek eylem / yardım / çıkış sayılmaz)');
      expect(showcaseParityProblems(drawer: drawer, grid: grid, secondary: secondary), isEmpty);
    });

    testWidgets('sakin vitrini (hero + hızlı işlemler + ızgara): Kapılar kartı tek; eşlik kuralı tutar', (t) async {
      const extras = <SirketMenuItem>{
        SirketMenuItem.kapilar,
        SirketMenuItem.duyurular,
        SirketMenuItem.taleplerim,
        SirketMenuItem.belgeler,
      };
      final items = await _pumpPanel(
        t,
        role: UserRole.apartmentOwner,
        audience: ShowcaseAudience.resident,
        extras: extras,
      );
      final grid = showcaseCardItems();
      expect(grid.where((i) => i == SirketMenuItem.kapilar), hasLength(1));
      expect(doorCommandButtonsOnScreen(), isEmpty);
      await _openDrawer(t);
      expect(
        showcaseParityProblems(drawer: drawerMenuItems(), grid: grid, secondary: showcaseChipItems()),
        isEmpty,
        reason: 'öğeler: $items',
      );
    });

    testWidgets('anahtar önekleri: hızlı işlem / rozet / yardım çipi kart sayılmaz; kapı düğmesi raporlanır', (t) async {
      await t.pumpWidget(
        harnessApp(
          const Column(
            key: kShowcaseKey,
            children: <Widget>[
              SizedBox(key: ValueKey<String>('panel_kart_kapilar'), width: 10, height: 10),
              SizedBox(key: ValueKey<String>('panel_kart_rozet'), width: 10, height: 10),
              SizedBox(key: ValueKey<String>('panel_hizli_kapilar'), width: 10, height: 10),
              SizedBox(key: ValueKey<String>('panel_ikincil_profilim'), width: 10, height: 10),
              SizedBox(key: ValueKey<String>('panel_ikincil_yardim'), width: 10, height: 10),
              SizedBox(key: ValueKey<String>('resident_door_open_button'), width: 10, height: 10),
              SizedBox(key: ValueKey<String>('individual_door_open'), width: 10, height: 10),
            ],
          ),
        ),
      );
      expect(showcaseCardItems(), <SirketMenuItem>[SirketMenuItem.kapilar]);
      expect(showcaseChipItems(), <SirketMenuItem>[SirketMenuItem.profilim]);
      expect(doorCommandButtonsOnScreen(), <String>['resident_door_open_button', 'individual_door_open']);
    });

    test('kapı düğmesi anahtarları uygulamada gerçekten var (e2e bayatlamasın)', () {
      final sources = <String, String>{
        'admin_door_open_button': 'lib/ui/widgets/admin_door_status_card.dart',
        'resident_door_open_button': 'lib/ui/widgets/resident_door_remote_card.dart',
        'individual_door_open': 'lib/ui/widgets/individual_door_card.dart',
      };
      expect(kDoorCommandKeys.toSet(), sources.keys.toSet());
      sources.forEach((key, path) {
        expect(File(path).readAsStringSync(), contains("ValueKey<String>('$key')"), reason: path);
      });
    });
  });

  group('vitrin / çekmece eşlik kuralı (showcaseParityProblems)', () {
    const drawer = <SirketMenuItem>[
      SirketMenuItem.dashboard,
      SirketMenuItem.kapilar,
      SirketMenuItem.duyurular,
      SirketMenuItem.profilim,
    ];

    test('aynı öğeler: sorun yok (Panel kart değildir, hesap öğesi ikincil satırda)', () {
      expect(
        showcaseParityProblems(
          drawer: drawer,
          grid: const <SirketMenuItem>[SirketMenuItem.kapilar, SirketMenuItem.duyurular],
          secondary: const <SirketMenuItem>[SirketMenuItem.profilim],
        ),
        isEmpty,
      );
    });

    test('eksik, fazla, yinelenen kart ve kart olan Panel yakalanır', () {
      final problems = showcaseParityProblems(
        drawer: drawer,
        grid: const <SirketMenuItem>[
          SirketMenuItem.dashboard,
          SirketMenuItem.duyurular,
          SirketMenuItem.duyurular,
          SirketMenuItem.finans,
        ],
        secondary: const <SirketMenuItem>[SirketMenuItem.profilim],
      );
      expect(problems, contains('Panel kendisi vitrinde kart olmamali'));
      expect(problems, contains('Vitrinde birden cok kez: duyurular'));
      expect(problems, contains('Cekmecede var, vitrinde karti yok: kapilar'));
      expect(problems, contains('Vitrinde karti var, cekmecede yok: finans'));
      expect(problems, hasLength(4));
    });
  });

  group('e2e rol ekran listeleri: Panel = vitrin turu, kapı turları "Kapılar" kartıyla açılan ekranda', () {
    void expectShape(
      List<E2eScreenSpec> screens, {
      required String who,
      required bool optional,
      E2eInteractions? doorTour,
    }) {
      expect(screens.take(2).map((s) => s.name), <String>['panel', 'kapilar'], reason: who);
      final panel = screens[0];
      expect(panel.menuLabel, 'Panel', reason: who);
      expect(panel.titleText, 'Panel', reason: who);
      expect(panel.showcaseCard, isNull, reason: who);
      expect(panel.interactions, same(showcaseTour), reason: '$who: Panel vitrin turu koşar (kapı turu değil)');
      final doors = screens[1];
      expect(doors.menuLabel, 'Kapılar', reason: who);
      expect(doors.titleText, 'Kapılar', reason: who);
      expect(doors.showcaseCard, SirketMenuItem.kapilar, reason: '$who: Kapılar vitrindeki kartla açılır');
      expect(doors.optional, optional, reason: who);
      expect(doors.interactions, isNotNull, reason: who);
      if (doorTour != null) expect(doors.interactions, same(doorTour), reason: who);
      expect(screens.where((s) => s.menuLabel == 'Panel'), hasLength(1), reason: who);
      expect(screens.where((s) => s.name == 'kapilar'), hasLength(1), reason: who);
    }

    test('daire sakini', () {
      expectShape(residentScreens(), who: 'sakin', optional: false, doorTour: residentRemoteTour);
    });

    test('bireysel (Kapılar Geçiş Kontrol kapalıyken yok: isteğe bağlı)', () {
      expectShape(individualScreens(), who: 'bireysel', optional: true, doorTour: individualPanelTour);
    });

    test('site yöneticisi: yönetici modu ve sakin modu', () {
      expectShape(siteManagerScreens(siteKeys: const <String>['site_1']), who: 'yönetici', optional: false);
      expectShape(
        siteManagerResidentModeScreens(),
        who: 'yönetici (sakin modu)',
        optional: false,
        doorTour: individualPanelTour,
      );
    });

    test('süper kullanıcı', () {
      expectShape(superUserScreens(), who: 'süper', optional: false);
    });
  });
}
