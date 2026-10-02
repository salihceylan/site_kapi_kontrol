#pragma once
#include <Arduino.h>
#include <WiFi.h>

inline IPAddress g_broker_ip(34, 120, 10, 20);
inline bool g_secure_connected = true;

class WiFiClientSecure : public WiFiClient {
 public:
  void setCACert(const char*) {}
  void setTimeout(uint32_t) {}
  void setHandshakeTimeout(uint32_t) {}
  bool connected() { return g_secure_connected; }
  IPAddress remoteIP() { return g_broker_ip; }
  int lastError(char* b, size_t) { if (b) b[0] = 0; return 0; }
};
