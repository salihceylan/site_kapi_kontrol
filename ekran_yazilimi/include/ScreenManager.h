#ifndef SCREEN_MANAGER_H
#define SCREEN_MANAGER_H

#include <TFT_eSPI.h>
#include <ArduinoJson.h>

class ScreenManager {
public:
    void begin();               // Initialize TFT and UI
    void showStatus(bool online); // Show online/offline indicator
    void updateFromPayload(const String& json); // Parse JSON from UART and update UI
    void handleInput();          // Handle button or touch input for settings
private:
    TFT_eSPI tft = TFT_eSPI();   // TFT driver instance
    void drawQRCode(const String& data);
    void drawDoorState(bool open);
    void drawSettingsMenu();
};

#endif // SCREEN_MANAGER_H

