// Ana makine DIFERANSIYEL / RASTGELE testi: GERCEK yerel_kapi_kontrol.h (UDP v2) karsisinda bagimsiz bir model (sartnameden yazildi).
// Rastgele (gecerli, bozuk, tip karistirilmis, dis kaynakli, kopya, eski ch'li, uzun) paketler rastgele zaman cizelgesinde (millis sarmasi dahil)
// gonderilir; cihazin yaniti / role tetiklemesi / challenge dondurmesi modelinkiyle karsilastirilir. AddressSanitizer ile derlenir (bellek hatalari).
#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WiFiUdp.h>

#include "mbedtls_stub_impl.h"

#define MQTT_BAGLANTI_H
#define OFFLINE_LOG_H
#define OTA_GUNCELLEME_H
#define WIFI_BAGLANTI_H

inline constexpr const char* OTA_CURRENT_VERSION = "5.2.0";
inline bool g_wifi_ready = true;
inline String g_token = "";
inline bool wifiHazirMi() { return g_wifi_ready; }
inline String wifiIpAdresi() { return WiFi.localIP().toString(); }
inline int wifiSinyalDbm() { return -60; }
inline bool wifiHasLocalControlToken() { return !g_token.isEmpty(); }
inline String wifiLocalControlToken() { return g_token; }
inline bool mqttBagliMi() { return false; }
inline int g_olay = 0, g_durum = 0, g_log = 0, g_ekran = 0;
inline bool mqttPublishEvent(const char*, const char* = "", const char* = nullptr) { g_olay++; return true; }
inline bool mqttPublishState(bool) { g_durum++; return true; }
inline void offlineLogKaydet(const char* = "", const char* = "", const char* = "") { g_log++; }
void displayUartSend(const char*) { g_ekran++; }
void displayUartSend(const String&) { g_ekran++; }

#ifdef CORE_PATH
#include CORE_PATH   // mutasyon testi: bozulmus cekirdek (yerel_kapi_kontrol.h bunu korumayla yeniden include etmez)
#endif
#include "yerel_kapi_kontrol.h"

static int g_fail = 0;
static uint64_t g_checks = 0;
#define EXPECT(cond, ...) do { g_checks++; if (!(cond)) { g_fail++; if (g_fail <= 12) { printf("  UYUSMAZLIK (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } } while (0)

static const std::string UID = "240AC4E2E001";
static const std::string TOKEN = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE";
static const std::string OTHER_TOKEN = "ZZZZ_other_token_0123456789_ABCDEFG";

struct Rng {
  uint64_t s;
  explicit Rng(uint64_t seed) : s(seed * 0x9E3779B97F4A7C15ULL + 0x1234567ULL) { for (int i = 0; i < 4; i++) next(); }
  uint32_t next() { s ^= s >> 12; s ^= s << 25; s ^= s >> 27; return static_cast<uint32_t>((s * 2685821657736338717ULL) >> 32); }
  int range(int a, int b) { return a + static_cast<int>(next() % static_cast<uint32_t>(b - a + 1)); }   // [a,b]
  bool chance(int pct) { return static_cast<int>(next() % 100) < pct; }
  template <class T> const T& pick(const std::vector<T>& v) { return v[next() % v.size()]; }
};

static std::string oracle_sig(const std::string& token, const std::string& action, const std::string& uid, const std::string& ch) {
  const std::string msg = action + "|" + uid + "|" + ch;
  uint8_t mac[32];
  refcrypto::hmac_sha256(reinterpret_cast<const uint8_t*>(token.data()), token.size(), reinterpret_cast<const uint8_t*>(msg.data()), msg.size(), mac);
  char hex[65]; refcrypto::to_hex(mac, 32, hex); return hex;
}
static bool is_hex(const std::string& s, size_t n) {
  if (s.size() != n) return false;
  for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}
static std::string upper(std::string s) { for (auto& c : s) c = static_cast<char>(toupper(static_cast<unsigned char>(c))); return s; }
static std::string trim(const std::string& s) { size_t b = 0, e = s.size(); while (b < e && isspace(static_cast<unsigned char>(s[b]))) b++; while (e > b && isspace(static_cast<unsigned char>(s[e - 1]))) e--; return s.substr(b, e - b); }

// ---- paket tanimi ------------------------------------------------------------------------------------------------------------
struct Fld {
  enum T { ABS, STR, NUM, NUL, BOOL, ARR } t = ABS;
  std::string s;
  bool isStr() const { return t == STR; }
  std::string str() const { return t == STR ? s : std::string(); }
};
struct Spec {
  enum K { JSON, RAW, BROKEN } kind = JSON;
  Fld action, target, devuid, ch, sig, token, nonce;
  std::string pad;          // uzun dolgu (oversize)
  std::string raw;          // RAW / BROKEN govde
  IPAddress src = IPAddress(192, 168, 100, 50);
  bool srcLocal = true;
};
static std::string render1(const Fld& f, const char* key) {
  std::string v;
  switch (f.t) {
    case Fld::ABS: return "";
    case Fld::STR: v = "\"" + f.s + "\""; break;
    case Fld::NUM: v = "12345"; break;
    case Fld::NUL: v = "null"; break;
    case Fld::BOOL: v = "true"; break;
    case Fld::ARR: v = "[\"x\"]"; break;
  }
  return std::string("\"") + key + "\":" + v;
}
static std::string render(const Spec& sp, Rng& r) {
  if (sp.kind == Spec::RAW) return sp.raw;
  std::vector<std::string> parts;
  auto add = [&](const std::string& p) { if (!p.empty()) parts.push_back(p); };
  add(render1(sp.action, "action")); add(render1(sp.target, "target_uid")); add(render1(sp.devuid, "device_uid"));
  add(render1(sp.ch, "ch")); add(render1(sp.sig, "sig")); add(render1(sp.token, "token")); add(render1(sp.nonce, "nonce"));
  if (!sp.pad.empty()) add("\"pad\":\"" + sp.pad + "\"");
  for (size_t i = parts.size(); i > 1; i--) std::swap(parts[i - 1], parts[r.next() % i]);   // anahtar sirasi rastgele
  std::string js = "{";
  for (size_t i = 0; i < parts.size(); i++) { if (i) js += ","; js += parts[i]; }
  js += "}";
  if (sp.kind == Spec::BROKEN) js = js.substr(0, js.size() - 1);   // son '}' dusurulur: GECERSIZ JSON
  return js;
}

// ---- model -------------------------------------------------------------------------------------------------------------------------
enum Beklenen { B_YOKSAY, B_UNAUTH, B_DUP, B_CHALLENGE, B_ROLE, B_OK, B_DISCOVER };
struct Model {
  std::string cur, prev;
  uint64_t genT = 0;
  bool accVar = false; std::string accCh, accSig, accAction; uint64_t accT = 0;
  bool trigVar = false; uint64_t trigT = 0;
  std::vector<std::string> eskiler;    // gecmis ch'ler
  bool tokenVar = true, hmacOk = true;
};

static bool kaynakYerel(const IPAddress& ip) {
  const uint8_t a = ip[0], b = ip[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  if (a == 169 && b == 254) return true;
  return false;   // test altagi 192.168.100.0/24 zaten ozel
}

static Beklenen siniflandir(const Spec& sp, Model& m, uint64_t t, const std::string& jsonGovde, bool relayBos, std::string& hedefNonce, bool& nonceVar) {
  nonceVar = false; hedefNonce.clear();
  if (!sp.srcLocal) return B_YOKSAY;
  if (sp.kind != Spec::JSON) return B_YOKSAY;
  if (jsonGovde.size() >= 512) return B_YOKSAY;
  const std::string action = sp.action.str();
  if (action != "open" && action != "pulse" && action != "discover") return B_YOKSAY;
  // hedef: target_uid metinse o, degilse device_uid metinse o, degilse bos
  std::string hedef = sp.target.isStr() ? sp.target.s : (sp.devuid.isStr() ? sp.devuid.s : "");
  hedef = upper(trim(hedef));
  if (action == "discover") {
    if (!(hedef.empty() || hedef == UID || hedef == "*")) return B_YOKSAY;
    if (sp.nonce.isStr() && sp.nonce.s.size() <= 32) { nonceVar = true; hedefNonce = sp.nonce.s; }
    return B_DISCOVER;
  }
  if (!hedef.empty() && hedef != UID) return B_YOKSAY;
  if (sp.nonce.isStr() && sp.nonce.s.size() <= 32) { nonceVar = true; hedefNonce = sp.nonce.s; }
  const bool eskiBicim = (sp.token.t != Fld::ABS && sp.token.t != Fld::NUL) && !sp.sig.isStr();
  if (eskiBicim) return B_UNAUTH;
  if (!m.tokenVar || !m.hmacOk) return B_UNAUTH;
  const std::string ch = sp.ch.str(), sig = sp.sig.str();
  const bool chF = is_hex(ch, 16), sigF = is_hex(sig, 64);
  if (chF && sigF && m.accVar && m.accAction == action && ch == m.accCh && sig == m.accSig && t - m.accT < 3000) return B_DUP;
  if (!chF || !(ch == m.cur || (!m.prev.empty() && ch == m.prev))) return B_CHALLENGE;
  if (!sigF || sig != oracle_sig(TOKEN, action, UID, ch)) return B_UNAUTH;
  if (!relayBos) return B_ROLE;
  return B_OK;
}

// ---- cihaz surucusu ----------------------------------------------------------------------------------------------------------------
static uint32_t g_start = 0;
static uint64_t g_t = 0;            // mutlak ms (64 bit)
static void cihazSaati() { g_fake_ms = static_cast<uint32_t>(g_start + g_t); }

static void adimAt(Model& m, uint64_t dt, bool cokBlokeli) {
  // dt'yi gercek loop gibi kucuk adimlara boler (cokBlokeli: tek adim = loop uzun sure bloke kaldi)
  uint64_t kalan = dt;
  while (kalan > 0) {
    const uint64_t a = cokBlokeli ? kalan : std::min<uint64_t>(kalan, 200);
    g_t += a; kalan -= a;
    cihazSaati();
    roleLoop();
    // model: challenge donmesi (tick aninda)
    const uint64_t gecen = g_t - m.genT;
    const std::string eskiCur = m.cur;
    yerelKapiKontrolLoop();
    if (gecen >= 10000) {
      EXPECT(std::string(gYerelDurum.ch) != eskiCur, "t=%llu: %llu ms sonra challenge donmedi", static_cast<unsigned long long>(g_t), static_cast<unsigned long long>(gecen));
      if (gecen >= 20000) EXPECT(std::string(gYerelDurum.onceki).empty(), "t=%llu: >=20 sn sonra onceki bosalmali", static_cast<unsigned long long>(g_t));
      else EXPECT(std::string(gYerelDurum.onceki) == eskiCur, "t=%llu: onceki = eski guncel olmali", static_cast<unsigned long long>(g_t));
      m.eskiler.push_back(eskiCur); if (m.eskiler.size() > 8) m.eskiler.erase(m.eskiler.begin());
      m.cur = gYerelDurum.ch; m.prev = gYerelDurum.onceki; m.genT = g_t;
    } else {
      EXPECT(std::string(gYerelDurum.ch) == m.cur && std::string(gYerelDurum.onceki) == m.prev, "t=%llu: challenge beklenmedik sekilde degisti", static_cast<unsigned long long>(g_t));
    }
    if (m.accVar && g_t - m.accT >= 3000) m.accVar = false;
    gYerelUdp.sent.clear();   // beacon birikimi
  }
}

static Fld S(const std::string& s) { Fld f; f.t = Fld::STR; f.s = s; return f; }
static Fld T(Fld::T t) { Fld f; f.t = t; return f; }

static std::string rndHex(Rng& r, size_t n) { static const char* H = "0123456789abcdef"; std::string s; for (size_t i = 0; i < n; i++) s += H[r.next() % 16]; return s; }
static std::string rndSafe(Rng& r, size_t n) { static const char* A = "abcXYZ019_-.:"; std::string s; for (size_t i = 0; i < n; i++) s += A[r.next() % 13]; return s; }

static Fld uretCh(Rng& r, Model& m) {
  switch (r.range(0, 13)) {
    case 0: case 1: case 2: case 3: return S(m.cur);
    case 4: case 5: return m.prev.empty() ? S(m.cur) : S(m.prev);
    case 6: return m.eskiler.empty() ? S(rndHex(r, 16)) : S(r.pick(m.eskiler));
    case 7: return S(rndHex(r, 16));
    case 8: { std::string x = m.cur; x[r.next() % 16] = x[r.next() % 16] == '0' ? '1' : '0'; return S(x); }
    case 9: return S(upper(m.cur));
    case 10: return S(m.cur.substr(0, r.range(0, 15)));
    case 11: return S(m.cur + rndHex(r, r.range(1, 3)));
    case 12: return r.chance(50) ? Fld() : S("");
    default: { Fld f; f.t = static_cast<Fld::T>(r.range(2, 5)); return f; }
  }
}
static Fld uretSig(Rng& r, const std::string& action, const std::string& ch, bool chStr) {
  const std::string a = action.empty() ? "open" : action;
  const std::string dogru = oracle_sig(TOKEN, a, UID, chStr ? ch : "");
  switch (r.range(0, 13)) {
    case 0: case 1: case 2: case 3: case 4: case 5: return S(dogru);
    case 6: { std::string x = dogru; size_t i = r.next() % 64; x[i] = x[i] == '0' ? '1' : '0'; return S(x); }
    case 7: return S(oracle_sig(TOKEN, a == "open" ? "pulse" : "open", UID, ch));
    case 8: return S(oracle_sig(TOKEN, a, "240AC4E2E002", ch));
    case 9: return S(oracle_sig(OTHER_TOKEN, a, UID, ch));
    case 10: return S(upper(dogru));
    case 11: return S(dogru.substr(0, r.range(0, 63)));
    case 12: return S(rndHex(r, 64));
    default: { Fld f; f.t = static_cast<Fld::T>(r.range(0, 5)); return f; }
  }
}
static Fld uretAction(Rng& r) {
  switch (r.range(0, 9)) {
    case 0: case 1: case 2: case 3: return S("open");
    case 4: case 5: case 6: return S("pulse");
    case 7: return S(r.pick(std::vector<std::string>{"OPEN", "close", "", "open ", "pulse2", "discover"}));
    default: { Fld f; f.t = static_cast<Fld::T>(r.range(0, 5)); return f; }
  }
}
static Fld uretHedef(Rng& r) {
  switch (r.range(0, 9)) {
    case 0: case 1: case 2: case 3: return S(UID);
    case 4: return S("240ac4e2e001");
    case 5: return S(" 240AC4E2E001 ");
    case 6: return S("");
    case 7: return S(r.pick(std::vector<std::string>{"240AC4E2E002", "*", "AAAAAAAAAAAA"}));
    case 8: return Fld();
    default: { Fld f; f.t = static_cast<Fld::T>(r.range(2, 5)); return f; }
  }
}

static std::string gonder(Spec sp, Rng& r, Model& m, const char* ad) {
  // paketi uret + cihaza ver + yaniti dondur ("" = yanit yok)
  const std::string js = render(sp, r);
  const uint32_t port = 40000 + (r.next() % 20000);
  WiFiUDP::In in; in.data = js; in.ip = sp.src; in.port = static_cast<uint16_t>(port);
  gYerelUdp.inq.push_back(in);
  // loop turu (zaman ilerlemez; paket bu anda islenir). Model: once donme (tick) uygulanir
  const uint64_t gecen = g_t - m.genT;
  (void)gecen;
  const std::string eskiCur = m.cur;
  const bool relayBos = !(m.trigVar && g_t - m.trigT < 2500);
  std::string nonce; bool nonceVar;
  const Beklenen be = siniflandir(sp, m, g_t, js, relayBos, nonce, nonceVar);
  const int olay0 = g_olay, log0 = g_log, ekran0 = g_ekran, dur0 = g_durum;
  const unsigned long sonTetik0 = roleSonTetikMs;
  yerelKapiKontrolLoop();
  std::string yanit; size_t n = 0;
  for (auto& o : gYerelUdp.sent) if (o.ip == sp.src && o.port == port) { yanit = o.data; n++; }
  gYerelUdp.sent.clear();
  const bool roleTetiklendi = (roleSonTetikMs != sonTetik0);
  if (be == B_YOKSAY) {
    EXPECT(n == 0, "[%s] yoksayilmasi gereken paket yanit aldi: %s", ad, yanit.c_str());
    EXPECT(!roleTetiklendi && g_olay == olay0, "[%s] yoksayilan paket role/olay tetikledi", ad);
    return "";
  }
  EXPECT(n == 1, "[%s] beklenen 1 yanit, gelen %zu (js=%s)", ad, n, js.substr(0, 120).c_str());
  if (n != 1) return yanit;
  JsonDocument d;
  const bool parseHata = !!deserializeJson(d, yanit);
  EXPECT(!parseHata, "[%s] yanit JSON degil: %s", ad, yanit.c_str());
  if (parseHata) return yanit;
  EXPECT(std::string(d["device_uid"] | "") == UID, "[%s] device_uid yok/yanlis", ad);
  if (nonceVar) EXPECT(std::string(d["nonce"] | "") == nonce, "[%s] nonce yansitilmadi", ad);
  else EXPECT(d["nonce"].isNull(), "[%s] beklenmeyen nonce", ad);
  const std::string err = d["error"] | "";
  const bool ok = d["ok"] | false;
  const bool kullanilabilir = m.tokenVar && m.hmacOk;
  switch (be) {
    case B_UNAUTH:
      EXPECT(!ok && err == "unauthorized" && (d["local_control_available"] | !kullanilabilir) == kullanilabilir && !roleTetiklendi,
             "[%s] unauthorized bekleniyordu: %s (js=%s)", ad, yanit.c_str(), js.substr(0, 160).c_str());
      break;
    case B_DUP:
      EXPECT(ok && (d["duplicate"] | false) && !roleTetiklendi && g_olay == olay0 && g_log == log0 && g_ekran == ekran0,
             "[%s] duplicate bekleniyordu / yan etki: %s", ad, yanit.c_str());
      break;
    case B_CHALLENGE:
      EXPECT(!ok && err == "challenge" && std::string(d["ch"] | "") == m.cur && !roleTetiklendi, "[%s] challenge bekleniyordu: %s (js=%s)", ad, yanit.c_str(), js.substr(0, 160).c_str());
      break;
    case B_DISCOVER:
      EXPECT(ok && err.empty() && std::string(d["ch"] | "") == m.cur && (d["local_control_available"] | !kullanilabilir) == kullanilabilir && (d["port"] | 0) == 8765 &&
             std::string(d["ip"] | "") == "192.168.100.200" && !roleTetiklendi, "[%s] discover yaniti: %s", ad, yanit.c_str());
      break;
    case B_ROLE:
      EXPECT(!ok && err == "role_mesgul" && !roleTetiklendi && std::string(gYerelDurum.ch) == m.cur, "[%s] role_mesgul bekleniyordu: %s", ad, yanit.c_str());
      break;
    case B_OK: {
      EXPECT(ok && d["duplicate"].isNull() && std::string(d["message"] | "") == "yerel_kapi_acma_komutu_alindi", "[%s] OK bekleniyordu: %s (js=%s)", ad, yanit.c_str(), js.substr(0, 160).c_str());
      EXPECT(roleTetiklendi && g_olay == olay0 + 1 && g_log == log0 + 1 && g_ekran == ekran0 + 1 && g_durum == dur0 + 1, "[%s] kabulde role + tam bir kez yan etki bekleniyordu", ad);
      const std::string action = sp.action.str();
      m.accVar = true; m.accCh = sp.ch.str(); m.accSig = sp.sig.str(); m.accAction = action; m.accT = g_t;
      m.trigVar = true; m.trigT = g_t;
      EXPECT(std::string(gYerelDurum.ch) != eskiCur && std::string(gYerelDurum.onceki).empty(), "[%s] kabul sonrasi challenge yenilenmeli, onceki bos", ad);
      m.eskiler.push_back(eskiCur); if (m.eskiler.size() > 8) m.eskiler.erase(m.eskiler.begin());
      m.cur = gYerelDurum.ch; m.prev = gYerelDurum.onceki; m.genT = g_t;
      break;
    }
    default: break;
  }
  return yanit;
}

int main(int argc, char** argv) {
  const int seed0 = argc > 1 ? atoi(argv[1]) : 1;
  const int seeds = argc > 2 ? atoi(argv[2]) : 8;
  const int olaySayisi = argc > 3 ? atoi(argv[3]) : 20000;
  uint64_t toplamPaket = 0;
  std::map<int, uint64_t> dagilim;
  for (int seed = seed0; seed < seed0 + seeds; seed++) {
    Rng r(static_cast<uint64_t>(seed));
    g_rng_state = 0x9E3779B97F4A7C15ULL ^ (static_cast<uint64_t>(seed) * 0xD1B54A32D192ED03ULL);
    // saat baslangici: sarma civari / rastgele
    const uint32_t baslar[] = {0u, 5000u, 0xFFFFFFFFu - 30000u, 0xFFFFFFFFu - 3000u, 0xFFFFFFF0u, 0x7FFFFFFFu - 5000u, 0x80000000u - 100u, static_cast<uint32_t>(r.next())};
    g_start = baslar[seed % 8];
    g_t = 0; cihazSaati();
    // cihazi sifirla (inline global'ler)
    yerelKapiKontrolDurdur();
    g_token = String(TOKEN.c_str()); g_wifi_ready = true; gYerelOzTestYapildi = false; gYerelHmacSaglam = false; g_hmac_mode = 0;
    gYerelSonBeaconMs = 0; gYerelSonLogVar = false; roleAktif = false; roleSonTetikMs = 0;
    Serial.clear();
    yerelKapiKontrolLoop();   // KAT + baslat
    Model m; m.cur = gYerelDurum.ch; m.prev = ""; m.genT = g_t;
    EXPECT(gYerelHmacSaglam && is_hex(m.cur, 16), "seed %d: baslangic", seed);
    Spec sonGecerli; bool sonVar = false;
    for (int ev = 0; ev < olaySayisi; ev++) {
      // ---- zaman ilerlet
      const int zr = r.range(0, 99);
      if (zr < 35) adimAt(m, static_cast<uint64_t>(r.range(0, 30)), false);
      else if (zr < 55) adimAt(m, 25, false);
      else if (zr < 75) adimAt(m, static_cast<uint64_t>(r.range(100, 3500)), false);
      else if (zr < 92) adimAt(m, static_cast<uint64_t>(r.range(3500, 12000)), false);
      else if (zr < 97) adimAt(m, static_cast<uint64_t>(r.range(12000, 60000)), true);     // loop uzun sure bloke
      else adimAt(m, static_cast<uint64_t>(r.range(60000, 400000)), false);
      // ---- ortam degisimi (nadiren): token yok / HMAC bozuk
      if (r.chance(1)) { m.tokenVar = !m.tokenVar; g_token = m.tokenVar ? String(TOKEN.c_str()) : String(""); }
      if (r.chance(1)) { m.hmacOk = !m.hmacOk; gYerelHmacSaglam = m.hmacOk; }
      // ---- paket
      Spec sp;
      const int pr = r.range(0, 99);
      if (pr < 6) { sp.kind = Spec::RAW; const int n = r.range(0, 700); for (int i = 0; i < n; i++) sp.raw += static_cast<char>(r.range(1, 255)); }
      else {
        if (pr < 12) sp.kind = Spec::BROKEN;
        sp.action = uretAction(r);
        const bool chStr = true;
        sp.ch = uretCh(r, m);
        sp.sig = uretSig(r, sp.action.str(), sp.ch.str(), chStr && sp.ch.isStr());
        sp.target = uretHedef(r);
        if (r.chance(40)) sp.devuid = uretHedef(r);
        if (r.chance(10)) sp.token = r.chance(50) ? S(TOKEN) : (r.chance(50) ? T(Fld::NUL) : T(Fld::NUM));
        if (r.chance(60)) sp.nonce = r.chance(85) ? S(rndSafe(r, r.range(0, 40))) : T(Fld::NUM);
        if (r.chance(4)) sp.pad = std::string(r.range(300, 600), 'p');
        if (r.chance(12)) { sp.srcLocal = false; sp.src = r.pick(std::vector<IPAddress>{IPAddress(8, 8, 8, 8), IPAddress(172, 15, 0, 1), IPAddress(172, 32, 0, 1), IPAddress(11, 0, 0, 1), IPAddress(100, 64, 0, 1)}); }
        else if (r.chance(15)) { sp.src = r.pick(std::vector<IPAddress>{IPAddress(10, 1, 2, 3), IPAddress(172, 20, 1, 1), IPAddress(192, 168, 1, 7), IPAddress(169, 254, 3, 3)}); }
        // kopya: son gecerli paketi aynen tekrarla
        if (sonVar && r.chance(18)) { sp = sonGecerli; if (r.chance(30)) sp.nonce = S(rndSafe(r, 6)); }
      }
      const std::string yan = gonder(sp, r, m, "fuzz");
      dagilim[static_cast<int>(yan.empty() ? -1 : (yan.find("duplicate") != std::string::npos ? 1 : yan.find("\"ok\":true") != std::string::npos ? 2 : yan.find("challenge") != std::string::npos ? 3 : yan.find("role_mesgul") != std::string::npos ? 4 : 5))]++;
      toplamPaket++;
      if (sp.kind == Spec::JSON && yan.find("yerel_kapi_acma_komutu_alindi") != std::string::npos) { sonGecerli = sp; sonVar = true; }
      // ---- degismezler
      EXPECT(is_hex(gYerelDurum.ch, 16) && (gYerelDurum.onceki[0] == '\0' || is_hex(gYerelDurum.onceki, 16)), "challenge bicimi bozuldu");
      if (ev % 1500 == 0) {
        // Serial'da token / 16+ hex dizisi yok
        EXPECT(!Serial.has(TOKEN) && !Serial.has(OTHER_TOKEN), "token Serial'da");
        size_t kos = 0, enUzun = 0;
        for (char c : Serial.all) { if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) { kos++; if (kos > enUzun) enUzun = kos; } else kos = 0; }
        EXPECT(enUzun < 16, "Serial'da %zu karakterlik hex dizisi (sizinti)", enUzun);
        Serial.clear(); Serial.history.clear();
      }
    }
    if (seed == seed0) printf("  (ilk tohum %d: %d olay, kalan role aktif=%d)\n", seed, olaySayisi, roleAktif ? 1 : 0);
    Serial.clear(); Serial.history.clear();
  }
  printf("  paket sayisi: %llu; yanit dagilimi: yanitsiz=%llu duplicate=%llu basari=%llu challenge=%llu role_mesgul=%llu unauthorized=%llu\n",
         static_cast<unsigned long long>(toplamPaket), static_cast<unsigned long long>(dagilim[-1]), static_cast<unsigned long long>(dagilim[1]),
         static_cast<unsigned long long>(dagilim[2]), static_cast<unsigned long long>(dagilim[3]), static_cast<unsigned long long>(dagilim[4]),
         static_cast<unsigned long long>(dagilim[5]));
  printf("\nSONUC: %llu dogrulama gecti, %d basarisiz\n", static_cast<unsigned long long>(g_checks - g_fail), g_fail);
  return g_fail == 0 ? 0 : 1;
}
