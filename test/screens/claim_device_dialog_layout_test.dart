// FAZ 5 / A2-G5: ClaimDeviceDialog taşma testi (AGENTS.md kural 6).
//
// `Dialog` (AlertDialog değil): başlık şeridi AppDialogHeader, gövde kaydırılabilir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/widgets/claim_device_dialog.dart';

import '../design/harness.dart' show recordHaptics;
import 'dialog_layout_harness.dart';

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith, this.hold = false})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? failWith;

  /// true: istek [gate] tamamlanana kadar sürer (yükleniyor durumunu gözlemlemek için).
  final bool hold;
  final Completer<void> gate = Completer<void>();
  final List<String> claimed = [];

  @override
  Future<Map<String, dynamic>> claimDevice({
    required String deviceInput,
  }) async {
    claimed.add(deviceInput);
    if (hold) await gate.future;
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
    'ClaimDeviceDialog: istek sürerken birincil düğme "yükleniyor"; başarıda tek hafif haptik + bildirim, kapanır',
    (t) async {
      final haptics = recordHaptics(t);
      final auth = _FakeAuth(hold: true);
      await _open(t, auth, width: 400, height: 900, scale: 1.0, dark: false);

      // Elle giriş: ikincil gönder düğmesi tonal (birincil kutu QR düğmesi dolu kalır).
      await t.tap(find.text('Seri No / UID ile Elle Ekle'));
      await settleFor(t);
      // Elle giriş formu yumuşak açılır (AnimatedSize, sonlu): kararlı durumda ticker kalmaz.
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      final submit = t.widget<PrimaryActionButton>(
        find.widgetWithText(PrimaryActionButton, 'Cihazı Hesaba Bağla'),
      );
      expect(submit.variant, AppButtonVariant.tonal);
      expect(
        t
            .widget<PrimaryActionButton>(
              find.widgetWithText(PrimaryActionButton, 'Kutu QR Kodunu Tara'),
            )
            .variant,
        AppButtonVariant.filled,
      );

      await t.enterText(find.byType(TextField), 'ABC123DEF456');
      await t.tap(find.text('Cihazı Hesaba Bağla'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      // Yükleniyor: tek düğme "yükleniyor" durumunda (tıklama kapalı) + mevcut açıklama metni.
      expect(
        find.text('Cihaz kontrol ediliyor ve hesabınıza bağlanıyor...'),
        findsOneWidget,
      );
      final loading = t.widget<PrimaryActionButton>(
        find.byType(PrimaryActionButton),
      );
      expect(loading.loading, isTrue);
      expect(loading.onPressed, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(haptics.where((h) => h.contains('lightImpact')), isEmpty);

      auth.gate.complete();
      await settleFor(t, 800);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Cihaz hesabınıza bağlandı.'), findsOneWidget);
      expect(
        haptics.where((h) => h.contains('lightImpact')),
        hasLength(1),
        reason: 'başarı anında hafif haptik',
      );
      expect(t.takeException(), isNull);
    },
  );

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
