#ifndef OTA_GUNCELLEME_H
#define OTA_GUNCELLEME_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <Update.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_ota_ops.h>
#include <esp_task_wdt.h>
#include <mbedtls/sha256.h>

#include "device_konfig.h"
#include "ota_is_kimligi.h"
#include "role_kontrol.h"
#include "tls_kok_sertifika.h"
#include "wifi_baglanti.h"

// Hedef donanimlara ozel surumler (C3 sahadaki cihazlar ile WROOM ayri takip edilir).
// 4.3.0 / 5.2.0: yerel kontrol protokolu v2 (challenge'a bagli HMAC; cihaz+uygulama birlikte), zayif admin PIN reddi, QR tekrar penceresi,
// OTA olaylarinda ota_job_id (protokol degisikligi nedeniyle minor artis).
inline constexpr char OTA_VERSION_C3[] = "4.3.0";
inline constexpr char OTA_VERSION_WROOM[] = "5.2.0";

#if defined(BOARD_ESP32_WROOM_RELAY) || defined(BOARD_ESP32_WROOM)
inline constexpr char OTA_TARGET[] = "esp32-wroom";
inline constexpr const char* OTA_CURRENT_VERSION = OTA_VERSION_WROOM;
inline constexpr char OTA_MANIFEST_URL[] =
  "https://api.gudeteknoloji.com.tr/firmware/esp32-wroom/manifest.json";
#else
inline constexpr char OTA_TARGET[] = "esp32-c3";
inline constexpr const char* OTA_CURRENT_VERSION = OTA_VERSION_C3;
inline constexpr char OTA_MANIFEST_URL[] =
  "https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json";
#endif
// Indirme URL'si yalniz manifestle ayni sunucudan ve HTTPS ile kabul edilir.
inline constexpr char OTA_ALLOWED_URL_PREFIX[] = "https://api.gudeteknoloji.com.tr/";

inline constexpr char OTA_PREFS_NAMESPACE[] = "ota_cfg";
inline constexpr char OTA_PREF_LAST_STATUS[] = "last_status";
inline constexpr char OTA_PREF_LAST_VERSION[] = "last_version";
inline constexpr char OTA_PREF_TRY_VERSION[] = "try_ver";
inline constexpr char OTA_PREF_TRY_COUNT[] = "try_cnt";
// OTA_KURULUM.txt: acilista Wi-Fi oturduktan ~90 sn + cihaz bazli (MAC) rastgele gecikme; sonra 24 saatte bir.
inline constexpr unsigned long OTA_BOOT_CHECK_DELAY_MS = 90UL * 1000UL;
inline constexpr unsigned long OTA_BOOT_JITTER_MS = 60UL * 1000UL;
inline constexpr unsigned long OTA_PERIODIC_CHECK_MS = 24UL * 60UL * 60UL * 1000UL;
inline constexpr unsigned long OTA_MIN_RETRY_MS = 10UL * 60UL * 1000UL;
inline constexpr unsigned long OTA_MIN_INTERVAL_MS = 60UL * 60UL * 1000UL;
inline constexpr unsigned long OTA_MAX_INTERVAL_MS = 7UL * 24UL * 60UL * 60UL * 1000UL;
inline constexpr unsigned long OTA_FAIL_BACKOFF_BASE_MS = 10UL * 60UL * 1000UL;
inline constexpr unsigned long OTA_SAGLIK_SURESI_MS = 60UL * 1000UL;  // Wi-Fi+MQTT bu sure saglikli kalinca imaj gecerli
inline constexpr uint8_t OTA_MAX_DENEME = 3;                           // ayni surum icin en fazla deneme
inline constexpr unsigned long OTA_JOB_JITTER_MS = 120UL * 1000UL;     // toplu is (ota_job_id): cihazlar 0-120 sn araya yayilir

using OtaEventPublisher = void (*)(const char* eventName, const char* detail);
// MQTT oturumunu OTA indirmesi icin kapatma / indirme bitince yeniden acma kancalari (mqtt_baglanti.h kaydeder)
using OtaMqttHook = void (*)();

// Planlanan kontrol zamani: {baslangic damgasi, sure} + KILITLI "vade geldi" bayragi. Karsilastirma ISARETSIZ
// (millis() - baslangic >= sure) ve sonuc otaCheckAndUpdate() her loop'ta cagrildigi icin kilitlenir; boylece plan, Wi-Fi/saat/role
// yuzunden uzun sure (>24,86 gun) kacirilsa bile isaretli tasma ya da 49,7 gunluk millis() tasmasi ile "gelecege" tasinamaz.
inline unsigned long gOtaPlanBaslangicMs = 0;
inline unsigned long gOtaPlanSureMs = 0;
inline bool gOtaVadeGeldi = false;
inline unsigned long gOtaLastAttemptAt = 0;
inline unsigned long gOtaPeriodicIntervalMs = OTA_PERIODIC_CHECK_MS;
inline uint8_t gOtaArdisikHata = 0;
inline bool gOtaIlkPlanYapildi = false;
inline bool gOtaPendingCheck = false;
inline bool gOtaRunning = false;
// Acilista calisan imaj PENDING_VERIFY (yeni OTA imaji henuz dogrulanmadi) ise true; otaGecerliligiDogrula() dogrulayinca false olur.
inline bool gOtaImajDogrulanmadi = false;
inline String gOtaLastStatus = "beklemede";
inline String gOtaLastVersion = "";
inline Preferences gOtaPrefs;
inline OtaEventPublisher gOtaEventPublisher = nullptr;
inline OtaMqttHook gOtaMqttKapat = nullptr;
inline OtaMqttHook gOtaMqttAc = nullptr;

inline unsigned long otaDeviceJitterMs(unsigned long maxMs) {
  if (maxMs == 0) {
    return 0;
  }
  uint64_t mac = ESP.getEfuseMac();
  return static_cast<unsigned long>(mac % maxMs);
}

inline void otaPlanNext(unsigned long baseDelayMs, bool withJitter = true, unsigned long maxJitterMs = 60UL * 60UL * 1000UL) {
  const unsigned long jitterMs = withJitter ? otaDeviceJitterMs(maxJitterMs) : 0;
  gOtaPlanBaslangicMs = millis();
  gOtaPlanSureMs = baseDelayMs + jitterMs;   // en fazla 7 gun + 1 saat: 32 bit'e sigar
  gOtaVadeGeldi = false;
}

// Planlanan kontrol zamani geldi mi? Her loop'ta (otaCheckAndUpdate basinda) cagrilir; sure dolunca sonuc KILITLENIR.
inline bool otaVadeGeldiMi() {
  if (!gOtaVadeGeldi && millis() - gOtaPlanBaslangicMs >= gOtaPlanSureMs) {
    gOtaVadeGeldi = true;
  }
  return gOtaVadeGeldi;
}

// Basarisizlikta ussel geri cekilme: 10 dk, 20 dk, 40 dk ... en fazla periyodik aralik
inline void otaPlanFailure() {
  if (gOtaArdisikHata < 8) {
    gOtaArdisikHata += 1;
  }
  unsigned long gecikme = OTA_FAIL_BACKOFF_BASE_MS << (gOtaArdisikHata - 1);
  if (gecikme > gOtaPeriodicIntervalMs) {
    gecikme = gOtaPeriodicIntervalMs;
  }
  otaPlanNext(gecikme);
}

// Surum karsilastirma (parcali): "4.1.4" < "4.2.0"; basa 'v' ve sondaki on-ek ("-beta") yok sayilir.
inline void otaSurumParcala(const String& s, long out[4]) {
  for (int i = 0; i < 4; i += 1) {
    out[i] = 0;
  }
  int idx = 0;
  size_t i = (s.length() > 0 && (s[0] == 'v' || s[0] == 'V')) ? 1 : 0;
  long cur = -1;
  for (; i <= s.length() && idx < 4; i += 1) {
    const char c = i < s.length() ? s[i] : '\0';
    if (c >= '0' && c <= '9') {
      cur = (cur < 0 ? 0 : cur) * 10 + (c - '0');
      if (cur > 1000000) {
        cur = 1000000;
      }
    } else {
      if (cur >= 0) {
        out[idx++] = cur;
        cur = -1;
      }
      if (c != '.') {
        break;
      }
    }
  }
}

// >0: a, b'den yeni; 0: esit; <0: a eski
inline int otaSurumKarsilastir(const String& a, const String& b) {
  long pa[4];
  long pb[4];
  otaSurumParcala(a, pa);
  otaSurumParcala(b, pb);
  for (int i = 0; i < 4; i += 1) {
    if (pa[i] != pb[i]) {
      return pa[i] > pb[i] ? 1 : -1;
    }
  }
  return 0;
}

inline void otaPersistStatus(const String& status, const String& version = "") {
  gOtaLastStatus = status;
  if (!version.isEmpty()) {
    gOtaLastVersion = version;
  }
  if (gOtaPrefs.isKey(OTA_PREF_LAST_STATUS) || !status.isEmpty()) {
    gOtaPrefs.putString(OTA_PREF_LAST_STATUS, gOtaLastStatus);
  }
  if (!gOtaLastVersion.isEmpty()) {
    gOtaPrefs.putString(OTA_PREF_LAST_VERSION, gOtaLastVersion);
  }
}

inline void otaPublishEvent(const char* eventName, const String& detail = "") {
  if (gOtaEventPublisher != nullptr) {
    gOtaEventPublisher(eventName, detail.c_str());  // yayinlayici (mqttPublishOtaEvent) olaya ota_job_id'yi ekler (kimlik varsa)
  }
  if (otaOlayBitirirMi(eventName)) {
    otaIsKimligiTemizle();  // deneme bitti (basari/hata/guncel): sonraki otomatik kontrol eski isin kimligini tasimasin
  }
}

inline void otaSetEventPublisher(OtaEventPublisher publisher) {
  gOtaEventPublisher = publisher;
}

inline void otaSetMqttHooks(OtaMqttHook kapat, OtaMqttHook ac) {
  gOtaMqttKapat = kapat;
  gOtaMqttAc = ac;
}

// Calisan imaj PENDING_VERIFY mi? (yeni OTA imaji acildi, henuz gecerli isaretlenmedi). Yalniz bir kez (acilista) okunur:
// bu durum otadata'dan gelir ve acilistan sonra yalniz otaGecerliligiDogrula() tarafindan degistirilir.
inline bool otaCalisanImajPendingMi() {
  const esp_partition_t* calisan = esp_ota_get_running_partition();
  esp_ota_img_states_t durum;
  return calisan != nullptr && esp_ota_get_state_partition(calisan, &durum) == ESP_OK && durum == ESP_OTA_IMG_PENDING_VERIFY;
}

inline void otaSetup() {
  gOtaPrefs.begin(OTA_PREFS_NAMESPACE, false);
  gOtaLastStatus = gOtaPrefs.getString(OTA_PREF_LAST_STATUS, "beklemede");
  gOtaLastVersion = gOtaPrefs.getString(OTA_PREF_LAST_VERSION, "");

  // Dogrulanmamis (PENDING_VERIFY) imaj calisirken diger OTA bolumu SILINMEZ: yeni imaj bozuksa elde gecerli imaj kalmazdi.
  gOtaImajDogrulanmadi = otaCalisanImajPendingMi();
  if (gOtaImajDogrulanmadi) {
    Serial.println("OTA: calisan imaj dogrulanmadi (PENDING_VERIFY); dogrulanana kadar yeni OTA baslatilmaz.");
  }

  // Yeni boot: NVS'te "guncelleme indiriliyor" / "guncelleme tamam" / "kontrol ediliyor" kalmissa, cihaz acilmistir.
  // Calisan surum hedef surumse basarili; degilse (ornegin geri alma) durumu dogru yaz.
  if (gOtaLastStatus == "guncelleme indiriliyor" || gOtaLastStatus == "guncelleme tamam" || gOtaLastStatus == "kontrol ediliyor") {
    if (gOtaLastStatus == "guncelleme tamam" && !gOtaLastVersion.isEmpty() && gOtaLastVersion != String(OTA_CURRENT_VERSION)) {
      otaPersistStatus("geri alindi: " + gOtaLastVersion + " yuklenemedi");
    } else {
      otaPersistStatus("guncel", OTA_CURRENT_VERSION);
    }
  } else if (!gOtaLastVersion.isEmpty() && gOtaLastVersion == String(OTA_CURRENT_VERSION)) {
    otaPersistStatus("guncel", OTA_CURRENT_VERSION);
  }

  // Calisan surum, denenen surumle ayniysa deneme sayacini temizle (guncelleme basarili)
  if (gOtaPrefs.getString(OTA_PREF_TRY_VERSION, "") == String(OTA_CURRENT_VERSION)) {
    gOtaPrefs.remove(OTA_PREF_TRY_VERSION);
    gOtaPrefs.remove(OTA_PREF_TRY_COUNT);
  }

  // Ilk kontrol Wi-Fi oturduktan sonra planlanir (otaCheckAndUpdate icinde)
  Serial.print("OTA surum: ");
  Serial.println(OTA_CURRENT_VERSION);
  Serial.print("OTA son durum: ");
  Serial.println(gOtaLastStatus);
}

// dagit=true (toplu is, ota_job_id): kontrol hemen degil, MAC tabanli 0-120 sn gecikmeyle planlanir; cok sayida cihaz ayni anda
// manifest + 1,8 MB indirmeye girmesin. Tekil/elle talep (dagit=false) hemen calisir. Ikisi de acik yonetici talebidir:
// OTA_MIN_RETRY_MS (otomatik tekrar siniri) bunlari geciktirmez.
inline void otaTalepEt(const char* reason = "manual", bool dagit = false) {
  if (dagit) {
    gOtaLastAttemptAt = 0;
    otaPlanNext(0, true, OTA_JOB_JITTER_MS);
  } else {
    gOtaPendingCheck = true;
  }
  Serial.print("OTA kontrol talebi: ");
  Serial.println(reason);
}

// Yonetici "retry" istediginde ayni surum icin deneme sayacini (ve ussel geri cekilmeyi) sifirlar.
inline void otaDenemeSayacinaSifirla() {
  gOtaPrefs.remove(OTA_PREF_TRY_VERSION);
  gOtaPrefs.remove(OTA_PREF_TRY_COUNT);
  gOtaArdisikHata = 0;
}

inline String otaLastStatus() {
  return gOtaLastStatus;
}

inline String otaLastVersion() {
  return gOtaLastVersion;
}

inline bool otaShouldCheckNow() {
  if (!wifiHazirMi() || gOtaRunning) {
    return false;
  }
  // Rol aktifken (kapi acik pulse) OTA baslatma; TLS/indirme dongusu zaman alir.
  if (roleAktif) {
    return false;
  }
  // TLS sertifika dogrulamasi icin saat senkron olmali
  if (!zamanSenkronMu()) {
    return false;
  }
  // Dogrulanmamis imaj calisirken OTA baslatma (gOtaPendingCheck korunur: dogrulama bitince talep calisir)
  if (gOtaImajDogrulanmadi) {
    return false;
  }
  if (!gOtaPendingCheck && gOtaLastAttemptAt > 0 && millis() - gOtaLastAttemptAt < OTA_MIN_RETRY_MS) {
    return false;
  }
  return gOtaPendingCheck || otaVadeGeldiMi();
}

inline unsigned long otaIntervalFromManifest(JsonDocument& doc) {
  const unsigned long intervalHours = doc["interval_hours"] | 24UL;
  unsigned long intervalMs = intervalHours * 60UL * 60UL * 1000UL;
  if (intervalMs < OTA_MIN_INTERVAL_MS) {
    intervalMs = OTA_MIN_INTERVAL_MS;
  }
  if (intervalMs > OTA_MAX_INTERVAL_MS) {
    intervalMs = OTA_MAX_INTERVAL_MS;
  }
  return intervalMs;
}

inline bool otaReadManifest(JsonDocument& doc) {
  WiFiClientSecure otaClient;
  otaClient.setCACert(TLS_ROOT_CA);
  otaClient.setTimeout(10);           // SANIYE
  otaClient.setHandshakeTimeout(15);  // SANIYE

  HTTPClient http;
  http.setTimeout(10000);             // ms
  String url = String(OTA_MANIFEST_URL) +
               "?current_version=" + OTA_CURRENT_VERSION +
               "&uid=" + cihazUniqueId();
  esp_task_wdt_reset();
  if (!http.begin(otaClient, url)) {
    otaPersistStatus("manifest baglantisi baslatilamadi");
    return false;
  }

  const int code = http.GET();
  esp_task_wdt_reset();
  if (code != HTTP_CODE_OK) {
    otaPersistStatus("manifest http hata: " + String(code));
    http.end();
    return false;
  }

  const String payload = http.getString();
  http.end();

  const DeserializationError error = deserializeJson(doc, payload);
  if (error) {
    otaPersistStatus("manifest json okunamadi");
    return false;
  }
  return true;
}

inline bool otaSha256HexGecerli(const String& hex) {
  if (hex.length() != 64) {
    return false;
  }
  for (size_t i = 0; i < hex.length(); i += 1) {
    const char c = hex[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
      return false;
    }
  }
  return true;
}

// Ayni surum icin deneme hakki var mi? Varsa sayaci artirip NVS'e yazar (indirme coksede/geri alinsa da sayilir).
inline bool otaDenemeHakkiAyir(const String& version) {
  const String kayitliSurum = gOtaPrefs.getString(OTA_PREF_TRY_VERSION, "");
  uint8_t sayac = gOtaPrefs.getUChar(OTA_PREF_TRY_COUNT, 0);
  if (kayitliSurum != version) {
    sayac = 0;
  }
  if (sayac >= OTA_MAX_DENEME) {
    return false;
  }
  gOtaPrefs.putString(OTA_PREF_TRY_VERSION, version);
  gOtaPrefs.putUChar(OTA_PREF_TRY_COUNT, static_cast<uint8_t>(sayac + 1));
  return true;
}

// Gecici ag/sunucu hatasinda (flash'a hicbir sey yazilmadan ya da yazilan kisim atilarak) hakki geri verir: hak yalniz guc kesintisi,
// geri alma, sha256/imaj dogrulama ve flash yazma hatalarinda yanar. NVS'e en fazla 1 yazim (yalniz bu nadir yolda).
inline void otaDenemeHakkiIadeEt(const String& version) {
  if (gOtaPrefs.getString(OTA_PREF_TRY_VERSION, "") != version) {
    return;
  }
  const uint8_t sayac = gOtaPrefs.getUChar(OTA_PREF_TRY_COUNT, 0);
  if (sayac > 0) {
    gOtaPrefs.putUChar(OTA_PREF_TRY_COUNT, static_cast<uint8_t>(sayac - 1));
  }
}

// HTTPClient::writeToStream hedefi: gelen veriyi Update'e yazar ve SHA-256'yi akis olarak hesaplar.
class OtaHashStream : public Stream {
 public:
  mbedtls_sha256_context ctx;
  size_t yazilan = 0;
  size_t toplam = 0;
  int sonYuzde = -1;
  bool hata = false;

  OtaHashStream() {
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts_ret(&ctx, 0);
  }
  ~OtaHashStream() {
    mbedtls_sha256_free(&ctx);
  }

  size_t write(const uint8_t* buf, size_t size) override {
    esp_task_wdt_reset();  // uzun indirme sirasinda loop watchdog'u besle
    if (hata) {
      return 0;
    }
    if (Update.write(const_cast<uint8_t*>(buf), size) != size) {
      hata = true;
      return 0;
    }
    mbedtls_sha256_update_ret(&ctx, buf, size);
    yazilan += size;
    if (toplam > 0) {
      const int yuzde = static_cast<int>((yazilan * 100ULL) / toplam);
      if (yuzde != sonYuzde && yuzde % 10 == 0) {
        sonYuzde = yuzde;
        Serial.print("[OTA] Indiriliyor: %");
        Serial.println(yuzde);
      }
    }
    return size;
  }
  size_t write(uint8_t b) override { return write(&b, 1); }
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  void flush() override {}

  String sonuc() {
    uint8_t ozet[32];
    mbedtls_sha256_finish_ret(&ctx, ozet);
    char hex[65];
    for (int i = 0; i < 32; i += 1) {
      snprintf(&hex[i * 2], 3, "%02x", ozet[i]);
    }
    hex[64] = '\0';
    return String(hex);
  }
};

// Firmware'i indirir, SHA-256'yi dogrular ve yalnizca dogruysa boot bolumunu degistirir.
// Donus: "" = basarili, aksi halde hata metni.
// agHatasi (cikis): true ise hata gecici AG hatasidir (baglanti/TLS/HTTP durum kodu/akis kopmasi); cagiran deneme hakkini iade eder.
// false ise hak YANAR: url/boyut/Update.begin, flash yazma, sha256 uyusmazligi ve Update.end (imaj dogrulama) hatalari.
inline String otaIndirVeYaz(const String& url, const String& beklenenSha256, const String& md5, bool& agHatasi) {
  agHatasi = false;
  WiFiClientSecure otaClient;
  otaClient.setCACert(TLS_ROOT_CA);
  otaClient.setTimeout(15);           // SANIYE
  otaClient.setHandshakeTimeout(20);  // SANIYE

  HTTPClient http;
  http.setTimeout(15000);             // ms
  esp_task_wdt_reset();
  if (!http.begin(otaClient, url)) {
    return "indirme baglantisi baslatilamadi";
  }
  const int code = http.GET();
  esp_task_wdt_reset();
  if (code != HTTP_CODE_OK) {
    http.end();
    agHatasi = true;  // negatif: baglanti/TLS/zaman asimi; pozitif: sunucu durum kodu. Flash'a dokunulmadi.
    return "indirme http hata: " + String(code);
  }

  const int boyut = http.getSize();
  if (boyut <= 0) {
    http.end();
    return "firmware boyutu bilinmiyor";
  }

  if (!Update.begin(static_cast<size_t>(boyut), U_FLASH)) {
    http.end();
    return "Update.begin basarisiz: " + String(Update.errorString());
  }
  if (md5.length() == 32) {
    String md5Kucuk = md5;
    md5Kucuk.toLowerCase();
    Update.setMD5(md5Kucuk.c_str());  // ikinci kontrol (Update.end icinde)
  }

  OtaHashStream akis;
  akis.toplam = static_cast<size_t>(boyut);
  const int yazilanBayt = http.writeToStream(&akis);
  http.end();

  if (akis.hata || yazilanBayt != boyut || akis.yazilan != static_cast<size_t>(boyut)) {
    agHatasi = !akis.hata;  // akis.hata: Update.write (flash) hatasi -> hak yanar; aksi halde baglanti koptu/okuma zaman asimi
    Update.abort();
    return "indirme eksik/hatali (" + String(yazilanBayt) + "/" + String(boyut) + ")";
  }

  String hesaplanan = akis.sonuc();
  String beklenen = beklenenSha256;
  beklenen.toLowerCase();
  if (hesaplanan != beklenen) {
    Update.abort();
    return "sha256 uyusmuyor";
  }

  if (!Update.end(false)) {
    return "Update.end basarisiz: " + String(Update.errorString());
  }
  return "";
}

inline void otaCheckAndUpdate() {
  otaVadeGeldiMi();  // plan suresi dolduysa kilitle (her loop'ta; Wi-Fi/saat/role yuzunden kacirilsa bile tasma "gelecek" uretmez)

  // Ilk kontrol: Wi-Fi ilk kez oturunca ~90 sn + MAC tabanli jitter sonrasina planlanir (OTA_KURULUM.txt)
  if (!gOtaIlkPlanYapildi) {
    if (wifiHazirMi()) {
      otaPlanNext(OTA_BOOT_CHECK_DELAY_MS, true, OTA_BOOT_JITTER_MS);
      gOtaIlkPlanYapildi = true;
    }
    if (!gOtaPendingCheck) {
      return;
    }
  }

  if (!otaShouldCheckNow()) {
    return;
  }

  gOtaRunning = true;
  gOtaPendingCheck = false;
  gOtaLastAttemptAt = millis();
  otaPersistStatus("kontrol ediliyor");
  Serial.println("OTA kontrolu basladi.");
  otaPublishEvent("ota_check_started");

  JsonDocument manifest;
  if (!otaReadManifest(manifest)) {
    Serial.print("OTA manifest hatasi: ");
    Serial.println(gOtaLastStatus);
    otaPublishEvent("ota_check_failed", gOtaLastStatus);
    otaPlanFailure();
    gOtaRunning = false;
    return;
  }

  gOtaPeriodicIntervalMs = otaIntervalFromManifest(manifest);
  const String manifestTarget = String(manifest["target"] | "");
  if (!manifestTarget.isEmpty() && manifestTarget != OTA_TARGET) {
    otaPersistStatus("hedef uyusmazligi: " + manifestTarget + " != " + String(OTA_TARGET));
    Serial.print("OTA HATA: Hedef mimari uyusmuyor! Cihaz hedefi: ");
    Serial.print(OTA_TARGET);
    Serial.print(", Manifestten gelen: ");
    Serial.println(manifestTarget);
    otaPublishEvent("ota_target_mismatch", manifestTarget);
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  const bool updateAvailable = manifest["update_available"] | false;
  const bool usbRequired = manifest["usb_required"] | false;
  const String version = String(manifest["version"] | "");
  const String url = String(manifest["url"] | "");
  const String sha256 = String(manifest["sha256"] | "");
  const String md5 = String(manifest["md5"] | "");
  // NOT: gOtaArdisikHata burada SIFIRLANMAZ (manifest alinmasi basari degildir; ussel geri cekilme 10/20/40 dk bozulurdu).
  // Yalniz "guncel" dallarinda sifirlanir.

  if (usbRequired) {
    otaPersistStatus("USB ile tam yukleme gerekli", version);
    otaPublishEvent("ota_usb_required", version);
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  if (!updateAvailable || url.isEmpty() || version.isEmpty()) {
    const String targetVersion = version.isEmpty() ? String(OTA_CURRENT_VERSION) : version;
    otaPersistStatus("guncel", targetVersion);
    Serial.println("OTA: cihaz guncel.");
    otaPublishEvent("ota_up_to_date", targetVersion);
    gOtaArdisikHata = 0;  // sunucu erisilebilir ve cihaz guncel: geri cekilme basa doner
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  // Yalnizca ARTAN surum: sunucu update_available dese bile esit/eski surum (downgrade) kabul edilmez.
  if (otaSurumKarsilastir(version, String(OTA_CURRENT_VERSION)) <= 0) {
    otaPersistStatus("guncel", String(OTA_CURRENT_VERSION));
    Serial.println("OTA: manifest surumu mevcut surumden yeni degil; downgrade reddedildi.");
    otaPublishEvent("ota_up_to_date", String(OTA_CURRENT_VERSION));
    gOtaArdisikHata = 0;  // guncel (downgrade reddedildi): geri cekilme basa doner
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  if (!url.startsWith(OTA_ALLOWED_URL_PREFIX)) {
    otaPersistStatus("indirme adresi reddedildi (https/sunucu uyusmuyor)", version);
    Serial.println("OTA HATA: manifest url izinli sunucu/HTTPS degil.");
    otaPublishEvent("ota_failed", gOtaLastStatus);
    otaPlanFailure();
    gOtaRunning = false;
    return;
  }

  if (!otaSha256HexGecerli(sha256)) {
    otaPersistStatus("manifest sha256 yok/gecersiz", version);
    Serial.println("OTA HATA: manifest sha256 alani yok veya gecersiz; guncelleme yapilmadi.");
    otaPublishEvent("ota_failed", gOtaLastStatus);
    otaPlanFailure();
    gOtaRunning = false;
    return;
  }

  const esp_partition_t* updatePartition = esp_ota_get_next_update_partition(nullptr);
  if (updatePartition == nullptr) {
    otaPersistStatus("OTA partition yok; cihaza USB ile OTA partition tablosu yuklenmeli", version);
    Serial.println(gOtaLastStatus);
    otaPublishEvent("ota_failed", gOtaLastStatus);
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  if (!otaDenemeHakkiAyir(version)) {
    otaPersistStatus("deneme siniri asildi (" + String(OTA_MAX_DENEME) + "): " + version, version);
    Serial.println("OTA: ayni surum icin deneme siniri asildi, daha yeni surum bekleniyor.");
    otaPublishEvent("ota_failed", gOtaLastStatus);
    otaPlanNext(gOtaPeriodicIntervalMs);
    gOtaRunning = false;
    return;
  }

  otaPersistStatus("guncelleme indiriliyor", version);
  otaPublishEvent("ota_update_available", version);
  Serial.print("Guncelleme geldi. Yeni versiyon: ");
  Serial.println(version);
  Serial.print("OTA hedef partition: ");
  Serial.print(updatePartition->label);
  Serial.print(" boyut: ");
  Serial.println(updatePartition->size);

  // MQTT TLS oturumunu kapat: mbedtls tamponlari (~33 KB bitisik) serbest kalsin, ikinci (indirme) TLS oturumu bellek yetersizliginden
  // (MBEDTLS_ERR_SSL_ALLOC_FAILED) dusmesin. availability=offline (retained) yayinlanir; bitince asagida yeniden baglanilir.
  if (gOtaMqttKapat != nullptr) {
    gOtaMqttKapat();
  }

  bool agHatasi = false;
  const String hata = otaIndirVeYaz(url, sha256, md5, agHatasi);

  // Sonuc once NVS'e yazilir (guc kesilirse acilista dogru okunsun); sonra MQTT hemen yeniden baglanir ki
  // ota_success / ota_failed olayi (sunucudaki OTA is takibi bunlara bagli) sunucuya ulassin.
  if (hata.isEmpty()) {
    otaPersistStatus("guncelleme tamam", version);
  } else {
    otaPersistStatus("guncelleme basarisiz: " + hata, version);
    if (agHatasi) {
      otaDenemeHakkiIadeEt(version);  // gecici ag hatasi: deneme hakki yanmasin (3 hak ~dakikalar icinde bitmesin)
    }
  }
  if (gOtaMqttAc != nullptr) {
    gOtaMqttAc();
  }

  if (!hata.isEmpty()) {
    Serial.println(gOtaLastStatus);
    otaPublishEvent("ota_failed", gOtaLastStatus);
    otaPlanFailure();  // geri cekilme: 10 dk, 20 dk, 40 dk ...
    gOtaRunning = false;
    return;
  }

  Serial.println("OTA: guncelleme tamam. WiFi RF kapatiliyor ve temiz yeniden baslatiliyor...");
  otaPublishEvent("ota_success", version);
  delay(300);
  WiFi.disconnect(true, true);
  WiFi.mode(WIFI_OFF);
  delay(300);
  esp_restart();
}

// Rollback dogrulamasi: yeni imaj PENDING_VERIFY durumundaysa Wi-Fi + MQTT bagli ve OTA_SAGLIK_SURESI_MS kadar
// kesintisiz saglikli kalinca imaji gecerli isaretler. Gecerli isaretlenmeden yeniden baslarsa bootloader onceki surume doner.
// (main.cpp'deki verifyRollbackLater() true dondurdugu icin Arduino cekirdegi imaji kendiliginden gecerli yapmaz.)
inline bool gOtaGecerliKontrolBitti = false;
inline bool gOtaSaglikSayiyor = false;
inline unsigned long gOtaSaglikBaslangicMs = 0;

inline void otaGecerliligiDogrula(bool saglikli) {
  if (gOtaGecerliKontrolBitti) {
    return;
  }
  if (!saglikli) {
    gOtaSaglikSayiyor = false;
    return;
  }
  if (!gOtaSaglikSayiyor) {
    gOtaSaglikSayiyor = true;
    gOtaSaglikBaslangicMs = millis();
    return;
  }
  if (millis() - gOtaSaglikBaslangicMs < OTA_SAGLIK_SURESI_MS) {
    return;
  }

  gOtaGecerliKontrolBitti = true;
  const esp_partition_t* calisan = esp_ota_get_running_partition();
  esp_ota_img_states_t durum;
  if (calisan != nullptr && esp_ota_get_state_partition(calisan, &durum) == ESP_OK && durum == ESP_OTA_IMG_PENDING_VERIFY) {
    if (esp_ota_mark_app_valid_cancel_rollback() == ESP_OK) {
      gOtaImajDogrulanmadi = false;  // artik yeni OTA baslatilabilir (bekleyen gOtaPendingCheck talebi calisir)
      Serial.println("OTA: yeni imaj saglikli calisti, gecerli olarak isaretlendi (rollback iptal).");
      otaPublishEvent("ota_validated", String(OTA_CURRENT_VERSION));
    } else {
      Serial.println("OTA: imaj gecerli isaretlenemedi!");
    }
  }
}

#endif
