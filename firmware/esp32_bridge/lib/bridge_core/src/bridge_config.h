// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Limits and constants of the bridge API v1 (docs/BRIDGE_API.md).
// Portable C++17: no Arduino or ESP-IDF headers in bridge_core.
#pragma once

#include <cstddef>
#include <cstdint>

#ifndef BRIDGE_FW_VERSION
#define BRIDGE_FW_VERSION "0.1.0"
#endif

namespace bridge {

constexpr int kApiVersion = 1;
constexpr const char* kFirmwareVersion = BRIDGE_FW_VERSION;
constexpr const char* kDefaultBridgeName = "IR Bridge";

// Transport limits.
constexpr size_t kMaxBodyBytes = 16 * 1024;

// Signal limits, also reported in GET /v1/info caps.
constexpr uint32_t kCarrierMinHz = 30000;
constexpr uint32_t kCarrierMaxHz = 60000;
constexpr uint32_t kMaxPatternUs = 4000000;
constexpr size_t kMaxDurations = 1024;
constexpr uint32_t kMinDurationUs = 1;
constexpr uint32_t kMaxDurationUs = 150000;

// Pairing.
constexpr size_t kMaxPairedClients = 8;
constexpr size_t kTokenBytes = 16;  // 128-bit tokens, 32 lowercase hex characters
constexpr size_t kTokenHexLength = kTokenBytes * 2;
constexpr size_t kMaxClientNameChars = 32;
constexpr uint32_t kPairingWindowMs = 60000;

// BOOT button timing.
constexpr uint32_t kDebounceMs = 30;
constexpr uint32_t kLongPressMs = 5000;          // clears every token
constexpr uint32_t kFactoryResetPressMs = 15000;  // also forgets Wi-Fi credentials

// Learn and capture.
constexpr uint32_t kDefaultLearnTimeoutMs = 15000;
constexpr uint32_t kMaxLearnTimeoutMs = 3600000;  // not in the contract; see README
constexpr uint32_t kCaptureSilenceMs = 100;

// Wi-Fi provisioning.
constexpr size_t kMaxBridgeNameChars = 32;
constexpr uint32_t kSetupPortalMs = 10u * 60u * 1000u;
constexpr uint32_t kOfflineBeforePortalMs = 10000;

constexpr uint16_t kHttpPort = 80;

}  // namespace bridge
