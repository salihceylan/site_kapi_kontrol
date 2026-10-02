// Ana makine testi: GERCEK cihaz_kontrol/include/admin_pin.h (zayif PIN reddi + kilit zamani {baslangic,sure}/isaretsiz) + gercek
// device_konfig.h (sabitZamanliEsit). NVS (Preferences) bellekte; saat sahte (32 bit, sarar).
#include <Arduino.h>
#include <Preferences.h>

#ifndef ADMIN_PIN_PATH
#define ADMIN_PIN_PATH "admin_pin.h"
#endif
#include ADMIN_PIN_PATH

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL: %s  (satir %d)\n", msg, __LINE__); } } while (0)
#define CHECKF(cond, ...) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

// Bagimsiz kehanet: zayif PIN kumesi (spesifikasyondan elle uretilir)
static std::vector<std::string> beklenen_zayiflar() {
  std::vector<std::string> v = {"000000", "111111", "123456", "654321", "123123", "121212", "112233", "000001"};
  for (int d = 0; d < 10; d++) v.push_back(std::string(6, static_cast<char>('0' + d)));
  for (int b = 0; b < 10; b++) {            // artan / azalan, 9'dan sonra 0
    std::string a, z;
    for (int i = 0; i < 6; i++) { a += static_cast<char>('0' + (b + i) % 10); z += static_cast<char>('0' + ((b - i) % 10 + 10) % 10); }
    v.push_back(a); v.push_back(z);
  }
  std::sort(v.begin(), v.end());
  v.erase(std::unique(v.begin(), v.end()), v.end());
  return v;
}

static uint32_t kalanSn() { uint32_t k = 0; adminPinDurum(k); return k; }

int main() {
  g_fake_ms = 5000;

  // ------------------------------------------------------------------------------------------------ P1 zayif PIN kumesi (10^6 PIN)
  { printf("P1 adminPinZayifMi: 10^6 PIN'in tamami bagimsiz kehanetle karsilastirilir\n");
    const auto beklenen = beklenen_zayiflar();
    std::vector<std::string> bulunan;
    char buf[8];
    for (int i = 0; i < 1000000; i++) { snprintf(buf, sizeof buf, "%06d", i); if (adminPinZayifMi(String(buf))) bulunan.push_back(buf); }
    CHECKF(bulunan == beklenen, "zayif kume uyusmadi: bulunan %zu, beklenen %zu", bulunan.size(), beklenen.size());
    CHECKF(beklenen.size() == 34, "beklenen kume 34 PIN (gelen %zu)", beklenen.size());
    for (const char* p : {"000000", "111111", "123456", "654321", "123123", "121212", "112233", "000001", "222222", "999999", "012345", "234567",
                          "345678", "456789", "987654", "876543", "765432", "543210", "567890", "098765"})
      CHECKF(adminPinZayifMi(String(p)), "%s zayif olmali", p);
    for (const char* p : {"482916", "135790", "909090", "000002", "100000", "123457", "654322", "246802", "111112", "121213", "112234", "314159"})
      CHECKF(!adminPinZayifMi(String(p)), "%s zayif OLMAMALI", p);
    CHECK(!adminPinZayifMi(String("12345")) && !adminPinZayifMi(String("")) && !adminPinZayifMi(String("1234567")), "yanlis uzunlukta zayif degil (bicim denetimi baska yerde)");
  }

  // ------------------------------------------------------------------------------------------------ P2 adminPinAyarla
  { printf("P2 adminPinAyarla: zayif/bicim hatasi false + neden; basarili ayar sayaci/kilidi sifirlar; PIN degeri hicbir yere yazilmaz\n");
    adminPinBaslat();
    CHECK(!adminPinTanimliMi(), "baslangicta PIN yok");
    Serial.clear();
    AdminPinRed red = ADMIN_PIN_RED_YOK;
    CHECK(!adminPinAyarla(String("123456"), &red) && red == ADMIN_PIN_RED_ZAYIF, "123456 reddedildi, neden ZAYIF");
    CHECK(!adminPinTanimliMi() && !g_nvs["admin_cfg"].count("admin_pin"), "zayif PIN saklanmadi (RAM ve NVS)");
    CHECK(!adminPinAyarla(String("000000"), &red) && red == ADMIN_PIN_RED_ZAYIF, "000000 reddedildi");
    CHECK(!adminPinAyarla(String("987654"), &red) && red == ADMIN_PIN_RED_ZAYIF, "987654 reddedildi");
    CHECK(!adminPinAyarla(String("12345"), &red) && red == ADMIN_PIN_RED_BICIM, "5 hane: bicim hatasi");
    CHECK(!adminPinAyarla(String("12a456"), &red) && red == ADMIN_PIN_RED_BICIM, "rakam disi: bicim hatasi");
    CHECK(!adminPinAyarla(String("1234567"), &red) && red == ADMIN_PIN_RED_BICIM, "7 hane: bicim hatasi");
    CHECK(!adminPinAyarla(String("123456")), "red out-param'i olmadan da false (nullptr)");
    CHECK(std::string(adminPinRedMetni(ADMIN_PIN_RED_ZAYIF)) == "weak_pin" && std::string(adminPinRedMetni(ADMIN_PIN_RED_BICIM)) == "invalid_pin", "olay nedenleri weak_pin / invalid_pin");
    CHECK(!Serial.has("123456") && !Serial.has("000000"), "ret yolunda PIN seriye yazilmadi (admin_pin.h hic yazmaz)");
    // gecerli
    gAdminPinHata = 3; g_nvs["admin_cfg"]["pin_fail"] = "3";
    CHECK(adminPinAyarla(String("482916"), &red) && red == ADMIN_PIN_RED_YOK, "482916 kabul");
    CHECK(adminPinTanimliMi() && g_nvs["admin_cfg"]["admin_pin"] == "482916", "PIN NVS'e yazildi");
    CHECK(gAdminPinHata == 0 && g_nvs["admin_cfg"]["pin_fail"] == "0" && !gAdminKilitAktif, "ayar sayaci ve kilidi sifirladi");
    // zayif ret mevcut PIN'i / sayaci DEGISTIRMEZ
    gAdminPinHata = 2; g_nvs["admin_cfg"]["pin_fail"] = "2";
    CHECK(!adminPinAyarla(String("111111"), &red), "mevcut PIN varken zayif ret");
    CHECK(gAdminPin == "482916" && gAdminPinHata == 2 && g_nvs["admin_cfg"]["admin_pin"] == "482916" && g_nvs["admin_cfg"]["pin_fail"] == "2", "reddedilen ayar mevcut PIN/sayaci degistirmedi");
    // silme
    CHECK(adminPinAyarla(String("")) && !adminPinTanimliMi() && !g_nvs["admin_cfg"].count("admin_pin"), "bos PIN silmeyi surdurur");
    CHECK(adminPinAyarla(String("482916")), "yeniden tanimla");
    gAdminPinHata = 0;
  }

  // ------------------------------------------------------------------------------------------------ P3 5 hata -> 5 dk kilit
  { printf("P3 mevcut davranis korunur: 5 hatali deneme -> 5 dk kilit, sayac NVS'te, kilit bitince tek hak\n");
    adminPinAyarla(String("482916"));
    uint32_t kalan = 99;
    for (int i = 1; i <= 4; i++) {
      CHECKF(adminPinDogrula(String("000001"), kalan) == ADMIN_PIN_YANLIS && kalan == static_cast<uint32_t>(5 - i), "%d. hata: YANLIS, kalan hak %d", i, 5 - i);
    }
    CHECK(g_nvs["admin_cfg"]["pin_fail"] == "4", "sayac NVS'te 4");
    const uint32_t t0 = g_fake_ms;
    CHECK(adminPinDogrula(String("000001"), kalan) == ADMIN_PIN_KILITLI && kalan == 300, "5. hata: KILITLI, 300 sn");
    CHECK(g_nvs["admin_cfg"]["pin_fail"] == "5" && gAdminKilitAktif, "sayac 5 ve kilit aktif");
    CHECK(adminPinDogrula(String("482916"), kalan) == ADMIN_PIN_KILITLI && kalan == 300, "kilitliyken DOGRU PIN bile reddedilir");
    g_fake_ms = t0 + 1;       CHECK(kalanSn() == 300, "1 ms sonra 300 sn (yukari yuvarlanir)");
    g_fake_ms = t0 + 1000;    CHECK(kalanSn() == 299, "1000 ms: 299000 ms kaldi -> 299 sn");
    g_fake_ms = t0 + 299000;  CHECK(kalanSn() == 1, "299000 ms: 1 sn");
    g_fake_ms = t0 + 299999;  CHECK(kalanSn() == 1, "299999 ms: 1 sn");
    const int w0 = g_nvs_writes;
    g_fake_ms = t0 + 300000;  CHECK(kalanSn() == 0 && !gAdminKilitAktif, "300000 ms: kilit kalkti");
    CHECK(gAdminPinHata == 4 && g_nvs["admin_cfg"]["pin_fail"] == "4" && g_nvs_writes - w0 == 1, "kilit sonrasi tek hak (4), NVS'e tam 1 yazim");
    CHECK(adminPinDogrula(String("000001"), kalan) == ADMIN_PIN_KILITLI && kalan == 300, "tek hak yanlis kullanilinca yeniden 5 dk kilit");
    g_fake_ms += 300000; kalanSn();
    CHECK(adminPinDogrula(String("482916"), kalan) == ADMIN_PIN_OK && gAdminPinHata == 0 && g_nvs["admin_cfg"]["pin_fail"] == "0", "kilit sonrasi dogru PIN: OK, sayac sifirlanir");
    // bicim hatali PIN denemesi de hata sayilir
    CHECK(adminPinDogrula(String("12345"), kalan) == ADMIN_PIN_YANLIS && gAdminPinHata == 1, "bicim hatali deneme YANLIS sayilir");
    adminPinDogrula(String("482916"), kalan);
  }

  // ------------------------------------------------------------------------------------------------ P4 yeniden baslatma kilidi sifirlamaz
  { printf("P4 yeniden baslatma kilidi sifirlamaz: acilista sayac >= 5 ise 5 dk kilit, bitince tek hak\n");
    g_fake_ms = 1000;
    g_nvs["admin_cfg"]["pin_fail"] = "5";
    adminPinBaslat();    // acilis benzetimi
    uint32_t kalan = 0;
    CHECK(gAdminKilitAktif && adminPinDurum(kalan) == ADMIN_PIN_KILITLI && kalan == 300, "acilista kilit 5 dk");
    g_fake_ms += 300000; adminPinZamanlayici();
    CHECK(!gAdminKilitAktif && gAdminPinHata == 4 && adminPinDurum(kalan) == ADMIN_PIN_OK, "bitince tek hak (ana dongu zamanlayicisi sorgu beklemeden kapatti)");
    g_nvs["admin_cfg"]["pin_fail"] = "0"; adminPinBaslat();
  }

  // ------------------------------------------------------------------------------------------------ P5 24,86 / 49,7 gun hortlamasi
  { printf("P5 kilit bittikten >= 24,86 gun sonra kilit YENIDEN gorunmez (F2A2 bulgusu); ana dongu zamanlayicisi ile 49,7 gun sarmasi da guvenli\n");
    adminPinAyarla(String("482916"));
    uint32_t kalan = 0;
    g_fake_ms = 777;
    for (int i = 0; i < 5; i++) adminPinDogrula(String("000001"), kalan);
    CHECK(gAdminKilitAktif, "kilit basladi");
    const uint32_t t0 = g_fake_ms;
    // gercek ana dongu gibi: her saniye zamanlayici; ~50 gun + 1 saat
    uint64_t gecen = 0; const uint64_t limit = (1ULL << 32) + 3600000ULL;
    uint32_t hortlayan = 0, ornek = 0; int yazim0 = g_nvs_writes;
    bool kilitHicDusmedi = false;
    while (gecen < limit) {
      g_fake_ms = t0 + static_cast<uint32_t>(gecen);
      adminPinZamanlayici();
      if (gecen == 299000) CHECK(gAdminKilitAktif, "299 sn: hala kilitli");
      if (gecen == 300000) CHECK(!gAdminKilitAktif && gAdminPinHata == 4, "300 sn: kilit kalkti, tek hak");
      if (gecen > 300000) {
        const bool kritik = (gecen >= (1ULL << 31) - 5000 && gecen < (1ULL << 31) + 7000) || (gecen >= (1ULL << 32) - 5000 && gecen < (1ULL << 32) + 7000) || (gecen % 86400000ULL) < 1000;
        if (kritik) { ornek++; if (kalanSn() != 0 || adminPinDurum(kalan) != ADMIN_PIN_OK || gAdminKilitAktif) hortlayan++; }
      }
      gecen += 1000;
    }
    (void)kilitHicDusmedi;
    CHECKF(hortlayan == 0, "kilit hortlamasi: %u/%u kritik ornekte kilit yeniden gorundu", hortlayan, ornek);
    CHECK(g_nvs_writes - yazim0 == 1, "tum surede NVS'e yalniz kilit bitisinde 1 yazim (flash asinmasi yok)");
    printf("  (%u kritik ornek, hortlayan: %u)\n", ornek, hortlayan);
    // zamanlayici OLMADAN da 25. gun: sorgu isaretsiz farkla kilidi kapali bulur
    adminPinAyarla(String("482916"));
    g_fake_ms = 4000;
    for (int i = 0; i < 5; i++) adminPinDogrula(String("000001"), kalan);
    g_fake_ms = 4000 + 25u * 86400000u;   // 25 gun sonra ILK sorgu (eski kod: isaretli tasma -> tekrar KILITLI)
    CHECK(adminPinDurum(kalan) == ADMIN_PIN_OK && kalan == 0, "25 gun sonra ilk sorgu: kilit YOK (eski kod burada tekrar kilitli gosterirdi)");
    adminPinAyarla(String("482916"));
  }

  printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
