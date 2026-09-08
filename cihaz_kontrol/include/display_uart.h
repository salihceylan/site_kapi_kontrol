#pragma once

#include <Arduino.h>

// Pin definitions for the display‑controller UART (ESP32‑WROOM ↔ ESP32‑C3)
constexpr int DISPLAY_UART_RX_PIN = 32; // UART1 RX
constexpr int DISPLAY_UART_TX_PIN = 33; // UART1 TX
constexpr uint32_t DISPLAY_UART_BAUD = 115200;

// Forward declaration of the init and loop functions
void displayUartSetup();
void displayUartLoop();

