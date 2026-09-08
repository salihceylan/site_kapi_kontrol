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
