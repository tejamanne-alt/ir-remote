// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_controls.h"

namespace bridge {

const char* buttonEventName(ButtonEvent e) {
  switch (e) {
    case ButtonEvent::None: return "none";
    case ButtonEvent::ShortPress: return "short";
    case ButtonEvent::LongPress: return "long";
    case ButtonEvent::FactoryResetPress: return "factory-reset";
  }
  return "unknown";
}

ButtonEvent ButtonTracker::update(bool rawPressed, uint64_t nowMs) {
  if (rawPressed != raw_) {
    raw_ = rawPressed;
    rawSinceMs_ = nowMs;
  }
  if (raw_ != stable_ && elapsedMs(nowMs, rawSinceMs_) >= debounceMs_) {
    stable_ = raw_;
    if (stable_) {
      pressedAtMs_ = rawSinceMs_;
      longFired_ = false;
      resetFired_ = false;
    } else {
      return longFired_ ? ButtonEvent::None : ButtonEvent::ShortPress;
    }
  }
  // raw_ too: a release that is still being debounced must not turn into a
  // long press.
  if (stable_ && raw_) {
    const uint64_t held = elapsedMs(nowMs, pressedAtMs_);
    if (!longFired_ && held >= longPressMs_) {
      longFired_ = true;
      return ButtonEvent::LongPress;
    }
    if (longFired_ && !resetFired_ && held >= factoryResetMs_) {
      resetFired_ = true;
      return ButtonEvent::FactoryResetPress;
    }
  }
  return ButtonEvent::None;
}

bool ledLevel(LedPattern pattern, uint64_t nowMs) {
  switch (pattern) {
    case LedPattern::Off: return false;
    case LedPattern::Solid: return true;
    case LedPattern::PairingBlink: return (nowMs % 500) < 250;
    case LedPattern::ClearedFlash: return (nowMs % 100) < 50;
    case LedPattern::ProvisioningBlink: return (nowMs % 2000) < 1000;
    case LedPattern::OfflineBlip: return (nowMs % 2000) < 100;
    case LedPattern::StorageError: {
      const uint64_t t = nowMs % 1000;
      return t < 100 || (t >= 200 && t < 300);
    }
  }
  return false;
}

}  // namespace bridge
