import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/force_change_password_dialog.dart';

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(api: AuthApi(baseUrl: 'http://localhost'));

  bool updateProfileCalled = false;
  String? returnedError;

  @override
  UserSession? get session => const UserSession(
        id: 1,
        fullName: 'Test Sakin',
        email: 'sakin@test.com',
        loginName: 'b1-d5',
        role: UserRole.apartmentOwner,
        isActive: true,
        token: 'fake_jwt_token',
        mustChangePassword: true,
      );

  @override
  Future<String?> updateMyProfile({
    required String fullName,
    required String email,
    String? phoneNumber,
    String? password,
    String? currentPassword,
  }) async {
    updateProfileCalled = true;
    return returnedError;
  }
}

void main() {
  group('must_change_password UserSession Serialization', () {
    test('UserSession parses must_change_password true and false', () {
      final jsonTrue = {
        'id': 101,
        'full_name': 'Ahmet Yilmaz',
        'email': 'ahmet@example.com',
        'login_name': 'a-1',
        'role': 'apartment_owner',
        'is_active': true,
        'token': 'tok123',
        'must_change_password': true,
      };
      final sessionTrue = UserSession.fromJson(jsonTrue);
      expect(sessionTrue.mustChangePassword, isTrue);
      expect(sessionTrue.toJson()['must_change_password'], isTrue);

      final jsonFalse = {
        'id': 102,
        'full_name': 'Mehmet Kaya',
        'email': 'mehmet@example.com',
        'role': 'individual',
        'is_active': true,
        'token': 'tok456',
        'must_change_password': false,
      };
      final sessionFalse = UserSession.fromJson(jsonFalse);
      expect(sessionFalse.mustChangePassword, isFalse);
      expect(sessionFalse.toJson()['must_change_password'], isFalse);

      final sessionUpdated = sessionTrue.copyWith(mustChangePassword: false);
      expect(sessionUpdated.mustChangePassword, isFalse);
    });
  });

  group('ForceChangePasswordDialog Widget Tests', () {
    testWidgets('renders dialog title, fields and button', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeAuth = _FakeAuthService();
      var passwordChangedCalled = false;
      var logoutCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForceChangePasswordDialog(
              session: fakeAuth.session!,
              authService: fakeAuth,
              onPasswordChanged: (updated) {
                passwordChangedCalled = true;
              },
              onLogout: () {
                logoutCalled = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Yeni Şifrenizi Belirleyin'), findsOneWidget);
      expect(find.text('Mevcut Geçici Şifre / PIN'), findsOneWidget);
      expect(find.text('Yeni Şifreniz'), findsOneWidget);
      expect(find.text('Yeni Şifreniz (Tekrar)'), findsOneWidget);
      expect(find.text('Yeni Şifremi Kaydet ve Devam Et'), findsOneWidget);
      expect(find.text('Şimdi Değil, Oturumu Kapat'), findsOneWidget);

      await tester.tap(find.text('Şimdi Değil, Oturumu Kapat'));
      await tester.pumpAndSettle();
      expect(logoutCalled, isTrue);
      expect(passwordChangedCalled, isFalse);
    });
  });
}

