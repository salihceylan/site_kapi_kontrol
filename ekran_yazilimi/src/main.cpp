#include <Arduino.h>
#include "ScreenManager.h"
#include "display_protocol.h"
#include "config.h"
#include "cst816d_touch.h"

// Communication with main ESP32-WROOM
ScreenManager screen;
CST816DTouch touch;

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

// Non-blocking capacitive touch polling
static unsigned long lastTouchPollMs = 0;

void processTouchInput() {
  if (!touch.isAvailable()) return;

  // Poll touch controller at ~20 Hz (non-blocking 50ms)
  if (millis() - lastTouchPollMs < 50) return;
  lastTouchPollMs = millis();

  int16_t tx, ty;
  if (touch.readTouch(tx, ty)) {
    screen.onTouch(tx, ty);
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

  // Initialize capacitive touch controller
  if (touch.begin(TOUCH_SDA_PIN, TOUCH_SCL_PIN, TOUCH_RST_PIN, TOUCH_INT_PIN)) {
    sendToWroom(CMD_TOUCH_READY);
  }

  // Notify WROOM that display controller has booted
  sendToWroom(CMD_DISP_READY);
}

void loop() {
  // 1. Process UART commands from WROOM (non-blocking)
  processUartInput();

  // 2. Process capacitive touch events (non-blocking)
  processTouchInput();

  // 3. Process hardware inputs / test button (non-blocking)
  processButtonInput();

  // 4. Update screen manager (non-blocking timeouts, animations)
  screen.update();
}
