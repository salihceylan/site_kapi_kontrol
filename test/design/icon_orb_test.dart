// IconOrb testleri: boyut, ton, anlamsal ağaç, durağanlık, taşma matrisi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

Widget _app(Widget w, {bool dark = false}) =>
    harnessApp(Center(child: w), dark: dark);

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

void main() {
  testWidgets('boyut: size x size; ikon yarısı; beyaz; yazı ölçeğinden etkilenmez', (
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
      expect(icon.color, Colors.white);
    }
  });

  testWidgets('ton gradyanı ve biçim (daire / squircle)', (t) async {
    for (final tone in AppTone.values) {
      await t.pumpWidget(_app(IconOrb(icon: Icons.lock, tone: tone)));
      expect(_deco(t).gradient, tone.gradient, reason: tone.name);
      expect(_deco(t).shape, isA<CircleBorder>());
    }
    await t.pumpWidget(
      _app(const IconOrb(icon: Icons.lock, shape: IconOrbShape.squircle)),
    );
    final shape = _deco(t).shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(44 * 0.30));
  });

  testWidgets('glow: tek katman, blur <= 16, spread yok; kapalıyken gölge yok', (
    t,
  ) async {
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock, size: 96)));
    expect(_deco(t).shadows, isNull);
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock, size: 96, glow: true)));
    final shadows = _deco(t).shadows!;
    expect(shadows, hasLength(1));
    expect(shadows.single.blurRadius, lessThanOrEqualTo(16));
    expect(shadows.single.spreadRadius, 0);
  });

  testWidgets('cila içerir (Gloss) ve dokunmayı yutmaz', (t) async {
    await t.pumpWidget(_app(const IconOrb(icon: Icons.lock)));
    expect(
      find.descendant(of: find.byType(IconOrb), matching: find.byType(Gloss)),
      findsOneWidget,
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
