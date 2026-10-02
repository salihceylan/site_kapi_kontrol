// Aydınlık / karanlık tema geçiş düğmesi (ThemeToggleButton + ThemeScope).
//
// AGENTS.md kural 6: taşma yok (320 dp x 2,0 ölçek); kural 2: kapsam yoksa düğme HİÇ görünmez, mevcut ekranlar
// değişmez. Düğme: 44 dp dokunma hedefi, tooltip + anlamsal etiket, görünen temaya göre ikon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/theme_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/theme_toggle_button.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';

import 'harness.dart';

/// Kapsam + MaterialApp: tema modu servisten okunur (uygulama kökündeki bağla aynı).
Widget _host(ThemeService service, {Widget? home}) {
  return ThemeScope(
    service: service,
    child: AnimatedBuilder(
      animation: service,
      builder: (context, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: service.mode,
        home:
            home ??
            Scaffold(
              appBar: AppBar(actions: const [ThemeToggleButton()]),
              body: const SizedBox.expand(),
            ),
      ),
    ),
  );
}

Brightness _brightness(WidgetTester t) =>
    Theme.of(t.element(find.byType(Scaffold).first)).brightness;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('kapsam yoksa düğme hiç görünmez (mevcut ekranlar değişmez)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(appBar: AppBar(actions: const [ThemeToggleButton()])),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('açık temada: koyu ay ikonu + "Koyu temaya geç"; dokununca karanlığa geçer', (t) async {
    final service = ThemeService();
    await service.setMode(ThemeMode.light);
    await t.pumpWidget(_host(service));

    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.byTooltip('Koyu temaya geç'), findsOneWidget);
    expect(_brightness(t), Brightness.light);

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();

    expect(service.mode, ThemeMode.dark);
    expect(_brightness(t), Brightness.dark);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(find.byTooltip('Aydınlık temaya geç'), findsOneWidget);
  });

  testWidgets('ikinci dokunuş aydınlığa döner ve tercih saklanır', (t) async {
    final service = ThemeService();
    await service.setMode(ThemeMode.dark);
    await t.pumpWidget(_host(service));
    expect(_brightness(t), Brightness.dark);

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();

    expect(service.mode, ThemeMode.light);
    expect(_brightness(t), Brightness.light);
    expect((await SharedPreferences.getInstance()).getString(ThemeService.storageKey), 'light');
  });

  testWidgets('sistem modu + sistem koyu: ikon aydınlık sembolü; dokununca AYDINLIĞA geçer', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    final service = ThemeService(); // varsayılan: sistem
    await t.pumpWidget(_host(service));

    expect(_brightness(t), Brightness.dark);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();
    expect(service.mode, ThemeMode.light);
    expect(_brightness(t), Brightness.light);
  });

  testWidgets('erişilebilirlik: anlamsal etiket var; dokunma hedefi en az 44 dp', (t) async {
    final handle = t.ensureSemantics();
    final service = ThemeService();
    await service.setMode(ThemeMode.light);
    await t.pumpWidget(_host(service));

    expect(find.bySemanticsLabel('Koyu temaya geç'), findsOneWidget);
    final size = t.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    handle.dispose();
  });

  testWidgets('giriş sayfası: düğme görünür, 320 dp x 2,0 ölçekte taşma yok; geçiş çalışır', (t) async {
    final service = ThemeService();
    await service.setMode(ThemeMode.light);
    final auth = AuthService(api: AuthApi(baseUrl: 'http://localhost'));
    addTearDown(auth.dispose);

    await pumpAt(
      t,
      SizedBox(
        width: 320,
        height: 640,
        child: ThemeScope(service: service, child: LoginPage(authService: auth)),
      ),
      width: 320,
      height: 640,
      scale: 2.0,
    );

    expect(find.byTooltip('Koyu temaya geç'), findsOneWidget);
    expect(find.text('AHBU Giriş'), findsOneWidget);

    await t.ensureVisible(find.byTooltip('Koyu temaya geç'));
    await t.tap(find.byTooltip('Koyu temaya geç'));
    await t.pump();
    expect(service.mode, ThemeMode.dark);
    expect(t.takeException(), isNull);
  });
}
