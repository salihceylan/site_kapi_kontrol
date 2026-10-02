// Ana makine sahtesi: PubSubClient. Yayinlari yakalar (PubSubClient'in tampon sinirini birebir uygular), gelen mesaji
// deliver() ile callback'e verir.
#pragma once
#include <Arduino.h>
#include <WiFi.h>

#define MQTT_CONNECT_BAD_CREDENTIALS 4
#define MQTT_CONNECT_UNAUTHORIZED 5
#define MQTT_MAX_HEADER_SIZE 5

class PubSubClient {
 public:
  struct Msg { std::string topic, payload; bool retained; };
  std::vector<Msg> published;
  std::vector<std::string> subscribed;
  bool connected_ = false;
  int state_ = -1;
  bool allowConnect = true;
  bool failPublish = false;
  size_t bufSize = 256;                 // PubSubClient varsayilani (MQTT_MAX_PACKET_SIZE)
  int connectCalls = 0;
  void (*cb)(char*, uint8_t*, unsigned int) = nullptr;

  template <class C> explicit PubSubClient(C&) {}
  PubSubClient& setServer(const char*, uint16_t) { return *this; }
  PubSubClient& setCallback(void (*c)(char*, uint8_t*, unsigned int)) { cb = c; return *this; }
  bool setBufferSize(uint16_t s) { bufSize = s; return true; }
  PubSubClient& setSocketTimeout(uint16_t) { return *this; }
  PubSubClient& setKeepAlive(uint16_t) { return *this; }
  bool connect(const char*, const char*, const char*, const char*, uint8_t, bool, const char*) {
    connectCalls++;
    if (!allowConnect) { state_ = 5; return false; }
    connected_ = true; state_ = 0; return true;
  }
  bool connected() { return connected_; }
  int state() { return state_; }
  void disconnect() { connected_ = false; state_ = -1; }
  bool loop() { return connected_; }
  bool subscribe(const char* t, uint8_t = 0) { subscribed.push_back(t); return true; }
  bool publish(const char* topic, const char* payload, bool retained = false) {
    if (!connected_ || failPublish) return false;
    if (static_cast<size_t>(MQTT_MAX_HEADER_SIZE) + 2 + strlen(topic) + strlen(payload) > bufSize) return false;   // PubSubClient::publish sinir kontrolu
    published.push_back({topic, payload, retained});
    return true;
  }
  void deliver(const std::string& topic, const std::string& payload) {
    std::vector<char> t(topic.begin(), topic.end());
    t.push_back(0);
    cb(t.data(), reinterpret_cast<uint8_t*>(const_cast<char*>(payload.data())), static_cast<unsigned int>(payload.size()));
  }
};
