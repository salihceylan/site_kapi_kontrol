// Ana makine testi: GERCEK cihaz_kontrol/include/gm60_scanner.h (QR okuma korumalari) + gercek role_kontrol.h / device_konfig.h.
// MQTT yayini, ekran UART'i ve GM60 seri hatti sahte; saat sahte (32 bit).
#include <Arduino.h>
#include <Preferences.h>

#define OFFLINE_LOG_H   // agir baslik etkisiz (gm60_scanner.h yalniz include eder)

#ifndef GM60_PATH
#define GM60_PATH "gm60_scanner.h"
#endif

// gm60_scanner.h'in on-bildirdigi MQTT fonksiyonlari (testte sahte)
static bool g_mqtt_bagli = true;
static bool g_yayin_basarili = true;
struct Yayin { std::string token; uint32_t id; };
static std::vector<Yayin> g_yayinlar;
bool mqttPublishQrVerify(const String& qrToken, uint32_t requestId) {
  if (!g_yayin_basarili) return false;
  g_yayinlar.push_back({qrToken.s, requestId});
  return true;
}
bool mqttBagliMi() { return g_mqtt_bagli; }
static std::vector<std::string> g_ekran;
void displayUartSend(const char* c) { g_ekran.push_back(c); }
void displayUartSend(const String& c) { g_ekran.push_back(c.c_str()); }

#include GM60_PATH

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL: %s  (satir %d)\n", msg, __LINE__); } } while (0)
#define CHECKF(cond, ...) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static int ekran_say(const char* k) { int n = 0; for (auto& s : g_ekran) if (s == k) n++; return n; }

// Taze durumla baslar (inline global'leri sifirlar)
static void sifirla(uint32_t baslangic) {
  gm60Buffer = ""; gm60TamponTasti = false; gm60SonOkumaMs = 0; gm60SonKarakterMs = 0; gm60Aktif = true; gm60Bagli = false;
  gm60SonGonderilenToken = ""; gm60SonGonderilenMs = 0; gm60AtlamaGeriBildirimYapildi = false;
  gm60SunucuYanitBekleniyor = false; gm60SunucuYanitBaslangicMs = 0; gm60IstekSayac = 0; gm60BekleyenIstekId = 0;
  g_yayinlar.clear(); g_ekran.clear(); g_mqtt_bagli = true; g_yayin_basarili = true;
  roleAktif = false; roleSonTetikMs = 0;
  g_fake_ms = baslangic;
  Serial.clear();
}
static void oku(const char* tok) { gm60QrVerisiniIsle(String(tok)); }
// qr_result benzetimi (mqttHandleQrResult'in gm60 tarafi): kabul + (ret ise) token unut
static bool sonuc(bool izin) {
  if (g_yayinlar.empty()) return false;
  if (!gm60SunucuYanitiKabulEt(true, g_yayinlar.back().id)) return false;
  if (!izin) { displayUartSend(CMD_QR_DENIED); gm60AyniQrYenidenDenensin(); }
  return true;
}

int main() {
  // ------------------------------------------------------------------------------------------------ G0 sabitler
  { printf("G0 sabitler\n");
    CHECK(GM60_TOKEN_TEKRAR_SURESI_MS == 8000UL, "GM60_TOKEN_TEKRAR_SURESI_MS = 8000 (sabit adi korunur)");
    CHECK(GM60_SUNUCU_YANITLAMA_TIMEOUT_MS == 10000UL, "sunucu yanit zaman asimi 10 sn (degismedi)");
  }

  // ------------------------------------------------------------------------------------------------ G1 seri hattan tam akis
  { printf("G1 seri hattan okuma -> qr_verify yayini + QR_READING\n");
    sifirla(100000);
    GM60Serial.feed("GUESTTOKEN1\r\n");
    gm60Loop();
    CHECK(g_yayinlar.size() == 1 && g_yayinlar[0].token == "GUESTTOKEN1", "token qr_verify ile yayinlandi");
    CHECK(ekran_say("QR_READING") == 1, "ekrana QR_READING");
    CHECK(gm60SunucuYanitBekleniyor && gm60SonGonderilenToken == "GUESTTOKEN1", "yanit bekleniyor, token kaydedildi");
    CHECK(!Serial.hist_has("GUESTTOKEN1"), "QR icerigi seriye yazilmaz");
    // sonlandiricisiz okuma: 50 ms sessizlik sonrasi islenir
    sifirla(200000);
    GM60Serial.feed("NOEOL");
    gm60Loop(); CHECK(g_yayinlar.empty(), "sonlandirici yok, henuz islenmedi");
    g_fake_ms += 60; gm60Loop();
    CHECK(g_yayinlar.size() == 1 && g_yayinlar[0].token == "NOEOL", "50 ms sessizlikte islendi");
  }

  // ------------------------------------------------------------------------------------------------ G2 basarili kabul: 8 sn tekrar penceresi
  { printf("G2 basarili kabul sonrasi ayni token: 5 sn debounce, 8 sn tekrar penceresi, kabul basina TEK geri bildirim\n");
    sifirla(100000);
    oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 1, "ilk okuma yayinlandi");
    CHECK(sonuc(true), "sunucu onayladi");
    g_ekran.clear();
    g_fake_ms = 100000 + 1000; oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 1 && g_ekran.empty(), "1 sn: debounce, SESSIZ (ekran titremez)");
    g_fake_ms = 100000 + 4999; oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 1 && g_ekran.empty(), "4999 ms: debounce, sessiz");
    g_fake_ms = 100000 + 5000; oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 1, "5 sn: ayni token hala 8 sn penceresinde -> gonderilmez");
    CHECK(ekran_say("QR_READING") == 1, "5 sn: kullaniciya BIR kez QR_READING geri bildirimi");
    g_fake_ms = 100000 + 6500; oku("MULTIUSE");
    g_fake_ms = 100000 + 7500; oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 1 && ekran_say("QR_READING") == 1, "tekrar okumalar: yayin yok, geri bildirim TEKRARLANMAZ (titreme yok)");
    g_fake_ms = 100000 + 7999; oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 1, "7999 ms: hala atlanir");
    g_fake_ms = 100000 + 8000; oku("MULTIUSE");
    CHECK(g_yayinlar.size() == 2 && g_yayinlar[1].token == "MULTIUSE", "8000 ms: ikinci kisi ayni QR ile gecebilir (eskiden 30 sn beklerdi)");
    CHECK(g_yayinlar[1].id == g_yayinlar[0].id + 1, "yeni istek kimligi");
    CHECK(Serial.hist_has("tekrar atlaniyor"), "seriye atlama nedeni yazildi");
    // geri bildirim yeni kabulle yeniden hakkini kazanir
    CHECK(sonuc(true), "ikinci onay");
    g_ekran.clear(); g_fake_ms = 108000 + 5000; oku("MULTIUSE");
    CHECK(ekran_say("QR_READING") == 1 && g_yayinlar.size() == 2, "yeni kabul sonrasi geri bildirim yeniden (kabul basina bir)");
  }

  // ------------------------------------------------------------------------------------------------ G3 role aktifken geri bildirim yok
  { printf("G3 kapi acik (role aktif) iken atlama geri bildirimi gonderilmez (kapi acik ekranini ezmez)\n");
    sifirla(100000);
    oku("T1"); sonuc(true); g_ekran.clear();
    roleAktif = true;
    g_fake_ms = 100000 + 5500; oku("T1");
    CHECK(g_yayinlar.size() == 1 && g_ekran.empty(), "role aktif: geri bildirim yok");
    roleAktif = false;
    g_fake_ms = 100000 + 6000; oku("T1");
    CHECK(ekran_say("QR_READING") == 1, "role birakilinca geri bildirim");
    roleAktif = false;
  }

  // ------------------------------------------------------------------------------------------------ G4 sunucu reddi
  { printf("G4 sunucu reddi sonrasi AYNI QR yeniden denenebilir (5 sn debounce gecerli)\n");
    sifirla(100000);
    oku("DENYME");
    CHECK(sonuc(false), "sunucu reddetti (qr_result allowed=false)");
    CHECK(gm60SonGonderilenToken == "" , "red sonrasi token unutuldu");
    g_ekran.clear();
    g_fake_ms = 100000 + 2000; oku("DENYME");
    CHECK(g_yayinlar.size() == 1, "2 sn: 5 sn debounce hala gecerli -> gonderilmez");
    g_fake_ms = 100000 + 5000; oku("DENYME");
    CHECK(g_yayinlar.size() == 2 && g_yayinlar[1].token == "DENYME", "5 sn: ayni QR yeniden gonderildi (eskiden 30 sn sessizce yok sayilirdi)");
    CHECK(ekran_say("QR_READING") == 1 && ekran_say("QR_DENIED") == 0, "yeniden okumada normal akis (QR_READING)");
  }

  // ------------------------------------------------------------------------------------------------ G5 zaman asimi
  { printf("G5 yanitsiz kalan (zaman asimi) istek sonrasi ayni QR yeniden denenebilir\n");
    sifirla(100000);
    oku("SLOWSRV");
    CHECK(gm60SunucuYanitBekleniyor, "yanit bekleniyor");
    g_fake_ms = 100000 + 9999; gm60Loop();
    CHECK(gm60SunucuYanitBekleniyor && gm60SonGonderilenToken == "SLOWSRV", "9999 ms: hala bekleniyor");
    g_fake_ms = 100000 + 10000; gm60Loop();
    CHECK(!gm60SunucuYanitBekleniyor && gm60SonGonderilenToken == "", "10 sn: zaman asimi, token unutuldu");
    g_fake_ms = 100000 + 10100; oku("SLOWSRV");
    CHECK(g_yayinlar.size() == 2, "zaman asimi sonrasi ayni QR yeniden gonderildi");
    // yeni okuma (loop tikisi olmadan) zaman asimi dalini tetikler
    sifirla(300000);
    oku("SLOW2");
    g_fake_ms = 300000 + 10500; oku("SLOW2");
    CHECK(g_yayinlar.size() == 2, "okuma yoluyla zaman asimi dalinda da token unutulur ve yeniden gonderilir");
    // yanit beklenirken (zaman asimindan once) baska okuma yok sayilir
    sifirla(400000);
    oku("PEND"); g_fake_ms = 400000 + 6000; oku("OTHER");
    CHECK(g_yayinlar.size() == 1, "yanit beklenirken baska token da gonderilmez (KORUMA 1)");
  }

  // ------------------------------------------------------------------------------------------------ G6 yayin hatasi
  { printf("G6 yayin hatasi: token unutulur, QR_DENIED; hemen yeniden denenebilir\n");
    sifirla(100000);
    oku("PREV"); sonuc(true);                              // onceki basarili okuma
    g_fake_ms = 100000 + 9000;
    g_yayin_basarili = false;
    oku("FAILPUB");
    CHECK(g_yayinlar.size() == 1 && ekran_say("QR_DENIED") == 1 && gm60SonGonderilenToken == "", "yayin hatasi: QR_DENIED, token unutuldu");
    CHECK(!gm60SunucuYanitBekleniyor, "yayin hatasinda yanit beklenmez");
    g_yayin_basarili = true; g_fake_ms += 100;
    oku("FAILPUB");
    CHECK(g_yayinlar.size() == 2 && g_yayinlar[1].token == "FAILPUB", "yayin duzelince ayni QR hemen yeniden gonderildi (debounce basarisiz yayinda ilerlemez)");
  }

  // ------------------------------------------------------------------------------------------------ G7 MQTT yok
  { printf("G7 MQTT yok: dinamik QR offline acilmaz\n");
    sifirla(100000); g_mqtt_bagli = false;
    oku("OFFLINE1");
    CHECK(g_yayinlar.empty() && ekran_say("QR_DENIED") == 1, "offline: QR_DENIED, yayin yok");
    CHECK(gm60SonGonderilenToken == "", "offline'da token kaydedilmez");
  }

  // ------------------------------------------------------------------------------------------------ G8 farkli token
  { printf("G8 farkli token 8 sn penceresine takilmaz (debounce sonrasi)\n");
    sifirla(100000);
    oku("AAA"); sonuc(true);
    g_fake_ms = 100000 + 5000; oku("BBB");
    CHECK(g_yayinlar.size() == 2 && g_yayinlar[1].token == "BBB", "5 sn: farkli token gonderilir");
  }

  // ------------------------------------------------------------------------------------------------ G9 millis sarmasi
  { printf("G9 millis() sarmasi: 8 sn pencere ve geri bildirim isaretsiz farkla dogru\n");
    sifirla(0xFFFFFFFFu - 15u);
    oku("WRAP"); sonuc(true); g_ekran.clear();
    g_fake_ms = static_cast<uint32_t>(0xFFFFFFF0u + 6000u);       // sarma sonrasi 6 sn
    oku("WRAP");
    CHECK(g_yayinlar.size() == 1 && ekran_say("QR_READING") == 1, "sarma: 6 sn -> atlanir + tek geri bildirim");
    g_fake_ms = static_cast<uint32_t>(0xFFFFFFF0u + 8000u);
    oku("WRAP");
    CHECK(g_yayinlar.size() == 2, "sarma: 8 sn -> gonderilir");
  }

  // ------------------------------------------------------------------------------------------------ G10 tampon / kontrol baytlari
  { printf("G10 kontrol baytlari temizlenir; asiri uzun okuma reddedilir (kirpilmaz)\n");
    sifirla(100000);
    GM60Serial.feed(std::string("\x02") + "CLEAN1\x03\r\n");
    gm60Loop();
    CHECK(g_yayinlar.size() == 1 && g_yayinlar[0].token == "CLEAN1", "STX/ETX temizlendi");
    sifirla(200000);
    GM60Serial.feed(std::string(600, 'Q') + "\n");
    gm60Loop();
    CHECK(g_yayinlar.empty() && ekran_say("QR_DENIED") == 1, "512 baytlik siniri asan okuma reddedildi, kesik token gonderilmedi");
  }

  printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
