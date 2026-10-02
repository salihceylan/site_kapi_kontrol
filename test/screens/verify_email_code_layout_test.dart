// FAZ 5 / A2-G1: e-posta doğrulama ekranı (VerifyEmailCodePage) taşma + tasarım sistemi testleri.
//
// AGENTS.md kural 6: hiçbir ekranda taşma olmaz. Matris: 320x640 x2,0 ve 360x640 x1,5, her biri açık
// ve koyu temada; eksik kod / sunucu hatası / yeniden gönderme başarısı bildirimleri ve yüklenme
// durumu da bu ölçülerde kurulur. Davranış (6 hane, 30 sn yeniden gönderme beklemesi, doğrulama ve
// yeniden gönderme çağrıları) ve metinler değişmez; yalnız görünüm: AppCard(2),
// PrimaryActionButton(loading), InlineNotice (hata/başarı), tema kenarlı kod alanı; tek zemin
// (kökte); ikincil metin `textSecondary`; yazı ölçeğini izleyen e-posta satırı (Text.rich).
//
// Not: widget testleri Ahem yazı tipiyle çalışır (her harf 1 em genişliğinde): satır sarma gerçek
// cihazdan daha serttir; geçen taşma testi gerçek yazı tipinde de geçer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_decorations.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/verify_email_code_page.dart';

import '../design/harness.dart';

/// Sahte kimlik servisi: ağa çıkmaz; doğrulama / yeniden gönderme sonuçları ve bekleme durumları
/// test tarafından belirlenir.
class _FakeAuth extends AuthService {
  _FakeAuth({this.onVerify, this.onResend})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final Future<String?> Function(String code)? onVerify;
  final Future<String?> Function()? onResend;
  final List<String> codes = <String>[];
  int resends = 0;

  @override
  Future<String?> verifyIndividualCode({
    required String email,
    required String code,
  }) async {
    codes.add(code);
    final handler = onVerify;
    return handler == null ? 'Kod hatalı.' : handler(code);
  }

  @override
  Future<String?> resendIndividualCode({required String email}) async {
    resends++;
    final handler = onResend;
    return handler == null ? null : handler();
  }
}

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

const String _email = 'muhammet.alperen.yildirim@ornek-alan-adi.com.tr';

const String _tooShort = 'Lütfen 6 haneli doğrulama kodunu eksiksiz giriniz.';

/// Sunucunun 404'te ürettiği uzun ek metin (auth_service.dart) dahil gerçekçi hata.
const String _longError =
    'Aktif doğrulama kodu bulunamadı. Kod 30 dakika geçerlidir; yeni kod için '
    '"Kodu Tekrar Gönder"e dokunun.';

const String _resendNote =
    'Bu e-posta adresi için bekleyen bir doğrulama varsa yeni 6 haneli kod birkaç dakika içinde '
    'e-postanıza ulaşır; önceki kodlar geçersiz olur. Ulaşmazsa spam klasörünü kontrol edin.';

Finder get _codeField => find.byType(TextField);

/// Sayfayı verilen ölçüde kurar (pumpAt gövdeyi kaydırılabilir sarar: sayfaya sabit boyut verilir).
Future<void> _pumpVerify(
  WidgetTester t,
  _FakeAuth auth, {
  String email = _email,
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
      child: VerifyEmailCodePage(authService: auth, email: email),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
}

/// Metni görünür kılıp dokunur (kaydırma animasyonu sürerken işaretçiler yok sayılır: bitene dek
/// zaman ilerletilir).
Future<void> _tapText(WidgetTester t, String text) async {
  final target = find.text(text);
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(target);
}

Future<void> _verifyWith(WidgetTester t, String code) async {
  await t.enterText(_codeField, code);
  await _tapText(t, 'Hesabımı Doğrula');
  // İlk kare ticker'ı başlatır; ikincisi animasyonu ilerletir (Pop girişi).
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

double _scaleOf(WidgetTester t, Finder f) =>
    MediaQuery.textScalerOf(t.element(f)).scale(10);

void main() {
  for (final (w, h, s) in _cells) {
    for (final dark in const <bool>[false, true]) {
      final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

      group('VerifyEmailCodePage taşma matrisi ($cell)', () {
        testWidgets('ilk kurulum: tüm öğeler var, taşma yok', (t) async {
          await _pumpVerify(
            t,
            _FakeAuth(),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );

          expect(
            find.text('E-Posta Doğrulama'),
            findsOneWidget,
          ); // AppBar başlığı
          expect(find.text('Doğrulama Kodunu Giriniz'), findsOneWidget);
          expect(find.textContaining(_email), findsOneWidget);
          expect(find.textContaining('adresinize gönderildi.'), findsOneWidget);
          expect(find.text('Hesabımı Doğrula'), findsOneWidget);
          expect(find.text('Kodu Tekrar Gönder (30 sn)'), findsOneWidget);
          expect(find.byType(InlineNotice), findsNothing);
        });

        testWidgets(
          'eksik kod hatası InlineNotice olarak, kod alanı kırmızı kenarlı',
          (t) async {
            final auth = _FakeAuth();
            await _pumpVerify(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _verifyWith(t, '12');

            expect(
              auth.codes,
              isEmpty,
              reason: 'eksik kod sunucuya gönderilmez',
            );
            expect(find.byType(InlineNotice), findsOneWidget);
            expect(find.text(_tooShort), findsOneWidget);
            final decoration = t.widget<TextField>(_codeField).decoration!;
            final theme = Theme.of(t.element(_codeField));
            expect(
              decoration.enabledBorder,
              theme.inputDecorationTheme.errorBorder,
            );
            expect(
              decoration.focusedBorder,
              theme.inputDecorationTheme.focusedErrorBorder,
            );
            expect(t.takeException(), isNull);
          },
        );

        testWidgets(
          'uzun sunucu hatası taşmadan; yeni denemede bildirim kalkar',
          (t) async {
            final auth = _FakeAuth(onVerify: (_) async => _longError);
            await _pumpVerify(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _verifyWith(t, '482913');

            expect(auth.codes, <String>['482913']);
            expect(find.text(_longError), findsOneWidget);
            expect(t.takeException(), isNull);

            // Yeniden doğrula: istek sürerken eski hata kalkar (mevcut davranış), çark görünür.
            final pending = Completer<String?>();
            final slow = _FakeAuth(onVerify: (_) => pending.future);
            await _pumpVerify(
              t,
              slow,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _verifyWith(t, '482913');
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(find.text('Hesabımı Doğrula'), findsNothing);
            expect(find.byType(InlineNotice), findsNothing);
            expect(t.takeException(), isNull);
            pending.complete('Kod hatalı.');
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
            expect(find.text('Kod hatalı.'), findsOneWidget);
            expect(find.text('Hesabımı Doğrula'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );

        testWidgets(
          'yeniden gönderme: 30 sn sonra etkin; uzun başarı bildirimi taşmadan; bekleme yeniden başlar',
          (t) async {
            final auth = _FakeAuth();
            await _pumpVerify(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await t.pump(const Duration(seconds: 30));
            expect(find.text('Kodu Tekrar Gönder'), findsOneWidget);

            await _tapText(t, 'Kodu Tekrar Gönder');
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));

            expect(auth.resends, 1);
            expect(find.text(_resendNote), findsOneWidget);
            expect(find.text('Kodu Tekrar Gönder (30 sn)'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );

        testWidgets('yeniden gönderme hatası da bildirim olarak gösterilir', (
          t,
        ) async {
          final auth = _FakeAuth(
            onResend: () async => 'Kod tekrar gönderilemedi.',
          );
          await _pumpVerify(t, auth, width: w, height: h, scale: s, dark: dark);
          await t.pump(const Duration(seconds: 30));
          await _tapText(t, 'Kodu Tekrar Gönder');
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));

          expect(find.text('Kod tekrar gönderilemedi.'), findsOneWidget);
          expect(
            find.text('Kodu Tekrar Gönder'),
            findsOneWidget,
            reason: 'bekleme başlamaz',
          );
          expect(t.takeException(), isNull);
        });
      });
    }
  }

  group('VerifyEmailCodePage: tasarım sistemi bağları', () {
    testWidgets(
      'tek AppCard(seviye 2) + PrimaryActionButton; tek alan, tek TextButton',
      (t) async {
        await _pumpVerify(t, _FakeAuth(), height: 900);

        expect(t.widget<AppCard>(find.byType(AppCard)).level, 2);
        expect(
          find.descendant(
            of: find.byType(PrimaryActionButton),
            matching: find.text('Hesabımı Doğrula'),
          ),
          findsOneWidget,
        );
        expect(
          t.getSize(find.byType(PrimaryActionButton)).height,
          greaterThanOrEqualTo(48),
        );
        // Mevcut testler/e2e: sayfada TEK TextField ve TEK TextButton (yeniden gönderme) vardır.
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byType(TextButton), findsOneWidget);
        expect(
          find.widgetWithText(TextButton, 'Kodu Tekrar Gönder (30 sn)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'kod alanı: 6 haneli rakam, ipucu "••••••" (e2e), sayısal klavye',
      (t) async {
        await _pumpVerify(t, _FakeAuth(), height: 900);

        final field = t.widget<TextField>(_codeField);
        expect(field.maxLength, VerifyEmailCodePage.codeLength);
        expect(field.keyboardType, TextInputType.number);
        expect(field.textAlign, TextAlign.center);
        expect(field.decoration!.hintText, '••••••');
        expect(field.decoration!.counterText, '');

        await t.enterText(_codeField, '12ab3456789');
        await t.pump();
        expect(t.widget<TextField>(_codeField).controller!.text, '123456');
      },
    );

    testWidgets(
      'kod alanı yazı ölçeği 1,4 ile sınırlı; başlık/metin tam ölçeği izler',
      (t) async {
        for (final (scale, code, title) in const <(double, double, double)>[
          (1.0, 10.0, 10.0),
          (1.2, 12.0, 12.0),
          (2.0, 14.0, 20.0),
        ]) {
          await _pumpVerify(
            t,
            _FakeAuth(),
            width: 360,
            height: 900,
            scale: scale,
          );
          expect(
            _scaleOf(t, _codeField),
            closeTo(code, 1e-9),
            reason: 'kod alanı, ölçek $scale',
          );
          expect(
            _scaleOf(t, find.text('Doğrulama Kodunu Giriniz')),
            closeTo(title, 1e-9),
            reason: 'başlık, ölçek $scale',
          );
          // E-posta satırı Text.rich: sistem ölçeğini izler (RichText varsayılanı izlemezdi).
          expect(
            _scaleOf(t, find.textContaining('adresinize gönderildi.')),
            closeTo(title, 1e-9),
            reason: 'e-posta satırı, ölçek $scale',
          );
        }
      },
    );

    testWidgets(
      'yeniden gönderme etiketi kırpılmaz (geri sayım büyük yazıda görünür)',
      (t) async {
        await _pumpVerify(t, _FakeAuth(), width: 320, height: 640, scale: 2.0);
        final label = t.widget<Text>(find.text('Kodu Tekrar Gönder (30 sn)'));
        expect(label.maxLines, isNull);
        expect(label.overflow, isNot(TextOverflow.ellipsis));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('geri sayım yeni düzende de işler: 30 -> 29 sn, düğme pasif', (
      t,
    ) async {
      final auth = _FakeAuth();
      await _pumpVerify(t, auth, height: 900);
      final resend = find.widgetWithText(
        TextButton,
        'Kodu Tekrar Gönder (30 sn)',
      );
      expect(t.widget<TextButton>(resend).onPressed, isNull);

      await t.pump(const Duration(seconds: 1));
      expect(find.text('Kodu Tekrar Gönder (29 sn)'), findsOneWidget);
      await t.pump(const Duration(seconds: 29));
      expect(find.text('Kodu Tekrar Gönder'), findsOneWidget);
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Kodu Tekrar Gönder'),
            )
            .onPressed,
        isNotNull,
      );
      expect(auth.resends, 0);
    });

    testWidgets(
      'sayfa zemini TEK kez (kökte) boyanır: Scaffold şeffaf, ikinci zemin yok',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpVerify(t, _FakeAuth(), height: 900, dark: dark);
          final scaffold = t.widget<Scaffold>(
            find.descendant(
              of: find.byType(VerifyEmailCodePage),
              matching: find.byType(Scaffold),
            ),
          );
          expect(
            scaffold.backgroundColor,
            isNull,
            reason: 'dark=$dark: tema zemini şeffaf',
          );
          expect(
            find.descendant(
              of: find.byType(VerifyEmailCodePage),
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
            ),
            findsNothing,
            reason: 'dark=$dark',
          );
        }
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ShaderMask), findsNothing);
      },
    );

    testWidgets(
      'metinler her iki temada >= 4,5:1 (kart yüzeyi üstünde); koyuda textMuted DEĞİL',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpVerify(t, _FakeAuth(), height: 900, dark: dark);
          final palette = dark ? AppPalette.dark : AppPalette.light;
          final surface = palette.surfaceAt(2);

          // Açıklama satırı: textSecondary; e-posta adresi vurgusu: ana metin rengi.
          final rich = t.widget<Text>(
            find.textContaining('adresinize gönderildi.'),
          );
          expect(
            rich.style!.color,
            palette.textSecondary,
            reason: 'dark=$dark',
          );
          expect(
            _contrast(rich.style!.color!, surface),
            greaterThanOrEqualTo(4.5),
          );
          final span = rich.textSpan! as TextSpan;
          final emailSpan = span.children!.whereType<TextSpan>().firstWhere(
            (c) => c.text == _email,
          );
          expect(emailSpan.style!.color, palette.text, reason: 'dark=$dark');
          expect(emailSpan.style!.fontWeight, FontWeight.w700);
          expect(_contrast(palette.text, surface), greaterThanOrEqualTo(4.5));

          // Kod rakamları ve ipucu.
          final decoration = t.widget<TextField>(_codeField).decoration!;
          final style = t.widget<TextField>(_codeField).style!;
          expect(
            style.color,
            AppTone.primary.ink(palette),
            reason: 'dark=$dark',
          );
          expect(_contrast(style.color!, surface), greaterThanOrEqualTo(4.5));
          expect(
            decoration.hintStyle!.color,
            palette.textMuted,
            reason: 'dark=$dark',
          );
          expect(
            _contrast(palette.textMuted, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      },
    );

    testWidgets(
      'bildirim tonları: hata -> danger, başarı -> success (ham Colors.red/green yok)',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          final palette = dark ? AppPalette.dark : AppPalette.light;
          final auth = _FakeAuth();
          await _pumpVerify(t, auth, height: 900, dark: dark);

          await _verifyWith(t, '1');
          var notice = t.widget<InlineNotice>(find.byType(InlineNotice));
          expect(notice.tone, AppTone.danger);
          var text = t.widget<Text>(find.text(_tooShort));
          expect(
            text.style!.color,
            AppTone.danger.ink(palette),
            reason: 'dark=$dark',
          );
          expect(
            _contrast(AppTone.danger.ink(palette), palette.surfaceAt(2)),
            greaterThanOrEqualTo(4.5),
          );

          await t.pump(const Duration(seconds: 30));
          await _tapText(t, 'Kodu Tekrar Gönder');
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          notice = t.widget<InlineNotice>(find.byType(InlineNotice));
          expect(
            notice.tone,
            AppTone.success,
            reason: 'başarı bildirimi hatanın yerini alır',
          );
          text = t.widget<Text>(find.text(_resendNote));
          expect(
            text.style!.color,
            AppTone.success.ink(palette),
            reason: 'dark=$dark',
          );
          expect(find.text(_tooShort), findsNothing);
        }
      },
    );

    testWidgets(
      'hareket azaltma: bildirim tek pump ile tam görünür, taşma yok',
      (t) async {
        await _pumpVerify(t, _FakeAuth(), width: 320, scale: 2.0, reduce: true);
        await t.enterText(_codeField, '12');
        await _tapText(t, 'Hesabımı Doğrula');
        await t.pump();

        final opacity = t.widget<Opacity>(
          find
              .ancestor(
                of: find.text(_tooShort),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(opacity.opacity, 1.0);
        expect(t.takeException(), isNull);
      },
    );
  });
}
