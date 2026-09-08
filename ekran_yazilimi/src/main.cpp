#include <Arduino.h>
#include "ScreenManager.h"
#include "display_protocol.h"
#include "config.h"

// Communication with main ESP32-WROOM
// On ESP32-C3, Serial is the primary hardware serial (USB/CDC or UART0 pins 20/21)
// If dedicated pins are used, HardwareSerial(1) can be utilized.
// Default: use Serial for UART link to WROOM (115200 baud)
ScreenManager screen;

// Forward declaration for sending commands to ESP32-WROOM
void sendToWroom(const char* cmd) {
  if (cmd == nullptr || strlen(cmd) == 0) return;
  Serial.print(cmd);
  Serial.print("\n");
}

// Non-blocking UART reception buffer
static String uartLineBuffer = "";

void processUartInput() {
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r' || c == '\n') {
      if (uartLineBuffer.length() > 0) {
        screen.processCommand(uartLineBuffer);
        uartLineBuffer = "";
      }
    } else {
      uartLineBuffer += c;
      // Buffer overflow protection: 256 chars max
      if (uartLineBuffer.length() >= 256) {
        uartLineBuffer = "";
      }
    }
  }
}

// Non-blocking hardware test button (active LOW with pullup)
static bool lastBtnState = HIGH;
static unsigned long lastBtnDebounceMs = 0;

void processButtonInput() {
  const bool curState = digitalRead(BTN_PIN);
  if (curState != lastBtnState && (millis() - lastBtnDebounceMs > 200)) {
    lastBtnDebounceMs = millis();
    lastBtnState = curState;
    if (curState == LOW) {
      screen.onButtonPress();
    }
  }
}

void setup() {
  Serial.begin(DISPLAY_UART_BAUD);

  pinMode(BTN_PIN, INPUT_PULLUP);

  screen.setSendCallback(sendToWroom);
  screen.begin();

  // Notify WROOM that display controller has booted
  sendToWroom(CMD_DISP_READY);
}

void loop() {
  // 1. Process UART commands from WROOM (non-blocking)
  processUartInput();

  // 2. Process hardware inputs (non-blocking)
  processButtonInput();

  // 3. Update screen manager (non-blocking timeouts, animations)
  screen.update();
}
