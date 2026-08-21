#ifndef MQTT_BAGLANTI_H
#define MQTT_BAGLANTI_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>

#include "role_kontrol.h"
#include "wifi_baglanti.h"

extern PubSubClient client;
extern WiFiClientSecure espClientSecure;

inline const char* MQTT_SERVER = "mqtt.gudeteknoloji.com.tr";
constexpr uint16_t MQTT_PORT = 8883;
inline const char* MQTT_USER = "esp32_door_01";
inline const char* MQTT_PASS = "Fingon08.";
constexpr bool MQTT_ALLOW_INSECURE_TLS = true;

inline const char* TOPIC_CMD = "site/1/door/1/cmd";
inline const char* TOPIC_STATE = "site/1/door/1/state";
inline const char* TOPIC_EVENT = "site/1/door/1/event";
inline const char* TOPIC_AVAILABILITY = "site/1/door/1/availability";

inline bool gDoorLocked = true;
inline unsigned long gLastMqttReconnectAt = 0;

inline String mqttDeviceTopic(const char* suffix) {
  return "device/" + cihazUniqueId() + "/" + suffix;
}

inline void mqttPublishAvailability(const char* value) {
  client.publish(TOPIC_AVAILABILITY, value, true);
  const String deviceAvailabilityTopic = mqttDeviceTopic("availability");
  client.publish(deviceAvailabilityTopic.c_str(), value, true);
}

inline void mqttPublishState(bool locked) {
  JsonDocument doc;
  doc["locked"] = locked;

  String payload;
  serializeJson(doc, payload);
  client.publish(TOPIC_STATE, payload.c_str(), true);
  const String deviceStateTopic = mqttDeviceTopic("state");
  client.publish(deviceStateTopic.c_str(), payload.c_str(), true);
}

inline void mqttPublishEvent(const char* eventName) {
  JsonDocument doc;
  doc["event"] = eventName;
  doc["ms"] = millis();

  String payload;
  serializeJson(doc, payload);
  client.publish(TOPIC_EVENT, payload.c_str(), false);
  const String deviceEventTopic = mqttDeviceTopic("event");
  client.publish(deviceEventTopic.c_str(), payload.c_str(), false);
}

inline bool shouldTriggerPulse(const String& message) {
  if (message == "pulse" || message == "on" || message == "{\"action\":\"pulse\"}") {
    return true;
  }

  JsonDocument json;
  const auto err = deserializeJson(json, message);
  if (err) {
    return false;
  }

  const char* action = json["action"] | "";
  return String(action) == "pulse";
}

inline void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message;
  message.reserve(length);
  for (unsigned int i = 0; i < length; i++) {
    message += static_cast<char>(payload[i]);
  }

  Serial.print("MQTT Topic: ");
  Serial.println(topic);
  Serial.print("MQTT Mesaj: ");
  Serial.println(message);

  const String deviceCmdTopic = mqttDeviceTopic("cmd");
  if (String(topic) != TOPIC_CMD && String(topic) != deviceCmdTopic) {
    return;
  }

  if (!shouldTriggerPulse(message)) {
    return;
  }

  roleTetikle();
  gDoorLocked = false;
  mqttPublishState(gDoorLocked);
  mqttPublishEvent("pulse_started");
}

inline bool mqttReconnect() {
  if (!wifiHazirMi()) {
    return false;
  }

  if (client.connected()) {
    return true;
  }

  const String clientId = "AHBU-" + cihazUniqueId();
  Serial.print("MQTT baglaniyor...");
  const String deviceAvailabilityTopic = mqttDeviceTopic("availability");

  if (client.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, deviceAvailabilityTopic.c_str(), 1, true, "offline")) {
    Serial.println("baglandi");
    client.subscribe(TOPIC_CMD, 1);
    const String deviceCmdTopic = mqttDeviceTopic("cmd");
    client.subscribe(deviceCmdTopic.c_str(), 1);
    mqttPublishAvailability("online");
    mqttPublishState(gDoorLocked);
    mqttPublishEvent("device_connected");
    return true;
  }

  Serial.print("Hata rc=");
  Serial.print(client.state());
  Serial.println(" tekrar denenecek");
  return false;
}

inline void mqttSetup() {
  // Uretimde MQTT_ALLOW_INSECURE_TLS false yapilip setCACert ile CA dogrulamasi
  // kullanilmalidir. Mevcut saha kurulumlari bozulmasin diye gecici fallback acik.
  if (MQTT_ALLOW_INSECURE_TLS) {
    espClientSecure.setInsecure();
  }
  client.setServer(MQTT_SERVER, MQTT_PORT);
  client.setCallback(mqttCallback);
}

inline void mqttLoopHandler() {
  if (!wifiHazirMi()) {
    if (client.connected()) {
      client.disconnect();
    }
    return;
  }

  if (!client.connected()) {
    if (millis() - gLastMqttReconnectAt < 2000) {
      return;
    }
    gLastMqttReconnectAt = millis();
    const bool connected = mqttReconnect();
    if (!connected) {
      return;
    }
  }

  client.loop();
}

inline void mqttNotifyPulseCompleted() {
  if (!client.connected()) {
    return;
  }

  gDoorLocked = true;
  mqttPublishState(gDoorLocked);
  mqttPublishEvent("pulse_completed");
}

#endif
