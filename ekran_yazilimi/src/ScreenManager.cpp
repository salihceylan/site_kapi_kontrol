#include "ScreenManager.h"
#include "config.h"
#include <ArduinoJson.h>
#include <qrcode.h>  // ricmoo/QRCode library

void ScreenManager::begin() {
    // Initialize TFT pins (defined in config.h)
    tft.begin();
    tft.setRotation(1);
    tft.fillScreen(TFT_BLACK);
    // Show placeholder UI
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setCursor(10, 10);
    tft.println("ESP32 WROOM Screen Firmware");
    // Initial status offline
    showStatus(false);
}

void ScreenManager::showStatus(bool online) {
    // Draw a small circle indicator at top-right
    uint16_t color = online ? TFT_GREEN : TFT_RED;
    tft.fillCircle(tft.width() - 15, 15, 5, color);
    // Optional label
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setCursor(tft.width() - 60, 10);
    tft.print(online ? "ONLINE" : "OFFLINE");
}

void ScreenManager::updateFromPayload(const String &json) {
    // Expected format: {"qr":"<data>","door":"open"}
    // ArduinoJson v7: use JsonDocument (DynamicJsonDocument removed)
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, json);
    if (err) {
        // Show error on screen
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.setCursor(10, 30);
        tft.println("JSON error");
        return;
    }
    // QR code
    if (doc["qr"].is<const char*>()) {
        String qrData = doc["qr"].as<String>();
        drawQRCode(qrData);
    }
    // Door state
    if (doc["door"].is<const char*>()) {
        String state = doc["door"].as<String>();
        bool open = (state == "open" || state == "opened");
        drawDoorState(open);
    }
    // Update online status
    if (doc["online"].is<bool>()) {
        bool online = doc["online"].as<bool>();
        showStatus(online);
    }
}

void ScreenManager::handleInput() {
    // Placeholder: check a GPIO button for settings (pin 0 as example)
    const uint8_t SETTINGS_BTN = 0;
    pinMode(SETTINGS_BTN, INPUT_PULLUP);
    static bool lastState = HIGH;
    bool cur = digitalRead(SETTINGS_BTN);
    if (lastState == HIGH && cur == LOW) {
        // Button pressed - open settings menu
        drawSettingsMenu();
    }
    lastState = cur;
}

void ScreenManager::drawQRCode(const String &data) {
    // ricmoo/QRCode API: qrcode_initText(&qrcode, qrcodeBytes, version, ecc, text)
    const int qrX   = 10;
    const int qrY   = 50;
    const int qrSize = 200;
    tft.fillRect(qrX, qrY, qrSize, qrSize, TFT_BLACK);

    QRCode qrcode;
    // Version 4 = up to 50 alphanumeric / 25 binary chars
    uint8_t qrcodeBytes[qrcode_getBufferSize(4)];
    int result = qrcode_initText(&qrcode, qrcodeBytes, 4, ECC_QUARTILE, data.c_str());
    if (result < 0) {
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.setCursor(10, qrY + qrSize + 5);
        tft.println("QR err");
        return;
    }

    const int scale = qrSize / qrcode.size;  // pixels per module
    for (uint8_t y = 0; y < qrcode.size; ++y) {
        for (uint8_t x = 0; x < qrcode.size; ++x) {
            uint16_t col = qrcode_getModule(&qrcode, x, y) ? TFT_BLACK : TFT_WHITE;
            tft.fillRect(qrX + x * scale, qrY + y * scale, scale, scale, col);
        }
    }
}

void ScreenManager::drawDoorState(bool open) {
    // Simple text status at bottom
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.setCursor(10, tft.height() - 30);
    tft.print("Door: ");
    tft.print(open ? "OPEN" : "CLOSED");
}

void ScreenManager::drawSettingsMenu() {
    // Simple overlay with two options (placeholder)
    tft.fillRect(20, 20, tft.width() - 40, tft.height() - 40, TFT_DARKGREY);
    tft.setTextColor(TFT_WHITE, TFT_DARKGREY);
    tft.setCursor(40, 50);
    tft.println("* Settings *");
    tft.setCursor(40, 80);
    tft.println("1. Wi‑Fi Config (TODO)");
    tft.setCursor(40, 110);
    tft.println("2. Back (press button again)");
    // Wait for button release to close (very naive)
    delay(2000);
    // Clear overlay
    tft.fillScreen(TFT_BLACK);
    // Redraw default UI
    tft.setCursor(10, 10);
    tft.println("ESP32 WROOM Screen Firmware");
    showStatus(false);
}

