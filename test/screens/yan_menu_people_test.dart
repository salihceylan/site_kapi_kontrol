// Platform Faz 2a: çekmecede "Kişiler" öğesi ve `additionalItems` (kurul üyesine salt okunur erişim).
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
  // İP-1D (G2): çekmece başlıklar altında gruplu çizilir ve ayar öğeleri sağ üstteki dişlidedir. Bu dosyanın sıra
  // kuralları menü LİSTESİNİN sırasıdır (`YanMenu.visibleItems`: vitrin kartlarının sırası); öğenin çekmecedeki
  // başlığı [_expectUnderHeader] ile sınanır.
  return <String>[
    for (final item in YanMenu.visibleItems(
      role: role,
      isResidentMode: resident,
      canToggleMode: toggle,
      additionalItems: additional,
      hiddenItems: hidden,
    ))
      YanMenu.titleFor(item, role),
  ];
}

/// Çekmecede [title] öğesi [header] başlığının altında mı (başlık öğenin üstünde ve öğe çizili)?
void _expectUnderHeader(WidgetTester t, String title, String header) => expectUnderDrawerHeader(t, title, header);

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
      // "Site Yönetimi" olmayan rolde "Panel"in hemen altı (listenin sonu DEĞİL).
      expect(titles, <String>[
        'Panel',
        'Kişiler',
        'Daireye Katıl',
        'Eller Serbest & Kestirmeler',
        'Profilim',
      ]);
      _expectUnderHeader(t, 'Kişiler', 'Daireler');
      await t.tap(find.text('Kişiler'));
      expect(selected, <SirketMenuItem>[SirketMenuItem.kisiler]);
    });

    testWidgets('rol listesinde "Site Yönetimi" varsa "Kişiler" onun hemen altındadır (yönetici sırasıyla tutarlı)', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.individual,
        toggle: true,
        additional: const <SirketMenuItem>{SirketMenuItem.kisiler},
      );
      expect(titles.indexOf('Kişiler'), titles.indexOf('Site Yönetimi') + 1);
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
        'Daireye Katıl',
        'Eller Serbest & Kestirmeler',
        'Profilim',
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
