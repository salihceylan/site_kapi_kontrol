// FAZ 5 / A1b (i): AppCard, SectionHeader ve InlineNotice widget testleri.
//
// Durumlar, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu), hareket azaltmada tek pump,
// pumpAndSettle'ın bitmesi, Semantics ve en az 44 dp dokunma hedefi.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

AppPalette _palette(bool dark) => dark ? AppPalette.dark : AppPalette.light;

/// WCAG kontrast oranı ([fg] opak, [bg] opak).
double _contrast(Color fg, Color bg) {
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// pumpAndSettle kaç kare ilerlediğini döndürür (100 ms'lik adımlar): geçen yaklaşık süre.
Future<Duration> _settle(WidgetTester t) async =>
    Duration(milliseconds: await t.pumpAndSettle() * 100);

/// Tam genişlikli kart (Scaffold gövdesi çocuğu sarar; kart gerçek kullanımdaki gibi genişlesin).
Widget _full(Widget child) => SizedBox(width: double.infinity, child: child);

Widget _app(Widget w, {bool dark = false, bool reduce = false}) => harnessApp(
  Align(alignment: Alignment.topLeft, child: w),
  dark: dark,
  reduce: reduce,
);

// --- AppCard yardımcıları -------------------------------------------------------------------

Finder get _cardFinder => find.byType(AppCard);

Material _material(WidgetTester t) => t.widget<Material>(
  find.descendant(of: _cardFinder, matching: find.byType(Material)).first,
);

BoxDecoration _shadowBox(WidgetTester t) =>
    t
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: _cardFinder,
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

RoundedRectangleBorder _shape(WidgetTester t) =>
    _material(t).shape! as RoundedRectangleBorder;

Finder _bar(Color color) => find.descendant(
  of: _cardFinder,
  matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == color),
);

// --- SectionHeader yardımcıları -------------------------------------------------------------

Finder get _headerFinder => find.byType(SectionHeader);

/// Rozetin (hap) DecoratedBox'ı.
Finder get _badge => find.descendant(
  of: _headerFinder,
  matching: find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(AppRadius.pill),
  ),
);

Finder get _title => find.descendant(
  of: _headerFinder,
  matching: find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.maxLines == 3 &&
        w.overflow == TextOverflow.ellipsis &&
        w.data != null,
  ),
);

/// Başlık Text'inin çizim nesnesi (satır sayısı/elips sınaması için).
RenderParagraph _titlePara(WidgetTester t) =>
    t.renderObject<RenderParagraph>(_title);

/// Rozet metni (AnimatedCount içindeki Text).
String _badgeText(WidgetTester t) => t
    .widget<Text>(find.descendant(of: _badge, matching: find.byType(Text)))
    .data!;

Widget _header({
  String title = 'Yetkili Kapılar',
  int? count,
  String suffix = '',
  IconData? icon,
  Widget? trailing,
}) => SectionHeader(
  title: title,
  count: count,
  countSuffix: suffix,
  icon: icon,
  trailing: trailing,
);

// --- InlineNotice yardımcıları --------------------------------------------------------------

Finder get _noticeFinder => find.byType(InlineNotice);

BoxDecoration _noticeBox(WidgetTester t) =>
    t
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: _noticeFinder,
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Finder get _noticeText => find.descendant(
  of: _noticeFinder,
  matching: find.byWidgetPredicate(
    (w) => w is Text && w.data != null && w.data != 'Tekrar Dene',
  ),
);

void main() {
  group('AppCard: yüzey', () {
    testWidgets(
      'varsayılan: opak surface, 1 px kenar, yarıçap 20, tek katman seviye-1 gölge, 16 dp iç boşluk (açık + koyu)',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          await t.pumpWidget(
            _app(_full(const AppCard(child: Text('içerik'))), dark: dark),
          );
          await t.pumpAndSettle();
          final material = _material(t);
          expect(material.color, p.surfaceAt(1));
          expect(material.color!.a, 1.0, reason: 'opak yüzey');
          expect(material.clipBehavior, Clip.antiAlias);
          final shape = _shape(t);
          expect(shape.borderRadius, BorderRadius.circular(AppRadius.lg));
          expect(shape.side.width, 1);
          expect(shape.side.color, p.border);
          final shadow = _shadowBox(t);
          expect(shadow.boxShadow, p.shadow(1));
          expect(shadow.boxShadow, hasLength(1), reason: 'tek katman');
          expect(shadow.boxShadow!.single.blurRadius, lessThanOrEqualTo(16));
          expect(shadow.boxShadow!.single.spreadRadius, 0);
          expect(shadow.borderRadius, BorderRadius.circular(AppRadius.lg));
          expect(
            t.getTopLeft(find.text('içerik')) - t.getTopLeft(_cardFinder),
            const Offset(AppSpace.lg, AppSpace.lg),
            reason: 'varsayılan iç boşluk 16',
          );
        }
      },
    );

    testWidgets(
      'level 1/2/3: yüzey ve gölge seviyesi (koyuda daha açık yüzey)',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          for (final level in [1, 2, 3]) {
            await t.pumpWidget(
              _app(
                _full(AppCard(level: level, child: const Text('x'))),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            expect(_material(t).color, p.surfaceAt(level), reason: 'L$level');
            expect(_shadowBox(t).boxShadow, p.shadow(level), reason: 'L$level');
          }
          if (dark) {
            expect(
              p.surfaceAt(3),
              isNot(p.surfaceAt(1)),
              reason: 'koyuda yükselti = daha açık yüzey',
            );
          }
        }
      },
    );

    testWidgets(
      'tonlu kart: opak soluk ton zemini + ton kenarı (7 ton x açık/koyu)',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          for (final tone in AppTone.values) {
            await t.pumpWidget(
              _app(
                _full(AppCard(tone: tone, child: const Text('x'))),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            final color = _material(t).color!;
            expect(color, Color.alphaBlend(tone.tint(p), p.surface));
            expect(color.a, 1.0, reason: 'opak (kompozit maliyeti yok)');
            expect(_shape(t).side.color, tone.hue.withValues(alpha: 0.5));
            expect(_shape(t).side.width, 1);
          }
        }
      },
    );

    testWidgets(
      'tonlu kartta ink metin >= 4,5:1 (4 anlamsal ton x açık/koyu)',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          for (final tone in [
            AppTone.danger,
            AppTone.warning,
            AppTone.success,
            AppTone.info,
          ]) {
            await t.pumpWidget(
              _app(
                _full(AppCard(tone: tone, child: const Text('x'))),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            expect(
              _contrast(tone.ink(p), _material(t).color!),
              greaterThanOrEqualTo(4.5),
              reason: '${tone.name} dark=$dark',
            );
          }
        }
      },
    );

    testWidgets(
      'seçili: 1,5 px birincil ink kenar + seviye 2 yükselti; Semantics seçili',
      (t) async {
        final handle = t.ensureSemantics();
        for (final dark in [false, true]) {
          final p = _palette(dark);
          await t.pumpWidget(
            _app(
              _full(const AppCard(selected: true, child: Text('x'))),
              dark: dark,
            ),
          );
          await t.pumpAndSettle();
          expect(_shape(t).side.width, 1.5);
          expect(_shape(t).side.color, AppTone.primary.ink(p));
          expect(_shadowBox(t).boxShadow, p.shadow(2));
          expect(_material(t).color, p.surfaceAt(2));
          expect(
            t.getSemantics(_cardFinder),
            isSemantics(isSelected: true, hasSelectedState: true),
          );
        }
        handle.dispose();
      },
    );

    testWidgets(
      'seçili kart daha yüksek seviyeyi DÜŞÜRMEZ (level 3 seçili: seviye 3)',
      (t) async {
        await t.pumpWidget(
          _app(
            _full(const AppCard(selected: true, level: 3, child: Text('x'))),
          ),
        );
        expect(_shadowBox(t).boxShadow, AppPalette.light.shadow(3));
      },
    );

    testWidgets('seçili olmayan kartta Semantics seçili bayrağı yok', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_app(_full(const AppCard(child: Text('x')))));
      expect(
        t.getSemantics(_cardFinder),
        isSemantics(hasSelectedState: false, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets(
      'accentBar: 3 dp, kart genişliğinde, kartın üstünde; düzeni DEĞİŞTİRMEZ',
      (t) async {
        const barColor = Color(0xFF3B82F6);
        await t.pumpWidget(_app(_full(const AppCard(child: Text('içerik')))));
        final plainSize = t.getSize(_cardFinder);
        final plainText =
            t.getTopLeft(find.text('içerik')) - t.getTopLeft(_cardFinder);
        expect(_bar(barColor), findsNothing);

        await t.pumpWidget(
          _app(
            _full(const AppCard(accentBar: barColor, child: Text('içerik'))),
          ),
        );
        expect(_bar(barColor), findsOneWidget);
        expect(t.getSize(_bar(barColor)), Size(plainSize.width, 3));
        expect(t.getTopLeft(_bar(barColor)), t.getTopLeft(_cardFinder));
        expect(
          t.getSize(_cardFinder),
          plainSize,
          reason: 'şerit kart boyutunu değiştirmez',
        );
        expect(
          t.getTopLeft(find.text('içerik')) - t.getTopLeft(_cardFinder),
          plainText,
          reason: 'şerit içeriği kaydırmaz',
        );
        expect(
          _material(t).clipBehavior,
          Clip.antiAlias,
          reason: 'şerit köşeye kırpılır',
        );
      },
    );

    testWidgets('accentBar + tonlu + seçili birlikte çalışır', (t) async {
      const barColor = Color(0xFF10B981);
      await t.pumpWidget(
        _app(
          _full(
            const AppCard(
              accentBar: barColor,
              tone: AppTone.warning,
              selected: true,
              child: Text('x'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(_bar(barColor), findsOneWidget);
      expect(_shape(t).side.width, 1.5);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'yasaklı dekor yok: BackdropFilter/ImageFiltered/ShaderMask/Opacity ve ek gölge katmanı',
      (t) async {
        await t.pumpWidget(
          _app(
            _full(
              const AppCard(
                accentBar: Colors.blue,
                tone: AppTone.info,
                selected: true,
                child: Text('x'),
              ),
            ),
          ),
        );
        for (final type in [
          BackdropFilter,
          ImageFiltered,
          ShaderMask,
          Opacity,
        ]) {
          expect(
            find.descendant(of: _cardFinder, matching: find.byType(type)),
            findsNothing,
            reason: '$type',
          );
        }
        expect(_material(t).elevation, 0, reason: 'Material gölgesi yok');
        expect(_shadowBox(t).boxShadow, hasLength(1));
      },
    );

    testWidgets(
      'sabit yükseklik yok: kart içeriği kadar uzar; iç boşluk özelleştirilebilir',
      (t) async {
        await t.pumpWidget(
          _app(
            _full(
              const Column(
                children: [
                  AppCard(child: SizedBox(height: 20)),
                  AppCard(child: SizedBox(height: 120)),
                  AppCard(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: SizedBox(height: 20),
                  ),
                ],
              ),
            ),
          ),
        );
        final a = t.getSize(_cardFinder.at(0));
        final b = t.getSize(_cardFinder.at(1));
        final c = t.getSize(_cardFinder.at(2));
        expect(a.height, 20 + 2 * AppSpace.lg);
        expect(b.height, 120 + 2 * AppSpace.lg);
        expect(c.height, 20 + 2 * AppSpace.md, reason: 'dar kart padding 12');
      },
    );

    testWidgets(
      'statik: kararlı durumda ticker yok, pumpAndSettle hemen biter',
      (t) async {
        await t.pumpWidget(
          _app(_full(const AppCard(selected: true, child: Text('x')))),
        );
        final elapsed = await _settle(t);
        expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 100)));
        expect(t.binding.transientCallbackCount, 0);
      },
    );
  });

  group('AppCard: etkileşim', () {
    testWidgets(
      'onTap null: InkWell yok, dokunuş hiçbir şey yapmaz; Semantics düğme/dokunma yok',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(_app(_full(const AppCard(child: Text('x')))));
        expect(
          find.descendant(of: _cardFinder, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(
          t.getSemantics(_cardFinder),
          isSemantics(isButton: false, hasTapAction: false),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'onTap: tek dokunma tek çağrı; InkWell kart yarıçapında; düğme + dokunma eylemi',
      (t) async {
        final handle = t.ensureSemantics();
        var taps = 0;
        await t.pumpWidget(
          _app(
            _full(
              AppCard(onTap: () => taps++, child: const Text('Siteye git')),
            ),
          ),
        );
        final ink = t.widget<InkWell>(
          find.descendant(of: _cardFinder, matching: find.byType(InkWell)),
        );
        expect(ink.borderRadius, BorderRadius.circular(AppRadius.lg));
        await t.tap(find.text('Siteye git'));
        await t.pumpAndSettle();
        expect(taps, 1);
        expect(
          t.getSemantics(_cardFinder),
          isSemantics(label: 'Siteye git', isButton: true, hasTapAction: true),
        );
        handle.dispose();
      },
    );

    testWidgets('klavye: Tab odak + Enter onTap çağırır (odak/fare erişimi)', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(
        _app(_full(AppCard(onTap: () => taps++, child: const Text('x')))),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(taps, 1);
    });

    testWidgets(
      'dokunma hedefi >= 44 dp: iç boşluksuz küçük içerikte bile 48 dp',
      (t) async {
        await t.pumpWidget(
          _app(
            _full(
              Column(
                children: [
                  AppCard(
                    onTap: () {},
                    padding: EdgeInsets.zero,
                    child: const SizedBox(height: 10),
                  ),
                  const AppCard(
                    padding: EdgeInsets.zero,
                    child: SizedBox(height: 10),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          t.getSize(_cardFinder.at(0)).height,
          48,
          reason: 'dokunulabilir',
        );
        expect(
          t.getSize(_cardFinder.at(1)).height,
          10,
          reason: 'salt görüntü: sabitleme yok',
        );
      },
    );

    testWidgets(
      'kart içindeki düğme kendi onPressed\'ini çağırır, kartın onTap\'ını DEĞİL',
      (t) async {
        var cardTaps = 0;
        var buttonTaps = 0;
        await t.pumpWidget(
          _app(
            _full(
              AppCard(
                onTap: () => cardTaps++,
                child: Column(
                  children: [
                    const Text('Site A'),
                    TextButton(
                      onPressed: () => buttonTaps++,
                      child: const Text('Sil'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Sil'));
        await t.pumpAndSettle();
        expect((cardTaps, buttonTaps), (0, 1));
        await t.tap(find.text('Site A'));
        await t.pumpAndSettle();
        expect((cardTaps, buttonTaps), (1, 1));
      },
    );

    testWidgets(
      'semanticLabel: kartın düğümüne eklenir, içerik ve iç düğmeler dışlanmaz',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          _app(
            _full(
              AppCard(
                semanticLabel: 'Site A özeti',
                child: Column(
                  children: [
                    const Text('Site A'),
                    TextButton(onPressed: () {}, child: const Text('Sil')),
                  ],
                ),
              ),
            ),
          ),
        );
        final data = t.getSemantics(_cardFinder).getSemanticsData();
        expect(data.label, contains('Site A özeti'));
        expect(data.label, contains('Site A'), reason: 'içerik dışlanmaz');
        expect(
          t.getSemantics(find.text('Sil')),
          isSemantics(label: 'Sil', isButton: true, hasTapAction: true),
          reason: 'iç düğme ayrı ve erişilebilir',
        );
        handle.dispose();
      },
    );

    testWidgets(
      'hareket azaltma: Material geçiş süresi 0; seçili durum tek pump ile tamam',
      (t) async {
        await t.pumpWidget(
          _app(_full(const AppCard(child: Text('x'))), reduce: true),
        );
        expect(_material(t).animationDuration, Duration.zero);
        await t.pumpWidget(
          _app(
            _full(const AppCard(selected: true, child: Text('x'))),
            reduce: true,
          ),
        );
        await t.pump();
        expect(t.binding.transientCallbackCount, 0);
        expect(_material(t).animationDuration, Duration.zero);
      },
    );

    testWidgets(
      'hareket açıkken Material geçiş süresi 200 ms (seçili geçişi) ve geçiş biter',
      (t) async {
        await t.pumpWidget(_app(_full(const AppCard(child: Text('x')))));
        expect(_material(t).animationDuration, AppMotion.base);
        await t.pumpWidget(
          _app(_full(const AppCard(selected: true, child: Text('x')))),
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(
          t.binding.transientCallbackCount,
          greaterThan(0),
          reason: 'geçiş sürüyor',
        );
        final elapsed = await _settle(t);
        expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 300)));
        expect(t.binding.transientCallbackCount, 0);
      },
    );
  });

  group('AppCard: taşma matrisi', () {
    Widget content() => Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            accentBar: AppTone.primary.hue,
            onTap: () {},
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yetkili Kapılar ve Cihaz Yönetimi: çok uzun bir kart başlığı',
                ),
                SizedBox(height: AppSpace.sm),
                Text(
                  'Açıklama metni birkaç satıra sarar ve kartı uzatır; sabit yükseklik yoktur.',
                ),
                SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Icon(Icons.door_front_door_rounded),
                    SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Otopark Giriş Kapısı - Blok A Daire Sakinleri',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const AppCard(
            tone: AppTone.warning,
            selected: true,
            level: 2,
            padding: EdgeInsets.all(AppSpace.md),
            child: Text(
              'Cihaz bağlı değil: önce bir cihaz ekleyin ve siteye bağlayın.',
            ),
          ),
        ],
      ),
    );

    testWidgets('kartlar x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(t, content(), width: width, scale: scale, dark: dark);
        expect(_cardFinder, findsNWidgets(2));
        for (var i = 0; i < 2; i++) {
          expect(
            t.getSize(_cardFinder.at(i)).width,
            width - 2 * AppSpace.lg,
            reason: 'kart $i tam genişlik ($width x $scale dark=$dark)',
          );
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('hareket azaltma ile de taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, content(), reduce: true);
      expect(_cardFinder, findsNWidgets(2));
    });
  });

  group('SectionHeader', () {
    testWidgets(
      'yalnız başlık: titleLarge, başlık düğümü, sola hizalı tam genişlik',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(title: 'Kullanıcılar'),
          ),
          width: 412,
          scale: 1.0,
        );
        expect(t.getSize(_headerFinder).width, 412 - 2 * AppSpace.lg);
        final style = t.widget<Text>(_title).style!;
        expect(style.fontSize, 18, reason: 'titleLarge');
        expect(style.fontWeight, FontWeight.w800);
        expect(_badge, findsNothing);
        expect(
          t.getSemantics(_title),
          isSemantics(label: 'Kullanıcılar', isHeader: true),
        );
        expect(
          find.text('Kullanıcılar'),
          findsOneWidget,
          reason: 'find.text bulur',
        );
        handle.dispose();
      },
    );

    testWidgets(
      'sayaç rozeti: hap, birincil tint zemin + ink metin (>= 4,5:1), bodySmall w700',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          await pumpAt(
            t,
            _header(count: 3, suffix: ' Kapı'),
            width: 412,
            scale: 1.0,
            dark: dark,
          );
          final box =
              t.widget<DecoratedBox>(_badge).decoration as BoxDecoration;
          expect(box.color, AppTone.primary.tint(p));
          final text = t.widget<Text>(
            find.descendant(of: _badge, matching: find.byType(Text)),
          );
          expect(text.data, '3 Kapı');
          expect(text.style!.color, AppTone.primary.ink(p));
          expect(text.style!.fontWeight, FontWeight.w700);
          expect(text.style!.fontSize, 12);
          expect(
            _contrast(
              AppTone.primary.ink(p),
              Color.alphaBlend(AppTone.primary.tint(p), p.surface),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      },
    );

    testWidgets('ikon: 20 dp, ikincil renk, başlıktan 8 dp önce', (t) async {
      final p = AppPalette.light;
      await pumpAt(
        t,
        _header(icon: Icons.door_front_door_rounded),
        width: 412,
        scale: 1.0,
      );
      final icon = t.widget<Icon>(find.byIcon(Icons.door_front_door_rounded));
      expect(icon.size, 20);
      expect(icon.color, p.textSecondary);
      expect(
        t.getTopLeft(_title).dx -
            t.getTopRight(find.byIcon(Icons.door_front_door_rounded)).dx,
        AppSpace.sm,
      );
    });

    testWidgets(
      'rozet başlıkla aynı satırda başlar ve başlığın hemen sağındadır (sığınca)',
      (t) async {
        await pumpAt(
          t,
          _header(title: 'Kapılar', count: 2, suffix: ' Kapı'),
          width: 820,
          scale: 1.0,
        );
        final title = t.getRect(_title);
        final badge = t.getRect(_badge);
        expect(badge.left, closeTo(title.right + AppSpace.sm, 0.5));
        expect((badge.center.dy - title.center.dy).abs(), lessThan(2));
      },
    );

    testWidgets(
      '"Yetkili Kapılar" + sayaç 360 x 1,5 ve 320 x 2,0: başlık KIRPILMAZ, rozet tam görünür',
      (t) async {
        for (final (width, scale) in [(360.0, 1.5), (320.0, 2.0)]) {
          await pumpAt(
            t,
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: _header(count: 12, suffix: ' Kapı'),
            ),
            width: width,
            scale: scale,
          );
          final para = _titlePara(t);
          expect(para.didExceedMaxLines, isFalse, reason: '$width x $scale');
          expect(_badgeText(t), '12 Kapı');
          final badgePara = t.renderObject<RenderParagraph>(
            find.descendant(of: _badge, matching: find.byType(Text)),
          );
          expect(
            badgePara.didExceedMaxLines,
            isFalse,
            reason: 'rozet kırpılmadı',
          );
          final area = Rect.fromLTWH(0, 0, width, 640);
          expect(area.contains(t.getTopLeft(_badge)), isTrue);
          expect(
            t.getBottomRight(_badge).dx,
            lessThanOrEqualTo(width - AppSpace.lg + 0.5),
            reason: 'rozet sağ kenarı taşmaz',
          );
        }
      },
    );

    testWidgets(
      'başlık sığmazsa rozet başlıkla birlikte ALT satıra iner (taşma yok)',
      (t) async {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(title: 'Bekleyen Site Onay Talepleri', count: 5),
          ),
          width: 320,
          scale: 2.0,
        );
        final title = t.getRect(_title);
        final badge = t.getRect(_badge);
        expect(
          badge.top,
          greaterThanOrEqualTo(title.bottom - 0.5),
          reason: 'rozet altta',
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'çok uzun başlık en çok 3 satır ve elips (RenderFlex taşması yok)',
      (t) async {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(
              title:
                  'Yönetici ve Cihaz Yönetimi Bölümü İçin Çok Çok Uzun Bir Başlık Metni',
              count: 3,
            ),
          ),
          width: 320,
          scale: 2.0,
        );
        final para = _titlePara(t);
        expect(para.maxLines, 3);
        expect(para.didExceedMaxLines, isTrue);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'sayaç değişince AnimatedCount ~320 ms akar ve yeni değere oturur',
      (t) async {
        Widget build(int count) =>
            harnessApp(_header(count: count, suffix: ' Kapı'));
        await t.pumpWidget(build(3));
        expect(_badgeText(t), '3 Kapı', reason: 'ilk karede animasyonsuz');
        expect(t.binding.transientCallbackCount, 0);
        await t.pumpWidget(build(9));
        await t.pump(const Duration(milliseconds: 100));
        final mid = int.parse(
          RegExp(r'\d+').firstMatch(_badgeText(t))!.group(0)!,
        );
        expect(mid, inInclusiveRange(4, 8), reason: 'ara değer akıyor');
        await t.pumpAndSettle();
        expect(_badgeText(t), '9 Kapı');
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('hareket azaltma: sayaç değişimi tek pump ile tamam', (
      t,
    ) async {
      Widget build(int count) =>
          harnessApp(_header(count: count, suffix: ' Kapı'), reduce: true);
      await t.pumpWidget(build(3));
      await t.pumpWidget(build(9));
      await t.pump();
      expect(_badgeText(t), '9 Kapı');
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'trailing sığıyorsa AYNI satırda ve satırın sonunda (820 x 1,0)',
      (t) async {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(
              title: 'Kapılar',
              count: 2,
              trailing: TextButton(onPressed: () {}, child: const Text('Tümü')),
            ),
          ),
          width: 820,
          scale: 1.0,
        );
        final title = t.getRect(_title);
        final button = t.getRect(find.byType(TextButton));
        expect(
          button.center.dy,
          closeTo(title.center.dy, 2),
          reason: 'aynı satır',
        );
        expect(
          button.right,
          closeTo(820 - AppSpace.lg, 0.5),
          reason: 'satır sonu',
        );
      },
    );

    testWidgets(
      'metinli trailing dar/büyük yazıda başlığın ALTINA düşer, taşmaz (320 x 2,0)',
      (t) async {
        var taps = 0;
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(
              title: 'Yetkili Kapılar',
              count: 2,
              trailing: TextButton(
                onPressed: () => taps++,
                child: const Text('Tümünü Gör'),
              ),
            ),
          ),
          width: 320,
          scale: 2.0,
        );
        final button = find.byType(TextButton);
        final lastTitleOrBadgeBottom = [
          t.getRect(_title).bottom,
          t.getRect(_badge).bottom,
        ].reduce((a, b) => a > b ? a : b);
        expect(
          t.getRect(button).top,
          greaterThanOrEqualTo(lastTitleOrBadgeBottom - 0.5),
          reason: 'düğme başlığın altında',
        );
        expect(
          t.getRect(button).left,
          closeTo(AppSpace.lg, 0.5),
          reason: 'sola hizalı',
        );
        expect(
          t.getRect(button).right,
          lessThanOrEqualTo(320 - AppSpace.lg + 0.5),
        );
        await t.tap(button);
        expect(taps, 1, reason: 'altta da dokunulabilir');
      },
    );

    testWidgets(
      '2 IconButton trailing: dokunulabilir, >= 44 dp, taşmaz (360 x 1,5)',
      (t) async {
        var refresh = 0;
        var add = 0;
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(
              title: 'Siteler',
              count: 4,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: () => refresh++,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Ekle',
                    onPressed: () => add++,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          ),
          width: 360,
          scale: 1.5,
        );
        for (final icon in [Icons.refresh_rounded, Icons.add_rounded]) {
          final button = find.widgetWithIcon(IconButton, icon);
          expect(t.getSize(button).width, greaterThanOrEqualTo(44));
          expect(t.getSize(button).height, greaterThanOrEqualTo(44));
        }
        await t.tap(find.byTooltip('Yenile'));
        await t.tap(find.byTooltip('Ekle'));
        expect((refresh, add), (1, 1));
      },
    );

    testWidgets(
      'Semantics: başlık + sayaç TEK başlık düğümü; trailing ayrı ve erişilebilir',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: _header(
              title: 'Yetkili Kapılar',
              count: 3,
              suffix: ' Kapı',
              trailing: IconButton(
                tooltip: 'Yenile',
                onPressed: () {},
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          width: 412,
          scale: 1.0,
        );
        expect(
          t.getSemantics(_title),
          isSemantics(label: 'Yetkili Kapılar, 3 Kapı', isHeader: true),
        );
        expect(
          find.bySemanticsLabel('Yetkili Kapılar, 3 Kapı'),
          findsOneWidget,
        );
        expect(
          t.getSemantics(find.byTooltip('Yenile')),
          isSemantics(isButton: true, hasTapAction: true, tooltip: 'Yenile'),
        );
        handle.dispose();
      },
    );

    testWidgets('pumpAndSettle biter (sayaç + ikon + trailing)', (t) async {
      await t.pumpWidget(
        harnessApp(
          _header(
            count: 3,
            icon: Icons.door_front_door_rounded,
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      );
      final elapsed = await _settle(t);
      expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 100)));
      expect(t.binding.transientCallbackCount, 0);
    });

    Widget headers() => Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(title: 'Kullanıcılar'),
          const SizedBox(height: AppSpace.md),
          _header(
            title: 'Yetkili Kapılar',
            count: 2,
            suffix: ' Kapı',
            icon: Icons.door_front_door_rounded,
          ),
          const SizedBox(height: AppSpace.md),
          _header(
            title: 'Yönetici & Cihaz Yönetimi',
            count: 12,
            trailing: TextButton(
              onPressed: () {},
              child: const Text('Tümünü Gör'),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _header(
            title: 'Siteler',
            count: 4,
            icon: Icons.apartment_rounded,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Yenile',
                  onPressed: () {},
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Ekle',
                  onPressed: () {},
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _header(
            title:
                'Çok uzun bir bölüm başlığı ve onun yanındaki uzun sayaç metni',
            count: 120,
            suffix: ' geçiş kaydı',
            trailing: Wrap(
              spacing: AppSpace.sm,
              children: [
                TextButton(onPressed: () {}, child: const Text('PDF')),
                TextButton(onPressed: () {}, child: const Text('Yenile')),
              ],
            ),
          ),
        ],
      ),
    );

    testWidgets('başlıklar x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(t, headers(), width: width, scale: scale, dark: dark);
        expect(_headerFinder, findsNWidgets(5));
        for (var i = 0; i < 5; i++) {
          expect(
            t.getSize(_headerFinder.at(i)).width,
            width - 2 * AppSpace.lg,
            reason: 'başlık $i ($width x $scale dark=$dark)',
          );
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('hareket azaltma ile de taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, headers(), reduce: true);
      expect(_headerFinder, findsNWidgets(5));
    });
  });

  group('SectionHeader: eylem yerleşimi (ölçerek karar)', () {
    /// Genişliği [w] olan, kenar boşluksuz başlık (ölçüler doğrudan [w] ile karşılaştırılır).
    Widget bare({
      String title = 'Yetkili Kapılar',
      int? count = 2,
      required Widget trailing,
    }) => _header(title: title, count: count, trailing: trailing);

    Widget icons(int n) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          IconButton(
            tooltip: 'Eylem $i',
            onPressed: () {},
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );

    testWidgets(
      'simge düğmeleri (1 ve 2) başlık satırının SONUNDA, dikeyde ortalı; başlık/rozet esner (320 x 2,0)',
      (t) async {
        for (final n in [1, 2]) {
          await pumpAt(
            t,
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: bare(trailing: icons(n)),
            ),
            width: 320,
            scale: 2.0,
          );
          final header = t.getRect(_headerFinder);
          final button = t.getRect(find.byType(Row).last);
          expect(
            button.right,
            closeTo(header.right, 0.5),
            reason: '$n simge: sonda',
          );
          expect(button.top, greaterThanOrEqualTo(header.top - 0.5));
          expect(
            button.center.dy,
            closeTo(header.center.dy, 1),
            reason: '$n simge: dikeyde ortalı',
          );
          // Başlık bloğu eylemin soluna sığdı (kalan genişlik).
          final title = t.getRect(_title);
          expect(
            title.right,
            lessThanOrEqualTo(button.left - AppSpace.sm + 0.5),
            reason: '$n simge: başlık eylemin soluna sığar',
          );
          expect(t.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'kart içi genişlik (296 dp), 1,0 ve 1,5 yazı: simge düğmesi başlık+rozetle AYNI satırda kalır',
      (t) async {
        for (final scale in [1.0, 1.5]) {
          await pumpAt(
            t,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: bare(title: 'Kapılar', trailing: icons(1)),
            ),
            width: 360,
            scale: scale,
          );
          final title = t.getRect(_title);
          final badge = t.getRect(_badge);
          final button = t.getRect(find.byType(Row).last);
          expect(
            badge.center.dy,
            closeTo(title.center.dy, 2),
            reason: 'rozet başlıkla aynı satır (x$scale)',
          );
          expect(
            button.center.dy,
            closeTo(title.center.dy, 2),
            reason: 'simge de aynı satır (x$scale)',
          );
          expect(button.right, 360 - 32);
        }
      },
    );

    testWidgets(
      'eşik: eylem genişliğin %40\'ı ve altı yan yana, üstü alt alta (kesin sınır)',
      (t) async {
        for (final (width, inline) in [(120.0, true), (120.5, false)]) {
          await pumpAt(
            t,
            bare(
              title: 'Kapı',
              count: null,
              trailing: SizedBox(
                key: const ValueKey('eylem'),
                width: width,
                height: 48,
              ),
            ),
            width: 300,
            scale: 1.0,
          );
          final header = t.getRect(_headerFinder);
          final action = t.getRect(find.byKey(const ValueKey('eylem')));
          expect(header.width, 300);
          if (inline) {
            expect(action.right, 300, reason: 'yan yana: sonda');
            expect(action.top, lessThan(header.top + 48));
            expect(header.height, 48, reason: 'tek satır: eylem 48 dp');
          } else {
            expect(action.left, 0, reason: 'alt alta: sola hizalı');
            final blockBottom = t.getRect(_title).bottom;
            expect(
              action.top,
              greaterThanOrEqualTo(blockBottom + AppSpace.xs - 0.5),
            );
            expect(header.height, greaterThan(48 + AppSpace.xs));
          }
        }
      },
    );

    testWidgets(
      'yükseklik: yan yana = en uzun çocuk; alt alta = başlık bloğu + 4 + eylem',
      (t) async {
        // Yan yana: eylem başlık bloğundan uzun (96) -> başlık ortalı.
        await pumpAt(
          t,
          bare(
            title: 'Kapı',
            count: null,
            trailing: const SizedBox(
              key: ValueKey('eylem'),
              width: 40,
              height: 96,
            ),
          ),
          width: 400,
          scale: 1.0,
        );
        expect(t.getSize(_headerFinder).height, 96);
        expect(
          t.getCenter(_title).dy,
          closeTo(t.getRect(_headerFinder).center.dy, 0.5),
          reason: 'kısa başlık ortalı',
        );
        // Alt alta.
        await pumpAt(
          t,
          bare(
            title: 'Kapı',
            count: null,
            trailing: const SizedBox(
              key: ValueKey('eylem'),
              width: 300,
              height: 30,
            ),
          ),
          width: 400,
          scale: 1.0,
        );
        final blockHeight = t
            .getSize(
              find.ancestor(of: _title, matching: find.byType(Row)).first,
            )
            .height;
        expect(t.getSize(_headerFinder).height, blockHeight + AppSpace.xs + 30);
      },
    );

    testWidgets(
      'eylem YOKSA başlık bloğu sola yaslı ve başlık tam genişlikte sarar',
      (t) async {
        await pumpAt(
          t,
          _header(title: 'Kapı', count: null),
          width: 400,
          scale: 1.0,
        );
        expect(t.getSize(_headerFinder).width, 400);
        expect(t.getTopLeft(_title).dx, 0);
      },
    );

    testWidgets(
      'sınırsız genişlikte (yatay kaydırma) içeriği kadar geniştir; hata yok',
      (t) async {
        await t.pumpWidget(
          harnessApp(
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _header(title: 'Kapı', count: 3, trailing: icons(1)),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final size = t.getSize(_headerFinder);
        final lead = t.getRect(_title).width;
        expect(size.width, greaterThan(lead));
        expect(size.width, lessThan(400));
        expect(
          t.getRect(find.byType(Row).last).right,
          closeTo(size.width, 0.5),
        );
      },
    );

    testWidgets(
      'IntrinsicWidth/IntrinsicHeight içinde de hata vermez ve boyutlar tutarlıdır',
      (t) async {
        await t.pumpWidget(
          harnessApp(
            Align(
              alignment: Alignment.topLeft,
              child: IntrinsicWidth(
                child: _header(title: 'Kapılar', count: 3, trailing: icons(1)),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final w = t.getSize(_headerFinder).width;
        expect(w, greaterThan(100));
        expect(w, lessThan(800));
        expect(t.getRect(find.byType(Row).last).right, closeTo(w, 0.5));

        await t.pumpWidget(
          harnessApp(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _header(
                      title: 'Yetkili Kapılar ve Cihaz Yönetimi',
                      count: 3,
                      trailing: icons(2),
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                    child: ColoredBox(color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          t.getSize(find.byType(SizedBox).last).height,
          t.getSize(_headerFinder).height,
          reason: 'IntrinsicHeight başlığın gerçek yüksekliğini kullandı',
        );
      },
    );

    testWidgets('kuru yerleşim gerçek boyutla aynıdır (yan yana ve alt alta)', (
      t,
    ) async {
      for (final trailing in [
        icons(1),
        TextButton(
          onPressed: () {},
          child: const Text('Çok uzun bir eylem metni'),
        ),
      ]) {
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: bare(title: 'Yönetici Kapıları', trailing: trailing),
          ),
          width: 360,
          scale: 1.5,
        );
        final box = t.renderObject<RenderBox>(_headerFinder);
        expect(box.getDryLayout(box.constraints), box.size);
        for (final width in [100.0, 200.0, 328.0, 600.0]) {
          final constraints = BoxConstraints(maxWidth: width);
          final dry = box.getDryLayout(constraints);
          expect(dry.width, width);
          expect(dry.height, greaterThan(0));
          expect(box.getMinIntrinsicHeight(width), dry.height);
        }
        expect(box.getMinIntrinsicWidth(double.infinity), greaterThan(0));
        expect(
          box.getMaxIntrinsicWidth(double.infinity),
          greaterThanOrEqualTo(box.getMinIntrinsicWidth(double.infinity)),
        );
      }
    });

    testWidgets(
      'taban çizgisi: başlık, yanındaki metinle taban çizgisinde hizalanır',
      (t) async {
        await pumpAt(
          t,
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('Büyük', style: TextStyle(fontSize: 40)),
              Expanded(
                child: bare(title: 'Kapı', count: null, trailing: icons(1)),
              ),
            ],
          ),
          width: 400,
          scale: 1.0,
        );
        final big = t.getTopLeft(find.text('Büyük')).dy;
        final small = t.getTopLeft(_title).dy;
        // Üstten hizalansaydı ikisi de aynı y'de olurdu; taban çizgisinde küçük metin aşağıdadır.
        expect(small, greaterThan(big + 5));
        final box = t.renderObject<RenderBox>(_headerFinder);
        expect(
          box.getDryBaseline(box.constraints, TextBaseline.alphabetic),
          isNotNull,
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'her iki yerleşimde de eylem dokunulabilir (isabet testi doğru çocuğa gider)',
      (t) async {
        for (final (width, label) in [
          (412.0, 'yan yana'),
          (320.0, 'alt alta'),
        ]) {
          var taps = 0;
          await pumpAt(
            t,
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: bare(
                title: 'Yönetici Kapıları',
                trailing: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Tümünü Gör'),
                ),
              ),
            ),
            width: width,
            scale: width == 412 ? 1.0 : 2.0,
          );
          await t.tap(find.byType(TextButton));
          expect(taps, 1, reason: label);
        }
      },
    );
  });

  group('InlineNotice', () {
    Widget notice({
      String message = 'E-posta veya şifre hatalı.',
      AppTone tone = AppTone.danger,
      VoidCallback? onRetry,
      IconData? icon,
    }) => InlineNotice(
      message: message,
      tone: tone,
      onRetry: onRetry,
      icon: icon,
    );

    testWidgets(
      '4 ton x açık/koyu: ton ikonu, opak tint zemin, hue kenarı, ink metin >= 4,5:1',
      (t) async {
        const icons = <AppTone, IconData>{
          AppTone.danger: Icons.error_outline_rounded,
          AppTone.success: Icons.check_circle_outline_rounded,
          AppTone.warning: Icons.warning_amber_rounded,
          AppTone.info: Icons.info_outline_rounded,
        };
        for (final dark in [false, true]) {
          final p = _palette(dark);
          for (final entry in icons.entries) {
            final tone = entry.key;
            await t.pumpWidget(
              _app(
                _full(notice(tone: tone, message: 'Mesaj ${tone.name}')),
                dark: dark,
              ),
            );
            await t.pumpAndSettle();
            final box = _noticeBox(t);
            final bg = Color.alphaBlend(tone.tint(p), p.surface);
            expect(box.color, bg, reason: '${tone.name} dark=$dark');
            expect(box.color!.a, 1.0, reason: 'opak');
            expect(
              (box.border! as Border).top.color,
              tone.hue.withValues(alpha: 0.4),
            );
            expect(box.borderRadius, BorderRadius.circular(AppRadius.sm));
            final icon = t.widget<Icon>(find.byIcon(entry.value));
            expect(icon.color, tone.ink(p));
            expect(icon.size, 20);
            final text = t.widget<Text>(find.text('Mesaj ${tone.name}'));
            expect(text.style!.color, tone.ink(p));
            expect(
              _contrast(text.style!.color!, bg),
              greaterThanOrEqualTo(4.5),
              reason: '${tone.name} dark=$dark',
            );
          }
        }
      },
    );

    testWidgets(
      'varsayılan ton danger; ton dışı (primary) bilgi ikonuna düşer; özel ikon geçer',
      (t) async {
        await t.pumpWidget(_app(_full(const InlineNotice(message: 'x'))));
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
        await t.pumpWidget(
          _app(_full(const InlineNotice(message: 'x', tone: AppTone.primary))),
        );
        expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
        await t.pumpWidget(
          _app(
            _full(const InlineNotice(message: 'x', icon: Icons.lock_rounded)),
          ),
        );
        expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      },
    );

    testWidgets('onRetry yok: "Tekrar Dene" düğmesi yok', (t) async {
      await t.pumpWidget(_app(_full(notice())));
      expect(find.text('Tekrar Dene'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets(
      'onRetry: "Tekrar Dene" metnin ALTINDA, sola hizalı, >= 48 dp; tek dokunma tek çağrı',
      (t) async {
        var retries = 0;
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: notice(
              message: 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.',
              onRetry: () => retries++,
            ),
          ),
          width: 412,
          scale: 1.0,
        );
        final message = t.getRect(_noticeText);
        final button = t.getRect(find.byType(TextButton));
        expect(
          button.top,
          greaterThanOrEqualTo(message.bottom - 0.5),
          reason: 'metnin altında',
        );
        expect(
          button.left,
          closeTo(message.left, 0.5),
          reason: 'metinle hizalı',
        );
        expect(button.height, greaterThanOrEqualTo(48));
        expect(button.width, greaterThanOrEqualTo(44));
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
        await t.tap(find.text('Tekrar Dene'));
        await t.pumpAndSettle();
        expect(retries, 1);
      },
    );

    testWidgets(
      'Semantics: canlı bölge + mesaj okunur; "Tekrar Dene" ayrı etkin düğüm',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          _app(_full(notice(message: 'Kayıt başarısız.', onRetry: () {}))),
        );
        await t.pumpAndSettle();
        expect(
          t.getSemantics(_noticeText),
          isSemantics(label: 'Kayıt başarısız.', isLiveRegion: true),
        );
        expect(
          t.getSemantics(find.text('Tekrar Dene')),
          isSemantics(label: 'Tekrar Dene', isButton: true, hasTapAction: true),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'giriş Pop: ilk karede opaklık 0, 200 ms sonra tam; mesaj tek kez bulunur',
      (t) async {
        await t.pumpWidget(_app(_full(notice())));
        final opacity = find
            .descendant(of: _noticeFinder, matching: find.byType(Opacity))
            .first;
        expect(t.widget<Opacity>(opacity).opacity, 0);
        await t.pump(const Duration(milliseconds: 100));
        expect(t.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1.01));
        await t.pumpAndSettle();
        expect(t.widget<Opacity>(opacity).opacity, 1);
        expect(find.text('E-posta veya şifre hatalı.'), findsOneWidget);
      },
    );

    testWidgets(
      'hareket azaltma: ilk karede son durum (tek pump), ticker yok',
      (t) async {
        await t.pumpWidget(_app(_full(notice(onRetry: () {})), reduce: true));
        final opacity = find
            .descendant(of: _noticeFinder, matching: find.byType(Opacity))
            .first;
        expect(t.widget<Opacity>(opacity).opacity, 1);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'mesaj değişince yeniden belirir (Pop yeniden başlar); eski mesaj ağaçta kalmaz',
      (t) async {
        await t.pumpWidget(_app(_full(notice(message: 'Birinci hata'))));
        await t.pumpAndSettle();
        await t.pumpWidget(_app(_full(notice(message: 'İkinci hata'))));
        expect(find.text('Birinci hata'), findsNothing);
        expect(find.text('İkinci hata'), findsOneWidget);
        final opacity = find
            .descendant(of: _noticeFinder, matching: find.byType(Opacity))
            .first;
        expect(
          t.widget<Opacity>(opacity).opacity,
          0,
          reason: 'yeniden belirdi',
        );
        await t.pumpAndSettle();
        expect(t.widget<Opacity>(opacity).opacity, 1);
      },
    );

    testWidgets(
      'uzun mesaj kırpılmadan sarar (320 x 2,0): satır sınırı/elips yok',
      (t) async {
        const long =
            'Bu hata mesajı çok uzundur ve dar ekranda büyük yazı ölçeğinde birçok satıra sarar; hiçbir yerde kırpılmaz.';
        await pumpAt(
          t,
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: notice(message: long, onRetry: () {}),
          ),
        );
        final para = t.renderObject<RenderParagraph>(find.text(long));
        expect(para.didExceedMaxLines, isFalse);
        expect(para.maxLines, isNull);
        expect(para.overflow, isNot(TextOverflow.ellipsis));
      },
    );

    testWidgets('pumpAndSettle biter (açık + koyu, tekrar dene ile)', (
      t,
    ) async {
      for (final dark in [false, true]) {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpWidget(_app(_full(notice(onRetry: () {})), dark: dark));
        final elapsed = await _settle(t);
        expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 400)));
        expect(t.binding.transientCallbackCount, 0);
      }
    });

    Widget notices() => Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          notice(),
          const SizedBox(height: AppSpace.sm),
          notice(
            tone: AppTone.success,
            message: 'Doğrulama kodu e-posta adresinize gönderildi.',
          ),
          const SizedBox(height: AppSpace.sm),
          notice(
            tone: AppTone.warning,
            message:
                'Bu işlem geri alınamaz; devam etmeden önce emin olun lütfen.',
            onRetry: () {},
          ),
          const SizedBox(height: AppSpace.sm),
          notice(
            tone: AppTone.info,
            message:
                'Çok uzun bir bilgi mesajı: birkaç satıra sarar ve kutuyu uzatır.',
            onRetry: () {},
          ),
        ],
      ),
    );

    testWidgets('bildirimler x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(t, notices(), width: width, scale: scale, dark: dark);
        expect(_noticeFinder, findsNWidgets(4));
        for (var i = 0; i < 4; i++) {
          expect(
            t.getSize(_noticeFinder.at(i)).width,
            width - 2 * AppSpace.lg,
            reason: 'bildirim $i ($width x $scale dark=$dark)',
          );
        }
        for (final retry in find.byType(TextButton).evaluate().toList()) {
          expect(
            t.getSize(find.byWidget(retry.widget)).height,
            greaterThanOrEqualTo(48),
          );
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('hareket azaltma ile de taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, notices(), reduce: true);
      expect(_noticeFinder, findsNWidgets(4));
    });
  });

  group('Bileşim: kart içinde başlık + rozetler + bildirim + boş durum', () {
    Widget screen() => Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: AppCard(
        accentBar: AppTone.violet.hue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Yetkili Kapılar',
              count: 2,
              countSuffix: ' Kapı',
              icon: Icons.door_front_door_rounded,
              trailing: IconButton(
                tooltip: 'Yenile',
                onPressed: () {},
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                StatusChip(
                  label: 'Çevrimiçi',
                  tone: AppTone.success,
                  pulse: true,
                ),
                StatusChip(label: 'Yerel Ağ', tone: AppTone.warning),
                StatusChip(label: 'Çevrimdışı', tone: AppTone.danger),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            InlineNotice(
              message: 'Kapı durumu alınamadı. Bağlantınızı kontrol edin.',
              onRetry: () {},
            ),
            const Divider(),
            const EmptyState.compact(
              icon: Icons.history_rounded,
              title: 'Henüz geçiş kaydı bulunmuyor',
              message: 'Kapı geçişleri burada listelenir.',
            ),
          ],
        ),
      ),
    );

    testWidgets(
      'gerçek kullanım bileşimi x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu',
      (t) async {
        await forEachHarnessCell((width, scale, dark) async {
          await pumpAt(t, screen(), width: width, scale: scale, dark: dark);
          expect(_cardFinder, findsOneWidget);
          expect(
            t.getSize(_cardFinder).width,
            width - 2 * AppSpace.lg,
            reason: 'kart tam genişlik ($width x $scale dark=$dark)',
          );
          for (final type in [
            SectionHeader,
            StatusChip,
            InlineNotice,
            EmptyState,
          ]) {
            expect(find.byType(type), findsWidgets, reason: '$type');
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'bileşim kararlı durumda sakin: nabız 3 turda biter, pumpAndSettle biter',
      (t) async {
        await t.pumpWidget(harnessApp(screen()));
        final elapsed = await _settle(t);
        expect(elapsed, lessThan(const Duration(seconds: 4)));
        expect(t.binding.transientCallbackCount, 0);
      },
    );
  });
}
