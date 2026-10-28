// K8 (P1-16): "Tüm işlemler" ekranı — kullanıcının görebildiği BÜTÜN işlemlerin kategorili, aramalı tam listesi. Kompakt menü kümesi listeyi
// KISALTMAZ; kümede olmayan işlem buradan açılır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/menu_layout.dart';
import 'package:site_kapi_kontrol/ui/views/all_actions_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

final List<SirketMenuItem> _visible = YanMenu.visibleItems(
  role: UserRole.siteManager,
  additionalItems: const <SirketMenuItem>{
    SirketMenuItem.kapilar,
    SirketMenuItem.kisiler,
    SirketMenuItem.duyurular,
    SirketMenuItem.finans,
    SirketMenuItem.belgeler,
    SirketMenuItem.talepler,
    SirketMenuItem.anketler,
    SirketMenuItem.komsuPanosu,
    SirketMenuItem.faaliyetRaporu,
    SirketMenuItem.ekipmanBakim,
  },
);

Finder _row(SirketMenuItem item) => find.byKey(ValueKey<String>('tum_islemler_${item.name}'));
Finder _group(SirketMenuGroup group) => find.byKey(ValueKey<String>('tum_islemler_grup_${group.name}'));
final Finder _search = find.byKey(const ValueKey<String>('tum_islemler_arama'));
final Finder _empty = find.byKey(const ValueKey<String>('tum_islemler_bos'));
final Finder _edit = find.byKey(const ValueKey<String>('tum_islemler_menu_duzenle'));
final Finder _summary = find.byKey(const ValueKey<String>('tum_islemler_ozet'));

/// Ekranı "Panel"den açılmış gibi kurar (geri/pop çalışsın diye bir açıcı sayfanın üstünde).
Future<void> _open(
  WidgetTester t, {
  List<SirketMenuItem>? items,
  Set<SirketMenuItem>? featured,
  Map<SirketMenuItem, int> badges = const <SirketMenuItem, int>{},
  ValueChanged<SirketMenuItem>? onOpen,
  VoidCallback? onEdit,
  Future<void> Function()? onRefresh,
  double width = 400,
  double height = 2400,
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey<String>('ac'),
              onPressed: () => AllActionsView.open(
                context,
                (_) => AllActionsView(
                  role: UserRole.siteManager,
                  items: items ?? _visible,
                  featured: featured,
                  badgeCounts: badges,
                  onOpen: onOpen ?? (_) {},
                  onEditMenuLayout: onEdit,
                  onRefresh: onRefresh,
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const ValueKey<String>('ac')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  group('tam liste (kompakt menüden bağımsız)', () {
    testWidgets('görünür TÜM öğeler (Panel hariç) kategorili listelenir; kategori başlığı sayacı öğe sayısıdır', (t) async {
      await _open(t);
      final expected = _visible.where((i) => i != SirketMenuItem.dashboard).toList();
      for (final item in expected) {
        expect(_row(item), findsOneWidget, reason: '${item.name} listede');
      }
      expect(_row(SirketMenuItem.dashboard), findsNothing, reason: 'Panel kendi sayfasıdır');
      for (final section in allActionsSections(_visible)) {
        expect(_group(section.group), findsOneWidget, reason: section.group.title);
      }
      expect(find.text('Tüm işlemler'), findsWidgets);
    });

    testWidgets('kompakt küme listeyi KISALTMAZ: kümede olmayan işlem de burada; yalnız "Ana menüde" işareti değişir', (t) async {
      final featured = <SirketMenuItem>{SirketMenuItem.dashboard, SirketMenuItem.finans, SirketMenuItem.duyurular, SirketMenuItem.kapilar};
      await _open(t, featured: featured);
      for (final item in _visible.where((i) => i != SirketMenuItem.dashboard)) {
        expect(_row(item), findsOneWidget, reason: '${item.name} kümede olmasa da listede');
      }
      // İşaret yalnız modüle bağlı ve kümede olan satırlarda.
      expect(find.descendant(of: _row(SirketMenuItem.finans), matching: find.text('Ana menüde')), findsOneWidget);
      expect(find.descendant(of: _row(SirketMenuItem.duyurular), matching: find.text('Ana menüde')), findsOneWidget);
      expect(find.descendant(of: _row(SirketMenuItem.anketler), matching: find.text('Ana menüde')), findsNothing);
      expect(find.descendant(of: _row(SirketMenuItem.belgeler), matching: find.text('Ana menüde')), findsNothing);
      expect(find.descendant(of: _row(SirketMenuItem.profilim), matching: find.text('Ana menüde')), findsNothing, reason: 'Ayarlar öğesi');
    });

    testWidgets('kompakt menü yoksa (featured null) hiçbir satırda "Ana menüde" işareti yok', (t) async {
      await _open(t);
      expect(find.text('Ana menüde'), findsNothing);
    });

    testWidgets('özet metni: öne çıkmayan işlem sayısını söyler', (t) async {
      final featured = <SirketMenuItem>{SirketMenuItem.dashboard, SirketMenuItem.finans};
      final beyond = YanMenu.itemsBeyondCompact(_visible, featured).length;
      final total = _visible.where((i) => i != SirketMenuItem.dashboard).length;
      await _open(t, featured: featured);
      expect(t.widget<Text>(_summary).data, 'Ana menüde öne çıkmayan $beyond işlem dahil, kullanabildiğiniz $total işlemin tamamı burada.');
      await _open(t);
      expect(t.widget<Text>(_summary).data, 'Kullanabildiğiniz $total işlemin tamamı burada.');
    });
  });

  group('arama', () {
    testWidgets('Türkçe katlama: "komsu" Komşu Panosu\'nu bulur; kategori başlığı daralan listeyle uyumlu', (t) async {
      await _open(t);
      await t.enterText(_search, 'komsu');
      await t.pump();
      expect(_row(SirketMenuItem.komsuPanosu), findsOneWidget);
      expect(_row(SirketMenuItem.finans), findsNothing);
      expect(_group(SirketMenuGroup.borclar), findsNothing, reason: 'eşleşmeyen kategori düşer');
      expect(_group(SirketMenuGroup.iletisim), findsOneWidget);
    });

    testWidgets('açıklamada ve kategori adında da aranır; sözcüklerin hepsi eşleşmeli', (t) async {
      await _open(t);
      await t.enterText(_search, 'aidat');
      await t.pump();
      expect(_row(SirketMenuItem.finans), findsOneWidget, reason: '"Aidat, borç ve tahsilat" açıklaması');
      await t.enterText(_search, 'aidat zzz');
      await t.pump();
      expect(_row(SirketMenuItem.finans), findsNothing);
      expect(_empty, findsOneWidget);
    });

    testWidgets('eşleşme yoksa boş durum kartı; temizle düğmesi tam listeyi geri getirir', (t) async {
      await _open(t);
      await t.enterText(_search, 'yokböyleişlem');
      await t.pump();
      expect(_empty, findsOneWidget);
      expect(find.text('Eşleşen işlem yok'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('tum_islemler_arama_temizle')));
      await t.pump();
      expect(_empty, findsNothing);
      expect(_row(SirketMenuItem.finans), findsOneWidget);
      expect(t.widget<TextField>(_search).controller!.text, isEmpty);
    });
  });

  group('gezinme', () {
    testWidgets('satıra dokunmak ekranı kapatır ve onOpen\'ı seçilen öğeyle çağırır (çekmeceden seçmekle aynı gezinme)', (t) async {
      final opened = <SirketMenuItem>[];
      await _open(t, onOpen: opened.add);
      await t.tap(_row(SirketMenuItem.anketler));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(opened, <SirketMenuItem>[SirketMenuItem.anketler]);
      expect(find.byType(AllActionsView), findsNothing, reason: 'ekran kapandı');
    });

    testWidgets('"Ana menüyü düzenle" yalnız yönetici geri çağrısı verilince çıkar ve onu çağırır', (t) async {
      await _open(t);
      expect(_edit, findsNothing);
      var edits = 0;
      await _open(t, onEdit: () => edits++);
      expect(_edit, findsOneWidget);
      await t.tap(_edit);
      expect(edits, 1);
    });
  });

  group('aşağı çekip yenileme (AGENTS.md Kural 7)', () {
    testWidgets('onRefresh verilirse aşağı çekmek çağırır; verilmezse yenileme göstergesi yok', (t) async {
      await _open(t);
      expect(find.byType(RefreshIndicator), findsNothing);
      var refreshes = 0;
      await _open(t, onRefresh: () async => refreshes++, height: 800);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await t.drag(find.byKey(const ValueKey<String>('tum_islemler_kaydirma')), const Offset(0, 400));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(refreshes, 1);
    });
  });

  group('rozet ve erişilebilirlik', () {
    testWidgets('bekleyen sayısı satırda rozet olur; ekran okuyucu "N bekleyen" okur; satır tek düğmedir', (t) async {
      final handle = t.ensureSemantics();
      await _open(t, badges: const <SirketMenuItem, int>{SirketMenuItem.talepler: 4, SirketMenuItem.duyurular: 120});
      final badge = find.descendant(of: _row(SirketMenuItem.talepler), matching: find.byKey(const ValueKey<String>('tum_islemler_rozet')));
      expect(find.descendant(of: badge, matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: find.descendant(of: _row(SirketMenuItem.duyurular), matching: find.byKey(const ValueKey<String>('tum_islemler_rozet'))), matching: find.text('99+')), findsOneWidget);
      final node = t.getSemantics(_row(SirketMenuItem.talepler));
      expect(node.label, 'Talepler, 4 bekleyen');
      handle.dispose();
    });

    testWidgets('başlıklar başlık düğümüdür; arama alanının etiketi var', (t) async {
      final handle = t.ensureSemantics();
      await _open(t);
      expect(
        t.getSemantics(find.descendant(of: _group(SirketMenuGroup.borclar), matching: find.text('Borçlar'))),
        isSemantics(isHeader: true),
      );
      expect(find.text('İşlem ara'), findsOneWidget);
      handle.dispose();
    });
  });

  group('taşma yok', () {
    const cells = <(double, double, double)>[(320, 640, 2.0), (360, 640, 1.5), (640, 320, 2.0), (820, 1180, 1.0)];
    for (final (w, h, s) in cells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}: tam liste, rozetler, işaretler, düzenle düğmesi', (t) async {
          await _open(
            t,
            featured: <SirketMenuItem>{SirketMenuItem.dashboard, SirketMenuItem.finans, SirketMenuItem.duyurular},
            badges: const <SirketMenuItem, int>{SirketMenuItem.talepler: 120, SirketMenuItem.anketler: 9},
            onEdit: () {},
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(t.takeException(), isNull);
          // Tüm satırları sırayla görünür yap (kaydırma): taşma hatası çıkmamalı, dokunma hedefi >= 48 dp.
          for (final item in _visible.where((i) => i != SirketMenuItem.dashboard)) {
            await t.ensureVisible(_row(item));
            await t.pump();
            expect(t.getSize(_row(item)).height, greaterThanOrEqualTo(48), reason: item.name);
          }
          expect(t.takeException(), isNull);
          await t.enterText(_search, 'borç');
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}
