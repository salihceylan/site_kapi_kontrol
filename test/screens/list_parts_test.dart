// FAZ 5 / A2-G3: liste ortak parçaları (list_parts.dart) ve ona bağlı kartların görsel dil testleri.
//
// Ortak parçanın API'si ve davranışı DEĞİŞMEZ (IconTile büyük yazıda gizlenir, PageHeaderCard eylemi
// dar/geniş ekranda yerleştirir, düğme stilleri ilgili düğme tipinde kalır); yalnız görünüm cilalanır:
// ikon rozeti (IconOrb), hero başlık kartı, düz ikincil düğme, onay haptiği. AGENTS.md kural 6: taşma
// matrisi (320x640 x2,0 ve 360x640 x1,5; açık + koyu).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/gloss.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/individual_apartment_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/setup_option_card.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

const String _longTitle =
    'Çok Uzun Bir Sayfa Başlığı Konut Yapı Kooperatifleri Yönetim Ekranı';

Widget _header({IconData? icon, AppTone? tone, Widget? action}) => SizedBox(
  width: double.infinity,
  child: PageHeaderCard(
    title: _longTitle,
    icon: icon,
    tone: tone ?? AppTone.primary,
    action: action,
  ),
);

Widget _action() => ElevatedButton.icon(
  onPressed: () {},
  icon: const Icon(Icons.add_business_outlined),
  label: const Text('Yeni Kayıt'),
);

void main() {
  group('IconTile (cilalı ikon rozeti)', () {
    testWidgets(
      'squircle IconOrb: ton, boyut ve sağ boşluk korunur; anlamsal ağaçta yok',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(
          t,
          const Row(
            children: [
              IconTile(
                icon: Icons.apartment_rounded,
                tone: AppTone.violet,
                size: 40,
                gap: AppSpace.md,
              ),
              Text('Ad'),
            ],
          ),
          width: 360,
          scale: 1.0,
          height: 400,
        );
        final orb = t.widget<IconOrb>(find.byType(IconOrb));
        expect(orb.tone, AppTone.violet);
        expect(orb.size, 40);
        expect(orb.shape, IconOrbShape.squircle);
        expect(orb.glow, isFalse);
        expect(t.getSize(find.byType(IconTile)), const Size(40 + AppSpace.md, 40));
        expect(
          t.getTopLeft(find.text('Ad')).dx - t.getTopRight(find.byType(IconOrb)).dx,
          closeTo(AppSpace.md, 0.5),
          reason: 'boşluk rozetin sağında',
        );
        final labels = t.semantics
            .simulatedAccessibilityTraversal()
            .map((n) => n.getSemanticsData().label)
            .where((l) => l.isNotEmpty)
            .toList();
        expect(labels, <String>['Ad'], reason: 'rozet dekoratif');
        handle.dispose();
      },
    );

    testWidgets('varsayılan boyut 44; iconSize geriye dönük uyumluluk için kabul edilir', (
      t,
    ) async {
      await pumpAt(
        t,
        const Row(
          children: [
            IconTile(icon: Icons.home_rounded),
            IconTile(icon: Icons.home_rounded, iconSize: 20),
          ],
        ),
        width: 360,
        scale: 1.0,
        height: 400,
      );
      final orbs = t.widgetList<IconOrb>(find.byType(IconOrb)).toList();
      expect(orbs, hasLength(2));
      expect(orbs.map((o) => o.size).toList(), <double>[44, 44]);
      expect(orbs.map((o) => o.tone).toSet(), <AppTone>{AppTone.primary});
    });

    testWidgets('büyük yazıda (2,0x) rozet ve boşluğu birlikte gizlenir', (
      t,
    ) async {
      await pumpAt(
        t,
        const Row(
          children: [
            IconTile(icon: Icons.home_rounded, gap: AppSpace.md),
            Text('Ad'),
          ],
        ),
        width: 320,
        scale: 2.0,
        height: 400,
      );
      expect(find.byType(IconOrb), findsNothing);
      expect(t.getSize(find.byType(IconTile)), Size.zero);
    });
  });

  group('PageHeaderCard (hero başlık kartı)', () {
    testWidgets('ikonsuz: yalnız başlık; yine de hero (seviye 2) yüzey', (
      t,
    ) async {
      await pumpAt(
        t,
        _header(),
        width: 360,
        scale: 1.0,
        height: 600,
      );
      expect(find.byType(IconOrb), findsNothing);
      expect(t.widget<AppCard>(find.byType(AppCard)).level, 2);
      expect(find.text(_longTitle), findsOneWidget);
    });

    testWidgets('ikonlu: 48 dp squircle rozet başlığın solunda; ton verilebilir', (
      t,
    ) async {
      await pumpAt(
        t,
        _header(icon: Icons.location_city_rounded, tone: AppTone.violet),
        width: 360,
        scale: 1.0,
        height: 600,
      );
      final orb = t.widget<IconOrb>(find.byType(IconOrb));
      expect(orb.icon, Icons.location_city_rounded);
      expect(orb.tone, AppTone.violet);
      expect(orb.size, 48);
      expect(orb.shape, IconOrbShape.squircle);
      expect(
        t.getTopRight(find.byType(IconOrb)).dx,
        lessThan(t.getTopLeft(find.text(_longTitle)).dx),
        reason: 'rozet başlığın solunda',
      );
    });

    testWidgets('dar ekranda (< 680) eylem başlığın altında tam genişlik; geniş ekranda sağda', (
      t,
    ) async {
      await pumpAt(
        t,
        _header(icon: Icons.apartment_rounded, action: _action()),
        width: 360,
        scale: 1.0,
        height: 800,
      );
      final card = t.getSize(find.byType(AppCard)).width;
      final button = find.byType(ElevatedButton);
      expect(
        t.getTopLeft(button).dy,
        greaterThanOrEqualTo(t.getBottomLeft(find.text(_longTitle)).dy),
        reason: 'dar: eylem başlığın altında',
      );
      expect(
        t.getSize(button).width,
        closeTo(card - 2 * AppSpace.lg, 0.5),
        reason: 'dar: eylem tam genişlik',
      );

      await pumpAt(
        t,
        _header(icon: Icons.apartment_rounded, action: _action()),
        width: 820,
        scale: 1.0,
        height: 800,
      );
      expect(
        t.getTopLeft(find.byType(ElevatedButton)).dx,
        greaterThan(t.getTopRight(find.text(_longTitle)).dx - 0.5),
        reason: 'geniş: eylem başlığın sağında',
      );
      expect(
        (t.getCenter(find.byType(ElevatedButton)).dy -
                t.getCenter(find.text(_longTitle)).dy)
            .abs(),
        lessThan(t.getSize(find.text(_longTitle)).height),
        reason: 'geniş: aynı satırda',
      );
    });

    testWidgets('büyük yazıda rozet gizlenir; başlık ve eylem kalır', (t) async {
      await pumpAt(
        t,
        _header(icon: Icons.apartment_rounded, action: _action()),
        width: 320,
        scale: 2.0,
        height: 1200,
      );
      expect(find.byType(IconOrb), findsNothing);
      expect(find.text(_longTitle), findsOneWidget);
      expect(find.text('Yeni Kayıt'), findsOneWidget);
    });

    g4LayoutMatrix('taşma matrisi: uzun başlık + rozet + eylem', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        _header(icon: Icons.apartment_rounded, action: _action()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      expect(find.text(_longTitle), findsOneWidget);
      expect(find.text('Yeni Kayıt'), findsOneWidget);
    });
  });

  group('Düğme stilleri ve haptik', () {
    testWidgets(
      'tonalActionStyle: ElevatedButton düz (cilasız); tema ve filledToneStyle dolu düğmesi cilalı',
      (t) async {
        await pumpAt(
          t,
          Builder(
            builder: (c) => Wrap(
              spacing: AppSpace.sm,
              children: [
                ElevatedButton(
                  onPressed: () {},
                  style: tonalActionStyle(c),
                  child: const Text('tonal'),
                ),
                OutlinedButton(
                  onPressed: () {},
                  style: tonalActionStyle(c, tone: AppTone.warning),
                  child: const Text('ince'),
                ),
                ElevatedButton(onPressed: () {}, child: const Text('dolu')),
                ElevatedButton(
                  onPressed: () {},
                  style: filledToneStyle(c, tone: AppTone.success),
                  child: const Text('tonlu dolu'),
                ),
              ],
            ),
          ),
          width: 360,
          scale: 1.0,
          height: 600,
        );
        Finder gloss(Type button, String label) => find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(button)),
          matching: find.byType(Gloss),
        );
        expect(gloss(ElevatedButton, 'tonal'), findsNothing);
        expect(gloss(OutlinedButton, 'ince'), findsNothing);
        expect(gloss(ElevatedButton, 'dolu'), findsOneWidget);
        expect(gloss(ElevatedButton, 'tonlu dolu'), findsOneWidget);
        // Düğme tipi ve tıklanabilirlik değişmez.
        expect(
          t.widget<ElevatedButton>(
            find.ancestor(
              of: find.text('tonal'),
              matching: find.byType(ElevatedButton),
            ),
          ).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('withLightHaptic: null -> null; dokununca hafif haptik + geri çağrı', (
      t,
    ) async {
      expect(withLightHaptic(null), isNull);
      final haptics = recordHaptics(t);
      var calls = 0;
      final wrapped = withLightHaptic(() => calls++);
      expect(wrapped, isNotNull);
      expect(haptics, isEmpty, reason: 'sarmalayıcı kurulunca haptik yok');
      wrapped!();
      await t.pump();
      expect(calls, 1);
      expect(haptics, <String>['HapticFeedbackType.lightImpact']);
    });
  });

  group('ListSkeleton', () {
    testWidgets('ikon yer tutucusu squircle: IconTile rozetiyle aynı biçim', (
      t,
    ) async {
      await pumpAt(
        t,
        const ListSkeleton(rows: 2),
        width: 360,
        scale: 1.0,
        height: 600,
      );
      final boxes = t
          .widgetList<SkeletonBox>(find.byType(SkeletonBox))
          .where((b) => b.width == 44)
          .toList();
      expect(boxes, hasLength(2));
      for (final box in boxes) {
        expect(box.height, 44);
        expect(box.radius, closeTo(44 * 0.30, 0.5));
      }
    });
  });

  group('IndividualApartmentCard (rol tonlu cilalı başlık rozeti)', () {
    Widget card({bool admin = true}) => SizedBox(
      width: double.infinity,
      child: IndividualApartmentCard(
        apartment: g4Apartment(admin: admin),
        onRemoveMember: (_) {},
      ),
    );

    testWidgets(
      'başlık rozeti rol tonunda: yönetici=warning, üye=primary; 48 dp squircle; satır avatarları sade kalır',
      (t) async {
        for (final (admin, tone) in const <(bool, AppTone)>[
          (true, AppTone.warning),
          (false, AppTone.primary),
        ]) {
          await pumpAt(
            t,
            card(admin: admin),
            width: 360,
            scale: 1.0,
            height: 1200,
          );
          final orb = t.widget<IconOrb>(find.byType(IconOrb));
          expect(orb.tone, tone, reason: admin ? 'yönetici' : 'üye');
          expect(orb.icon, Icons.home_work_rounded);
          expect(orb.size, 48);
          expect(orb.shape, IconOrbShape.squircle);
          expect(orb.glow, isFalse);
          expect(
            find.byType(CircleAvatar),
            findsNWidgets(2),
            reason: 'üye satırları sade avatar (her satıra parlak rozet yok)',
          );
        }
      },
    );

    testWidgets('büyük yazıda rozet gizlenir; site adı, birim ve rol rozeti kalır', (
      t,
    ) async {
      await pumpAt(t, card(), width: 320, scale: 2.0, height: 2400);
      expect(find.byType(IconOrb), findsNothing);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(find.text('A Blok • Daire 12'), findsOneWidget);
      expect(find.textContaining('Daire Yöneticisi'), findsOneWidget);
    });

    g4LayoutMatrix('taşma matrisi: yönetici ve üye kartı', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        Column(children: [card(), card(admin: false)]),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      expect(find.text('Güneş Sitesi'), findsNWidgets(2));
    });
  });

  group('SetupOptionCard (hero seçenek kartı)', () {
    g4LayoutMatrix('taşma matrisi: uzun başlık, rozet ve açıklama', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        SizedBox(
          width: double.infinity,
          child: SetupOptionCard(
            tone: AppTone.success,
            icon: Icons.key_rounded,
            title: 'Çok Uzun Bir Kurulum Seçeneği Başlığı Burada Yer Alır',
            badge: 'Uzun Bir Rozet Metni',
            description:
                'Bu açıklama metni birkaç satıra sarar ve hiçbir koşulda kırpılmaz; büyük yazıda rozet metnin üstüne geçer.',
            action: ElevatedButton(onPressed: () {}, child: const Text('Eylem')),
          ),
        ),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      expect(find.byType(IconOrb), findsOneWidget);
      expect(find.text('Eylem'), findsOneWidget);
    });
  });
}
