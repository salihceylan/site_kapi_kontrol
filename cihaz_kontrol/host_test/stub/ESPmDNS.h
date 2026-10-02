#pragma once
#include <Arduino.h>

struct FakeMDNST {
  bool begin(const char*) { return true; }
  void addService(const char*, const char*, uint16_t) {}
  void end() {}
};
inline FakeMDNST MDNS;
