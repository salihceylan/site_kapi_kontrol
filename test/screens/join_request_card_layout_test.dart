// "Katılım Başvurularım" kartı (JoinRequestCard): cilalı site rozeti durumun tonunu taşır, durum
// rozeti (StatusChip) metinle birlikte durur; taşma yok (320x640 x2,0 ve 360x640 x1,5; açık + koyu).
// Kartı bireysel ana görünüm ile "Daireye Katıl" ekranı paylaşır: ekran testleri
// (individual_home_view_layout_test, join_and_setup_view_layout_test) kartın metinlerini ayrıca sınar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/join_request_card.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

/// Üç durum x uzun site adı/ayrıntı: kartlar ekran genişliğini kaplar (sayfa kabuğu gibi).
Widget _cards({bool details = true}) {
  return Builder(
    builder: (context) {
      final th = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final req in g4Requests())
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: JoinRequestCard(
                title: req.siteName ?? 'Site #${req.siteCode}',
                status: JoinRequestCard.statusOf(req),
                details: details
                    ? [
                        Text(
                          '${req.blockName?.isNotEmpty == true ? '${req.blockName} • ' : ''}Daire ${req.unitLabel ?? '-'}',
                          style: th.bodyMedium,
                        ),
                        if (req.notes?.isNotEmpty == true)
                          Text('Not: "${req.notes}"', style: th.bodySmall),
                      ]
                    : const <Widget>[],
              ),
            ),
        ],
      );
    },
  );
}

void main() {
  group('JoinRequestCard taşma matrisi', () {
    g4LayoutMatrix('üç durum: başlık, durum rozeti, ayrıntılar', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        SizedBox(width: double.infinity, child: _cards()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );
      for (final text in const <String>[
        'Güneş Sitesi',
        'Yeşilvadi Konutları Doğu Etap Sitesi',
        'Site #103',
        'Onay Bekliyor',
        'Onaylandı',
        'Reddedildi',
        'A Blok • Daire 12',
        'Daire 5',
        'Daire 8',
        'Not: "Daireye taşındım, kiracıyım"',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(AppCard),
        ),
        findsNothing,
        reason: 'kart-içinde-kart yok',
      );
    });
  });

  group('JoinRequestCard görsel dil', () {
    testWidgets('site rozeti (40 squircle) durumun tonunu taşır: bekliyor uyarı, onaylı başarı, reddedildi hata', (
      t,
    ) async {
      await pumpAt(
        t,
        SizedBox(width: double.infinity, child: _cards()),
        width: 360,
        scale: 1.0,
        height: 1000,
      );
      final orbs = t.widgetList<IconOrb>(find.byType(IconOrb)).toList();
      expect(orbs.map((o) => o.tone).toList(), <AppTone>[
        AppTone.warning,
        AppTone.success,
        AppTone.danger,
      ]);
      expect(
        orbs.every(
          (o) =>
              o.size == 40 &&
              o.shape == IconOrbShape.squircle &&
              o.icon == Icons.apartment_rounded &&
              !o.glow,
        ),
        isTrue,
      );
      // Durum rozeti ayrıca metinle durur (renk tek başına anlam taşımaz).
      AppTone toneOf(String label) =>
          t.widget<StatusChip>(find.widgetWithText(StatusChip, label)).tone;
      expect(toneOf('Onay Bekliyor'), AppTone.warning);
      expect(toneOf('Onaylandı'), AppTone.success);
      expect(toneOf('Reddedildi'), AppTone.danger);
    });

    testWidgets('rozet dekoratiftir (anlamsal etiketi yok); durum rozeti etiketiyle okunur', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpAt(
        t,
        SizedBox(width: double.infinity, child: _cards(details: false)),
        width: 360,
        scale: 1.0,
        height: 700,
      );
      expect(
        t.getSemantics(find.widgetWithText(StatusChip, 'Onay Bekliyor')),
        isSemantics(label: 'Onay Bekliyor'),
      );
      // Rozet yalnız süstür: etiketsiz IconOrb anlamsal ağaçtan dışlanır.
      for (final orb in t.widgetList<IconOrb>(find.byType(IconOrb))) {
        expect(orb.semanticLabel, isNull);
      }
      handle.dispose();
    });

    testWidgets('en büyük yazıda (2,0x) rozet gizlenir; metin ve durum rozeti kalır', (
      t,
    ) async {
      await pumpAt(
        t,
        SizedBox(width: double.infinity, child: _cards()),
        width: 320,
        scale: 2.0,
        height: 2400,
      );
      expect(find.byType(IconOrb), findsNothing);
      expect(find.text('Onay Bekliyor'), findsOneWidget);
      expect(find.text('Güneş Sitesi'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('hareket azaltma: kart statiktir, ticker kalmaz', (t) async {
      await pumpAt(
        t,
        SizedBox(width: double.infinity, child: _cards()),
        width: 360,
        scale: 1.0,
        height: 1000,
        reduce: true,
      );
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(t.binding.hasScheduledFrame, isFalse);
      expect(find.byType(IconOrb), findsNWidgets(3));
    });
  });
}
