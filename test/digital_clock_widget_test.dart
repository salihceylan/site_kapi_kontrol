import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/widgets/digital_clock_widget.dart';

void main() {
  final testSession = UserSession(
    id: 1,
    fullName: 'Yönetici Ahmet Yılmaz Çok Uzun İsimli Kullanıcı',
    email: 'admin@example.com',
    loginName: 'admin',
    role: UserRole.superUser,
    isActive: true,
    token: 'test_token',
  );

  testWidgets('DigitalClockWidget renders without overflow on 320px screen width', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: DigitalClockWidget(session: testSession),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(DigitalClockWidget), findsOneWidget);
    expect(find.text('TSİ (UTC+3)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DigitalClockWidget renders without overflow with large font scale (1.5x)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: DigitalClockWidget(session: testSession),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(DigitalClockWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DigitalClockWidget renders without overflow on ultra narrow 280px screen', (tester) async {
    tester.view.physicalSize = const Size(280, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: DigitalClockWidget(session: testSession),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(DigitalClockWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
