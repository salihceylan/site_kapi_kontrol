import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/pages/wifi_provision_page.dart';

void main() {
  testWidgets(
    'Wi-Fi kurulum sayfası: içerik kısa olsa da arka plan gövdeyi doldurur (E2E bulgusu: altta koyu şerit)',
    (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 915 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: WifiProvisionPage(surfaceColor: Color(0xFF1A2555)),
        ),
      );
      await tester.pump();

      final background = find.byKey(const ValueKey<String>('wifi_provision_background'));
      expect(background, findsOneWidget);
      final backgroundSize = tester.getSize(background);
      final scaffoldSize = tester.getSize(find.byType(Scaffold));
      final appBarHeight = tester.getSize(find.byType(AppBar)).height;

      expect(backgroundSize.width, closeTo(scaffoldSize.width, 0.5));
      expect(backgroundSize.height, closeTo(scaffoldSize.height - appBarHeight, 0.5));
      expect(tester.takeException(), isNull);
    },
  );
}
