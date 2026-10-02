// Ana makine sahtesi: WiFiUDP (gelen paketler kuyrukta; giden paketler `sent`te yakalanir).
#pragma once
#include <Arduino.h>
#include <WiFi.h>

class WiFiUDP {
 public:
  struct In { std::string data; IPAddress ip; uint16_t port = 0; };
  struct Out { IPAddress ip; uint16_t port = 0; std::string data; };
  std::deque<In> inq;
  In cur;
  size_t rpos = 0;
  std::vector<Out> sent;
  Out pending;
  bool started = false;

  uint8_t begin(uint16_t) { started = true; return 1; }
  void stop() { started = false; }
  int parsePacket() {
    if (inq.empty()) return 0;
    cur = inq.front();
    inq.pop_front();
    rpos = 0;
    return static_cast<int>(cur.data.size());
  }
  int read(char* buf, size_t n) {
    const size_t k = std::min(n, cur.data.size() - rpos);
    memcpy(buf, cur.data.data() + rpos, k);
    rpos += k;
    return static_cast<int>(k);
  }
  IPAddress remoteIP() { return cur.ip; }
  uint16_t remotePort() { return cur.port; }
  int beginPacket(IPAddress ip, uint16_t port) { pending = Out(); pending.ip = ip; pending.port = port; return 1; }
  size_t print(const String& v) { pending.data += v.s; return v.length(); }
  size_t print(const char* v) { pending.data += v; return strlen(v); }
  int endPacket() { sent.push_back(pending); return 1; }
  void flush() { cur.data.clear(); rpos = 0; }
};
