// "Hesabımı Sil" sayfası (AccountDeletionView): önizleme -> silinecek / saklanacak -> engeller -> parola + "SİL" onayı
// -> başarıda yerel durum temizliği, giriş ekranına dönüş ve bilgi mesajı.
//
// Taşma matrisi (320x640 x2,0, 360x640 x1,5, yatay, tablet; açık + koyu), hata / yükleniyor / engelli durumlar,
// yanlış "boş" ileti yok, çift gönderim kilidi, geri tuşu koruması, silme sırasında çıkan engel (409).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/views/account_deletion_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'account_fixtures.dart';
import 'dialog_layout_harness.dart';

const Key _continue = ValueKey<String>('account_delete_continue');
const Key _password = ValueKey<String>('account_password_field');
const Key _word = ValueKey<String>('account_confirm_word_field');
const Key _submit = ValueKey<String>('account_dialog_submit');

Future<void> _pumpApp(
  WidgetTester t,
  Widget home, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _pumpPage(
  WidgetTester t,
  AccountHarness h, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
}) => _pumpApp(t, AccountDeletionView(service: h.service), width: width, height: height, scale: scale, dark: dark);

/// Ana sayfa (oturum açıkken "Hesap Sayfası" düğmesi silme sayfasını iter) / giriş ekranı (oturum kapanınca).
class _Host extends StatelessWidget {
  const _Host(this.h);

  final AccountHarness h;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: h.auth,
      builder: (context, _) {
        if (!h.auth.loggedIn) {
          return const Scaffold(body: Center(child: Text('Giriş Ekranı')));
        }
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => AccountDeletionView(service: h.service)),
              ),
              child: const Text('Hesap Sayfası'),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openPageFromHost(WidgetTester t, AccountHarness h) async {
  await _pumpApp(t, _Host(h));
  await t.tap(find.text('Hesap Sayfası'));
  await settleFor(t);
}

Future<void> _openConfirmDialog(WidgetTester t) async {
  await t.ensureVisible(find.byKey(_continue));
  await t.pump();
  await t.tap(find.byKey(_continue));
  await settleFor(t);
  expect(find.byType(AlertDialog), findsOneWidget);
}

ElevatedButton _submitButton(WidgetTester t) => t.widget<ElevatedButton>(find.byKey(_submit));

Future<void> _fillAndSubmit(WidgetTester t, {String password = 'Gizli123', String word = 'SİL'}) async {
  await t.enterText(find.byKey(_password), password);
  await t.enterText(find.byKey(_word), word);
  await t.pump();
  await t.tap(find.byKey(_submit));
  await t.pump();
}

void main() {
  group('taşma matrisi', () {
    accountLayoutMatrix('silinebilir: uyarı + silinecekler + saklanacaklar + düğmeler', (t, w, h, s, dark) async {
      await _pumpPage(t, AccountHarness(), width: w, height: h, scale: s, dark: dark);
      expect(find.text('Silinecekler'), findsOneWidget);
      expect(find.text('Saklanacaklar'), findsOneWidget);
      expect(find.textContaining('Adınız, e-posta adresiniz'), findsOneWidget);
      expect(find.textContaining('yasal saklama'), findsOneWidget);
      expect(find.text('Silmeye Devam Et'), findsOneWidget);
      expect(find.byType(ListSkeleton), findsNothing);
    });

    accountLayoutMatrix('engelli: nedenler (uzun site adı + site kodu + yönerge), devam kapalı', (t, w, h, s, dark) async {
      final harness = AccountHarness()
        ..api.preview = acPreview(canDelete: false, blockers: const [acLastManager, acSuperUser]);
      await _pumpPage(t, harness, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('account_blockers')), findsOneWidget);
      expect(find.text('Hesabınız şu anda silinemez'), findsOneWidget);
      expect(find.textContaining('tek yöneticisiniz'), findsOneWidget);
      expect(find.text('Site kodu: 12'), findsOneWidget);
      expect(find.textContaining('başka bir yönetici atayın'), findsOneWidget);
      expect(find.text('Süper kullanıcı hesabı bu ekrandan silinemez.'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNull);
    });

    accountLayoutMatrix('yükleniyor: iskelet, liste ve devam düğmesi yok', (t, w, h, s, dark) async {
      final harness = AccountHarness()..api.previewGate = Completer<void>();
      await _pumpPage(t, harness, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byKey(_continue), findsNothing);
      expect(find.text('Silinecekler'), findsNothing);
    });

    accountLayoutMatrix('hata: "Tekrar Dene", yanlış "silinecek yok" / devam yok', (t, w, h, s, dark) async {
      final harness = AccountHarness()..api.previewError = ApiException('Sunucu yanıt vermedi, tekrar deneyin.');
      await _pumpPage(t, harness, width: w, height: h, scale: s, dark: dark);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(_continue), findsNothing);
      expect(find.text('Silinecekler'), findsNothing);
    });

    accountLayoutMatrix('onay penceresi: SİL yazdırma + hata (320x640 x2,0 dahil)', (t, w, h, s, dark) async {
      final harness = AccountHarness()..api.deleteError = acWrongPassword();
      await _pumpPage(t, harness, width: w, height: h, scale: s, dark: dark);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      expect(find.text('Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.'), findsOneWidget);
    });
  });

  group('erişilebilirlik ve odak', () {
    testWidgets('bölüm başlıkları başlık anlamı taşır; engel kartı ve düğmeler etiketli', (t) async {
      final handle = t.ensureSemantics();
      final harness = AccountHarness()..api.preview = acPreview(canDelete: false, blockers: const [acLastManager]);
      await _pumpPage(t, harness);
      for (final title in <String>['Silinecekler', 'Saklanacaklar', 'Hesabınız şu anda silinemez']) {
        expect(t.getSemantics(find.text(title)).flagsCollection.isHeader, isTrue, reason: title);
      }
      expect(find.byTooltip('Yenile'), findsOneWidget, reason: 'simge düğmesi ipucu (ekran okuyucu etiketi) taşır');
      expect(find.bySemanticsLabel('Silmeye Devam Et'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('silme sırasında engel çıkınca ekran okuyucuya duyurulur', (t) async {
      final messages = captureAnnouncements(t);
      final h = AccountHarness()
        ..api.deleteError = AccountDeleteBlockedException(
          'Hesabınız şu anda silinemez. Nedenleri aşağıda görebilirsiniz.',
          blockers: const [acLastManager],
        );
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      expect(messages, contains('Hesabınız şu anda silinemez.'));
    });

    testWidgets('yanlış şifre sonrası odak diyalogdaki hata kutusunda; Vazgeç sayfada devam düğmesine döner', (t) async {
      final h = AccountHarness()..api.deleteError = acWrongPassword();
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      expect(
        t.widget<Focus>(find.byKey(const ValueKey<String>('account_dialog_error_focus'))).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      await t.tap(find.byKey(const ValueKey<String>('account_dialog_cancel')));
      await settleFor(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNotNull, reason: 'sayfa kullanılabilir kalır');
    });

    testWidgets('başarıdan sonra silme sayfasının hiçbir öğesi odakta kalmaz (giriş ekranı odağı alır)', (t) async {
      final h = AccountHarness();
      await _openPageFromHost(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(AccountDeletionView), findsNothing);
      final primary = FocusManager.instance.primaryFocus;
      expect(primary?.context?.mounted ?? true, isTrue, reason: 'odak kapanmış sayfadaki bir öğede asılı kalmaz');
      expect(find.text('Giriş Ekranı'), findsOneWidget);
    });
  });

  group('önizleme durumları', () {
    testWidgets('önizleme YENİLENİRKEN eski önizleme görünür ama "Silmeye Devam Et" KAPALI; yanıtla açılır', (t) async {
      final h = AccountHarness();
      await _pumpPage(t, h);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNotNull);

      final gate = Completer<void>();
      h.api.previewGate = gate;
      await t.tap(find.byTooltip('Yenile'));
      await t.pump();
      expect(find.text('Silinecekler'), findsOneWidget, reason: 'eski liste yenilenirken kalır');
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNull, reason: 'bayat önizlemeyle ilerlenemez');
      expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh_rounded)).onPressed, isNull);

      gate.complete();
      await settleFor(t);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNotNull);
    });

    testWidgets('önizleme yüklenir: tek istek; yenile düğmesi yeniden çeker', (t) async {
      final h = AccountHarness();
      await _pumpPage(t, h);
      expect(h.api.previewCalls, 1);
      await t.tap(find.byTooltip('Yenile'));
      await settleFor(t);
      expect(h.api.previewCalls, 2);
      expect(find.text('Silinecekler'), findsOneWidget);
    });

    testWidgets('hata -> Tekrar Dene -> yüklenir', (t) async {
      final h = AccountHarness()..api.previewError = ApiException('Sunucuya bağlanılamadı.');
      await _pumpPage(t, h);
      expect(find.text('Sunucuya bağlanılamadı.'), findsOneWidget);
      expect(find.byKey(_continue), findsNothing);

      h.api.previewError = null;
      await t.tap(find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.text('Silinecekler'), findsOneWidget);
      expect(find.byKey(_continue), findsOneWidget);
      expect(find.text('Sunucuya bağlanılamadı.'), findsNothing);
    });

    testWidgets('can_delete true ama silinecekler boş: bilgilendirilmiş onay verilemez -> hata, devam yok', (t) async {
      final h = AccountHarness()..api.preview = acPreview(willRemove: const <String>[]);
      await _pumpPage(t, h);
      expect(find.text('Silinecek verilerin ayrıntısı alınamadı. Lütfen tekrar deneyin.'), findsOneWidget);
      expect(find.byKey(_continue), findsNothing);
    });

    testWidgets('engelli: devam düğmesine dokunmak pencere AÇMAZ; açıklama görünür', (t) async {
      final h = AccountHarness()..api.preview = acPreview(canDelete: false, blockers: const [acSuperUser]);
      await _pumpPage(t, h);
      await t.ensureVisible(find.byKey(_continue));
      await t.tap(find.byKey(_continue), warnIfMissed: false);
      await settleFor(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Yukarıdaki engeller kalkmadan hesabınız silinemez.'), findsOneWidget);
      expect(find.byType(AppCard), findsWidgets);
    });

    testWidgets('can_delete false ama engel listesi boş: genel neden metni (sessiz ilerleme yok)', (t) async {
      final h = AccountHarness()..api.preview = acPreview(canDelete: false);
      await _pumpPage(t, h);
      expect(find.textContaining('Ayrıntı için destek ekibiyle iletişime geçin'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNull);
    });
  });

  group('silme onayı', () {
    testWidgets('"SİL" yazılana dek düğme kapalı; büyük/küçük harf ve SIL/sil kabul edilir', (t) async {
      final h = AccountHarness();
      await _pumpPage(t, h);
      await _openConfirmDialog(t);

      await t.enterText(find.byKey(_password), 'Gizli123');
      await t.pump();
      expect(_submitButton(t).onPressed, isNull, reason: 'onay sözcüğü yok');

      for (final wrong in <String>['SİLME', 'S', 'delete', '']) {
        await t.enterText(find.byKey(_word), wrong);
        await t.pump();
        expect(_submitButton(t).onPressed, isNull, reason: '"$wrong"');
      }
      for (final ok in <String>['SİL', 'sil', 'SIL', ' Sil ', 'sİl']) {
        await t.enterText(find.byKey(_word), ok);
        await t.pump();
        expect(_submitButton(t).onPressed, isNotNull, reason: '"$ok"');
      }
      expect(h.api.deletePasswords, isEmpty);
    });

    testWidgets('şifre boş: doğrulama iletisi, sunucuya gidilmez', (t) async {
      final h = AccountHarness();
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await t.enterText(find.byKey(_word), 'SİL');
      await t.pump();
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(find.text('Devam etmek için şifrenizi girin.'), findsWidgets);
      expect(h.api.deletePasswords, isEmpty);
    });

    testWidgets('yanlış şifre: pencere AÇIK, ileti görünür, hiçbir yerel durum silinmez, oturum kapanmaz', (t) async {
      final h = AccountHarness()..api.deleteError = acWrongPassword();
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t, password: 'yanlis');
      await settleFor(t);

      expect(h.api.deletePasswords, <String>['yanlis']);
      expect(find.text('Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(h.auth.logoutCalls, 0);
      expect(h.wiper.wipes, 0);
      expect(h.auth.forcedRefreshes, 0);
    });

    testWidgets('silme sırasında engel çıkar (409): pencere kapanır, sayfa nedenleri gösterir, devam kapanır', (t) async {
      final h = AccountHarness()
        ..api.deleteError = AccountDeleteBlockedException(
          'Hesabınız şu anda silinemez. Nedenleri aşağıda görebilirsiniz.',
          blockers: const [acLastManager],
        );
      await _pumpPage(t, h);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNotNull);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey<String>('account_blockers')), findsOneWidget);
      expect(find.textContaining('tek yöneticisiniz'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(_continue)).onPressed, isNull);
      expect(h.auth.logoutCalls, 0);
      expect(h.wiper.wipes, 0);
      expect(find.text('Silinecekler'), findsOneWidget, reason: 'önceki listeler korunur');
    });

    testWidgets('çift dokunuş: silme isteği TEK kez gider; sürerken geri tuşu ve Vazgeç kapatmaz', (t) async {
      final h = AccountHarness()..api.deleteGate = Completer<void>();
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await t.tap(find.byKey(_submit), warnIfMissed: false);
      await t.pump();

      expect(h.api.deletePasswords, hasLength(1));
      expect(find.text('Siliniyor...'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNull);
      expect(t.widget<TextButton>(find.byKey(const ValueKey<String>('account_dialog_cancel'))).onPressed, isNull);

      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      await navigator.maybePop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(h.auth.logoutCalls, 0, reason: 'sunucu yanıtı gelmeden yerel durum silinmez');

      h.api.deleteGate!.complete();
      await settleFor(t);
    });

    testWidgets('sunucu hatası (5xx): ileti pencerede, yerel durum DURUR, tekrar denenebilir', (t) async {
      final h = AccountHarness()
        ..api.deleteError = ApiException('Hesap silinemedi. (Hata kodu: E-1)', statusCode: 500);
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      expect(find.text('Hesap silinemedi. (Hata kodu: E-1)'), findsOneWidget);
      expect(h.wiper.wipes, 0);
      expect(_submitButton(t).onPressed, isNotNull);

      h.api.deleteError = null;
      await t.tap(find.byKey(_submit));
      await settleFor(t);
      expect(h.api.deletePasswords, hasLength(2));
      expect(h.wiper.wipes, 1);
    });

    testWidgets('kilitli parola (429): ileti + düğme kilitli', (t) async {
      final h = AccountHarness()
        ..api.deleteError = ApiException(
          'Şifre için çok fazla hatalı deneme yapıldı. 15 dakika sonra tekrar deneyin.',
          statusCode: 429,
          code: 'CURRENT_PASSWORD_LOCKED',
          retryAfterSeconds: 900,
        );
      await _pumpPage(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      expect(find.textContaining('15 dakika sonra tekrar deneyin'), findsOneWidget);
      expect(_submitButton(t).onPressed, isNull);
    });
  });

  group('başarı: yerel temizlik, girişe dönüş, bilgi mesajı', () {
    testWidgets('çıkış -> yerel temizlik; tüm sayfalar kapanır; giriş ekranında bilgi mesajı', (t) async {
      final h = AccountHarness();
      await _openPageFromHost(t, h);
      expect(find.text('Silinecekler'), findsOneWidget);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      await t.pump(const Duration(seconds: 1));

      expect(h.api.deletePasswords, <String>['Gizli123']);
      expect(
        h.order,
        <String>['hint', 'logout', 'wipe'],
        reason: 'kayıtlı e-posta, sonra merkezi çıkış, sonra yerel temizlik',
      );
      expect(h.auth.loggedIn, isFalse);
      expect(find.text('Giriş Ekranı'), findsOneWidget);
      expect(find.byType(AccountDeletionView), findsNothing, reason: 'silme sayfası da kapanır');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(AccountDeletionView.deletedMessage), findsOneWidget, reason: 'bilgi mesajı giriş ekranında');
    });

    testWidgets('yerel temizlik EKSİK kaldıysa ileti "temizlendi" DEMEZ; dürüst uyarı gösterilir', (t) async {
      final h = AccountHarness();
      h.wiper.report = const LocalWipeReport(failedSteps: <String>['secure_storage']);
      await _openPageFromHost(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      await t.pump(const Duration(seconds: 1));
      expect(find.text(AccountDeletionView.deletedPartialMessage), findsOneWidget);
      expect(find.text(AccountDeletionView.deletedMessage), findsNothing);
      expect(find.textContaining('cihaz ayarlarından temizleyin'), findsOneWidget);
      expect(h.auth.loggedIn, isFalse, reason: 'hesap yine de silindi, oturum kapandı');
    });

    testWidgets('bilgi mesajı hesap sayfası kapandıktan sonra da ekranda kalır (süre dolana dek)', (t) async {
      final h = AccountHarness();
      await _openPageFromHost(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      await t.pump(const Duration(seconds: 5));
      expect(find.text(AccountDeletionView.deletedMessage), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pump(const Duration(seconds: 1));
      expect(find.text(AccountDeletionView.deletedMessage), findsNothing, reason: '8 sn sonra kapanır');
    });

    testWidgets('hesap zaten silinmişse (401 ACCOUNT_DELETED) hedef durum sağlanmıştır: yerel temizlik yapılır', (t) async {
      final h = AccountHarness()
        ..api.deleteError = SessionExpiredException('Bu hesap silinmiş.', 'ACCOUNT_DELETED');
      await _openPageFromHost(t, h);
      await _openConfirmDialog(t);
      await _fillAndSubmit(t);
      await settleFor(t);
      await t.pump(const Duration(seconds: 1));
      expect(h.order, <String>['hint', 'logout', 'wipe']);
      expect(h.auth.forcedRefreshes, 0);
      expect(find.text('Giriş Ekranı'), findsOneWidget);
    });
  });
}
