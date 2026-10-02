// FAZ 5 / A1a: AnimatedCount, StaggeredEntry ve Pop widget testleri.
//
// Durumlar, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu), hareket azaltmada tek
// pump, pumpAndSettle'ın bitmesi (kararlı durumda ticker yok) ve Semantics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/page_transitions.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

/// [scope] altındaki ilk Opacity'nin değeri.
double _opacity(WidgetTester t, Finder scope) {
  final f = find.descendant(of: scope, matching: find.byType(Opacity)).first;
  return t.widget<Opacity>(f).opacity;
}

/// [scope] altındaki ilk Transform'un ötelemesi (y) ve ölçeği.
Matrix4 _transform(WidgetTester t, Finder scope) {
  final f = find.descendant(of: scope, matching: find.byType(Transform)).first;
  return t.widget<Transform>(f).transform;
}

/// Ekranda görünen sayaç metni.
String _countText(WidgetTester t) => t
    .widget<Text>(
      find.descendant(
        of: find.byType(AnimatedCount),
        matching: find.byType(Text),
      ),
    )
    .data!;

int _countValue(WidgetTester t) =>
    int.parse(RegExp(r'\d+').firstMatch(_countText(t))!.group(0)!);

Widget _count(
  int value, {
  String prefix = '',
  String suffix = '',
  TextStyle? style,
}) => AnimatedCount(value: value, prefix: prefix, suffix: suffix, style: style);

void main() {
  group('AnimatedCount', () {
    testWidgets('ilk karede animasyonsuz: doğrudan değer görünür', (t) async {
      await t.pumpWidget(harnessApp(Center(child: _count(3, suffix: ' Kapı'))));
      expect(find.text('3 Kapı'), findsOneWidget);
      expect(
        t.binding.transientCallbackCount,
        0,
        reason: 'ilk kurulumda ticker yok',
      );
    });

    testWidgets('değer artınca 320 ms akar: ara değerler ve son değer', (
      t,
    ) async {
      await t.pumpWidget(harnessApp(Center(child: _count(3))));
      await t.pumpWidget(harnessApp(Center(child: _count(8))));
      expect(_countValue(t), 3, reason: 'animasyon başında eski değer');
      final seen = <int>[];
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 60));
        seen.add(_countValue(t));
      }
      for (var i = 1; i < seen.length; i++) {
        expect(
          seen[i],
          greaterThanOrEqualTo(seen[i - 1]),
          reason: 'artan sayı geri gitmez: $seen',
        );
      }
      expect(
        seen.any((v) => v > 3 && v < 8),
        isTrue,
        reason: 'ara değer görülmeli: $seen',
      );
      await t.pumpAndSettle();
      expect(_countValue(t), 8);
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets(
      'değer azalınca da akar; hızlı yeniden hedefleme geri sıçramaz',
      (t) async {
        await t.pumpWidget(harnessApp(Center(child: _count(10))));
        await t.pumpWidget(harnessApp(Center(child: _count(2))));
        await t.pump(const Duration(milliseconds: 100));
        final mid = _countValue(t);
        expect(mid, lessThan(10));
        expect(mid, greaterThan(2));
        // Yarıda yeni hedef: görünen değerden devam eder (10'a geri sıçramaz).
        await t.pumpWidget(harnessApp(Center(child: _count(20))));
        expect(_countValue(t), inInclusiveRange(2, mid));
        await t.pumpAndSettle();
        expect(_countValue(t), 20);
      },
    );

    testWidgets(
      'hareket azaltma: tek pump son değeri gösterir ve ticker çalışmaz',
      (t) async {
        await t.pumpWidget(harnessApp(Center(child: _count(3)), reduce: true));
        await t.pumpWidget(harnessApp(Center(child: _count(8)), reduce: true));
        await t.pump();
        expect(_countValue(t), 8);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('pumpAndSettle biter (sonsuz animasyon yok)', (t) async {
      await t.pumpWidget(harnessApp(Center(child: _count(1))));
      await t.pumpWidget(harnessApp(Center(child: _count(99))));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('önek/sonek, tabular rakam ve verilen stil korunur', (t) async {
      await t.pumpWidget(
        harnessApp(
          Center(
            child: _count(
              3,
              prefix: '(',
              suffix: ')',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.red,
              ),
            ),
          ),
        ),
      );
      expect(find.text('(3)'), findsOneWidget);
      final text = t.widget<Text>(find.text('(3)'));
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(text.style!.fontWeight, FontWeight.w800);
      expect(text.style!.color, Colors.red);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('stil verilmezse ortam metin stilini miras alır', (t) async {
      await t.pumpWidget(
        harnessApp(
          Center(
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 20, color: Colors.green),
              child: _count(5),
            ),
          ),
        ),
      );
      final ctx = t.element(find.text('5'));
      final style = DefaultTextStyle.of(
        ctx,
      ).style.merge(t.widget<Text>(find.text('5')).style);
      expect(style.fontSize, 20);
      expect(style.color, Colors.green);
    });

    testWidgets('dar kutuda tek satır + elips: taşma yok', (t) async {
      await t.pumpWidget(
        harnessApp(
          Center(
            child: SizedBox(
              width: 40,
              child: _count(123456789, suffix: ' geçiş kaydı'),
            ),
          ),
          scale: 2.0,
        ),
      );
      expect(t.takeException(), isNull);
      expect(
        t.getSize(find.byType(AnimatedCount)).width,
        lessThanOrEqualTo(40),
      );
    });

    testWidgets(
      'Semantics: akış sırasında bile etiket HEDEF değerdir (ara değer okunmaz)',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          harnessApp(Center(child: _count(3, suffix: ' Kapı'))),
        );
        await t.pumpWidget(
          harnessApp(Center(child: _count(8, suffix: ' Kapı'))),
        );
        await t.pump(const Duration(milliseconds: 60));
        expect(
          _countValue(t),
          lessThan(8),
          reason: 'görünen metin hâlâ akıyor',
        );
        expect(find.bySemanticsLabel('8 Kapı'), findsOneWidget);
        expect(find.bySemanticsLabel('3 Kapı'), findsNothing);
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel('8 Kapı'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('Semantics: etiket görünen metindir', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(harnessApp(Center(child: _count(3, suffix: ' Kapı'))));
      expect(find.bySemanticsLabel('3 Kapı'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('taşma matrisi: 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Wrap(
              spacing: AppSpace.sm,
              children: [
                AnimatedCount(value: 2, suffix: ' Kapı'),
                AnimatedCount(value: 3, prefix: '(', suffix: ')'),
                AnimatedCount(
                  value: 128,
                  prefix: 'Toplam ',
                  suffix: ' geçiş kaydı bulundu',
                ),
              ],
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(
          find.text('2 Kapı'),
          findsOneWidget,
          reason: '$width x $scale dark=$dark',
        );
      });
    });
  });

  group('StaggeredEntry', () {
    Widget item(int i, {Key? key, Widget? child}) => StaggeredEntry(
      key: key,
      index: i,
      child: child ?? SizedBox(height: 48, child: Text('Öğe $i')),
    );

    testWidgets(
      'index 0: görünmez + 12 dp aşağıda başlar, 200 ms sonra tamamdır',
      (t) async {
        await t.pumpWidget(harnessApp(Center(child: item(0))));
        final scope = find.byType(StaggeredEntry);
        expect(_opacity(t, scope), 0);
        expect(_transform(t, scope).getTranslation().y, closeTo(12, 1e-9));
        await t.pump(const Duration(milliseconds: 100));
        final mid = _opacity(t, scope);
        expect(mid, greaterThan(0));
        expect(mid, lessThan(1));
        expect(
          _transform(t, scope).getTranslation().y,
          inExclusiveRange(0, 12),
        );
        await t.pump(const Duration(milliseconds: 120));
        expect(_opacity(t, scope), 1);
        expect(_transform(t, scope).getTranslation().y, 0);
      },
    );

    testWidgets('kademe: öğe başına 30 ms gecikme, toplam <= 440 ms', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(Column(children: [for (var i = 0; i < 8; i++) item(i)])),
      );
      Finder at(int i) =>
          find.byWidgetPredicate((w) => w is StaggeredEntry && w.index == i);
      // 3. öğe 90 ms sonra başlar.
      await t.pump(const Duration(milliseconds: 80));
      expect(_opacity(t, at(3)), 0, reason: '80 ms: 3. öğe henüz başlamadı');
      expect(_opacity(t, at(0)), greaterThan(0));
      await t.pump(const Duration(milliseconds: 40)); // 120 ms
      final ops = [for (var i = 0; i < 8; i++) _opacity(t, at(i))];
      for (var i = 1; i < ops.length; i++) {
        expect(
          ops[i],
          lessThanOrEqualTo(ops[i - 1]),
          reason: 'gecikme arttıkça opaklık düşer: $ops',
        );
      }
      expect(ops.first, greaterThan(ops[3]));
      // 7. öğe: 210 ms gecikme + 200 ms = 410 ms; 440 ms sonra hepsi tamam.
      await t.pump(const Duration(milliseconds: 320)); // 440 ms
      for (var i = 0; i < 8; i++) {
        expect(_opacity(t, at(i)), 1, reason: 'öğe $i');
        expect(_transform(t, at(i)).getTranslation().y, 0);
      }
      expect(
        t.binding.transientCallbackCount,
        0,
        reason: 'kararlı durumda ticker yok',
      );
    });

    testWidgets('index >= 8: hareketsiz, doğrudan görünür, ticker yok', (
      t,
    ) async {
      await t.pumpWidget(harnessApp(Column(children: [item(8), item(20)])));
      for (final i in [8, 20]) {
        final scope = find.byWidgetPredicate(
          (w) => w is StaggeredEntry && w.index == i,
        );
        expect(_opacity(t, scope), 1);
        expect(_transform(t, scope).getTranslation().y, 0);
      }
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('hareket azaltma: ilk karede tamdır, ticker yok', (t) async {
      await t.pumpWidget(
        harnessApp(Column(children: [item(0), item(5)]), reduce: true),
      );
      expect(_opacity(t, find.byType(StaggeredEntry).first), 1);
      expect(_opacity(t, find.byType(StaggeredEntry).last), 1);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('hareket giriş sürerken azaltılırsa öğe hemen tamamlanır', (
      t,
    ) async {
      await t.pumpWidget(harnessApp(Column(children: [item(2)])));
      await t.pump(const Duration(milliseconds: 100));
      expect(_opacity(t, find.byType(StaggeredEntry)), lessThan(1));
      await t.pumpWidget(harnessApp(Column(children: [item(2)]), reduce: true));
      expect(_opacity(t, find.byType(StaggeredEntry)), 1);
      expect(_transform(t, find.byType(StaggeredEntry)).getTranslation().y, 0);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('pumpAndSettle biter', (t) async {
      await t.pumpWidget(
        harnessApp(Column(children: [for (var i = 0; i < 12; i++) item(i)])),
      );
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'yenilemede tekrar oynamaz: ebeveyn yeniden kurulunca opaklık 1 kalır',
      (t) async {
        await t.pumpWidget(harnessApp(Column(children: [item(0)])));
        await t.pumpAndSettle();
        await t.pumpWidget(
          harnessApp(
            Column(children: [item(0, child: const Text('yenilendi'))]),
          ),
        );
        expect(find.text('yenilendi'), findsOneWidget);
        expect(_opacity(t, find.byType(StaggeredEntry)), 1);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'alt ağaç State\'i sıra 7 <-> 8 geçişinde kaybolmaz (yapı sabit)',
      (t) async {
        final key = GlobalKey<_CounterState>();
        Widget build(int index) => harnessApp(
          Column(
            children: [
              StaggeredEntry(
                index: index,
                child: _Counter(key: key),
              ),
            ],
          ),
        );
        await t.pumpWidget(build(7));
        await t.pumpAndSettle();
        key.currentState!.bump();
        key.currentState!.bump();
        await t.pump();
        expect(find.text('sayaç 2'), findsOneWidget);
        await t.pumpWidget(build(8)); // sıra kaydı: 7 -> 8
        expect(key.currentState!.count, 2, reason: 'State korunmalı');
        await t.pumpWidget(build(3)); // 8 -> 3 (artık hareketlenmez; ağaç aynı)
        await t.pumpAndSettle();
        expect(key.currentState!.count, 2);
        expect(find.text('sayaç 2'), findsOneWidget);
        expect(_opacity(t, find.byType(StaggeredEntry)), 1);
      },
    );

    testWidgets('Semantics ilk karede (opaklık 0 iken) de açıktır', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(harnessApp(Column(children: [item(2)])));
      expect(_opacity(t, find.byType(StaggeredEntry)), 0);
      expect(find.bySemanticsLabel('Öğe 2'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('çocuğun boyutunu ve dokunma hedefini değiştirmez (>= 44 dp)', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          Column(
            children: [
              item(0),
              const SizedBox(height: 48, child: Text('düz')),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(StaggeredEntry)).height, 48);
      expect(
        t.getSize(find.byType(StaggeredEntry)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('animasyon sürerken kaldırmak hata vermez', (t) async {
      await t.pumpWidget(harnessApp(Column(children: [item(5)])));
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpWidget(harnessApp(const SizedBox()));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
    });

    testWidgets('negatif sıra güvenli (0 gibi)', (t) async {
      await t.pumpWidget(harnessApp(Column(children: [item(-3)])));
      await t.pumpAndSettle();
      expect(_opacity(t, find.byType(StaggeredEntry)), 1);
    });

    testWidgets('taşma matrisi: 10 öğeli liste', (t) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              children: [
                for (var i = 0; i < 10; i++)
                  StaggeredEntry(
                    index: i,
                    child: Card(
                      child: ListTile(
                        title: Text('Site $i: Güneş Sitesi Ana Giriş Kapısı'),
                        subtitle: const Text('Çevrimiçi'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(
          find.text('Site 0: Güneş Sitesi Ana Giriş Kapısı'),
          findsOneWidget,
          reason: '$width x $scale dark=$dark',
        );
      });
    });
  });

  group('Pop', () {
    testWidgets(
      'ilk kurulum: 0,9 ölçek + saydam başlar, 200 ms sonra tamamdır',
      (t) async {
        await t.pumpWidget(
          harnessApp(const Center(child: Pop(child: Text('Merhaba')))),
        );
        final scope = find.byType(Pop);
        expect(_opacity(t, scope), 0);
        expect(_transform(t, scope).storage[0], closeTo(0.9, 1e-9));
        await t.pump(const Duration(milliseconds: 100));
        expect(_opacity(t, scope), inExclusiveRange(0, 1.0000001));
        await t.pump(const Duration(milliseconds: 150));
        expect(_opacity(t, scope), 1);
        expect(_transform(t, scope).storage[0], closeTo(1, 1e-9));
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'anahtar değişince eski çocuk HEMEN kalkar, yalnız yeni çocuk belirir',
      (t) async {
        Widget pop(String text) => harnessApp(
          Center(
            child: Pop(key: ValueKey(text), child: Text(text)),
          ),
        );
        await t.pumpWidget(pop('A'));
        await t.pumpAndSettle();
        expect(find.text('A'), findsOneWidget);
        await t.pumpWidget(pop('B'));
        expect(
          find.text('A'),
          findsNothing,
          reason: 'eski çocuk ağaçta kalmamalı',
        );
        expect(find.text('B'), findsOneWidget);
        expect(find.byType(Pop), findsOneWidget);
        expect(
          _opacity(t, find.byType(Pop)),
          0,
          reason: 'yeni çocuk saydam başlar',
        );
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 60));
          expect(
            find.byType(Text),
            findsOneWidget,
            reason: 'her karede tek metin',
          );
        }
        expect(_opacity(t, find.byType(Pop)), 1);
      },
    );

    testWidgets('aynı anahtarla yeniden kurma animasyonu tekrarlamaz', (
      t,
    ) async {
      Widget pop(String text) => harnessApp(
        Center(
          child: Pop(key: const ValueKey('x'), child: Text(text)),
        ),
      );
      await t.pumpWidget(pop('A'));
      await t.pumpAndSettle();
      await t.pumpWidget(pop('A2'));
      expect(find.text('A2'), findsOneWidget);
      expect(_opacity(t, find.byType(Pop)), 1);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('hareket azaltma: tek pump son durum, ticker yok', (t) async {
      await t.pumpWidget(
        harnessApp(
          const Center(child: Pop(child: Text('Merhaba'))),
          reduce: true,
        ),
      );
      expect(_opacity(t, find.byType(Pop)), 1);
      expect(_transform(t, find.byType(Pop)).storage[0], closeTo(1, 1e-9));
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('pumpAndSettle biter', (t) async {
      await t.pumpWidget(
        harnessApp(const Center(child: Pop(child: Text('Merhaba')))),
      );
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('Semantics ilk karede (opaklık 0 iken) de açıktır', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        harnessApp(const Center(child: Pop(child: Text('Durum')))),
      );
      expect(_opacity(t, find.byType(Pop)), 0);
      expect(find.bySemanticsLabel('Durum'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('taşma matrisi: uzun durum metni', (t) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Pop(
              child: Text(
                'Kapı açma komutu gönderildi, cihazdan yanıt bekleniyor lütfen bekleyin',
              ),
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(
          find.byType(Pop),
          findsOneWidget,
          reason: '$width x $scale dark=$dark',
        );
        expect(_opacity(t, find.byType(Pop)), 1);
      });
    });
  });

  group('Dokunma hedefi: sarmalayıcılar hedefi bozmaz (>= 44 dp)', () {
    Widget tappable(String text, VoidCallback onTap) => SizedBox(
      width: 160,
      height: 48,
      child: InkWell(
        onTap: onTap,
        child: Center(child: Text(text)),
      ),
    );

    testWidgets(
      'Pop ve StaggeredEntry içindeki düğme animasyon sürerken de dokunulur',
      (t) async {
        var popTaps = 0;
        var staggerTaps = 0;
        await t.pumpWidget(
          harnessApp(
            Column(
              children: [
                Pop(child: tappable('pop', () => popTaps++)),
                StaggeredEntry(
                  index: 2,
                  child: tappable('stagger', () => staggerTaps++),
                ),
              ],
            ),
          ),
        );
        // İlk karede (opaklık 0) bile hedef yerinde ve dokunulabilir.
        await t.tap(find.text('pop'));
        await t.tap(find.text('stagger'));
        await t.pump(const Duration(milliseconds: 40));
        await t.tap(find.text('pop'));
        await t.tap(find.text('stagger'));
        await t.pumpAndSettle();
        await t.tap(find.text('pop'));
        await t.tap(find.text('stagger'));
        await t.pump();
        expect(popTaps, 3);
        expect(staggerTaps, 3);
        expect(t.getSize(find.byType(Pop)).height, greaterThanOrEqualTo(44));
        expect(
          t.getSize(find.byType(StaggeredEntry)).height,
          greaterThanOrEqualTo(44),
        );
      },
    );

    testWidgets('PageEntry sarmalı içerik de dokunulur ve boyutu değişmez', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(
        harnessApp(PageEntry(child: tappable('sayfa', () => taps++))),
      );
      await t.tap(find.text('sayfa'));
      await t.pumpAndSettle();
      await t.tap(find.text('sayfa'));
      expect(taps, 2);
      expect(
        t.getSize(find.byType(PageEntry)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('sayaç $count');
}
