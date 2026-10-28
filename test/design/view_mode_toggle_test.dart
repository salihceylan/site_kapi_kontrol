// Liste ↔ kutucuk geçiş düğmesi (ViewModeToggle + ViewModeScope), P2-22.
//
// AGENTS.md kural 6: taşma yok (320 dp x 2,0 ölçek, başlık satırında); kural 2: kapsam yoksa düğme HİÇ görünmez, mevcut
// ekranlar değişmez. Düğme: 44 dp dokunma hedefi, tooltip + anlamsal etiket, geçilecek kipe göre ikon, tercih saklanır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';

import 'harness.dart';

/// Kapsam + MaterialApp: kip servisten okunur (uygulama kökündeki bağla aynı).
Widget _host(ViewModeService service, {ViewScreen screen = ViewScreen.apartments}) {
  return ViewModeScope(
    service: service,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Row(
            children: [
              ?ViewModeToggle.maybe(context, screen),
              Text('kip: ${ViewModeScope.modeOf(context, screen).name}'),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('kapsam yoksa düğme hiç görünmez ve kip ekranın varsayılanıdır (mevcut ekranlar değişmez)', (t) async {
    late ListViewMode apartments;
    late ListViewMode modules;
    Widget? maybe;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              apartments = ViewModeScope.modeOf(context, ViewScreen.apartments);
              modules = ViewModeScope.modeOf(context, ViewScreen.modules);
              maybe = ViewModeToggle.maybe(context, ViewScreen.apartments);
              return const ViewModeToggle(screen: ViewScreen.apartments);
            },
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(maybe, isNull);
    expect(apartments, ListViewMode.list);
    expect(modules, ListViewMode.tiles);
    expect(t.takeException(), isNull);
  });

  testWidgets('listedeyken ızgara simgesi + "Kutucuk görünümüne geç"; dokununca kutucuğa geçer ve saklanır', (t) async {
    final service = ViewModeService();
    await t.pumpWidget(_host(service));

    expect(find.text('kip: list'), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byTooltip('Kutucuk görünümüne geç'), findsOneWidget);

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();

    expect(service.modeOf(ViewScreen.apartments), ListViewMode.tiles);
    expect(find.text('kip: tiles'), findsOneWidget, reason: 'bağımlı widget yeniden kuruldu');
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    expect(find.byTooltip('Liste görünümüne geç'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(ViewScreen.apartments.storageKey), 'tiles');
  });

  testWidgets('ikinci dokunuş listeye döner; öteki ekranların kipi etkilenmez', (t) async {
    final service = ViewModeService();
    await service.setMode(ViewScreen.apartments, ListViewMode.tiles);
    await t.pumpWidget(_host(service));
    expect(find.byTooltip('Liste görünümüne geç'), findsOneWidget);

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();

    expect(service.modeOf(ViewScreen.apartments), ListViewMode.list);
    expect(service.modeOf(ViewScreen.persons), ListViewMode.list);
    expect(service.modeOf(ViewScreen.modules), ListViewMode.tiles);
    expect((await SharedPreferences.getInstance()).getString(ViewScreen.apartments.storageKey), 'list');
  });

  testWidgets('Panel modülleri varsayılan kutucuk: düğme "Liste görünümüne geç" der', (t) async {
    final service = ViewModeService();
    await t.pumpWidget(_host(service, screen: ViewScreen.modules));
    expect(find.text('kip: tiles'), findsOneWidget);
    expect(find.byTooltip('Liste görünümüne geç'), findsOneWidget);
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
  });

  testWidgets('kayıtlı tercih (uygulama yeniden açıldı) ilk karede doğru kipte açılır', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{ViewScreen.apartments.storageKey: 'tiles'});
    final service = ViewModeService();
    await service.load();
    await t.pumpWidget(_host(service));
    expect(find.text('kip: tiles'), findsOneWidget);
    expect(find.byTooltip('Liste görünümüne geç'), findsOneWidget);
  });

  testWidgets('erişilebilirlik: anlamsal etiket var (geçilecek kip); dokunma hedefi en az 44 dp', (t) async {
    final handle = t.ensureSemantics();
    final service = ViewModeService();
    await t.pumpWidget(_host(service));

    expect(find.bySemanticsLabel('Kutucuk görünümüne geç'), findsOneWidget);
    final size = t.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Liste görünümüne geç'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('başlık satırında 320 dp x 2,0 ölçekte taşma yok (SectionHeader + düğme + yenile)', (t) async {
    final service = ViewModeService();
    for (final dark in const <bool>[false, true]) {
      await pumpAt(
        t,
        ViewModeScope(
          service: service,
          child: Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionHeader(
                title: 'Daireler',
                count: 120,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?ViewModeToggle.maybe(context, ViewScreen.apartments),
                    IconButton(onPressed: () {}, tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded)),
                  ],
                ),
              ),
            ),
          ),
        ),
        width: 320,
        scale: 2.0,
        dark: dark,
      );
      expect(find.byTooltip('Kutucuk görünümüne geç'), findsOneWidget);
      expect(find.byTooltip('Yenile'), findsOneWidget);
      await t.tap(find.byTooltip('Kutucuk görünümüne geç'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Liste görünümüne geç'), findsOneWidget);
      expect(t.takeException(), isNull);
      await service.setMode(ViewScreen.apartments, ListViewMode.list);
    }
  });
}
