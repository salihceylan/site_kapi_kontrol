// Profil -> "Gizlilik ve Veri" bölümü (AccountPrivacySection) ve parola penceresi (AccountPasswordDialog).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5 (+ yatay 640x360, tablet 820x1180), açık + koyu tema; taşma yok.
// Davranış: parola doğrulaması, doğru Türkçe hata iletileri (CURRENT_PASSWORD_*, EXPORT_RATE_LIMITED), yanlış
// parolada pencere AÇIK kalır / alan temizlenir / odak döner, çift gönderim yok, işlem sürerken geri tuşu
// kapatmaz, hazır dosya paylaşım menüsü kapansa da bellekte kalır ve "Kapat" ile atılır.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/account_password_dialog.dart';
import 'package:site_kapi_kontrol/ui/widgets/account_privacy_section.dart';

import 'account_fixtures.dart';
import 'dialog_layout_harness.dart';
import 'list_fixtures.dart';

const Key _exportButton = ValueKey<String>('account_export_button');
const Key _deleteButton = ValueKey<String>('account_delete_button');
const Key _passwordField = ValueKey<String>('account_password_field');
const Key _submit = ValueKey<String>('account_dialog_submit');
const Key _cancel = ValueKey<String>('account_dialog_cancel');
const Key _discard = ValueKey<String>('account_export_discard');

/// Bölüm açılışında çalışan "kalıntı süpürme" çağrı sayısı (gerçek disk yerine sahte).
final List<int> _sweeps = <int>[];

Future<GlobalKey<AccountPrivacySectionState>> _pump(
  WidgetTester t,
  AccountHarness h, {
  double width = 400,
  double height = 1100,
  double scale = 1.0,
  bool dark = false,
}) async {
  final key = GlobalKey<AccountPrivacySectionState>();
  await pumpList(
    t,
    AccountPrivacySection(
      key: key,
      authService: h.auth,
      service: h.service,
      sharer: h.sharer,
      sweepLeftovers: () async => _sweeps.add(1),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  return key;
}

Future<void> _tapKey(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pump();
  await t.tap(find.byKey(key));
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _enterPassword(WidgetTester t, String value) async {
  await t.enterText(find.byKey(_passwordField), value);
  await t.pump();
}

Finder get _dialog => find.byType(AlertDialog);

TextField _passwordTextField(WidgetTester t) => t.widget<TextField>(
  find.descendant(of: find.byKey(_passwordField), matching: find.byType(TextField)),
);

ElevatedButton _submitButton(WidgetTester t) => t.widget<ElevatedButton>(find.byKey(_submit));

void main() {
  setUp(_sweeps.clear);

  group('taşma matrisi: bölüm', () {
    listMatrix('boş durum: iki eylem de görünür', (t, w, h, s, dark) async {
      await _pump(t, AccountHarness(), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Gizlilik ve Veri'), findsOneWidget);
      expect(find.byKey(_exportButton), findsOneWidget);
      expect(find.byKey(_deleteButton), findsOneWidget);
      expect(find.text('Verilerimi İndir'), findsNWidgets(2), reason: 'blok başlığı + düğme');
      expect(find.text('Hesabımı Sil'), findsNWidgets(2));
    });

    listMatrix('dosya hazır kartı (uzun dosya adı) taşmaz', (t, w, h, s, dark) async {
      final harness = AccountHarness()
        ..api.export = acExport(name: 'kisisel-veri-4242424242-20261016-cok-uzun-bir-dosya-adi-ornegi.json');
      await _pump(t, harness, width: w, height: h, scale: s, dark: dark);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await _tapKey(t, _submit);
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('account_export_ready')), findsOneWidget);
      expect(find.text('Paylaş / Kaydet'), findsOneWidget);
      expect(find.byKey(_discard), findsOneWidget);
    });
  });

  group('taşma matrisi: parola penceresi', () {
    accountLayoutMatrix('dışa aktarma penceresi', (t, w, h, s, dark) async {
      await openDialogAt(
        t,
        (context) => AccountPasswordDialog.show<bool>(
          context,
          title: 'Verilerimi İndir',
          icon: Icons.download_rounded,
          message:
              'Hesabınıza ait kişisel verilerin bir kopyasını JSON dosyası olarak hazırlarız. Devam etmek için '
              'şifrenizi girin. Bu işlem 24 saat içinde en fazla 3 kez yapılabilir.',
          confirmLabel: 'Verilerimi Hazırla',
          busyLabel: 'Hazırlanıyor...',
          onSubmit: (_) async => true,
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      expect(find.text('Şifreniz'), findsOneWidget);
      expect(find.byKey(_submit), findsOneWidget);
    });

    accountLayoutMatrix('silme onayı (SİL yazdırma) + hata kutusu', (t, w, h, s, dark) async {
      await openDialogAt(
        t,
        (context) => AccountPasswordDialog.show<bool>(
          context,
          title: 'Hesabı kalıcı olarak sil',
          icon: Icons.delete_forever_rounded,
          message: 'Bu işlem geri alınamaz. Hesabınız silinecek ve oturumunuz kapanacak.',
          confirmLabel: 'Hesabımı Sil',
          busyLabel: 'Siliniyor...',
          confirmWord: 'SİL',
          onSubmit: (_) async => throw acWrongPassword(),
        ),
        width: w,
        height: h,
        scale: s,
        dark: dark,
      );
      await t.enterText(find.byKey(const ValueKey<String>('account_confirm_word_field')), 'SİL');
      await _enterPassword(t, 'x');
      await t.pump();
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(find.text('Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.'), findsOneWidget);
    });

    testWidgets('klavye açık yatay telefon (640x360): gönder düğmesi görünür alanda kalır', (t) async {
      await openDialogAt(
        t,
        (context) => AccountPasswordDialog.show<bool>(
          context,
          title: 'Hesabı kalıcı olarak sil',
          icon: Icons.delete_forever_rounded,
          message: 'Bu işlem geri alınamaz.',
          confirmLabel: 'Hesabımı Sil',
          busyLabel: 'Siliniyor...',
          confirmWord: 'SİL',
          onSubmit: (_) async => true,
        ),
        width: 640,
        height: 360,
        scale: 1.0,
        dark: false,
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final rect = t.getRect(find.byKey(_submit));
      expect(rect.bottom, lessThanOrEqualTo(360 - 200 + 0.5), reason: 'klavyenin üstünde, kaybolmaz');
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(t.takeException(), isNull);
    });

    testWidgets('klavye açık 320x640 x2,0: alanlar kaydırılabilir, taşma yok, düğme erişilebilir', (t) async {
      await openDialogAt(
        t,
        (context) => AccountPasswordDialog.show<bool>(
          context,
          title: 'Hesabı kalıcı olarak sil',
          icon: Icons.delete_forever_rounded,
          message: 'Bu işlem geri alınamaz. Hesabınız silinecek ve oturumunuz kapanacak.',
          confirmLabel: 'Hesabımı Sil',
          busyLabel: 'Siliniyor...',
          confirmWord: 'SİL',
          onSubmit: (_) async => true,
        ),
        width: 320,
        height: 640,
        scale: 2.0,
        dark: false,
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      final rect = t.getRect(find.byKey(_submit));
      expect(rect.bottom, lessThanOrEqualTo(640 - 300 + 0.5));
    });
  });

  group('Verilerimi İndir', () {
    testWidgets('boş şifre: doğrulama iletisi, sunucuya gidilmez, pencere açık kalır', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      expect(find.text('Verilerimi İndir'), findsWidgets);
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(find.text('Devam etmek için şifrenizi girin.'), findsWidgets);
      expect(h.api.exportPasswords, isEmpty);
      expect(_dialog, findsOneWidget);
    });

    testWidgets('yanlış şifre: Türkçe ileti, pencere AÇIK, alan temizlenir ve odaklanır, oturum kapanmaz', (t) async {
      final h = AccountHarness();
      h.api.exportError = acWrongPassword();
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'yanlis');
      await t.tap(find.byKey(_submit));
      await settleFor(t);

      expect(h.api.exportPasswords, <String>['yanlis']);
      expect(find.text('Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(_dialog, findsOneWidget);
      expect(_passwordTextField(t).controller!.text, isEmpty, reason: 'yanlış parola alanı temizlenir');
      // Odak parola alanına DÖNMEZ (klavye hata kutusunu örterdi); hata kutusuna gelir.
      expect(_passwordTextField(t).focusNode!.hasFocus, isFalse);
      expect(
        t.widget<Focus>(find.byKey(const ValueKey<String>('account_dialog_error_focus'))).focusNode!.hasPrimaryFocus,
        isTrue,
        reason: 'hata sonrası odak hata kutusunda',
      );
      expect(h.auth.logoutCalls, 0);
      expect(h.sharer.shared, isEmpty);

      // Düzeltip yeniden dener: başarı.
      h.api.exportError = null;
      await _enterPassword(t, 'dogru');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(h.api.exportPasswords, <String>['yanlis', 'dogru']);
      expect(_dialog, findsNothing);
    });

    testWidgets('klavye AÇIKKEN (320x640 x2,0) yanlış şifre iletisi görünür bölgede kalır; alan ve düğme erişilebilir', (t) async {
      final h = AccountHarness();
      h.api.exportError = acWrongPassword();
      final messages = captureAnnouncements(t);
      await _pump(t, h, width: 320, height: 640, scale: 2.0);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'yanlis');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 600));

      final error = find.text('Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.');
      expect(error, findsOneWidget);
      final rect = t.getRect(error);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300 + 0.5), reason: 'klavyenin üstünde, örtülmez');
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(t.getRect(find.byKey(_submit)).bottom, lessThanOrEqualTo(640 - 300 + 0.5), reason: 'düğme de görünür');
      expect(messages.any((m) => m.contains('Şifreniz hatalı')), isTrue, reason: 'ekran okuyucuya duyurulur');
      expect(t.takeException(), isNull);
    });

    testWidgets('sunucunun kabul ettiği 1024 karakterlik mevcut parola kesilmeden gönderilir', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      final longPassword = 'a' * 1024;
      await _enterPassword(t, longPassword);
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(h.api.exportPasswords.single.length, 1024);
      expect(AccountPasswordDialog.maxPasswordLength, 1024);
    });

    testWidgets('bölüm açılınca diskte kalmış kişisel veri kalıntıları süpürülür (bir kez)', (t) async {
      await _pump(t, AccountHarness());
      expect(_sweeps, hasLength(1));
      await t.pump(const Duration(seconds: 1));
      expect(_sweeps, hasLength(1), reason: 'yeniden kurmadan tekrarlanmaz');
    });

    testWidgets('odak geri döner: Vazgeç sonrası "Verilerimi İndir"e; Kapat sonrası yine ona; başarıda "Paylaş / Kaydet"e', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      OutlinedButton exportButton() => t.widget<OutlinedButton>(find.byKey(_exportButton));

      await _tapKey(t, _exportButton);
      await t.tap(find.byKey(_cancel));
      await settleFor(t);
      expect(exportButton().focusNode!.hasPrimaryFocus, isTrue, reason: 'Vazgeç sonrası odak düğmede');

      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      final share = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Paylaş / Kaydet'));
      expect(share.focusNode!.hasPrimaryFocus, isTrue, reason: 'başarıdan sonra odak hazır dosyada');

      await _tapKey(t, _discard);
      expect(exportButton().focusNode!.hasPrimaryFocus, isTrue, reason: 'Kapat sonrası odak düğmede');
    });

    testWidgets('başarı: dosya paylaşıma verilir, "hazır" kartı çıkar (ad + boyut); "Kapat" bellekten atar', (t) async {
      final h = AccountHarness();
      final key = await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);

      expect(h.sharer.shared, hasLength(1));
      expect(h.sharer.shared.single.fileName, 'kisisel-veri-42-20261016.json');
      expect(find.byKey(const ValueKey<String>('account_export_ready')), findsOneWidget);
      expect(find.textContaining('kisisel-veri-42-20261016.json'), findsOneWidget);
      expect(find.textContaining('12 KB'), findsOneWidget);
      expect(key.currentState!.pendingExport, isNotNull);

      await _tapKey(t, _discard);
      expect(key.currentState!.pendingExport, isNull, reason: 'Kapat veriyi bellekten atar');
      expect(find.byKey(const ValueKey<String>('account_export_ready')), findsNothing);
    });

    testWidgets('paylaşım menüsü kapatılınca "Paylaş / Kaydet" aynı dosyayı yeniden sunar (sunucuya gitmeden)', (t) async {
      final h = AccountHarness();
      h.sharer.outcome = ExportShareOutcome.dismissed;
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(h.sharer.shared, hasLength(1));

      await t.ensureVisible(find.text('Paylaş / Kaydet'));
      await t.tap(find.text('Paylaş / Kaydet'));
      await settleFor(t);
      expect(h.sharer.shared, hasLength(2));
      expect(identical(h.sharer.shared[0], h.sharer.shared[1]), isTrue);
      expect(h.api.exportPasswords, hasLength(1), reason: 'yeniden paylaşım dışa aktarma hakkını harcamaz');
    });

    testWidgets('paylaşım menüsü açılamazsa hata görünür, dosya hazır kalır, yeniden denenebilir', (t) async {
      final h = AccountHarness();
      h.sharer.error = StateError('paylaşım yok');
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);

      expect(find.textContaining('Paylaşım menüsü açılamadı'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('account_export_ready')), findsOneWidget);

      h.sharer.error = null;
      await t.ensureVisible(find.text('Paylaş / Kaydet'));
      await t.tap(find.text('Paylaş / Kaydet'));
      await settleFor(t);
      expect(find.textContaining('Paylaşım menüsü açılamadı'), findsNothing);
    });

    testWidgets('hız sınırı (EXPORT_RATE_LIMITED): doğru Türkçe, gönder düğmesi süre dolana dek kilitli', (t) async {
      final h = AccountHarness();
      h.api.exportError = acExportLimited(retryAfter: 30);
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);

      expect(
        find.text('Kişisel verilerinizi 24 saat içinde en fazla 3 kez indirebilirsiniz. 5 saat sonra tekrar deneyin.'),
        findsOneWidget,
      );
      expect(_submitButton(t).onPressed, isNull, reason: 'kilitli');
      await t.pump(const Duration(seconds: 31));
      expect(_submitButton(t).onPressed, isNotNull, reason: 'süre dolunca açılır');
    });

    testWidgets('kilitli parola (CURRENT_PASSWORD_LOCKED): ileti + bekleme, alan temizlenir', (t) async {
      final h = AccountHarness();
      h.api.exportError = ApiException(
        'Şifre için çok fazla hatalı deneme yapıldı. 15 dakika sonra tekrar deneyin.',
        statusCode: 429,
        code: 'CURRENT_PASSWORD_LOCKED',
        retryAfterSeconds: 900,
      );
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'x');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(find.textContaining('15 dakika sonra tekrar deneyin'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNull);
      expect(_passwordTextField(t).controller!.text, isEmpty);
    });

    testWidgets('çift dokunuş: istek tek kez gider; işlem sürerken Vazgeç / geri tuşu pencereyi kapatmaz', (t) async {
      final h = AccountHarness();
      h.api.exportGate = Completer<void>();
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await t.pump();
      await t.tap(find.byKey(_submit), warnIfMissed: false);
      await t.pump();

      expect(h.api.exportPasswords, hasLength(1), reason: 'çift gönderim yok');
      expect(find.text('Hazırlanıyor...'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNull);
      expect(t.widget<TextButton>(find.byKey(_cancel)).onPressed, isNull);

      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      await navigator.maybePop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(_dialog, findsOneWidget, reason: 'geri tuşu işlem sürerken pencereyi kapatmaz');

      h.api.exportGate!.complete();
      await settleFor(t);
      expect(_dialog, findsNothing);
      expect(h.sharer.shared, hasLength(1));
    });

    testWidgets('ağ hatası: ileti pencerede, tekrar denenebilir', (t) async {
      final h = AccountHarness();
      h.api.exportError = ApiException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(find.textContaining('Sunucuya bağlanılamadı'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNotNull);
      expect(_passwordTextField(t).controller!.text, 'Gizli123', reason: 'ağ hatasında şifre korunur');
    });

    testWidgets('Vazgeç: sunucuya gidilmez', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      await t.tap(find.byKey(_cancel));
      await settleFor(t);
      expect(_dialog, findsNothing);
      expect(h.api.exportPasswords, isEmpty);
      expect(h.sharer.shared, isEmpty);
    });

    testWidgets('şifre alanı gizli ve öneri / otomatik düzeltme kapalı; göster düğmesi çalışır', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      await _tapKey(t, _exportButton);
      var field = _passwordTextField(t);
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      await t.tap(find.byTooltip('Şifreyi göster'));
      await t.pump();
      expect(_passwordTextField(t).obscureText, isFalse);
      expect(find.byTooltip('Şifreyi gizle'), findsOneWidget);
    });

    testWidgets('hesap değişince (yeni AuthService) önceki hesabın hazır dosyası atılır', (t) async {
      final h = AccountHarness();
      final key = await _pump(t, h);
      await _tapKey(t, _exportButton);
      await _enterPassword(t, 'Gizli123');
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(key.currentState!.pendingExport, isNotNull);

      final other = AccountHarness();
      await pumpList(
        t,
        AccountPrivacySection(key: key, authService: other.auth, service: other.service, sharer: other.sharer),
        width: 400,
        height: 1100,
        scale: 1.0,
        dark: false,
      );
      expect(key.currentState!.pendingExport, isNull);
    });
  });

  group('Hesabımı Sil girişi', () {
    testWidgets('düğme silme sayfasını açar; önizleme istenir; geri dönünce düğme yeniden etkin', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      await _tapKey(t, _deleteButton);
      await settleFor(t);
      expect(find.text('Hesabımı Sil'), findsWidgets);
      expect(h.api.previewCalls, 1);
      expect(find.text('Silinecekler'), findsOneWidget);

      await t.pageBack();
      await settleFor(t);
      expect(find.byKey(_deleteButton), findsOneWidget);
      expect(t.widget<OutlinedButton>(find.byKey(_deleteButton)).onPressed, isNotNull);
    });

    testWidgets('silme sayfasından Vazgeç ile dönünce odak "Hesabımı Sil" düğmesine gelir', (t) async {
      final h = AccountHarness();
      await _pump(t, h);
      await _tapKey(t, _deleteButton);
      await settleFor(t);
      await t.tap(find.byKey(const ValueKey<String>('account_delete_cancel')));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(t.widget<OutlinedButton>(find.byKey(_deleteButton)).focusNode!.hasPrimaryFocus, isTrue);
    });

    testWidgets('bölüm AppCard içinde tek kart', (t) async {
      await _pump(t, AccountHarness());
      expect(find.descendant(of: find.byType(AccountPrivacySection), matching: find.byType(AppCard)), findsOneWidget);
    });

    testWidgets('süper kullanıcı için de görünür (silme engeli sunucudan gelir)', (t) async {
      final h = AccountHarness(role: UserRole.superUser);
      h.api.preview = acPreview(canDelete: false, blockers: const [acSuperUser]);
      await _pump(t, h);
      expect(find.byKey(_deleteButton), findsOneWidget);
    });
  });
}
