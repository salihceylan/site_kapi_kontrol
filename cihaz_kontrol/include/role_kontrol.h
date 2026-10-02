#ifndef ROLE_KONTROL_H
#define ROLE_KONTROL_H

#include <Arduino.h>
#include <esp_timer.h>

#if defined(BOARD_ESP32_WROOM_RELAY)
// Opto-isolated relay on ESP32-WROOM-32E Relay Module
// GPIO16 = Relay kontrol pini (opto-isolated)
// GPIO23 = Power / Download Mode durum LED
constexpr uint8_t ROLE_PIN = 16;
constexpr unsigned long ROLE_SURE_MS = 1500;
constexpr bool ROLE_ACTIVE_LOW = false;
#else
constexpr uint8_t ROLE_PIN = 10;
constexpr unsigned long ROLE_SURE_MS = 1500;
constexpr bool ROLE_ACTIVE_LOW = false;
#endif

// Manuel tutma (atolye testi, seri 'h'): kapi kilidi sonsuza dek acik kalmasin diye bu sure sonunda OTOMATIK birakilir.
inline constexpr unsigned long ROLE_MANUEL_TUTMA_MS = 60UL * 1000UL;

// Kapi kilit durumu (true = kilitli). Tek tanim burada; mqtt/yerel/ekran moduller kullanir.
inline bool gDoorLocked = true;

inline unsigned long roleBaslangic = 0;
inline unsigned long roleSonTetikMs = 0;
// Aktif kalma suresi: normal pulse ROLE_SURE_MS, manuel tutma ROLE_MANUEL_TUTMA_MS (yedek loop birakmasi bunu kullanir)
inline unsigned long roleAktifSureMs = ROLE_SURE_MS;
// roleAktif / roleBirakildiBildirimi hem loop gorevinden hem esp_timer gorevinden degisir.
inline volatile bool roleAktif = false;
inline volatile bool roleBirakildiBildirimi = false;
inline esp_timer_handle_t roleTimer = nullptr;
inline portMUX_TYPE roleMux = portMUX_INITIALIZER_UNLOCKED;

inline void rolePinDurumuYazdir(const char* baslik) {
  Serial.print(baslik);
  Serial.print(" GPIO ");
  Serial.print(ROLE_PIN);
  Serial.print(" = ");
  Serial.println(digitalRead(ROLE_PIN) == HIGH ? "HIGH" : "LOW");
}

// Role BIRAKMA: loop/Wi-Fi/MQTT/OTA gibi bloklayan islerden bagimsiz olsun diye esp_timer gorevinde
// calisir (loop kilitlense bile role ROLE_SURE_MS sonra birakilir). Serial kullanmaz.
inline void roleBirak() {
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
  portENTER_CRITICAL(&roleMux);
  if (roleAktif) {
    roleAktif = false;
    roleBirakildiBildirimi = true;
  }
  portEXIT_CRITICAL(&roleMux);
}

inline void roleTimerCallback(void*) {
  roleBirak();
}

// setup()'in ILK satiri olmali: pin once pasif seviyeye cekilir, sonra cikis yapilir (acilista role tiklamasin).
inline void roleSetup() {
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
  pinMode(ROLE_PIN, OUTPUT);
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);

  if (roleTimer == nullptr) {
    esp_timer_create_args_t args = {};
    args.callback = &roleTimerCallback;
    args.arg = nullptr;
    args.dispatch_method = ESP_TIMER_TASK;
    args.name = "role_birak";
    if (esp_timer_create(&args, &roleTimer) != ESP_OK) {
      roleTimer = nullptr;  // roleLoop() yedek birakma yolu devrede kalir
    }
  }
}

inline void roleSetupLogYaz() {
  Serial.print("Role bos durum GPIO ");
  Serial.print(ROLE_PIN);
  Serial.print(" -> ");
  Serial.println(ROLE_ACTIVE_LOW ? "HIGH" : "LOW");
  rolePinDurumuYazdir("Role setup okuma");
}

// Atolye testi (seri 'h' / 'l'). Cikti satiri ("Role manuel GPIO <pin> = HIGH|LOW") sirket aracinin ayristirdigi bicimdir.
//  - Aktif seviye ('h'): role ROLE_MANUEL_TUTMA_MS (60 sn) sonra esp_timer ile OTOMATIK birakilir. Tutma sirasinda roleAktif
//    true oldugu icin yeni pulse (roleTetikle) ve OTA baslamaz.
//  - Pasif seviye ('l'): role hemen birakilir (aktifse tamamlanma bildirimi loop'ta yapilir).
inline void roleManuelSeviye(uint8_t level) {
  const uint8_t aktifSeviye = ROLE_ACTIVE_LOW ? LOW : HIGH;
  if (level == aktifSeviye) {
    const unsigned long simdi = millis();
    portENTER_CRITICAL(&roleMux);
    roleAktif = true;
    roleBirakildiBildirimi = false;
    roleSonTetikMs = simdi;
    roleBaslangic = simdi;
    roleAktifSureMs = ROLE_MANUEL_TUTMA_MS;
    portEXIT_CRITICAL(&roleMux);

    digitalWrite(ROLE_PIN, aktifSeviye);
    if (roleTimer != nullptr) {
      esp_timer_stop(roleTimer);  // calismiyorsa hata doner; onemsiz
      if (esp_timer_start_once(roleTimer, static_cast<uint64_t>(ROLE_MANUEL_TUTMA_MS) * 1000ULL) != ESP_OK) {
        Serial.println("Role zamanlayici baslatilamadi; loop tabanli birakma kullanilacak.");
      }
    }
    rolePinDurumuYazdir("Role manuel");
    Serial.print("Role manuel tutma: ");
    Serial.print(ROLE_MANUEL_TUTMA_MS / 1000UL);
    Serial.println(" sn sonra OTOMATIK birakilacak (l ile hemen birakilir).");
  } else {
    if (roleTimer != nullptr) {
      esp_timer_stop(roleTimer);
    }
    roleBirak();
    rolePinDurumuYazdir("Role manuel");
  }
}

// true: role tetiklendi (cagiran yan etkileri - gDoorLocked, event, log, ekran - yalniz bu durumda yapmali)
// false: debounce / zaten aktif (hicbir sey yapilmadi)
inline bool roleTetikle() {
  const unsigned long simdi = millis();
  bool izinli = false;
  portENTER_CRITICAL(&roleMux);
  if (!(roleAktif || (roleSonTetikMs > 0 && simdi - roleSonTetikMs < 2500))) {
    izinli = true;
    roleAktif = true;
    roleBirakildiBildirimi = false;
    roleSonTetikMs = simdi;
    roleBaslangic = simdi;
    roleAktifSureMs = ROLE_SURE_MS;
  }
  portEXIT_CRITICAL(&roleMux);

  if (!izinli) {
    Serial.println("Role debounce: Role zaten aktif veya son tetikten bu yana 2.5s gecmedi.");
    return false;
  }

  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? LOW : HIGH);
  if (roleTimer != nullptr) {
    esp_timer_stop(roleTimer);  // calismiyorsa hata doner; onemsiz
    if (esp_timer_start_once(roleTimer, static_cast<uint64_t>(ROLE_SURE_MS) * 1000ULL) != ESP_OK) {
      Serial.println("Role zamanlayici baslatilamadi; loop tabanli birakma kullanilacak.");
    }
  }
  Serial.print("Role tetiklendi GPIO ");
  Serial.print(ROLE_PIN);
  Serial.print(" -> ");
  Serial.println(ROLE_ACTIVE_LOW ? "LOW" : "HIGH");
  rolePinDurumuYazdir("Role tetik okuma");
  return true;
}

// Her loop turunda cagrilir. true: role BIR KEZ birakildi (cagiran gDoorLocked'i gunceller, ekrani/MQTT'yi bilgilendirir).
inline bool roleLoop() {
  // Yedek yol: esp_timer calismadiysa loop birakir.
  if (roleAktif && millis() - roleBaslangic >= roleAktifSureMs + 50UL) {
    roleBirak();
  }

  bool bildirim = false;
  portENTER_CRITICAL(&roleMux);
  if (roleBirakildiBildirimi) {
    roleBirakildiBildirimi = false;
    bildirim = true;
  }
  portEXIT_CRITICAL(&roleMux);

  if (bildirim) {
    Serial.print("Role birakildi GPIO ");
    Serial.print(ROLE_PIN);
    Serial.print(" -> ");
    Serial.println(ROLE_ACTIVE_LOW ? "HIGH" : "LOW");
    rolePinDurumuYazdir("Role birak okuma");
  }
  return bildirim;
}

#endif
