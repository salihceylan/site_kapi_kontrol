// Site yoneticisi menu turu: manager_1 (tek site) ve manager_2 (cok siteli yonetici); her kombinasyonda
// once yonetici paneli, sonra "Sakin Moduna Gec" (AppBar rozeti / cekmece ogesi dönüşümlü) ve geri.
// Bkz. support/e2e_driver.dart basligindaki calistirma komutu. E2E_ONLY=manager_1 ile tek kullanici.

import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_env.dart';
import 'support/screens_site_manager.dart';

Future<void> _walkManager(
  WidgetTester tester,
  E2eSession session, {
  required String userKey,
  required List<String> siteKeys,
}) async {
  final user = E2eEnv.user(userKey);
  await bootApp(tester);
  await login(tester, user);
  var viaDrawer = false;
  for (final combo in E2eCombo.parse(E2eEnv.combosRaw)) {
    await session.runScenario(
      user: user,
      combination: combo,
      screens: siteManagerScreens(siteKeys: siteKeys),
      scenarioMode: 'yonetici',
    );
    await switchMode(tester, toResident: true, viaDrawer: viaDrawer);
    await session.runScenario(
      user: user,
      combination: combo,
      screens: siteManagerResidentModeScreens(),
      scenarioMode: 'sakin',
    );
    await switchMode(tester, toResident: false, viaDrawer: viaDrawer);
    viaDrawer = !viaDrawer;
  }
  await logout(tester);
}

void main() {
  initE2eBinding();
  final only = E2eEnv.onlyUsers;
  bool wanted(String key) => only.isEmpty || only.contains(key);

  testWidgets(
    'E2E yuruyus: manager_1 (tek site; yonetici + sakin modu)',
    (tester) async {
      if (!wanted('manager_1')) return;
      await runE2e(
        tester,
        suite: 'walk_site_manager',
        body: (s) => _walkManager(tester, s, userKey: 'manager_1', siteKeys: const <String>['site_1']),
      );
    },
    timeout: const Timeout(Duration(hours: 3)),
  );

  testWidgets(
    'E2E yuruyus: manager_2 (cok siteli yonetici; yonetici + sakin modu)',
    (tester) async {
      if (!wanted('manager_2')) return;
      await runE2e(
        tester,
        suite: 'walk_site_manager',
        body: (s) => _walkManager(
          tester,
          s,
          userKey: 'manager_2',
          siteKeys: const <String>['site_2', 'site_1'],
        ),
      );
    },
    timeout: const Timeout(Duration(hours: 3)),
  );
}
