// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// SHA-256 (FIPS 180-4), written from the specification. Used to verify OTA
// images against the X-Firmware-SHA256 header before the boot partition is
// switched. Portable so the OTA path can be tested on the host.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace bridge {

class Sha256 {
 public:
  static constexpr size_t kDigestBytes = 32;

  Sha256() { reset(); }
  void reset();
  void update(const uint8_t* data, size_t len);
  void finish(uint8_t digest[kDigestBytes]);

  // Convenience: lowercase hex digest of a buffer.
  static std::string hexDigest(const uint8_t* data, size_t len);

 private:
  void compress(const uint8_t block[64]);

  uint32_t h_[8];
  uint8_t buffer_[64];
  size_t bufferLen_ = 0;
  uint64_t totalBytes_ = 0;
};

// Lowercase hex of bytes.
std::string toHex(const uint8_t* data, size_t len);
// Parses exactly 2*len hex characters (either case) into out. False on any
// other input.
bool fromHex(const std::string& hex, uint8_t* out, size_t len);

}  // namespace bridge
