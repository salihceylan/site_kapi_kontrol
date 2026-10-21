// Site yoneticisi ekran tanimlari: yonetici paneli + "Sakin Modu" (cift mod). IP-1D: Profilim, Kayıtlı Cihazlar,
// Bluetooth ve Eller Serbest sag ustteki disliden (Ayarlar paneli) acilir (openDrawerAndTap orada da arar); cok siteli
// yoneticide cekmecenin en ustundeki site secici gezilir ([siteSelectorTour]).

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';
import 'screens_individual.dart';
import 'screens_sites.dart';

/// Yonetici modu: Panel (modul vitrini), Kapılar (kapi paneli: vitrindeki kartla), site secici, Profilim, Site Yonetimi,
/// Kayitli Cihazlar, Katilim, Bluetooth.
List<E2eScreenSpec> siteManagerScreens({required List<String> siteKeys}) => <E2eScreenSpec>[
      panelShowcaseScreen,
      kapilarScreen((c) => adminPanelTour(c, siteKeys: siteKeys)),
      const E2eScreenSpec(
        name: 'site_secici',
        menuLabel: 'Panel',
        titleText: 'Panel',
        interactions: siteSelectorTour,
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

/// "Sakin Modu" (yonetici ayni zamanda sakin): Panel (sakin vitrini), Kapılar (IndividualHomeView), Katilim,
/// Profilim, Eller Serbest diyalogu.
List<E2eScreenSpec> siteManagerResidentModeScreens() => <E2eScreenSpec>[
      panelShowcaseScreen,
      kapilarScreen(individualPanelTour),
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

/// Cekmecenin en ustundeki site satiri (IP-1D / G2). Tek siteli yoneticide bilgi satiridir (dokunulmaz). Cok siteli
/// yoneticide secicidir: ikinci site secilir (menu o sitenin modullerine daralir; goruntu alinir), sonra "Tüm siteler"e
/// donulur. Veri DEGISTIRMEZ (yalniz istemci kapsami).
Future<void> siteSelectorTour(E2eScreenContext c) async {
  final tester = c.tester;
  if (!await openDrawer(tester)) return;
  final row = find.byKey(const ValueKey<String>('yan_menu_site'));
  if (row.evaluate().isEmpty) {
    E2eRuntime.collector.note(kind: 'expectation', message: 'Cekmecenin en ustunde site satiri yok');
    await closeOverlays(tester);
    return;
  }
  await c.shot('site_satiri');
  final options = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('yan_menu_site_secenek_');
  });
  if (!await tapFinder(tester, row, description: 'site satiri', settleAfter: const Duration(milliseconds: 600)) ||
      options.evaluate().isEmpty) {
    E2eRuntime.act('site satiri secici degil (tek site)');
    await closeOverlays(tester);
    return;
  }
  final keys = <String>[
    for (final e in options.evaluate()) (e.widget.key! as ValueKey<String>).value,
  ];
  final site = keys.firstWhere((k) => !k.endsWith('_tum'), orElse: () => '');
  if (site.isEmpty) {
    await closeOverlays(tester);
    return;
  }
  await tapFinder(tester, find.byKey(ValueKey<String>(site)), description: 'site secimi', settleAfter: const Duration(milliseconds: 800));
  await c.shot('site_secildi');
  if (await tapFinder(tester, row, description: 'site satiri', settleAfter: const Duration(milliseconds: 600))) {
    await tapFinder(
      tester,
      find.byKey(const ValueKey<String>('yan_menu_site_secenek_tum')),
      description: 'Tüm siteler',
      settleAfter: const Duration(milliseconds: 800),
    );
  }
  await closeOverlays(tester);
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
