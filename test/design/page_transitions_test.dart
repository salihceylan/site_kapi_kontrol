// FAZ 5 / A0: AppPageTransitionsBuilder (rota geçişi) ve PageEntry (sayfa içeriği girişi) testleri.
import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

Widget _app({
  bool reduce = false,
  TargetPlatform? platform,
  bool dark = false,
}) {
  final base = dark ? AppTheme.dark() : AppTheme.light();
  return MaterialApp(
    navigatorKey: _nav,
    theme: platform == null ? base : base.copyWith(platform: platform),
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: reduce),
      child: child!,
    ),
    home: const Scaffold(body: Center(child: Text('Sayfa A'))),
  );
}

/// Rotayı iter ve iki kare ilerletir: MaterialApp'in HeroController'ı yeni rotayı ilk karede
/// `offstage` tutar (hedef Hero ölçümü); ikinci karede içerik sahneye girer, animasyon 0'dadır.
Future<void> _pushAndStart(WidgetTester t) async {
  _push();
  await t.pump();
  await t.pump();
}

void _push() {
  _nav.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('Sayfa B'))),
    ),
  );
}

/// 'Sayfa B'nin en yakın FadeTransition/SlideTransition ataları (AppPageTransitionsBuilder'ın).
FadeTransition _fade(WidgetTester t) => t.widget<FadeTransition>(
  find
      .ancestor(of: find.text('Sayfa B'), matching: find.byType(FadeTransition))
      .first,
);

SlideTransition _slide(WidgetTester t) => t.widget<SlideTransition>(
  find
      .ancestor(
        of: find.text('Sayfa B'),
        matching: find.byType(SlideTransition),
      )
      .first,
);

void main() {
  group('AppPageTransitionsBuilder', () {
    test('süreler: giriş 240 ms, çıkış 200 ms (<= 320 ms bütçe)', () {
      const builder = AppPageTransitionsBuilder();
      expect(builder.transitionDuration, const Duration(milliseconds: 240));
      expect(
        builder.reverseTransitionDuration,
        const Duration(milliseconds: 200),
      );
      expect(builder.transitionDuration, lessThanOrEqualTo(AppMotion.slow));
      expect(builder.reverseTransitionDuration, AppMotion.base);
    });

    testWidgets('push: solma + %4 yatay kayma; 240 ms sonra tam ve durağan', (
      t,
    ) async {
      await t.pumpWidget(_app());
      await _pushAndStart(t); // rota eklendi, animasyon 0'da
      expect(find.text('Sayfa B'), findsOneWidget);
      expect(_fade(t).opacity.value, 0);
      expect(_slide(t).position.value.dx, closeTo(0.04, 1e-9));
      expect(_slide(t).position.value.dy, 0);

      await t.pump(const Duration(milliseconds: 100));
      final midOpacity = _fade(t).opacity.value;
      final midDx = _slide(t).position.value.dx;
      expect(midOpacity, inExclusiveRange(0, 1));
      expect(midDx, inExclusiveRange(0, 0.04));

      await t.pump(const Duration(milliseconds: 150)); // 250 ms > 240 ms
      expect(_fade(t).opacity.value, 1);
      expect(_slide(t).position.value.dx, 0);
      await t.pumpAndSettle();
      expect(
        t.binding.transientCallbackCount,
        0,
        reason: 'kararlı durumda ticker yok',
      );
    });

    testWidgets('pop: 200 ms\'de solarak çıkar, sonra ağaçtan kalkar', (
      t,
    ) async {
      await t.pumpWidget(_app());
      _push();
      await t.pumpAndSettle();
      _nav.currentState!.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Sayfa B'),
        findsOneWidget,
        reason: '100 ms: hâlâ çıkıyor',
      );
      expect(_fade(t).opacity.value, lessThan(1));
      await t.pump(const Duration(milliseconds: 150)); // 250 ms > 200 ms
      await t.pumpAndSettle();
      expect(find.text('Sayfa B'), findsNothing);
      expect(find.text('Sayfa A'), findsOneWidget);
    });

    testWidgets(
      'giriş sırasında geri dönmek (yarıda çevirme) hata vermez ve tutarlı biter',
      (t) async {
        await t.pumpWidget(_app());
        _push();
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        _nav.currentState!.pop();
        await t.pump();
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 40));
          expect(t.takeException(), isNull);
        }
        await t.pumpAndSettle();
        expect(find.text('Sayfa B'), findsNothing);
      },
    );

    testWidgets('hareket azaltma: geçiş katmanı yok, içerik doğrudan gelir', (
      t,
    ) async {
      await t.pumpWidget(_app(reduce: true));
      await _pushAndStart(t);
      expect(find.text('Sayfa B'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Sayfa B'),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.text('Sayfa B'),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'hareket azaltma açıkken açılıp kapanınca hareket geri gelir (MediaQuery bağımlılığı)',
      (t) async {
        await t.pumpWidget(_app(reduce: true));
        await t.pumpWidget(_app());
        await _pushAndStart(t);
        expect(_slide(t).position.value.dx, closeTo(0.04, 1e-9));
      },
    );

    testWidgets(
      'iOS: Cupertino geri-kaydırma geçişi korunur (AppPageTransitionsBuilder değil)',
      (t) async {
        await t.pumpWidget(_app(platform: TargetPlatform.iOS));
        _push();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(
          find.ancestor(
            of: find.text('Sayfa B'),
            matching: find.byType(CupertinoPageTransition),
          ),
          findsWidgets,
        );
      },
    );

    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
    ]) {
      testWidgets('${platform.name}: fade + slide geçişi', (t) async {
        await t.pumpWidget(_app(platform: platform));
        _push();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(_fade(t).opacity.value, inExclusiveRange(0, 1));
        expect(
          find.ancestor(
            of: find.text('Sayfa B'),
            matching: find.byType(CupertinoPageTransition),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('açık ve koyu temada geçiş tamamlanır (iki tema)', (t) async {
      for (final dark in [false, true]) {
        await t.pumpWidget(_app(dark: dark));
        _push();
        await t.pumpAndSettle();
        expect(find.text('Sayfa B'), findsOneWidget);
        _nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(find.text('Sayfa B'), findsNothing);
      }
    });

    testWidgets(
      'geçiş sırasında üst ağaç yeniden kurulsa da animasyon kesilmez',
      (t) async {
        await t.pumpWidget(_app());
        _push();
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        await t.pumpWidget(_app()); // aynı yapı, yeniden kurma
        await t.pump(const Duration(milliseconds: 60));
        expect(_fade(t).opacity.value, inExclusiveRange(0, 1));
        await t.pumpAndSettle();
        expect(_fade(t).opacity.value, 1);
      },
    );
  });

  group('PageEntry', () {
    Widget entry(String id, {bool reduce = false, Widget? child}) => harnessApp(
      PageEntry(key: ValueKey(id), child: child ?? Text('İçerik $id')),
      reduce: reduce,
    );

    double opacity(WidgetTester t) => t
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(PageEntry),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    double dy(WidgetTester t) => t
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(PageEntry),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .y;

    testWidgets(
      'ilk kurulum: saydam + 8 dp aşağıda başlar, 200 ms sonra tamamdır',
      (t) async {
        await t.pumpWidget(entry('a'));
        expect(opacity(t), 0);
        expect(dy(t), closeTo(8, 1e-9));
        await t.pump(const Duration(milliseconds: 100));
        expect(opacity(t), inExclusiveRange(0, 1));
        expect(dy(t), inExclusiveRange(0, 8));
        await t.pump(const Duration(milliseconds: 120));
        expect(opacity(t), 1);
        expect(dy(t), 0);
        expect(
          t.binding.transientCallbackCount,
          0,
          reason: 'giriş bitince ticker çalışmaz',
        );
      },
    );

    testWidgets(
      'anahtar değişince YALNIZ yeni içerik gelir (çift widget yok) ve yeniden oynar',
      (t) async {
        await t.pumpWidget(entry('a'));
        await t.pumpAndSettle();
        expect(find.text('İçerik a'), findsOneWidget);
        await t.pumpWidget(entry('b'));
        expect(
          find.text('İçerik a'),
          findsNothing,
          reason: 'eski içerik hemen kalkar',
        );
        expect(find.text('İçerik b'), findsOneWidget);
        expect(find.byType(PageEntry), findsOneWidget);
        expect(opacity(t), 0);
        for (var i = 0; i < 5; i++) {
          await t.pump(const Duration(milliseconds: 50));
          expect(
            find.byType(Text),
            findsOneWidget,
            reason: 'her karede tek içerik',
          );
        }
        expect(opacity(t), 1);
      },
    );

    testWidgets('aynı anahtarla yeniden kurma animasyonu tekrarlamaz', (
      t,
    ) async {
      await t.pumpWidget(entry('a'));
      await t.pumpAndSettle();
      await t.pumpWidget(entry('a', child: const Text('güncel')));
      expect(find.text('güncel'), findsOneWidget);
      expect(opacity(t), 1);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'çocuk animasyon boyunca yeniden kurulmaz (yalnız boyama dönüşümü)',
      (t) async {
        var builds = 0;
        await t.pumpWidget(
          harnessApp(
            PageEntry(
              child: Builder(
                builder: (_) {
                  builds++;
                  return const Text('ağır içerik');
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(builds, 1);
      },
    );

    testWidgets('hareket azaltma: ilk karede tam, ticker yok', (t) async {
      await t.pumpWidget(entry('a', reduce: true));
      expect(opacity(t), 1);
      expect(dy(t), 0);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('hareket yarıda azaltılırsa içerik hemen tamamlanır', (
      t,
    ) async {
      await t.pumpWidget(entry('a'));
      await t.pump(const Duration(milliseconds: 50));
      expect(opacity(t), lessThan(1));
      await t.pumpWidget(entry('a', reduce: true));
      expect(opacity(t), 1);
    });

    testWidgets('pumpAndSettle biter', (t) async {
      await t.pumpWidget(entry('a'));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('Semantics ilk karede (opaklık 0 iken) de açıktır', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(entry('a'));
      expect(opacity(t), 0);
      expect(find.bySemanticsLabel('İçerik a'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('taşma matrisi: 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: PageEntry(
              key: ValueKey('$width$scale$dark'),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kapı Kontrol Paneli: Güneş Sitesi A Blok Ana Giriş'),
                  SizedBox(height: AppSpace.sm),
                  Text(
                    'Çevrimiçi (Bulut) · Son görülme 12 sn önce · Yerel ağ bulundu',
                  ),
                ],
              ),
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(
          opacity(t),
          1,
          reason:
              '450 ms sonra giriş bitmiş olmalı ($width x $scale dark=$dark)',
        );
      });
    });
  });
}
