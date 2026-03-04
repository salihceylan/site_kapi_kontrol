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

  wifiBaglan();
  roleSetup();
  mqttSetup();
}

void loop() {
  mqttLoopHandler();
  if (roleLoop()) {
    mqttNotifyPulseCompleted();
  }
}
