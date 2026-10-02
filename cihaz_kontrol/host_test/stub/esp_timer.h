// Ana makine sahtesi: esp_timer. esp_timer_create HATA doner: role_kontrol.h roleTimer'i nullptr yapar ve ROLE birakmasi roleLoop()
// yedek yolundan (millis tabanli) yapilir; testler fake saati ilerletip roleLoop() cagirir.
#pragma once
#include <Arduino.h>

typedef int esp_err_t;
#define ESP_OK 0
#define ESP_FAIL -1
typedef void* esp_timer_handle_t;
#define ESP_TIMER_TASK 0
typedef struct {
  void (*callback)(void*);
  void* arg;
  int dispatch_method;
  const char* name;
} esp_timer_create_args_t;
inline esp_err_t esp_timer_create(const esp_timer_create_args_t*, esp_timer_handle_t*) { return ESP_FAIL; }
inline esp_err_t esp_timer_start_once(esp_timer_handle_t, uint64_t) { return ESP_FAIL; }
inline esp_err_t esp_timer_stop(esp_timer_handle_t) { return ESP_FAIL; }
