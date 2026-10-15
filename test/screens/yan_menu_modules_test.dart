// Platform modül sistemi Faz 1: çekmece öğeleri ("Modüller", "Denetim Kaydı") ve modül süzgeci
// (`hiddenItems`). Mevcut yerleşim/taşma testleri `yan_menu_layout_test.dart` içindedir; burada yeni
// öğe sayıları, gizleme ve DoorControlDisabledCard taşma/davranış testleri vardır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_menu.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_control_disabled_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';
import 'list_fixtures.dart';

Future<void> _pumpMenu(
  WidgetTester t,
  UserRole role, {
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
  bool resident = false,
  bool toggle = false,
  double width = 360,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) {
  return pumpAt(
    t,
    SizedBox(
      height: height,
      child: YanMenu(
        fullName: 'Ali Veli',
        userEmail: 'ali@example.com',
        role: role,
        selectedItem: SirketMenuItem.dashboard,
        isResidentMode: resident,
        canToggleMode: toggle,
        onToggleMode: toggle ? () {} : null,
        hiddenItems: hidden,
        onSelect: (_) {},
        onLogout: () {},
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
}

List<String> _titles(WidgetTester t) {
  final tiles = find.byType(ListTile);
  return <String>[
    for (var i = 0; i < tiles.evaluate().length; i++)
      ((t.widget<ListTile>(tiles.at(i))).title! as Text).data!,
  ];
}

void main() {
  group('yeni öğeler ve sayılar', () {
    testWidgets('süper kullanıcı: 13 öğe + çıkış; Modüller siteler\'in, Denetim Kaydı en sonun yanında', (t) async {
      await _pumpMenu(t, UserRole.superUser, height: 1200);
      final titles = _titles(t);
      expect(titles, hasLength(14));
      expect(titles.indexOf('Modüller'), titles.indexOf('Site Yönetimi') + 1);
      expect(titles[titles.length - 2], 'Denetim Kaydı');
      expect(titles.last, 'Çıkış Yap');
    });

    testWidgets('site yöneticisi (yönetici modu): 7 öğe, Modüller var; Denetim Kaydı YOK', (t) async {
      await _pumpMenu(t, UserRole.siteManager, toggle: true, height: 1200);
      final titles = _titles(t);
      expect(titles, contains('Modüller'));
      expect(titles, isNot(contains('Denetim Kaydı')));
      expect(titles, hasLength(1 + 7 + 1), reason: 'mod geçişi + 7 öğe + çıkış');
    });

    testWidgets('site yöneticisi sakin modu, daire kullanıcısı, bireysel: Modüller/Denetim Kaydı YOK', (t) async {
      for (final (role, resident, toggle, count) in <(UserRole, bool, bool, int)>[
        (UserRole.siteManager, true, true, 4),
        (UserRole.apartmentOwner, false, false, 4),
        (UserRole.individual, false, false, 3),
        (UserRole.individual, false, true, 6),
      ]) {
        await _pumpMenu(t, role, resident: resident, toggle: toggle, height: 1200);
        final titles = _titles(t);
        expect(titles, isNot(contains('Modüller')), reason: '$role');
        expect(titles, isNot(contains('Denetim Kaydı')), reason: '$role');
        expect(titles, hasLength(count + (toggle ? 1 : 0) + 1), reason: '$role');
      }
    });
  });

  group('hiddenItems', () {
    testWidgets('varsayılan boş: hiçbir öğe gizlenmez', (t) async {
      await _pumpMenu(t, UserRole.siteManager, toggle: true, height: 1200);
      expect(_titles(t), containsAll(<String>['Kayıtlı Cihazlar', 'Bluetooth ile Wi-Fi Kur']));
    });

    testWidgets('kapı öğeleri gizlenir; Panel, Modüller, Site Yönetimi, Katıl & Kur kalır', (t) async {
      await _pumpMenu(
        t,
        UserRole.siteManager,
        toggle: true,
        height: 1200,
        hidden: doorControlMenuItems,
      );
      final titles = _titles(t);
      expect(titles, isNot(contains('Kayıtlı Cihazlar')));
      expect(titles, isNot(contains('Bluetooth ile Wi-Fi Kur')));
      expect(titles, containsAll(<String>[
        'Panel',
        'Profilim',
        'Site Yönetimi',
        'Modüller',
        'Daireye Katıl & Cihaz Ekle',
        'Çıkış Yap',
      ]));
    });

    testWidgets('daire kullanıcısında Eller Serbest gizlenir', (t) async {
      await _pumpMenu(
        t,
        UserRole.apartmentOwner,
        hidden: doorControlMenuItems,
      );
      final titles = _titles(t);
      expect(titles, isNot(contains('Eller Serbest & Kestirmeler')));
      expect(titles, <String>['Panel', 'Daireye Katıl & Cihaz Ekle', 'Profilim', 'Çıkış Yap']);
    });

    testWidgets('giriş animasyonu sırası ekrandaki sırayla kalır (gizleme sonrası boşluk yok)', (t) async {
      await _pumpMenu(
        t,
        UserRole.siteManager,
        height: 1200,
        hidden: doorControlMenuItems,
      );
      final indexes = t
          .widgetList<StaggeredEntry>(find.byType(StaggeredEntry))
          .map((e) => e.index)
          .toList();
      expect(indexes, <int>[for (var i = 0; i < indexes.length; i++) i]);
    });
  });

  group('DoorControlDisabledCard', () {
    listMatrix('yönetici (düğmeli) ve sakin (yalnız bilgi) varyantları taşmaz', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      var opened = 0;
      await pumpList(
        t,
        Column(
          children: [
            DoorControlDisabledCard(onOpenModules: () => opened++),
            const SizedBox(height: 12),
            const DoorControlDisabledCard(),
          ],
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Geçiş Kontrol modülü kapalı'), findsNWidgets(2));
      expect(find.byType(PrimaryActionButton), findsOneWidget);
      await t.ensureVisible(find.text('Modüller Ekranını Aç'));
      await t.tap(find.text('Modüller Ekranını Aç'));
      expect(opened, 1);
    });
  });
}

