// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// IR hardware adapter over IRremoteESP8266 (LGPL-2.1): raw transmit with a
// carrier, and capture + decode from a demodulating 38 kHz receiver.
#pragma once

#include <cstdint>

#include "bridge_core.h"

namespace ir_io {

void begin();
// Blocks for the length of the pattern. The receiver is off meanwhile so the
// bridge does not capture its own transmission. Returns elapsed microseconds.
uint64_t transmit(const bridge::SendRawJob& job);
// True when a capture is ready; fills `out` (leading gap dropped).
bool poll(bridge::Capture& out, uint64_t nowMs);

}  // namespace ir_io
