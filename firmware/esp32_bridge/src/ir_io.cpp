// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "ir_io.h"

#include <Arduino.h>
#include <IRrecv.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <IRutils.h>
#include <esp_timer.h>

#include "board_config.h"

namespace ir_io {

namespace {

IRsend irSend(board::kIrLedPin);
// save_buffer = true: decode() copies the capture and re-arms the receiver at
// once, so the next frame is not lost while this one is being reported.
IRrecv irRecv(board::kIrReceiverPin, board::kCaptureBufferEntries, board::kCaptureTimeoutMs, true);
decode_results results;

}  // namespace

void begin() {
  irSend.begin();
#if DECODE_HASH
  irRecv.setUnknownThreshold(board::kMinUnknownEntries);
#endif
  irRecv.enableIRIn();
}

uint64_t transmit(const bridge::SendRawJob& job) {
  irRecv.disableIRIn();
  const int64_t start = esp_timer_get_time();
  irSend.enableIROut(job.carrierHz, board::kIrDutyPercent);
  for (size_t i = 0; i < job.durationsUs.size(); ++i) {
    uint32_t us = job.durationsUs[i];
    if (i % 2 == 0) {
      // IRsend::mark() takes 16 bits; back-to-back marks are one longer mark.
      while (us > 0) {
        const uint16_t chunk = us > 65535 ? 65535 : static_cast<uint16_t>(us);
        irSend.mark(chunk);
        us -= chunk;
      }
    } else {
      irSend.space(us);
    }
  }
  irSend.space(0);  // LED off
  const int64_t elapsed = esp_timer_get_time() - start;
  irRecv.enableIRIn();
  return elapsed > 0 ? static_cast<uint64_t>(elapsed) : 0;
}

bool poll(bridge::Capture& out, uint64_t nowMs) {
  if (!irRecv.decode(&results)) return false;
  out = bridge::Capture();
  out.atMs = nowMs;
  out.carrierHz = 0;  // a demodulating receiver cannot measure the carrier
  // rawbuf[0] is the silence before the capture; the contract drops it.
  out.durationsUs.reserve(results.rawlen > 0 ? results.rawlen - 1 : 0);
  for (uint16_t i = 1; i < results.rawlen; ++i) {
    out.durationsUs.push_back(static_cast<uint32_t>(results.rawbuf[i]) * kRawTick);
  }
  if (results.decode_type != UNKNOWN && !results.overflow) {
    out.decoded.protocol = typeToString(results.decode_type, false).c_str();
    out.decoded.bits = results.bits;
    if (hasACState(results.decode_type)) {
      const size_t bytes = results.bits / 8;
      for (size_t i = 0; i < bytes && i < kStateSizeMax; ++i) out.decoded.state.push_back(results.state[i]);
    } else {
      out.decoded.value = results.value;
    }
  }
  return true;
}

}  // namespace ir_io
