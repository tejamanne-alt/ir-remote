// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Streamed OTA update with SHA-256 verification (docs/ADR-ota.md).
// The image is hashed while it is written to the inactive partition; the
// boot partition is switched only after the digest matches.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "bridge_http.h"
#include "bridge_sha256.h"
#include "bridge_signal.h"

namespace bridge {

// The flash side of an update (esp_ota_* on the device, a fake in tests).
class OtaTarget {
 public:
  virtual ~OtaTarget() = default;
  // Largest image the inactive partition can hold.
  virtual size_t capacityBytes() = 0;
  virtual bool begin(size_t imageBytes) = 0;
  virtual bool write(const uint8_t* data, size_t len) = 0;
  // Completes the write and validates the image. Does not change the boot
  // partition. After false, the target has cleaned up.
  virtual bool finalize() = 0;
  // Selects the new image for the next boot.
  virtual bool activate() = 0;
  // Discards a partially written image. Safe to call when nothing is open.
  virtual void abort() = 0;
};

class OtaSession {
 public:
  enum class State : uint8_t { Idle, Receiving, Failed };

  // Validates the headers and opens the target. status 0 = accepted.
  ApiError begin(OtaTarget& target, const std::string& sha256Header, bool hasContentLength,
                 uint64_t contentLength);
  // Hashes and writes one chunk. Returns false once the session has failed;
  // the failure is reported by finish().
  bool write(const uint8_t* data, size_t len);
  // Verifies and commits, or reports the failure. Always returns to Idle.
  Response finish();
  // The client went away: discard everything.
  void abort();

  State state() const { return state_; }
  bool active() const { return state_ != State::Idle; }
  uint64_t receivedBytes() const { return received_; }

 private:
  void failWith(int status, const char* code, const std::string& detail);

  OtaTarget* target_ = nullptr;
  State state_ = State::Idle;
  uint64_t expected_ = 0;
  uint64_t received_ = 0;
  Sha256 hash_;
  uint8_t want_[Sha256::kDigestBytes] = {};
  Response failure_;
};

}  // namespace bridge
