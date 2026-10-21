// FAZ 5 / A2-G2: DigitalClockWidget stil yaması (P'nin saat ayrıştırması KORUNUR) testleri.
//
// - Taşma matrisi: 320x640 x2,0 ve 360x640 x1,5; açık + koyu; üç rol; kullanıcı satırı açık/kapalı.
// - Tasarım: AppCard(accentBar: rol, seviye 1), StatusChip(info), metin gölgesi yok, tabular rakamlar,
//   renkler palet/ton belirteçlerinden, kontrast >= 4,5:1.
// - P sözleşmesi: saniyelik güncelleme yalnız saat metnini yeniden kurar (yeni bileşenler kurulmaz).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/digital_clock_widget.dart';

import '../design/harness.dart';
import '../support/rebuild_probe.dart';
import 'g2_support.dart';

final DateTime _fixedNow = DateTime(2026, 5, 1, 14, 35, 27);

Widget _clock({
  UserRole role = UserRole.superUser,
  bool showUserInfo = true,
  String fullName = 'Yönetici Ahmet Yılmaz Çok Uzun İsimli Kullanıcı',
  DateTime Function()? now,
}) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: DigitalClockWidget(
        session: g2Session(role: role, fullName: fullName),
        showUserInfo: showUserInfo,
        nowProvider: now ?? () => _fixedNow,
      ),
    ),
  );
}

void main() {
  tearDown(RebuildProbe.stop);

  group('taşma matrisi (320x640 x2,0 ve 360x640 x1,5; açık + koyu)', () {
    for (final role in UserRole.values) {
      testWidgets('rol: ${role.name}', (t) async {
        for (final cell in kG2Cells) {
          for (final dark in const <bool>[false, true]) {
            await pumpAt(
              t,
              _clock(role: role),
              width: cell.width,
              height: 640,
              scale: cell.scale,
              dark: dark,
            );
            expect(
              find.text('TSİ (UTC+3)'),
              findsOneWidget,
              reason: g2CellLabel(cell.width, cell.scale, dark),
            );
            expect(find.text('14:35:27'), findsOneWidget);
            expect(find.text('1 Mayıs 2026, Cuma'), findsOneWidget);
          }
        }
      });
    }

    testWidgets('kullanıcı satırı olmadan (showUserInfo: false)', (t) async {
      for (final cell in kG2Cells) {
        for (final dark in const <bool>[false, true]) {
          await pumpAt(
            t,
            _clock(showUserInfo: false),
            width: cell.width,
            height: 640,
            scale: cell.scale,
            dark: dark,
          );
          expect(find.byType(Divider), findsNothing);
          expect(find.byIcon(Icons.person_rounded), findsNothing);
        }
      }
    });

    testWidgets('çok dar (280 px) ve çok büyük yazı (2,0)', (t) async {
      await pumpAt(t, _clock(), width: 280, height: 640, scale: 2.0);
      await pumpAt(
        t,
        _clock(fullName: 'A'),
        width: 280,
        height: 640,
        scale: 2.0,
        dark: true,
      );
    });

    testWidgets(
      'hareket azaltma açıkken ve pumpAndSettle biter (kararlı durumda ticker yok)',
      (t) async {
        await pumpAt(t, _clock(), width: 360, scale: 1.0, reduce: true);
        await t.pumpAndSettle();
        await pumpAt(t, _clock(), width: 360, scale: 1.0);
        await t.pumpAndSettle();
      },
    );
  });

  group('düzen: saat ve rozet', () {
    testWidgets(
      'normal genişlikte (360 px x 1,0) saat ve rozet tek satırda (kompakt)',
      (t) async {
        await pumpAt(t, _clock(), width: 360, scale: 1.0);
        final time = t.getCenter(find.text('14:35:27'));
        final badge = t.getCenter(find.text('TSİ (UTC+3)'));
        expect((badge.dy - time.dy).abs(), lessThan(12), reason: 'aynı satır');
        expect(badge.dx, greaterThan(time.dx));
      },
    );

    testWidgets(
      'büyük yazıda (320 px x 2,0) rozet alt satıra iner; saat okunaklı kalır',
      (t) async {
        await pumpAt(t, _clock(), width: 320, scale: 2.0);
        final time = t.getRect(find.text('14:35:27'));
        final badge = t.getRect(find.text('TSİ (UTC+3)'));
        expect(
          badge.top,
          greaterThanOrEqualTo(time.bottom - 1),
          reason: 'rozet saatin altında',
        );
        // Saat yalnız taşmayacak kadar küçülür: yazı boyutu 24 x 2,0 = 48 dp'nin en az yarısı.
        expect(time.height, greaterThan(24));
      },
    );

    testWidgets(
      'kart tam genişlik ve tek AppCard (seviye 1); rol şeridi 3 dp',
      (t) async {
        for (final role in UserRole.values) {
          await pumpAt(t, _clock(role: role), width: 360, scale: 1.0);
          final card = t.widget<AppCard>(find.byType(AppCard));
          expect(card.level, 1);
          expect(
            card.accentBar,
            role.tone.hue,
            reason: 'rol vurgusu = ton rengi (şerit)',
          );
          expect(t.getSize(find.byType(AppCard)).width, closeTo(360 - 32, 0.5));
          final bar = find.descendant(
            of: find.byType(AppCard),
            matching: find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == role.tone.hue,
            ),
          );
          expect(bar, findsOneWidget, reason: role.name);
          expect(t.getSize(bar).height, 3);
        }
      },
    );
  });

  group('tipografi ve belirteçler', () {
    testWidgets(
      'saat: metin gölgesi yok, sabit genişlikli rakamlar, headlineMedium boyutu',
      (t) async {
        await pumpAt(t, _clock(), width: 360, scale: 1.0);
        final style = t.widget<Text>(find.text('14:35:27')).style!;
        expect(
          style.shadows,
          isNull,
          reason: 'Shadow her saniye yeniden boyanıyordu (W4)',
        );
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(style.fontFamily, 'monospace');
        expect(style.fontSize, 24);
        expect(style.fontWeight, FontWeight.w900);
      },
    );

    testWidgets(
      'renkler: saat = palet metni, tarih = ikincil, ad = palet metni (koyu/açık)',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          await pumpAt(t, _clock(), width: 360, scale: 1.0, dark: dark);
          expect(g2TextColor(t, find.text('14:35:27')), p.text);
          expect(
            g2TextColor(t, find.text('1 Mayıs 2026, Cuma')),
            p.textSecondary,
          );
          expect(
            g2TextColor(
              t,
              find.text('Yönetici Ahmet Yılmaz Çok Uzun İsimli Kullanıcı'),
            ),
            p.text,
          );
          for (final c in <Color>[p.text, p.textSecondary]) {
            expect(
              g2Contrast(c, p.surface),
              greaterThanOrEqualTo(4.5),
              reason: 'dark=$dark',
            );
          }
        }
      },
    );

    testWidgets(
      'TSİ rozeti StatusChip(info); bayrak emojisi ve metin korunur',
      (t) async {
        await pumpAt(t, _clock(), width: 360, scale: 1.0);
        final chip = t.widget<StatusChip>(
          find.widgetWithText(StatusChip, 'TSİ (UTC+3)'),
        );
        expect(chip.tone, AppTone.info);
        expect(
          chip.pulse,
          isFalse,
          reason: 'kararlı durumda sonsuz animasyon yok',
        );
        expect(find.text('🇹🇷 '), findsOneWidget);
      },
    );

    testWidgets('rol rozeti StatusChip(rol tonu) ve rol etiketi birebir', (
      t,
    ) async {
      for (final role in UserRole.values) {
        await pumpAt(t, _clock(role: role), width: 360, scale: 1.0);
        final chip = t.widget<StatusChip>(
          find.widgetWithText(StatusChip, role.label),
        );
        expect(chip.tone, role.tone, reason: role.name);
        expect(chip.icon, Icons.shield_outlined);
      }
    });

    testWidgets(
      'sade stil (G7): rol rozeti metni gövde metni rengi (zemin boyanmaz), avatar ve saat rozeti düz; ikonlar '
      'işaret renginde >= 4,5:1 (açık + koyu, her rol)',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          for (final role in UserRole.values) {
            await pumpAt(
              t,
              _clock(role: role),
              width: 360,
              scale: 1.0,
              dark: dark,
            );
            final ink = g2TextColor(t, find.text(role.label));
            expect(ink, p.textSecondary, reason: '${role.name} dark=$dark');
            // Rozet zemini: kart yüzeyi (StatusChip sade stilde boyamaz).
            expect(
              g2Contrast(ink, p.surface),
              greaterThanOrEqualTo(4.5),
              reason: '${role.name} dark=$dark',
            );
            // Avatar: rol tonlu düz rozet (IconOrb): soluk yüzey + ikon tonun işaret rengi.
            final avatarIcon = t.widget<Icon>(find.byIcon(Icons.person_rounded));
            expect(avatarIcon.color, role.tone.sign(p), reason: '${role.name} dark=$dark');
            final avatar = t.widget<IconOrb>(
              find
                  .ancestor(
                    of: find.byIcon(Icons.person_rounded),
                    matching: find.byType(IconOrb),
                  )
                  .first,
            );
            expect(avatar.tone, role.tone, reason: role.name);
            expect(
              g2Contrast(role.tone.sign(p), p.surfaceMuted),
              greaterThanOrEqualTo(4.5),
              reason: '${role.name} avatar dark=$dark',
            );
          }
          // Saat ikonu: düz info rozeti (IconOrb); bilgi durum tonu değildir: ikon gövde metni renginde.
          await pumpAt(t, _clock(), width: 360, scale: 1.0, dark: dark);
          final icon = t.widget<Icon>(
            find.byIcon(Icons.access_time_filled_rounded),
          );
          expect(icon.color, AppTone.info.sign(p));
          expect(
            g2Contrast(AppTone.info.sign(p), p.surfaceMuted),
            greaterThanOrEqualTo(4.5),
            reason: 'saat rozeti dark=$dark',
          );
          final clockOrb = t.widget<IconOrb>(
            find
                .ancestor(
                  of: find.byIcon(Icons.access_time_filled_rounded),
                  matching: find.byType(IconOrb),
                )
                .first,
          );
          expect(clockOrb.tone, AppTone.info);
          expect(clockOrb.glow, isFalse, reason: 'sakin: hero değil, glow yok');
        }
      },
    );
  });

  group('P sözleşmesi korunur: saniyelik güncelleme yalnız saat metnini kurar', () {
    testWidgets(
      '5 saniyede yeni bileşenler (AppCard, StatusChip, Wrap, Text dışı) yeniden kurulmaz',
      (t) async {
        var now = _fixedNow;
        await pumpAt(t, _clock(now: () => now), width: 360, scale: 1.0);
        expect(find.text('14:35:27'), findsOneWidget);

        RebuildProbe.start();
        for (var i = 0; i < 5; i++) {
          now = now.add(const Duration(seconds: 1));
          await t.pump(const Duration(seconds: 1));
        }
        expect(find.text('14:35:32'), findsOneWidget);
        expect(RebuildProbe.count(DigitalClockWidget), 0);
        expect(RebuildProbe.count(AppCard), 0);
        expect(RebuildProbe.count(StatusChip), 0);
        expect(RebuildProbe.count(LayoutBuilder), 0);
        expect(RebuildProbe.count(Wrap), 0);
        expect(RebuildProbe.count(Row), 0);
        expect(RebuildProbe.count(Column), 0);
        expect(
          RebuildProbe.count(Text),
          5,
          reason: 'yalnız saat metni (saniyede bir)',
        );
        expect(RebuildProbe.total, lessThanOrEqualTo(12));
      },
    );

    testWidgets(
      'saat metni kendi RepaintBoundary\'sinde (saniyelik boyama kartın katmanını bozmaz)',
      (t) async {
        await pumpAt(t, _clock(), width: 360, scale: 1.0);
        final nearest = find
            .ancestor(
              of: find.text('14:35:27'),
              matching: find.byType(RepaintBoundary),
            )
            .first;
        expect(
          t.getSize(nearest).height,
          lessThan(t.getSize(find.byType(AppCard)).height / 2),
        );
      },
    );
  });

  group(
    'geniş ekranlar (412 / 820 / 1100 px) ve yatay telefon (640x360); yazı 1,0',
    () {
      for (final role in UserRole.values) {
        testWidgets('rol: ${role.name}', (t) async {
          for (final size in const <({double w, double h})>[
            (w: 412, h: 640),
            (w: 820, h: 1180),
            (w: 1100, h: 800),
            (w: 640, h: 360),
          ]) {
            for (final dark in const <bool>[false, true]) {
              await pumpAt(
                t,
                _clock(role: role),
                width: size.w,
                height: size.h,
                scale: 1.0,
                dark: dark,
              );
              // Geniş ekranda saat ve rozet her zaman tek satırda.
              final time = t.getCenter(find.text('14:35:27'));
              final badge = t.getCenter(find.text('TSİ (UTC+3)'));
              expect(
                (badge.dy - time.dy).abs(),
                lessThan(12),
                reason: '${size.w}x${size.h}',
              );
            }
          }
        });
      }
    },
  );
}
