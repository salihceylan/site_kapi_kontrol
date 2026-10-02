#ifndef ADMIN_PIN_H
#define ADMIN_PIN_H

// Yonetici ekran PIN'i (C10) - YALNIZ ekranli WROOM hedefi kullanir.
//  - PIN ana MCU NVS'inde (namespace admin_cfg, anahtar admin_pin, 6 hane) saklanir; ekranda sabit PIN YOKTUR.
//  - PIN yoksa yonetici menusu kilitlidir (ADMIN_PIN_TANIMSIZ).
//  - Ardisik 5 hatali denemede 5 dk kilit; kilit bitince yalniz 1 deneme hakki verilir (4 hata sayilir),
//    sayac kalici (NVS) oldugu icin yeniden baslatma kilidi atlatmaz (acilista kilit 5 dk yeniden baslar).
//  - PIN tanimlama: MQTT {"action":"admin_pin_config","admin_pin":"NNNNNN"} veya seri satir ADMINPIN:NNNNNN.
//  - ZAYIF PIN'ler reddedilir (adminPinZayifMi: 000000, 111111, 123456, 654321, 123123, 121212, 112233, 000001, hepsi ayni rakam,
//    tam ardisik artan/azalan); ret nedeni seriye ve MQTT olayina yazilir (weak_pin / invalid_pin), PIN degeri ASLA yazilmaz.
//  - PIN hicbir zaman seriye/MQTT'ye yazdirilmaz.

#include <Arduino.h>
#include <Preferences.h>

#include "device_konfig.h"

inline constexpr char ADMIN_PREFS_NAMESPACE[] = "admin_cfg";
inline constexpr char ADMIN_PREF_PIN[] = "admin_pin";
inline constexpr char ADMIN_PREF_FAIL[] = "pin_fail";
inline constexpr size_t ADMIN_PIN_UZUNLUK = 6;
inline constexpr uint8_t ADMIN_PIN_MAX_HATA = 5;
inline constexpr unsigned long ADMIN_PIN_KILIT_MS = 5UL * 60UL * 1000UL;

enum AdminPinSonuc : uint8_t {
  ADMIN_PIN_OK = 0,
  ADMIN_PIN_YANLIS = 1,
  ADMIN_PIN_KILITLI = 2,
  ADMIN_PIN_TANIMSIZ = 3,
};

// adminPinAyarla'nin ret nedeni (PIN DEGERI asla yazilmaz; yalnizca neden seriye / MQTT olayina gider)
enum AdminPinRed : uint8_t {
  ADMIN_PIN_RED_YOK = 0,
  ADMIN_PIN_RED_BICIM = 1,   // tam 6 rakam degil
  ADMIN_PIN_RED_ZAYIF = 2,   // zayif / tahmin edilebilir PIN (adminPinZayifMi)
};

inline Preferences gAdminPrefs;
inline String gAdminPin;
inline uint8_t gAdminPinHata = 0;
inline bool gAdminKilitAktif = false;
// Kilit zamani {baslangic, sure=ADMIN_PIN_KILIT_MS}: karsilastirma ISARETSIZ (simdi - baslangic >= sure). Eskiden saklanan "millis()+5dk"
// bitis damgasi ISARETLI karsilastiriliyordu: kilit bittikten >= 24,86 gun sonraki ilk sorguda damga "gelecek" sayilir, kilit tekrar
// "aktif" gorunurdu. adminPinZamanlayici() ana donguden cagrilir: kilit suresi dolunca bayrak KILITLI sekilde kapanir.
inline uint32_t gAdminKilitBaslangicMs = 0;

inline bool adminPinBicimGecerli(const String& pin) {
  if (pin.length() != ADMIN_PIN_UZUNLUK) {
    return false;
  }
  for (size_t i = 0; i < pin.length(); i += 1) {
    if (pin[i] < '0' || pin[i] > '9') {
      return false;
    }
  }
  return true;
}

inline bool adminPinTanimliMi() {
  return !gAdminPin.isEmpty();
}

// Zayif / tahmin edilebilir PIN mi? (6 haneli rakam dizisi icin; bicim denetimi adminPinBicimGecerli'de)
//  - sabit liste: 000000, 111111, 123456, 654321, 123123, 121212, 112233, 000001
//  - hepsi ayni rakam (222222 ...) ve tam ardisik diziler: artan (012345, 123456, 234567, ... 567890 ... 901234) ve
//    azalan (987654, 876543, 765432, 654321, 543210 ... 098765); 9'dan sonra 0 gelir (tus takimi sirasi, mod 10)
inline bool adminPinZayifMi(const String& pin) {
  if (pin.length() != ADMIN_PIN_UZUNLUK) {
    return false;
  }
  static const char* const ZAYIF_LISTE[] = {"000000", "111111", "123456", "654321", "123123", "121212", "112233", "000001"};
  for (size_t i = 0; i < sizeof(ZAYIF_LISTE) / sizeof(ZAYIF_LISTE[0]); i += 1) {
    if (pin == ZAYIF_LISTE[i]) {
      return true;
    }
  }
  bool hepsiAyni = true;
  bool artan = true;
  bool azalan = true;
  for (size_t i = 1; i < pin.length(); i += 1) {
    const int onceki = pin[i - 1] - '0';
    const int simdi = pin[i] - '0';
    if (simdi != onceki) {
      hepsiAyni = false;
    }
    if (simdi != (onceki + 1) % 10) {
      artan = false;
    }
    if (simdi != (onceki + 9) % 10) {
      azalan = false;
    }
  }
  return hepsiAyni || artan || azalan;
}

inline const char* adminPinRedMetni(AdminPinRed red) {
  return red == ADMIN_PIN_RED_ZAYIF ? "weak_pin" : "invalid_pin";
}

inline void adminPinKilitBaslat() {
  gAdminKilitAktif = true;
  gAdminKilitBaslangicMs = static_cast<uint32_t>(millis());
}

inline void adminPinBaslat() {
  gAdminPrefs.begin(ADMIN_PREFS_NAMESPACE, false);
  const String kayitli = gAdminPrefs.getString(ADMIN_PREF_PIN, "");
  gAdminPin = adminPinBicimGecerli(kayitli) ? kayitli : String("");
  gAdminPinHata = gAdminPrefs.getUChar(ADMIN_PREF_FAIL, 0);
  gAdminKilitAktif = false;
  if (gAdminPinHata >= ADMIN_PIN_MAX_HATA) {
    adminPinKilitBaslat();  // yeniden baslatma kilidi sifirlamaz
  }
}

// pin bos ise PIN silinir (menu kilitlenir). Gecersiz biciminde ya da ZAYIF PIN'de false doner (PIN/sayac degismez);
// ret nedeni red'e yazilir (PIN DEGERI hicbir yere yazilmaz): cagiran seriye / MQTT olayina NEDEN'i yazmalidir.
inline bool adminPinAyarla(const String& pin, AdminPinRed* red = nullptr) {
  if (red != nullptr) {
    *red = ADMIN_PIN_RED_YOK;
  }
  if (pin.isEmpty()) {
    gAdminPrefs.remove(ADMIN_PREF_PIN);
    gAdminPin = "";
  } else {
    if (!adminPinBicimGecerli(pin)) {
      if (red != nullptr) {
        *red = ADMIN_PIN_RED_BICIM;
      }
      return false;
    }
    if (adminPinZayifMi(pin)) {
      if (red != nullptr) {
        *red = ADMIN_PIN_RED_ZAYIF;
      }
      return false;
    }
    gAdminPrefs.putString(ADMIN_PREF_PIN, pin);
    gAdminPin = pin;
  }
  gAdminPinHata = 0;
  gAdminKilitAktif = false;
  gAdminPrefs.putUChar(ADMIN_PREF_FAIL, 0);
  return true;
}

// Kilit suresi dolduysa kaldirir (kilitli, bir kez); kalan saniyeyi dondurur (0: kilit yok).
inline uint32_t adminPinKilitKalanSn() {
  if (!gAdminKilitAktif) {
    return 0;
  }
  const uint32_t gecenMs = static_cast<uint32_t>(millis()) - gAdminKilitBaslangicMs;  // ISARETSIZ fark
  if (gecenMs >= ADMIN_PIN_KILIT_MS) {
    gAdminKilitAktif = false;
    gAdminPinHata = ADMIN_PIN_MAX_HATA - 1;  // kilit sonrasi tek deneme hakki
    gAdminPrefs.putUChar(ADMIN_PREF_FAIL, gAdminPinHata);
    return 0;
  }
  const uint32_t kalanMs = ADMIN_PIN_KILIT_MS - gecenMs;
  return (kalanMs + 999) / 1000;
}

// Ana donguden her turda cagrilir: kilit suresi dolunca bayragi (ve "tek hak" durumunu) sorgu beklemeden KILITLI sekilde kapatir;
// boylece uzun suredir kimse sormamis olsa da bayat baslangic damgasi kilidi yeniden "aktif" gosteremez. Kilit yokken yalniz bayrak okur.
inline void adminPinZamanlayici() {
  if (gAdminKilitAktif) {
    adminPinKilitKalanSn();
  }
}

// Durum sorgusu (PIN denemesi yapmaz). kalan: kilitliyse saniye
inline AdminPinSonuc adminPinDurum(uint32_t& kalan) {
  kalan = 0;
  if (!adminPinTanimliMi()) {
    return ADMIN_PIN_TANIMSIZ;
  }
  kalan = adminPinKilitKalanSn();
  return kalan > 0 ? ADMIN_PIN_KILITLI : ADMIN_PIN_OK;
}

// PIN dogrular. Sonuc ADMIN_PIN_YANLIS ise kalan = kalan deneme hakki, KILITLI ise kalan = kilit suresi (sn).
inline AdminPinSonuc adminPinDogrula(const String& pin, uint32_t& kalan) {
  kalan = 0;
  if (!adminPinTanimliMi()) {
    return ADMIN_PIN_TANIMSIZ;
  }
  kalan = adminPinKilitKalanSn();
  if (kalan > 0) {
    return ADMIN_PIN_KILITLI;
  }

  if (adminPinBicimGecerli(pin) && sabitZamanliEsit(pin, gAdminPin)) {
    if (gAdminPinHata != 0) {
      gAdminPinHata = 0;
      gAdminPrefs.putUChar(ADMIN_PREF_FAIL, 0);
    }
    return ADMIN_PIN_OK;
  }

  if (gAdminPinHata < 255) {
    gAdminPinHata += 1;
  }
  gAdminPrefs.putUChar(ADMIN_PREF_FAIL, gAdminPinHata);
  if (gAdminPinHata >= ADMIN_PIN_MAX_HATA) {
    adminPinKilitBaslat();
    kalan = adminPinKilitKalanSn();
    return ADMIN_PIN_KILITLI;
  }
  kalan = ADMIN_PIN_MAX_HATA - gAdminPinHata;
  return ADMIN_PIN_YANLIS;
}

#endif
