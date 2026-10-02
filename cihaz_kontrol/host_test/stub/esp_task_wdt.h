#pragma once
#include <Arduino.h>
inline int g_wdt_resets = 0;
inline void esp_task_wdt_reset() { g_wdt_resets++; }
inline int esp_task_wdt_init(uint32_t, bool) { return 0; }
inline int esp_task_wdt_add(void*) { return 0; }
