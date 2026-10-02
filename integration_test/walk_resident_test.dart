// Daire sakini (apartment_owner) menu turu: resident_a1, resident_a2, resident_b1
// (kullanici adi + PIN ile giris). E2E_ONLY=resident_a1 ile tek kullanici.

import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_env.dart';
import 'support/screens_resident.dart';

void main() {
  initE2eBinding();
  final only = E2eEnv.onlyUsers;

  for (final key in const <String>['resident_a1', 'resident_a2', 'resident_b1']) {
    testWidgets(
      'E2E yuruyus: $key (daire sakini)',
      (tester) async {
        if (only.isNotEmpty && !only.contains(key)) return;
        await runE2e(
          tester,
          suite: 'walk_resident',
          body: (session) async {
            final user = E2eEnv.user(key);
            await bootApp(tester);
            await login(tester, user);
            for (final combo in E2eCombo.parse(E2eEnv.combosRaw)) {
              await session.runScenario(user: user, combination: combo, screens: residentScreens());
            }
            await logout(tester);
          },
        );
      },
      timeout: const Timeout(Duration(hours: 3)),
    );
  }
}
