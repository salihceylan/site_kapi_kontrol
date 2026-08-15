#ifndef WIFI_BAGLANTI_H
#define WIFI_BAGLANTI_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <Preferences.h>
#include <WiFi.h>

#include <algorithm>
#include <vector>

#include "device_konfig.h"

inline constexpr char WIFI_PREFS_NAMESPACE[] = "wifi_cfg";
inline constexpr char WIFI_PREF_SSID[] = "ssid";
inline constexpr char WIFI_PREF_PASSWORD[] = "password";

inline constexpr char BLE_WIFI_SERVICE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f001";
inline constexpr char BLE_WIFI_STATE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f002";
inline constexpr char BLE_WIFI_COMMAND_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f003";
inline constexpr char BLE_WIFI_NETWORKS_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f004";
inline constexpr char BLE_WIFI_RESULT_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f005";

inline constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 15000;
inline constexpr unsigned long WIFI_BLINK_INTERVAL_MS = 400;
inline constexpr size_t WIFI_SCAN_RESULT_LIMIT = 8;

inline Preferences gWifiPrefs;
inline String gSavedWifiSsid;
inline String gSavedWifiPassword;
inline bool gWifiConfigured = false;
inline bool gWifiConnected = false;
inline bool gProvisioningMode = false;
inline bool gPendingWifiScan = false;
inline bool gPendingWifiProvision = false;
inline String gPendingProvisionSsid;
inline String gPendingProvisionPassword;
inline String gBleNetworksPayload = R"({"networks":[]})";
inline String gBleResultPayload = R"({"status":"idle","message":""})";
inline unsigned long gLastWifiAttemptAt = 0;
inline unsigned long gLastLedToggleAt = 0;
inline unsigned long gResetPressedAt = 0;
inline bool gLedLogicalState = false;
inline bool gResetHandled = false;
inline BLEServer* gBleServer = nullptr;
inline BLEService* gBleService = nullptr;
inline BLEAdvertising* gBleAdvertising = nullptr;
inline BLECharacteristic* gBleStateCharacteristic = nullptr;
inline BLECharacteristic* gBleNetworksCharacteristic = nullptr;
inline BLECharacteristic* gBleResultCharacteristic = nullptr;
inline bool gBleStarted = false;

inline void wifiSetStatusLed(bool on) {
  const uint8_t level = WIFI_STATUS_LED_ACTIVE_HIGH ? (on ? HIGH : LOW) : (on ? LOW : HIGH);
  digitalWrite(WIFI_STATUS_LED_PIN, level);
}

inline bool wifiResetButtonPressed() {
  const int buttonState = digitalRead(WIFI_RESET_BUTTON_PIN);
  return WIFI_RESET_BUTTON_ACTIVE_LOW ? buttonState == LOW : buttonState == HIGH;
}

inline void wifiLoadStoredCredentials() {
  gSavedWifiSsid = gWifiPrefs.getString(WIFI_PREF_SSID, "");
  gSavedWifiPassword = gWifiPrefs.getString(WIFI_PREF_PASSWORD, "");
  gWifiConfigured = !gSavedWifiSsid.isEmpty();
}

inline void wifiPersistCredentials(const String& ssid, const String& password) {
  gWifiPrefs.putString(WIFI_PREF_SSID, ssid);
  gWifiPrefs.putString(WIFI_PREF_PASSWORD, password);
  gSavedWifiSsid = ssid;
  gSavedWifiPassword = password;
  gWifiConfigured = !gSavedWifiSsid.isEmpty();
}

inline void wifiForgetCredentials() {
  gWifiPrefs.remove(WIFI_PREF_SSID);
  gWifiPrefs.remove(WIFI_PREF_PASSWORD);
  gSavedWifiSsid.clear();
  gSavedWifiPassword.clear();
  gWifiConfigured = false;
}

inline String wifiBuildStatePayload() {
  JsonDocument doc;
  doc["device_uid"] = cihazUniqueId();
  doc["wifi_connected"] = gWifiConnected;
  doc["provisioning"] = gProvisioningMode;
  doc["has_credentials"] = gWifiConfigured;
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

  if (millis() - gLastLedToggleAt < WIFI_BLINK_INTERVAL_MS) {
    return;
  }

  gLastLedToggleAt = millis();
  gLedLogicalState = !gLedLogicalState;
  wifiSetStatusLed(gLedLogicalState);
}

inline bool wifiTryConnect(const String& ssid, const String& password, unsigned long timeoutMs = 15000) {
  Serial.printf("WiFi baglantisi deneniyor: %s\n", ssid.c_str());
  gLastWifiAttemptAt = millis();
  WiFi.disconnect(true, true);
  delay(150);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());

  const unsigned long startedAt = millis();
  while (millis() - startedAt < timeoutMs) {
    if (WiFi.status() == WL_CONNECTED) {
      gWifiConnected = true;
      Serial.print("WiFi baglandi, IP: ");
      Serial.println(WiFi.localIP());
      wifiNotifyBleState();
      return true;
    }

    wifiUpdateLed();
    delay(150);
  }

  gWifiConnected = false;
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

  std::vector<WifiNetworkInfo> networks;
  const int count = WiFi.scanNetworks(false, true);
  for (int index = 0; index < count; index += 1) {
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

  serializeJson(doc, gBleNetworksPayload);
  if (gBleNetworksCharacteristic != nullptr) {
    gBleNetworksCharacteristic->setValue(gBleNetworksPayload.c_str());
    gBleNetworksCharacteristic->notify();
  }
  wifiNotifyBleResult("scan_complete", "WiFi listesi guncellendi.");
}

inline String wifiBleDeviceName() {
  return "GUDE" + cihazUniqueId();
}

inline void wifiStopProvisioningMode();
inline void wifiStartProvisioningMode();

inline void wifiApplyProvisioningRequest() {
  gPendingWifiProvision = false;
  const String ssid = gPendingProvisionSsid;
  const String password = gPendingProvisionPassword;

  if (ssid.isEmpty()) {
    wifiNotifyBleResult("error", "SSID zorunlu.");
    return;
  }

  wifiNotifyBleResult("connecting", "Secilen aga baglaniliyor.");
  if (!wifiTryConnect(ssid, password, 20000)) {
    gProvisioningMode = true;
    wifiNotifyBleResult("failed", "WiFi baglantisi kurulamadi.");
    return;
  }

  wifiPersistCredentials(ssid, password);
  wifiNotifyBleResult("connected", "WiFi ayari kaydedildi.");
  wifiNotifyBleState();
  delay(1000);
  ESP.restart();
}

class WifiProvisionCommandCallbacks : public BLECharacteristicCallbacks {
 public:
  void onWrite(BLECharacteristic* characteristic) override {
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
    if (ssid.isEmpty()) {
      wifiNotifyBleResult("error", "SSID bilgisi eksik.");
      return;
    }

    gPendingProvisionSsid = ssid;
    gPendingProvisionPassword = password;
    gPendingWifiProvision = true;
  }
};

inline void wifiStartProvisioningMode() {
  gProvisioningMode = true;
  if (gBleStarted) {
    wifiNotifyBleState();
    return;
  }

  const String bleName = wifiBleDeviceName();
  BLEDevice::init(bleName.c_str());
  BLEDevice::setPower(ESP_PWR_LVL_P9);

  gBleServer = BLEDevice::createServer();
  gBleService = gBleServer->createService(BLE_WIFI_SERVICE_UUID);

  gBleStateCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_STATE_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  gBleNetworksCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_NETWORKS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  gBleResultCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_RESULT_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLECharacteristic* commandCharacteristic = gBleService->createCharacteristic(
    BLE_WIFI_COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  commandCharacteristic->setCallbacks(new WifiProvisionCommandCallbacks());

  gBleService->start();
  gBleAdvertising = BLEDevice::getAdvertising();
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
    return;
  }

  if (gBleAdvertising != nullptr) {
    gBleAdvertising->stop();
  }
  BLEDevice::deinit(true);
  gBleAdvertising = nullptr;
  gBleService = nullptr;
  gBleServer = nullptr;
  gBleStateCharacteristic = nullptr;
  gBleNetworksCharacteristic = nullptr;
  gBleResultCharacteristic = nullptr;
  gBleStarted = false;
  gProvisioningMode = false;
  Serial.println("BLE WiFi provisioning kapatildi.");
}

inline void wifiHandleResetButton() {
  const bool pressed = wifiResetButtonPressed();
  if (!pressed) {
    gResetPressedAt = 0;
    gResetHandled = false;
    return;
  }

  if (gResetPressedAt == 0) {
    gResetPressedAt = millis();
    return;
  }

  if (gResetHandled || millis() - gResetPressedAt < WIFI_RESET_HOLD_MS) {
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
  pinMode(WIFI_STATUS_LED_PIN, OUTPUT);
  pinMode(WIFI_RESET_BUTTON_PIN, WIFI_RESET_BUTTON_ACTIVE_LOW ? INPUT_PULLUP : INPUT);
  wifiSetStatusLed(false);

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

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(false);

  Serial.printf("Kayitli WiFi bulundu: %s\n", gSavedWifiSsid.c_str());
  if (wifiTryConnect(gSavedWifiSsid, gSavedWifiPassword, 20000)) {
    wifiStopProvisioningMode();
    return;
  }

  Serial.println("Kayitli WiFi'ye baglanamadi, cihaz yeniden deneyecek.");
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

  if (gWifiConnected) {
    wifiStopProvisioningMode();
  } else if (!gWifiConfigured) {
    wifiStartProvisioningMode();
  } else if (millis() - gLastWifiAttemptAt >= WIFI_RETRY_INTERVAL_MS) {
    wifiTryConnect(gSavedWifiSsid, gSavedWifiPassword, 8000);
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

#endif
