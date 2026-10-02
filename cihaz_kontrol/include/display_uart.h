#pragma once

#include <Arduino.h>

// Pin definitions for the display-controller UART (ESP32-WROOM <-> ESP32-C3)
// Connected: WROOM GPIO32 (RX) <- C3 (TX), WROOM GPIO33 (TX) -> C3 (RX)
constexpr int DISPLAY_UART_RX_PIN = 32; // UART1 RX
constexpr int DISPLAY_UART_TX_PIN = 33; // UART1 TX
constexpr uint32_t DISPLAY_UART_BAUD = 115200;

// Function declarations
void displayUartSetup();
void displayUartLoop();
void displayUartSend(const char* cmd);
void displayUartSend(const String& cmd);
void broadcastScreenQrToken(bool isNewToken = false);

// main.cpp tarafinda tanimlanan sistem durum/olay kancalari (src/display_uart.cpp bunlari kullanir;
// boylece display_uart.cpp icindeki sahte on-bildirimler ve ikinci kopya Serial/HardwareSerial nesneleri gerekmez)
bool systemWifiReady();
String systemWifiSsid();
String systemWifiIp();
int systemWifiRssi();
bool systemMqttReady();
bool systemCameraConnected();
String systemFirmwareVersion();
String systemHardwareTarget();
// Yonetici ekran PIN'iyle kapi acma: true ise role tetiklendi (yan etkiler main.cpp'de yapildi)
bool systemAdminKapiAc();
// MQTT olay yayini (denetim): PIN/token ASLA detail icinde olmamali
void systemMqttOlay(const char* eventName, const char* detail);
// Ekranin WiFi/MQTT durumunu aninda yeniden gonder (ekran yeniden basladiginda kendini toparlasin)
void displayDurumuYenidenGonder();
