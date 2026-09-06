#ifndef DEVICE_KONFIG_H
#define DEVICE_KONFIG_H

#include <Arduino.h>

#if defined(BOARD_ESP32_WROOM_RELAY)
constexpr int WIFI_STATUS_LED_PIN = 2;
constexpr bool WIFI_STATUS_LED_ACTIVE_HIGH = true;
constexpr int BLE_STATUS_LED_PIN = -1;
constexpr bool BLE_STATUS_LED_ACTIVE_HIGH = true;
constexpr uint8_t WIFI_RESET_BUTTON_PIN = 0;
constexpr bool WIFI_RESET_BUTTON_ACTIVE_LOW = true;
constexpr unsigned long WIFI_RESET_HOLD_MS = 3000;
constexpr uint16_t YEREL_KAPI_KONTROL_PORT = 8765;

// GM60 Barcode & QR Scanner UART2 Pins
constexpr int GM60_RX_PIN = 16;
constexpr int GM60_TX_PIN = 17;
constexpr uint32_t GM60_BAUD_RATE = 9600;
#else
constexpr int WIFI_STATUS_LED_PIN = 2;
constexpr bool WIFI_STATUS_LED_ACTIVE_HIGH = true;
constexpr int BLE_STATUS_LED_PIN = -1;
constexpr bool BLE_STATUS_LED_ACTIVE_HIGH = true;
constexpr uint8_t WIFI_RESET_BUTTON_PIN = 0;
constexpr bool WIFI_RESET_BUTTON_ACTIVE_LOW = true;
constexpr unsigned long WIFI_RESET_HOLD_MS = 3000;
constexpr uint16_t YEREL_KAPI_KONTROL_PORT = 8765;

// GM60 Pins on C3 (Optional)
constexpr int GM60_RX_PIN = 20;
constexpr int GM60_TX_PIN = 21;
constexpr uint32_t GM60_BAUD_RATE = 9600;
#endif

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
