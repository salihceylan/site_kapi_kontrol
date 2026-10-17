// Platform Faz 3b-A: çekmecede "Belgeler" öğesi (`additionalItems`).
//
// Rol listesinde YOKTUR; yalnız `documents` modülü AÇIK siteye bağlı kullanıcıya HomePage ekler. Çekmece yalnız
// yerleşimi bilir: "Borcum" / "Finans" / "Duyurular" / "Kişiler" sırasıyla ilk bulunanın altına gelir.
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
  double height = 1600,
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
  final tiles = find.descendant(
    of: find.byType(Drawer),
    matching: find.byType(ListTile),
  );
  return <String>[
    for (var i = 0; i < tiles.evaluate().length; i++)
      ((t.widget<ListTile>(tiles.at(i))).title! as Text).data!,
  ];
}

void main() {
  group('Belgeler çekmece öğesi', () {
    testWidgets('varsayılan menüde YOKTUR (rol listesinde değil)', (t) async {
      for (final role in UserRole.values) {
        final titles = await _pumpMenu(
          t,
          role,
          toggle: role != UserRole.apartmentOwner,
        );
        expect(titles, isNot(contains('Belgeler')), reason: '$role');
      }
    });

    testWidgets(
      'yönetici: "Duyurular"ın hemen altında; seçilince belgeler döner',
      (t) async {
        final selected = <SirketMenuItem>[];
        final titles = await _pumpMenu(
          t,
          UserRole.siteManager,
          toggle: true,
          additional: const <SirketMenuItem>{
            SirketMenuItem.duyurular,
            SirketMenuItem.belgeler,
          },
          onSelect: selected.add,
        );
        expect(titles.indexOf('Belgeler'), titles.indexOf('Duyurular') + 1);
        await t.tap(find.text('Belgeler'));
        expect(selected, <SirketMenuItem>[SirketMenuItem.belgeler]);
      },
    );

    testWidgets('"Finans" varsa onun altında; "Borcum" varsa onun altında', (
      t,
    ) async {
      var titles = await _pumpMenu(
        t,
        UserRole.siteManager,
        toggle: true,
        additional: const <SirketMenuItem>{
          SirketMenuItem.duyurular,
          SirketMenuItem.finans,
          SirketMenuItem.belgeler,
        },
      );
      expect(titles.indexOf('Belgeler'), titles.indexOf('Finans') + 1);
      titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{
          SirketMenuItem.duyurular,
          SirketMenuItem.borcum,
          SirketMenuItem.belgeler,
        },
      );
      expect(titles.indexOf('Belgeler'), titles.indexOf('Borcum') + 1);
    });

    testWidgets('yalnız "Kişiler" varsa (süper kullanıcı) onun altında', (
      t,
    ) async {
      final titles = await _pumpMenu(
        t,
        UserRole.superUser,
        additional: const <SirketMenuItem>{SirketMenuItem.belgeler},
      );
      expect(titles.indexOf('Belgeler'), titles.indexOf('Kişiler') + 1);
    });

    testWidgets('hiçbiri yoksa (sakin) "Panel"in altında', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.belgeler},
      );
      expect(titles.indexOf('Belgeler'), titles.indexOf('Panel') + 1);
    });

    testWidgets('gizlenen (hiddenItems) Belgeler çekmecede çıkmaz', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.siteManager,
        toggle: true,
        additional: const <SirketMenuItem>{SirketMenuItem.belgeler},
        hidden: const <SirketMenuItem>{SirketMenuItem.belgeler},
      );
      expect(titles, isNot(contains('Belgeler')));
    });

    for (final cell in const <(double, double)>[(320, 2.0), (360, 1.5)]) {
      testWidgets('taşma yok: ${cell.$1.toInt()} dp x${cell.$2}', (t) async {
        final titles = await _pumpMenu(
          t,
          UserRole.siteManager,
          toggle: true,
          width: cell.$1,
          scale: cell.$2,
          additional: const <SirketMenuItem>{
            SirketMenuItem.duyurular,
            SirketMenuItem.finans,
            SirketMenuItem.belgeler,
          },
        );
        expect(titles, contains('Belgeler'));
        expect(t.takeException(), isNull);
      });
    }
  });
}
