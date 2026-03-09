#ifndef DEVICE_KONFIG_H
#define DEVICE_KONFIG_H

#include <Arduino.h>

#ifdef LED_BUILTIN
constexpr uint8_t WIFI_STATUS_LED_PIN = LED_BUILTIN;
#else
constexpr uint8_t WIFI_STATUS_LED_PIN = 2;
#endif

constexpr bool WIFI_STATUS_LED_ACTIVE_HIGH = true;
constexpr uint8_t WIFI_RESET_BUTTON_PIN = 0;
constexpr bool WIFI_RESET_BUTTON_ACTIVE_LOW = true;
constexpr unsigned long WIFI_RESET_HOLD_MS = 3000;

inline String cihazUniqueId() {
  const uint64_t chipId = ESP.getEfuseMac();
  char buffer[17];
  snprintf(
    buffer,
    sizeof(buffer),
    "%04X%08X",
    static_cast<uint16_t>(chipId >> 32),
    static_cast<uint32_t>(chipId)
  );
  return String(buffer);
}

#endif
