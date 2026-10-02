// E2E altyapisinin kendi dogrulamasi (uygulamaya/arka uca baglanmaz):
//  - canli (integration) baglamada RenderFlex tasmasi toplayiciya duser ve test COKMEZ,
//  - gorunum presetleri + yazi olcegi uygulanir,
//  - ekran goruntusu PNG olarak yazilir.
//
//   flutter test integration_test/harness_selftest_test.dart -d windows \
//     --dart-define=API_BASE_URL=http://127.0.0.1:18080 --dart-define-from-file=<E2E>/dart_defines.json

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_driver.dart';
import 'support/e2e_env.dart';

void main() {
  initE2eBinding();

  testWidgets('altyapi: tasma yakalanir, preset uygulanir, ekran goruntusu yazilir', (tester) async {
    await runE2e(
      tester,
      suite: 'harness_selftest',
      body: (session) async {
        session.userKey = 'selftest';
        await session.applyCombo(const E2eCombo(E2eViewPreset.smallPhone, 1.5));

        runApp(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: <Widget>[
                  Container(width: 400, height: 40, color: Colors.red),
                  Container(width: 400, height: 40, color: Colors.blue),
                ],
              ),
            ),
          ),
        );
        E2eRuntime.collector.beginScreen('selftest_overflow');
        await pumpFor(tester, const Duration(seconds: 1));

        // Preset: 360x640 mantiksal piksel.
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(size.width, closeTo(360, 0.5));
        expect(size.height, closeTo(640, 0.5));
        expect(tester.platformDispatcher.textScaleFactor, 1.5);

        final findings = E2eRuntime.collector.drain();
        expect(findings.any((f) => f.kind == 'overflow'), isTrue, reason: 'tasma toplayiciya dusmeli');

        final path = '${E2eEnv.runDir}/selftest/overflow.png';
        final saved = await saveScreenshot(tester, path);
        expect(saved, isNotNull);
        expect(File(path).existsSync() && File(path).lengthSync() > 1000, isTrue);
      },
    );
  });
}
