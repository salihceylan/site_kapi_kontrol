// Ana makine testi: GERCEK mqtt_baglanti.h + ota_guncelleme.h + ota_is_kimligi.h + gm60_scanner.h + admin_pin.h + role_kontrol.h.
// Ag (PubSubClient / HTTPClient / Update / TLS) sahte; saat sahte; JSON gercek (ArduinoJson). Kapsam: D (ota_job_id), B (MQTT admin PIN),
// C (qr_result red dali), E (surumler), S (OTA IMZA: Ed25519 dogrulama, imzasiz/bozuk paket reddi, izinli surum dusurme, kopru).
// Hem WROOM (-DBOARD_ESP32_WROOM_RELAY) hem C3 derlemesi ile calistirilir.
// OTA imzasi: gomulu anahtar (ota_public_key.h) yerine CALISMA ZAMANINDA etiketten turetilen TEST anahtari kullanilir
// (ota_imza.h, OTA_IMZA_TEST_ANAHTARI) - TEST ANAHTARI, uretimde kullanilmaz; depoda gizli anahtar yoktur.
#ifndef OTA_IMZA_TEST_ANAHTARI
#define OTA_IMZA_TEST_ANAHTARI
#endif
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "mbedtls_stub_impl.h"
#include "ed25519_test_imzalayici.h"

#define WIFI_BAGLANTI_H     // agir basliklar etkisiz; ihtiyac duyulan semboller asagida
#define OFFLINE_LOG_H

inline bool g_wifi_ready = true;
inline bool g_mqtt_kimlik = true;
inline bool wifiHazirMi() { return g_wifi_ready; }
inline bool wifiHasMqttCredentials() { return g_mqtt_kimlik; }
inline String wifiMqttHost(const char* f) { return String(f); }
inline uint16_t wifiMqttPort(uint16_t f) { return f; }
inline String wifiMqttUser(const char*) { return String("cihaz-user"); }
inline String wifiMqttPassword(const char*) { return String("cihaz-sifre"); }
inline int wifiSinyalDbm() { return -61; }
inline int wifiSinyalYuzde() { return 70; }
inline String wifiIpAdresi() { return WiFi.localIP().toString(); }
inline bool wifiProvisioningAktifMi() { return false; }
inline String g_local_token = "";
inline bool wifiHasLocalControlToken() { return !g_local_token.isEmpty(); }
inline int wifiPersistLocalToken(const String&) { return 1; }
inline void offlineLogAckIsle(uint32_t) {}
inline void offlineLogMqttBaglandi() {}

WiFiClientSecure espClientSecure;
PubSubClient client(espClientSecure);

static std::vector<std::string> g_ekran;
void displayUartSend(const char* c) { g_ekran.push_back(c); }
void displayUartSend(const String& c) { g_ekran.push_back(c.c_str()); }

// (mutasyon testleri icin once ota_* basliklari: mqtt_baglanti.h bunlari korumayla yeniden include etmez)
#include "ota_is_kimligi.h"
#include "ota_guncelleme.h"
#include "mqtt_baglanti.h"

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL: %s  (satir %d)\n", msg, __LINE__); } } while (0)
#define CHECKF(cond, ...) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static const std::string UID = "240AC4E2E001";
static const std::string T_CMD = "device/" + UID + "/cmd";
static const std::string T_EVT = "device/" + UID + "/event";
static const std::string T_QRR = "device/" + UID + "/qr_result";
static const std::string T_QRV = "device/" + UID + "/qr_verify";
static const std::string T_STATE = "device/" + UID + "/state";
static const std::string T_AVAIL = "device/" + UID + "/availability";

struct Olay { std::string event, detail, payload; bool jobVar = false, jobSayi = false; std::string job; };
static std::vector<Olay> olaylar(size_t from = 0) {
  std::vector<Olay> r;
  for (size_t i = from; i < client.published.size(); i++) {
    const auto& m = client.published[i];
    if (m.topic != T_EVT) continue;
    JsonDocument d;
    if (deserializeJson(d, m.payload)) continue;
    Olay o; o.event = d["event"] | ""; o.detail = d["detail"] | ""; o.payload = m.payload;
    if (!d["ota_job_id"].isNull()) {
      o.jobVar = true;
      if (d["ota_job_id"].is<const char*>()) { o.job = d["ota_job_id"].as<const char*>(); o.jobSayi = false; }
      else { o.job = std::to_string(d["ota_job_id"].as<long long>()); o.jobSayi = true; }
    }
    r.push_back(o);
  }
  return r;
}
static std::string adlar(const std::vector<Olay>& v) { std::string s; for (auto& o : v) s += o.event + (o.jobVar ? "[" + o.job + "]" : std::string("")) + " "; return s; }
static const Olay* bul(const std::vector<Olay>& v, const char* ad) { for (auto& o : v) if (o.event == ad) return &o; return nullptr; }
// Gecici vektor ile guvenli kullanim icin KOPYA dondurur (event bos = bulunamadi)
static Olay bulK(const std::vector<Olay>& v, const char* ad) { for (auto& o : v) if (o.event == ad) return o; return Olay(); }

static void loop_once(uint32_t ms = 1000) {
  g_fake_ms += ms;
  mqttLoopHandler();
  otaCheckAndUpdate();
  otaGecerliligiDogrula(wifiHazirMi() && mqttBagliMi());
}
static void komut(const std::string& json) { client.deliver(T_CMD, json); }

static std::string fw_govde;     // sahte firmware
static std::string fw_sha;
static std::string hexsha(const std::string& d) {
  uint8_t o[32]; refcrypto::sha256(reinterpret_cast<const uint8_t*>(d.data()), d.size(), o); char h[65]; refcrypto::to_hex(o, 32, h); return h;
}
static std::string fw_url() { return std::string("https://api.gudeteknoloji.com.tr/firmware/") + OTA_TARGET + "/app.bin"; }
static void manifest_kur(const std::string& json) { g_http_routes[OTA_MANIFEST_URL] = FakeRoute{200, json, -1}; }
static std::string manifest_json(bool avail, const std::string& ver, const std::string& sha, const std::string& url, const std::string& target = OTA_TARGET, bool usb = false) {
  return std::string("{\"target\":\"") + target + "\",\"update_available\":" + (avail ? "true" : "false") + ",\"usb_required\":" + (usb ? "true" : "false") +
         ",\"version\":\"" + ver + "\",\"url\":\"" + url + "\",\"sha256\":\"" + sha + "\",\"md5\":\"\",\"interval_hours\":24}";
}

// Yeniden baslatma benzetimi: OTA bayraklarini sifirla (cihaz yeniden acilir), MQTT bagli kalir
static void yeniden_acilis() { g_restart_requested = false; gOtaRunning = false; }

// ota_check komutu gonder + OTA akisini tamamlayana kadar dongu (en fazla ~250 sn sahte zaman); olaylari dondurur
static std::vector<Olay> ota_kos(const std::string& cmd, int adim = 250) {
  const size_t mark = client.published.size();
  komut(cmd);
  for (int i = 0; i < adim; i++) { loop_once(1000); if (g_restart_requested) break; }
  return olaylar(mark);
}

// ---- OTA IMZA yardimcilari (TEST anahtari: calisma zamaninda etiketten turetilir, uretimde kullanilmaz) -----------------------------
static ed_test::Anahtar g_yayinci;     // cihaza gomulu sayilan dogru anahtar
static ed_test::Anahtar g_saldirgan;   // sunucuyu ele geciren saldirganin kendi anahtari
static std::string fw_sig_url() { return fw_url() + ".sig"; }
static void test_anahtarini_kur(const uint8_t anahtar[32]) { memcpy(gOtaImzaTestAnahtari, anahtar, 32); gOtaImzaAnahtarDurumu = OTA_ANAHTAR_BILINMIYOR; }
// Ek manifest alanlari: {"a":1,...} govdesinin sonuna ekler
static std::string manifest_ek(const std::string& json, const std::string& ekAlanlar) { return json.substr(0, json.size() - 1) + "," + ekAlanlar + "}"; }
static std::string hexyaz(const std::string& ham) { std::string r; char b[3]; for (unsigned char c : ham) { snprintf(b, sizeof(b), "%02x", c); r += b; } return r; }
static std::string b64yaz(const std::string& ham) {
  static const char B[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string r;
  size_t i = 0;
  for (; i + 2 < ham.size(); i += 3) {
    const uint32_t v = (static_cast<unsigned char>(ham[i]) << 16) | (static_cast<unsigned char>(ham[i + 1]) << 8) | static_cast<unsigned char>(ham[i + 2]);
    r += B[(v >> 18) & 63]; r += B[(v >> 12) & 63]; r += B[(v >> 6) & 63]; r += B[v & 63];
  }
  if (i + 1 == ham.size()) {
    const uint32_t v = static_cast<unsigned char>(ham[i]) << 16;
    r += B[(v >> 18) & 63]; r += B[(v >> 12) & 63]; r += "==";
  }
  return r;
}
// (hedef, surum, govde [, rollback_max]) icin ham 64 baytlik Ed25519 imzasi - imzalayan tarafin yaptigi is
static std::string imza_ham(const ed_test::Anahtar& k, const std::string& hedef, const std::string& surum, const std::string& govde, const char* rollbackMax = nullptr) {
  char yuk[OTA_IMZA_YUK_MAX];
  const std::string sha = hexsha(govde);
  const size_t n = otaImzaYukuOlustur(yuk, sizeof(yuk), hedef.c_str(), surum.c_str(), static_cast<uint32_t>(govde.size()), sha.c_str(), rollbackMax);
  uint8_t imza[64] = {0};
  if (n > 0) ed_test::imzala(k.tohum, reinterpret_cast<const uint8_t*>(yuk), n, imza);
  return std::string(reinterpret_cast<const char*>(imza), 64);
}
// paketin yanina ".sig" dosyasini koyar (sunucu simulasyonu)
static void imza_kur(const std::string& surum, const std::string& govde, const char* rollbackMax = nullptr, const std::string& hedef = OTA_TARGET) {
  g_http_routes[fw_sig_url()] = FakeRoute{200, imza_ham(g_yayinci, hedef, surum, govde, rollbackMax), -1};
}

int main() {
  g_fake_ms = 1000000;
  g_local_token = "tok";
  g_yayinci = ed_test::anahtarCifti("t_mqtt/yayinci");
  g_saldirgan = ed_test::anahtarCifti("t_mqtt/saldirgan");
  test_anahtarini_kur(g_yayinci.genel);

  // ------------------------------------------------------------------------------------------------ E surumler
  { printf("E sürümler (OTA_VERSION_C3 4.4.0, OTA_VERSION_WROOM 5.3.0: OTA imza dogrulamasi / kopru surumu)\n");
    CHECK(std::string(OTA_VERSION_C3) == "4.4.0", "OTA_VERSION_C3 = 4.4.0");
    CHECK(std::string(OTA_VERSION_WROOM) == "5.3.0", "OTA_VERSION_WROOM = 5.3.0");
#if defined(BOARD_ESP32_WROOM_RELAY)
    CHECK(std::string(OTA_CURRENT_VERSION) == "5.3.0" && std::string(OTA_TARGET) == "esp32-wroom", "WROOM derlemesi: 5.3.0 / esp32-wroom");
#else
    CHECK(std::string(OTA_CURRENT_VERSION) == "4.4.0" && std::string(OTA_TARGET) == "esp32-c3", "C3 derlemesi: 4.4.0 / esp32-c3");
#endif
    // Onceki surumler (AHBU adli 4.3.1 / 5.2.0, ara surumler 4.3.2 / 5.2.1, SmartKeyPass adli 4.3.3 / 5.2.2): kopru surum bunlardan
    // BUYUK olmali (artan-surum kurali: imza bilmeyen sahadaki cihazlar bu surume OTA ile gecebilir).
    CHECK(otaSurumKarsilastir(String(OTA_VERSION_C3), String("4.3.3")) > 0 && otaSurumKarsilastir(String(OTA_VERSION_WROOM), String("5.2.2")) > 0, "yeni surumler sahadaki SmartKeyPass surumlerinden BUYUK (OTA artan-surum kurali)");
  }

  // ------------------------------------------------------------------------------------------------ acilis: gercek mqttSetup/otaSetup/baglanma
  { printf("0 acilis: mqttSetup + otaSetup + MQTT baglantisi (gercek kod)\n");
    mqttSetup(); otaSetup();
#if defined(BOARD_ESP32_WROOM_RELAY)
    adminPinBaslat();
#endif
    gm60Aktif = true;
    CHECK(client.bufSize == 1024, "MQTT tamponu 1024 B");
    for (int i = 0; i < 5 && !client.connected(); i++) loop_once(1000);
    CHECK(client.connected(), "MQTT baglandi");
    CHECK(!olaylar().empty() && olaylar()[0].event == "device_connected", "device_connected olayi yayinlandi (is kimligi YOK)");
    CHECK(!olaylar()[0].jobVar, "device_connected olayinda ota_job_id yok");
    otaCheckAndUpdate();   // ilk plan (gOtaIlkPlanYapildi) bir kez kurulsun
  }

  // ------------------------------------------------------------------------------------------------ D1 ota_job_id ayristirma
  { printf("D1 ota_check komutunda ota_job_id: saklama / temizleme / dogrulama; ota_check_requested olayina yansir\n");
    struct V { const char* json; bool sakla; const char* beklenen; bool sayi; const char* aciklama; };
    const std::string uzun40 = "abcdefghij0123456789ABCDEFGHIJ-_.:012345";   // 40 karakter
    const std::string uzun41 = uzun40 + "x";
    CHECK(uzun40.size() == 40 && uzun41.size() == 41, "(test verisi 40/41)");
    const std::vector<V> v = {
      {"{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":17,\"requested_by\":\"admin\",\"requested_at\":\"2026-10-01T10:00:00.000Z\"}", true, "17", true, "sunucu bicimi: tamsayi 17"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"job-7\"}", true, "job-7", false, "metin kimlik"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"123\"}", true, "123", false, "sayi gibi METIN: metin kalir"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":9007199254740991}", true, "9007199254740991", true, "JS guvenli tamsayi siniri"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":null}", false, "", false, "null (tekil/elle talep)"},
      {"{\"action\":\"ota_check\"}", false, "", false, "alan yok"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"\"}", false, "", false, "bos metin"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"has space\"}", false, "", false, "bosluk iceren metin red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"a\\\"b\"}", false, "", false, "tirnak iceren metin red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"a\\\\b\"}", false, "", false, "ters bolu iceren metin red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":\"<x>\"}", false, "", false, "ozel karakter red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":0}", false, "", false, "sifir red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":-3}", false, "", false, "negatif red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":1.5}", false, "", false, "ondalik red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":true}", false, "", false, "bool red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":[1]}", false, "", false, "dizi red"},
      {"{\"action\":\"ota_check\",\"ota_job_id\":{\"a\":1}}", false, "", false, "nesne red"},
    };
    for (const auto& x : v) {
      const size_t mark = client.published.size();
      otaIsKimligiTemizle();
      komut(x.json);
      const auto ov = olaylar(mark);
      const Olay* o = bul(ov, "ota_check_requested");
      CHECKF(o != nullptr, "ota_check_requested yayinlandi: %s", x.aciklama);
      if (!o) continue;
      if (x.sakla) {
        CHECKF(otaIsKimligiVarMi() && std::string(gOtaIsKimligi) == x.beklenen && gOtaIsKimligiSayi == x.sayi, "saklandi (%s)", x.aciklama);
        CHECKF(o->jobVar && o->job == x.beklenen && o->jobSayi == x.sayi, "olaya ayni tipte yansidi (%s) payload=%s", x.aciklama, o->payload.c_str());
      } else {
        CHECKF(!otaIsKimligiVarMi() && !o->jobVar, "saklanmadi ve olaya EKLENMEDI (%s)", x.aciklama);
      }
      CHECKF(o->payload.find("\"ota_job_id\"") == std::string::npos || x.sakla, "kimlik yokken alan hic yok (%s)", x.aciklama);
    }
    // 40 / 41 karakter
    { const size_t m1 = client.published.size();
      komut("{\"action\":\"ota_check\",\"ota_job_id\":\"" + uzun40 + "\"}");
      const Olay o = bulK(olaylar(m1), "ota_check_requested");
      CHECK(o.event == "ota_check_requested" && o.jobVar && o.job == uzun40, "40 karakterlik kimlik kabul ve yansir");
      const size_t m2 = client.published.size();
      komut("{\"action\":\"ota_check\",\"ota_job_id\":\"" + uzun41 + "\"}");
      const Olay o2 = bulK(olaylar(m2), "ota_check_requested");
      CHECK(o2.event == "ota_check_requested" && !o2.jobVar && !otaIsKimligiVarMi(), "41 karakterlik kimlik REDDEDILIR (onceki de temizlenir)"); }
    // dize komutlari kimlik tasimaz ve eskisini temizler
    { komut("{\"action\":\"ota_check\",\"ota_job_id\":55}"); CHECK(otaIsKimligiVarMi(), "(on kosul: kimlik 55)");
      const size_t m = client.published.size(); komut("ota");
      const Olay o = bulK(olaylar(m), "ota_check_requested");
      CHECK(o.event == "ota_check_requested" && !o.jobVar && !otaIsKimligiVarMi(), "\"ota\" dize komutu eski kimligi temizler, olaya eklemez");
      komut("{\"action\":\"ota_check\",\"ota_job_id\":56}");
      const size_t m2 = client.published.size(); komut("ota_check");
      const Olay o2 = bulK(olaylar(m2), "ota_check_requested");
      CHECK(o2.event == "ota_check_requested" && !o2.jobVar && !otaIsKimligiVarMi(), "\"ota_check\" dize komutu da temizler");
      komut("{\"action\":\"ota_check\",\"ota_job_id\":57}");
      const size_t m3 = client.published.size(); komut("{\"action\":\"ota_check\",\"retry\":true}");
      const Olay o3 = bulK(olaylar(m3), "ota_check_requested");
      CHECK(o3.event == "ota_check_requested" && !o3.jobVar && !otaIsKimligiVarMi(), "kimliksiz ota_check JSON'u eski kimligi temizler"); }
    // OTA disi olaylar kimlik tasimaz; durum yayini da tasimaz
    { komut("{\"action\":\"ota_check\",\"ota_job_id\":58}");
      const size_t m = client.published.size();
      mqttPublishEvent("pulse_started", "x"); mqttPublishEvent("device_connected");
      mqttPublishState(false);
      bool sizinti = false;
      for (size_t i = m; i < client.published.size(); i++) if (client.published[i].payload.find("ota_job_id") != std::string::npos) sizinti = true;
      CHECK(!sizinti, "OTA disi olaylarda ve durum yayininda ota_job_id yok");
      const size_t m2 = client.published.size(); mqttPublishEvent("ota_up_to_date", "5.2.0");
      CHECK(olaylar(m2).size() == 1 && olaylar(m2)[0].jobVar && olaylar(m2)[0].job == "58", "ota_* adli olay kimligi tasir");
      otaIsKimligiTemizle(); }
  }

  // ------------------------------------------------------------------------------------------------ D2 gercek OTA akislari
  fw_govde.assign(60000, '\0');
  for (size_t i = 0; i < fw_govde.size(); i++) fw_govde[i] = static_cast<char>((i * 31 + 7) & 0xFF);
  fw_sha = hexsha(fw_govde);
  g_http_routes[fw_url()] = FakeRoute{200, fw_govde, -1};

  { printf("D2.A tam OTA basarisi (ota_job_id=23): TUM ota_* olaylari (ota_success dahil) is kimligiyle gider; sonra temizlenir\n");
    manifest_kur(manifest_json(true, "9.0.0", fw_sha, fw_url()));
    imza_kur("9.0.0", fw_govde);   // OTA imzasi artik zorunlu: paketin yaninda gecerli .sig
    Update.written = 0; client.published.clear();
    const auto ov = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":23,\"requested_by\":\"admin\",\"requested_at\":\"2026-10-01T10:00:00.000Z\"}");
    printf("  olaylar: %s\n", adlar(ov).c_str());
    const char* sira[] = {"ota_check_requested", "ota_check_started", "ota_update_available", "device_connected", "ota_success"};
    bool siraOk = ov.size() == 5;
    for (size_t i = 0; siraOk && i < 5; i++) if (ov[i].event != sira[i]) siraOk = false;
    CHECK(siraOk, "olay sirasi: requested, started, update_available, (MQTT yeniden baglandi), success");
    for (const auto& o : ov) {
      if (o.event == "device_connected") CHECK(!o.jobVar, "device_connected (ota_ degil) kimlik tasimaz");
      else CHECKF(o.jobVar && o.job == "23" && o.jobSayi, "%s ota_job_id=23 (tamsayi) tasir", o.event.c_str());
    }
    CHECK(g_restart_requested && Update.ends == 1 && Update.written == fw_govde.size(), "firmware yazildi, yeniden baslatma istendi");
    CHECK(!otaIsKimligiVarMi(), "ota_success sonrasi kimlik temizlendi");
    const Olay* basari = bul(ov, "ota_success");
    CHECK(basari && basari->detail == "9.0.0", "ota_success detail = yeni surum");
    // MQTT oturumu indirmeden once kapatildi, sonra yeniden acildi: availability offline (retained) -> online
    bool offlineGordu = false, onlineGordu = false; size_t offIdx = 0, onIdx = 0;
    for (size_t i = 0; i < client.published.size(); i++) {
      if (client.published[i].topic == T_AVAIL && client.published[i].payload == "offline" && client.published[i].retained) { offlineGordu = true; offIdx = i; }
      if (client.published[i].topic == T_AVAIL && client.published[i].payload == "online" && offlineGordu) { onlineGordu = true; onIdx = i; }
    }
    CHECK(offlineGordu && onlineGordu && offIdx < onIdx, "indirmeden once availability=offline (retained), sonra yeniden online");
    size_t maxLen = 0; for (const auto& o : ov) maxLen = std::max(maxLen, o.payload.size());
    printf("  (en uzun olay yuku: %zu bayt; PubSubClient siniri %zu - %zu konu - 7)\n", maxLen, client.bufSize, T_EVT.size());
    CHECK(maxLen + T_EVT.size() + 7 <= client.bufSize, "olay yuku tampona sigdi");
    yeniden_acilis();
  }

  { printf("D2.B hash uyusmazligi: ota_failed kimlikle gider (kimlik yoksa alan eklenmez)\n");
    manifest_kur(manifest_json(true, "9.1.0", std::string(64, 'a'), fw_url()));
    imza_kur("9.1.0", fw_govde);   // imza hazir: akis sha256 denetimine kadar ilerlesin
    client.published.clear(); Update.aborts = 0;
    const auto ov = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":24}");
    printf("  olaylar: %s\n", adlar(ov).c_str());
    const Olay* f = bul(ov, "ota_failed");
    CHECK(f && f->jobVar && f->job == "24" && f->detail.find("sha256") != std::string::npos, "ota_failed ota_job_id=24 + sha256 nedeni");
    CHECK(!g_restart_requested && !otaIsKimligiVarMi(), "yeniden baslatma yok; basarisizlik sonrasi kimlik temizlendi");
    CHECK(bul(ov, "ota_check_started") && bul(ov, "ota_check_started")->job == "24" && bul(ov, "ota_update_available")->job == "24", "once-sonrasi tum olaylar kimlikli");
    yeniden_acilis();
  }

  { printf("D2.C guncel cihaz: ota_up_to_date; D2.D manifest hatasi: ota_check_failed; D2.E akis kopmasi: ota_failed + hak iadesi\n");
    manifest_kur(manifest_json(false, "5.2.0", fw_sha, fw_url()));
    client.published.clear();
    auto ov = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":\"JOB-25\"}");
    const Olay* u = bul(ov, "ota_up_to_date");
    CHECK(u && u->jobVar && u->job == "JOB-25" && !u->jobSayi, "ota_up_to_date metin kimlikle (JOB-25)");
    CHECK(!otaIsKimligiVarMi(), "guncel sonucu sonrasi kimlik temizlendi");
    // manifest hatasi
    g_http_routes[OTA_MANIFEST_URL] = FakeRoute{500, "oops", -1};
    client.published.clear();
    ov = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":26}");
    const Olay* cf = bul(ov, "ota_check_failed");
    CHECK(cf && cf->jobVar && cf->job == "26", "ota_check_failed ota_job_id=26");
    CHECK(!otaIsKimligiVarMi(), "manifest hatasi sonrasi temizlendi");
    // akis kopmasi
    manifest_kur(manifest_json(true, "9.2.0", fw_sha, fw_url()));
    imza_kur("9.2.0", fw_govde);
    g_http_routes[fw_url()] = FakeRoute{200, fw_govde, 20000};
    client.published.clear();
    ov = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":27}");
    const Olay* ff = bul(ov, "ota_failed");
    CHECK(ff && ff->jobVar && ff->job == "27" && ff->detail.find("indirme eksik") != std::string::npos, "akis kopmasi: ota_failed ota_job_id=27");
    CHECK(!g_restart_requested, "kopmada yeniden baslatma yok");
    g_http_routes[fw_url()] = FakeRoute{200, fw_govde, -1};
    yeniden_acilis();
  }

  { printf("D2.F diger sonlandirici olaylar: usb_required, target_mismatch, url/sha gecersiz, partition yok, downgrade, deneme siniri\n");
    struct S { const char* ad; std::string manifest; const char* olay; bool noPart; };
    const std::vector<S> sv = {
      {"usb_required", manifest_json(true, "9.3.0", fw_sha, fw_url(), OTA_TARGET, true), "ota_usb_required", false},
      {"target_mismatch", manifest_json(true, "9.3.0", fw_sha, fw_url(), "esp32-baska"), "ota_target_mismatch", false},
      {"url izinli degil", manifest_json(true, "9.3.0", fw_sha, "https://evil.example.com/app.bin"), "ota_failed", false},
      {"sha gecersiz", manifest_json(true, "9.3.0", "xyz", fw_url()), "ota_failed", false},
      {"downgrade", manifest_json(true, "1.0.0", fw_sha, fw_url()), "ota_up_to_date", false},
      {"OTA partition yok", manifest_json(true, "9.3.0", fw_sha, fw_url()), "ota_failed", true},
    };
    int n = 40;
    for (const auto& s : sv) {
      manifest_kur(s.manifest); g_no_update_partition = s.noPart; client.published.clear();
      const auto ov = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":" + std::to_string(n) + "}");
      const Olay* o = bul(ov, s.olay);
      CHECKF(o && o->jobVar && o->job == std::to_string(n), "%s: %s ota_job_id=%d ile gitti (olaylar: %s)", s.ad, s.olay, n, adlar(ov).c_str());
      CHECKF(!otaIsKimligiVarMi(), "%s: sonrasinda kimlik temizlendi", s.ad);
      g_no_update_partition = false; yeniden_acilis(); n++;
    }
  }

  { printf("D2.G kimliksiz kontrol: ota_job_id alani HICBIR olayda yok; eski is kimligi sonraki kontrole YAPISMAZ\n");
    manifest_kur(manifest_json(false, "5.2.0", fw_sha, fw_url()));
    client.published.clear();
    // is kimligiyle baslayan kontrol bitti (up_to_date); ardindan elle / zamanlanmis kontrol
    auto ov1 = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":90}");
    CHECK(bul(ov1, "ota_up_to_date") && bul(ov1, "ota_up_to_date")->job == "90", "is 90 tamamlandi");
    client.published.clear();
    const auto ov2 = ota_kos("{\"action\":\"ota_check\"}");
    bool kimlikli = false; for (const auto& o : ov2) if (o.jobVar) kimlikli = true;
    CHECKF(!kimlikli && bul(ov2, "ota_up_to_date"), "kimliksiz ota_check: olaylar kimliksiz (%s)", adlar(ov2).c_str());
    // is kimligi komutla geldi ama kontrol baska yolla (zamanlanmis) tetiklenip bitti: sonraki kontrol kimlik tasimaz
    komut("{\"action\":\"ota_check\",\"ota_job_id\":91}");
    CHECK(otaIsKimligiVarMi(), "(kimlik 91 bekliyor)");
    for (int i = 0; i < 200; i++) loop_once(1000);
    CHECK(!otaIsKimligiVarMi(), "kimlik, kontrolun sonuc olayiyla birlikte temizlendi");
    client.published.clear();
    otaTalepEt("test-zamanlanmis");
    for (int i = 0; i < 5; i++) loop_once(1000);
    const auto ov3 = olaylar();
    bool k3 = false; for (const auto& o : ov3) if (o.jobVar) k3 = true;
    CHECK(!k3 && bul(ov3, "ota_up_to_date"), "sonraki bagimsiz kontrol eski kimligi tasimaz");
    yeniden_acilis();
  }

  { printf("D2.H kimlikli dagitik is (jitter): ota_check_requested hemen, ota_check_started 0-120 sn sonra; ikisi de kimlikli\n");
    manifest_kur(manifest_json(false, "5.2.0", fw_sha, fw_url()));
    client.published.clear();
    const uint32_t t0 = g_fake_ms;
    komut("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":77}");
    { const auto ovh = olaylar(); CHECK(bul(ovh, "ota_check_requested") != nullptr && bul(ovh, "ota_check_started") == nullptr, "talep hemen, kontrol henuz baslamadi (jitter)"); }
    uint32_t basladi = 0;
    for (int i = 0; i < 200 && !basladi; i++) { loop_once(1000); { const auto ovh = olaylar(); if (bul(ovh, "ota_check_started")) basladi = g_fake_ms - t0; } }
    CHECKF(basladi > 0 && basladi <= 121000, "kontrol jitter sonrasi basladi (%u ms)", basladi);
    { const auto ovh = olaylar(); const Olay st = bulK(ovh, "ota_check_started"); CHECK(st.event == "ota_check_started" && st.job == "77", "ota_check_started kimlikli"); }
  }

  // ------------------------------------------------------------------------------------------------ S OTA IMZA (Ed25519)
  { printf("S OTA IMZA: imzasiz / bozuk / baska surum-hedef-paket icin imzali paket REDDEDILIR; yalniz dogru imza kurar; izinli surum dusurme; kopru\n");
    int is = 300;
    const std::string S_VER = "9.20.0";
    const std::string mfOk = manifest_json(true, S_VER, fw_sha, fw_url());
    const std::string DIGER_HEDEF = std::string(OTA_TARGET) == "esp32-c3" ? "esp32-wroom" : "esp32-c3";
    g_http_routes[fw_url()] = FakeRoute{200, fw_govde, -1};

    auto yeni = [&]() { yeniden_acilis(); Update.written = 0; Update.ends = 0; Update.aborts = 0; g_http_requests.clear(); client.published.clear(); };
    auto istendi = [&](const std::string& url) { for (const auto& u : g_http_requests) if (u == url) return true; return false; };
    auto sayac = [&]() -> std::string { auto& m = g_nvs["ota_cfg"]; auto it = m.find("try_cnt"); return it == m.end() ? std::string("") : it->second; };
    auto kos = [&](const std::string& manifest) { manifest_kur(manifest); yeni(); return ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":" + std::to_string(++is) + "}"); };
    // Reddedilen kurulum: ota_failed + neden; boot bolumu DEGISMEDI (Update.end hic cagrilmadi); yeniden baslatma yok
    auto red = [&](const std::vector<Olay>& ov, const char* neden, const char* ad) {
      const Olay* f = bul(ov, "ota_failed");
      CHECKF(f != nullptr && f->detail.find(neden) != std::string::npos, "%s: ota_failed '%s' (olaylar: %s)", ad, neden, adlar(ov).c_str());
      CHECKF(bul(ov, "ota_success") == nullptr && !g_restart_requested && Update.ends == 0, "%s: KURULMADI (ota_success yok, yeniden baslatma yok, Update.end cagrilmadi)", ad);
      CHECKF(f != nullptr && f->jobVar, "%s: ota_failed ota_job_id tasir", ad);
    };
    auto basari = [&](const std::vector<Olay>& ov, const char* surum, const char* ad) {
      const Olay* s = bul(ov, "ota_success");
      CHECKF(s != nullptr && s->detail == surum && g_restart_requested && Update.ends == 1 && Update.written == fw_govde.size(), "%s: KURULDU (ota_success %s, Update.end 1, yeniden baslatma) olaylar: %s", ad, surum, adlar(ov).c_str());
      CHECKF(bul(ov, "ota_failed") == nullptr, "%s: ota_failed yok", ad);
    };
    auto guncel = [&](const std::vector<Olay>& ov, const char* ad) {
      CHECKF(bul(ov, "ota_up_to_date") != nullptr && bul(ov, "ota_failed") == nullptr && bul(ov, "ota_success") == nullptr, "%s: ota_up_to_date (kurulum yok) olaylar: %s", ad, adlar(ov).c_str());
      CHECKF(!g_restart_requested && Update.ends == 0 && Update.written == 0, "%s: flash'a dokunulmadi", ad);
      CHECKF(!istendi(fw_url()) && !istendi(fw_sig_url()), "%s: ne paket ne imza istendi", ad);
    };
    const std::string cur = OTA_CURRENT_VERSION;

    { printf("S1 gecerli imza: manifest -> .sig -> paket sirasi; imza dogrulaninca Update.end + ota_success\n");
      imza_kur(S_VER, fw_govde);
      const auto ov = kos(mfOk);
      basari(ov, S_VER.c_str(), "S1");
      int iM = -1, iS = -1, iF = -1;
      for (size_t i = 0; i < g_http_requests.size(); i++) {
        const std::string& u = g_http_requests[i];
        if (u.find(OTA_MANIFEST_URL) == 0) iM = static_cast<int>(i); else if (u == fw_sig_url()) iS = static_cast<int>(i); else if (u == fw_url()) iF = static_cast<int>(i);
      }
      CHECK(iM >= 0 && iS > iM && iF > iS, "sira: manifest, imza dosyasi, paket (imza yoksa paket hic indirilmez)");
      bool yetenek = false;
      for (const auto& u : g_http_requests) if (u.find(OTA_MANIFEST_URL) == 0 && u.find("imza=ed25519-v1") != std::string::npos && u.find("current_version=") != std::string::npos && u.find("uid=") != std::string::npos) yetenek = true;
      CHECK(yetenek, "manifest istegi imza yetenegini bildirir (&imza=ed25519-v1): sunucu kopru mantigi icin");
      CHECK(g_nvs["ota_cfg"]["last_status"] == "guncelleme tamam", "durum: guncelleme tamam");
    }

    { printf("S2 IMZASIZ PAKET (kopru guvencesi): sunucuda .sig yok (404) -> paket INDIRILMEZ, kurulmaz; hak yanar (kalici)\n");
      g_http_routes[fw_sig_url()] = FakeRoute{404, "yok", -1};
      const auto ov = kos(mfOk);
      red(ov, "imza: dosya yok", "S2 404");
      CHECK(istendi(fw_sig_url()) && !istendi(fw_url()), "S2: paket HIC indirilmedi (imza once alinir)");
      CHECK(Update.written == 0 && Update.aborts == 0, "S2: OTA bolumune hicbir sey yazilmadi");
      CHECK(sayac() == "1", "S2: kalici red deneme hakkini yakti (1)");
      CHECK(g_nvs["ota_cfg"]["last_status"].find("imza: dosya yok") != std::string::npos, "S2: durum NVS'e yazildi");
      g_http_routes[fw_sig_url()] = FakeRoute{403, "yasak", -1};
      red(kos(mfOk), "imza: dosya yok", "S2 403");
      g_http_routes[fw_sig_url()] = FakeRoute{410, "gone", -1};
      red(kos(mfOk), "imza: dosya yok", "S2 410");
      // KOPRU / zorunluluk: imzayi kapatmaya calisan HICBIR manifest alani ya da MQTT komutu alani cihazda etkili degildir
      g_http_routes[fw_sig_url()] = FakeRoute{404, "yok", -1};
      red(kos(manifest_ek(mfOk, "\"force\":true,\"signed\":false,\"sig_required\":false,\"require_signature\":false,\"unsigned_ok\":true,\"imza_zorunlu\":false,\"verify\":false,\"md5\":\"\"")),
          "imza: dosya yok", "S2 imzayi kapatmaya calisan manifest alanlari");
      CHECK(!istendi(fw_url()), "S2: bu alanlarla da paket indirilmedi");
      manifest_kur(mfOk); yeni();
      const auto ovk = ota_kos("{\"action\":\"ota_check\",\"retry\":true,\"ota_job_id\":399,\"allow_unsigned\":true,\"skip_signature\":true,\"signature_required\":false,\"force\":true}");
      red(ovk, "imza: dosya yok", "S2 imzayi kapatmaya calisan MQTT komut alanlari");
      CHECK(!istendi(fw_url()), "S2: MQTT komutuyla da paket indirilmedi");
    }

    { printf("S3 gecici ag/sunucu hatasi (imza dosyasi 503 / baglanti yok): kurulmaz ama deneme hakki YANMAZ\n");
      g_http_routes[fw_sig_url()] = FakeRoute{503, "bakimda", -1};
      auto ov = kos(mfOk);
      red(ov, "imza: dosya alinamadi (http 503)", "S3 503");
      CHECK(!istendi(fw_url()) && sayac() == "0", "S3: paket indirilmedi; hak iade edildi (0)");
      g_http_routes.erase(fw_sig_url());   // rota yok -> baglanti hatasi (-1)
      ov = kos(mfOk);
      red(ov, "imza: dosya alinamadi (http -1)", "S3 baglanti yok");
      CHECK(!istendi(fw_url()) && sayac() == "0", "S3: baglanti yokken de hak yanmadi");
    }

    { printf("S4 bozuk imza: paket indirilir ama Update.end ASLA cagrilmaz (iptal), ota_failed 'imza: dogrulama basarisiz'\n");
      std::string s = imza_ham(g_yayinci, OTA_TARGET, S_VER, fw_govde);
      s[5] ^= 1;
      g_http_routes[fw_sig_url()] = FakeRoute{200, s, -1};
      const auto ov = kos(mfOk);
      red(ov, "imza: dogrulama basarisiz", "S4");
      CHECK(Update.written == fw_govde.size() && Update.aborts == 1, "S4: paket yazildi ve imza hatasinda IPTAL edildi (abort=1)");
      CHECK(sayac() == "1", "S4: imza hatasi hakki yakar");
      CHECK(Serial.hist_has("OTA GUVENLIK: paket imzasi dogrulanamadi"), "S4: Turkce guvenlik gunlugu seriye yazildi");
      size_t maxLen = 0; for (const auto& o : ov) maxLen = std::max(maxLen, o.payload.size());
      CHECKF(maxLen + T_EVT.size() + 7 <= client.bufSize, "S4: olay yuku tampona sigdi (%zu bayt)", maxLen);
    }

    { printf("S5 saldirgan senaryolari: gecerli imzali ama BASKA surum / paket / hedef / anahtar icin imza, yetkisiz rollback_max, bos imza\n");
      struct V { const char* ad; std::string sig; };
      const std::vector<V> v = {
        {"baska surum icin imza (9.20.1)", imza_ham(g_yayinci, OTA_TARGET, "9.20.1", fw_govde)},
        {"ESKI surum icin gecerli imza yeniden sunuldu (9.0.0)", imza_ham(g_yayinci, OTA_TARGET, "9.0.0", fw_govde)},
        {"baska paket govdesi icin imza", imza_ham(g_yayinci, OTA_TARGET, S_VER, fw_govde + "x")},
        {"BASKA DONANIM HEDEFI icin gecerli imza", imza_ham(g_yayinci, DIGER_HEDEF, S_VER, fw_govde)},
        {"saldirganin KENDI anahtariyla imza", imza_ham(g_saldirgan, OTA_TARGET, S_VER, fw_govde)},
        {"yetkisiz rollback_max iceren imza (yukseltmede)", imza_ham(g_yayinci, OTA_TARGET, S_VER, fw_govde, "99.0.0")},
        {"tum-sifir imza", std::string(64, '\0')},
        {"tum-0xFF imza", std::string(64, '\xff')},
      };
      for (const auto& x : v) {
        g_http_routes[fw_sig_url()] = FakeRoute{200, x.sig, -1};
        red(kos(mfOk), "imza: dogrulama basarisiz", x.ad);
      }
    }

    { printf("S6 manifeste gomulu imza (hex / base64): .sig dosyasi gerekmez; bozuk gomulu imza paket indirmeden reddedilir\n");
      g_http_routes.erase(fw_sig_url());
      const std::string ham = imza_ham(g_yayinci, OTA_TARGET, S_VER, fw_govde);
      auto ov = kos(manifest_ek(mfOk, "\"signature\":\"" + hexyaz(ham) + "\""));
      basari(ov, S_VER.c_str(), "S6 hex");
      CHECK(!istendi(fw_sig_url()), "S6: gomulu imza varken .sig istenmedi");
      ov = kos(manifest_ek(mfOk, "\"signature\":\"" + b64yaz(ham) + "\""));
      basari(ov, S_VER.c_str(), "S6 base64");
      ov = kos(manifest_ek(mfOk, "\"signature\":\"zzzz-bozuk\""));
      red(ov, "imza: bicim gecersiz (manifest signature)", "S6 bozuk gomulu");
      CHECK(!istendi(fw_url()), "S6: bozuk gomulu imzada paket indirilmedi");
      ov = kos(manifest_ek(mfOk, "\"signature\":\"" + hexyaz(imza_ham(g_saldirgan, OTA_TARGET, S_VER, fw_govde)) + "\""));
      red(ov, "imza: dogrulama basarisiz", "S6 saldirgan gomulu imza");
    }

    { printf("S7 imza dosyasi adresi: sig_url / signature_url, hex+CRLF ve base64 dosya bicimleri, baska sunucu REDDI, asiri buyuk dosya\n");
      const std::string ham = imza_ham(g_yayinci, OTA_TARGET, S_VER, fw_govde);
      const std::string ozel = std::string("https://api.gudeteknoloji.com.tr/firmware/") + OTA_TARGET + "/imza-9.20.0.sig";
      g_http_routes.erase(fw_sig_url());
      g_http_routes[ozel] = FakeRoute{200, hexyaz(ham) + "\r\n", -1};
      auto ov = kos(manifest_ek(mfOk, "\"sig_url\":\"" + ozel + "\""));
      basari(ov, S_VER.c_str(), "S7 sig_url (hex+CRLF)");
      CHECK(istendi(ozel) && !istendi(fw_sig_url()), "S7: sig_url kullanildi, varsayilan adres istenmedi");
      g_http_routes[ozel] = FakeRoute{200, b64yaz(ham) + "\n", -1};
      ov = kos(manifest_ek(mfOk, "\"signature_url\":\"" + ozel + "\""));
      basari(ov, S_VER.c_str(), "S7 signature_url (base64)");
      g_http_routes[fw_sig_url()] = FakeRoute{200, ham, -1};   // varsayilan: ham 64 bayt
      ov = kos(mfOk);
      basari(ov, S_VER.c_str(), "S7 varsayilan .sig (ham 64 bayt)");
      ov = kos(manifest_ek(mfOk, "\"sig_url\":\"https://evil.example.com/firmware/imza.sig\""));
      red(ov, "imza: adres reddedildi", "S7 baska sunucu");
      CHECK(!istendi("https://evil.example.com/firmware/imza.sig") && !istendi(fw_url()), "S7: baska sunucuya baglanilmadi, paket indirilmedi");
      ov = kos(manifest_ek(mfOk, "\"sig_url\":\"http://api.gudeteknoloji.com.tr/x.sig\""));
      red(ov, "imza: adres reddedildi", "S7 http (TLS'siz) adres");
      g_http_routes[fw_sig_url()] = FakeRoute{200, std::string(600, 'a'), -1};
      ov = kos(mfOk);
      red(ov, "imza: dosya cok buyuk", "S7 600 baytlik imza dosyasi");
      CHECK(!istendi(fw_url()), "S7: asiri buyuk imza dosyasinda paket indirilmedi");
      g_http_routes[fw_sig_url()] = FakeRoute{200, std::string(70, 'a'), -1};
      ov = kos(mfOk);
      red(ov, "imza: bicim gecersiz", "S7 70 baytlik cop imza dosyasi");
      // paket adresi sorgu iceriyorsa varsayilan imza adresi TURETILMEZ; sig_url ile verilebilir
      const std::string mfSorgu = manifest_json(true, S_VER, fw_sha, fw_url() + "?x=1");
      ov = kos(mfSorgu);
      red(ov, "imza: adres turetilemedi", "S7 sorgulu paket adresi");
      g_http_routes[fw_sig_url()] = FakeRoute{200, ham, -1};
      ov = kos(manifest_ek(mfSorgu, "\"sig_url\":\"" + fw_sig_url() + "\""));
      basari(ov, S_VER.c_str(), "S7 sorgulu adres + sig_url");
    }

    { printf("S8 manifest surum alani imza yukune uygun degilse (satir ekleme) indirme baslamaz\n");
      imza_kur(S_VER, fw_govde);
      const char* kotu[] = {"9.20.0\\nsize=1", "9.20.0 ", "9.20.0\\t", "9.20.0/../x", "1234567890123456789012345.9"};
      for (const char* k : kotu) {
        const auto ov = kos(manifest_json(true, k, fw_sha, fw_url()));
        red(ov, "imza: manifest surum alani gecersiz", k);
        CHECKF(!istendi(fw_url()) && !istendi(fw_sig_url()), "S8 (%s): hicbir indirme yok", k);
      }
    }

    { printf("S9 IMZA ANAHTARI HAZIR DEGIL (yer tutucu / tum-sifir): hicbir paket kurulmaz, ne imza ne paket indirilir, hak yanmaz\n");
      imza_kur(S_VER, fw_govde);
      test_anahtarini_kur(ed_test::YER_TUTUCU_DUZ);
      auto ov = kos(mfOk);
      red(ov, "imza: anahtar yerlestirilmemis", "S9 yer tutucu");
      CHECK(!istendi(fw_url()) && !istendi(fw_sig_url()) && Update.written == 0, "S9: yer tutucu anahtarla HICBIR indirme yapilmadi");
      CHECK(sayac() == "", "S9: deneme hakki yakilmadi");
      uint8_t sifir[32] = {0};
      test_anahtarini_kur(sifir);
      ov = kos(mfOk);
      red(ov, "imza: anahtar yerlestirilmemis", "S9 tum-sifir anahtar");
      uint8_t kimlik[32] = {1};   // y=1: kimlik noktasi (kucuk mertebeli) - sahte imza uretmeyi kolaylastirir
      test_anahtarini_kur(kimlik);
      g_http_routes[fw_sig_url()] = FakeRoute{200, std::string("\x01") + std::string(63, '\0'), -1};   // R=kimlik, S=0
      ov = kos(mfOk);
      red(ov, "imza: anahtar yerlestirilmemis", "S9 kucuk mertebeli anahtar + sahte imza");
      CHECK(!istendi(fw_url()), "S9: zayif anahtarla sahte imza paket indirtmedi");
      test_anahtarini_kur(g_yayinci.genel);
      imza_kur(S_VER, fw_govde);
      basari(kos(mfOk), S_VER.c_str(), "S9 anahtar duzelince kurar");
    }

    { printf("S10 IZINLI SURUM DUSURME: yalniz allow_downgrade + imzali rollback_max + kapsam; esit surum ve sunucunun tek basina verdigi izin etkisiz\n");
      const std::string eski = "1.0.0", eskiRb = "1.5.0";
      g_http_routes[fw_url()] = FakeRoute{200, fw_govde, -1};
      const std::string mfEski = manifest_json(true, eski, fw_sha, fw_url());
      const std::string izin = "\"allow_downgrade\":true";
      // izin yok -> mevcut davranis: guncel sayilir, kurulmaz
      guncel(kos(mfEski), "S10 izin yok (eski surum)");
      // izin var ama imza rollback_max icermiyor -> indirilir, imzada reddedilir
      imza_kur(eski, fw_govde);
      auto ov = kos(manifest_ek(mfEski, izin));
      red(ov, "imza: dogrulama basarisiz", "S10 izin var, imza rollback_max'siz");
      CHECK(Update.written == fw_govde.size() && Update.aborts == 1, "S10: sunucunun izni tek basina yetmedi, paket iptal edildi");
      // izin + imzali rollback_max = cihazin surumu -> kurulur
      imza_kur(eski, fw_govde, cur.c_str());
      ov = kos(manifest_ek(mfEski, izin));
      basari(ov, eski.c_str(), "S10 izin + imzali rollback_max");
      // alias
      ov = kos(manifest_ek(mfEski, "\"downgrade_allowed\":true"));
      basari(ov, eski.c_str(), "S10 downgrade_allowed takma adi");
      // rollback_max kapsami cihazin surumunu icermiyorsa: bu cihaz icin guncelleme yok
      imza_kur(eski, fw_govde, eskiRb.c_str());
      guncel(kos(manifest_ek(mfEski, izin + ",\"rollback_max\":\"" + eskiRb + "\"")), "S10 rollback_max cihazin surumunun altinda");
      // genis kapsam: manifest ve imza ayni rollback_max
      imza_kur(eski, fw_govde, "99.0.0");
      ov = kos(manifest_ek(mfEski, izin + ",\"rollback_max\":\"99.0.0\""));
      basari(ov, eski.c_str(), "S10 genis kapsam (manifest = imza)");
      // KAPSAM GENISLETME saldirisi: imza dar (cihazin surumu), manifest genis diyor
      imza_kur(eski, fw_govde, cur.c_str());
      ov = kos(manifest_ek(mfEski, izin + ",\"rollback_max\":\"99.0.0\""));
      red(ov, "imza: dogrulama basarisiz", "S10 kapsam genisletme saldirisi");
      // gecersiz rollback_max (satir ekleme)
      ov = kos(manifest_ek(mfEski, izin + ",\"rollback_max\":\"9.9\\nx=1\""));
      guncel(ov, "S10 gecersiz rollback_max");
      // izin dize ("true") ya da sayi (1) ise sayilmaz
      guncel(kos(manifest_ek(mfEski, "\"allow_downgrade\":\"true\"")), "S10 izin dize");
      guncel(kos(manifest_ek(mfEski, "\"allow_downgrade\":1")), "S10 izin sayi");
      // ESIT surum: izin olsa da kurulmaz
      guncel(kos(manifest_ek(manifest_json(true, cur, fw_sha, fw_url()), izin)), "S10 esit surum + izin");
      // YUKSELTME + izin: normal yukseltme; imza rollback_max ICERMEMELI
      imza_kur(S_VER, fw_govde);
      basari(kos(manifest_ek(mfOk, izin)), S_VER.c_str(), "S10 yukseltme + izin (imza rollback'siz)");
      imza_kur(S_VER, fw_govde, cur.c_str());
      red(kos(manifest_ek(mfOk, izin)), "imza: dogrulama basarisiz", "S10 yukseltmede rollback_max'li imza reddedilir");
    }

    { printf("S11 deneme siniri: ayni surum icin 3 imza hatasindan sonra cihaz 4. kez INDIRMEZ (retry olmadan)\n");
      std::string kotu = imza_ham(g_yayinci, OTA_TARGET, S_VER, fw_govde);
      kotu[0] ^= 1;
      g_http_routes[fw_sig_url()] = FakeRoute{200, kotu, -1};
      manifest_kur(mfOk);
      otaDenemeSayacinaSifirla();
      int indirme = 0;
      for (int k = 0; k < 4; k++) {
        yeni();
        const auto ov = ota_kos("{\"action\":\"ota_check\",\"ota_job_id\":" + std::to_string(++is) + "}");
        if (istendi(fw_url())) indirme++;
        if (k < 3) CHECKF(bul(ov, "ota_failed") && bul(ov, "ota_failed")->detail.find("imza: dogrulama basarisiz") != std::string::npos, "S11: deneme %d imza hatasi", k + 1);
        else CHECKF(bul(ov, "ota_failed") && bul(ov, "ota_failed")->detail.find("deneme siniri asildi") != std::string::npos && !istendi(fw_sig_url()), "S11: 4. denemede sinir asildi, imza/paket istenmedi (olaylar: %s)", adlar(ov).c_str());
      }
      CHECKF(indirme == 3, "S11: toplam 3 indirme (%d)", indirme);
      CHECK(Update.ends == 0 && !g_restart_requested, "S11: hicbirinde kurulum yok");
    }

    { printf("S12 acilis gunlugu: anahtar parmak izi / yer tutucu uyarisi; ozel anahtar (tohum) hicbir gunluge yazilmaz\n");
      uint8_t ozet[32];
      refcrypto::sha256(g_yayinci.genel, 32, ozet);
      char hex[17];
      for (int i = 0; i < 8; i++) snprintf(&hex[i * 2], 3, "%02x", ozet[i]);
      Serial.clear();
      otaSetup();
      CHECK(Serial.has("OTA imza anahtari: HAZIR") && Serial.has(std::string("parmak izi ") + hex), "S12: HAZIR + parmak izi (SHA-256 ilk 8 bayt) seriye yazildi");
      test_anahtarini_kur(ed_test::YER_TUTUCU_DUZ);
      Serial.clear();
      otaSetup();
      CHECK(Serial.has("OTA imza anahtari: YER TUTUCU") && Serial.has("OTA ile guncelleme KAPALI"), "S12: yer tutucu uyarisi");
      uint8_t sifir[32] = {0};
      test_anahtarini_kur(sifir);
      Serial.clear();
      otaSetup();
      CHECK(Serial.has("OTA imza anahtari: GECERSIZ"), "S12: gecersiz anahtar uyarisi");
      test_anahtarini_kur(g_yayinci.genel);
      otaSetup();
      bool sizinti = Serial.hist_has(hexyaz(std::string(reinterpret_cast<const char*>(g_yayinci.tohum), 32)));
      for (size_t i = 0; i < client.published.size(); i++) if (client.published[i].payload.find(hexyaz(std::string(reinterpret_cast<const char*>(g_yayinci.tohum), 32))) != std::string::npos) sizinti = true;
      CHECK(!sizinti, "S12: ozel anahtar (tohum) seriye ve MQTT yayinlarina HIC yazilmadi");
    }
    test_anahtarini_kur(g_yayinci.genel);
    yeniden_acilis();
  }

#if defined(BOARD_ESP32_WROOM_RELAY)
  // ------------------------------------------------------------------------------------------------ B admin_pin_config (MQTT)
  { printf("B MQTT admin_pin_config: zayif PIN reddi nedenle olaya (weak_pin) yazilir; PIN degeri seriye/olaya YAZILMAZ\n");
    Serial.clear(); const size_t m = client.published.size();
    komut("{\"action\":\"admin_pin_config\",\"admin_pin\":\"123456\"}");
    auto ov = olaylar(m);
    CHECK(ov.size() == 1 && ov[0].event == "admin_pin_config_rejected" && ov[0].detail == "weak_pin", "123456 -> admin_pin_config_rejected / weak_pin");
    CHECK(!adminPinTanimliMi(), "zayif PIN saklanmadi");
    CHECK(Serial.has("zayif PIN") && !Serial.has("123456"), "seriye NEDEN yazildi, PIN yazilmadi");
    const char* zayiflar[] = {"000000", "111111", "654321", "123123", "121212", "112233", "000001", "012345", "987654", "876543", "234567", "345678", "456789"};
    for (const char* p : zayiflar) {
      const size_t mm = client.published.size();
      komut(std::string("{\"action\":\"admin_pin_config\",\"admin_pin\":\"") + p + "\"}");
      auto o2 = olaylar(mm);
      CHECKF(o2.size() == 1 && o2[0].event == "admin_pin_config_rejected" && o2[0].detail == "weak_pin" && !adminPinTanimliMi(), "%s reddedildi (weak_pin)", p);
      for (size_t i = mm; i < client.published.size(); i++) CHECKF(client.published[i].payload.find(p) == std::string::npos, "%s olay/durum yukunde YOK", p);
    }
    const size_t m2 = client.published.size();
    komut("{\"action\":\"admin_pin_config\",\"admin_pin\":\"12345\"}");
    CHECK(olaylar(m2).size() == 1 && olaylar(m2)[0].detail == "invalid_pin", "5 hane -> invalid_pin");
    const size_t m3 = client.published.size();
    komut("{\"action\":\"admin_pin_config\",\"admin_pin\":123456}");
    CHECK(olaylar(m3).size() == 1 && olaylar(m3)[0].event == "admin_pin_config_rejected" && olaylar(m3)[0].detail == "invalid_pin", "sayi olarak gonderilen PIN -> invalid_pin");
    const size_t m4 = client.published.size();
    komut("{\"action\":\"admin_pin_config\"}");
    CHECK(olaylar(m4).size() == 1 && olaylar(m4)[0].detail == "invalid_pin", "PIN alani yok -> invalid_pin");
    Serial.clear(); const size_t m5 = client.published.size();
    komut("{\"action\":\"admin_pin_config\",\"admin_pin\":\"482916\"}");
    auto o5 = olaylar(m5);
    CHECK(adminPinTanimliMi() && !o5.empty() && o5[0].event == "admin_pin_configured", "gecerli PIN kabul + admin_pin_configured");
    CHECK(!Serial.has("482916"), "kabulde de PIN seriye yazilmadi");
    bool durumPinli = false;
    for (size_t i = m5; i < client.published.size(); i++) if (client.published[i].topic == T_STATE) { JsonDocument d; deserializeJson(d, client.published[i].payload); if ((d["admin_pin_set"] | false) == true) durumPinli = true; }
    CHECK(durumPinli, "durum yayininda admin_pin_set=true (PIN degeri yok)");
    for (size_t i = m5; i < client.published.size(); i++) CHECK(client.published[i].payload.find("482916") == std::string::npos, "yayin yuklerinde PIN yok");
    // zayif PIN, mevcut gecerli PIN'i degistirmez
    komut("{\"action\":\"admin_pin_config\",\"admin_pin\":\"000000\"}");
    CHECK(gAdminPin == "482916", "reddedilen zayif PIN mevcut PIN'i silmedi/degistirmedi");
    const size_t m6 = client.published.size();
    komut("{\"action\":\"admin_pin_config\",\"admin_pin\":\"\"}");
    CHECK(!adminPinTanimliMi() && !olaylar(m6).empty() && olaylar(m6)[0].event == "admin_pin_configured", "bos PIN silmeyi surdurur");
  }
#endif

  // ------------------------------------------------------------------------------------------------ C qr_result red dali (gercek mqttHandleQrResult)
  { printf("C qr_result: red -> ayni QR hemen yeniden denenebilir; onay -> 8 sn tekrar penceresi; eslesmeyen sonuc yok sayilir\n");
    auto okuQr = [&](const char* tok) { gm60QrVerisiniIsle(String(tok)); };
    auto sonQv = [&]() -> JsonDocument* { static JsonDocument d; for (size_t i = client.published.size(); i-- > 0;) if (client.published[i].topic == T_QRV) { d.clear(); deserializeJson(d, client.published[i].payload); return &d; } return nullptr; };
    auto qvSay = [&]() { int n = 0; for (auto& m : client.published) if (m.topic == T_QRV) n++; return n; };
    // taze durum
    gm60SonOkumaMs = 0; gm60SonGonderilenToken = ""; gm60SunucuYanitBekleniyor = false; roleAktif = false; roleSonTetikMs = 0;
    g_ekran.clear(); client.published.clear(); g_fake_ms += 60000;
    okuQr("GUESTQR1");
    CHECK(qvSay() == 1, "qr_verify yayinlandi");
    const auto* d1 = sonQv();
    CHECK(d1 && std::string((*d1)["token"] | "") == "GUESTQR1" && (*d1)["request_id"].is<unsigned>(), "qr_verify {token, request_id}");
    const uint32_t id1 = (*d1)["request_id"].as<uint32_t>();
    // eslesmeyen request_id: yok sayilir (token unutulmaz, QR_DENIED yok)
    g_ekran.clear();
    client.deliver(T_QRR, "{\"allowed\":false,\"reason\":\"expired\",\"request_id\":" + std::to_string(id1 + 7) + "}");
    CHECK(gm60SonGonderilenToken == "GUESTQR1" && gm60SunucuYanitBekleniyor && g_ekran.empty(), "eslesmeyen request_id yok sayildi");
    // gercek red
    client.deliver(T_QRR, "{\"allowed\":false,\"reason\":\"expired\",\"request_id\":" + std::to_string(id1) + "}");
    CHECK(!gm60SunucuYanitBekleniyor && gm60SonGonderilenToken == "" && g_ekran.size() == 1 && g_ekran[0] == "QR_DENIED", "red: QR_DENIED + token unutuldu");
    g_fake_ms += 2000; okuQr("GUESTQR1");
    CHECK(qvSay() == 1, "2 sn: 5 sn debounce hala gecerli -> gonderilmez");
    g_fake_ms += 3000; okuQr("GUESTQR1");
    CHECK(qvSay() == 2, "5 sn: ayni QR yeniden denendi (eskiden 30 sn sessizce yok sayilirdi)");
    const uint32_t id2 = (*sonQv())["request_id"].as<uint32_t>();
    CHECK(id2 == id1 + 1, "yeni request_id");
    // onay: token 8 sn korunur
    g_ekran.clear();
    client.deliver(T_QRR, "{\"allowed\":true,\"reason\":\"ok\",\"request_id\":" + std::to_string(id2) + "}");
    CHECK(gm60SonGonderilenToken == "GUESTQR1" && !gm60SunucuYanitBekleniyor && g_ekran.empty(), "onay: token kalir (tekrar penceresi), ekran bildirimi pulse'tan gelir");
    g_fake_ms += 5000; okuQr("GUESTQR1");
    CHECK(qvSay() == 2, "onaydan 5 sn sonra ayni token hala gonderilmez (8 sn)");
    g_fake_ms += 3000; okuQr("GUESTQR1");
    CHECK(qvSay() == 3, "8 sn sonra ikinci kisi ayni QR ile gecebilir");
    // request_id'siz (eski sunucu) red de kabul edilir
    g_ekran.clear();
    client.deliver(T_QRR, "{\"allowed\":false,\"reason\":\"x\"}");
    CHECK(gm60SonGonderilenToken == "" && !g_ekran.empty() && g_ekran.back() == "QR_DENIED", "request_id'siz sonuc bekleyen istekle eslenir; red token'i unutturur");
    // bekleyen istek yokken gelen sonuc yok sayilir
    g_ekran.clear(); gm60SonGonderilenToken = "KEEP";
    client.deliver(T_QRR, "{\"allowed\":false,\"request_id\":" + std::to_string(id2) + "}");
    CHECK(gm60SonGonderilenToken == "KEEP" && g_ekran.empty(), "bekleyen istek yokken gelen sonuc yok sayilir");
    // bozuk JSON
    client.deliver(T_QRR, "{bozuk");
    CHECK(gm60SonGonderilenToken == "KEEP", "bozuk qr_result etkisiz");
  }

  printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
