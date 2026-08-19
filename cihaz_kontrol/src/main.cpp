#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

#include "mqtt_baglanti.h"
#include "role_kontrol.h"
#include "wifi_baglanti.h"

WiFiClientSecure espClientSecure;
PubSubClient client(espClientSecure);

constexpr unsigned long STATUS_PRINT_INTERVAL_MS = 5000;
unsigned long sonDurumYazdirmaMs = 0;

void seriDurumYazdir() {
  Serial.println("----- CIHAZ DURUMU -----");
  Serial.print("Cihaz UID: ");
  Serial.println(cihazUniqueId());
  Serial.print("WiFi kayitli: ");
  Serial.println(wifiAktifSsid().isEmpty() ? "hayir" : "evet");
  Serial.print("WiFi SSID: ");
  Serial.println(wifiAktifSsid().isEmpty() ? "-" : wifiAktifSsid());
  Serial.print("WiFi bagli: ");
  Serial.println(wifiHazirMi() ? "evet" : "hayir");
  Serial.print("WiFi IP: ");
  Serial.println(wifiIpAdresi().isEmpty() ? "-" : wifiIpAdresi());
  Serial.print("WiFi gucu: ");
  if (wifiHazirMi()) {
    Serial.print("%");
    Serial.print(wifiSinyalYuzde());
    Serial.print(" (");
    Serial.print(wifiSinyalDbm());
    Serial.println(" dBm)");
  } else {
    Serial.println("-");
  }
  Serial.print("Bluetooth provisioning: ");
  Serial.println(wifiProvisioningAktifMi() ? "acik" : "kapali");
  Serial.print("Bluetooth adi: ");
  Serial.println(wifiProvisioningAktifMi() ? wifiBleDeviceName() : "-");
  Serial.print("WiFi LED GPIO: ");
  Serial.println(WIFI_STATUS_LED_PIN);
  Serial.print("Bluetooth LED GPIO: ");
  Serial.println(BLE_STATUS_LED_PIN);
  Serial.print("MQTT: ");
  Serial.println(client.connected() ? "bagli" : "bagli degil");
  Serial.print("MQTT sunucu: ");
  Serial.print(MQTT_SERVER);
  Serial.print(":");
  Serial.println(MQTT_PORT);
  Serial.print("Role GPIO: ");
  Serial.println(ROLE_PIN);
  Serial.println("------------------------");
}

void setup() {
  Serial.begin(115200);
  delay(300);

  roleSetup();
  wifiBaglan();
  mqttSetup();
}

void loop() {
  wifiLoop();
  mqttLoopHandler();
  if (roleLoop()) {
    mqttNotifyPulseCompleted();
  }

  if (millis() - sonDurumYazdirmaMs >= STATUS_PRINT_INTERVAL_MS) {
    sonDurumYazdirmaMs = millis();
    seriDurumYazdir();
  }
}
