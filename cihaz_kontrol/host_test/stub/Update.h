#pragma once
#include <Arduino.h>
#define U_FLASH 0
inline bool g_update_fail_begin = false;
inline bool g_update_fail_write = false;
struct UpdateClass {
  size_t total = 0, written = 0;
  bool active = false;
  int aborts = 0, ends = 0;
  bool begin(size_t size, int = U_FLASH) { if (g_update_fail_begin) return false; total = size; written = 0; active = true; return true; }
  bool setMD5(const char*) { return true; }
  size_t write(uint8_t*, size_t n) { if (g_update_fail_write) return 0; written += n; return n; }
  bool end(bool = false) { ends++; active = false; return written == total; }
  void abort() { aborts++; active = false; }
  const char* errorString() { return g_update_fail_write ? "Write Failed" : "No Error"; }
};
inline UpdateClass Update;
