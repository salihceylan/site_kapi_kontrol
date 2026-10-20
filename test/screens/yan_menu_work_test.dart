// İş Takibi: çekmecede "Talepler" (yönetim) ve "Taleplerim" (sakin) öğeleri (`additionalItems`).
//
// Rol listesinde YOKTURLAR; yalnız `work_tracking` modülü AÇIK siteye bağlı kullanıcıya HomePage ekler. Çekmece yalnız
// yerleşimi bilir: "Talepler" Belgeler / Borcum / Finans / Duyurular / Kişiler sırasıyla ilk bulunanın altına gelir,
// "Taleplerim" varsa "Talepler"in altına.
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
  ValueChanged<SirketMenuItem>? onSelect,
  bool toggle = false,
}) async {
  t.view.physicalSize = const Size(360, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    harnessApp(
      SizedBox(
        height: 1600,
        child: YanMenu(
          fullName: 'Ali Veli',
          userEmail: 'ali@example.com',
          role: role,
          selectedItem: SirketMenuItem.dashboard,
          onSelect: onSelect ?? (_) {},
          onLogout: () {},
          canToggleMode: toggle,
          onToggleMode: toggle ? () {} : null,
          additionalItems: additional,
          hiddenItems: hidden,
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 450));
  // İP-1D (G2): çekmece başlıklar altında gruplu çizilir ve ayar öğeleri sağ üstteki dişlidedir. Bu dosyanın sıra
  // kuralları menü LİSTESİNİN sırasıdır (`YanMenu.visibleItems`: vitrin kartlarının sırası); öğenin çekmecedeki
  // başlığı [_expectUnderHeader] ile sınanır.
  return <String>[
    for (final item in YanMenu.visibleItems(
      role: role,
      canToggleMode: toggle,
      additionalItems: additional,
      hiddenItems: hidden,
    ))
      YanMenu.titleFor(item, role),
  ];
}

/// Çekmecede [title] öğesi [header] başlığının altında mı (başlık öğenin üstünde ve öğe çizili)?
void _expectUnderHeader(WidgetTester t, String title, String header) {
  final h = t.getRect(find.text(header));
  final tile = t.getRect(find.widgetWithText(ListTile, title));
  expect(h.bottom, lessThanOrEqualTo(tile.top + 0.01), reason: '"$title" "$header" başlığının altında');
}

void main() {
  testWidgets('varsayılan menüde YOKTURLAR (rol listesinde değil)', (t) async {
    for (final role in UserRole.values) {
      final titles = await _pumpMenu(t, role, toggle: role != UserRole.apartmentOwner);
      expect(titles, isNot(contains('Talepler')), reason: '$role');
      expect(titles, isNot(contains('Taleplerim')), reason: '$role');
    }
  });

  testWidgets('"Belgeler" varsa onun altında; "Taleplerim" "Talepler"in hemen altında; seçilince doğru öğe döner', (t) async {
    final selected = <SirketMenuItem>[];
    final titles = await _pumpMenu(
      t,
      UserRole.apartmentOwner,
      additional: const <SirketMenuItem>{
        SirketMenuItem.duyurular,
        SirketMenuItem.belgeler,
        SirketMenuItem.talepler,
        SirketMenuItem.taleplerim,
      },
      onSelect: selected.add,
    );
    expect(titles.indexOf('Talepler'), titles.indexOf('Belgeler') + 1);
    expect(titles.indexOf('Taleplerim'), titles.indexOf('Talepler') + 1);
    _expectUnderHeader(t, 'Talepler', 'İletişim');
    _expectUnderHeader(t, 'Taleplerim', 'İletişim');
    await t.tap(find.text('Taleplerim'));
    expect(selected, <SirketMenuItem>[SirketMenuItem.taleplerim]);
  });

  testWidgets('üstteki öğeler yoksa sırayla "Borcum" / "Finans" / "Duyurular" / "Kişiler" altına düşer', (t) async {
    var titles = await _pumpMenu(
      t,
      UserRole.apartmentOwner,
      additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.borcum, SirketMenuItem.talepler},
    );
    expect(titles.indexOf('Talepler'), titles.indexOf('Borcum') + 1);
    titles = await _pumpMenu(
      t,
      UserRole.superUser,
      additional: const <SirketMenuItem>{SirketMenuItem.talepler},
    );
    expect(titles.indexOf('Talepler'), titles.indexOf('Kişiler') + 1);
  });

  testWidgets('yalnız "Taleplerim" (sakin): Duyurular\'ın altında', (t) async {
    final titles = await _pumpMenu(
      t,
      UserRole.apartmentOwner,
      additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.taleplerim},
    );
    expect(titles.indexOf('Taleplerim'), titles.indexOf('Duyurular') + 1);
  });

  testWidgets('gizli öğe çizilmez', (t) async {
    final titles = await _pumpMenu(
      t,
      UserRole.siteManager,
      toggle: true,
      additional: const <SirketMenuItem>{SirketMenuItem.talepler},
      hidden: const <SirketMenuItem>{SirketMenuItem.talepler},
    );
    expect(titles, isNot(contains('Talepler')));
  });
}
