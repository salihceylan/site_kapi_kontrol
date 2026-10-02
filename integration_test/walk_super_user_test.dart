// Super kullanici menu turu (Windows masaustu / Android emulator).
// Bkz. support/e2e_driver.dart basligindaki calistirma komutu.

import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_env.dart';
import 'support/screens_super_user.dart';

void main() {
  initE2eBinding();

  testWidgets(
    'E2E yuruyus: super_user (tum menuler, presetler, yazi olcegi)',
    (tester) async {
      await runE2e(
        tester,
        suite: 'walk_super_user',
        body: (session) async {
          final user = E2eEnv.user('super_user');
          await bootApp(tester);
          await login(tester, user);
          for (final combo in E2eCombo.parse(E2eEnv.combosRaw)) {
            await session.runScenario(user: user, combination: combo, screens: superUserScreens());
          }
          await logout(tester);
        },
      );
    },
    timeout: const Timeout(Duration(hours: 3)),
  );
}
