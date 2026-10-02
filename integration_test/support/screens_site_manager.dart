// Site yoneticisi ekran tanimlari: yonetici paneli + "Sakin Modu" (cift mod).

import 'package:flutter_test/flutter_test.dart';

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';
import 'screens_individual.dart';
import 'screens_sites.dart';

/// Yonetici paneli (Panel, Profilim, Site Yonetimi, Kayitli Cihazlar, Katilim, Bluetooth).
List<E2eScreenSpec> siteManagerScreens({required List<String> siteKeys}) => <E2eScreenSpec>[
      E2eScreenSpec(
        name: 'panel',
        menuLabel: 'Panel',
        titleText: 'AHBU Panel',
        interactions: (c) => adminPanelTour(c, siteKeys: siteKeys),
      ),
      const E2eScreenSpec(
        name: 'profilim',
        menuLabel: 'Profilim',
        titleText: 'Profilim',
        interactions: profileValidationTour,
      ),
      E2eScreenSpec(
        name: 'site_yonetimi',
        menuLabel: 'Site Yönetimi',
        titleText: 'Site Yönetimi',
        expectTexts: <String>[
          for (final k in siteKeys) E2eEnv.siteName(k) ?? '',
        ].where((e) => e.isNotEmpty).toList(),
        interactions: (c) async {
          var first = true;
          for (final key in siteKeys) {
            await sitesTour(c, siteKey: key, canCreateSite: first, newSiteTitle: 'Site Kurulum Sihirbazı');
            first = false;
          }
        },
      ),
      E2eScreenSpec(
        name: 'kayitli_cihazlar',
        menuLabel: 'Kayıtlı Cihazlar',
        titleText: 'Kayıtlı Cihazlar',
        expectTexts: <String>[
          for (final uid in E2eEnv.deviceUidsForSites(siteKeys)) uid,
        ].take(1).toList(),
        interactions: (c) => deviceInventoryTour(c, uids: E2eEnv.deviceUidsForSites(siteKeys)),
      ),
      const E2eScreenSpec(
        name: 'katilim_kurulum',
        menuLabel: 'Daireye Katıl & Cihaz Ekle',
        titleText: 'Daireye Katıl & Cihaz Ekle',
        interactions: joinAndSetupTour,
      ),
      const E2eScreenSpec(
        name: 'bluetooth_wifi',
        menuLabel: 'Bluetooth ile Wi-Fi Kur',
        titleText: 'Bluetooth ile Wi-Fi Kurulumu',
        interactions: bluetoothWifiTour,
      ),
    ];

/// "Sakin Modu" (yonetici ayni zamanda sakin): Panel (IndividualHomeView), Katilim, Profilim,
/// Eller Serbest diyalogu.
List<E2eScreenSpec> siteManagerResidentModeScreens() => <E2eScreenSpec>[
      const E2eScreenSpec(
        name: 'panel',
        menuLabel: 'Panel',
        titleText: 'AHBU Panel',
        interactions: individualPanelTour,
      ),
      const E2eScreenSpec(
        name: 'katilim_kurulum',
        menuLabel: 'Daireye Katıl & Cihaz Ekle',
        titleText: 'Daireye Katıl & Cihaz Ekle',
        interactions: joinAndSetupTour,
      ),
      const E2eScreenSpec(
        name: 'profilim',
        menuLabel: 'Profilim',
        titleText: 'Profilim',
      ),
      const E2eScreenSpec(
        name: 'eller_serbest',
        menuLabel: 'Eller Serbest & Kestirmeler',
        opensDialogInstead: true,
        interactions: _handsFree,
      ),
    ];

Future<void> _handsFree(E2eScreenContext c) async {
  await c.shotAtEnd('eller_serbest_sonu');
}

/// Cift mod gecisi: AppBar rozeti veya cekmece ogesi. [toResident] true ise "Sakin Modu"na gecer.
Future<void> switchMode(
  WidgetTester tester, {
  required bool toResident,
  required bool viaDrawer,
}) async {
  E2eRuntime.collector.beginScreen(toResident ? 'mod_sakin' : 'mod_yonetici');
  if (viaDrawer) {
    await openDrawerAndTap(tester, toResident ? 'Sakin Moduna Geç' : 'Yönetici Paneline Geç');
  } else {
    await closeOverlays(tester);
    final label = toResident ? 'Sakin Modu' : 'Yönetici Paneli';
    if (findText(label, exact: true).evaluate().isEmpty && find.byTooltip(label).evaluate().isNotEmpty) {
      // Dar ekranda (< 400 dp) ya da buyuk yazida (> 1,3x) AppBar rozeti yalniz ikondur; etiketi Tooltip tasir.
      await tapTooltip(tester, label);
    } else {
      await tapText(tester, label, exact: true, required: true);
    }
  }
  await settle(tester, min: const Duration(seconds: 2), max: const Duration(seconds: 8));
}
