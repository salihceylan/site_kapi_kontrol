// Ana makine testi: GERCEK cihaz_kontrol/include/yerel_kontrol_cekirdek.h (yerel kontrol v2 cekirdegi).
// mbedtls_md_hmac -> referans HMAC-SHA256 (sahte mbedtls/md.h). Sahte saat (uint32_t, 49,7 gunde sarar), sahte RNG, sahte role.
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "mbedtls_stub_impl.h"

#ifndef CORE_PATH
#define CORE_PATH "../include/yerel_kontrol_cekirdek.h"
#endif
#include CORE_PATH

#ifndef VECTORS_PATH
#define VECTORS_PATH "vectors.txt"
#endif

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL: %s  (satir %d)\n", msg, __LINE__); } } while (0)
#define CHECKF(cond, ...) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

// ---- sahte RNG (xorshift64*), sahte role --------------------------------------------------------------------------------
static uint64_t g_rng_state = 0x9E3779B97F4A7C15ULL;
static int g_rnd_calls = 0;
static uint32_t fake_rnd() {
  g_rnd_calls++;
  g_rng_state ^= g_rng_state >> 12;
  g_rng_state ^= g_rng_state << 25;
  g_rng_state ^= g_rng_state >> 27;
  return static_cast<uint32_t>((g_rng_state * 2685821657736338717ULL) >> 32);
}
static bool g_role_ok = true;
static int g_role_calls = 0;
static bool fake_role() { g_role_calls++; return g_role_ok; }

static const char* TOKEN = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE";
static const char* UID = "240AC4E2E001";

// Bagimsiz kehanet (oracle): mesaji testte KENDIMIZ kurup referans HMAC ile imzalariz (cekirdegin yerelMesajKur'una GUVENMEZ)
static std::string oracle_sig(const std::string& token, const std::string& action, const std::string& uid, const std::string& ch) {
  const std::string msg = action + "|" + uid + "|" + ch;
  uint8_t mac[32];
  refcrypto::hmac_sha256(reinterpret_cast<const uint8_t*>(token.data()), token.size(), reinterpret_cast<const uint8_t*>(msg.data()), msg.size(), mac);
  char hex[65];
  refcrypto::to_hex(mac, 32, hex);
  return hex;
}

struct Sim {
  YerelDurum d;
  uint32_t now;
  explicit Sim(uint32_t start) : now(start) {
    memset(&d, 0, sizeof d);
    yerelChBaslat(d, now, fake_rnd);
  }
  YerelSonuc open(const std::string& ch, const std::string& sig, const char* action = "open", bool hmacOk = true, const char* token = TOKEN) {
    return yerelAcmaDegerlendir(d, token, hmacOk, UID, action, ch.c_str(), sig.c_str(), now, fake_role, fake_rnd);
  }
  void tick(uint32_t ms) { now += ms; yerelChZamanlayici(d, now, fake_rnd); }
  std::string ch() const { return d.ch; }
  std::string onceki() const { return d.onceki; }
};

static const char* ad(YerelSonuc s) {
  switch (s) {
    case YEREL_SONUC_KABUL: return "KABUL";
    case YEREL_SONUC_YINELENEN: return "YINELENEN";
    case YEREL_SONUC_CHALLENGE: return "CHALLENGE";
    case YEREL_SONUC_YETKISIZ: return "YETKISIZ";
    case YEREL_SONUC_TOKEN_YOK: return "TOKEN_YOK";
    case YEREL_SONUC_ROLE_MESGUL: return "ROLE_MESGUL";
  }
  return "?";
}
#define EXPECT(got, want, msg) do { const YerelSonuc _g = (got); const YerelSonuc _w = (want); \
  if (_g == _w) { g_pass++; } else { g_fail++; printf("  FAIL: %s: beklenen %s, gelen %s  (satir %d)\n", msg, ad(_w), ad(_g), __LINE__); } } while (0)

static bool is_lower_hex(const std::string& s, size_t n) {
  if (s.size() != n) return false;
  for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}

int main() {
  // ------------------------------------------------------------------------------------------------ T0 referans HMAC dogrulugu
  { printf("T0 referans SHA-256/HMAC (bilinen vektorler)\n");
    uint8_t out[32]; char hex[65];
    refcrypto::sha256(reinterpret_cast<const uint8_t*>("abc"), 3, out); refcrypto::to_hex(out, 32, hex);
    CHECK(strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0, "SHA-256(abc)");
    refcrypto::sha256(reinterpret_cast<const uint8_t*>(""), 0, out); refcrypto::to_hex(out, 32, hex);
    CHECK(strcmp(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0, "SHA-256(bos)");
    const char* uzun = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";   // 56 bayt: iki blok sinir durumu
    refcrypto::sha256(reinterpret_cast<const uint8_t*>(uzun), strlen(uzun), out); refcrypto::to_hex(out, 32, hex);
    CHECK(strcmp(hex, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") == 0, "SHA-256(56 bayt)");
    uint8_t k1[20]; memset(k1, 0x0b, 20);
    refcrypto::hmac_sha256(k1, 20, reinterpret_cast<const uint8_t*>("Hi There"), 8, out); refcrypto::to_hex(out, 32, hex);
    CHECK(strcmp(hex, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7") == 0, "RFC4231 #1");
    refcrypto::hmac_sha256(reinterpret_cast<const uint8_t*>("Jefe"), 4, reinterpret_cast<const uint8_t*>("what do ya want for nothing?"), 28, out);
    refcrypto::to_hex(out, 32, hex);
    CHECK(strcmp(hex, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843") == 0, "RFC4231 #2");
    uint8_t k6[131]; memset(k6, 0xaa, 131);   // 64 bayttan uzun anahtar
    const char* m6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    refcrypto::hmac_sha256(k6, 131, reinterpret_cast<const uint8_t*>(m6), strlen(m6), out); refcrypto::to_hex(out, 32, hex);
    CHECK(strcmp(hex, "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54") == 0, "RFC4231 #6 (uzun anahtar)");
  }

  // ------------------------------------------------------------------------------------------------ T1 sartname KAT (bilinen cevap)
  { printf("T1 sartnamedeki bilinen-cevap vektoru (token/UID/ch -> open ve pulse imzasi)\n");
    char imza[65], msg[80];
    CHECK(yerelMesajKur(msg, sizeof msg, "open", "240AC4E2E001", "0123456789abcdef") == 34, "mesaj uzunlugu (open)");
    CHECK(strcmp(msg, "open|240AC4E2E001|0123456789abcdef") == 0, "mesaj biciminin BIREBIR eslesmesi (open)");
    CHECK(yerelMesajKur(msg, sizeof msg, "pulse", "240AC4E2E001", "0123456789abcdef") == 35, "mesaj uzunlugu (pulse)");
    CHECK(strcmp(msg, "pulse|240AC4E2E001|0123456789abcdef") == 0, "mesaj biciminin BIREBIR eslesmesi (pulse)");
    g_hmac_mode = 0;
    CHECK(yerelImzaHesapla("AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE", "open", "240AC4E2E001", "0123456789abcdef", imza), "open imzasi hesaplanabildi");
    CHECK(strcmp(imza, "92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4") == 0, "open imzasi == sartname vektoru");
    CHECK(g_hmac_last_key == "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE", "HMAC anahtari = token baytlari (43)");
    CHECK(g_hmac_last_msg == "open|240AC4E2E001|0123456789abcdef", "HMAC mesaji tam olarak action|UID|ch");
    CHECK(g_hmac_last_md_type == MBEDTLS_MD_SHA256, "SHA-256 secildi");
    CHECK(yerelImzaHesapla("AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE", "pulse", "240AC4E2E001", "0123456789abcdef", imza), "pulse imzasi hesaplanabildi");
    CHECK(strcmp(imza, "3bb6390fa9c7a2135232000306e9a6293e38fabd736edcf7400ecd55c597b881") == 0, "pulse imzasi == sartname vektoru");
    CHECK(strlen(imza) == 64 && is_lower_hex(imza, 64), "imza 64 kucuk hex");
    // kucuk harfli UID verilse de mesaj BUYUK harf UID ile kurulur
    CHECK(yerelImzaHesapla("AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE", "open", "240ac4e2e001", "0123456789abcdef", imza) &&
          strcmp(imza, "92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4") == 0, "kucuk harf UID -> BUYUK harfle imzalanir");
    CHECK(yerelKatCalistir(), "yerelKatCalistir() dogru HMAC ile true");
    CHECK(g_hmac_last_msg == "pulse|240AC4E2E001|0123456789abcdef", "KAT son olarak pulse vektorunu hesapladi");
  }

  // ------------------------------------------------------------------------------------------------ T2 KAT oz-testi bozuk HMAC'i yakalar (fail-closed)
  { printf("T2 KAT oz-testi: bozuk HMAC yollari yakalanir\n");
    g_hmac_mode = 1; CHECK(!yerelKatCalistir(), "HMAC hata kodu donerse KAT false");
    g_hmac_mode = 2; CHECK(!yerelKatCalistir(), "HMAC ciktisi 1 bit bozuksa KAT false");
    g_hmac_mode = 3; CHECK(!yerelKatCalistir(), "SHA-256 md_info yoksa KAT false");
    g_hmac_mode = 0; CHECK(yerelKatCalistir(), "normal modda KAT true");
    char imza[65];
    g_hmac_mode = 1; CHECK(!yerelImzaHesapla(TOKEN, "open", UID, "0123456789abcdef", imza), "HMAC hatasi -> imza hesaplanamadi (false)");
    g_hmac_mode = 0;
    // hmacSaglam=false: gecerli imzayla bile TOKEN_YOK (yerel acma KAPALI) ve role/HMAC hic cagrilmaz
    Sim s(100); g_role_calls = 0; g_hmac_calls = 0;
    const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    EXPECT(s.open(ch0, sig, "open", false), YEREL_SONUC_TOKEN_YOK, "oz-test basarisiz (fail-closed): gecerli imza bile reddedilir");
    CHECK(g_role_calls == 0 && g_hmac_calls == 0, "fail-closed: role ve HMAC cagrilmadi");
    EXPECT(s.open(ch0, sig, "open", true), YEREL_SONUC_KABUL, "oz-test basariliyken ayni paket kabul");
  }

  // ------------------------------------------------------------------------------------------------ T3 Node crypto capraz dogrulama
  { printf("T3 Node crypto ile uretilen rastgele HMAC vektorleri (cekirdek == Node)\n");
    std::ifstream f(VECTORS_PATH);
    CHECK(f.good(), "vectors.txt acildi");
    std::string line; int n = 0, ok = 0, e2e = 0;
    while (std::getline(f, line)) {
      std::istringstream is(line);
      std::string token, uid, ch, action, sig;
      if (!(is >> token >> uid >> ch >> action >> sig)) continue;
      n++;
      char imza[65];
      const bool h = yerelImzaHesapla(token.c_str(), action.c_str(), uid.c_str(), ch.c_str(), imza);
      if (h && sig == imza) ok++;
      else printf("  vektor %d uyusmadi (token uzunlugu %zu)\n", n, token.size());
      // uctan uca: cihaz bu uid/ch ile kabul eder
      YerelDurum d; memset(&d, 0, sizeof d); yerelChBaslat(d, 1000, fake_rnd); memcpy(d.ch, ch.c_str(), 17);
      g_role_ok = true;
      if (yerelAcmaDegerlendir(d, token.c_str(), true, uid.c_str(), action.c_str(), ch.c_str(), sig.c_str(), 1000, fake_role, fake_rnd) == YEREL_SONUC_KABUL) e2e++;
    }
    CHECKF(n >= 600 && ok == n, "vektorler: %d/%d eslesti", ok, n);
    CHECKF(e2e == n, "uctan uca kabul: %d/%d", e2e, n);
    printf("  (Node vektoru: %d, imza eslesmesi: %d, uctan uca kabul: %d)\n", n, ok, e2e);
  }

  // ------------------------------------------------------------------------------------------------ T4 yardimcilar
  { printf("T4 yardimcilar (hex dogrulama, sabit zamanli esitlik, ch uretimi, mesaj kurma)\n");
    CHECK(yerelHexMi("0123456789abcdef", 16), "hex gecerli");
    CHECK(!yerelHexMi("0123456789abcdeF", 16), "buyuk harf hex red");
    CHECK(!yerelHexMi("0123456789abcde", 16), "15 karakter red");
    CHECK(!yerelHexMi("0123456789abcdef0", 16), "17 karakter red");
    CHECK(!yerelHexMi("0123456789abcdeg", 16), "hex disi red");
    CHECK(!yerelHexMi(nullptr, 16), "nullptr red");
    CHECK(!yerelHexMi("", 16), "bos red");
    CHECK(!yerelHexMi("0123456789abcdef ", 16), "sondaki bosluk red");
    CHECK(yerelSabitEsit("abcdef", "abcdef", 6), "esit");
    CHECK(!yerelSabitEsit("abcdef", "abcdeg", 6), "son karakter farki");
    CHECK(!yerelSabitEsit("abcdef", "bbcdef", 6), "ilk karakter farki");
    CHECK(yerelSabitEsit("abcdef", "abcdxx", 4), "yalniz ilk n bayt karsilastirilir");
    // ch uretimi: 2 x 32 bit, MSB once, 16 kucuk hex
    static uint32_t seq[2]; static int si = 0;
    struct L { static uint32_t r() { return seq[si++ % 2]; } };
    seq[0] = 0x01234567u; seq[1] = 0x89abcdefu; si = 0;
    char ch[17]; yerelChUret(ch, L::r);
    CHECK(strcmp(ch, "0123456789abcdef") == 0, "ch = RNG baytlari MSB-once kucuk hex");
    seq[0] = 0xFFFFFFFFu; seq[1] = 0x00000000u; si = 0; yerelChUret(ch, L::r);
    CHECK(strcmp(ch, "ffffffff00000000") == 0, "ch uc degerler");
    g_rnd_calls = 0; yerelChUret(ch, fake_rnd);
    CHECK(g_rnd_calls == 2 && is_lower_hex(ch, 16), "ch: 2 RNG cagrisi (8 bayt), 16 kucuk hex");
    char a[17], b[17]; yerelChUret(a, fake_rnd); yerelChUret(b, fake_rnd);
    CHECK(strcmp(a, b) != 0, "ardisik ch'ler farkli");
    // mesaj kurma kenar durumlari
    char m[40];
    CHECK(yerelMesajKur(m, sizeof m, "open", UID, "0123456789abcdef") == 34, "kapasite yeterli");
    CHECK(yerelMesajKur(m, 35, "open", UID, "0123456789abcdef") == 34, "kapasite tam (34 + NUL)");
    CHECK(yerelMesajKur(m, 34, "open", UID, "0123456789abcdef") == 0, "kapasite 1 bayt eksik -> 0");
    CHECK(yerelMesajKur(m, sizeof m, "", UID, "0123456789abcdef") == 0, "bos action -> 0");
    CHECK(yerelMesajKur(m, sizeof m, "open", "", "0123456789abcdef") == 0, "bos uid -> 0");
    CHECK(yerelMesajKur(m, sizeof m, "open", UID, "") == 0, "bos ch -> 0");
    CHECK(yerelMesajKur(m, sizeof m, nullptr, UID, "x") == 0, "nullptr -> 0");
    char imza[65];
    CHECK(!yerelImzaHesapla("", "open", UID, "0123456789abcdef", imza), "bos token -> imza yok");
    CHECK(!yerelImzaHesapla(nullptr, "open", UID, "0123456789abcdef", imza), "nullptr token -> imza yok");
  }

  // ------------------------------------------------------------------------------------------------ T5 durum makinesi
  { printf("T5.1 gecerli acma -> KABUL, challenge yenilenir, son-kabul kaydi\n");
    g_role_ok = true; g_role_calls = 0;
    Sim s(1000);
    const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    CHECK(is_lower_hex(ch0, 16), "baslangic ch 16 kucuk hex");
    EXPECT(s.open(ch0, sig), YEREL_SONUC_KABUL, "gecerli open");
    CHECK(g_role_calls == 1, "role tam bir kez tetiklendi");
    CHECK(s.ch() != ch0 && is_lower_hex(s.ch(), 16), "basarida guncel ch yeniden uretildi");
    CHECK(s.onceki().empty(), "basarida onceki ch BOSALTILDI");
    CHECK(s.d.sonKabulVar && ch0 == s.d.sonKabulCh && sig == s.d.sonKabulSig && s.d.sonKabulBaslangicMs == 1000, "son-kabul kaydi (ch, sig, zaman)");
  }
  { printf("T5.2 yinelenen paket penceresi (3 sn)\n");
    g_role_ok = true; g_role_calls = 0;
    Sim s(50000);
    const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    EXPECT(s.open(ch0, sig), YEREL_SONUC_KABUL, "ilk paket");
    const std::string chSonra = s.ch();
    s.tick(25);
    EXPECT(s.open(ch0, sig), YEREL_SONUC_YINELENEN, "25 ms sonra ayni paket -> duplicate");
    CHECK(g_role_calls == 1, "yinelenende role TEKRAR tetiklenmedi");
    CHECK(s.ch() == chSonra, "yinelenen paket challenge'i degistirmedi");
    s.now = 50000 + 2999; s.tick(0);
    EXPECT(s.open(ch0, sig), YEREL_SONUC_YINELENEN, "2999 ms: hala duplicate");
    s.now = 50000 + 3000; s.tick(0);
    EXPECT(s.open(ch0, sig), YEREL_SONUC_CHALLENGE, "3000 ms: pencere kapandi, eski ch -> challenge");
    CHECK(g_role_calls == 1, "pencere sonrasi da role tetiklenmedi");
    CHECK(!s.d.sonKabulVar, "kayit kilitli kapandi");
    // duplicate yalniz AYNI ch+sig: sig'in tek hanesi farkliysa duplicate DEGIL
    Sim s2(70000); const std::string c2 = s2.ch(); const std::string g2 = oracle_sig(TOKEN, "open", UID, c2);
    EXPECT(s2.open(c2, g2), YEREL_SONUC_KABUL, "s2 ilk"); s2.tick(25);
    std::string bad = g2; bad[63] = bad[63] == '0' ? '1' : '0';
    EXPECT(s2.open(c2, bad), YEREL_SONUC_CHALLENGE, "ayni ch, farkli sig: duplicate degil (ch artik gecersiz -> challenge)");
    // ayni sig, farkli action ayni sayilmaz
    EXPECT(s2.open(c2, g2, "pulse"), YEREL_SONUC_CHALLENGE, "ayni ch+sig ama pulse: duplicate degil");
  }
  { printf("T5.3 yanlis imza: unauthorized, challenge TUKETILMEZ\n");
    g_role_ok = true; g_role_calls = 0;
    Sim s(5000);
    const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    for (int pos : {0, 1, 31, 62, 63}) {
      std::string bad = sig; bad[pos] = bad[pos] == '0' ? '1' : '0';
      EXPECT(s.open(ch0, bad), YEREL_SONUC_YETKISIZ, "tek hanesi bozuk imza reddedilir (her konum)");
    }
    CHECK(g_role_calls == 0, "yanlis imzada role tetiklenmedi");
    CHECK(s.ch() == ch0, "yanlis imza challenge'i tuketmedi");
    CHECK(!s.d.sonKabulVar, "yanlis imza kabul kaydi olusturmadi");
    // baska token ile imza
    EXPECT(s.open(ch0, oracle_sig("BASKA_TOKEN_0123456789_ABCDEF", "open", UID, ch0)), YEREL_SONUC_YETKISIZ, "farkli token imzasi");
    // baska cihaz UID'si ile imza (capraz cihaz tekrar oynatma)
    EXPECT(s.open(ch0, oracle_sig(TOKEN, "open", "240AC4E2E002", ch0)), YEREL_SONUC_YETKISIZ, "baska UID icin imza bu cihazda gecmez");
    // kucuk harfli UID ile imza (UID buyuk harfle imzalanmali) gecersiz
    EXPECT(s.open(ch0, oracle_sig(TOKEN, "open", "240ac4e2e001", ch0)), YEREL_SONUC_YETKISIZ, "kucuk harf UID mesajiyla imza gecmez");
    // action baglama: open imzasi pulse olarak gecmez
    EXPECT(s.open(ch0, sig, "pulse"), YEREL_SONUC_YETKISIZ, "open imzasi pulse isteginde gecersiz");
    // ch baglama: baska ch icin imza
    EXPECT(s.open(ch0, oracle_sig(TOKEN, "open", UID, "ffffffffffffffff")), YEREL_SONUC_YETKISIZ, "baska ch icin imza gecersiz");
    EXPECT(s.open(ch0, sig), YEREL_SONUC_KABUL, "dogru imza sonunda kabul (challenge hala gecerliydi)");
    // pulse
    g_role_calls = 0; Sim p(9000); const std::string pc = p.ch();
    EXPECT(p.open(pc, oracle_sig(TOKEN, "pulse", UID, pc), "pulse"), YEREL_SONUC_KABUL, "gecerli pulse");
  }
  { printf("T5.4 eski ch -> challenge; onceki ch bir donem daha kabul\n");
    g_role_ok = true; g_role_calls = 0;
    Sim s(1000);
    const std::string ch0 = s.ch();
    s.tick(9999);
    CHECK(s.ch() == ch0, "9999 ms: donme yok");
    s.tick(1);
    CHECK(s.ch() != ch0 && s.onceki() == ch0, "10000 ms: guncel yenilendi, onceki = eski guncel");
    const std::string ch1 = s.ch();
    EXPECT(s.open(ch0, oracle_sig(TOKEN, "open", UID, ch0)), YEREL_SONUC_KABUL, "onceki ch ile gecerli imza kabul");
    CHECK(g_role_calls == 1, "onceki ch ile role tetiklendi");
    CHECK(s.ch() != ch1 && s.onceki().empty(), "kabul sonrasi iki challenge de yenilendi");
    // iki donem sonra: stale
    Sim t(1000); const std::string t0 = t.ch(); t.tick(10000); t.tick(10000);
    EXPECT(t.open(t0, oracle_sig(TOKEN, "open", UID, t0)), YEREL_SONUC_CHALLENGE, "iki donem eski ch -> challenge");
    CHECK(t.ch() != t0 && t.onceki() != t0, "eski ch ne guncel ne onceki");
    // hic bilinmeyen ch
    EXPECT(t.open("0000000000000000", oracle_sig(TOKEN, "open", UID, "0000000000000000")), YEREL_SONUC_CHALLENGE, "bilinmeyen ch -> challenge");
    // ch hic yok
    EXPECT(t.open("", ""), YEREL_SONUC_CHALLENGE, "ch ve sig yok -> challenge");
    // ch bos onceki ile eslesmemeli
    Sim u(1000); u.d.onceki[0] = '\0';
    EXPECT(u.open("", oracle_sig(TOKEN, "open", UID, "")), YEREL_SONUC_CHALLENGE, "bos ch bos onceki ile eslesmez");
  }
  { printf("T5.5 role mesgul: challenge tuketilmez, kayit yok\n");
    Sim s(1000); g_role_calls = 0;
    const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    g_role_ok = false;
    EXPECT(s.open(ch0, sig), YEREL_SONUC_ROLE_MESGUL, "role mesgul");
    CHECK(s.ch() == ch0, "role mesgulde challenge degismedi");
    CHECK(!s.d.sonKabulVar, "role mesgulde kabul kaydi yok");
    EXPECT(s.open(ch0, sig), YEREL_SONUC_ROLE_MESGUL, "tekrar: yine mesgul (duplicate DEGIL)");
    CHECK(g_role_calls == 2, "role her istekte denendi");
    g_role_ok = true;
    EXPECT(s.open(ch0, sig), YEREL_SONUC_KABUL, "role bosalinca ayni (ch, sig) kabul");
    g_role_ok = true;
  }
  { printf("T5.6 token yok / bos / null\n");
    g_role_ok = true; g_role_calls = 0; g_hmac_calls = 0;
    Sim s(1000); const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    EXPECT(s.open(ch0, sig, "open", true, ""), YEREL_SONUC_TOKEN_YOK, "bos token");
    EXPECT(s.open(ch0, sig, "open", true, nullptr), YEREL_SONUC_TOKEN_YOK, "null token");
    CHECK(g_role_calls == 0 && g_hmac_calls == 0, "token yokken ne role ne HMAC");
    // duplicate penceresinde bile token yoksa TOKEN_YOK
    EXPECT(s.open(ch0, sig), YEREL_SONUC_KABUL, "token varken kabul"); s.tick(25);
    EXPECT(s.open(ch0, sig, "open", true, ""), YEREL_SONUC_TOKEN_YOK, "token silinince duplicate yerine TOKEN_YOK");
  }
  { printf("T5.7 bicim hatalari: net red (challenge / unauthorized), sessiz yok sayma yok\n");
    g_role_ok = true; g_role_calls = 0;
    Sim s(1000);
    memcpy(s.d.ch, "0123456789abcdef", 17);
    const std::string ch0 = s.ch(); const std::string sig = oracle_sig(TOKEN, "open", UID, ch0);
    const char* kotuCh[] = {"", "0123456789abcde", "0123456789abcdef0", "0123456789ABCDEF", "g123456789abcdef", "0123456789abcdef ", " 0123456789abcdef",
                            "0123456789abcde\n"};
    for (const char* c : kotuCh) EXPECT(s.open(c, sig), YEREL_SONUC_CHALLENGE, "gecersiz ch bicimi -> challenge");
    const std::string kotuSig[] = {"", sig.substr(0, 63), sig + "0", [&] { std::string x = sig; for (auto& c : x) if (c >= 'a' && c <= 'f') c = (char)(c - 32); return x; }(),
                                   [&] { std::string x = sig; x[10] = 'z'; return x; }(), [&] { std::string x = sig; x[0] = ' '; return x; }(),
                                   std::string("0000000000000000000000000000000000000000000000000000000000000000")};
    for (const std::string& g : kotuSig) EXPECT(s.open(ch0, g), YEREL_SONUC_YETKISIZ, "gecersiz sig bicimi / yanlis sig -> unauthorized");
    const char* kotuEylem[] = {"close", "", "OPEN", "Open", "open ", "pulse2", "discover"};
    for (const char* a : kotuEylem) EXPECT(s.open(ch0, sig, a), YEREL_SONUC_YETKISIZ, "bilinmeyen action");
    EXPECT(yerelAcmaDegerlendir(s.d, TOKEN, true, UID, nullptr, ch0.c_str(), sig.c_str(), s.now, fake_role, fake_rnd), YEREL_SONUC_YETKISIZ, "action nullptr");
    EXPECT(yerelAcmaDegerlendir(s.d, TOKEN, true, UID, "open", nullptr, nullptr, s.now, fake_role, fake_rnd), YEREL_SONUC_CHALLENGE, "ch/sig nullptr -> challenge");
    CHECK(g_role_calls == 0, "bicim hatalarinda role tetiklenmedi");
    CHECK(s.ch() == ch0, "bicim hatalari challenge'i tuketmedi");
    EXPECT(yerelAcmaDegerlendir(s.d, TOKEN, true, UID, "open", ch0.c_str(), sig.c_str(), s.now, nullptr, fake_rnd), YEREL_SONUC_ROLE_MESGUL, "role geri cagrisi yoksa mesgul (fail-closed)");
  }
  { printf("T5.8 10 sn donme temposu (100 ms adimlarla 60 sn) ve uzun bloke\n");
    Sim s(3000);
    std::vector<std::string> gorulen; gorulen.push_back(s.ch());
    std::vector<uint32_t> zaman; zaman.push_back(0);
    for (uint32_t t = 100; t <= 60000; t += 100) {
      s.tick(100);
      if (s.ch() != gorulen.back()) { gorulen.push_back(s.ch()); zaman.push_back(t); }
    }
    CHECKF(gorulen.size() == 7, "60 sn'de 6 donme (7 farkli ch) bekleniyordu, gelen %zu", gorulen.size());
    bool aralikOk = true; for (size_t i = 1; i < zaman.size(); i++) if (zaman[i] - zaman[i - 1] != 10000) aralikOk = false;
    CHECK(aralikOk, "donmeler tam 10 sn arayla");
    CHECK(s.onceki() == gorulen[gorulen.size() - 2], "onceki = bir onceki guncel");
    // uzun bloke (25 sn): tek donme, onceki bosaltilir (25 sn onceki guncel ARTIK kabul edilmez)
    Sim b(1000); const std::string b0 = b.ch();
    b.tick(25000);
    CHECK(b.ch() != b0 && b.onceki().empty(), "25 sn bloke: guncel yenilendi, onceki bosaltildi");
    g_role_ok = true; g_role_calls = 0;
    EXPECT(b.open(b0, oracle_sig(TOKEN, "open", UID, b0)), YEREL_SONUC_CHALLENGE, "25 sn eski ch 'onceki' olarak KABUL EDILMEZ");
    // orta bloke (15 sn): onceki = eski guncel, hala kabul
    Sim c(1000); const std::string c0 = c.ch();
    c.tick(15000);
    CHECK(c.onceki() == c0, "15 sn bloke: onceki = eski guncel");
    EXPECT(c.open(c0, oracle_sig(TOKEN, "open", UID, c0)), YEREL_SONUC_KABUL, "15 sn bloke sonrasi onceki ch kabul");
    // tam 20 sn: sinir (>= 2 donem) -> onceki bosalir
    Sim e(1000); const std::string e0 = e.ch(); e.tick(19999);
    CHECK(e.onceki() == e0, "19999 ms: onceki = eski guncel");
    Sim e2(1000); const std::string f0 = e2.ch(); e2.tick(20000);
    CHECK(e2.onceki().empty() && e2.ch() != f0, "20000 ms: onceki bosaltildi");
  }
  { printf("T5.9 millis() sarmasi (49,7 gun): zamanlayicilar isaretsiz farkla dogru\n");
    // 5 sn sonra sarilacak saatte baslat; 60 sn boyunca 100 ms adim
    Sim s(0xFFFFFFFFu - 5000u + 1u);
    std::vector<uint32_t> zaman; std::string son = s.ch(); int donme = 0;
    for (uint32_t t = 100; t <= 60000; t += 100) {
      s.tick(100);
      if (s.ch() != son) { son = s.ch(); donme++; zaman.push_back(t); }
    }
    CHECKF(donme == 6, "sarma boyunca 6 donme bekleniyordu, gelen %d", donme);
    bool ok = true; for (size_t i = 1; i < zaman.size(); i++) if (zaman[i] - zaman[i - 1] != 10000) ok = false;
    CHECK(ok && s.now < 60000, "donme araliklari sarmadan etkilenmedi (now sarildi)");
    // sarma aninda kabul + duplicate
    g_role_ok = true; g_role_calls = 0;
    Sim w(0xFFFFFFFEu); const std::string w0 = w.ch(); const std::string ws = oracle_sig(TOKEN, "open", UID, w0);
    EXPECT(w.open(w0, ws), YEREL_SONUC_KABUL, "sarmadan 2 ms once kabul");
    w.tick(100);   // now = 0x62: saat sarildi
    CHECK(w.now == 0x62u, "saat sarildi (0x62)");
    EXPECT(w.open(w0, ws), YEREL_SONUC_YINELENEN, "sarma sonrasi 100 ms: duplicate");
    CHECK(g_role_calls == 1, "sarma: role bir kez");
    w.now = 0xFFFFFFFEu + 3000u; w.tick(0);
    EXPECT(w.open(w0, ws), YEREL_SONUC_CHALLENGE, "sarma sonrasi 3000 ms: pencere kapandi");
    // sarmadan once uretilen ch sarma sonrasi onceki olarak kabul
    Sim v(0xFFFFFFF0u); const std::string v0 = v.ch(); v.tick(10000);
    CHECK(v.onceki() == v0 && v.ch() != v0, "sarma: 10 sn sonra onceki dogru");
    EXPECT(v.open(v0, oracle_sig(TOKEN, "open", UID, v0)), YEREL_SONUC_KABUL, "sarma: onceki ch kabul");
  }
  { printf("T5.10 bayat damga hortlamasi: kabul kaydi 24,86 gun / 49,7 gun sonra YENIDEN ACILMAZ\n");
    g_role_ok = true; g_role_calls = 0;
    const uint32_t T = 1234;
    Sim s(T);
    const std::string c0 = s.ch(); const std::string sg = oracle_sig(TOKEN, "open", UID, c0);
    EXPECT(s.open(c0, sg), YEREL_SONUC_KABUL, "ilk kabul");
    const int rolesIlk = g_role_calls;
    // 1 sn adimla ~49,7 gun + 1 saat ilerle (her adimda dongu zamanlayicisi calisir: gercek loop gibi)
    uint64_t gecen = 0; const uint64_t limit = (1ULL << 32) + 3600000ULL;
    uint32_t sahte = 0, replay = 0, yanlisHortlak = 0; bool varGordu = false;
    while (gecen < limit) {
      s.tick(1000); gecen += 1000;
      if (gecen >= 3000 && s.d.sonKabulVar) varGordu = true;
      const uint32_t f = static_cast<uint32_t>(gecen);
      // kritik pencereler: 2^31 (isaretli tasma) ve 2^32 (sarma) civari + rastgele ornekler
      const bool kritik = (gecen >= (1ULL << 31) - 5000 && gecen < (1ULL << 31) + 7000) || (gecen >= (1ULL << 32) - 5000 && gecen < (1ULL << 32) + 7000) || (f % 86400000u) < 1000;
      if (kritik) {
        replay++;
        const YerelSonuc r = s.open(c0, sg);
        if (r == YEREL_SONUC_YINELENEN || r == YEREL_SONUC_KABUL) yanlisHortlak++;
        (void)sahte;
      }
    }
    CHECKF(yanlisHortlak == 0, "hortlama: eski (ch,sig) %u/%u denemede kabul/duplicate dondu", yanlisHortlak, replay);
    CHECK(!varGordu, "kayit 3 sn sonra kilitli kapali kaldi (kayit bayragi yeniden acilmadi)");
    CHECK(g_role_calls == rolesIlk, "tum surede role yeniden tetiklenmedi");
    printf("  (%u kritik pencere denemesi, hortlayan: %u)\n", replay, yanlisHortlak);
  }
  { printf("T5.11 baska sinirlar: yinelenen paket role mesgulken, ardisik farkli acmalar\n");
    g_role_ok = true; g_role_calls = 0;
    Sim s(1000);
    const std::string a = s.ch(); EXPECT(s.open(a, oracle_sig(TOKEN, "open", UID, a)), YEREL_SONUC_KABUL, "acma 1");
    s.tick(200);
    const std::string b = s.ch(); EXPECT(s.open(b, oracle_sig(TOKEN, "open", UID, b)), YEREL_SONUC_KABUL, "acma 2 (yeni ch ile)");
    CHECK(g_role_calls == 2, "iki farkli acma iki role");
    s.tick(25);
    EXPECT(s.open(b, oracle_sig(TOKEN, "open", UID, b)), YEREL_SONUC_YINELENEN, "ikincinin kopyasi duplicate");
    EXPECT(s.open(a, oracle_sig(TOKEN, "open", UID, a)), YEREL_SONUC_CHALLENGE, "ilkinin kopyasi artik challenge (yalniz EN SON kabul hatirlanir)");
    CHECK(g_role_calls == 2, "kopyalar role tetiklemedi");
  }

  printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
