#ifndef OTA_IMZA_H
#define OTA_IMZA_H

// OTA PAKET IMZASI (Ed25519) - SmartKeyPass cihaz tarafi MANTIGI. ARDUINO BAGIMSIZ: yalniz <stdint.h>/<stdio.h>/<string.h> + ota_ed25519.h;
// ana makinede (host_test/t_imza.cpp) aynen derlenip sinanir. Akis (ag, flash, olaylar) ota_guncelleme.h'dedir.
//
// GUVENLIK MODELI (ozet; ayrinti docs/OTA_IMZA_CIHAZ.md)
//  - Imzalayan taraf (sirket) ozel anahtari DEPO DISINDA tutar; cihaza yalniz genel anahtar gomulur (ota_public_key.h).
//  - Sunucu (VPS) ele gecirilse bile imza uretemez: cihaz imzasiz / yanlis imzali paketi ASLA kurmaz (boot bolumu degismez).
//  - Imza yalniz dosya baytlarini degil, kim-hangi-surum bilgisini de baglar. Boylece eski ama GECERLI IMZALI bir paketi yeniden
//    sunarak surum dusurtme (rollback) ve baska donanim hedefinin paketini kurdurma saldirilari imza denetiminde yakalanir.
//
// IMZALANAN ILETI (yuk) - ASCII, her satir tek "\n" ile biter (son satir dahil), baska bosluk yok. Bicim imzalama araci (tools/ota_imza,
// BAGLAYICI TANIM: tools/ota_imza/README.md) ve sunucu ile BIREBIR aynidir (tek etiket KAPI-OTA-IMZA-V1; eski taslak etiketi SKP-OTA-V1 KALDIRILDI):
//     KAPI-OTA-IMZA-V1\n
//     target=<esp32-c3 | esp32-wroom>\n
//     version=<surum, ornek 4.4.1>\n
//     size=<firmware.bin bayt sayisi, ondalik>\n
//     sha256=<firmware.bin SHA-256, 64 KUCUK harf hex>\n
//     rollback_max=<surum>\n            <- YALNIZ izinli surum dusurmede (asagida); yoksa bu satir HIC olmaz
//  `target` cihazin KENDI hedefidir (manifestten degil): C3 icin imzalanmis paket WROOM'da dogrulanmaz.
//  `size` ve `sha256` cihazin gercekte indirip flash'a yazdigi baytlardan hesaplanir (manifestin iddiasindan degil).
//  `version` manifestteki surumdur; imzali oldugu icin sunucu surumu sahte gosteremez.
//  Etiket "KAPI-OTA-IMZA-V1" alan ayiricidir: ayni anahtarla baska amacla atilan imza OTA imzasi sayilmaz.
//
// CIPLAK IMZA (manifestte `signature`; ayri dosyada da olabilir): Ed25519 imzasi, 64 bayt. Uc bicimden biri kabul edilir:
//     64 bayt ham ikili | 128 hane hex (bosluk/satir sonu serbest) | 88 karakter base64 (== dolgulu)
// IMZA DOSYASI (<paket>.sig): aracin urettigi JSON ({format, algorithm, target, version, size, sha256, [rollback_max,] key_id, signature}) ya da
// yukaridaki ciplak bicimlerden biri. JSON'u ayristirma ota_guncelleme.h'dedir (otaImzaDosyasiCozumle); yalniz format/algorithm/signature okunur.
//
// IZINLI SURUM DUSURME: Varsayilan olarak cihaz mevcut surumden DUSUK ya da ESIT surumu kurmaz. Yalniz manifest `allow_downgrade: true`
// derse VE imzalanan yukte `rollback_max=<surum>` satiri varsa VE cihazin mevcut surumu bu surumden buyuk degilse kurulur.
// Yani sunucunun tek basina verdigi izin hicbir sey acmaz; izin imzanin icindedir ve kapsami (rollback_max) sinirlidir.

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ota_ed25519.h"
#include "ota_public_key.h"

inline constexpr size_t OTA_IMZA_BOYUT = ota_ed25519::IMZA_BOYUT;              // 64
inline constexpr size_t OTA_IMZA_ANAHTAR_BOYUT = ota_ed25519::ANAHTAR_BOYUT;   // 32
inline constexpr size_t OTA_IMZA_YUK_MAX = 256;                                // yuk tamponu (en uzun gecerli yuk 200 bayt)
inline constexpr size_t OTA_IMZA_SURUM_MAX = 24;
inline constexpr size_t OTA_IMZA_HEDEF_MAX = 16;
inline constexpr char OTA_IMZA_YUK_ETIKETI[] = "KAPI-OTA-IMZA-V1";
inline constexpr char OTA_IMZA_ALGORITMA[] = "Ed25519";                       // .sig JSON'undaki "algorithm" degeri

// Gomulu genel anahtar ASCII "OTA-PUBLIC-KEY-NOT-SET-REPLACE!!" ise "anahtar yerlestirilmemis" demektir (ota_public_key.h'in teslim
// edilen hali). Tanima tablosu KASITLI OLARAK her bayti 0xA5 ile XOR'lanmis tutulur: acik metin 32 bayt ikilide YALNIZ ota_public_key.h
// hala yer tutucuysa bulunur. Boylece yayin oncesi ikili taramasi (cihaz_kontrol/tools/ota_anahtar.mjs kontrol) gercek anahtarli bir
// derlemede yanlis alarm vermez, yer tutuculu derlemeyi ise kesin yakalar.
inline constexpr uint8_t OTA_IMZA_YER_TUTUCU_MASKE = 0xA5;
inline constexpr uint8_t OTA_IMZA_YER_TUTUCU_XOR[OTA_IMZA_ANAHTAR_BOYUT] = {
  0xea, 0xf1, 0xe4, 0x88, 0xf5, 0xf0, 0xe7, 0xe9, 0xec, 0xe6, 0x88, 0xee, 0xe0, 0xfc, 0x88, 0xeb,
  0xea, 0xf1, 0x88, 0xf6, 0xe0, 0xf1, 0x88, 0xf7, 0xe0, 0xf5, 0xe9, 0xe4, 0xe6, 0xe0, 0x84, 0x84,
};

inline bool otaImzaYerTutucuMu(const uint8_t* anahtar) {
  if (anahtar == nullptr) {
    return false;
  }
  uint8_t fark = 0;
  for (size_t i = 0; i < OTA_IMZA_ANAHTAR_BOYUT; i += 1) {
    fark = static_cast<uint8_t>(fark | ((anahtar[i] ^ OTA_IMZA_YER_TUTUCU_MASKE) ^ OTA_IMZA_YER_TUTUCU_XOR[i]));
  }
  return fark == 0;
}

enum OtaAnahtarDurumu : uint8_t {
  OTA_ANAHTAR_BILINMIYOR = 0,  // henuz hesaplanmadi
  OTA_ANAHTAR_HAZIR,           // gecerli, kucuk mertebeli olmayan Ed25519 noktasi
  OTA_ANAHTAR_YER_TUTUCU,      // ota_public_key.h hala yer tutucu: hicbir paket kurulmaz
  OTA_ANAHTAR_GECERSIZ,        // nokta degil / kanonik degil / zayif (tum-sifir vb.): hicbir paket kurulmaz
};

enum OtaImzaSonuc : uint8_t {
  OTA_IMZA_TAMAM = 0,
  OTA_IMZA_ANAHTAR_YOK,    // anahtar HAZIR degil (yer tutucu ya da gecersiz)
  OTA_IMZA_ALAN_GECERSIZ,  // hedef / surum / sha256 / rollback_max imza yukune girmeye uygun degil
  OTA_IMZA_GECERSIZ,       // Ed25519 dogrulamasi basarisiz (yanlis anahtar, bozuk imza, degismis paket/surum/hedef)
};

// ---- Gomulu anahtar ----------------------------------------------------------------------------------------------------------
#if defined(OTA_IMZA_TEST_ANAHTARI)
// YALNIZ ANA MAKINE TESTLERI (host_test, /DOTA_IMZA_TEST_ANAHTARI): calisma zamaninda uretilen TEST ANAHTARI - uretimde kullanilmaz.
// Firmware (PlatformIO) derlemesinde bu bayrak TANIMLI DEGILDIR; yanlislikla tanimlansa bile baslangic degeri tum-sifirdir (gecersiz
// anahtar: OTA_ANAHTAR_GECERSIZ) ve hicbir paket kurulmaz.
inline uint8_t gOtaImzaTestAnahtari[OTA_IMZA_ANAHTAR_BOYUT] = {0};
inline const uint8_t* otaImzaAnahtari() {
  return gOtaImzaTestAnahtari;
}
#else
inline const uint8_t* otaImzaAnahtari() {
  return OTA_IMZA_GENEL_ANAHTAR;
}
#endif

inline OtaAnahtarDurumu otaImzaAnahtarDurumuHesapla(const uint8_t* anahtar) {
  if (anahtar == nullptr) {
    return OTA_ANAHTAR_GECERSIZ;
  }
  if (otaImzaYerTutucuMu(anahtar)) {
    return OTA_ANAHTAR_YER_TUTUCU;
  }
  return ota_ed25519::anahtarGecerliMi(anahtar) ? OTA_ANAHTAR_HAZIR : OTA_ANAHTAR_GECERSIZ;
}

// ---- Imza yukune girecek alanlarin dogrulanmasi (satir ekleme / alan karistirma saldirilarini kapatir) ------------------------------
inline bool otaImzaSurumGecerliMi(const char* s) {
  if (s == nullptr) {
    return false;
  }
  const size_t n = strlen(s);
  if (n == 0 || n > OTA_IMZA_SURUM_MAX) {
    return false;
  }
  for (size_t i = 0; i < n; i += 1) {
    const char c = s[i];
    const bool harfRakam = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    if (!(harfRakam || (i > 0 && (c == '.' || c == '_' || c == '+' || c == '-')))) {
      return false;
    }
  }
  return true;
}

inline bool otaImzaHedefGecerliMi(const char* s) {
  if (s == nullptr) {
    return false;
  }
  const size_t n = strlen(s);
  if (n == 0 || n > OTA_IMZA_HEDEF_MAX) {
    return false;
  }
  for (size_t i = 0; i < n; i += 1) {
    const char c = s[i];
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || (i > 0 && c == '-'))) {
      return false;
    }
  }
  return true;
}

// 64 hane, YALNIZ kucuk harf hex (yuk tek bicimli olsun: imzalayan ve cihaz ayni baytlari uretir)
inline bool otaImzaSha256GecerliMi(const char* s) {
  if (s == nullptr || strlen(s) != 64) {
    return false;
  }
  for (size_t i = 0; i < 64; i += 1) {
    const char c = s[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
      return false;
    }
  }
  return true;
}

// ---- Imza yuku -----------------------------------------------------------------------------------------------------------------
namespace ota_imza_ic {
// Sinirli ekleme: tasarsa yazma pozisyonunu cap+1'e iter (cagiran bunu hata sayar).
inline void ekle(char* out, size_t cap, size_t& pos, const char* metin) {
  const size_t n = strlen(metin);
  if (pos + n <= cap) {
    memcpy(out + pos, metin, n);
  }
  pos += n;
}
}  // namespace ota_imza_ic

// Imza yukunu `out`a yazar (NUL'suz; dondurulen uzunluk kullanilir). 0 = gecersiz alan ya da tampon yetmedi.
// rollbackMax: nullptr ya da bos = izinli dusurme YOK (satir eklenmez).
inline size_t otaImzaYukuOlustur(char* out, size_t cap, const char* hedef, const char* surum, uint32_t boyut, const char* sha256,
                                 const char* rollbackMax) {
  if (out == nullptr || !otaImzaHedefGecerliMi(hedef) || !otaImzaSurumGecerliMi(surum) || !otaImzaSha256GecerliMi(sha256)) {
    return 0;
  }
  const bool dusurme = rollbackMax != nullptr && rollbackMax[0] != '\0';
  if (dusurme && !otaImzaSurumGecerliMi(rollbackMax)) {
    return 0;
  }
  char boyutMetni[16];
  snprintf(boyutMetni, sizeof(boyutMetni), "%lu", static_cast<unsigned long>(boyut));

  size_t pos = 0;
  ota_imza_ic::ekle(out, cap, pos, OTA_IMZA_YUK_ETIKETI);
  ota_imza_ic::ekle(out, cap, pos, "\ntarget=");
  ota_imza_ic::ekle(out, cap, pos, hedef);
  ota_imza_ic::ekle(out, cap, pos, "\nversion=");
  ota_imza_ic::ekle(out, cap, pos, surum);
  ota_imza_ic::ekle(out, cap, pos, "\nsize=");
  ota_imza_ic::ekle(out, cap, pos, boyutMetni);
  ota_imza_ic::ekle(out, cap, pos, "\nsha256=");
  ota_imza_ic::ekle(out, cap, pos, sha256);
  if (dusurme) {
    ota_imza_ic::ekle(out, cap, pos, "\nrollback_max=");
    ota_imza_ic::ekle(out, cap, pos, rollbackMax);
  }
  ota_imza_ic::ekle(out, cap, pos, "\n");
  return pos <= cap ? pos : 0;
}

// ---- Imza dosyasi / metni cozumleme ------------------------------------------------------------------------------------------------
namespace ota_imza_ic {
inline int hexDegeri(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}
inline int base64Degeri(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}
inline bool bosluk(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}
}  // namespace ota_imza_ic

// 64 bayt ham | 128 hane hex | 88 karakter base64 (dolgulu) -> out[64]. Baska her sey false (out degismeyebilir).
inline bool otaImzaCozumle(const uint8_t* veri, size_t n, uint8_t out[OTA_IMZA_BOYUT]) {
  if (veri == nullptr) {
    return false;
  }
  if (n == OTA_IMZA_BOYUT) {
    memcpy(out, veri, OTA_IMZA_BOYUT);
    return true;
  }
  size_t bas = 0;
  size_t son = n;
  while (bas < son && ota_imza_ic::bosluk(veri[bas])) {
    bas += 1;
  }
  while (son > bas && ota_imza_ic::bosluk(veri[son - 1])) {
    son -= 1;
  }
  const uint8_t* m = veri + bas;
  const size_t len = son - bas;

  uint8_t gecici[OTA_IMZA_BOYUT];
  if (len == 2 * OTA_IMZA_BOYUT) {
    for (size_t i = 0; i < OTA_IMZA_BOYUT; i += 1) {
      const int yuksek = ota_imza_ic::hexDegeri(static_cast<char>(m[2 * i]));
      const int dusuk = ota_imza_ic::hexDegeri(static_cast<char>(m[2 * i + 1]));
      if (yuksek < 0 || dusuk < 0) {
        return false;
      }
      gecici[i] = static_cast<uint8_t>((yuksek << 4) | dusuk);
    }
    memcpy(out, gecici, OTA_IMZA_BOYUT);
    return true;
  }
  if (len == 88) {  // 21 tam dortlu (63 bayt) + "xx==" (1 bayt) = 64 bayt
    size_t cikis = 0;
    for (size_t g = 0; g < 22; g += 1) {
      const uint8_t* q = m + 4 * g;
      const bool son4 = (g == 21);
      const int a = ota_imza_ic::base64Degeri(static_cast<char>(q[0]));
      const int b = ota_imza_ic::base64Degeri(static_cast<char>(q[1]));
      if (a < 0 || b < 0) {
        return false;
      }
      if (!son4) {
        const int c = ota_imza_ic::base64Degeri(static_cast<char>(q[2]));
        const int d = ota_imza_ic::base64Degeri(static_cast<char>(q[3]));
        if (c < 0 || d < 0) {
          return false;
        }
        gecici[cikis++] = static_cast<uint8_t>((a << 2) | (b >> 4));
        gecici[cikis++] = static_cast<uint8_t>(((b & 15) << 4) | (c >> 2));
        gecici[cikis++] = static_cast<uint8_t>(((c & 3) << 6) | d);
      } else {
        // son grup: tek bayt + "==" ; kullanilmayan 4 bit sifir olmali (kanonik kodlama)
        if (q[2] != '=' || q[3] != '=' || (b & 15) != 0) {
          return false;
        }
        gecici[cikis++] = static_cast<uint8_t>((a << 2) | (b >> 4));
      }
    }
    if (cikis != OTA_IMZA_BOYUT) {
      return false;
    }
    memcpy(out, gecici, OTA_IMZA_BOYUT);
    return true;
  }
  return false;
}

// ---- Dogrulama -----------------------------------------------------------------------------------------------------------------
// Imza, `anahtar` icin (hedef, surum, boyut, sha256 [, rollbackMax]) yukunu imzalamis mi? Anahtar HAZIR degilse hicbir imza gecerli
// sayilmaz (yer tutucu / zayif anahtarla dogrulama basarisi UYDURULAMAZ).
inline OtaImzaSonuc otaImzaDogrula(const uint8_t imza[OTA_IMZA_BOYUT], const uint8_t* anahtar, const char* hedef, const char* surum,
                                   uint32_t boyut, const char* sha256, const char* rollbackMax) {
  if (otaImzaAnahtarDurumuHesapla(anahtar) != OTA_ANAHTAR_HAZIR) {
    return OTA_IMZA_ANAHTAR_YOK;
  }
  char yuk[OTA_IMZA_YUK_MAX];
  const size_t n = otaImzaYukuOlustur(yuk, sizeof(yuk), hedef, surum, boyut, sha256, rollbackMax);
  if (n == 0) {
    return OTA_IMZA_ALAN_GECERSIZ;
  }
  return ota_ed25519::dogrula(imza, reinterpret_cast<const uint8_t*>(yuk), n, anahtar) ? OTA_IMZA_TAMAM : OTA_IMZA_GECERSIZ;
}

#endif
