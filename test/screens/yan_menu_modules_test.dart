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
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
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
        badgeCounts: badges,
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
    testWidgets('süper kullanıcı: 18 öğe + çıkış; Kişiler Site Yönetimi\'nin, Modüller Kişiler\'in, Modül Talepleri Modüller\'in, Site Başvuruları Modül Talepleri\'nin hemen altında; sonda Denetim Kaydı, Platform Ayarları, İstemci Hataları', (t) async {
      await _pumpMenu(t, UserRole.superUser, height: 1200);
      final titles = _titles(t);
      expect(titles, hasLength(19));
      expect(titles.indexOf('Kişiler'), titles.indexOf('Site Yönetimi') + 1);
      expect(titles.indexOf('Modüller'), titles.indexOf('Kişiler') + 1);
      expect(titles.indexOf('Modül Talepleri'), titles.indexOf('Modüller') + 1);
      expect(titles.indexOf('Site Başvuruları'), titles.indexOf('Modül Talepleri') + 1);
      expect(titles[titles.length - 4], 'Denetim Kaydı');
      expect(titles[titles.length - 3], 'Platform Ayarları');
      expect(titles[titles.length - 2], 'İstemci Hataları');
      expect(titles.last, 'Çıkış Yap');
    });

    testWidgets('site yöneticisi (yönetici modu): 8 öğe, Kişiler ve Modüller var; Denetim Kaydı ve Modül Talepleri YOK', (t) async {
      await _pumpMenu(t, UserRole.siteManager, toggle: true, height: 1200);
      final titles = _titles(t);
      expect(titles, contains('Kişiler'));
      expect(titles.indexOf('Kişiler'), titles.indexOf('Site Yönetimi') + 1);
      expect(titles, contains('Modüller'));
      expect(titles, isNot(contains('Denetim Kaydı')));
      expect(titles, isNot(contains('Modül Talepleri')));
      expect(titles, hasLength(1 + 8 + 1), reason: 'mod geçişi + 8 öğe + çıkış');
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
        expect(titles, isNot(contains('Kişiler')), reason: '$role: yalnız additionalItems ile (kurul üyesi)');
        expect(titles, isNot(contains('Denetim Kaydı')), reason: '$role');
        expect(titles, isNot(contains('Modül Talepleri')), reason: '$role');
        expect(titles, isNot(contains('Platform Ayarları')), reason: '$role: yalnız süper kullanıcı');
        expect(titles, isNot(contains('İstemci Hataları')), reason: '$role: yalnız süper kullanıcı');
        expect(titles, hasLength(count + (toggle ? 1 : 0) + 1), reason: '$role');
      }
    });
  });

  group('sayı rozeti (Modül Talepleri: bekleyen talep sayısı)', () {
    final badgeFinder = find.byKey(const ValueKey<String>('yan_menu_rozet'));

    testWidgets('sayı > 0 ise yalnız o öğede rozet; 0 ya da yoksa rozet yok; 99 üstü "99+"', (t) async {
      await _pumpMenu(
        t,
        UserRole.superUser,
        height: 1400,
        badges: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 3},
      );
      expect(badgeFinder, findsOneWidget);
      final tile = find.widgetWithText(ListTile, 'Modül Talepleri');
      expect(find.descendant(of: tile, matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: tile, matching: badgeFinder), findsOneWidget);

      await _pumpMenu(
        t,
        UserRole.superUser,
        height: 1400,
        badges: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 0},
      );
      expect(badgeFinder, findsNothing);

      await _pumpMenu(t, UserRole.superUser, height: 1400);
      expect(badgeFinder, findsNothing);

      await _pumpMenu(
        t,
        UserRole.superUser,
        height: 1400,
        badges: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 150},
      );
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('rozet beyaz metin / tehlike tonu zemini >= 4,5:1 ve ekran okuyucuya "N bekleyen" der', (t) async {
      final handle = t.ensureSemantics();
      await _pumpMenu(
        t,
        UserRole.superUser,
        height: 1400,
        badges: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 7},
      );
      final box = t.widget<DecoratedBox>(badgeFinder);
      final fill = (box.decoration as BoxDecoration).color!;
      expect(contrastRatio(Colors.white, fill), greaterThanOrEqualTo(4.5));
      // ListTile anlamsal düğümüne birleşir: "Modül Talepleri ... 7 bekleyen".
      expect(find.bySemanticsLabel(RegExp(r'Modül Talepleri[\s\S]*7 bekleyen')), findsOneWidget);
      handle.dispose();
    });

    for (final (w, h, s) in const <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5)]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('rozetli çekmece taşmaz: ${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}', (t) async {
          await _pumpMenu(
            t,
            UserRole.superUser,
            width: w,
            height: h,
            scale: s,
            dark: dark,
            badges: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 128},
          );
          expect(badgeFinder, findsOneWidget);
          await t.ensureVisible(find.text('Modül Talepleri'));
          await t.pump();
          expect(t.takeException(), isNull);
          // Başlık kırpılmadan (en çok 3 satır) görünür.
          expect(find.text('Modül Talepleri'), findsOneWidget);
        });
      }
    }
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

