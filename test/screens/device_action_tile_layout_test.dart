// FAZ 5 / A2-G6: cihaz eylem kartı (DeviceActionTile) taşma + tasarım testleri.
//
// AGENTS.md kural 6: taşma yok. Matris: 320x640 x2,0 ve 360x640 x1,5 (açık + koyu) dar kullanım
// (DeviceAddView < 680 px: alt alta Column) ve geniş kullanım (>= 680 px: yan yana Row).
// Düğme `ElevatedButton` KALIR (tema stili; e2e 'QR Oku' / 'Unique ID Gir' metinleriyle bulur);
// kart `AppCard`, ikon karosu `AppTone.primary`, başlık/açıklama tema yuvalarıdır (ham renk yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_action_tile.dart';

import '../design/harness.dart';

const String _qrTitle = 'QR ile Şirket Veritabanına Kaydet';
const String _qrDescription =
    'Cihaz üzerindeki QR kodu okutur, Unique ID alanını otomatik doldurur ve şirket kayıt formunu açar.';
const String _qrButton = 'QR Oku';
const String _manualTitle = 'Unique ID ile Şirket Veritabanına Kaydet';
const String _manualDescription =
    'QR okunamıyorsa veya masaüstü sürümde çalışıyorsanız cihaz Unique ID bilgisini elle girerek şirket hesabına kayıt yapar.';
const String _manualButton = 'Unique ID Gir';

DeviceActionTile _qrTile([VoidCallback? onPressed]) => DeviceActionTile(
  icon: Icons.qr_code_scanner_outlined,
  title: _qrTitle,
  description: _qrDescription,
  buttonLabel: _qrButton,
  onPressed: onPressed ?? () {},
);

DeviceActionTile _manualTile([VoidCallback? onPressed]) => DeviceActionTile(
  icon: Icons.edit_note_outlined,
  title: _manualTitle,
  description: _manualDescription,
  buttonLabel: _manualButton,
  onPressed: onPressed ?? () {},
);

/// DeviceAddView dar düzeni (< 680 px): sayfa boşluğu 16, kartlar alt alta (Column, ortalı).
Widget _compact({VoidCallback? onQr, VoidCallback? onManual}) => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          _qrTile(onQr),
          const SizedBox(height: 12),
          _manualTile(onManual),
        ],
      ),
    ],
  ),
);

/// DeviceAddView geniş düzeni (>= 680 px): kartlar yan yana (Row, üstten hizalı).
Widget _wide({VoidCallback? onQr, VoidCallback? onManual}) => Padding(
  padding: const EdgeInsets.all(16),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _qrTile(onQr)),
      const SizedBox(width: 12),
      Expanded(child: _manualTile(onManual)),
    ],
  ),
);

const List<(double, double, double)> _cells = <(double, double, double)>[
  (320, 640, 2.0),
  (360, 640, 1.5),
];

String _cellName(double w, double h, double s, bool dark) =>
    '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';

void main() {
  group('DeviceActionTile taşma matrisi (dar düzen: alt alta)', () {
    for (final (w, h, s) in _cells) {
      for (final dark in const <bool>[false, true]) {
        testWidgets(
          '${_cellName(w, h, s, dark)}: taşma yok; kartlar tam genişlik; düğmeler ElevatedButton; metinler aynı',
          (t) async {
            await pumpAt(
              t,
              _compact(),
              width: w,
              height: h,
              scale: s,
              dark: dark,
            );
            expect(find.byType(DeviceActionTile), findsNWidgets(2));
            expect(find.byType(AppCard), findsNWidgets(2));
            expect(find.byType(ElevatedButton), findsNWidgets(2));
            for (final text in const <String>[
              _qrTitle,
              _qrDescription,
              _qrButton,
              _manualTitle,
              _manualDescription,
              _manualButton,
            ]) {
              expect(find.text(text), findsOneWidget, reason: text);
            }
            // Eski Container(width: double.infinity) gibi: sütunda ortalansa da tam genişlik.
            for (var i = 0; i < 2; i++) {
              expect(
                t.getSize(find.byType(DeviceActionTile).at(i)).width,
                w - 32,
                reason: '$i. kart tam genişlik',
              );
            }
            // Düğme dokunma hedefi >= 44 dp.
            for (var i = 0; i < 2; i++) {
              expect(
                t.getSize(find.byType(ElevatedButton).at(i)).height,
                greaterThanOrEqualTo(44),
              );
            }
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  });

  group('DeviceActionTile taşma matrisi (geniş düzen: yan yana)', () {
    for (final (w, h, s) in const <(double, double, double)>[
      (820, 640, 1.0),
      (820, 640, 2.0),
      (700, 640, 1.5),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets(
          '${_cellName(w, h, s, dark)}: iki kart eşit genişlikte yan yana, taşma yok',
          (t) async {
            await pumpAt(t, _wide(), width: w, height: h, scale: s, dark: dark);
            final first = t.getSize(find.byType(DeviceActionTile).first);
            final second = t.getSize(find.byType(DeviceActionTile).last);
            expect(first.width, second.width);
            expect(first.width, (w - 32 - 12) / 2);
            expect(find.byType(ElevatedButton), findsNWidgets(2));
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  });

  group('DeviceActionTile görünümü: AppCard + ton + tema yuvaları (ham renk yok)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        '${dark ? 'koyu' : 'açık'}: ikon karosu primary tonu; başlık/açıklama tema renkleri',
        (t) async {
          await pumpAt(
            t,
            _compact(),
            width: 360,
            height: 640,
            scale: 1.0,
            dark: dark,
          );
          final p = t.element(find.byType(DeviceActionTile).first).palette;

          // Kart: AppCard, seviye 1, tonsuz.
          final card = t.widget<AppCard>(find.byType(AppCard).first);
          expect(card.level, 1);
          expect(card.tone, isNull);
          expect(card.onTap, isNull);

          // İkon karosu: 28 dp ikon (düğmedeki 18 dp ikondan ayrı), ton tint zemini + ink rengi.
          final glyph = find.byWidgetPredicate(
            (w) =>
                w is Icon &&
                w.icon == Icons.qr_code_scanner_outlined &&
                w.size == 28,
          );
          expect(glyph, findsOneWidget);
          expect(t.widget<Icon>(glyph).color, AppTone.primary.ink(p));
          final tile = t.widget<Container>(
            find.ancestor(of: glyph, matching: find.byType(Container)).first,
          );
          final decoration = tile.decoration! as BoxDecoration;
          expect(decoration.shape, BoxShape.circle);
          expect(decoration.color, AppTone.primary.tint(p));
          expect(tile.padding, const EdgeInsets.all(AppSpace.md));

          // Başlık = titleLarge (palet metni), açıklama = bodyMedium (ikincil metin).
          final textTheme = Theme.of(
            t.element(find.byType(DeviceActionTile).first),
          ).textTheme;
          expect(
            t.widget<Text>(find.text(_qrTitle)).style,
            textTheme.titleLarge,
          );
          expect(t.widget<Text>(find.text(_qrTitle)).style!.color, p.text);
          expect(
            t.widget<Text>(find.text(_qrDescription)).style,
            textTheme.bodyMedium,
          );
          expect(
            t.widget<Text>(find.text(_qrDescription)).style!.color,
            p.textSecondary,
          );
        },
      );
    }

    testWidgets(
      'düğme tema stilini alır (ElevatedButton.icon; elle renk/stil verilmez)',
      (t) async {
        await pumpAt(t, _compact(), width: 360, height: 640, scale: 1.0);
        final button = t.widget<ElevatedButton>(
          find.byType(ElevatedButton).first,
        );
        expect(button.style, isNull, reason: 'stil temadan gelir');
        expect(button.onPressed, isNotNull);
      },
    );
  });

  group('DeviceActionTile davranışı ve erişilebilirlik', () {
    testWidgets(
      'düğmeye dokunma ilgili geri çağrıyı tetikler (kaydırarak erişilir)',
      (t) async {
        var qr = 0;
        var manual = 0;
        await pumpAt(
          t,
          _compact(onQr: () => qr++, onManual: () => manual++),
          width: 320,
          height: 640,
          scale: 2.0,
        );
        await t.ensureVisible(find.text(_qrButton));
        await t.pump();
        await t.tap(find.text(_qrButton));
        expect((qr, manual), (1, 0));

        await t.ensureVisible(find.text(_manualButton));
        await t.pump();
        await t.tap(find.text(_manualButton));
        expect((qr, manual), (1, 1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'anlamsal ağaç: kart başlık + açıklama tek düğüm (eski davranış), düğme ayrı; süs ikonu yok',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(t, _compact(), width: 360, height: 1200, scale: 1.0);
        expect(
          t.getSemantics(find.text(_qrTitle)),
          isSemantics(label: '$_qrTitle\n$_qrDescription', isHeader: false),
        );
        expect(
          t.getSemantics(find.widgetWithText(ElevatedButton, _qrButton)),
          isSemantics(label: _qrButton, isButton: true),
        );
        final labels = t.semantics
            .simulatedAccessibilityTraversal()
            .map((n) => n.getSemanticsData().label)
            .where((l) => l.isNotEmpty)
            .toList();
        // Sıra: kart metni, düğme; karo ikonu etiketsizdir (okunmaz).
        expect(labels, <String>[
          '$_qrTitle\n$_qrDescription',
          _qrButton,
          '$_manualTitle\n$_manualDescription',
          _manualButton,
        ]);
        handle.dispose();
      },
    );

    testWidgets(
      'hareket azaltma / sonsuz animasyon yok: kurulumdan sonra kare planlı değil',
      (t) async {
        await pumpAt(t, _compact(), width: 360, height: 1200, scale: 1.0);
        expect(t.binding.transientCallbackCount, 0);
        expect(t.binding.hasScheduledFrame, isFalse);
      },
    );
  });
}
