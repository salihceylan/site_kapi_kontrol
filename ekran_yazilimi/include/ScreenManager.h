#pragma once

#include <Arduino.h>
#include <TFT_eSPI.h>

enum ScreenState {
  STATE_HOME,
  STATE_DOOR_OPENED,
  STATE_QR_SUCCESS,
  STATE_QR_DENIED,
  STATE_SETTINGS
};

// Callback type to send UART commands to main ESP32-WROOM
typedef void (*UartSendCallback)(const char* cmd);

class ScreenManager {
public:
  ScreenManager();
  void begin();
  void update(); // Non-blocking loop handler (handles auto-return timeouts)
  void processCommand(const String& cmd);

  // Status updates from main controller
  void setWifiStatus(bool connected);
  void setMqttStatus(bool connected);

  // Screen transitions
  void showHomeScreen();
  void showDoorOpened();
  void showDoorClosed();
  void showQrSuccess(const String& code);
  void showQrDenied();
  void showSettingsScreen();
  void setDynamicQr(const String& qrCode);

  // Input handling
  void onTouch(int16_t x, int16_t y);
  void onButtonPress(); // Fallback hardware button

  void setSendCallback(UartSendCallback cb) { _sendCb = cb; }

private:
  TFT_eSPI tft;
  ScreenState _currentState;
  unsigned long _stateEnteredMs;
  unsigned long _autoReturnTimeoutMs;

  bool _wifiConnected;
  bool _mqttConnected;
  String _qrData;
  String _lastQrCode;

  UartSendCallback _sendCb;

  void drawTopBar();
  void drawHomeScreen();
  void drawDoorOpenedScreen();
  void drawQrSuccessScreen(const String& code);
  void drawQrDeniedScreen();
  void drawSettingsScreen();
  void drawQRCode(const String& data, int x, int y, int size);

  void sendCommand(const char* cmd);
};
