// FAZ 5 / A2-G1: kayıt ekranı (RegisterIndividualPage) taşma + tasarım sistemi testleri.
//
// AGENTS.md kural 6: hiçbir ekranda taşma olmaz. Matris: 320x640 x2,0 ve 360x640 x1,5, her biri açık
// ve koyu temada; doğrulama hataları, sunucu hatası (InlineNotice) ve yüklenme durumu da bu ölçülerde
// kurulur. Davranış (alan sırası/etiketleri, doğrulayıcılar, kayıt çağrısı, doğrulama sayfasına
// gidiş) ve metinler değişmez; yalnız görünüm: AppCard(2), PrimaryActionButton(loading),
// InlineNotice; tek zemin (kökte); ad/soyad alanları geniş kartta yan yana, telefonda/büyük yazıda
// alt alta; 44 dp "Giriş Yapın" düğmesi; koyu temada ikincil metin `textSecondary`.
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
import 'package:site_kapi_kontrol/ui/pages/register_individual_page.dart';
import 'package:site_kapi_kontrol/ui/pages/verify_email_code_page.dart';

import '../design/harness.dart';

/// Sahte kimlik servisi: ağa çıkmaz; kayıt sonucu ve bekleme durumu test tarafından belirlenir.
class _FakeAuth extends AuthService {
  _FakeAuth({this.onRegister})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  final Future<String?> Function()? onRegister;
  final List<List<String>> registers = <List<String>>[];

  @override
  Future<String?> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    registers.add(<String>[firstName, lastName, email, password]);
    final handler = onRegister;
    return handler == null ? null : handler();
  }
}

/// AGENTS.md kural 6 matrisi: (genişlik, yükseklik, yazı ölçeği).
const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

const String _longError =
    'Bu e-posta adresiyle daha önce kayıt oluşturulmuş. Giriş yapmayı ya da şifrenizi sıfırlamayı '
    'deneyin; sorun sürerse destek ekibiyle iletişime geçin.';

Finder get _fields => find.byType(TextFormField);

/// Alan etiketleri, ekrandaki sırayla.
List<String?> _labels(WidgetTester t) => t
    .widgetList<TextField>(find.byType(TextField))
    .map((f) => f.decoration?.labelText)
    .toList();

/// Sayfayı verilen ölçüde kurar (pumpAt gövdeyi kaydırılabilir sarar: sayfaya sabit boyut verilir).
Future<void> _pumpRegister(
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
      child: RegisterIndividualPage(authService: auth),
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
Future<void> _tapLast(WidgetTester t, String text) async {
  final target = find.text(text).last;
  await t.pump(const Duration(milliseconds: 300));
  await t.ensureVisible(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(target);
}

Future<void> _fillForm(WidgetTester t) async {
  await t.enterText(_fields.at(0), 'Ali');
  await t.enterText(_fields.at(1), 'Veli');
  await t.enterText(_fields.at(2), 'ALI@Example.com');
  await t.enterText(_fields.at(3), 'parola123');
  await t.enterText(_fields.at(4), 'parola123');
}

Future<void> _submit(WidgetTester t) async {
  await _tapLast(t, 'Kayıt Ol');
  // İlk kare ticker'ı başlatır; ikincisi animasyonu ilerletir (Pop girişi, sayfa geçişi).
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

void main() {
  for (final (w, h, s) in _cells) {
    for (final dark in const <bool>[false, true]) {
      final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

      group('RegisterIndividualPage taşma matrisi ($cell)', () {
        testWidgets('ilk kurulum: tüm öğeler var, taşma yok', (t) async {
          await _pumpRegister(
            t,
            _FakeAuth(),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );

          expect(
            find.text('Yeni Hesap Oluştur'),
            findsOneWidget,
          ); // AppBar başlığı
          expect(
            find.text('Kayıt Ol'),
            findsNWidgets(2),
          ); // kart başlığı + düğme
          expect(
            find.text('Kapı kontrol ve site üyelik hesabınızı oluşturun'),
            findsOneWidget,
          );
          expect(_labels(t), <String?>[
            'Ad',
            'Soyad',
            'E-Posta',
            'Şifre',
            'Şifre Tekrar',
          ]);
          expect(find.text('Zaten bir hesabınız var mı? '), findsOneWidget);
          expect(find.text('Giriş Yapın'), findsOneWidget);
        });

        testWidgets('boş formda doğrulama hataları taşmadan gösterilir', (
          t,
        ) async {
          await _pumpRegister(
            t,
            _FakeAuth(),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          await _tapLast(t, 'Kayıt Ol');
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));

          expect(find.text('Ad gerekli'), findsOneWidget);
          expect(find.text('Soyad gerekli'), findsOneWidget);
          expect(find.text('E-posta adresi zorunludur'), findsOneWidget);
          expect(find.text('Şifre zorunludur'), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets(
          'uyuşmayan şifre ve kısa şifre hataları taşmadan gösterilir',
          (t) async {
            await _pumpRegister(
              t,
              _FakeAuth(),
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await t.enterText(_fields.at(0), 'Ali');
            await t.enterText(_fields.at(1), 'Veli');
            await t.enterText(_fields.at(2), 'ali@example.com');
            await t.enterText(_fields.at(3), '123');
            await t.enterText(_fields.at(4), '456');
            await _tapLast(t, 'Kayıt Ol');
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));

            expect(
              find.text('Şifre en az 6 karakter olmalıdır'),
              findsOneWidget,
            );
            expect(find.text('Şifreler birbiriyle eşleşmiyor'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );

        testWidgets(
          'uzun sunucu hatası InlineNotice olarak kartın başında, taşmadan',
          (t) async {
            final auth = _FakeAuth(onRegister: () async => _longError);
            await _pumpRegister(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _fillForm(t);
            await _submit(t);

            expect(auth.registers, hasLength(1));
            expect(find.byType(InlineNotice), findsOneWidget);
            expect(find.text(_longError), findsOneWidget);
            expect(find.byType(VerifyEmailCodePage), findsNothing);
            // Hata bildirimi başlığın ve alt başlığın ALTINDA, ilk alanın ÜSTÜNDE.
            final noticeTop = t.getTopLeft(find.byType(InlineNotice)).dy;
            expect(
              noticeTop,
              greaterThan(t.getBottomLeft(find.text('Kayıt Ol').first).dy),
            );
            expect(noticeTop, lessThan(t.getTopLeft(_fields.first).dy));
            expect(t.takeException(), isNull);
          },
        );

        testWidgets('yüklenirken etiket yerine çark; tüm sayfa taşmaz', (
          t,
        ) async {
          final pending = Completer<String?>();
          final auth = _FakeAuth(onRegister: () => pending.future);
          await _pumpRegister(
            t,
            auth,
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          await _fillForm(t);
          await _submit(t);

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            find.text('Kayıt Ol'),
            findsOneWidget,
            reason: 'yalnız kart başlığı kalır',
          );
          expect(t.takeException(), isNull);

          pending.complete(_longError);
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Kayıt Ol'), findsNWidgets(2));
          expect(t.takeException(), isNull);
        });

        testWidgets(
          'başarıda doğrulama sayfasına gidilir (e-posta küçük harfe çevrilir)',
          (t) async {
            final auth = _FakeAuth();
            await _pumpRegister(
              t,
              auth,
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            await _fillForm(t);
            await _submit(t);
            await t.pump(const Duration(milliseconds: 400));

            expect(auth.registers.single, <String>[
              'Ali',
              'Veli',
              'ali@example.com',
              'parola123',
            ]);
            expect(find.byType(VerifyEmailCodePage), findsOneWidget);
            expect(find.text('Doğrulama Kodunu Giriniz'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      });
    }
  }

  group('RegisterIndividualPage: tasarım sistemi bağları', () {
    testWidgets(
      'tek AppCard(seviye 2) + PrimaryActionButton; mevcut alan sırası',
      (t) async {
        await _pumpRegister(t, _FakeAuth(), height: 900);

        final card = t.widget<AppCard>(find.byType(AppCard));
        expect(card.level, 2);
        expect(find.byType(PrimaryActionButton), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PrimaryActionButton),
            matching: find.text('Kayıt Ol'),
          ),
          findsOneWidget,
        );
        expect(
          t.getSize(find.byType(PrimaryActionButton)).height,
          greaterThanOrEqualTo(48),
        );
        // e2e ve mevcut testler alan SIRASINA/etiketlerine bağlı.
        expect(_labels(t), <String?>[
          'Ad',
          'Soyad',
          'E-Posta',
          'Şifre',
          'Şifre Tekrar',
        ]);
      },
    );

    testWidgets(
      'sayfa zemini TEK kez (kökte) boyanır: Scaffold şeffaf, ikinci zemin yok',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpRegister(t, _FakeAuth(), height: 900, dark: dark);
          final scaffold = t.widget<Scaffold>(
            find.descendant(
              of: find.byType(RegisterIndividualPage),
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
              of: find.byType(RegisterIndividualPage),
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
      },
    );

    testWidgets('pahalı efektler yok (BackdropFilter / ShaderMask)', (t) async {
      await _pumpRegister(t, _FakeAuth(), height: 900);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets(
      'ad / soyad: telefonda (360) ve büyük yazıda alt alta; geniş kartta yan yana',
      (t) async {
        Future<(Offset, Offset)> positions() async {
          final first = t.getTopLeft(_fields.at(0));
          final last = t.getTopLeft(_fields.at(1));
          return (first, last);
        }

        // Telefon: alt alta (aynı sol kenar, soyad ad'ın altında).
        await _pumpRegister(t, _FakeAuth(), width: 360, height: 900);
        var (first, last) = await positions();
        expect(last.dx, first.dx);
        expect(last.dy, greaterThan(first.dy));
        expect(
          t.getSize(_fields.at(0)).width,
          t.getSize(_fields.at(2)).width,
          reason: 'her alan kartın tam genişliğinde',
        );

        // Büyük yazı (1,5): geniş kartta bile alt alta.
        await _pumpRegister(
          t,
          _FakeAuth(),
          width: 820,
          height: 900,
          scale: 1.5,
        );
        (first, last) = await positions();
        expect(last.dx, first.dx);
        expect(last.dy, greaterThan(first.dy));

        // Geniş kart + normal yazı: yan yana (aynı üst kenar, soyad sağda), iki alan eşit genişlikte.
        await _pumpRegister(
          t,
          _FakeAuth(),
          width: 820,
          height: 900,
          scale: 1.0,
        );
        (first, last) = await positions();
        expect(last.dy, first.dy);
        expect(last.dx, greaterThan(first.dx));
        expect(t.getSize(_fields.at(0)).width, t.getSize(_fields.at(1)).width);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('yan yana ad/soyad: doğrulama hataları taşmadan (820 x 1,0)', (
      t,
    ) async {
      await _pumpRegister(t, _FakeAuth(), width: 820, height: 900, scale: 1.0);
      await _tapLast(t, 'Kayıt Ol');
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Ad gerekli'), findsOneWidget);
      expect(find.text('Soyad gerekli'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('ad/soyad düzeni değişince alan durumu (hata/metin) korunur', (
      t,
    ) async {
      // Aynı sayfa önce dar, sonra geniş ölçüde: Row <-> Column geçişi alanları yeniden KURMAZ.
      final width = ValueNotifier<double>(360);
      addTearDown(width.dispose);
      await pumpAt(
        t,
        ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (context, w, _) => SizedBox(
            width: w,
            height: 900,
            child: RegisterIndividualPage(authService: _FakeAuth()),
          ),
        ),
        width: 820,
        height: 900,
        scale: 1.0,
      );
      await t.enterText(_fields.at(0), 'Ali');
      await _tapLast(t, 'Kayıt Ol');
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Soyad gerekli'), findsOneWidget);
      expect(find.text('Ad gerekli'), findsNothing);
      expect(
        t.getTopLeft(_fields.at(1)).dx,
        t.getTopLeft(_fields.at(0)).dx,
        reason: 'dar: alt alta',
      );

      width.value = 820;
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(
        t.getTopLeft(_fields.at(1)).dy,
        t.getTopLeft(_fields.at(0)).dy,
        reason: 'geniş: yan yana',
      );
      expect(
        find.text('Soyad gerekli'),
        findsOneWidget,
        reason: 'doğrulama hatası yerinde kalır',
      );
      final texts = t
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text);
      expect(texts.first, 'Ali');
      expect(t.takeException(), isNull);
    });

    testWidgets('"Giriş Yapın" TextButton >= 44 dp; kayıt sayfasını kapatır', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        harnessApp(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RegisterIndividualPage(authService: _FakeAuth()),
                  ),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Aç'));
      await t.pumpAndSettle();
      expect(find.byType(RegisterIndividualPage), findsOneWidget);

      final back = find.widgetWithText(TextButton, 'Giriş Yapın');
      expect(back, findsOneWidget);
      expect(t.getSize(back).height, greaterThanOrEqualTo(44));
      await t.ensureVisible(back);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(back);
      await t.pumpAndSettle();
      expect(find.byType(RegisterIndividualPage), findsNothing);
    });

    testWidgets(
      'ikincil metinler her iki temada >= 4,5:1 (kart yüzeyi üstünde)',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          await _pumpRegister(t, _FakeAuth(), height: 900, dark: dark);
          final palette = dark ? AppPalette.dark : AppPalette.light;
          final surface = palette.surfaceAt(2);
          for (final text in <String>[
            'Kapı kontrol ve site üyelik hesabınızı oluşturun',
            'Zaten bir hesabınız var mı? ',
          ]) {
            final color = t.widget<Text>(find.text(text)).style!.color!;
            expect(
              color,
              palette.textSecondary,
              reason:
                  '"$text" dark=$dark: koyu temada textMuted DEĞİL textSecondary',
            );
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
      await _pumpRegister(t, _FakeAuth(), width: 320, scale: 2.0, reduce: true);
      expect(find.text('Kayıt Ol'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });
  });
}
