// FAZ 5 / A1b (i): StatusChip widget testleri.
//
// Durumlar (7 ton x açık/koyu, ikon/nokta/nabız), nabzın 3 tur sonra DURMASI (pumpAndSettle biter,
// kararlı durumda ticker yok), renk geçişi, hareket azaltma, Semantics (tek düğüm, dokunulamaz) ve
// taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

/// Nabzın toplam süresi (3 x 900 ms).
const Duration _pulseTotal = Duration(milliseconds: 2700);

StatusChip _chip({
  String label = 'Çevrimiçi',
  AppTone tone = AppTone.success,
  IconData? icon,
  bool pulse = false,
}) => StatusChip(label: label, tone: tone, icon: icon, pulse: pulse);

Widget _app(
  StatusChip chip, {
  bool dark = false,
  bool reduce = false,
  double scale = 1.0,
}) => harnessApp(
  Center(child: chip),
  dark: dark,
  reduce: reduce,
  scale: scale,
);

/// pumpAndSettle kaç kare ilerlediğini döndürür (100 ms'lik adımlar): geçen yaklaşık süre.
Future<Duration> _settle(WidgetTester t) async =>
    Duration(milliseconds: await t.pumpAndSettle() * 100);

AppPalette _palette(bool dark) => dark ? AppPalette.dark : AppPalette.light;

/// Rozet gövdesinin (ilk DecoratedBox) o an çizilen süslemesi.
BoxDecoration _bodyDecoration(WidgetTester t) {
  final f = find.descendant(
    of: find.descendant(
      of: find.byType(StatusChip),
      matching: find.byType(AnimatedContainer),
    ),
    matching: find.byType(DecoratedBox),
  );
  return t.widget<DecoratedBox>(f.first).decoration as BoxDecoration;
}

/// Daire biçimli süslemeli kutular: nabız halkası (varsa) ve nokta; sonuncusu noktadır.
Finder _circles() => find.descendant(
  of: find.byType(StatusChip),
  matching: find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
);

Color _dotColor(WidgetTester t) {
  final f = _circles();
  return ((t.widget<DecoratedBox>(f.last)).decoration as BoxDecoration).color!;
}

/// Etiketin etkin (animasyonlu) metin stili.
TextStyle _labelStyle(WidgetTester t, [String label = 'Çevrimiçi']) =>
    DefaultTextStyle.of(t.element(find.text(label))).style;

/// Nabız halkasının o anki ölçeği (halka yoksa null).
double? _ringScale(WidgetTester t) {
  final f = find.descendant(
    of: find.byType(StatusChip),
    matching: find.byType(Transform),
  );
  if (f.evaluate().isEmpty) return null;
  return t.widget<Transform>(f.first).transform.getMaxScaleOnAxis();
}

void main() {
  group('StatusChip: görünüm', () {
    testWidgets(
      '7 ton x açık/koyu: tint zemin, hue kenarı, ink metin ve nokta, hap biçimi',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          for (final tone in AppTone.values) {
            await t.pumpWidget(_app(_chip(tone: tone), dark: dark));
            await t.pumpAndSettle();
            final deco = _bodyDecoration(t);
            expect(deco.color, tone.tint(p), reason: '${tone.name} dark=$dark');
            expect(
              (deco.border! as Border).top.color,
              tone.hue.withValues(alpha: 0.4),
            );
            expect(
              deco.borderRadius,
              BorderRadius.circular(AppRadius.pill),
              reason: 'hap biçimi',
            );
            final style = _labelStyle(t);
            expect(style.color, tone.ink(p));
            expect(style.fontWeight, FontWeight.w700);
            expect(_dotColor(t), tone.ink(p));
            expect(find.text('Çevrimiçi'), findsOneWidget);
          }
        }
      },
    );

    testWidgets('ikon verilir ve nabız kapalıysa nokta yerine ikon çizilir', (
      t,
    ) async {
      await t.pumpWidget(
        _app(_chip(tone: AppTone.warning, icon: Icons.wifi_rounded)),
      );
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
      expect(_circles(), findsNothing, reason: 'nokta yok');
      final icon = t.widget<Icon>(find.byIcon(Icons.wifi_rounded));
      expect(icon.size, 14);
      expect(icon.color, AppTone.warning.ink(AppPalette.light));
    });

    testWidgets('ikon yok: nokta (8 dp) çizilir', (t) async {
      await t.pumpWidget(_app(_chip()));
      await t.pumpAndSettle();
      expect(_circles(), findsOneWidget);
      expect(
        t.getSize(_circles().last),
        const Size(8, 8),
        reason: 'nokta 8 dp',
      );
    });

    testWidgets('nabızda nokta önceliklidir: ikon verilse bile ikon çizilmez', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(icon: Icons.wifi_rounded, pulse: true)));
      await t.pump();
      expect(find.byIcon(Icons.wifi_rounded), findsNothing);
      expect(_circles(), findsNWidgets(2), reason: 'halka + nokta');
    });

    testWidgets('nabız bitince ikonlu rozet ikonu gösterir (pulse false)', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(icon: Icons.wifi_rounded, pulse: true)));
      await t.pump();
      await t.pumpWidget(_app(_chip(icon: Icons.wifi_rounded)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
    });

    testWidgets('etiket tek satır + elips: dar kutuda kırpılır, taşmaz', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: _chip(label: 'Çok uzun bir durum etiketi burada'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(StatusChip)).width, lessThanOrEqualTo(120));
      final paragraph = t.renderObject<RenderParagraph>(
        find.text('Çok uzun bir durum etiketi burada'),
      );
      expect(paragraph.maxLines, 1);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(paragraph.overflow, TextOverflow.ellipsis);
    });

    testWidgets('sabit boyut yok: yazı ölçeği büyüyünce rozet de büyür', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip()));
      final small = t.getSize(find.byType(StatusChip));
      await t.pumpWidget(_app(_chip(), scale: 2.0));
      final big = t.getSize(find.byType(StatusChip));
      expect(big.height, greaterThan(small.height));
      expect(big.width, greaterThan(small.width));
    });
  });

  group('StatusChip: nabız (3 tur sonra durur)', () {
    testWidgets('nabız sürerken halka ölçeği 1,0 -> 1,75 aralığında ilerler', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump();
      expect(t.binding.transientCallbackCount, greaterThan(0));
      expect(_circles(), findsNWidgets(2));
      await t.pump(
        const Duration(milliseconds: 450),
      ); // 900 ms'lik turun ortası
      expect(_ringScale(t), closeTo(1 + 0.75 * 0.5, 0.02));
      final ring =
          t.widget<DecoratedBox>(_circles().first).decoration as BoxDecoration;
      final ink = AppTone.success.ink(AppPalette.light);
      expect(ring.color!.a, closeTo(0.35 * 0.5, 0.02));
      expect(ring.color!.toARGB32() & 0x00FFFFFF, ink.toARGB32() & 0x00FFFFFF);
    });

    testWidgets(
      '3 tur (2,7 sn) sonra DURUR: ticker yok, halka ağaçtan kalkar',
      (t) async {
        await t.pumpWidget(_app(_chip(pulse: true)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 1800)); // 2. turun sonu
        expect(
          t.binding.transientCallbackCount,
          greaterThan(0),
          reason: '2 tur bitti, 3. tur sürüyor',
        );
        expect(_circles(), findsNWidgets(2));
        await t.pump(const Duration(milliseconds: 1000)); // 2,8 sn
        await t.pump();
        expect(t.binding.transientCallbackCount, 0, reason: 'nabız bitti');
        expect(_ringScale(t), isNull, reason: 'halka kalmadı');
        expect(_circles(), findsOneWidget, reason: 'yalnız nokta');
      },
    );

    testWidgets('pumpAndSettle biter ve ~2,7 sn sürer (açık + koyu)', (
      t,
    ) async {
      for (final dark in [false, true]) {
        await t.pumpWidget(
          const SizedBox.shrink(),
        ); // State sızmasın: yeni nabız
        await t.pumpWidget(_app(_chip(pulse: true), dark: dark));
        final elapsed = await _settle(t);
        expect(elapsed, greaterThanOrEqualTo(_pulseTotal));
        expect(elapsed, lessThan(const Duration(seconds: 4)));
        expect(t.binding.transientCallbackCount, 0);
      }
    });

    testWidgets('pulse true -> false: nabız hemen durur, halka kalkar', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(_ringScale(t), isNotNull);
      await t.pumpWidget(_app(_chip()));
      await t.pump();
      expect(_ringScale(t), isNull);
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'pulse false -> true: nabız yeniden başlar ve yine 3 turda biter',
      (t) async {
        await t.pumpWidget(_app(_chip(pulse: true)));
        await t.pumpAndSettle(); // ilk nabız bitti
        expect(_ringScale(t), isNull);
        await t.pumpWidget(_app(_chip(label: 'Çevrimdışı')));
        await t.pump();
        await t.pumpWidget(_app(_chip(pulse: true)));
        await t.pump();
        expect(_circles(), findsNWidgets(2), reason: 'yeni nabız başladı');
        final elapsed = await _settle(t);
        expect(elapsed, greaterThanOrEqualTo(_pulseTotal));
        expect(_ringScale(t), isNull);
      },
    );

    testWidgets(
      'nabız bittikten sonra pulse true kalırken ton/etiket değişimi nabzı yeniden BAŞLATMAZ',
      (t) async {
        await t.pumpWidget(_app(_chip(pulse: true)));
        await t.pumpAndSettle();
        await t.pumpWidget(
          _app(_chip(label: 'Yerel Ağ', tone: AppTone.warning, pulse: true)),
        );
        await t.pump();
        expect(_ringScale(t), isNull, reason: 'halka yok');
        final elapsed = await _settle(t);
        expect(
          elapsed,
          lessThan(const Duration(milliseconds: 500)),
          reason: 'yalnız 200 ms renk geçişi',
        );
      },
    );

    testWidgets('tema (açık -> koyu) değişimi nabzı yeniden başlatmaz', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pumpAndSettle();
      await t.pumpWidget(_app(_chip(pulse: true), dark: true));
      final elapsed = await _settle(t);
      expect(
        elapsed,
        lessThan(const Duration(seconds: 1)),
        reason: 'yalnız tema geçişi, yeni nabız yok',
      );
      expect(_ringScale(t), isNull);
    });

    testWidgets('yazı ölçeği değişimi nabzı yeniden başlatmaz', (t) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pumpAndSettle();
      await t.pumpWidget(_app(_chip(pulse: true), scale: 1.5));
      await t.pump();
      expect(_ringScale(t), isNull);
      expect(t.binding.transientCallbackCount, lessThanOrEqualTo(1));
      await t.pumpAndSettle();
    });

    testWidgets('nabız sürerken ağaçtan kalkarsa hata yok, ticker kalmaz', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('nabızsız rozet hiç ticker kurmaz', (t) async {
      await t.pumpWidget(_app(_chip()));
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('halka ayrı RepaintBoundary içinde çizilir', (t) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump();
      final boundary = find.descendant(
        of: find.byType(StatusChip),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsWidgets);
      expect(
        find.descendant(of: boundary.first, matching: find.byType(Transform)),
        findsOneWidget,
      );
      await t.pumpAndSettle();
    });
  });

  group('StatusChip: hareket azaltma', () {
    testWidgets('nabız hiç başlamaz: tek pump, ticker yok, halka yok', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(pulse: true), reduce: true));
      await t.pump();
      expect(t.binding.transientCallbackCount, 0);
      expect(_ringScale(t), isNull);
      expect(_circles(), findsOneWidget, reason: 'yalnız nokta');
    });

    testWidgets('ton değişimi anında: tek pump yeni renkleri gösterir', (
      t,
    ) async {
      final p = AppPalette.light;
      await t.pumpWidget(_app(_chip(), reduce: true));
      await t.pumpWidget(
        _app(_chip(label: 'Çevrimdışı', tone: AppTone.danger), reduce: true),
      );
      await t.pump();
      expect(_bodyDecoration(t).color, AppTone.danger.tint(p));
      expect(_labelStyle(t, 'Çevrimdışı').color, AppTone.danger.ink(p));
      expect(_dotColor(t), AppTone.danger.ink(p));
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('nabız sürerken hareket azaltma açılırsa durur', (t) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump(const Duration(milliseconds: 300));
      expect(_ringScale(t), isNotNull);
      await t.pumpWidget(_app(_chip(pulse: true), reduce: true));
      await t.pump();
      expect(_ringScale(t), isNull);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('hareket azaltma kapanınca nabız (pulse hâlâ true) başlar', (
      t,
    ) async {
      await t.pumpWidget(_app(_chip(pulse: true), reduce: true));
      await t.pump();
      expect(_ringScale(t), isNull);
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump();
      expect(_circles(), findsNWidgets(2));
      await t.pumpAndSettle();
    });

    testWidgets('pumpAndSettle hemen biter (nabızlı, açık + koyu)', (t) async {
      for (final dark in [false, true]) {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpWidget(_app(_chip(pulse: true), dark: dark, reduce: true));
        final elapsed = await _settle(t);
        expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 100)));
        expect(t.binding.transientCallbackCount, 0);
      }
    });
  });

  group('StatusChip: renk geçişi (200 ms)', () {
    testWidgets(
      'ton değişimi: zemin, kenar, metin ve nokta ara değer alır; sonunda yeni tona oturur',
      (t) async {
        final p = AppPalette.light;
        await t.pumpWidget(_app(_chip()));
        await t.pumpAndSettle();
        await t.pumpWidget(
          _app(_chip(label: 'Çevrimdışı', tone: AppTone.danger)),
        );
        await t.pump(const Duration(milliseconds: 100));
        final mid = _bodyDecoration(t);
        expect(mid.color, isNot(AppTone.success.tint(p)));
        expect(mid.color, isNot(AppTone.danger.tint(p)));
        expect(
          (mid.border! as Border).top.color,
          isNot(AppTone.danger.hue.withValues(alpha: 0.4)),
        );
        expect(
          _labelStyle(t, 'Çevrimdışı').color,
          isNot(AppTone.danger.ink(p)),
        );
        expect(_dotColor(t), isNot(AppTone.danger.ink(p)));
        expect(_dotColor(t), isNot(AppTone.success.ink(p)));
        await t.pumpAndSettle();
        final end = _bodyDecoration(t);
        expect(end.color, AppTone.danger.tint(p));
        expect(
          (end.border! as Border).top.color,
          AppTone.danger.hue.withValues(alpha: 0.4),
        );
        expect(_labelStyle(t, 'Çevrimdışı').color, AppTone.danger.ink(p));
        expect(_dotColor(t), AppTone.danger.ink(p));
      },
    );

    testWidgets('ikonlu rozet: ikon rengi de geçer ve yeni tona oturur', (
      t,
    ) async {
      final p = AppPalette.light;
      await t.pumpWidget(
        _app(_chip(tone: AppTone.warning, icon: Icons.wifi_rounded)),
      );
      await t.pumpAndSettle();
      await t.pumpWidget(
        _app(_chip(tone: AppTone.danger, icon: Icons.wifi_rounded)),
      );
      await t.pump(const Duration(milliseconds: 100));
      final mid = t.widget<Icon>(find.byIcon(Icons.wifi_rounded)).color;
      expect(mid, isNot(AppTone.warning.ink(p)));
      expect(mid, isNot(AppTone.danger.ink(p)));
      await t.pumpAndSettle();
      expect(
        t.widget<Icon>(find.byIcon(Icons.wifi_rounded)).color,
        AppTone.danger.ink(p),
      );
    });

    testWidgets('ilk kurulumda animasyon yok (ticker yok)', (t) async {
      await t.pumpWidget(_app(_chip(tone: AppTone.danger)));
      expect(t.binding.transientCallbackCount, 0);
    });
  });

  group('StatusChip: Semantics', () {
    testWidgets(
      'tek düğüm: etiket var; düğme/dokunma eylemi yok; iç metin tekrar okunmaz',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(_app(_chip(label: 'Çevrimiçi (Bulut)')));
        await t.pumpAndSettle();
        expect(
          t.getSemantics(find.byType(StatusChip)),
          isSemantics(
            label: 'Çevrimiçi (Bulut)',
            isButton: false,
            hasTapAction: false,
          ),
        );
        expect(find.bySemanticsLabel('Çevrimiçi (Bulut)'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('nabızlı ve ikonlu rozette de tek, dokunulamaz düğüm', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.bySemanticsLabel('Çevrimiçi'), findsOneWidget);
      expect(
        t
            .getSemantics(find.byType(StatusChip))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await t.pumpWidget(_app(_chip(label: 'Yerel Ağ', icon: Icons.wifi)));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Yerel Ağ'), findsOneWidget);
      expect(
        t.semantics
            .simulatedAccessibilityTraversal()
            .where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap))
            .length,
        0,
        reason: 'rozet dokunulamaz',
      );
      handle.dispose();
    });

    testWidgets('etkileşim yok: InkWell/GestureDetector içermez', (t) async {
      await t.pumpWidget(_app(_chip(pulse: true)));
      await t.pump();
      for (final type in [InkWell, GestureDetector, IconButton]) {
        expect(
          find.descendant(
            of: find.byType(StatusChip),
            matching: find.byType(type),
          ),
          findsNothing,
          reason: '$type',
        );
      }
      await t.pumpAndSettle();
    });
  });

  group('StatusChip: taşma matrisi', () {
    Widget chips() => Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          _chip(label: 'Çevrimiçi', pulse: true),
          _chip(label: 'Yerel Ağ', tone: AppTone.warning),
          _chip(label: 'Çevrimdışı', tone: AppTone.danger),
          _chip(label: 'Cihaz Yok', tone: AppTone.neutral),
          _chip(
            label: 'Onay Bekliyor',
            tone: AppTone.warning,
            icon: Icons.schedule_rounded,
          ),
          _chip(
            label: 'Çevrimiçi (Bulut) - çok uzun bir durum etiketi, kırpılmalı',
            tone: AppTone.info,
            icon: Icons.cloud_done_rounded,
          ),
        ],
      ),
    );

    testWidgets('tüm rozetler x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(t, chips(), width: width, scale: scale, dark: dark);
        final chipsFinder = find.byType(StatusChip);
        expect(chipsFinder, findsNWidgets(6));
        for (var i = 0; i < 6; i++) {
          final size = t.getSize(chipsFinder.at(i));
          expect(
            size.width,
            lessThanOrEqualTo(width - 2 * AppSpace.lg + 0.01),
            reason: 'rozet $i genişliği ($width x $scale dark=$dark)',
          );
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('hareket azaltma ile de taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, chips(), reduce: true);
      expect(find.byType(StatusChip), findsNWidgets(6));
    });
  });
}
