// Ana makine sahtesi: HTTPClient. Rotalar URL (sorgu dizesi atilir) ile eslenir; govde bayt dizisi.
#pragma once
#include <Arduino.h>
#include <WiFiClientSecure.h>

#define HTTP_CODE_OK 200
struct FakeRoute {
  int code = 200;
  std::string body;
  int dropAfter = -1;   // akis bu kadar bayttan sonra kopar (-1: kopmaz)
};
inline std::map<std::string, FakeRoute> g_http_routes;
inline std::vector<std::string> g_http_requests;
inline int g_http_default_code = -1;   // rota yoksa: negatif = baglanti hatasi

class HTTPClient {
 public:
  std::string url;
  const FakeRoute* route = nullptr;
  void setTimeout(uint16_t) {}
  bool begin(WiFiClient&, String u) {
    url = u.s;
    g_http_requests.push_back(url);
    const std::string key = url.substr(0, url.find('?'));
    auto it = g_http_routes.find(key);
    route = it == g_http_routes.end() ? nullptr : &it->second;
    return true;
  }
  int GET() { return route ? route->code : g_http_default_code; }
  String getString() { return route ? String(route->body.c_str()) : String(); }
  int getSize() { return route ? static_cast<int>(route->body.size()) : -1; }
  void end() {}
  int writeToStream(Stream* st) {
    if (!route) return -1;
    const size_t n = route->body.size();
    const size_t gonder = route->dropAfter >= 0 ? static_cast<size_t>(route->dropAfter) : n;
    size_t i = 0;
    while (i < gonder) {
      const size_t k = std::min<size_t>(1024, gonder - i);
      if (st->write(reinterpret_cast<const uint8_t*>(route->body.data()) + i, k) != k) return -6;   // HTTPC_ERROR_STREAM_WRITE
      i += k;
    }
    return static_cast<int>(i);
  }
};
