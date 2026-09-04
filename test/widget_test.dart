import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/main.dart';

void main() {
  testWidgets('Login page renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(const MyApp(networkCheckEnabled: false));
    await tester.pumpAndSettle();

    expect(find.text('AHBU Giriş'), findsOneWidget);
    expect(find.text('Giriş Yap'), findsOneWidget);
  });
}
