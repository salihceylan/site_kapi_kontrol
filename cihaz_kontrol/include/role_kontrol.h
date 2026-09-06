#ifndef ROLE_KONTROL_H
#define ROLE_KONTROL_H

#include <Arduino.h>

#if defined(BOARD_ESP32_WROOM_RELAY)
// Standard opto-isolated relay on ESP32-WROOM-32E Relay Module is GPIO 16 (or GPIO 23)
constexpr uint8_t ROLE_PIN = 16;
constexpr unsigned long ROLE_SURE_MS = 1500;
constexpr bool ROLE_ACTIVE_LOW = false;
#else
constexpr uint8_t ROLE_PIN = 10;
constexpr unsigned long ROLE_SURE_MS = 1500;
constexpr bool ROLE_ACTIVE_LOW = false;
#endif

inline unsigned long roleBaslangic = 0;
inline unsigned long roleSonTetikMs = 0;
inline bool roleAktif = false;

inline void rolePinDurumuYazdir(const char* baslik) {
  Serial.print(baslik);
  Serial.print(" GPIO ");
  Serial.print(ROLE_PIN);
  Serial.print(" = ");
  Serial.println(digitalRead(ROLE_PIN) == HIGH ? "HIGH" : "LOW");
}

inline void roleSetup() {
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
  pinMode(ROLE_PIN, OUTPUT);
  Serial.print("Role bos durum GPIO ");
  Serial.print(ROLE_PIN);
  Serial.print(" -> ");
  Serial.println(ROLE_ACTIVE_LOW ? "HIGH" : "LOW");
  rolePinDurumuYazdir("Role setup okuma");
}

inline void roleManuelSeviye(uint8_t level) {
  roleAktif = false;
  digitalWrite(ROLE_PIN, level);
  rolePinDurumuYazdir("Role manuel");
}

inline void roleTetikle() {
  if (roleAktif || (roleSonTetikMs > 0 && millis() - roleSonTetikMs < 2500)) {
    Serial.println("Role debounce: Role zaten aktif veya son tetikten bu yana 2.5s gecmedi.");
    return;
  }
  roleSonTetikMs = millis();
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? LOW : HIGH);
  roleBaslangic = millis();
  roleAktif = true;
  Serial.print("Role tetiklendi GPIO ");
  Serial.print(ROLE_PIN);
  Serial.print(" -> ");
  Serial.println(ROLE_ACTIVE_LOW ? "LOW" : "HIGH");
  rolePinDurumuYazdir("Role tetik okuma");
}

inline bool roleLoop() {
  if (roleAktif && millis() - roleBaslangic >= ROLE_SURE_MS) {
    digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
    roleAktif = false;
    Serial.print("Role birakildi GPIO ");
    Serial.print(ROLE_PIN);
    Serial.print(" -> ");
    Serial.println(ROLE_ACTIVE_LOW ? "HIGH" : "LOW");
    rolePinDurumuYazdir("Role birak okuma");
    return true;
  }

  return false;
}

#endif
