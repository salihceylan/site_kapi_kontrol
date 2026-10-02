// Ana makine sahtesi: WiFi / IPAddress / WiFiClient / WiFiServer (HTTP testleri istemciye betiklenmis istek verir, yaniti yakalar).
#pragma once
#include <Arduino.h>

#define WIFI_MODE_NULL 0
#define WIFI_OFF 0
#define WIFI_STA 1

inline bool g_tcp_probe_ok = true;   // WiFiClient::connect (MQTT TCP on-kontrolu) sonucu

class IPAddress {
 public:
  uint8_t o[4] = {0, 0, 0, 0};
  IPAddress() {}
  IPAddress(uint8_t a, uint8_t b, uint8_t c, uint8_t d) { o[0] = a; o[1] = b; o[2] = c; o[3] = d; }
  IPAddress(uint32_t v) { memcpy(o, &v, 4); }          // Arduino-ESP32: ilk sekizli dword'un dusuk baytinda
  uint8_t operator[](int i) const { return o[i]; }
  operator uint32_t() const { uint32_t v; memcpy(&v, o, 4); return v; }
  bool operator==(const IPAddress& b) const { return memcmp(o, b.o, 4) == 0; }
  bool operator!=(const IPAddress& b) const { return !(*this == b); }
  String toString() const { char b[24]; snprintf(b, sizeof b, "%u.%u.%u.%u", o[0], o[1], o[2], o[3]); return String(b); }
};

struct FakeClientState {
  std::string rx;
  size_t rpos = 0;
  std::string tx;
  bool conn = true;
  bool valid = true;
  IPAddress rip;
};

class WiFiClient {
 public:
  std::shared_ptr<FakeClientState> st;
  WiFiClient() : st(std::make_shared<FakeClientState>()) { st->valid = false; }
  explicit WiFiClient(std::shared_ptr<FakeClientState> s) : st(std::move(s)) {}
  bool connected() { return st->conn; }
  int available() { return static_cast<int>(st->rx.size() - st->rpos); }
  int read() { return st->rpos < st->rx.size() ? static_cast<unsigned char>(st->rx[st->rpos++]) : -1; }
  size_t write(const uint8_t* b, size_t n) { st->tx.append(reinterpret_cast<const char*>(b), n); return n; }
  void stop() { st->conn = false; }
  IPAddress remoteIP() { return st->rip; }
  explicit operator bool() const { return st->valid; }
  void setNoDelay(bool) {}
  int connect(IPAddress, uint16_t, int32_t = 0) { return g_tcp_probe_ok ? 1 : 0; }
  void setTimeout(uint32_t) {}
};

class WiFiServer {
 public:
  std::deque<std::shared_ptr<FakeClientState>> bekleyen;
  bool started = false;
  WiFiServer(uint16_t, uint8_t = 4) {}
  void begin() { started = true; }
  void setNoDelay(bool) {}
  void stop() { started = false; }
  WiFiClient available() {
    if (bekleyen.empty()) return WiFiClient();
    auto s = bekleyen.front();
    bekleyen.pop_front();
    return WiFiClient(s);
  }
};

struct FakeWiFiT {
  IPAddress lip{192, 168, 100, 200};
  IPAddress mask{255, 255, 255, 0};
  IPAddress bcast{192, 168, 100, 255};
  int mode_ = WIFI_STA;
  IPAddress localIP() { return lip; }
  IPAddress subnetMask() { return mask; }
  IPAddress broadcastIP() { return bcast; }
  String SSID() { return String("TestAP"); }
  int getMode() { return mode_; }
  void mode(int m) { mode_ = m; }
  void disconnect(bool = false, bool = false) {}
};
inline FakeWiFiT WiFi;
