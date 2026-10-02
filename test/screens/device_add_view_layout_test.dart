// FAZ 5 / A2-G4: DeviceAddView ("Cihaz Ekle") taşma ve davranış testleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema (pumpAt); ayrıca geniş ekranda
// (>= 680 px) iki kart yan yana. Metinler (iki kullanım: süper kullanıcı/yönetici ve bireysel kullanıcı)
// ve düğme tipi (ElevatedButton) aynı kalır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/views/device_add_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_action_tile.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

class _Taps {
  int qr = 0;
  int manual = 0;
}

/// Şirket (süper kullanıcı/yönetici) kullanımı: varsayılan metinler.
Widget _companyView(_Taps taps) => DeviceAddView(
  onOpenQrRegistration: () => taps.qr++,
  onOpenManualRegistration: () => taps.manual++,
);

/// Bireysel kullanıcı kullanımı (home_page.dart ile aynı özel metinler).
Widget _individualView(_Taps taps) => DeviceAddView(
  title: 'Yönetici Olarak Cihaz Ekle',
  qrTitle: 'Kutu QR Kodunu Okut',
  qrDescription:
      'Cihaz ambalaj kutusundaki QR kodu kameraya göstererek cihazı hesabınıza bağlayın ve yeni site kurulumunu başlatın.',
  qrButtonLabel: 'QR Kodunu Okut',
  manualTitle: 'Seri No / UID ile Cihaz Ekle',
  manualDescription:
      'Kamera kullanamıyorsanız kutu üzerindeki Seri No veya UID kodunu elle girerek cihazı bağlayın.',
  manualButtonLabel: 'Seri No Gir',
  onOpenQrRegistration: () => taps.qr++,
  onOpenManualRegistration: () => taps.manual++,
);

void main() {
  group('taşma matrisi', () {
    g4LayoutMatrix('şirket kullanımı (varsayılan metinler)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        _companyView(_Taps()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Şirket Veritabanına Cihaz Kaydet'), findsOneWidget);
      expect(find.text('QR ile Şirket Veritabanına Kaydet'), findsOneWidget);
      expect(
        find.text('Unique ID ile Şirket Veritabanına Kaydet'),
        findsOneWidget,
      );
      expect(find.text('QR Oku'), findsOneWidget);
      expect(find.text('Unique ID Gir'), findsOneWidget);
      expect(find.byType(DeviceActionTile), findsNWidgets(2));
    });

    g4LayoutMatrix('bireysel kullanım (özel metinler)', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      await pumpAt(
        t,
        _individualView(_Taps()),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Yönetici Olarak Cihaz Ekle'), findsOneWidget);
      expect(find.text('Kutu QR Kodunu Okut'), findsOneWidget);
      expect(find.text('Seri No / UID ile Cihaz Ekle'), findsOneWidget);
      expect(find.text('QR Kodunu Okut'), findsOneWidget);
      expect(find.text('Seri No Gir'), findsOneWidget);
    });
  });

  group('düzen ve davranış', () {
    testWidgets(
      'geniş ekranda (820 px) iki kart yan yana, dar ekranda alt alta',
      (t) async {
        await pumpAt(
          t,
          _companyView(_Taps()),
          width: 820,
          scale: 1.0,
          height: 900,
        );
        final tiles = find.byType(DeviceActionTile);
        expect(
          t.getTopLeft(tiles.at(0)).dy,
          closeTo(t.getTopLeft(tiles.at(1)).dy, 0.5),
          reason: 'yan yana: aynı üst kenar',
        );
        expect(
          t.getTopLeft(tiles.at(1)).dx,
          greaterThan(t.getTopLeft(tiles.at(0)).dx),
        );

        await pumpAt(
          t,
          _companyView(_Taps()),
          width: 360,
          scale: 1.0,
          height: 1400,
        );
        final narrow = find.byType(DeviceActionTile);
        expect(
          t.getTopLeft(narrow.at(1)).dy,
          greaterThan(t.getBottomLeft(narrow.at(0)).dy - 0.5),
          reason: 'alt alta',
        );
      },
    );

    testWidgets(
      'düğmeler ElevatedButton olarak kalır ve doğru geri çağrıyı tetikler',
      (t) async {
        final taps = _Taps();
        await pumpAt(
          t,
          _companyView(taps),
          width: 360,
          scale: 1.0,
          height: 1400,
        );

        expect(find.widgetWithText(ElevatedButton, 'QR Oku'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Unique ID Gir'),
          findsOneWidget,
        );

        await t.tap(find.text('QR Oku'));
        await t.pump();
        await t.tap(find.text('Unique ID Gir'));
        await t.pump();
        expect((taps.qr, taps.manual), (1, 1));
      },
    );

    testWidgets('başlık kartı tam genişlikte ve başlık anlamsal başlıktır', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpAt(
        t,
        _companyView(_Taps()),
        width: 360,
        scale: 1.0,
        height: 1400,
      );

      final header = find
          .ancestor(
            of: find.text('Şirket Veritabanına Cihaz Kaydet'),
            matching: find.byType(AppCard),
          )
          .first;
      expect(t.getSize(header).width, closeTo(360, 0.5));
      expect(
        t.getSemantics(find.text('Şirket Veritabanına Cihaz Kaydet')),
        matchesSemantics(
          label: 'Şirket Veritabanına Cihaz Kaydet',
          isHeader: true,
        ),
      );
      handle.dispose();
    });
  });
}
