// FAZ 5 / A1b (i): AppDialog ve AppDialogHeader widget testleri.
//
// AlertDialog döndürme (bulucular bozulmaz), başlık şeridi, eylem satırı, içerik kaydırma, sabit
// içerik genişliği, hareket azaltma, pumpAndSettle'ın bitmesi, Semantics, en az 44 dp eylem hedefi ve
// taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu; diyalog gerçek `showDialog` ile açılır).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

import 'harness.dart';

AppPalette _palette(bool dark) => dark ? AppPalette.dark : AppPalette.light;

/// pumpAndSettle kaç kare ilerlediğini döndürür (100 ms'lik adımlar): geçen yaklaşık süre.
Future<Duration> _settle(WidgetTester t) async =>
    Duration(milliseconds: await t.pumpAndSettle() * 100);

Finder get _alert => find.byType(AlertDialog);
Finder get _header => find.byType(AppDialogHeader);

/// Başlık şeridinin ikon karosu (44 dp).
Finder get _iconTile => find.descendant(
  of: _header,
  matching: find.byWidgetPredicate(
    (w) => w is SizedBox && w.width == 44 && w.height == 44,
  ),
);

Widget _dialog({
  String title = 'Şifremi Unuttum',
  String? subtitle = 'E-posta adresinizi girin',
  IconData? icon = Icons.lock_reset_rounded,
  AppTone tone = AppTone.primary,
  Widget child = const Text('Şifre sıfırlama bağlantısı gönderilecek.'),
  List<Widget>? actions,
}) => AppDialog(
  title: title,
  subtitle: subtitle,
  icon: icon,
  tone: tone,
  actions:
      actions ??
      [
        TextButton(onPressed: () {}, child: const Text('Vazgeç')),
        FilledButton(onPressed: () {}, child: const Text('Gönder')),
      ],
  child: child,
);

/// [dialog]'u gerçek `showDialog` ile açar (harness ölçü/ölçek/tema/hareket ayarlarıyla).
Future<void> _open(
  WidgetTester t,
  Widget dialog, {
  double width = 412,
  double height = 800,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
}) async {
  await pumpAt(
    t,
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () =>
            showDialog<void>(context: context, builder: (_) => dialog),
        child: const Text('Aç'),
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
  await t.tap(find.text('Aç'));
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  group('AppDialog: yapı', () {
    testWidgets(
      'AlertDialog DÖNDÜRÜR (bulucu tek); başlık = AppDialogHeader; titlePadding sıfır; kenar boşluğu 16/24',
      (t) async {
        await _open(t, _dialog());
        expect(_alert, findsOneWidget);
        final alert = t.widget<AlertDialog>(_alert);
        expect(alert.title, isA<AppDialogHeader>());
        expect(
          alert.scrollable,
          isTrue,
          reason: 'başlık + içerik birlikte kaydırılır',
        );
        expect(alert.titlePadding, EdgeInsets.zero);
        expect(
          alert.insetPadding,
          const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.xl,
          ),
        );
        expect(
          alert.contentPadding,
          const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.md),
        );
        expect(
          alert.actionsPadding,
          const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
        );
        expect(alert.actions, hasLength(2));
        expect(find.text('Şifremi Unuttum'), findsOneWidget);
        expect(find.text('E-posta adresinizi girin'), findsOneWidget);
        expect(
          find.text('Şifre sıfırlama bağlantısı gönderilecek.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('eylem sırası: iptal solda, birincil sağda; ikisi de çalışır', (
      t,
    ) async {
      var cancels = 0;
      var submits = 0;
      await _open(
        t,
        _dialog(
          actions: [
            TextButton(onPressed: () => cancels++, child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => submits++,
              child: const Text('Gönder'),
            ),
          ],
        ),
      );
      expect(
        t.getTopLeft(find.text('Vazgeç')).dx,
        lessThan(t.getTopLeft(find.text('Gönder')).dx),
      );
      expect(
        t.getRect(find.byType(FilledButton)).right,
        lessThanOrEqualTo(t.getRect(find.byType(AlertDialog)).right),
        reason: 'birincil eylem sağ uçta',
      );
      await t.tap(find.text('Vazgeç'));
      await t.tap(find.text('Gönder'));
      expect((cancels, submits), (1, 1));
    });

    testWidgets(
      'eylem yoksa eylem alanı eklenmez ve içerik altında 24 dp boşluk kalır',
      (t) async {
        await _open(t, _dialog(actions: const []));
        final alert = t.widget<AlertDialog>(_alert);
        expect(alert.actions, isNull);
        expect(find.byType(OverflowBar), findsNothing);
        expect(
          alert.contentPadding,
          const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
        );
      },
    );

    testWidgets(
      'birincil eylem Navigator.pop ile kapatır; bariyere dokunmak kapatır',
      (t) async {
        await _open(
          t,
          Builder(
            builder: (context) => _dialog(
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          ),
        );
        await t.tap(find.text('Tamam'));
        await t.pumpAndSettle();
        expect(_alert, findsNothing);
        // Yeniden aç ve bariyerden kapat.
        await t.tap(find.text('Aç'));
        await t.pumpAndSettle();
        expect(_alert, findsOneWidget);
        await t.tapAt(const Offset(2, 2));
        await t.pumpAndSettle();
        expect(_alert, findsNothing);
      },
    );

    testWidgets(
      'içerik genişliği dialogWidthForScreen (SABİT; IntrinsicWidth için)',
      (t) async {
        for (final width in [320.0, 412.0, 820.0]) {
          await _open(t, _dialog(), width: width);
          final content = find.descendant(
            of: _alert,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width != null && w.width! >= 260,
            ),
          );
          expect(
            content,
            findsOneWidget,
            reason: 'sabit genişlikli içerik @ $width',
          );
          final context = t.element(_alert);
          final expected = dialogWidthForScreen(context);
          expect(t.widget<SizedBox>(content).width, expected);
          expect(
            t.getSize(content).width,
            lessThanOrEqualTo(expected),
            reason: 'ekrana sığacak kadar kısılabilir',
          );
          expect(
            t
                .getRect(
                  find
                      .descendant(of: _alert, matching: find.byType(Material))
                      .first,
                )
                .width,
            lessThanOrEqualTo(width - 2 * AppSpace.lg),
            reason: 'diyalog ekrana sığar @ $width',
          );
        }
        // Geniş ekranda sınır 420 dp.
        await _open(t, _dialog(), width: 820);
        expect(
          t
              .getSize(
                find.descendant(
                  of: _alert,
                  matching: find.byWidgetPredicate(
                    (w) => w is SizedBox && w.width != null && w.width! >= 260,
                  ),
                ),
              )
              .width,
          420,
        );
      },
    );

    testWidgets('320 px ekranda diyalog 288 dp (kenar boşluğu 16): taşma yok', (
      t,
    ) async {
      await _open(t, _dialog(), width: 320, height: 640, scale: 1.0);
      final box = t.getRect(
        find.descendant(of: _alert, matching: find.byType(Material)).first,
      );
      expect(box.width, 288);
      expect(box.left, AppSpace.lg);
    });
  });

  group('AppDialogHeader: başlık şeridi', () {
    testWidgets(
      'ikon karosu 44 dp (tint zemin, ink ikon 24) + başlık + alt başlık; iç boşluk 24/24/24/12 (açık + koyu)',
      (t) async {
        for (final dark in [false, true]) {
          final p = _palette(dark);
          await _open(t, _dialog(), dark: dark);
          final tone = AppTone.primary;
          final tile = t.widget<DecoratedBox>(
            find
                .ancestor(of: _iconTile, matching: find.byType(DecoratedBox))
                .first,
          );
          final deco = tile.decoration as BoxDecoration;
          expect(deco.color, tone.tint(p));
          expect(deco.borderRadius, BorderRadius.circular(AppRadius.md));
          expect(t.getSize(_iconTile), const Size(44, 44));
          final icon = t.widget<Icon>(find.byIcon(Icons.lock_reset_rounded));
          expect(icon.size, 24);
          expect(icon.color, tone.ink(p));
          // İç boşluk.
          final header = t.getTopLeft(_header);
          expect(
            t.getTopLeft(_iconTile) - header,
            const Offset(AppSpace.xl, AppSpace.xl),
          );
          expect(
            t.getBottomLeft(_header).dy -
                t.getBottomLeft(find.text('E-posta adresinizi girin')).dy,
            greaterThanOrEqualTo(AppSpace.md),
            reason: 'alt iç boşluk >= 12',
          );
          // Metin stilleri.
          final title = t.widget<Text>(find.text('Şifremi Unuttum'));
          expect(title.style!.fontSize, 18, reason: 'titleLarge');
          expect(title.style!.color, p.text);
          expect(title.maxLines, 3);
          final subtitle = t.widget<Text>(
            find.text('E-posta adresinizi girin'),
          );
          expect(subtitle.style!.fontSize, 12, reason: 'bodySmall');
          expect(subtitle.style!.color, p.textMuted);
          expect(subtitle.maxLines, 3);
          // Başlık ikon karosunun 12 dp sağında.
          expect(
            t.getTopLeft(find.text('Şifremi Unuttum')).dx,
            t.getTopRight(_iconTile).dx + AppSpace.md,
          );
        }
      },
    );

    testWidgets('7 ton: karo zemini tint, ikon ink (açık + koyu)', (t) async {
      for (final dark in [false, true]) {
        final p = _palette(dark);
        for (final tone in AppTone.values) {
          await t.pumpWidget(
            harnessApp(
              Center(
                child: AppDialogHeader(
                  title: 'Başlık',
                  icon: Icons.warning_amber_rounded,
                  tone: tone,
                ),
              ),
              dark: dark,
            ),
          );
          await t.pumpAndSettle(); // tema geçişi (200 ms) bitsin
          final tile = t.widget<DecoratedBox>(
            find
                .ancestor(of: _iconTile, matching: find.byType(DecoratedBox))
                .first,
          );
          expect(
            (tile.decoration as BoxDecoration).color,
            tone.tint(p),
            reason: '${tone.name} dark=$dark',
          );
          expect(
            t.widget<Icon>(find.byIcon(Icons.warning_amber_rounded)).color,
            tone.ink(p),
          );
        }
      }
    });

    testWidgets(
      'ikon ve alt başlık yoksa karo ve alt başlık çizilmez; başlık sol kenarda',
      (t) async {
        await t.pumpWidget(
          harnessApp(
            const Align(
              alignment: Alignment.topLeft,
              child: AppDialogHeader(title: 'Yalnız Başlık'),
            ),
          ),
        );
        expect(_iconTile, findsNothing);
        expect(find.byType(Icon), findsNothing);
        expect(find.text('Yalnız Başlık'), findsOneWidget);
        expect(t.getTopLeft(find.text('Yalnız Başlık')).dx, AppSpace.xl);
      },
    );

    testWidgets(
      'Dialog içinde tek başına kullanılır (cihaz sahiplenme / QR modalı biçimi)',
      (t) async {
        await t.pumpWidget(
          harnessApp(
            const Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDialogHeader(
                    title: 'Cihaz Sahiplen',
                    subtitle: 'Ambalaj kutusundaki QR kod ile bağlayın',
                    icon: Icons.qr_code_scanner_rounded,
                  ),
                  Padding(
                    padding: EdgeInsets.all(AppSpace.xl),
                    child: Text('içerik'),
                  ),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Cihaz Sahiplen'), findsOneWidget);
        expect(
          t.getTopLeft(find.text('içerik')).dy,
          greaterThan(
            t
                .getBottomLeft(
                  find.text('Ambalaj kutusundaki QR kod ile bağlayın'),
                )
                .dy,
          ),
        );
      },
    );

    testWidgets('başlık ve alt başlık en çok 3 satır + elips (320 x 2,0)', (
      t,
    ) async {
      await _open(
        t,
        _dialog(
          title:
              'Çok uzun bir diyalog başlığı: birçok satıra sarar ve üç satırda kırpılır elbette',
          subtitle:
              'Çok uzun bir alt başlık metni: dar ekranda büyük yazıda birçok satıra sarar ve kırpılır',
        ),
        width: 320,
        height: 640,
        scale: 2.0,
      );
      final title = t.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').startsWith('Çok uzun bir diyalog'),
        ),
      );
      expect(title.maxLines, 3);
      expect(title.didExceedMaxLines, isTrue);
      final subtitle = t.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (w) =>
              w is Text && (w.data ?? '').startsWith('Çok uzun bir alt başlık'),
        ),
      );
      expect(subtitle.maxLines, 3);
      expect(subtitle.didExceedMaxLines, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'gerçek başlık + alt başlık 360 x 1,5\'te KIRPILMAZ; 320 x 2,0\'da en çok 3 satır ve taşma yok',
      (t) async {
        for (final dark in [false, true]) {
          await _open(
            t,
            _dialog(
              title: 'Şifremi Unuttum',
              subtitle: 'E-posta adresinizi girin',
            ),
            width: 360,
            height: 640,
            scale: 1.5,
            dark: dark,
          );
          for (final text in ['Şifremi Unuttum', 'E-posta adresinizi girin']) {
            final para = t.renderObject<RenderParagraph>(find.text(text));
            expect(
              para.didExceedMaxLines,
              isFalse,
              reason: '$text @ 360 x 1.5 dark=$dark',
            );
          }
        }
        // Test yazı tipi (Ahem) gerçek yazı tipinden ~2 kat geniştir: 320 x 2,0'da yalnız üst sınır
        // ve sığma sınanır.
        await _open(
          t,
          _dialog(
            title: 'Şifremi Unuttum',
            subtitle: 'E-posta adresinizi girin',
          ),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        for (final text in ['Şifremi Unuttum', 'E-posta adresinizi girin']) {
          expect(t.renderObject<RenderParagraph>(find.text(text)).maxLines, 3);
          expect(
            t.getSize(find.text(text)).width,
            lessThanOrEqualTo(320 - 2 * AppSpace.lg - 2 * AppSpace.xl),
          );
        }
        expect(t.takeException(), isNull);
      },
    );
  });

  group('AppDialog: Semantics', () {
    testWidgets('başlık "başlık" düğümüdür', (t) async {
      final handle = t.ensureSemantics();
      await _open(t, _dialog());
      final node = t.getSemantics(find.text('Şifremi Unuttum'));
      expect(node, isSemantics(isHeader: true));
      // Başlık + alt başlık tek "başlık" düğümünde birleşir (ekran okuyucu birlikte okur).
      final label = node.getSemanticsData().label;
      expect(label, contains('Şifremi Unuttum'));
      expect(label, contains('E-posta adresinizi girin'));
      handle.dispose();
    });

    testWidgets(
      'eylem düğmeleri ayrı, etkin düğümlerdir ve en az 44 dp (tüm ölçekler)',
      (t) async {
        final handle = t.ensureSemantics();
        for (final scale in kHarnessScales) {
          await _open(t, _dialog(), width: 360, height: 800, scale: scale);
          for (final label in ['Vazgeç', 'Gönder']) {
            expect(
              t.getSemantics(find.text(label)),
              isSemantics(
                label: label,
                isButton: true,
                isEnabled: true,
                hasTapAction: true,
              ),
              reason: '$label @ $scale',
            );
          }
          for (final type in [TextButton, FilledButton]) {
            final size = t.getSize(find.byType(type));
            expect(
              size.height,
              greaterThanOrEqualTo(44),
              reason: '$type @ $scale',
            );
            expect(
              size.width,
              greaterThanOrEqualTo(44),
              reason: '$type @ $scale',
            );
          }
        }
        handle.dispose();
      },
    );
  });

  group('AppDialog: taşma ve kaydırma', () {
    Widget tall() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextField(decoration: InputDecoration(labelText: 'E-posta')),
        const SizedBox(height: AppSpace.md),
        const InlineNotice(
          message:
              'E-posta adresi kayıtlı değil, kontrol edip yeniden deneyin.',
        ),
        const SizedBox(height: AppSpace.md),
        for (var i = 0; i < 12; i++)
          Text('Satır $i: uzun bir içerik satırı, dar ekranda sarar.'),
      ],
    );

    testWidgets(
      'uzun içerik 320 x 640 x 2,0\'da KAYDIRILIR; eylemler ekranda ve dokunulabilir kalır',
      (t) async {
        var submits = 0;
        await _open(
          t,
          _dialog(
            child: tall(),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Vazgeç')),
              FilledButton(
                onPressed: () => submits++,
                child: const Text('Gönder'),
              ),
            ],
          ),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        final scrollable = find.descendant(
          of: _alert,
          matching: find.byType(Scrollable),
        );
        expect(
          t.state<ScrollableState>(scrollable.first).position.maxScrollExtent,
          greaterThan(0),
          reason: 'içerik kaydırılır',
        );
        final screen = const Rect.fromLTWH(0, 0, 320, 640);
        expect(
          screen.contains(t.getTopLeft(find.byType(FilledButton))),
          isTrue,
        );
        expect(
          screen.contains(t.getBottomRight(find.byType(FilledButton))),
          isTrue,
        );
        expect(
          screen.contains(t.getTopLeft(find.text('Şifremi Unuttum'))),
          isTrue,
        );
        await t.tap(find.text('Gönder'));
        expect(submits, 1);
        // Kaydırınca son satıra ulaşılır.
        await t.drag(find.byType(TextField), const Offset(0, -1500));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'dar/büyük yazıda eylemler alt alta (OverflowBar), hepsi görünür ve ekran içinde',
      (t) async {
        await _open(
          t,
          _dialog(
            actions: [
              TextButton(onPressed: () {}, child: const Text('Vazgeç')),
              TextButton(onPressed: () {}, child: const Text('Sonra Hatırlat')),
              FilledButton(onPressed: () {}, child: const Text('Gönder')),
            ],
          ),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        final rects = [
          for (final label in ['Vazgeç', 'Sonra Hatırlat', 'Gönder'])
            t.getRect(find.text(label)),
        ];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].overlaps(rects[j]),
              isFalse,
              reason: 'eylem $i ve $j üst üste binmez',
            );
            expect(
              (rects[i].center.dy - rects[j].center.dy).abs(),
              greaterThan(20),
              reason: 'alt alta dizilir',
            );
          }
          expect(
            const Rect.fromLTWH(0, 0, 320, 640).contains(rects[i].center),
            isTrue,
          );
        }
      },
    );

    testWidgets(
      'klavye açıkken taşma yok: 360 x 640 x 1,5 (300 dp) ve yatay 640 x 360 (200 dp)',
      (t) async {
        for (final (w, h, scale, keyboard) in [
          (360.0, 640.0, 1.0, 300.0),
          (360.0, 640.0, 1.5, 300.0),
          (320.0, 640.0, 2.0, 280.0),
          (640.0, 360.0, 1.0, 200.0),
          (640.0, 360.0, 1.5, 200.0),
        ]) {
          t.view.viewInsets = FakeViewPadding(bottom: keyboard);
          addTearDown(t.view.resetViewInsets);
          await _open(
            t,
            _dialog(child: tall()),
            width: w,
            height: h,
            scale: scale,
          );
          expect(
            t.takeException(),
            isNull,
            reason: '$w x $h x $scale kb=$keyboard',
          );
          expect(_alert, findsOneWidget);
          expect(
            const Rect.fromLTWH(
              0,
              0,
              1000,
              1000,
            ).contains(t.getCenter(find.text('Gönder'))),
            isTrue,
          );
        }
      },
    );

    testWidgets(
      'başlık içerikle BİRLİKTE kaydırılır; eylem satırı SABİT kalır',
      (t) async {
        await _open(
          t,
          _dialog(child: tall()),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        final titleBefore = t.getTopLeft(find.text('Şifremi Unuttum')).dy;
        final actionBefore = t.getRect(find.byType(FilledButton));
        await t.drag(find.byType(TextField), const Offset(0, -400));
        await t.pumpAndSettle();
        expect(
          t.getTopLeft(find.text('Şifremi Unuttum')).dy,
          lessThan(titleBefore - 50),
          reason: 'başlık içerikle birlikte yukarı kaydı',
        );
        expect(
          t.getRect(find.byType(FilledButton)),
          actionBefore,
          reason: 'eylemler sabit',
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'içerikte EmptyState (tam ve kompakt) taşma/hata vermez (IntrinsicWidth güvenli)',
      (t) async {
        for (final compact in [false, true]) {
          await _open(
            t,
            _dialog(
              child: compact
                  ? const EmptyState.compact(
                      icon: Icons.group_off_rounded,
                      title: 'Henüz sakin yok',
                      message: 'Sakinler davet edildikçe burada listelenir.',
                    )
                  : const EmptyState(
                      icon: Icons.group_off_rounded,
                      title: 'Henüz sakin yok',
                      message: 'Sakinler davet edildikçe burada listelenir.',
                    ),
            ),
            width: 320,
            height: 640,
            scale: 2.0,
          );
          expect(find.text('Henüz sakin yok'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
      },
    );

    Widget content() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Bu işlem geri alınamaz. Devam etmek için kullanıcı adınızı ve şifrenizi yeniden girin.',
        ),
        const SizedBox(height: AppSpace.md),
        const TextField(
          decoration: InputDecoration(labelText: 'Kullanıcı adı'),
        ),
        const SizedBox(height: AppSpace.sm),
        const InlineNotice(
          message: 'Girilen şifre hatalı, lütfen yeniden deneyin.',
          onRetry: null,
        ),
        const SizedBox(height: AppSpace.sm),
        SwitchListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Beni hatırla'),
        ),
      ],
    );

    testWidgets(
      'diyalog x 320/360/412/820 x 1,0/1,5/2,0 x açık/koyu (2 eylem, ikonlu)',
      (t) async {
        await forEachHarnessCell((width, scale, dark) async {
          await _open(
            t,
            _dialog(child: content()),
            width: width,
            height: 640,
            scale: scale,
            dark: dark,
          );
          expect(_alert, findsOneWidget);
          final box = t.getRect(
            find.descendant(of: _alert, matching: find.byType(Material)).first,
          );
          expect(
            box.width,
            lessThanOrEqualTo(width - 2 * AppSpace.lg + 0.01),
            reason: 'diyalog ekrana sığar ($width x $scale dark=$dark)',
          );
          expect(
            box.height,
            lessThanOrEqualTo(640 - 2 * AppSpace.xl + 0.01),
            reason: 'diyalog yüksekliği sınırlı ($width x $scale dark=$dark)',
          );
          for (final label in ['Vazgeç', 'Gönder']) {
            expect(
              const Rect.fromLTWH(
                0,
                0,
                820,
                640,
              ).contains(t.getCenter(find.text(label))),
              isTrue,
            );
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    testWidgets('diyalog x tüm hücreler (3 eylem, ikonsuz, çok uzun başlık)', (
      t,
    ) async {
      await forEachHarnessCell((width, scale, dark) async {
        await _open(
          t,
          _dialog(
            icon: null,
            title:
                'Çok uzun bir diyalog başlığı: yönetici davetini kabul etmek üzeresiniz',
            subtitle: null,
            child: tall(),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Vazgeç')),
              OutlinedButton(onPressed: () {}, child: const Text('Reddet')),
              FilledButton(onPressed: () {}, child: const Text('Kabul Et')),
            ],
          ),
          width: width,
          height: 640,
          scale: scale,
          dark: dark,
        );
        expect(_alert, findsOneWidget);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('AppDialog: yatay yönlendirme', () {
    testWidgets(
      'yatay ekranlar x 1,0/1,5/2,0 x açık/koyu: taşma yok (2 ve 3 eylem)',
      (t) async {
        for (final (w, h) in [(640.0, 360.0), (800.0, 360.0), (568.0, 320.0)]) {
          for (final scale in kHarnessScales) {
            for (final dark in [false, true]) {
              for (final actions in [2, 3]) {
                await _open(
                  t,
                  _dialog(
                    actions: [
                      TextButton(onPressed: () {}, child: const Text('Vazgeç')),
                      if (actions == 3)
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Daha Sonra'),
                        ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Gönder'),
                      ),
                    ],
                  ),
                  width: w,
                  height: h,
                  scale: scale,
                  dark: dark,
                );
                expect(_alert, findsOneWidget, reason: '$w x $h x $scale');
              }
            }
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('AppDialog: hareket azaltma ve animasyon', () {
    testWidgets(
      'hareket azaltmada da açılır/kapanır; pumpAndSettle biter; ticker kalmaz',
      (t) async {
        await _open(
          t,
          Builder(
            builder: (context) => _dialog(
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          ),
          reduce: true,
        );
        expect(_alert, findsOneWidget);
        expect(t.binding.transientCallbackCount, 0);
        await t.tap(find.text('Tamam'));
        final elapsed = await _settle(t);
        expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 500)));
        expect(_alert, findsNothing);
        expect(t.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('açık ve koyu temada pumpAndSettle biter, ticker kalmaz', (
      t,
    ) async {
      for (final dark in [false, true]) {
        await _open(t, _dialog(), dark: dark);
        final elapsed = await _settle(t);
        expect(elapsed, lessThanOrEqualTo(const Duration(milliseconds: 300)));
        expect(t.binding.transientCallbackCount, 0);
      }
    });

    testWidgets('başlık şeridi statiktir: kendi animasyonu/ticker\'ı yok', (
      t,
    ) async {
      await t.pumpWidget(
        harnessApp(
          const Align(
            alignment: Alignment.topLeft,
            child: AppDialogHeader(
              title: 'Başlık',
              subtitle: 'Alt başlık',
              icon: Icons.info_outline_rounded,
            ),
          ),
        ),
      );
      expect(t.binding.transientCallbackCount, 0);
      expect(find.byType(AnimatedContainer), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });
  });
}
