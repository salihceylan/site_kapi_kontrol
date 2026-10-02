import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/submit_join_request_dialog.dart';

void main() {
  testWidgets(
    'katılım kodu yazılınca "Site Bilgilerini Getir" düğmesi hemen görünür (E2E bulgusu)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubmitJoinRequestDialog(
              authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')),
            ),
          ),
        ),
      );
      await tester.pump();

      // Boşken düğme yok.
      expect(find.text('Site Bilgilerini Getir'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'SJT-ABC123');
      await tester.pump();

      expect(find.text('Site Bilgilerini Getir'), findsOneWidget);

      // Silinince tekrar kaybolur.
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      expect(find.text('Site Bilgilerini Getir'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
