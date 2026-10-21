// Roller arasinda ortak ekran gezintileri (yalniz GUVENLI etkilesimler: ac/kapat, sekme, arama,
// akordeon, "yenile"; veri DEGISTIREN dugmelere dokunulmaz — bkz. E2ePolicy).
//
// "Panel" MODUL VITRINIDIR ([panelShowcaseScreen] + [showcaseTour]); kapi paneli "Kapılar" ekranindadir ve oraya
// vitrindeki "Kapılar" kartina dokunarak gecilir ([kapilarScreen]). Kapi turlari yalniz orada calisir.

import 'package:flutter_test/flutter_test.dart' show find;
import 'package:site_kapi_kontrol/ui/widgets/admin_door_status_card.dart' show AdminDoorStatusCard;
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart' show SirketMenuItem, YanMenu;

import 'e2e_driver.dart';
import 'e2e_env.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

/// "Panel" ekrani: modul vitrini ([showcaseTour]).
const E2eScreenSpec panelShowcaseScreen = E2eScreenSpec(
  name: 'panel',
  menuLabel: 'Panel',
  titleText: 'Panel',
  interactions: showcaseTour,
);

/// "Kapılar" ekrani (kapi paneli): Panel vitrinindeki "Kapılar" kartina dokunarak acilir; [tour] orada calisir.
/// [optional]: rolde hic "Kapılar" yoksa (Geçiş Kontrol kapali / kapi yetkisi yok) bulgusuz atlanir.
E2eScreenSpec kapilarScreen(E2eInteractions tour, {bool optional = false}) => E2eScreenSpec(
      name: 'kapilar',
      menuLabel: 'Kapılar',
      titleText: 'Kapılar',
      showcaseCard: SirketMenuItem.kapilar,
      optional: optional,
      interactions: tour,
    );

/// Panel = MODUL VITRINI: vitrin gorunur, en az bir kart vardir, kart kumesi cekmeceyle aynidir ("Panel" disindaki her
/// oge ya izgarada ya "Hesap ve ayarlar" satirinda), vitrinde kapi komutu dugmesi YOKTUR (kapi yalniz "Kapılar"da
/// acilir) ve bir karta dokununca o kartin sayfasi acilir (AppBar basligi = kart basligi). Sonunda Panel'e donulur.
Future<void> showcaseTour(E2eScreenContext c) async {
  final tester = c.tester;
  if (!await pumpUntilFound(tester, find.byKey(kShowcaseKey), timeout: _s(6))) {
    E2eRuntime.collector.note(kind: 'navigation', message: 'Panel modul vitrini gorunmedi');
    return;
  }
  for (final key in doorCommandButtonsOnScreen()) {
    E2eRuntime.collector.note(
      kind: 'expectation',
      message: 'Panel vitrininde kapi komutu dugmesi var ($key): kapi yalniz "Kapılar" sayfasinda acilmali',
    );
  }
  final grid = showcaseCardItems();
  final secondary = showcaseChipItems();
  if (grid.isEmpty) {
    E2eRuntime.collector.note(kind: 'expectation', message: 'Panel vitrininde modul karti yok');
  }
  E2eRuntime.act('vitrin: ${grid.length} kart (${grid.map((i) => i.name).join(', ')}), ${secondary.length} ikincil');
  if (await openDrawer(tester)) {
    // IP-1D: ayar ogeleri cekmecede degil, sag ustteki disliden acilan Ayarlar panelinde; eslik ikisinin birlesimiyle.
    final drawer = <SirketMenuItem>[...drawerMenuItems()];
    await closeOverlays(tester);
    drawer.addAll(await settingsMenuItems(tester));
    for (final problem in showcaseParityProblems(drawer: drawer, grid: grid, secondary: secondary)) {
      E2eRuntime.collector.note(kind: 'expectation', message: 'Vitrin / cekmece: $problem');
    }
  } else {
    E2eRuntime.collector.note(kind: 'navigation', message: 'Cekmece acilamadi (vitrin / cekmece karsilastirmasi)');
  }

  // Bir karta dokun: dogru sayfa acilir. "Kapılar" kendi ekran taniminda (kartla) gezilir; burada baska bir kart.
  SirketMenuItem? sample;
  for (final item in grid) {
    if (item != SirketMenuItem.kapilar) {
      sample = item;
      break;
    }
  }
  final role = currentRole(tester);
  if (sample == null || role == null) return;
  final title = YanMenu.titleFor(sample, role);
  if (!await tapFinder(tester, showcaseCardFinder(sample), description: 'vitrin karti "$title"')) return;
  await settle(tester, min: const Duration(milliseconds: 900), max: const Duration(seconds: 8));
  if (!await pumpUntilFound(tester, appBarTitle(title), timeout: _s(5))) {
    E2eRuntime.collector.note(
      kind: 'navigation',
      message: 'Vitrin karti "$title" kendi sayfasini acmadi (AppBar basligi degismedi)',
    );
  }
  await c.shot('vitrin_karti_${sample.name}');
  await openDrawerAndTap(tester, 'Panel');
  await settle(tester, min: const Duration(milliseconds: 600));
}

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
    'Cihaz Ekle',
    exact: true,
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

/// "Kapılar" sayfasindaki kapi kontrol karti (AdminDoorStatusCard): site/kapi sec, detaylari ac, kapi ac, misafir
/// gecisi ve QR modali ac/kapat, gecis loglari akordiyonunu ac/kapat. Cagiran once "Kapılar"a gecmis olmalidir
/// ([kapilarScreen]); Panel artik modul vitrinidir ve orada kapi paneli YOKTUR. Kart, site/kapi secimi ve (en az bir
/// cevrimici kapida) kapi acma ZORUNLUDUR: bulunamazsa sessizce atlanmaz, bulgu yazilir.
Future<void> adminPanelTour(
  E2eScreenContext c, {
  required List<String> siteKeys,
  bool pressOpenDoor = true,
}) async {
  final card = find.byType(AdminDoorStatusCard);
  if (!await pumpUntilFound(c.tester, card, timeout: _s(6))) {
    E2eRuntime.collector.note(
      kind: 'navigation',
      message: 'Kapi paneli (AdminDoorStatusCard) yok: kapi turu "Kapılar" sayfasi disinda calisti',
    );
    return;
  }
  var opened = false;
  for (final siteKey in siteKeys) {
    final site = E2eEnv.siteName(siteKey);
    if (site == null) continue;
    if (!await c.pick(label: 'Site Seçin', item: site)) {
      E2eRuntime.collector.note(kind: 'expectation', message: 'Kapi panelinde site secilemedi: "$site"');
      continue;
    }
    await c.settleUi(min: const Duration(milliseconds: 1500));
    var index = 0;
    for (final door in E2eEnv.doorNames(siteKey)) {
      index += 1;
      if (!await c.pick(label: 'Kapı Seçin', item: door)) {
        E2eRuntime.collector.note(kind: 'expectation', message: 'Kapi panelinde kapi secilemedi: "$door" ($site)');
        continue;
      }
      await c.settleUi(min: _s(2));
      await c.shot('${siteKey}_kapi$index');
      if (findText('Detaylar', exact: true, within: card).evaluate().isNotEmpty) {
        await c.tap('Detaylar', exact: true, within: card);
        await c.expect('Cihaz UID');
        await c.shot('${siteKey}_kapi${index}_detaylar');
        await c.tap('Gizle', exact: true, required: false, within: card);
      }
      // "KAPI AÇ" yalniz bulutta cevrimici kapida cikar (aksi halde "ÇEVRİMDIŞI"): ilk cevrimici kapida bir kez.
      if (pressOpenDoor && !opened && findText('Kapı Aç', exact: true, within: card).evaluate().isNotEmpty) {
        opened = true;
        await c.tap('Kapı Aç', exact: true, within: card);
        await c.expect('Kapı açma komutu gönderildi', wait: _s(8));
      }
      if (index == 1) {
        await c.openAndClose('Kurye / Misafir Geçişi Oluştur', shotName: '${siteKey}_misafir_gecisi', within: card);
        await c.openAndClose('Giriş QR Kodu Göster', shotName: '${siteKey}_giris_qr', within: card);
      }
      await doorLogsAccordion(c, shotPrefix: '${siteKey}_kapi$index');
    }
  }
  if (pressOpenDoor && !opened) {
    E2eRuntime.collector.note(
      kind: 'expectation',
      message: 'Kapi acma sinanmadi: hicbir kapida "KAPI AÇ" hazir degildi (kapilar cevrimdisi / cihaz yok)',
    );
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
