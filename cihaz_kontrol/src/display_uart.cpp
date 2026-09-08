#include "display_uart.h"
#include "display_protocol.h"
#include <Arduino.h>

// Forward declaration – roleTetikle() is defined in role_kontrol.h (included in main.cpp)
// We declare it here to avoid pulling in the full header (which contains inline globals)
// that would cause multiple-definition issues across translation units.
void roleTetikle();

// Use UART1 (HardwareSerial(1)) for communication with ESP32-C3 display controller
static HardwareSerial displaySerial(1);

void displayUartSetup() {
  // Initialise UART with defined pins and baud rate
  displaySerial.begin(DISPLAY_UART_BAUD, SERIAL_8N1, DISPLAY_UART_RX_PIN, DISPLAY_UART_TX_PIN);
  Serial.print("[Display UART] initialized (RX=");
  Serial.print(DISPLAY_UART_RX_PIN);
  Serial.print(", TX=");
  Serial.print(DISPLAY_UART_TX_PIN);
  Serial.println(")");
}

// Helper to process a complete line (command) received from the display controller
static void handleDisplayCommand(const String &cmd) {
  // Simple protocol: commands are plain ASCII strings terminated by '\n'
  if (cmd.startsWith(CMD_QR_PREFIX)) {
    // Example: "QR:<data>"
    String qrData = cmd.substring(strlen(CMD_QR_PREFIX));
    Serial.print("[Display UART] QR received: ");
    Serial.println(qrData);
    // TODO: forward to MQTT/QR validation logic as needed
  } else if (cmd == CMD_DOOR_OPEN) {
    Serial.println("[Display UART] Door open command received");
    // Trigger door relay via existing role logic
    roleTetikle();
  } else if (cmd == CMD_DOOR_CLOSE) {
    Serial.println("[Display UART] Door close command received");
    // Close action placeholder
  } else if (cmd == CMD_READY) {
    Serial.println("[Display UART] Display reports READY");
  } else {
    Serial.print("[Display UART] Unknown command: ");
    Serial.println(cmd);
  }
}

void displayUartLoop() {
  while (displaySerial.available() > 0) {
    static String lineBuffer;
    char c = static_cast<char>(displaySerial.read());
    if (c == '\r' || c == '\n') {
      if (lineBuffer.length() > 0) {
        handleDisplayCommand(lineBuffer);
        lineBuffer.clear();
      }
    } else {
      lineBuffer += c;
      // Prevent runaway buffer
      if (lineBuffer.length() > 256) {
        lineBuffer.remove(0);
      }
    }
  }
}
