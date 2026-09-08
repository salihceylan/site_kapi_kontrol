#pragma once

// Simple line-based protocol between ESP32-WROOM (Main MCU) and ESP32-C3 (Display Controller)
// Commands are terminated by '\n' (or '\r\n')

// ==========================================
// Commands from Main ESP32 -> Display ESP32
// ==========================================
#define CMD_MAIN_READY           "READY"
#define CMD_WIFI_CONNECTED       "WIFI_CONNECTED"
#define CMD_WIFI_DISCONNECTED    "WIFI_DISCONNECTED"
#define CMD_MQTT_CONNECTED       "MQTT_CONNECTED"
#define CMD_DOOR_OPENED          "DOOR_OPENED"
#define CMD_DOOR_CLOSED          "DOOR_CLOSED"
#define CMD_QR_OK_PREFIX         "QR_OK|"          // e.g. "QR_OK|123456"
#define CMD_QR_DENIED            "QR_DENIED"
#define CMD_SHOW_QR_PREFIX       "SHOW_QR|"        // e.g. "SHOW_QR|xxxxxxxx"
#define CMD_SHOW_HOME            "SHOW_HOME"
#define CMD_SHOW_SETTINGS        "SHOW_SETTINGS"

// ==========================================
// Commands from Display ESP32 -> Main ESP32
// ==========================================
#define CMD_DISP_READY           "READY"
#define CMD_BTN_OPEN             "BTN_OPEN"
#define CMD_BTN_SETTINGS         "BTN_SETTINGS"
#define CMD_BTN_HOME             "BTN_HOME"
#define CMD_BTN_BACK             "BTN_BACK"
#define CMD_TOUCH_READY          "TOUCH_READY"

// Legacy/Alternative compatibility
#define CMD_DOOR_OPEN            "DOOR_OPEN"
#define CMD_DOOR_CLOSE           "DOOR_CLOSE"
#define CMD_QR_PREFIX            "QR:"             // e.g. "QR:AB12CD..."
