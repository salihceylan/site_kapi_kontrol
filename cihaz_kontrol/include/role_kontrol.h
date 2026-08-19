#ifndef ROLE_KONTROL_H
#define ROLE_KONTROL_H

#include <Arduino.h>

constexpr uint8_t ROLE_PIN = 10;
constexpr unsigned long ROLE_SURE_MS = 1500;
constexpr bool ROLE_ACTIVE_LOW = true;

inline unsigned long roleBaslangic = 0;
inline bool roleAktif = false;

inline void roleSetup() {
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
  pinMode(ROLE_PIN, OUTPUT);
}

inline void roleTetikle() {
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? LOW : HIGH);
  roleBaslangic = millis();
  roleAktif = true;
  Serial.println("Role tetiklendi");
}

inline bool roleLoop() {
  if (roleAktif && millis() - roleBaslangic >= ROLE_SURE_MS) {
    digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
    roleAktif = false;
    Serial.println("Role birakildi");
    return true;
  }

  return false;
}

#endif
