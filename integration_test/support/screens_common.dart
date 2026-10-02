// Roller arasinda ortak ekran gezintileri (yalniz GUVENLI etkilesimler: ac/kapat, sekme, arama,
// akordeon, "yenile"; veri DEGISTIREN dugmelere dokunulmaz — bkz. E2ePolicy).

import 'e2e_driver.dart';
import 'e2e_env.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

/// "Daireye Katıl & Cihaz Ekle" ekrani: iki diyalogu ac/kapat; sahipsiz cihaz UID'sini ve site
/// katilim kodunu yaz (gonderme/sahiplenme YOK), yalniz okuma amacli "Site Bilgilerini Getir".
Future<void> joinAndSetupTour(E2eScreenContext c, {bool lookupJoinToken = false}) async {
  await c.openAndClose(
    'QR / Kod ile Daireye Katıl',
    shotName: 'daireye_katil_diyalogu',
    expectTexts: const <String>['Katılım Kodu'],
    whileOpen: lookupJoinToken
        ? () async {
            final token = E2eEnv.joinToken('site_1');
            if (token != null) {
              await c.type(token, label: 'Katılım Kodu veya QR');
              await c.tap('Site Bilgilerini Getir', exact: true, required: false);
              await c.settleUi(min: _s(2));
              await c.shot('site_bilgisi_getirildi');
            }
          }
        : null,
  );
  await c.openAndClose(
    'Cihaz Ekleyerek Site Yöneticisi Ol',
    shotName: 'cihaz_sahiplen_diyalogu',
    expectTexts: const <String>['Cihaz Sahiplen'],
    whileOpen: () async {
      // "Kutu QR Kodunu Tara": QR tarama sayfasi (masaustunde "desteklenmiyor" bilgisi); ac/kapat.
      await c.openAndClose('Kutu QR Kodunu Tara', shotName: 'kutu_qr_tara');
      // Elle UID girisi: alan acilir, sahipsiz UID yazilir, "Sahiplen"e DOKUNULMAZ.
      if (await c.tap('Seri No / UID ile Elle Ekle', required: false)) {
        final uid = E2eEnv.unclaimedDeviceUid();
        if (uid != null) {
          await c.type(uid, label: 'Cihaz UID');
        }
        await c.shot('uid_alani');
      }
    },
  );
}

/// Kapi kontrol karti (AdminDoorStatusCard): site/kapi sec, detaylari ac, kapi ac, misafir gecisi
/// ve QR modali ac/kapat, gecis loglari akordiyonunu ac/kapat.
Future<void> adminPanelTour(
  E2eScreenContext c, {
  required List<String> siteKeys,
  bool pressOpenDoor = true,
}) async {
  var opened = false;
  for (final siteKey in siteKeys) {
    final site = E2eEnv.siteName(siteKey);
    if (site == null) continue;
    await c.pick(label: 'Site Seçin', item: site);
    await c.settleUi(min: const Duration(milliseconds: 1500));
    var index = 0;
    for (final door in E2eEnv.doorNames(siteKey)) {
      index += 1;
      await c.pick(label: 'Kapı Seçin', item: door);
      await c.settleUi(min: _s(2));
      await c.shot('${siteKey}_kapi$index');
      if (c.has('Detaylar', exact: true)) {
        await c.tap('Detaylar', exact: true);
        await c.expect('Cihaz UID');
        await c.shot('${siteKey}_kapi${index}_detaylar');
        await c.tap('Gizle', exact: true, required: false);
      }
      if (pressOpenDoor && !opened && c.has('Kapı Aç', exact: true)) {
        opened = true;
        await c.tap('Kapı Aç', exact: true);
        await c.expect('Kapı açma komutu gönderildi', wait: _s(8));
      }
      if (index == 1) {
        await c.openAndClose('Kurye / Misafir Geçişi Oluştur', shotName: '${siteKey}_misafir_gecisi');
        await c.openAndClose('Giriş QR Kodu Göster', shotName: '${siteKey}_giris_qr');
      }
      await doorLogsAccordion(c, shotPrefix: '${siteKey}_kapi$index');
    }
  }
}

/// "KAPI Geçiş Logları" akordiyonunu acar, sonuna kaydirir, kapatir.
Future<void> doorLogsAccordion(E2eScreenContext c, {required String shotPrefix}) async {
  if (!c.has('Geçiş Logları')) return;
  if (!await c.tap('Geçiş Logları', required: false)) return;
  await c.settleUi(min: _s(2));
  await c.shot('${shotPrefix}_loglar');
  await c.shotAtEnd('${shotPrefix}_loglar_sonu');
  await c.tap('Geçiş Logları', required: false);
}

/// Profilim: gecersiz giris ile form dogrulamasini tetikler (sunucuya ISTEK GITMEZ), sonra geri alir.
Future<void> profileValidationTour(E2eScreenContext c) async {
  final original = E2eEnv.userFullName(c.session.userKey);
  if (!c.has('Ad Soyad')) return;
  await c.type('ab', label: 'Ad Soyad');
  await c.type('yeni', label: 'Yeni Şifre');
  await c.tap('Profili Kaydet', exact: true);
  await c.expect('en az 3 karakter');
  await c.shot('dogrulama_hatasi');
  if (original != null) {
    await c.type(original, label: 'Ad Soyad');
  }
  await c.type('', label: 'Yeni Şifre');
}

/// Cihaz kartlari: UID'ye dokunup ac, "Düzenle" ve "Kapıya Ata" diyaloglarini ac/kapat, kapat.
Future<void> deviceInventoryTour(E2eScreenContext c, {required List<String> uids}) async {
  for (final uid in uids) {
    if (!await c.tap(uid, exact: true, required: false)) continue;
    await c.settleUi(min: const Duration(milliseconds: 800));
    await c.shot('cihaz_$uid');
    await c.openAndClose('Düzenle', exact: true, shotName: 'cihaz_duzenle_$uid');
    await c.openAndClose('Kapıya Ata', exact: true, shotName: 'cihaz_kapiya_ata_$uid');
    await c.tap(uid, exact: true, required: false);
  }
  await c.tapTip('Yenile', required: false);
}

/// "Bluetooth ile Wi-Fi Kur": kurulum sayfasini ac/kapat (Windows'ta BLE yok: cokmemeli).
Future<void> bluetoothWifiTour(E2eScreenContext c) async {
  await c.openAndClose(
    'Bluetooth ile Wi-Fi Kurulumunu Aç',
    exact: true,
    shotName: 'wifi_kurulum_sayfasi',
  );
}
