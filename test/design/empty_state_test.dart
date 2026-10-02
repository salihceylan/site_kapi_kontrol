// FAZ 5 / A1b (i): EmptyState widget testleri.
//
// Durumlar (boş | boş + eylem | yalnız başlık | kompakt), giriş animasyonu ve hareket azaltma,
// pumpAndSettle'ın bitmesi, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu), sınırlı
// yükseklikte kaydırma, Semantics ve en az 44 dp dokunma hedefi.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

AppPalette _palette(bool dark) => dark ? AppPalette.dark : AppPalette.light;

/// pumpAndSettle kaç kare ilerlediğini döndürür (100 ms'lik adımlar): geçen yaklaşık süre.
Future<Duration> _settle(WidgetTester t) async =>
    Duration(milliseconds: await t.pumpAndSettle() * 100);

const String _title = 'Kayıtlı site bulunamadı.';
const String _message = 'Yeni bir site ekleyerek başlayabilirsiniz.';

Finder get _empty => find.byType(EmptyState);

/// İkon karosu: ton zeminli DecoratedBox (EmptyState altındaki ilk ton kutusu).
Finder get _tile => find
    .descendant(
      of: _empty,
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius != null &&
            (w.decoration as BoxDecoration).color != null,
      ),
    )
    .first;

Finder get _entranceOpacity =>
    find.descendant(of: _empty, matching: find.byType(Opacity)).first;

double _opacity(WidgetTester t) => t.widget<Opacity>(_entranceOpacity).opacity;

/// Girişteki yukarı kayma (dp): 8 -> 0.
double _rise(WidgetTester t) => t
    .widget<Transform>(
      find
          .descendant(of: _entranceOpacity, matching: find.byType(Transform))
          .first,
    )
    .transform
    .getTranslation()
    .y;

Widget _es({
  String title = _title,
  String? message = _message,
  String? actionLabel,
  VoidCallback? onAction,
  AppTone tone = AppTone.primary,
  bool compact = false,
  IconData icon = Icons.apartment_rounded,
}) => compact
    ? EmptyState.compact(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        tone: tone,
      )
    : EmptyState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        tone: tone,
      );

Widget _app(Widget w, {bool dark = false, bool reduce = false}) =>
    harnessApp(w, dark: dark, reduce: reduce);

void main() {
  group('EmptyState: görünüm ve durumlar', () {
    testWidgets(
      'ikon karosu (64 dp, tint zemin, ink ikon 32) + başlık + mesaj, ortalı (7 ton x açık/koyu)',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          for (final tone in AppTone.values) {
            await t.pumpWidget(_app(_es(tone: tone), dark: dark));
            await t.pumpAndSettle();
            final box =
                t.widget<DecoratedBox>(_tile).decoration as BoxDecoration;
            expect(box.color, tone.tint(p), reason: '${tone.name} dark=$dark');
            expect(box.borderRadius, BorderRadius.circular(AppRadius.lg));
            expect(t.getSize(_tile), const Size(64, 64));
            final icon = t.widget<Icon>(find.byIcon(Icons.apartment_rounded));
            expect(icon.size, 32);
            expect(icon.color, tone.ink(p));
            final title = t.widget<Text>(find.text(_title));
            expect(title.textAlign, TextAlign.center);
            expect(title.style!.fontSize, 15.5, reason: 'titleMedium');
            expect(title.style!.color, p.text);
            final message = t.widget<Text>(find.text(_message));
            expect(message.textAlign, TextAlign.center);
            expect(message.style!.color, p.textSecondary);
            // Yatayda ortalı.
            final screen = t.getSize(find.byType(Scaffold)).width;
            expect(t.getCenter(find.text(_title)).dx, closeTo(screen / 2, 1));
            expect(t.getCenter(_tile).dx, closeTo(screen / 2, 1));
          }
        }
      },
    );

    testWidgets('yalnız başlık: mesaj yok, eylem yok', (t) async {
      await t.pumpWidget(_app(_es(message: null)));
      await t.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_message), findsNothing);
      expect(find.byType(PrimaryActionButton), findsNothing);
    });

    testWidgets(
      'eylem YALNIZ actionLabel ve onAction birlikte verilince gösterilir',
      (t) async {
        await t.pumpWidget(_app(_es(actionLabel: 'Site Ekle')));
        expect(
          find.byType(PrimaryActionButton),
          findsNothing,
          reason: 'onAction yok',
        );
        await t.pumpWidget(_app(_es(onAction: () {})));
        expect(
          find.byType(PrimaryActionButton),
          findsNothing,
          reason: 'actionLabel yok',
        );
        await t.pumpWidget(
          _app(_es(actionLabel: 'Site Ekle', onAction: () {})),
        );
        expect(find.byType(PrimaryActionButton), findsOneWidget);
        expect(find.text('Site Ekle'), findsOneWidget);
      },
    );

    testWidgets(
      'eylem: tonal, içerik genişliğinde, >= 48 dp, tek dokunma tek çağrı',
      (t) async {
        var calls = 0;
        await t.pumpWidget(
          _app(_es(actionLabel: 'Site Ekle', onAction: () => calls++)),
        );
        await t.pumpAndSettle();
        final button = t.widget<PrimaryActionButton>(
          find.byType(PrimaryActionButton),
        );
        expect(button.variant, AppButtonVariant.tonal);
        expect(button.expand, isFalse);
        final size = t.getSize(find.byType(PrimaryActionButton));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(44));
        await t.tap(find.text('Site Ekle'));
        await t.pumpAndSettle();
        expect(calls, 1);
      },
    );

    testWidgets(
      'en çok 360 dp genişlik: geniş ekranda içerik 360 dp\'yi aşmaz',
      (t) async {
        await pumpAt(
          t,
          SizedBox(
            width: double.infinity,
            child: _es(
              title: 'Çok uzun bir boş durum başlığı ' * 4,
              message: 'Çok uzun bir açıklama metni ' * 8,
            ),
          ),
          width: 820,
          scale: 1.0,
        );
        final content = find.descendant(
          of: _empty,
          matching: find.byType(SingleChildScrollView),
        );
        expect(t.getSize(content).width, lessThanOrEqualTo(360));
        expect(t.getCenter(content).dx, closeTo(410, 1), reason: 'ortalı');
      },
    );

    testWidgets(
      'ListView içinde (sınırsız yükseklik) içeriği kadar yer kaplar',
      (t) async {
        await t.pumpWidget(
          _app(
            ListView(
              children: [_es(actionLabel: 'Ekle', onAction: () {})],
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(t.getSize(_empty).height, lessThan(400));
        expect(find.text('Ekle'), findsOneWidget);
      },
    );

    testWidgets('bölüm içinde (Expanded) dikey ortalanır', (t) async {
      await t.pumpWidget(
        _app(
          Column(
            children: [
              const SizedBox(height: 100),
              Expanded(child: _es()),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      final area = Rect.fromLTWH(0, 100, 800, 600 - 100);
      expect(t.getCenter(_tile).dy, inInclusiveRange(area.top, area.bottom));
      final box = t.getRect(
        find.descendant(of: _empty, matching: find.byType(Padding)).first,
      );
      expect(box.center.dy, closeTo(area.center.dy, 2));
    });

    testWidgets(
      'sınırlı yükseklik + büyük yazı: taşma YOK, içerik KAYDIRILIR',
      (t) async {
        await pumpAt(
          t,
          SizedBox(
            height: 220,
            child: _es(actionLabel: 'Site Ekle', onAction: () {}),
          ),
          scale: 2.0,
        );
        final scrollable = find.descendant(
          of: _empty,
          matching: find.byType(Scrollable),
        );
        final position = t.state<ScrollableState>(scrollable).position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason: 'sığmayan içerik kaydırılır',
        );
        expect(t.takeException(), isNull);
        // Eylem kaydırınca görünür ve dokunulabilir.
        var calls = 0;
        await pumpAt(
          t,
          SizedBox(
            height: 220,
            child: _es(actionLabel: 'Site Ekle', onAction: () => calls++),
          ),
          scale: 2.0,
        );
        await t.ensureVisible(find.text('Site Ekle'));
        await t.pump();
        await t.tap(find.text('Site Ekle'));
        await t.pump();
        expect(calls, 1);
      },
    );

    testWidgets(
      'sığan içerik KAYDIRILMAZ (maxScrollExtent 0) ve üst PrimaryScrollController\'ı almaz',
      (t) async {
        await t.pumpWidget(_app(SizedBox(height: 500, child: _es())));
        await t.pumpAndSettle();
        final scrollable = find.descendant(
          of: _empty,
          matching: find.byType(Scrollable),
        );
        expect(
          t.state<ScrollableState>(scrollable).position.maxScrollExtent,
          0,
        );
        final view = t.widget<SingleChildScrollView>(
          find.descendant(
            of: _empty,
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(view.primary, isFalse);
      },
    );

    testWidgets('yasaklı dekor yok: BackdropFilter/ImageFiltered/ShaderMask', (
      t,
    ) async {
      await t.pumpWidget(_app(_es(actionLabel: 'Ekle', onAction: () {})));
      await t.pumpAndSettle();
      for (final type in [BackdropFilter, ImageFiltered, ShaderMask]) {
        expect(
          find.descendant(of: _empty, matching: find.byType(type)),
          findsNothing,
        );
      }
    });
  });

  group('EmptyState: kompakt', () {
    Widget compact({
      String? actionLabel,
      VoidCallback? onAction,
      bool dark = false,
    }) => _app(
      SizedBox(
        width: double.infinity,
        child: _es(
          compact: true,
          icon: Icons.history_rounded,
          title: 'Henüz kayıt yok',
          message: 'Kapı geçişleri burada listelenir.',
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
      dark: dark,
    );

    testWidgets(
      'satır düzeni: 40 dp ikon karosu solda, metin sağda ve sola hizalı',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          await t.pumpWidget(compact(dark: dark));
          await t.pumpAndSettle();
          final box = t.widget<DecoratedBox>(_tile).decoration as BoxDecoration;
          expect(box.color, AppTone.primary.tint(p));
          expect(box.borderRadius, BorderRadius.circular(AppRadius.sm));
          expect(t.getSize(_tile), const Size(40, 40));
          expect(t.widget<Icon>(find.byIcon(Icons.history_rounded)).size, 24);
          final tile = t.getRect(_tile);
          final title = t.getRect(find.text('Henüz kayıt yok'));
          final message = t.getRect(
            find.text('Kapı geçişleri burada listelenir.'),
          );
          expect(title.left, closeTo(tile.right + AppSpace.md, 0.5));
          expect(message.left, closeTo(title.left, 0.5), reason: 'sola hizalı');
          expect(message.top, greaterThanOrEqualTo(title.bottom));
          expect(
            t.widget<Text>(find.text('Henüz kayıt yok')).textAlign,
            isNot(TextAlign.center),
          );
          expect(tile.left, AppSpace.md, reason: 'kompakt iç boşluk 12');
        }
      },
    );

    testWidgets(
      'kartta tam genişlik kaplar; sabit 360 dp sınırı ve kaydırma yok',
      (t) async {
        await pumpAt(
          t,
          SizedBox(
            width: double.infinity,
            child: _es(compact: true, title: 'Henüz kayıt yok'),
          ),
          width: 820,
          scale: 1.0,
        );
        expect(t.getSize(_empty).width, 820);
        expect(
          find.descendant(
            of: _empty,
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('eylem metnin/karonun ALTINDA, sola hizalı; dokunulabilir', (
      t,
    ) async {
      var calls = 0;
      await t.pumpWidget(
        compact(actionLabel: 'Yenile', onAction: () => calls++),
      );
      await t.pumpAndSettle();
      final tile = t.getRect(_tile);
      final button = t.getRect(find.byType(PrimaryActionButton));
      expect(button.top, greaterThanOrEqualTo(tile.bottom));
      expect(button.left, AppSpace.md);
      expect(button.height, greaterThanOrEqualTo(48));
      await t.tap(find.text('Yenile'));
      expect(calls, 1);
    });

    testWidgets('Semantics: tek birleşik düğüm; eylem ayrı düğme', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(compact(actionLabel: 'Yenile', onAction: () {}));
      await t.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          'Henüz kayıt yok. Kapı geçişleri burada listelenir.',
        ),
        findsOneWidget,
      );
      expect(
        t.getSemantics(find.text('Yenile')),
        isSemantics(label: 'Yenile', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('EmptyState: giriş animasyonu ve hareket azaltma', () {
    testWidgets(
      '200 ms solma + 8 dp yukarı kayma: başlangıç 0 / 8, bitiş 1 / 0',
      (t) async {
        await t.pumpWidget(_app(_es()));
        expect(_opacity(t), 0);
        expect(_rise(t), closeTo(8, 0.01));
        await t.pump(const Duration(milliseconds: 100));
        expect(_opacity(t), inExclusiveRange(0, 1));
        expect(_rise(t), inExclusiveRange(0, 8));
        await t.pumpAndSettle();
        expect(_opacity(t), 1);
        expect(_rise(t), 0);
      },
    );

    testWidgets('kompakt da aynı girişi oynar', (t) async {
      await t.pumpWidget(
        _app(SizedBox(width: double.infinity, child: _es(compact: true))),
      );
      expect(_opacity(t), 0);
      await t.pumpAndSettle();
      expect(_opacity(t), 1);
    });

    testWidgets(
      'hareket azaltma: ilk karede son durum (opaklık 1, kayma 0), ticker yok',
      (t) async {
        await t.pumpWidget(
          _app(_es(actionLabel: 'Ekle', onAction: () {}), reduce: true),
        );
        expect(_opacity(t), 1);
        expect(_rise(t), 0);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'pumpAndSettle biter (kararlı durumda animasyon yok; açık + koyu; her iki düzen)',
      (t) async {
        for (final dark in [false, true]) {
          for (final compactLayout in [false, true]) {
            await t.pumpWidget(const SizedBox.shrink());
            await t.pumpWidget(
              _app(
                SizedBox(
                  width: double.infinity,
                  child: _es(
                    compact: compactLayout,
                    actionLabel: 'Ekle',
                    onAction: () {},
                  ),
                ),
                dark: dark,
              ),
            );
            final elapsed = await _settle(t);
            expect(
              elapsed,
              lessThanOrEqualTo(const Duration(milliseconds: 300)),
            );
            expect(t.binding.transientCallbackCount, 0);
          }
        }
      },
    );

    testWidgets('ilk karede (opaklık 0) bile anlamsal ağaçta bulunur', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_app(_es()));
      expect(_opacity(t), 0);
      expect(find.bySemanticsLabel('$_title. $_message'), findsOneWidget);
      handle.dispose();
    });
  });

  group('EmptyState: Semantics', () {
    testWidgets(
      'başlık + mesaj TEK düğüm ("başlık. mesaj"); ikon/metin tekrar okunmaz; eylem dışlanmaz',
      (t) async {
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          _app(_es(actionLabel: 'Site Ekle', onAction: () {})),
        );
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel('$_title. $_message'), findsOneWidget);
        expect(
          find.bySemanticsLabel(_title),
          findsNothing,
          reason: 'iç metin dışlandı',
        );
        expect(
          t.getSemantics(find.text('Site Ekle')),
          isSemantics(
            label: 'Site Ekle',
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
      },
    );

    testWidgets('mesaj yoksa etiket yalnız başlıktır', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_app(_es(message: null)));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel(_title), findsOneWidget);
      handle.dispose();
    });
  });

  group('EmptyState: taşma matrisi', () {
    Widget content() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _es(actionLabel: 'Yeni Site Oluştur', onAction: () {}),
        _es(
          title:
              'Aramanızla eşleşen kullanıcı bulunamadı, filtreyi değiştirin.',
          message:
              'Çok uzun bir açıklama metni: dar ekranda ve büyük yazıda birçok satıra sarar, kırpılmaz.',
          tone: AppTone.warning,
          icon: Icons.search_off_rounded,
          actionLabel: 'Filtreyi Temizle ve Tüm Kullanıcıları Göster',
          onAction: () {},
        ),
        _es(title: 'Kayıt yok', message: null, tone: AppTone.neutral),
        _es(
          compact: true,
          icon: Icons.history_rounded,
          title: 'Henüz geçiş kaydı bulunmuyor',
          message:
              'Kapı geçişleri burada listelenir; ilk geçişten sonra görünür.',
          actionLabel: 'Yenile',
          onAction: () {},
        ),
      ],
    );

    testWidgets('boş durumlar x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(t, content(), width: width, scale: scale, dark: dark);
        expect(_empty, findsNWidgets(4));
        for (var i = 0; i < 4; i++) {
          expect(
            t.getSize(_empty.at(i)).width,
            width,
            reason: 'boş durum $i ($width x $scale dark=$dark)',
          );
        }
        for (final button
            in find.byType(PrimaryActionButton).evaluate().toList()) {
          expect(
            t.getSize(find.byWidget(button.widget)).height,
            greaterThanOrEqualTo(48),
          );
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('sınırlı yükseklik (200 dp) x tüm hücreler: taşma yok', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          SizedBox(
            height: 200,
            child: _es(
              title: 'Aramanızla eşleşen kullanıcı bulunamadı.',
              actionLabel: 'Filtreyi Temizle',
              onAction: () {},
            ),
          ),
          width: width,
          scale: scale,
          dark: dark,
        );
        expect(_empty, findsOneWidget);
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('hareket azaltma ile de taşma yok (320 x 2,0)', (t) async {
      await pumpAt(t, content(), reduce: true);
      expect(_empty, findsNWidgets(4));
    });

    testWidgets('mesaj kırpılmaz: satır sınırı ve elips yok (320 x 2,0)', (
      t,
    ) async {
      const long =
          'Çok uzun bir açıklama metni: dar ekranda ve büyük yazıda birçok satıra sarar, hiçbir yerde kırpılmaz.';
      await pumpAt(
        t,
        SizedBox(
          width: double.infinity,
          child: _es(message: long),
        ),
      );
      final para = t.renderObject<RenderParagraph>(find.text(long));
      expect(para.didExceedMaxLines, isFalse);
      expect(para.overflow, isNot(TextOverflow.ellipsis));
    });
  });
}
