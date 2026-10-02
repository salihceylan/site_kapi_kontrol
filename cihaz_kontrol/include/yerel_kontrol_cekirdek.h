#ifndef YEREL_KONTROL_CEKIRDEK_H
#define YEREL_KONTROL_CEKIRDEK_H

// Yerel kontrol protokolu v2 CEKIRDEGI (sartname: LOCALCTRL_V2): challenge'a bagli HMAC-SHA256 dogrulamasi ve
// challenge / yinelenen-paket durum makinesi.
//  - ARDUINO BAGIMSIZDIR: yalniz <stddef.h>, <stdint.h>, <string.h> ve mbedtls/md.h kullanir. Ayni dosya ana makinede (host),
//    mbedtls_md_hmac'in referans bir SHA-256/HMAC ile degistirildigi sahte bir mbedtls/md.h ile BIREBIR derlenip test edilir.
//  - Zamanlayicilar {baslangic, sure} + ISARETSIZ fark ((uint32_t)(simdi - baslangic) >= sure) kalibidir. "millis()+x" bitis
//    damgasi SAKLANMAZ ve isaretli karsilastirma YOKTUR (24,86 gunde isaretli tasma, 49,7 gunde millis sarmasi). Yinelenen-paket
//    kaydi her zamanlayici adiminda suresi dolunca KILITLI sekilde kapatilir (pencereyi yeniden acacak bayat damga kalmaz).
//  - Sir (token) hicbir dizeye / loga yazilmaz; imza yalniz sabit zamanli karsilastirilir; paket tarafinda token YOKTUR.
//
// Protokol ozeti (ayrintilar LOCALCTRL_V2.md):
//   sig = lowerhex( HMAC-SHA256( key = token, msg = action + "|" + UID_BUYUK + "|" + ch ) ),  ch = 16 kucuk hex (8 rastgele bayt)
//   ch cihaz tarafindan her 10 sn'de dondurulur (guncel + onceki kabul), basarili acmada yeniden uretilir.

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <mbedtls/md.h>

inline constexpr uint32_t YEREL_CH_DONME_MS = 10000UL;           // challenge her 10 sn'de bir doner
inline constexpr uint32_t YEREL_YINELEME_PENCERESI_MS = 3000UL;  // ayni ch+sig bu surede tekrar gelirse "duplicate"
inline constexpr size_t YEREL_CH_UZUNLUK = 16;                   // 8 bayt -> 16 kucuk hex
inline constexpr size_t YEREL_SIG_UZUNLUK = 64;                  // 32 bayt -> 64 kucuk hex

using YerelRastgele32 = uint32_t (*)();   // firmware: esp_random
using YerelRoleTetikle = bool (*)();      // firmware: roleTetikle (true: role tetiklendi)

struct YerelDurum {
  char ch[YEREL_CH_UZUNLUK + 1];              // guncel challenge
  char onceki[YEREL_CH_UZUNLUK + 1];          // bir onceki challenge ("" = yok)
  uint32_t chBaslangicMs;                     // guncel challenge'in uretildigi an
  bool sonKabulVar;                           // son kabul kaydi gecerli mi (yinelenen-paket penceresi acik)
  uint8_t sonKabulEylem;                      // 0: open, 1: pulse
  char sonKabulCh[YEREL_CH_UZUNLUK + 1];
  char sonKabulSig[YEREL_SIG_UZUNLUK + 1];
  uint32_t sonKabulBaslangicMs;               // son kabulun zamani
};

enum YerelSonuc : uint8_t {
  YEREL_SONUC_KABUL = 0,      // imza dogru + role tetiklendi: yanit + yan etkiler cagirana ait; challenge yenilendi, kabul kaydedildi
  YEREL_SONUC_YINELENEN,      // son 3 sn'de kabul edilmis ayni ch+sig: {"ok":true,"duplicate":true}; role TETIKLENMEDI
  YEREL_SONUC_CHALLENGE,      // ch gecersiz/eski/yok -> "challenge" hatasi + guncel ch
  YEREL_SONUC_YETKISIZ,       // imza yanlis/bicim hatali (ch dogru) -> "unauthorized"
  YEREL_SONUC_TOKEN_YOK,      // token yok ya da HMAC oz-testi basarisiz (fail-closed) -> "unauthorized", local_control_available:false
  YEREL_SONUC_ROLE_MESGUL,    // imza dogru ama role mesgul -> "role_mesgul"; challenge TUKETILMEDI
};

// s tam 'uzunluk' karakter ve hepsi [0-9a-f] ise true (s'nin sonundaki NUL dahil; ilk NUL'dan oteye okunmaz).
inline bool yerelHexMi(const char* s, size_t uzunluk) {
  if (s == nullptr) {
    return false;
  }
  for (size_t i = 0; i < uzunluk; i += 1) {
    const char c = s[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
      return false;  // NUL da buraya duser: kisa dize, ilk NUL'dan oteye okunmaz
    }
  }
  return s[uzunluk] == '\0';
}

inline void yerelHexYaz(const uint8_t* veri, size_t n, char* cikis) {
  static const char RAKAM[] = "0123456789abcdef";
  for (size_t i = 0; i < n; i += 1) {
    cikis[2 * i] = RAKAM[veri[i] >> 4];
    cikis[2 * i + 1] = RAKAM[veri[i] & 0x0F];
  }
  cikis[2 * n] = '\0';
}

// Sabit zamanli esitlik (device_konfig.h sabitZamanliEsit'in char* esdegeri; ayni algoritma): erken cikis YOK. a ve b en az n bayt olmali.
inline bool yerelSabitEsit(const char* a, const char* b, size_t n) {
  uint8_t fark = 0;
  for (size_t i = 0; i < n; i += 1) {
    fark |= static_cast<uint8_t>(static_cast<uint8_t>(a[i]) ^ static_cast<uint8_t>(b[i]));
  }
  return fark == 0;
}

// 8 rastgele bayt -> 16 kucuk hex (+NUL; cikis en az 17 bayt)
inline void yerelChUret(char* cikis, YerelRastgele32 rnd) {
  uint8_t ham[8];
  for (size_t i = 0; i < 2; i += 1) {
    const uint32_t r = rnd();
    ham[4 * i + 0] = static_cast<uint8_t>(r >> 24);
    ham[4 * i + 1] = static_cast<uint8_t>(r >> 16);
    ham[4 * i + 2] = static_cast<uint8_t>(r >> 8);
    ham[4 * i + 3] = static_cast<uint8_t>(r);
  }
  yerelHexYaz(ham, sizeof(ham), cikis);
}

// Guncel ch'yi yeniden uretir ve onceki'yi BOSALTIR (acilis / basarili acma sonrasi). Zamanlayiciyi yeniden baslatir.
inline void yerelChBaslat(YerelDurum& d, uint32_t simdi, YerelRastgele32 rnd) {
  yerelChUret(d.ch, rnd);
  d.onceki[0] = '\0';
  d.chBaslangicMs = simdi;
}

// Her loop turunda (ve her istekte) cagrilir: ch'yi dondurur (10 sn), yinelenen-paket penceresini suresi dolunca KILITLI kapatir.
// Loop uzun sure (>= 20 sn) bloke kalmissa eski guncel ch artik "onceki" olarak da KABUL EDILMEZ (en fazla ~2 donem gecerlilik).
inline void yerelChZamanlayici(YerelDurum& d, uint32_t simdi, YerelRastgele32 rnd) {
  if (d.ch[0] == '\0') {
    yerelChBaslat(d, simdi, rnd);
  } else {
    const uint32_t gecen = simdi - d.chBaslangicMs;  // ISARETSIZ fark
    if (gecen >= YEREL_CH_DONME_MS) {
      if (gecen >= 2U * YEREL_CH_DONME_MS) {
        d.onceki[0] = '\0';
      } else {
        memcpy(d.onceki, d.ch, sizeof(d.onceki));
      }
      yerelChUret(d.ch, rnd);
      d.chBaslangicMs = simdi;
    }
  }
  if (d.sonKabulVar && static_cast<uint32_t>(simdi - d.sonKabulBaslangicMs) >= YEREL_YINELEME_PENCERESI_MS) {
    d.sonKabulVar = false;
  }
}

// out = action + "|" + UID_BUYUK + "|" + ch. Donus: uzunluk (NUL haric); sigmazsa / bos girdi 0.
inline size_t yerelMesajKur(char* out, size_t kapasite, const char* action, const char* uid, const char* ch) {
  if (out == nullptr || action == nullptr || uid == nullptr || ch == nullptr) {
    return 0;
  }
  size_t n = 0;
  const size_t la = strlen(action);
  const size_t lu = strlen(uid);
  const size_t lc = strlen(ch);
  if (la == 0 || lu == 0 || lc == 0 || la + lu + lc + 2 + 1 > kapasite) {
    return 0;
  }
  memcpy(out + n, action, la);
  n += la;
  out[n++] = '|';
  for (size_t i = 0; i < lu; i += 1) {
    const char c = uid[i];
    out[n++] = (c >= 'a' && c <= 'z') ? static_cast<char>(c - 'a' + 'A') : c;  // UID BUYUK harf
  }
  out[n++] = '|';
  memcpy(out + n, ch, lc);
  n += lc;
  out[n] = '\0';
  return n;
}

// sig = lowerhex(HMAC-SHA256(key = UTF-8(token), msg = action|UID_BUYUK|ch)); cikis en az 65 bayt. false: hesaplanamadi.
inline bool yerelImzaHesapla(const char* token, const char* action, const char* uid, const char* ch, char* cikis) {
  if (token == nullptr || token[0] == '\0' || cikis == nullptr) {
    return false;
  }
  char mesaj[80];
  const size_t n = yerelMesajKur(mesaj, sizeof(mesaj), action, uid, ch);
  if (n == 0) {
    return false;
  }
  const mbedtls_md_info_t* bilgi = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (bilgi == nullptr) {
    return false;
  }
  uint8_t mac[32];
  if (mbedtls_md_hmac(bilgi, reinterpret_cast<const unsigned char*>(token), strlen(token),
                      reinterpret_cast<const unsigned char*>(mesaj), n, mac) != 0) {
    return false;
  }
  yerelHexYaz(mac, sizeof(mac), cikis);
  return true;
}

// Bilinen-cevap testi (KAT): sartnamedeki vektor. Uretimle AYNI yerelImzaHesapla yolu kullanilir. Acilista bir kez calistirilir;
// false ise firmware yerel acmayi KAPALI tutar (fail-closed). Vektor herkese acik bir TEST degeridir (gercek token degildir).
inline constexpr char YEREL_KAT_TOKEN[] = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE";
inline constexpr char YEREL_KAT_UID[] = "240AC4E2E001";
inline constexpr char YEREL_KAT_CH[] = "0123456789abcdef";
inline constexpr char YEREL_KAT_SIG_OPEN[] = "92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4";
inline constexpr char YEREL_KAT_SIG_PULSE[] = "3bb6390fa9c7a2135232000306e9a6293e38fabd736edcf7400ecd55c597b881";

inline bool yerelKatCalistir() {
  char imza[YEREL_SIG_UZUNLUK + 1];
  if (!yerelImzaHesapla(YEREL_KAT_TOKEN, "open", YEREL_KAT_UID, YEREL_KAT_CH, imza) ||
      !yerelSabitEsit(imza, YEREL_KAT_SIG_OPEN, YEREL_SIG_UZUNLUK)) {
    return false;
  }
  if (!yerelImzaHesapla(YEREL_KAT_TOKEN, "pulse", YEREL_KAT_UID, YEREL_KAT_CH, imza) ||
      !yerelSabitEsit(imza, YEREL_KAT_SIG_PULSE, YEREL_SIG_UZUNLUK)) {
    return false;
  }
  return true;
}

// Acma / pulse istegini degerlendirir (kaynak adres ve hedef UID kontrolleri CAGIRANDA yapilmistir). Sira (sartname):
//  (1) token yok / HMAC saglam degil -> TOKEN_YOK;  (2) ayni ch+sig son 3 sn'de kabul edilmis -> YINELENEN (role TETIKLENMEZ);
//  (3) ch gecersiz/eski -> CHALLENGE;  (4) imza yanlis -> YETKISIZ;  (5) role tetiklenemezse -> ROLE_MESGUL (challenge TUKETILMEZ);
//  (6) basari: challenge'lar yeniden uretilir (onceki bosalir) + son-kabul kaydi (ch, sig, zaman) -> KABUL.
// uid: bu cihazin UID'si (BUYUK harf hex). ch / sig: pakettekiler ("" = yok). token: kayitli yerel kontrol anahtari.
inline YerelSonuc yerelAcmaDegerlendir(YerelDurum& d, const char* token, bool hmacSaglam, const char* uid, const char* action,
                                       const char* ch, const char* sig, uint32_t simdi, YerelRoleTetikle role,
                                       YerelRastgele32 rnd) {
  yerelChZamanlayici(d, simdi, rnd);

  if (token == nullptr || token[0] == '\0' || !hmacSaglam) {
    return YEREL_SONUC_TOKEN_YOK;
  }
  if (action == nullptr) {
    return YEREL_SONUC_YETKISIZ;
  }
  uint8_t eylem;
  if (strcmp(action, "open") == 0) {
    eylem = 0;
  } else if (strcmp(action, "pulse") == 0) {
    eylem = 1;
  } else {
    return YEREL_SONUC_YETKISIZ;
  }
  if (ch == nullptr) {
    ch = "";
  }
  if (sig == nullptr) {
    sig = "";
  }
  const bool chBicimOk = yerelHexMi(ch, YEREL_CH_UZUNLUK);
  const bool sigBicimOk = yerelHexMi(sig, YEREL_SIG_UZUNLUK);

  // Yinelenen paket: ch artik gecerli olmayabilir (kabulde yenilendi) -> challenge denetiminden ONCE bakilir.
  if (chBicimOk && sigBicimOk && d.sonKabulVar && d.sonKabulEylem == eylem &&
      static_cast<uint32_t>(simdi - d.sonKabulBaslangicMs) < YEREL_YINELEME_PENCERESI_MS &&
      yerelSabitEsit(ch, d.sonKabulCh, YEREL_CH_UZUNLUK) && yerelSabitEsit(sig, d.sonKabulSig, YEREL_SIG_UZUNLUK)) {
    return YEREL_SONUC_YINELENEN;
  }

  if (!chBicimOk) {
    return YEREL_SONUC_CHALLENGE;
  }
  const bool guncelMi = yerelSabitEsit(ch, d.ch, YEREL_CH_UZUNLUK);
  const bool oncekiMi = d.onceki[0] != '\0' && yerelSabitEsit(ch, d.onceki, YEREL_CH_UZUNLUK);
  if (!guncelMi && !oncekiMi) {
    return YEREL_SONUC_CHALLENGE;
  }

  if (!sigBicimOk) {
    return YEREL_SONUC_YETKISIZ;
  }
  char beklenen[YEREL_SIG_UZUNLUK + 1];
  if (!yerelImzaHesapla(token, action, uid, ch, beklenen)) {
    return YEREL_SONUC_YETKISIZ;  // hesaplanamadi: fail-closed
  }
  if (!yerelSabitEsit(beklenen, sig, YEREL_SIG_UZUNLUK)) {
    return YEREL_SONUC_YETKISIZ;
  }

  if (role == nullptr || !role()) {
    return YEREL_SONUC_ROLE_MESGUL;
  }

  yerelChBaslat(d, simdi, rnd);
  memcpy(d.sonKabulCh, ch, sizeof(d.sonKabulCh));
  memcpy(d.sonKabulSig, sig, sizeof(d.sonKabulSig));
  d.sonKabulEylem = eylem;
  d.sonKabulBaslangicMs = simdi;
  d.sonKabulVar = true;
  return YEREL_SONUC_KABUL;
}

#endif
