#ifndef MQTT_BAGLANTI_H
#define MQTT_BAGLANTI_H

#include <Arduino.h>
#include <PubSubClient.h>

#include "role_kontrol.h"

extern PubSubClient client;

inline const char* MQTT_SERVER = "75.101.239.24";
constexpr uint16_t MQTT_PORT = 1883;
inline const char* MQTT_USER = "zeynep";
inline const char* MQTT_PASS = "Fingon08.";
inline const char* ROLE_TOPIC = "esp32/role1";

inline void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String mesaj;
  mesaj.reserve(length);

  for (unsigned int i = 0; i < length; i++) {
    mesaj += static_cast<char>(payload[i]);
  }

  Serial.print("MQTT Mesaj: ");
  Serial.println(mesaj);

  if (String(topic) == ROLE_TOPIC && mesaj == "on") {
    roleTetikle();
  }
}

inline bool mqttReconnect() {
  if (client.connected()) {
    return true;
  }

  const String clientId = "ESP32S3-" + String(static_cast<uint32_t>(ESP.getEfuseMac()), HEX);
  Serial.print("MQTT baglaniyor...");

  if (client.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
    Serial.println("baglandi");
    client.subscribe(ROLE_TOPIC);
    return true;
  }

  Serial.print("Hata rc=");
  Serial.print(client.state());
  Serial.println(" tekrar denenecek");
  return false;
}

inline void mqttSetup() {
  client.setServer(MQTT_SERVER, MQTT_PORT);
  client.setCallback(mqttCallback);
}

inline void mqttLoopHandler() {
  if (!client.connected()) {
    const bool connected = mqttReconnect();
    if (!connected) {
      delay(2000);
      return;
    }
  }

  client.loop();
}

#endif
