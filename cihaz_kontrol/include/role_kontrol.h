#ifndef ROLE_KONTROL_H
#define ROLE_KONTROL_H

#include <Arduino.h>

constexpr uint8_t ROLE_PIN = 5;
constexpr unsigned long ROLE_SURE_MS = 1500;

inline unsigned long roleBaslangic = 0;
inline bool roleAktif = false;

inline void roleSetup() {
  pinMode(ROLE_PIN, OUTPUT);
  digitalWrite(ROLE_PIN, HIGH);
}

inline void roleTetikle() {
  digitalWrite(ROLE_PIN, LOW);
  roleBaslangic = millis();
  roleAktif = true;
  Serial.println("Role tetiklendi");
}

inline bool roleLoop() {
  if (roleAktif && millis() - roleBaslangic >= ROLE_SURE_MS) {
    digitalWrite(ROLE_PIN, HIGH);
    roleAktif = false;
    Serial.println("Role birakildi");
    return true;
  }

  return false;
}

#endif
