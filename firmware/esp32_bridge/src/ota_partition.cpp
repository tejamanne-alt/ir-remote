// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "ota_partition.h"

#include <esp_log.h>

static const char* kTag = "ota";

size_t EspOtaTarget::capacityBytes() {
  const esp_partition_t* p = esp_ota_get_next_update_partition(nullptr);
  return p ? p->size : 0;
}

bool EspOtaTarget::begin(size_t imageBytes) {
  (void)imageBytes;  // only logged; sequential writes need no size up front
  abort();
  partition_ = esp_ota_get_next_update_partition(nullptr);
  if (partition_ == nullptr) return false;
  // Erase sector by sector while writing, instead of erasing the whole image
  // up front, which would block the network task for seconds.
  const esp_err_t err = esp_ota_begin(partition_, OTA_WITH_SEQUENTIAL_WRITES, &handle_);
  if (err != ESP_OK) {
    ESP_LOGE(kTag, "esp_ota_begin(%u bytes): %s", static_cast<unsigned>(imageBytes),
             esp_err_to_name(err));
    return false;
  }
  open_ = true;
  return true;
}

bool EspOtaTarget::write(const uint8_t* data, size_t len) {
  if (!open_) return false;
  const esp_err_t err = esp_ota_write(handle_, data, len);
  if (err != ESP_OK) ESP_LOGE(kTag, "esp_ota_write: %s", esp_err_to_name(err));
  return err == ESP_OK;
}

bool EspOtaTarget::finalize() {
  if (!open_) return false;
  open_ = false;
  // Validates the image (header, segments, checksum/appended digest). It does
  // not touch the boot partition.
  const esp_err_t err = esp_ota_end(handle_);
  if (err != ESP_OK) ESP_LOGE(kTag, "esp_ota_end: %s", esp_err_to_name(err));
  return err == ESP_OK;
}

bool EspOtaTarget::activate() {
  if (partition_ == nullptr) return false;
  const esp_err_t err = esp_ota_set_boot_partition(partition_);
  if (err != ESP_OK) ESP_LOGE(kTag, "esp_ota_set_boot_partition: %s", esp_err_to_name(err));
  return err == ESP_OK;
}

void EspOtaTarget::abort() {
  if (open_) {
    esp_ota_abort(handle_);
    open_ = false;
  }
}
