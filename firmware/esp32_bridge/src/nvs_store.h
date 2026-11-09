// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// NVS persistence (Arduino Preferences) for paired tokens and Wi-Fi settings.
#pragma once

#include <string>

#include "bridge_core.h"

namespace nvs_store {

// Token list as one blob in namespace "irb-auth", key "clients".
class TokenBlobStorage : public bridge::TokenStorage {
 public:
  bool loadBlob(std::string& out) override;
  bool saveBlob(const std::string& blob) override;
};

// Wi-Fi credentials and bridge name in namespace "irb-wifi".
bool loadWifi(bridge::WifiCredentials& out);
bool saveWifi(const bridge::WifiCredentials& credentials);
bool clearWifi();

}  // namespace nvs_store
