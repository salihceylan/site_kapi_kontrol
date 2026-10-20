// Panel modül vitrini (ModuleShowcaseView): kartlar, fail-closed, hero kart, hızlı işlemler, odak barı, duyarlı ızgara,
// erişilebilirlik ve taşma matrisi (320/360/412/820 x yazı ölçeği 1,0/1,5/2,0 x açık/koyu).
//
// Vitrin yan menünün hesapladığı öğe listesinden ([YanMenu.visibleItems]) türer: listede olmayan modülün kartı olamaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';

UserSession _session(UserRole role, {String name = 'Ayşe Yılmaz'}) => UserSession(
  id: 7,
  fullName: name,
  email: 'a@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 't',
);

List<SirketMenuItem> _items(
  UserRole role, {
  Set<SirketMenuItem> extras = const <SirketMenuItem>{},
  Set<SirketMenuItem> hidden = const <SirketMenuItem>{},
  bool resident = false,
  bool toggle = false,
}) => YanMenu.visibleItems(
  role: role,
  isResidentMode: resident,
  canToggleMode: toggle,
  additionalItems: extras,
  hiddenItems: hidden,
);

/// Sakinin tüm modülleri açık menüsü.
final Set<SirketMenuItem> _residentExtras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.borcum,
  SirketMenuItem.belgeler,
  SirketMenuItem.taleplerim,
  SirketMenuItem.rezervasyon,
  SirketMenuItem.anket,
  SirketMenuItem.ziyaretcilerim,
  SirketMenuItem.kararlar,
};

/// Yöneticinin tüm modülleri açık menüsü.
final Set<SirketMenuItem> _managerExtras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
  SirketMenuItem.rezervasyonlar,
  SirketMenuItem.anketler,
  SirketMenuItem.ziyaretciKayitlari,
  SirketMenuItem.sozlesmeler,
  SirketMenuItem.kararDefteri,
};

MyFinance _debt(int minor, {int? overdue, DateTime? due}) => MyFinance(
  items: [
    MyFinanceApartment(
      siteCode: 1,
      siteName: 'Güneş Sitesi',
      apartmentId: 5,
      label: 'D:3',
      blockName: 'A Blok',
      balanceMinor: minor,
      overdueMinor: overdue,
      nextDueDate: due,
    ),
  ],
);

Widget _view({
  required UserRole role,
  required ShowcaseAudience audience,
  required List<SirketMenuItem> items,
  required ValueChanged<SirketMenuItem> onOpen,
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  Map<SirketMenuItem, String> nouns = const <SirketMenuItem, String>{},
  Future<MyFinance> Function()? fetch,
  String? siteName,
  VoidCallback? onHelp,
  Widget? below,
}) => SizedBox(
  width: double.infinity,
  child: ModuleShowcaseView(
    session: _session(role),
    audience: audience,
    menuItems: items,
    badgeCounts: badges,
    badgeNouns: nouns,
    onOpen: onOpen,
    fetchMyFinance: fetch,
    residentSiteName: siteName,
    onOpenHelp: onHelp,
    belowHero: below,
  ),
);

Finder _card(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_kart_${item.name}'));
Finder _quick(SirketMenuItem item) => find.byKey(ValueKey<String>('panel_hizli_${item.name}'));

Future<void> _pump(
  WidgetTester t,
  Widget w, {
  double width = 400,
  double height = 1400,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
}) async {
  await pumpAt(t, w, width: width, height: height, scale: scale, dark: dark, reduce: reduce);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  group('kartlar ve fail-closed', () {
    testWidgets('her görünen menü öğesi için kart: görsel + başlık + açıklama; Panel kart değildir', (t) async {
      final items = _items(UserRole.siteManager, extras: _managerExtras);
      await _pump(t, _view(role: UserRole.siteManager, audience: ShowcaseAudience.admin, items: items, onOpen: (_) {}));

      final model = buildShowcaseModel(menuItems: items, role: UserRole.siteManager);
      expect(model.grid, isNotEmpty);
      for (final e in model.grid) {
        expect(_card(e.item), findsOneWidget, reason: '${e.item} kartı');
        final card = _card(e.item);
        expect(find.descendant(of: card, matching: find.text(e.title)), findsOneWidget);
        expect(find.descendant(of: card, matching: find.text(e.description)), findsOneWidget);
        final art = t.widget<ModuleArt>(find.descendant(of: card, matching: find.byType(ModuleArt)));
        expect(art.kind, e.art);
      }
      expect(_card(SirketMenuItem.dashboard), findsNothing, reason: 'vitrin kendi kartını çizmez');
    });

    testWidgets('kapalı modülün kartı yok: menü listesinde olmayan öğeler hiçbir koşulda çizilmez', (t) async {
      // Finans, Belgeler, Rezervasyon ve Kapılar (Geçiş Kontrol) kapalı.
      final items = _items(
        UserRole.siteManager,
        extras: _managerExtras,
        hidden: {SirketMenuItem.kapilar, SirketMenuItem.finans, SirketMenuItem.belgeler, SirketMenuItem.rezervasyonlar},
      );
      await _pump(
        t,
        _view(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.admin,
          items: items,
          // Rozet haritasında kapalı modül için sayı olsa bile kart çıkmaz.
          badges: {SirketMenuItem.finans: 5},
          onOpen: (_) {},
        ),
      );
      for (final closed in [
        SirketMenuItem.kapilar,
        SirketMenuItem.finans,
        SirketMenuItem.belgeler,
        SirketMenuItem.rezervasyonlar,
      ]) {
        expect(_card(closed), findsNothing, reason: '$closed kapalı: kartı yok');
      }
      expect(_card(SirketMenuItem.duyurular), findsOneWidget);
      expect(_card(SirketMenuItem.talepler), findsOneWidget);
    });

    testWidgets('hesap / ayar öğeleri ızgarada değil, "Hesap ve ayarlar" satırında; yardım düğmesi çalışır', (t) async {
      final opened = <SirketMenuItem>[];
      var help = 0;
      final items = _items(UserRole.siteManager, extras: _managerExtras);
      await _pump(
        t,
        _view(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.admin,
          items: items,
          onOpen: opened.add,
          onHelp: () => help++,
        ),
      );
      expect(_card(SirketMenuItem.profilim), findsNothing);
      expect(_card(SirketMenuItem.bluetoothWifiKur), findsNothing);
      expect(find.text('Hesap ve ayarlar'), findsOneWidget);
      final profil = find.byKey(const ValueKey<String>('panel_ikincil_profilim'));
      expect(profil, findsOneWidget);
      await t.ensureVisible(profil);
      await t.tap(profil);
      expect(opened, <SirketMenuItem>[SirketMenuItem.profilim]);

      final yardim = find.byKey(const ValueKey<String>('panel_ikincil_yardim'));
      await t.ensureVisible(yardim);
      await t.tap(yardim);
      expect(help, 1);
      expect(opened.length, 1, reason: 'yardım bir menü öğesi seçmez');
    });

    testWidgets('karta dokunmak onOpen(öğe) çağırır (çekmecede seçmekle aynı gezinme)', (t) async {
      final opened = <SirketMenuItem>[];
      final items = _items(UserRole.apartmentOwner, extras: _residentExtras);
      await _pump(
        t,
        _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: items, onOpen: opened.add),
      );
      for (final item in [SirketMenuItem.duyurular, SirketMenuItem.belgeler, SirketMenuItem.kararlar, SirketMenuItem.kapilar]) {
        await t.ensureVisible(_card(item));
        await t.tap(_card(item));
        expect(opened.last, item);
      }
    });

    testWidgets('rozet: sayı > 0 ise nokta + sayı, 99\'dan büyükse "99+", 0 ise yok', (t) async {
      final items = _items(UserRole.apartmentOwner, extras: _residentExtras);
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          badges: {SirketMenuItem.duyurular: 3, SirketMenuItem.ziyaretcilerim: 150, SirketMenuItem.belgeler: 0},
          nouns: {SirketMenuItem.duyurular: 'okunmamış'},
          onOpen: (_) {},
        ),
      );
      const rozet = ValueKey<String>('panel_kart_rozet');
      expect(find.descendant(of: _card(SirketMenuItem.duyurular), matching: find.byKey(rozet)), findsOneWidget);
      expect(find.descendant(of: _card(SirketMenuItem.duyurular), matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: _card(SirketMenuItem.ziyaretcilerim), matching: find.text('99+')), findsOneWidget);
      expect(find.descendant(of: _card(SirketMenuItem.belgeler), matching: find.byKey(rozet)), findsNothing);
    });

    testWidgets('erişilebilirlik: her kart tek düğme; etiket = başlık + rozet, ipucu = açıklama', (t) async {
      final handle = t.ensureSemantics();
      final items = _items(UserRole.apartmentOwner, extras: _residentExtras);
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          badges: {SirketMenuItem.duyurular: 3},
          nouns: {SirketMenuItem.duyurular: 'okunmamış'},
          onOpen: (_) {},
        ),
      );
      expect(
        t.getSemantics(_card(SirketMenuItem.duyurular)),
        isSemantics(
          label: 'Duyurular, 3 okunmamış',
          hint: showcaseDescription(SirketMenuItem.duyurular),
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        t.getSemantics(_card(SirketMenuItem.belgeler)),
        isSemantics(
          label: 'Belgeler',
          hint: showcaseDescription(SirketMenuItem.belgeler),
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Dokunma hedefi >= 48 dp.
      expect(t.getSize(_card(SirketMenuItem.belgeler)).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });
  });

  group('sakin hero kartı', () {
    final items = _items(UserRole.apartmentOwner, extras: _residentExtras);

    testWidgets('Borcum açık + borç bilgisi alındı: "Güncel borcunuz", tutar, vade bilgisi ve "Borcum\'a git"', (t) async {
      final opened = <SirketMenuItem>[];
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: opened.add,
          fetch: () async => _debt(325000, overdue: 100000, due: DateTime(2026, 11, 10)),
        ),
      );
      expect(find.text('Güncel borcunuz'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_hero_tutar')), findsOneWidget);
      expect(find.text('3.250,00 ₺'), findsOneWidget);
      expect(find.text('Vadesi geçen: 1.000,00 ₺'), findsOneWidget);
      expect(find.text('Sıradaki vade: 10.11.2026'), findsOneWidget);
      expect(find.text('Güneş Sitesi · A Blok / D:3'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('panel_hero_borcuma_git')));
      expect(opened, <SirketMenuItem>[SirketMenuItem.borcum]);
    });

    testWidgets('bakiye sıfır: "Borcunuz yok" yalnız sunucu sıfır döndürdüyse; alacak varsa "Alacağınız"', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          fetch: () async => _debt(0),
        ),
      );
      expect(find.text('Borcunuz yok'), findsOneWidget);

      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          fetch: () async => _debt(-4500),
        ),
      );
      expect(find.text('Alacağınız'), findsOneWidget);
      expect(find.text('45,00 ₺'), findsOneWidget);
    });

    testWidgets('yükleniyor / hata: selamlama + site bilgisi; ASLA "Borcunuz yok" denmez', (t) async {
      final gate = Completer<MyFinance>();
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          siteName: 'Güneş Sitesi',
          fetch: () => gate.future,
        ),
      );
      expect(find.text('Merhaba, Ayşe'), findsOneWidget);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(find.text('Borcunuz yok'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_borcuma_git')), findsNothing);

      gate.completeError(StateError('ağ yok'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Merhaba, Ayşe'), findsOneWidget);
      expect(find.text('Borç bilginiz şu an alınamadı.'), findsOneWidget);
      expect(find.text('Borcunuz yok'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_borcuma_git')), findsOneWidget, reason: 'hata durumunda yine de Borcum\'a gidilebilir');
    });

    testWidgets('modül kapalı hatası (MODULE_DISABLED) sessiz selamlama: hata notu yok', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          fetch: () async => throw ApiException('kapalı', statusCode: 403, code: 'MODULE_DISABLED'),
        ),
      );
      expect(find.text('Merhaba, Ayşe'), findsOneWidget);
      expect(find.text('Borç bilginiz şu an alınamadı.'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_borcuma_git')), findsNothing);
    });

    testWidgets('Borcum menüde YOKSA (finans kapalı) borç bilgisi hiç istenmez: selamlama', (t) async {
      var calls = 0;
      final noDebt = _items(UserRole.apartmentOwner, extras: _residentExtras.difference({SirketMenuItem.borcum}));
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: noDebt,
          onOpen: (_) {},
          fetch: () async {
            calls++;
            return _debt(1000);
          },
        ),
      );
      expect(calls, 0, reason: 'kapalı modülün ucu çağrılmaz');
      expect(find.text('Merhaba, Ayşe'), findsOneWidget);
      expect(find.text('Güncel borcunuz'), findsNothing);
      expect(_card(SirketMenuItem.borcum), findsNothing);
    });

    testWidgets('modül sonradan kapanınca eski tutar ekranda KALMAZ', (t) async {
      final key = GlobalKey<ModuleShowcaseViewState>();
      Widget build(List<SirketMenuItem> menu) => SizedBox(
        width: double.infinity,
        child: ModuleShowcaseView(
          key: key,
          session: _session(UserRole.apartmentOwner),
          audience: ShowcaseAudience.resident,
          menuItems: menu,
          onOpen: (_) {},
          fetchMyFinance: () async => _debt(325000),
        ),
      );
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(harnessApp(SingleChildScrollView(child: build(items))));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('3.250,00 ₺'), findsOneWidget);

      final closed = _items(UserRole.apartmentOwner, extras: _residentExtras.difference({SirketMenuItem.borcum}));
      await t.pumpWidget(harnessApp(SingleChildScrollView(child: build(closed))));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('3.250,00 ₺'), findsNothing);
      expect(find.text('Güncel borcunuz'), findsNothing);
      expect(find.text('Merhaba, Ayşe'), findsOneWidget);
    });

    testWidgets('"Yeni duyuru" kartı (belowHero) hero kartın altında, hızlı işlemlerin üstünde durur', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          below: const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: SizedBox(key: ValueKey<String>('altta_kart'), height: 40, width: double.infinity),
          ),
        ),
      );
      final hero = t.getTopLeft(find.byKey(const ValueKey<String>('panel_hero_selam'))).dy;
      final below = t.getTopLeft(find.byKey(const ValueKey<String>('altta_kart'))).dy;
      final quick = t.getTopLeft(find.byKey(const ValueKey<String>('panel_hizli_izgara'))).dy;
      expect(hero, lessThan(below));
      expect(below, lessThan(quick));
    });
  });

  group('hızlı işlemler (yalnız modülü açıkken)', () {
    testWidgets('sakin: Kapıyı aç, Arıza bildir, Ziyaretçi ve kargo, Belgeler; dokununca ilgili öğe açılır', (t) async {
      final opened = <SirketMenuItem>[];
      final items = _items(UserRole.apartmentOwner, extras: _residentExtras);
      await _pump(
        t,
        _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: items, onOpen: opened.add),
      );
      expect(_quick(SirketMenuItem.kapilar), findsOneWidget);
      expect(_quick(SirketMenuItem.taleplerim), findsOneWidget);
      expect(_quick(SirketMenuItem.ziyaretcilerim), findsOneWidget);
      expect(_quick(SirketMenuItem.belgeler), findsOneWidget);
      expect(find.text('Kapıyı aç'), findsOneWidget);
      expect(find.text('Arıza bildir'), findsOneWidget);
      await t.tap(_quick(SirketMenuItem.taleplerim));
      await t.tap(_quick(SirketMenuItem.kapilar));
      expect(opened, <SirketMenuItem>[SirketMenuItem.taleplerim, SirketMenuItem.kapilar]);
    });

    testWidgets('kapı modülü kapalı: kapı kartı da "Kapıyı aç" hızlı eylemi de yok; öteki hızlı işlemler durur', (t) async {
      final items = _items(
        UserRole.apartmentOwner,
        extras: _residentExtras,
        hidden: {SirketMenuItem.kapilar, SirketMenuItem.ellerSerbest},
      );
      await _pump(
        t,
        _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: items, onOpen: (_) {}),
      );
      expect(_card(SirketMenuItem.kapilar), findsNothing);
      expect(_quick(SirketMenuItem.kapilar), findsNothing);
      expect(find.text('Kapıyı aç'), findsNothing);
      expect(_quick(SirketMenuItem.taleplerim), findsOneWidget);
      expect(_quick(SirketMenuItem.belgeler), findsOneWidget);
    });

    testWidgets('modülü kapalı olanın hızlı eylemi yok (iş takibi ve belgeler kapalı)', (t) async {
      final items = _items(
        UserRole.apartmentOwner,
        extras: _residentExtras.difference({SirketMenuItem.taleplerim, SirketMenuItem.belgeler}),
      );
      await _pump(
        t,
        _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: items, onOpen: (_) {}),
      );
      expect(_quick(SirketMenuItem.taleplerim), findsNothing);
      expect(_quick(SirketMenuItem.belgeler), findsNothing);
      expect(find.text('Arıza bildir'), findsNothing);
      expect(_quick(SirketMenuItem.kapilar), findsOneWidget);
    });

    testWidgets('hiç hızlı işlem yoksa başlığı da çizilmez; yönetici ve bireysel vitrininde hızlı işlem yoktur', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: _items(UserRole.apartmentOwner),
          onOpen: (_) {},
        ),
      );
      expect(find.text('Hızlı işlemler'), findsNothing);

      await _pump(
        t,
        _view(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.admin,
          items: _items(UserRole.siteManager, extras: _managerExtras),
          onOpen: (_) {},
        ),
      );
      expect(find.text('Hızlı işlemler'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsNothing);

      await _pump(
        t,
        _view(
          role: UserRole.individual,
          audience: ShowcaseAudience.individual,
          items: _items(UserRole.individual, extras: {SirketMenuItem.kapilar}),
          onOpen: (_) {},
        ),
      );
      expect(find.text('Hızlı işlemler'), findsNothing);
      expect(find.byKey(const ValueKey<String>('panel_hero_selam')), findsNothing);
      expect(_card(SirketMenuItem.kapilar), findsOneWidget);
      expect(_card(SirketMenuItem.katilimVeKurulum), findsOneWidget);
    });
  });

  group('yönetici odak barı', () {
    testWidgets('bekleyen sayı varsa koyu bar: başlık "N iş", her satırda tek düğme o sayfaya gider', (t) async {
      final opened = <SirketMenuItem>[];
      await _pump(
        t,
        _view(
          role: UserRole.superUser,
          audience: ShowcaseAudience.admin,
          items: _items(UserRole.superUser, extras: {SirketMenuItem.kapilar}),
          badges: {SirketMenuItem.modulTalepleri: 4, SirketMenuItem.siteBasvurulari: 2},
          onOpen: opened.add,
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_odak_bar')), findsOneWidget);
      expect(find.text('Dikkat edilmesi gereken 2 iş var'), findsOneWidget);
      expect(find.text('4 bekleyen modül talebi'), findsOneWidget);
      expect(find.text('2 bekleyen site başvurusu'), findsOneWidget);

      // Bar koyu odak rengindedir (#0F172A).
      final bar = t.widget<DecoratedBox>(
        find.descendant(of: find.byKey(const ValueKey<String>('panel_odak_bar')), matching: find.byType(DecoratedBox)).first,
      );
      expect((bar.decoration as BoxDecoration).color, const Color(0xFF0F172A));

      await t.tap(find.byKey(const ValueKey<String>('panel_odak_modulTalepleri')));
      await t.tap(find.byKey(const ValueKey<String>('panel_odak_siteBasvurulari')));
      expect(opened, <SirketMenuItem>[SirketMenuItem.modulTalepleri, SirketMenuItem.siteBasvurulari]);
    });

    testWidgets('bekleyen sayı yoksa bar çizilmez; tek bekleyen "1 iş"', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.superUser,
          audience: ShowcaseAudience.admin,
          items: _items(UserRole.superUser),
          badges: {SirketMenuItem.modulTalepleri: 0, SirketMenuItem.siteBasvurulari: 0},
          onOpen: (_) {},
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_odak_bar')), findsNothing);

      await _pump(
        t,
        _view(
          role: UserRole.superUser,
          audience: ShowcaseAudience.admin,
          items: _items(UserRole.superUser),
          badges: {SirketMenuItem.siteBasvurulari: 1},
          onOpen: (_) {},
        ),
      );
      expect(find.text('Dikkat edilmesi gereken 1 iş var'), findsOneWidget);
    });

    testWidgets('sakin vitrininde odak barı yok (rozetler kartlarda gösterilir)', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: _items(UserRole.apartmentOwner, extras: _residentExtras),
          badges: {SirketMenuItem.duyurular: 2},
          onOpen: (_) {},
        ),
      );
      expect(find.byKey(const ValueKey<String>('panel_odak_bar')), findsNothing);
    });
  });

  group('duyarlı ızgara', () {
    Future<List<double>> columnTops(WidgetTester t, List<SirketMenuItem> items) async => [
      for (final item in items) t.getTopLeft(_card(item)).dy,
    ];

    testWidgets('telefon (400 dp): 2 sütun; geniş (1100 dp): 4 sütun; yazı 2,0 telefonda 1 sütun', (t) async {
      final menu = _items(UserRole.siteManager, extras: _managerExtras);
      final model = buildShowcaseModel(menuItems: menu, role: UserRole.siteManager);
      final first4 = model.grid.take(4).map((e) => e.item).toList();

      await _pump(t, _view(role: UserRole.siteManager, audience: ShowcaseAudience.admin, items: menu, onOpen: (_) {}), width: 400);
      var tops = await columnTops(t, first4);
      expect(tops[0], tops[1], reason: '2 sütun: ilk iki kart aynı satırda');
      expect(tops[2], greaterThan(tops[0]), reason: '3. kart alt satırda');

      await _pump(t, _view(role: UserRole.siteManager, audience: ShowcaseAudience.admin, items: menu, onOpen: (_) {}), width: 1100);
      tops = await columnTops(t, first4);
      expect(tops.toSet().length, 1, reason: '4 sütun: ilk dört kart aynı satırda');

      await _pump(t, _view(role: UserRole.siteManager, audience: ShowcaseAudience.admin, items: menu, onOpen: (_) {}), width: 400, scale: 2.0);
      tops = await columnTops(t, first4);
      expect(tops[1], greaterThan(tops[0]), reason: 'büyük yazıda tek sütun');
    });

    testWidgets('aynı satırdaki kartlar aynı yüksekliktedir', (t) async {
      final menu = _items(UserRole.siteManager, extras: _managerExtras);
      await _pump(t, _view(role: UserRole.siteManager, audience: ShowcaseAudience.admin, items: menu, onOpen: (_) {}), width: 400);
      final model = buildShowcaseModel(menuItems: menu, role: UserRole.siteManager);
      final a = t.getSize(_card(model.grid[0].item)).height;
      final b = t.getSize(_card(model.grid[1].item)).height;
      expect(a, b);
    });
  });

  group('hareket azaltma', () {
    testWidgets('disableAnimations açıkken vitrin ilk karede tam görünür (giriş animasyonu yok)', (t) async {
      final menu = _items(UserRole.apartmentOwner, extras: _residentExtras);
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: menu, onOpen: (_) {}),
            ),
          ),
        ),
      );
      // Tek kare: StaggeredEntry hareket azaltmada hemen tamamdır (opaklık 1).
      final opacities = t.widgetList<Opacity>(find.descendant(of: _card(SirketMenuItem.kapilar), matching: find.byType(Opacity)));
      expect(opacities, isEmpty);
      final entry = find.ancestor(of: _card(SirketMenuItem.kapilar), matching: find.byType(Opacity));
      for (final o in t.widgetList<Opacity>(entry)) {
        expect(o.opacity, 1.0);
      }
      // Kararlı durumda ticker yok: pumpAndSettle biter.
      await t.pumpAndSettle();
    });
  });

  group('taşma matrisi', () {
    testWidgets('sakin vitrini (borç + hızlı işlemler + tüm modüller): 320-820 dp x 1,0-2,0 yazı x açık/koyu', (t) async {
      final menu = _items(UserRole.apartmentOwner, extras: _residentExtras);
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          _view(
            role: UserRole.apartmentOwner,
            audience: ShowcaseAudience.resident,
            items: menu,
            badges: {SirketMenuItem.duyurular: 120, SirketMenuItem.ziyaretcilerim: 3},
            fetch: () async => _debt(32500000, overdue: 100000, due: DateTime(2026, 11, 10)),
            siteName: 'Çok Uzun Adlı Güneşli Vadi Konutları Sitesi 2. Etap',
            onOpen: (_) {},
            onHelp: () {},
          ),
          width: width,
          height: 900,
          scale: scale,
          dark: dark,
        );
        await t.pump(const Duration(milliseconds: 200));
        expect(t.takeException(), isNull, reason: '${width.toInt()} x$scale ${dark ? 'koyu' : 'açık'}');
      });
    });

    testWidgets('yönetici vitrini (odak barı + tüm modüller + ikincil satır): tüm hücreler', (t) async {
      final menu = _items(UserRole.superUser, extras: {..._managerExtras, SirketMenuItem.kisiler});
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          _view(
            role: UserRole.superUser,
            audience: ShowcaseAudience.admin,
            items: menu,
            badges: {SirketMenuItem.modulTalepleri: 12, SirketMenuItem.siteBasvurulari: 3},
            onOpen: (_) {},
            onHelp: () {},
          ),
          width: width,
          height: 900,
          scale: scale,
          dark: dark,
        );
        await t.pump(const Duration(milliseconds: 200));
        expect(t.takeException(), isNull, reason: '${width.toInt()} x$scale ${dark ? 'koyu' : 'açık'}');
      });
    });

    testWidgets('bireysel vitrin ve selamlama (hata) hâli: 320 dp x 2,0 yazı', (t) async {
      for (final dark in const [false, true]) {
        await pumpAt(
          t,
          _view(
            role: UserRole.individual,
            audience: ShowcaseAudience.individual,
            items: _items(UserRole.individual, extras: {SirketMenuItem.kapilar}),
            onOpen: (_) {},
          ),
          width: 320,
          height: 640,
          scale: 2.0,
          dark: dark,
        );
        await pumpAt(
          t,
          _view(
            role: UserRole.apartmentOwner,
            audience: ShowcaseAudience.resident,
            items: _items(UserRole.apartmentOwner, extras: _residentExtras),
            fetch: () async => throw StateError('ağ'),
            onOpen: (_) {},
          ),
          width: 320,
          height: 640,
          scale: 2.0,
          dark: dark,
        );
        await t.pump(const Duration(milliseconds: 200));
        expect(t.takeException(), isNull);
      }
    });
  });

  testWidgets('tasarım kuralları: kart beyaz yüzey + ince çerçeve, gölge yok (açık tema)', (t) async {
    final menu = _items(UserRole.apartmentOwner, extras: _residentExtras);
    await _pump(t, _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: menu, onOpen: (_) {}));
    final material = t.widget<Material>(_card(SirketMenuItem.belgeler));
    expect(material.color, const Color(0xFFFFFFFF));
    expect(material.elevation, 0);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side.color, const Color(0xFFE2E8F0));
    expect(shape.side.width, 1);
  });
}
