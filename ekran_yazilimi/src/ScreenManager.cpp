#include "ScreenManager.h"
#include "display_protocol.h"
#include "config.h"
#include <qrcode.h>

ScreenManager::ScreenManager()
  : _currentState(STATE_HOME),
    _stateEnteredMs(0),
    _autoReturnTimeoutMs(0),
    _wifiConnected(false),
    _mqttConnected(false),
    _qrData("SITE-KAPI-KONTROL"),
    _lastQrCode(""),
    _sendCb(nullptr) {
}

void ScreenManager::begin() {
  tft.init();
  tft.setRotation(0); // Portrait 240x320
  tft.fillScreen(TFT_BLACK);
  showHomeScreen();
}

void ScreenManager::update() {
  // Non-blocking state timeout handler
  if (_autoReturnTimeoutMs > 0 && (millis() - _stateEnteredMs >= _autoReturnTimeoutMs)) {
    _autoReturnTimeoutMs = 0;
    showHomeScreen();
  }
}

void ScreenManager::sendCommand(const char* cmd) {
  if (_sendCb != nullptr && cmd != nullptr) {
    _sendCb(cmd);
  }
}

void ScreenManager::setWifiStatus(bool connected) {
  if (_wifiConnected != connected) {
    _wifiConnected = connected;
    if (_currentState == STATE_HOME) {
      drawTopBar();
    }
  }
}

void ScreenManager::setMqttStatus(bool connected) {
  if (_mqttConnected != connected) {
    _mqttConnected = connected;
    if (_currentState == STATE_HOME) {
      drawTopBar();
    }
  }
}

void ScreenManager::drawTopBar() {
  tft.fillRect(0, 0, 240, 26, TFT_NAVY);

  // WiFi Indicator
  uint16_t wifiCol = _wifiConnected ? TFT_GREEN : TFT_RED;
  tft.fillCircle(10, 13, 4, wifiCol);
  tft.setTextColor(TFT_WHITE, TFT_NAVY);
  tft.setTextSize(1);
  tft.setCursor(18, 9);
  tft.print(_wifiConnected ? "WiFi OK" : "WiFi YOK");

  // MQTT Indicator
  uint16_t mqttCol = _mqttConnected ? TFT_GREEN : TFT_RED;
  tft.fillCircle(140, 13, 4, mqttCol);
  tft.setCursor(148, 9);
  tft.print(_mqttConnected ? "Bulut OK" : "Bulut YOK");

  tft.drawFastHLine(0, 26, 240, TFT_DARKGREY);
}

void ScreenManager::showHomeScreen() {
  _currentState = STATE_HOME;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 0;
  drawHomeScreen();
}

void ScreenManager::drawHomeScreen() {
  tft.fillScreen(TFT_BLACK);
  drawTopBar();

  // QR Code Area
  tft.setTextColor(TFT_LIGHTGREY, TFT_BLACK);
  tft.setTextSize(1);
  tft.setCursor(55, 34);
  tft.print("Giris Icin QR Okutunuz");

  // Draw QR code centered
  drawQRCode(_qrData, 45, 50, 150);

  // "KAPIYI AC" Button (X: 20, Y: 215, W: 200, H: 45)
  tft.fillRoundRect(20, 215, 200, 45, 8, TFT_DARKGREEN);
  tft.drawRoundRect(20, 215, 200, 45, 8, TFT_GREEN);
  tft.setTextColor(TFT_WHITE, TFT_DARKGREEN);
  tft.setTextSize(2);
  tft.setCursor(50, 228);
  tft.print("KAPIYI AC");

  // "AYARLAR" Button (X: 20, Y: 268, W: 200, H: 38)
  tft.fillRoundRect(20, 268, 200, 38, 6, TFT_DARKGREY);
  tft.drawRoundRect(20, 268, 200, 38, 6, TFT_LIGHTGREY);
  tft.setTextColor(TFT_WHITE, TFT_DARKGREY);
  tft.setTextSize(1);
  tft.setCursor(95, 282);
  tft.print("AYARLAR");
}

void ScreenManager::showDoorOpened() {
  _currentState = STATE_DOOR_OPENED;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 4000; // Return home after 4 seconds
  drawDoorOpenedScreen();
}

void ScreenManager::drawDoorOpenedScreen() {
  tft.fillScreen(TFT_BLACK);

  // Large Green Banner
  tft.fillRoundRect(15, 60, 210, 180, 12, TFT_DARKGREEN);
  tft.drawRoundRect(15, 60, 210, 180, 12, TFT_GREEN);

  tft.setTextColor(TFT_WHITE, TFT_DARKGREEN);
  tft.setTextSize(3);
  tft.setCursor(30, 95);
  tft.print("KAPI");
  tft.setCursor(30, 130);
  tft.print("ACILDI");

  tft.setTextSize(1);
  tft.setTextColor(TFT_YELLOW, TFT_DARKGREEN);
  tft.setCursor(45, 190);
  tft.print("Lutfen geciniz...");

  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  tft.setCursor(50, 280);
  tft.print("Otomatik kapanacak");
}

void ScreenManager::showDoorClosed() {
  if (_currentState == STATE_DOOR_OPENED) {
    showHomeScreen();
  }
}

void ScreenManager::showQrSuccess(const String& code) {
  _currentState = STATE_QR_SUCCESS;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 3000;
  drawQrSuccessScreen(code);
}

void ScreenManager::drawQrSuccessScreen(const String& code) {
  tft.fillScreen(TFT_BLACK);

  tft.fillRoundRect(15, 60, 210, 180, 12, TFT_DARKGREEN);
  tft.drawRoundRect(15, 60, 210, 180, 12, TFT_GREEN);

  tft.setTextColor(TFT_WHITE, TFT_DARKGREEN);
  tft.setTextSize(2);
  tft.setCursor(30, 100);
  tft.print("GIRIS ONAYLANDI");

  tft.setTextSize(1);
  tft.setTextColor(TFT_YELLOW, TFT_DARKGREEN);
  tft.setCursor(30, 150);
  tft.print("Gecis yetkisi verildi");

  if (code.length() > 0) {
    tft.setCursor(30, 170);
    tft.print("Kod: ");
    tft.print(code.substring(0, 14));
  }
}

void ScreenManager::showQrDenied() {
  _currentState = STATE_QR_DENIED;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 3000;
  drawQrDeniedScreen();
}

void ScreenManager::drawQrDeniedScreen() {
  tft.fillScreen(TFT_BLACK);

  tft.fillRoundRect(15, 60, 210, 180, 12, TFT_MAROON);
  tft.drawRoundRect(15, 60, 210, 180, 12, TFT_RED);

  tft.setTextColor(TFT_WHITE, TFT_MAROON);
  tft.setTextSize(2);
  tft.setCursor(35, 100);
  tft.print("GECERSIZ QR");

  tft.setTextSize(1);
  tft.setTextColor(TFT_WHITE, TFT_MAROON);
  tft.setCursor(35, 150);
  tft.print("Gecis yetkisi yok");
  tft.setCursor(35, 170);
  tft.print("veya suresi dolmus!");
}

void ScreenManager::showSettingsScreen() {
  _currentState = STATE_SETTINGS;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 30000; // 30s timeout on settings page
  drawSettingsScreen();
}

void ScreenManager::drawSettingsScreen() {
  tft.fillScreen(TFT_BLACK);

  // Title Bar
  tft.fillRect(0, 0, 240, 28, TFT_DARKGREY);
  tft.setTextColor(TFT_WHITE, TFT_DARKGREY);
  tft.setTextSize(1);
  tft.setCursor(15, 9);
  tft.print("CIHAZ BILGISI & AYARLAR");

  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setCursor(15, 45);
  tft.print("Donanim: ESP32-C3 + ST7789");

  tft.setCursor(15, 65);
  tft.print("Ekran: 2.4\" 240x320 TFT");

  tft.setCursor(15, 85);
  tft.print("Protokol: UART 115200");

  tft.setCursor(15, 115);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.print("WiFi: ");
  tft.print(_wifiConnected ? "BAGLI" : "KOPUK");

  tft.setCursor(15, 135);
  tft.print("MQTT: ");
  tft.print(_mqttConnected ? "BAGLI" : "KOPUK");

  tft.setTextColor(TFT_LIGHTGREY, TFT_BLACK);
  tft.setCursor(15, 175);
  tft.print("Is mantigi ana ESP32-WROOM");
  tft.setCursor(15, 190);
  tft.print("kontrolunde yurutulur.");

  // Back Button (X: 20, Y: 260, W: 200, H: 42)
  tft.fillRoundRect(20, 260, 200, 42, 6, TFT_NAVY);
  tft.drawRoundRect(20, 260, 200, 42, 6, TFT_CYAN);
  tft.setTextColor(TFT_WHITE, TFT_NAVY);
  tft.setTextSize(2);
  tft.setCursor(85, 273);
  tft.print("GERI");
}

void ScreenManager::setDynamicQr(const String& qrCode) {
  _qrData = qrCode;
  if (_currentState == STATE_HOME) {
    drawQRCode(_qrData, 45, 50, 150);
  }
}

void ScreenManager::drawQRCode(const String &data, int qrX, int qrY, int qrSize) {
  tft.fillRect(qrX - 2, qrY - 2, qrSize + 4, qrSize + 4, TFT_WHITE);

  QRCode qrcode;
  uint8_t qrcodeBytes[qrcode_getBufferSize(4)];
  int result = qrcode_initText(&qrcode, qrcodeBytes, 4, ECC_QUARTILE, data.c_str());
  if (result < 0) {
    tft.setTextColor(TFT_RED, TFT_WHITE);
    tft.setTextSize(1);
    tft.setCursor(qrX + 10, qrY + 60);
    tft.println("QR Hata!");
    return;
  }

  const int scale = qrSize / qrcode.size;
  const int offsetX = qrX + (qrSize - (qrcode.size * scale)) / 2;
  const int offsetY = qrY + (qrSize - (qrcode.size * scale)) / 2;

  for (uint8_t y = 0; y < qrcode.size; ++y) {
    for (uint8_t x = 0; x < qrcode.size; ++x) {
      uint16_t col = qrcode_getModule(&qrcode, x, y) ? TFT_BLACK : TFT_WHITE;
      tft.fillRect(offsetX + x * scale, offsetY + y * scale, scale, scale, col);
    }
  }
}

void ScreenManager::onTouch(int16_t x, int16_t y) {
  if (_currentState == STATE_HOME) {
    // "KAPIYI AC" Button: X[20..220], Y[215..260]
    if (x >= 20 && x <= 220 && y >= 215 && y <= 260) {
      sendCommand(CMD_BTN_OPEN);
      showDoorOpened();
      return;
    }
    // "AYARLAR" Button: X[20..220], Y[268..306]
    if (x >= 20 && x <= 220 && y >= 268 && y <= 306) {
      sendCommand(CMD_BTN_SETTINGS);
      showSettingsScreen();
      return;
    }
  } else if (_currentState == STATE_SETTINGS) {
    // "GERI" Button: X[20..220], Y[260..302]
    if (x >= 20 && x <= 220 && y >= 260 && y <= 302) {
      sendCommand(CMD_BTN_BACK);
      showHomeScreen();
      return;
    }
  } else if (_currentState == STATE_DOOR_OPENED || _currentState == STATE_QR_SUCCESS || _currentState == STATE_QR_DENIED) {
    // Touching any alert dismisses back to home immediately
    showHomeScreen();
  }
}

void ScreenManager::onButtonPress() {
  // Physical test button cycle
  if (_currentState == STATE_HOME) {
    sendCommand(CMD_BTN_OPEN);
    showDoorOpened();
  } else {
    showHomeScreen();
  }
}

void ScreenManager::processCommand(const String& rawCmd) {
  String cmd = rawCmd;
  cmd.trim();
  if (cmd.length() == 0) return;

  if (cmd == CMD_MAIN_READY) {
    sendCommand(CMD_DISP_READY);
  } else if (cmd == CMD_WIFI_CONNECTED) {
    setWifiStatus(true);
  } else if (cmd == CMD_WIFI_DISCONNECTED) {
    setWifiStatus(false);
  } else if (cmd == CMD_MQTT_CONNECTED) {
    setMqttStatus(true);
  } else if (cmd == CMD_DOOR_OPENED) {
    showDoorOpened();
  } else if (cmd == CMD_DOOR_CLOSED) {
    showDoorClosed();
  } else if (cmd.startsWith(CMD_QR_OK_PREFIX)) {
    String param = cmd.substring(strlen(CMD_QR_OK_PREFIX));
    showQrSuccess(param);
  } else if (cmd == CMD_QR_DENIED) {
    showQrDenied();
  } else if (cmd.startsWith(CMD_SHOW_QR_PREFIX)) {
    String qr = cmd.substring(strlen(CMD_SHOW_QR_PREFIX));
    setDynamicQr(qr);
  } else if (cmd == CMD_SHOW_HOME) {
    showHomeScreen();
  } else if (cmd == CMD_SHOW_SETTINGS) {
    showSettingsScreen();
  }
}
