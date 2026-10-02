// FAZ 5 / A2-G5: InviteSiteManagerDialog taşma testi (AGENTS.md kural 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/invite_site_manager_dialog.dart';

import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.ok = false, this.message})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final bool ok;
  final String? message;
  final List<String> invited = [];

  @override
  Future<(bool, String?)> inviteSiteManager(
    int siteCode, {
    required String email,
    String? fullName,
  }) async {
    invited.add(email);
    return (ok, message);
  }
}

Future<void> _open(
  WidgetTester t,
  _FakeAuth auth, {
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) => openDialogAt(
  t,
  (context) => InviteSiteManagerDialog.show(
    context,
    authService: auth,
    siteCode: 101,
    siteName: 'Güneş Sitesi Uzun İsimli Konutları Blok Yönetimi',
  ),
  width: width,
  height: height,
  scale: scale,
  dark: dark,
);

void main() {
  layoutMatrix('InviteSiteManagerDialog (form + doğrulama)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await _open(
      t,
      _FakeAuth(),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Yönetici Davet Et'), findsOneWidget);
    expect(find.byType(InlineNotice), findsOneWidget); // bilgi kutusu

    await scrollTo(t, find.text('Davet Gönder'));
    await t.tap(find.text('Davet Gönder'));
    await settleFor(t);
    expect(find.text('Lütfen e-posta adresi girin.'), findsOneWidget);
  });

  layoutMatrix('InviteSiteManagerDialog (sunucu hatası: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth(
      message:
          'Bu e-posta adresine davet gönderilemedi; lütfen adresi kontrol edip tekrar deneyin.',
    );
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await t.enterText(
      find.widgetWithText(TextFormField, 'E-posta Adresi *'),
      'yonetici@ornek-site.com',
    );
    await scrollTo(t, find.text('Davet Gönder'));
    await t.tap(find.text('Davet Gönder'));
    await settleFor(t);

    expect(auth.invited, ['yonetici@ornek-site.com']);
    // bilgi kutusu + hata kutusu
    expect(find.byType(InlineNotice), findsNWidgets(2));
    expect(
      find.textContaining('Bu e-posta adresine davet gönderilemedi'),
      findsOneWidget,
    );
    await scrollTo(t, find.textContaining('Bu e-posta adresine davet'));
  });

  testWidgets(
    'InviteSiteManagerDialog: başarıda kapanır ve başarı bildirimi gösterir',
    (t) async {
      final auth = _FakeAuth(ok: true, message: 'Davet iletildi.');
      await _open(t, auth, width: 360, height: 640, scale: 1.0, dark: false);

      await t.enterText(
        find.widgetWithText(TextFormField, 'E-posta Adresi *'),
        'yonetici@ornek-site.com',
      );
      await t.tap(find.text('Davet Gönder'));
      await settleFor(t, 700);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Davet iletildi.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
