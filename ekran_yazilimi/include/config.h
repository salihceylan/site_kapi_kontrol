#pragma once
#include <Arduino.h>

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

// Pinout mapping for ST7789 display on ESP32-C3 module
// (Pins can also be defined via build_flags or TFT_eSPI User_Setup)
#ifndef TFT_CS
  #define TFT_CS   7
#endif
#ifndef TFT_DC
  #define TFT_DC   2
#endif
#ifndef TFT_RST
  #define TFT_RST  1
#endif
#ifndef TFT_MOSI
  #define TFT_MOSI 6
#endif
#ifndef TFT_SCLK
  #define TFT_SCLK 4
#endif

// ==========================================
// Touch / Hardware Input (CST816D / Button)
// ==========================================
constexpr int TOUCH_SDA_PIN = 4;
constexpr int TOUCH_SCL_PIN = 5;
constexpr int TOUCH_INT_PIN = 0;
constexpr int TOUCH_RST_PIN = 1;

// Physical fallback / testing button (e.g. Boot button GPIO 9 on ESP32-C3)
constexpr int BTN_PIN = 9;
