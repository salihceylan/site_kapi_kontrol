// FAZ 5 / A1b-(ii): DoorOpenButton widget testleri.
//
// Durum makinesi (ready/opening/offline/disabled), başarı sinyali (successTick: sıra, bekleme,
// yeniden başlatma, dispose), çevrimdışıda `onBlocked ?? onPressed`, haptik zamanlaması (yalnız
// onay anında), PressableScale'in iç onTap'ı ENGELLEMEMESİ, hareket azaltma (tek pump son durum),
// pumpAndSettle'ın bitmesi, Semantics (etiket/etkin/canlı bölge/ekran okuyucu etkinleştirmesi),
// dokunma hedefi (>= 44 dp), daire çapı sınırları ve taşma matrisi
// (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

const String _medium = 'HapticFeedbackType.mediumImpact';
const String _light = 'HapticFeedbackType.lightImpact';
const String _selection = 'HapticFeedbackType.selectionClick';

DoorOpenButton _door({
  DoorOpenState state = DoorOpenState.ready,
  String label = 'KAPIYI AÇ',
  IconData icon = Icons.lock_open_rounded,
  VoidCallback? onPressed,
  VoidCallback? onBlocked,
  AppTone tone = AppTone.primary,
  DoorOpenVariant variant = DoorOpenVariant.circle,
  String openingLabel = 'AÇILIYOR',
  String doneLabel = 'GÖNDERİLDİ',
  int successTick = 0,
}) => DoorOpenButton(
  state: state,
  label: label,
  icon: icon,
  onPressed: onPressed,
  onBlocked: onBlocked,
  tone: tone,
  variant: variant,
  openingLabel: openingLabel,
  doneLabel: doneLabel,
  successTick: successTick,
);

/// Düğmeyi ortalanmış (loose kısıt) kurar: dairenin çapı kendi hesabıyla belirlenir.
Widget _app(
  Widget button, {
  bool dark = false,
  bool reduce = false,
  double scale = 1.0,
}) => harnessApp(
  Center(child: button),
  dark: dark,
  reduce: reduce,
  scale: scale,
);

final Finder _button = find.byType(DoorOpenButton);

/// Düğmenin o an çizilen süslemesi.
ShapeDecoration _deco(WidgetTester t) {
  final f = find.descendant(
    of: find.byType(AnimatedContainer),
    matching: find.byType(DecoratedBox),
  );
  return t.widget<DecoratedBox>(f.first).decoration as ShapeDecoration;
}

List<Color> _gradientColors(WidgetTester t) =>
    (_deco(t).gradient! as LinearGradient).colors;

/// PressableScale'in hedef ölçeği (setState sonrası hemen).
double _targetScale(WidgetTester t) => t
    .widget<AnimatedScale>(
      find.descendant(of: _button, matching: find.byType(AnimatedScale)),
    )
    .scale;

/// Ekranda çizilen (animasyonlu) ölçek.
double _paintedScale(WidgetTester t) => t
    .widget<ScaleTransition>(
      find.descendant(of: _button, matching: find.byType(ScaleTransition)),
    )
    .scale
    .value;

/// Çevrimdışı titremenin o anki yatay ötelemesi.
double _shakeDx(WidgetTester t) => t
    .widget<Transform>(
      find.descendant(of: _button, matching: find.byType(Transform)).first,
    )
    .transform
    .getTranslation()
    .x;

/// Pop (içerik belirişi) opaklığı.
double _popOpacity(WidgetTester t) => t
    .widget<Opacity>(
      find
          .descendant(of: find.byType(Pop), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

/// Erişilebilirlik gezintisinde dokunma eylemi olan düğüm sayısı.
int _tapNodes(WidgetTester t) => t.semantics
    .simulatedAccessibilityTraversal()
    .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
    .length;

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Taşma matrisi hücresi için tüm durumları içeren sütun (başarı sayacı dışarıdan sürülür).
Widget _stateColumn(DoorOpenVariant variant, ValueNotifier<int> tick) {
  final circle = variant == DoorOpenVariant.circle;
  Widget one(DoorOpenState s, String label, String opening, {AppTone? tone}) {
    final b = ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (context, value, _) => _door(
        state: s,
        label: label,
        openingLabel: opening,
        doneLabel: circle ? 'GÖNDERİLDİ' : 'Gönderildi',
        variant: variant,
        tone: tone ?? AppTone.primary,
        icon: s == DoorOpenState.ready
            ? Icons.lock_open_rounded
            : Icons.lock_outline_rounded,
        onPressed: () {},
        successTick: value,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: circle ? Center(child: b) : b,
    );
  }

  return Padding(
    padding: const EdgeInsets.all(AppSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        one(
          DoorOpenState.ready,
          circle ? 'YEREL AĞDAN AÇ' : 'Kapı Aç (Yerel Wi-Fi)',
          circle ? 'AÇILIYOR' : 'Kapı Açılıyor...',
          tone: AppTone.warning,
        ),
        one(
          DoorOpenState.opening,
          circle ? 'KAPIYI AÇ' : 'Kapıyı Aç',
          circle ? 'AÇILIYOR' : 'Gönderiliyor...',
        ),
        one(
          DoorOpenState.offline,
          circle ? 'ÇEVRİMDİŞI' : 'Cihaz Çevrimdışı',
          'AÇILIYOR',
        ),
        one(
          DoorOpenState.disabled,
          circle
              ? 'UZAKTAN KAPALI'
              : 'Bu kapıda uzaktan açma yetkisi kapalıdır',
          'AÇILIYOR',
          tone: AppTone.success,
        ),
      ],
    ),
  );
}

void main() {
  group('durumlar', () {
    testWidgets(
      'ready: etiket + ikon + ton gradyanı + TEK glow gölge; dokununca onPressed + orta şiddette haptik',
      (t) async {
        final haptics = recordHaptics(t);
        var calls = 0;
        await t.pumpWidget(_app(_door(onPressed: () => calls++)));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.byType(Pop),
          findsNothing,
          reason: 'ilk kurulumda beliriş animasyonu yok',
        );
        final deco = _deco(t);
        expect(deco.gradient, AppTone.primary.gradient);
        expect(deco.shape, isA<CircleBorder>());
        expect(deco.shadows, hasLength(1));
        expect(deco.shadows!.single.blurRadius, lessThanOrEqualTo(16));
        expect(deco.shadows!.single.spreadRadius, 0);
        expect(
          deco.shadows!.single.color,
          AppTone.primary.a.withValues(alpha: 0.35),
        );
        expect(
          t.widget<Text>(find.text('KAPIYI AÇ')).style!.color,
          Colors.white,
        );
        expect(
          t.widget<Icon>(find.byIcon(Icons.lock_open_rounded)).color,
          Colors.white,
        );

        await t.tap(find.text('KAPIYI AÇ'));
        await t.pump();
        expect(calls, 1);
        expect(haptics, <String>[_medium]);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'her ton (bulut/yerel ağ/QR/bilgi) kendi gradyanını ve glow rengini kullanır',
      (t) async {
        for (final dark in [false, true]) {
          for (final tone in [
            AppTone.primary,
            AppTone.warning,
            AppTone.success,
            AppTone.info,
          ]) {
            await t.pumpWidget(
              _app(
                _door(tone: tone, onPressed: () {}),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            final deco = _deco(t);
            expect(
              deco.gradient,
              tone.gradient,
              reason: '${tone.name} dark=$dark',
            );
            expect(
              deco.shadows!.single.color,
              tone.a.withValues(alpha: 0.35),
              reason: '${tone.name} dark=$dark',
            );
            expect(
              t.widget<Text>(find.text('KAPIYI AÇ')).style!.color,
              Colors.white,
            );
          }
        }
      },
    );

    testWidgets(
      'opening: aynı CircularProgressIndicator + openingLabel; etiket/ikon yok; dokunma kapalı',
      (t) async {
        final haptics = recordHaptics(t);
        var pressed = 0;
        var blocked = 0;
        await t.pumpWidget(
          _app(
            _door(
              state: DoorOpenState.opening,
              onPressed: () => pressed++,
              onBlocked: () => blocked++,
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('AÇILIYOR'), findsOneWidget);
        expect(find.text('KAPIYI AÇ'), findsNothing);
        expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
        expect(_deco(t).gradient, AppTone.primary.gradient);
        expect(
          t
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .color,
          Colors.white,
        );
        await t.tap(find.text('AÇILIYOR'));
        await t.pump();
        expect(pressed, 0);
        expect(blocked, 0);
        expect(haptics, isEmpty);
        expect(_targetScale(t), 1.0);
      },
    );

    testWidgets(
      'ready -> opening -> ready: içerik değişir, yalnız YENİ içerik belirir',
      (t) async {
        Widget build(DoorOpenState s) =>
            _app(_door(state: s, onPressed: () {}));
        await t.pumpWidget(build(DoorOpenState.ready));
        await t.pumpWidget(build(DoorOpenState.opening));
        expect(
          find.text('KAPIYI AÇ'),
          findsNothing,
          reason: 'eski içerik hemen kalktı',
        );
        expect(find.text('AÇILIYOR'), findsOneWidget);
        expect(find.byType(Pop), findsOneWidget);
        expect(_popOpacity(t), 0, reason: 'yeni içerik saydam başlar');
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 60));
          expect(
            find.byType(Text),
            findsOneWidget,
            reason: 'her karede tek metin',
          );
        }
        expect(_popOpacity(t), 1);

        await t.pumpWidget(build(DoorOpenState.ready));
        expect(find.text('AÇILIYOR'), findsNothing);
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'offline: nötr görünüm; dokununca selectionClick + yatay titreme + onBlocked (onPressed DEĞİL)',
      (t) async {
        final haptics = recordHaptics(t);
        var pressed = 0;
        var blocked = 0;
        await t.pumpWidget(
          _app(
            _door(
              state: DoorOpenState.offline,
              label: 'ÇEVRİMDİŞI',
              icon: Icons.lock_outline_rounded,
              onPressed: () => pressed++,
              onBlocked: () => blocked++,
            ),
          ),
        );
        final p = AppPalette.light;
        final deco = _deco(t);
        expect(deco.gradient, DoorOpenButton.neutralGradient(p));
        expect(deco.shadows, p.shadow(1));
        expect(
          t.widget<Text>(find.text('ÇEVRİMDİŞI')).style!.color,
          p.textSecondary,
        );
        expect(_shakeDx(t), 0);

        await t.tap(find.text('ÇEVRİMDİŞI'));
        await t.pump();
        expect(blocked, 1);
        expect(pressed, 0, reason: 'onBlocked varken onPressed çağrılmaz');
        expect(haptics, <String>[_selection]);
        await t.pump(const Duration(milliseconds: 60));
        expect(
          _shakeDx(t),
          closeTo(-4.5, 1e-9),
          reason: '60 ms: sin(1,5 pi) x 6 x 0,75',
        );
        await t.pump(const Duration(milliseconds: 80));
        expect(_shakeDx(t), isNot(0));
        await t.pumpAndSettle();
        expect(_shakeDx(t), 0, reason: 'titreme sönümlenip biter');
        expect(t.binding.transientCallbackCount, 0);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'offline ve onBlocked yoksa onPressed çağrılır (bireysel görünüm yeniden-kontrol akışı)',
      (t) async {
        var pressed = 0;
        await t.pumpWidget(
          _app(_door(state: DoorOpenState.offline, onPressed: () => pressed++)),
        );
        await t.tap(find.text('KAPIYI AÇ'));
        await t.pump();
        expect(pressed, 1);
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      'offline ve hiçbir geri çağrı yoksa da çökmez (titreme + haptik yine olur)',
      (t) async {
        final haptics = recordHaptics(t);
        await t.pumpWidget(_app(_door(state: DoorOpenState.offline)));
        await t.tap(find.text('KAPIYI AÇ'));
        await t.pump();
        expect(haptics, <String>[_selection]);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'disabled: nötr görünüm; dokunma hiçbir şey yapmaz (geri çağrı, haptik, ölçek yok)',
      (t) async {
        final haptics = recordHaptics(t);
        var pressed = 0;
        var blocked = 0;
        await t.pumpWidget(
          _app(
            _door(
              state: DoorOpenState.disabled,
              label: 'KAPALI',
              onPressed: () => pressed++,
              onBlocked: () => blocked++,
            ),
          ),
        );
        final p = AppPalette.light;
        expect(_deco(t).gradient, DoorOpenButton.neutralGradient(p));
        expect(
          t.widget<Text>(find.text('KAPALI')).style!.color,
          p.textSecondary,
        );
        final g = await t.startGesture(t.getCenter(find.text('KAPALI')));
        await t.pump(const Duration(milliseconds: 200));
        expect(_targetScale(t), 1.0);
        await g.up();
        await t.pumpAndSettle();
        expect(pressed, 0);
        expect(blocked, 0);
        expect(haptics, isEmpty);
        expect(_shakeDx(t), 0);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('onPressed null iken ready dokunuşu çökmez', (t) async {
      await t.pumpWidget(_app(_door()));
      await t.tap(find.text('KAPIYI AÇ'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'nötr görünüm tondan bağımsızdır (offline + success/warning ton)',
      (t) async {
        final p = AppPalette.light;
        for (final tone in [AppTone.success, AppTone.warning]) {
          await t.pumpWidget(
            _app(_door(state: DoorOpenState.offline, tone: tone)),
          );
          await t.pumpAndSettle();
          expect(
            _deco(t).gradient,
            DoorOpenButton.neutralGradient(p),
            reason: tone.name,
          );
        }
      },
    );

    testWidgets(
      'etiket/ton değişimi (bulut -> yerel ağ): gradyan morph olur, içerik belirmesi yok',
      (t) async {
        await t.pumpWidget(_app(_door(onPressed: () {})));
        await t.pumpWidget(
          _app(
            _door(
              label: 'YEREL AĞDAN AÇ',
              icon: Icons.wifi_rounded,
              tone: AppTone.warning,
              onPressed: () {},
            ),
          ),
        );
        expect(find.text('YEREL AĞDAN AÇ'), findsOneWidget);
        expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
        expect(
          find.byType(Pop),
          findsNothing,
          reason: 'durum değişmedi: beliriş yok',
        );
        await t.pump(const Duration(milliseconds: 100));
        final mid = _gradientColors(t);
        expect(mid, isNot(AppTone.primary.gradient.colors));
        expect(mid, isNot(AppTone.warning.gradient.colors));
        await t.pumpAndSettle();
        expect(_deco(t).gradient, AppTone.warning.gradient);
      },
    );

    testWidgets('aynı özelliklerle yeniden kurma animasyon/Pop tetiklemez', (
      t,
    ) async {
      await t.pumpWidget(_app(_door(onPressed: () {})));
      for (var i = 0; i < 5; i++) {
        await t.pumpWidget(_app(_door(onPressed: () {})));
      }
      expect(find.byType(Pop), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'düz MaterialApp (AppTheme/AppPalette uzantısı YOK) içinde de çalışır: parlaklığa göre palet',
      (t) async {
        for (final dark in [false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          for (final variant in DoorOpenVariant.values) {
            var pressed = 0;
            var blocked = 0;
            await t.pumpWidget(
              MaterialApp(
                theme: dark ? ThemeData.dark() : ThemeData.light(),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        children: [
                          _door(variant: variant, onPressed: () => pressed++),
                          _door(
                            variant: variant,
                            state: DoorOpenState.offline,
                            label: 'ÇEVRİMDİŞI',
                            onBlocked: () => blocked++,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            await t.tap(find.text('KAPIYI AÇ'));
            await t.tap(find.text('ÇEVRİMDİŞI'));
            await t.pumpAndSettle();
            expect(pressed, 1, reason: '${variant.name} dark=$dark');
            expect(blocked, 1, reason: '${variant.name} dark=$dark');
            expect(t.takeException(), isNull);
            final neutral = find.byType(AnimatedContainer).at(1);
            final deco =
                t
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: neutral,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as ShapeDecoration;
            expect(
              deco.gradient,
              DoorOpenButton.neutralGradient(p),
              reason: '${variant.name} dark=$dark: palet parlaklıktan türer',
            );
          }
        }
      },
    );

    testWidgets(
      'çubuk: etiket + ikon + gradyan; opening spinner + openingLabel',
      (t) async {
        await t.pumpWidget(
          _app(
            SizedBox(
              width: 320,
              child: _door(
                variant: DoorOpenVariant.bar,
                label: 'Kapı Aç',
                openingLabel: 'Gönderiliyor...',
                doneLabel: 'Gönderildi',
                onPressed: () {},
              ),
            ),
          ),
        );
        expect(find.text('Kapı Aç'), findsOneWidget);
        expect(_deco(t).shape, isA<RoundedRectangleBorder>());
        expect(_deco(t).gradient, AppTone.primary.gradient);
        expect(t.widget<Text>(find.text('Kapı Aç')).maxLines, 2);
        await t.pumpWidget(
          _app(
            SizedBox(
              width: 320,
              child: _door(
                state: DoorOpenState.opening,
                variant: DoorOpenVariant.bar,
                label: 'Kapı Aç',
                openingLabel: 'Gönderiliyor...',
                doneLabel: 'Gönderildi',
                onPressed: () {},
              ),
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Gönderiliyor...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Kapı Aç'), findsNothing);
      },
    );

    testWidgets('nötr etiket/ikon iki temada ve gradyanın iki ucunda >= 4,5:1', (
      t,
    ) async {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        final gradient = DoorOpenButton.neutralGradient(p);
        // Gradyan uçları OPAKTIR (saydam uç, ortada parlak bant üretirdi) ve tonla aynı çaprazdadır.
        expect(gradient.begin, AppTone.primary.gradient.begin);
        expect(gradient.end, AppTone.primary.gradient.end);
        expect(gradient.colors, hasLength(2));
        for (final end in gradient.colors) {
          expect(end.a, 1.0, reason: 'dark=${p.isDark}: uç opak olmalı');
          final ratio = _contrast(p.textSecondary, end);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'dark=${p.isDark} oran=${ratio.toStringAsFixed(2)}',
          );
        }
        // Koyu yüzeyin 2.-3. yükselti seviyelerinde de ışıma/boşluk oluşmaz: uç opak olduğundan
        // kontrast zeminden bağımsızdır (yukarıdaki ölçüm yeterlidir).
      }
    });
  });

  group('başarı sinyali (successTick)', () {
    Widget host({
      DoorOpenState state = DoorOpenState.ready,
      int tick = 0,
      bool reduce = false,
      DoorOpenVariant variant = DoorOpenVariant.circle,
      VoidCallback? onPressed,
    }) => _app(
      SizedBox(
        width: variant == DoorOpenVariant.bar ? 320 : null,
        child: _door(
          state: state,
          successTick: tick,
          variant: variant,
          onPressed: onPressed,
        ),
      ),
      reduce: reduce,
    );

    testWidgets(
      'tik artınca: onay işareti + GÖNDERİLDİ + success morph + hafif haptik; 1,4 sn sonra geri',
      (t) async {
        final haptics = recordHaptics(t);
        await t.pumpWidget(host());
        await t.pumpWidget(host(tick: 1));
        await t.pump();
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        expect(find.text('KAPIYI AÇ'), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
        expect(haptics, <String>[_light]);

        await t.pump(const Duration(milliseconds: 100));
        final mid = _gradientColors(t);
        expect(
          mid,
          isNot(AppTone.primary.gradient.colors),
          reason: 'morph sürüyor',
        );
        expect(
          mid,
          isNot(AppTone.success.gradient.colors),
          reason: 'morph henüz bitmedi',
        );
        await t.pump(const Duration(milliseconds: 150));
        expect(_deco(t).gradient, AppTone.success.gradient);
        expect(
          t.widget<Text>(find.text('GÖNDERİLDİ')).style!.color,
          Colors.white,
        );

        // Zamanlayıcı pumpWidget anında (t0) başladı: 1399 ms hâlâ başarı.
        await t.pump(const Duration(milliseconds: 1149)); // toplam 1399 ms
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 1)); // 1400 ms
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
        await t.pumpAndSettle();
        expect(_deco(t).gradient, AppTone.primary.gradient);
        expect(haptics, <String>[_light], reason: 'geri dönüşte haptik yok');
        expect(t.binding.transientCallbackCount, 0);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'ilk kurulumdaki tik değeri sinyal sayılmaz; değişmeyen tik de değil',
      (t) async {
        final haptics = recordHaptics(t);
        await t.pumpWidget(host(tick: 5));
        await t.pump(const Duration(seconds: 2));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        await t.pumpWidget(host(tick: 5));
        await t.pump(const Duration(seconds: 2));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(haptics, isEmpty);
      },
    );

    testWidgets('sayaç düşse de (yalnız değişim önemlidir) sinyal sayılır', (
      t,
    ) async {
      await t.pumpWidget(host(tick: 3));
      await t.pumpWidget(host(tick: 2));
      await t.pump();
      expect(find.text('GÖNDERİLDİ'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
    });

    testWidgets(
      'komut sürerken (opening) gelen sinyal komut bitince gösterilir',
      (t) async {
        final haptics = recordHaptics(t);
        await t.pumpWidget(host());
        await t.pumpWidget(host(state: DoorOpenState.opening));
        await t.pump(const Duration(milliseconds: 300));
        await t.pumpWidget(host(state: DoorOpenState.opening, tick: 1));
        await t.pump(const Duration(milliseconds: 300));
        expect(
          find.text('AÇILIYOR'),
          findsOneWidget,
          reason: 'komut hâlâ sürüyor',
        );
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        expect(haptics, isEmpty, reason: 'başarı haptiği gösterimle birlikte');

        await t.pumpWidget(host(tick: 1)); // komut bitti
        await t.pump();
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(haptics, <String>[_light]);
        await t.pump(const Duration(milliseconds: 1400));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      'komut bitişi ve tik AYNI güncellemede (opening -> ready + tik)',
      (t) async {
        final haptics = recordHaptics(t);
        await t.pumpWidget(host());
        await t.pumpWidget(host(state: DoorOpenState.opening));
        await t.pump(const Duration(milliseconds: 300));
        await t.pumpWidget(host(tick: 1));
        await t.pump();
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(haptics, <String>[_light]);
        await t.pump(const Duration(milliseconds: 1400));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      'başarı sürerken yeni komut başlarsa gösterim biter ve zamanlayıcı iptal olur',
      (t) async {
        await t.pumpWidget(host());
        await t.pumpWidget(host(tick: 1));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        await t.pumpWidget(host(state: DoorOpenState.opening, tick: 1));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('AÇILIYOR'), findsOneWidget);
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Komut, ESKİ zamanlayıcı dolmadan (başarıdan 600 ms sonra; 800 ms kaldı) aynı tik ile
        // biterse eski başarı yeniden BELİRMEZ (yeni sinyal yok).
        await t.pumpWidget(host(tick: 1));
        await t.pump();
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        // Eski zamanlayıcı iptal edilmiştir: dolacağı anda da hiçbir şey değişmez.
        await t.pump(const Duration(milliseconds: 1000));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(find.text('GÖNDERİLDİ'), findsNothing);
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      'komut sürerken başarı zamanlayıcısı dolsa da spinner kesilmez',
      (t) async {
        await t.pumpWidget(host());
        await t.pumpWidget(host(tick: 1));
        await t.pump(const Duration(milliseconds: 300));
        await t.pumpWidget(host(state: DoorOpenState.opening, tick: 1));
        await t.pump(
          const Duration(seconds: 2),
        ); // eski 1,4 sn'lik pencere aşıldı
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('AÇILIYOR'), findsOneWidget);
        await t.pumpWidget(host(tick: 1));
        await t.pumpAndSettle();
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
      },
    );

    testWidgets('ardışık sinyaller 1,4 sn penceresini yeniden başlatır', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      await t.pumpWidget(host());
      await t.pumpWidget(host(tick: 1));
      await t.pump(const Duration(milliseconds: 1000));
      await t.pumpWidget(host(tick: 2)); // yeni pencere: +1,4 sn
      await t.pump();
      await t.pump(const Duration(milliseconds: 1399));
      expect(find.text('GÖNDERİLDİ'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1));
      expect(find.text('KAPIYI AÇ'), findsOneWidget);
      expect(haptics, <String>[_light, _light]);
      await t.pumpAndSettle();
    });

    testWidgets(
      'başarı sürerken ready dokunuşu hâlâ onPressed çağırır (komut engellenmez)',
      (t) async {
        var calls = 0;
        await t.pumpWidget(host(onPressed: () => calls++));
        await t.pumpWidget(host(tick: 1, onPressed: () => calls++));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text('GÖNDERİLDİ'));
        await t.pump();
        expect(calls, 1);
        await t.pump(const Duration(milliseconds: 1500));
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      'başarı gösterimi çevrimdışı/devre dışı durumda da (komut gönderilmiştir) görünür',
      (t) async {
        for (final s in [DoorOpenState.offline, DoorOpenState.disabled]) {
          await t.pumpWidget(host(state: s));
          await t.pumpWidget(host(state: s, tick: 1));
          await t.pump(const Duration(milliseconds: 300));
          expect(find.text('GÖNDERİLDİ'), findsOneWidget, reason: s.name);
          expect(_deco(t).gradient, AppTone.success.gradient, reason: s.name);
          await t.pump(const Duration(milliseconds: 1400));
          expect(find.text('KAPIYI AÇ'), findsOneWidget, reason: s.name);
          await t.pumpAndSettle();
          final p = AppPalette.light;
          expect(
            _deco(t).gradient,
            DoorOpenButton.neutralGradient(p),
            reason: s.name,
          );
          // Sonraki durum için tik sıfırdan başlar.
          await t.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets('çubukta başarı etiketi çağıranın doneLabel değeridir', (
      t,
    ) async {
      Widget bar(int tick) => _app(
        SizedBox(
          width: 320,
          child: _door(
            variant: DoorOpenVariant.bar,
            label: 'Kapı Aç',
            doneLabel: 'Gönderildi',
            successTick: tick,
          ),
        ),
      );
      await t.pumpWidget(bar(0));
      await t.pumpWidget(bar(1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Gönderildi'), findsOneWidget);
      expect(find.text('GÖNDERİLDİ'), findsNothing);
      await t.pump(const Duration(milliseconds: 1400));
      await t.pumpAndSettle();
      expect(find.text('Kapı Aç'), findsOneWidget);
    });

    testWidgets(
      'dispose: bekleyen başarı zamanlayıcısı iptal edilir (ağaç sökülünce Timer kalmaz)',
      (t) async {
        await t.pumpWidget(host());
        await t.pumpWidget(host(tick: 1));
        await t.pump(const Duration(milliseconds: 200));
        // 1,4 sn'lik zamanlayıcının 1,2 sn'si DAHA var: ağaç şimdi sökülür ve test BURADA biter
        // (sonrasında pump YOK). dispose zamanlayıcıyı iptal etmezse flutter_test test sonunda
        // "A Timer is still pending even after the widget tree was disposed" ile bu testi düşürür.
        await t.pumpWidget(const SizedBox.shrink());
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('dispose: titreme sürerken ağaç sökülürse hata yok', (t) async {
      await t.pumpWidget(
        _app(_door(state: DoorOpenState.offline, onBlocked: () {})),
      );
      await t.tap(find.text('KAPIYI AÇ'));
      await t.pump(const Duration(milliseconds: 60));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
    });

    testWidgets('çubuk varyantında da tik akışı çalışır', (t) async {
      await t.pumpWidget(host(variant: DoorOpenVariant.bar));
      await t.pumpWidget(host(variant: DoorOpenVariant.bar, tick: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('GÖNDERİLDİ'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1400));
      await t.pumpAndSettle();
      expect(find.text('KAPIYI AÇ'), findsOneWidget);
    });
  });

  group('haptik ve etkileşim', () {
    testWidgets('haptik YALNIZ onay anında (parmak kalkınca): basışta yok', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      var calls = 0;
      await t.pumpWidget(_app(_door(onPressed: () => calls++)));
      final g = await t.startGesture(t.getCenter(find.text('KAPIYI AÇ')));
      await t.pump(const Duration(milliseconds: 250));
      expect(haptics, isEmpty, reason: 'basış anında titreşim yok');
      expect(calls, 0);
      await g.up();
      await t.pump();
      expect(haptics, <String>[_medium]);
      expect(calls, 1);
    });

    testWidgets('offline: basışta haptik yok, onayda selectionClick', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      await t.pumpWidget(
        _app(_door(state: DoorOpenState.offline, onBlocked: () {})),
      );
      final g = await t.startGesture(t.getCenter(find.text('KAPIYI AÇ')));
      await t.pump(const Duration(milliseconds: 250));
      expect(haptics, isEmpty);
      await g.up();
      await t.pump();
      expect(haptics, <String>[_selection]);
      await t.pumpAndSettle();
    });

    testWidgets(
      'kaydırma (tap iptali) haptik vermez, onPressed çağırmaz, ölçek takılı kalmaz',
      (t) async {
        final haptics = recordHaptics(t);
        var calls = 0;
        await t.pumpWidget(
          harnessApp(
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Center(child: _door(onPressed: () => calls++)),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        );
        final g = await t.startGesture(t.getCenter(find.text('KAPIYI AÇ')));
        await t.pump(const Duration(milliseconds: 150));
        expect(_targetScale(t), 0.96);
        await g.moveBy(const Offset(0, -90));
        await t.pump();
        expect(_targetScale(t), 1.0, reason: 'onTapCancel ölçeği geri aldı');
        await g.up();
        await t.pumpAndSettle();
        expect(haptics, isEmpty);
        expect(calls, 0);
      },
    );

    testWidgets('klavye: odak + Enter onPressed çağırır (orta haptik)', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      var calls = 0;
      await t.pumpWidget(_app(_door(onPressed: () => calls++)));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(calls, 1);
      expect(haptics, <String>[_medium]);
      await t.pumpAndSettle();
    });

    testWidgets('opening ve disabled odak almaz (dokunma eylemi yok)', (
      t,
    ) async {
      for (final s in [DoorOpenState.opening, DoorOpenState.disabled]) {
        await t.pumpWidget(_app(_door(state: s, onPressed: () {})));
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<DoorOpenButton>(),
          isNull,
          reason: s.name,
        );
        await t.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  group('PressableScale iç onTap\'ı ENGELLEMEZ', () {
    testWidgets(
      'ready: basılıyken 0,96, bırakınca onPressed çağrılır ve ölçek 1,0 olur',
      (t) async {
        var calls = 0;
        await t.pumpWidget(_app(_door(onPressed: () => calls++)));
        expect(_targetScale(t), 1.0);
        final g = await t.startGesture(t.getCenter(find.text('KAPIYI AÇ')));
        await t.pump(const Duration(milliseconds: 150)); // kPressTimeout geçti
        await t.pump(
          const Duration(milliseconds: 150),
        ); // 120 ms'lik ölçek animasyonu biter
        expect(_targetScale(t), 0.96);
        expect(_paintedScale(t), closeTo(0.96, 1e-9));
        expect(calls, 0, reason: 'tap parmak kalkınca olur');
        await g.up();
        await t.pump();
        expect(calls, 1, reason: 'iç InkWell onTap tetiklendi');
        await t.pump(const Duration(milliseconds: 200));
        expect(_targetScale(t), 1.0);
        expect(_paintedScale(t), closeTo(1.0, 1e-9));
      },
    );

    testWidgets('kısa dokunuşta onPressed tam bir kez çalışır', (t) async {
      var calls = 0;
      await t.pumpWidget(_app(_door(onPressed: () => calls++)));
      await t.tap(find.text('KAPIYI AÇ'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(_targetScale(t), 1.0);
    });

    testWidgets(
      'offline/opening/disabled: basılıyken ölçek DEĞİŞMEZ, onBlocked yine çalışır',
      (t) async {
        var blocked = 0;
        await t.pumpWidget(
          _app(_door(state: DoorOpenState.offline, onBlocked: () => blocked++)),
        );
        final g = await t.startGesture(t.getCenter(find.text('KAPIYI AÇ')));
        await t.pump(const Duration(milliseconds: 250));
        expect(_targetScale(t), 1.0);
        await g.up();
        await t.pump();
        expect(blocked, 1);
        await t.pumpAndSettle();
        for (final s in [DoorOpenState.opening, DoorOpenState.disabled]) {
          await t.pumpWidget(_app(_door(state: s, onPressed: () {})));
          final g2 = await t.startGesture(t.getCenter(_button));
          await t.pump(const Duration(milliseconds: 250));
          expect(_targetScale(t), 1.0, reason: s.name);
          await g2.up();
          await t.pump(const Duration(milliseconds: 100));
        }
      },
    );
  });

  group('hareket azaltma', () {
    testWidgets(
      'tik: tek pump ile success görünümü (morph anında); haptik kalır; ticker yok',
      (t) async {
        final haptics = recordHaptics(t);
        Widget build(int tick) =>
            _app(_door(successTick: tick, onPressed: () {}), reduce: true);
        await t.pumpWidget(build(0));
        await t.pumpWidget(build(1));
        await t.pump();
        expect(_deco(t).gradient, AppTone.success.gradient);
        expect(find.text('GÖNDERİLDİ'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(_popOpacity(t), 1, reason: 'beliriş anında tamam');
        expect(haptics, <String>[_light]);
        expect(
          t.binding.transientCallbackCount,
          0,
          reason: 'kararlı durumda ticker yok',
        );
        await t.pump(const Duration(milliseconds: 1400));
        expect(find.text('KAPIYI AÇ'), findsOneWidget);
        expect(_deco(t).gradient, AppTone.primary.gradient);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('offline: titreme YOK, haptik + onBlocked kalır', (t) async {
      final haptics = recordHaptics(t);
      var blocked = 0;
      await t.pumpWidget(
        _app(
          _door(state: DoorOpenState.offline, onBlocked: () => blocked++),
          reduce: true,
        ),
      );
      await t.tap(find.text('KAPIYI AÇ'));
      await t.pump();
      expect(blocked, 1);
      expect(haptics, <String>[_selection]);
      // Hareket normalken 60 ms'de titreme -4,5 dp'dir (yukarıdaki test); azaltmada hiç ötelenmez.
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 60));
        expect(_shakeDx(t), 0, reason: 'adım $i');
      }
      await t.pumpAndSettle(); // (yalnız mürekkep dalgası bitmeyi bekler)
      expect(_shakeDx(t), 0);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'durum geçişi (ready -> opening): içerik tek pump ile tam görünür',
      (t) async {
        Widget build(DoorOpenState s) =>
            _app(_door(state: s, onPressed: () {}), reduce: true);
        await t.pumpWidget(build(DoorOpenState.ready));
        await t.pumpWidget(build(DoorOpenState.opening));
        expect(find.text('AÇILIYOR'), findsOneWidget);
        expect(_popOpacity(t), 1);
        expect(_deco(t).gradient, AppTone.primary.gradient);
      },
    );

    testWidgets('ölçek ve morph süreleri sıfır', (t) async {
      await t.pumpWidget(_app(_door(onPressed: () {}), reduce: true));
      expect(
        t
            .widget<AnimatedScale>(
              find.descendant(
                of: _button,
                matching: find.byType(AnimatedScale),
              ),
            )
            .duration,
        Duration.zero,
      );
      expect(
        t.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
        Duration.zero,
      );
      final g = await t.startGesture(t.getCenter(find.text('KAPIYI AÇ')));
      await t.pump(const Duration(milliseconds: 110));
      expect(_paintedScale(t), closeTo(0.96, 1e-9));
      await g.up();
      await t.pump();
      expect(_paintedScale(t), closeTo(1.0, 1e-9));
    });

    testWidgets('hareket normalken süreler 200/120 ms', (t) async {
      await t.pumpWidget(_app(_door(onPressed: () {})));
      expect(
        t.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
        AppMotion.base,
      );
      expect(
        t
            .widget<AnimatedScale>(
              find.descendant(
                of: _button,
                matching: find.byType(AnimatedScale),
              ),
            )
            .duration,
        AppMotion.fast,
      );
    });
  });

  group('pumpAndSettle biter (kararlı durumda sonsuz animasyon yok)', () {
    for (final variant in DoorOpenVariant.values) {
      testWidgets(
        '${variant.name}: ready/offline/disabled/başarı sonrası, açık+koyu',
        (t) async {
          for (final dark in [false, true]) {
            for (final s in [
              DoorOpenState.ready,
              DoorOpenState.offline,
              DoorOpenState.disabled,
            ]) {
              await t.pumpWidget(
                _app(
                  SizedBox(
                    width: 320,
                    child: _door(
                      state: s,
                      variant: variant,
                      onPressed: () {},
                      onBlocked: () {},
                    ),
                  ),
                  dark: dark,
                ),
              );
              await t.pumpAndSettle();
              expect(
                t.binding.transientCallbackCount,
                0,
                reason: '${variant.name} ${s.name} dark=$dark',
              );
            }
            // Başarı yolu sonunda da ticker kalmaz.
            Widget bar(int tick) => _app(
              SizedBox(
                width: 320,
                child: _door(variant: variant, successTick: tick),
              ),
              dark: dark,
            );
            await t.pumpWidget(bar(0));
            await t.pumpWidget(bar(1));
            await t.pump(const Duration(milliseconds: 1400));
            await t.pumpAndSettle();
            expect(
              t.binding.transientCallbackCount,
              0,
              reason: 'başarı sonrası',
            );
          }
        },
      );
    }

    testWidgets(
      'opening: spinner işlevsel gösterge olarak döner; çıkınca ticker kalmaz',
      (t) async {
        Widget build(DoorOpenState s) =>
            _app(_door(state: s, onPressed: () {}));
        await t.pumpWidget(build(DoorOpenState.opening));
        await t.pump(const Duration(seconds: 2));
        expect(t.binding.transientCallbackCount, greaterThan(0));
        await t.pumpWidget(build(DoorOpenState.ready));
        await t.pumpAndSettle();
        expect(t.binding.transientCallbackCount, 0);
      },
    );
  });

  group('Semantics', () {
    testWidgets(
      'ready: düğme, etkin, dokunulabilir, etiket görünen metin; TEK dokunulabilir düğüm',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(_app(_door(onPressed: () {})));
        expect(
          t.getSemantics(_button),
          isSemantics(
            label: 'KAPIYI AÇ',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            isLiveRegion: false,
          ),
        );
        expect(_tapNodes(t), 1, reason: 'çift düğüm yok (InkWell dışlandı)');
        handle.dispose();
      },
    );

    testWidgets(
      'ekran okuyucu etkinleştirmesi (semantics tap) ready iken onPressed çağırır',
      (t) async {
        final handle = t.ensureSemantics();
        final haptics = recordHaptics(t);
        var calls = 0;
        await t.pumpWidget(_app(_door(onPressed: () => calls++)));
        t.semantics.tap(find.semantics.byLabel('KAPIYI AÇ'));
        await t.pump();
        expect(calls, 1);
        expect(haptics, <String>[_medium]);
        handle.dispose();
      },
    );

    testWidgets(
      'offline: etkin + dokunma eylemi var (uyarı/yeniden-kontrol erişilebilir); etkinleştirme onBlocked çağırır',
      (t) async {
        final handle = t.ensureSemantics();
        var blocked = 0;
        await t.pumpWidget(
          _app(
            _door(
              state: DoorOpenState.offline,
              label: 'ÇEVRİMDİŞI',
              onBlocked: () => blocked++,
            ),
          ),
        );
        expect(
          t.getSemantics(_button),
          isSemantics(
            label: 'ÇEVRİMDİŞI',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
          ),
        );
        expect(_tapNodes(t), 1);
        t.semantics.tap(find.semantics.byLabel('ÇEVRİMDİŞI'));
        await t.pump();
        expect(blocked, 1);
        await t.pumpAndSettle();
        handle.dispose();
      },
    );

    testWidgets('disabled: düğme ama etkin değil, dokunma eylemi YOK', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        _app(
          _door(
            state: DoorOpenState.disabled,
            label: 'KAPALI',
            onPressed: () {},
          ),
        ),
      );
      expect(
        t.getSemantics(_button),
        isSemantics(
          label: 'KAPALI',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
          hasTapAction: false,
          isLiveRegion: false,
        ),
      );
      expect(_tapNodes(t), 0);
      handle.dispose();
    });

    testWidgets(
      'opening: etiket openingLabel, canlı bölge (duyurulur), etkin değil, dokunma yok',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          _app(_door(state: DoorOpenState.opening, onPressed: () {})),
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(
          t.getSemantics(_button),
          isSemantics(
            label: 'AÇILIYOR',
            isButton: true,
            isEnabled: false,
            hasEnabledState: true,
            hasTapAction: false,
            isLiveRegion: true,
          ),
        );
        expect(_tapNodes(t), 0);
        handle.dispose();
      },
    );

    testWidgets(
      'başarı: etiket doneLabel + canlı bölge; sonra eski etiket ve canlı bölge kapalı',
      (t) async {
        final handle = t.ensureSemantics();
        Widget build(int tick) =>
            _app(_door(successTick: tick, onPressed: () {}));
        await t.pumpWidget(build(0));
        await t.pumpWidget(build(1));
        await t.pump(const Duration(milliseconds: 300));
        expect(
          t.getSemantics(_button),
          isSemantics(label: 'GÖNDERİLDİ', isButton: true, isLiveRegion: true),
        );
        await t.pump(const Duration(milliseconds: 1400));
        await t.pumpAndSettle();
        expect(
          t.getSemantics(_button),
          isSemantics(label: 'KAPIYI AÇ', isButton: true, isLiveRegion: false),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'dokunma hedefi: daire >= 132 dp (kare), çubuk >= 52 dp; her durumda ve ölçekte >= 44 dp',
      (t) async {
        for (final scale in kHarnessScales) {
          for (final s in DoorOpenState.values) {
            await pumpAt(
              t,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: _door(state: s, onPressed: () {}),
                  ),
                  _door(
                    state: s,
                    variant: DoorOpenVariant.bar,
                    onPressed: () {},
                  ),
                ],
              ),
              scale: scale,
            );
            final faces = find.byType(AnimatedContainer);
            final circle = t.getSize(faces.at(0));
            expect(
              circle.width,
              circle.height,
              reason: 'daire kare: ${s.name}',
            );
            expect(
              circle.width,
              greaterThanOrEqualTo(132),
              reason: '${s.name} x$scale',
            );
            expect(circle.width, lessThanOrEqualTo(184));
            final bar = t.getSize(faces.at(1));
            expect(
              bar.height,
              greaterThanOrEqualTo(52),
              reason: '${s.name} x$scale',
            );
            expect(bar.width, 320);
            // Etkileşimli alan ölçüsü (InkWell) de >= 44 dp.
            final inks = find.byType(InkWell);
            for (var i = 0; i < inks.evaluate().length; i++) {
              final size = t.getSize(inks.at(i));
              expect(size.height, greaterThanOrEqualTo(44));
              expect(size.width, greaterThanOrEqualTo(44));
            }
          }
        }
      },
    );
  });

  group('boyut', () {
    Future<double> diameter(WidgetTester t, double width) async {
      await t.pumpWidget(
        harnessApp(
          Center(
            child: SizedBox(
              width: width,
              child: _door(onPressed: () {}),
            ),
          ),
        ),
      );
      final size = t.getSize(find.byType(AnimatedContainer));
      expect(size.width, size.height, reason: 'daire kare ($width)');
      return size.width;
    }

    testWidgets(
      'daire çapı = genişliğin yarısı, 132-184 dp arasına sıkıştırılır',
      (t) async {
        expect(await diameter(t, 200), 132, reason: 'alt sınır');
        expect(await diameter(t, 264), 132);
        expect(await diameter(t, 300), 150);
        expect(await diameter(t, 360), 180);
        expect(await diameter(t, 368), 184);
        expect(await diameter(t, 600), 184, reason: 'üst sınır');
      },
    );

    testWidgets('sınırsız genişlikte (yatay kaydırma) 184 dp ve hata yok', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _door(onPressed: () {}),
          ),
        ),
      );
      expect(t.getSize(find.byType(AnimatedContainer)), const Size(184, 184));
      expect(t.takeException(), isNull);
    });

    testWidgets('dar yükseklikte daire küçülür ama taşmaz', (t) async {
      await t.pumpWidget(
        harnessApp(
          Center(
            child: SizedBox(
              width: 400,
              height: 100,
              child: Center(child: _door(onPressed: () {})),
            ),
          ),
        ),
      );
      expect(t.getSize(find.byType(AnimatedContainer)), const Size(100, 100));
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'sıkı genişlikte (Column stretch) daire kendi çapında kalır ve ortalanır',
      (t) async {
        await pumpAt(
          t,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_door(onPressed: () {})],
          ),
          width: 360,
          scale: 1.0,
        );
        final size = t.getSize(find.byType(AnimatedContainer));
        expect(size, const Size(180, 180));
        expect(t.getCenter(find.byType(AnimatedContainer)).dx, 180);
      },
    );

    testWidgets(
      'çubuk tam genişliği kaplar; yazı büyüyünce 52 dp üstüne uzar ve etiket 2 satıra sarar',
      (t) async {
        await pumpAt(
          t,
          _door(
            variant: DoorOpenVariant.bar,
            label: 'Kapı Aç (Yerel Wi-Fi)',
            onPressed: () {},
          ),
          width: 320,
          scale: 1.0,
        );
        final normal = t.getSize(find.byType(AnimatedContainer));
        expect(normal.width, 320);
        expect(normal.height, greaterThanOrEqualTo(52));
        await pumpAt(
          t,
          _door(
            variant: DoorOpenVariant.bar,
            label: 'Kapı Aç (Yerel Wi-Fi)',
            onPressed: () {},
          ),
          width: 320,
          scale: 2.0,
        );
        final big = t.getSize(find.byType(AnimatedContainer));
        expect(big.width, 320);
        expect(
          big.height,
          greaterThan(normal.height),
          reason: 'etiket sarıp uzadı',
        );
        expect(t.widget<Text>(find.text('Kapı Aç (Yerel Wi-Fi)')).maxLines, 2);
      },
    );

    testWidgets(
      'daire içeriği tek satır; yazı 2,0x olunca küçülür (FittedBox), taşmaz',
      (t) async {
        await pumpAt(
          t,
          Center(
            child: _door(
              label: 'YEREL AĞDAN AÇ',
              icon: Icons.wifi_rounded,
              tone: AppTone.warning,
              onPressed: () {},
            ),
          ),
          width: 320,
          scale: 2.0,
        );
        final text = t.widget<Text>(find.text('YEREL AĞDAN AÇ'));
        expect(text.maxLines, 1);
        final fitted = t.widget<FittedBox>(
          find.descendant(of: _button, matching: find.byType(FittedBox)),
        );
        expect(fitted.fit, BoxFit.scaleDown);
        // Etiket KIRPILMAZ (elips yok): FittedBox içerikte yerleşimi sınırsız genişlikte yapar ve
        // sonra küçültür; kırpma olsaydı uzun etiketler 2,0x yazıda "YEREL AĞD…" olurdu.
        final paragraph = t.renderObject<RenderParagraph>(
          find.text('YEREL AĞDAN AÇ'),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'etiket tam gösterilmeli (küçülür, kısalmaz)',
        );
        // Ölçeklenmiş etiket, daire iç kutusunu (çap - 2 x 12 dp) aşmaz.
        final inner = t.getRect(find.byType(AnimatedContainer)).width - 24;
        expect(
          t.getRect(find.text('YEREL AĞDAN AÇ')).width,
          lessThanOrEqualTo(inner + 1e-6),
        );
        // İçerik dairenin İÇİNDE kalır (etiket köşeleri yarıçapı aşmaz: beyaz metin zemine taşmaz).
        final circle = t.getRect(find.byType(AnimatedContainer));
        final label = t.getRect(find.text('YEREL AĞDAN AÇ'));
        final radius = circle.width / 2;
        for (final corner in [
          label.topLeft,
          label.topRight,
          label.bottomLeft,
          label.bottomRight,
        ]) {
          expect(
            (corner - circle.center).distance,
            lessThanOrEqualTo(radius),
            reason: 'köşe $corner daire dışında',
          );
        }
      },
    );
  });

  group('dokunma alanı', () {
    testWidgets(
      'daire: yalnız daire içi dokunuşlar çalışır; kare köşeleri boştur (yanlışlıkla kapı açılmaz)',
      (t) async {
        final haptics = recordHaptics(t);
        var calls = 0;
        await t.pumpWidget(_app(_door(onPressed: () => calls++)));
        final rect = t.getRect(find.byType(AnimatedContainer));
        final r = rect.width / 2;

        // Kare köşeleri (daire dışı): dokunma hiçbir şey yapmaz, ölçek de değişmez.
        for (final corner in [
          rect.topLeft + const Offset(3, 3),
          rect.topRight + const Offset(-3, 3),
          rect.bottomLeft + const Offset(3, -3),
          rect.bottomRight + const Offset(-3, -3),
        ]) {
          expect(
            (corner - rect.center).distance,
            greaterThan(r),
            reason: 'önkoşul: $corner daire dışında',
          );
          final g = await t.startGesture(corner);
          await t.pump(const Duration(milliseconds: 250));
          expect(_targetScale(t), 1.0, reason: 'köşe basışında ölçek yok');
          await g.up();
          await t.pump();
        }
        expect(calls, 0);
        expect(haptics, isEmpty);

        // Dairenin kenarına yakın iç noktalar ve merkez: çalışır.
        for (final inside in [
          rect.center,
          rect.center + Offset(r * 0.9, 0),
          rect.center + Offset(-r * 0.9, 0),
          rect.center + Offset(0, r * 0.9),
          rect.center + Offset(0, -r * 0.9),
        ]) {
          await t.tapAt(inside);
          await t.pumpAndSettle();
        }
        expect(calls, 5);
        expect(haptics, hasLength(5));
      },
    );

    testWidgets('daire: çevrimdışı titreme/uyarı da yalnız daire içinde', (
      t,
    ) async {
      var blocked = 0;
      await t.pumpWidget(
        _app(_door(state: DoorOpenState.offline, onBlocked: () => blocked++)),
      );
      final rect = t.getRect(find.byType(AnimatedContainer));
      await t.tapAt(rect.topLeft + const Offset(3, 3));
      await t.pumpAndSettle();
      expect(blocked, 0);
      await t.tapAt(rect.center);
      await t.pumpAndSettle();
      expect(blocked, 1);
    });

    testWidgets(
      'daire: boyama kırpılmaz (glow gölgesi dairenin dışına taşar)',
      (t) async {
        await t.pumpWidget(_app(_door(onPressed: () {})));
        final clip = t.widget<ClipOval>(
          find.descendant(of: _button, matching: find.byType(ClipOval)),
        );
        expect(clip.clipBehavior, Clip.none);
      },
    );

    testWidgets('çubuk: köşeler dahil tüm dikdörtgen dokunulur', (t) async {
      var calls = 0;
      await t.pumpWidget(
        _app(
          SizedBox(
            width: 320,
            child: _door(
              variant: DoorOpenVariant.bar,
              label: 'Kapı Aç',
              onPressed: () => calls++,
            ),
          ),
        ),
      );
      final rect = t.getRect(find.byType(AnimatedContainer));
      await t.tapAt(rect.topLeft + const Offset(20, 5));
      await t.pumpAndSettle();
      await t.tapAt(rect.bottomRight - const Offset(20, 5));
      await t.pumpAndSettle();
      expect(calls, 2);
    });
  });

  group('taşma matrisi', () {
    for (final variant in DoorOpenVariant.values) {
      testWidgets(
        '${variant.name}: tüm durumlar + başarı x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu',
        (t) async {
          await forEachHarnessCell((width, scale, dark) async {
            final tick = ValueNotifier<int>(0);
            addTearDown(tick.dispose);
            await pumpAt(
              t,
              _stateColumn(variant, tick),
              width: width,
              scale: scale,
              dark: dark,
            );
            final reason = '$width x $scale dark=$dark';
            expect(
              find.byType(DoorOpenButton),
              findsNWidgets(4),
              reason: reason,
            );
            expect(
              find.byType(CircularProgressIndicator),
              findsOneWidget,
              reason: reason,
            );
            // Başarı gösterimi (tik + doneLabel) de taşmaz.
            tick.value = 1;
            await t.pump(const Duration(milliseconds: 300));
            expect(t.takeException(), isNull, reason: reason);
            expect(
              find.text(
                variant == DoorOpenVariant.circle ? 'GÖNDERİLDİ' : 'Gönderildi',
              ),
              findsNWidgets(3),
              reason: '$reason (opening hariç üçü başarıda)',
            );
            await t.pump(const Duration(milliseconds: 1500));
            expect(t.takeException(), isNull, reason: reason);
          });
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }

    testWidgets(
      'AGENTS: 320x640 x2,0 ve 360x640 x1,5, açık+koyu (iki varyant, tüm durumlar)',
      (t) async {
        for (final (width, scale) in [(320.0, 2.0), (360.0, 1.5)]) {
          for (final dark in [false, true]) {
            for (final variant in DoorOpenVariant.values) {
              await pumpAt(
                t,
                _stateColumn(variant, ValueNotifier<int>(0)),
                width: width,
                height: 640,
                scale: scale,
                dark: dark,
              );
              expect(find.byType(DoorOpenButton), findsNWidgets(4));
            }
          }
        }
      },
    );

    testWidgets(
      'uzun etiketler: daire tek satır + elips, çubuk 2 satır + elips; taşma yok',
      (t) async {
        const long =
            'Çok uzun bir kapı etiketi: tüm site girişlerini aynı anda açar';
        for (final scale in kHarnessScales) {
          await pumpAt(
            t,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _door(label: long, onPressed: () {}),
                ),
                _door(
                  variant: DoorOpenVariant.bar,
                  label: long,
                  onPressed: () {},
                ),
              ],
            ),
            width: 320,
            scale: scale,
          );
          expect(find.text(long), findsNWidgets(2));
          final texts = find
              .text(long)
              .evaluate()
              .map((e) => e.widget as Text)
              .toList();
          expect(texts[0].maxLines, 1);
          expect(texts[1].maxLines, 2);
          expect(texts[0].overflow, TextOverflow.ellipsis);
          expect(texts[1].overflow, TextOverflow.ellipsis);
        }
      },
    );
  });
}
