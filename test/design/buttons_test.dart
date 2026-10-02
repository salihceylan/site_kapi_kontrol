// FAZ 5 / A1a: PressableScale ve PrimaryActionButton widget testleri.
//
// Durumlar (normal/basılı/devre dışı/yükleniyor/başarılı), üç görünüm (filled/tonal/outline), taşma
// matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu), hareket azaltmada tek pump, pumpAndSettle'ın
// bitmesi, Semantics, klavye, haptik zamanlaması ve en az 44 dp dokunma hedefi.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

const String _selection = 'HapticFeedbackType.selectionClick';

/// PressableScale'in hedef ölçeği (setState sonrası hemen).
double _targetScale(WidgetTester t, [Finder? within]) {
  final f = within == null
      ? find.byType(AnimatedScale)
      : find.descendant(of: within, matching: find.byType(AnimatedScale));
  return t.widget<AnimatedScale>(f.first).scale;
}

/// Ekranda çizilen (animasyonlu) ölçek.
double _paintedScale(WidgetTester t, [Finder? within]) {
  final f = within == null
      ? find.byType(ScaleTransition)
      : find.descendant(of: within, matching: find.byType(ScaleTransition));
  return t.widget<ScaleTransition>(f.first).scale.value;
}

/// PrimaryActionButton'ın o an çizilen kutu süslemesi.
BoxDecoration _decoration(WidgetTester t) {
  final f = find.descendant(
    of: find.byType(AnimatedContainer),
    matching: find.byType(DecoratedBox),
  );
  return t.widget<DecoratedBox>(f.first).decoration as BoxDecoration;
}

/// Erişilebilirlik gezintisinde (TalkBack/VoiceOver) dokunma eylemi olan düğüm sayısı.
int _tapNodes(WidgetTester t) => t.semantics
    .simulatedAccessibilityTraversal()
    .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
    .length;

PrimaryActionButton _button({
  String label = 'Kaydet',
  VoidCallback? onPressed,
  IconData? icon,
  AppTone tone = AppTone.primary,
  AppButtonVariant variant = AppButtonVariant.filled,
  bool loading = false,
  bool success = false,
  bool expand = true,
}) => PrimaryActionButton(
  label: label,
  onPressed: onPressed,
  icon: icon,
  tone: tone,
  variant: variant,
  loading: loading,
  success: success,
  expand: expand,
);

void main() {
  group('PressableScale', () {
    Widget target(VoidCallback onTap, {bool enabled = true}) => Center(
      child: PressableScale(
        enabled: enabled,
        child: Material(
          child: InkWell(
            onTap: onTap,
            child: const SizedBox(
              width: 160,
              height: 48,
              child: Center(child: Text('Dokun')),
            ),
          ),
        ),
      ),
    );

    testWidgets(
      'iç InkWell onTap ENGELLENMEZ; basılıyken 0,97, bırakınca 1,0',
      (t) async {
        var taps = 0;
        await t.pumpWidget(harnessApp(target(() => taps++)));
        expect(_targetScale(t), 1.0);

        final g = await t.startGesture(t.getCenter(find.text('Dokun')));
        await t.pump(
          const Duration(milliseconds: 150),
        ); // kPressTimeout (100 ms) geçti: onTapDown
        await t.pump(
          const Duration(milliseconds: 150),
        ); // 120 ms'lik ölçek animasyonu biter
        expect(_targetScale(t), 0.97);
        expect(_paintedScale(t), closeTo(0.97, 1e-9));
        expect(taps, 0, reason: 'tap parmak kalkınca olur');

        await g.up();
        await t.pump();
        expect(taps, 1, reason: 'iç InkWell onTap tetiklendi');
        await t.pump(const Duration(milliseconds: 200));
        expect(
          _targetScale(t),
          1.0,
          reason: 'onTapCancel/onTapUp ile geri döner',
        );
        expect(_paintedScale(t), closeTo(1.0, 1e-9));
      },
    );

    testWidgets('kısa dokunuşta (basılı tutmadan) onTap tam bir kez çalışır', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(harnessApp(target(() => taps++)));
      await t.tap(find.text('Dokun'));
      await t.pumpAndSettle();
      expect(taps, 1);
      expect(_targetScale(t), 1.0);
    });

    testWidgets(
      'sürükleme/kaydırma başlayınca ölçek takılı kalmaz ve tap olmaz',
      (t) async {
        var taps = 0;
        await t.pumpWidget(
          harnessApp(
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  target(() => taps++),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        );
        final g = await t.startGesture(t.getCenter(find.text('Dokun')));
        await t.pump(const Duration(milliseconds: 150));
        expect(_targetScale(t), 0.97);
        await g.moveBy(const Offset(0, -80));
        await t.pump();
        expect(_targetScale(t), 1.0, reason: 'onTapCancel ölçeği geri aldı');
        await g.up();
        await t.pumpAndSettle();
        expect(taps, 0);
        expect(_targetScale(t), 1.0);
      },
    );

    testWidgets('enabled: false iken ölçek hiç değişmez; tap yine çalışır', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(harnessApp(target(() => taps++, enabled: false)));
      final g = await t.startGesture(t.getCenter(find.text('Dokun')));
      await t.pump(const Duration(milliseconds: 150));
      expect(_targetScale(t), 1.0);
      await g.up();
      await t.pump();
      expect(taps, 1);
    });

    testWidgets('basılıyken devre dışı bırakılırsa ölçek geri döner', (
      t,
    ) async {
      Widget build(bool enabled) => harnessApp(target(() {}, enabled: enabled));
      await t.pumpWidget(build(true));
      final g = await t.startGesture(t.getCenter(find.text('Dokun')));
      await t.pump(const Duration(milliseconds: 150));
      expect(_targetScale(t), 0.97);
      await t.pumpWidget(build(false));
      expect(_targetScale(t), 1.0);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('düzeni ve boyutu değiştirmez; özel ölçek kabul eder', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          const Center(
            child: PressableScale(
              scale: 0.9,
              child: SizedBox(width: 120, height: 60, child: Text('x')),
            ),
          ),
        ),
      );
      final before = t.getSize(find.byType(PressableScale));
      final g = await t.startGesture(t.getCenter(find.byType(PressableScale)));
      await t.pump(const Duration(milliseconds: 300));
      expect(_targetScale(t), 0.9);
      expect(t.getSize(find.byType(PressableScale)), before);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('hareket azaltma: ölçek animasyonu süresiz (tek pump)', (
      t,
    ) async {
      await t.pumpWidget(harnessApp(target(() {}), reduce: true));
      expect(
        t.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      final g = await t.startGesture(t.getCenter(find.text('Dokun')));
      await t.pump(const Duration(milliseconds: 110));
      expect(_paintedScale(t), closeTo(0.97, 1e-9));
      await g.up();
      await t.pump();
      expect(_paintedScale(t), closeTo(1.0, 1e-9));
    });

    testWidgets(
      'Semantics: dış GestureDetector anlamsal tap eklemez (tek dokunulabilir düğüm)',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(harnessApp(target(() {})));
        final detector = t.widget<GestureDetector>(
          find
              .descendant(
                of: find.byType(PressableScale),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(detector.excludeFromSemantics, isTrue);
        expect(_tapNodes(t), 1, reason: 'yalnız InkWell dokunulabilir');
        expect(
          t.getSemantics(find.text('Dokun')),
          isSemantics(label: 'Dokun', hasTapAction: true),
        );
        handle.dispose();
      },
    );

    testWidgets('48 dp çocuk 44 dp hedefin altına düşmez', (t) async {
      await t.pumpWidget(harnessApp(target(() {})));
      expect(
        t.getSize(find.byType(PressableScale)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('taşma matrisi', (t) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: PressableScale(
              child: Material(
                child: InkWell(
                  onTap: () {},
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: Text(
                      'Uzun bir kart başlığı ve açıklaması burada yer alır',
                    ),
                  ),
                ),
              ),
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(find.byType(PressableScale), findsOneWidget);
      });
    });
  });

  group('PrimaryActionButton: durumlar', () {
    testWidgets('normal: etiket + ikon görünür, onPressed tek kez çağrılır', (
      t,
    ) async {
      var calls = 0;
      await t.pumpWidget(
        harnessApp(
          Center(
            child: _button(icon: Icons.save_rounded, onPressed: () => calls++),
          ),
        ),
      );
      expect(find.text('Kaydet'), findsOneWidget);
      expect(find.byIcon(Icons.save_rounded), findsOneWidget);
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'devre dışı (onPressed null): tıklanmaz, haptik yok, nötr görünüm',
      (t) async {
        final haptics = recordHaptics(t);
        await t.pumpWidget(harnessApp(Center(child: _button(onPressed: null))));
        await t.pumpAndSettle();
        await t.tap(find.text('Kaydet'));
        await t.pumpAndSettle();
        expect(haptics, isEmpty);
        final deco = _decoration(t);
        expect(deco.gradient, isNull);
        expect(deco.boxShadow, isNull);
        final p = AppPalette.light;
        expect(deco.color, p.border);
        expect(
          t.widget<Text>(find.text('Kaydet')).style!.color,
          p.textSecondary,
        );
        expect(_targetScale(t), 1.0);
      },
    );

    testWidgets('yükleniyor: etiket ağaçta YOK, spinner var, tıklama kapalı', (
      t,
    ) async {
      var calls = 0;
      final haptics = recordHaptics(t);
      await t.pumpWidget(
        harnessApp(
          Center(
            child: _button(
              label: 'Giriş Yap',
              icon: Icons.login,
              loading: true,
              onPressed: () => calls++,
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Giriş Yap'), findsNothing);
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byType(PrimaryActionButton), warnIfMissed: false);
      await t.pump();
      expect(calls, 0);
      expect(haptics, isEmpty);
      expect(_targetScale(t), 1.0);
    });

    testWidgets('yükleniyor biter: etiket geri gelir ve tıklama açılır', (
      t,
    ) async {
      var calls = 0;
      Widget build(bool loading) => harnessApp(
        Center(
          child: _button(
            label: 'Giriş Yap',
            loading: loading,
            onPressed: () => calls++,
          ),
        ),
      );
      await t.pumpWidget(build(true));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Giriş Yap'), findsNothing);
      await t.pumpWidget(build(false));
      await t.pumpAndSettle();
      expect(find.text('Giriş Yap'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.text('Giriş Yap'));
      await t.pump();
      expect(calls, 1);
    });

    testWidgets(
      'başarılı: onay işareti + success tonuna morph; tıklama kapalı',
      (t) async {
        var calls = 0;
        Widget build(bool success) => harnessApp(
          Center(
            child: _button(
              label: 'Kaydet',
              icon: Icons.save_rounded,
              success: success,
              onPressed: () => calls++,
            ),
          ),
        );
        await t.pumpWidget(build(false));
        await t.pumpAndSettle();
        expect(_decoration(t).gradient, AppTone.primary.gradient);
        expect(find.byIcon(Icons.check_rounded), findsNothing);

        await t.pumpWidget(build(true));
        await t.pump(const Duration(milliseconds: 100));
        final mid = _decoration(t).gradient! as LinearGradient;
        expect(
          mid.colors,
          isNot(AppTone.primary.gradient.colors),
          reason: 'morph sürüyor',
        );
        expect(
          mid.colors,
          isNot(AppTone.success.gradient.colors),
          reason: 'morph henüz bitmedi',
        );
        await t.pumpAndSettle();
        expect(_decoration(t).gradient, AppTone.success.gradient);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.byIcon(Icons.save_rounded), findsNothing);
        expect(find.text('Kaydet'), findsOneWidget, reason: 'etiket kalır');
        await t.tap(find.text('Kaydet'));
        await t.pump();
        expect(calls, 0, reason: 'başarı anında tıklama kapalı');

        await t.pumpWidget(build(false)); // ebeveyn ~1,2 sn sonra false yapar
        await t.pumpAndSettle();
        expect(_decoration(t).gradient, AppTone.primary.gradient);
        await t.tap(find.text('Kaydet'));
        await t.pump();
        expect(calls, 1);
      },
    );

    testWidgets('hareket azaltma: başarı morph tek pump ile tamam', (t) async {
      Widget build(bool success) => harnessApp(
        Center(
          child: _button(success: success, onPressed: () {}),
        ),
        reduce: true,
      );
      await t.pumpWidget(build(false));
      await t.pumpWidget(build(true));
      await t.pump();
      expect(_decoration(t).gradient, AppTone.success.gradient);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        t.binding.transientCallbackCount,
        0,
        reason: 'kararlı durumda ticker yok',
      );
    });

    testWidgets(
      'pumpAndSettle biter: normal, devre dışı ve başarılı (her görünüm, açık+koyu)',
      (t) async {
        for (final dark in [false, true]) {
          for (final variant in AppButtonVariant.values) {
            for (final state in ['normal', 'disabled', 'success']) {
              await t.pumpWidget(
                harnessApp(
                  Center(
                    child: _button(
                      variant: variant,
                      onPressed: state == 'disabled' ? null : () {},
                      success: state == 'success',
                    ),
                  ),
                  dark: dark,
                ),
              );
              await t.pumpAndSettle();
              expect(
                t.binding.transientCallbackCount,
                0,
                reason: '$variant $state dark=$dark',
              );
            }
          }
        }
      },
    );

    testWidgets(
      'görünümler: filled beyaz etiket + gradyan + tek gölge; tonal/outline ink etiket',
      (t) async {
        for (final dark in [false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          for (final tone in [
            AppTone.primary,
            AppTone.info,
            AppTone.danger,
            AppTone.violet,
          ]) {
            await t.pumpWidget(
              harnessApp(
                Center(
                  child: _button(tone: tone, onPressed: () {}),
                ),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            var deco = _decoration(t);
            expect(deco.gradient, tone.gradient);
            expect(deco.boxShadow, hasLength(1));
            expect(deco.boxShadow!.single.blurRadius, lessThanOrEqualTo(16));
            expect(deco.boxShadow!.single.spreadRadius, 0);
            expect(
              t.widget<Text>(find.text('Kaydet')).style!.color,
              Colors.white,
            );

            await t.pumpWidget(
              harnessApp(
                Center(
                  child: _button(
                    tone: tone,
                    variant: AppButtonVariant.tonal,
                    onPressed: () {},
                  ),
                ),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            deco = _decoration(t);
            expect(deco.gradient, isNull);
            expect(deco.color, tone.tint(p));
            expect(deco.boxShadow, isNull);
            expect(
              t.widget<Text>(find.text('Kaydet')).style!.color,
              tone.ink(p),
            );

            await t.pumpWidget(
              harnessApp(
                Center(
                  child: _button(
                    tone: tone,
                    variant: AppButtonVariant.outline,
                    onPressed: () {},
                  ),
                ),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            deco = _decoration(t);
            expect(deco.gradient, isNull);
            expect(deco.color, isNull);
            expect(
              (deco.border! as Border).top.color,
              tone.hue.withValues(alpha: 0.6),
            );
            expect(
              t.widget<Text>(find.text('Kaydet')).style!.color,
              tone.ink(p),
            );
          }
        }
      },
    );

    testWidgets('tonal başarı success tonuna döner (ink + tint)', (t) async {
      final p = AppPalette.light;
      await t.pumpWidget(
        harnessApp(
          Center(
            child: _button(
              variant: AppButtonVariant.tonal,
              success: true,
              onPressed: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(_decoration(t).color, AppTone.success.tint(p));
      expect(
        t.widget<Text>(find.text('Kaydet')).style!.color,
        AppTone.success.ink(p),
      );
    });

    testWidgets('expand: false içerik genişliğinde (>= 120 dp) ve ortalanır', (
      t,
    ) async {
      await pumpAt(
        t,
        Align(
          alignment: Alignment.centerLeft,
          child: _button(label: 'Tamam', expand: false, onPressed: () {}),
        ),
        width: 412,
        scale: 1.0,
      );
      final size = t.getSize(find.byType(PrimaryActionButton));
      expect(size.width, lessThan(412));
      expect(size.width, greaterThanOrEqualTo(120));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('expand: true tüm genişliği kaplar', (t) async {
      await pumpAt(t, _button(onPressed: () {}), width: 360, scale: 1.0);
      expect(t.getSize(find.byType(PrimaryActionButton)).width, 360);
    });
  });

  group('PrimaryActionButton: haptik ve etkileşim', () {
    testWidgets(
      'haptik YALNIZ tap onayında (parmak kalkınca) çalar, basış anında değil',
      (t) async {
        final haptics = recordHaptics(t);
        var calls = 0;
        await t.pumpWidget(
          harnessApp(Center(child: _button(onPressed: () => calls++))),
        );
        final g = await t.startGesture(t.getCenter(find.text('Kaydet')));
        await t.pump(const Duration(milliseconds: 200));
        expect(haptics, isEmpty, reason: 'basış anında titreşim yok');
        expect(calls, 0);
        await g.up();
        await t.pump();
        expect(haptics, <String>[_selection]);
        expect(calls, 1);
      },
    );

    testWidgets('kaydırma (tap iptali) haptik vermez ve onPressed çağırmaz', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      var calls = 0;
      await t.pumpWidget(
        harnessApp(
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 40),
                _button(onPressed: () => calls++),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      final g = await t.startGesture(t.getCenter(find.text('Kaydet')));
      await t.pump(const Duration(milliseconds: 150));
      await g.moveBy(const Offset(0, -90));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(haptics, isEmpty);
      expect(calls, 0);
    });

    testWidgets('klavye: odak + Enter onPressed çağırır (erişilebilirlik)', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      var calls = 0;
      await t.pumpWidget(
        harnessApp(Center(child: _button(onPressed: () => calls++))),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(calls, 1);
      expect(haptics, <String>[_selection]);
    });

    testWidgets('onPressed null iken tab odağı almaz', (t) async {
      await t.pumpWidget(harnessApp(Center(child: _button(onPressed: null))));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<PrimaryActionButton>(),
        isNull,
      );
    });

    testWidgets('basılıyken ölçek 0,97 olur ve bırakınca döner', (t) async {
      await t.pumpWidget(harnessApp(Center(child: _button(onPressed: () {}))));
      final scope = find.byType(PrimaryActionButton);
      final g = await t.startGesture(t.getCenter(find.text('Kaydet')));
      await t.pump(const Duration(milliseconds: 150));
      expect(_targetScale(t, scope), 0.97);
      await g.up();
      await t.pumpAndSettle();
      expect(_targetScale(t, scope), 1.0);
    });
  });

  group('PrimaryActionButton: Semantics ve dokunma hedefi', () {
    testWidgets('normal: düğme, etkin, dokunulabilir, etiketli', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(harnessApp(Center(child: _button(onPressed: () {}))));
      expect(
        t.getSemantics(find.text('Kaydet')),
        isSemantics(
          label: 'Kaydet',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      expect(_tapNodes(t), 1, reason: 'tek dokunulabilir düğüm');
      handle.dispose();
    });

    testWidgets('devre dışı: düğme ama etkin değil, dokunma eylemi yok', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(harnessApp(Center(child: _button(onPressed: null))));
      expect(
        t.getSemantics(find.text('Kaydet')),
        isSemantics(
          label: 'Kaydet',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
          hasTapAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets(
      'yükleniyor: etiket "etiket, Yükleniyor", canlı bölge, etkin değil',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          harnessApp(Center(child: _button(loading: true, onPressed: () {}))),
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(find.bySemanticsLabel('Kaydet, Yükleniyor'), findsOneWidget);
        expect(
          t.getSemantics(find.byType(CircularProgressIndicator)),
          isSemantics(
            label: 'Kaydet, Yükleniyor',
            isButton: true,
            isEnabled: false,
            isLiveRegion: true,
            hasTapAction: false,
          ),
        );
        handle.dispose();
      },
    );

    testWidgets('başarılı: etiket korunur, düğme etkin değil', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        harnessApp(Center(child: _button(success: true, onPressed: () {}))),
      );
      await t.pumpAndSettle();
      expect(
        t.getSemantics(find.text('Kaydet')),
        isSemantics(
          label: 'Kaydet',
          isButton: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets(
      'dokunma hedefi >= 44 dp (48 dp) her durumda ve her yazı ölçeğinde',
      (t) async {
        for (final scale in kHarnessScales) {
          await pumpAt(
            t,
            Column(
              children: [
                _button(onPressed: () {}),
                _button(onPressed: null),
                _button(loading: true, onPressed: () {}),
                _button(success: true, onPressed: () {}),
                _button(variant: AppButtonVariant.tonal, onPressed: () {}),
                _button(variant: AppButtonVariant.outline, onPressed: () {}),
                Align(
                  child: _button(
                    label: 'Tamam',
                    expand: false,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
            scale: scale,
          );
          final buttons = find.byType(PrimaryActionButton);
          for (var i = 0; i < buttons.evaluate().length; i++) {
            final size = t.getSize(buttons.at(i));
            expect(
              size.height,
              greaterThanOrEqualTo(48),
              reason: 'düğme $i, ölçek $scale',
            );
            expect(
              size.width,
              greaterThanOrEqualTo(44),
              reason: 'düğme $i, ölçek $scale',
            );
          }
        }
      },
    );
  });

  group('PrimaryActionButton: taşma matrisi', () {
    for (final variant in AppButtonVariant.values) {
      testWidgets(
        '${variant.name}: tüm durumlar x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu',
        (t) async {
          await forEachHarnessCell((width, scale, dark) async {
            await pumpAt(
              t,
              Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _button(variant: variant, onPressed: () {}),
                    const SizedBox(height: AppSpace.sm),
                    _button(
                      label: 'Kapıya Misafir Geçiş Kodu Oluştur',
                      icon: Icons.qr_code_2_rounded,
                      tone: AppTone.info,
                      variant: variant,
                      onPressed: () {},
                    ),
                    const SizedBox(height: AppSpace.sm),
                    _button(
                      label: 'Kaydediliyor',
                      variant: variant,
                      loading: true,
                      onPressed: () {},
                    ),
                    const SizedBox(height: AppSpace.sm),
                    _button(
                      label: 'Kaydedildi',
                      variant: variant,
                      success: true,
                      onPressed: () {},
                    ),
                    const SizedBox(height: AppSpace.sm),
                    _button(
                      label: 'Devre dışı',
                      variant: variant,
                      onPressed: null,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _button(
                            label: 'İptal',
                            variant: AppButtonVariant.outline,
                            tone: AppTone.neutral,
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: _button(
                            label: 'Kaydet',
                            variant: variant,
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        _button(
                          label: 'Tamam',
                          expand: false,
                          variant: variant,
                          onPressed: () {},
                        ),
                        _button(
                          label:
                              'Çok uzun bir eylem etiketi: tüm kapılara geçiş izni ver',
                          expand: false,
                          variant: variant,
                          icon: Icons.vpn_key_rounded,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              width: width,
              scale: scale,
              dark: dark,
            );
            expect(
              find.text('Kaydediliyor'),
              findsNothing,
              reason: 'yüklenirken etiket yok ($width x $scale dark=$dark)',
            );
            expect(find.text('Kaydedildi'), findsOneWidget);
          });
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
