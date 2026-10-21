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

  // İP-1C bağımsız inceleme (karar G6 + G7): büyük diyalog parçaları da sade kurala bağlıdır. Durum zemini
  // BOYANMAZ; mavi yalnız bağlantı ve odakta (bilgi / birincil / mor tonlu panel ve hap mavi-mor boyanmaz).
  testWidgets(
    'sade stil (G7): DialogPanel ve DialogMetaPill zemini her tonda nötr soluk yüzey; ton panelde yalnız kenarda '
    '(durum tonları), hapta yalnız metin ve simgede (açık + koyu)',
    (t) async {
      for (final dark in const <bool>[false, true]) {
        final p = dark ? AppPalette.dark : AppPalette.light;
        for (final tone in <AppTone?>[null, ...AppTone.values]) {
          final name = '${tone?.name ?? 'nötr'} / ${dark ? 'koyu' : 'açık'}';
          final label = 'Etiket ${tone?.name ?? 'nötr'}';
          await pumpAt(
            t,
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DialogPanel(tone: tone, child: const Text('Panel')),
                  const SizedBox(height: AppSpace.sm),
                  DialogMetaPill(label, tone: tone, icon: Icons.info_outline_rounded),
                ],
              ),
            ),
            width: 360,
            scale: 1.0,
            dark: dark,
          );

          final panel = t
              .widget<DecoratedBox>(
                find.descendant(of: find.byType(DialogPanel), matching: find.byType(DecoratedBox)).first,
              )
              .decoration as BoxDecoration;
          expect(panel.color, p.surfaceMuted, reason: 'panel zemini $name');
          expect(
            (panel.border! as Border).top.color,
            tone != null && tone.isStatus ? tone.hue.withValues(alpha: 0.4) : p.border,
            reason: 'panel kenarı $name',
          );

          final pill = t
              .widget<DecoratedBox>(
                find.descendant(of: find.byType(DialogMetaPill), matching: find.byType(DecoratedBox)).first,
              )
              .decoration as BoxDecoration;
          expect(pill.color, p.surfaceMuted, reason: 'hap zemini $name');
          expect((pill.border! as Border).top.color, p.border, reason: 'hap kenarı $name');
          final ink = tone == null ? p.text : tone.sign(p);
          expect(t.widget<Text>(find.text(label)).style!.color, ink, reason: 'hap metni $name');
          expect(
            t.widget<Icon>(find.descendant(of: find.byType(DialogMetaPill), matching: find.byType(Icon))).color,
            ink,
            reason: 'hap simgesi $name',
          );
          expect(_contrast(ink, p.surfaceMuted), greaterThanOrEqualTo(4.5), reason: name);
        }
      }
    },
  );

  testWidgets(
    'sade stil (G6): dialogTonalButtonStyle ikincil düğmedir: yüzey zemin + 1 px palet kenarı + başlık metni '
    '(durum tonunda ink); tonlu / mavi zemin yok, en az 48 dp (açık + koyu)',
    (t) async {
      for (final dark in const <bool>[false, true]) {
        final p = dark ? AppPalette.dark : AppPalette.light;
        late BuildContext ctx;
        await pumpAt(
          t,
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
          width: 360,
          scale: 1.0,
          height: 200,
          dark: dark,
        );
        final none = <WidgetState>{};
        const disabled = <WidgetState>{WidgetState.disabled};
        for (final tone in AppTone.values) {
          final name = '${tone.name} / ${dark ? 'koyu' : 'açık'}';
          final s = dialogTonalButtonStyle(ctx, tone: tone);
          expect(s.backgroundColor!.resolve(none), p.surface, reason: name);
          expect(s.foregroundColor!.resolve(none), tone.isStatus ? tone.ink(p) : p.text, reason: name);
          expect(s.side!.resolve(none), BorderSide(color: p.border), reason: name);
          expect(s.minimumSize!.resolve(none)!.height, greaterThanOrEqualTo(48), reason: name);
          expect(s.foregroundColor!.resolve(disabled), p.textSecondary, reason: name);
          expect(s.backgroundColor!.resolve(disabled), p.surfaceMuted, reason: name);
        }
      }
    },
  );

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
