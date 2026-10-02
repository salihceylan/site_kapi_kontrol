// Site Yonetimi / Daire Sakinleri ekrani gezintisi (SitesView) — yalniz ac/kapat etkilesimleri.
// "Sil", "Onayla", "Reddet", PDF, "Bilgileri Gonder" gibi veri degistiren/yan etkili dugmelere
// DOKUNULMAZ (E2ePolicy + bu betik).

import 'e2e_driver.dart';
import 'e2e_env.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

/// Secilen sitenin yapisini (yoneticiler, daireler, kapilar) ve ilgili diyaloglari gezer.
Future<void> sitesTour(
  E2eScreenContext c, {
  required String siteKey,
  bool canCreateSite = false,
  bool apartmentMode = false,
  bool canInviteManager = true,
  String newSiteTitle = 'Yeni Site Ekle',
}) async {
  final site = E2eEnv.siteName(siteKey);
  if (canCreateSite) {
    await c.openAndClose(
      'Yeni Site',
      exact: true,
      shotName: 'yeni_site_diyalogu',
      expectTexts: <String>[newSiteTitle],
    );
  }
  if (site == null) return;
  if (!await c.tap(site, required: false)) return;
  await c.settleUi(min: _s(2));
  await c.expect('Site Kodu', wait: _s(8));
  await c.shot('secili_site');
  await c.shotAtEnd('secili_site_sonu');

  await c.openAndClose('Siteyi Düzenle', exact: true, shotName: 'site_duzenle', expectTexts: const <String>['Site Düzenle']);
  // Site karti dokununca acilir/kapanir: onceki ziyaretten kalan secim yuzunden kapaliysa yeniden ac.
  if (!c.has('Giriş & Güvenlik Politikaları', exact: true)) {
    await c.tap(site, required: false);
    await c.settleUi(min: const Duration(milliseconds: 800));
  }
  await c.openAndClose('Giriş & Güvenlik Politikaları', exact: true, shotName: 'guvenlik_politikalari');
  await c.openAndClose('Site Katılım QR', exact: true, shotName: 'site_katilim_qr');
  await c.openAndClose('Katılım Talepleri', exact: true, shotName: 'katilim_talepleri');
  await c.openAndClose('Sakin Listesi (Akordiyon)', exact: true, shotName: 'sakin_listesi');
  if (canInviteManager) {
    await c.openAndClose('Yönetici Davet Et', exact: true, shotName: 'yonetici_davet_diyalogu');
  }

  // Daireler akordiyonu -> ilk daire karti -> sakin duzenleme diyalogu (kaydetmeden).
  if (await c.tap('Daireler', exact: true, required: false)) {
    await c.settleUi(min: const Duration(milliseconds: 800));
    await c.shot('daireler_acik');
    final apartment = E2eEnv.firstApartmentLabel(siteKey);
    if (apartment != null && await c.tap(apartment, exact: true, required: false)) {
      await c.settleUi(min: const Duration(milliseconds: 600));
      await c.shot('daire_karti_acik');
      await c.openAndClose('Düzenle', exact: true, shotName: 'daire_sakin_duzenle');
      await c.tap(apartment, exact: true, required: false);
    }
    await c.tap('Daireler', exact: true, required: false);
  }

  // Kapilar: yeni kapi diyalogu, kapi menusu (yetkiler / duzenle), cihaz atama diyalogu.
  await c.openAndClose('Yeni Kapı', exact: true, shotName: 'yeni_kapi_diyalogu');
  await c.openByAndClose(() => c.popupMenu('Kapı Yetkileri'), name: 'kapi_yetkileri');
  await c.openByAndClose(() => c.popupMenu('Kapıyı Düzenle'), name: 'kapi_duzenle');
  if (c.has('Değiştir', exact: true)) {
    await c.openAndClose('Değiştir', exact: true, shotName: 'kapi_cihaz_degistir');
  } else if (c.has('Cihaz Ata', exact: true)) {
    await c.openAndClose('Cihaz Ata', exact: true, shotName: 'kapi_cihaz_ata');
  }
  await c.tapTip('Yenile', required: false);
}
