// Telefon bildirimi (Faz 3b-B): bildirime dokunma yönlendirmesi "Güncellenen koşullar" kapısını atlamasın diye
// kapının durumu dışa açılır (LegalConsentBlock.active): ilk denetim sürerken ve bekleyen onay varken true; onay /
// boş liste / hata (kapı kilitlemez) / kapanışta false; kapı devre dışıyken hiç true olmaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/legal_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/views/legal_consent_gate.dart';

import 'legal_fixtures.dart';

class _Auth extends AuthService {
  _Auth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  UserSession? get session => const UserSession(
    id: 5,
    fullName: 'Ali Veli',
    email: 'ali@example.com',
    loginName: null,
    role: UserRole.apartmentOwner,
    isActive: true,
    token: 'tok-5',
  );

  @override
  Future<void> refreshSession({bool force = false}) async {}
}

Future<void> _pump(WidgetTester t, FakeLegalServer server, {bool enabled = true}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: LegalConsentGate(
        authService: _Auth(),
        enabled: enabled,
        api: LegalApi(baseUrl: 'https://api.example.test', client: server.client),
        child: const Scaffold(body: Text('ANA SAYFA')),
      ),
    ),
  );
}

void main() {
  tearDown(() => LegalConsentBlock.active.value = false);

  testWidgets('ilk denetim sürerken true; bekleyen yoksa false', (t) async {
    final server = FakeLegalServer()..consentsGate = Completer<void>();
    await _pump(t, server);
    await t.pump();
    expect(LegalConsentBlock.active.value, isTrue);
    server.consentsGate!.complete();
    await t.pump(const Duration(milliseconds: 100));
    expect(LegalConsentBlock.active.value, isFalse);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bekleyen onay varken true; kapı ağaçtan çıkınca false', (t) async {
    final server = FakeLegalServer()
      ..pending = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'terms', 'title': 'Kullanım Koşulları', 'version': '2026-11-01'},
      ];
    await _pump(t, server);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Güncellenen Koşullar'), findsOneWidget);
    expect(LegalConsentBlock.active.value, isTrue);
    await t.pumpWidget(const SizedBox.shrink());
    expect(LegalConsentBlock.active.value, isFalse);
  });

  testWidgets('denetim hatası kapıyı kilitlemez: false', (t) async {
    final server = FakeLegalServer()..consentsStatus = 500;
    await _pump(t, server);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(LegalConsentBlock.active.value, isFalse);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('kapı devre dışıyken hiç true olmaz', (t) async {
    final server = FakeLegalServer();
    await _pump(t, server, enabled: false);
    await t.pump();
    expect(LegalConsentBlock.active.value, isFalse);
  });
}
