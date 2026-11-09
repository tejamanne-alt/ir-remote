// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Request body parsing and validation for the JSON routes, and the WebSocket
// capture message.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "bridge_config.h"

namespace bridge {

// Outcome of parsing a body. status == 0 means success.
struct ApiError {
  int status = 0;
  const char* code = nullptr;
  std::string detail;
  bool ok() const { return status == 0; }
};

struct SendRawJob {
  uint32_t carrierHz = 0;
  std::vector<uint32_t> durationsUs;  // mark first, odd count
  uint64_t totalUs = 0;
};

// POST /v1/send/raw: {"carrierHz": int, "durationsUs": [int, ...]}.
// Errors, in order of precedence: bad_json (syntax, wrong type, missing or
// duplicate field), too_large (more than kMaxDurations values),
// invalid_durations (empty, even count, value outside 1..150000, total over
// kMaxPatternUs), carrier_out_of_range.
ApiError parseSendRaw(const std::string& body, SendRawJob& job);

// POST /v1/pair: {"client": "<1..32 characters>"}.
ApiError parsePair(const std::string& body, std::string& client);

// POST /v1/learn: {"timeoutMs": int}. An empty body or a missing field means
// kDefaultLearnTimeoutMs; 0 means capture mode.
ApiError parseLearn(const std::string& body, uint32_t& timeoutMs);

// POST /v1/send/ac: checks only that the body is a JSON object (v1 firmware
// has no AC encoders, so the route answers 501 after this check).
ApiError parseSendAc(const std::string& body);

struct DecodedSignal {
  std::string protocol;        // empty: the firmware did not recognise it
  uint16_t bits = 0;
  uint64_t value = 0;          // protocols up to 64 bits
  std::vector<uint8_t> state;  // multi-byte protocols (e.g. A/C); overrides value
};

struct Capture {
  std::vector<uint32_t> durationsUs;  // mark first, leading gap already dropped
  uint32_t carrierHz = 0;             // 0: unknown (demodulating receiver) -> null
  DecodedSignal decoded;
  uint64_t atMs = 0;  // milliseconds since boot
};

// "0x" + uppercase hex. value is padded to ceil(bits / 4) digits; state bytes
// are printed in order, two digits each.
std::string formatDecodedValue(const DecodedSignal& decoded);

// {"type":"capture",...}. Trims the capture to an odd count of at most
// kMaxDurations values and clamps each to 1..kMaxDurationUs, so it can be
// sent back through /v1/send/raw. Returns an empty string for an empty capture.
std::string buildCaptureMessage(const Capture& capture);

std::string buildLearnTimeoutMessage();
std::string buildLearnStoppedMessage();

}  // namespace bridge
