// Premium yüzey katmanları: AppCard ışığı, StatusChip LED noktası, AppSnack cam rozeti,
// PrimaryActionButton cilası + başarı ışıltısı ve AppTheme ince ayarları (cilalı düğmeler, ilerleme,
// menü, ipucu, alt sayfa).
//
// Ortak ilke: hepsi statik gradyan/gölgedir; dokunmayı yutmaz, kararlı durumda ticker yoktur,
// hareket azaltmada efekt yoktur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

AppPalette _palette(bool dark) => dark ? AppPalette.dark : AppPalette.light;

Widget _app(Widget w, {bool dark = false, bool reduce = false}) => harnessApp(
  Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: w)),
  dark: dark,
  reduce: reduce,
);

/// [root] altındaki gradyanlı DecoratedBox'lar.
Finder _gradientBoxes(Finder root) => find.descendant(
  of: root,
  matching: find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).gradient != null,
  ),
);

Gradient _gradientOf(WidgetTester t, Finder box) =>
    (t.widget<DecoratedBox>(box).decoration as BoxDecoration).gradient!;

void main() {
  group('AppCard: premium yüzey katmanı', () {
    testWidgets('açık tema, level 1: düz kart (ışık/yıkama yok)', (t) async {
      await t.pumpWidget(_app(const AppCard(child: Text('x'))));
      expect(_gradientBoxes(find.byType(AppCard)), findsNothing);
    });

    testWidgets('koyu tema, level 1: sol-üstten cam gibi hafif üst ışık', (
      t,
    ) async {
      await t.pumpWidget(_app(const AppCard(child: Text('x')), dark: true));
      await t.pumpAndSettle();
      final box = _gradientBoxes(find.byType(AppCard));
      expect(box, findsOneWidget);
      final g = _gradientOf(t, box) as LinearGradient;
      expect(g.colors.first.a, lessThan(0.1), reason: 'çok hafif');
      expect(g.colors.last.a, 0);
    });

    testWidgets('level >= 2 (hero): tonun sol-üst yıkaması; ton verilirse o ton', (
      t,
    ) async {
      for (final dark in [false, true]) {
        final p = _palette(dark);
        for (final level in [2, 3]) {
          await t.pumpWidget(
            _app(AppCard(level: level, child: const Text('x')), dark: dark),
          );
          await t.pumpAndSettle();
          final g =
              _gradientOf(t, _gradientBoxes(find.byType(AppCard)))
                  as RadialGradient;
          expect(
            g.colors.first,
            AppTone.primary.hue.withValues(alpha: p.isDark ? 0.16 : 0.09),
            reason: 'L$level dark=$dark',
          );
          expect(g.colors.last.a, 0);
        }
        await t.pumpWidget(
          _app(
            AppCard(level: 2, tone: AppTone.warning, child: const Text('x')),
            dark: dark,
          ),
        );
        await t.pumpAndSettle();
        final g =
            _gradientOf(t, _gradientBoxes(find.byType(AppCard)))
                as RadialGradient;
        expect(g.colors.first.toARGB32() & 0x00FFFFFF,
            AppTone.warning.hue.toARGB32() & 0x00FFFFFF);
      }
    });

    testWidgets('ışık katmanı dokunmayı yutmaz ve opak Material rengi değişmez', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(
        _app(
          AppCard(
            level: 2,
            onTap: () => taps++,
            child: const SizedBox(height: 40, child: Text('içerik')),
          ),
          dark: true,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('içerik'));
      expect(taps, 1);
      final material = t.widget<Material>(
        find
            .descendant(of: find.byType(AppCard), matching: find.byType(Material))
            .first,
      );
      expect(material.color, AppPalette.dark.surfaceAt(2));
      expect(material.color!.a, 1.0);
      // Katman IgnorePointer içindedir.
      expect(
        find.ancestor(
          of: _gradientBoxes(find.byType(AppCard)),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    testWidgets('accentBar: çubuk korunur + altında ince ışık sızıntısı', (
      t,
    ) async {
      const bar = Color(0xFF7E22CE);
      await t.pumpWidget(
        _app(const AppCard(accentBar: bar, child: Text('x'))),
      );
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == bar,
          ),
        ),
        findsOneWidget,
        reason: '3 dp çubuk',
      );
      final spill = _gradientBoxes(find.byType(AppCard));
      expect(spill, findsOneWidget);
      final g = _gradientOf(t, spill) as LinearGradient;
      expect(g.colors.first, bar.withValues(alpha: 0.16));
      expect(g.colors.last, bar.withValues(alpha: 0));
    });

    testWidgets('durağan: ticker ve kare yok', (t) async {
      await t.pumpWidget(
        _app(
          const AppCard(
            level: 2,
            accentBar: Colors.blue,
            child: Text('x'),
          ),
          dark: true,
        ),
      );
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
      expect(t.binding.hasScheduledFrame, isFalse);
    });
  });

  group('StatusChip: düz nokta (sade stil, LED parıltısı yok)', () {
    Finder ledDot() => find.descendant(
      of: find.byType(StatusChip),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).boxShadow != null,
      ),
    );

    testWidgets('nabızlı (canlı) nokta da düzdür: gölge / parıltı yok; nabız sonlu', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          const Center(
            child: StatusChip(
              label: 'Çevrimiçi',
              tone: AppTone.success,
              pulse: true,
            ),
          ),
        ),
      );
      await t.pump();
      expect(ledDot(), findsNothing);
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0, reason: 'nabız biter');
    });

    testWidgets('nabızsız nokta düzdür (parıltı yok)', (t) async {
      await t.pumpWidget(
        harnessApp(
          const Center(
            child: StatusChip(label: 'Cihaz Yok', tone: AppTone.neutral),
          ),
        ),
      );
      expect(ledDot(), findsNothing);
    });
  });

  group('AppSnack: cam rozetli simge', () {
    testWidgets('simge yarı saydam beyaz daire rozette, anlamsal ağaçta yok', (
      t,
    ) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      AppSnack.show(
        t.element(find.byType(Scaffold)),
        'Kaydedildi',
        kind: AppSnackKind.success,
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final badge = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(badge, findsOneWidget);
      final deco = t.widget<DecoratedBox>(badge).decoration as BoxDecoration;
      expect(deco.color, Colors.white.withValues(alpha: 0.20));
      expect(deco.border, isNotNull);
      expect(
        t.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color,
        Colors.white,
      );
      expect(
        find.ancestor(
          of: badge,
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
    });
  });

  group('PrimaryActionButton: cila ve başarı ışıltısı', () {
    Finder gloss() => find.descendant(
      of: find.byType(PrimaryActionButton),
      matching: find.byType(Gloss),
    );

    PrimaryActionButton button({
      AppButtonVariant variant = AppButtonVariant.filled,
      VoidCallback? onPressed,
      bool loading = false,
      bool success = false,
    }) => PrimaryActionButton(
      label: 'Kaydet',
      onPressed: onPressed,
      variant: variant,
      loading: loading,
      success: success,
    );

    testWidgets('yalnız canlı dolu düğme cilalıdır', (t) async {
      await t.pumpWidget(_app(button(onPressed: () {})));
      expect(gloss(), findsOneWidget);
      await t.pumpWidget(_app(button(onPressed: () {}, loading: true)));
      expect(gloss(), findsOneWidget, reason: 'yükleniyor: canlı');
      await t.pumpWidget(_app(button(onPressed: () {}, success: true)));
      expect(gloss(), findsOneWidget, reason: 'başarılı: canlı');
      await t.pumpWidget(_app(button()));
      expect(gloss(), findsNothing, reason: 'devre dışı: düz');
      for (final v in [AppButtonVariant.tonal, AppButtonVariant.outline]) {
        await t.pumpWidget(_app(button(variant: v, onPressed: () {})));
        expect(gloss(), findsNothing, reason: '${v.name}: ikincil, düz');
      }
    });

    testWidgets(
      'success false -> true: ışıltı bir kez oynar ve biter (ticker kalmaz)',
      (t) async {
        Animation<double> sweep() => t.widget<Gloss>(gloss()).sweep!;
        await t.pumpWidget(_app(button(onPressed: () {})));
        expect(sweep().value, 0);
        await t.pumpWidget(_app(button(onPressed: () {}, success: true)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));
        expect(sweep().value, greaterThan(0));
        await t.pump(PrimaryActionButton.sweepDuration);
        await t.pump(const Duration(milliseconds: 50));
        expect(sweep().status, AnimationStatus.completed);
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('hareket azaltmada ışıltı oynamaz', (t) async {
      Animation<double> sweep() => t.widget<Gloss>(gloss()).sweep!;
      await t.pumpWidget(_app(button(onPressed: () {}), reduce: true));
      await t.pumpWidget(
        _app(button(onPressed: () {}, success: true), reduce: true),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(sweep().value, 0);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('cila dokunmayı yutmaz: onPressed çalışır', (t) async {
      var calls = 0;
      await t.pumpWidget(_app(button(onPressed: () => calls++)));
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      expect(calls, 1);
    });
  });

  group('AppTheme: sade düğmeler + ince ayarlar', () {
    for (final entry in <String, ThemeData Function()>{
      'açık': AppTheme.light,
      'koyu': AppTheme.dark,
    }.entries) {
      test('${entry.key}: hiçbir tema düğmesinde cila / degrade katmanı yok (sade stil G6)', () {
        final theme = entry.value();
        expect(theme.elevatedButtonTheme.style!.backgroundBuilder, isNull);
        expect(theme.filledButtonTheme.style!.backgroundBuilder, isNull);
        expect(theme.outlinedButtonTheme.style!.backgroundBuilder, isNull);
        expect(theme.textButtonTheme.style!.backgroundBuilder, isNull);
      });

      test('${entry.key}: ilerleme, menü, ipucu ve alt sayfa ayarları', () {
        final theme = entry.value();
        expect(theme.progressIndicatorTheme.strokeCap, StrokeCap.round);
        expect(theme.progressIndicatorTheme.linearMinHeight, 6);
        final popup = theme.popupMenuTheme.shape! as RoundedRectangleBorder;
        expect(popup.borderRadius, BorderRadius.circular(AppRadius.md));
        expect(theme.popupMenuTheme.surfaceTintColor, Colors.transparent);
        final tip = theme.tooltipTheme.decoration! as BoxDecoration;
        expect(tip.borderRadius, BorderRadius.circular(AppRadius.sm));
        expect(theme.tooltipTheme.textStyle!.color, Colors.white);
        final sheet = theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
        expect(
          sheet.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        );
        expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
      });
    }

    testWidgets('tema düğmeleri (dolu, devre dışı, ikincil, metin) düz çizilir: cila yok, durağan', (
      t,
    ) async {
      for (final dark in [false, true]) {
        await t.pumpWidget(
          harnessApp(
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(onPressed: () {}, child: const Text('E')),
                  FilledButton(onPressed: () {}, child: const Text('F')),
                  const ElevatedButton(onPressed: null, child: Text('D')),
                  OutlinedButton(onPressed: () {}, child: const Text('O')),
                  TextButton(onPressed: () {}, child: const Text('T')),
                ],
              ),
            ),
            dark: dark,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(Gloss), findsNothing, reason: 'dark=$dark');
        expect(t.binding.transientCallbackCount, 0, reason: 'durağan');
      }
    });

    testWidgets('tema düğmesi dokunmayı alır (onPressed çalışır)', (
      t,
    ) async {
      var calls = 0;
      await t.pumpWidget(
        harnessApp(
          Center(
            child: ElevatedButton(
              onPressed: () => calls++,
              child: const Text('Tamam'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Tamam'));
      await t.pumpAndSettle();
      expect(calls, 1);
    });
  });
}
