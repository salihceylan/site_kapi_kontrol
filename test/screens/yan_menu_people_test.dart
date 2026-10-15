// Platform Faz 2a: çekmecede "Kişiler" öğesi ve `additionalItems` (kurul üyesine salt okunur erişim).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';

Future<List<String>> _pumpMenu(
  WidgetTester t,
  UserRole role, {
  Set<SirketMenuItem> additional = const <SirketMenuItem>{},
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
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

void main() {
  group('Kişiler çekmece öğesi', () {
    testWidgets('rol listesinde yalnız süper kullanıcı ve site yöneticisi (yönetici modu) vardır', (t) async {
      expect(await _pumpMenu(t, UserRole.superUser), contains('Kişiler'));
      expect(await _pumpMenu(t, UserRole.siteManager, toggle: true), contains('Kişiler'));
      expect(await _pumpMenu(t, UserRole.siteManager, resident: true, toggle: true),
          isNot(contains('Kişiler')));
      expect(await _pumpMenu(t, UserRole.apartmentOwner), isNot(contains('Kişiler')));
      expect(await _pumpMenu(t, UserRole.individual), isNot(contains('Kişiler')));
    });

    testWidgets('additionalItems (kurul üyesi): rol listesinin sonuna eklenir, çıkıştan önce; seçilince kisiler döner', (t) async {
      final selected = <SirketMenuItem>[];
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.kisiler},
        onSelect: selected.add,
      );
      expect(titles, <String>[
        'Panel',
        'Daireye Katıl & Cihaz Ekle',
        'Eller Serbest & Kestirmeler',
        'Profilim',
        'Kişiler',
        'Çıkış Yap',
      ]);
      await t.tap(find.text('Kişiler'));
      expect(selected, <SirketMenuItem>[SirketMenuItem.kisiler]);
    });

    testWidgets('rol listesinde zaten varsa tekrarlanmaz (site yöneticisi hem yönetici hem kurul üyesi)', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.siteManager,
        toggle: true,
        additional: const <SirketMenuItem>{SirketMenuItem.kisiler},
      );
      expect(titles.where((e) => e == 'Kişiler'), hasLength(1));
    });

    testWidgets('sakin modundaki site yöneticisi kurul üyesiyse "Kişiler" görür', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.siteManager,
        resident: true,
        toggle: true,
        additional: const <SirketMenuItem>{SirketMenuItem.kisiler},
      );
      expect(titles, contains('Kişiler'));
    });

    testWidgets('hiddenItems ek öğeyi de gizler; varsayılan menü eskisi gibidir', (t) async {
      final hidden = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.kisiler},
        hidden: const <SirketMenuItem>{SirketMenuItem.kisiler},
      );
      expect(hidden, isNot(contains('Kişiler')));
      final plain = await _pumpMenu(t, UserRole.apartmentOwner);
      expect(plain, <String>[
        'Panel',
        'Daireye Katıl & Cihaz Ekle',
        'Eller Serbest & Kestirmeler',
        'Profilim',
        'Çıkış Yap',
      ]);
    });

    for (final (width, scale) in const <(double, double)>[(320.0, 2.0), (360.0, 1.5)]) {
      testWidgets('taşma yok: ${width.toInt()} dp x$scale, kurul üyesi menüsü', (t) async {
        await _pumpMenu(
          t,
          UserRole.apartmentOwner,
          additional: const <SirketMenuItem>{SirketMenuItem.kisiler},
          width: width,
          height: 640,
          scale: scale,
        );
        expect(t.takeException(), isNull);
        expect(find.text('Kişiler'), findsOneWidget);
      });
    }
  });
}
