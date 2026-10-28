// K8 (P1-16): kompakt menü + "Tüm işlemler" girişi (YanMenu). YETENEK ile MENÜ YERLEŞİMİ ayrı katmandır: kompakt menü çekmecede yalnız
// YERLEŞİMİ değiştirir (öne çıkan öğeler); kümede olmayan görünür öğe kaybolmaz, "Tüm işlemler" girişi her zaman vardır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

const Set<SirketMenuItem> _extras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
  SirketMenuItem.anketler,
  SirketMenuItem.komsuPanosu,
};

Finder _tile(SirketMenuItem item) => find.byKey(ValueKey<SirketMenuItem>(item));
Finder _header(SirketMenuGroup group) => find.byKey(ValueKey<String>('yan_menu_grup_${group.name}'));
final Finder _allActions = find.byKey(const ValueKey<String>('yan_menu_tum_islemler'));

Future<void> _pump(
  WidgetTester t,
  YanMenu menu, {
  double width = 400,
  double height = 2000,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(drawer: menu, body: const SizedBox.expand()),
    ),
  );
  t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

YanMenu _menu({
  Set<SirketMenuItem>? featured,
  VoidCallback? onAllActions,
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
  UserRole role = UserRole.siteManager,
}) =>
    YanMenu(
      fullName: 'Ayşe Yılmaz',
      userEmail: 'ayse@example.com',
      role: role,
      selectedItem: SirketMenuItem.dashboard,
      onSelect: (_) {},
      onLogout: () {},
      additionalItems: _extras,
      hiddenItems: hidden,
      badgeCounts: badges,
      onOpenHelp: () {},
      featuredItems: featured,
      onOpenAllActions: onAllActions,
    );

void main() {
  group('geriye uyum: kompakt menü verilmezse çekmece eskisi gibidir', () {
    testWidgets('featuredItems ve onOpenAllActions yok: ne "Tüm işlemler" ne de gizlenen öğe', (t) async {
      await _pump(t, _menu());
      expect(_allActions, findsNothing);
      for (final item in _extras) {
        expect(_tile(item), findsOneWidget, reason: item.name);
      }
    });

    testWidgets('yalnız onOpenAllActions: tüm öğeler durur, "Tüm işlemler" "Yardım ve Destek"in üstündedir', (t) async {
      var taps = 0;
      await _pump(t, _menu(onAllActions: () => taps++));
      for (final item in _extras) {
        expect(_tile(item), findsOneWidget, reason: item.name);
      }
      expect(_allActions, findsOneWidget);
      expect(find.descendant(of: _allActions, matching: find.text('Tüm işlemler')), findsOneWidget);
      final help = t.getRect(find.byKey(const ValueKey<String>('yan_menu_yardim')));
      expect(t.getRect(_allActions).bottom, lessThanOrEqualTo(help.top + 0.01));
      // Başlıklı bölümlerin ardında: son bölümün son öğesinden sonra gelir.
      expect(t.getRect(_allActions).top, greaterThanOrEqualTo(t.getRect(_tile(SirketMenuItem.belgeler)).bottom - 0.01));
      await t.tap(_allActions);
      expect(taps, 1);
    });
  });

  group('kompakt menü: yalnız öne çıkanlar çizilir, görünür liste değişmez', () {
    final featured = <SirketMenuItem>{
      SirketMenuItem.dashboard,
      SirketMenuItem.kapilar,
      SirketMenuItem.siteler,
      SirketMenuItem.katilimVeKurulum,
      SirketMenuItem.yeniSite,
      SirketMenuItem.duyurular,
      SirketMenuItem.finans,
    };

    testWidgets('öne çıkmayan öğe çekmecede YOK; Panel, sabit öğeler ve öne çıkanlar VAR; "Tüm işlemler" her zaman var', (t) async {
      await _pump(t, _menu(featured: featured, onAllActions: () {}));
      for (final item in featured) {
        expect(_tile(item), findsOneWidget, reason: '${item.name} öne çıkıyor');
      }
      for (final item in <SirketMenuItem>[
        SirketMenuItem.belgeler,
        SirketMenuItem.talepler,
        SirketMenuItem.anketler,
        SirketMenuItem.komsuPanosu,
      ]) {
        expect(_tile(item), findsNothing, reason: '${item.name} yalnız "Tüm işlemler"de');
      }
      expect(_allActions, findsOneWidget);
    });

    testWidgets('görünürlük kuralı korunur: gizli (fail-closed) öğe kümede olsa bile çekmecede YOK', (t) async {
      await _pump(
        t,
        _menu(featured: featured, hidden: const <SirketMenuItem>{SirketMenuItem.kapilar}, onAllActions: () {}),
      );
      expect(_tile(SirketMenuItem.kapilar), findsNothing);
      expect(_tile(SirketMenuItem.finans), findsOneWidget);
    });

    testWidgets('öğesi kalmayan başlık çizilmez (İletişim: yalnız Duyurular kaldı; Daireler/Borçlar durur)', (t) async {
      await _pump(t, _menu(featured: featured, onAllActions: () {}));
      expect(_header(SirketMenuGroup.iletisim), findsOneWidget, reason: 'Duyurular İletişim başlığında');
      await _pump(
        t,
        _menu(
          featured: <SirketMenuItem>{...featured}..remove(SirketMenuItem.duyurular),
          onAllActions: () {},
        ),
      );
      expect(_header(SirketMenuGroup.iletisim), findsNothing, reason: 'İletişim öğeleri hep "Tüm işlemler"de: başlık da yok');
      expect(_header(SirketMenuGroup.borclar), findsOneWidget);
    });

    testWidgets('boş küme: yalnız sabit öğeler (Panel, Kapılar, Site Yönetimi ...) + "Tüm işlemler"; Ayarlar öğeleri çekmecede değil', (t) async {
      await _pump(t, _menu(featured: const <SirketMenuItem>{}, onAllActions: () {}));
      expect(_tile(SirketMenuItem.finans), findsNothing);
      expect(_tile(SirketMenuItem.duyurular), findsNothing);
      expect(_allActions, findsOneWidget);
      // Panel kümeden düşmez.
      expect(find.byType(YanMenu), findsOneWidget);
      expect(find.text('Ana sayfa'), findsOneWidget);
    });

    testWidgets('"Tüm işlemler" rozeti = öne çıkmayan öğelerin bekleyen sayıları toplamı; öne çıkanların sayısı eklenmez', (t) async {
      await _pump(
        t,
        _menu(
          featured: featured,
          onAllActions: () {},
          badges: const <SirketMenuItem, int>{
            SirketMenuItem.talepler: 2,
            SirketMenuItem.anketler: 3,
            SirketMenuItem.duyurular: 7, // öne çıkan: kendi satırında
          },
        ),
      );
      final badge = find.descendant(of: _allActions, matching: find.byKey(const ValueKey<String>('yan_menu_rozet')));
      expect(find.descendant(of: badge, matching: find.text('5')), findsOneWidget);
      final own = find.descendant(of: _tile(SirketMenuItem.duyurular), matching: find.byKey(const ValueKey<String>('yan_menu_rozet')));
      expect(find.descendant(of: own, matching: find.text('7')), findsOneWidget);
    });

    testWidgets('gizlenen öğe yoksa "Tüm işlemler"de rozet yok', (t) async {
      await _pump(
        t,
        _menu(featured: null, onAllActions: () {}, badges: const <SirketMenuItem, int>{SirketMenuItem.talepler: 4}),
      );
      expect(find.descendant(of: _allActions, matching: find.byKey(const ValueKey<String>('yan_menu_rozet'))), findsNothing);
    });

    testWidgets('anlamsal ağaç: "Tüm işlemler" tek düğme; rozetli hâlde "N bekleyen" okunur', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        _menu(featured: featured, onAllActions: () {}, badges: const <SirketMenuItem, int>{SirketMenuItem.anketler: 3}),
      );
      final node = t.getSemantics(find.descendant(of: _allActions, matching: find.byType(ListTile)));
      expect(node.label, contains('Tüm işlemler'));
      expect(node.label, contains('3 bekleyen'));
      handle.dispose();
    });
  });

  group('taşma yok: kompakt çekmece + Tüm işlemler (rozetli)', () {
    const cells = <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (640, 320, 2.0)];
    for (final (w, h, s) in cells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}', (t) async {
          await _pump(
            t,
            _menu(
              featured: const <SirketMenuItem>{SirketMenuItem.dashboard, SirketMenuItem.finans},
              onAllActions: () {},
              badges: const <SirketMenuItem, int>{SirketMenuItem.talepler: 120, SirketMenuItem.anketler: 9},
            ),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(t.takeException(), isNull);
          await t.ensureVisible(_allActions);
          await t.pump();
          expect(t.takeException(), isNull);
          expect(t.getSize(_allActions).height, greaterThanOrEqualTo(48));
        });
      }
    }
  });
}
