// İP-1D (G2): HomePage testlerinin ortak menü gezinmesi. Çekmece başlıklar altındadır; ayar öğeleri (Profilim, Modüller,
// cihazlar, kullanıcı yönetimi, Denetim Kaydı, Platform Ayarları, İstemci Hataları, Modül Talepleri, Site Başvuruları,
// Eller Serbest ...) çekmecede DEĞİL, sağ üstteki dişliden ("Ayarlar") açılan paneldedir. Bu dosya `_test.dart` ile
// bitmediği için kendi başına test olarak çalışmaz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

ScaffoldState _scaffold(WidgetTester t) => t.state<ScaffoldState>(find.byType(Scaffold).first);

/// Çekmeceyi açar.
Future<void> openMenuDrawer(WidgetTester t) async {
  _scaffold(t).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Sağ üstteki dişliden Ayarlar panelini açar (açık çekmece önce kapanır).
Future<void> openSettingsPanel(WidgetTester t) async {
  final scaffold = _scaffold(t);
  if (scaffold.isDrawerOpen) {
    scaffold.closeDrawer();
    await t.pump();
    await t.pump(const Duration(milliseconds: 450));
  }
  final gear = find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Ayarlar'));
  if (gear.evaluate().isNotEmpty) {
    await t.tap(gear);
  } else {
    scaffold.openEndDrawer();
  }
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// Açık çekmeceyi ya da Ayarlar panelini kapatır.
Future<void> closeMenuPanels(WidgetTester t) async {
  final scaffold = _scaffold(t);
  if (scaffold.isDrawerOpen) scaffold.closeDrawer();
  if (scaffold.isEndDrawerOpen) scaffold.closeEndDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

/// [label] öğesini bulur: önce çekmecede, yoksa Ayarlar panelinde. Paneli açık bırakır ve öğenin bulucusunu döner (hiçbirinde
/// yoksa boş bulucu; çekmece açık kalır).
Future<Finder> findMenuEntry(WidgetTester t, String label) async {
  await openMenuDrawer(t);
  final inDrawer = find.descendant(of: find.byType(YanMenu), matching: find.text(label));
  if (inDrawer.evaluate().isNotEmpty) return inDrawer.first;
  await openSettingsPanel(t);
  final inSettings = find.descendant(of: find.byType(YanMenuAyarlar), matching: find.text(label));
  if (inSettings.evaluate().isNotEmpty) return inSettings.first;
  await closeMenuPanels(t);
  await openMenuDrawer(t);
  return inDrawer;
}

/// [label] öğesine dokunur (çekmecede ya da Ayarlar panelinde; bkz. [findMenuEntry]) ve sayfa geçişini bekler.
Future<void> tapMenuEntry(WidgetTester t, String label, {Duration settle = const Duration(milliseconds: 600)}) async {
  final entry = await findMenuEntry(t, label);
  await t.ensureVisible(entry);
  await t.pump();
  await t.tap(entry);
  await t.pump();
  await t.pump(settle);
}

/// Açık panelin (çekmece ya da Ayarlar) ListTile başlıkları, sırayla.
List<String> openPanelTitles(WidgetTester t) => <String>[
      for (final tile in t.widgetList<ListTile>(find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile))))
        if (tile.title is Text && (tile.title! as Text).data != null) (tile.title! as Text).data!,
    ];

/// Çekmece ve Ayarlar panelindeki tüm başlıklar (çekmece sırası, ardından panel sırası). Paneller kapalı bırakılır.
Future<List<String>> menuAndSettingsTitles(WidgetTester t) async {
  await openMenuDrawer(t);
  final drawer = openPanelTitles(t);
  await openSettingsPanel(t);
  final settings = openPanelTitles(t);
  await closeMenuPanels(t);
  return <String>[...drawer, ...settings];
}

/// Çekmecedeki öğe başlıkları (yalnız menü öğeleri; site satırı / grup başlıkları ListTile değildir).
Future<List<String>> drawerTitlesOnly(WidgetTester t) async {
  await openMenuDrawer(t);
  final titles = openPanelTitles(t);
  await closeMenuPanels(t);
  return titles;
}

/// Ayarlar panelindeki öğe başlıkları.
Future<List<String>> settingsTitlesOnly(WidgetTester t) async {
  await openSettingsPanel(t);
  final titles = openPanelTitles(t);
  await closeMenuPanels(t);
  return titles;
}

/// AÇIK çekmecedeki YanMenu'nün hesapladığı menü LİSTESİ başlıkları: vitrin kartlarının sırası (`YanMenu.visibleItems`),
/// çekmece öğeleri ve Ayarlar paneli öğeleri birlikte. Öğe sıralama (yerleşim) kuralları bu listede sınanır; öğenin
/// çekmecedeki başlığı [expectUnderDrawerHeader] ile.
List<String> menuListTitles(WidgetTester t) {
  final menu = t.widget<YanMenu>(find.byType(YanMenu));
  return <String>[
    for (final item in YanMenu.visibleItems(
      role: menu.role,
      isResidentMode: menu.isResidentMode,
      canToggleMode: menu.canToggleMode,
      additionalItems: menu.additionalItems,
      hiddenItems: menu.hiddenItems,
    ))
      YanMenu.titleFor(item, menu.role),
  ];
}

/// AÇIK çekmecede [title] öğesi [header] başlığının altında mı (başlık öğenin üstünde)?
void expectUnderDrawerHeader(WidgetTester t, String title, String header) {
  final h = find.descendant(of: find.byType(YanMenu), matching: find.text(header));
  final tile = find.descendant(of: find.byType(YanMenu), matching: find.widgetWithText(ListTile, title));
  expect(h, findsOneWidget, reason: '"$header" başlığı çekmecede');
  expect(tile, findsOneWidget, reason: '"$title" çekmecede');
  expect(t.getRect(h).bottom, lessThanOrEqualTo(t.getRect(tile).top + 0.01), reason: '"$title" "$header" başlığının altında');
}
