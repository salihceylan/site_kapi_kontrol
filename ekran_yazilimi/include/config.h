#pragma once
#include <Arduino.h>

#define DISPLAY_FIRMWARE_VERSION "1.1.1"

// ==========================================
// UART Configuration to ESP32-WROOM (Main MCU)
// ==========================================
// Connections:
// ESP32-WROOM GPIO32 (RX) <- ESP32-C3 GPIO21 (TX)
// ESP32-WROOM GPIO33 (TX) -> ESP32-C3 GPIO20 (RX)
// GND                     <-> GND
constexpr int DISPLAY_UART_RX_PIN = 20; // C3 UART RX from WROOM TX33
constexpr int DISPLAY_UART_TX_PIN = 21; // C3 UART TX to WROOM RX32
constexpr uint32_t DISPLAY_UART_BAUD = 115200;

// ==========================================
// Display Configuration (ST7789 2.4" 240x320)
// ==========================================
#define TFT_WIDTH   240
#define TFT_HEIGHT  320

// Pinout mapping for ST7789 display on ESP32-C3 2.4" module
#ifndef TFT_MOSI
  #define TFT_MOSI 7
#endif
#ifndef TFT_SCLK
  #define TFT_SCLK 6
#endif
#ifndef TFT_CS
  #define TFT_CS   -1
#endif
#ifndef TFT_DC
  #define TFT_DC   10
#endif
#ifndef TFT_RST
  #define TFT_RST  8
#endif
#ifndef TFT_BL
  #define TFT_BL   0
#endif

// ==========================================
// Touch / Hardware Input (CST816D / Button / LED)
// ==========================================
constexpr int TOUCH_SDA_PIN = 4;
constexpr int TOUCH_SCL_PIN = 5;
constexpr int TOUCH_RST_PIN = 2;
constexpr int TOUCH_INT_PIN = 3;

// Onboard Status LED & Boot Button
constexpr int STATUS_LED_PIN = 1;
constexpr int BTN_PIN = 9;
