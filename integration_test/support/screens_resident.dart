// Daire sakini (apartment_owner) ekran tanimlari: Panel (modul vitrini), alt cubuk sekmeleri (IP-1D / G3), "Kapılar"
// (akilli kumanda karti) + Eller Serbest diyalogu. Profilim ve Eller Serbest sag ustteki disliden (Ayarlar) acilir.

import 'package:flutter/material.dart' show Drawer, ValueKey;
import 'package:flutter_test/flutter_test.dart' show find;
import 'package:site_kapi_kontrol/ui/design/door_open_button.dart' show DoorOpenButton, DoorOpenState;
import 'package:site_kapi_kontrol/ui/widgets/resident_door_remote_card.dart' show ResidentDoorRemoteCard;

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

List<E2eScreenSpec> residentScreens() => <E2eScreenSpec>[
      panelShowcaseScreen,
      kapilarScreen(residentRemoteTour),
      const E2eScreenSpec(
        name: 'alt_cubuk',
        menuLabel: 'Panel',
        titleText: 'Panel',
        interactions: residentBottomBarTour,
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

/// "Kapılar" sayfasindaki sade kumanda (ResidentDoorRemoteCard): kapi cipleri, yuvarlak kapi dugmesi (sonucu
/// dogrulanir), QR / ekran QR / misafir gecisi cekmeceden. Kumanda yoksa sessizce gecilmez: bulgu yazilir.
Future<void> residentRemoteTour(E2eScreenContext c) async {
  final remote = find.byType(ResidentDoorRemoteCard);
  if (!await pumpUntilFound(c.tester, remote, timeout: _s(6))) {
    E2eRuntime.collector.note(
      kind: 'expectation',
      message: 'Kapılar sayfasinda kapi kumandasi (ResidentDoorRemoteCard) yok',
    );
    return;
  }
  final doors = E2eEnv.doorNames('site_1');
  if (doors.length > 1) {
    for (final door in doors) {
      if (await c.tap(door, exact: true, required: false, within: remote)) {
        await c.settleUi(min: _s(2));
        await c.shot('kapi_${doors.indexOf(door) + 1}');
      }
    }
    // QR / ekran QR dugmeleri ilk kapida (ekranli cihaz) gorunur: ilk kapiya geri don.
    await c.tap(doors.first, exact: true, required: false, within: remote);
    await c.settleUi(min: _s(2));
  }
  await residentOpenDoorAndVerify(c);
  // Sade ekranda QR / ekran QR / misafir gecisi komutlari cekmecededir ("Kapılar"in altinda; o yoksa "Panel"in
  // altinda); kapida yetki ya da cihaz yoksa oge hic gorunmez: atlanir.
  await _drawerAction(c, 'Kapıya QR Göster', 'kapiya_qr_goster');
  await _drawerAction(c, 'Kapı Ekranından QR Oku', 'ekrandan_qr_oku');
  await _drawerAction(c, 'Kurye / Misafir Geçiş Linki Oluştur', 'misafir_gecisi');
}

/// Kapi dugmesine ANAHTARIYLA ('resident_door_open_button') dokunur ve SONUCU dogrular: uzaktan / yerel acmada
/// "Kapı açma komutu gönderildi" bildirimi, yalniz-QR kapida QR penceresi. Dugme yoksa, hazir degilse ya da sonuc
/// gorunmezse bulgu yazilir (eskiden metinle aranip vitrindeki "Kapıyı aç" kutusuna da dokunulabiliyor ve sonuc
/// beklenmeden "kapi acildi" goruntusu aliniyordu).
Future<void> residentOpenDoorAndVerify(E2eScreenContext c) async {
  final tester = c.tester;
  final button = find.byKey(const ValueKey<String>('resident_door_open_button'));
  if (!await pumpUntilFound(tester, button, timeout: _s(4))) {
    E2eRuntime.collector.note(kind: 'expectation', message: 'Kapi acma dugmesi (resident_door_open_button) yok');
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
  if (foldText(door.label) == foldText('QR KOD İLE AÇ')) {
    // Yalniz QR kapi: dugme kapiya gosterilecek karekodu acar (kapi komutu GONDERMEZ).
    final shown = await c.openByAndClose(
      () => tapFinder(tester, button.first, description: 'kapi dugmesi "${door.label}"'),
      name: 'kapi_qr_penceresi',
    );
    if (!shown) {
      E2eRuntime.collector.note(kind: 'expectation', message: 'Yalniz-QR kapi dugmesi QR penceresini acmadi');
    }
    return;
  }
  if (!await tapFinder(tester, button.first, description: 'kapi dugmesi "${door.label}"')) return;
  if (await pumpUntilFound(tester, findText('Kapı açma komutu gönderildi'), timeout: _s(10))) {
    E2eRuntime.act('kapi acma komutu gonderildi (bildirimle dogrulandi)');
    await c.shot('kapi_acma_sonrasi');
  } else {
    final shown = visibleSnackBarTexts();
    E2eRuntime.collector.note(
      kind: 'expectation',
      message: 'Kapi acma dogrulanamadi: "Kapı açma komutu gönderildi" bildirimi gelmedi'
          '${shown.isEmpty ? '' : ' (gorunen: ${shown.join(' | ')})'}',
    );
    await c.shot('kapi_acma_sonucu');
  }
  await c.closeAll(); // olasi "Konum Hatasi" diyalogu
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

/// Alt cubuk (IP-1D / G3): Ozet · Duyuru · Arıza · Kapı · Belgeler sekmeleri gorunur ogelerden turer. Her sekme kendi
/// sayfasini acar (AppBar basligi), geri tusu Ozet'e (Panel) dondurur. Kapi sekmesi kapiyi ACMAZ, Kapılar sayfasini
/// acar. Cubuk yoksa (iki sekmeden az) bulgu yazilmaz, yalniz not dusulur.
Future<void> residentBottomBarTour(E2eScreenContext c) async {
  final tester = c.tester;
  if (find.byKey(kResidentBarKey).evaluate().isEmpty) {
    E2eRuntime.act('alt cubuk yok (iki sekmeden az)');
    return;
  }
  final tabs = bottomTabsOnScreen();
  E2eRuntime.act('alt cubuk: ${tabs.map((t) => t.$2).join(', ')}');
  if (tabs.isEmpty || tabs.first.$1 != 'ozet') {
    E2eRuntime.collector.note(kind: 'expectation', message: 'Alt cubugun ilk sekmesi "Özet" degil');
  }
  const titles = <String, String>{
    'duyuru': 'Duyurular',
    'ariza': 'Taleplerim',
    'kapi': 'Kapılar',
    'belgeler': 'Belgeler',
  };
  for (final (key, label) in tabs) {
    final title = titles[key];
    if (title == null) continue;
    if (!await tapBottomTab(tester, key)) continue;
    await c.settleUi(min: _s(1));
    if (!await pumpUntilFound(tester, appBarTitle(title), timeout: _s(5))) {
      E2eRuntime.collector.note(kind: 'navigation', message: 'Alt cubuk "$label" sekmesi "$title" sayfasini acmadi');
    }
    await c.shot('sekme_$key');
    // Geri tusu sekmeden Ozet'e (Panel) doner.
    await tester.binding.handlePopRoute();
    await c.settleUi(min: _s(1));
    if (!await pumpUntilFound(tester, find.byKey(kShowcaseKey), timeout: _s(5))) {
      E2eRuntime.collector.note(kind: 'navigation', message: 'Alt cubuk "$label" sekmesinden geri tusu Özet\'e donmedi');
      await tapBottomTab(tester, 'ozet');
    }
  }
}

/// Eller Serbest & Kestirmeler diyalogu: kaydir, goruntule (kapatma generic akista yapilir).
Future<void> handsFreeTour(E2eScreenContext c) async {
  await c.shotAtEnd('eller_serbest_sonu');
}
