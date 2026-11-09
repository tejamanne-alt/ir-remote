// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_auth.h"

#include "bridge_json.h"

namespace bridge {

namespace {

const char kBlobHeader[] = "irbtok1\n";
constexpr size_t kBlobHeaderLen = sizeof(kBlobHeader) - 1;

inline bool isLowerHex(char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); }
inline bool isOws(char c) { return c == ' ' || c == '\t'; }
inline char asciiLower(char c) { return (c >= 'A' && c <= 'Z') ? static_cast<char>(c + 32) : c; }

}  // namespace

bool isTokenFormat(const std::string& token) {
  if (token.size() != kTokenHexLength) return false;
  for (char c : token) {
    if (!isLowerHex(c)) return false;
  }
  return true;
}

std::string tokenFromBytes(const uint8_t bytes[kTokenBytes]) {
  static const char kHex[] = "0123456789abcdef";
  std::string out;
  out.reserve(kTokenHexLength);
  for (size_t i = 0; i < kTokenBytes; ++i) {
    out += kHex[bytes[i] >> 4];
    out += kHex[bytes[i] & 0x0F];
  }
  return out;
}

bool parseBearer(const std::string& header, std::string& token) {
  token.clear();
  size_t i = 0;
  const size_t n = header.size();
  while (i < n && isOws(header[i])) ++i;
  static const char kScheme[] = "bearer";
  for (size_t k = 0; k < 6; ++k, ++i) {
    if (i >= n || asciiLower(header[i]) != kScheme[k]) return false;
  }
  if (i >= n || !isOws(header[i])) return false;
  while (i < n && isOws(header[i])) ++i;
  size_t end = n;
  while (end > i && isOws(header[end - 1])) --end;
  if (end <= i) return false;
  for (size_t k = i; k < end; ++k) {
    if (isOws(header[k])) return false;  // more than one credential word
  }
  token.assign(header, i, end - i);
  return true;
}

bool isValidDisplayName(const std::string& name, size_t maxChars) {
  if (name.empty()) return false;
  if (!json::isValidUtf8(name.data(), name.size())) return false;
  const size_t chars = json::countCodePoints(name);
  if (chars == 0 || chars > maxChars) return false;
  for (size_t i = 0; i < name.size(); ++i) {
    const unsigned char c = static_cast<unsigned char>(name[i]);
    if (c < 0x20 || c == 0x7F) return false;
    // U+0080..U+009F are encoded as C2 80..C2 9F.
    if (c == 0xC2 && i + 1 < name.size()) {
      const unsigned char d = static_cast<unsigned char>(name[i + 1]);
      if (d >= 0x80 && d <= 0x9F) return false;
    }
  }
  return true;
}

bool constantTimeEquals(const std::string& a, const std::string& b) {
  if (a.size() != b.size()) return false;
  unsigned char diff = 0;
  for (size_t i = 0; i < a.size(); ++i) {
    diff = static_cast<unsigned char>(diff | (static_cast<unsigned char>(a[i]) ^
                                              static_cast<unsigned char>(b[i])));
  }
  return diff == 0;
}

std::string serializeClients(const std::vector<PairedClient>& clients) {
  std::string out(kBlobHeader);
  for (const PairedClient& c : clients) {
    out += c.token;
    out += '\t';
    out += c.client;
    out += '\n';
  }
  return out;
}

bool parseClients(const std::string& blob, std::vector<PairedClient>& out) {
  out.clear();
  if (blob.empty()) return true;
  if (blob.compare(0, kBlobHeaderLen, kBlobHeader) != 0) return false;
  size_t pos = kBlobHeaderLen;
  while (pos < blob.size() && out.size() < kMaxPairedClients) {
    size_t eol = blob.find('\n', pos);
    if (eol == std::string::npos) eol = blob.size();
    const std::string line = blob.substr(pos, eol - pos);
    pos = eol + 1;
    const size_t tab = line.find('\t');
    if (tab == std::string::npos) continue;
    PairedClient c;
    c.token = line.substr(0, tab);
    c.client = line.substr(tab + 1);
    if (!isTokenFormat(c.token) || !isValidDisplayName(c.client, kMaxClientNameChars)) continue;
    bool duplicate = false;
    for (const PairedClient& existing : out) {
      if (existing.token == c.token) duplicate = true;
    }
    if (!duplicate) out.push_back(c);
  }
  return true;
}

bool TokenStore::load() {
  clients_.clear();
  std::string blob;
  if (!storage_.loadBlob(blob)) return false;
  return parseClients(blob, clients_);
}

TokenStore::AddResult TokenStore::add(const PairedClient& client) {
  if (full()) return AddResult::Full;
  clients_.push_back(client);
  if (!storage_.saveBlob(serializeClients(clients_))) {
    clients_.pop_back();
    return AddResult::StorageError;
  }
  return AddResult::Added;
}

bool TokenStore::contains(const std::string& token) const {
  if (!isTokenFormat(token)) return false;
  // Compare against every slot, used or not, so timing does not reveal how
  // many clients are paired or which slot matched.
  static const std::string kUnused(kTokenHexLength, 'x');  // never a valid token
  bool found = false;
  for (size_t i = 0; i < kMaxPairedClients; ++i) {
    const std::string& candidate = (i < clients_.size()) ? clients_[i].token : kUnused;
    found = constantTimeEquals(candidate, token) || found;
  }
  return found;
}

bool TokenStore::clear() {
  clients_.clear();
  return persist();
}

bool TokenStore::persist() { return storage_.saveBlob(serializeClients(clients_)); }

}  // namespace bridge
