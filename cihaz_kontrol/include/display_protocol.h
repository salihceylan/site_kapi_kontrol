#pragma once

// Simple line‑based protocol from ESP32‑WROOM to ESP32‑C3 display controller
// Commands are terminated by '\n' (or '\r\n')

#define CMD_READY      "READY"
#define CMD_DOOR_OPEN  "DOOR_OPEN"
#define CMD_DOOR_CLOSE "DOOR_CLOSE"
#define CMD_QR_PREFIX  "QR:"   // e.g. "QR:AB12CD..."

// You can extend this list with status updates, error codes, etc.

