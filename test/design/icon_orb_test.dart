// IconOrb testleri: boyut, ton, anlamsal ağaç, durağanlık, taşma matrisi.
//
// İP-1C (karar G6 + G7, sade stil): rozet DÜZDÜR: soluk yüzey zemin + 1 px palet kenarı; degrade, cila (Gloss) ve
// renkli parıltı YOK (`glow` geriye uyum için durur, etkisizdir). İkon tonun işaret rengindedir ([AppTone.sign]: durum
// tonlarında ink, öteki tonlarda gövde metni rengi) ve zemine >= 4,5:1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

Widget _app(Widget w, {bool dark = false}) =>
    harnessApp(Center(child: w), dark: dark);

/// Temiz ağaçla kurar (tema geçişinin ilk karesi eski paleti göstermesin).
Future<void> _pump(WidgetTester t, Widget w, {bool dark = false}) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(_app(w, dark: dark));
  await t.pumpAndSettle();
}

ShapeDecoration _deco(WidgetTester t) => t
    .widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(IconOrb),
            matching: find.byType(DecoratedBox),
          )
          .first,
    )
    .decoration as ShapeDecoration;

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return ((l1 > l2 ? l1 : l2) + 0.05) / ((l1 > l2 ? l2 : l1) + 0.05);
}

void main() {
  testWidgets('boyut: size x size; ikon yarısı; işaret rengi; yazı ölçeğinden etkilenmez', (
    t,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await t.pumpWidget(
        harnessApp(
          const Center(
            child: IconOrb(icon: Icons.meeting_room_rounded, size: 48),
          ),
          scale: scale,
        ),
      );
      expect(t.getSize(find.byType(IconOrb)), const Size(48, 48));
      final icon = t.widget<Icon>(find.byIcon(Icons.meeting_room_rounded));
      expect(icon.size, 24);
      expect(icon.color, AppTone.primary.sign(AppPalette.light));
      expect(icon.shadows, isNull, reason: 'ikon gölgesi yok');
    }
  });

  testWidgets('düz zemin: soluk yüzey + 1 px kenar, degrade yok; ikon tonun işaret rengi (7 ton x açık/koyu)', (t) async {
    for (final dark in [false, true]) {
      final p = dark ? AppPalette.dark : AppPalette.light;
      for (final tone in AppTone.values) {
        await _pump(t, IconOrb(icon: Icons.lock, tone: tone), dark: dark);
        final deco = _deco(t);
        expect(deco.gradient, isNull, reason: tone.name);
        expect(deco.color, p.surfaceMuted, reason: '${tone.name} dark=$dark');
        expect((deco.shape as CircleBorder).side, BorderSide(color: p.border));
        final icon = t.widget<Icon>(find.byIcon(Icons.lock));
        expect(icon.color, tone.sign(p), reason: '${tone.name} dark=$dark');
        expect(
          _contrast(icon.color!, p.surfaceMuted),
          greaterThanOrEqualTo(4.5),
          reason: '${tone.name} dark=$dark',
        );
      }
    }
    await _pump(t, const IconOrb(icon: Icons.lock, shape: IconOrbShape.squircle));
    final shape = _deco(t).shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(44 * 0.30));
    expect(shape.side, BorderSide(color: AppPalette.light.border));
  });

  testWidgets('mavi yok: birincil / bilgi / mor tonlarda ikon nötr (gövde metni), durum tonlarında ink', (t) async {
    for (final tone in const [AppTone.primary, AppTone.info, AppTone.violet, AppTone.neutral]) {
      expect(tone.sign(AppPalette.light), AppPalette.light.textSecondary, reason: tone.name);
    }
    for (final tone in const [AppTone.success, AppTone.warning, AppTone.danger]) {
      expect(tone.sign(AppPalette.light), tone.inkLight, reason: tone.name);
    }
  });

  testWidgets('glow geriye uyum için durur ama gölge çizmez (sade stil)', (
    t,
  ) async {
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock, size: 96)));
    expect(_deco(t).shadows, isNull);
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock, size: 96, glow: true)));
    expect(_deco(t).shadows, isNull);
  });

  testWidgets('cila yok (Gloss içermez)', (t) async {
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock, glow: true)));
    expect(
      find.descendant(of: find.byType(IconOrb), matching: find.byType(Gloss)),
      findsNothing,
    );
  });

  testWidgets('anlamsal ağaç: etiketsiz dışlanır; etiketli tek görüntü düğümü', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock)));
    expect(find.bySemanticsLabel('Kapı'), findsNothing);
    await t.pumpWidget(
      _app(const IconOrb(icon: Icons.lock, semanticLabel: 'Kapı')),
    );
    expect(find.bySemanticsLabel('Kapı'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('durağan: ticker ve kare yok', (t) async {
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock, glow: true)));
    await t.pumpAndSettle();
    expect(t.binding.transientCallbackCount, 0);
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('taşma matrisi: 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (t) async {
    await forEachHarnessCell((width, scale, dark) async {
      await pumpAt(
        t,
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconOrb(icon: Icons.lock, size: 24),
            IconOrb(icon: Icons.lock, size: 44, tone: AppTone.success),
            IconOrb(
              icon: Icons.lock,
              size: 64,
              shape: IconOrbShape.squircle,
              tone: AppTone.warning,
              glow: true,
            ),
            IconOrb(icon: Icons.lock, size: 96, tone: AppTone.violet, glow: true),
          ],
        ),
        width: width,
        scale: scale,
        dark: dark,
      );
      expect(find.byType(IconOrb), findsNWidgets(4));
    });
  });
}
