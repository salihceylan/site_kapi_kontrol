#ifndef OFFLINE_LOG_H
#define OFFLINE_LOG_H

// Cevrimdisi kapi gecis kayitlari (C6):
//  - Kayitlar LittleFS'te NDJSON (her satir tek JSON kayit) tutulur: /offline_logs.ndjson
//  - Kayit: {"client_log_id":"<uid>-<boot>-<seq>","epoch":<sn|0>,"boot_ms":<ms>,"trigger_type":"..","user_name":"..",
//            "apartment_label":"..","action":"open"}
//  - Teslim: device/<uid>/logs konusuna QoS0 {"batch_id":<uint>,"logs":[...]} (tek yayin <= 900 bayt; buyukse bolunur).
//  - Sunucu idempotent yazar ve device/<uid>/cmd'ye {"action":"logs_ack","batch_id":<id>} yollar;
//    cihaz YALNIZCA ack gelince o batch'in satirlarini siler (ack gelmezse zaman asimiyla tekrar yayinlar).
//  - Dosya dolarsa EN ESKI kayitlar atilir (tum dosya silinmez); yazma gecici dosya + rename ile atomiktir.
//  - Saat senkron degilken epoch=0 + boot_ms yazilir; saat gelince ayni acilisin kayitlarinin epoch'u gonderim sirasinda duzeltilir.

#include <Arduino.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <time.h>

#include "device_konfig.h"
#include "wifi_baglanti.h"

extern PubSubClient client;

inline constexpr char OFFLINE_LOG_FILE[] = "/offline_logs.ndjson";
inline constexpr char OFFLINE_LOG_TMP[] = "/offline_logs.tmp";
inline constexpr char OFFLINE_LOG_LEGACY[] = "/offline_logs.json";  // eski JSON dizi bicimi (bir kerelik goc)
inline constexpr char OFFLINE_LOG_PREFS[] = "olog";
inline constexpr size_t OFFLINE_LOG_MAX_FILE_SIZE = 16 * 1024;     // asilirsa en eski kayitlar atilir
inline constexpr size_t OFFLINE_LOG_COMPACT_TARGET = 12 * 1024;    // atma sonrasi hedef boyut
inline constexpr size_t OFFLINE_LOG_BATCH_BUDGET = 800;            // kayit bayti (sarmalayici ile toplam <= 900)
inline constexpr unsigned long OFFLINE_LOG_SYNC_INTERVAL_MS = 3000;
inline constexpr unsigned long OFFLINE_LOG_ACK_TIMEOUT_MIN_MS = 15000;
inline constexpr unsigned long OFFLINE_LOG_ACK_TIMEOUT_MAX_MS = 600000;

inline bool gOfflineLogFsHazir = false;
inline uint32_t gOfflineLogBootId = 0;
inline uint32_t gOfflineLogSeq = 0;
inline bool gOfflineLogBekleyen = false;
inline uint32_t gOfflineLogBatchSayac = 0;
inline uint32_t gOfflineLogBatchId = 0;  // ack bekleyen batch (0: yok)
inline size_t gOfflineLogBatchSatir = 0;
inline unsigned long gOfflineLogBatchGonderimMs = 0;
inline unsigned long gOfflineLogAckTimeoutMs = OFFLINE_LOG_ACK_TIMEOUT_MIN_MS;
inline unsigned long gSonLogSenkronizasyonMs = 0;

inline unsigned long getMevcutZamanEpoch() {
  return epochSimdi();
}

// Metni kontrol karakterlerinden arindirir ve UTF-8 karakter ortasindan kesmeden en fazla maxBytes bayta indirir.
inline String offlineLogMetinTemizle(const char* s, size_t maxBytes) {
  String out;
  if (s == nullptr) {
    return out;
  }
  const size_t len = strlen(s);
  size_t n = len < maxBytes ? len : maxBytes;
  if (n < len) {
    while (n > 0 && (static_cast<uint8_t>(s[n]) & 0xC0) == 0x80) {
      n -= 1;
    }
  }
  out.reserve(n);
  for (size_t i = 0; i < n; i += 1) {
    const uint8_t c = static_cast<uint8_t>(s[i]);
    out += (c < 0x20 || c == 0x7F) ? ' ' : static_cast<char>(c);
  }
  return out;
}

// Dosyadan (src) ilk 'atlanacakSatir' satiri atip kalani gecici dosyaya yazar, sonra atomik rename eder.
// atlanacakSatir yerine baytAtla verilirse once o kadar bayt atlanir ve siradaki satir basina hizalanir.
inline bool offlineLogDosyayiYenile(size_t atlanacakSatir, size_t baytAtla) {
  File src = LittleFS.open(OFFLINE_LOG_FILE, "r");
  if (!src) {
    return false;
  }

  if (baytAtla > 0) {
    if (!src.seek(baytAtla)) {
      src.close();
      return false;
    }
    while (src.available()) {
      if (src.read() == '\n') {
        break;
      }
    }
  } else {
    size_t atlanan = 0;
    while (atlanan < atlanacakSatir && src.available()) {
      if (src.read() == '\n') {
        atlanan += 1;
      }
    }
  }

  File dst = LittleFS.open(OFFLINE_LOG_TMP, "w");
  if (!dst) {
    src.close();
    return false;
  }

  bool yazmaTamam = true;
  size_t yazilan = 0;
  uint8_t tampon[128];
  while (src.available()) {
    const int n = src.read(tampon, sizeof(tampon));
    if (n <= 0) {
      break;
    }
    if (dst.write(tampon, static_cast<size_t>(n)) != static_cast<size_t>(n)) {
      yazmaTamam = false;
      break;
    }
    yazilan += static_cast<size_t>(n);
  }
  src.close();
  dst.close();

  if (!yazmaTamam) {
    LittleFS.remove(OFFLINE_LOG_TMP);
    return false;
  }

  if (yazilan == 0) {
    LittleFS.remove(OFFLINE_LOG_TMP);
    LittleFS.remove(OFFLINE_LOG_FILE);
    gOfflineLogBekleyen = false;
    return true;
  }

  if (!LittleFS.rename(OFFLINE_LOG_TMP, OFFLINE_LOG_FILE)) {
    // Bazi surumlerde hedef varken rename basarisiz olabilir: once hedefi kaldirip tekrar dene.
    LittleFS.remove(OFFLINE_LOG_FILE);
    if (!LittleFS.rename(OFFLINE_LOG_TMP, OFFLINE_LOG_FILE)) {
      return false;
    }
  }
  return true;
}

// Sunucu (door_log_service ALLOWED_TRIGGER_TYPES) allowlist'i disindaki trigger_type kaydi RED + ack ile DUSER (veri kaybi).
// Bu yuzden bilinmeyen deger "offline_sync"e cevrilir.
inline const char* offlineLogTurSecimi(const char* tur) {
  static const char* const izinli[] = {
    "cloud_app", "voice", "local_wifi", "local_udp", "local_http", "local_ble", "ble", "guest_pass", "offline_sync",
    "qr_scanner", "screen_qr", "display_btn", "admin_display_btn", "physical_btn", "serial_btn", "mqtt", "mqtt_pulse", "remote",
  };
  if (tur != nullptr) {
    for (size_t i = 0; i < sizeof(izinli) / sizeof(izinli[0]); i += 1) {
      if (strcmp(tur, izinli[i]) == 0) {
        return izinli[i];
      }
    }
  }
  return "offline_sync";
}

// Ham kaydi (epoch/boot_ms disaridan) dosyanin sonuna ekler. Dosya dolarsa en eski kayitlar atilir.
inline void offlineLogEkle(
  const char* triggerType,
  const char* userName,
  const char* apartmentLabel,
  uint32_t epochTime,
  uint32_t bootMs
) {
  if (!gOfflineLogFsHazir) {
    return;
  }

  gOfflineLogSeq += 1;
  JsonDocument doc;
  doc["client_log_id"] = cihazUniqueId() + "-" + String(gOfflineLogBootId) + "-" + String(gOfflineLogSeq);
  doc["epoch"] = epochTime;
  doc["boot_ms"] = bootMs;
  doc["trigger_type"] = offlineLogTurSecimi(triggerType);
  doc["user_name"] = offlineLogMetinTemizle(userName, 40);
  doc["apartment_label"] = offlineLogMetinTemizle(apartmentLabel, 24);
  doc["action"] = "open";

  String satir;
  serializeJson(doc, satir);
  satir += '\n';

  File f = LittleFS.open(OFFLINE_LOG_FILE, "a");
  if (!f) {
    Serial.println("Offline Log: Dosya yazma hatasi!");
    return;
  }
  const size_t yazilan = f.print(satir);
  const size_t boyut = f.size();
  f.close();
  if (yazilan != satir.length()) {
    Serial.println("Offline Log: Kayit eksik yazildi (flash dolu olabilir).");
  }
  gOfflineLogBekleyen = true;

  if (boyut > OFFLINE_LOG_MAX_FILE_SIZE) {
    const size_t atlanacak = boyut - OFFLINE_LOG_COMPACT_TARGET;
    if (offlineLogDosyayiYenile(0, atlanacak)) {
      gOfflineLogBatchId = 0;  // dosya degisti: bekleyen batch'in ack'i artik satir sayisiyla eslesmez
      Serial.println("Offline Log: dosya doldu, en eski kayitlar atildi.");
    }
  }
}

inline void offlineLogKaydet(
  const char* triggerType = "local_wifi",
  const char* userName = "Yerel Ag Kullanicisi",
  const char* apartmentLabel = ""
) {
  offlineLogEkle(triggerType, userName, apartmentLabel, epochSimdi(), millis());
  Serial.println("Offline Log: kapi gecisi kaydedildi.");
}

// Eski bicimdeki (JSON dizi) dosyayi NDJSON'a tasir ve siler.
inline void offlineLogEskiBicimiTasi() {
  if (!LittleFS.exists(OFFLINE_LOG_LEGACY)) {
    return;
  }
  File f = LittleFS.open(OFFLINE_LOG_LEGACY, "r");
  if (f && f.size() <= 20480) {
    const String icerik = f.readString();
    f.close();
    JsonDocument doc;
    if (!deserializeJson(doc, icerik) && doc.is<JsonArray>()) {
      for (JsonObject kayit : doc.as<JsonArray>()) {
        offlineLogEkle(
          kayit["trigger_type"] | "offline_sync",
          kayit["user_name"] | "",
          kayit["apartment_label"] | "",
          static_cast<uint32_t>(kayit["epoch_time"] | 0UL),
          0
        );
      }
    }
  } else if (f) {
    f.close();
  }
  LittleFS.remove(OFFLINE_LOG_LEGACY);
}

inline void offlineLogInit() {
  if (LittleFS.begin(false)) {
    gOfflineLogFsHazir = true;
    Serial.println("Offline Log Sistemi: LittleFS baslatildi.");
  } else {
    Serial.println("Offline Log Sistemi: LittleFS mount basarisiz, formatlaniyor...");
    if (LittleFS.format() && LittleFS.begin(true)) {
      gOfflineLogFsHazir = true;
      Serial.println("Offline Log Sistemi: LittleFS formatlandi ve baslatildi.");
    } else {
      gOfflineLogFsHazir = false;
      Serial.println("Offline Log Sistemi: LittleFS baslatilamadi!");
      return;
    }
  }

  // Acilis kimligi: client_log_id icinde kullanilir (ayni cihazda acilislar arasi benzersizlik).
  // NVS acilis sayaci tek basina yetmez: NVS silinir / erase_flash yapilirsa sayac 1'e doner ve "<uid>-1-1" gibi kimlikler eski
  // kayitlarla cakisir (sunucu yeni kaydi "duplicate" sayip ack eder = sessiz veri kaybi). Bu yuzden 11 bit rastgele eklenir:
  // bootId = (rastgele11 << 20) | (sayac & 0xFFFFF)  -> en fazla 31 bit (String::toInt() ile guvenle ayristirilir; kimlik
  // "<12 hane uid>-<<=10 hane>-<<=10 hane>" <= 34 karakter, sunucu deseni /^[A-Za-z0-9._:-]{1,64}$/).
  Preferences prefs;
  if (prefs.begin(OFFLINE_LOG_PREFS, false)) {
    const uint32_t sayac = prefs.getUInt("boot", 0) + 1;
    prefs.putUInt("boot", sayac);
    prefs.end();
    gOfflineLogBootId = ((esp_random() & 0x7FFUL) << 20) | (sayac & 0xFFFFFUL);
  } else {
    gOfflineLogBootId = esp_random() & 0x7FFFFFFF;
  }
  gOfflineLogBatchSayac = esp_random() & 0x00FFFFFF;

  // Kesintiye ugramis atomik yazma: gecici dosya var ve asil dosya yoksa geri al
  if (LittleFS.exists(OFFLINE_LOG_TMP)) {
    if (!LittleFS.exists(OFFLINE_LOG_FILE)) {
      LittleFS.rename(OFFLINE_LOG_TMP, OFFLINE_LOG_FILE);
    } else {
      LittleFS.remove(OFFLINE_LOG_TMP);
    }
  }

  offlineLogEskiBicimiTasi();

  if (LittleFS.exists(OFFLINE_LOG_FILE)) {
    File f = LittleFS.open(OFFLINE_LOG_FILE, "r");
    if (f) {
      gOfflineLogBekleyen = f.size() > 0;
      f.close();
    }
  }
}

// MQTT yeniden baglaninca ack bekleyen batch'i serbest birak: hemen yeniden gonderilsin (sunucu idempotent).
inline void offlineLogMqttBaglandi() {
  gOfflineLogBatchId = 0;
  gSonLogSenkronizasyonMs = 0;
}

// Dosyanin basindan bir batch hazirlar. payload: {"batch_id":N,"logs":[...]}; satir: tuketilen (silinecek) satir sayisi.
inline bool offlineLogBatchHazirla(uint32_t batchId, String& payload, size_t& satir) {
  satir = 0;
  File f = LittleFS.open(OFFLINE_LOG_FILE, "r");
  if (!f) {
    return false;
  }

  String kayitlar;
  size_t kayitSayisi = 0;
  const uint32_t simdiEpoch = epochSimdi();

  while (f.available()) {
    String ham = f.readStringUntil('\n');
    ham.trim();
    if (ham.length() > 400) {
      // Bozuk/cok uzun satir: tuket (ack ile silinir) ama gonderme
      satir += 1;
      continue;
    }
    if (kayitSayisi > 0 && kayitlar.length() + ham.length() + 1 > OFFLINE_LOG_BATCH_BUDGET) {
      break;  // bu satir sonraki batch'te
    }
    satir += 1;
    if (ham.isEmpty()) {
      continue;
    }

    JsonDocument doc;
    if (deserializeJson(doc, ham) || !doc.is<JsonObject>()) {
      continue;  // bozuk satir: atla (batch ack'inde silinir)
    }

    // Saat senkron degilken yazilan ayni acilis kayitlarinin epoch'unu duzelt
    if (simdiEpoch != 0 && (doc["epoch"] | 0UL) == 0) {
      const String id = doc["client_log_id"] | "";
      const int p1 = id.indexOf('-');
      const int p2 = id.indexOf('-', p1 + 1);
      if (p1 > 0 && p2 > p1 && static_cast<uint32_t>(id.substring(p1 + 1, p2).toInt()) == gOfflineLogBootId) {
        const uint32_t bootMs = doc["boot_ms"] | 0UL;
        const uint32_t gecen = (millis() - bootMs) / 1000UL;
        if (gecen < simdiEpoch) {
          doc["epoch"] = simdiEpoch - gecen;
        }
      }
    }

    String duz;
    serializeJson(doc, duz);
    if (kayitSayisi > 0) {
      kayitlar += ',';
    }
    kayitlar += duz;
    kayitSayisi += 1;
  }
  f.close();

  if (satir == 0) {
    return false;
  }
  if (kayitSayisi == 0) {
    // Hepsi bozuk satirdi: ack beklemeden temizle
    offlineLogDosyayiYenile(satir, 0);
    return false;
  }

  payload = "{\"batch_id\":" + String(batchId) + ",\"logs\":[" + kayitlar + "]}";
  return true;
}

// Sunucudan {"action":"logs_ack","batch_id":N} geldi: o batch'in satirlarini sil. true: silindi
inline bool offlineLogAckIsle(uint32_t batchId) {
  if (batchId == 0 || batchId != gOfflineLogBatchId || gOfflineLogBatchSatir == 0) {
    return false;
  }
  const size_t satir = gOfflineLogBatchSatir;
  gOfflineLogBatchId = 0;
  gOfflineLogBatchSatir = 0;
  if (!gOfflineLogFsHazir || !LittleFS.exists(OFFLINE_LOG_FILE)) {
    gOfflineLogBekleyen = false;
    return true;
  }

  if (!offlineLogDosyayiYenile(satir, 0)) {
    Serial.println("Offline Log: ack sonrasi dosya guncellenemedi.");
    return false;
  }

  gOfflineLogAckTimeoutMs = OFFLINE_LOG_ACK_TIMEOUT_MIN_MS;
  gSonLogSenkronizasyonMs = 0;  // siradaki batch hemen gitsin
  if (LittleFS.exists(OFFLINE_LOG_FILE)) {
    File f = LittleFS.open(OFFLINE_LOG_FILE, "r");
    gOfflineLogBekleyen = f && f.size() > 0;
    if (f) {
      f.close();
    }
  } else {
    gOfflineLogBekleyen = false;
  }
  Serial.println("Offline Log: batch sunucu tarafindan onaylandi, yerel kayitlar silindi.");
  return true;
}

inline void offlineLogSenkronizeEt() {
  const unsigned long simdikiMs = millis();
  if (simdikiMs - gSonLogSenkronizasyonMs < OFFLINE_LOG_SYNC_INTERVAL_MS) {
    return;
  }
  gSonLogSenkronizasyonMs = simdikiMs;

  if (!gOfflineLogFsHazir || !gOfflineLogBekleyen || !wifiHazirMi() || !client.connected()) {
    return;
  }

  if (gOfflineLogBatchId != 0) {
    if (simdikiMs - gOfflineLogBatchGonderimMs < gOfflineLogAckTimeoutMs) {
      return;  // ack bekleniyor
    }
    // Ack gelmedi: ayni kayitlari yeni batch olarak tekrar yayinla (sunucu idempotent); aralik katlanarak artar.
    gOfflineLogBatchId = 0;
    gOfflineLogAckTimeoutMs = min(gOfflineLogAckTimeoutMs * 2, OFFLINE_LOG_ACK_TIMEOUT_MAX_MS);
  }

  if (!LittleFS.exists(OFFLINE_LOG_FILE)) {
    gOfflineLogBekleyen = false;
    return;
  }

  gOfflineLogBatchSayac += 1;
  if (gOfflineLogBatchSayac == 0) {
    gOfflineLogBatchSayac = 1;
  }
  String payload;
  size_t satir = 0;
  if (!offlineLogBatchHazirla(gOfflineLogBatchSayac, payload, satir)) {
    if (!LittleFS.exists(OFFLINE_LOG_FILE)) {
      gOfflineLogBekleyen = false;
    }
    return;
  }

  const String topic = "device/" + cihazUniqueId() + "/logs";
  if (client.publish(topic.c_str(), payload.c_str(), false)) {
    gOfflineLogBatchId = gOfflineLogBatchSayac;
    gOfflineLogBatchSatir = satir;
    gOfflineLogBatchGonderimMs = simdikiMs;
    Serial.print("Offline Log: batch yayinlandi, ack bekleniyor (satir=");
    Serial.print(satir);
    Serial.println(")");
  } else {
    Serial.println("Offline Log: batch yayinlanamadi (MQTT).");
  }
}

#endif
