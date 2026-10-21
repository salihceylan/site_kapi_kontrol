// İP-1D / G3: daire sakini alt çubuğu (ResidentBottomBar, Material 3 NavigationBar). Sekmeler verilen sırayla çizilir,
// seçili sekme işaretlidir, dokunma geri çağrısı sekmeyi verir, Duyuru rozeti ekran okuyucuda sayıyla okunur; 320 dp ×
// 2,0 yazıda taşma yok (etiketler yazı ölçeğiyle büyümez, çubuğun dışına taşmaz).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/resident_tabs.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_bottom_bar.dart';

Finder _tab(ResidentTab tab) => find.byKey(ValueKey<String>('sakin_sekme_${tab.name}'));

Future<void> _pump(
  WidgetTester t, {
  List<ResidentTab> tabs = ResidentTab.values,
  ResidentTab selected = ResidentTab.ozet,
  ValueChanged<ResidentTab>? onSelect,
  Map<ResidentTab, int> badges = const <ResidentTab, int>{},
  double width = 400,
  double height = 800,
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
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: ResidentBottomBar(
          tabs: tabs,
          selected: selected,
          onSelect: onSelect ?? (_) {},
          badges: badges,
          tone: AppTone.success,
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('Material 3 NavigationBar: verilen sekmeler sırayla, seçili sekme işaretli', (t) async {
    await _pump(t, selected: ResidentTab.kapi);
    final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 5);
    expect(bar.selectedIndex, ResidentTab.values.indexOf(ResidentTab.kapi));
    final lefts = <double>[for (final tab in ResidentTab.values) t.getTopLeft(_tab(tab)).dx];
    expect(lefts, equals(<double>[...lefts]..sort()), reason: 'soldan sağa karar sırası');
    for (final tab in ResidentTab.values) {
      expect(find.descendant(of: _tab(tab), matching: find.text(tab.label)), findsOneWidget, reason: tab.label);
    }
  });

  testWidgets('dokunma sekmeyi verir (seçili sekmeye dokunmak da)', (t) async {
    final picks = <ResidentTab>[];
    await _pump(
      t,
      tabs: const <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru, ResidentTab.belgeler],
      onSelect: picks.add,
    );
    await t.tap(_tab(ResidentTab.belgeler));
    await t.pump();
    await t.tap(_tab(ResidentTab.ozet));
    await t.pump();
    expect(picks, <ResidentTab>[ResidentTab.belgeler, ResidentTab.ozet]);
  });

  testWidgets('verilmeyen sekme çizilmez; seçili sekme listede yoksa Özet işaretli', (t) async {
    await _pump(
      t,
      tabs: const <ResidentTab>[ResidentTab.ozet, ResidentTab.duyuru],
      selected: ResidentTab.kapi,
    );
    expect(_tab(ResidentTab.kapi), findsNothing);
    expect(_tab(ResidentTab.belgeler), findsNothing);
    expect(t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
  });

  testWidgets('Duyuru rozeti: sayı görünür, ekran okuyucu "N okunmamış" okur', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, badges: const <ResidentTab, int>{ResidentTab.duyuru: 3});
    final badge = find.byKey(const ValueKey<String>('sakin_sekme_rozet_duyuru'));
    expect(find.descendant(of: badge, matching: find.text('3')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('3 okunmamış')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sakin_sekme_rozet_ozet')), findsNothing, reason: 'rozetsiz sekme');
    handle.dispose();
  });

  testWidgets('99\'dan büyük rozet "99+"', (t) async {
    await _pump(t, badges: const <ResidentTab, int>{ResidentTab.duyuru: 140});
    expect(find.text('99+'), findsOneWidget);
  });

  group('taşma yok: etiketler çubuğun içinde, dokunma hedefi >= 48 dp', () {
    const cells = <(double, double)>[(320, 2.0), (320, 1.0), (360, 1.5), (412, 2.0), (820, 1.0)];
    for (final (w, s) in cells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()} dp x$s ${dark ? 'koyu' : 'açık'}', (t) async {
          await _pump(t, width: w, scale: s, dark: dark, badges: const <ResidentTab, int>{ResidentTab.duyuru: 140});
          expect(t.takeException(), isNull);
          final bar = t.getRect(find.byType(NavigationBar));
          for (final tab in ResidentTab.values) {
            final cell = t.getRect(_tab(tab));
            expect(cell.height, greaterThanOrEqualTo(48), reason: '${tab.label} dokunma hedefi');
            expect(cell.width, greaterThanOrEqualTo(48), reason: '${tab.label} dokunma hedefi');
            final label = t.getRect(find.descendant(of: _tab(tab), matching: find.text(tab.label)));
            expect(label.top, greaterThanOrEqualTo(bar.top - 0.01), reason: '${tab.label} çubuğun içinde');
            expect(label.bottom, lessThanOrEqualTo(bar.bottom + 0.01), reason: '${tab.label} çubuğun içinde');
            expect(label.left, greaterThanOrEqualTo(cell.left - 0.01), reason: '${tab.label} hücresinde');
            expect(label.right, lessThanOrEqualTo(cell.right + 0.01), reason: '${tab.label} hücresinde');
          }
        });
      }
    }
  });

  testWidgets('etiket ve simge rengi çubuk zemininde >= 4,5:1 (metin) / 3:1 (simge)', (t) async {
    for (final dark in const <bool>[false, true]) {
      await _pump(t, dark: dark, selected: ResidentTab.duyuru);
      final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
      final bg = bar.backgroundColor!;
      double contrast(Color a, Color b) {
        final l1 = a.computeLuminance();
        final l2 = b.computeLuminance();
        return ((l1 > l2 ? l1 : l2) + 0.05) / ((l1 > l2 ? l2 : l1) + 0.05);
      }

      for (final tab in ResidentTab.values) {
        final text = t.widget<Text>(find.descendant(of: _tab(tab), matching: find.text(tab.label)));
        final color = text.style?.color ?? DefaultTextStyle.of(t.element(find.text(tab.label))).style.color!;
        expect(contrast(color, bg), greaterThanOrEqualTo(4.5), reason: '${tab.label} etiketi (${dark ? 'koyu' : 'açık'})');
        final icon = t.widget<Icon>(find.descendant(of: _tab(tab), matching: find.byType(Icon)).first);
        // Seçili sekmenin simgesi göstergenin (saydam ton zemini, çubuk zeminine bindirilir) üstündedir.
        final under = tab == ResidentTab.duyuru ? Color.alphaBlend(bar.indicatorColor!, bg) : bg;
        expect(contrast(icon.color!, under), greaterThanOrEqualTo(3.0), reason: '${tab.label} simgesi');
      }
    }
  });
}
