#include <Arduino.h>
#include <esp_task_wdt.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

#include "mqtt_baglanti.h"
#include "offline_log.h"
#include "ota_guncelleme.h"
#include "role_kontrol.h"
#include "wifi_baglanti.h"
#include "yerel_kapi_kontrol.h"

WiFiClientSecure espClientSecure;
PubSubClient client(espClientSecure);

constexpr unsigned int WDT_TIMEOUT_SECONDS = 8;
constexpr unsigned long STATUS_PRINT_INTERVAL_MS = 5000;
unsigned long sonDurumYazdirmaMs = 0;

void pinBulmaTesti() {
  const uint8_t testPins[] = {3, 4, 5, 6, 7, 8, 9, 10, 20, 21};
  Serial.println("Pin bulma testi basladi. LED + ucunu yazilan GPIO pinine, - ucunu GND'ye baglayin.");
  for (uint8_t i = 0; i < sizeof(testPins); i++) {
    esp_task_wdt_reset();
    const uint8_t pin = testPins[i];
    pinMode(pin, OUTPUT);
    digitalWrite(pin, HIGH);
    Serial.print("TEST GPIO ");
    Serial.print(pin);
    Serial.println(" -> HIGH");
    delay(1200);
    digitalWrite(pin, LOW);
    Serial.print("TEST GPIO ");
    Serial.print(pin);
    Serial.println(" -> LOW");
    delay(300);
  }
  pinMode(ROLE_PIN, OUTPUT);
  digitalWrite(ROLE_PIN, ROLE_ACTIVE_LOW ? HIGH : LOW);
  Serial.println("Pin bulma testi bitti.");
}

void seriKomutKontrol() {
  while (Serial.available() > 0) {
    const char komut = static_cast<char>(Serial.read());
    if (komut == 'r' || komut == 'R') {
      Serial.println("Seri komut: role pulse");
      roleTetikle();
    } else if (komut == 'h' || komut == 'H') {
      Serial.println("Seri komut: role pini HIGH");
      roleManuelSeviye(HIGH);
    } else if (komut == 'l' || komut == 'L') {
      Serial.println("Seri komut: role pini LOW");
      roleManuelSeviye(LOW);
    } else if (komut == 'p' || komut == 'P') {
      Serial.println("Seri komut: pin bulma testi");
      pinBulmaTesti();
    } else if (komut == 'w') {
      Serial.println("Seri komut: WiFi LED 5 saniye ON");
      wifiStatusLedManuel(true);
    } else if (komut == 'q') {
      Serial.println("Seri komut: WiFi LED 5 saniye OFF");
      wifiStatusLedManuel(false);
    }
  }
}

void seriDurumYazdir() {
  Serial.println("----- CIHAZ DURUMU -----");
  Serial.print("Cihaz UID: ");
  Serial.println(cihazUniqueId());
  Serial.print("WiFi kayitli: ");
  Serial.println(wifiAktifSsid().isEmpty() ? "hayir" : "evet");
  Serial.print("WiFi SSID: ");
  Serial.println(wifiAktifSsid().isEmpty() ? "-" : wifiAktifSsid());
  Serial.print("WiFi bagli: ");
  Serial.println(wifiHazirMi() ? "evet" : "hayir");
  Serial.print("WiFi IP: ");
  Serial.println(wifiIpAdresi().isEmpty() ? "-" : wifiIpAdresi());
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
  Serial.println(wifiProvisioningAktifMi() ? "acik" : "kapali");
  Serial.print("Bluetooth adi: ");
  Serial.println(wifiProvisioningAktifMi() ? wifiBleDeviceName() : "-");
  Serial.print("WiFi LED GPIO: ");
  Serial.println(WIFI_STATUS_LED_PIN);
  wifiStatusLedDurumuYazdir();
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
  Serial.print("Role GPIO: ");
  Serial.println(ROLE_PIN);
  Serial.print("Yerel kapi kontrol: ");
  Serial.println(yerelKapiKontrolAktifMi() ? "aktif" : "pasif");
  Serial.print("Yerel kapi kontrol port: ");
  Serial.println(YEREL_KAPI_KONTROL_PORT);
  Serial.print("Firmware surumu: ");
  Serial.println(OTA_CURRENT_VERSION);
  Serial.print("OTA durum: ");
  Serial.println(otaLastStatus());
  Serial.print("OTA son hedef surum: ");
  Serial.println(otaLastVersion().isEmpty() ? "-" : otaLastVersion());
  rolePinDurumuYazdir("Role pin okuma");
  Serial.println("Seri role test: h=HIGH, l=LOW, r=pulse, p=pin bulma");
  Serial.println("Seri WiFi LED test: w=5sn ON, q=5sn OFF");
  Serial.println("------------------------");
}

void setup() {
  Serial.begin(115200);
  delay(300);

  esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
  esp_task_wdt_add(NULL);

  offlineLogInit();
  roleSetup();
  wifiBaglan();
  otaSetup();
  mqttSetup();
}

void loop() {
  esp_task_wdt_reset();
  seriKomutKontrol();
  wifiLoop();
  yerelKapiKontrolLoop();
  mqttLoopHandler();
  otaCheckAndUpdate();
  offlineLogSenkronizeEt();
  offlineLogHaftalikTemizle();
  if (roleLoop()) {
    mqttNotifyPulseCompleted();
  }

  if (millis() - sonDurumYazdirmaMs >= STATUS_PRINT_INTERVAL_MS) {
    sonDurumYazdirmaMs = millis();
    seriDurumYazdir();
  }
}
