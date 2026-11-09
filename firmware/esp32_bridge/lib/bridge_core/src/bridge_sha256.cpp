// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_sha256.h"

#include <cstring>

namespace bridge {

namespace {

// First 32 bits of the fractional parts of the cube roots of the first 64
// primes (FIPS 180-4, section 4.2.2).
const uint32_t kRound[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
    0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
    0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
    0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
    0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
    0xc67178f2};

inline uint32_t rotr(uint32_t x, unsigned n) { return (x >> n) | (x << (32u - n)); }

int hexNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

}  // namespace

void Sha256::reset() {
  // First 32 bits of the fractional parts of the square roots of the first 8
  // primes (section 5.3.3).
  h_[0] = 0x6a09e667;
  h_[1] = 0xbb67ae85;
  h_[2] = 0x3c6ef372;
  h_[3] = 0xa54ff53a;
  h_[4] = 0x510e527f;
  h_[5] = 0x9b05688c;
  h_[6] = 0x1f83d9ab;
  h_[7] = 0x5be0cd19;
  bufferLen_ = 0;
  totalBytes_ = 0;
}

void Sha256::compress(const uint8_t block[64]) {
  uint32_t w[64];
  for (int t = 0; t < 16; ++t) {
    w[t] = (static_cast<uint32_t>(block[4 * t]) << 24) |
           (static_cast<uint32_t>(block[4 * t + 1]) << 16) |
           (static_cast<uint32_t>(block[4 * t + 2]) << 8) | static_cast<uint32_t>(block[4 * t + 3]);
  }
  for (int t = 16; t < 64; ++t) {
    const uint32_t s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
    const uint32_t s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
    w[t] = w[t - 16] + s0 + w[t - 7] + s1;
  }
  uint32_t a = h_[0], b = h_[1], c = h_[2], d = h_[3];
  uint32_t e = h_[4], f = h_[5], g = h_[6], h = h_[7];
  for (int t = 0; t < 64; ++t) {
    const uint32_t bigS1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    const uint32_t ch = (e & f) ^ (~e & g);
    const uint32_t t1 = h + bigS1 + ch + kRound[t] + w[t];
    const uint32_t bigS0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    const uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    const uint32_t t2 = bigS0 + maj;
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }
  h_[0] += a;
  h_[1] += b;
  h_[2] += c;
  h_[3] += d;
  h_[4] += e;
  h_[5] += f;
  h_[6] += g;
  h_[7] += h;
}

void Sha256::update(const uint8_t* data, size_t len) {
  if (len == 0) return;
  totalBytes_ += len;
  if (bufferLen_ > 0) {
    const size_t take = (64 - bufferLen_ < len) ? 64 - bufferLen_ : len;
    std::memcpy(buffer_ + bufferLen_, data, take);
    bufferLen_ += take;
    data += take;
    len -= take;
    if (bufferLen_ == 64) {
      compress(buffer_);
      bufferLen_ = 0;
    }
  }
  while (len >= 64) {
    compress(data);
    data += 64;
    len -= 64;
  }
  if (len > 0) {
    std::memcpy(buffer_, data, len);
    bufferLen_ = len;
  }
}

void Sha256::finish(uint8_t digest[kDigestBytes]) {
  const uint64_t bitLength = totalBytes_ * 8;
  uint8_t pad[72] = {0x80};
  const size_t padLen = (bufferLen_ < 56) ? (56 - bufferLen_) : (120 - bufferLen_);
  for (int i = 0; i < 8; ++i) {
    pad[padLen + static_cast<size_t>(i)] = static_cast<uint8_t>(bitLength >> (56 - 8 * i));
  }
  // update() would count the padding in totalBytes_, which no longer matters.
  update(pad, padLen + 8);
  for (int i = 0; i < 8; ++i) {
    digest[4 * i] = static_cast<uint8_t>(h_[i] >> 24);
    digest[4 * i + 1] = static_cast<uint8_t>(h_[i] >> 16);
    digest[4 * i + 2] = static_cast<uint8_t>(h_[i] >> 8);
    digest[4 * i + 3] = static_cast<uint8_t>(h_[i]);
  }
  reset();
}

std::string Sha256::hexDigest(const uint8_t* data, size_t len) {
  Sha256 s;
  s.update(data, len);
  uint8_t d[kDigestBytes];
  s.finish(d);
  return toHex(d, sizeof d);
}

std::string toHex(const uint8_t* data, size_t len) {
  static const char kHex[] = "0123456789abcdef";
  std::string out;
  out.reserve(len * 2);
  for (size_t i = 0; i < len; ++i) {
    out += kHex[data[i] >> 4];
    out += kHex[data[i] & 0x0F];
  }
  return out;
}

bool fromHex(const std::string& hex, uint8_t* out, size_t len) {
  if (hex.size() != len * 2) return false;
  for (size_t i = 0; i < len; ++i) {
    const int hi = hexNibble(hex[2 * i]);
    const int lo = hexNibble(hex[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = static_cast<uint8_t>((hi << 4) | lo);
  }
  return true;
}

}  // namespace bridge
