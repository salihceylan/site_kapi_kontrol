#ifndef YEREL_KAPI_KONTROL_H
#define YEREL_KAPI_KONTROL_H

// Yerel ag kapi kontrolu - PROTOKOL v2 (LOCALCTRL_V2): UDP (port 8765) ile acma challenge'a bagli HMAC-SHA256 iledir; HTTP yalniz durum.
//  - Yetki YALNIZ sunucunun MQTT local_control_config ile gonderdigi token'dan turetilen imza iledir. Token ASLA aga cikmaz: istemci
//    cihazin yayinladigi tek kullanimlik `ch` (challenge) degerine bagli sig = HMAC-SHA256(token, "action|UID|ch") gonderir.
//    UID tek basina YETMEZ. Token bos ise (ya da acilis HMAC oz-testi basarisizsa) yerel kontrol KAPALI (fail-closed).
//  - v1 `token` alani KABUL EDILMEZ. HTTP POST /ahbu/open KALDIRILDI (404 route_bulunamadi); GET /ahbu/status sir icermez ve kalir.
//  - Dogrulama mantigi (ch/sig/yinelenen paket durum makinesi) Arduino'dan bagimsiz yerel_kontrol_cekirdek.h'tedir (ana makinede test edilir).
//  - Token, MQTT parolasindan AYRI saklanir (wifi_baglanti.h).
//  - Kaynak adres yalniz ozel/yerel aglardan (RFC1918, link-local) veya ayni alt agdan kabul edilir.
//  - Seriye token / sig / ch YAZILMAZ (yalniz kabul/red ve nedeni).

#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <WiFi.h>
#include <WiFiUdp.h>

#include "device_konfig.h"
#include "display_protocol.h"
#include "display_uart.h"
#include "mqtt_baglanti.h"
#include "offline_log.h"
#include "ota_guncelleme.h"
#include "role_kontrol.h"
#include "wifi_baglanti.h"
#include "yerel_kontrol_cekirdek.h"

inline constexpr size_t YEREL_HTTP_MAX_BAYT = 512;            // istek (satir+baslik) toplam siniri
inline constexpr unsigned long YEREL_HTTP_MAX_SURE_MS = 300;  // istegin tamami en fazla bu surede okunur

inline WiFiServer gYerelKapiServer(YEREL_KAPI_KONTROL_PORT, 1);  // tek bagli istemci
inline WiFiUDP gYerelUdp;
inline bool gYerelKapiServerAktif = false;
inline bool gYerelUdpAktif = false;

// v2 durumu: challenge (guncel + onceki) ve son-kabul kaydi (yinelenen paket penceresi). Mantik yerel_kontrol_cekirdek.h'tedir.
inline YerelDurum gYerelDurum = {};
// HMAC bilinen-cevap oz-testi (KAT) gecene kadar KAPALI (fail-closed); yerelKapiKontrolLoop ilk turunda, yerel kontrol baslamadan calisir.
inline bool gYerelHmacSaglam = false;
inline bool gYerelOzTestYapildi = false;
inline bool gYerelOzTestOlayBekliyor = false;  // oz-test basarisiz: MQTT olayi baglaninca yayinlanir

struct YerelHttpIstek {
  String method;
  String path;
  String deviceUid;
};

enum YerelOkuSonuc : uint8_t {
  YEREL_OKU_TAMAM = 0,
  YEREL_OKU_GECERSIZ,
  YEREL_OKU_BUYUK,
  YEREL_OKU_ZAMAN_ASIMI,
};

// Yerel kontrol kullanilabilir mi? Token VAR ve HMAC oz-testi gecti. (local_control_available: discover / status / unauthorized yanitlari)
inline bool yerelKontrolKullanilabilirMi() {
  return gYerelHmacSaglam && wifiHasLocalControlToken();
}

// Acilis HMAC bilinen-cevap testi: sartnamedeki vektor (token/UID/ch -> open ve pulse imzasi) uretimle AYNI HMAC koduyla hesaplanir.
// Uyusmazsa yerel acma KAPALI kalir (gYerelHmacSaglam=false); MQTT olayi (local_control_selftest_failed) baglaninca yayinlanir.
inline void yerelHmacOzTesti() {
  gYerelOzTestYapildi = true;
  gYerelHmacSaglam = yerelKatCalistir();
  if (gYerelHmacSaglam) {
    Serial.println("Yerel kontrol: HMAC oz-testi basarili.");
  } else {
    Serial.println("UYARI: Yerel kontrol HMAC oz-testi BASARISIZ; yerel kapi acma KAPALI (fail-closed).");
    gYerelOzTestOlayBekliyor = true;
  }
}

// Reddedilen / yinelenen paket satirlari seriyi bogmasin: en fazla 1 sn'de bir (ISARETSIZ fark; sir YAZILMAZ).
inline unsigned long gYerelSonLogMs = 0;
inline bool gYerelSonLogVar = false;
inline void yerelSinirliLog(const char* satir) {
  const unsigned long simdi = millis();
  if (gYerelSonLogVar && simdi - gYerelSonLogMs < 1000UL) {
    return;
  }
  gYerelSonLogVar = true;
  gYerelSonLogMs = simdi;
  Serial.println(satir);
}

inline void yerelHttpCevap(WiFiClient& client, int code, const char* status, const String& body) {
  String cevap = "HTTP/1.1 ";
  cevap += String(code);
  cevap += " ";
  cevap += status;
  cevap += "\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: ";
  cevap += String(body.length());
  cevap += "\r\n\r\n";
  cevap += body;
  client.write(reinterpret_cast<const uint8_t*>(cevap.c_str()), cevap.length());
}

// JSON dize kacisi (cift tirnak, ters bolu ve tum kontrol karakterleri)
inline String yerelJsonEscape(const String& raw) {
  String escaped;
  escaped.reserve(raw.length() + 4);
  for (size_t i = 0; i < raw.length(); i += 1) {
    const char c = raw.charAt(i);
    if (c == '"' || c == '\\') {
      escaped += '\\';
      escaped += c;
    } else if (static_cast<uint8_t>(c) < 0x20) {
      char kod[7];
      snprintf(kod, sizeof(kod), "\\u%04x", static_cast<unsigned>(static_cast<uint8_t>(c)));
      escaped += kod;
    } else {
      escaped += c;
    }
  }
  return escaped;
}

// Kaynak adres yerel mi? (RFC1918, link-local veya cihazla ayni alt ag)
inline bool yerelAdresIzinli(const IPAddress& ip) {
  const uint8_t a = ip[0];
  const uint8_t b = ip[1];
  if (a == 10) {
    return true;
  }
  if (a == 172 && b >= 16 && b <= 31) {
    return true;
  }
  if (a == 192 && b == 168) {
    return true;
  }
  if (a == 169 && b == 254) {
    return true;
  }
  const uint32_t kaynak = static_cast<uint32_t>(ip);
  const uint32_t benim = static_cast<uint32_t>(WiFi.localIP());
  const uint32_t maske = static_cast<uint32_t>(WiFi.subnetMask());
  return maske != 0 && (kaynak & maske) == (benim & maske);
}

// HTTP istegini sinirli okur: en fazla YEREL_HTTP_MAX_BAYT bayt, en fazla YEREL_HTTP_MAX_SURE_MS ms.
// v2: yalniz GET /ahbu/status kalmistir; token/kullanici basliklari ARTIK okunmaz (yalniz X-AHBU-Device-UID).
inline YerelOkuSonuc yerelHttpIstekOku(WiFiClient& client, YerelHttpIstek& request) {
  char tampon[YEREL_HTTP_MAX_BAYT + 1];
  size_t n = 0;
  bool basliklarBitti = false;
  const unsigned long baslangic = millis();

  while ((client.connected() || client.available()) && millis() - baslangic < YEREL_HTTP_MAX_SURE_MS) {
    while (client.available() && n < YEREL_HTTP_MAX_BAYT) {
      const int c = client.read();
      if (c < 0) {
        break;
      }
      tampon[n++] = static_cast<char>(c);
      if (n >= 4 && memcmp(tampon + n - 4, "\r\n\r\n", 4) == 0) {
        basliklarBitti = true;
        break;
      }
      if (n >= 2 && tampon[n - 1] == '\n' && tampon[n - 2] == '\n') {
        basliklarBitti = true;
        break;
      }
    }
    if (basliklarBitti) {
      break;
    }
    if (n >= YEREL_HTTP_MAX_BAYT) {
      return YEREL_OKU_BUYUK;
    }
    yield();
    delay(1);
  }
  if (!basliklarBitti) {
    return n >= YEREL_HTTP_MAX_BAYT ? YEREL_OKU_BUYUK : YEREL_OKU_ZAMAN_ASIMI;
  }
  tampon[n] = '\0';

  // Ilk satir: METHOD PATH HTTP/x
  char* satirSonu = strchr(tampon, '\n');
  if (satirSonu == nullptr) {
    return YEREL_OKU_GECERSIZ;
  }
  *satirSonu = '\0';
  char* sonrakiSatir = satirSonu + 1;
  String ilk(tampon);
  ilk.trim();
  const int ilkBosluk = ilk.indexOf(' ');
  const int ikinciBosluk = ilk.indexOf(' ', ilkBosluk + 1);
  if (ilkBosluk <= 0 || ikinciBosluk <= ilkBosluk || ilkBosluk > 8 || ikinciBosluk - ilkBosluk > 80) {
    return YEREL_OKU_GECERSIZ;
  }
  request.method = ilk.substring(0, ilkBosluk);
  request.path = ilk.substring(ilkBosluk + 1, ikinciBosluk);

  // Basliklar (en fazla 16 satir)
  int baslikSayisi = 0;
  char* imlec = sonrakiSatir;
  while (*imlec != '\0' && baslikSayisi < 16) {
    char* bitis = strchr(imlec, '\n');
    if (bitis != nullptr) {
      *bitis = '\0';
    }
    String satir(imlec);
    satir.trim();
    imlec = (bitis != nullptr) ? bitis + 1 : imlec + strlen(imlec);
    baslikSayisi += 1;
    if (satir.isEmpty()) {
      break;
    }

    const int ayirac = satir.indexOf(':');
    if (ayirac <= 0) {
      continue;
    }
    String ad = satir.substring(0, ayirac);
    String deger = satir.substring(ayirac + 1);
    ad.trim();
    deger.trim();
    ad.toLowerCase();

    if (ad == "x-ahbu-device-uid") {
      request.deviceUid = deger.substring(0, 32);
    }
  }

  return YEREL_OKU_TAMAM;
}

// Cihaz UID'si eslesiyor mu (belirtilmisse)? Esitlik buyuk/kucuk harf duyarsiz.
inline bool yerelUidEslesiyor(const String& gelenUid) {
  if (gelenUid.isEmpty()) {
    return true;
  }
  String u = gelenUid;
  u.trim();
  u.toUpperCase();
  return u == cihazUniqueId();
}

inline void yerelStatusHandler(WiFiClient& client, const YerelHttpIstek& request) {
  if (!yerelUidEslesiyor(request.deviceUid)) {
    yerelHttpCevap(client, 404, "Not Found", R"({"ok":false,"error":"cihaz_uid_eslesmedi"})");
    return;
  }

  JsonDocument doc;
  doc["ok"] = true;
  doc["device_uid"] = cihazUniqueId();
  doc["firmware_version"] = OTA_CURRENT_VERSION;
  doc["wifi_connected"] = wifiHazirMi();
  doc["ip"] = wifiIpAdresi();
  doc["local_control_port"] = YEREL_KAPI_KONTROL_PORT;
  doc["local_control_available"] = yerelKontrolKullanilabilirMi();
  doc["door_locked"] = gDoorLocked;
  String body;
  serializeJson(doc, body);
  yerelHttpCevap(client, 200, "OK", body);
}

// Role tetiklendikten sonra yan etkiler (YALNIZ roleTetikle() true ise cagrilir)
inline void yerelKapiAcildiYanEtkileri(const char* olay, const char* offlineTur, const String& kullanici, const String& daire) {
  gDoorLocked = false;
  displayUartSend(CMD_DOOR_OPENED);
  mqttPublishEvent(olay, "");
  mqttPublishState(gDoorLocked);
  offlineLogKaydet(offlineTur, kullanici.isEmpty() ? "Yerel Kullanici" : kullanici.c_str(), daire.c_str());
}

inline void yerelKapiKontrolBaslat() {
  if (gYerelKapiServerAktif || !wifiHazirMi()) {
    return;
  }

  gYerelKapiServer.begin();
  gYerelKapiServer.setNoDelay(true);
  gYerelKapiServerAktif = true;

  if (!gYerelUdpAktif) {
    gYerelUdp.begin(YEREL_KAPI_KONTROL_PORT);
    gYerelUdpAktif = true;
    // Wi-Fi hazir (RF acik): esp_random gercek rastgele. Her (yeniden) baslangicta challenge taze uretilir, son-kabul kaydi silinir.
    yerelChBaslat(gYerelDurum, millis(), esp_random);
    gYerelDurum.sonKabulVar = false;
  }

  String mdnsHost = "ahbu-" + cihazUniqueId();
  mdnsHost.toLowerCase();
  if (MDNS.begin(mdnsHost.c_str())) {
    MDNS.addService("ahbu", "tcp", YEREL_KAPI_KONTROL_PORT);
    Serial.print("mDNS aktif: http://");
    Serial.print(mdnsHost);
    Serial.print(".local:");
    Serial.println(YEREL_KAPI_KONTROL_PORT);
  }

  Serial.print("Yerel kapi kontrol aktif: http://");
  Serial.print(wifiIpAdresi());
  Serial.print(":");
  Serial.print(YEREL_KAPI_KONTROL_PORT);
  Serial.println("/ahbu/status");
}

inline void yerelKapiKontrolDurdur() {
  if (gYerelUdpAktif) {
    gYerelUdp.stop();
    gYerelUdpAktif = false;
  }

  if (!gYerelKapiServerAktif) {
    return;
  }

  MDNS.end();
  gYerelKapiServer.stop();
  gYerelKapiServerAktif = false;
  Serial.println("Yerel kapi kontrol durduruldu.");
}

// UDP yaniti (kaynak adrese); nonce varsa eslestirme icin aynen geri yansitilir.
inline void yerelUdpYanit(JsonDocument& cevap, const String& nonce) {
  if (!nonce.isEmpty()) {
    cevap["nonce"] = nonce;
  }
  String govde;
  serializeJson(cevap, govde);
  gYerelUdp.beginPacket(gYerelUdp.remoteIP(), gYerelUdp.remotePort());
  gYerelUdp.print(govde);
  gYerelUdp.endPacket();
}

// Periyodik UDP BROADCAST beacon (uygulamanin yerel yol onbellegi bununla dolar):
// {"device_uid":"<UID>","ip":"<yerel_ip>","port":8765,"rssi":<dBm>,"hw":"c3|wroom","ch":"<16 hex>"}  ~5 sn'de bir, yalniz Wi-Fi bagliyken.
// `ch` = guncel challenge (v2): uygulama bunu onbellege alip acma imzasini ona baglar (12 sn'den eskiyse yeniden ister).
// Kaynak portu 8765'tir (UDP sunucu soketi). Uygulama IP'yi JSON'dan degil paketin kaynak adresinden alir.
inline constexpr unsigned long YEREL_BEACON_ARALIK_MS = 5000;
inline unsigned long gYerelSonBeaconMs = 0;

inline void yerelBeaconYayinla() {
  if (!gYerelUdpAktif || !wifiHazirMi()) {
    return;
  }
  const unsigned long simdi = millis();
  if (gYerelSonBeaconMs != 0 && simdi - gYerelSonBeaconMs < YEREL_BEACON_ARALIK_MS) {
    return;
  }
  gYerelSonBeaconMs = simdi == 0 ? 1 : simdi;

  yerelChZamanlayici(gYerelDurum, static_cast<uint32_t>(simdi), esp_random);
  JsonDocument doc;
  doc["device_uid"] = cihazUniqueId();
  doc["ip"] = wifiIpAdresi();
  doc["port"] = YEREL_KAPI_KONTROL_PORT;
  doc["rssi"] = wifiSinyalDbm();
#if defined(BOARD_ESP32_WROOM_RELAY)
  doc["hw"] = "wroom";
#else
  doc["hw"] = "c3";
#endif
  doc["ch"] = gYerelDurum.ch;
  String govde;
  serializeJson(doc, govde);

  // Hem alt ag yayini hem sinirli yayin (bazi AP'ler birini filtreler)
  const IPAddress hedefler[2] = {WiFi.broadcastIP(), IPAddress(255, 255, 255, 255)};
  for (int i = 0; i < 2; i += 1) {
    if (hedefler[i] == IPAddress(0, 0, 0, 0)) {
      continue;
    }
    if (gYerelUdp.beginPacket(hedefler[i], YEREL_KAPI_KONTROL_PORT)) {
      gYerelUdp.print(govde);
      gYerelUdp.endPacket();
    }
  }
}

inline bool yerelRoleKopru() {
  return roleTetikle();
}

// open / pulse istegi (v2). Karar mantigi yerelAcmaDegerlendir'dedir (challenge + HMAC + yinelenen paket + role); burada yalniz JSON ayristirma,
// yanit ve yan etkiler vardir. Hedef UID eslesmesi ve kaynak adres kontrolu cagirandadir.
inline void yerelUdpAcmaIsle(JsonDocument& doc, const String& action, const String& benimUid, const String& nonce) {
  // v1 paketi (acik metin `token`, imza yok): ARTIK kabul edilmez; NET red yaniti (istemci zaman asimina dusmesin)
  if (!doc["token"].isNull() && !doc["sig"].is<const char*>()) {
    yerelSinirliLog("UDP Kapi Acma REDDEDILDI: eski (v1) token paketi artik kabul edilmiyor.");
    JsonDocument cevap;
    cevap["ok"] = false;
    cevap["error"] = "unauthorized";
    cevap["device_uid"] = benimUid;
    cevap["local_control_available"] = yerelKontrolKullanilabilirMi();
    yerelUdpYanit(cevap, nonce);
    return;
  }

  const char* ch = doc["ch"] | "";
  const char* sig = doc["sig"] | "";
  const String token = wifiLocalControlToken();
  const YerelSonuc sonuc = yerelAcmaDegerlendir(gYerelDurum, token.c_str(), gYerelHmacSaglam, benimUid.c_str(), action.c_str(), ch, sig,
                                                static_cast<uint32_t>(millis()), yerelRoleKopru, esp_random);

  JsonDocument cevap;
  switch (sonuc) {
    case YEREL_SONUC_KABUL:
      // Once yanit (gecikme dusuk kalsin), sonra log/MQTT/ekran yan etkileri
      cevap["ok"] = true;
      cevap["message"] = "yerel_kapi_acma_komutu_alindi";
      cevap["device_uid"] = benimUid;
      yerelUdpYanit(cevap, nonce);
      yerelKapiAcildiYanEtkileri("local_udp_pulse_started", "local_udp", String("Yerel UDP"), String(""));
      Serial.println("Yerel UDP: KAPI ACILDI (role tetiklendi).");
      return;
    case YEREL_SONUC_YINELENEN:
      // Ayni ch+sig son 3 sn'de kabul edilmisti (istemci paketi UDP kaybina karsi iki kez yollar): role/log/olay TEKRARLANMAZ
      yerelSinirliLog("Yerel UDP: yinelenen acma paketi (role tekrar tetiklenmedi).");
      cevap["ok"] = true;
      cevap["duplicate"] = true;
      cevap["device_uid"] = benimUid;
      yerelUdpYanit(cevap, nonce);
      return;
    case YEREL_SONUC_CHALLENGE:
      // Normal akis (istemci onbellegi bayat): guncel ch ile tek kez yeniden dener
      cevap["ok"] = false;
      cevap["error"] = "challenge";
      cevap["ch"] = gYerelDurum.ch;
      cevap["device_uid"] = benimUid;
      yerelUdpYanit(cevap, nonce);
      return;
    case YEREL_SONUC_ROLE_MESGUL:
      cevap["ok"] = false;
      cevap["error"] = "role_mesgul";
      cevap["device_uid"] = benimUid;
      yerelUdpYanit(cevap, nonce);
      return;
    case YEREL_SONUC_YETKISIZ:
    case YEREL_SONUC_TOKEN_YOK:
    default:
      yerelSinirliLog(sonuc == YEREL_SONUC_YETKISIZ ? "UDP Kapi Acma REDDEDILDI: imza gecersiz."
                                                    : "UDP Kapi Acma REDDEDILDI: yerel kontrol kapali (anahtar yok / oz-test).");
      cevap["ok"] = false;
      cevap["error"] = "unauthorized";
      cevap["device_uid"] = benimUid;
      cevap["local_control_available"] = yerelKontrolKullanilabilirMi();
      yerelUdpYanit(cevap, nonce);
      return;
  }
}

inline void yerelUdpIsle() {
  const int paketBoyutu = gYerelUdp.parsePacket();
  if (paketBoyutu <= 0) {
    return;
  }

  char paket[512];
  if (paketBoyutu >= static_cast<int>(sizeof(paket))) {
    gYerelUdp.flush();  // cok buyuk paket: yok say
    return;
  }
  const int len = gYerelUdp.read(paket, sizeof(paket) - 1);
  if (len <= 0) {
    return;
  }
  paket[len] = '\0';

  // Yalniz yerel/ozel ag kaynaklari (portu internetten yonlendirilmis olsa bile dis adresler reddedilir)
  if (!yerelAdresIzinli(gYerelUdp.remoteIP())) {
    return;
  }

  JsonDocument doc;
  if (deserializeJson(doc, paket, static_cast<size_t>(len)) || !doc.is<JsonObject>()) {
    return;
  }

  const String action = String(doc["action"] | "");
  String hedefUid = String(doc["target_uid"] | (doc["device_uid"] | ""));
  hedefUid.trim();
  hedefUid.toUpperCase();
  const String benimUid = cihazUniqueId();
  String nonce = String(doc["nonce"] | "");
  if (nonce.length() > 32) {
    nonce = "";
  }

  if (action == "discover") {
    // Yalnizca hedef UID bu cihazla eslesiyorsa veya genel arama (*/bos) ise yanit ver
    if (hedefUid.isEmpty() || hedefUid == benimUid || hedefUid == "*") {
      yerelChZamanlayici(gYerelDurum, static_cast<uint32_t>(millis()), esp_random);
      JsonDocument cevap;
      cevap["ok"] = true;
      cevap["device_uid"] = benimUid;
      cevap["ip"] = wifiIpAdresi();
      cevap["port"] = YEREL_KAPI_KONTROL_PORT;
      cevap["ch"] = gYerelDurum.ch;
      cevap["local_control_available"] = yerelKontrolKullanilabilirMi();
      yerelUdpYanit(cevap, nonce);
    }
    return;
  }

  if (action == "open" || action == "pulse") {
    // Hedef UID belirtilmisse MUTLAKA bu cihazla eslesmelidir
    if (!hedefUid.isEmpty() && hedefUid != benimUid) {
      yerelSinirliLog("UDP Kapi Acma REDDEDILDI: hedef UID bu cihazla eslesmiyor.");
      return;
    }
    yerelUdpAcmaIsle(doc, action, benimUid, nonce);
  }
}

inline void yerelKapiKontrolLoop() {
  // Acilis HMAC oz-testi: yerel kontrol baslamadan ONCE (ilk turda) bir kez; basarisizsa olay MQTT baglaninca yayinlanir.
  if (!gYerelOzTestYapildi) {
    yerelHmacOzTesti();
  }
  if (gYerelOzTestOlayBekliyor && mqttBagliMi()) {
    if (mqttPublishEvent("local_control_selftest_failed", "hmac_kat")) {
      gYerelOzTestOlayBekliyor = false;
    }
  }

  if (!wifiHazirMi()) {
    yerelKapiKontrolDurdur();
    return;
  }

  yerelKapiKontrolBaslat();

  // 1. UDP Kesif & Hizli Komut Yanitlayici + challenge dondurme (10 sn) + periyodik beacon
  if (gYerelUdpAktif) {
    yerelChZamanlayici(gYerelDurum, static_cast<uint32_t>(millis()), esp_random);
    yerelUdpIsle();
    yerelBeaconYayinla();
  }

  // 2. HTTP TCP Sunucu (yalniz GET /ahbu/status; acma YOK)
  WiFiClient istemci = gYerelKapiServer.available();
  if (!istemci) {
    return;
  }

  if (!yerelAdresIzinli(istemci.remoteIP())) {
    istemci.stop();
    return;
  }

  YerelHttpIstek request;
  const YerelOkuSonuc okuma = yerelHttpIstekOku(istemci, request);
  if (okuma == YEREL_OKU_BUYUK) {
    yerelHttpCevap(istemci, 431, "Request Header Fields Too Large", R"({"ok":false,"error":"istek_cok_buyuk"})");
    istemci.stop();
    return;
  }
  if (okuma != YEREL_OKU_TAMAM) {
    yerelHttpCevap(istemci, 400, "Bad Request", R"({"ok":false,"error":"gecersiz_istek"})");
    istemci.stop();
    return;
  }

  if (request.method == "GET" && request.path == "/ahbu/status") {
    yerelStatusHandler(istemci, request);
  } else {
    // POST /ahbu/open v2'de KALDIRILDI (token acik metin tasirdi): 404
    yerelHttpCevap(istemci, 404, "Not Found", R"({"ok":false,"error":"route_bulunamadi"})");
  }
  delay(1);
  istemci.stop();
}

inline bool yerelKapiKontrolAktifMi() {
  return gYerelKapiServerAktif;
}

#endif
