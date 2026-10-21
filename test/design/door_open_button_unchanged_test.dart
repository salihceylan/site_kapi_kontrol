// İP-1C (G6 + G7 sade tasarım): kapı düğmesinin GÖRÜNÜŞÜ değişmez (karar kaydı G6/G7: "Kapı düğmesinin görünüşü ve kapı
// akışı değişmez").
//
// Sade stil temayı ve ortak bileşenleri değiştirir; `DoorOpenButton` bilinçli istisnadır (cilalı yuvarlak düğme, aura,
// efektler). Bu dosya iki kanıt taşır:
//  1. DEĞER kilidi (her platformda): düğmenin her durum x ton x biçim x temada okuduğu yüzey degradesi, gölgesi, cila şiddeti,
//     etiket / ikon stili ve mürekkep renkleri, sade stile geçişten ÖNCEKİ (4d754cf) değerlerle birebir aynıdır.
//  2. PİKSEL kilidi (Windows): açık ve koyu temada tüm durumların ızgarası, geçişten ÖNCE üretilmiş altın görüntülerle piksel
//     piksel aynıdır (`goldens/door_open_button_*.png`). Yazı tipi testin varsayılanıdır (kutucuk); renk, cila, aura, gölge ve
//     yerleşim pikselde görünür. Linux/macOS yazı ve kenar yumuşatma farkı yüzünden yalnız Windows'ta karşılaştırılır.
// Davranış (durum makinesi, haptik, başarı sinyali, erişilebilirlik) `door_open_button_test.dart`'tadır ve o dosya değişmedi.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

final Finder _door = find.byType(DoorOpenButton);

ShapeDecoration _face(WidgetTester t) =>
    t.widget<AnimatedContainer>(find.descendant(of: _door, matching: find.byType(AnimatedContainer))).decoration!
        as ShapeDecoration;

Gloss _gloss(WidgetTester t) => t.widget<Gloss>(find.descendant(of: _door, matching: find.byType(Gloss)));

TextStyle _label(WidgetTester t) => t.widget<Text>(find.descendant(of: _door, matching: find.byType(Text))).style!;

Icon _icon(WidgetTester t) => t.widget<Icon>(find.descendant(of: _door, matching: find.byType(Icon)));

InkWell _ink(WidgetTester t) => t.widget<InkWell>(find.descendant(of: _door, matching: find.byType(InkWell)));

// Sade stile geçişten önceki (4d754cf) değerler. DEĞİŞTİRMEYİN: değişirse kapı düğmesinin görünüşü değişmiş demektir.

/// Canlı yüzey degradesi (kapı düğmesinin üç tonu: bulut, yerel ağ, karekod).
const Map<AppTone, List<Color>> _liveGradient = <AppTone, List<Color>>{
  AppTone.primary: <Color>[Color(0xFF2563EB), Color(0xFF1D4ED8)],
  AppTone.warning: <Color>[Color(0xFFB45309), Color(0xFF92400E)],
  AppTone.success: <Color>[Color(0xFF047857), Color(0xFF065F46)],
};

/// Canlı yüzeyin renkli gölgesi: degradenin ilk rengi %35, blur 16, aşağı 6 dp.
BoxShadow _liveShadow(AppTone tone) => BoxShadow(
      color: _liveGradient[tone]!.first.withValues(alpha: 0.35),
      blurRadius: 16,
      offset: const Offset(0, 6),
    );

/// Nötr (çevrimdışı / devre dışı) yüzey: soluk yüzey -> yüzey kenarı (koyuda saydam kenar yüzeye bindirilmiş).
final Map<bool, List<Color>> _neutralGradient = <bool, List<Color>>{
  false: <Color>[const Color(0xFFF1F5F9), Color.alphaBlend(const Color(0xFFE2E8F0), const Color(0xFFFFFFFF))],
  true: <Color>[const Color(0xFF0F172A), Color.alphaBlend(const Color(0x24FFFFFF), const Color(0xFF1E293B))],
};

const Map<bool, BoxShadow> _neutralShadow = <bool, BoxShadow>{
  false: BoxShadow(color: Color(0x0D0F172A), blurRadius: 6, offset: Offset(0, 2)),
  true: BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 2)),
};

/// Nötr yüzeydeki içerik rengi (ikincil metin).
const Map<bool, Color> _neutralInk = <bool, Color>{false: Color(0xFF475569), true: Color(0xFFCBD5E1)};

/// Canlı yüzeydeki beyaz içeriğin ince gölgesi.
const Shadow _contentShadow = Shadow(color: Color(0x47000000), blurRadius: 4, offset: Offset(0, 1.5));

DoorOpenButton _button({
  required DoorOpenState state,
  AppTone tone = AppTone.primary,
  DoorOpenVariant variant = DoorOpenVariant.circle,
}) =>
    DoorOpenButton(
      state: state,
      label: state == DoorOpenState.ready ? 'KAPIYI AÇ' : 'ÇEVRİMDIŞI',
      icon: state == DoorOpenState.ready ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
      tone: tone,
      variant: variant,
      onPressed: () {},
    );

/// Altın görüntü ızgarası: üst sıra daire (3 canlı ton + çevrimdışı + devre dışı), alt sıra çubuk (aynı sıra).
Widget _grid() {
  const states = <(DoorOpenState, AppTone)>[
    (DoorOpenState.ready, AppTone.primary),
    (DoorOpenState.ready, AppTone.warning),
    (DoorOpenState.ready, AppTone.success),
    (DoorOpenState.offline, AppTone.primary),
    (DoorOpenState.disabled, AppTone.primary),
  ];
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (s, tone) in states)
              SizedBox(width: 200, height: 200, child: Center(child: _button(state: s, tone: tone))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (s, tone) in states)
              SizedBox(
                width: 200,
                height: 88,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: _button(state: s, tone: tone, variant: DoorOpenVariant.bar)),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  group('kapı düğmesi: değerler sade stile geçişten önceki gibi (her platform)', () {
    for (final dark in const <bool>[false, true]) {
      final theme = dark ? 'koyu' : 'açık';
      for (final variant in DoorOpenVariant.values) {
        final circle = variant == DoorOpenVariant.circle;
        for (final tone in _liveGradient.keys) {
          testWidgets('$theme ${variant.name} hazır (${tone.name}): degrade, gölge, cila, etiket, ikon, mürekkep', (t) async {
            await t.pumpWidget(harnessApp(Center(child: _button(state: DoorOpenState.ready, tone: tone, variant: variant)),
                dark: dark));
            await t.pump(const Duration(milliseconds: 300));
            final face = _face(t);
            expect((face.gradient! as LinearGradient).colors, _liveGradient[tone]);
            expect((face.gradient! as LinearGradient).begin, Alignment.topLeft);
            expect((face.gradient! as LinearGradient).end, Alignment.bottomRight);
            expect(face.shadows, <BoxShadow>[_liveShadow(tone)]);
            expect(face.shape, circle ? const CircleBorder() : isA<RoundedRectangleBorder>());
            final gloss = _gloss(t);
            expect(gloss.strength, 1.0);
            expect(gloss.shape, circle ? GlossShape.circle : GlossShape.rounded);
            expect(gloss.radius, 16);
            final label = _label(t);
            expect(label.color, Colors.white);
            expect(label.fontSize, circle ? 15 : 16);
            expect(label.fontWeight, FontWeight.w900);
            expect(label.letterSpacing, 0.8);
            expect(label.shadows, const <Shadow>[_contentShadow]);
            final icon = _icon(t);
            expect(icon.size, circle ? 48 : 22);
            expect(icon.color, Colors.white);
            expect(icon.shadows, const <Shadow>[_contentShadow]);
            final ink = _ink(t);
            expect(ink.splashColor, Colors.white.withValues(alpha: 0.24));
            expect(ink.highlightColor, Colors.white.withValues(alpha: 0.10));
            expect(ink.hoverColor, Colors.white.withValues(alpha: 0.10));
            expect(ink.focusColor, Colors.white.withValues(alpha: 0.22));
            // Aura (yalnız dairede, canlıyken): yüzeyin altında RepaintBoundary + CustomPaint.
            final auras = find.descendant(
              of: _door,
              matching: find.byWidgetPredicate((w) => w is CustomPaint && '${w.painter.runtimeType}' == '_AuraPainter'),
            );
            expect(auras, circle ? findsOneWidget : findsNothing);
          });
        }
        for (final state in const <DoorOpenState>[DoorOpenState.offline, DoorOpenState.disabled]) {
          testWidgets('$theme ${variant.name} ${state.name}: nötr degrade, tek gölge, soluk cila, ikincil metin', (t) async {
            await t.pumpWidget(harnessApp(Center(child: _button(state: state, variant: variant)), dark: dark));
            await t.pump(const Duration(milliseconds: 300));
            final face = _face(t);
            expect((face.gradient! as LinearGradient).colors, _neutralGradient[dark]);
            expect(face.shadows, <BoxShadow>[_neutralShadow[dark]!]);
            expect(_gloss(t).strength, 0.55);
            final label = _label(t);
            expect(label.color, _neutralInk[dark]);
            expect(label.shadows, isNull);
            expect(label.fontWeight, FontWeight.w900);
            expect(_icon(t).color, _neutralInk[dark]);
            final ink = _ink(t);
            expect(ink.splashColor, _neutralInk[dark]!.withValues(alpha: 0.14));
            expect(ink.focusColor, _neutralInk[dark]!.withValues(alpha: 0.14));
          });
        }
      }
    }
  });

  group('kapı düğmesi: piksel piksel aynı (Windows, altın görüntü geçişten önce üretildi)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets('${dark ? 'koyu' : 'açık'} tema: daire ve çubuk, tüm durumlar', (t) async {
        t.view.physicalSize = const Size(1032, 360);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          harnessApp(
            Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(key: const ValueKey<String>('kapi_izgara'), child: _grid()),
            ),
            dark: dark,
          ),
        );
        await t.pump(const Duration(milliseconds: 500));
        await expectLater(
          find.byKey(const ValueKey<String>('kapi_izgara')),
          matchesGoldenFile('goldens/door_open_button_${dark ? 'dark' : 'light'}.png'),
        );
      }, skip: !Platform.isWindows);

      // Açılıyor: ilerleme göstergesi (uç biçimi temadan) + sonar halkaları; sabit anda (350 ms) karşılaştırılır.
      testWidgets('${dark ? 'koyu' : 'açık'} tema: açılıyor (daire ve çubuk, sabit an)', (t) async {
        t.view.physicalSize = const Size(440, 260);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          harnessApp(
            Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: const ValueKey<String>('kapi_aciliyor'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 200, height: 200, child: Center(child: _button(state: DoorOpenState.opening))),
                      SizedBox(
                        width: 200,
                        height: 88,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: _button(state: DoorOpenState.opening, variant: DoorOpenVariant.bar),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            dark: dark,
          ),
        );
        await t.pump(const Duration(milliseconds: 350));
        await expectLater(
          find.byKey(const ValueKey<String>('kapi_aciliyor')),
          matchesGoldenFile('goldens/door_open_button_opening_${dark ? 'dark' : 'light'}.png'),
        );
      }, skip: !Platform.isWindows);
    }
  });
}
