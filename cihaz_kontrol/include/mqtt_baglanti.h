#ifndef MQTT_BAGLANTI_H
#define MQTT_BAGLANTI_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>

#include "role_kontrol.h"
#include "ota_guncelleme.h"
#include "tls_kok_sertifika.h"
#include "wifi_baglanti.h"

extern PubSubClient client;
extern WiFiClientSecure espClientSecure;

inline const char* MQTT_DEFAULT_SERVER = "mqtt.gudeteknoloji.com.tr";
constexpr uint16_t MQTT_DEFAULT_PORT = 8883;
inline const char* MQTT_DEFAULT_USER = "";
inline const char* MQTT_DEFAULT_PASS = "";

inline bool gDoorLocked = true;
inline unsigned long gLastMqttReconnectAt = 0;
inline String gMqttConfiguredHost = MQTT_DEFAULT_SERVER;
inline uint16_t gMqttConfiguredPort = MQTT_DEFAULT_PORT;

inline String mqttDeviceTopic(const char* suffix) {
  return "device/" + cihazUniqueId() + "/" + suffix;
}

inline void mqttPublishAvailability(const char* value) {
  const String deviceAvailabilityTopic = mqttDeviceTopic("availability");
  client.publish(deviceAvailabilityTopic.c_str(), value, true);
}

inline void mqttPublishState(bool locked) {
  JsonDocument doc;
  doc["locked"] = locked;
  doc["firmware_version"] = OTA_CURRENT_VERSION;
  doc["ota_status"] = otaLastStatus();
  doc["ota_last_version"] = otaLastVersion();
  doc["wifi_rssi"] = wifiSinyalDbm();
  doc["wifi_signal_percent"] = wifiSinyalYuzde();
  doc["local_ip"] = wifiIpAdresi();
  doc["local_control_port"] = YEREL_KAPI_KONTROL_PORT;
  doc["local_control_available"] = wifiHasLocalControlToken();

  String payload;
  serializeJson(doc, payload);
  const String deviceStateTopic = mqttDeviceTopic("state");
  client.publish(deviceStateTopic.c_str(), payload.c_str(), true);
}

inline void mqttPublishEvent(const char* eventName, const char* detail = "") {
  JsonDocument doc;
  doc["event"] = eventName;
  if (detail != nullptr && detail[0] != '\0') {
    doc["detail"] = detail;
  }
  doc["ms"] = millis();
  doc["firmware_version"] = OTA_CURRENT_VERSION;
  doc["ota_status"] = otaLastStatus();

  String payload;
  serializeJson(doc, payload);
  const String deviceEventTopic = mqttDeviceTopic("event");
  client.publish(deviceEventTopic.c_str(), payload.c_str(), false);
}

inline void mqttPublishOtaEvent(const char* eventName, const char* detail) {
  if (!client.connected()) {
    return;
  }
  mqttPublishEvent(eventName, detail);
  mqttPublishState(gDoorLocked);
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

inline bool shouldTriggerOtaCheck(const String& message) {
  if (message == "ota" || message == "ota_check") {
    return true;
  }

  JsonDocument json;
  const auto err = deserializeJson(json, message);
  if (err) {
    return false;
  }

  const char* action = json["action"] | "";
  return String(action) == "ota_check";
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
  if (String(topic) != deviceCmdTopic) {
    return;
  }

  if (shouldTriggerOtaCheck(message)) {
    otaTalepEt("mqtt");
    mqttPublishEvent("ota_check_requested");
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
  if (!wifiHasMqttCredentials()) {
    Serial.println("MQTT kimligi yok; BLE provisioning ile cihaz kimligi yazilmali.");
    return false;
  }

  const String clientId = "AHBU-" + cihazUniqueId();
  Serial.print("MQTT baglaniyor...");
  const String deviceAvailabilityTopic = mqttDeviceTopic("availability");
  const String mqttUser = wifiMqttUser(MQTT_DEFAULT_USER);
  const String mqttPass = wifiMqttPassword(MQTT_DEFAULT_PASS);

  if (client.connect(clientId.c_str(), mqttUser.c_str(), mqttPass.c_str(), deviceAvailabilityTopic.c_str(), 1, true, "offline")) {
    Serial.println("baglandi");
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
  espClientSecure.setCACert(TLS_ROOT_CA);
  espClientSecure.setTimeout(2);
  gMqttConfiguredHost = wifiMqttHost(MQTT_DEFAULT_SERVER);
  gMqttConfiguredPort = wifiMqttPort(MQTT_DEFAULT_PORT);
  client.setServer(gMqttConfiguredHost.c_str(), gMqttConfiguredPort);
  client.setCallback(mqttCallback);
  client.setSocketTimeout(2);
  client.setKeepAlive(10);
  otaSetEventPublisher(mqttPublishOtaEvent);
}

inline String mqttAktifSunucu() {
  return gMqttConfiguredHost;
}

inline uint16_t mqttAktifPort() {
  return gMqttConfiguredPort;
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
