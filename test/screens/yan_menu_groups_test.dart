// İP-1D / G2: gruplu çekmece (YanMenu) ve sağ üstteki dişliden açılan "Ayarlar" paneli (YanMenuAyarlar).
//
// Sözleşme 2.4: çekmecede 8 başlık (Ana sayfa · Daireler · Borçlar · Tahsilat · Giderler · İletişim · Raporlar · Site
// hizmetleri); öğeler başlığının altında; öğesi olmayan başlık görünmez; rozet ve fail-closed kuralı korunur; Ayarlar
// öğeleri çekmecede değil dişli panelindedir; site seçici çekmecenin en üstündedir (mod geçişinin de üstünde).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

const Set<SirketMenuItem> _managerExtras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
};

Finder _header(SirketMenuGroup group) => find.byKey(ValueKey<String>('yan_menu_grup_${group.name}'));
Finder _tile(SirketMenuItem item) => find.byKey(ValueKey<SirketMenuItem>(item));
final Finder _siteRow = find.byKey(const ValueKey<String>('yan_menu_site'));

/// Gerçek `Scaffold.drawer` (+ isteğe bağlı `endDrawer`) içinde kurar ve [end] true ise Ayarlar panelini, değilse
/// çekmeceyi açar.
Future<void> _pump(
  WidgetTester t, {
  Widget? drawer,
  Widget? endDrawer,
  bool end = false,
  double width = 400,
  double height = 1200,
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
      home: Scaffold(drawer: drawer, endDrawer: endDrawer, body: const SizedBox.expand()),
    ),
  );
  final scaffold = t.state<ScaffoldState>(find.byType(Scaffold));
  end ? scaffold.openEndDrawer() : scaffold.openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

YanMenu _menu({
  UserRole role = UserRole.siteManager,
  Set<SirketMenuItem> extras = _managerExtras,
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  List<YanMenuAction> actions = const <YanMenuAction>[],
  YanMenuSiteContext? site,
  bool toggle = false,
  bool resident = false,
  ValueChanged<SirketMenuItem>? onSelect,
}) =>
    YanMenu(
      fullName: 'Ayşe Yılmaz',
      userEmail: 'ayse@example.com',
      role: role,
      selectedItem: SirketMenuItem.dashboard,
      onSelect: onSelect ?? (_) {},
      onLogout: () {},
      additionalItems: extras,
      hiddenItems: hidden,
      badgeCounts: badges,
      extraActions: actions,
      siteContext: site,
      canToggleMode: toggle,
      isResidentMode: resident,
      onToggleMode: toggle ? () {} : null,
      onOpenHelp: () {},
    );

YanMenuAyarlar _settings({
  UserRole role = UserRole.superUser,
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  List<YanMenuAction> actions = const <YanMenuAction>[],
  SirketMenuItem selected = SirketMenuItem.dashboard,
  ValueChanged<SirketMenuItem>? onSelect,
}) =>
    YanMenuAyarlar(
      role: role,
      selectedItem: selected,
      onSelect: onSelect ?? (_) {},
      badgeCounts: badges,
      extraActions: actions,
    );

void main() {
  group('gruplu çekmece', () {
    testWidgets('yalnız öğesi olan başlıklar, karar G2 sırasıyla; Ayarlar öğeleri çekmecede yok', (t) async {
      await _pump(t, drawer: _menu());
      final visible = <SirketMenuGroup>[
        for (final group in SirketMenuGroup.values)
          if (_header(group).evaluate().isNotEmpty) group,
      ];
      expect(visible, <SirketMenuGroup>[
        SirketMenuGroup.anaSayfa,
        SirketMenuGroup.daireler,
        SirketMenuGroup.borclar,
        SirketMenuGroup.iletisim,
        SirketMenuGroup.siteHizmetleri,
      ]);
      // Başlıklar yukarıdan aşağı aynı sırada.
      final tops = <double>[for (final g in visible) t.getTopLeft(_header(g)).dy];
      expect(tops, equals(<double>[...tops]..sort()));
      for (final group in visible) {
        expect(find.descendant(of: _header(group), matching: find.text(group.title)), findsOneWidget);
      }
      for (final item in const <SirketMenuItem>[
        SirketMenuItem.profilim,
        SirketMenuItem.moduller,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ]) {
        expect(_tile(item), findsNothing, reason: '${item.name} Ayarlar panelindedir');
      }
      expect(find.text('Ayarlar'), findsNothing, reason: 'Ayarlar çekmece başlığı değil');
    });

    testWidgets('her öğe kendi başlığının altında, sonraki başlığın üstünde', (t) async {
      await _pump(t, drawer: _menu());
      final sections = YanMenu.drawerSections(
        YanMenu.visibleItems(role: UserRole.siteManager, additionalItems: _managerExtras),
      );
      for (var i = 0; i < sections.length; i++) {
        final top = t.getRect(_header(sections[i].group)).bottom;
        final bottom = i + 1 < sections.length ? t.getRect(_header(sections[i + 1].group)).top : double.infinity;
        for (final item in sections[i].items) {
          final r = t.getRect(_tile(item));
          expect(r.top, greaterThanOrEqualTo(top - 0.01), reason: '${item.name} başlığın altında');
          expect(r.bottom, lessThanOrEqualTo(bottom + 0.01), reason: '${item.name} sonraki başlığın üstünde');
        }
      }
    });

    testWidgets('başlıklar ekran okuyucuda başlık düğümüdür', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, drawer: _menu());
      expect(
        t.getSemantics(find.descendant(of: _header(SirketMenuGroup.iletisim), matching: find.text('İletişim'))),
        isSemantics(label: 'İletişim', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('rozet korunur; gizli öğe (fail-closed) ve boşalan başlığı çizilmez', (t) async {
      await _pump(
        t,
        drawer: _menu(
          extras: const <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.duyurular},
          hidden: const <SirketMenuItem>{SirketMenuItem.kapilar},
          badges: const <SirketMenuItem, int>{SirketMenuItem.duyurular: 3},
        ),
      );
      expect(_tile(SirketMenuItem.kapilar), findsNothing);
      expect(_header(SirketMenuGroup.siteHizmetleri), findsNothing, reason: 'tek öğesi gizli: başlık da yok');
      final badge = find.descendant(
        of: _tile(SirketMenuItem.duyurular),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(find.descendant(of: badge, matching: find.text('3')), findsOneWidget);
    });

    testWidgets('kapı ek eylemleri "Kapılar"ın hemen altında (Site hizmetleri)', (t) async {
      await _pump(
        t,
        drawer: _menu(
          role: UserRole.apartmentOwner,
          extras: const <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.belgeler},
          actions: <YanMenuAction>[
            YanMenuAction(icon: Icons.qr_code_2_rounded, title: 'Kapıya QR Göster', onTap: () {}),
          ],
        ),
      );
      final doors = t.getRect(_tile(SirketMenuItem.kapilar));
      final action = t.getRect(find.byKey(const ValueKey<String>('yan_menu_ek_0')));
      final docs = t.getRect(_tile(SirketMenuItem.belgeler));
      expect(action.top, greaterThanOrEqualTo(doors.bottom - 0.01));
      expect(docs.top, greaterThanOrEqualTo(action.bottom - 0.01), reason: 'eylem Kapılar ile Belgeler arasında');
    });

    testWidgets('öğeye dokunmak onSelect geri çağrısını verir', (t) async {
      SirketMenuItem? picked;
      await _pump(t, drawer: _menu(onSelect: (i) => picked = i));
      await t.tap(_tile(SirketMenuItem.finans));
      expect(picked, SirketMenuItem.finans);
    });
  });

  group('site seçici (çekmecenin en üstü)', () {
    const one = YanMenuSiteContext(sites: <YanMenuSite>[YanMenuSite(code: 1, name: 'Güneş Sitesi')]);

    testWidgets('tek site: bilgi satırı (düğme değil); mod geçişinin üstünde', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, drawer: _menu(site: one, toggle: true));
      expect(_siteRow, findsOneWidget);
      expect(find.descendant(of: _siteRow, matching: find.text('Güneş Sitesi')), findsOneWidget);
      expect(t.getRect(_siteRow).bottom, lessThanOrEqualTo(t.getRect(find.text('Sakin Moduna Geç')).top + 0.01));
      expect(
        t.getRect(_siteRow).bottom,
        lessThanOrEqualTo(t.getRect(_header(SirketMenuGroup.anaSayfa)).top + 0.01),
        reason: 'site satırı başlıkların üstünde',
      );
      expect(
        t.getSemantics(_siteRow),
        isSemantics(label: 'Site: Güneş Sitesi', isButton: false, hasTapAction: false),
        reason: 'seçilecek başka site yok',
      );
      handle.dispose();
    });

    testWidgets('çok site: seçici; dokununca liste açılır, seçilen site geri çağrıyla gelir', (t) async {
      final handle = t.ensureSemantics();
      final picks = <int?>[];
      await _pump(
        t,
        drawer: _menu(
          site: YanMenuSiteContext(
            sites: const <YanMenuSite>[YanMenuSite(code: 1, name: 'Güneş Sitesi'), YanMenuSite(code: 2, name: 'Ay Sitesi')],
            onChanged: picks.add,
          ),
        ),
      );
      expect(find.descendant(of: _siteRow, matching: find.text('Tüm siteler (2)')), findsOneWidget);
      expect(t.getSemantics(_siteRow), isSemantics(isButton: true, hasTapAction: true));
      await t.tap(_siteRow);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      for (final (key, label) in <(String, String)>[('tum', 'Tüm siteler'), ('1', 'Güneş Sitesi'), ('2', 'Ay Sitesi')]) {
        final option = find.byKey(ValueKey<String>('yan_menu_site_secenek_$key'));
        expect(option, findsOneWidget, reason: label);
        expect(find.descendant(of: option, matching: find.text(label)), findsOneWidget);
      }
      await t.tap(find.byKey(const ValueKey<String>('yan_menu_site_secenek_2')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(picks, <int?>[2]);
      handle.dispose();
    });

    testWidgets('seçili site satırda görünür; "Tüm siteler" null verir', (t) async {
      final picks = <int?>[];
      await _pump(
        t,
        drawer: _menu(
          site: YanMenuSiteContext(
            sites: const <YanMenuSite>[YanMenuSite(code: 1, name: 'Güneş Sitesi'), YanMenuSite(code: 2, name: 'Ay Sitesi')],
            selectedCode: 2,
            onChanged: picks.add,
          ),
        ),
      );
      expect(find.descendant(of: _siteRow, matching: find.text('Ay Sitesi')), findsOneWidget);
      await t.tap(_siteRow);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey<String>('yan_menu_site_secenek_tum')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(picks, <int?>[null]);
    });

    testWidgets('seçim verilmeyen çok site (sakin): bilgi satırı "ilk site +N site"', (t) async {
      await _pump(
        t,
        drawer: _menu(
          role: UserRole.apartmentOwner,
          site: const YanMenuSiteContext(
            sites: <YanMenuSite>[YanMenuSite(code: 1, name: 'Güneş Sitesi'), YanMenuSite(code: 2, name: 'Ay Sitesi')],
          ),
        ),
      );
      expect(find.descendant(of: _siteRow, matching: find.text('Güneş Sitesi +1 site')), findsOneWidget);
    });

    testWidgets('site bağlamı verilmezse satır yok', (t) async {
      await _pump(t, drawer: _menu());
      expect(_siteRow, findsNothing);
    });
  });

  group('Ayarlar paneli (dişli)', () {
    testWidgets('süper kullanıcı: ayar öğeleri menü sırasıyla, rozet, ek eylem; çekmece öğesi yok', (t) async {
      final handle = t.ensureSemantics();
      SirketMenuItem? picked;
      var widgetTaps = 0;
      await _pump(
        t,
        end: true,
        endDrawer: _settings(
          badges: const <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 4},
          actions: <YanMenuAction>[
            YanMenuAction(icon: Icons.widgets_outlined, title: 'Masaüstüne Widget Ekle', onTap: () => widgetTaps++),
          ],
          onSelect: (i) => picked = i,
        ),
      );
      final expected = YanMenu.settingsItems(YanMenu.visibleItems(role: UserRole.superUser));
      final shown = <SirketMenuItem>[
        for (final e in find
            .descendant(of: find.byType(YanMenuAyarlar), matching: find.byWidgetPredicate((w) => w.key is ValueKey<SirketMenuItem>))
            .evaluate())
          (e.widget.key! as ValueKey<SirketMenuItem>).value,
      ];
      expect(shown, expected);
      expect(shown, isNot(contains(SirketMenuItem.siteler)), reason: 'Site Yönetimi çekmecededir');
      expect(
        t.getSemantics(find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text('Ayarlar'))),
        isSemantics(label: 'Ayarlar', isHeader: true),
      );
      final badge = find.descendant(
        of: _tile(SirketMenuItem.modulTalepleri),
        matching: find.byKey(const ValueKey<String>('yan_menu_rozet')),
      );
      expect(find.descendant(of: badge, matching: find.text('4')), findsOneWidget);
      await t.ensureVisible(_tile(SirketMenuItem.platformAyarlari));
      await t.pump();
      await t.tap(_tile(SirketMenuItem.platformAyarlari));
      expect(picked, SirketMenuItem.platformAyarlari);
      final action = find.byKey(const ValueKey<String>('yan_menu_ayar_ek_0'));
      await t.ensureVisible(action);
      await t.pump();
      await t.tap(action);
      expect(widgetTaps, 1);
      handle.dispose();
    });

    testWidgets('seçili ayar öğesi işaretli (seçili çubuk)', (t) async {
      await _pump(t, end: true, endDrawer: _settings(role: UserRole.siteManager, selected: SirketMenuItem.moduller));
      final tile = t.widget<ListTile>(find.descendant(of: _tile(SirketMenuItem.moduller), matching: find.byType(ListTile)));
      expect(tile.selected, isTrue);
    });

    test('rozet toplamı: yalnız ayar öğelerinin rozetleri', () {
      expect(
        YanMenuAyarlar.badgeTotal(
          const <SirketMenuItem>[SirketMenuItem.modulTalepleri, SirketMenuItem.siteBasvurulari, SirketMenuItem.duyurular],
          const <SirketMenuItem, int>{
            SirketMenuItem.modulTalepleri: 2,
            SirketMenuItem.siteBasvurulari: 1,
            SirketMenuItem.duyurular: 9,
          },
        ),
        3,
      );
    });
  });

  group('taşma yok: çekmece ve Ayarlar paneli', () {
    const cells = <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (640, 320, 2.0), (820, 1180, 1.0)];
    for (final (w, h, s) in cells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}', (t) async {
          await _pump(
            t,
            width: w,
            height: h,
            scale: s,
            dark: dark,
            drawer: _menu(
              site: YanMenuSiteContext(
                sites: const <YanMenuSite>[
                  YanMenuSite(code: 1, name: 'Çok Uzun Adlı Güneşli Vadi Konutları Sitesi'),
                  YanMenuSite(code: 2, name: 'Ay Sitesi'),
                ],
                onChanged: (_) {},
              ),
              toggle: true,
              badges: const <SirketMenuItem, int>{SirketMenuItem.duyurular: 120},
            ),
          );
          expect(t.takeException(), isNull);
          for (final e in find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile)).evaluate()) {
            expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(48));
          }
          expect(t.getSize(_siteRow).height, greaterThanOrEqualTo(48));
          await _pump(t, width: w, height: h, scale: s, dark: dark, end: true, endDrawer: _settings());
          expect(t.takeException(), isNull);
          for (final e in find.descendant(of: find.byType(YanMenuAyarlar), matching: find.byType(ListTile)).evaluate()) {
            expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(48));
          }
        });
      }
    }
  });
}
