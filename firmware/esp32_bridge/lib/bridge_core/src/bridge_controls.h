// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Physical controls: BOOT button classification, the pairing window and
// status LED patterns. Time is always injected (milliseconds since boot as a
// 64-bit count, so it never wraps); nothing here reads a clock.
#pragma once

#include <cstdint>

#include "bridge_config.h"

namespace bridge {

// Elapsed milliseconds, robust against a clock that steps backwards.
inline uint64_t elapsedMs(uint64_t nowMs, uint64_t sinceMs) {
  return nowMs >= sinceMs ? nowMs - sinceMs : 0;
}

enum class ButtonEvent : uint8_t {
  None,
  ShortPress,         // released before kLongPressMs: opens the pairing window
  LongPress,          // held kLongPressMs: clears every token (fires while held)
  FactoryResetPress,  // held kFactoryResetPressMs: also forgets Wi-Fi (fires while held)
};

const char* buttonEventName(ButtonEvent e);

class ButtonTracker {
 public:
  ButtonTracker(uint32_t debounceMs = kDebounceMs, uint32_t longPressMs = kLongPressMs,
                uint32_t factoryResetMs = kFactoryResetPressMs)
      : debounceMs_(debounceMs), longPressMs_(longPressMs), factoryResetMs_(factoryResetMs) {}

  // rawPressed: the current pin reading (true = pressed). Call at least every
  // ~10 ms. Returns at most one event per call.
  ButtonEvent update(bool rawPressed, uint64_t nowMs);
  bool pressed() const { return stable_; }

 private:
  uint32_t debounceMs_;
  uint32_t longPressMs_;
  uint32_t factoryResetMs_;
  bool raw_ = false;
  uint64_t rawSinceMs_ = 0;
  bool stable_ = false;
  uint64_t pressedAtMs_ = 0;
  bool longFired_ = false;
  bool resetFired_ = false;
};

class PairingWindow {
 public:
  explicit PairingWindow(uint32_t durationMs = kPairingWindowMs) : durationMs_(durationMs) {}
  // Opens (or re-opens) the window for durationMs from now.
  void open(uint64_t nowMs) {
    open_ = true;
    openedAtMs_ = nowMs;
  }
  void close() { open_ = false; }
  bool isOpen(uint64_t nowMs) const {
    return open_ && elapsedMs(nowMs, openedAtMs_) < durationMs_;
  }
  void tick(uint64_t nowMs) {
    if (open_ && !isOpen(nowMs)) open_ = false;
  }
  uint64_t remainingMs(uint64_t nowMs) const {
    return isOpen(nowMs) ? durationMs_ - elapsedMs(nowMs, openedAtMs_) : 0;
  }

 private:
  uint32_t durationMs_;
  bool open_ = false;
  uint64_t openedAtMs_ = 0;
};

enum class LedPattern : uint8_t {
  Off,
  Solid,              // learn or capture mode is active
  PairingBlink,       // 2 Hz while the pairing window is open
  ClearedFlash,       // 10 Hz for 2 s after the tokens were cleared
  ProvisioningBlink,  // 0.5 Hz while the setup access point is up
  OfflineBlip,        // 100 ms flash every 2 s: credentials stored, not connected
};

// LED level for a pattern at a point in time.
bool ledLevel(LedPattern pattern, uint64_t nowMs);

}  // namespace bridge
