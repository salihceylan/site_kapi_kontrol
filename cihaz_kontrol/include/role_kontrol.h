#ifndef ROLE_KONTROL_H
#define ROLE_KONTROL_H

#include <Arduino.h>

constexpr uint8_t ROLE_PIN = 10;
constexpr unsigned long ROLE_SURE_MS = 1500;
constexpr bool ROLE_ACTIVE_LOW = false;

inline unsigned long roleBaslangic = 0;
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
