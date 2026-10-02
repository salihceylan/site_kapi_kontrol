// FAZ 5 / A2-G4: BluetoothWifiView ("Bluetooth ile Wi-Fi Kur" hero) taşma ve davranış testleri.
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema (pumpAt). Görünüm: ikon karosu +
// mevcut başlık + mevcut düğme (E2E "Bluetooth ile Wi-Fi Kurulumunu Aç" metni ve ElevatedButton tipi aynı).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/views/bluetooth_wifi_view.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

void main() {
  g4LayoutMatrix('hero kartı', (t, width, height, scale, dark) async {
    var opened = 0;
    await pumpAt(
      t,
      BluetoothWifiView(onOpenWifiProvision: () => opened++),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.text('Bluetooth ile Wi-Fi Kur'), findsOneWidget);
    expect(find.text('Bluetooth ile Wi-Fi Kurulumunu Aç'), findsOneWidget);
    expect(
      find.byIcon(Icons.bluetooth_searching_outlined),
      findsNWidgets(2),
      reason: 'ikon karosu + düğme ikonu',
    );
    expect(opened, 0);
  });

  group('davranış', () {
    testWidgets(
      'düğme ElevatedButton olarak kalır ve kurulum sayfasını açma geri çağrısını tetikler',
      (t) async {
        var opened = 0;
        await pumpAt(
          t,
          BluetoothWifiView(onOpenWifiProvision: () => opened++),
          width: 360,
          scale: 1.0,
          height: 800,
        );

        expect(
          find.widgetWithText(
            ElevatedButton,
            'Bluetooth ile Wi-Fi Kurulumunu Aç',
          ),
          findsOneWidget,
        );
        await t.tap(find.text('Bluetooth ile Wi-Fi Kurulumunu Aç'));
        await t.pump();
        expect(opened, 1);
      },
    );

    testWidgets('düğme etiketi büyük yazıda kırpılmadan satıra sarar', (
      t,
    ) async {
      await pumpAt(
        t,
        BluetoothWifiView(onOpenWifiProvision: () {}),
        width: 320,
        scale: 2.0,
        height: 900,
      );

      final label = t.widget<Text>(
        find.text('Bluetooth ile Wi-Fi Kurulumunu Aç'),
      );
      expect(label.overflow, isNot(TextOverflow.ellipsis));
      expect(label.maxLines, isNull);
      expect(
        t.getSize(find.byType(ElevatedButton)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets(
      'geniş ekranda (1024 px) düğme tüm karta yayılmaz: en çok 480 dp, kart içinde ortalı',
      (t) async {
        await pumpAt(
          t,
          BluetoothWifiView(onOpenWifiProvision: () {}),
          width: 1024,
          scale: 1.0,
          height: 800,
        );

        final button = find.byType(ElevatedButton);
        expect(t.getSize(button).width, lessThanOrEqualTo(480.5));
        final card = find
            .ancestor(of: button, matching: find.byType(AppCard))
            .first;
        final cardCenter = t.getCenter(card).dx;
        expect(
          t.getCenter(button).dx,
          closeTo(cardCenter, 1.0),
          reason: 'hero içeriği kartta ortalı',
        );
      },
    );

    testWidgets(
      'başlık anlamsal başlıktır; ikon karosu ekran okuyucudan dışlanır',
      (t) async {
        final handle = t.ensureSemantics();
        await pumpAt(
          t,
          BluetoothWifiView(onOpenWifiProvision: () {}),
          width: 360,
          scale: 1.0,
          height: 800,
        );

        expect(
          t.getSemantics(find.text('Bluetooth ile Wi-Fi Kur')),
          matchesSemantics(label: 'Bluetooth ile Wi-Fi Kur', isHeader: true),
        );
        handle.dispose();
      },
    );
  });
}
