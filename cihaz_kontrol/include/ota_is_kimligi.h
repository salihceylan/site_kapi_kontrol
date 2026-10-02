#ifndef OTA_IS_KIMLIGI_H
#define OTA_IS_KIMLIGI_H

// OTA is kimligi (ota_job_id) yansitma. Sunucu ota_check komutunda `ota_job_id` gonderir (panelden toplu is: pozitif tamsayi; tekil/elle talep:
// null/yok) ve cihazdan gelen OTA olaylarinda ayni `ota_job_id`'yi bekler (server/src/mqtt_bridge.js: recordOtaJobDeviceEvent; kimlik yoksa son
// 6 saatteki is varsayilir). Kimlik YALNIZ RAM'dedir (yeniden baslatmada kaybolur kabul): ota_success olayi yeniden baslatmadan ONCE yayinlanir.
//  - Gecerli kimlik: 1..40 karakterlik metin ([A-Za-z0-9._:-]) ya da pozitif tamsayi. Digerleri (bos, null, sayi disi, ozel karakter, uzun) GECERSIZ
//    sayilir ve onceki kimlik TEMIZLENIR (eski bir isin kimligi sonraki bagimsiz kontrole yapismasin).
//  - Kimlik, adi "ota_" ile baslayan olaylara eklenir; is BITINCE (basari / hata / guncel) temizlenir.
//  - ARDUINO BAGIMSIZ: yalniz ArduinoJson + <string.h>/<stdio.h>; ana makinede (host) aynen derlenip test edilir.

#include <ArduinoJson.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

inline constexpr size_t OTA_IS_KIMLIGI_MAX = 40;
inline char gOtaIsKimligi[OTA_IS_KIMLIGI_MAX + 1] = "";  // bos: kimlik yok
inline bool gOtaIsKimligiSayi = false;                   // true: sunucu tamsayi gonderdi -> olayda da tamsayi olarak yansitilir

inline void otaIsKimligiTemizle() {
  gOtaIsKimligi[0] = '\0';
  gOtaIsKimligiSayi = false;
}

inline bool otaIsKimligiVarMi() {
  return gOtaIsKimligi[0] != '\0';
}

inline bool otaIsKimligiGuvenliKarakter(char c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '.' || c == '_' || c == ':' || c == '-';
}

// ota_check komutundaki `ota_job_id`'yi saklar. true: gecerli kimlik saklandi; false: yok/gecersiz (onceki kimlik temizlendi).
inline bool otaIsKimligiAyarla(JsonVariantConst v) {
  otaIsKimligiTemizle();
  if (v.is<const char*>()) {
    const char* s = v.as<const char*>();
    const size_t n = s != nullptr ? strlen(s) : 0;
    if (n == 0 || n > OTA_IS_KIMLIGI_MAX) {
      return false;
    }
    for (size_t i = 0; i < n; i += 1) {
      if (!otaIsKimligiGuvenliKarakter(s[i])) {
        return false;
      }
    }
    memcpy(gOtaIsKimligi, s, n);
    gOtaIsKimligi[n] = '\0';
    gOtaIsKimligiSayi = false;
    return true;
  }
  if (v.is<int64_t>()) {
    const int64_t x = v.as<int64_t>();
    if (x <= 0) {
      return false;
    }
    snprintf(gOtaIsKimligi, sizeof(gOtaIsKimligi), "%lld", static_cast<long long>(x));
    gOtaIsKimligiSayi = true;
    return true;
  }
  return false;
}

// Bu olay adi is kimligi tasir mi? ("ota_" ile baslayan tum olaylar: ota_check_requested, ota_check_started, ota_update_available, ota_success, ...)
inline bool otaOlayIsKimligiTasirMi(const char* olayAdi) {
  return olayAdi != nullptr && strncmp(olayAdi, "ota_", 4) == 0;
}

// Bu olay OTA kontrol/guncelleme denemesini BITIRIR mi? (sonrasinda kimlik temizlenir)
inline bool otaOlayBitirirMi(const char* olayAdi) {
  if (olayAdi == nullptr) {
    return false;
  }
  return strcmp(olayAdi, "ota_success") == 0 || strcmp(olayAdi, "ota_failed") == 0 || strcmp(olayAdi, "ota_check_failed") == 0 ||
         strcmp(olayAdi, "ota_up_to_date") == 0 || strcmp(olayAdi, "ota_usb_required") == 0 || strcmp(olayAdi, "ota_target_mismatch") == 0;
}

// Kimlik varsa olay JSON'una ekler (`ota_job_id`); yoksa alan EKLENMEZ. Tamsayi gelmisse tamsayi, metin gelmisse metin olarak yansitilir.
inline void otaIsKimligiEkle(JsonDocument& doc) {
  if (!otaIsKimligiVarMi()) {
    return;
  }
  if (gOtaIsKimligiSayi) {
    doc["ota_job_id"] = static_cast<int64_t>(strtoll(gOtaIsKimligi, nullptr, 10));
  } else {
    doc["ota_job_id"] = gOtaIsKimligi;  // char[] -> ArduinoJson dizeyi kopyalar
  }
}

#endif
