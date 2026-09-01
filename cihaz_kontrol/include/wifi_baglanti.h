#ifndef WIFI_BAGLANTI_H
#define WIFI_BAGLANTI_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <WiFi.h>

#include <algorithm>
#include <vector>

#include "device_konfig.h"

inline constexpr char WIFI_PREFS_NAMESPACE[] = "wifi_cfg";
inline constexpr char WIFI_PREF_SSID[] = "ssid";
inline constexpr char WIFI_PREF_PASSWORD[] = "password";
inline constexpr char WIFI_PREF_MQTT_HOST[] = "mqtt_host";
inline constexpr char WIFI_PREF_MQTT_PORT[] = "mqtt_port";
inline constexpr char WIFI_PREF_MQTT_USER[] = "mqtt_user";
inline constexpr char WIFI_PREF_MQTT_PASSWORD[] = "mqtt_pass";
inline constexpr char WIFI_PREF_LOCAL_CONTROL_TOKEN[] = "local_token";

inline constexpr char BLE_WIFI_SERVICE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f001";
inline constexpr char BLE_WIFI_STATE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f002";
inline constexpr char BLE_WIFI_COMMAND_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f003";
inline constexpr char BLE_WIFI_NETWORKS_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f004";
inline constexpr char BLE_WIFI_RESULT_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f005";

inline constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 15000;
inline constexpr unsigned long WIFI_CONFIGURED_BLINK_INTERVAL_MS = 700;
inline constexpr unsigned long WIFI_UNCONFIGURED_BLINK_INTERVAL_MS = 150;
inline constexpr size_t WIFI_SCAN_RESULT_LIMIT = 8;

inline Preferences gWifiPrefs;
inline String gSavedWifiSsid;
inline String gSavedWifiPassword;
inline String gSavedMqttHost;
inline uint16_t gSavedMqttPort = 0;
inline String gSavedMqttUser;
inline String gSavedMqttPassword;
inline String gSavedLocalControlToken;
inline bool gWifiConfigured = false;
inline bool gWifiConnected = false;
inline bool gProvisioningMode = false;
inline bool gPendingWifiScan = false;
inline bool gPendingWifiProvision = false;
inline String gPendingProvisionSsid;
inline String gPendingProvisionPassword;
inline String gPendingMqttHost;
inline uint16_t gPendingMqttPort = 0;
inline String gPendingMqttUser;
inline String gPendingMqttPassword;
inline String gPendingLocalControlToken;
inline String gBleNetworksPayload = R"({"networks":[]})";
inline String gBleResultPayload = R"({"status":"idle","message":""})";
inline unsigned long gLastWifiAttemptAt = 0;
inline unsigned long gLastLedToggleAt = 0;
inline unsigned long gResetPressedAt = 0;
inline unsigned long gResetLastProgressAt = 0;
inline bool gLedLogicalState = false;
inline bool gResetHandled = false;
inline NimBLEServer* gBleServer = nullptr;
inline NimBLEService* gBleService = nullptr;
inline NimBLEAdvertising* gBleAdvertising = nullptr;
inline NimBLECharacteristic* gBleStateCharacteristic = nullptr;
inline NimBLECharacteristic* gBleNetworksCharacteristic = nullptr;
inline NimBLECharacteristic* gBleResultCharacteristic = nullptr;
inline bool gBleStarted = false;

inline void wifiSetStatusLed(bool on) {
  if (WIFI_STATUS_LED_PIN < 0) {
    return;
  }

  pinMode(WIFI_STATUS_LED_PIN, OUTPUT);
  const uint8_t level = WIFI_STATUS_LED_ACTIVE_HIGH ? (on ? HIGH : LOW) : (on ? LOW : HIGH);
  digitalWrite(WIFI_STATUS_LED_PIN, level);
}

inline void wifiSetBleStatusLed(bool on) {
  if (BLE_STATUS_LED_PIN < 0) {
    return;
  }

  pinMode(BLE_STATUS_LED_PIN, OUTPUT);
  const uint8_t level = BLE_STATUS_LED_ACTIVE_HIGH ? (on ? HIGH : LOW) : (on ? LOW : HIGH);
  digitalWrite(BLE_STATUS_LED_PIN, level);
}

inline bool wifiResetButtonPressed() {
  const int buttonState = digitalRead(WIFI_RESET_BUTTON_PIN);
  return WIFI_RESET_BUTTON_ACTIVE_LOW ? buttonState == LOW : buttonState == HIGH;
}

inline void wifiLoadStoredCredentials() {
  gSavedWifiSsid = gWifiPrefs.getString(WIFI_PREF_SSID, "");
  gSavedWifiPassword = gWifiPrefs.getString(WIFI_PREF_PASSWORD, "");
  gSavedMqttHost = gWifiPrefs.getString(WIFI_PREF_MQTT_HOST, "");
  gSavedMqttPort = static_cast<uint16_t>(gWifiPrefs.getUInt(WIFI_PREF_MQTT_PORT, 0));
  gSavedMqttUser = gWifiPrefs.getString(WIFI_PREF_MQTT_USER, "");
  gSavedMqttPassword = gWifiPrefs.getString(WIFI_PREF_MQTT_PASSWORD, "");
  gSavedLocalControlToken = gWifiPrefs.getString(WIFI_PREF_LOCAL_CONTROL_TOKEN, "");
  gWifiConfigured = !gSavedWifiSsid.isEmpty();
}

inline void wifiPersistCredentials(const String& ssid, const String& password) {
  gWifiPrefs.putString(WIFI_PREF_SSID, ssid);
  gWifiPrefs.putString(WIFI_PREF_PASSWORD, password);
  gSavedWifiSsid = ssid;
  gSavedWifiPassword = password;
  gWifiConfigured = !gSavedWifiSsid.isEmpty();
}

inline void wifiPersistMqttCredentials(
  const String& host,
  uint16_t port,
  const String& username,
  const String& password,
  const String& localControlToken = ""
) {
  if (host.isEmpty() || port == 0 || username.isEmpty() || password.isEmpty()) {
    return;
  }

  gWifiPrefs.putString(WIFI_PREF_MQTT_HOST, host);
  gWifiPrefs.putUInt(WIFI_PREF_MQTT_PORT, port);
  gWifiPrefs.putString(WIFI_PREF_MQTT_USER, username);
  gWifiPrefs.putString(WIFI_PREF_MQTT_PASSWORD, password);
  gSavedMqttHost = host;
  gSavedMqttPort = port;
  gSavedMqttUser = username;
  gSavedMqttPassword = password;
  if (!localControlToken.isEmpty()) {
    gWifiPrefs.putString(WIFI_PREF_LOCAL_CONTROL_TOKEN, localControlToken);
    gSavedLocalControlToken = localControlToken;
  }
}

inline void wifiForgetCredentials() {
  gWifiPrefs.remove(WIFI_PREF_SSID);
  gWifiPrefs.remove(WIFI_PREF_PASSWORD);
  gSavedWifiSsid.clear();
  gSavedWifiPassword.clear();
  gWifiConfigured = false;
}

inline bool wifiHasMqttCredentials() {
  return !gSavedMqttUser.isEmpty() && !gSavedMqttPassword.isEmpty();
}

inline String wifiMqttHost(const char* fallback) {
  return gSavedMqttHost.isEmpty() ? String(fallback) : gSavedMqttHost;
}

inline uint16_t wifiMqttPort(uint16_t fallback) {
  return gSavedMqttPort == 0 ? fallback : gSavedMqttPort;
}

inline String wifiMqttUser(const char* fallback) {
  return gSavedMqttUser.isEmpty() ? String(fallback) : gSavedMqttUser;
}

inline String wifiMqttPassword(const char* fallback) {
  return gSavedMqttPassword.isEmpty() ? String(fallback) : gSavedMqttPassword;
}

inline bool wifiHasLocalControlToken() {
  return !gSavedLocalControlToken.isEmpty();
}

inline String wifiLocalControlToken() {
  return gSavedLocalControlToken;
}

inline void wifiPersistLocalControlToken(const String& token) {
  if (token.isEmpty()) {
    return;
  }

  gWifiPrefs.putString(WIFI_PREF_LOCAL_CONTROL_TOKEN, token);
  gSavedLocalControlToken = token;
}

inline String wifiBuildStatePayload() {
  JsonDocument doc;
  doc["device_uid"] = cihazUniqueId();
  doc["wifi_connected"] = gWifiConnected;
  doc["provisioning"] = gProvisioningMode;
  doc["has_credentials"] = gWifiConfigured;
  doc["mqtt_configured"] = wifiHasMqttCredentials();
  doc["ssid"] = gWifiConnected ? WiFi.SSID() : gSavedWifiSsid;
  doc["ip"] = gWifiConnected ? WiFi.localIP().toString() : "";

  String payload;
  serializeJson(doc, payload);
  return payload;
}

inline void wifiNotifyBleState() {
  if (gBleStateCharacteristic == nullptr) {
    return;
  }

  const String payload = wifiBuildStatePayload();
  gBleStateCharacteristic->setValue(payload.c_str());
  gBleStateCharacteristic->notify();
}

inline void wifiNotifyBleResult(const String& status, const String& message = "") {
  JsonDocument doc;
  doc["status"] = status;
  doc["message"] = message;
  serializeJson(doc, gBleResultPayload);

  if (gBleResultCharacteristic == nullptr) {
    return;
  }

  gBleResultCharacteristic->setValue(gBleResultPayload.c_str());
  gBleResultCharacteristic->notify();
}

inline void wifiUpdateLed() {
  if (gWifiConnected) {
    wifiSetStatusLed(true);
    return;
  }

  const unsigned long blinkInterval = gWifiConfigured
    ? WIFI_CONFIGURED_BLINK_INTERVAL_MS
    : WIFI_UNCONFIGURED_BLINK_INTERVAL_MS;

  if (millis() - gLastLedToggleAt < blinkInterval) {
    return;
  }

  gLastLedToggleAt = millis();
  gLedLogicalState = !gLedLogicalState;
  wifiSetStatusLed(gLedLogicalState);
}

inline bool wifiTryConnect(const String& ssid, const String& password, unsigned long timeoutMs = 15000) {
  Serial.printf("WiFi baglantisi deneniyor: %s\n", ssid.c_str());
  gLastWifiAttemptAt = millis();
  WiFi.mode(WIFI_STA);
  delay(100);
  WiFi.begin(ssid.c_str(), password.c_str());
  const unsigned long startedAt = millis();
  while (millis() - startedAt < timeoutMs) {
    esp_task_wdt_reset();
    roleLoop();
    if (WiFi.status() == WL_CONNECTED) {
      Serial.print("WiFi baglandi, IP: ");
      Serial.println(WiFi.localIP());
      wifiNotifyBleState();
      return true;
    }

    wifiUpdateLed();
    delay(100);
  }

  Serial.println("WiFi baglantisi basarisiz.");
  wifiNotifyBleState();
  return false;
}

struct WifiNetworkInfo {
  String ssid;
  int32_t rssi;
  bool secure;
};

inline void wifiPerformScan() {
  wifiNotifyBleResult("scanning", "Yakin WiFi aglari taraniyor.");

  WiFi.disconnect(false, false);
  WiFi.mode(WIFI_STA);
  delay(150);

  int16_t count = WiFi.scanNetworks(false, false);
  if (count < 0) {
    WiFi.disconnect(true, false);
    delay(100);
    WiFi.mode(WIFI_STA);
    delay(200);
    count = WiFi.scanNetworks(false, false);
  }

  std::vector<WifiNetworkInfo> networks;
  if (count > 0) {
    for (int16_t index = 0; index < count; index += 1) {
      const String ssid = WiFi.SSID(index);
      if (ssid.isEmpty()) {
        continue;
      }

      const bool exists = std::any_of(
        networks.begin(),
        networks.end(),
        [&ssid](const WifiNetworkInfo& info) {
          return info.ssid == ssid;
        }
      );
      if (exists) {
        continue;
      }

      networks.push_back({
        .ssid = ssid,
        .rssi = WiFi.RSSI(index),
        .secure = WiFi.encryptionType(index) != WIFI_AUTH_OPEN,
      });
    }
  }

  WiFi.scanDelete();
  std::sort(
    networks.begin(),
    networks.end(),
    [](const WifiNetworkInfo& left, const WifiNetworkInfo& right) {
      return left.rssi > right.rssi;
    }
  );

  JsonDocument doc;
  JsonArray list = doc["networks"].to<JsonArray>();
  const size_t limit = std::min(WIFI_SCAN_RESULT_LIMIT, networks.size());
  for (size_t index = 0; index < limit; index += 1) {
    JsonObject item = list.add<JsonObject>();
    item["ssid"] = networks[index].ssid;
    item["rssi"] = networks[index].rssi;
    item["secure"] = networks[index].secure;
  }

  gBleNetworksPayload = "";
  serializeJson(doc, gBleNetworksPayload);
  if (gBleNetworksCharacteristic != nullptr) {
    gBleNetworksCharacteristic->setValue(gBleNetworksPayload.c_str());
    gBleNetworksCharacteristic->notify();
  }
  wifiNotifyBleResult("scan_complete", String(networks.size()) + " WiFi agi bulundu.");
}

inline String wifiBleDeviceName() {
  return "AHBU" + cihazUniqueId();
}

inline void wifiStopProvisioningMode();
inline void wifiStartProvisioningMode();

inline void wifiApplyProvisioningRequest() {
  gPendingWifiProvision = false;
  const String ssid = gPendingProvisionSsid;
  const String password = gPendingProvisionPassword;
  const String mqttHost = gPendingMqttHost;
  const uint16_t mqttPort = gPendingMqttPort;
  const String mqttUser = gPendingMqttUser;
  const String mqttPassword = gPendingMqttPassword;
  const String localControlToken = gPendingLocalControlToken;

  if (ssid.isEmpty()) {
    wifiNotifyBleResult("error", "SSID zorunlu.");
    return;
  }

  wifiPersistCredentials(ssid, password);
  wifiPersistMqttCredentials(mqttHost, mqttPort, mqttUser, mqttPassword, localControlToken);
  wifiNotifyBleResult("restarting", "WiFi ve MQTT bilgileri kaydedildi. Cihaz temiz baglanti icin yeniden baslatiliyor.");
  wifiNotifyBleState();
  delay(1500);
  ESP.restart();
}

class WifiProvisionCommandCallbacks : public NimBLECharacteristicCallbacks {
 public:
  void onWrite(NimBLECharacteristic* characteristic) override {
    const std::string value = characteristic->getValue();
    if (value.empty()) {
      return;
    }

    const String message(value.c_str());
    JsonDocument doc;
    const DeserializationError error = deserializeJson(doc, message);
    if (error) {
      if (message.equalsIgnoreCase("scan")) {
        gPendingWifiScan = true;
      } else {
        wifiNotifyBleResult("error", "BLE komutu okunamadi.");
      }
      return;
    }

    const String action = String(doc["action"] | "");
    if (action == "scan") {
      gPendingWifiScan = true;
      return;
    }

    const String ssid = String(doc["ssid"] | "");
    const String password = String(doc["password"] | "");
    const String mqttHost = String(doc["mqtt_host"] | "");
    const uint16_t mqttPort = static_cast<uint16_t>(doc["mqtt_port"] | 0);
    const String mqttUser = String(doc["mqtt_username"] | "");
    const String mqttPassword = String(doc["mqtt_password"] | "");
    const String localControlToken = String(doc["local_control_token"] | "");
    if (ssid.isEmpty()) {
      wifiNotifyBleResult("error", "SSID bilgisi eksik.");
      return;
    }
    if (
      mqttHost.isEmpty() ||
      mqttPort == 0 ||
      mqttUser.isEmpty() ||
      mqttPassword.isEmpty()
    ) {
      wifiNotifyBleResult("error", "MQTT cihaz kimligi eksik. Once cihazi sirket hesabina kaydedin.");
      return;
    }

    gPendingProvisionSsid = ssid;
    gPendingProvisionPassword = password;
    gPendingMqttHost = mqttHost;
    gPendingMqttPort = mqttPort;
    gPendingMqttUser = mqttUser;
    gPendingMqttPassword = mqttPassword;
    gPendingLocalControlToken = localControlToken;
    gPendingWifiProvision = true;
  }
};

inline void wifiStartProvisioningMode() {
  gProvisioningMode = true;
  wifiSetBleStatusLed(true);
  if (gBleStarted) {
    wifiNotifyBleState();
    return;
  }

  const String bleName = wifiBleDeviceName();
  NimBLEDevice::init(bleName.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  gBleServer = NimBLEDevice::createServer();
  gBleService = gBleServer->createService(BLE_WIFI_SERVICE_UUID);

  gBleStateCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_STATE_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  gBleNetworksCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_NETWORKS_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  gBleResultCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_RESULT_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  NimBLECharacteristic* commandCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_COMMAND_UUID,
    NIMBLE_PROPERTY::WRITE
  );
  commandCharacteristic->setCallbacks(new WifiProvisionCommandCallbacks());

  gBleService->start();
  gBleAdvertising = NimBLEDevice::getAdvertising();
  gBleAdvertising->addServiceUUID(BLE_WIFI_SERVICE_UUID);
  gBleAdvertising->setScanResponse(true);
  gBleAdvertising->start();
  gBleStarted = true;

  gBleNetworksPayload = R"({"networks":[]})";
  gBleNetworksCharacteristic->setValue(gBleNetworksPayload.c_str());
  wifiNotifyBleResult("ready", "Bluetooth provisioning hazir.");
  wifiNotifyBleState();
  Serial.printf("BLE WiFi provisioning aktif: %s\n", bleName.c_str());
}

inline void wifiStopProvisioningMode() {
  if (!gBleStarted) {
    gProvisioningMode = false;
    wifiSetBleStatusLed(false);
    return;
  }

  if (gBleAdvertising != nullptr) {
    gBleAdvertising->stop();
  }
  NimBLEDevice::deinit(true);
  gBleAdvertising = nullptr;
  gBleService = nullptr;
  gBleServer = nullptr;
  gBleStateCharacteristic = nullptr;
  gBleNetworksCharacteristic = nullptr;
  gBleResultCharacteristic = nullptr;
  gBleStarted = false;
  gProvisioningMode = false;
  wifiSetBleStatusLed(false);
  Serial.println("BLE WiFi provisioning kapatildi.");
}

inline void wifiHandleResetButton() {
  const bool pressed = wifiResetButtonPressed();
  if (!pressed) {
    if (gResetPressedAt != 0 && !gResetHandled) {
      Serial.println("WiFi reset butonu birakildi, sifirlama iptal.");
    }
    gResetPressedAt = 0;
    gResetLastProgressAt = 0;
    gResetHandled = false;
    return;
  }

  if (gResetPressedAt == 0) {
    gResetPressedAt = millis();
    gResetLastProgressAt = gResetPressedAt;
    Serial.println("WiFi reset butonu algilandi. Sifirlama icin 3 saniye basili tutun.");
    return;
  }

  if (gResetHandled) {
    return;
  }

  const unsigned long heldMs = millis() - gResetPressedAt;
  if (heldMs < WIFI_RESET_HOLD_MS) {
    if (millis() - gResetLastProgressAt >= 1000) {
      gResetLastProgressAt = millis();
      Serial.print("WiFi reset basili: ");
      Serial.print(heldMs / 1000);
      Serial.println(" sn");
    }
    return;
  }

  gResetHandled = true;
  Serial.println("WiFi ayarlari sifirlaniyor...");
  wifiForgetCredentials();
  WiFi.disconnect(true, true);
  delay(200);
  ESP.restart();
}

inline void wifiBaglan() {
  if (WIFI_STATUS_LED_PIN >= 0) {
    pinMode(WIFI_STATUS_LED_PIN, OUTPUT);
  }
  if (BLE_STATUS_LED_PIN >= 0) {
    pinMode(BLE_STATUS_LED_PIN, OUTPUT);
  }
  pinMode(WIFI_RESET_BUTTON_PIN, WIFI_RESET_BUTTON_ACTIVE_LOW ? INPUT_PULLUP : INPUT);
  wifiSetStatusLed(false);
  wifiSetBleStatusLed(false);

  gWifiPrefs.begin(WIFI_PREFS_NAMESPACE, false);
  wifiLoadStoredCredentials();
  gWifiConnected = false;
  gLastWifiAttemptAt = 0;

  if (!gWifiConfigured) {
    Serial.println("Kayitli WiFi yok, BLE provisioning baslatiliyor.");
    WiFi.mode(WIFI_OFF);
    delay(150);
    wifiStartProvisioningMode();
    return;
  }

  if (!wifiHasMqttCredentials()) {
    Serial.println("Kayitli WiFi var ama MQTT kimligi yok, BLE provisioning baslatiliyor.");
    WiFi.disconnect(true, false);
    WiFi.mode(WIFI_OFF);
    delay(150);
    wifiStartProvisioningMode();
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(false);

  Serial.printf("Kayitli WiFi bulundu: %s\n", gSavedWifiSsid.c_str());
  if (wifiTryConnect(gSavedWifiSsid, gSavedWifiPassword, 20000)) {
    wifiStopProvisioningMode();
    return;
  }

  Serial.println("Kayitli WiFi'ye baglanamadi, BLE provisioning baslatiliyor.");
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_OFF);
  delay(150);
  wifiStartProvisioningMode();
}

inline void wifiLoop() {
  wifiHandleResetButton();
  gWifiConnected = WiFi.status() == WL_CONNECTED;

  if (gPendingWifiScan) {
    gPendingWifiScan = false;
    wifiPerformScan();
  }

  if (gPendingWifiProvision) {
    wifiApplyProvisioningRequest();
  }

  if (gWifiConnected && wifiHasMqttCredentials()) {
    wifiStopProvisioningMode();
  } else if (gProvisioningMode) {
    wifiUpdateLed();
    return;
  } else if (!gWifiConfigured) {
    wifiStartProvisioningMode();
  } else if (!wifiHasMqttCredentials()) {
    if (WiFi.getMode() != WIFI_OFF) {
      WiFi.disconnect(true, false);
      WiFi.mode(WIFI_OFF);
      delay(50);
    }
    wifiStartProvisioningMode();
  } else if (millis() - gLastWifiAttemptAt >= WIFI_RETRY_INTERVAL_MS) {
    gLastWifiAttemptAt = millis();
    Serial.println("WiFi baglantisi koptu; arka planda yeniden baglaniliyor...");
    WiFi.disconnect(false, false);
    WiFi.begin(gSavedWifiSsid.c_str(), gSavedWifiPassword.c_str());
  }

  wifiUpdateLed();
}

inline bool wifiHazirMi() {
  return gWifiConnected;
}

inline bool wifiProvisioningAktifMi() {
  return gProvisioningMode;
}

inline String wifiAktifSsid() {
  return gWifiConnected ? WiFi.SSID() : gSavedWifiSsid;
}

inline String wifiIpAdresi() {
  return gWifiConnected ? WiFi.localIP().toString() : "";
}

inline int wifiSinyalDbm() {
  return gWifiConnected ? WiFi.RSSI() : 0;
}

inline int wifiSinyalYuzde() {
  if (!gWifiConnected) {
    return 0;
  }

  const int rssi = WiFi.RSSI();
  if (rssi <= -100) {
    return 0;
  }
  if (rssi >= -50) {
    return 100;
  }
  return 2 * (rssi + 100);
}

#endif
