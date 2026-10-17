// FAZ 5 / A1b-(iii): LoginHero widget testleri.
//
// Marka başlığı artık Güde Teknoloji'nin ışıklı VEKTÖR logosunu ([AnimatedGudeLogo]) gösterir (eski dairesel
// çerçeveli PNG logo kalktı). Durumlar (başlık+alt başlık / yalnız başlık / yalnız logo), logonun boyutu ve
// temaya uyumu (bitmap çözümü yok), ışık animasyonunun varsayılan anahtarla ve hareket azaltmayla bağı,
// giriş animasyonu ve hareket azaltma, pumpAndSettle'ın bitmesi, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x
// açık/koyu + 320x640@2,0 / 360x640@1,5 / 640x360@2,0 pencereleri) ve Semantics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/brand/gude_logo.dart';
import 'package:site_kapi_kontrol/brand/gude_logo_animated.dart';
import 'package:site_kapi_kontrol/brand/logo_palette.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/login_hero.dart';

import 'harness.dart';

const String _title = 'Giriş';
const String _subtitle = 'Akıllı Kapı & Site Otomasyon Paneli';

const LoginHero _full = LoginHero(title: _title, subtitle: _subtitle);

/// Heroya ait ilk Opacity'nin değeri.
double _opacity(WidgetTester t) {
  final f = find
      .descendant(of: find.byType(LoginHero), matching: find.byType(Opacity))
      .first;
  return t.widget<Opacity>(f).opacity;
}

/// Heroya ait ilk Transform'un dikey ötelemesi.
double _dy(WidgetTester t) {
  final f = find
      .descendant(of: find.byType(LoginHero), matching: find.byType(Transform))
      .first;
  return t.widget<Transform>(f).transform.getTranslation().y;
}

final Finder _logoFinder = find.byType(AnimatedGudeLogo);

Finder _sweepLayer() => find.descendant(
  of: _logoFinder,
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is GudeLogoSweepPainter,
  ),
);

Finder _glowLayer() => find.descendant(
  of: _logoFinder,
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is GudeLogoGlowPainter,
  ),
);

void main() {
  group('LoginHero: durumlar', () {
    testWidgets('başlık + alt başlık + logo: metinler birebir', (t) async {
      await pumpAt(t, _full, scale: 1.0);
      expect(find.text('Giriş'), findsOneWidget);
      expect(find.text('Akıllı Kapı & Site Otomasyon Paneli'), findsOneWidget);
      expect(_logoFinder, findsOneWidget);
    });

    testWidgets('yalnız başlık: alt başlık yok', (t) async {
      await pumpAt(t, const LoginHero(title: _title), scale: 1.0);
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_subtitle), findsNothing);
      expect(_logoFinder, findsOneWidget);
    });

    testWidgets('yalnız alt başlık: başlık yok', (t) async {
      await pumpAt(t, const LoginHero(subtitle: _subtitle), scale: 1.0);
      expect(find.text(_subtitle), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('ikisi de null: yalnız logo (açılış/ara ekran)', (t) async {
      await pumpAt(t, const LoginHero(), scale: 1.0);
      expect(find.byType(Text), findsNothing);
      expect(_logoFinder, findsOneWidget);
      expect(
        t.getSize(find.byType(LoginHero)).width,
        closeTo(LoginHero.logoHeight * GudeLogo.aspect, 0.01),
      );
    });
  });

  group('LoginHero: logo (vektör, çerçevesiz, temaya uyumlu)', () {
    testWidgets(
      'boyut: 120 dp yükseklik, en/boy oranı logoyla aynı; daire/halka/kırpma yok',
      (t) async {
        await pumpAt(t, const LoginHero(), scale: 1.0);
        expect(LoginHero.logoHeight, 120);
        final size = t.getSize(_logoFinder);
        expect(size.height, 120);
        expect(size.width / size.height, closeTo(GudeLogo.aspect, 1e-6));
        expect(t.getSize(find.byType(LoginHero)), size);
        expect(find.byType(ClipOval), findsNothing, reason: 'daireye kırpma yok');
        expect(find.byType(Gloss), findsNothing, reason: 'eski halka cilası yok');
        expect(
          find.descendant(
            of: find.byType(LoginHero),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).shape == BoxShape.circle,
            ),
          ),
          findsNothing,
          reason: 'dairesel çerçeve yok',
        );
      },
    );

    testWidgets('bitmap logo kullanılmaz: Image widget\'ı ve ImageCache boş', (
      t,
    ) async {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await pumpAt(t, _full, scale: 1.0);
      expect(find.byType(Image), findsNothing);
      expect(PaintingBinding.instance.imageCache.currentSizeBytes, 0);
      expect(PaintingBinding.instance.imageCache.liveImageCount, 0);
    });

    testWidgets('yatayda ortalı (genişleyen üst öğe içinde de)', (t) async {
      await pumpAt(
        t,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_full],
        ),
        width: 360,
        scale: 1.0,
      );
      expect(t.getCenter(_logoFinder).dx, closeTo(180, 0.01));
      expect(t.getCenter(find.text(_title)).dx, closeTo(180, 0.01));
    });

    testWidgets('kullanılabilir genişlik logodan darsa en/boy oranı korunarak küçülür', (
      t,
    ) async {
      await pumpAt(
        t,
        const SizedBox(width: 150, child: LoginHero()),
        scale: 1.0,
      );
      final size = t.getSize(_logoFinder);
      expect(size.width, closeTo(150, 0.01));
      expect(size.width / size.height, closeTo(GudeLogo.aspect, 1e-6));
      expect(size.height, lessThan(LoginHero.logoHeight));
    });

    testWidgets('renkler temaya göre: koyuda koyu palet, açıkta açık palet', (
      t,
    ) async {
      for (final dark in const [false, true]) {
        await pumpAt(t, const LoginHero(), scale: 1.0, dark: dark);
        final art =
            (t.widget<CustomPaint>(_sweepLayer().first).painter!
                    as GudeLogoSweepPainter)
                .art;
        expect(art, isA<GudeLogoPainter>());
        expect(
          (art as GudeLogoPainter).palette,
          dark ? LogoPalette.dark : LogoPalette.light,
          reason: 'dark=$dark',
        );
        expect(
          (t.widget<CustomPaint>(_glowLayer().first).painter!
                  as GudeLogoGlowPainter)
              .dark,
          dark,
        );
      }
    });

    testWidgets('yasaklı pahalı efektler yok (BackdropFilter / ShaderMask)', (
      t,
    ) async {
      await pumpAt(t, _full, scale: 1.0);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets(
      'tipografi: başlık headlineMedium (24/w800), alt başlık bodyMedium; ortalı',
      (t) async {
        await pumpAt(t, _full, scale: 1.0);
        final th = Theme.of(t.element(find.byType(LoginHero))).textTheme;
        final title = t.widget<Text>(find.text(_title));
        final sub = t.widget<Text>(find.text(_subtitle));
        expect(title.style, th.headlineMedium);
        expect(title.style!.fontSize, 24);
        expect(title.style!.fontWeight, FontWeight.w800);
        expect(title.textAlign, TextAlign.center);
        expect(sub.style, th.bodyMedium);
        expect(sub.textAlign, TextAlign.center);
      },
    );

    testWidgets('stretch eden üst öğe (LoginPage Column) içinde de çalışır', (
      t,
    ) async {
      await pumpAt(
        t,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_full],
        ),
        width: 360,
        scale: 1.0,
      );
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(LoginHero)).width, 360);
    });

    testWidgets('yüksek karşıtlıkta da logo ve başlık çizilir', (t) async {
      await t.pumpWidget(
        harnessApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(highContrast: true),
              child: const LoginHero(title: _title),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 450));
      expect(_logoFinder, findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('LoginHero: ışık animasyonu (varsayılan anahtar + hareket azaltma)', () {
    GudeLogoGlowPainter glow(WidgetTester t) =>
        t.widget<CustomPaint>(_glowLayer().first).painter! as GudeLogoGlowPainter;

    testWidgets('testlerde varsayılan kapalı: ticker yok, pumpAndSettle biter', (
      t,
    ) async {
      expect(GudeLogoAnimation.enabledByDefault, isFalse);
      await t.pumpWidget(harnessApp(_full));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      expect(glow(t).progress.value, 0);
    });

    testWidgets('anahtar açıkken logo canlı: tur ilerler, süpürme oynar', (
      t,
    ) async {
      GudeLogoAnimation.enabledByDefault = true;
      addTearDown(() => GudeLogoAnimation.enabledByDefault = false);
      await t.pumpWidget(harnessApp(_full));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1700));
      expect(glow(t).progress.value, closeTo(1700 / 7000, 0.003));
      expect(
        (t.widget<CustomPaint>(_sweepLayer().first).painter!
                as GudeLogoSweepPainter)
            .sweep
            .value,
        closeTo(0.5, 0.02),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('hareket azaltma: anahtar açık olsa da logo durağan, ticker yok', (
      t,
    ) async {
      GudeLogoAnimation.enabledByDefault = true;
      addTearDown(() => GudeLogoAnimation.enabledByDefault = false);
      await t.pumpWidget(harnessApp(_full, reduce: true));
      await t.pump();
      await t.pump(const Duration(milliseconds: 2000));
      expect(glow(t).progress.value, 0);
      expect(t.binding.transientCallbackCount, 0);
    });
  });

  group('LoginHero: giriş animasyonu ve hareket azaltma', () {
    testWidgets(
      '320 ms solma + 12 dp yukarı kayma; sonra sabit; pumpAndSettle biter',
      (t) async {
        await t.pumpWidget(harnessApp(_full));
        expect(_opacity(t), 0, reason: 'ilk kare: görünmez');
        expect(_dy(t), 12, reason: 'ilk kare: 12 dp aşağıda');

        var lastOpacity = 0.0;
        var lastDy = 12.0;
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 60));
          expect(_opacity(t), greaterThanOrEqualTo(lastOpacity));
          expect(_dy(t), lessThanOrEqualTo(lastDy));
          lastOpacity = _opacity(t);
          lastDy = _dy(t);
        }
        expect(
          lastOpacity,
          inExclusiveRange(0, 1),
          reason: '240 ms: ara değer',
        );
        expect(lastDy, inExclusiveRange(0, 12));

        await t.pumpAndSettle();
        expect(_opacity(t), 1);
        expect(_dy(t), 0);
        expect(
          t.binding.transientCallbackCount,
          0,
          reason: 'kararlı durumda ticker yok',
        );
      },
    );

    testWidgets('toplam süre 320 ms: 330 ms sonra tamamlanmış', (t) async {
      await t.pumpWidget(harnessApp(_full));
      await t.pump();
      await t.pump(const Duration(milliseconds: 330));
      expect(_opacity(t), 1);
      expect(_dy(t), 0);
    });

    testWidgets('hareket azaltma: ilk karede son durum, ticker yok', (t) async {
      await t.pumpWidget(harnessApp(_full, reduce: true));
      expect(_opacity(t), 1);
      expect(_dy(t), 0);
      expect(t.binding.transientCallbackCount, 0);
      await t.pump();
      expect(_opacity(t), 1);
    });

    testWidgets(
      'metin değişince yeniden animasyon oynamaz (yalnız ilk kurulumda)',
      (t) async {
        await t.pumpWidget(harnessApp(const LoginHero(title: 'Birinci')));
        await t.pumpAndSettle();
        await t.pumpWidget(harnessApp(const LoginHero(title: 'İkinci')));
        expect(
          _opacity(t),
          1,
          reason: 'aynı eleman güncellendi: solma tekrar başlamaz',
        );
        expect(find.text('İkinci'), findsOneWidget);
      },
    );
  });

  group('LoginHero: Semantics', () {
    testWidgets(
      'başlık başlık (header) olarak okunur; alt başlık düz metin; logo dekoratif',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(t, _full, scale: 1.0);
        expect(
          t.getSemantics(find.text(_title)),
          isSemantics(label: _title, isHeader: true),
        );
        expect(
          t.getSemantics(find.text(_subtitle)),
          isSemantics(label: _subtitle, isHeader: false),
        );
        final labelled = t.semantics
            .simulatedAccessibilityTraversal()
            .map((n) => n.getSemanticsData().label)
            .where((l) => l.isNotEmpty)
            .toList();
        expect(labelled, [
          _title,
          _subtitle,
        ], reason: 'logo anlamsal ağaçta yok (dekoratif)');
        handle.dispose();
      },
    );

    testWidgets('yalnız logo: anlamsal ağaçta etiketli düğüm yok', (t) async {
      final handle = t.ensureSemantics();
      await pumpAt(t, const LoginHero(), scale: 1.0);
      final labelled = t.semantics.simulatedAccessibilityTraversal().where(
        (n) => n.getSemanticsData().label.isNotEmpty,
      );
      expect(labelled, isEmpty);
      handle.dispose();
    });

    testWidgets('başlık ilk karede (opaklık 0) bile anlamsal ağaçta vardır', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(harnessApp(_full));
      expect(_opacity(t), 0);
      expect(find.bySemanticsLabel(_title), findsOneWidget);
      handle.dispose();
    });
  });

  group('LoginHero: taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu)', () {
    testWidgets('başlık+alt başlık / yalnız logo hiçbir hücrede taşmaz', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        for (final hero in const [
          _full,
          LoginHero(),
          LoginHero(title: _title),
        ]) {
          await pumpAt(
            t,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: hero,
            ),
            width: width,
            scale: scale,
            dark: dark,
          );
          expect(
            t.getSize(find.byType(LoginHero)).width,
            lessThanOrEqualTo(width),
            reason: '${width}px x$scale ${dark ? 'koyu' : 'açık'}',
          );
        }
      });
    });

    testWidgets(
      'belirli pencereler (320x640@2,0 / 360x640@1,5 / 640x360@2,0 / tablet), ışık animasyonu AÇIKKEN de taşmaz',
      (t) async {
        GudeLogoAnimation.enabledByDefault = true;
        addTearDown(() => GudeLogoAnimation.enabledByDefault = false);
        const cells = <(double, double, double)>[
          (320, 640, 2.0),
          (360, 640, 1.5),
          (640, 360, 2.0),
          (820, 1180, 1.0),
        ];
        for (final (w, h, s) in cells) {
          for (final dark in const [false, true]) {
            await pumpAt(
              t,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _full,
              ),
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            // Süpürmenin içinde de çiz.
            await t.pump(const Duration(milliseconds: 1250));
            expect(t.takeException(), isNull, reason: '${w}x$h @$s dark=$dark');
            expect(
              t.getRect(find.byType(LoginHero)).width,
              lessThanOrEqualTo(w),
            );
          }
        }
      },
    );

    testWidgets(
      'çok uzun başlık/alt başlık ve bölünemeyen uzun sözcük satır sarar, taşmaz',
      (t) async {
        await forEachHarnessCell((width, scale, dark) async {
          await pumpAt(
            t,
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  LoginHero(
                    title: 'Akıllı Kapı Site Otomasyon Yönetim Paneli Girişi',
                    subtitle:
                        'Akıllı Kapı & Site Otomasyon Paneli: kapılarınızı ve cihazlarınızı yönetin',
                  ),
                  LoginHero(title: 'Süpersitekonfigürasyonyönetimi'),
                ],
              ),
            ),
            width: width,
            scale: scale,
            dark: dark,
          );
        });
      },
    );

    testWidgets('hareket azaltmada da taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, _full, width: 320, scale: 2.0, reduce: true);
      expect(t.takeException(), isNull);
    });
  });
}
