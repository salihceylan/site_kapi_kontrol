#ifndef OTA_PUBLIC_KEY_H
#define OTA_PUBLIC_KEY_H

#include <stdint.h>

// =====================================================================================================================
//  OTA IMZA GENEL ANAHTARI (Ed25519, 32 bayt)
//
//  DURUM: YER TUTUCU  (gercek anahtar henuz yerlestirilmedi)
//
//  Bu dosyada YALNIZ GENEL (public) anahtar bulunur; sir degildir. OZEL (private) ANAHTAR ASLA bu depoya, bu dosyaya, bir gunluge
//  ya da bir teste yazilmaz: imzalayan makinede, depo DISINDA saklanir (docs/OTA_IMZA_CIHAZ.md).
//
//  ANAHTAR URETINCE DEGISTIR (yer tutucu ile uretim derlemesi YAPMAYIN):
//    1) Imza anahtar ciftini uretin (ozel anahtar depo disinda kalir; yalniz genel anahtar kopyalanir).
//    2) Genel anahtari bu dosyaya yazin - elle duzenlemek yerine:
//         node cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar: 64 hane hex | base64 | SPKI PEM dosyasi>
//       (bu betik dosyayi bastan yazar ve parmak izini gosterir)
//    3) Derleyin; yayinlamadan once ikilide yer tutucu KALMADIGINI ve dogru anahtarin gomuldugunu denetleyin:
//         node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar>
//    4) Kartin seri cikisinda "OTA imza anahtari: HAZIR (parmak izi ...)" satirini ve parmak izinin betigin gosterdigiyle ayni
//       oldugunu dogrulayin.
//    Yayin derlemesinde SKP_OTA_ANAHTAR_ZORUNLU=1 ortam degiskeni yer tutuculu derlemeyi DERLEME asamasinda durdurur
//    (tools/ota_anahtar_kontrol_pio.py; yer tutucu varken bu degisken yoksa yalniz UYARI basar).
//
//  YER TUTUCU ILE NE OLUR: cihaz yer tutucuyu CALISMA ZAMANINDA tanir ve hicbir paketi KURMAZ ("imza anahtari yerlestirilmemis").
//  Yani yanlislikla yer tutuculu bir surum yayinlanirsa o cihazlar bir daha OTA ile guncellenemez (USB gerekir). Bu yuzden
//  yayin oncesi 3. adim ZORUNLUDUR.
// =====================================================================================================================
inline constexpr uint8_t OTA_IMZA_GENEL_ANAHTAR[32] = {
  // ASCII "OTA-PUBLIC-KEY-NOT-SET-REPLACE!!" (gecerli bir anahtar DEGILDIR)
  0x4f, 0x54, 0x41, 0x2d, 0x50, 0x55, 0x42, 0x4c, 0x49, 0x43, 0x2d, 0x4b, 0x45, 0x59, 0x2d, 0x4e,
  0x4f, 0x54, 0x2d, 0x53, 0x45, 0x54, 0x2d, 0x52, 0x45, 0x50, 0x4c, 0x41, 0x43, 0x45, 0x21, 0x21,
};

#endif
