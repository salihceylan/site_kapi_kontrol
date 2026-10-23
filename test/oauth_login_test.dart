import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/pages/register_individual_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/social_auth_buttons.dart';

import 'design/harness.dart';
import 'legal_fixtures.dart';

class _FakeSocialAuth extends AuthService {
  _FakeSocialAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<Map<String, dynamic>> oauthCalls = <Map<String, dynamic>>[];
  String? nextError;

  @override
  Future<String?> loginWithOAuth({
    required String provider,
    required String idToken,
    String? fullName,
    String? firstName,
    String? lastName,
    List<AcceptedDocument>? acceptedDocuments,
  }) async {
    oauthCalls.add(<String, dynamic>{
      'provider': provider,
      'idToken': idToken,
      'fullName': fullName,
      'firstName': firstName,
      'lastName': lastName,
      'accepted': <String>[
        for (final d in acceptedDocuments ?? const <AcceptedDocument>[]) '${d.id}@${d.version}',
      ],
    });
    return nextError;
  }
}

void main() {
  test('AuthApi.oauthStatus ve AuthApi.loginWithOAuth dogru uc noktalari cagirir', () async {
    late String lastPath;
    late Map<String, dynamic> lastBody;

    final client = MockClient((request) async {
      lastPath = request.url.path;
      if (request.url.path == '/auth/oauth/status') {
        return http.Response(
          jsonEncode({
            'google': {'enabled': true, 'client_id': 'g-client'},
            'apple': {'enabled': true, 'client_id': 'a-client'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      lastBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'ok': true,
          'is_new_user': true,
          'provider': 'google',
          'token': 'jwt-social-123',
          'user': {
            'id': 501,
            'full_name': 'Deniz Kaya',
            'email': 'deniz@gmail.com',
            'role': 'individual',
            'is_active': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://localhost', client: client);
    final status = await api.oauthStatus();
    expect((status['google'] as Map)['enabled'], isTrue);
    expect((status['apple'] as Map)['enabled'], isTrue);

    final session = await api.loginWithOAuth(
      provider: 'google',
      idToken: 'id-token-xyz',
      firstName: 'Deniz',
      lastName: 'Kaya',
    );
    expect(lastPath, '/auth/oauth/google');
    expect(lastBody['id_token'], 'id-token-xyz');
    expect(lastBody['first_name'], 'Deniz');
    expect(lastBody['last_name'], 'Kaya');
    expect(session.id, 501);
    expect(session.fullName, 'Deniz Kaya');
    expect(session.email, 'deniz@gmail.com');
    expect(session.token, 'jwt-social-123');
  });

  testWidgets('LoginPage Google ve iCloud (Apple) butonlarini tasma olmadan gosterir ve tetikler', (tester) async {
    final auth = _FakeSocialAuth();
    await pumpAt(
      tester,
      SizedBox(
        width: 320,
        height: 640,
        child: LoginPage(
          authService: auth,
          onProvideSocialCredentials: (provider) async => SocialAuthCredentials(
            idToken: 'token-$provider',
          ),
        ),
      ),
      width: 320,
      height: 640,
      scale: 2.0,
    );

    final googleBtn = find.byKey(const Key('social-auth-google-button'));
    final appleBtn = find.byKey(const Key('social-auth-apple-button'));
    expect(googleBtn, findsOneWidget);
    expect(appleBtn, findsOneWidget);

    await tester.ensureVisible(googleBtn);
    await tester.pumpAndSettle();
    await tester.tap(googleBtn);
    await tester.pumpAndSettle();

    expect(auth.oauthCalls.length, 1);
    expect(auth.oauthCalls.first['provider'], 'google');
    expect(auth.oauthCalls.first['idToken'], 'token-google');

    await tester.ensureVisible(appleBtn);
    await tester.pumpAndSettle();
    await tester.tap(appleBtn);
    await tester.pumpAndSettle();

    expect(auth.oauthCalls.length, 2);
    expect(auth.oauthCalls.last['provider'], 'apple');
    expect(auth.oauthCalls.last['idToken'], 'token-apple');
  });

  testWidgets('Android ve web ortaminda iCloud (Apple) butonu gosterilmez, yalniz Google gosterilir', (tester) async {
    final auth = _FakeSocialAuth();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpAt(
        tester,
        SizedBox(
          width: 360,
          height: 640,
          child: LoginPage(
            authService: auth,
          ),
        ),
        width: 360,
        height: 640,
        scale: 1.0,
      );

      final googleBtn = find.byKey(const Key('social-auth-google-button'));
      final appleBtn = find.byKey(const Key('social-auth-apple-button'));
      expect(googleBtn, findsOneWidget);
      expect(appleBtn, findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Google ile giris dogrudan tek dokunusla calisir, id_token veya kod sormaz', (tester) async {
    final auth = _FakeSocialAuth();
    await pumpAt(
      tester,
      SizedBox(
        width: 360,
        height: 640,
        child: LoginPage(
          authService: auth,
          onProvideSocialCredentials: (provider) async => SocialAuthCredentials(
            idToken: 'google-oauth-token-123',
            fullName: 'Mehmet Yılmaz',
          ),
        ),
      ),
      width: 360,
      height: 640,
      scale: 1.0,
    );

    final googleBtn = find.byKey(const Key('social-auth-google-button'));
    await tester.ensureVisible(googleBtn);
    await tester.pumpAndSettle();
    await tester.tap(googleBtn);
    await tester.pumpAndSettle();

    // id_token / Doğrulama Belirteci veya kod isteme pencereleri asla açılmamalı
    expect(find.textContaining('id_token'), findsNothing);
    expect(find.textContaining('Doğrulama Belirteci'), findsNothing);
    expect(find.textContaining('6 Haneli Doğrulama Kodu'), findsNothing);

    expect(auth.oauthCalls.length, 1);
    expect(auth.oauthCalls.first['provider'], 'google');
    expect(auth.oauthCalls.first['idToken'], 'google-oauth-token-123');
    expect(auth.oauthCalls.first['fullName'], 'Mehmet Yılmaz');
  });

  testWidgets('RegisterIndividualPage yasal onay sonrasi Google ve iCloud ile kaydolmayi destekler', (tester) async {
    final auth = _FakeSocialAuth();
    final legal = FakeLegalServer();

    await pumpAt(
      tester,
      SizedBox(
        width: 360,
        height: 640,
        child: RegisterIndividualPage(
          authService: auth,
          legalApi: legal.api,
          onProvideSocialCredentials: (provider) async => SocialAuthCredentials(
            idToken: 'reg-token-$provider',
            firstName: 'Selin',
            lastName: 'Demir',
          ),
        ),
      ),
      width: 360,
      height: 640,
      scale: 1.0,
    );
    await tester.pumpAndSettle();

    // Yasal onay kutusunu işaretle
    final checkbox = find.byType(Checkbox);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    final appleBtn = find.byKey(const Key('social-auth-apple-button'));
    await tester.ensureVisible(appleBtn);
    await tester.pumpAndSettle();
    await tester.tap(appleBtn);
    await tester.pumpAndSettle();

    expect(auth.oauthCalls.length, 1);
    expect(auth.oauthCalls.first['provider'], 'apple');
    expect(auth.oauthCalls.first['idToken'], 'reg-token-apple');
    expect(auth.oauthCalls.first['firstName'], 'Selin');
    expect((auth.oauthCalls.first['accepted'] as List).isNotEmpty, isTrue);
  });
}
