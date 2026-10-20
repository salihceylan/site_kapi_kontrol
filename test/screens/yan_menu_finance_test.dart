// Platform Faz 4a: çekmecede "Finans" ve "Borcum" öğeleri (`additionalItems`).
//
// İkisi de rol listesinde YOKTUR; yalnız `finance` modülü AÇIK siteye bağlı kullanıcıya HomePage ekler. Çekmece
// yalnız yerleşimi bilir: "Duyurular"ın (yoksa "Kişiler"in) altına, "Borcum" varsa "Finans"ın altına gelir.
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
void _expectUnderHeader(WidgetTester t, String title, String header) {
  final h = t.getRect(find.text(header));
  final tile = t.getRect(find.widgetWithText(ListTile, title));
  expect(h.bottom, lessThanOrEqualTo(tile.top + 0.01), reason: '"$title" "$header" başlığının altında');
}

void main() {
  group('Finans / Borcum çekmece öğeleri', () {
    testWidgets('varsayılan menüde YOKTUR (rol listesinde değildirler)', (t) async {
      for (final role in UserRole.values) {
        final titles = await _pumpMenu(t, role, toggle: role != UserRole.apartmentOwner);
        expect(titles, isNot(contains('Finans')), reason: '$role');
        expect(titles, isNot(contains('Borcum')), reason: '$role');
      }
    });

    testWidgets('yönetici: "Duyurular"ın hemen altında; seçilince finans döner', (t) async {
      final selected = <SirketMenuItem>[];
      final titles = await _pumpMenu(
        t,
        UserRole.siteManager,
        toggle: true,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.finans},
        onSelect: selected.add,
      );
      expect(titles.indexOf('Finans'), titles.indexOf('Duyurular') + 1);
      expect(titles.indexOf('Duyurular'), titles.indexOf('Kişiler') + 1);
      _expectUnderHeader(t, 'Finans', 'Borçlar');
      await t.tap(find.text('Finans'));
      expect(selected, <SirketMenuItem>[SirketMenuItem.finans]);
    });

    testWidgets('"Duyurular" yoksa "Kişiler"in altında', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.superUser,
        additional: const <SirketMenuItem>{SirketMenuItem.finans},
      );
      expect(titles.indexOf('Finans'), titles.indexOf('Kişiler') + 1);
    });

    testWidgets('sakin: Borcum "Duyurular"ın altında; seçilince borcum döner', (t) async {
      final selected = <SirketMenuItem>[];
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.duyurular, SirketMenuItem.borcum},
        onSelect: selected.add,
      );
      expect(titles, <String>[
        'Panel',
        'Duyurular',
        'Borcum',
        'Daireye Katıl & Cihaz Ekle',
        'Eller Serbest & Kestirmeler',
        'Profilim',
      ]);
      _expectUnderHeader(t, 'Borcum', 'Borçlar');
      expect(find.text('Profilim'), findsNothing, reason: 'Profilim Ayarlar panelinde (dişli)');
      await t.tap(find.text('Borcum'));
      expect(selected, <SirketMenuItem>[SirketMenuItem.borcum]);
    });

    testWidgets('ikisi birden (kurul üyesi sakin): Finans, ardından Borcum', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{
          SirketMenuItem.kisiler,
          SirketMenuItem.duyurular,
          SirketMenuItem.finans,
          SirketMenuItem.borcum,
        },
      );
      expect(titles.sublist(1, 5), <String>['Kişiler', 'Duyurular', 'Finans', 'Borcum']);
    });

    testWidgets('hiddenItems ek öğeleri de gizler', (t) async {
      final titles = await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        additional: const <SirketMenuItem>{SirketMenuItem.finans, SirketMenuItem.borcum},
        hidden: const <SirketMenuItem>{SirketMenuItem.finans, SirketMenuItem.borcum},
      );
      expect(titles, isNot(contains('Finans')));
      expect(titles, isNot(contains('Borcum')));
    });

    for (final (width, scale) in const <(double, double)>[(320.0, 2.0), (360.0, 1.5)]) {
      testWidgets('taşma yok: ${width.toInt()} dp x$scale, tüm ek öğelerle', (t) async {
        await _pumpMenu(
          t,
          UserRole.apartmentOwner,
          additional: const <SirketMenuItem>{
            SirketMenuItem.kisiler,
            SirketMenuItem.duyurular,
            SirketMenuItem.finans,
            SirketMenuItem.borcum,
          },
          width: width,
          height: 640,
          scale: scale,
        );
        expect(t.takeException(), isNull);
      });
    }
  });
}
