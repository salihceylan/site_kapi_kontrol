#pragma once

// Simple line-based protocol between ESP32-WROOM (Main MCU) and ESP32-C3 (Display Controller)
// Commands are terminated by '\n' (or '\r\n'). Fields are separated by '|' (senders MUST NOT put '|' or
// control characters inside a field; the main MCU sanitizes SSID values). Max line length: 255 bytes.
// On overflow the receiver drops the rest of the line up to the next '\n' (resynchronisation).
//
// NOTE: This file MUST be byte-identical in cihaz_kontrol/include and ekran_yazilimi/include.

// ==========================================
// Commands from Main ESP32 -> Display ESP32
// ==========================================
#define CMD_MAIN_READY           "READY"
#define CMD_WIFI_CONNECTED       "WIFI_CONNECTED"
#define CMD_WIFI_DISCONNECTED    "WIFI_DISCONNECTED"
#define CMD_MQTT_CONNECTED       "MQTT_CONNECTED"
#define CMD_MQTT_DISCONNECTED    "MQTT_DISCONNECTED"
#define CMD_DOOR_OPENED          "DOOR_OPENED"
#define CMD_DOOR_CLOSED          "DOOR_CLOSED"
#define CMD_QR_READING           "QR_READING"
#define CMD_QR_OK_PREFIX         "QR_OK|"          // e.g. "QR_OK|123456"
#define CMD_QR_DENIED            "QR_DENIED"
#define CMD_SHOW_QR_PREFIX       "SHOW_QR|"        // e.g. "SHOW_QR|AHBU:DOOR:<UID>:<TOKEN>"
#define CMD_SHOW_HOME            "SHOW_HOME"
#define CMD_SHOW_SETTINGS        "SHOW_SETTINGS"
#define CMD_SYS_STATUS_PREFIX    "SYS_STATUS|"     // "SYS_STATUS|SSID|IP|RSSI|MQTT(1/0)|UPTIME|CAM(1/0)"
#define CMD_SYS_INFO_PREFIX      "SYS_INFO|"       // "SYS_INFO|UID|FW|TARGET"  (gercek UID, surum ve hedef)

// Admin PIN (C10): PIN ana MCU NVS'inde tutulur, ekranda sabit PIN YOKTUR; dogrulamayi ana MCU yapar.
#define CMD_ADMIN_OK             "ADMIN_OK"        // ADMIN_AUTH basarili
#define CMD_ADMIN_DENIED_PREFIX  "ADMIN_DENIED|"   // "ADMIN_DENIED|BAD|<kalan_deneme>" | "|LOCKED|<sn>" | "|NOPIN" | "|BUSY"
#define CMD_ADMIN_STATE_PREFIX   "ADMIN_STATE|"    // "ADMIN_STATE|READY" | "|NOPIN" | "|LOCKED|<sn>"  (REQ_ADMIN yaniti)

// ==========================================
// Commands from Display ESP32 -> Main ESP32
// ==========================================
#define CMD_DISP_READY           "READY"
#define CMD_BTN_OPEN             "BTN_OPEN"        // fiziksel buton: ana MCU yetkisiz sayar (kapi acmaz)
#define CMD_ADMIN_OPEN           "ADMIN_OPEN"      // "ADMIN_OPEN|<6 haneli pin>": ana MCU PIN'i dogrular ve roleyi tetikler
#define CMD_ADMIN_AUTH           "ADMIN_AUTH"      // "ADMIN_AUTH|<6 haneli pin>": menu girisi icin PIN dogrulama
#define CMD_REQ_ADMIN            "REQ_ADMIN"       // PIN durumu iste (ADMIN_STATE yaniti)
#define CMD_REQ_STATUS           "REQ_STATUS"
#define CMD_REQ_INFO             "REQ_INFO"
#define CMD_BTN_SETTINGS         "BTN_SETTINGS"
#define CMD_BTN_HOME             "BTN_HOME"
#define CMD_BTN_BACK             "BTN_BACK"
#define CMD_TOUCH_READY          "TOUCH_READY"

// Legacy/Alternative compatibility
#define CMD_DOOR_OPEN            "DOOR_OPEN"
#define CMD_DOOR_CLOSE           "DOOR_CLOSE"
#define CMD_QR_PREFIX            "QR:"             // e.g. "QR:AB12CD..."
