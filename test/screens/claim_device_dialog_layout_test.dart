// FAZ 5 / A2-G5: ClaimDeviceDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog` (AlertDialog değil): başlık şeridi AppDialogHeader, gövde kaydırılabilir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/widgets/claim_device_dialog.dart';

import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;
  final List<String> claimed = [];

  @override
  Future<Map<String, dynamic>> claimDevice({
    required String deviceInput,
  }) async {
    claimed.add(deviceInput);
    if (failWith != null) throw ApiException(failWith!);
    return <String, dynamic>{
      'message': 'Cihaz hesabınıza bağlandı.',
      'device': {'device_uid': deviceInput},
    };
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
  (context) => ClaimDeviceDialog.show(context, auth),
  width: width,
  height: height,
  scale: scale,
  dark: dark,
);

void main() {
  layoutMatrix('ClaimDeviceDialog (QR + elle giriş formu)', (
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

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Cihaz Sahiplen'), findsOneWidget);
    expect(find.byType(PrimaryActionButton), findsOneWidget);

    await scrollTo(t, find.text('Seri No / UID ile Elle Ekle'));
    await t.tap(find.text('Seri No / UID ile Elle Ekle'));
    await settleFor(t);
    expect(find.text('Elle Girişi Kapat'), findsOneWidget);
    await scrollTo(t, find.text('Cihazı Hesaba Bağla'));
    await scrollTo(t, find.text('Vazgeç'));
  });

  layoutMatrix('ClaimDeviceDialog (hata: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeAuth(
      failWith:
          'Bu cihaz başka bir hesaba bağlı olduğu için sahiplenilemedi; lütfen cihaz seri numarasını kontrol edin.',
    );
    await _open(
      t,
      auth,
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollTo(t, find.text('Seri No / UID ile Elle Ekle'));
    await t.tap(find.text('Seri No / UID ile Elle Ekle'));
    await settleFor(t);
    await t.enterText(find.byType(TextField), 'abc123def456');
    await scrollTo(t, find.text('Cihazı Hesaba Bağla'));
    await t.tap(find.text('Cihazı Hesaba Bağla'));
    await settleFor(t, 800);

    expect(auth.claimed, ['abc123def456']);
    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.textContaining('başka bir hesaba bağlı'), findsOneWidget);
    await scrollTo(t, find.byType(InlineNotice));
  });

  testWidgets(
    'ClaimDeviceDialog: boş gönderimde mevcut uyarı metni; başarıda kapanır',
    (t) async {
      final auth = _FakeAuth();
      await _open(t, auth, width: 400, height: 900, scale: 1.0, dark: false);

      await t.tap(find.text('Seri No / UID ile Elle Ekle'));
      await settleFor(t);
      await t.tap(find.text('Cihazı Hesaba Bağla'));
      await settleFor(t);
      expect(
        find.text('Lütfen geçerli bir cihaz QR kodu veya Seri No giriniz.'),
        findsOneWidget,
      );

      await t.enterText(find.byType(TextField), 'ABC123DEF456');
      await t.tap(find.text('Cihazı Hesaba Bağla'));
      await settleFor(t, 800);
      expect(auth.claimed, ['ABC123DEF456']);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Cihaz hesabınıza bağlandı.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
