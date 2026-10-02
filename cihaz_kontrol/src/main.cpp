#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <esp_task_wdt.h>

#include "mqtt_baglanti.h"
#include "ota_guncelleme.h"
#include "role_kontrol.h"
#include "wifi_baglanti.h"
#include "yerel_kapi_kontrol.h"
#include "gm60_scanner.h"
#include "display_uart.h"
#include "display_protocol.h"

#include "offline_log.h"

#if defined(BOARD_ESP32_WROOM_RELAY)
#include "admin_pin.h"
#endif

// SERI KOMUTLAR (sirket "Cihaz Dene" araci kullanir):
//  - HER derlemede, her zaman acik: '?' 's' 'u' 'i' (salt-okunur durum: UID / hedef / surum), 'r' (tek, debounce'lu role pulse),
//    'k' (GM60 kamera self-test) ve satir tabanli "ADMINPIN:NNNNNN" (yalniz ekranli WROOM).
//  - ATOLYE MODU kapisi (uretim derlemesi): 'h' (role HIGH, 60 sn sonra OTOMATIK birakilir), 'l' (role LOW) ve 'p' (pin bulma testi)
//    yalniz atolye modunda calisir. Atolye modu = kayitli Wi-Fi bilgisi YOK (yeni / sifirlanmis kart) VEYA BLE provisioning
//    penceresi aktif (reset butonuna 3 sn basili tutma). Saha cihazi (Wi-Fi kayitli, provisioning kapali) h/l/p'ye cevap vermez.
//  - Derleme bayragi -D AHBU_DEBUG_SERIAL_CMDS: atolye modu kapisi kalkar (tum komutlar her zaman acik) ve 5 sn'lik durum dokumu aktif olur.

WiFiClientSecure espClientSecure;
PubSubClient client(espClientSecure);

constexpr unsigned long STATUS_PRINT_INTERVAL_MS = 5000;
unsigned long sonDurumYazdirmaMs = 0;

// Loop watchdog: loop bu sure icinde esp_task_wdt_reset() cagirmazsa cihaz yeniden baslar.
// OTA indirme / TLS el sikisma gibi uzun islerde ilgili kod watchdog'u besler.
constexpr uint32_t LOOP_WDT_TIMEOUT_S = 30;

// Arduino cekirdeginin zayif (weak) kancasi: true donunce yeni (OTA) imaj otomatik gecerli ISARETLENMEZ;
// otaGecerliligiDogrula() Wi-Fi+MQTT ~60 sn saglikli calisinca isaretler, aksi halde bootloader onceki surume doner.
extern "C" bool verifyRollbackLater() {
  return true;
}

void seriDurumYazdir();

// ATOLYE MODU kapisi (h / l / p komutlari). Tespit:
//  (a) kayitli Wi-Fi bilgisi yok (gWifiConfigured == false: yeni veya Wi-Fi'si sifirlanmis kart) VEYA
//  (b) BLE provisioning penceresi su an aktif (wifiProvisioningAktifMi(): reset butonu 3 sn -> Wi-Fi bilgisi silinir -> yeniden baslar).
// AHBU_DEBUG_SERIAL_CMDS derlemesinde her zaman acik.
static bool atolyeModuAcikMi() {
#if defined(AHBU_DEBUG_SERIAL_CMDS)
  return true;
#else
  return !gWifiConfigured || wifiProvisioningAktifMi();
#endif
}

// Seri porta herhangi bir bayt geldi (arac/terminal bagli ve konusuyor): periyodik durum dokumu bu durumda da acilir.
static bool gSeriOturumAktif = false;

// Pin bulma testi (atolye): her test pinini 800 ms HIGH yapar. Islem loop'u bloklar, yani Wi-Fi/MQTT/OTA isleri bu surede
// calismaz; watchdog her adimda beslenir. Bitince pinler GUVENLI duruma doner: role PASIF, dugme/UART pinleri yeniden kurulur.
void pinBulmaTesti() {
#if defined(BOARD_ESP32_WROOM_RELAY)
  const uint8_t testPins[] = {2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33};
#else
  const uint8_t testPins[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 21};
#endif
  const uint8_t rolePasif = ROLE_ACTIVE_LOW ? HIGH : LOW;

  // Baslamadan once calisan pulse / manuel tutma varsa birak (role pasif baslasin)
  if (roleTimer != nullptr) {
    esp_timer_stop(roleTimer);
  }
  roleBirak();

  Serial.println("==========================================");
  Serial.println("PIN BULMA TESTI BASLADI!");
  Serial.println("Kartin uzerindeki D1, D4 isiklarina ve roleye bakin.");
  Serial.println("==========================================");
  for (uint8_t i = 0; i < sizeof(testPins); i++) {
    const uint8_t pin = testPins[i];
    esp_task_wdt_reset();
    pinMode(pin, OUTPUT);
    digitalWrite(pin, HIGH);
    Serial.print(">>> TEST GPIO ");
    Serial.print(pin);
    Serial.println(" -> HIGH");
    for (int adim = 0; adim < 8; adim++) {  // 8 x 100 ms = 800 ms; her adimda watchdog beslenir
      delay(100);
      esp_task_wdt_reset();
    }
    digitalWrite(pin, pin == ROLE_PIN ? rolePasif : LOW);
    delay(150);
  }

  // GUVENLI DURUMA DON: test pinleri yuksek empedansa, role pini PASIF cikis, dugme ve UART pinleri yeniden kurulur
  for (uint8_t i = 0; i < sizeof(testPins); i++) {
    if (testPins[i] != ROLE_PIN) {
      pinMode(testPins[i], INPUT);
    }
  }
  pinMode(ROLE_PIN, OUTPUT);
  digitalWrite(ROLE_PIN, rolePasif);
  pinMode(WIFI_RESET_BUTTON_PIN, WIFI_RESET_BUTTON_ACTIVE_LOW ? INPUT_PULLUP : INPUT);
  gm60Setup();         // GM60 UART pinleri test sirasinda GPIO'ya cevrildi: yeniden bagla
  displayUartSetup();  // yalniz WROOM: ekran UART'ini yeniden bagla (C3'te bos fonksiyon)
  while (Serial.available() > 0) {
    Serial.read();     // test sirasinda birikmis tuslari at (testin tekrar tetiklenmesini onler)
  }
  esp_task_wdt_reset();
  Serial.println("==========================================");
  Serial.println("PIN BULMA TESTI BITTI.");
  rolePinDurumuYazdir("Role pin okuma");
  Serial.println("==========================================");
}

// Satir tabanli seri komutlar (her derlemede acik): "ADMINPIN:NNNNNN" (yalniz ekranli WROOM). PIN yankilanmaz/yazdirilmaz.
static void seriSatirIsle(const String& satir) {
#if defined(BOARD_ESP32_WROOM_RELAY)
  if (satir.startsWith("ADMINPIN:")) {
    AdminPinRed red = ADMIN_PIN_RED_YOK;
    if (adminPinAyarla(satir.substring(9), &red)) {
      Serial.println("Yonetici PIN'i guncellendi.");
      mqttPublishState(gDoorLocked);
    } else if (red == ADMIN_PIN_RED_ZAYIF) {
      // Ret NEDENI yazilir; PIN degeri yazilmaz
      Serial.println("Yonetici PIN'i REDDEDILDI: zayif PIN (000000/111111/123456/654321/123123/121212/112233/000001, ayni rakam ya da ardisik rakamlar yasak).");
    } else {
      Serial.println("Yonetici PIN'i gecersiz (tam 6 rakam olmali; silmek icin 'ADMINPIN:' bos birakilir).");
    }
    return;
  }
#endif
  (void)satir;
}

void seriKomutKontrol() {
  static String satir;
  static unsigned long sonKarakterMs = 0;

  // Yarim kalmis satir takilmasin
  if (!satir.isEmpty() && millis() - sonKarakterMs > 2000) {
    satir = "";
  }

  while (Serial.available() > 0) {
    const char komut = static_cast<char>(Serial.read());
    sonKarakterMs = millis();
    gSeriOturumAktif = true;

    if (komut == '\r' || komut == '\n') {
      if (!satir.isEmpty()) {
        seriSatirIsle(satir);
        satir = "";
      }
      continue;
    }

    if (satir.isEmpty()) {
      // 1) Salt-okunur durum komutlari (HER derlemede acik): cihaz UID / hedef / surum / durum ozeti. Sir yazdirmaz.
      if (komut == '?' || komut == 's' || komut == 'S' || komut == 'u' || komut == 'U' || komut == 'i' || komut == 'I') {
        seriDurumYazdir();
        continue;
      }

      // 2) 'r' (tek, debounce'lu normal pulse) ve 'k' (kamera self-test): HER derlemede acik
      if (komut == 'r' || komut == 'R') {
        Serial.println("Seri komut: role pulse");
        if (roleTetikle()) {
          gDoorLocked = false;
          displayUartSend(CMD_DOOR_OPENED);
          mqttPublishEvent("serial_pulse_started");
          mqttPublishState(gDoorLocked);
          offlineLogKaydet("serial_btn", "Seri Port", "");
        }
        continue;
      }
      if (komut == 'k' || komut == 'K') {
        Serial.println("Seri komut: kamera self-test");
        gm60SelfTestManuel();
        esp_task_wdt_reset();
        continue;
      }

      // 3) 'h' / 'l' / 'p': ATOLYE MODU kapisi (yeni/sifirlanmis kart veya BLE provisioning penceresi)
      if (komut == 'h' || komut == 'H' || komut == 'l' || komut == 'L' || komut == 'p' || komut == 'P') {
        if (!atolyeModuAcikMi()) {
          Serial.println("Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)");
          continue;
        }
        if (komut == 'h' || komut == 'H') {
          Serial.println("Seri komut: role pini HIGH");
          roleManuelSeviye(HIGH);  // 60 sn sonra OTOMATIK birakilir; tutma sirasinda yeni pulse/OTA baslamaz
          if (roleAktif) {
            gDoorLocked = false;
          }
        } else if (komut == 'l' || komut == 'L') {
          Serial.println("Seri komut: role pini LOW");
          roleManuelSeviye(LOW);   // hemen birakir (tamamlanma bildirimi loop'ta)
        } else {
          Serial.println("Seri komut: pin bulma testi");
          pinBulmaTesti();
        }
        continue;
      }
    }

    if (satir.length() < 40) {
      satir += komut;
    } else {
      satir = "";  // asiri uzun satir: at
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Ekran (yalniz WROOM): dinamik QR rotasyonu ve durum senkronizasyonu
// ---------------------------------------------------------------------------------------------
#if defined(BOARD_ESP32_WROOM_RELAY)

static bool sonWifiDurum = false;
static bool sonMqttDurum = false;
static unsigned long sonDisplayQrSyncMs = 0;

// 30 Saniyelik Dinamik Ekran QR Rotasyonu
static String gCurrentScreenQrToken = "";
static unsigned long gScreenQrTokenGeneratedMs = 0;
static bool gScreenQrMqttYayinlandi = false;
constexpr unsigned long SCREEN_QR_ROTATION_INTERVAL_MS = 30000UL;

// esp_random() yalniz Wi-Fi veya Bluetooth (RF) aciksa gercek rastgeledir.
static bool rfAktifMi() {
  return WiFi.getMode() != WIFI_MODE_NULL || wifiProvisioningAktifMi();
}

static String generateDynamicScreenQrToken() {
  const char charset[] = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  constexpr uint32_t n = sizeof(charset) - 1;
  constexpr uint32_t sinir = (0xFFFFFFFFu / n) * n;  // modulo yanliligini onle (reddetmeli ornekleme)
  String token = "";
  while (token.length() < 6) {
    const uint32_t r = esp_random();
    if (r >= sinir) {
      continue;
    }
    token += charset[r % n];
  }
  return token;
}

void broadcastScreenQrToken(bool isNewToken) {
  // RF kapaliyken token URETME: esp_random() tahmin edilebilir olabilir.
  if (!rfAktifMi()) {
    return;
  }

  if (gCurrentScreenQrToken.length() == 0 || isNewToken) {
    gCurrentScreenQrToken = generateDynamicScreenQrToken();
    gScreenQrTokenGeneratedMs = millis();
    gScreenQrMqttYayinlandi = false;
  }

  // 1. Ekran kartina UART uzerinden dinamik QR verisini gonder (30 sn gecerli)
  const String qrCmd = String(CMD_SHOW_QR_PREFIX) + "AHBU:DOOR:" + cihazUniqueId() + ":" + gCurrentScreenQrToken;
  displayUartSend(qrCmd);

  // 2. Token sunucuya bildirilmediyse (yeni token veya onceki yayin basarisiz) MQTT ile gonder; retained KULLANILMAZ
  if (!gScreenQrMqttYayinlandi && client.connected()) {
    gScreenQrMqttYayinlandi = mqttPublishScreenQr(gCurrentScreenQrToken, 30);
  }
}

void displayDurumuYenidenGonder() {
  displayUartSend(wifiHazirMi() ? CMD_WIFI_CONNECTED : CMD_WIFI_DISCONNECTED);
  displayUartSend(client.connected() ? CMD_MQTT_CONNECTED : CMD_MQTT_DISCONNECTED);
}

void displayDurumSenkronizasyonLoop() {
  const bool aktifWifi = wifiHazirMi();
  if (aktifWifi != sonWifiDurum) {
    sonWifiDurum = aktifWifi;
    displayUartSend(aktifWifi ? CMD_WIFI_CONNECTED : CMD_WIFI_DISCONNECTED);
  }

  const bool aktifMqtt = client.connected();
  if (aktifMqtt != sonMqttDurum) {
    sonMqttDurum = aktifMqtt;
    displayUartSend(aktifMqtt ? CMD_MQTT_CONNECTED : CMD_MQTT_DISCONNECTED);
    // MQTT yeni baglandiysa yeni ekran QR token'ini hemen sunucuya bildir
    if (aktifMqtt) {
      broadcastScreenQrToken(true);
      sonDisplayQrSyncMs = millis();
    }
  }

  // 30 saniyede bir YENI dinamik QR uret ve yayinla
  if (gCurrentScreenQrToken.length() == 0 || (millis() - gScreenQrTokenGeneratedMs >= SCREEN_QR_ROTATION_INTERVAL_MS)) {
    broadcastScreenQrToken(true);
    sonDisplayQrSyncMs = millis();
  }
  // Ekran karti senkronizasyonu icin her 5 saniyede bir mevcut token ve baglanti durumlarini tekrar ilet
  else if (millis() - sonDisplayQrSyncMs >= 5000) {
    sonDisplayQrSyncMs = millis();
    displayDurumuYenidenGonder();
    broadcastScreenQrToken(false);
  }
}

#else

// ESP32-C3 Super Mini: harici ekran yok (Kural 3) -> ekran QR token'i uretilmez/yayinlanmaz.
void broadcastScreenQrToken(bool isNewToken) {
  (void)isNewToken;
}
void displayDurumuYenidenGonder() {}
void displayDurumSenkronizasyonLoop() {}

#endif

// System status getters for display UART
bool systemWifiReady() { return wifiHazirMi(); }
String systemWifiSsid() { return wifiAktifSsid(); }
String systemWifiIp() { return wifiIpAdresi(); }
int systemWifiRssi() { return wifiSinyalDbm(); }
bool systemMqttReady() { return mqttBagliMi(); }
bool systemCameraConnected() { return gm60Bagli; }
String systemFirmwareVersion() { return String(OTA_CURRENT_VERSION); }
String systemHardwareTarget() { return String(OTA_TARGET); }

void systemMqttOlay(const char* eventName, const char* detail) {
  mqttPublishEvent(eventName, detail);
}

// Ekrandan PIN dogrulamasi gecen yonetici kapi acma istegi. true: role tetiklendi.
bool systemAdminKapiAc() {
#if defined(BOARD_ESP32_WROOM_RELAY)
  if (!roleTetikle()) {
    return false;
  }
  gDoorLocked = false;
  mqttPublishEvent("admin_display_pulse_started");
  mqttPublishState(gDoorLocked);
  offlineLogKaydet("admin_display_btn", "Yonetici Ekran", "");
  return true;
#else
  return false;
#endif
}

void seriDurumYazdir() {
  // Salt-okunur ozet: token / PIN / parola / MQTT bilgisi ASLA yazdirilmaz.
  Serial.println("--- ESP32 SISTEM BILGISI ---");
  Serial.print("Cihaz Unique ID: ");
  Serial.println(cihazUniqueId());
  Serial.print("Firmware Versiyon: ");
  Serial.println(OTA_CURRENT_VERSION);
  Serial.print("Hardware Target: ");
  Serial.println(OTA_TARGET);
  Serial.print("Wi-Fi Durumu: ");
  Serial.println(wifiHazirMi() ? "Bagli" : "Bagli Degil");
  Serial.print("WiFi kayitli: ");
  Serial.println(wifiAktifSsid().isEmpty() ? "Yok" : "Var");
  Serial.print("WiFi SSID: ");
  Serial.println(wifiAktifSsid().isEmpty() ? "-" : wifiAktifSsid());
  Serial.print("WiFi IP: ");
  Serial.println(wifiHazirMi() ? wifiIpAdresi() : "-");
  Serial.print("WiFi gucu: ");
  if (wifiHazirMi()) {
    Serial.print("%");
    Serial.print(wifiSinyalYuzde());
    Serial.print(" (");
    Serial.print(wifiSinyalDbm());
    Serial.println(" dBm)");
  } else {
    Serial.println("-");
  }
  Serial.print("Bluetooth provisioning: ");
  Serial.println(wifiProvisioningAktifMi() ? "aktif" : "pasif");
  Serial.print("Bluetooth adi: ");
  Serial.println(wifiBleDeviceName());
  Serial.print("WiFi LED GPIO: ");
  Serial.println(WIFI_STATUS_LED_PIN);
  Serial.print("Bluetooth LED GPIO: ");
  if (BLE_STATUS_LED_PIN < 0) {
    Serial.println("-");
  } else {
    Serial.println(BLE_STATUS_LED_PIN);
  }
  Serial.print("MQTT: ");
  Serial.println(client.connected() ? "bagli" : "bagli degil");
  Serial.print("MQTT kimligi: ");
  Serial.println(wifiHasMqttCredentials() ? "cihaz ozel kimlikli" : "eksik");
  Serial.print("MQTT sunucu: ");
  Serial.print(mqttAktifSunucu());
  Serial.print(":");
  Serial.println(mqttAktifPort());
  Serial.print("Yerel kontrol: ");
  Serial.println(!wifiHasLocalControlToken() ? "kapali (anahtar yok)" : (gYerelHmacSaglam ? "etkin (anahtar var)" : "KAPALI (HMAC oz-testi basarisiz)"));
#if defined(BOARD_ESP32_WROOM_RELAY)
  Serial.print("Yonetici PIN: ");
  Serial.println(adminPinTanimliMi() ? "tanimli" : "tanimli degil");
#endif
  Serial.print("Role GPIO: ");
  Serial.println(ROLE_PIN);
  Serial.print("Kamera / QR Okuyucu: ");
  Serial.println(gm60Bagli ? "Bagli (Hazir)" : (gm60Aktif ? "Bagli Degil" : "Pasif"));
  Serial.print("GM60 QR Okuyucu: ");
  Serial.println(gm60Bagli ? "aktif (bagli)" : (gm60Aktif ? "aktif (baglanti bekleniyor)" : "pasif"));
  Serial.print("Firmware surumu: ");
  Serial.println(OTA_CURRENT_VERSION);
  Serial.print("OTA durum: ");
  Serial.println(otaLastStatus());
  Serial.print("OTA son hedef surum: ");
  Serial.println(otaLastVersion().isEmpty() ? "-" : otaLastVersion());
  rolePinDurumuYazdir("Role pin okuma");
  Serial.print("Atolye modu: ");
  Serial.println(atolyeModuAcikMi() ? "acik" : "kapali");
  if (atolyeModuAcikMi()) {
    Serial.println("Seri role test: h=HIGH, l=LOW, r=pulse, k=kamera test, p=pin bulma");
  } else {
    Serial.println("Seri komutlar: ?=durum, r=pulse, k=kamera test (h/l/p yalniz atolye modunda)");
  }
  Serial.println("------------------------");
}

void setup() {
  // ILK satir: role pini pasif seviyeye cekilir (acilista role tiklamasin). Wi-Fi/MQTT/OTA gibi bloklayan isler
  // role suresini etkilemez: birakma esp_timer gorevinde yapilir (role_kontrol.h).
  roleSetup();

#if defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
  // C3: Serial = HWCDC (USB-Serial/JTAG). TX tamponu begin()'den ONCE buyutulur (ISR henuz kapali); 256 B varsayilani, host
  // bagliyken ardisik log patlamalarini (seriDurumYazdir ~0,9 KB) timeout=0 ile keserdi.
  Serial.setTxBufferSize(2048);
#endif
  Serial.begin(115200);
#if defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
  // Cekirdek, USB host bir kez baglanti kurunca TX zaman asimini 100 ms'ye yukseltir ve host ayrilsa da dusurmez: tampon
  // dolunca her print() 100 ms bloklar (5 sn'lik durum dokumu loop'u saniyelerce bloklar). 0 = hic bekleme (tampon doluysa yazi atilir).
  Serial.setTxTimeoutMs(0);
#endif
  delay(100);
  roleSetupLogYaz();

  // Loop watchdog (loop task abone edilir; OTA/TLS indirme sirasinda ilgili kod besler)
  esp_task_wdt_init(LOOP_WDT_TIMEOUT_S, true);
  esp_task_wdt_add(nullptr);

#if defined(BOARD_ESP32_WROOM_RELAY)
  // Canlilik gostergesi: Power LED (GPIO23) acilista 2 kez yanip soner, sonra acik kalir
  pinMode(WIFI_STATUS_LED_PIN, OUTPUT);
  for (int i = 0; i < 2; i++) {
    digitalWrite(WIFI_STATUS_LED_PIN, HIGH);
    delay(100);
    digitalWrite(WIFI_STATUS_LED_PIN, LOW);
    delay(100);
  }
  digitalWrite(WIFI_STATUS_LED_PIN, HIGH);
#endif

  offlineLogInit();
  esp_task_wdt_reset();
#if defined(BOARD_ESP32_WROOM_RELAY)
  adminPinBaslat();
#endif
  gm60Setup();
  displayUartSetup();

  // === ACILIS DONANIM SELF-TESTI ===
  // (Role cek-birak testi KALDIRILDI: acilista kapi/role istenmeden tetiklenmemeli.)
  Serial.println("\n==========================================");
  Serial.println("DONANIM SELF-TEST BASLATILIYOR");
  Serial.println("==========================================");
  Serial.print("[TEST 1/1] GM60 Kamera test ediliyor (Isik/Bip/Yanit)... ");
  const bool kameraOk = gm60SelfTest(false);
  if (kameraOk) {
    Serial.println("OK (Kamera bagli, isik yakildi ve ses verildi)");
  } else {
    Serial.println("UYARI (Kamera yanit vermedi - baglanti/pinleri kontrol edin)");
  }
  Serial.println("==========================================\n");
  esp_task_wdt_reset();

  wifiBaglan();
  esp_task_wdt_reset();
  otaSetup();
  mqttSetup();
}

void loop() {
  esp_task_wdt_reset();

  // Role birakildi (esp_timer): durumu MQTT baglantisindan BAGIMSIZ guncelle, sonra bildir.
  if (roleLoop()) {
    gDoorLocked = true;
    displayUartSend(CMD_DOOR_CLOSED);
    mqttNotifyPulseCompleted();
  }

  seriKomutKontrol();
  gm60Loop();
  displayUartLoop();
  displayDurumSenkronizasyonLoop();
  wifiLoop();
  yerelKapiKontrolLoop();
  mqttLoopHandler();
  otaCheckAndUpdate();
  otaGecerliligiDogrula(wifiHazirMi() && mqttBagliMi());
  offlineLogSenkronizeEt();
  mqttKendiniToparla();  // MQTT 6 saatten uzun baglanamazsa kontrollu yeniden baslatma (role aktif degilken)
#if defined(BOARD_ESP32_WROOM_RELAY)
  adminPinZamanlayici();  // PIN kilidi suresi dolunca sorgu beklemeden kapat (bayat baslangic damgasi kilidi yeniden acamaz)
#endif

  // Periyodik (5 sn) durum dokumu: debug derlemesinde, atolye modunda (yeni/sifirlanmis kart) veya seri porta bir arac/terminal
  // baglanip konustuktan sonra (sirket "Cihaz Dene" paneli canli guncellensin). Saha cihazinda kimse dinlemiyorsa yazdirilmaz.
#if defined(AHBU_DEBUG_SERIAL_CMDS)
  const bool periyodikDurum = true;
#else
  const bool periyodikDurum = atolyeModuAcikMi() || gSeriOturumAktif;
#endif
  if (periyodikDurum && millis() - sonDurumYazdirmaMs >= STATUS_PRINT_INTERVAL_MS) {
    sonDurumYazdirmaMs = millis();
    seriDurumYazdir();
  }
}
