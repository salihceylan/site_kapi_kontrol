// İP-1C (karar G7): StatusDot — durum noktası + metin (sözleşme 2.3).
//
// Nokta metnin solundadır, zemin boyanmaz. Renk: tamam #10B981, bekliyor #F59E0B, kritik #E11D48; öteki tonlar nötr gri.
// Açık temada noktası yüzeye 3:1'i tutmayan tonlar (tamam, bekliyor) 1 dp koyu kenar alır (vitrinle aynı yöntem). Metin
// gövde metni renginde (>= 4,5:1). Durağandır; taşmaz; ekran okuyucu yalnız metni okur.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/status_dot.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

Finder _dots() => find.descendant(
  of: find.byType(StatusDot),
  matching: find.byWidgetPredicate(
    (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
);

BoxDecoration _dot(WidgetTester t) => t.widget<DecoratedBox>(_dots()).decoration as BoxDecoration;

/// Temiz ağaçla kurar: aynı MaterialApp'ta tema değişirse 200 ms'lik tema geçişinin ilk karesi eski paleti gösterir.
Future<void> _pump(WidgetTester t, Widget app) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(app);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('nokta + metin; zemin ve çerçeve yok (yalnız nokta boyanır)', (t) async {
    await _pump(t, harnessApp(const Center(child: StatusDot(label: 'Çevrimiçi', tone: AppTone.success))));
    expect(find.text('Çevrimiçi'), findsOneWidget);
    expect(_dots(), findsOneWidget);
    final painted = t
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(StatusDot), matching: find.byType(DecoratedBox)))
        .map((b) => b.decoration as BoxDecoration)
        .where((d) => d.shape != BoxShape.circle && (d.color != null || d.border != null || d.gradient != null));
    expect(painted, isEmpty, reason: 'zemin boyanmaz');
    final size = t.getSize(_dots());
    expect(size, const Size(StatusDot.size, StatusDot.size));
  });

  testWidgets('nokta rengi: durum tonlarında durum rengi, ötekilerde nötr gri (açık + koyu)', (t) async {
    const expected = <AppTone, Color>{
      AppTone.success: Color(0xFF10B981),
      AppTone.warning: Color(0xFFF59E0B),
      AppTone.danger: Color(0xFFE11D48),
      AppTone.primary: Color(0xFF64748B),
      AppTone.info: Color(0xFF64748B),
      AppTone.violet: Color(0xFF64748B),
      AppTone.neutral: Color(0xFF64748B),
    };
    for (final dark in const [false, true]) {
      for (final e in expected.entries) {
        await _pump(t, harnessApp(Center(child: StatusDot(label: 'x', tone: e.key)), dark: dark));
        expect(_dot(t).color, e.value, reason: '${e.key.name} dark=$dark');
      }
    }
  });

  testWidgets('kenar: açık temada tamam ve bekliyor noktasına 1 dp koyu kenar (tonun a rengi); koyuda kenar yok', (t) async {
    for (final tone in AppTone.values) {
      await _pump(t, harnessApp(Center(child: StatusDot(label: 'x', tone: tone))));
      final border = _dot(t).border as Border?;
      if (tone == AppTone.success || tone == AppTone.warning) {
        expect(border, isNotNull, reason: tone.name);
        expect(border!.top.color, tone.a, reason: tone.name);
        expect(border.top.width, 1);
      } else {
        expect(border, isNull, reason: tone.name);
      }
      expect(StatusDot.edgeOf(tone, AppPalette.light), border?.top.color);
      await _pump(t, harnessApp(Center(child: StatusDot(label: 'x', tone: tone)), dark: true));
      expect(_dot(t).border, isNull, reason: '${tone.name} koyu');
      expect(StatusDot.edgeOf(tone, AppPalette.dark), isNull);
    }
  });

  testWidgets('metin: gövde metni rengi, kalın, varsayılan tek satır + elips; maxLines null iken sarar', (t) async {
    for (final dark in const [false, true]) {
      final p = dark ? AppPalette.dark : AppPalette.light;
      await _pump(t, harnessApp(const Center(child: StatusDot(label: 'Bekliyor', tone: AppTone.warning)), dark: dark));
      final text = t.widget<Text>(find.text('Bekliyor'));
      expect(text.style!.color, p.textSecondary);
      expect(text.style!.fontWeight, FontWeight.w700);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
    const long = 'Vadesi geçen borç: 1.250,00 TL ve sıradaki vade 10.11.2026 tarihinde';
    await t.pumpWidget(
      harnessApp(const Center(child: SizedBox(width: 160, child: StatusDot(label: long, tone: AppTone.danger, maxLines: null)))),
    );
    expect(t.takeException(), isNull);
    expect(t.widget<Text>(find.text(long)).maxLines, isNull);
    expect(t.getSize(find.byType(StatusDot)).height, greaterThan(30), reason: 'birden çok satıra sardı');
  });

  testWidgets('ekran okuyucu metni okur, nokta dışlanır; dokunulamaz', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, harnessApp(const Center(child: StatusDot(label: 'Çevrimdışı', tone: AppTone.danger))));
    expect(find.bySemanticsLabel('Çevrimdışı'), findsOneWidget);
    expect(
      find.ancestor(of: _dots(), matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
    final node = t.getSemantics(find.bySemanticsLabel('Çevrimdışı'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });

  testWidgets('durağan: ticker ve kare yok', (t) async {
    await _pump(t, harnessApp(const Center(child: StatusDot(label: 'Çevrimiçi', tone: AppTone.success))));
    expect(t.binding.transientCallbackCount, 0);
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('taşma matrisi: 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu (Wrap içinde)', (t) async {
    await forEachHarnessCell((width, scale, dark) async {
      await pumpAt(
        t,
        const SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusDot(label: 'Çevrimiçi (Bulut)', tone: AppTone.success),
              StatusDot(label: 'Yerel ağda bekliyor', tone: AppTone.warning),
              StatusDot(label: 'Çevrimdışı', tone: AppTone.danger),
              StatusDot(label: 'Çok uzun bir durum etiketi kesilmeden elips ile kısalır', tone: AppTone.neutral),
            ],
          ),
        ),
        width: width,
        scale: scale,
        dark: dark,
      );
    });
  });
}
