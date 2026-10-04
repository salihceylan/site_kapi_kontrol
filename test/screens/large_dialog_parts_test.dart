// "Büyük diyalog" ortak parçalarının (`large_dialog_parts.dart`) testi: taşma matrisi (AGENTS.md kural 6),
// kontrast (metin >= 4,5:1), büyük yazıda rozet bırakma eşiği ve kararlı durumda ticker yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';

import '../design/harness.dart';

const String _long =
    'Çok uzun bir başlık metni: büyük yazıda ve dar ekranda kırpılmadan satırlara sarmalıdır';

/// WCAG göreli parlaklık oranı.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets(
    'parçalar 320/360/412/820 dp x yazı 1,0/1,5/2,0 x açık/koyu temada taşmaz',
    (t) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          const SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DialogPanel(
                    child: DialogSectionTitle(
                      icon: Icons.apartment_rounded,
                      title: _long,
                      subtitle: _long,
                    ),
                  ),
                  SizedBox(height: AppSpace.md),
                  DialogPanel(
                    tone: AppTone.danger,
                    child: Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        DialogMetaPill(
                          _long,
                          tone: AppTone.danger,
                          icon: Icons.block_rounded,
                        ),
                        DialogMetaPill(
                          'A Blok',
                          tone: AppTone.primary,
                          minWidth: 64,
                        ),
                        DialogMetaPill('Daire 12'),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSpace.md),
                  DialogLoadingNote(text: _long),
                  SizedBox(height: AppSpace.md),
                  DialogRowsSkeleton(caption: _long),
                ],
              ),
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
      });
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('hideRowOrbs: yalnız büyük yazıda (>= 1,75x) rozetleri bırakır', (
    t,
  ) async {
    for (final (scale, expected) in <(double, bool)>[
      (1.0, false),
      (1.5, false),
      (1.74, false),
      (1.75, true),
      (2.0, true),
    ]) {
      late bool got;
      await t.pumpWidget(
        harnessApp(
          Builder(
            builder: (context) {
              got = hideRowOrbs(context);
              return const SizedBox.shrink();
            },
          ),
          scale: scale,
        ),
      );
      expect(got, expected, reason: 'yazı ölçeği $scale');
    }
  });

  testWidgets('DialogMetaPill: her ton ve temada metin >= 4,5:1 (zemin = ton tintli yüzey)', (
    t,
  ) async {
    for (final dark in const <bool>[false, true]) {
      final p = dark ? AppPalette.dark : AppPalette.light;
      for (final tone in <AppTone?>[null, ...AppTone.values]) {
        final label = 'Etiket ${tone?.name ?? 'nötr'}';
        await pumpAt(
          t,
          SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.topLeft,
              child: DialogMetaPill(label, tone: tone),
            ),
          ),
          width: 360,
          scale: 1.0,
          dark: dark,
        );

        final text = t.widget<Text>(find.text(label));
        final box = t.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final bg = (box.decoration as BoxDecoration).color!;
        expect(
          _contrast(text.style!.color!, bg),
          greaterThanOrEqualTo(4.5),
          reason: '${tone?.name ?? 'nötr'} / ${dark ? 'koyu' : 'açık'}',
        );
        // Zemin gerçekten opak ve ilgili yüzeyden türemiş (tone null: soluk yüzey).
        expect(bg.a, 1.0);
        if (tone == null) expect(bg, p.surfaceMuted);
      }
    }
  });

  testWidgets(
    'iskelet yalnız yüklenirken ticker çalıştırır; kapsam kalkınca ve hareket azaltmada ticker yok',
    (t) async {
      await t.pumpWidget(
        harnessApp(
          const SingleChildScrollView(
            child: Column(
              children: [
                DialogLoadingNote(text: 'Yükleniyor'),
                DialogRowsSkeleton(),
              ],
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.transientCallbackCount, greaterThan(0));

      // Yükleme bitti: kapsam ağaçtan kalkar, boşta ticker kalmaz.
      await t.pumpWidget(harnessApp(const SizedBox.shrink()));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.transientCallbackCount, 0);

      // Hareket azaltma: iskelet durağan çizilir (shimmer ticker'ı hiç başlamaz).
      await t.pumpWidget(
        harnessApp(const DialogRowsSkeleton(), reduce: true),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
    },
  );
}
