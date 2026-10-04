// Daire sakini (apartment_owner) ekran tanimlari: akilli kumanda karti + Eller Serbest diyalogu.

import 'package:flutter/material.dart' show Drawer;
import 'package:flutter_test/flutter_test.dart' show find;

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

List<E2eScreenSpec> residentScreens() => <E2eScreenSpec>[
      const E2eScreenSpec(
        name: 'panel',
        menuLabel: 'Panel',
        titleText: 'AHBU Panel',
        interactions: residentRemoteTour,
      ),
      const E2eScreenSpec(
        name: 'katilim_kurulum',
        menuLabel: 'Daireye Katıl & Cihaz Ekle',
        titleText: 'Daireye Katıl & Cihaz Ekle',
        interactions: joinAndSetupTour,
      ),
      const E2eScreenSpec(
        name: 'eller_serbest',
        menuLabel: 'Eller Serbest & Kestirmeler',
        opensDialogInstead: true,
        interactions: handsFreeTour,
      ),
      const E2eScreenSpec(
        name: 'profilim',
        menuLabel: 'Profilim',
        titleText: 'Profilim',
      ),
    ];

/// ResidentDoorRemoteCard: kapi cipleri, dev "KAPIYI AC" dugmesi, QR modali, misafir gecisi.
Future<void> residentRemoteTour(E2eScreenContext c) async {
  final doors = E2eEnv.doorNames('site_1');
  if (doors.length > 1) {
    for (final door in doors) {
      if (await c.tap(door, exact: true, required: false)) {
        await c.settleUi(min: _s(2));
        await c.shot('kapi_${doors.indexOf(door) + 1}');
      }
    }
    // QR / ekran QR dugmeleri ilk kapida (ekranli cihaz) gorunur: ilk kapiya geri don.
    await c.tap(doors.first, exact: true, required: false);
    await c.settleUi(min: _s(2));
  }
  for (final label in const <String>['KAPIYI AÇ', 'YEREL AĞDAN AÇ', 'QR KOD İLE AÇ']) {
    if (c.has(label, exact: true)) {
      await c.tap(label, exact: true);
      await c.settleUi(min: _s(2));
      await c.shot('kapi_acma_sonrasi');
      await c.closeAll(); // olasi QR modali / "Konum Hatasi" diyalogu
      break;
    }
  }
  // Sade ekranda QR / ekran QR / misafir geçişi komutları cekmecededir (Panel'in altinda); kapida
  // yetki ya da cihaz yoksa oge hic gorunmez: atlanir.
  await _drawerAction(c, 'Kapıya QR Göster', 'kapiya_qr_goster');
  await _drawerAction(c, 'Kapı Ekranından QR Oku', 'ekrandan_qr_oku');
  await _drawerAction(c, 'Kurye / Misafir Geçiş Linki Oluştur', 'misafir_gecisi');
}

/// Cekmecedeki ek komutu (varsa) acar, goruntu alir, kapatir.
Future<void> _drawerAction(E2eScreenContext c, String label, String shotName) async {
  await closeOverlays(c.tester);
  if (!await openDrawer(c.tester)) return;
  if (findText(label, exact: true, within: find.byType(Drawer)).evaluate().isEmpty) {
    await closeOverlays(c.tester);
    return;
  }
  if (await openDrawerAndTap(c.tester, label)) {
    await c.settleUi(min: _s(2));
    await c.shot(shotName);
    await c.closeAll();
  }
}

/// Eller Serbest & Kestirmeler diyalogu: kaydir, goruntule (kapatma generic akista yapilir).
Future<void> handsFreeTour(E2eScreenContext c) async {
  await c.shotAtEnd('eller_serbest_sonu');
}
