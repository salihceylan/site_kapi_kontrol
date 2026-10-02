// Bireysel kullanici / sakin modu ekran tanimlari (IndividualHomeView) + guvenli etkilesimler.
// Veri degistiren eylemler (Uyeyi Cikar, Basvuru Gonder, Cihaz Sahiplen, Kaydet...) YAPILMAZ.

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

/// Bireysel kullanici menusu: Panel, Daireye Katil & Cihaz Ekle, Profilim.
List<E2eScreenSpec> individualScreens({bool lookupJoinToken = false}) => <E2eScreenSpec>[
      const E2eScreenSpec(
        name: 'panel',
        menuLabel: 'Panel',
        titleText: 'AHBU Panel',
        interactions: individualPanelTour,
      ),
      E2eScreenSpec(
        name: 'katilim_kurulum',
        menuLabel: 'Daireye Katıl & Cihaz Ekle',
        titleText: 'Daireye Katıl & Cihaz Ekle',
        interactions: (c) => joinAndSetupTour(c, lookupJoinToken: lookupJoinToken),
      ),
      const E2eScreenSpec(
        name: 'profilim',
        menuLabel: 'Profilim',
        titleText: 'Profilim',
        interactions: profileValidationTour,
      ),
    ];

/// IndividualHomeView: yenile dugmeleri, site cipleri, kapi kartlari (ac, QR, misafir kodu),
/// bos durum kartlari (Site Sakini Olarak Devam Et / Yonetici Olarak Cihaz Ekle).
Future<void> individualPanelTour(E2eScreenContext c) async {
  await c.tapTip('Kapıları Yenile', required: false);
  await c.tapTip('Daireleri Yenile', required: false);

  // Site filtre cipleri (birden fazla site varsa).
  if (c.has('Tüm Siteler', exact: true)) {
    final sites = <String>[
      E2eEnv.siteName('site_1') ?? '',
      E2eEnv.siteName('site_2') ?? '',
    ].where((e) => e.isNotEmpty);
    for (final site in sites) {
      if (await c.tap(site, exact: true, required: false)) {
        await c.settleUi(min: const Duration(milliseconds: 600));
        await c.shot('site_filtre');
      }
    }
    await c.tap('Tüm Siteler', exact: true, required: false);
  }

  // Kapi kartlari.
  if (c.has('Kapıyı Aç', exact: true)) {
    await c.tap('Kapıyı Aç', exact: true);
    await c.settleUi(min: _s(2));
    await c.shot('kapi_acma_sonrasi');
    await c.closeAll(); // olasi "Konum Hatasi" / "Gecis Reddedildi" diyaloglari
  }
  await c.openAndClose('Kapıya QR Göster', shotName: 'kapiya_qr_goster', required: false);
  await c.openAndClose('Misafir Kodu', shotName: 'misafir_kodu', required: false);
  await c.openAndClose('Kapı Ekranından QR Oku', shotName: 'ekrandan_qr_oku', required: false);

  // Bos durum kartlari (site/cihaz yok).
  await c.openAndClose('Site Sakini Olarak Devam Et', shotName: 'sakin_olarak_devam', required: false);
  await c.openAndClose('Yönetici Olarak Cihaz Ekle', shotName: 'yonetici_cihaz_ekle', required: false);

  // Cihaz listesi bolumu.
  await c.openAndClose('Cihaz Ekle', exact: true, shotName: 'cihaz_ekle_diyalogu', required: false);
  await c.tapTip('Yenile', required: false);
}
