// FAZ 5 / A2-G6: çekmece (YanMenu) taşma + tasarım testleri.
//
// AGENTS.md kural 6: hiçbir ekranda taşma olmaz. Matris: 320x640 x2,0 ve 360x640 x1,5, her biri açık
// ve koyu temada; ayrıca yatay/kısa ekranlar ve geniş ekranlar. D13: rol gradyanlı başlık (beyaz
// metin >= 4,5:1), düz beyaz logo halkası, `ListTile` korunan seçili-hap menü öğesi + 4x22 çubuk,
// ilk 8 öğe StaggeredEntry, hareket azaltma. Davranış (onSelect/onToggleMode/onLogout) ve metinler
// değişmez.
//
// Not: widget testleri Ahem yazı tipiyle çalışır (her harf 1 em genişliğinde): satır sarma gerçek
// cihazdan daha serttir; geçen taşma testi gerçek yazı tipinde de geçer.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../design/harness.dart';

/// Bir çekmece yapılandırması (rol + mod + seçili öğe + başlık metinleri).
class _Cfg {
  const _Cfg(
    this.name,
    this.role,
    this.itemCount, {
    this.selected = SirketMenuItem.dashboard,
    this.resident = false,
    this.toggle = false,
    this.fullName = 'Ali Veli',
    this.email = 'ali@example.com',
  });

  final String name;
  final UserRole role;

  /// Menü öğesi sayısı (mod geçişi ve "Çıkış Yap" hariç).
  final int itemCount;
  final SirketMenuItem selected;
  final bool resident;
  final bool toggle;
  final String fullName;
  final String email;

  /// Ekrandaki ListTile sayısı: öğeler + (geçiş) + çıkış.
  int get tileCount => itemCount + (toggle ? 1 : 0) + 1;

  /// Seçili öğenin ListTile sırası (geçiş öğesi varsa başta).
  int selectedTileIndex(List<SirketMenuItem> order) =>
      order.indexOf(selected) + (toggle ? 1 : 0);
}

const String _longName = 'Muhammet Alperen Yıldırım Kaya';
const String _longEmail =
    'muhammet.alperen.yildirim.kaya@ornek-alan-adi.com.tr';

const List<_Cfg> _cfgs = <_Cfg>[
  _Cfg(
    'süper kullanıcı (11 öğe)',
    UserRole.superUser,
    11,
    selected: SirketMenuItem.siteler,
  ),
  _Cfg(
    'site yöneticisi + mod geçişi',
    UserRole.siteManager,
    6,
    selected: SirketMenuItem.siteler,
    toggle: true,
  ),
  _Cfg(
    'site yöneticisi sakin modu',
    UserRole.siteManager,
    4,
    selected: SirketMenuItem.ellerSerbest,
    resident: true,
    toggle: true,
  ),
  _Cfg(
    'daire kullanıcısı (uzun ad/e-posta)',
    UserRole.apartmentOwner,
    4,
    selected: SirketMenuItem.katilimVeKurulum,
    fullName: _longName,
    email: _longEmail,
  ),
  _Cfg(
    'bireysel (uzun ad/e-posta)',
    UserRole.individual,
    3,
    selected: SirketMenuItem.profilim,
    fullName: _longName,
    email: _longEmail,
  ),
  _Cfg(
    'bireysel çift mod',
    UserRole.individual,
    6,
    selected: SirketMenuItem.kayitliCihazlar,
    toggle: true,
  ),
];

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

/// Yatay / kısa ekranlar (< 480 dp): başlık + liste + sürüm tek kaydırma alanında akar (compact).
const List<(double, double, double)> _shortCells = <(double, double, double)>[
  (640, 320, 2.0),
  (640, 360, 1.5),
  (568, 320, 1.5),
];

/// Geniş ekranlar (telefon 412x915 ve tablet/masaüstü 820x1180) varsayılan yazıda.
const List<(double, double, double)> _wideCells = <(double, double, double)>[
  (412, 915, 1.0),
  (820, 1180, 1.0),
];

final Finder _tiles = find.byType(ListTile);
final Finder _bars = find.byKey(
  const ValueKey<String>('yan_menu_secili_cubuk'),
);

YanMenu _menu(
  _Cfg c, {
  ValueChanged<SirketMenuItem>? onSelect,
  VoidCallback? onLogout,
  VoidCallback? onToggle,
}) {
  return YanMenu(
    fullName: c.fullName,
    userEmail: c.email,
    role: c.role,
    selectedItem: c.selected,
    isResidentMode: c.resident,
    canToggleMode: c.toggle,
    onToggleMode: c.toggle ? (onToggle ?? () {}) : null,
    onSelect: onSelect ?? (_) {},
    onLogout: onLogout ?? () {},
  );
}

/// `pumpAt` düzeneğiyle (ölçü/ölçek/tema; giriş animasyonları biter) çekmeceyi kurar.
Future<void> _pumpMenu(
  WidgetTester t,
  _Cfg c, {
  required double width,
  required double height,
  required double scale,
  bool dark = false,
  bool reduce = false,
  ValueChanged<SirketMenuItem>? onSelect,
  VoidCallback? onLogout,
  VoidCallback? onToggle,
  GlobalKey? boundaryKey,
}) {
  final menu = SizedBox(
    height: height,
    child: _menu(c, onSelect: onSelect, onLogout: onLogout, onToggle: onToggle),
  );
  return pumpAt(
    t,
    boundaryKey == null ? menu : RepaintBoundary(key: boundaryKey, child: menu),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

/// Giriş animasyonunu da gözlemlemek için: kurulumdan sonra ilerletme YOK (yalnız ilk kare).
Future<void> _pumpRaw(
  WidgetTester t,
  _Cfg c, {
  double width = 360,
  double height = 640,
  bool dark = false,
  bool reduce = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    harnessApp(
      SizedBox(height: height, child: _menu(c)),
      dark: dark,
      reduce: reduce,
    ),
  );
}

/// Gerçek `Scaffold.drawer` + `openDrawer()` (e2e/HomePage ile aynı yol).
Future<void> _pumpScaffoldDrawer(
  WidgetTester t,
  YanMenu menu, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
  bool open = true,
  GlobalKey? boundaryKey,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) {
        final app = MediaQuery(
          data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduce,
          ),
          child: child!,
        );
        return boundaryKey == null
            ? app
            : RepaintBoundary(key: boundaryKey, child: app);
      },
      home: Scaffold(drawer: menu, body: const SizedBox.expand()),
    ),
  );
  if (!open) return;
  t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull);
}

/// WCAG 2.x kontrast oranı; saydam ön plan [bg] üzerine bindirilir.
double _contrast(Color fg, Color bg) {
  final composed = Color.alphaBlend(fg, bg);
  final l1 = composed.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

AppPalette _palette(WidgetTester t) => t.element(find.byType(YanMenu)).palette;

/// [tileIndex]. ListTile'ı saran hap (AnimatedContainer): seçilide ton zemini, değilse aynı
/// rengin saydamı.
BoxDecoration _pill(WidgetTester t, int tileIndex) =>
    t
            .widget<AnimatedContainer>(
              find
                  .ancestor(
                    of: _tiles.at(tileIndex),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

/// [key] sınırındaki görüntüden mantıksal [point]'teki rengi okur (DPR 1,0; [point] sınırın
/// sol-üstüne göredir). Boyamanın GERÇEKTEN yapıldığını sınar (widget ağacı bunu göstermez).
Future<Color> _pixel(WidgetTester t, GlobalKey key, Offset point) async {
  late Color color;
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final i = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
    color = Color.fromARGB(
      data!.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
    image.dispose();
  });
  return color;
}

/// İki renk her kanalda en çok [tolerance]/255 farklıysa true.
bool _sameColor(Color a, Color b, {int tolerance = 2}) =>
    ((a.r - b.r).abs() * 255).round() <= tolerance &&
    ((a.g - b.g).abs() * 255).round() <= tolerance &&
    ((a.b - b.b).abs() * 255).round() <= tolerance;

double _entryOpacity(WidgetTester t, int i) => t
    .widget<Opacity>(
      find
          .descendant(
            of: find.byType(StaggeredEntry).at(i),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

/// Başlık metninin (ListTile.title) layout sırasında aldığı en büyük genişlik.
double _titleMaxWidth(WidgetTester t, String title) {
  final paragraph = find.descendant(
    of: find.widgetWithText(ListTile, title),
    matching: find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == title,
    ),
  );
  return t.renderObject<RenderParagraph>(paragraph).constraints.maxWidth;
}

/// Ekrandaki tüm ListTile'lar: >= 48 dp yüksek ve çekmece genişliği içinde.
void _expectTiles(WidgetTester t, _Cfg c) {
  expect(_tiles, findsNWidgets(c.tileCount));
  final drawer = t.getRect(find.byType(Drawer));
  for (var i = 0; i < c.tileCount; i++) {
    final rect = t.getRect(_tiles.at(i));
    expect(
      rect.height,
      greaterThanOrEqualTo(48),
      reason: '${c.name}: $i. öğe dokunma hedefi >= 48 dp',
    );
    expect(rect.left, greaterThanOrEqualTo(drawer.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(drawer.right + 0.01));
  }
}

String _cellName(double w, double h, double s, bool dark) =>
    '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

void main() {
  group('YanMenu taşma matrisi (320x640 x2,0 ve 360x640 x1,5; açık+koyu)', () {
    for (final c in _cfgs) {
      for (final (w, h, s) in _cells) {
        for (final dark in const <bool>[false, true]) {
          testWidgets(
            '${c.name}: ${_cellName(w, h, s, dark)}: taşma yok, tüm öğeler erişilebilir',
            (t) async {
              await _pumpMenu(t, c, width: w, height: h, scale: s, dark: dark);
              _expectTiles(t, c);
              expect(find.text(c.fullName), findsOneWidget);
              expect(find.text(c.email), findsOneWidget);
              expect(find.text(c.role.label), findsOneWidget);
              expect(find.text(AppConfig.versionDisplay), findsOneWidget);
              // Liste kayar: en alttaki ("Çıkış Yap") en büyük yazıda da erişilir.
              await t.ensureVisible(find.text('Çıkış Yap'));
              await t.pump();
              expect(find.text('Çıkış Yap').hitTestable(), findsOneWidget);
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('YanMenu yatay/kısa ve geniş ekranlar: taşma yok', () {
    for (final c in _cfgs) {
      for (final (w, h, s) in _shortCells) {
        for (final dark in const <bool>[false, true]) {
          testWidgets(
            '${c.name}: kısa ${_cellName(w, h, s, dark)}: tek kaydırma alanı, taşma yok, son öğeye inilir',
            (t) async {
              await _pumpMenu(t, c, width: w, height: h, scale: s, dark: dark);
              _expectTiles(t, c);
              // e2e sözleşmesi: çekmecede tek Scrollable (başlık da bunun içinde kayar).
              expect(
                find.descendant(
                  of: find.byType(Drawer),
                  matching: find.byType(Scrollable),
                ),
                findsOneWidget,
              );
              expect(t.widget<Text>(find.text(c.fullName)).maxLines, 2);
              await t.ensureVisible(find.text('Çıkış Yap'));
              await t.pump();
              expect(find.text('Çıkış Yap').hitTestable(), findsOneWidget);
              expect(t.takeException(), isNull);
            },
          );
        }
      }
      for (final (w, h, s) in _wideCells) {
        testWidgets(
          '${c.name}: geniş ${_cellName(w, h, s, false)}: taşma yok',
          (t) async {
            await _pumpMenu(t, c, width: w, height: h, scale: s);
            _expectTiles(t, c);
            expect(
              t.widget<Text>(find.text(c.fullName)).maxLines,
              2,
              reason: 'uzun ekranda ad en çok 2 satır',
            );
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  });

  group('YanMenu başlığı: rol gradyanı, beyaz metin, düz beyaz logo halkası', () {
    for (final role in UserRole.values) {
      for (final dark in const <bool>[false, true]) {
        testWidgets(
          '${role.name} ${dark ? 'koyu' : 'açık'}: gradyan role.tone.gradient; ad/e-posta tam beyaz >= 4,5:1; rozet >= 4,5:1',
          (t) async {
            final c = _Cfg('başlık', role, 3);
            await _pumpMenu(
              t,
              c,
              width: 360,
              height: 640,
              scale: 1.0,
              dark: dark,
            );
            final tone = role.tone;

            // Gradyan: tek başlık kutusu ve rolün tonu.
            final header = find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).gradient == tone.gradient,
            );
            expect(header, findsOneWidget);
            final decoration =
                t.widget<Container>(header).decoration! as BoxDecoration;
            expect(decoration.border, isNull, reason: 'alt çizgi/gölge yok');
            expect(decoration.boxShadow, isNull);

            // Ad ve e-posta TAM beyaz (alfa yok); gradyanın iki ucunda >= 4,5:1.
            for (final text in <String>[c.fullName, c.email]) {
              final style = t.widget<Text>(find.text(text)).style!;
              expect(style.color, Colors.white, reason: '"$text" tam beyaz');
              for (final stop in <Color>[
                tone.a,
                Color.lerp(tone.a, tone.b, 0.5)!,
                tone.b,
              ]) {
                expect(
                  _contrast(Colors.white, stop),
                  greaterThanOrEqualTo(4.5),
                  reason: '"$text" beyaz / $stop',
                );
              }
            }

            // Rol rozeti: metin beyaz, zemin gradyanın EN AÇIK ucunda bile >= 4,5:1.
            final badge = find
                .ancestor(
                  of: find.text(role.label),
                  matching: find.byType(Container),
                )
                .first;
            final badgeDecoration =
                t.widget<Container>(badge).decoration! as BoxDecoration;
            final badgeStyle = t.widget<Text>(find.text(role.label)).style!;
            expect(badgeStyle.color, Colors.white);
            for (final stop in <Color>[
              tone.a,
              Color.lerp(tone.a, tone.b, 0.5)!,
              tone.b,
            ]) {
              final fill = Color.alphaBlend(badgeDecoration.color!, stop);
              expect(
                _contrast(Colors.white, fill),
                greaterThanOrEqualTo(4.5),
                reason: 'rozet metni / rozet zemini ($stop üstünde)',
              );
            }
          },
        );
      }
    }

    testWidgets(
      'logo halkası düz beyaz, gölgesiz; avatar boyuta göre küçük çözülür',
      (t) async {
        await _pumpMenu(t, _cfgs.first, width: 360, height: 640, scale: 1.0);
        final ring = find
            .ancestor(
              of: find.byType(CircleAvatar),
              matching: find.byType(Container),
            )
            .first;
        final ringDecoration =
            t.widget<Container>(ring).decoration! as BoxDecoration;
        expect(ringDecoration.shape, BoxShape.circle);
        expect(ringDecoration.color, Colors.white);
        expect(ringDecoration.gradient, isNull);
        expect(ringDecoration.boxShadow, isNull, reason: 'gölge yok');

        final avatar = t.widget<CircleAvatar>(find.byType(CircleAvatar));
        expect(avatar.radius, 26);
        expect(avatar.backgroundColor, Colors.white);
        expect(avatar.backgroundImage, isA<ResizeImage>());
      },
    );

    testWidgets(
      'ad en çok 2 satır, e-posta tek satır (uzun metin kırpılır, taşmaz)',
      (t) async {
        await _pumpMenu(t, _cfgs[3], width: 320, height: 640, scale: 2.0);
        final name = t.widget<Text>(find.text(_longName));
        expect(name.maxLines, 2);
        expect(name.overflow, TextOverflow.ellipsis);
        final email = t.widget<Text>(find.text(_longEmail));
        expect(email.maxLines, 1);
        expect(email.overflow, TextOverflow.ellipsis);
        expect(t.takeException(), isNull);
      },
    );
  });

  group(
    'YanMenu kaydırma düzeni: uzun ekranda başlık sabit, kısa ekranda başlık da kayar',
    () {
      Finder header() => find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).gradient ==
                UserRole.superUser.tone.gradient,
      );
      Finder drawerScroll() => find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      );

      testWidgets(
        'uzun ekran (360x640): başlık sabit kalır, yalnız liste kayar',
        (t) async {
          await _pumpMenu(t, _cfgs[0], width: 360, height: 640, scale: 1.0);
          final headerTop = t.getTopLeft(header()).dy;
          final firstTileTop = t.getTopLeft(_tiles.first).dy;
          await t.drag(drawerScroll(), const Offset(0, -200));
          await t.pump();
          expect(t.getTopLeft(header()).dy, headerTop, reason: 'başlık sabit');
          expect(t.getTopLeft(_tiles.first).dy, lessThan(firstTileTop));
          expect(t.takeException(), isNull);
        },
      );

      testWidgets(
        'kısa ekran (640x360): başlık listeyle birlikte kayar, tek Scrollable',
        (t) async {
          await _pumpMenu(t, _cfgs[0], width: 640, height: 360, scale: 1.0);
          expect(drawerScroll(), findsOneWidget);
          final headerTop = t.getTopLeft(header()).dy;
          await t.drag(drawerScroll(), const Offset(0, -200));
          await t.pump();
          expect(
            t.getTopLeft(header()).dy,
            lessThan(headerTop),
            reason: 'kısa ekranda başlık da kayar (liste alanı daralmaz)',
          );
          expect(t.takeException(), isNull);
        },
      );

      testWidgets('eşik: 479 dp kısa, 480 dp uzun düzen', (t) async {
        await _pumpMenu(t, _cfgs[0], width: 360, height: 479, scale: 1.0);
        final headerTopShort = t.getTopLeft(header()).dy;
        await t.drag(drawerScroll(), const Offset(0, -150));
        await t.pump();
        expect(t.getTopLeft(header()).dy, lessThan(headerTopShort));

        await _pumpMenu(t, _cfgs[0], width: 360, height: 480, scale: 1.0);
        final headerTopTall = t.getTopLeft(header()).dy;
        await t.drag(drawerScroll(), const Offset(0, -150));
        await t.pump();
        expect(t.getTopLeft(header()).dy, headerTopTall);
      });
    },
  );

  group('YanMenu öğeleri: seçili hap (ListTile korunur), çubuk, genişlik', () {
    final orders = <_Cfg, List<SirketMenuItem>>{
      _cfgs[0]: const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.kullaniciYonetimi,
        SirketMenuItem.superUserYonetimi,
        SirketMenuItem.siteYoneticileriYonetimi,
        SirketMenuItem.daireKullanicilariYonetimi,
        SirketMenuItem.siteler,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.cihazEkle,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.bluetoothWifiKur,
      ],
      _cfgs[1]: const [
        SirketMenuItem.dashboard,
        SirketMenuItem.profilim,
        SirketMenuItem.siteler,
        SirketMenuItem.kayitliCihazlar,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.bluetoothWifiKur,
      ],
      _cfgs[4]: const [
        SirketMenuItem.dashboard,
        SirketMenuItem.katilimVeKurulum,
        SirketMenuItem.profilim,
      ],
    };

    for (final entry in orders.entries) {
      final c = entry.key;
      for (final dark in const <bool>[false, true]) {
        testWidgets(
          '${c.name} ${dark ? 'koyu' : 'açık'}: tek seçili öğe: ton zemini + ink + kalın başlık + 22 dp çubuk; diğerleri sönük',
          (t) async {
            await _pumpMenu(
              t,
              c,
              width: 360,
              height: 640,
              scale: 1.0,
              dark: dark,
            );
            final p = _palette(t);
            final tone = c.role.tone;
            final selectedIndex = c.selectedTileIndex(entry.value);

            var selectedCount = 0;
            for (var i = 0; i < c.tileCount; i++) {
              final tile = t.widget<ListTile>(_tiles.at(i));
              final isSelected = i == selectedIndex;
              // Mod geçişi öğesi ve çıkış kendi tonunu taşır; menü öğeleri rolün tonunu.
              final tileTone = (c.toggle && i == 0)
                  ? (c.resident ? AppTone.primary : AppTone.success)
                  : (i == c.tileCount - 1 ? AppTone.danger : tone);
              expect(tile.selected, isSelected, reason: '$i. öğe');
              expect(tile.dense, isTrue);
              expect(tile.selectedColor, tileTone.ink(p));
              // Hap zemini Ink (selectedTileColor) DEĞİL, ListTile'ı saran AnimatedContainer'dır
              // (bkz. piksel testleri: Ink + Opacity + kaydırma katmanı hapi kaybettirir).
              expect(tile.selectedTileColor, isNull);
              expect(
                _pill(t, i).color,
                isSelected
                    ? tileTone.tint(p)
                    : tileTone.tint(p).withValues(alpha: 0),
                reason: '$i. hap zemini',
              );
              if (isSelected) selectedCount++;

              // Başlık/ikon renkleri palet + ton (ham renk yok).
              final title = tile.title! as Text;
              final icon = tile.leading! as Icon;
              if (isSelected) {
                expect(title.style!.color, p.text);
                expect(title.style!.fontWeight, FontWeight.w800);
                expect(icon.color, tileTone.ink(p));
              } else {
                expect(title.style!.color, p.textSecondary);
                expect(title.style!.fontWeight, FontWeight.w500);
                expect(icon.color, p.textSecondary);
              }

              // 4x22 çubuk yalnız seçilide görünür (diğerlerinde yükseklik 0).
              final bar = t.getSize(_bars.at(i));
              expect(bar.width, 4);
              expect(bar.height, isSelected ? 22 : 0, reason: '$i. çubuk');
              final barBox = t.widget<AnimatedContainer>(_bars.at(i));
              expect(
                (barBox.decoration! as BoxDecoration).color,
                tileTone.ink(p),
              );
              expect(barBox.duration, AppMotion.base);
            }
            expect(selectedCount, 1);
          },
        );
      }
    }

    testWidgets(
      'rol tonu: süper=primary, yönetici=success, daire/bireysel=violet',
      (t) async {
        final expected = <UserRole, AppTone>{
          UserRole.superUser: AppTone.primary,
          UserRole.siteManager: AppTone.success,
          UserRole.apartmentOwner: AppTone.violet,
          UserRole.individual: AppTone.violet,
        };
        for (final entry in expected.entries) {
          await _pumpMenu(
            t,
            _Cfg('ton', entry.key, 3),
            width: 360,
            height: 640,
            scale: 1.0,
          );
          final p = _palette(t);
          final tile = t.widget<ListTile>(
            find.widgetWithText(ListTile, 'Panel'),
          );
          expect(
            _pill(t, 0).color,
            entry.value.tint(p),
            reason: entry.key.name,
          );
          expect(tile.selectedColor, entry.value.ink(p));
        }
      },
    );

    testWidgets(
      'başlığa ayrılan genişlik seçili/seçilmeyen öğede AYNI ve trailing yer ayırmaz',
      (t) async {
        // Uzun başlık: trailing (>= 32 dp ayrılır) olsaydı her öğede daralır ve gereksiz sarardı.
        const target = 'Daireye Katıl & Cihaz Ekle';
        const unselected = _Cfg(
          'seçili değil',
          UserRole.individual,
          3,
          selected: SirketMenuItem.profilim,
        );
        const selected = _Cfg(
          'seçili',
          UserRole.individual,
          3,
          selected: SirketMenuItem.katilimVeKurulum,
        );
        await _pumpMenu(t, unselected, width: 360, height: 640, scale: 1.0);
        final tileWidth = t
            .getSize(find.widgetWithText(ListTile, target))
            .width;
        final widthUnselected = _titleMaxWidth(t, target);
        await _pumpMenu(t, selected, width: 360, height: 640, scale: 1.0);
        final widthSelected = _titleMaxWidth(t, target);

        expect(widthSelected, widthUnselected);
        // Kenar boşluğu (2x16) + ikon sütunu (40 + 16) dışında kalan alanın tamamı başlığındır.
        expect(
          widthSelected,
          greaterThanOrEqualTo(tileWidth - 100),
          reason:
              'başlık alanı: ListTile genişliği $tileWidth, başlık $widthSelected',
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'mod geçişi + ayırıcılar + çıkış: metinler ve sıra eski menüyle AYNI',
      (t) async {
        await _pumpMenu(t, _cfgs[1], width: 360, height: 640, scale: 1.0);
        final titles = <String>[
          for (var i = 0; i < _cfgs[1].tileCount; i++)
            ((t.widget<ListTile>(_tiles.at(i))).title! as Text).data!,
        ];
        expect(titles, <String>[
          'Sakin Moduna Geç',
          'Panel',
          'Profilim',
          'Site Yönetimi',
          'Kayıtlı Cihazlar',
          'Daireye Katıl & Cihaz Ekle',
          'Bluetooth ile Wi-Fi Kur',
          'Çıkış Yap',
        ]);
        expect(find.byType(Divider), findsNWidgets(2));

        await _pumpMenu(t, _cfgs[2], width: 360, height: 640, scale: 1.0);
        expect(find.text('Yönetici Paneline Geç'), findsOneWidget);
        expect(find.text('Sakin Moduna Geç'), findsNothing);

        // Tüm süper kullanıcı başlıkları.
        await _pumpMenu(t, _cfgs[0], width: 360, height: 640, scale: 1.0);
        for (final title in const <String>[
          'Panel',
          'Profilim',
          'Kullanıcı Yönetimi',
          'Süper Kullanıcı Yönetimi',
          'Site Yöneticileri Yönetimi',
          'Daire Sakinleri',
          'Site Yönetimi',
          'Daireye Katıl & Cihaz Ekle',
          'Şirket Cihazı Kaydet',
          'Şirket Cihaz Envanteri',
          'Bluetooth ile Wi-Fi Kur',
          'Çıkış Yap',
        ]) {
          expect(find.text(title), findsOneWidget, reason: title);
        }
      },
    );

    testWidgets(
      'çekmece yüzeyi: tema rengi (koyu #0F172A / açık beyaz), sağ köşeler 28 dp (eski görünüm)',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpMenu(
            t,
            _cfgs.first,
            width: 360,
            height: 640,
            scale: 1.0,
            dark: dark,
          );
          final drawer = t.widget<Drawer>(find.byType(Drawer));
          // Yüzey AppTheme.drawerTheme'den gelir (elle renk yok): Drawer'ın Material'i.
          expect(drawer.backgroundColor, isNull);
          final surface = t.widget<Material>(
            find
                .descendant(
                  of: find.byType(Drawer),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(surface.color, dark ? const Color(0xFF0F172A) : Colors.white);
          expect(
            drawer.shape,
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
          );
        }
      },
    );
  });

  group(
    'YanMenu seçili hap gerçekten BOYANIR (piksel): Opacity + kaydırma alanı tuzağı',
    () {
      // ListTile.selectedTileColor (Ink) bu ağaçta (StaggeredEntry Opacity'si + kaydırma alanı ayrı
      // katman) hiç çizilmiyordu: widget ağacı doğru görünür ama ekranda hap yoktu. Bu testler
      // gerçek boyamayı sınar.
      Future<void> expectPill(
        WidgetTester t,
        GlobalKey key,
        _Cfg c,
        int selectedIndex,
      ) async {
        final p = _palette(t);
        final bg = p.isDark ? p.surfaceMuted : p.surface;
        final origin = t.getTopLeft(find.byKey(key));
        final otherIndex = selectedIndex == 0 ? 1 : 0;
        for (final i in <int>[selectedIndex, otherIndex]) {
          final rect = t.getRect(_tiles.at(i));
          // Hapın sol ucu: ikon/metin yok, hap içinde.
          final px = await _pixel(
            t,
            key,
            Offset(rect.left + 6, rect.center.dy) - origin,
          );
          final expected = i == selectedIndex
              ? Color.alphaBlend(c.role.tone.tint(p), bg)
              : bg;
          expect(
            _sameColor(px, expected),
            isTrue,
            reason:
                '${i == selectedIndex ? 'seçili' : 'seçili olmayan'} öğe ($i) pikseli $px, beklenen $expected',
          );
        }
      }

      for (final dark in const <bool>[false, true]) {
        final mode = dark ? 'koyu' : 'açık';
        testWidgets(
          '$mode: pumpAt düzeneği (giriş animasyonu bittikten sonra)',
          (t) async {
            final key = GlobalKey();
            await _pumpMenu(
              t,
              _cfgs[0],
              width: 360,
              height: 640,
              scale: 1.0,
              dark: dark,
              boundaryKey: key,
            );
            await expectPill(
              t,
              key,
              _cfgs[0],
              _cfgs[0].selectedTileIndex(const [
                SirketMenuItem.dashboard,
                SirketMenuItem.profilim,
                SirketMenuItem.kullaniciYonetimi,
                SirketMenuItem.superUserYonetimi,
                SirketMenuItem.siteYoneticileriYonetimi,
                SirketMenuItem.daireKullanicilariYonetimi,
                SirketMenuItem.siteler,
              ]),
            );
          },
        );

        for (final reduce in const <bool>[false, true]) {
          testWidgets(
            '$mode${reduce ? ', hareket azaltma' : ''}: gerçek Scaffold çekmecesi açıldıktan sonra',
            (t) async {
              final key = GlobalKey();
              await _pumpScaffoldDrawer(
                t,
                _menu(_cfgs[1]),
                dark: dark,
                reduce: reduce,
                boundaryKey: key,
              );
              // Site yöneticisi + geçiş öğesi: seçili "Site Yönetimi" (geçiş, Panel, Profilim, Site...).
              await expectPill(
                t,
                key,
                _cfgs[1],
                _cfgs[1].selectedTileIndex(const [
                  SirketMenuItem.dashboard,
                  SirketMenuItem.profilim,
                  SirketMenuItem.siteler,
                ]),
              );
            },
          );
        }
      }

      testWidgets(
        'hap öğeyle birlikte belirir: giriş başında yok, bittiğinde var',
        (t) async {
          final key = GlobalKey();
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: harnessApp(SizedBox(height: 640, child: _menu(_cfgs[0]))),
            ),
          );
          final p = _palette(t);
          final bg = p.surface;
          final selected = _cfgs[0].selectedTileIndex(const [
            SirketMenuItem.dashboard,
            SirketMenuItem.profilim,
            SirketMenuItem.kullaniciYonetimi,
            SirketMenuItem.superUserYonetimi,
            SirketMenuItem.siteYoneticileriYonetimi,
            SirketMenuItem.daireKullanicilariYonetimi,
            SirketMenuItem.siteler,
          ]);
          Future<Color> sample() async {
            final rect = t.getRect(_tiles.at(selected));
            return _pixel(t, key, Offset(rect.left + 6, rect.center.dy));
          }

          // 7. öğe (gecikme 180 ms): ilk karede tamamen saydam, hap da yok.
          expect(_entryOpacity(t, selected), 0);
          expect(
            _sameColor(await sample(), bg),
            isTrue,
            reason: 'ilk karede hap görünmez',
          );
          await t.pump(const Duration(milliseconds: 450));
          expect(
            _sameColor(
              await sample(),
              Color.alphaBlend(UserRole.superUser.tone.tint(p), bg),
            ),
            isTrue,
            reason: 'giriş bitince hap boyanmış',
          );
        },
      );
    },
  );

  group('YanMenu davranışı: dokunma geri çağrıları', () {
    testWidgets('öğe/çıkış/mod geçişi doğru geri çağrıyı tetikler', (t) async {
      final selected = <SirketMenuItem>[];
      var logouts = 0;
      var toggles = 0;
      await _pumpMenu(
        t,
        _cfgs[1],
        width: 360,
        height: 640,
        scale: 1.0,
        onSelect: selected.add,
        onLogout: () => logouts++,
        onToggle: () => toggles++,
      );

      await t.tap(find.text('Profilim'));
      await t.tap(find.text('Daireye Katıl & Cihaz Ekle'));
      expect(selected, <SirketMenuItem>[
        SirketMenuItem.profilim,
        SirketMenuItem.katilimVeKurulum,
      ]);

      await t.tap(find.text('Sakin Moduna Geç'));
      expect(toggles, 1);

      await t.ensureVisible(find.text('Çıkış Yap'));
      await t.pump();
      await t.tap(find.text('Çıkış Yap'));
      expect(logouts, 1);
      expect(selected.length, 2, reason: 'mod geçişi/çıkış onSelect çağırmaz');
    });

    testWidgets(
      'mod geçişi yalnız canToggleMode && onToggleMode varsa gösterilir',
      (t) async {
        await _pumpMenu(t, _cfgs[1], width: 360, height: 640, scale: 1.0);
        expect(find.text('Sakin Moduna Geç'), findsOneWidget);

        // canToggleMode true ama onToggleMode null: geçiş öğesi yok.
        await _pumpMenu(t, _cfgs[4], width: 360, height: 640, scale: 1.0);
        expect(find.text('Sakin Moduna Geç'), findsNothing);
        expect(find.text('Yönetici Paneline Geç'), findsNothing);
        expect(find.byType(Divider), findsOneWidget);
      },
    );

    testWidgets('ListTile erişilebilir: seçili öğe "seçili", hepsi düğme', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await _pumpMenu(t, _cfgs[4], width: 360, height: 640, scale: 1.0);
      expect(
        t.getSemantics(find.widgetWithText(ListTile, 'Profilim')),
        isSemantics(isSelected: true, isButton: true, label: 'Profilim'),
      );
      expect(
        t.getSemantics(find.widgetWithText(ListTile, 'Panel')),
        isSemantics(isSelected: false, isButton: true, label: 'Panel'),
      );
      // Süs çubuğu anlamsal ağaçta yok.
      final labels = t.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.getSemanticsData().label)
          .where((l) => l.isNotEmpty)
          .toList();
      expect(labels.where((l) => l == 'Profilim'), hasLength(1));
      handle.dispose();
    });
  });

  group(
    'YanMenu hareketi: ilk 8 öğe StaggeredEntry, hareket azaltma, sonsuz animasyon yok',
    () {
      testWidgets(
        'sıra ekrandaki sıradır (geçiş=0, öğeler, çıkış) ve ilk 8 sonrası sırada kalır',
        (t) async {
          await _pumpMenu(t, _cfgs[0], width: 360, height: 640, scale: 1.0);
          final indexes = t
              .widgetList<StaggeredEntry>(find.byType(StaggeredEntry))
              .map((e) => e.index)
              .toList();
          expect(indexes, <int>[
            for (var i = 0; i < _cfgs[0].tileCount; i++) i,
          ]);

          await _pumpMenu(t, _cfgs[1], width: 360, height: 640, scale: 1.0);
          final withToggle = t
              .widgetList<StaggeredEntry>(find.byType(StaggeredEntry))
              .map((e) => e.index)
              .toList();
          expect(withToggle, <int>[
            for (var i = 0; i < _cfgs[1].tileCount; i++) i,
          ]);
        },
      );

      testWidgets(
        'giriş: ilk karede gizli, kademeli belirir, 450 ms sonra hepsi tam görünür',
        (t) async {
          await _pumpRaw(t, _cfgs[0]);
          final count = _cfgs[0].tileCount;
          expect(find.byType(StaggeredEntry), findsNWidgets(count));
          expect(_entryOpacity(t, 0), 0, reason: 'ilk karede gizli');

          await t.pump(const Duration(milliseconds: 100));
          expect(_entryOpacity(t, 0), greaterThan(0));
          expect(
            _entryOpacity(t, 0),
            greaterThan(_entryOpacity(t, 5)),
            reason: 'kademe: sonraki öğe daha geç belirir',
          );

          await t.pump(const Duration(milliseconds: 450));
          for (var i = 0; i < count; i++) {
            expect(_entryOpacity(t, i), 1, reason: '$i. öğe tam görünür');
          }
          // Kararlı durumda ticker yok: pumpAndSettle biter, kare planlı değil.
          await t.pumpAndSettle();
          expect(t.binding.transientCallbackCount, 0);
        },
      );

      testWidgets(
        'hareket azaltma: ilk karede hepsi görünür; çubuk süresi sıfır',
        (t) async {
          await _pumpRaw(t, _cfgs[0], reduce: true);
          for (var i = 0; i < _cfgs[0].tileCount; i++) {
            expect(_entryOpacity(t, i), 1, reason: '$i. öğe hemen görünür');
          }
          final bar = t.widget<AnimatedContainer>(_bars.first);
          expect(bar.duration, Duration.zero);
          expect(t.binding.transientCallbackCount, 0);
        },
      );

      testWidgets(
        'seçim değişince çubuk 200 ms\'de 0 -> 22 dp büyür (hareket azaltmada anında)',
        (t) async {
          Future<void> build(
            SirketMenuItem selected, {
            bool reduce = false,
          }) async {
            t.view.physicalSize = const Size(360, 640);
            t.view.devicePixelRatio = 1.0;
            addTearDown(t.view.reset);
            await t.pumpWidget(
              harnessApp(
                SizedBox(
                  height: 640,
                  child: YanMenu(
                    fullName: 'Ali Veli',
                    userEmail: 'ali@example.com',
                    role: UserRole.individual,
                    selectedItem: selected,
                    onSelect: (_) {},
                    onLogout: () {},
                  ),
                ),
                reduce: reduce,
              ),
            );
            await t.pump(const Duration(milliseconds: 450));
          }

          await build(SirketMenuItem.dashboard);
          expect(t.getSize(_bars.at(2)).height, 0);
          // Aynı ağaç, yeni seçim: çubuk animasyonla büyür.
          await t.pumpWidget(
            harnessApp(
              SizedBox(
                height: 640,
                child: YanMenu(
                  fullName: 'Ali Veli',
                  userEmail: 'ali@example.com',
                  role: UserRole.individual,
                  selectedItem: SirketMenuItem.profilim,
                  onSelect: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          );
          await t.pump(const Duration(milliseconds: 100));
          final mid = t.getSize(_bars.at(2)).height;
          expect(mid, greaterThan(0));
          expect(mid, lessThan(22), reason: 'animasyon sürüyor');
          await t.pump(const Duration(milliseconds: 300));
          expect(t.getSize(_bars.at(2)).height, 22);
          expect(t.getSize(_bars.at(0)).height, 0);
          await t.pumpAndSettle();
        },
      );
    },
  );

  group('YanMenu gerçek Scaffold çekmecesinde (e2e/HomePage yolu)', () {
    testWidgets(
      'tek Scrollable (e2e kaydırma bulucusu), her ListTile hapın içindeki saydam Material içinde, yazı ölçeği x2,0 taşmaz',
      (t) async {
        await _pumpScaffoldDrawer(
          t,
          _menu(_cfgs[0]),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        final drawer = find.byType(Drawer);
        expect(drawer, findsOneWidget);
        // integration_test/support/e2e_driver.dart: `find.descendant(of: Drawer, matching: Scrollable)`.
        expect(
          find.descendant(of: drawer, matching: find.byType(Scrollable)),
          findsOneWidget,
        );
        // Her ListTile kendi saydam Material'inde ve o Material hapın (renkli kutu) İÇİNDE: dalga
        // hapın üstüne çizilir; Flutter'ın "ink gizleniyor" denetimi (FlutterError) tetiklenmez.
        for (var i = 0; i < _cfgs[0].tileCount; i++) {
          final material = find
              .ancestor(of: _tiles.at(i), matching: find.byType(Material))
              .first;
          expect(t.widget<Material>(material).type, MaterialType.transparency);
          final pill = find
              .ancestor(
                of: _tiles.at(i),
                matching: find.byType(AnimatedContainer),
              )
              .first;
          expect(
            find.descendant(
              of: pill,
              matching: find.byWidget(t.widget(material)),
            ),
            findsOneWidget,
            reason: '$i. öğe: Material hapın içinde',
          );
        }
        expect(find.byType(Divider), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'e2e: kaydırarak son öğeye inip dokunma çalışır (320x640 x2,0)',
      (t) async {
        final selected = <SirketMenuItem>[];
        await _pumpScaffoldDrawer(
          t,
          _menu(_cfgs[0], onSelect: selected.add),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        final scrollable = find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        );
        await t.scrollUntilVisible(
          find.text('Bluetooth ile Wi-Fi Kur'),
          120,
          scrollable: scrollable,
        );
        await t.tap(find.text('Bluetooth ile Wi-Fi Kur'));
        expect(selected, <SirketMenuItem>[SirketMenuItem.bluetoothWifiKur]);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'HomePage akışı: açıp 400 ms sonra dokunma (animasyon bitmeden de isabet)',
      (t) async {
        final selected = <SirketMenuItem>[];
        await _pumpScaffoldDrawer(
          t,
          _menu(_cfgs[4], onSelect: selected.add),
          open: false,
        );
        t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Profilim'));
        expect(selected, <SirketMenuItem>[SirketMenuItem.profilim]);
        expect(t.takeException(), isNull);
      },
    );

    for (final dark in const <bool>[false, true]) {
      testWidgets(
        '${dark ? 'koyu' : 'açık'}: açık çekmece 360x640 x1,5 taşmaz ve sürüm satırı görünür',
        (t) async {
          await _pumpScaffoldDrawer(t, _menu(_cfgs[1]), scale: 1.5, dark: dark);
          expect(find.text(AppConfig.versionDisplay), findsOneWidget);
          expect(_tiles, findsNWidgets(_cfgs[1].tileCount));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
      );
    }
  });
}
