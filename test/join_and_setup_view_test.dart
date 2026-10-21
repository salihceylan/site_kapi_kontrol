import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/views/join_and_setup_view.dart';

class MockAuthServiceForJoinAndSetup extends AuthService {
  MockAuthServiceForJoinAndSetup() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async {
    return (
      <JoinRequestRecord>[
        JoinRequestRecord(
          id: 1,
          siteCode: 101,
          siteName: 'Güneş Sitesi',
          blockName: 'A Blok',
          apartmentId: 10,
          unitLabel: '12',
          status: 'PENDING',
          notes: 'Daireye taşındım',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      null,
    );
  }
}

void main() {
  final session = UserSession(
    token: 'test_token',
    id: 1,
    fullName: 'Ahmet Ceylan',
    email: 'ahmet@example.com',
    loginName: 'ahmet',
    role: UserRole.individual,
    isActive: true,
  );

  testWidgets('JoinAndSetupView renders both setup cards and handles interactions', (tester) async {
    final mockAuth = MockAuthServiceForJoinAndSetup();
    bool joinClicked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JoinAndSetupView(
            authService: mockAuth,
            session: session,
            onOpenJoinSite: () => joinClicked = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title and Cards
    expect(find.text('Daireye Katıl'), findsOneWidget);
    expect(find.text('Site Sakini Girişi'), findsOneWidget);
    // Başvuru akışı kapalıyken (applications null) kurulum kartı yok; cihaz ekleme bu ekranda hiç yok.
    expect(find.text('Site Kurulumu'), findsNothing);

    // Verify Action Buttons
    expect(find.text('QR / Kod ile Daireye Katıl'), findsOneWidget);
    expect(find.text('Cihaz Ekle'), findsNothing);

    // Verify Join Request List item rendered
    expect(find.text('Katılım Başvurularım'), findsOneWidget);
    expect(find.text('Güneş Sitesi'), findsOneWidget);
    expect(find.text('A Blok • Daire 12'), findsOneWidget);

    // Tap Join button
    await tester.tap(find.text('QR / Kod ile Daireye Katıl'));
    await tester.pump();
    expect(joinClicked, isTrue);
  });
}
