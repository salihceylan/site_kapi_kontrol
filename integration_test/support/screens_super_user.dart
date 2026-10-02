// Super kullanici ekran tanimlari + guvenli etkilesimler.

import 'package:flutter/material.dart' show Icons;

import 'e2e_driver.dart';
import 'e2e_env.dart';
import 'screens_common.dart';
import 'screens_sites.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

List<E2eScreenSpec> superUserScreens() {
  final site1 = E2eEnv.siteName('site_1') ?? 'Yeşilvadi Sitesi';
  final site2 = E2eEnv.siteName('site_2') ?? 'Mavi Park Evleri';
  return <E2eScreenSpec>[
    E2eScreenSpec(
      name: 'panel',
      menuLabel: 'Panel',
      titleText: 'AHBU Panel',
      interactions: (c) => adminPanelTour(c, siteKeys: const <String>['site_1', 'site_2']),
    ),
    const E2eScreenSpec(
      name: 'profilim',
      menuLabel: 'Profilim',
      titleText: 'Profilim',
      interactions: profileValidationTour,
    ),
    E2eScreenSpec(
      name: 'kullanici_yonetimi',
      menuLabel: 'Kullanıcı Yönetimi',
      titleText: 'Kullanıcı Yönetimi',
      expectTexts: <String>[E2eEnv.userFullName('manager_1') ?? 'Ayşe Yılmaz'],
      interactions: _allUsers,
    ),
    E2eScreenSpec(
      name: 'super_kullanici_yonetimi',
      menuLabel: 'Süper Kullanıcı Yönetimi',
      titleText: 'Süper Kullanıcı Yönetimi',
      expectTexts: <String>[E2eEnv.userFullName('super_user') ?? 'Süper Yönetici'],
      interactions: (c) => managedUsersTour(
        c,
        newButton: 'Yeni Süper Kullanıcı',
        userName: E2eEnv.userFullName('super_user') ?? 'Süper Yönetici',
      ),
    ),
    E2eScreenSpec(
      name: 'site_yoneticileri',
      menuLabel: 'Site Yöneticileri Yönetimi',
      titleText: 'Site Yöneticileri Yönetimi',
      expectTexts: <String>[
        E2eEnv.userFullName('manager_1') ?? 'Ayşe Yılmaz',
        E2eEnv.userFullName('manager_2') ?? 'Mehmet Demir',
      ],
      interactions: (c) => managedUsersTour(
        c,
        newButton: 'Yeni Site Yöneticisi',
        userName: E2eEnv.userFullName('manager_1') ?? 'Ayşe Yılmaz',
      ),
    ),
    E2eScreenSpec(
      name: 'daire_sakinleri',
      menuLabel: 'Daire Sakinleri',
      titleText: 'Daire Sakinleri',
      expectTexts: <String>[site1, site2],
      interactions: (c) => sitesTour(c, siteKey: 'site_1', canCreateSite: true, apartmentMode: true),
    ),
    E2eScreenSpec(
      name: 'site_yonetimi',
      menuLabel: 'Site Yönetimi',
      titleText: 'Site Yönetimi',
      expectTexts: <String>[site1, site2],
      interactions: (c) => sitesTour(c, siteKey: 'site_1', canCreateSite: true),
    ),
    const E2eScreenSpec(
      name: 'katilim_kurulum',
      menuLabel: 'Daireye Katıl & Cihaz Ekle',
      titleText: 'Daireye Katıl & Cihaz Ekle',
      interactions: joinAndSetupTour,
    ),
    const E2eScreenSpec(
      name: 'sirket_cihaz_kaydet',
      menuLabel: 'Şirket Cihazı Kaydet',
      titleText: 'Şirket Cihazı Kaydet',
      interactions: _deviceRegisterTour,
    ),
    E2eScreenSpec(
      name: 'sirket_cihaz_envanteri',
      menuLabel: 'Şirket Cihaz Envanteri',
      titleText: 'Şirket Cihaz Envanteri',
      expectTexts: <String>[
        E2eEnv.deviceUid('device_wroom_1') ?? '240AC4E2E001',
        E2eEnv.deviceUid('device_c3_2') ?? '7CDFA1E2E004',
      ],
      interactions: _superDeviceInventory,
    ),
    const E2eScreenSpec(
      name: 'bluetooth_wifi',
      menuLabel: 'Bluetooth ile Wi-Fi Kur',
      titleText: 'Bluetooth ile Wi-Fi Kurulumu',
      interactions: bluetoothWifiTour,
    ),
  ];
}

/// Kullanici Yonetimi (tum kullanicilar dizini): arama, rol filtreleri, detay alt sayfasi, duzenleme
/// diyalogu (kaydetmeden), veritabani sagligi diyalogu (temizlik YAPMADAN).
Future<void> _allUsers(E2eScreenContext c) async {
  final manager = E2eEnv.userFullName('manager_2') ?? 'Mehmet Demir';
  final other = E2eEnv.userFullName('individual_rejected') ?? 'Selin Aydın';
  await c.expect(manager);

  await c.type(manager.split(' ').first, hint: 'Kişi adı');
  await c.settleUi(min: const Duration(milliseconds: 1600));
  await c.expect(manager);
  await c.expectAbsent(other);
  await c.shot('arama_sonucu');
  await c.tapIconButton(Icons.clear_rounded, required: false);
  await c.settleUi(min: const Duration(milliseconds: 1600));
  await c.expect(other);

  for (final chip in const <String>[
    'Site Yöneticileri',
    'Daire Sakinleri',
    'Bireysel Kullanıcılar',
    'Tüm Roller',
  ]) {
    await c.tap(chip, exact: true, required: false);
    await c.settleUi(min: const Duration(milliseconds: 1500));
    await c.shot('filtre_${chip.split(' ').first}');
  }

  // Kullanici satiri -> detay alt sayfasi -> Duzenle diyalogu (kaydetmeden kapat).
  if (await c.tap(manager, exact: true, required: false)) {
    await c.settleUi(min: const Duration(milliseconds: 900));
    await c.shot('kullanici_detay_alt_sayfa');
    await c.openAndClose('Düzenle', exact: true, shotName: 'kullanici_duzenle_diyalogu');
    await c.closeAll();
  }

  // Veritabani sagligi (yalniz GET /admin/maintenance/health); "Cop Temizligi Yap" dugmesine dokunulmaz.
  await c.openByAndClose(
    () => c.tapTip('Veritabanı Sağlığı & Çöp Temizliği', unsafe: true),
    name: 'veritabani_sagligi',
  );
  await c.tapTip('Listeyi Yenile', required: false);
}

/// Yonetilen kullanici listeleri (super kullanici / site yoneticisi): "Yeni ..." diyalogu, kart acilimi
/// ve "Duzenle" diyalogu (kaydetmeden kapatilir).
Future<void> managedUsersTour(
  E2eScreenContext c, {
  required String newButton,
  required String userName,
}) async {
  await c.openAndClose(newButton, exact: true, shotName: 'yeni_kullanici_diyalogu');
  if (await c.tap(userName, exact: true, required: false)) {
    await c.settleUi(min: const Duration(milliseconds: 700));
    await c.shot('kullanici_karti_acik');
    await c.openAndClose('Düzenle', exact: true, shotName: 'kullanici_duzenle_diyalogu');
    await c.tap(userName, exact: true, required: false);
  }
  await c.tapIconButton(Icons.refresh, required: false);
  await c.settleUi(min: _s(1));
}

Future<void> _deviceRegisterTour(E2eScreenContext c) async {
  await c.openAndClose(
    'Unique ID Gir',
    exact: true,
    shotName: 'uid_diyalogu',
    expectTexts: const <String>['Cihaz Kaydet'],
    whileOpen: () async {
      await c.type('1CDA72A172E0', label: 'Cihaz Unique ID');
      await c.shot('uid_yazildi');
    },
  );
  await c.openAndClose('QR Oku', exact: true, shotName: 'qr_tara_sayfasi');
}

Future<void> _superDeviceInventory(E2eScreenContext c) => deviceInventoryTour(
      c,
      uids: <String>[
        E2eEnv.unclaimedDeviceUid() ?? '7CDFA1E2E004',
        E2eEnv.deviceUid('device_wroom_1') ?? '240AC4E2E001',
      ],
    );
