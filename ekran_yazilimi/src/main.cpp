#include <Arduino.h>
#include "ScreenManager.h"
#include "config.h"

ScreenManager screen;

void setup() {
  Serial.begin(115200);
  screen.begin();                     // TFT init, default UI
  screen.showStatus(false);           // start as offline
}

void loop() {
  if (Serial.available()) {
    String payload = Serial.readStringUntil('\n'); // JSON from WROOM
    screen.updateFromPayload(payload);
  }
  screen.handleInput();               // handle button/touch
  delay(10);
}

