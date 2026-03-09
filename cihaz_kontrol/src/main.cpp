#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

#include "mqtt_baglanti.h"
#include "role_kontrol.h"
#include "wifi_baglanti.h"

WiFiClientSecure espClientSecure;
PubSubClient client(espClientSecure);

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
}
