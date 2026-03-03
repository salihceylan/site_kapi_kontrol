#ifndef WIFI_BAGLANTI_H
#define WIFI_BAGLANTI_H

#include <WiFi.h>

const char* ssid = "Salih";
const char* password = "Fingon08";

void wifiBaglan() {

  Serial.println("WiFi'ye bağlanılıyor...");
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi bağlı!");
  Serial.print("IP Adresi: ");
  Serial.println(WiFi.localIP());
}

#endif