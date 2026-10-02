// FAZ 5 / A1b-(iii): LoginHero widget testleri.
//
// Durumlar (başlık+alt başlık / yalnız başlık / yalnız logo), logonun gösterim boyutunda çözülmesi,
// giriş animasyonu ve hareket azaltma, pumpAndSettle'ın bitmesi, taşma matrisi (320/360/412/820 x
// 1,0/1,5/2,0 x açık/koyu) ve Semantics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/login_hero.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

const String _title = 'AHBU Giriş';
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

/// Logo halkasının (gradyanlı kap) süslemesi.
BoxDecoration _ringDecoration(WidgetTester t) {
  final f = find
      .descendant(of: find.byType(LoginHero), matching: find.byType(Container))
      .first;
  return t.widget<Container>(f).decoration! as BoxDecoration;
}

Image _logo(WidgetTester t) => t.widget<Image>(find.byType(Image));

void main() {
  group('LoginHero: durumlar', () {
    testWidgets('başlık + alt başlık + logo: metinler birebir', (t) async {
      await pumpAt(t, _full, scale: 1.0);
      expect(find.text('AHBU Giriş'), findsOneWidget);
      expect(find.text('Akıllı Kapı & Site Otomasyon Paneli'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('yalnız başlık: alt başlık yok', (t) async {
      await pumpAt(t, const LoginHero(title: _title), scale: 1.0);
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_subtitle), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('yalnız alt başlık: başlık yok', (t) async {
      await pumpAt(t, const LoginHero(subtitle: _subtitle), scale: 1.0);
      expect(find.text(_subtitle), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('ikisi de null: yalnız logo (açılış/ara ekran)', (t) async {
      await pumpAt(t, const LoginHero(), scale: 1.0);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(t.getSize(find.byType(LoginHero)).width, LoginHero.ringDiameter);
    });

    testWidgets('boyutlar: 96 dp halka, 80 dp logo (cover, daire kırpma)', (
      t,
    ) async {
      await pumpAt(t, const LoginHero(), scale: 1.0);
      expect(LoginHero.ringDiameter, 96);
      expect(LoginHero.logoDiameter, 80);
      expect(t.getSize(find.byType(LoginHero)), const Size(96, 96));
      expect(t.getSize(find.byType(Image)), const Size(80, 80));
      expect(_logo(t).fit, BoxFit.cover);
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('logo varlığı DEĞİŞMEZ: assets/images/app_logo.png', (t) async {
      await pumpAt(t, const LoginHero(), scale: 1.0);
      final provider = _logo(t).image;
      expect(provider, isA<ResizeImage>());
      final inner = (provider as ResizeImage).imageProvider;
      expect(inner, isA<AssetImage>());
      expect((inner as AssetImage).assetName, 'assets/images/app_logo.png');
      expect(LoginHero.logoAsset, 'assets/images/app_logo.png');
    });

    testWidgets(
      'halka: birincil gradyan, iç yüzey palet yüzeyi, TEK gölge (blur <= 16, spread yok)',
      (t) async {
        for (final dark in const [false, true]) {
          await pumpAt(t, const LoginHero(), scale: 1.0, dark: dark);
          final p = dark ? AppPalette.dark : AppPalette.light;
          final ring = _ringDecoration(t);
          expect(ring.shape, BoxShape.circle);
          expect(ring.gradient, AppTone.primary.gradient);
          expect(
            ring.boxShadow,
            hasLength(1),
            reason: 'yüzey başına 1 gölge katmanı',
          );
          expect(ring.boxShadow!.single.blurRadius, lessThanOrEqualTo(16));
          expect(ring.boxShadow!.single.spreadRadius, 0);
          expect(ring.boxShadow, p.shadow(2));
          final inner = t.widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(LoginHero),
                  matching: find.byType(DecoratedBox),
                )
                .at(1),
          );
          expect(
            (inner.decoration as BoxDecoration).color,
            p.surface,
            reason: 'dark=$dark',
          );
        }
      },
    );

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
  });

  group('LoginHero: logo gösterim boyutunda çözülür', () {
    for (final dpr in const [1.0, 2.0, 3.0, 3.5]) {
      testWidgets('devicePixelRatio $dpr: cacheWidth = ceil(80 x dpr)', (
        t,
      ) async {
        t.view.physicalSize = Size(360 * dpr, 640 * dpr);
        t.view.devicePixelRatio = dpr;
        addTearDown(t.view.reset);
        await t.pumpWidget(harnessApp(const LoginHero()));
        final provider = _logo(t).image as ResizeImage;
        expect(provider.width, (80 * dpr).ceil());
        expect(provider.height, isNull, reason: 'en-boy oranı korunur');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets(
      'gerçek çözümleme: 1024x1024 tam çözünürlük bellekte TUTULMAZ (3.0 dpr: ~225 KB)',
      (t) async {
        t.view.physicalSize = const Size(1080, 2400);
        t.view.devicePixelRatio = 3.0;
        addTearDown(t.view.reset);
        final cache = PaintingBinding.instance.imageCache;
        cache.clear();
        cache.clearLiveImages();

        await t.pumpWidget(harnessApp(const LoginHero()));
        await t.runAsync(() async {
          final element = t.element(find.byType(Image));
          await precacheImage(_logo(t).image, element);
        });
        await t.pump();
        expect(
          cache.currentSizeBytes,
          lessThan(1024 * 1024),
          reason: 'tam çözünürlüklü (4 MB) bitmap tutulmamalı',
        );
      },
    );
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
        ], reason: 'logo (resim) anlamsal ağaçta yok');
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
