// Bireysel kullanici menu turu: individual_joined / pending / free / family / rejected.
// individual_free kullanicisi icin (sahipsiz cihaz UID'si + site katilim kodu) yalniz OKUMA amacli
// alanlar doldurulur; gonderme/sahiplenme yapilmaz. E2E_ONLY=individual_free ile tek kullanici.

import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_env.dart';
import 'support/screens_individual.dart';

void main() {
  initE2eBinding();
  final only = E2eEnv.onlyUsers;

  for (final key in const <String>[
    'individual_joined',
    'individual_pending',
    'individual_free',
    'individual_family',
    'individual_rejected',
  ]) {
    testWidgets(
      'E2E yuruyus: $key (bireysel)',
      (tester) async {
        if (only.isNotEmpty && !only.contains(key)) return;
        await runE2e(
          tester,
          suite: 'walk_individual',
          body: (session) async {
            final user = E2eEnv.user(key);
            await bootApp(tester);
            await login(tester, user);
            for (final combo in E2eCombo.parse(E2eEnv.combosRaw)) {
              await session.runScenario(
                user: user,
                combination: combo,
                screens: individualScreens(lookupJoinToken: key == 'individual_free'),
              );
            }
            await logout(tester);
          },
        );
      },
      timeout: const Timeout(Duration(hours: 3)),
    );
  }
}
