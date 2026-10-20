// Bireysel kullanici / sakin modu ekran tanimlari: Panel (modul vitrini) + "Kapılar" (IndividualHomeView) + guvenli
// etkilesimler. Veri degistiren eylemler (Uyeyi Cikar, Basvuru Gonder, Cihaz Sahiplen, Kaydet...) YAPILMAZ.

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart' show find;
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart' show DoorOpenButton, DoorOpenState;
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart' show IndividualHomeView;

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

/// Bireysel kullanici menusu: Panel (modul vitrini), Kapılar (IndividualHomeView: kapilar, daireler, basvurular,
/// cihazlar), Daireye Katil & Cihaz Ekle, Profilim. "Kapılar" Geçiş Kontrol kapaliyken hic yoktur: atlanir.
List<E2eScreenSpec> individualScreens({bool lookupJoinToken = false}) => <E2eScreenSpec>[
      panelShowcaseScreen,
      kapilarScreen(individualPanelTour, optional: true),
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

/// "Kapılar" sayfasi (IndividualHomeView): yenile dugmeleri, site cipleri, kapi kartlari (ac, QR, misafir kodu),
/// bos durum kartlari (Site Sakini Olarak Devam Et / Yonetici Olarak Cihaz Ekle). Bireysel ana ekran artik "Panel"
/// degil "Kapılar"dir: gorunum yoksa tur calismaz, 'navigation' bulgusu yazilir. Dokunuslar bu gorunumle sinirlidir.
Future<void> individualPanelTour(E2eScreenContext c) async {
  final home = find.byType(IndividualHomeView);
  if (!await pumpUntilFound(c.tester, home, timeout: _s(6))) {
    E2eRuntime.collector.note(
      kind: 'navigation',
      message: 'Kapılar sayfasinda bireysel ana ekran (IndividualHomeView) yok',
    );
    return;
  }
  await c.tapTip('Kapıları Yenile', required: false);
  await c.tapTip('Daireleri Yenile', required: false);

  // Site filtre cipleri (birden fazla site varsa).
  if (findText('Tüm Siteler', exact: true, within: home).evaluate().isNotEmpty) {
    final sites = <String>[
      E2eEnv.siteName('site_1') ?? '',
      E2eEnv.siteName('site_2') ?? '',
    ].where((e) => e.isNotEmpty);
    for (final site in sites) {
      if (await c.tap(site, exact: true, required: false, within: home)) {
        await c.settleUi(min: const Duration(milliseconds: 600));
        await c.shot('site_filtre');
      }
    }
    await c.tap('Tüm Siteler', exact: true, required: false, within: home);
  }

  // Kapi kartlari: kapi dugmesi ANAHTARLA bulunur (etiket "KAPIYI AÇ" ya da "UZAKTAN AÇ"); sonuc dogrulanir.
  await _individualOpenDoorAndVerify(c);
  await c.openAndClose('Kapıya QR Göster', shotName: 'kapiya_qr_goster', required: false, within: home);
  await c.openAndClose('Misafir Kodu', shotName: 'misafir_kodu', required: false, within: home);
  await c.openAndClose('Kapı Ekranından QR Oku', shotName: 'ekrandan_qr_oku', required: false, within: home);

  // Bos durum kartlari (site/cihaz yok).
  await c.openAndClose('Site Sakini Olarak Devam Et', shotName: 'sakin_olarak_devam', required: false, within: home);
  await c.openAndClose('Yönetici Olarak Cihaz Ekle', shotName: 'yonetici_cihaz_ekle', required: false, within: home);

  // Cihaz listesi bolumu.
  await c.openAndClose('Cihaz Ekle', exact: true, shotName: 'cihaz_ekle_diyalogu', required: false, within: home);
  await c.tapTip('Yenile', required: false);
}

/// Ilk kapi kartinin dugmesi ('individual_door_open'): kapisi olmayan kullanicida dugme yoktur (atlanir); varsa ve
/// hazirsa dokunulur ve "... kapısı açılıyor" bildirimi beklenir, gelmezse bulgu yazilir (hata bildirimi eklenir).
Future<void> _individualOpenDoorAndVerify(E2eScreenContext c) async {
  final tester = c.tester;
  final button = find.descendant(
    of: find.byType(IndividualHomeView),
    matching: find.byKey(const ValueKey<String>('individual_door_open')),
  );
  if (!await pumpUntilFound(tester, button, timeout: const Duration(milliseconds: 1200))) {
    E2eRuntime.skip('kapi dugmesi yok (kullanicinin kapisi yok)');
    return;
  }
  final door = tester.widget<DoorOpenButton>(button.first);
  if (door.state != DoorOpenState.ready) {
    E2eRuntime.collector.note(
      kind: 'expectation',
      message: 'Kapi acma dugmesi hazir degil: "${door.label}" (${door.state.name}); kapi acma sinanmadi',
    );
    await c.shot('kapi_hazir_degil');
    return;
  }
  if (!await tapFinder(tester, button.first, description: 'kapi dugmesi "${door.label}"')) return;
  if (await pumpUntilFound(tester, findText('kapısı açılıyor'), timeout: _s(10))) {
    E2eRuntime.act('kapi acma komutu gonderildi (bildirimle dogrulandi)');
    await c.shot('kapi_acma_sonrasi');
  } else {
    final shown = visibleSnackBarTexts();
    E2eRuntime.collector.note(
      kind: 'expectation',
      message: 'Kapi acma dogrulanamadi: "kapısı açılıyor" bildirimi gelmedi'
          '${shown.isEmpty ? '' : ' (gorunen: ${shown.join(' | ')})'}',
    );
    await c.shot('kapi_acma_sonucu');
  }
  await c.closeAll(); // olasi "Konum Hatasi" / "Gecis Reddedildi" diyaloglari
}
