// FAZ 5 / A0: test düzeneğinin (harness.dart) kendi doğrulaması.
//
// Diğer ajanların tüm taşma testleri `pumpAt`'e güvenir: bu dosya, düzeneğin gerçekten ölçü/ölçek/tema
// uyguladığını ve taşmayı YAKALADIĞINI (negatif kontrol) kanıtlar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

void main() {
  group('pumpAt', () {
    testWidgets(
      'genişlik/yükseklik, yazı ölçeği, tema ve hareket azaltma uygulanır',
      (t) async {
        late BuildContext ctx;
        await pumpAt(
          t,
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox(width: double.infinity, height: 10);
            },
          ),
          width: 360,
          height: 700,
          scale: 1.5,
          dark: true,
          reduce: true,
        );
        final mq = MediaQuery.of(ctx);
        expect(mq.size, const Size(360, 700));
        expect(mq.devicePixelRatio, 1.0);
        expect(mq.textScaler.scale(10), 15);
        expect(mq.disableAnimations, isTrue);
        expect(Theme.of(ctx).brightness, Brightness.dark);
        expect(ctx.palette, same(AppPalette.dark));
        // Gövde (SingleChildScrollView) çocuğu kendi boyutuna sarar; tam genişlik isteyen çocuk
        // ekran genişliğini (360) alır.
        expect(
          t
              .getSize(
                find.byWidgetPredicate((w) => w is SizedBox && w.height == 10),
              )
              .width,
          360,
          reason: 'gövde tam genişlik verir',
        );
      },
    );

    testWidgets('varsayılanlar: 320x640, ölçek 2,0, açık tema, hareket açık', (
      t,
    ) async {
      late BuildContext ctx;
      await pumpAt(
        t,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      final mq = MediaQuery.of(ctx);
      expect(mq.size, const Size(320, 640));
      expect(mq.textScaler.scale(10), 20);
      expect(mq.disableAnimations, isFalse);
      expect(Theme.of(ctx).brightness, Brightness.light);
      expect(ctx.palette, same(AppPalette.light));
    });

    testWidgets('negatif kontrol: yatay taşan widget YAKALANIR (TestFailure)', (
      t,
    ) async {
      Object? caught;
      try {
        await pumpAt(
          t,
          const Row(
            children: [
              SizedBox(width: 250, height: 10),
              SizedBox(width: 250, height: 10),
            ],
          ),
          width: 320,
          scale: 1.0,
        );
      } on TestFailure catch (e) {
        caught = e;
      }
      expect(
        caught,
        isA<TestFailure>(),
        reason: 'RenderFlex taşması pumpAt tarafından yakalanmalı',
      );
      expect('$caught', contains('overflowed'));
    });

    testWidgets(
      'negatif kontrol: büyük yazıda taşan Row YAKALANIR, küçük yazıda geçer',
      (t) async {
        Widget row() => const Row(
          children: [Text('Kapıyı Aç Kapıyı Aç'), Text('Kapıyı Aç')],
        );
        await pumpAt(t, row(), width: 820, scale: 1.0); // geçer
        Object? caught;
        try {
          await pumpAt(t, row(), width: 320, scale: 2.0);
        } on TestFailure catch (e) {
          caught = e;
        }
        expect(caught, isA<TestFailure>());
      },
    );

    testWidgets('art arda çağrılarda State sızmaz (her çağrı temiz kurulum)', (
      t,
    ) async {
      var inits = 0;
      Widget probe() => _Probe(onInit: () => inits++);
      await pumpAt(t, probe());
      await pumpAt(t, probe(), width: 360);
      await pumpAt(t, probe(), width: 412, dark: true);
      expect(inits, 3);
    });

    testWidgets(
      'forEachHarnessCell: 4 genişlik x 3 ölçek x 2 tema = 24 hücre, hepsi farklı',
      (t) async {
        final cells = <String>{};
        await forEachHarnessCell((width, scale, dark) async {
          cells.add('$width|$scale|$dark');
        });
        expect(cells, hasLength(24));
        expect(kHarnessWidths, <double>[320, 360, 412, 820]);
        expect(kHarnessScales, <double>[1.0, 1.5, 2.0]);
      },
    );

    testWidgets(
      'harnessApp: ilk kareyi gözlemlemek için ince kabuk (ölçek, tema, hareket)',
      (t) async {
        late BuildContext ctx;
        await t.pumpWidget(
          harnessApp(
            Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
            dark: true,
            reduce: true,
            scale: 1.3,
          ),
        );
        expect(MediaQuery.of(ctx).textScaler.scale(10), closeTo(13, 1e-9));
        expect(MediaQuery.of(ctx).disableAnimations, isTrue);
        expect(Theme.of(ctx).brightness, Brightness.dark);
      },
    );

    testWidgets('recordHaptics: HapticFeedback çağrılarını kaydeder', (
      t,
    ) async {
      final haptics = recordHaptics(t);
      await HapticFeedback.selectionClick();
      await HapticFeedback.mediumImpact();
      await HapticFeedback.lightImpact();
      expect(haptics, <String>[
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 10);
}
