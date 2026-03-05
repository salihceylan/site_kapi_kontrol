import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ahbu/main.dart';

void main() {
  testWidgets('Login page renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MyApp(networkCheckEnabled: false));
    await tester.pumpAndSettle();

    expect(find.text('Uyelik Girisi'), findsOneWidget);
    expect(find.text('Giris Yap'), findsOneWidget);
  });
}
