#ifndef GM60_SCANNER_H
#define GM60_SCANNER_H

#include <Arduino.h>
#include "device_konfig.h"
#include "role_kontrol.h"
#include "display_uart.h"
#include "display_protocol.h"
#include "offline_log.h"

#if defined(BOARD_ESP32_WROOM_RELAY)
static HardwareSerial GM60Serial(2);
#else
static HardwareSerial GM60Serial(1);
#endif

bool mqttPublishQrVerify(const String& qrToken, uint32_t requestId);
bool mqttBagliMi();

// Okuyucu tamponu: bu uzunlugu asan giris KIRPILMAZ, tamamen reddedilir (kesik token dogrulamaya gitmesin)
constexpr size_t GM60_MAX_QR_UZUNLUK = 512;

inline String gm60Buffer = "";
inline bool gm60TamponTasti = false;
inline unsigned long gm60SonOkumaMs = 0;
inline unsigned long gm60SonKarakterMs = 0;
inline bool gm60Aktif = false;
inline bool gm60Bagli = false;

// Coklu tetikleme onleme
// Son basariyla gonderilen QR token ve zamani (8s boyunca ayni token tekrar islenmez). Eskiden 30 sn idi: cok kullanimli misafir QR'i
// ikinci kisi icin 30 sn calismiyordu. Sunucu reddi / hata / zaman asimi sonrasi token ayrica unutulur (gm60AyniQrYenidenDenensin).
inline String gm60SonGonderilenToken = "";
inline unsigned long gm60SonGonderilenMs = 0;
constexpr unsigned long GM60_TOKEN_TEKRAR_SURESI_MS = 8000UL; // 8 saniye

// "Ayni token atlaniyor" dalinda kullaniciya geri bildirim: kabulden hemen sonraki tekrar okumalarda (kapi acik ekrani) ekran
// TITRETILMEZ; bu sureden sonra (ve role aktif degilken) her kabul icin en fazla BIR KEZ mevcut CMD_QR_READING gonderilir.
inline bool gm60AtlamaGeriBildirimYapildi = false;
constexpr unsigned long GM60_ATLAMA_GERI_BILDIRIM_MIN_MS = 3500UL;

// Sunucu yanitini bekleme bayragi
// qr_verify gonderildikten sonra qr_result gelene veya 10s gecene kadar yeni okuma bloke edilir
inline bool gm60SunucuYanitBekleniyor = false;
inline unsigned long gm60SunucuYanitBaslangicMs = 0;
constexpr unsigned long GM60_SUNUCU_YANITLAMA_TIMEOUT_MS = 10000UL; // 10 saniye

// C7: qr_verify istek kimligi (artan sayi; her acilista rastgele tabandan baslar) ve bekleyen istek
inline uint32_t gm60IstekSayac = 0;
inline uint32_t gm60BekleyenIstekId = 0;

// Sunucu reddi / hata / zaman asimi sonrasi: ayni QR hemen yeniden denenebilsin (mevcut 5 sn debounce yine gecerlidir).
// Basarili kabulden sonra CAGRILMAZ: tek kullanimlik token 8 sn icinde yeniden gonderilmez.
inline void gm60AyniQrYenidenDenensin() {
  gm60SonGonderilenToken = "";
  gm60AtlamaGeriBildirimYapildi = false;
}

// Sunucu yanitladi (qr_result geldi) - mqtt_baglanti.h icinden cagrilir.
// idVar=false: eski sunucu (request_id yok) -> bekleyen istek varsa kabul. idVar=true: bekleyen istekle ESLESMELI.
// false donerse sonuc gec/eski/eslesmeyen demektir ve yok sayilmalidir.
inline bool gm60SunucuYanitiKabulEt(bool idVar, uint32_t id) {
  if (!gm60SunucuYanitBekleniyor) {
    return false;
  }
  if (idVar && id != gm60BekleyenIstekId) {
    return false;
  }
  gm60SunucuYanitBekleniyor = false;
  return true;
}

inline bool gm60Probe(int rx, int tx, uint32_t baud) {
  GM60Serial.end();
  delay(15);
  GM60Serial.begin(baud, SERIAL_8N1, rx, tx);
  while (GM60Serial.available() > 0) {
    GM60Serial.read();
  }

  // Test 1: Trigger / Işık Açma Komutu (0x7E 0x00 0x08 0x01 0x00 0x02 0x01 0xAB 0xCD)
  const uint8_t CMD_LIGHT_ON[] = { 0x7E, 0x00, 0x08, 0x01, 0x00, 0x02, 0x01, 0xAB, 0xCD };
  GM60Serial.write(CMD_LIGHT_ON, sizeof(CMD_LIGHT_ON));
  GM60Serial.flush();

  unsigned long baslangic = millis();
  bool yanit = false;
  while (millis() - baslangic < 250) {
    if (GM60Serial.available() > 0) {
      yanit = true;
      break;
    }
    delay(10);
  }

  // Test 2: Query Baud Komutu
  if (!yanit) {
    const uint8_t CMD_QUERY[] = { 0x7E, 0x00, 0x07, 0x01, 0x00, 0x2A, 0x02, 0xD8, 0x0F };
    GM60Serial.write(CMD_QUERY, sizeof(CMD_QUERY));
    GM60Serial.flush();
    baslangic = millis();
    while (millis() - baslangic < 200) {
      if (GM60Serial.available() > 0) {
        yanit = true;
        break;
      }
      delay(10);
    }
  }

  if (yanit) {
    delay(200);
    // Işığı kapat
    const uint8_t CMD_LIGHT_OFF[] = { 0x7E, 0x00, 0x08, 0x01, 0x00, 0x02, 0x00, 0xAB, 0xCD };
    GM60Serial.write(CMD_LIGHT_OFF, sizeof(CMD_LIGHT_OFF));
    GM60Serial.flush();
    // Bip ver
    const uint8_t CMD_BEEP[] = { 0x7E, 0x00, 0x08, 0x01, 0x00, 0x31, 0x01, 0xAB, 0xCD };
    GM60Serial.write(CMD_BEEP, sizeof(CMD_BEEP));
    GM60Serial.flush();
    delay(50);
    while (GM60Serial.available() > 0) {
      GM60Serial.read();
    }
    return true;
  }

  return false;
}

inline bool gm60SelfTest(bool seriYazdir = false) {
  if (!gm60Aktif) {
    gm60Bagli = false;
    return false;
  }

  // 1. Seri tamponunu temizle
  while (GM60Serial.available() > 0) {
    GM60Serial.read();
  }

  // 2. GM60 Trigger / Işık Açma Komutu (0x7E 0x00 0x08 0x01 0x00 0x02 0x01 0xAB 0xCD)
  const uint8_t CMD_LIGHT_ON[] = { 0x7E, 0x00, 0x08, 0x01, 0x00, 0x02, 0x01, 0xAB, 0xCD };
  GM60Serial.write(CMD_LIGHT_ON, sizeof(CMD_LIGHT_ON));
  GM60Serial.flush();

  unsigned long baslangic = millis();
  bool yanit = false;
  while (millis() - baslangic < 250) {
    if (GM60Serial.available() > 0) {
      yanit = true;
      break;
    }
    delay(10);
  }

  // Işıkların görünmesi için bekle
  delay(250);

  // 3. GM60 Trigger / Işık Kapatma Komutu
  const uint8_t CMD_LIGHT_OFF[] = { 0x7E, 0x00, 0x08, 0x01, 0x00, 0x02, 0x00, 0xAB, 0xCD };
  GM60Serial.write(CMD_LIGHT_OFF, sizeof(CMD_LIGHT_OFF));
  GM60Serial.flush();

  // 4. GM60 Buzzer Bip Komutları (Farklı firmware varyantları için 0x31 ve 0x30)
  const uint8_t CMD_BEEP_1[] = { 0x7E, 0x00, 0x08, 0x01, 0x00, 0x31, 0x01, 0xAB, 0xCD };
  GM60Serial.write(CMD_BEEP_1, sizeof(CMD_BEEP_1));
  GM60Serial.flush();
  delay(30);

  while (GM60Serial.available() > 0) {
    GM60Serial.read();
  }

  gm60Bagli = yanit;
  if (seriYazdir) {
    Serial.print("[GM60 TEST] Kamera Durumu: ");
    Serial.println(gm60Bagli ? "BAGLI (Hazir)" : "BAGLI DEGIL (Yanit Yok)");
  }
  return gm60Bagli;
}

inline void gm60SelfTestManuel() {
  Serial.println("\n[MANUEL TEST] GM60 Kamera Isik / Bip / Haberlesme Testi baslatildi...");
  gm60SelfTest(true);
}

inline void gm60Setup() {
#if defined(BOARD_ESP32_WROOM_RELAY)
  GM60Serial.begin(GM60_BAUD_RATE, SERIAL_8N1, GM60_RX_PIN, GM60_TX_PIN);
  gm60Aktif = true;
  Serial.print("GM60 QR Okuyucu baslatildi (UART2 RX:");
  Serial.print(GM60_RX_PIN);
  Serial.print(", TX:");
  Serial.print(GM60_TX_PIN);
  Serial.println(")");
#elif defined(BOARD_ESP32_C3)
  if (GM60_RX_PIN >= 0 && GM60_TX_PIN >= 0) {
    GM60Serial.begin(GM60_BAUD_RATE, SERIAL_8N1, GM60_RX_PIN, GM60_TX_PIN);
    gm60Aktif = true;
    Serial.println("GM60 QR Okuyucu baslatildi (ESP32-C3 UART1)");
  }
#endif
}

inline void gm60QrVerisiniIsle(String qrData) {
  qrData.trim();
  // Gorunmeyen kontrol baytlarini (STX, ETX, paket basliklari) temizle
  while (qrData.length() > 0 && static_cast<uint8_t>(qrData[0]) < 0x20) {
    qrData.remove(0, 1);
  }
  while (qrData.length() > 0 && static_cast<uint8_t>(qrData[qrData.length() - 1]) < 0x20) {
    qrData.remove(qrData.length() - 1, 1);
  }

  if (qrData.length() == 0) {
    return;
  }

  // QR icerigi (token) guvenlik nedeniyle seriye yazdirilmaz; yalniz uzunluk.
  Serial.print("\n[GM60] QR okundu, uzunluk: ");
  Serial.println(qrData.length());

  // KORUMA 1: Sunucu yanitini bekleme bayragi kontrolu
  // Bir onceki qr_verify mesaji gonderildiyse ve sunucu henuz yanitlamadiysa
  // (veya 10s gecmediyse) yeni okumalar islenmez.
  if (gm60SunucuYanitBekleniyor) {
    const unsigned long gecenSure = millis() - gm60SunucuYanitBaslangicMs;
    if (gecenSure < GM60_SUNUCU_YANITLAMA_TIMEOUT_MS) {
      Serial.print("[GM60] Sunucu yaniti bekleniyor (");
      Serial.print(gecenSure);
      Serial.println("ms), yeni okuma atlaniyor.");
      return;
    }
    // Timeout doldu, bayragi temizle ve devam et (yanitsiz kalan istegin token'i unutulur: ayni QR yeniden denenebilir)
    Serial.println("[GM60] Sunucu yanit timeout doldu, tekrar deneniyor.");
    gm60SunucuYanitBekleniyor = false;
    gm60AyniQrYenidenDenensin();
  }

  // KORUMA 2: Debounce - son BASARILI yayindan sonraki 5 saniye icinde okuma tekrarini engelle
  if (gm60SonOkumaMs != 0 && millis() - gm60SonOkumaMs < 5000) {
    Serial.println("[GM60] Debounce suresi dolmadi, atlaniyor.");
    return;
  }

  // KORUMA 3: Ayni token 8 saniye icinde tekrar gonderilmez (ret/hata/zaman asimi sonrasi token unutuldugu icin bu dala girmez)
  if (qrData == gm60SonGonderilenToken &&
      (millis() - gm60SonGonderilenMs) < GM60_TOKEN_TEKRAR_SURESI_MS) {
    const unsigned long gecenMs = millis() - gm60SonGonderilenMs;
    Serial.print("[GM60] Ayni token ");
    Serial.print(gecenMs / 1000);
    Serial.println("s once gonderildi, tekrar atlaniyor.");
    // Geri bildirim (mevcut komut; yeni UART komutu YOK): kabulden hemen sonra sessiz (ekran titremesin), sonra kabul basina en fazla bir kez
    if (!gm60AtlamaGeriBildirimYapildi && gecenMs >= GM60_ATLAMA_GERI_BILDIRIM_MIN_MS && !roleAktif) {
      gm60AtlamaGeriBildirimYapildi = true;
      displayUartSend(CMD_QR_READING);
    }
    return;
  }

  // 1. MQTT sunucu baglantisi varsa:
  if (mqttBagliMi()) {
    Serial.println("[GM60] QR token sunucuya iletiliyor (MQTT qr_verify)...");
    displayUartSend(CMD_QR_READING);
    if (gm60IstekSayac == 0) {
      gm60IstekSayac = esp_random() & 0x00FFFFFF;
    }
    const uint32_t istekId = gm60IstekSayac + 1;
    const bool gonderildi = mqttPublishQrVerify(qrData, istekId);
    if (gonderildi) {
      Serial.println("[GM60] QR basariyla sunucuya gonderildi. Sunucu dogrulamasi bekleniyor.");
      // Debounce yalniz basarili yayinda ilerler; token'i kaydet ve sunucu yaniti bekleme bayragi sec
      gm60IstekSayac = istekId;
      gm60BekleyenIstekId = istekId;
      gm60SonOkumaMs = millis() == 0 ? 1 : millis();
      gm60SonGonderilenToken = qrData;
      gm60SonGonderilenMs = millis();
      gm60AtlamaGeriBildirimYapildi = false;
      gm60SunucuYanitBekleniyor = true;
      gm60SunucuYanitBaslangicMs = millis();
    } else {
      Serial.println("[GM60 HATA] QR sunucuya iletilemedi.");
      gm60AyniQrYenidenDenensin();  // yayin hatasi: ayni QR hemen yeniden denenebilsin
      displayUartSend(CMD_QR_DENIED);
    }
    return;
  }

  // 2. Eger MQTT sunucu baglantisi YOKSA (offline):
  // Guvenlik: Dinamik tokenler (QR:...) sunucu tarafinda dogrulanmak ZORUNDADIR.
  // Internet yokken kapi acilmaz ve guvenli sekilde kapali kalir.
  Serial.println("[GM60 UYARI] MQTT baglantisi yok! Dinamik QR offline modda acilamaz.");
  displayUartSend(CMD_QR_DENIED);
}

// Tampondaki okumayi isler; tampon tastiysa okumayi reddeder (KIRPMAZ).
inline void gm60TamponuIsle() {
  const String data = gm60Buffer;
  const bool tasti = gm60TamponTasti;
  gm60Buffer = "";
  gm60TamponTasti = false;
  if (tasti) {
    Serial.println("[GM60] QR cok uzun (tampon tasti), okuma reddedildi.");
    displayUartSend(CMD_QR_DENIED);
    return;
  }
  gm60QrVerisiniIsle(data);
}

inline void gm60Loop() {
  if (!gm60Aktif) {
    return;
  }

  // Sunucu yanit bayragi suresi doldu: bayragi temizle (ekran kendi zaman asimiyla ana ekrana doner); yanitsiz kalan token unutulur
  if (gm60SunucuYanitBekleniyor && millis() - gm60SunucuYanitBaslangicMs >= GM60_SUNUCU_YANITLAMA_TIMEOUT_MS) {
    gm60SunucuYanitBekleniyor = false;
    gm60AyniQrYenidenDenensin();
  }

  while (GM60Serial.available() > 0) {
    gm60Bagli = true;
    gm60SonKarakterMs = millis();
    const char c = static_cast<char>(GM60Serial.read());
    if (c == '\r' || c == '\n') {
      if (gm60Buffer.length() > 0 || gm60TamponTasti) {
        gm60TamponuIsle();
      }
    } else {
      if (gm60Buffer.length() < GM60_MAX_QR_UZUNLUK) {
        gm60Buffer += c;
      } else {
        gm60TamponTasti = true;  // sonraki karakterler atilir, okuma reddedilir
      }
    }
  }

  // Eger barkod sonlandirici (\r veya \n) gelmediyse bile, 50ms sessizlik olustugunda barkodu isle
  if ((gm60Buffer.length() > 0 || gm60TamponTasti) && (millis() - gm60SonKarakterMs > 50)) {
    gm60TamponuIsle();
  }
}

#endif
