#include "display_uart.h"
#include "display_protocol.h"
#include "device_konfig.h"
#include <Arduino.h>

#if defined(BOARD_ESP32_WROOM_RELAY)

#include "admin_pin.h"

// HardwareSerial(1) for communication with ESP32-C3 display controller on WROOM
static HardwareSerial displaySerial(1);

// Alinan satir siniri; tasma halinde sonraki '\n'e kadar her sey atilir (satir sonu yeniden senkronizasyonu)
constexpr size_t DISPLAY_LINE_MAX = 255;

// Seriye yazdirilirken gizli veri (PIN, QR token) maskelenir
static bool displayLogGizli(const String& s) {
  return s.startsWith("ADMIN_") || s.startsWith(CMD_SHOW_QR_PREFIX) || s.startsWith(CMD_QR_PREFIX);
}

// Periyodik (5 sn'de bir) giden durum/QR satirlari seriyi bogmasin
static bool displayLogPeriyodik(const String& s) {
  return s.startsWith("WIFI_") || s.startsWith("MQTT_") || s.startsWith(CMD_SHOW_QR_PREFIX);
}

static void displayLogYaz(const char* yon, const String& s) {
  if (displayLogPeriyodik(s)) {
    return;
  }
  Serial.print("[DISPLAY] ");
  Serial.print(yon);
  Serial.print(": ");
  if (displayLogGizli(s)) {
    const int ayirac = s.indexOf('|');
    Serial.print(ayirac > 0 ? s.substring(0, ayirac) : s);
    Serial.println("|***");
  } else {
    Serial.println(s);
  }
}

void displayUartSetup() {
  displaySerial.setRxBufferSize(512);
  displaySerial.begin(DISPLAY_UART_BAUD, SERIAL_8N1, DISPLAY_UART_RX_PIN, DISPLAY_UART_TX_PIN);
  Serial.print("[DISPLAY] UART1 initialized (RX=");
  Serial.print(DISPLAY_UART_RX_PIN);
  Serial.print(", TX=");
  Serial.print(DISPLAY_UART_TX_PIN);
  Serial.println(")");

  // Ekran kartina READY gonder. Ekran QR token'i RF acilana kadar uretilmez (esp_random gercek rastgele olsun);
  // loop icindeki senkronizasyon token'i uretince ekrana iletir.
  displayUartSend(CMD_MAIN_READY);
}

void displayUartSend(const char* cmd) {
  if (cmd == nullptr || strlen(cmd) == 0) return;
  displaySerial.print(cmd);
  displaySerial.print("\n");
  displayLogYaz("TX", String(cmd));
}

void displayUartSend(const String& cmd) {
  if (cmd.length() == 0) return;
  displaySerial.print(cmd);
  displaySerial.print("\n");
  displayLogYaz("TX", cmd);
}

// SSID gibi serbest metni protokol alanina guvenli hale getirir: '|' ve kontrol/ASCII-disi karakterler '?' olur.
static String displayAlanTemizle(const String& raw, size_t maxLen) {
  String out;
  out.reserve(maxLen);
  for (size_t i = 0; i < raw.length() && out.length() < maxLen; i += 1) {
    const uint8_t c = static_cast<uint8_t>(raw[i]);
    out += (c < 0x20 || c > 0x7E || c == '|') ? '?' : static_cast<char>(c);
  }
  return out;
}

static void displayAdminDurumuGonder() {
  uint32_t kalan = 0;
  const AdminPinSonuc durum = adminPinDurum(kalan);
  if (durum == ADMIN_PIN_TANIMSIZ) {
    displayUartSend(String(CMD_ADMIN_STATE_PREFIX) + "NOPIN");
  } else if (durum == ADMIN_PIN_KILITLI) {
    displayUartSend(String(CMD_ADMIN_STATE_PREFIX) + "LOCKED|" + String(kalan));
  } else {
    displayUartSend(String(CMD_ADMIN_STATE_PREFIX) + "READY");
  }
}

static void displayAdminRedGonder(AdminPinSonuc sonuc, uint32_t kalan) {
  String msg = String(CMD_ADMIN_DENIED_PREFIX);
  if (sonuc == ADMIN_PIN_TANIMSIZ) {
    msg += "NOPIN";
  } else if (sonuc == ADMIN_PIN_KILITLI) {
    msg += "LOCKED|" + String(kalan);
  } else {
    msg += "BAD|" + String(kalan);
  }
  displayUartSend(msg);
}

// ADMIN_AUTH|<pin> (menu girisi) ve ADMIN_OPEN|<pin> (kapi acma) ayni dogrulayiciyi ve hata sayacini paylasir.
static void displayAdminIstegiIsle(bool kapiAc, const String& pin) {
  uint32_t kalan = 0;
  const AdminPinSonuc sonuc = adminPinDogrula(pin, kalan);
  if (sonuc != ADMIN_PIN_OK) {
    if (sonuc == ADMIN_PIN_YANLIS) {
      systemMqttOlay("admin_pin_failed", "bad_pin");
    } else if (sonuc == ADMIN_PIN_KILITLI) {
      systemMqttOlay("admin_pin_locked", "locked");
    }
    displayAdminRedGonder(sonuc, kalan);
    return;
  }

  if (!kapiAc) {
    displayUartSend(CMD_ADMIN_OK);
    return;
  }

  if (systemAdminKapiAc()) {
    Serial.println("[DISPLAY] Yonetici PIN dogrulandi -> role tetiklendi");
    displayUartSend(CMD_DOOR_OPENED);
  } else {
    displayUartSend(String(CMD_ADMIN_DENIED_PREFIX) + "BUSY|0");
  }
}

// Helper to process a complete line (command) received from display controller
static void handleDisplayCommand(const String &rawCmd) {
  String cmd = rawCmd;
  cmd.trim();
  if (cmd.length() == 0) return;

  displayLogYaz("RX", cmd);

  if (cmd == CMD_DISP_READY || cmd == CMD_MAIN_READY || cmd == CMD_TOUCH_READY) {
    // Ekran (yeniden) basladi: durumlari ve guncel QR'i hemen gonder
    displayDurumuYenidenGonder();
    broadcastScreenQrToken(false);
  } else if (cmd == CMD_BTN_OPEN || cmd == CMD_DOOR_OPEN) {
    Serial.println("[DISPLAY] UYARI: Yetkisiz ekran kapi acma komutu guvenlik nedeniyle engellendi");
  } else if (cmd.startsWith(String(CMD_ADMIN_OPEN) + "|")) {
    displayAdminIstegiIsle(true, cmd.substring(strlen(CMD_ADMIN_OPEN) + 1));
  } else if (cmd.startsWith(String(CMD_ADMIN_AUTH) + "|")) {
    displayAdminIstegiIsle(false, cmd.substring(strlen(CMD_ADMIN_AUTH) + 1));
  } else if (cmd == CMD_ADMIN_OPEN || cmd == CMD_ADMIN_AUTH) {
    // PIN'siz yonetici istegi (eski ekran yazilimi): reddet
    Serial.println("[DISPLAY] UYARI: PIN'siz ADMIN komutu reddedildi (ekran yazilimi guncel olmali)");
    displayAdminRedGonder(ADMIN_PIN_YANLIS, 0);
  } else if (cmd == CMD_REQ_ADMIN) {
    displayAdminDurumuGonder();
  } else if (cmd == CMD_REQ_STATUS) {
    const unsigned long s = millis() / 1000;
    const unsigned long h = s / 3600;
    const unsigned long m = (s % 3600) / 60;
    const unsigned long sec = s % 60;
    char uptimeBuf[32];
    snprintf(uptimeBuf, sizeof(uptimeBuf), "%luh %lum %lus", h, m, sec);

    String statusMsg = String(CMD_SYS_STATUS_PREFIX);
    statusMsg += displayAlanTemizle(systemWifiSsid(), 32);
    statusMsg += "|";
    statusMsg += systemWifiReady() ? displayAlanTemizle(systemWifiIp(), 15) : String("-");
    statusMsg += "|";
    statusMsg += systemWifiReady() ? (String(systemWifiRssi()) + " dBm") : String("-");
    statusMsg += "|";
    statusMsg += systemMqttReady() ? "1" : "0";
    statusMsg += "|";
    statusMsg += String(uptimeBuf);
    statusMsg += "|";
    statusMsg += systemCameraConnected() ? "1" : "0";
    displayUartSend(statusMsg);
  } else if (cmd == CMD_REQ_INFO) {
    // Gercek UID, firmware surumu ve hedef (sabit/sahte deger YOK)
    String infoMsg = String(CMD_SYS_INFO_PREFIX);
    infoMsg += displayAlanTemizle(cihazUniqueId(), 16);
    infoMsg += "|";
    infoMsg += displayAlanTemizle(systemFirmwareVersion(), 16);
    infoMsg += "|";
    infoMsg += displayAlanTemizle(systemHardwareTarget(), 24);
    displayUartSend(infoMsg);
  } else if (cmd == CMD_BTN_SETTINGS) {
    Serial.println("[DISPLAY] Ayarlar butonu alindi");
    displayUartSend(CMD_SHOW_SETTINGS);
  } else if (cmd == CMD_BTN_HOME || cmd == CMD_BTN_BACK) {
    Serial.println("[DISPLAY] Ana ekrana donus butonu alindi");
    displayUartSend(CMD_SHOW_HOME);
  } else if (cmd.startsWith(CMD_QR_PREFIX)) {
    // QR verisi ekrandan gelirse yalnizca bildirilir (icerik yazdirilmaz, dogrulama yapilmaz)
    Serial.println("[DISPLAY] QR verisi alindi (yok sayildi)");
  } else {
    Serial.println("[DISPLAY] Bilinmeyen komut (yoksayildi)");
  }
}

void displayUartLoop() {
  static String lineBuffer;
  static bool satirAtla = false;  // tasma sonrasi: bir sonraki '\n'e kadar her seyi at

  while (displaySerial.available() > 0) {
    const char c = static_cast<char>(displaySerial.read());

    if (satirAtla) {
      if (c == '\n') {
        satirAtla = false;
        lineBuffer = "";
      }
      continue;
    }

    if (c == '\r' || c == '\n') {
      if (lineBuffer.length() > 0) {
        const String satir = lineBuffer;
        lineBuffer = "";
        handleDisplayCommand(satir);
      }
    } else if (static_cast<uint8_t>(c) < 0x20) {
      // Cerceveleme gurultusu (kontrol baytlari): yok say
    } else {
      if (lineBuffer.length() >= DISPLAY_LINE_MAX) {
        Serial.println("[DISPLAY] RX satiri cok uzun, sonraki satir sonuna kadar atlaniyor");
        lineBuffer = "";
        satirAtla = true;
      } else {
        lineBuffer += c;
      }
    }
  }
}

#else

// Sahadaki ESP32-C3 Super Mini cihazlarinda harici ekran yoktur (Kural 3).
// Bu nedenle fonksiyonlar C3 hedefleri icin guvenli no-op olarak calisir.
void displayUartSetup() {}
void displayUartLoop() {}
void displayUartSend(const char*) {}
void displayUartSend(const String&) {}

#endif
