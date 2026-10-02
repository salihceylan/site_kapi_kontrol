#ifndef MQTT_BAGLANTI_H
#define MQTT_BAGLANTI_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>

#if defined(BOARD_ESP32_WROOM_RELAY)
#include "admin_pin.h"
#endif
#include "display_protocol.h"
#include "display_uart.h"
#include "gm60_scanner.h"
#include "offline_log.h"
#include "ota_guncelleme.h"
#include "role_kontrol.h"
#include "tls_kok_sertifika.h"
#include "wifi_baglanti.h"

extern PubSubClient client;
extern WiFiClientSecure espClientSecure;

inline const char* MQTT_DEFAULT_SERVER = "mqtt.gudeteknoloji.com.tr";
constexpr uint16_t MQTT_DEFAULT_PORT = 8883;
inline const char* MQTT_DEFAULT_USER = "";
inline const char* MQTT_DEFAULT_PASS = "";

// C5: TLS sertifika dogrulamasi ACIK (setCACert). WiFiClientSecure::setTimeout / setHandshakeTimeout SANIYE cinsindendir.
inline constexpr size_t MQTT_BUFFER_SIZE = 1024;           // state/event/logs yayinlari icin (varsayilan 256 yetmez)
inline constexpr uint32_t MQTT_TLS_TIMEOUT_S = 5;
inline constexpr uint32_t MQTT_TLS_HANDSHAKE_TIMEOUT_S = 10;
inline constexpr uint16_t MQTT_SOCKET_TIMEOUT_S = 5;
inline constexpr uint16_t MQTT_KEEPALIVE_S = 15;
inline constexpr unsigned long MQTT_RECONNECT_MIN_MS = 2000;
inline constexpr unsigned long MQTT_RECONNECT_MAX_MS = 60000;
inline constexpr unsigned long MQTT_UNAUTH_BEKLEME_MS = 5UL * 60UL * 1000UL;   // rc=4/5 (yetkisiz): uzun bekleme
inline constexpr unsigned long MQTT_SAAT_BEKLEME_MS = 5000;                    // NTP saati gelene kadar tekrar kontrol
inline constexpr int64_t MQTT_PULSE_MAX_YAS_S = 60;                            // |now - requested_at| siniri
inline constexpr uint32_t MQTT_ONKONTROL_TIMEOUT_MS = 400;                     // broker IP'sine TCP on-kontrolu (DNS/TLS yok)
inline constexpr uint8_t MQTT_ONKONTROL_ATLAMA_MAX = 3;                        // art arda 3 on-kontrol hatasindan sonra 4. deneme TAM connect
inline constexpr unsigned long MQTT_KENDINI_TOPARLA_MS = 6UL * 60UL * 60UL * 1000UL;  // 6 saat hic baglanilamazsa kontrollu yeniden baslat
inline constexpr char MQTT_SYS_PREFS[] = "ahbu_sys";                           // yeniden baslatma nedeni isareti (NVS)
inline constexpr char MQTT_SYS_PREF_RESET[] = "rst";

// Yeniden baglanma beklemesi: {baslangic damgasi (denemenin BITISI), sure}. Karsilastirma ISARETSIZ (millis() - baslangic < sure) ve
// sure dolunca bekleme KILITLI sekilde sifirlanir (mqttBeklemeSuruyorMu, her loop'ta cagrilir). Eskiden saklanan "millis() + sure" bitis
// damgasi ISARETLI karsilastiriliyordu: baglantiyken damga bayatlar, ~24,86 gun sonra "gelecek" sayilir ve kopma sonrasi yeniden
// baglanma ~25 gun kilitlenirdi. Simdi baglantiyken sure=0'dir; bayat damga hicbir bekleme uretemez.
inline unsigned long gMqttBeklemeBaslangicMs = 0;
inline unsigned long gMqttBeklemeSureMs = 0;     // 0: bekleme yok
inline uint8_t gMqttBasarisizSayac = 0;
inline IPAddress gMqttSonIp;                     // son basarili baglantidaki broker IP'si (0.0.0.0: bilinmiyor)
inline uint8_t gMqttOnKontrolHataSayac = 0;      // son tam connect'ten beri art arda TCP on-kontrol hatasi
inline unsigned long gMqttSaglikliMs = 0;        // son "MQTT bagli / bagli olmasi beklenmeyen" an (kendini toparlama sayaci)
inline uint8_t gMqttBootNedeni = 0;              // 1: onceki acilis MQTT kendini toparlama yeniden baslatmasiydi
inline uint8_t gMqttYayinHataArdisik = 0;
inline String gMqttConfiguredHost = MQTT_DEFAULT_SERVER;
inline uint16_t gMqttConfiguredPort = MQTT_DEFAULT_PORT;

inline void mqttBeklemeKur(unsigned long sureMs) {
  gMqttBeklemeBaslangicMs = millis();
  gMqttBeklemeSureMs = sureMs;
}

// true: yeniden baglanma beklemesi suruyor. Sure dolunca bekleme sifirlanir (kilitli); mqttLoopHandler her loop'ta cagirir.
inline bool mqttBeklemeSuruyorMu() {
  if (gMqttBeklemeSureMs == 0) {
    return false;
  }
  if (millis() - gMqttBeklemeBaslangicMs >= gMqttBeklemeSureMs) {
    gMqttBeklemeSureMs = 0;
    return false;
  }
  return true;
}

// Son islenen pulse request_id'leri (QoS1 tekrar tesliminde cift tetiklemeyi onler)
inline char gPulseIdHalka[8][33] = {};
inline uint8_t gPulseIdSira = 0;

inline String mqttDeviceTopic(const char* suffix) {
  return "device/" + cihazUniqueId() + "/" + suffix;
}

// Tum yayinlar buradan gecer: donus degeri kontrol edilir; ardisik hatada baglanti yenilenir.
inline bool mqttYayinla(const char* topic, const char* payload, bool retained) {
  if (!client.connected()) {
    return false;
  }
  const bool ok = client.publish(topic, payload, retained);
  if (ok) {
    gMqttYayinHataArdisik = 0;
    return true;
  }
  Serial.print("MQTT publish basarisiz: ");
  Serial.println(topic);
  gMqttYayinHataArdisik += 1;
  if (gMqttYayinHataArdisik >= 5) {
    gMqttYayinHataArdisik = 0;
    client.disconnect();  // bozuk baglanti: mqttLoopHandler geri cekilmeyle yeniden baglanir
  }
  return false;
}

inline bool mqttPublishAvailability(const char* value) {
  const String deviceAvailabilityTopic = mqttDeviceTopic("availability");
  return mqttYayinla(deviceAvailabilityTopic.c_str(), value, true);
}

inline bool mqttPublishState(bool locked) {
  JsonDocument doc;
  doc["locked"] = locked;
  doc["firmware_version"] = OTA_CURRENT_VERSION;
  doc["hardware_target"] = OTA_TARGET;
  doc["target"] = OTA_TARGET;
  doc["ota_status"] = otaLastStatus();
  doc["ota_last_version"] = otaLastVersion();
  doc["wifi_rssi"] = wifiSinyalDbm();
  doc["wifi_signal_percent"] = wifiSinyalYuzde();
  doc["local_ip"] = wifiIpAdresi();
  doc["local_control_port"] = YEREL_KAPI_KONTROL_PORT;
  doc["local_control_available"] = wifiHasLocalControlToken();
#if defined(BOARD_ESP32_WROOM_RELAY)
  doc["camera_connected"] = gm60Bagli;
  doc["camera_status"] = gm60Bagli ? "ready" : "not_detected";
  doc["admin_pin_set"] = adminPinTanimliMi();  // PIN'in kendisi ASLA yayinlanmaz
#endif

  String payload;
  serializeJson(doc, payload);
  const String deviceStateTopic = mqttDeviceTopic("state");
  return mqttYayinla(deviceStateTopic.c_str(), payload.c_str(), true);
}

inline bool mqttPublishEvent(const char* eventName, const char* detail = "", const char* requestId = nullptr) {
  JsonDocument doc;
  doc["event"] = eventName;
  if (detail != nullptr && detail[0] != '\0') {
    doc["detail"] = detail;
  }
  if (requestId != nullptr && requestId[0] != '\0') {
    doc["request_id"] = requestId;
  }
  doc["ms"] = millis();
  doc["firmware_version"] = OTA_CURRENT_VERSION;
  doc["hardware_target"] = OTA_TARGET;
  doc["target"] = OTA_TARGET;
  doc["ota_status"] = otaLastStatus();
  if (otaOlayIsKimligiTasirMi(eventName)) {
    otaIsKimligiEkle(doc);  // OTA olaylari (ota_*): sunucudaki is takibi icin ota_job_id yansitilir (kimlik yoksa alan eklenmez)
  }

  String payload;
  serializeJson(doc, payload);
  const String deviceEventTopic = mqttDeviceTopic("event");
  return mqttYayinla(deviceEventTopic.c_str(), payload.c_str(), false);
}

inline void mqttPublishOtaEvent(const char* eventName, const char* detail) {
  if (!client.connected()) {
    return;
  }
  mqttPublishEvent(eventName, detail);
  mqttPublishState(gDoorLocked);
}

inline bool mqttBagliMi() {
  return client.connected();
}

// C7: qr_verify yayinina request_id eklenir; sunucu qr_result'a ayni request_id'yi geri koyar.
inline bool mqttPublishQrVerify(const String& qrToken, uint32_t requestId) {
  if (!client.connected()) {
    return false;
  }
  JsonDocument doc;
  doc["token"] = qrToken;
  doc["timestamp"] = millis();
  doc["request_id"] = requestId;
  String payload;
  serializeJson(doc, payload);
  const String topic = mqttDeviceTopic("qr_verify");
  return mqttYayinla(topic.c_str(), payload.c_str(), false);
}

// Ekran QR token'i: retained KULLANILMAZ (eski/bayat token yeni abonelere iletilmesin); token seriye yazdirilmaz.
inline bool mqttPublishScreenQr(const String& token, int validSeconds = 30) {
  if (!client.connected()) {
    return false;
  }
  JsonDocument doc;
  doc["token"] = token;
  doc["valid_seconds"] = validSeconds;
  doc["device_uid"] = cihazUniqueId();
  doc["timestamp_ms"] = millis();
  String payload;
  serializeJson(doc, payload);
  const String topic = mqttDeviceTopic("screen_qr");
  return mqttYayinla(topic.c_str(), payload.c_str(), false);
}

inline bool shouldTriggerOtaCheck(const String& message) {
  return message == "ota" || message == "ota_check";
}

// requested_at (S4a/C5): epoch SANIYE (sayi). Sayi degilse (eski uygulama yolu ISO metin gonderebilir) veya yoksa
// "yok" sayilir (0) ve pulse geriye donuk uyum icin KABUL edilir. Milisaniye (>1e11) de tolere edilir.
inline int64_t mqttReadRequestedAt(JsonVariantConst v) {
  if (v.isNull() || !v.is<double>()) {
    return 0;
  }
  double x = v.as<double>();
  if (x > 1e11) {
    x /= 1000.0;  // milisaniye
  }
  return x > 0 ? static_cast<int64_t>(x) : 0;
}

inline void mqttReadRequestId(JsonVariantConst v, char* out, size_t outLen) {
  out[0] = '\0';
  if (v.is<const char*>()) {
    strncpy(out, v.as<const char*>(), outLen - 1);
    out[outLen - 1] = '\0';
  } else if (v.is<double>()) {
    snprintf(out, outLen, "%lld", static_cast<long long>(v.as<double>()));
  }
}

// true: bu request_id yakinda islendi (tekrar). Degilse halkaya kaydeder.
inline bool mqttPulseIdTekrarMi(const char* id) {
  if (id == nullptr || id[0] == '\0') {
    return false;
  }
  for (int i = 0; i < 8; i += 1) {
    if (strncmp(gPulseIdHalka[i], id, sizeof(gPulseIdHalka[i]) - 1) == 0) {
      return true;
    }
  }
  strncpy(gPulseIdHalka[gPulseIdSira], id, sizeof(gPulseIdHalka[0]) - 1);
  gPulseIdHalka[gPulseIdSira][sizeof(gPulseIdHalka[0]) - 1] = '\0';
  gPulseIdSira = (gPulseIdSira + 1) % 8;
  return false;
}

// C5: pulse komutu. requested_at ile saat farki > 60 sn ise reddedilir (yalniz firmware saati senkronsa).
inline void mqttHandlePulse(JsonDocument& json) {
  char rid[33];
  mqttReadRequestId(json["request_id"], rid, sizeof(rid));

  const int64_t requestedAt = mqttReadRequestedAt(json["requested_at"]);
  const uint32_t simdi = epochSimdi();
  if (requestedAt > 0 && simdi != 0) {
    const int64_t fark = static_cast<int64_t>(simdi) - requestedAt;
    if (fark > MQTT_PULSE_MAX_YAS_S || fark < -MQTT_PULSE_MAX_YAS_S) {
      Serial.println("MQTT pulse REDDEDILDI: requested_at zaman penceresi disinda.");
      mqttPublishEvent("pulse_rejected", "stale", rid);
      return;
    }
  }

  if (mqttPulseIdTekrarMi(rid)) {
    Serial.println("MQTT pulse yok sayildi: ayni request_id tekrar geldi.");
    return;
  }

  if (!roleTetikle()) {
    mqttPublishEvent("pulse_rejected", "role_busy", rid);
    return;
  }
  gDoorLocked = false;
  displayUartSend(CMD_DOOR_OPENED);
  mqttPublishState(gDoorLocked);
  mqttPublishEvent("pulse_started", "", rid);
}

// C7: sunucu sonucu. request_id varsa bekleyen istekle eslesmeli; eslesmeyen/gec gelen sonuc yok sayilir.
inline void mqttHandleQrResult(const String& message) {
  JsonDocument resDoc;
  if (deserializeJson(resDoc, message)) {
    return;
  }
  const bool idVar = resDoc["request_id"].is<double>();
  const uint32_t id = idVar ? static_cast<uint32_t>(resDoc["request_id"].as<double>()) : 0;
  if (!gm60SunucuYanitiKabulEt(idVar, id)) {
    Serial.println("[MQTT QR Sonuc] eslesmeyen/eski sonuc yok sayildi.");
    return;
  }

  const bool allowed = resDoc["allowed"] | false;
  const char* reason = resDoc["reason"] | "";
  Serial.print("[MQTT QR Sonuc] Izin: ");
  Serial.print(allowed ? "ONAYLANDI" : "REDDEDILDI");
  Serial.print(" | Neden: ");
  Serial.println(reason);
  if (allowed) {
    // Kapi acma pulse'i ayrica gelir ve ekran bildirimini oradan yapar; role zaten aktifse hemen goster.
    if (roleAktif) {
      displayUartSend(CMD_DOOR_OPENED);
    }
  } else {
    displayUartSend(CMD_QR_DENIED);
    // Sunucu reddi: ayni QR hemen yeniden denenebilsin (5 sn debounce yine gecerli); onaylanan token 8 sn tekrar penceresinde kalir
    gm60AyniQrYenidenDenensin();
  }
}

inline void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // PubSubClient yayin yaparken ayni tamponu kullandigindan once icerigi kopyala.
  String message;
  message.reserve(length);
  for (unsigned int i = 0; i < length; i++) {
    message += static_cast<char>(payload[i]);
  }

  const String deviceCmdTopic = mqttDeviceTopic("cmd");
  const String qrResultTopic = mqttDeviceTopic("qr_result");
  const String gelenTopic(topic);

  if (gelenTopic == qrResultTopic) {
    mqttHandleQrResult(message);
    return;
  }

  if (gelenTopic != deviceCmdTopic) {
    return;
  }

  // Komut govdesi (token/PIN icerebilir) seriye YAZDIRILMAZ.
  Serial.print("MQTT komut alindi (");
  Serial.print(length);
  Serial.println(" bayt)");

  if (shouldTriggerOtaCheck(message)) {
    otaIsKimligiTemizle();  // dize komutu is kimligi tasimaz: onceki isin kimligi bu kontrole yapismasin
    otaTalepEt("mqtt");
    mqttPublishEvent("ota_check_requested");
    return;
  }

  JsonDocument doc;
  if (deserializeJson(doc, message) || !doc.is<JsonObject>()) {
    return;
  }

  const String action = String(doc["action"] | "");

  if (action == "pulse") {
    mqttHandlePulse(doc);
  } else if (action == "ota_check") {
    if (doc["retry"] | false) {
      otaDenemeSayacinaSifirla();
    }
    // Is kimligi (ota_job_id; metin/pozitif tamsayi, <=40 karakter) RAM'de saklanir ve OTA olaylarina (ota_*) yansitilir; yok/gecersizse
    // onceki kimlik temizlenir. Sunucu olay JSON'unda ota_job_id'yi bekler (mqtt_bridge.js recordOtaJobDeviceEvent).
    otaIsKimligiAyarla(doc["ota_job_id"]);
    // Toplu is (ota_job_id var): cihazlar ayni anda manifest + 1,8 MB indirmeye girmesin; MAC tabanli 0-120 sn gecikmeyle planlanir.
    // Tekil/elle talepte (ota_job_id null/yok) kontrol hemen calisir.
    otaTalepEt("mqtt", !doc["ota_job_id"].isNull());
    mqttPublishEvent("ota_check_requested");
  } else if (action == "local_control_config") {
    // C4: yerel kontrol anahtari NVS'e yazilir (MQTT parolasindan ayri)
    const int sonuc = wifiPersistLocalToken(String(doc["local_control_token"] | ""));
    if (sonuc == 2) {
      Serial.println("Yerel kontrol anahtari guncellendi.");
      mqttPublishState(gDoorLocked);
    } else if (sonuc == 0) {
      mqttPublishEvent("local_control_config_rejected", "invalid_token");
    }
  } else if (action == "admin_pin_config") {
#if defined(BOARD_ESP32_WROOM_RELAY)
    // C10: yonetici PIN'i (6 hane); bos metin PIN'i siler (menu kilitlenir). PIN loglanmaz/yayinlanmaz.
    AdminPinRed pinRed = ADMIN_PIN_RED_BICIM;  // metin degilse adminPinAyarla cagrilmaz: bicim hatasi
    if (doc["admin_pin"].is<const char*>() && adminPinAyarla(String(doc["admin_pin"].as<const char*>()), &pinRed)) {
      Serial.println("Yonetici PIN'i guncellendi.");
      mqttPublishEvent("admin_pin_configured");
      mqttPublishState(gDoorLocked);
    } else {
      // Ret NEDENI yazilir (weak_pin: zayif/tahmin edilebilir | invalid_pin: 6 rakam degil); PIN degeri seriye/olaya YAZILMAZ
      Serial.println(pinRed == ADMIN_PIN_RED_ZAYIF ? "Yonetici PIN'i reddedildi (MQTT): zayif PIN." : "Yonetici PIN'i reddedildi (MQTT): gecersiz bicim.");
      mqttPublishEvent("admin_pin_config_rejected", adminPinRedMetni(pinRed));
    }
#else
    mqttPublishEvent("admin_pin_config_rejected", "unsupported_target");
#endif
  } else if (action == "logs_ack") {
    offlineLogAckIsle(static_cast<uint32_t>(doc["batch_id"] | 0UL));
  }
}

inline unsigned long mqttGeriCekilmeMs(int rc) {
  unsigned long taban;
  if (rc == MQTT_CONNECT_BAD_CREDENTIALS || rc == MQTT_CONNECT_UNAUTHORIZED) {
    taban = MQTT_UNAUTH_BEKLEME_MS;
  } else {
    const uint8_t kaydir = gMqttBasarisizSayac > 5 ? 5 : gMqttBasarisizSayac;
    taban = MQTT_RECONNECT_MIN_MS << kaydir;
    if (taban > MQTT_RECONNECT_MAX_MS) {
      taban = MQTT_RECONNECT_MAX_MS;
    }
  }
  return taban + (esp_random() % (taban / 4 + 1));  // %25'e kadar jitter
}

// Internet kesikken client.connect() DNS (<= ~15 sn) + TCP (5 sn) + TLS (10 sn) yuzunden loop'u 5-15 sn bloklar; bu surede yerel
// UDP/HTTP/QR/ekran cevapsiz kalir. Broker IP'si biliniyorsa once bu kisa TCP on-kontrolu yapilir (DNS ve TLS yok).
inline bool mqttTcpOnKontrol(const IPAddress& ip, uint16_t port) {
  WiFiClient sonda;
  esp_task_wdt_reset();
  const bool acildi = sonda.connect(ip, port, static_cast<int32_t>(MQTT_ONKONTROL_TIMEOUT_MS)) != 0;
  sonda.stop();
  esp_task_wdt_reset();
  return acildi;
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
    mqttBeklemeKur(10000);
    return false;
  }
  // TLS sertifika dogrulamasi gecerli sistem saati ister (NTP). Saat gelmeden deneme yapma.
  if (!zamanSenkronMu()) {
    mqttBeklemeKur(MQTT_SAAT_BEKLEME_MS);
    return false;
  }

  // On-kontrol: son basarili broker IP'si biliniyorsa ve art arda MQTT_ONKONTROL_ATLAMA_MAX hata yoksa once kisa TCP denemesi.
  // Acilamazsa tam connect'e (DNS+TLS, uzun blok) GIRILMEZ; normal geri cekilme uygulanir. Sonraki (4.) deneme ya da IP bilinmiyorsa
  // tam connect yapilir: broker IP'si degisirse / ilk acilista kendini iyilestirir.
  if (static_cast<uint32_t>(gMqttSonIp) != 0 && gMqttOnKontrolHataSayac < MQTT_ONKONTROL_ATLAMA_MAX) {
    if (!mqttTcpOnKontrol(gMqttSonIp, gMqttConfiguredPort)) {
      gMqttOnKontrolHataSayac += 1;
      if (gMqttBasarisizSayac < 255) {
        gMqttBasarisizSayac += 1;
      }
      Serial.println("MQTT: broker TCP on-kontrolu basarisiz (ag/internet yok?); tam baglanti denenmedi.");
      mqttBeklemeKur(mqttGeriCekilmeMs(0));
      return false;
    }
  }
  gMqttOnKontrolHataSayac = 0;  // tam connect'e giriliyor (on-kontrol gecti ya da atlandi)

  const String clientId = "AHBU-" + cihazUniqueId();
  const String deviceAvailabilityTopic = mqttDeviceTopic("availability");
  const String mqttUser = wifiMqttUser(MQTT_DEFAULT_USER);
  const String mqttPass = wifiMqttPassword(MQTT_DEFAULT_PASS);
  Serial.print("MQTT baglaniyor (id=");
  Serial.print(clientId);
  Serial.print(" user=");
  Serial.print(mqttUser);
  Serial.print(" host=");
  Serial.print(gMqttConfiguredHost);
  Serial.print(")...");

  esp_task_wdt_reset();
  const bool baglandi = client.connect(clientId.c_str(), mqttUser.c_str(), mqttPass.c_str(), deviceAvailabilityTopic.c_str(), 1, true, "offline");
  esp_task_wdt_reset();

  if (baglandi) {
    Serial.println("baglandi");
    gMqttBasarisizSayac = 0;
    gMqttYayinHataArdisik = 0;
    gMqttBeklemeSureMs = 0;
    // Sonraki kopmada DNS'siz TCP on-kontrolu icin broker IP'sini sakla (soket acik: getpeername; ag islemi/DNS yok)
    if (espClientSecure.connected()) {
      const IPAddress uzakIp = espClientSecure.remoteIP();
      if (static_cast<uint32_t>(uzakIp) != 0) {
        gMqttSonIp = uzakIp;
      }
    }
    const String deviceCmdTopic = mqttDeviceTopic("cmd");
    const String qrResultTopic = mqttDeviceTopic("qr_result");
    const bool abone = client.subscribe(deviceCmdTopic.c_str(), 1) && client.subscribe(qrResultTopic.c_str(), 1);
    if (!abone) {
      Serial.println("MQTT abonelik basarisiz; baglanti yenilenecek.");
      client.disconnect();
      mqttBeklemeKur(mqttGeriCekilmeMs(0));
      return false;
    }
    mqttPublishAvailability("online");
    mqttPublishState(gDoorLocked);
    mqttPublishEvent("device_connected");
    if (gMqttBootNedeni != 0) {
      // Onceki acilis MQTT kendini toparlama yeniden baslatmasiydi: bir kez raporla (saha tanilamasi)
      mqttPublishEvent("self_recovery_restart", "mqtt_6h");
      gMqttBootNedeni = 0;
    }
    offlineLogMqttBaglandi();
    return true;
  }

  const int rc = client.state();
  Serial.print("Hata rc=");
  Serial.print(rc);
  char tlsHata[100] = {};
  if (espClientSecure.lastError(tlsHata, sizeof(tlsHata) - 1) != 0 && tlsHata[0] != '\0') {
    Serial.print(" tls=");
    Serial.print(tlsHata);
  }
  Serial.println(" tekrar denenecek");
  if (gMqttBasarisizSayac < 255) {
    gMqttBasarisizSayac += 1;
  }
  if (rc > 0) {
    // Broker CONNACK ile reddetti (kimlik/yetki/sunucu mesgul): TCP+TLS+MQTT katmanlari calisiyor, cihaz arizasi degil;
    // yeniden baslatma bunu duzeltmez -> kendini toparlama sayaci tazelenir.
    gMqttSaglikliMs = millis();
  }
  // Bekleme, denemenin BITISINDEN itibaren olculur (baglanti denemesi bloklayici olabilir).
  mqttBeklemeKur(mqttGeriCekilmeMs(rc));
  return false;
}

// OTA indirmesinden once: MQTT TLS oturumunu kapat (mbedtls tamponlari ~33 KB serbest kalir; C3'te ikinci TLS oturumu bellek
// yetersizliginden dusebilir). Temiz DISCONNECT'te broker LWT'yi yayinlamaz: retained availability=offline acikca yayinlanir.
inline void mqttOtaOncesiKapat() {
  if (!client.connected()) {
    return;
  }
  mqttPublishAvailability("offline");
  client.disconnect();
  Serial.println("MQTT: OTA indirmesi icin oturum kapatildi.");
}

// OTA bitince (basari ya da hata): bekleme olmadan hemen yeniden baglan; ota_success / ota_failed olayi ve durum yayini sunucuya
// ulassin. Baglanamazsa mqttReconnect normal geri cekilmeyi kurar ve mqttLoopHandler devam ettirir.
inline void mqttOtaSonrasiYenidenBaglan() {
  gMqttBeklemeSureMs = 0;
  if (wifiHazirMi() && !client.connected()) {
    mqttReconnect();
  }
}

// Yeniden baslatma nedeni isareti (NVS): kendini toparlama yeniden baslatmasindan once yazilir, acilista okunup silinir.
inline void mqttBootNedeniOku() {
  Preferences prefs;
  if (!prefs.begin(MQTT_SYS_PREFS, false)) {
    return;
  }
  gMqttBootNedeni = prefs.getUChar(MQTT_SYS_PREF_RESET, 0);
  if (gMqttBootNedeni != 0) {
    prefs.remove(MQTT_SYS_PREF_RESET);
  }
  prefs.end();
}

// Kendini toparlama: MQTT kimligi tanimli + Wi-Fi hazir oldugu halde 6 saatten uzun SURE HIC baglanilamadiysa (heap parcalanmasi,
// TLS/lwIP ya da surucu takilmasi kalici olabilir) kontrollu ESP.restart(). Yeniden baslatma role pulse'i URETMEZ (roleSetup() setup'in
// ILK satiri; pin pasif seviyeye cekilir). Sayac her loop'ta "son saglikli an" ile taze tutulur: baglantiyken / baglanti beklenmezken
// (Wi-Fi yok, kimlik yok, BLE provisioning) surekli yenilenir; bayat damga ya da 49,7 gunluk millis() tasmasi etki edemez.
// Calisan imaj PENDING_VERIFY ise bu yeniden baslatma bootloader'da onceki imaja geri donusu (rollback) tetikler: istenen davranis.
inline void mqttKendiniToparla() {
  const bool baglantiBeklenir = wifiHazirMi() && wifiHasMqttCredentials() && !wifiProvisioningAktifMi();
  if (client.connected() || !baglantiBeklenir) {
    gMqttSaglikliMs = millis();
    return;
  }
  if (millis() - gMqttSaglikliMs < MQTT_KENDINI_TOPARLA_MS) {
    return;
  }
  if (roleAktif || gOtaRunning) {
    return;  // role birakilinca / OTA bitince
  }

  Serial.println("MQTT 6 saattir baglanamadi: kontrollu yeniden baslatma (kendini toparlama).");
  Preferences prefs;
  if (prefs.begin(MQTT_SYS_PREFS, false)) {
    prefs.putUChar(MQTT_SYS_PREF_RESET, 1);
    prefs.end();
  }
  delay(100);
  ESP.restart();
}

inline void mqttSetup() {
  espClientSecure.setCACert(TLS_ROOT_CA);
  espClientSecure.setTimeout(MQTT_TLS_TIMEOUT_S);                       // SANIYE
  espClientSecure.setHandshakeTimeout(MQTT_TLS_HANDSHAKE_TIMEOUT_S);    // SANIYE
  gMqttConfiguredHost = wifiMqttHost(MQTT_DEFAULT_SERVER);
  gMqttConfiguredPort = wifiMqttPort(MQTT_DEFAULT_PORT);
  client.setServer(gMqttConfiguredHost.c_str(), gMqttConfiguredPort);
  client.setCallback(mqttCallback);
  if (!client.setBufferSize(MQTT_BUFFER_SIZE)) {
    Serial.println("MQTT tamponu ayrilamadi; yayinlar basarisiz olabilir!");
  }
  client.setSocketTimeout(MQTT_SOCKET_TIMEOUT_S);
  client.setKeepAlive(MQTT_KEEPALIVE_S);
  otaSetEventPublisher(mqttPublishOtaEvent);
  otaSetMqttHooks(mqttOtaOncesiKapat, mqttOtaSonrasiYenidenBaglan);
  mqttBootNedeniOku();
  gMqttSaglikliMs = millis();
}

inline String mqttAktifSunucu() {
  return gMqttConfiguredHost;
}

inline uint16_t mqttAktifPort() {
  return gMqttConfiguredPort;
}

inline void mqttLoopHandler() {
  // Her loop'ta (Wi-Fi kopukken de) degerlendirilir: sure dolunca bekleme kilitli sekilde sifirlanir
  const bool bekliyor = mqttBeklemeSuruyorMu();

  if (!wifiHazirMi()) {
    if (client.connected()) {
      client.disconnect();
    }
    return;
  }

  if (!client.connected()) {
    if (bekliyor) {
      return;
    }
    if (!mqttReconnect()) {
      return;
    }
  }

  client.loop();
}

// Role birakildi: durum yayini (MQTT bagli degilse atlanir; gDoorLocked guncellemesi cagiranin gorevidir)
inline void mqttNotifyPulseCompleted() {
  if (!client.connected()) {
    return;
  }

  mqttPublishState(gDoorLocked);
  mqttPublishEvent("pulse_completed");
}

#endif
