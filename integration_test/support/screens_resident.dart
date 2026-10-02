// Daire sakini (apartment_owner) ekran tanimlari: akilli kumanda karti + Eller Serbest diyalogu.

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
  await c.openAndClose('Kapıya QR Göster', shotName: 'kapiya_qr_goster', required: false);
  await c.openAndClose('Kapı Ekranından QR Oku', shotName: 'ekrandan_qr_oku', required: false);
  await c.openAndClose('Kurye / Misafir Geçiş Linki Oluştur', shotName: 'misafir_gecisi', required: false);
}

/// Eller Serbest & Kestirmeler diyalogu: kaydir, goruntule (kapatma generic akista yapilir).
Future<void> handsFreeTour(E2eScreenContext c) async {
  await c.shotAtEnd('eller_serbest_sonu');
}
