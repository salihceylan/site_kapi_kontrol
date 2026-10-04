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
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/create_guest_pass_dialog.dart';

import '../design/harness.dart';
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
  _FakeAuth({this.error, this.expiresAt})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? error;

  /// Sunucunun döndürdüğü son geçerlilik zamanı (varsayılan: 2030).
  final DateTime? expiresAt;

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
        expiresAt: expiresAt ?? DateTime(2030, 1, 1),
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

  testWidgets(
    'CreateGuestPassDialog: süre/tür satırları seçim kartıdır (seçili anlamı, rozet tonu, onay işareti)',
    (t) async {
      final handle = t.ensureSemantics();
      await openDialogAt(
        t,
        (context) => CreateGuestPassDialog.show(
          context,
          door: _door(),
          authService: _FakeAuth(),
          showMessage: (_) {},
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );

      const single = 'Tek Kullanımlık (30 Dakika)';
      const timed = 'Süreli Misafir (2 Saat - 5 Kullanım)';
      Finder cardOf(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(AppCard));
      AppTone toneOf(String title) => t
          .widget<IconOrb>(
            find.descendant(of: cardOf(title), matching: find.byType(IconOrb)),
          )
          .tone;

      expect(find.byType(AppCard), findsNWidgets(3));
      // Seçili satır "seçili" bildirir; diğerleri yalnız düğmedir (seçili durumu taşımaz).
      expect(
        t.getSemantics(cardOf(single)),
        isSemantics(isSelected: true, hasSelectedState: true, isButton: true),
      );
      expect(
        t.getSemantics(cardOf(timed)),
        isSemantics(hasSelectedState: false, isButton: true, hasTapAction: true),
      );
      expect(toneOf(single), AppTone.primary);
      expect(toneOf(timed), AppTone.neutral);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await t.tap(find.text(timed));
      await settleFor(t);

      expect(
        t.getSemantics(cardOf(single)),
        isSemantics(hasSelectedState: false, isButton: true),
      );
      expect(
        t.getSemantics(cardOf(timed)),
        isSemantics(isSelected: true, hasSelectedState: true, isButton: true),
      );
      expect(toneOf(single), AppTone.neutral);
      expect(toneOf(timed), AppTone.primary);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets(
    'CreateGuestPassDialog: büyük yazıda (2,0) seçim satırlarında süs rozeti yok, metin okunur',
    (t) async {
      await openDialogAt(
        t,
        (context) => CreateGuestPassDialog.show(
          context,
          door: _door(),
          authService: _FakeAuth(),
          showMessage: (_) {},
        ),
        width: 320,
        height: 1400,
        scale: 2.0,
        dark: false,
      );
      expect(find.byType(AppCard), findsNWidgets(3));
      // Yalnız başlık rozeti kalır.
      expect(find.byType(IconOrb), findsOneWidget);
      expect(find.text('Tek Kullanımlık (30 Dakika)'), findsOneWidget);
    },
  );

  testWidgets(
    'CreateGuestPassDialog: sonuç kartı (success hero rozet, tek link, geçerlilik bilgisi), haptik ve kopyala',
    (t) async {
      final haptics = recordHaptics(t);
      final messages = <String>[];
      await openDialogAt(
        t,
        (context) => CreateGuestPassDialog.show(
          context,
          door: _door(),
          authService: _FakeAuth(),
          showMessage: messages.add,
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );

      await scrollTo(t, find.text('Linki Oluştur'));
      await t.tap(find.text('Linki Oluştur'));
      await settleFor(t, 800);

      expect(haptics, ['HapticFeedbackType.lightImpact'], reason: 'oluşturma (başarı) anı');
      expect(find.text('🎉 Geçiş Linki Hazır!'), findsOneWidget);

      // Premium sonuç kartı: hero (level 2, success tonlu) + 56 dp success rozet.
      final card = t.widget<AppCard>(find.byType(AppCard));
      expect(card.level, 2);
      expect(card.tone, AppTone.success);
      final hero = t
          .widgetList<IconOrb>(find.byType(IconOrb))
          .singleWhere((o) => o.size == 56);
      expect(hero.tone, AppTone.success);
      expect(hero.glow, isTrue);
      expect(hero.shape, IconOrbShape.circle);

      // Link tek bir seçilebilir metin; geçerlilik bilgisi sunucu verisinden.
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('tok123uzunbirbaglantiornegi'), findsOneWidget);
      expect(find.text('Son geçerlilik: 01.01.2030 00:00'), findsOneWidget);
      expect(find.text('Kullanım hakkı: 1'), findsOneWidget);
      expect(
        find.text(
          'Kurye veya misafiriniz bu linke tıklayarak A Blok Ana Giriş Kapısı kapısını açabilir.',
        ),
        findsOneWidget,
      );

      // Kopyala: haptik + mevcut bildirim metni + pencere kapanır.
      await t.tap(find.text('Linki Kopyala'));
      await settleFor(t, 700);
      expect(messages, ['Geçiş linki panoya kopyalandı!']);
      expect(haptics.length, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'CreateGuestPassDialog: süresi geçmiş tarih için "Son geçerlilik" satırı gösterilmez (uydurma zaman yok)',
    (t) async {
      await openDialogAt(
        t,
        (context) => CreateGuestPassDialog.show(
          context,
          door: _door(),
          authService: _FakeAuth(expiresAt: DateTime(2020, 1, 1)),
          showMessage: (_) {},
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await scrollTo(t, find.text('Linki Oluştur'));
      await t.tap(find.text('Linki Oluştur'));
      await settleFor(t, 800);

      expect(find.text('🎉 Geçiş Linki Hazır!'), findsOneWidget);
      expect(find.textContaining('Son geçerlilik'), findsNothing);
      expect(find.text('Kullanım hakkı: 1'), findsOneWidget);
    },
  );

  testWidgets(
    'CreateGuestPassDialog: sunucu hatasında haptik verilmez ve hata kutusu görünür',
    (t) async {
      final haptics = recordHaptics(t);
      await openDialogAt(
        t,
        (context) => CreateGuestPassDialog.show(
          context,
          door: _door(),
          authService: _FakeAuth(error: 'Sunucuya ulaşılamadı.'),
          showMessage: (_) {},
        ),
        width: 360,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      await scrollTo(t, find.text('Linki Oluştur'));
      await t.tap(find.text('Linki Oluştur'));
      await settleFor(t, 800);

      expect(find.byType(InlineNotice), findsOneWidget);
      expect(find.text('Sunucuya ulaşılamadı.'), findsOneWidget);
      expect(haptics, isEmpty);
    },
  );
}
