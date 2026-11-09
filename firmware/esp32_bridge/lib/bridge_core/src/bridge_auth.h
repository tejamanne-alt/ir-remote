// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Bearer tokens: format checks, Authorization header parsing, the persistent
// token store (up to kMaxPairedClients), and its storage interface.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "bridge_config.h"

namespace bridge {

struct PairedClient {
  std::string token;   // 32 lowercase hex
  std::string client;  // device name sent at pairing, 1..32 characters
};

// Persistence for the token list (NVS on the device, memory in tests). The
// store hands over one opaque blob so the device can write it atomically.
class TokenStorage {
 public:
  virtual ~TokenStorage() = default;
  // Loads the blob; an absent record is an empty blob and still returns true.
  virtual bool loadBlob(std::string& out) = 0;
  virtual bool saveBlob(const std::string& blob) = 0;
};

// 32 lowercase hex characters.
bool isTokenFormat(const std::string& token);
std::string tokenFromBytes(const uint8_t bytes[kTokenBytes]);

// Extracts the token from "Bearer <token>" (scheme case-insensitive, any
// amount of spaces or tabs). Returns false for anything else.
bool parseBearer(const std::string& header, std::string& token);

// Client names and bridge names: valid UTF-8, 1..maxChars code points, no C0
// or C1 control characters and no DEL.
bool isValidDisplayName(const std::string& name, size_t maxChars);

// Compares equal-length strings without data-dependent early exit.
bool constantTimeEquals(const std::string& a, const std::string& b);

// Blob format: "irbtok1\n" then "<token>\t<client>\n" per client.
std::string serializeClients(const std::vector<PairedClient>& clients);
// Parses a blob, dropping malformed or duplicate records and anything past
// kMaxPairedClients. Returns false (and leaves out empty) when the header is
// wrong; an empty blob parses to an empty list.
bool parseClients(const std::string& blob, std::vector<PairedClient>& out);

class TokenStore {
 public:
  enum class AddResult : uint8_t { Added, Full, StorageError };

  explicit TokenStore(TokenStorage& storage) : storage_(storage) {}

  // Loads from storage. On failure the store starts empty and returns false.
  bool load();
  AddResult add(const PairedClient& client);
  // Constant-time across all slots and characters.
  bool contains(const std::string& token) const;
  // Forgets every token in memory, then persists. Returns false when the
  // empty list could not be written.
  bool clear();

  size_t size() const { return clients_.size(); }
  bool full() const { return clients_.size() >= kMaxPairedClients; }
  const std::vector<PairedClient>& clients() const { return clients_; }

 private:
  TokenStorage& storage_;
  std::vector<PairedClient> clients_;
};

}  // namespace bridge
