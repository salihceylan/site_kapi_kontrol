#ifndef MQTT_BAGLANTI_H
#define MQTT_BAGLANTI_H

#include <PubSubClient.h>
#include "role_kontrol.h"

extern PubSubClient client;

// MQTT Ayarları
const char* mqtt_server = "75.101.239.24";  // VPS IP
const int mqtt_port = 1883;
const char* mqtt_user = "zeynep";
const char* mqtt_pass = "Fingon08.";

void mqttCallback(char* topic, byte* payload, unsigned int length) {

  String mesaj = "";
  for (int i = 0; i < length; i++) {
    mesaj += (char)payload[i];
  }

  Serial.print("MQTT Mesaj: ");
  Serial.println(mesaj);

  if (String(topic) == "esp32/role1") {

    if (mesaj == "on") {
      roleTetikle();  // Donanım katmanına yönlendiriyoruz
    }
  }
}

void mqttReconnect() {

  while (!client.connected()) {

    Serial.print("MQTT bağlanıyor...");

    if (client.connect("ESP32Client", mqtt_user, mqtt_pass)) {

      Serial.println("bağlandı");
      client.subscribe("esp32/role1");

    } else {

      Serial.print("Hata rc=");
      Serial.print(client.state());
      Serial.println(" tekrar deneniyor...");
      delay(2000);
    }
  }
}

void mqttSetup() {
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(mqttCallback);
}

void mqttLoopHandler() {

  if (!client.connected()) {
    mqttReconnect();
  }

  client.loop();
}

#endif