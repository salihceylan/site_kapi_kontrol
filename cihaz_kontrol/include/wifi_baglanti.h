#ifndef WIFI_BAGLANTI_H
#define WIFI_BAGLANTI_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <Preferences.h>
#include <WiFi.h>

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

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
// C4: yerel kontrol anahtari sunucudan (MQTT local_control_config) gelir; MQTT parolasindan AYRI saklanir.
inline constexpr char WIFI_PREF_LOCAL_TOKEN[] = "lc_token";

inline constexpr char BLE_WIFI_SERVICE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f001";
inline constexpr char BLE_WIFI_STATE_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f002";
inline constexpr char BLE_WIFI_COMMAND_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f003";
inline constexpr char BLE_WIFI_NETWORKS_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f004";
inline constexpr char BLE_WIFI_RESULT_UUID[] = "6f64be30-0d46-4f6d-9cd4-4f9d08b5f005";

// BLE ile verilen MQTT sunucusu yalniz bu alan adi ekine izin verir (sahte broker yonlendirmesini onler).
// Ozel/test ortami icin derleme bayragi: -D AHBU_MQTT_HOST_SUFFIX=".ornek.com"
#ifndef AHBU_MQTT_HOST_SUFFIX
#define AHBU_MQTT_HOST_SUFFIX ".gudeteknoloji.com.tr"
#endif
inline constexpr size_t BLE_COMMAND_MAX_BYTES = 640;

inline constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 15000;
// Yedek yeniden baglanma (cekirdegin setAutoReconnect'ine ek): bekleme 6 -> 12 -> 24 -> 48 -> 60 sn katlanir, baglaninca 6 sn'ye doner.
inline constexpr unsigned long WIFI_RETRY_MIN_MS = 6000;
inline constexpr unsigned long WIFI_RETRY_MAX_MS = 60000;
// WL_IDLE_STATUS (AP'ye baglandi, DHCP/IP bekleniyor) deneme en fazla bu kadar kesilmez
inline constexpr unsigned long WIFI_IP_BEKLEME_MAX_MS = 30000;
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
inline String gSavedLocalToken;
inline bool gWifiConfigured = false;
inline bool gWifiConnected = false;
inline bool gProvisioningMode = false;
// BLE geri cagrisi (BTC gorevi) ile loop gorevi arasinda paylasilir: volatile + tek yonlu devir.
// Geri cagri yalniz bayrak false iken veriyi yazar ve en son bayragi true yapar; loop veriyi okuyup bayragi en son temizler.
inline volatile bool gPendingWifiScan = false;
inline volatile bool gPendingWifiProvision = false;
inline String gPendingProvisionSsid;
inline String gPendingProvisionPassword;
inline String gPendingMqttHost;
inline uint16_t gPendingMqttPort = 0;
inline String gPendingMqttUser;
inline String gPendingMqttPassword;
inline String gBleNetworksPayload = R"({"networks":[]})";
inline String gBleResultPayload = R"({"status":"idle","message":""})";
inline unsigned long gLastWifiAttemptAt = 0;
inline unsigned long gWifiRetryBeklemeMs = WIFI_RETRY_MIN_MS;  // sonraki yedek yeniden deneme beklemesi (ussel)
inline unsigned long gLastLedToggleAt = 0;
inline unsigned long gResetPressedAt = 0;
inline unsigned long gResetLastProgressAt = 0;
inline bool gLedLogicalState = false;
inline bool gResetHandled = false;
inline BLEServer* gBleServer = nullptr;
inline BLEService* gBleService = nullptr;
inline BLEAdvertising* gBleAdvertising = nullptr;
inline BLECharacteristic* gBleStateCharacteristic = nullptr;
inline BLECharacteristic* gBleNetworksCharacteristic = nullptr;
inline BLECharacteristic* gBleResultCharacteristic = nullptr;
inline volatile bool gBleStarted = false;
inline SemaphoreHandle_t gBleResultMutex = nullptr;

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
  gSavedLocalToken = gWifiPrefs.getString(WIFI_PREF_LOCAL_TOKEN, "");
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
  const String& password
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

// C4: yerel kontrol yalniz sunucunun gonderdigi token ile yetkilendirilir. Token yoksa yerel kontrol KAPALI (fail-closed).
// Bu fonksiyon ASLA MQTT parolasini dondurmez.
inline String wifiLocalControlToken() {
  return gSavedLocalToken;
}

inline bool wifiHasLocalControlToken() {
  return !gSavedLocalToken.isEmpty();
}

inline bool wifiLocalTokenGecerliMi(const String& token) {
  if (token.length() < 16 || token.length() > 64) {
    return false;
  }
  for (size_t i = 0; i < token.length(); i += 1) {
    const char c = token[i];
    const bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_';
    if (!ok) {
      return false;
    }
  }
  return true;
}

// 0: gecersiz, 1: degismedi, 2: guncellendi (NVS'e yalnizca degisince yazilir - flash asinmasi)
inline int wifiPersistLocalToken(const String& token) {
  if (!wifiLocalTokenGecerliMi(token)) {
    return 0;
  }
  if (sabitZamanliEsit(token, gSavedLocalToken)) {
    return 1;
  }
  gWifiPrefs.putString(WIFI_PREF_LOCAL_TOKEN, token);
  gSavedLocalToken = token;
  return 2;
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
}

inline void wifiNotifyBleResult(const String& status, const String& message = "") {
  // Hem loop hem BLE geri cagrisi (BTC gorevi) cagirir: ortak String'i muteksle koru.
  const bool kilitli = gBleResultMutex != nullptr && xSemaphoreTake(gBleResultMutex, pdMS_TO_TICKS(100)) == pdTRUE;

  JsonDocument doc;
  doc["status"] = status;
  doc["message"] = message;
  serializeJson(doc, gBleResultPayload);

  if (gBleResultCharacteristic != nullptr) {
    gBleResultCharacteristic->setValue(gBleResultPayload.c_str());
  }

  if (kilitli) {
    xSemaphoreGive(gBleResultMutex);
  }
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
  delay(150);
  WiFi.disconnect(false, false);
  delay(150);
  WiFi.begin(ssid.c_str(), password.c_str());

  const unsigned long startedAt = millis();
  while (millis() - startedAt < timeoutMs) {
    if (WiFi.status() == WL_CONNECTED) {
      gWifiConnected = true;
      Serial.print("WiFi baglandi, IP: ");
      Serial.println(WiFi.localIP());
      configTime(3 * 3600, 0, "pool.ntp.org", "time.google.com", "time.cloudflare.com");
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
  }
  wifiNotifyBleResult("scan_complete", "WiFi listesi guncellendi.");
}

inline String wifiBleDeviceName() {
  return "AHBU" + cihazUniqueId();
}

inline void wifiStopProvisioningMode();
inline void wifiStartProvisioningMode();

inline void wifiApplyProvisioningRequest() {
  // Bayrak true iken BLE geri cagrisi yeni veri yazmaz; once kopyala, EN SON bayragi temizle.
  const String ssid = gPendingProvisionSsid;
  const String password = gPendingProvisionPassword;
  const String mqttHost = gPendingMqttHost;
  const uint16_t mqttPort = gPendingMqttPort;
  const String mqttUser = gPendingMqttUser;
  const String mqttPassword = gPendingMqttPassword;
  gPendingProvisionSsid = "";
  gPendingProvisionPassword = "";
  gPendingMqttHost = "";
  gPendingMqttPort = 0;
  gPendingMqttUser = "";
  gPendingMqttPassword = "";
  __sync_synchronize();
  gPendingWifiProvision = false;

  if (ssid.isEmpty()) {
    wifiNotifyBleResult("error", "SSID zorunlu.");
    return;
  }

  wifiPersistCredentials(ssid, password);
  wifiPersistMqttCredentials(mqttHost, mqttPort, mqttUser, mqttPassword);
  wifiNotifyBleResult("restarting", "WiFi ve MQTT bilgileri kaydedildi. Cihaz temiz baglanti icin yeniden baslatiliyor.");
  wifiNotifyBleState();
  delay(1500);
  ESP.restart();
}

// MQTT sunucu adi guvenligi: yalniz varsayilan host veya izin verilen alan adi eki.
inline bool wifiMqttHostIzinliMi(const String& host) {
  if (host.isEmpty() || host.length() > 80) {
    return false;
  }
  for (size_t i = 0; i < host.length(); i += 1) {
    const char c = host[i];
    const bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '.';
    if (!ok) {
      return false;
    }
  }
  String h = host;
  h.toLowerCase();
  String ek = String(AHBU_MQTT_HOST_SUFFIX);
  ek.toLowerCase();
  if (h.length() <= ek.length()) {
    return false;
  }
  return h.endsWith(ek);
}

class WifiProvisionCommandCallbacks : public BLECharacteristicCallbacks {
 public:
  void onWrite(BLECharacteristic* characteristic) override {
    // Yalniz provisioning penceresi acikken komut kabul edilir (pencere disinda sessizce yok sayilir).
    if (!gProvisioningMode || !gBleStarted) {
      return;
    }

    const std::string value = characteristic->getValue();
    if (value.empty() || value.size() > BLE_COMMAND_MAX_BYTES) {
      return;
    }

    // Bir onceki talep loop tarafindan henuz islenmediyse yeni talep alma (paylasilan degiskenleri koru).
    if (gPendingWifiProvision || gPendingWifiScan) {
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
    const uint32_t mqttPortRaw = static_cast<uint32_t>(doc["mqtt_port"] | 0);
    const String mqttUser = String(doc["mqtt_username"] | "");
    const String mqttPassword = String(doc["mqtt_password"] | "");
    if (ssid.isEmpty() || ssid.length() > 32 || password.length() > 63) {
      wifiNotifyBleResult("error", "SSID bilgisi eksik veya gecersiz.");
      return;
    }
    if (
      mqttHost.isEmpty() ||
      mqttPortRaw == 0 ||
      mqttPortRaw > 65535 ||
      mqttUser.isEmpty() ||
      mqttPassword.isEmpty() ||
      mqttUser.length() > 64 ||
      mqttPassword.length() > 128
    ) {
      wifiNotifyBleResult("error", "MQTT cihaz kimligi eksik. Once cihazi sirket hesabina kaydedin.");
      return;
    }
    if (!wifiMqttHostIzinliMi(mqttHost)) {
      wifiNotifyBleResult("error", "MQTT sunucu adresi izinli degil.");
      return;
    }

    gPendingProvisionSsid = ssid;
    gPendingProvisionPassword = password;
    gPendingMqttHost = mqttHost;
    gPendingMqttPort = static_cast<uint16_t>(mqttPortRaw);
    gPendingMqttUser = mqttUser;
    gPendingMqttPassword = mqttPassword;
    __sync_synchronize();
    gPendingWifiProvision = true;  // en son: loop artik tutarli veriyi okuyabilir
  }
};

inline void wifiStartProvisioningMode() {
  gProvisioningMode = true;
  wifiSetBleStatusLed(true);
  if (gBleStarted) {
    wifiNotifyBleState();
    return;
  }

  if (gBleResultMutex == nullptr) {
    gBleResultMutex = xSemaphoreCreateMutex();
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
    wifiSetBleStatusLed(false);
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
  gLastWifiAttemptAt = millis();

  // Yazilimsal reset / OTA sonrasi RF register kilitlenmesini onlemek icin temiz sifirlama
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_OFF);
  delay(100);

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

  // WiFi baglanti olaylarini dinle ve logla
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
    if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
      Serial.printf("WiFi baglanti koptu / basarisiz (Hata kodu: %d)\n", info.wifi_sta_disconnected.reason);
    } else if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
      Serial.printf("WiFi IP alindi: %s\n", WiFi.localIP().toString().c_str());
    }
  });

  Serial.printf("Kayitli WiFi bulundu: %s, baglaniliyor...\n", gSavedWifiSsid.c_str());
  WiFi.begin(gSavedWifiSsid.c_str(), gSavedWifiPassword.c_str());
}

inline void wifiLoop() {
  wifiHandleResetButton();
  gWifiConnected = (WiFi.status() == WL_CONNECTED);

  // Baglanti AZ ONCE koptu: cekirdegin otomatik yeniden baglanmasina (setAutoReconnect) once sure tani; yedek deneme kopmadan
  // itibaren olculur. (Eskiden bayat damga yuzunden kopma aninda hemen disconnect+begin yapilip devam eden otomatik deneme kesiliyordu.)
  static bool sOncekiBagli = false;
  if (sOncekiBagli && !gWifiConnected) {
    gLastWifiAttemptAt = millis();
    gWifiRetryBeklemeMs = WIFI_RETRY_MIN_MS;
  }
  sOncekiBagli = gWifiConnected;

  if (gPendingWifiScan) {
    gPendingWifiScan = false;
    wifiPerformScan();
  }

  if (gPendingWifiProvision) {
    wifiApplyProvisioningRequest();
  }

  static bool sNtpConfigured = false;
  if (gWifiConnected) {
    gWifiRetryBeklemeMs = WIFI_RETRY_MIN_MS;  // baglandi: geri cekilme basa doner
    if (!sNtpConfigured) {
      configTime(3 * 3600, 0, "pool.ntp.org", "time.google.com", "time.cloudflare.com");
      sNtpConfigured = true;
    }
    if (gProvisioningMode && wifiHasMqttCredentials()) {
      wifiStopProvisioningMode();
    }
  } else if (!gWifiConfigured) {
    sNtpConfigured = false;
    if (!gProvisioningMode) {
      wifiStartProvisioningMode();
    }
  } else {
    sNtpConfigured = false;
    // Kayitli Wi-Fi var ama bagli degil: yedek yeniden deneme. Bekleme 6->12->24->48->60 sn katlanir (kalabalik aglarda baglanma
    // yarida kesilmesin, AP kapaliyken her 6 sn'de tam tarama olmasin); baglaninca 6 sn'ye doner.
    const unsigned long gecen = millis() - gLastWifiAttemptAt;
    if (gecen >= gWifiRetryBeklemeMs) {
      if (WiFi.status() == WL_IDLE_STATUS && gecen < WIFI_IP_BEKLEME_MAX_MS) {
        // AP'ye baglandi, IP (DHCP) bekleniyor: devam eden baglanmayi kesme
      } else {
        gLastWifiAttemptAt = millis();
        const unsigned long sonraki = gWifiRetryBeklemeMs * 2;
        gWifiRetryBeklemeMs = sonraki > WIFI_RETRY_MAX_MS ? WIFI_RETRY_MAX_MS : sonraki;
        Serial.printf("WiFi baglantisi yeniden deneniyor (%s)...\n", gSavedWifiSsid.c_str());
        WiFi.disconnect(false, false);
        delay(50);
        WiFi.begin(gSavedWifiSsid.c_str(), gSavedWifiPassword.c_str());
      }
    }
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
