#ifndef GM60_SCANNER_H
#define GM60_SCANNER_H

#include <Arduino.h>
#include "device_konfig.h"
#include "role_kontrol.h"
#include "qr_dogrulama.h"

#if defined(BOARD_ESP32_WROOM_RELAY)
static HardwareSerial GM60Serial(2);
#else
static HardwareSerial GM60Serial(1);
#endif

inline String gm60Buffer = "";
inline unsigned long gm60SonOkumaMs = 0;
inline bool gm60Aktif = false;

inline void gm60Setup() {
#if defined(BOARD_ESP32_WROOM_RELAY)
  GM60Serial.begin(GM60_BAUD_RATE, SERIAL_8N1, GM60_RX_PIN, GM60_TX_PIN);
  gm60Aktif = true;
  Serial.print("GM60 QR Okuyucu baslatildi (UART2 RX:");
  Serial.print(GM60_RX_PIN);
  Serial.print(", TX:");
  Serial.print(GM60_TX_PIN);
  Serial.println(")");
#elif defined(BOARD_ESP32_C3)
  if (GM60_RX_PIN >= 0 && GM60_TX_PIN >= 0) {
    GM60Serial.begin(GM60_BAUD_RATE, SERIAL_8N1, GM60_RX_PIN, GM60_TX_PIN);
    gm60Aktif = true;
    Serial.println("GM60 QR Okuyucu baslatildi (ESP32-C3 UART1)");
  }
#endif
}

inline void gm60Loop() {
  if (!gm60Aktif) {
    return;
  }

  while (GM60Serial.available() > 0) {
    const char c = static_cast<char>(GM60Serial.read());
    if (c == '\r' || c == '\n') {
      if (gm60Buffer.length() > 0) {
        String qrData = gm60Buffer;
        gm60Buffer = "";
        qrData.trim();

        Serial.print("GM60 QR Okundu: ");
        Serial.println(qrData);

        // Debounce: 2.5 saniye icinde ayni kapiyi tekrar tekrar tetikleme
        if (millis() - gm60SonOkumaMs < 2500) {
          Serial.println("GM60 QR debounce suresi dolmadi, atlaniyor.");
          return;
        }

        String reason;
        if (qrKoduGecerliMi(qrData, reason)) {
          Serial.print("GM60 QR Onaylandi: ");
          Serial.println(reason);
          gm60SonOkumaMs = millis();
          roleTetikle();
        } else {
          Serial.print("GM60 QR Reddedildi: ");
          Serial.println(reason);
        }
      }
    } else {
      if (gm60Buffer.length() < 256) {
        gm60Buffer += c;
      }
    }
  }
}

#endif
