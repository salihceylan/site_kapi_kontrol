#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>

#include "wifi_baglanti.h"
#include "mqtt_baglanti.h"
#include "role_kontrol.h"

WiFiClient espClient;
PubSubClient client(espClient);

void setup() {
  Serial.begin(115200);

  wifiBaglan();
  roleSetup();
  mqttSetup();
}

void loop() {
  mqttLoopHandler();
  roleLoop();
}
