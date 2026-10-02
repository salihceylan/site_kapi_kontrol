// Ana makine (MSVC) sahtesi: cihaz_kontrol basliklarinin kullandigi Arduino/ESP32 API'sinin kucuk bir alt kumesi.
// Tum global durum `inline` degiskendir (tek cevirim birimi); testler bunlari dogrudan okur/yazar.
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <algorithm>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#define HIGH 1
#define LOW 0
#define INPUT 0
#define OUTPUT 1
#define INPUT_PULLUP 2
#define SERIAL_8N1 0x800001c
#define PROGMEM
typedef uint8_t byte;
typedef bool boolean;

// ---- sahte saat (32 bit, ESP32 millis() gibi 49,7 gunde sarar) ve donanim durumu -------------------------------------------
inline uint32_t g_fake_ms = 0;
inline uint64_t g_efuse_mac = 0x0000240AC4E2E001ULL;   // cihazUniqueId() = "240AC4E2E001"
inline int g_pin_state[64] = {};
inline bool g_restart_requested = false;

inline unsigned long millis() { return g_fake_ms; }
inline void delay(unsigned long ms) { g_fake_ms += static_cast<uint32_t>(ms); }
inline void yield() {}
inline void pinMode(uint8_t, uint8_t) {}
inline void digitalWrite(uint8_t pin, uint8_t v) { g_pin_state[pin & 63] = v; }
inline int digitalRead(uint8_t pin) { return g_pin_state[pin & 63]; }

// esp_random: testler g_rng_state ile tohumlar (xorshift64*); gercek cihazda donanim RNG'dir
inline uint64_t g_rng_state = 0x9E3779B97F4A7C15ULL;
inline uint32_t esp_random() {
  g_rng_state ^= g_rng_state >> 12;
  g_rng_state ^= g_rng_state << 25;
  g_rng_state ^= g_rng_state >> 27;
  return static_cast<uint32_t>((g_rng_state * 2685821657736338717ULL) >> 32);
}

// ---- Arduino String (std::string tabanli; ArduinoJson'un std-string yazicisi icin push_back/append/clear var) ------------------
class String {
 public:
  std::string s;
  String() {}
  String(const char* c) : s(c ? c : "") {}
  String(const String&) = default;
  String(String&&) = default;
  String& operator=(const String&) = default;
  String& operator=(String&&) = default;
  String& operator=(const char* c) { s = c ? c : ""; return *this; }
  String(char c) : s(1, c) {}
  String(int v) : s(std::to_string(v)) {}
  String(unsigned v) : s(std::to_string(v)) {}
  String(long v) : s(std::to_string(v)) {}
  String(unsigned long v) : s(std::to_string(v)) {}
  String(long long v) : s(std::to_string(v)) {}
  String(unsigned long long v) : s(std::to_string(v)) {}
  unsigned int length() const { return static_cast<unsigned int>(s.size()); }
  const char* c_str() const { return s.c_str(); }
  bool isEmpty() const { return s.empty(); }
  char operator[](unsigned int i) const { return i < s.size() ? s[i] : 0; }
  char charAt(unsigned int i) const { return (*this)[i]; }
  String& operator+=(const String& o) { s += o.s; return *this; }
  String& operator+=(const char* c) { if (c) s += c; return *this; }
  String& operator+=(char c) { s += c; return *this; }
  unsigned char concat(const char* c) { if (c) s += c; return 1; }
  void reserve(unsigned int n) { s.reserve(n); }
  void trim() {
    size_t b = 0, e = s.size();
    while (b < e && isspace(static_cast<unsigned char>(s[b]))) b++;
    while (e > b && isspace(static_cast<unsigned char>(s[e - 1]))) e--;
    s = s.substr(b, e - b);
  }
  void toUpperCase() { for (auto& c : s) c = static_cast<char>(toupper(static_cast<unsigned char>(c))); }
  void toLowerCase() { for (auto& c : s) c = static_cast<char>(tolower(static_cast<unsigned char>(c))); }
  int indexOf(char c, unsigned int from = 0) const { const size_t r = s.find(c, from); return r == std::string::npos ? -1 : static_cast<int>(r); }
  int indexOf(const String& o, unsigned int from = 0) const { const size_t r = s.find(o.s, from); return r == std::string::npos ? -1 : static_cast<int>(r); }
  String substring(unsigned int b) const { return b >= s.size() ? String("") : String(s.substr(b).c_str()); }
  String substring(unsigned int b, unsigned int e) const {
    if (b >= s.size() || e <= b) return String("");
    return String(s.substr(b, e - b).c_str());
  }
  bool startsWith(const String& p) const { return s.size() >= p.s.size() && s.compare(0, p.s.size(), p.s) == 0; }
  bool endsWith(const String& p) const { return s.size() >= p.s.size() && s.compare(s.size() - p.s.size(), p.s.size(), p.s) == 0; }
  void remove(unsigned int idx) { if (idx < s.size()) s.erase(idx); }
  void remove(unsigned int idx, unsigned int count) { if (idx < s.size()) s.erase(idx, count); }
  long toInt() const { return atol(s.c_str()); }
  bool equals(const String& o) const { return s == o.s; }
  bool operator==(const String& o) const { return s == o.s; }
  bool operator==(const char* c) const { return s == (c ? c : ""); }
  bool operator!=(const String& o) const { return s != o.s; }
  bool operator!=(const char* c) const { return s != (c ? c : ""); }
  bool operator<(const String& o) const { return s < o.s; }
  // ArduinoJson: String girdisi (IteratorReader: const_iterator + begin/end) ve std::string benzeri yazici gereksinimleri
  typedef std::string::const_iterator const_iterator;
  const_iterator begin() const { return s.begin(); }
  const_iterator end() const { return s.end(); }
  void push_back(char c) { s.push_back(c); }
  String& append(const char* c, size_t n) { s.append(c, n); return *this; }
  String& append(const char* c) { s.append(c); return *this; }
  void clear() { s.clear(); }
};
inline String operator+(const String& a, const String& b) { String r(a); r += b; return r; }
inline String operator+(const String& a, const char* b) { String r(a); r += b; return r; }
inline String operator+(const char* a, const String& b) { String r(a); r += b; return r; }
inline bool operator==(const char* a, const String& b) { return b == a; }

// ---- Serial: yazilanlari yakalar (testler Serial.all'da sir sizintisi arar) ---------------------------------------------------
struct FakeSerialT {
  std::string all;       // clear() ile silinir
  std::string history;   // HICBIR ZAMAN silinmez (sir sizintisi taramasi icin)
  std::string cur;
  std::vector<std::string> lines;
  size_t print(const char* c) { if (c) { cur += c; all += c; history += c; return strlen(c); } return 0; }
  size_t print(const String& v) { return print(v.c_str()); }
  size_t print(char c) { cur += c; all += c; history += c; return 1; }
  size_t print(int v) { return print(std::to_string(v).c_str()); }
  size_t print(unsigned v) { return print(std::to_string(v).c_str()); }
  size_t print(long v) { return print(std::to_string(v).c_str()); }
  size_t print(unsigned long v) { return print(std::to_string(v).c_str()); }
  size_t print(long long v) { return print(std::to_string(v).c_str()); }
  size_t print(unsigned long long v) { return print(std::to_string(v).c_str()); }
  size_t println() { all += "\n"; lines.push_back(cur); cur.clear(); return 2; }
  template <class T> size_t println(const T& v) { print(v); return println(); }
  int available() { return 0; }
  int read() { return -1; }
  void begin(unsigned long) {}
  void clear() { all.clear(); cur.clear(); lines.clear(); }
  int count(const std::string& needle) const {
    int n = 0; size_t p = 0;
    while ((p = all.find(needle, p)) != std::string::npos) { n++; p += needle.size(); }
    return n;
  }
  bool has(const std::string& needle) const { return all.find(needle) != std::string::npos; }
  bool hist_has(const std::string& needle) const { return history.find(needle) != std::string::npos; }
};
inline FakeSerialT Serial;

// ---- ESP, HardwareSerial ------------------------------------------------------------------------------------------------------
struct FakeESP {
  uint64_t getEfuseMac() { return g_efuse_mac; }
  void restart() { g_restart_requested = true; }
  uint32_t getFreeHeap() { return 100000; }
};
inline FakeESP ESP;

class HardwareSerial {
 public:
  std::deque<uint8_t> rx;
  std::string tx;
  explicit HardwareSerial(int) {}
  void begin(unsigned long, uint32_t = 0, int8_t = -1, int8_t = -1) {}
  void end() {}
  int available() { return static_cast<int>(rx.size()); }
  int read() { if (rx.empty()) return -1; const int c = rx.front(); rx.pop_front(); return c; }
  size_t write(const uint8_t* b, size_t n) { tx.append(reinterpret_cast<const char*>(b), n); return n; }
  void flush() {}
  void setRxBufferSize(size_t) {}
  void feed(const std::string& v) { for (char c : v) rx.push_back(static_cast<uint8_t>(c)); }
};

// ---- FreeRTOS kritik bolge (role_kontrol.h) -------------------------------------------------------------------------------------
typedef int portMUX_TYPE;
#define portMUX_INITIALIZER_UNLOCKED 0
#define portENTER_CRITICAL(m) ((void)(m))
#define portEXIT_CRITICAL(m) ((void)(m))

// ---- Print / Stream (ota_guncelleme.h OtaHashStream tabani) ---------------------------------------------------------------------
class Print {
 public:
  virtual ~Print() {}
  virtual size_t write(uint8_t) = 0;
  virtual size_t write(const uint8_t* buf, size_t size) { size_t n = 0; while (size--) n += write(*buf++); return n; }
};
class Stream : public Print {
 public:
  virtual int available() = 0;
  virtual int read() = 0;
  virtual int peek() = 0;
  virtual void flush() = 0;
};
