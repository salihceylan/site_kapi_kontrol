// Liste ↔ kutucuk anahtarı (P2-22): Panel "Modüller" bölümü ile Kişiler → Daireler ve Kişiler sekmeleri.
//
// Sözleşmeler:
// - Varsayılan görünüm DEĞİŞMEZ (Panel kutucuk; Daireler / Kişiler liste); kapsam yoksa düğme yoktur.
// - Düğme görünümü değiştirir; tercih cihazda saklanır ve yeniden açılışta geri gelir; ekranlar birbirinden bağımsızdır.
// - Kutucukta da aynı dokunma, anlamsal etiket, rozet, çoklu seçim ve işlem menüsü vardır.
// - AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; iki kipte de taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/apartment_crm_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/person_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/showcase_layouts.dart';
import 'package:site_kapi_kontrol/ui/widgets/tile_grid.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

const String _toTiles = 'Kutucuk görünümüne geç';
const String _toList = 'Liste görünümüne geç';

UserSession _session(UserRole role) => UserSession(
  id: 7,
  fullName: 'Ayşe Yılmaz',
  email: 'a@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 't',
);

final Set<SirketMenuItem> _managerExtras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
};

List<SirketMenuItem> get _items => YanMenu.visibleItems(
  role: UserRole.siteManager,
  isResidentMode: false,
  canToggleMode: false,
  additionalItems: _managerExtras,
  hiddenItems: const <SirketMenuItem>{},
);

/// Ana sayfanın gövde yerleşimi: vitrin tam genişlikte, 16 dp kenar boşluğuyla.
Widget _page(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: SizedBox(width: double.infinity, child: child),
);

Widget _panel({
  ViewModeService? service,
  ValueChanged<SirketMenuItem>? onOpen,
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  Map<SirketMenuItem, String> nouns = const <SirketMenuItem, String>{},
}) {
  final view = _page(
    ModuleShowcaseView(
      session: _session(UserRole.siteManager),
      audience: ShowcaseAudience.admin,
      menuItems: _items,
      badgeCounts: badges,
      badgeNouns: nouns,
      onOpen: onOpen ?? (_) {},
    ),
  );
  return service == null ? view : ViewModeScope(service: service, child: view);
}

Finder _card(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_kart_${item.name}'));

Future<void> _tapToggle(WidgetTester t, String tooltip) async {
  await t.tap(find.byTooltip(tooltip));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('Panel "Modüller" bölümü', () {
    testWidgets('kapsam yok: eski görünüm (kutucuk ızgarası), anahtar düğmesi yok', (t) async {
      await pumpAt(t, _panel(), width: 400, height: 1400, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_liste')), findsNothing);
      expect(find.byTooltip(_toList), findsNothing);
      expect(find.byTooltip(_toTiles), findsNothing);
      expect(find.byType(ViewModeToggle), findsNothing);
    });

    testWidgets('kapsam var, tercih yok: varsayılan kutucuk; düğme "Liste görünümüne geç" der', (t) async {
      await pumpAt(t, _panel(service: ViewModeService()), width: 400, height: 1400, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_liste')), findsNothing);
      expect(find.byType(ShowcaseModuleRow), findsNothing);
      expect(find.byTooltip(_toList), findsOneWidget);
    });

    testWidgets('listeye geçince her modül tek satır: başlık + açıklama; kart anahtarları aynı', (t) async {
      final service = ViewModeService();
      await pumpAt(t, _panel(service: service), width: 400, height: 1400, scale: 1.0);
      await _tapToggle(t, _toList);

      expect(find.byKey(const ValueKey<String>('panel_vitrin_liste')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsNothing);
      final model = buildShowcaseModel(menuItems: _items, role: UserRole.siteManager);
      expect(find.byType(ShowcaseModuleRow), findsNWidgets(model.grid.length));
      for (final e in model.grid) {
        final card = _card(e.item);
        expect(card, findsOneWidget, reason: '${e.item} satırı');
        expect(find.descendant(of: card, matching: find.text(e.title)), findsOneWidget);
        expect(find.descendant(of: card, matching: find.text(e.description)), findsOneWidget);
      }
      expect(find.byTooltip(_toTiles), findsOneWidget, reason: 'düğme artık kutucuğa dönmeyi söyler');
      expect((await SharedPreferences.getInstance()).getString(ViewScreen.modules.storageKey), 'list');
      expect(t.takeException(), isNull);
    });

    testWidgets('satıra dokunmak kutucukla aynı gezinmedir (onOpen çağrılır)', (t) async {
      final service = ViewModeService();
      await service.setMode(ViewScreen.modules, ListViewMode.list);
      final opened = <SirketMenuItem>[];
      await pumpAt(t, _panel(service: service, onOpen: opened.add), width: 400, height: 1400, scale: 1.0);

      await t.tap(_card(SirketMenuItem.duyurular));
      await t.pump();
      expect(opened, <SirketMenuItem>[SirketMenuItem.duyurular]);
    });

    testWidgets('liste satırında rozet ve anlamsal etiket (başlık + sayı + sözcük) vardır', (t) async {
      final handle = t.ensureSemantics();
      final service = ViewModeService();
      await service.setMode(ViewScreen.modules, ListViewMode.list);
      await pumpAt(
        t,
        _panel(
          service: service,
          badges: <SirketMenuItem, int>{SirketMenuItem.duyurular: 3},
          nouns: <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
        ),
        width: 400,
        height: 1400,
        scale: 1.0,
      );

      expect(find.descendant(of: _card(SirketMenuItem.duyurular), matching: find.byKey(const ValueKey<String>('panel_kart_rozet'))), findsOneWidget);
      expect(find.descendant(of: _card(SirketMenuItem.duyurular), matching: find.text('3')), findsOneWidget);
      expect(find.bySemanticsLabel('Duyurular, 3 okunmamış'), findsOneWidget);
      // Rozetsiz satırda rozet yok.
      expect(find.descendant(of: _card(SirketMenuItem.finans), matching: find.byKey(const ValueKey<String>('panel_kart_rozet'))), findsNothing);
      handle.dispose();
    });

    testWidgets('kayıtlı tercih (yeniden açılış) ilk karede liste olarak açılır; kutucuğa dönülünce yine saklanır', (t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{ViewScreen.modules.storageKey: 'list'});
      final service = ViewModeService();
      await service.load();
      await pumpAt(t, _panel(service: service), width: 400, height: 1400, scale: 1.0);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_liste')), findsOneWidget);

      await _tapToggle(t, _toTiles);
      expect(find.byKey(const ValueKey<String>('panel_vitrin_izgara')), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString(ViewScreen.modules.storageKey), 'tiles');
    });

    listMatrix('liste kipi: dolu görünüm', (t, w, h, s, dark) async {
      final service = ViewModeService();
      await service.setMode(ViewScreen.modules, ListViewMode.list);
      await pumpAt(
        t,
        _panel(
          service: service,
          badges: <SirketMenuItem, int>{SirketMenuItem.duyurular: 120, SirketMenuItem.talepler: 4},
          nouns: <SirketMenuItem, String>{SirketMenuItem.duyurular: 'okunmamış'},
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.byType(ShowcaseModuleRow), findsWidgets);
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('Kişiler → Daireler ve Kişiler sekmeleri', () {
    Future<void> pumpPeople(
      WidgetTester t,
      PeopleFakeAuth auth, {
      ViewModeService? service,
      double width = 400,
      double height = 1600,
      double scale = 1.0,
      bool dark = false,
    }) async {
      final view = PeopleView(authService: auth, manageSites: true, readOnlySites: const <PeopleSite>[]);
      await pumpList(
        t,
        service == null ? view : ViewModeScope(service: service, child: view),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      // Önce siteler gelir, sekme sonra kurulur ve kendi verisini çeker: iki aşama.
      await settleFor(t, 100);
      await settleFor(t, 100);
    }

    Future<void> openTab(WidgetTester t, int index) async {
      await tapFinder(t, find.byKey(ValueKey<String>('people_tab_$index')));
      await settleFor(t);
    }

    group('Daireler', () {
      testWidgets('kapsam yok: eski liste kartları, anahtar yok', (t) async {
        await pumpPeople(t, PeopleFakeAuth.seeded());
        await openTab(t, 1);
        expect(find.byType(ApartmentCrmCard), findsNWidgets(3));
        expect(find.byType(ApartmentCrmTile), findsNothing);
        expect(find.byTooltip(_toTiles), findsNothing);
        expect(find.byTooltip('Yenile'), findsOneWidget);
      });

      testWidgets('varsayılan liste; düğme kutucuğa geçirir: aynı üç daire kompakt kutucuklarla', (t) async {
        final service = ViewModeService();
        await pumpPeople(t, PeopleFakeAuth.seeded(), service: service);
        await openTab(t, 1);
        expect(find.byType(ApartmentCrmCard), findsNWidgets(3));
        expect(find.byType(ApartmentCrmTile), findsNothing);

        await _tapToggle(t, _toTiles);

        expect(find.byType(ApartmentCrmCard), findsNothing);
        expect(find.byType(ApartmentCrmTile), findsNWidgets(3));
        expect(find.byKey(const ValueKey<String>('crm_kutucuk_izgara')), findsOneWidget);
        expect(find.text('A Blok - 5'), findsOneWidget);
        expect(find.text('Kat 2 · 3+1 · Arsa payı 35/1000'), findsOneWidget);
        expect(find.text('Malik: Ayşe Yılmaz'), findsOneWidget);
        expect(find.text('Kiracı: Mehmet Demir'), findsOneWidget);
        expect(find.text('Malik: kayıtlı değil'), findsNWidgets(2));
        expect(find.byTooltip(_toList), findsOneWidget);
        expect((await SharedPreferences.getInstance()).getString(ViewScreen.apartments.storageKey), 'tiles');
        expect(t.takeException(), isNull);
      });

      testWidgets('kutucuğa dokunmak daire kartını açar (liste kartıyla aynı); anlamsal etiket aynı', (t) async {
        final handle = t.ensureSemantics();
        final auth = PeopleFakeAuth.seeded();
        final service = ViewModeService();
        await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
        await pumpPeople(t, auth, service: service);
        await openTab(t, 1);

        // Kartın birleşik özeti: "Daire kartı: A Blok - 5" önde, içerik arkasında (liste kartıyla aynı).
        expect(find.bySemanticsLabel(RegExp(r'^Daire kartı: A Blok - 5')), findsOneWidget);
        await tapFinder(t, find.text('A Blok - 5'));
        await settleFor(t);
        expect(auth.getApartmentCalls, <int>[301]);
        expect(find.byType(AlertDialog), findsOneWidget);
        handle.dispose();
      });

      testWidgets('süzgeç / arama kutucuk kipinde de çalışır; boş sonuç mesajı aynı', (t) async {
        final auth = PeopleFakeAuth.seeded();
        final service = ViewModeService();
        await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
        await pumpPeople(t, auth, service: service);
        await openTab(t, 1);

        await t.enterText(find.byKey(const ValueKey<String>('apartments_search')), 'zzz');
        await t.pump(const Duration(milliseconds: 400));
        await t.pump();
        expect(auth.apartmentCalls.last.query, 'zzz');
        expect(find.byType(ApartmentCrmTile), findsNothing);
        expect(find.text('Bu arama ve süzgeç için daire bulunamadı.'), findsOneWidget);
      });

      testWidgets('Daireler tercihi Kişiler sekmesini etkilemez (ekranlar bağımsız)', (t) async {
        final service = ViewModeService();
        await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
        await pumpPeople(t, PeopleFakeAuth.seeded(), service: service);
        expect(find.byType(PersonCard), findsNWidgets(2), reason: 'Kişiler hâlâ liste');
        expect(find.byType(PersonCrmTile), findsNothing);
        await openTab(t, 1);
        expect(find.byType(ApartmentCrmTile), findsNWidgets(3));
      });

      listMatrix('kutucuk kipi: dolu görünüm', (t, w, h, s, dark) async {
        final service = ViewModeService();
        await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
        await pumpPeople(t, PeopleFakeAuth.seeded(), service: service, width: w, height: h, scale: s, dark: dark);
        await openTab(t, 1);
        expect(find.byType(ApartmentCrmTile), findsNWidgets(3));
        expect(find.text('A Blok - 5'), findsOneWidget);
      });
    });

    group('Kişiler', () {
      testWidgets('kapsam yok: eski liste kartları, anahtar yok', (t) async {
        await pumpPeople(t, PeopleFakeAuth.seeded());
        expect(find.byType(PersonCard), findsNWidgets(2));
        expect(find.byType(PersonCrmTile), findsNothing);
        expect(find.byTooltip(_toTiles), findsNothing);
      });

      testWidgets('düğme kutucuğa geçirir: ad, hesap çipi, ilk daire, telefon; işlem menüsü kartla aynı', (t) async {
        final service = ViewModeService();
        await pumpPeople(t, PeopleFakeAuth.seeded(), service: service);
        expect(find.byType(PersonCard), findsNWidgets(2));

        await _tapToggle(t, _toTiles);

        expect(find.byType(PersonCard), findsNothing);
        expect(find.byType(PersonCrmTile), findsNWidgets(2));
        expect(find.text('Ayşe Yılmaz'), findsOneWidget);
        expect(find.text('Mehmet Demir'), findsOneWidget);
        expect(find.text('Zeynep Kaya'), findsNothing, reason: 'eski sakin varsayılan süzgeçte yok');
        expect(find.text('Hesabı var'), findsOneWidget);
        expect(find.text('A Blok - 5'), findsOneWidget);
        expect(find.text('+90 555 111 22 33'), findsOneWidget);
        expect(find.byTooltip('İşlemler'), findsNWidgets(2), reason: 'yazma yetkisi: her kutucukta menü');
        expect((await SharedPreferences.getInstance()).getString(ViewScreen.persons.storageKey), 'tiles');

        // Menü kartla aynı: "Detayları Gör", "Düzenle" ...
        await t.tap(find.byTooltip('İşlemler').first);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Detayları Gör'), findsOneWidget);
        expect(find.text('Düzenle'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('kutucuğa dokunmak kişi kartını açar; anlamsal etiket "Kişi kartı: Ad"', (t) async {
        final handle = t.ensureSemantics();
        final auth = PeopleFakeAuth.seeded();
        final service = ViewModeService();
        await service.setMode(ViewScreen.persons, ListViewMode.tiles);
        await pumpPeople(t, auth, service: service);

        expect(find.bySemanticsLabel(RegExp(r'^Kişi kartı: Ayşe Yılmaz')), findsOneWidget);
        await tapFinder(t, find.text('Ayşe Yılmaz'));
        await settleFor(t);
        expect(find.byType(AlertDialog), findsOneWidget);
        handle.dispose();
      });

      testWidgets('çoklu seçim kutucukta çalışır: onay kutuları çıkar, dokunmak seçer, menü gizlenir', (t) async {
        final service = ViewModeService();
        await service.setMode(ViewScreen.persons, ListViewMode.tiles);
        await pumpPeople(t, PeopleFakeAuth.seeded(), service: service);

        await tapFinder(t, find.byTooltip('Çoklu Seçim'));
        expect(find.text('İşlem yapılacak kişileri seçin'), findsOneWidget);
        // 2 kutucuk onay kutusu + "tümünü seç" onay kutusu.
        expect(find.byType(Checkbox), findsNWidgets(3));
        expect(find.byTooltip('İşlemler'), findsNothing, reason: 'seçim kipinde menü yok (kartla aynı)');

        await tapFinder(t, find.text('Ayşe Yılmaz'));
        expect(find.text('1 kişi seçildi'), findsOneWidget);
        await tapFinder(t, find.text('Mehmet Demir'));
        expect(find.text('2 kişi seçildi'), findsOneWidget);
        await tapFinder(t, find.text('Ayşe Yılmaz'));
        expect(find.text('1 kişi seçildi'), findsOneWidget);
      });

      testWidgets('salt okunur kurul üyesi: kutucukta HİÇBİR yazma menüsü ya da düğmesi yok', (t) async {
        final service = ViewModeService();
        await service.setMode(ViewScreen.persons, ListViewMode.tiles);
        final auth = PeopleFakeAuth.seeded(role: UserRole.apartmentOwner);
        final view = PeopleView(
          authService: auth,
          manageSites: false,
          readOnlySites: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')],
        );
        await pumpList(
          t,
          ViewModeScope(service: service, child: view),
          width: 400,
          height: 1600,
          scale: 1.0,
          dark: false,
        );
        await settleFor(t, 100);
        await settleFor(t, 100);
        expect(find.byType(PersonCrmTile), findsNWidgets(2));
        expect(find.byTooltip('İşlemler'), findsNothing);
        expect(find.text('Kişi Ekle'), findsNothing);
        expect(find.byTooltip('Çoklu Seçim'), findsNothing);
      });

      listMatrix('kutucuk kipi: dolu görünüm, işlem menüsü açık', (t, w, h, s, dark) async {
        final service = ViewModeService();
        await service.setMode(ViewScreen.persons, ListViewMode.tiles);
        await pumpPeople(t, PeopleFakeAuth.seeded(), service: service, width: w, height: h, scale: s, dark: dark);
        expect(find.byType(PersonCrmTile), findsNWidgets(2));
        expect(find.text('Hesabı var'), findsOneWidget);
        // İşlem menüsü (üç nokta) en uzun etiketlerle de taşmaz.
        await t.ensureVisible(find.byTooltip('İşlemler').last);
        await t.pump();
        await t.tap(find.byTooltip('İşlemler').last);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Detayları Gör'), findsOneWidget);
      });
    });
  });

  group('TileGrid', () {
    test('sütun sayısı: telefonda 2, geniş ekranda 3-4; büyük yazıda azalır; en az 1', () {
      expect(tileColumns(288, 1.0), 2);
      expect(tileColumns(288, 1.5), 1);
      expect(tileColumns(288, 2.0), 1);
      expect(tileColumns(380, 1.0), 2);
      expect(tileColumns(700, 1.0), 3);
      expect(tileColumns(1000, 1.0), 4);
      expect(tileColumns(100, 2.0), 1);
      expect(tileColumns(288, 0.5), 2, reason: 'küçük yazı ölçeği sütun artırmaz');
    });

    testWidgets('satırlar eşit yükseklikte; son satırdaki boş hücre taşma yaratmaz', (t) async {
      await pumpAt(
        t,
        TileGrid(
          children: [
            for (var i = 0; i < 5; i++)
              Card(
                key: ValueKey<String>('k$i'),
                child: Text('Kutucuk $i${i == 1 ? ' ve çok daha uzun bir açıklama metni ile ikinci satıra uzanır' : ''}'),
              ),
          ],
        ),
        width: 360,
        scale: 1.0,
      );
      final h0 = t.getSize(find.byKey(const ValueKey<String>('k0'))).height;
      final h1 = t.getSize(find.byKey(const ValueKey<String>('k1'))).height;
      expect(h0, h1, reason: 'aynı satırdaki kutucuklar aynı yükseklikte');
      expect(t.getSize(find.byKey(const ValueKey<String>('k0'))).width, closeTo(t.getSize(find.byKey(const ValueKey<String>('k1'))).width, 0.01));
      expect(find.byKey(const ValueKey<String>('k4')), findsOneWidget);
    });
  });
}
