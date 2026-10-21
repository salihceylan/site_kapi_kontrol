// Platform Faz 3a: çekmecede "Duyurular" öğesi — `additionalItems`, "Kişiler"in altına yerleşim, sayı rozeti
// ve ekran okuyucu ifadesi ("N okunmamış"); varsayılan menü (öğe sayıları) DEĞİŞMEZ.
//
// İP-1D (G2): menü LİSTESİNDEKİ sıra (`YanMenu.visibleItems`, vitrin kartlarının sırası) eskisi gibidir; ÇEKMECEDE öğe
// kendi başlığının altındadır (Duyurular "İletişim"de). Ayar öğeleri (Profilim, Eller Serbest, Modül Talepleri ...)
// çekmecede değil, sağ üstteki dişliden açılan Ayarlar panelindedir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';
import '../support/menu_nav.dart' show expectUnderDrawerHeader;

Future<List<String>> _pumpMenu(
  WidgetTester t,
  UserRole role, {
  Set<SirketMenuItem> additional = const <SirketMenuItem>{},
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  Map<SirketMenuItem, String> nouns = const <SirketMenuItem, String>{},
  bool resident = false,
  bool toggle = false,
  ValueChanged<SirketMenuItem>? onSelect,
  double width = 360,
  double height = 1400,
  double scale = 1.0,
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
          isResidentMode: resident,
          canToggleMode: toggle,
          onToggleMode: toggle ? () {} : null,
          additionalItems: additional,
          hiddenItems: hidden,
          badgeCounts: badges,
          badgeNouns: nouns,
        ),
      ),
      scale: scale,
    ),
  );
  await t.pump(const Duration(milliseconds: 450));
  final tiles = find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile));
  return <String>[
    for (var i = 0; i < tiles.evaluate().length; i++)
      ((t.widget<ListTile>(tiles.at(i))).title! as Text).data!,
  ];
}

/// Menü listesinin (vitrin sırası) başlıkları.
List<String> _listTitles(
  UserRole role, {
  Set<SirketMenuItem> additional = const <SirketMenuItem>{},
  bool resident = false,
  bool toggle = false,
}) =>
    <String>[
      for (final item in YanMenu.visibleItems(
        role: role,
        isResidentMode: resident,
        canToggleMode: toggle,
        additionalItems: additional,
      ))
        YanMenu.titleFor(item, role),
    ];

/// Çekmecede [title] öğesi [header] başlığının altında mı (başlık öğenin üstünde)?
void _expectUnderHeader(WidgetTester t, String title, String header) => expectUnderDrawerHeader(t, title, header);

void main() {
  group('Duyurular çekmece öğesi', () {
    testWidgets('rol listesinde YOK: varsayılan menü eskisi gibidir (hiçbir rolde Duyurular çıkmaz)', (t) async {
      for (final role in UserRole.values) {
        expect(await _pumpMenu(t, role), isNot(contains('Duyurular')), reason: role.name);
      }
      // Menü listesi eskisi gibi; çekmecede ayar öğeleri yok (dişlide).
      expect(_listTitles(UserRole.apartmentOwner), <String>[
        'Panel',
        'Daireye Katıl',
        'Eller Serbest & Kestirmeler',
        'Profilim',
      ]);
      expect(await _pumpMenu(t, UserRole.apartmentOwner), <String>[
        'Panel',
        'Daireye Katıl',
        'Çıkış Yap',
      ]);
    });

    testWidgets('daire sakini: "Panel"in hemen altına eklenir ve seçilince duyurular döner', (t) async {
      final selected = <SirketMenuItem>[];
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        onSelect: selected.add,
      );
      expect(
        _listTitles(UserRole.apartmentOwner, additional: const <SirketMenuItem>{SirketMenuItem.duyurular}).take(2),
        <String>['Panel', 'Duyurular'],
        reason: 'menü listesinde (vitrin sırası) Panel\'in hemen altında',
      );
      expect(titles, <String>[
        'Panel',
        'Daireye Katıl',
        'Duyurular',
        'Çıkış Yap',
      ]);
      _expectUnderHeader(t, 'Duyurular', 'İletişim');
      await t.tap(find.text('Duyurular'));
      expect(selected, <SirketMenuItem>[SirketMenuItem.duyurular]);
    });

    testWidgets('yönetici ve süper kullanıcı: "Kişiler"in hemen altında', (t) async {
      for (final role in <UserRole>[UserRole.siteManager, UserRole.superUser]) {
        final titles = await _pumpMenu(
          t,
          role,
          toggle: role == UserRole.siteManager,
          additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        );
        final list = _listTitles(
          role,
          toggle: role == UserRole.siteManager,
          additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        );
        expect(list.indexOf('Duyurular'), list.indexOf('Kişiler') + 1, reason: '${role.name} (menü listesi)');
        expect(titles.where((e) => e == 'Duyurular'), hasLength(1));
        _expectUnderHeader(t, 'Duyurular', 'İletişim');
        _expectUnderHeader(t, 'Kişiler', 'Daireler');
      }
    });

    testWidgets('kurul üyesi (Kişiler + Duyurular ekleri): sıra Kişiler, Duyurular', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.kisiler},
      );
      expect(
        _listTitles(
          UserRole.apartmentOwner,
          additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.kisiler},
        ).take(3).toList(),
        <String>['Panel', 'Kişiler', 'Duyurular'],
      );
      expect(titles, <String>['Panel', 'Kişiler', 'Daireye Katıl', 'Duyurular', 'Çıkış Yap']);
    });

    testWidgets('sakin modundaki site yöneticisi: Duyurular eklenir (kişiler rol listesinde yok)', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.siteManager,
        resident: true,
        toggle: true,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
      );
      expect(titles, contains('Duyurular'));
      expect(titles, isNot(contains('Kişiler')));
    });

    testWidgets('hiddenItems ek öğeyi de gizler', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        hidden: const <SirketMenuItem>{SirketMenuItem.duyurular},
      );
      expect(titles, isNot(contains('Duyurular')));
    });

    testWidgets('rozet: okunmamış sayısı; ekran okuyucu "N okunmamış" der; 99+ ; 0 ise yok', (t) async {
      final semantics = t.ensureSemantics();
      await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        badges: const <SirketMenuItem, int>{SirketMenuItem.duyurular: 3},
        nouns: const <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
      );
      final badge = find.byKey(const ValueKey<String>('yan_menu_rozet'));
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('3')), findsOneWidget);
      expect(
        t.getSemantics(find.widgetWithText(ListTile, 'Duyurular')).getSemanticsData().label,
        allOf(contains('Duyurular'), contains('3 okunmamış')),
      );

      await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        badges: const <SirketMenuItem, int>{SirketMenuItem.duyurular: 250},
        nouns: const <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
      );
      expect(find.text('99+'), findsOneWidget);
      expect(
        t.getSemantics(find.widgetWithText(ListTile, 'Duyurular')).getSemanticsData().label,
        contains('250 okunmamış'),
        reason: 'ekran okuyucu gerçek sayıyı söyler',
      );

      await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular},
        badges: const <SirketMenuItem, int>{SirketMenuItem.duyurular: 0},
      );
      expect(find.byKey(const ValueKey<String>('yan_menu_rozet')), findsNothing);
      semantics.dispose();
    });

    testWidgets('nouns verilmeyen öğe eski sözcüğü ("bekleyen") korur (Modül Talepleri, Ayarlar panelinde)', (t) async {
      final semantics = t.ensureSemantics();
      t.view.physicalSize = const Size(360, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harnessApp(
          SizedBox(
            height: 1400,
            child: YanMenuAyarlar(
              role: UserRole.superUser,
              selectedItem: SirketMenuItem.dashboard,
              onSelect: (_) {},
              badgeCounts: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 4},
            ),
          ),
          scale: 1.0,
        ),
      );
      await t.pump(const Duration(milliseconds: 450));
      expect(
        t.getSemantics(find.widgetWithText(ListTile, 'Modül Talepleri')).getSemanticsData().label,
        contains('4 bekleyen'),
      );
      semantics.dispose();
    });

    for (final (width, scale) in const <(double, double)>[(320.0, 2.0), (360.0, 1.5)]) {
      testWidgets('taşma yok: ${width.toInt()} dp x$scale, rozetli Duyurular + Kişiler', (t) async {
        await _pumpMenu(
          t,
          UserRole.apartmentOwner,
          additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.kisiler},
          badges: const <SirketMenuItem, int>{SirketMenuItem.duyurular: 12},
          nouns: const <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
          width: width,
          height: 640,
          scale: scale,
        );
        expect(t.takeException(), isNull);
        expect(find.text('Duyurular'), findsOneWidget);
      });
    }
  });
}
