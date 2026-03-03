#ifndef WIFI_BAGLANTI_H
#define WIFI_BAGLANTI_H

#include <Arduino.h>
#include <WiFi.h>

inline const char* WIFI_SSID = "Salih";
inline const char* WIFI_PASSWORD = "Fingon08";

inline void wifiBaglan() {
  Serial.println("WiFi'ye baglaniliyor...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }

  Serial.println("\nWiFi bagli!");
  Serial.print("IP Adresi: ");
  Serial.println(WiFi.localIP());
}

#endif
