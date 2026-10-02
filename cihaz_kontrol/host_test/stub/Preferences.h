// Ana makine sahtesi: NVS Preferences (bellek icinde; yazma sayaci testlerde flash asinmasi/yazma sayisi denetimi icin)
#pragma once
#include <Arduino.h>

inline std::map<std::string, std::map<std::string, std::string>> g_nvs;
inline int g_nvs_writes = 0;

class Preferences {
 public:
  std::string ns;
  bool begin(const char* name, bool = false) { ns = name; g_nvs[ns]; return true; }
  void end() {}
  bool isKey(const char* k) { return g_nvs[ns].count(k) != 0; }
  bool remove(const char* k) { g_nvs_writes++; return g_nvs[ns].erase(k) != 0; }
  String getString(const char* k, const String& def = String()) {
    auto it = g_nvs[ns].find(k);
    return it == g_nvs[ns].end() ? def : String(it->second.c_str());
  }
  size_t putString(const char* k, const String& v) { g_nvs_writes++; g_nvs[ns][k] = v.s; return v.length(); }
  uint8_t getUChar(const char* k, uint8_t def = 0) {
    auto it = g_nvs[ns].find(k);
    return it == g_nvs[ns].end() ? def : static_cast<uint8_t>(atoi(it->second.c_str()));
  }
  size_t putUChar(const char* k, uint8_t v) { g_nvs_writes++; g_nvs[ns][k] = std::to_string(v); return 1; }
  uint32_t getUInt(const char* k, uint32_t def = 0) {
    auto it = g_nvs[ns].find(k);
    return it == g_nvs[ns].end() ? def : static_cast<uint32_t>(strtoul(it->second.c_str(), nullptr, 10));
  }
  size_t putUInt(const char* k, uint32_t v) { g_nvs_writes++; g_nvs[ns][k] = std::to_string(v); return 4; }
};
