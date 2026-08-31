#ifndef OFFLINE_LOG_H
#define OFFLINE_LOG_H

#include <Arduino.h>
#include <LittleFS.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <time.h>

#include "device_konfig.h"
#include "tls_kok_sertifika.h"
#include "wifi_baglanti.h"

inline const char* OFFLINE_LOG_FILE = "/offline_logs.json";
inline constexpr unsigned long OFFLINE_LOG_MAX_AGE_SECONDS = 7 * 24 * 3600; // 7 gün
inline unsigned long gSonLogTemizlemeMs = 0;
inline unsigned long gSonLogSenkronizasyonMs = 0;
inline bool gOfflineLogFsHazir = false;

inline void offlineLogInit() {
  if (LittleFS.begin(true)) {
    gOfflineLogFsHazir = true;
    Serial.println("Offline Log Sistemi: LittleFS baslatildi.");
  } else {
    gOfflineLogFsHazir = false;
    Serial.println("Offline Log Sistemi: LittleFS baslatilamadi!");
  }
}

inline unsigned long getMevcutZamanEpoch() {
  time_t now;
  time(&now);
  if (now > 1600000000) {
    return static_cast<unsigned long>(now);
  }
  return 0;
}

inline void offlineLogKaydet(
  const char* triggerType = "local_wifi",
  const char* userName = "Yerel Ag Kullanicisi",
  const char* apartmentLabel = ""
) {
  if (!gOfflineLogFsHazir) {
    return;
  }

  const unsigned long epochTime = getMevcutZamanEpoch();
  const unsigned long bootMs = millis();

  String mevcutIcerik = "";
  if (LittleFS.exists(OFFLINE_LOG_FILE)) {
    File f = LittleFS.open(OFFLINE_LOG_FILE, "r");
    if (f) {
      mevcutIcerik = f.readString();
      f.close();
    }
  }

  mevcutIcerik.trim();
  if (mevcutIcerik.startsWith("[") && mevcutIcerik.endsWith("]")) {
    mevcutIcerik = mevcutIcerik.substring(1, mevcutIcerik.length() - 1);
    mevcutIcerik.trim();
  }

  String yeniKayit = "{";
  yeniKayit += "\"trigger_type\":\"" + String(triggerType) + "\",";
  yeniKayit += "\"user_name\":\"" + String(userName) + "\",";
  yeniKayit += "\"apartment_label\":\"" + String(apartmentLabel) + "\",";
  yeniKayit += "\"epoch_time\":" + String(epochTime) + ",";
  yeniKayit += "\"boot_ms\":" + String(bootMs);
  yeniKayit += "}";

  if (mevcutIcerik.length() > 0) {
    mevcutIcerik += "," + yeniKayit;
  } else {
    mevcutIcerik = yeniKayit;
  }

  File f = LittleFS.open(OFFLINE_LOG_FILE, "w");
  if (f) {
    f.print("[" + mevcutIcerik + "]");
    f.close();
    Serial.println("Offline Log: Kapı gecisi LittleFS hafizasina kaydedildi.");
  } else {
    Serial.println("Offline Log: Dosya yazma hatasi!");
  }
}

inline void offlineLogHaftalikTemizle() {
  if (!gOfflineLogFsHazir || !LittleFS.exists(OFFLINE_LOG_FILE)) {
    return;
  }

  const unsigned long simdikiMs = millis();
  if (simdikiMs - gSonLogTemizlemeMs < 3600000ULL) { // Saatte bir kontrol et
    return;
  }
  gSonLogTemizlemeMs = simdikiMs;

  const unsigned long epochNow = getMevcutZamanEpoch();
  if (epochNow > 1600000000) {
    // NTP aktifse 7 günden eski dosyaları temizle
    File f = LittleFS.open(OFFLINE_LOG_FILE, "r");
    if (!f) return;
    const size_t fileSize = f.size();
    f.close();

    // Dosya 7 günden eskiyse ve internet yoksa dosya boyutuna ve zamana göre temizle
    if (fileSize > 64 * 1024) { // 64KB üzerinde ise
      LittleFS.remove(OFFLINE_LOG_FILE);
      Serial.println("Offline Log: 64KB uzeri eski loglar temizlendi.");
    }
  } else {
    // İnternet hiç gelmediyse ve cihaz 7 günden uzun süredir aciksa (millis > 7 gun)
    if (simdikiMs > OFFLINE_LOG_MAX_AGE_SECONDS * 1000ULL) {
      LittleFS.remove(OFFLINE_LOG_FILE);
      Serial.println("Offline Log: 7 gundur internete baglanmayan loglar temizlendi.");
    }
  }
}

inline void offlineLogSenkronizeEt() {
  if (!gOfflineLogFsHazir || !wifiHazirMi() || !LittleFS.exists(OFFLINE_LOG_FILE)) {
    return;
  }

  const unsigned long simdikiMs = millis();
  if (simdikiMs - gSonLogSenkronizasyonMs < 30000) { // 30 saniyede bir dene
    return;
  }
  gSonLogSenkronizasyonMs = simdikiMs;

  File f = LittleFS.open(OFFLINE_LOG_FILE, "r");
  if (!f) {
    return;
  }
  String icerik = f.readString();
  f.close();
  icerik.trim();

  if (icerik.isEmpty() || icerik == "[]") {
    LittleFS.remove(OFFLINE_LOG_FILE);
    return;
  }

  String payload = "{\"device_uid\":\"" + cihazUniqueId() + "\",\"logs\":" + icerik + "}";

  WiFiClientSecure secureClient;
  secureClient.setCACert(TLS_ROOT_CA);
  secureClient.setTimeout(10);

  HTTPClient http;
  String syncUrl = "https://api.gudeteknoloji.com.tr/device/sync-logs";
  if (http.begin(secureClient, syncUrl)) {
    http.addHeader("Content-Type", "application/json");
    http.addHeader("x-ahbu-device-uid", cihazUniqueId());
    
    int httpCode = http.POST(payload);
    if (httpCode >= 200 && httpCode < 300) {
      Serial.print("Offline Log: Sunucuya basariyla senkronize edildi (HTTP ");
      Serial.print(httpCode);
      Serial.println("). Yerel loglar silindi.");
      LittleFS.remove(OFFLINE_LOG_FILE);
    } else {
      Serial.print("Offline Log: Senkronizasyon basarisiz (HTTP ");
      Serial.print(httpCode);
      Serial.println("). Sonra tekrar denenecek.");
    }
    http.end();
  }
}

#endif

