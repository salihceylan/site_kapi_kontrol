// FAZ 5 / A2-G1: giriş ekranı (LoginPage) taşma + tasarım sistemi testleri.
//
// AGENTS.md kural 6: hiçbir ekranda taşma olmaz. Matris: 320x640 x2,0 ve 360x640 x1,5, her biri açık
// ve koyu temada; doğrulama hataları, SnackBar'lar, yüklenme durumu ve "Şifremi Unuttum" diyaloğu
// (AppDialog + InlineNotice) da bu ölçülerde kurulur. Davranış (giriş/şifre sıfırlama çağrıları,
// "beni hatırla", gezinme) ve metinler değişmez; yalnız görünüm: LoginHero, AppCard(2),
// PrimaryActionButton(loading), AppDialog, InlineNotice, AppSnack; tek zemin (kökte); 44 dp
// "Yeni Hesap Oluştur"/"Şifremi Unuttum?" düğmeleri.
//
// Not: widget testleri Ahem yazı tipiyle çalışır (her harf 1 em genişliğinde): satır sarma gerçek
// cihazdan daha serttir; geçen taşma testi gerçek yazı tipinde de geçer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/login_hero.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';

import '../design/harness.dart';

/// Sahte kimlik servisi: ağa çıkmaz; giriş / şifre sıfırlama sonuçları ve bekleme durumları
/// test tarafından belirlenir.
class _FakeAuth extends AuthService {
  _FakeAuth({this.notice, this.onLogin, this.onForgot})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final String? notice;
  final Future<String?> Function(String identifier, String password)? onLogin;
  final Future<String?> Function(String email)? onForgot;
  final List<String> logins = <String>[];
  final List<String> forgots = <String>[];

  @override
  String? takeSessionNotice() => notice;

  @override
  Future<String?> login({
    required String email,
    required String password,
    UserRole? role,
  }) async {
    logins.add(email);
    final handler = onLogin;
    return handler == null ? null : handler(email, password);
  }

  @override
  Future<String?> forgotPassword({required String email}) async {
    forgots.add(email);
    final handler = onForgot;
    return handler == null ? null : handler(email);
  }
}

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

const String _longError =
    'Çok fazla hatalı deneme yapıldı. Hesabınız güvenlik nedeniyle geçici olarak kilitlendi; '
    '5 dakika sonra tekrar deneyin ya da şifrenizi sıfırlayın.';

const String _forgotSuccess =
    'Bu e-posta adresiyle kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi. '
    'Lütfen gelen kutunuzu (ve gereksiz klasörünü) kontrol ediniz.';

Finder get _identifierField => find.byType(TextFormField).at(0);
Finder get _passwordField => find.byType(TextFormField).at(1);
Finder get _dialogField => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextFormField),
);

/// Sayfayı verilen ölçüde kurar (pumpAt gövdeyi kaydırılabilir sarar: sayfaya sabit boyut verilir).
Future<void> _pumpLogin(
  WidgetTester t,
  _FakeAuth auth, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
}) {
  return pumpAt(
    t,
    SizedBox(
      width: width,
      height: height,
      child: LoginPage(authService: auth),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

/// Metni görünür kılıp dokunur. Önceki yazma, imleci görünür kılmak için kısa bir kaydırma
/// başlatır; kaydırma animasyonu sürerken kaydırılabilir alan işaretçileri yok sayar: dokunmadan
/// önce animasyonlar bitene dek zaman ilerletilir.
Future<void> _tapText(WidgetTester t, String text) async {
  final target = find.text(text);
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(target);
}

Future<void> _fillAndSubmit(WidgetTester t) async {
  await t.enterText(_identifierField, 'ali@example.com');
  await t.enterText(_passwordField, 'parola123');
  await _tapText(t, 'Giriş Yap');
  // İlk kare ticker'ı başlatır; ikincisi animasyonu ilerletir (Pop/SnackBar girişi).
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _openForgotDialog(WidgetTester t) async {
  await _tapText(t, 'Şifremi Unuttum?');
  await t.pumpAndSettle();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final (w, h, s) in _cells) {
    for (final dark in const <bool>[false, true]) {
      final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

      group('LoginPage taşma matrisi ($cell)', () {
        testWidgets('ilk kurulum: tüm öğeler var, taşma yok', (t) async {
          await _pumpLogin(
            t,
            _FakeAuth(),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );

          expect(find.text('AHBU Giriş'), findsOneWidget);
          expect(
            find.text('Akıllı Kapı & Site Otomasyon Paneli'),
            findsOneWidget,
          );
          expect(find.text('E-posta veya Kullanıcı Adı'), findsOneWidget);
          expect(find.text('Şifre'), findsOneWidget);
          expect(
            find.text('Beni Hatırla (Kullanıcı adını kaydet)'),
            findsOneWidget,
          );
          expect(find.text('Şifremi Unuttum?'), findsOneWidget);
          expect(find.text('Giriş Yap'), findsOneWidget);
          expect(find.text('Hesabınız yok mu? '), findsOneWidget);
          expect(find.text('Yeni Hesap Oluştur'), findsOneWidget);
          expect(find.text(AppConfig.versionDisplay), findsOneWidget);
        });

        testWidgets('boş formda doğrulama hataları taşmadan gösterilir', (
          t,
        ) async {
          await _pumpLogin(
            t,
            _FakeAuth(),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          await _tapText(t, 'Giriş Yap');
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));

          expect(
            find.text('Lütfen e-posta veya kullanıcı adınızı girin.'),
            findsOneWidget,
          );
          expect(find.text('Lütfen şifrenizi girin.'), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets(
          'uzun giriş hatası SnackBar\'ı hata tonunda, taşmadan gösterilir',
          (t) async {
            final auth = _FakeAuth(onLogin: (_, _) async => _longError);
            await _pumpLogin(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _fillAndSubmit(t);

            expect(auth.logins, <String>['ali@example.com']);
            expect(find.text(_longError), findsOneWidget);
            final snack = t.widget<SnackBar>(find.byType(SnackBar));
            expect(snack.backgroundColor, AppTone.danger.b);
            expect(t.takeException(), isNull);
          },
        );

        testWidgets(
          'oturum sonu bildirimi (uyarı tonu, 6 sn) taşmadan gösterilir',
          (t) async {
            const notice =
                'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.';
            await _pumpLogin(
              t,
              _FakeAuth(notice: notice),
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await t.pump(const Duration(milliseconds: 400));

            expect(find.text(notice), findsOneWidget);
            final snack = t.widget<SnackBar>(find.byType(SnackBar));
            expect(snack.backgroundColor, AppTone.warning.b);
            expect(snack.duration, const Duration(seconds: 6));
            expect(t.takeException(), isNull);
          },
        );

        testWidgets('yüklenirken etiket yerine çark; tüm sayfa taşmaz', (
          t,
        ) async {
          final pending = Completer<String?>();
          final auth = _FakeAuth(onLogin: (_, _) => pending.future);
          await _pumpLogin(t, auth, width: w, height: h, scale: s, dark: dark);
          await _fillAndSubmit(t);

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('Giriş Yap'), findsNothing);
          expect(t.takeException(), isNull);

          pending.complete(null);
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Giriş Yap'), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets(
          '"Şifremi Unuttum" diyaloğu (AppDialog) açılır; hata bildirimi taşmaz',
          (t) async {
            final auth = _FakeAuth(
              onForgot: (_) async =>
                  'Bu e-posta adresi ile kayıtlı hesap bulunamadı. Lütfen adresi kontrol edin.',
            );
            await _pumpLogin(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _openForgotDialog(t);

            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.byType(AppDialogHeader), findsOneWidget);
            expect(find.text('Şifremi Unuttum'), findsOneWidget);
            expect(find.text('E-posta Adresi'), findsOneWidget);
            expect(find.text('İptal'), findsOneWidget);
            expect(find.text('Bağlantı Gönder'), findsOneWidget);
            expect(t.takeException(), isNull);

            await t.enterText(_dialogField, 'ali@example.com');
            await _tapText(t, 'Bağlantı Gönder');
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));

            expect(auth.forgots, <String>['ali@example.com']);
            expect(find.byType(InlineNotice), findsOneWidget);
            expect(
              find.text(
                'Bu e-posta adresi ile kayıtlı hesap bulunamadı. Lütfen adresi kontrol edin.',
              ),
              findsOneWidget,
            );
            expect(
              find.byType(AlertDialog),
              findsOneWidget,
              reason: 'hatada diyalog kapanmaz',
            );
            expect(t.takeException(), isNull);
          },
        );

        testWidgets(
          'şifre sıfırlama başarısı: diyalog kapanır, uzun başarı SnackBar\'ı taşmaz',
          (t) async {
            final auth = _FakeAuth();
            await _pumpLogin(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _openForgotDialog(t);
            await t.enterText(_dialogField, 'ali@example.com');
            await _tapText(t, 'Bağlantı Gönder');
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
            await t.pump(const Duration(milliseconds: 400));

            expect(find.byType(AlertDialog), findsNothing);
            expect(find.text(_forgotSuccess), findsOneWidget);
            final snack = t.widget<SnackBar>(find.byType(SnackBar));
            expect(snack.backgroundColor, AppTone.success.b);
            expect(snack.duration, const Duration(seconds: 5));
            expect(t.takeException(), isNull);
          },
        );
      });
    }
  }

  group('LoginPage: tasarım sistemi bağları', () {
    testWidgets(
      'LoginHero + tek AppCard(seviye 2) + PrimaryActionButton; mevcut metinler',
      (t) async {
        await _pumpLogin(t, _FakeAuth(), scale: 1.0);

        expect(find.byType(LoginHero), findsOneWidget);
        final card = t.widget<AppCard>(find.byType(AppCard));
        expect(card.level, 2);
        expect(find.byType(PrimaryActionButton), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2));
        // Giriş Yap düğmesi etiketi (e2e ve mevcut testler bu metne bağlı) ve 48 dp dokunma hedefi.
        expect(
          find.descendant(
            of: find.byType(PrimaryActionButton),
            matching: find.text('Giriş Yap'),
          ),
          findsOneWidget,
        );
        expect(
          t.getSize(find.byType(PrimaryActionButton)).height,
          greaterThanOrEqualTo(48),
        );
      },
    );

    testWidgets(
      'sayfa zemini TEK kez (kökte) boyanır: sayfada ikinci zemin yok',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpLogin(t, _FakeAuth(), dark: dark);
          final pageBackgrounds = find.descendant(
            of: find.byType(LoginPage),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  (identical(
                        w.decoration,
                        AppDecorations.pageBackgroundLight,
                      ) ||
                      identical(
                        w.decoration,
                        AppDecorations.pageBackgroundDark,
                      )),
            ),
          );
          expect(pageBackgrounds, findsNothing, reason: 'dark=$dark');
        }
      },
    );

    testWidgets('pahalı efektler yok (BackdropFilter / ShaderMask)', (t) async {
      await _pumpLogin(t, _FakeAuth());
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets(
      '"Yeni Hesap Oluştur" ve "Şifremi Unuttum?" TextButton; dokunma hedefi >= 44 dp',
      (t) async {
        await _pumpLogin(t, _FakeAuth());

        final register = find.widgetWithText(TextButton, 'Yeni Hesap Oluştur');
        final forgot = find.widgetWithText(TextButton, 'Şifremi Unuttum?');
        expect(register, findsOneWidget);
        expect(forgot, findsOneWidget);
        expect(t.getSize(register).height, greaterThanOrEqualTo(44));
        expect(t.getSize(forgot).height, greaterThanOrEqualTo(44));
        expect(t.getSize(register).width, greaterThanOrEqualTo(44));
        expect(t.widget<TextButton>(register).onPressed, isNotNull);
      },
    );

    testWidgets(
      'yüklenirken "Şifremi Unuttum?" pasif ve giriş düğmesi tıklamaya kapalı (mevcut davranış)',
      (t) async {
        final pending = Completer<String?>();
        final auth = _FakeAuth(onLogin: (_, _) => pending.future);
        await _pumpLogin(t, auth);
        await _fillAndSubmit(t);

        final forgot = find.widgetWithText(TextButton, 'Şifremi Unuttum?');
        expect(t.widget<TextButton>(forgot).onPressed, isNull);

        // Yükleniyorken çarka dokunmak ikinci bir istek göndermez.
        await t.tap(
          find.byType(CircularProgressIndicator),
          warnIfMissed: false,
        );
        await t.pump();
        expect(auth.logins, hasLength(1));

        pending.complete(null);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(t.widget<TextButton>(forgot).onPressed, isNotNull);
      },
    );

    testWidgets(
      '"Beni Hatırla" satırı tek anlamsal öğe: kutu + etiket, dokunma ile değişir',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          await _pumpLogin(t, _FakeAuth(), height: 800);

          final node = t.getSemantics(find.byType(Checkbox));
          expect(node.label, contains('Beni Hatırla (Kullanıcı adını kaydet)'));

          expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
          // Etiket metnine dokunmak da kutuyu değiştirir (satırın tamamı dokunma alanı).
          await t.tap(find.text('Beni Hatırla (Kullanıcı adını kaydet)'));
          await t.pump();
          expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
          await t.tap(find.byType(Checkbox));
          await t.pump();
          expect(
            t.widget<Checkbox>(find.byType(Checkbox)).value,
            isTrue,
            reason:
                'kutuya dokunmak TEK kez değiştirir (satır dokunması çift tetiklemez)',
          );
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '"Beni Hatırla" etiketi kırpılmaz (büyük yazıda satıra sarar)',
      (t) async {
        await _pumpLogin(t, _FakeAuth(), width: 320, height: 640, scale: 2.0);
        final label = t.widget<Text>(
          find.text('Beni Hatırla (Kullanıcı adını kaydet)'),
        );
        expect(label.maxLines, isNull);
        expect(label.overflow, isNot(TextOverflow.ellipsis));
      },
    );

    testWidgets(
      'ikincil metinler her iki temada >= 4,5:1 (kart yüzeyi üstünde)',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpLogin(t, _FakeAuth(), height: 800, dark: dark);
          final palette = dark ? AppPalette.dark : AppPalette.light;
          final surface = palette.surfaceAt(2);
          for (final text in <String>[
            'Akıllı Kapı & Site Otomasyon Paneli',
            'Hesabınız yok mu? ',
            'Beni Hatırla (Kullanıcı adını kaydet)',
            AppConfig.versionDisplay,
          ]) {
            final color = t.widget<Text>(find.text(text)).style!.color!;
            expect(
              _contrast(color, surface),
              greaterThanOrEqualTo(4.5),
              reason: '"$text" dark=$dark',
            );
          }
        }
      },
    );

    testWidgets('hareket azaltma: tek pump ile son durum, taşma yok', (
      t,
    ) async {
      await _pumpLogin(t, _FakeAuth(), width: 320, scale: 2.0, reduce: true);
      expect(find.text('AHBU Giriş'), findsOneWidget);
      expect(find.text('Giriş Yap'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'giriş başarılı: yalnız giriş çağrılır ve hata bildirimi çıkmaz',
      (t) async {
        final auth = _FakeAuth();
        await _pumpLogin(t, auth);
        await _fillAndSubmit(t);

        expect(auth.logins, <String>['ali@example.com']);
        expect(find.byType(SnackBar), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('saved_login_identifier'), 'ali@example.com');
      },
    );
  });
}
