#ifndef OTA_GUNCELLEME_H
#define OTA_GUNCELLEME_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "tls_kok_sertifika.h"
#include "wifi_baglanti.h"

inline constexpr char OTA_CURRENT_VERSION[] = "1.1.0";
inline constexpr char OTA_TARGET[] = "esp32-c3";
inline constexpr char OTA_MANIFEST_URL[] =
  "https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json";
inline constexpr unsigned long OTA_BOOT_CHECK_DELAY_MS = 90000;
inline constexpr unsigned long OTA_PERIODIC_CHECK_MS = 24UL * 60UL * 60UL * 1000UL;
inline constexpr unsigned long OTA_MIN_RETRY_MS = 10UL * 60UL * 1000UL;

inline unsigned long gOtaNextCheckAt = 0;
inline unsigned long gOtaLastAttemptAt = 0;
inline bool gOtaPendingCheck = false;
inline bool gOtaRunning = false;
inline String gOtaLastStatus = "beklemede";

inline unsigned long otaDeviceJitterMs(unsigned long maxMs) {
  if (maxMs == 0) {
    return 0;
  }
  uint64_t mac = ESP.getEfuseMac();
  return static_cast<unsigned long>(mac % maxMs);
}

inline void otaPlanNext(unsigned long baseDelayMs) {
  gOtaNextCheckAt = millis() + baseDelayMs + otaDeviceJitterMs(60UL * 60UL * 1000UL);
}

inline void otaSetup() {
  otaPlanNext(OTA_BOOT_CHECK_DELAY_MS);
  Serial.print("OTA surum: ");
  Serial.println(OTA_CURRENT_VERSION);
}

inline void otaTalepEt(const char* reason = "manual") {
  gOtaPendingCheck = true;
  Serial.print("OTA kontrol talebi: ");
  Serial.println(reason);
}

inline String otaLastStatus() {
  return gOtaLastStatus;
}

inline bool otaShouldCheckNow() {
  if (!wifiHazirMi() || gOtaRunning) {
    return false;
  }
  if (millis() - gOtaLastAttemptAt < OTA_MIN_RETRY_MS) {
    return false;
  }
  return gOtaPendingCheck || millis() >= gOtaNextCheckAt;
}

inline bool otaReadManifest(JsonDocument& doc) {
  WiFiClientSecure otaClient;
  otaClient.setCACert(TLS_ROOT_CA);

  HTTPClient http;
  String url = String(OTA_MANIFEST_URL) +
               "?current_version=" + OTA_CURRENT_VERSION +
               "&uid=" + cihazUniqueId();
  if (!http.begin(otaClient, url)) {
    gOtaLastStatus = "manifest baglantisi baslatilamadi";
    return false;
  }

  const int code = http.GET();
  if (code != HTTP_CODE_OK) {
    gOtaLastStatus = "manifest http hata: " + String(code);
    http.end();
    return false;
  }

  const String payload = http.getString();
  http.end();

  const DeserializationError error = deserializeJson(doc, payload);
  if (error) {
    gOtaLastStatus = "manifest json okunamadi";
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
  gOtaLastStatus = "kontrol ediliyor";
  Serial.println("OTA kontrolu basladi.");

  JsonDocument manifest;
  if (!otaReadManifest(manifest)) {
    Serial.print("OTA manifest hatasi: ");
    Serial.println(gOtaLastStatus);
    otaPlanNext(OTA_PERIODIC_CHECK_MS);
    gOtaRunning = false;
    return;
  }

  const bool updateAvailable = manifest["update_available"] | false;
  const String version = String(manifest["version"] | "");
  const String url = String(manifest["url"] | "");
  if (!updateAvailable || url.isEmpty()) {
    gOtaLastStatus = "guncel";
    Serial.println("OTA: cihaz guncel.");
    otaPlanNext(OTA_PERIODIC_CHECK_MS);
    gOtaRunning = false;
    return;
  }

  Serial.print("OTA yeni surum bulundu: ");
  Serial.println(version);
  Serial.print("OTA indiriliyor: ");
  Serial.println(url);

  WiFiClientSecure otaClient;
  otaClient.setCACert(TLS_ROOT_CA);
  httpUpdate.rebootOnUpdate(true);
  const t_httpUpdate_return result = httpUpdate.update(otaClient, url);

  switch (result) {
    case HTTP_UPDATE_FAILED:
      gOtaLastStatus =
        "guncelleme basarisiz: " + String(httpUpdate.getLastError()) +
        " " + httpUpdate.getLastErrorString();
      Serial.println(gOtaLastStatus);
      break;
    case HTTP_UPDATE_NO_UPDATES:
      gOtaLastStatus = "guncelleme yok";
      Serial.println("OTA: guncelleme yok.");
      break;
    case HTTP_UPDATE_OK:
      gOtaLastStatus = "guncelleme tamam";
      Serial.println("OTA: guncelleme tamam, cihaz yeniden baslatiliyor.");
      break;
  }

  otaPlanNext(OTA_PERIODIC_CHECK_MS);
  gOtaRunning = false;
}

#endif
