#ifndef DEVICE_KONFIG_H
#define DEVICE_KONFIG_H

#include <Arduino.h>
#include <time.h>

#if defined(BOARD_ESP32_WROOM_RELAY)
// ESP32-WROOM-32E Relay Board (DC 7-60V / Micro USB 5V)
// GPIO16 = Relay (opto-isolated) -- GM60 buraya BAĞLANAMAZ
// GPIO23 = Power / Download Mode durum LED (aktif HIGH)
constexpr int WIFI_STATUS_LED_PIN = 23;
constexpr bool WIFI_STATUS_LED_ACTIVE_HIGH = true;
constexpr int BLE_STATUS_LED_PIN = -1;
constexpr bool BLE_STATUS_LED_ACTIVE_HIGH = true;
constexpr uint8_t WIFI_RESET_BUTTON_PIN = 0;
constexpr bool WIFI_RESET_BUTTON_ACTIVE_LOW = true;
constexpr unsigned long WIFI_RESET_HOLD_MS = 3000;
constexpr uint16_t YEREL_KAPI_KONTROL_PORT = 8765;

// GM60 Barcode & QR Scanner UART2 Pins (Doğrulanmış Sabit Bağlantı: RX2=25, TX2=26)
constexpr int GM60_RX_PIN = 25;
constexpr int GM60_TX_PIN = 26;
constexpr uint32_t GM60_BAUD_RATE = 9600;
#else
// ESP32-C3 Super Mini Board
constexpr int WIFI_STATUS_LED_PIN = 2;
constexpr bool WIFI_STATUS_LED_ACTIVE_HIGH = true;
constexpr int BLE_STATUS_LED_PIN = -1;
constexpr bool BLE_STATUS_LED_ACTIVE_HIGH = true;
constexpr uint8_t WIFI_RESET_BUTTON_PIN = 0;
constexpr bool WIFI_RESET_BUTTON_ACTIVE_LOW = true;
constexpr unsigned long WIFI_RESET_HOLD_MS = 3000;
constexpr uint16_t YEREL_KAPI_KONTROL_PORT = 8765;

// GM60 Pins on C3 (UART1 RX: 20, TX: 21)
inline int GM60_RX_PIN = 20;
inline int GM60_TX_PIN = 21;
inline uint32_t GM60_BAUD_RATE = 9600;
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

// Sistem saati NTP ile senkron mu? (TLS sertifika dogrulamasi, OTA, pulse zaman penceresi buna baglidir)
inline uint32_t epochSimdi() {
  const time_t now = time(nullptr);
  return now > 1600000000 ? static_cast<uint32_t>(now) : 0;
}

inline bool zamanSenkronMu() {
  return epochSimdi() != 0;
}

// Sabit zamanli esitlik: token/PIN karsilastirmalarinda zamanlama sizintisini onler.
inline bool sabitZamanliEsit(const String& a, const String& b) {
  const size_t la = a.length();
  const size_t lb = b.length();
  const size_t n = la > lb ? la : lb;
  uint8_t fark = (la != lb) ? 1 : 0;
  for (size_t i = 0; i < n; i += 1) {
    const uint8_t ca = i < la ? static_cast<uint8_t>(a[i]) : 0;
    const uint8_t cb = i < lb ? static_cast<uint8_t>(b[i]) : 0;
    fark |= static_cast<uint8_t>(ca ^ cb);
  }
  return fark == 0;
}

#endif
