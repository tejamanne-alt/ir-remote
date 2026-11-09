// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Pin map and hardware constants. Keep in sync with README.md ("Pin map").
#pragma once

#include <cstdint>

namespace board {

// IR LED driver: GPIO -> 470 ohm -> NPN base (see README for the circuit).
constexpr uint8_t kIrLedPin = 4;
// TSOP38238-class receiver output (active low). GPIO34 is input-only and has
// no boot-time output, so it never fights the receiver's output stage.
constexpr uint8_t kIrReceiverPin = 34;
// BOOT button on every ESP32 dev board (active low, pulled up on the board).
constexpr uint8_t kBootButtonPin = 0;
// Status LED (on-board LED of most DevKit V1 boards; add one on DevKitC).
constexpr uint8_t kStatusLedPin = 2;
constexpr bool kStatusLedActiveHigh = true;

// Carrier duty cycle in percent. Most consumer remotes use about 1/3.
constexpr uint8_t kIrDutyPercent = 33;

// Receiver: room for kMaxDurations marks/spaces plus the leading gap.
constexpr uint16_t kCaptureBufferEntries = 1025;
// A capture ends after this much silence (contract: 100 ms). IRremoteESP8266
// allows up to 130 ms here.
constexpr uint8_t kCaptureTimeoutMs = 100;
// Unknown-protocol captures shorter than this many entries are treated as
// noise and dropped by the decoder.
constexpr uint16_t kMinUnknownEntries = 12;

// Restart this long after a reply that announces a restart (OTA, setup).
constexpr uint32_t kRestartDelayMs = 1500;

}  // namespace board
