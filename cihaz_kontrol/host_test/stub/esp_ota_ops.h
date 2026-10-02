#pragma once
#include <Arduino.h>
#include <esp_timer.h>   // esp_err_t / ESP_OK

typedef struct { char label[17]; size_t size; } esp_partition_t;
typedef enum { ESP_OTA_IMG_NEW = 0, ESP_OTA_IMG_PENDING_VERIFY = 1, ESP_OTA_IMG_VALID = 2, ESP_OTA_IMG_INVALID = 3, ESP_OTA_IMG_ABORTED = 4, ESP_OTA_IMG_UNDEFINED = -1 } esp_ota_img_states_t;
inline esp_ota_img_states_t g_img_state = ESP_OTA_IMG_VALID;
inline esp_partition_t g_part_run = {"app0", 0x1E0000};
inline esp_partition_t g_part_next = {"app1", 0x1E0000};
inline bool g_no_update_partition = false;
inline const esp_partition_t* esp_ota_get_running_partition() { return &g_part_run; }
inline const esp_partition_t* esp_ota_get_next_update_partition(const esp_partition_t*) { return g_no_update_partition ? nullptr : &g_part_next; }
inline esp_err_t esp_ota_get_state_partition(const esp_partition_t*, esp_ota_img_states_t* s) { *s = g_img_state; return ESP_OK; }
inline esp_err_t esp_ota_mark_app_valid_cancel_rollback() { g_img_state = ESP_OTA_IMG_VALID; return ESP_OK; }
inline void esp_restart() { g_restart_requested = true; }
