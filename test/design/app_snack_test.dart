// FAZ 5 / A1b-(iii): AppSnack widget testleri.
//
// Durumlar (tür -> simge + dolgu), mevcut SnackBar davranışı (4 sn, floating, kuyruğa girer), replace,
// eylem, taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu), hareket azaltma ve Semantics.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

import 'harness.dart';

const String _longMessage =
    'Bu e-posta adresiyle kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi. '
    'Lütfen gelen kutunuzu (ve gereksiz klasörünü) kontrol ediniz.';

/// SnackBar gösterecek bağlam: harness Scaffold'unun elemanı (MaterialApp'in ScaffoldMessenger'ı altında).
BuildContext _ctx(WidgetTester t) => t.element(find.byType(Scaffold));

/// Gösterilen SnackBar'ın giriş animasyonunu (250 ms) tamamlar.
Future<void> _enter(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

SnackBar _snack(WidgetTester t) => t.widget<SnackBar>(find.byType(SnackBar));

/// SnackBar yüzeyinin (Material) o anki dolgu rengi: tema rengi dahil gerçek renk.
Color _surfaceColor(WidgetTester t) {
  final material = find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
      .first;
  return t.widget<Material>(material).color!;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

IconData _iconOf(AppSnackKind kind) => switch (kind) {
  AppSnackKind.info => Icons.info_rounded,
  AppSnackKind.success => Icons.check_circle_rounded,
  AppSnackKind.warning => Icons.warning_amber_rounded,
  AppSnackKind.error => Icons.error_rounded,
};

void main() {
  group('AppSnack: türler (simge + tonlu dolgu)', () {
    for (final kind in AppSnackKind.values) {
      testWidgets('${kind.name}: mesaj, simge ve dolgu', (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0);
        AppSnack.show(_ctx(t), 'Kapı açılıyor... 🚪', kind: kind);
        await _enter(t);

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Kapı açılıyor... 🚪'), findsOneWidget);
        final icon = t.widget<Icon>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byIcon(_iconOf(kind)),
          ),
        );
        expect(icon.color, Colors.white);
        expect(icon.size, 20);

        final expected = switch (kind) {
          AppSnackKind.success => AppTone.success.b,
          AppSnackKind.warning => AppTone.warning.b,
          AppSnackKind.error => AppTone.danger.b,
          AppSnackKind.info => null,
        };
        expect(_snack(t).backgroundColor, expected);
        if (expected != null) {
          expect(_surfaceColor(t), expected);
        }
      });
    }

    testWidgets('info: dolgu TEMA SnackBar rengidir (açık ve koyu)', (t) async {
      for (final dark in const [false, true]) {
        await pumpAt(t, const SizedBox(), scale: 1.0, dark: dark);
        AppSnack.show(_ctx(t), 'Bilgi');
        await _enter(t);
        final theme = Theme.of(_ctx(t));
        expect(
          _surfaceColor(t),
          theme.snackBarTheme.backgroundColor,
          reason: dark ? 'koyu tema' : 'açık tema',
        );
        expect(
          _snack(t).backgroundColor,
          isNull,
          reason: 'info tema rengini kullanır',
        );
      }
    });

    testWidgets(
      'beyaz metin/simge tüm dolgularda >= 4,5:1 (tonlar ve tema rengi)',
      (t) async {
        for (final tone in [AppTone.success, AppTone.warning, AppTone.danger]) {
          expect(
            _contrast(Colors.white, tone.b),
            greaterThanOrEqualTo(4.5),
            reason: tone.name,
          );
        }
        for (final dark in const [false, true]) {
          final theme = dark ? AppTheme.dark() : AppTheme.light();
          expect(
            _contrast(Colors.white, theme.snackBarTheme.backgroundColor!),
            greaterThanOrEqualTo(4.5),
            reason: dark ? 'koyu tema info' : 'açık tema info',
          );
        }
      },
    );

    testWidgets('her türün simgesi farklıdır (renk tek başına anlam taşımaz)', (
      t,
    ) async {
      final icons = AppSnackKind.values.map(_iconOf).toSet();
      expect(icons, hasLength(AppSnackKind.values.length));
    });

    testWidgets('mesaj metni birebir gösterilir (Türkçe, emoji, tırnak)', (
      t,
    ) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      const message = '"Ana Kapı" kapısı açılıyor... ✅ Şifre güncellendi.';
      AppSnack.show(_ctx(t), message, kind: AppSnackKind.success);
      await _enter(t);
      expect(find.text(message), findsOneWidget);
    });
  });

  group('AppSnack: mevcut SnackBar davranışı', () {
    testWidgets(
      'varsayılan: floating, 4 sn, AppRadius.md köşe, en çok 4 satır',
      (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0);
        AppSnack.show(_ctx(t), 'Merhaba');
        await _enter(t);
        final snack = _snack(t);
        expect(snack.behavior, SnackBarBehavior.floating);
        expect(snack.duration, const Duration(seconds: 4));
        expect(AppSnack.defaultDuration, const Duration(seconds: 4));
        final shape = snack.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(AppRadius.md));
        final text = t.widget<Text>(find.text('Merhaba'));
        expect(text.maxLines, 4);
        expect(text.overflow, TextOverflow.ellipsis);
      },
    );

    testWidgets('verilen süre ve maxLines uygulanır', (t) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      AppSnack.show(
        _ctx(t),
        'Uzun',
        duration: const Duration(seconds: 6),
        maxLines: 7,
      );
      await _enter(t);
      expect(_snack(t).duration, const Duration(seconds: 6));
      expect(t.widget<Text>(find.text('Uzun')).maxLines, 7);
    });

    testWidgets('süre dolunca kendiliğinden kapanır; pumpAndSettle biter', (
      t,
    ) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      AppSnack.show(_ctx(t), 'Geçici', kind: AppSnackKind.warning);
      await t.pumpAndSettle();
      expect(
        find.text('Geçici'),
        findsOneWidget,
        reason: '3,9 sn dolmadan görünür',
      );
      await t.pump(const Duration(milliseconds: 3800));
      expect(find.text('Geçici'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('Geçici'), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('varsayılan: art arda mesajlar KUYRUĞA girer (replace=false)', (
      t,
    ) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      AppSnack.show(_ctx(t), 'Birinci');
      AppSnack.show(_ctx(t), 'İkinci');
      await _enter(t);
      expect(find.text('Birinci'), findsOneWidget);
      expect(find.text('İkinci'), findsNothing, reason: 'sırada bekler');
      // Birincinin süresi dolup çıkınca ikinci gelir.
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('İkinci'), findsOneWidget);
      expect(find.text('Birinci'), findsNothing);
    });

    testWidgets(
      'replace: true mevcut SnackBar\'ı HEMEN kaldırır ve sıradakileri atar',
      (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0);
        AppSnack.show(_ctx(t), 'Eski');
        AppSnack.show(_ctx(t), 'Sıradaki');
        await _enter(t);
        expect(find.text('Eski'), findsOneWidget);

        AppSnack.show(
          _ctx(t),
          'Yeni',
          kind: AppSnackKind.success,
          replace: true,
        );
        await t.pump();
        expect(
          find.text('Eski'),
          findsNothing,
          reason: 'hemen kalktı (çıkış animasyonu yok)',
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Yeni'), findsOneWidget);
        expect(find.text('Sıradaki'), findsNothing);

        // Atılan sıradaki mesaj sonradan da gelmez.
        await t.pump(const Duration(seconds: 4));
        await t.pumpAndSettle();
        expect(find.text('Yeni'), findsNothing);
        expect(find.text('Sıradaki'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('replace: true hiç SnackBar yokken de güvenli', (t) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      AppSnack.show(_ctx(t), 'Tek', replace: true);
      await _enter(t);
      expect(find.text('Tek'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'art arda replace: yalnız sonuncu görünür (animasyon kesilmesi hatası yok)',
      (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0);
        for (var i = 1; i <= 5; i++) {
          AppSnack.show(
            _ctx(t),
            'Mesaj $i',
            replace: true,
            kind: AppSnackKind.error,
          );
          await t.pump(const Duration(milliseconds: 40));
        }
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Mesaj 5'), findsOneWidget);
        for (var i = 1; i < 5; i++) {
          expect(find.text('Mesaj $i'), findsNothing);
        }
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'erişilebilir gezinme (TalkBack/VoiceOver) açıkken kuyruk ve replace de çalışır',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(accessibleNavigation: true),
              child: child!,
            ),
            home: const Scaffold(body: SizedBox()),
          ),
        );
        AppSnack.show(_ctx(t), 'A');
        AppSnack.show(_ctx(t), 'B');
        await _enter(t);
        expect(find.text('A'), findsOneWidget);
        expect(find.text('B'), findsNothing, reason: 'kuyrukta');

        AppSnack.show(_ctx(t), 'C', kind: AppSnackKind.error, replace: true);
        await _enter(t);
        expect(find.text('C'), findsOneWidget);
        expect(find.text('A'), findsNothing);
        expect(find.text('B'), findsNothing, reason: 'sıradaki atıldı');

        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('ScaffoldMessenger yoksa sessizce hiçbir şey yapmaz', (
      t,
    ) async {
      late BuildContext bare;
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              bare = context;
              return const SizedBox();
            },
          ),
        ),
      );
      AppSnack.show(bare, 'görünmez', kind: AppSnackKind.error, replace: true);
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('görünmez'), findsNothing);
    });

    testWidgets('düz MaterialApp (AppTheme yok) altında da çalışır', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AppSnack.show(
                  context,
                  'Düz tema',
                  kind: AppSnackKind.success,
                ),
                child: const Text('göster'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('göster'));
      await _enter(t);
      expect(find.text('Düz tema'), findsOneWidget);
      expect(_surfaceColor(t), AppTone.success.b);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'diyalog bağlamından da gösterilir (Navigator altındaki bağlam)',
      (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0);
        showDialog<void>(
          context: _ctx(t),
          builder: (dialogContext) => AlertDialog(
            content: TextButton(
              onPressed: () => AppSnack.show(
                dialogContext,
                'Diyalogdan',
                kind: AppSnackKind.success,
              ),
              child: const Text('kaydet'),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('kaydet'));
        await _enter(t);
        expect(find.text('Diyalogdan'), findsOneWidget);
      },
    );
  });

  group('AppSnack: eylem', () {
    testWidgets('eylem görünür ve dokununca çağrılır', (t) async {
      await pumpAt(t, const SizedBox(), scale: 1.0);
      var taps = 0;
      AppSnack.show(
        _ctx(t),
        'Silindi',
        kind: AppSnackKind.error,
        action: SnackBarAction(label: 'Geri Al', onPressed: () => taps++),
      );
      await _enter(t);
      expect(find.text('Geri Al'), findsOneWidget);
      await t.tap(find.text('Geri Al'));
      await t.pump();
      expect(taps, 1);
    });

    testWidgets(
      'tonlu dolguda etiketi belirtilmemiş eylem BEYAZ olur (okunur)',
      (t) async {
        for (final kind in [
          AppSnackKind.success,
          AppSnackKind.warning,
          AppSnackKind.error,
        ]) {
          await pumpAt(t, const SizedBox(), scale: 1.0);
          AppSnack.show(
            _ctx(t),
            'x',
            kind: kind,
            action: SnackBarAction(label: 'Tamam', onPressed: () {}),
          );
          await _enter(t);
          expect(
            t.widget<SnackBarAction>(find.byType(SnackBarAction)).textColor,
            Colors.white,
            reason: kind.name,
          );
        }
      },
    );

    testWidgets(
      'çağıranın verdiği eylem rengi ve etiketi korunur; info tema rengini kullanır',
      (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0);
        AppSnack.show(
          _ctx(t),
          'x',
          kind: AppSnackKind.error,
          action: SnackBarAction(
            label: 'Özel',
            textColor: Colors.yellow,
            onPressed: () {},
          ),
        );
        await _enter(t);
        expect(
          t.widget<SnackBarAction>(find.byType(SnackBarAction)).textColor,
          Colors.yellow,
        );

        AppSnack.show(
          _ctx(t),
          'y',
          replace: true,
          action: SnackBarAction(label: 'Bilgi', onPressed: () {}),
        );
        await _enter(t);
        expect(
          t.widget<SnackBarAction>(find.byType(SnackBarAction)).textColor,
          isNull,
          reason: 'info: eylem rengine dokunulmaz (tema)',
        );
      },
    );
  });

  group('AppSnack: taşma matrisi (320/360/412/820 x 1,0/1,5/2,0 x açık/koyu)', () {
    // Not: flutter test'in Ahem yazı tipinde her harf 1 em genişliğindedir (gerçek yazı tiplerinin ~2
    // katı): matris bilerek kötü durumu sınar. Düz `SnackBar(Text) + uzun etiketli eylem` bile 320 px x
    // 1,5+ ölçekte Ahem ile taşar (Flutter'ın eylem satırı sınırı; AppSnack'ten bağımsız), bu yüzden
    // matriste kısa etiketli eylem ('Tamam') kullanılır; uzun etiket ayrı testte gerçekçi genişliktedir.
    testWidgets(
      'uzun mesaj her türde ve eylemle her hücrede taşmaz, ekranda kalır',
      (t) async {
        await forEachHarnessCell((width, scale, dark) async {
          await pumpAt(
            t,
            const SizedBox(),
            width: width,
            scale: scale,
            dark: dark,
          );
          for (final kind in AppSnackKind.values) {
            for (final withAction in const [false, true]) {
              AppSnack.show(
                _ctx(t),
                _longMessage,
                kind: kind,
                replace: true,
                action: withAction
                    ? SnackBarAction(label: 'Tamam', onPressed: () {})
                    : null,
              );
              await _enter(t);
              expect(
                t.takeException(),
                isNull,
                reason:
                    '${width}px x$scale ${dark ? 'koyu' : 'açık'} ${kind.name} eylem=$withAction',
              );
              final rect = t.getRect(find.byType(SnackBar));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.bottom, lessThanOrEqualTo(640));
            }
          }
        });
      },
    );

    testWidgets(
      'uzun etiketli eylem (Tekrar Dene) 360 px x 1,0 yazıda taşmaz',
      (t) async {
        for (final kind in AppSnackKind.values) {
          await pumpAt(t, const SizedBox(), width: 360, scale: 1.0);
          AppSnack.show(
            _ctx(t),
            _longMessage,
            kind: kind,
            action: SnackBarAction(label: 'Tekrar Dene', onPressed: () {}),
          );
          await _enter(t);
          expect(t.takeException(), isNull, reason: kind.name);
          expect(find.text('Tekrar Dene'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'en çok 4 satır: 320 px x 2,0 yazıda uzun mesaj elipsle kısalır, taşmaz',
      (t) async {
        await pumpAt(t, const SizedBox(), width: 320, scale: 2.0);
        AppSnack.show(_ctx(t), _longMessage, kind: AppSnackKind.error);
        await _enter(t);
        final render = t.renderObject<RenderParagraph>(find.text(_longMessage));
        expect(
          render.didExceedMaxLines,
          isTrue,
          reason: '140 karakter 4 satıra sığmaz: elips',
        );
        // Ekran okuyucu her zaman TAM metni okur.
        final handle = t.ensureSemantics();
        await t.pump();
        expect(find.bySemanticsLabel(_longMessage), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets(
      'maxLines artırılınca uzun mesaj kısalmaz (şifre sıfırlama bildirimi gibi)',
      (t) async {
        await pumpAt(t, const SizedBox(), width: 360, scale: 1.0);
        AppSnack.show(
          _ctx(t),
          _longMessage,
          kind: AppSnackKind.success,
          maxLines: 12,
        );
        await _enter(t);
        final render = t.renderObject<RenderParagraph>(find.text(_longMessage));
        expect(render.didExceedMaxLines, isFalse);
      },
    );
  });

  group('AppSnack: hareket azaltma', () {
    testWidgets(
      'yerleşik animasyon kullanılır: görünür, süre dolunca kapanır, settle biter',
      (t) async {
        await pumpAt(t, const SizedBox(), scale: 1.0, reduce: true);
        AppSnack.show(_ctx(t), 'Sade', kind: AppSnackKind.success);
        await _enter(t);
        expect(find.text('Sade'), findsOneWidget);
        await t.pump(const Duration(seconds: 4));
        await t.pumpAndSettle();
        expect(find.text('Sade'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'animasyon stili verilmez: sonradan gelen mesaj görünen SnackBar\'ı bozmaz',
      (t) async {
        // snackBarAnimationStyle farklı süreyle verilseydi ScaffoldMessenger ortak denetleyiciyi
        // dispose edip yeniden yaratırdı (görünen SnackBar'ın animasyonu kesilirdi).
        await pumpAt(t, const SizedBox(), scale: 1.0);
        AppSnack.show(_ctx(t), 'A', kind: AppSnackKind.info);
        await t.pump(const Duration(milliseconds: 100));
        AppSnack.show(_ctx(t), 'B', kind: AppSnackKind.error);
        AppSnack.show(_ctx(t), 'C', kind: AppSnackKind.success, replace: true);
        await _enter(t);
        await t.pumpAndSettle();
        expect(find.text('C'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('AppSnack: Semantics', () {
    testWidgets(
      'SnackBar canlı bölgedir; etiket yalnız mesajdır (simge dışlanır)',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(t, const SizedBox(), scale: 1.0);
        AppSnack.show(_ctx(t), 'Kapı açılıyor.', kind: AppSnackKind.success);
        await _enter(t);
        expect(
          t.getSemantics(find.text('Kapı açılıyor.')),
          isSemantics(label: 'Kapı açılıyor.', isLiveRegion: true),
        );
        handle.dispose();
      },
    );

    testWidgets('eylem ayrı, dokunulabilir bir düğümdür', (t) async {
      final handle = t.ensureSemantics();
      await pumpAt(t, const SizedBox(), scale: 1.0);
      AppSnack.show(
        _ctx(t),
        'Silindi',
        kind: AppSnackKind.error,
        action: SnackBarAction(label: 'Geri Al', onPressed: () {}),
      );
      await _enter(t);
      expect(
        t.getSemantics(find.text('Geri Al')),
        isSemantics(label: 'Geri Al', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });
}
