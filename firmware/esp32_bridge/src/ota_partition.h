// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// bridge::OtaTarget over the ESP-IDF OTA API (esp_ota_ops.h, Apache-2.0).
#pragma once

#include <esp_ota_ops.h>

#include "bridge_core.h"

class EspOtaTarget : public bridge::OtaTarget {
 public:
  size_t capacityBytes() override;
  bool begin(size_t imageBytes) override;
  bool write(const uint8_t* data, size_t len) override;
  bool finalize() override;
  bool activate() override;
  void abort() override;

 private:
  const esp_partition_t* partition_ = nullptr;
  esp_ota_handle_t handle_ = 0;
  bool open_ = false;
};
