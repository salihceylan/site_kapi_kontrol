// FAZ 5 / A2-G5: CreateGuestPassDialog taşma testi (AGENTS.md kural 6).
//
// İki pencere: (1) form, (2) "Geçiş Linki Hazır!" sonuç penceresi. Sunucu hatası InlineNotice ile
// gösterilir; hata kutusu da taşmamalıdır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/guest_pass.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';

import 'dialog_layout_harness.dart';

DoorRecord _door() => DoorRecord(
  id: 7,
  siteCode: 101,
  siteName: 'Güneş Sitesi',
  doorName: 'A Blok Ana Giriş Kapısı',
  doorIndex: 1,
  isActive: true,
  assignedDeviceId: 1,
  assignedDeviceUid: 'ESP32_C3_TEST',
  mqttSiteId: 101,
  createdAt: DateTime(2026, 1, 1),
);

class _FakeAuth extends AuthService {
  _FakeAuth({this.error}) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? error;

  @override
  Future<(GuestPassRecord?, String?)> createGuestPass({
    required int doorId,
    required String title,
    required String passType,
    int? durationMinutes,
    int? maxUses,
  }) async {
    if (error != null) return (null, error);
    return (
      GuestPassRecord(
        id: 1,
        title: title,
        token: 'tok123',
        passType: passType,
        expiresAt: DateTime(2030, 1, 1),
        maxUses: maxUses ?? 1,
        usedCount: 0,
        isActive: true,
        webUrl:
            'https://api.gudeteknoloji.com.tr/guest/tok123uzunbirbaglantiornegi',
        doorName: 'A Blok Ana Giriş Kapısı',
        siteName: 'Güneş Sitesi',
      ),
      null,
    );
  }
}

void main() {
  layoutMatrix('CreateGuestPassDialog (form)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => CreateGuestPassDialog.show(
        context,
        door: _door(),
        authService: _FakeAuth(),
        showMessage: (_) {},
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AppDialogHeader), findsOneWidget);
    expect(find.text('Geçiş Süresi ve Türü'), findsOneWidget);
    expect(find.text('Tek Kullanımlık (30 Dakika)'), findsOneWidget);

    // Başka bir ön ayar seçilir (seçili durum görünümü) ve boş başlıkla doğrulama hatası alınır.
    await scrollTo(t, find.text('Günlük Geçiş (12 Saat - 10 Kullanım)'));
    await t.tap(find.text('Günlük Geçiş (12 Saat - 10 Kullanım)'));
    await settleFor(t);
    await t.enterText(find.byType(TextFormField), '');
    await scrollTo(t, find.text('Linki Oluştur'));
    await t.tap(find.text('Linki Oluştur'));
    await settleFor(t);
    expect(find.text('Başlık alanı boş bırakılamaz.'), findsOneWidget);
  });

  layoutMatrix('CreateGuestPassDialog (sunucu hatası: InlineNotice)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => CreateGuestPassDialog.show(
        context,
        door: _door(),
        authService: _FakeAuth(
          error:
              'Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
        ),
        showMessage: (_) {},
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollTo(t, find.text('Linki Oluştur'));
    await t.tap(find.text('Linki Oluştur'));
    await settleFor(t);
    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.textContaining('Sunucuya bağlanılamadı.'), findsOneWidget);
    await scrollTo(t, find.byType(InlineNotice));
  });

  layoutMatrix('CreateGuestPassDialog (Geçiş Linki Hazır!)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await openDialogAt(
      t,
      (context) => CreateGuestPassDialog.show(
        context,
        door: _door(),
        authService: _FakeAuth(),
        showMessage: (_) {},
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    await scrollTo(t, find.text('Linki Oluştur'));
    await t.tap(find.text('Linki Oluştur'));
    await settleFor(t, 800);

    expect(find.text('🎉 Geçiş Linki Hazır!'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('tok123uzunbirbaglantiornegi'), findsOneWidget);
    await scrollTo(t, find.text('Paylaş'));
    expect(find.text('Linki Kopyala'), findsOneWidget);
  });
}
