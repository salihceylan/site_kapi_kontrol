#ifndef OTA_GUNCELLEME_H
#define OTA_GUNCELLEME_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_ota_ops.h>

#include "tls_kok_sertifika.h"
#include "wifi_baglanti.h"

inline constexpr char OTA_CURRENT_VERSION[] = "2.0.1";
inline constexpr char OTA_TARGET[] = "esp32-c3";
inline constexpr char OTA_MANIFEST_URL[] =
  "https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json";
inline constexpr char OTA_PREFS_NAMESPACE[] = "ota_cfg";
inline constexpr char OTA_PREF_LAST_STATUS[] = "last_status";
inline constexpr char OTA_PREF_LAST_VERSION[] = "last_version";
inline constexpr unsigned long OTA_BOOT_CHECK_DELAY_MS = 10000; // 10 saniye sonra ilk kontrol
inline constexpr unsigned long OTA_BOOT_JITTER_MS = 15000; // 0-15 sn rastgele yayilma
inline constexpr unsigned long OTA_PERIODIC_CHECK_MS = 60UL * 60UL * 1000UL; // 1 saatte bir periyodik kontrol
inline constexpr unsigned long OTA_MIN_RETRY_MS = 30000; // Basarisiz olursa 30 sn sonra tekrar dene
inline constexpr unsigned long OTA_MIN_INTERVAL_MS = 15UL * 60UL * 1000UL; // min 15 dk
inline constexpr unsigned long OTA_MAX_INTERVAL_MS = 24UL * 60UL * 60UL * 1000UL; // max 24 saat

using OtaEventPublisher = void (*)(const char* eventName, const char* detail);

inline unsigned long gOtaNextCheckAt = 0;
inline unsigned long gOtaLastAttemptAt = 0;
inline unsigned long gOtaPeriodicIntervalMs = OTA_PERIODIC_CHECK_MS;
inline bool gOtaPendingCheck = false;
inline bool gOtaRunning = false;
inline String gOtaLastStatus = "beklemede";
inline String gOtaLastVersion = "";
inline Preferences gOtaPrefs;
inline OtaEventPublisher gOtaEventPublisher = nullptr;

inline unsigned long otaDeviceJitterMs(unsigned long maxMs) {
  if (maxMs == 0) {
    return 0;
  }
  uint64_t mac = ESP.getEfuseMac();
  return static_cast<unsigned long>(mac % maxMs);
}

inline void otaPlanNext(unsigned long baseDelayMs, bool withJitter = true, unsigned long maxJitterMs = 60UL * 60UL * 1000UL) {
  const unsigned long jitterMs = withJitter ? otaDeviceJitterMs(maxJitterMs) : 0;
  gOtaNextCheckAt = millis() + baseDelayMs + jitterMs;
}

inline void otaPersistStatus(const String& status, const String& version = "") {
  gOtaLastStatus = status;
  if (!version.isEmpty()) {
    gOtaLastVersion = version;
  }
  if (gOtaPrefs.isKey(OTA_PREF_LAST_STATUS) || !status.isEmpty()) {
    gOtaPrefs.putString(OTA_PREF_LAST_STATUS, gOtaLastStatus);
  }
  if (!gOtaLastVersion.isEmpty()) {
    gOtaPrefs.putString(OTA_PREF_LAST_VERSION, gOtaLastVersion);
  }
}

inline void otaPublishEvent(const char* eventName, const String& detail = "") {
  if (gOtaEventPublisher != nullptr) {
    gOtaEventPublisher(eventName, detail.c_str());
  }
}

inline void otaSetEventPublisher(OtaEventPublisher publisher) {
  gOtaEventPublisher = publisher;
}

inline void otaSetup() {
  gOtaPrefs.begin(OTA_PREFS_NAMESPACE, false);
  gOtaLastStatus = gOtaPrefs.getString(OTA_PREF_LAST_STATUS, "beklemede");
  gOtaLastVersion = gOtaPrefs.getString(OTA_PREF_LAST_VERSION, "");
  otaPlanNext(OTA_BOOT_CHECK_DELAY_MS, true, OTA_BOOT_JITTER_MS);
  Serial.print("OTA surum: ");
  Serial.println(OTA_CURRENT_VERSION);
  Serial.print("OTA son durum: ");
  Serial.println(gOtaLastStatus);
}

inline void otaTalepEt(const char* reason = "manual") {
  gOtaPendingCheck = true;
  Serial.print("OTA kontrol talebi: ");
  Serial.println(reason);
}

inline String otaLastStatus() {
  return gOtaLastStatus;
}

inline String otaLastVersion() {
  return gOtaLastVersion;
}

inline bool otaShouldCheckNow() {
  if (!wifiHazirMi() || gOtaRunning) {
    return false;
  }
  if (!gOtaPendingCheck && gOtaLastAttemptAt > 0 && millis() - gOtaLastAttemptAt < OTA_MIN_RETRY_MS) {
    return false;
  }
  return gOtaPendingCheck || static_cast<int32_t>(millis() - gOtaNextCheckAt) >= 0;
}

inline unsigned long otaIntervalFromManifest(JsonDocument& doc) {
  const unsigned long intervalHours = doc["interval_hours"] | 24UL;
  unsigned long intervalMs = intervalHours * 60UL * 60UL * 1000UL;
  if (intervalMs < OTA_MIN_INTERVAL_MS) {
    intervalMs = OTA_MIN_INTERVAL_MS;
  }
  if (intervalMs > OTA_MAX_INTERVAL_MS) {
    intervalMs = OTA_MAX_INTERVAL_MS;
  }
  return intervalMs;
}

inline bool otaReadManifest(JsonDocument& doc) {
  WiFiClientSecure otaClient;
  otaClient.setCACert(TLS_ROOT_CA);
  otaClient.setTimeout(12);

  HTTPClient http;
  http.setTimeout(12000);
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  String url = String(OTA_MANIFEST_URL) +
               "?current_version=" + OTA_CURRENT_VERSION +
               "&uid=" + cihazUniqueId();
  if (!http.begin(otaClient, url)) {
    otaPersistStatus("manifest baglantisi baslatilamadi");
    return false;
  }

  const int code = http.GET();
  if (code != HTTP_CODE_OK) {
    otaPersistStatus("manifest http hata: " + String(code));
    http.end();
    return false;
  }

  const String payload = http.getString();
  http.end();

  const DeserializationError error = deserializeJson(doc, payload);
  if (error) {
    otaPersistStatus("manifest json okunamadi");
    return false;
  }
  return true;
}

inline void otaCheckAndUpdate() {
  if (!otaShouldCheckNow()) {
    return;
  }

  gOtaRunning = true;
  gOtaPendingCheck = false;
  gOtaLastAttemptAt = millis();
  otaPersistStatus("kontrol ediliyor");
  Serial.println("OTA kontrolu basladi.");
  otaPublishEvent("ota_check_started");

  JsonDocument manifest;
  if (!otaReadManifest(manifest)) {
    Serial.print("OTA manifest hatasi: ");
    Serial.println(gOtaLastStatus);
    otaPublishEvent("ota_check_failed", gOtaLastStatus);
    otaPlanNext(45000); // Hata durumunda 45 saniye sonra tekrar dene
    gOtaRunning = false;
    return;
  }

  gOtaPeriodicIntervalMs = otaIntervalFromManifest(manifest);
  const bool updateAvailable = manifest["update_available"] | false;
  const String version = String(manifest["version"] | "");
  const String url = String(manifest["url"] | "");
  const String md5 = String(manifest["md5"] | "");
  if (!updateAvailable || url.isEmpty()) {
    otaPersistStatus("guncel", version);
    Serial.println("OTA: cihaz guncel.");
    otaPublishEvent("ota_up_to_date", version);
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  otaPersistStatus("guncelleme indiriliyor", version);
  otaPublishEvent("ota_update_available", version);
  Serial.print("Guncelleme geldi. Yeni versiyon: ");
  Serial.println(version);
  Serial.print("OTA indiriliyor: ");
  Serial.println(url);

  const esp_partition_t* updatePartition = esp_ota_get_next_update_partition(nullptr);
  if (updatePartition == nullptr) {
    otaPersistStatus("OTA partition yok; cihaza USB ile OTA partition tablosu yuklenmeli", version);
    Serial.println(gOtaLastStatus);
    otaPublishEvent("ota_failed", gOtaLastStatus);
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }
  Serial.print("OTA hedef partition: ");
  Serial.print(updatePartition->label);
  Serial.print(" boyut: ");
  Serial.println(updatePartition->size);

  // WDT 8 saniye olduğu için 1.18MB indirme sırasında reset atmasını engelle
  esp_task_wdt_delete(NULL);

  WiFiClientSecure otaClient;
  otaClient.setCACert(TLS_ROOT_CA);
  otaClient.setTimeout(15);

  httpUpdate.rebootOnUpdate(true);
  httpUpdate.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  httpUpdate.setLedPin(WIFI_STATUS_LED_PIN, LOW);

  Update.onProgress([](size_t progress, size_t size) {
    if (size > 0) {
      Serial.printf("OTA Indiriliyor: %u%%\r", (progress * 100) / size);
    }
  });

  if (md5.length() == 32) {
    Serial.print("OTA manifest MD5: ");
    Serial.println(md5);
  }
  const t_httpUpdate_return result = httpUpdate.update(otaClient, url);

  // Güncelleme başarısız olduysa veya yeniden başlamadıysa WDT'yi tekrar devreye al
  esp_task_wdt_init(8, true);
  esp_task_wdt_add(NULL);

  switch (result) {
    case HTTP_UPDATE_FAILED:
      otaPersistStatus(
        "guncelleme basarisiz: " + String(httpUpdate.getLastError()) +
        " " + httpUpdate.getLastErrorString(),
        version
      );
      Serial.println(gOtaLastStatus);
      otaPublishEvent("ota_failed", gOtaLastStatus);
      break;
    case HTTP_UPDATE_NO_UPDATES:
      otaPersistStatus("guncelleme yok", version);
      Serial.println("OTA: guncelleme yok.");
      otaPublishEvent("ota_no_updates", version);
      break;
    case HTTP_UPDATE_OK:
      otaPersistStatus("guncelleme tamam", version);
      Serial.println("OTA: guncelleme tamam, cihaz yeniden baslatiliyor.");
      otaPublishEvent("ota_success", version);
      break;
  }

  otaPlanNext(gOtaPeriodicIntervalMs);
  gOtaRunning = false;
}

#endif
