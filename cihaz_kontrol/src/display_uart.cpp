#include "display_uart.h"
#include "display_protocol.h"
#include <Arduino.h>

#if defined(BOARD_ESP32_WROOM_RELAY)

// Forward declarations
void roleTetikle();

// HardwareSerial(1) for communication with ESP32-C3 display controller on WROOM
static HardwareSerial displaySerial(1);

void displayUartSetup() {
  displaySerial.begin(DISPLAY_UART_BAUD, SERIAL_8N1, DISPLAY_UART_RX_PIN, DISPLAY_UART_TX_PIN);
  Serial.print("[DISPLAY] UART1 initialized (RX=");
  Serial.print(DISPLAY_UART_RX_PIN);
  Serial.print(", TX=");
  Serial.print(DISPLAY_UART_TX_PIN);
  Serial.println(")");

  // Send initial READY state to display controller
  displayUartSend(CMD_MAIN_READY);
}

void displayUartSend(const char* cmd) {
  if (cmd == nullptr || strlen(cmd) == 0) return;
  displaySerial.print(cmd);
  displaySerial.print("\n");
  Serial.print("[DISPLAY] TX: ");
  Serial.println(cmd);
}

void displayUartSend(const String& cmd) {
  if (cmd.length() == 0) return;
  displaySerial.print(cmd);
  displaySerial.print("\n");
  Serial.print("[DISPLAY] TX: ");
  Serial.println(cmd);
}

// Helper to process a complete line (command) received from display controller
static void handleDisplayCommand(const String &rawCmd) {
  String cmd = rawCmd;
  cmd.trim();
  if (cmd.length() == 0) return;

  Serial.print("[DISPLAY] RX: ");
  Serial.println(cmd);

  if (cmd == CMD_BTN_OPEN || cmd == CMD_DOOR_OPEN) {
    Serial.println("[DISPLAY] Kapi acma butonu alindi -> Role tetikleniyor");
    roleTetikle();
  } else if (cmd == CMD_BTN_SETTINGS) {
    Serial.println("[DISPLAY] Ayarlar butonu alindi");
    displayUartSend(CMD_SHOW_SETTINGS);
  } else if (cmd == CMD_BTN_HOME || cmd == CMD_BTN_BACK) {
    Serial.println("[DISPLAY] Ana ekrana donus butonu alindi");
    displayUartSend(CMD_SHOW_HOME);
  } else if (cmd == CMD_TOUCH_READY || cmd == CMD_DISP_READY) {
    Serial.println("[DISPLAY] Ekran karti READY bildirdi");
  } else if (cmd.startsWith(CMD_QR_PREFIX)) {
    String qrData = cmd.substring(strlen(CMD_QR_PREFIX));
    qrData.trim();
    Serial.print("[DISPLAY] QR verisi alindi: ");
    Serial.println(qrData);
  } else {
    Serial.print("[DISPLAY] Bilinmeyen komut (yoksayildi): ");
    Serial.println(cmd);
  }
}

void displayUartLoop() {
  static String lineBuffer;

  while (displaySerial.available() > 0) {
    char c = static_cast<char>(displaySerial.read());
    if (c == '\r' || c == '\n') {
      if (lineBuffer.length() > 0) {
        handleDisplayCommand(lineBuffer);
        lineBuffer = "";
      }
    } else {
      lineBuffer += c;
      // Buffer overflow protection: max 256 bytes
      if (lineBuffer.length() >= 256) {
        lineBuffer = "";
      }
    }
  }
}

#else

// Sahadaki ESP32-C3 Super Mini cihazlarinda harici ekran yoktur (Kural 3).
// Bu nedenle fonksiyonlar C3 hedefleri icin guvenli no-op olarak calisir.
void displayUartSetup() {}
void displayUartLoop() {}
void displayUartSend(const char* cmd) {}
void displayUartSend(const String& cmd) {}

#endif
