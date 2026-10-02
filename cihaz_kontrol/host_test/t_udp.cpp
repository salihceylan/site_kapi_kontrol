// Ana makine testi: GERCEK cihaz_kontrol/include/yerel_kapi_kontrol.h (UDP + HTTP, v2) + gercek role_kontrol.h + gercek
// yerel_kontrol_cekirdek.h. Ag (WiFiUDP/WiFiServer), saat, RNG ve MQTT/ekran/log yan etkileri sahte; paketler gercek JSON ile islenir.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WiFiUdp.h>

#include "mbedtls_stub_impl.h"

// Agir basliklar etkisizlestirilir (koruma makrolari); ihtiyac duyulan semboller asagida testte tanimlanir.
#define MQTT_BAGLANTI_H
#define OFFLINE_LOG_H
#define OTA_GUNCELLEME_H
#define WIFI_BAGLANTI_H

inline constexpr const char* OTA_CURRENT_VERSION = "5.2.0";
inline bool g_wifi_ready = true;
inline String g_token = "";
inline bool g_mqtt_connected = false;
inline bool wifiHazirMi() { return g_wifi_ready; }
inline String wifiIpAdresi() { return WiFi.localIP().toString(); }
inline int wifiSinyalDbm() { return -60; }
inline bool wifiHasLocalControlToken() { return !g_token.isEmpty(); }
inline String wifiLocalControlToken() { return g_token; }
inline bool mqttBagliMi() { return g_mqtt_connected; }
struct Ev { std::string name, detail; };
inline std::vector<Ev> g_events;
inline int g_state_publishes = 0;
inline bool mqttPublishEvent(const char* name, const char* detail = "", const char* = nullptr) {
  g_events.push_back({name, detail ? detail : ""});
  return true;
}
inline bool mqttPublishState(bool) { g_state_publishes++; return true; }
inline std::vector<std::string> g_offline_logs;
inline void offlineLogKaydet(const char* tur = "local_wifi", const char* user = "Yerel Ag Kullanicisi", const char* apt = "") {
  g_offline_logs.push_back(std::string(tur) + "|" + user + "|" + apt);
}
inline std::vector<std::string> g_display;
void displayUartSend(const char* c) { g_display.push_back(c); }
void displayUartSend(const String& c) { g_display.push_back(c.c_str()); }

#include "yerel_kapi_kontrol.h"

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL: %s  (satir %d)\n", msg, __LINE__); } } while (0)
#define CHECKF(cond, ...) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static const char* TOKEN = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE";
static const char* UID = "240AC4E2E001";
static std::vector<std::string> g_gizli;   // testte kullanilan sir degerleri (token, sig, ch): Serial'da gorunmemeli

static std::string oracle_sig(const std::string& token, const std::string& action, const std::string& uid, const std::string& ch) {
  const std::string msg = action + "|" + uid + "|" + ch;
  uint8_t mac[32];
  refcrypto::hmac_sha256(reinterpret_cast<const uint8_t*>(token.data()), token.size(), reinterpret_cast<const uint8_t*>(msg.data()), msg.size(), mac);
  char hex[65];
  refcrypto::to_hex(mac, 32, hex);
  return hex;
}

static const IPAddress KAYNAK(192, 168, 100, 50);

// Bir UDP paketi yollar, bir loop turu calistirir; paketin kaynagina giden yanitlari dondurur (beacon'lar disarida kalir).
static std::vector<std::string> udp(const std::string& payload, IPAddress from = KAYNAK, uint16_t port = 51234) {
  const size_t once = gYerelUdp.sent.size();
  WiFiUDP::In in; in.data = payload; in.ip = from; in.port = port;
  gYerelUdp.inq.push_back(in);
  yerelKapiKontrolLoop();
  std::vector<std::string> r;
  for (size_t i = once; i < gYerelUdp.sent.size(); i++) {
    if (gYerelUdp.sent[i].ip == from && gYerelUdp.sent[i].port == port) r.push_back(gYerelUdp.sent[i].data);
  }
  return r;
}

static std::vector<std::string> keys_of(JsonDocument& d) {
  std::vector<std::string> k;
  for (JsonPair kv : d.as<JsonObject>()) k.push_back(kv.key().c_str());
  std::sort(k.begin(), k.end());
  return k;
}
static bool keys_eq(JsonDocument& d, std::vector<std::string> beklenen) {
  std::sort(beklenen.begin(), beklenen.end());
  return keys_of(d) == beklenen;
}
static std::string joinkeys(JsonDocument& d) { std::string s; for (auto& k : keys_of(d)) s += k + ","; return s; }

static bool is_lower_hex(const std::string& s, size_t n) {
  if (s.size() != n) return false;
  for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}

static void rolu_birak() { g_fake_ms += 2600; roleLoop(); }

static std::string json_ch_al() {   // uygulama gibi: discover ile guncel ch'yi ogren
  auto r = udp(std::string("{\"action\":\"discover\",\"target_uid\":\"") + UID + "\",\"nonce\":\"dsc\"}");
  JsonDocument d; if (r.size() != 1 || deserializeJson(d, r[0])) return "";
  std::string ch = d["ch"] | "";
  g_gizli.push_back(ch);
  return ch;
}

static std::string acma_paketi(const std::string& action, const std::string& ch, const std::string& sig, const std::string& nonce, const std::string& hedef = UID) {
  g_gizli.push_back(sig);
  return "{\"action\":\"" + action + "\",\"target_uid\":\"" + hedef + "\",\"device_uid\":\"" + hedef + "\",\"ch\":\"" + ch + "\",\"sig\":\"" + sig + "\",\"nonce\":\"" + nonce + "\"}";
}

static std::string http(const std::string& istek, IPAddress from = IPAddress(192, 168, 100, 60)) {
  auto st = std::make_shared<FakeClientState>();
  st->rx = istek; st->rip = from;
  gYerelKapiServer.bekleyen.push_back(st);
  yerelKapiKontrolLoop();
  return st->tx;
}
static std::string http_body(const std::string& resp) { const size_t p = resp.find("\r\n\r\n"); return p == std::string::npos ? "" : resp.substr(p + 4); }

int main() {
  g_fake_ms = 100000;
  g_token = TOKEN;
  g_gizli.push_back(TOKEN);

  // ------------------------------------------------------------------------------------------------ U1 acilis KAT + baslangic
  { printf("U1 acilis HMAC oz-testi (KAT) yerel kontrol baslamadan calisir; ilk turda baslangic + ilk beacon\n");
    CHECK(!gYerelOzTestYapildi && !gYerelHmacSaglam, "baslangicta oz-test yapilmadi, HMAC saglam DEGIL (fail-closed varsayilan)");
    yerelKapiKontrolLoop();
    CHECK(gYerelOzTestYapildi && gYerelHmacSaglam, "KAT gecti -> gYerelHmacSaglam");
    CHECK(Serial.has("HMAC oz-testi basarili"), "seriye oz-test sonucu yazildi");
    CHECK(gYerelUdpAktif && gYerelKapiServerAktif, "yerel kontrol basladi");
    CHECK(is_lower_hex(gYerelDurum.ch, 16), "acilista challenge uretildi (16 kucuk hex)");
    CHECK(gYerelDurum.onceki[0] == '\0', "acilista onceki bos");
    CHECK(g_events.empty(), "oz-test basariliyken MQTT olayi yok");
    CHECK(gYerelUdp.sent.size() == 2, "ilk turda beacon: alt ag yayini + sinirli yayin");
  }

  // ------------------------------------------------------------------------------------------------ U2 beacon
  { printf("U2 beacon biçimi (sartname: device_uid, ip, port, rssi, hw, ch) ve 5 sn / 10 sn tempo\n");
    JsonDocument d;
    CHECK(!deserializeJson(d, gYerelUdp.sent[0].data), "beacon gecerli JSON");
    CHECKF(keys_eq(d, {"device_uid", "ip", "port", "rssi", "hw", "ch"}), "beacon alanlari: %s", joinkeys(d).c_str());
    CHECK(std::string(d["device_uid"] | "") == UID && std::string(d["ip"] | "") == "192.168.100.200" && (d["port"] | 0) == 8765 && (d["rssi"] | 0) == -60, "beacon degerleri");
    CHECK(std::string(d["hw"] | "") == "wroom", "hw=wroom (WROOM derlemesi)");
    CHECK(std::string(d["ch"] | "") == gYerelDurum.ch && is_lower_hex(d["ch"] | "", 16), "beacon ch = guncel challenge");
    CHECK(gYerelUdp.sent[0].ip == IPAddress(192, 168, 100, 255) && gYerelUdp.sent[0].port == 8765, "1. hedef: alt ag yayini:8765");
    CHECK(gYerelUdp.sent[1].ip == IPAddress(255, 255, 255, 255), "2. hedef: sinirli yayin");
    const std::string chA = gYerelDurum.ch;
    const size_t n0 = gYerelUdp.sent.size();
    g_fake_ms = 100000 + 4999; yerelKapiKontrolLoop();
    CHECK(gYerelUdp.sent.size() == n0, "4999 ms: beacon yok");
    g_fake_ms = 100000 + 5000; yerelKapiKontrolLoop();
    CHECK(gYerelUdp.sent.size() == n0 + 2, "5000 ms: yeni beacon");
    { JsonDocument d2; deserializeJson(d2, gYerelUdp.sent[n0].data); CHECK(std::string(d2["ch"] | "") == chA, "5 sn: ch ayni (10 sn'de bir doner)"); }
    g_fake_ms = 100000 + 9999; yerelKapiKontrolLoop();
    CHECK(gYerelDurum.ch == chA, "9999 ms: donme yok");
    g_fake_ms = 100000 + 10000; yerelKapiKontrolLoop();
    CHECK(chA != gYerelDurum.ch && chA == gYerelDurum.onceki, "10000 ms: challenge dondu (onceki = eski guncel)");
    const size_t n1 = gYerelUdp.sent.size();
    CHECK(n1 == n0 + 4, "10 sn: bir beacon daha (5 sn tempo)");
    { JsonDocument d3; deserializeJson(d3, gYerelUdp.sent[n1 - 2].data); CHECK(std::string(d3["ch"] | "") == gYerelDurum.ch, "10 sn beacon'i YENI ch'yi tasir"); }
    g_gizli.push_back(chA);
  }

  // ------------------------------------------------------------------------------------------------ U3 discover
  { printf("U3 discover (ch + local_control_available)\n");
    g_fake_ms += 100;
    auto r = udp(std::string("{\"action\":\"discover\",\"target_uid\":\"") + UID + "\",\"nonce\":\"abc123\"}");
    CHECK(r.size() == 1, "discover yanitlandi");
    JsonDocument d; deserializeJson(d, r[0]);
    CHECKF(keys_eq(d, {"ok", "device_uid", "ip", "port", "ch", "local_control_available", "nonce"}), "discover alanlari: %s", joinkeys(d).c_str());
    CHECK((d["ok"] | false) == true && std::string(d["device_uid"] | "") == UID && std::string(d["ip"] | "") == "192.168.100.200" && (d["port"] | 0) == 8765, "discover degerleri");
    CHECK(std::string(d["ch"] | "") == gYerelDurum.ch, "discover ch = guncel challenge");
    CHECK((d["local_control_available"] | false) == true, "token var -> local_control_available:true");
    CHECK(std::string(d["nonce"] | "") == "abc123", "nonce yansitildi");
    CHECK(udp("{\"action\":\"discover\",\"target_uid\":\"*\"}").size() == 1, "hedef * -> yanit");
    CHECK(udp("{\"action\":\"discover\",\"target_uid\":\"\"}").size() == 1, "hedef bos -> yanit");
    CHECK(udp("{\"action\":\"discover\"}").size() == 1, "hedef yok -> yanit");
    CHECK(udp("{\"action\":\"discover\",\"target_uid\":\"240ac4e2e001\"}").size() == 1, "kucuk harfli hedef -> yanit (buyutulur)");
    CHECK(udp("{\"action\":\"discover\",\"target_uid\":\"AAAAAAAAAAAA\"}").empty(), "baska cihaz hedefi -> yanit YOK");
    auto r2 = udp(std::string("{\"action\":\"discover\",\"target_uid\":\"") + UID + "\",\"nonce\":\"012345678901234567890123456789012\"}");
    JsonDocument d2; deserializeJson(d2, r2[0]);
    CHECK(d2["nonce"].isNull(), "33 karakterlik nonce yansitilmaz");
  }

  // ------------------------------------------------------------------------------------------------ U4 gecerli acma
  { printf("U4 gecerli open: yanit + yan etkiler; challenge yenilenir; Serial'da sir yok\n");
    g_events.clear(); g_display.clear(); g_offline_logs.clear(); g_state_publishes = 0; Serial.clear();
    const std::string ch = json_ch_al();
    const std::string sig = oracle_sig(TOKEN, "open", UID, ch);
    auto r = udp(acma_paketi("open", ch, sig, "n-open-1"));
    CHECK(r.size() == 1, "tek yanit");
    JsonDocument d; deserializeJson(d, r[0]);
    CHECKF(keys_eq(d, {"ok", "message", "device_uid", "nonce"}), "basari alanlari: %s", joinkeys(d).c_str());
    CHECK((d["ok"] | false) == true && std::string(d["message"] | "") == "yerel_kapi_acma_komutu_alindi" && std::string(d["device_uid"] | "") == UID && std::string(d["nonce"] | "") == "n-open-1", "basari yaniti degerleri");
    CHECK(roleAktif && !gDoorLocked, "role tetiklendi, kapi kilidi acik");
    CHECK(g_display.size() == 1 && g_display[0] == "DOOR_OPENED", "ekrana DOOR_OPENED");
    CHECK(g_events.size() == 1 && g_events[0].name == "local_udp_pulse_started", "MQTT olayi local_udp_pulse_started (1 kez)");
    CHECK(g_state_publishes == 1, "durum yayini 1 kez");
    CHECK(g_offline_logs.size() == 1 && g_offline_logs[0] == "local_udp|Yerel UDP|", "offline log: local_udp / Yerel UDP");
    CHECK(gYerelDurum.ch != ch && is_lower_hex(gYerelDurum.ch, 16) && gYerelDurum.onceki[0] == '\0', "basarida challenge yenilendi, onceki bos");
    CHECK(Serial.has("KAPI ACILDI"), "seriye yalniz kabul satiri");
    g_gizli.push_back(gYerelDurum.sonKabulCh);

    // ---- U5 yinelenen paket (istemci UDP kaybina karsi 25 ms sonra ayni paketi yollar)
    printf("U5 yinelenen paket (25 ms sonra ayni ch+sig): duplicate:true, role/log/olay TEKRAR YOK\n");
    const uint32_t sonTetik = roleSonTetikMs;
    g_fake_ms += 25;
    auto r2 = udp(acma_paketi("open", ch, sig, "n-open-1"));
    CHECK(r2.size() == 1, "yinelenene de yanit");
    JsonDocument d2; deserializeJson(d2, r2[0]);
    CHECKF(keys_eq(d2, {"ok", "duplicate", "device_uid", "nonce"}), "duplicate alanlari: %s", joinkeys(d2).c_str());
    CHECK((d2["ok"] | false) == true && (d2["duplicate"] | false) == true && std::string(d2["device_uid"] | "") == UID && std::string(d2["nonce"] | "") == "n-open-1", "duplicate yaniti");
    CHECK(roleSonTetikMs == sonTetik, "role TEKRAR tetiklenmedi");
    CHECK(g_events.size() == 1 && g_offline_logs.size() == 1 && g_display.size() == 1 && g_state_publishes == 1, "olay/log/ekran/durum tekrar yazilmadi");
    CHECK(Serial.count("KAPI ACILDI") == 1, "KAPI ACILDI satiri tek");
    g_fake_ms += 2900;   // toplam ~2925 ms: hala pencerede
    auto r3 = udp(acma_paketi("open", ch, sig, "n-open-1"));
    JsonDocument d3; deserializeJson(d3, r3[0]);
    CHECK((d3["duplicate"] | false) == true, "2925 ms: hala duplicate");
    g_fake_ms += 100;    // ~3025 ms: pencere kapandi -> eski ch artik challenge
    auto r4 = udp(acma_paketi("open", ch, sig, "n-open-1"));
    JsonDocument d4; deserializeJson(d4, r4[0]);
    CHECK(std::string(d4["error"] | "") == "challenge", "3025 ms: pencere kapandi -> challenge");
    CHECK(g_events.size() == 1, "pencere sonrasi da olay tekrar yok");
    rolu_birak();
  }

  // ------------------------------------------------------------------------------------------------ U6 challenge hatalari
  { printf("U6 challenge hatasi (ch yok/eski/bozuk): {ok:false,error:challenge,ch:<guncel>,device_uid}\n");
    g_events.clear(); g_fake_ms += 50;
    const std::string cur = gYerelDurum.ch;
    const std::string sigGecerliBicim(64, 'a');
    std::vector<std::string> paketler = {
      acma_paketi("open", "0000000000000000", sigGecerliBicim, "c1"),
      acma_paketi("open", "", sigGecerliBicim, "c2"),
      acma_paketi("open", "XYZ", sigGecerliBicim, "c3"),
      std::string("{\"action\":\"open\",\"target_uid\":\"") + UID + "\",\"nonce\":\"c4\"}",                       // ch/sig hic yok
      acma_paketi("open", [&] { std::string x = cur; for (auto& c : x) if (c >= 'a' && c <= 'f') c = (char)(c - 32); return x; }(), sigGecerliBicim, "c5"),   // buyuk harf ch
      std::string("{\"action\":\"pulse\",\"target_uid\":\"") + UID + "\",\"ch\":12345,\"sig\":true,\"nonce\":\"c6\"}"   // yanlis tipler
    };
    int i = 0;
    for (const auto& p : paketler) {
      auto r = udp(p); i++;
      CHECKF(r.size() == 1, "paket %d yanitlandi (sessiz yok sayma YOK)", i);
      if (r.size() != 1) continue;
      JsonDocument d; deserializeJson(d, r[0]);
      CHECKF(keys_eq(d, {"ok", "error", "ch", "device_uid", "nonce"}), "challenge alanlari: %s", joinkeys(d).c_str());
      CHECKF((d["ok"] | true) == false && std::string(d["error"] | "") == "challenge" && std::string(d["ch"] | "") == gYerelDurum.ch && std::string(d["device_uid"] | "") == UID,
             "challenge yaniti paket %d", i);
    }
    CHECK(!roleAktif && g_events.empty(), "challenge hatalarinda role/olay yok");
    CHECK(gYerelDurum.ch == cur, "challenge hatalari challenge'i tuketmedi");
    // istemci yeniden dener (tek kez) ve basarir
    const std::string sig = oracle_sig(TOKEN, "pulse", UID, cur);
    auto r = udp(acma_paketi("pulse", cur, sig, "retry"));
    JsonDocument d; deserializeJson(d, r[0]);
    CHECK((d["ok"] | false) == true && std::string(d["message"] | "") == "yerel_kapi_acma_komutu_alindi", "challenge'taki ch ile yeniden deneme basarili (pulse)");
    CHECK(g_events.size() == 1 && g_events[0].name == "local_udp_pulse_started", "pulse de ayni yan etkiler");
    rolu_birak(); g_events.clear();
  }

  // ------------------------------------------------------------------------------------------------ U7 yanlis imza
  { printf("U7 yanlis imza: unauthorized + local_control_available:true; challenge tuketilmez\n");
    g_fake_ms += 50;
    const std::string ch = gYerelDurum.ch;
    std::string sig = oracle_sig(TOKEN, "open", UID, ch);
    std::string bad = sig; bad[63] = bad[63] == '0' ? '1' : '0';
    auto r = udp(acma_paketi("open", ch, bad, "u1"));
    CHECK(r.size() == 1, "yanit var");
    JsonDocument d; deserializeJson(d, r[0]);
    CHECKF(keys_eq(d, {"ok", "error", "device_uid", "local_control_available", "nonce"}), "unauthorized alanlari: %s", joinkeys(d).c_str());
    CHECK((d["ok"] | true) == false && std::string(d["error"] | "") == "unauthorized" && (d["local_control_available"] | false) == true && std::string(d["nonce"] | "") == "u1", "unauthorized yaniti");
    CHECK(!roleAktif && g_events.empty() && gYerelDurum.ch == ch, "role yok, olay yok, challenge ayni");
    CHECK(Serial.has("imza gecersiz"), "seriye NEDEN yazildi");
    auto r2 = udp(acma_paketi("open", ch, std::string(64, '0'), "u2"));
    JsonDocument d2; deserializeJson(d2, r2[0]);
    CHECK(std::string(d2["error"] | "") == "unauthorized", "sifir imza reddedildi");
    auto r3 = udp(acma_paketi("open", ch, "abc", "u3"));
    JsonDocument d3; deserializeJson(d3, r3[0]);
    CHECK(std::string(d3["error"] | "") == "unauthorized", "kisa imza -> unauthorized (net red)");
    g_gizli.push_back(bad);
  }

  // ------------------------------------------------------------------------------------------------ U8 role mesgul
  { printf("U8 role mesgul: {ok:false,error:role_mesgul}; challenge tuketilmez; role bosalinca ayni paket kabul\n");
    g_events.clear(); g_display.clear(); g_fake_ms += 50;
    std::string ch = gYerelDurum.ch;
    auto r0 = udp(acma_paketi("open", ch, oracle_sig(TOKEN, "open", UID, ch), "m0"));
    { JsonDocument d; deserializeJson(d, r0[0]); CHECK((d["ok"] | false) == true, "once bir acma (role mesgul olsun)"); }
    g_events.clear(); g_display.clear();
    g_fake_ms += 1000;                                  // role hala aktif / debounce suruyor
    const std::string ch2 = gYerelDurum.ch;             // basarida yenilenen ch
    const std::string sig2 = oracle_sig(TOKEN, "open", UID, ch2);
    auto r = udp(acma_paketi("open", ch2, sig2, "m1"));
    JsonDocument d; deserializeJson(d, r[0]);
    CHECKF(keys_eq(d, {"ok", "error", "device_uid", "nonce"}), "role_mesgul alanlari: %s", joinkeys(d).c_str());
    CHECK((d["ok"] | true) == false && std::string(d["error"] | "") == "role_mesgul" && std::string(d["nonce"] | "") == "m1", "role_mesgul yaniti");
    CHECK(gYerelDurum.ch == ch2, "role mesgulde challenge TUKETILMEDI");
    CHECK(g_events.empty() && g_display.empty(), "role mesgulde yan etki yok");
    rolu_birak();
    auto r2 = udp(acma_paketi("open", ch2, sig2, "m2"));
    JsonDocument d2; deserializeJson(d2, r2[0]);
    CHECK((d2["ok"] | false) == true && d2["duplicate"].isNull() && std::string(d2["message"] | "") == "yerel_kapi_acma_komutu_alindi", "role bosalinca ayni (ch,sig) basariyla kabul");
    CHECK(g_events.size() == 1, "tek olay");
    rolu_birak(); g_events.clear(); g_display.clear();
  }

  // ------------------------------------------------------------------------------------------------ U9 v1 / token / hedef / kaynak / bozuk
  { printf("U9 v1 `token` paketi, hedef UID uyusmazligi, dis kaynak, bozuk paketler\n");
    g_fake_ms += 50; g_events.clear(); Serial.clear();
    const std::string ch = gYerelDurum.ch;
    // v1: acik metin token, ch/sig yok
    auto r = udp(std::string("{\"action\":\"open\",\"target_uid\":\"") + UID + "\",\"device_uid\":\"" + UID + "\",\"token\":\"" + TOKEN + "\",\"nonce\":\"v1\"}");
    CHECK(r.size() == 1, "v1 paketine NET yanit");
    JsonDocument d; deserializeJson(d, r[0]);
    CHECKF(keys_eq(d, {"ok", "error", "device_uid", "local_control_available", "nonce"}), "v1 red alanlari: %s", joinkeys(d).c_str());
    CHECK((d["ok"] | true) == false && std::string(d["error"] | "") == "unauthorized" && (d["local_control_available"] | false) == true, "v1 token paketi: unauthorized");
    CHECK(!roleAktif && g_events.empty(), "v1 paketi role tetiklemedi (token artik KABUL EDILMEZ)");
    auto rp = udp(std::string("{\"action\":\"pulse\",\"token\":\"") + TOKEN + "\"}");
    JsonDocument dp; deserializeJson(dp, rp[0]);
    CHECK(std::string(dp["error"] | "") == "unauthorized" && !roleAktif, "v1 pulse (hedefsiz) da unauthorized");
    CHECK(!Serial.has(TOKEN), "Serial'da token YOK");
    // v1 + dogru token ile ch/sig de verilmisse: token YOK SAYILIR, imza dogrulanir
    { const std::string sg = oracle_sig(TOKEN, "open", UID, ch);
      auto rv = udp(std::string("{\"action\":\"open\",\"target_uid\":\"") + UID + "\",\"token\":\"" + TOKEN + "\",\"ch\":\"" + ch + "\",\"sig\":\"" + sg + "\"}");
      JsonDocument dv; deserializeJson(dv, rv[0]);
      CHECK((dv["ok"] | false) == true && roleAktif, "ek `token` alani zararsiz yoksayilir; gecerli ch+sig kabul");
      g_gizli.push_back(sg); rolu_birak(); g_events.clear(); }
    // hedef UID uyusmazligi: yanit YOK, role YOK
    g_fake_ms += 1100;   // seri log hiz siniri (1 sn) onceki red satirini bekletmesin
    { const std::string c2 = gYerelDurum.ch; const std::string sg = oracle_sig(TOKEN, "open", "AAAAAAAAAAAA", c2);
      Serial.clear();
      auto rh = udp(acma_paketi("open", c2, sg, "h1", "AAAAAAAAAAAA"));
      CHECK(rh.empty() && !roleAktif && g_events.empty(), "baska cihaza giden paket: yanit yok, role yok");
      CHECK(Serial.has("hedef UID bu cihazla eslesmiyor"), "seriye neden yazildi"); }
    // hedefsiz (bos) acma paketi: bu cihaza yonelik sayilir; imza UID'ye bagli
    { const std::string c2 = gYerelDurum.ch; const std::string sg = oracle_sig(TOKEN, "open", UID, c2);
      auto rh = udp(std::string("{\"action\":\"open\",\"ch\":\"") + c2 + "\",\"sig\":\"" + sg + "\",\"nonce\":\"nh\"}");
      JsonDocument dh; deserializeJson(dh, rh[0]);
      CHECK((dh["ok"] | false) == true, "hedef UID alani yok: imza bu cihazin UID'sine bagli oldugu icin kabul");
      g_gizli.push_back(sg); rolu_birak(); g_events.clear(); }
    // dis kaynak
    { const std::string c2 = gYerelDurum.ch; const std::string sg = oracle_sig(TOKEN, "open", UID, c2);
      auto rd = udp(acma_paketi("open", c2, sg, "d1"), IPAddress(8, 8, 8, 8));
      CHECK(rd.empty() && !roleAktif, "dis (internet) kaynakli paket: yanit yok, role yok");
      auto rd2 = udp("{\"action\":\"discover\"}", IPAddress(8, 8, 8, 8));
      CHECK(rd2.empty(), "dis kaynakli discover'a da yanit yok");
      auto rd3 = udp(acma_paketi("open", c2, sg, "d2"), IPAddress(10, 1, 2, 3));
      CHECK(rd3.size() == 1 && roleAktif, "RFC1918 (10.x) kaynak kabul");
      rolu_birak(); g_events.clear(); }
    // bozuk
    { auto r1 = udp("this is not json"); auto r2 = udp("[1,2,3]"); auto r3 = udp(""); auto r4 = udp(std::string(600, 'x'));
      auto r5 = udp("{\"action\":\"explode\",\"target_uid\":\"" + std::string(UID) + "\"}"); auto r6 = udp("{\"nonce\":\"zz\"}");
      CHECK(r1.empty() && r2.empty() && r3.empty() && r4.empty() && r5.empty() && r6.empty(), "bozuk/bilinmeyen paketlere yanit yok, cokme yok"); }
  }

  // ------------------------------------------------------------------------------------------------ U10 HTTP
  { printf("U10 HTTP: GET /ahbu/status kalir; POST /ahbu/open KALDIRILDI (404); sir sizmaz\n");
    g_events.clear(); g_fake_ms += 3000;
    const std::string st = http("GET /ahbu/status HTTP/1.1\r\nHost: x\r\n\r\n");
    CHECK(st.rfind("HTTP/1.1 200 OK", 0) == 0, "status 200");
    JsonDocument d; deserializeJson(d, http_body(st));
    CHECKF(keys_eq(d, {"ok", "device_uid", "firmware_version", "wifi_connected", "ip", "local_control_port", "local_control_available", "door_locked"}), "status alanlari: %s", joinkeys(d).c_str());
    CHECK((d["ok"] | false) == true && std::string(d["device_uid"] | "") == UID && std::string(d["firmware_version"] | "") == "5.2.0" && (d["local_control_available"] | false) == true, "status degerleri");
    CHECK(st.find(gYerelDurum.ch) == std::string::npos && st.find(TOKEN) == std::string::npos, "status ch/token sizdirmaz");
    const std::string post = http(std::string("POST /ahbu/open HTTP/1.1\r\nHost: x\r\nX-AHBU-Local-Token: ") + TOKEN + "\r\nX-AHBU-Device-UID: " + UID + "\r\nContent-Length: 0\r\n\r\n");
    CHECK(post.rfind("HTTP/1.1 404 Not Found", 0) == 0 && post.find("route_bulunamadi") != std::string::npos, "POST /ahbu/open -> 404 route_bulunamadi (v1 token'li istek olsa bile)");
    CHECK(!roleAktif && g_events.empty(), "POST /ahbu/open role tetiklemez");
    const std::string get_open = http("GET /ahbu/open HTTP/1.1\r\nHost: x\r\n\r\n");
    CHECK(get_open.rfind("HTTP/1.1 404", 0) == 0, "GET /ahbu/open de 404");
    const std::string baska = http("GET /ahbu/status HTTP/1.1\r\nX-AHBU-Device-UID: ZZZZ\r\n\r\n");
    CHECK(baska.rfind("HTTP/1.1 404", 0) == 0 && baska.find("cihaz_uid_eslesmedi") != std::string::npos, "baska UID basligi -> cihaz_uid_eslesmedi");
    const std::string uidok = http(std::string("GET /ahbu/status HTTP/1.1\r\nx-ahbu-device-uid: 240ac4e2e001\r\n\r\n"));
    CHECK(uidok.rfind("HTTP/1.1 200", 0) == 0, "kucuk harfli UID basligi kabul");
    const std::string bad = http("garbage\r\n\r\n");
    CHECK(bad.rfind("HTTP/1.1 400", 0) == 0, "bozuk istek satiri -> 400");
    const std::string buyuk = http("GET /ahbu/status HTTP/1.1\r\nX-Pad: " + std::string(700, 'a') + "\r\n\r\n");
    CHECK(buyuk.rfind("HTTP/1.1 431", 0) == 0, "asiri buyuk istek -> 431");
    const std::string yarim = http("GET /ahbu/status HTTP/1.1\r\nHost: x\r\n");   // baslik sonu hic gelmez
    CHECK(yarim.rfind("HTTP/1.1 400", 0) == 0, "tamamlanmayan istek (zaman asimi) -> 400");
    const std::string dis = http("GET /ahbu/status HTTP/1.1\r\n\r\n", IPAddress(8, 8, 8, 8));
    CHECK(dis.empty(), "dis kaynakli HTTP istemcisi yanitsiz kapatilir");
  }

  // ------------------------------------------------------------------------------------------------ U11 token yok
  { printf("U11 token yok (sunucu henuz gondermedi): unauthorized + local_control_available:false (v1 ile ayni)\n");
    g_events.clear(); g_token = ""; g_fake_ms += 50;
    const std::string ch = gYerelDurum.ch;
    auto r = udp(acma_paketi("open", ch, oracle_sig(TOKEN, "open", UID, ch), "t1"));
    JsonDocument d; deserializeJson(d, r[0]);
    CHECK((d["ok"] | true) == false && std::string(d["error"] | "") == "unauthorized" && (d["local_control_available"] | true) == false && !roleAktif, "token yok: unauthorized, available:false, role yok");
    auto rd = udp("{\"action\":\"discover\"}");
    JsonDocument dd; deserializeJson(dd, rd[0]);
    CHECK((dd["local_control_available"] | true) == false && !std::string(dd["ch"] | "").empty(), "discover: available:false ama ch yine var");
    const std::string st = http("GET /ahbu/status HTTP/1.1\r\n\r\n");
    JsonDocument ds; deserializeJson(ds, http_body(st));
    CHECK((ds["local_control_available"] | true) == false, "status available:false");
    g_token = TOKEN;
  }

  // ------------------------------------------------------------------------------------------------ U12 oz-test basarisiz
  { printf("U12 KAT basarisiz (fail-closed): yerel acma KAPALI, olay MQTT baglaninca bir kez yayinlanir\n");
    g_events.clear(); Serial.clear(); g_mqtt_connected = false;
    gYerelOzTestYapildi = false; gYerelHmacSaglam = false; g_hmac_mode = 2;     // bozuk HMAC
    g_fake_ms += 50; yerelKapiKontrolLoop();
    CHECK(gYerelOzTestYapildi && !gYerelHmacSaglam, "KAT basarisiz -> gYerelHmacSaglam=false");
    CHECK(Serial.has("oz-testi BASARISIZ") && Serial.has("fail-closed"), "seriye UYARI satiri");
    CHECK(gYerelOzTestOlayBekliyor && g_events.empty(), "MQTT yokken olay beklemede");
    g_hmac_mode = 0;   // (testte HMAC'i duzeltsek de oz-test sonucu kalicidir: acma kapali kalir)
    const std::string ch = gYerelDurum.ch;
    auto r = udp(acma_paketi("open", ch, oracle_sig(TOKEN, "open", UID, ch), "f1"));
    JsonDocument d; deserializeJson(d, r[0]);
    CHECK((d["ok"] | true) == false && std::string(d["error"] | "") == "unauthorized" && (d["local_control_available"] | true) == false && !roleAktif && g_events.empty(),
          "gecerli imza bile reddedilir (unauthorized, available:false), role yok");
    auto rd = udp("{\"action\":\"discover\"}");
    JsonDocument dd; deserializeJson(dd, rd[0]);
    CHECK((dd["local_control_available"] | true) == false, "discover available:false");
    CHECK(g_events.empty(), "olay hala yok (MQTT bagli degil)");
    g_mqtt_connected = true; g_fake_ms += 10; yerelKapiKontrolLoop();
    CHECK(g_events.size() == 1 && g_events[0].name == "local_control_selftest_failed" && g_events[0].detail == "hmac_kat", "MQTT baglaninca local_control_selftest_failed olayi");
    CHECK(!gYerelOzTestOlayBekliyor, "olay bayragi dustu");
    g_fake_ms += 10; yerelKapiKontrolLoop(); yerelKapiKontrolLoop();
    CHECK(g_events.size() == 1, "olay tekrar yayinlanmadi");
    // toparlanma (yeniden baslatma benzetimi): HMAC duzgunken oz-test tekrarlanirsa acma yeniden acilir
    g_events.clear(); g_mqtt_connected = false; gYerelOzTestYapildi = false; Serial.clear();
    g_fake_ms += 10; yerelKapiKontrolLoop();
    CHECK(gYerelHmacSaglam && Serial.has("oz-testi basarili"), "duzgun HMAC ile oz-test gecti");
    const std::string ch2 = gYerelDurum.ch;
    auto r2 = udp(acma_paketi("open", ch2, oracle_sig(TOKEN, "open", UID, ch2), "f2"));
    JsonDocument d2; deserializeJson(d2, r2[0]);
    CHECK((d2["ok"] | false) == true && roleAktif, "oz-test gecince yerel acma calisir");
    rolu_birak(); g_events.clear();
  }

  // ------------------------------------------------------------------------------------------------ U13 log hiz siniri
  { printf("U13 reddedilen paket seri log'u hiz sinirli (seriyi bogmaz), sir yazmaz\n");
    Serial.clear(); g_fake_ms += 5000;
    const std::string ch = gYerelDurum.ch;
    for (int i = 0; i < 40; i++) udp(acma_paketi("open", ch, std::string(64, 'b'), "x"));
    CHECKF(Serial.count("imza gecersiz") == 1, "40 red paketi -> 1 log satiri (gelen %d)", Serial.count("imza gecersiz"));
    g_fake_ms += 1000;
    udp(acma_paketi("open", ch, std::string(64, 'b'), "x"));
    CHECKF(Serial.count("imza gecersiz") == 2, "1 sn sonra bir satir daha (gelen %d)", Serial.count("imza gecersiz"));
  }

  // ------------------------------------------------------------------------------------------------ U14 millis sarmasi
  { printf("U14 millis() sarmasi: beacon 5 sn / challenge 10 sn temposu ve acma sarma boyunca dogru\n");
    yerelKapiKontrolDurdur();
    gYerelUdp.sent.clear(); gYerelSonBeaconMs = 0;
    g_fake_ms = 0xFFFFFFFFu - 12000u;                    // sarmaya 12 sn var
    yerelKapiKontrolLoop();                              // yeniden basla: yeni ch, ilk beacon
    std::vector<std::pair<uint32_t, std::string>> beacons;   // (gecen ms, ch)
    const uint32_t t0 = g_fake_ms;
    auto topla = [&](size_t bas) {
      for (size_t i = bas; i < gYerelUdp.sent.size(); i += 2) {   // her beacon iki paket (alt ag + sinirli)
        JsonDocument d; deserializeJson(d, gYerelUdp.sent[i].data);
        beacons.push_back({static_cast<uint32_t>(g_fake_ms - t0), std::string(d["ch"] | "")});
      }
    };
    topla(0);
    std::string onceki = gYerelDurum.ch; int donme = 0;
    bool chTutarli = true;
    for (uint32_t t = 100; t <= 30000; t += 100) {
      g_fake_ms = t0 + t;
      const size_t n = gYerelUdp.sent.size();
      yerelKapiKontrolLoop();
      if (gYerelUdp.sent.size() > n) {
        topla(n);
        if (beacons.back().second != gYerelDurum.ch) chTutarli = false;
      }
      if (gYerelDurum.ch != onceki) { donme++; onceki = gYerelDurum.ch; }
    }
    CHECK(g_fake_ms < 30000, "saat sarildi");
    CHECKF(beacons.size() == 7, "30 sn'de 7 beacon (t=0,5,...,30) bekleniyordu, gelen %zu", beacons.size());
    bool aralik = true; for (size_t i = 1; i < beacons.size(); i++) if (beacons[i].first - beacons[i - 1].first != 5000) aralik = false;
    CHECK(aralik, "beacon araligi sarma boyunca tam 5 sn");
    CHECKF(donme == 3, "30 sn'de 3 challenge donmesi bekleniyordu, gelen %d", donme);
    CHECK(chTutarli, "her beacon o andaki guncel ch'yi tasidi");
    // sarma sonrasi acma (sarmadan once ogrenilen ch ile)
    yerelKapiKontrolDurdur(); gYerelSonBeaconMs = 0;
    g_fake_ms = 0xFFFFFFF0u; yerelKapiKontrolLoop();
    const std::string ch = json_ch_al();
    g_fake_ms += 40;   // sarildi
    CHECK(g_fake_ms < 100, "acma testi: saat sarildi");
    auto r = udp(acma_paketi("open", ch, oracle_sig(TOKEN, "open", UID, ch), "w1"));
    JsonDocument d; deserializeJson(d, r[0]);
    CHECK((d["ok"] | false) == true && roleAktif, "sarmadan once ogrenilen ch sarma sonrasi gecerli");
    g_fake_ms += 25;
    auto r2 = udp(acma_paketi("open", ch, oracle_sig(TOKEN, "open", UID, ch), "w1"));
    JsonDocument d2; deserializeJson(d2, r2[0]);
    CHECK((d2["duplicate"] | false) == true, "sarma sonrasi duplicate penceresi");
    rolu_birak(); g_events.clear();
  }

  // ------------------------------------------------------------------------------------------------ U15 Serial'da sir yok
  { printf("U15 tum senaryolar boyunca Serial ciktisi: token / sig / ch YOK\n");
    int bulunan = 0;
    CHECK(Serial.history.size() > 400 && Serial.hist_has("KAPI ACILDI") && Serial.hist_has("REDDEDILDI"), "Serial gecmisi bos degil (tarama anlamli)");
    for (const auto& s : g_gizli) {
      if (!s.empty() && Serial.hist_has(s)) { bulunan++; printf("  SIZINTI: '%s...' Serial'da\n", s.substr(0, 8).c_str()); }
    }
    CHECKF(bulunan == 0, "%d sir Serial'da bulundu", bulunan);
    // tum Serial gecmisinde (Clear'dan bagimsiz) 16 / 64 karakterlik ardisik kucuk hex dizisi YOK (ch/sig sizintisi)
    { const std::string& h = Serial.history; size_t kos = 0; size_t enUzun = 0;
      for (char c : h) { if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) { kos++; if (kos > enUzun) enUzun = kos; } else kos = 0; }
      CHECKF(enUzun < 16, "Serial gecmisinde %zu karakterlik hex dizisi var", enUzun); }
    printf("  (%zu gizli deger tarandi)\n", g_gizli.size());
  }

  printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
