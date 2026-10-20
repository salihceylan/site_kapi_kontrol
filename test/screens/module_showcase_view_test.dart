// Panel modül vitrini (ModuleShowcaseView): kartlar, fail-closed, hero kart, hızlı işlemler, odak barı, duyarlı ızgara,
// erişilebilirlik (ekran okuyucu etiketleri, klavye odağı, dokunma hedefi), tasarım belirteçleri (AppShowcaseColors,
// koyu kutu yalnız eylem isteyen yerde, açık temada düz zemin) ve taşma matrisi (320/360/412/820 x yazı ölçeği
// 1,0/1,5/2,0 x açık/koyu; 320 dp'de 1,15 ve 1,3 de).
//
// Vitrin yan menünün hesapladığı öğe listesinden ([YanMenu.visibleItems]) türer: listede olmayan modülün kartı olamaz.
// Vitrin her testte ana sayfanın GERÇEK gövde genişliğiyle kurulur ([_page]: 16 / 20 dp kenar boşluğu).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/design/module_art.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';

/// WCAG 2.x kontrast oranı (saydam ön plan opak [background] üstüne bindirilir).
double _contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Koyu temanın sayfa zemini tonları (üst / orta / alt).
List<Color> get _darkPage => (AppDecorations.pageBackgroundDark.gradient! as LinearGradient).colors;

/// [owner] altındaki ilk yüzeyin (odak kutusu ya da düz kart) dekorasyonu.
BoxDecoration _surfaceOf(WidgetTester t, Finder owner) =>
    t.widget<DecoratedBox>(find.descendant(of: owner, matching: find.byType(DecoratedBox)).first).decoration
        as BoxDecoration;

const ValueKey<String> _heroDebt = ValueKey<String>('panel_hero_borc');
const ValueKey<String> _heroGreeting = ValueKey<String>('panel_hero_selam');
const ValueKey<String> _heroGo = ValueKey<String>('panel_hero_borcuma_git');
const ValueKey<String> _focusRing = ValueKey<String>('panel_hap_odak');

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

/// Ana sayfanın gövde yerleşimi (`HomePage._buildScrollBody`): ekran < 600 dp iken 16, değilse 20 dp yan boşluk,
/// içerik en çok 1100 dp. Vitrin testlerde de GERÇEK sayfa genişliğiyle kurulur (320 dp ekranda vitrine 288 dp kalır).
Widget _page(Widget child) => LayoutBuilder(
  builder: (context, constraints) {
    final pad = constraints.maxWidth < 600 ? 16.0 : 20.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  },
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
}) => _page(
  ModuleShowcaseView(
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

    testWidgets(
        'ekran okuyucu: borç kartı görünen TÜM satırları okur (site / daire, tutar, vadesi geçen, sıradaki vade); '
        'tutarlar Borcum ekranındaki gibi "lira" okunuşuyla; "Borcum\'a git" ayrı düğme', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          fetch: () async => _debt(325000, overdue: 100000, due: DateTime(2026, 11, 10)),
        ),
      );
      expect(
        t.getSemantics(find.byKey(const ValueKey<String>('panel_hero_ozet'))),
        isSemantics(
          label: 'Güneş Sitesi, A Blok / D:3. Güncel borcunuz: üç bin iki yüz elli lira. '
              'Vadesi geçen: bin lira. Sıradaki vade: 10.11.2026.',
        ),
      );
      // Rakam yığını ("3.250,00 ₺") hiçbir düğümde okunmaz; düğmenin adı görünen metindir.
      expect(find.bySemanticsLabel(RegExp(r'\d\.\d{3},\d{2}')), findsNothing);
      expect(
        t.getSemantics(find.byKey(_heroGo)),
        isSemantics(label: "Borcum'a git", isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('ekran okuyucu: çok daireli sakinde site adı (modül verisinden) ve alacak satırı da okunur', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: items,
          onOpen: (_) {},
          siteName: 'Güneş Sitesi',
          fetch: () async => MyFinance(
            items: [
              MyFinanceApartment(
                siteCode: 1,
                siteName: 'Güneş Sitesi',
                apartmentId: 5,
                label: 'D:3',
                blockName: 'A Blok',
                balanceMinor: 120000,
                overdueMinor: 20050,
              ),
              MyFinanceApartment(
                siteCode: 1,
                siteName: 'Güneş Sitesi',
                apartmentId: 6,
                label: 'D:4',
                blockName: 'A Blok',
                balanceMinor: -4500,
              ),
            ],
          ),
        ),
      );
      expect(find.text('Alacağınız: 45,00 ₺'), findsOneWidget);
      expect(
        t.getSemantics(find.byKey(const ValueKey<String>('panel_hero_ozet'))),
        isSemantics(
          label: 'Güneş Sitesi. Güncel borcunuz: bin iki yüz lira. Vadesi geçen: iki yüz lira elli kuruş. '
              'Alacağınız: kırk beş lira.',
        ),
      );
      handle.dispose();
    });

    testWidgets(
        'koyu kart YALNIZ ödenecek borçta; borç yok, alacak, selamlama ve hata hâli düz beyaz kart (ince çerçeve, '
        'gölge yok) ve ana düğme koyu (#0F172A)', (t) async {
      Widget view(Future<MyFinance> Function() fetch) => _view(
            role: UserRole.apartmentOwner,
            audience: ShowcaseAudience.resident,
            items: items,
            onOpen: (_) {},
            fetch: fetch,
          );
      Color? pill() => t.widget<Material>(find.byKey(_heroGo)).color;
      final darkBox = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == AppShowcaseColors.focus,
      );

      await _pump(t, view(() async => _debt(325000)));
      expect(_surfaceOf(t, find.byKey(_heroDebt)).color, AppShowcaseColors.focus, reason: 'ödenecek borç: koyu kutu');
      expect(pill(), AppShowcaseColors.onFocus, reason: 'koyu kutuda açık hap');

      for (final (name, finance) in [('borç yok', _debt(0)), ('alacak', _debt(-4500))]) {
        await _pump(t, view(() async => finance));
        final plain = _surfaceOf(t, find.byKey(_heroDebt));
        expect(plain.color, AppShowcaseColors.card, reason: name);
        expect((plain.border! as Border).top.color, AppShowcaseColors.cardBorder, reason: name);
        expect(plain.boxShadow, isNull, reason: '$name: gölge yok');
        expect(pill(), AppShowcaseColors.focus, reason: '$name: ana düğme koyu');
        expect(darkBox, findsNothing, reason: '$name: eylem istemeyen durumda koyu kutu yok');
      }

      final gate = Completer<MyFinance>();
      await _pump(t, view(() => gate.future));
      expect(_surfaceOf(t, find.byKey(_heroGreeting)).color, AppShowcaseColors.card, reason: 'selamlama');
      expect(darkBox, findsNothing);
      gate.completeError(StateError('ağ yok'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Borç bilginiz şu an alınamadı.'), findsOneWidget);
      expect(_surfaceOf(t, find.byKey(_heroGreeting)).color, AppShowcaseColors.card, reason: 'hata hâli');
      expect(pill(), AppShowcaseColors.focus);
      expect(darkBox, findsNothing);
      // Beyaz kartta kehribar nokta koyu kehribar kenarlıdır (dolgu beyazda 3:1'in altında).
      final dot = t.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(_heroGreeting),
          matching: find.byKey(const ValueKey<String>('panel_durum_noktasi')),
        ),
      );
      final dotDeco = dot.decoration as BoxDecoration;
      expect(dotDeco.color, AppShowcaseColors.statusWarn);
      expect((dotDeco.border! as Border).top.color, AppTone.warning.a);
    });

    testWidgets('koyu tema: borç kartı lacivert odak kutusu; borç yok ve selamlama palet yüzeyi; düğme açık hap', (t) async {
      Widget view(Future<MyFinance> Function() fetch) => _view(
            role: UserRole.apartmentOwner,
            audience: ShowcaseAudience.resident,
            items: items,
            onOpen: (_) {},
            fetch: fetch,
          );
      Color? pill() => t.widget<Material>(find.byKey(_heroGo)).color;

      await _pump(t, view(() async => _debt(325000)), dark: true);
      expect(_surfaceOf(t, find.byKey(_heroDebt)).color, AppShowcaseColors.focusDark);
      expect(pill(), AppShowcaseColors.onFocus);

      await _pump(t, view(() async => _debt(0)), dark: true);
      expect(_surfaceOf(t, find.byKey(_heroDebt)).color, AppPalette.dark.surface);
      expect(pill(), AppShowcaseColors.onFocus, reason: 'koyu temada ana düğme açık hap');

      await _pump(t, view(() async => throw StateError('ağ')), dark: true);
      expect(_surfaceOf(t, find.byKey(_heroGreeting)).color, AppPalette.dark.surface);
      expect(pill(), AppShowcaseColors.onFocus);
      final dot = t.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(_heroGreeting),
          matching: find.byKey(const ValueKey<String>('panel_durum_noktasi')),
        ),
      );
      expect((dot.decoration as BoxDecoration).border, isNull, reason: 'koyu kartta kehribar nokta zaten >= 3:1');
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

    testWidgets(
        'ekran okuyucu: her düğmenin adı satırın bağlamlı etiketidir ("2 bekleyen site başvurusu. İncele"); iki "İncele" '
        'ayrılır, satır metni ayrıca okunmaz', (t) async {
      final handle = t.ensureSemantics();
      final menu = _items(UserRole.superUser, extras: {SirketMenuItem.kapilar});
      const badges = <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 4, SirketMenuItem.siteBasvurulari: 2};
      await _pump(
        t,
        _view(role: UserRole.superUser, audience: ShowcaseAudience.admin, items: menu, badges: badges, onOpen: (_) {}),
      );
      final entries = buildFocusEntries(menuItems: menu, badgeCounts: badges);
      expect(entries, hasLength(2));
      for (final e in entries) {
        expect(e.action, 'İncele');
        expect(
          t.getSemantics(find.byKey(ValueKey<String>('panel_odak_${e.item.name}'))),
          isSemantics(label: e.semanticLabel, isButton: true, hasTapAction: true),
          reason: '${e.item}',
        );
        expect(find.bySemanticsLabel(e.text), findsNothing, reason: '${e.item}: satır metni iki kez okunmaz');
      }
      expect(
        t.getSemantics(find.byKey(const ValueKey<String>('panel_odak_siteBasvurulari'))),
        isSemantics(label: '2 bekleyen site başvurusu. İncele', isButton: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel('İncele'), findsNothing, reason: 'yalın "İncele" adlı düğme yok');
      expect(find.bySemanticsLabel('Dikkat edilmesi gereken 2 iş var'), findsOneWidget);
      handle.dispose();
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

  group('klavye odağı ve dokunma hedefi', () {
    final adminMenu = _items(UserRole.superUser, extras: {SirketMenuItem.kapilar});
    const adminBadges = <SirketMenuItem, int>{SirketMenuItem.modulTalepleri: 4, SirketMenuItem.siteBasvurulari: 2};
    final residentMenu = _items(UserRole.apartmentOwner, extras: _residentExtras);

    Widget admin({VoidCallback? onHelp}) => _view(
          role: UserRole.superUser,
          audience: ShowcaseAudience.admin,
          items: adminMenu,
          badges: adminBadges,
          onOpen: (_) {},
          onHelp: onHelp,
        );
    Widget resident(Future<MyFinance> Function() fetch, {VoidCallback? onHelp}) => _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: residentMenu,
          fetch: fetch,
          onOpen: (_) {},
          onHelp: onHelp,
        );

    Future<void> tab(WidgetTester t) async {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }

    Future<void> unfocus(WidgetTester t) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump();
    }

    /// Odak halkası [pill] düğmesinin çevresinde mi (aynı Stack); halkanın rengi.
    Color ringAround(WidgetTester t, Key pill, String reason) {
      final ring = find.byKey(_focusRing);
      expect(ring, findsOneWidget, reason: '$reason: odak halkası');
      final stack = find.ancestor(of: ring, matching: find.byType(Stack)).first;
      expect(find.descendant(of: stack, matching: find.byKey(pill)), findsOneWidget, reason: '$reason: halka odaklı düğmede');
      final shape = (t.widget<DecoratedBox>(ring).decoration as ShapeDecoration).shape as StadiumBorder;
      expect(shape.side.width, greaterThanOrEqualTo(2), reason: reason);
      return shape.side.color;
    }

    testWidgets(
        'koyu bar / kart üstündeki açık düğmelerde ve düz karttaki ana düğmede klavye odağı iki temada görünür '
        '(halka yanındaki yüzeye >= 3:1; hapın kendi odak rengi)', (t) async {
      final first = buildFocusEntries(menuItems: adminMenu, badgeCounts: adminBadges).first;
      final firstKey = ValueKey<String>('panel_odak_${first.item.name}');
      for (final dark in const [false, true]) {
        final mode = dark ? 'koyu' : 'açık';
        final box = dark ? AppShowcaseColors.focusDark : AppShowcaseColors.focus;

        // Yönetici dikkat barı: ilk Tab ilk satırın düğmesine gelir.
        await _pump(t, admin(), dark: dark);
        expect(find.byKey(_focusRing), findsNothing, reason: '$mode: odak yokken halka yok');
        await tab(t);
        expect(_contrast(ringAround(t, firstKey, '$mode bar'), box), greaterThanOrEqualTo(3.0), reason: '$mode bar');
        final ink = t.widget<InkWell>(find.descendant(of: find.byKey(firstKey), matching: find.byType(InkWell)));
        expect(ink.focusColor, isNotNull, reason: 'temanın varsayılan odak rengi açık hapta görünmez');
        expect(ink.hoverColor, isNotNull);
        await unfocus(t);
        expect(find.byKey(_focusRing), findsNothing, reason: '$mode: odak ayrılınca halka kalkar');

        // Sakin borç kartı (koyu kutu): "Borcum'a git".
        await _pump(t, resident(() async => _debt(325000)), dark: dark);
        await tab(t);
        expect(_contrast(ringAround(t, _heroGo, '$mode borç'), box), greaterThanOrEqualTo(3.0), reason: '$mode borç');
        await unfocus(t);

        // Düz kart (borç bilgisi alınamadı): açıkta koyu hap, koyuda açık hap; halka kart yüzeyine >= 3:1.
        await _pump(t, resident(() async => throw StateError('ağ')), dark: dark);
        await tab(t);
        final card = dark ? AppPalette.dark.surface : AppShowcaseColors.card;
        expect(_contrast(ringAround(t, _heroGo, '$mode düz kart'), card), greaterThanOrEqualTo(3.0), reason: mode);
        await unfocus(t);
      }
    });

    testWidgets(
        'hap düğmeler ve "Hesap ve ayarlar" düğmeleri en az 48 dp; Android dokunma hedefi ve etiket yönergeleri '
        '(sakin ve yönetici vitrini)', (t) async {
      final handle = t.ensureSemantics();
      void atLeast48(Key key) {
        final size = t.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(48), reason: '$key yükseklik');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$key genişlik');
      }

      await _pump(t, resident(() async => _debt(325000), onHelp: () {}));
      atLeast48(_heroGo);
      atLeast48(const ValueKey<String>('panel_ikincil_profilim'));
      atLeast48(const ValueKey<String>('panel_ikincil_yardim'));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));

      await _pump(t, admin(onHelp: () {}));
      for (final e in buildFocusEntries(menuItems: adminMenu, badgeCounts: adminBadges)) {
        atLeast48(ValueKey<String>('panel_odak_${e.item.name}'));
      }
      atLeast48(const ValueKey<String>('panel_ikincil_yardim'));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('tasarım belirteçleri ve zemin', () {
    test('vitrin renkleri işverenin tablosundaki değişkenlerdir (zemin, kart + kenar, metin, odak, durum noktaları)', () {
      expect(AppShowcaseColors.background, const Color(0xFFF8FAFC));
      expect(AppShowcaseColors.card, const Color(0xFFFFFFFF));
      expect(AppShowcaseColors.cardBorder, const Color(0xFFE2E8F0));
      expect(AppShowcaseColors.text, const Color(0xFF475569));
      expect(AppShowcaseColors.focus, const Color(0xFF0F172A));
      expect(AppShowcaseColors.statusOk, const Color(0xFF10B981));
      expect(AppShowcaseColors.statusWarn, const Color(0xFFF59E0B));
      expect(AppShowcaseColors.statusCrit, const Color(0xFFE11D48));
    });

    test('kontrast: metin >= 4,5:1; nokta, kenar ve odak halkası >= 3:1; kart çerçevesi düz zeminde seçilir', () {
      for (final bg in const [AppShowcaseColors.card, AppShowcaseColors.background]) {
        expect(_contrast(AppShowcaseColors.text, bg), greaterThanOrEqualTo(4.5), reason: 'normal metin');
      }
      // Odak kutusu (açıkta gece kömürü, koyuda lacivert) üstünde metin, ikincil metin, durum noktaları, odak halkası.
      for (final box in const [AppShowcaseColors.focus, AppShowcaseColors.focusDark]) {
        expect(_contrast(AppShowcaseColors.onFocus, box), greaterThanOrEqualTo(4.5));
        expect(_contrast(AppShowcaseColors.onFocusMuted, box), greaterThanOrEqualTo(4.5));
        expect(_contrast(AppShowcaseColors.statusWarn, box), greaterThanOrEqualTo(3.0));
        expect(_contrast(AppShowcaseColors.statusCrit, box), greaterThanOrEqualTo(3.0));
        expect(_contrast(AppTone.primary.inkDark, box), greaterThanOrEqualTo(3.0));
      }
      // Hap metni; açık kartta koyu hapın sınırı ve halkası; koyu temanın düz kartında açık hapın halkası.
      expect(_contrast(AppShowcaseColors.focus, AppShowcaseColors.onFocus), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppShowcaseColors.focus, AppShowcaseColors.card), greaterThanOrEqualTo(3.0));
      expect(_contrast(AppTone.primary.inkLight, AppShowcaseColors.card), greaterThanOrEqualTo(3.0));
      expect(_contrast(AppTone.primary.inkDark, AppPalette.dark.surface), greaterThanOrEqualTo(3.0));
      // Rozetin mercan noktası soluk rozet zemininde.
      expect(_contrast(AppShowcaseColors.statusCrit, AppPalette.light.surfaceMuted), greaterThanOrEqualTo(3.0));
      expect(_contrast(AppShowcaseColors.statusCrit, AppPalette.dark.surfaceMuted), greaterThanOrEqualTo(3.0));
      // Beyaz kartta kehribar nokta tek başına 3:1'in altında: koyu kehribar kenarı >= 3:1; koyu temanın kartında gerekmez.
      expect(_contrast(AppShowcaseColors.statusWarn, AppShowcaseColors.card), lessThan(3.0));
      expect(_contrast(AppTone.warning.a, AppShowcaseColors.card), greaterThanOrEqualTo(3.0));
      expect(_contrast(AppShowcaseColors.statusWarn, AppPalette.dark.surface), greaterThanOrEqualTo(3.0));
      // Koyu temada odak kutusunun kenarı zemine ve kutuya >= 3:1.
      for (final page in _darkPage) {
        expect(_contrast(AppTone.primary.hue, page), greaterThanOrEqualTo(3.0));
      }
      expect(_contrast(AppTone.primary.hue, AppShowcaseColors.focusDark), greaterThanOrEqualTo(3.0));
      // Kart çerçevesi düz zeminde görünür (eski gradyanın alt tonu çerçeveyle AYNIYDI: 1,0:1).
      final oldBottom = (AppDecorations.pageBackgroundLight.gradient! as LinearGradient).colors.last;
      expect(_contrast(AppShowcaseColors.cardBorder, oldBottom), lessThan(1.01));
      expect(_contrast(AppShowcaseColors.cardBorder, AppShowcaseColors.background), greaterThanOrEqualTo(1.15));
    });

    testWidgets(
        'açık temada vitrin zemini DÜZ #F8FAFC ve görünen alanın tamamını (kenar boşlukları, üst / alt) kaplar; kartlar '
        'beyaz + #E2E8F0 çerçeve; koyu temada zemin boyanmaz', (t) async {
      const zemin = ValueKey<String>('panel_vitrin_zemin');
      final menu = _items(UserRole.apartmentOwner, extras: _residentExtras);
      Widget view() => _view(role: UserRole.apartmentOwner, audience: ShowcaseAudience.resident, items: menu, onOpen: (_) {});
      for (final (width, height) in const [(320.0, 640.0), (1366.0, 768.0)]) {
        await _pump(t, view(), width: width, height: height);
        Rect? painted;
        Color? color;
        expect(
          t.renderObject(find.byKey(zemin)),
          paints
            ..something((method, args) {
              if (method != #drawRect) return false;
              painted = args[0] as Rect;
              color = (args[1] as Paint).color;
              return true;
            }),
        );
        // Paint rengi kayan nokta (float32) saklar: 8 bitlik ARGB değeriyle karşılaştırılır.
        expect(color?.toARGB32(), AppShowcaseColors.background.toARGB32(), reason: '$width');
        final onScreen = painted!.shift(t.getTopLeft(find.byKey(zemin)));
        expect(onScreen.left, lessThanOrEqualTo(0), reason: '$width: sol kenar boşluğu');
        expect(onScreen.top, lessThanOrEqualTo(0), reason: '$width: üst');
        expect(onScreen.right, greaterThanOrEqualTo(width), reason: '$width: sağ kenar boşluğu');
        expect(onScreen.bottom, greaterThanOrEqualTo(height), reason: '$width: alt');
        final card = t.widget<Material>(_card(SirketMenuItem.belgeler));
        expect(card.color, AppShowcaseColors.card);
        expect((card.shape! as RoundedRectangleBorder).side.color, AppShowcaseColors.cardBorder);
      }
      await _pump(t, view(), dark: true);
      expect(t.renderObject(find.byKey(zemin)), paintsNothing);
    });

    testWidgets('koyu temada odak kutusu (dikkat barı, borç kartı) zeminden ayrışır: lacivert yüzey + >= 3:1 mavi kenar', (t) async {
      await _pump(
        t,
        _view(
          role: UserRole.superUser,
          audience: ShowcaseAudience.admin,
          items: _items(UserRole.superUser),
          badges: {SirketMenuItem.siteBasvurulari: 1},
          onOpen: (_) {},
        ),
        dark: true,
      );
      final bar = _surfaceOf(t, find.byKey(const ValueKey<String>('panel_odak_bar')));
      await _pump(
        t,
        _view(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          items: _items(UserRole.apartmentOwner, extras: _residentExtras),
          fetch: () async => _debt(325000),
          onOpen: (_) {},
        ),
        dark: true,
      );
      final hero = _surfaceOf(t, find.byKey(_heroDebt));
      for (final (name, box) in [('dikkat barı', bar), ('borç kartı', hero)]) {
        expect(box.color, AppShowcaseColors.focusDark, reason: name);
        final edge = (box.border! as Border).top;
        expect(edge.width, greaterThanOrEqualTo(1.5), reason: name);
        expect(_contrast(edge.color, box.color!), greaterThanOrEqualTo(3.0), reason: '$name: kenar / kutu');
        for (final page in _darkPage) {
          expect(box.color, isNot(page), reason: '$name: kutu zeminle aynı renk değil');
          expect(_contrast(edge.color, page), greaterThanOrEqualTo(3.0), reason: '$name: kenar / zemin');
        }
      }
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

    testWidgets(
        'gerçek sayfa genişliği: 320 dp ekranda vitrine 288 dp kalır; yazı 1,0 ve 1,15 İKİ sütun (kart içi ~114 dp, '
        '99+ rozetiyle), 1,3-2,0 tek sütun; taşma yok (sakin ve yönetici, açık / koyu)', (t) async {
      final cases = <(String, UserRole, ShowcaseAudience, List<SirketMenuItem>, Future<MyFinance> Function()?)>[
        (
          'sakin',
          UserRole.apartmentOwner,
          ShowcaseAudience.resident,
          _items(UserRole.apartmentOwner, extras: _residentExtras),
          () async => _debt(32500000, overdue: 100000, due: DateTime(2026, 11, 10)),
        ),
        (
          'yönetici',
          UserRole.superUser,
          ShowcaseAudience.admin,
          _items(UserRole.superUser, extras: {..._managerExtras, SirketMenuItem.kisiler}),
          null,
        ),
      ];
      for (final (name, role, audience, menu, fetch) in cases) {
        final grid = buildShowcaseModel(menuItems: menu, role: role).grid;
        final first = grid[0].item;
        final second = grid[1].item;
        for (final (scale, columns) in const [(1.0, 2), (1.15, 2), (1.3, 1), (1.5, 1), (2.0, 1)]) {
          for (final dark in const [false, true]) {
            final cell = '$name 320 x$scale ${dark ? 'koyu' : 'açık'}';
            await pumpAt(
              t,
              _view(
                role: role,
                audience: audience,
                items: menu,
                // İlk iki kartta en geniş rozet ("99+"); yönetici barında iki satır.
                badges: {first: 150, second: 150, SirketMenuItem.modulTalepleri: 12, SirketMenuItem.siteBasvurulari: 3},
                fetch: fetch,
                siteName: 'Çok Uzun Adlı Güneşli Vadi Konutları Sitesi 2. Etap',
                onOpen: (_) {},
                onHelp: () {},
              ),
              width: 320,
              height: 900,
              scale: scale,
              dark: dark,
            );
            await t.pump(const Duration(milliseconds: 200));
            expect(t.takeException(), isNull, reason: cell);
            expect(t.getSize(find.byKey(const ValueKey<String>('panel_vitrin'))).width, 288, reason: '$cell: 320 - 2 x 16');
            expect(showcaseColumns(288, scale), columns, reason: cell);
            final a = t.getTopLeft(_card(first)).dy;
            final b = t.getTopLeft(_card(second)).dy;
            if (columns == 2) {
              expect(b, a, reason: '$cell: iki sütun (ilk iki kart aynı satırda)');
            } else {
              expect(b, greaterThan(a), reason: '$cell: tek sütun');
            }
            // Rozet kartın içinde kalır (sığmayınca görselin altına iner, kartı taşırmaz).
            final card = t.getRect(_card(first));
            final badge = t.getRect(
              find.descendant(of: _card(first), matching: find.byKey(const ValueKey<String>('panel_kart_rozet'))),
            );
            expect(badge.left >= card.left && badge.right <= card.right + 0.01, isTrue, reason: '$cell: rozet kartta');
          }
        }
      }
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
