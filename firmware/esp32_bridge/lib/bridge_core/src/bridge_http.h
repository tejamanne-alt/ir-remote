// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Transport-neutral HTTP request/response types and the API error codes.
#pragma once

#include <cstdint>
#include <string>

namespace bridge {

enum class Method : uint8_t { Get, Head, Post, Put, Delete, Patch, Options, Other };

// Maps "GET", "post", ... to a Method; anything unknown is Method::Other.
Method parseMethod(const char* name);
const char* methodName(Method m);

struct Request {
  Method method = Method::Get;
  std::string path;           // without query string
  std::string authorization;  // Authorization header value, empty if absent
  std::string body;
  uint64_t contentLength = 0;  // declared Content-Length (0 if absent)
  bool bodyTruncated = false;  // the glue stopped buffering at kMaxBodyBytes
  bool webSocketUpgrade = false;
};

struct Response {
  int status = 200;
  std::string body;
  std::string allow;  // when non-empty, send an Allow header (405 responses)
  const char* contentType = "application/json";
};

// Error codes. The first block is the v1 contract; the second block covers
// cases the contract does not name (see README, "Contract notes").
namespace err {
constexpr const char* kBadJson = "bad_json";
constexpr const char* kInvalidDurations = "invalid_durations";
constexpr const char* kCarrierOutOfRange = "carrier_out_of_range";
constexpr const char* kUnauthorized = "unauthorized";
constexpr const char* kPairingWindowClosed = "pairing_window_closed";
constexpr const char* kNotFound = "not_found";
constexpr const char* kMethodNotAllowed = "method_not_allowed";
constexpr const char* kBusy = "busy";
constexpr const char* kTooLarge = "too_large";
constexpr const char* kNotImplemented = "not_implemented";
constexpr const char* kPairingFull = "pairing_full";

constexpr const char* kBadRequest = "bad_request";            // 400, OTA headers
constexpr const char* kHashMismatch = "hash_mismatch";        // 400, OTA digest
constexpr const char* kBadImage = "bad_image";                // 400, OTA image rejected
constexpr const char* kUpgradeRequired = "upgrade_required";  // 426, GET /v1/ws without upgrade
constexpr const char* kStorageError = "storage_error";        // 500, NVS write failed
constexpr const char* kOtaFailed = "ota_failed";              // 500, flash write failed
}  // namespace err

// {"error": code, "detail": detail}
Response errorResponse(int status, const char* code, const std::string& detail);

}  // namespace bridge
