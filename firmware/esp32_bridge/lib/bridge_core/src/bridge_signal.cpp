// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_signal.h"

#include "bridge_auth.h"
#include "bridge_http.h"
#include "bridge_json.h"

namespace bridge {

namespace {

ApiError makeError(int status, const char* code, std::string detail) {
  ApiError e;
  e.status = status;
  e.code = code;
  e.detail = std::move(detail);
  return e;
}

ApiError badJson(std::string detail) { return makeError(400, err::kBadJson, std::move(detail)); }

ApiError syntaxError(const json::Reader& r) {
  return badJson(std::string("body is not valid JSON (") + json::errorName(r.error()) +
                 " at byte " + std::to_string(r.errorOffset()) + ")");
}

// The value at the cursor has the wrong type. Skip it first so that a body
// that is not JSON at all is reported as such.
ApiError typeError(json::Reader& r, const char* detail) {
  if (!r.skipValue()) return syntaxError(r);
  return badJson(detail);
}

// Opens the top-level object, or explains why the body is not one.
bool openObject(json::Reader& r, ApiError& error) {
  if (r.peekType() == json::Type::Object) return r.enterObject();
  if (r.atEnd()) {
    error = badJson("body is empty; expected a JSON object");
    return false;
  }
  json::Reader whole = r;  // a copy, still positioned at the first value
  error = (whole.skipValue() && whole.expectEnd()) ? badJson("body must be a JSON object")
                                                    : syntaxError(whole);
  return false;
}

ApiError finishObject(json::Reader& r) {
  if (!r.ok() || !r.expectEnd()) return syntaxError(r);
  return ApiError();
}

bool readInteger(json::Reader& r, int64_t& out, const char* field, ApiError& error) {
  const std::string typeMsg = std::string(field) + " must be an integer";
  if (r.peekType() != json::Type::Number) {
    error = typeError(r, typeMsg.c_str());
    return false;
  }
  json::Number n;
  if (!r.readNumber(n)) {
    error = syntaxError(r);
    return false;
  }
  if (!n.integer) {
    error = badJson(typeMsg);
    return false;
  }
  out = n.asInt64();
  return true;
}

bool isBlank(const std::string& s) {
  for (char c : s) {
    if (c != ' ' && c != '\t' && c != '\r' && c != '\n') return false;
  }
  return true;
}

}  // namespace

ApiError parseSendRaw(const std::string& body, SendRawJob& job) {
  job = SendRawJob();
  json::Reader r(body);
  ApiError error;
  if (!openObject(r, error)) return error;

  bool haveCarrier = false;
  bool haveDurations = false;
  int64_t carrier = 0;
  std::vector<int64_t> values;
  size_t count = 0;
  std::string key;
  while (r.nextMember(key)) {
    if (key == "carrierHz") {
      if (haveCarrier) return badJson("duplicate field carrierHz");
      haveCarrier = true;
      if (!readInteger(r, carrier, "carrierHz", error)) return error;
    } else if (key == "durationsUs") {
      if (haveDurations) return badJson("duplicate field durationsUs");
      haveDurations = true;
      if (r.peekType() != json::Type::Array) {
        return typeError(r, "durationsUs must be an array of integers");
      }
      r.enterArray();
      while (r.nextElement()) {
        int64_t v = 0;
        if (r.peekType() != json::Type::Number) {
          return typeError(r, "durationsUs must contain only integers");
        }
        if (!readInteger(r, v, "each durationsUs value", error)) return error;
        ++count;
        if (count <= kMaxDurations) values.push_back(v);
      }
      if (!r.ok()) return syntaxError(r);
    } else if (!r.skipValue()) {
      return syntaxError(r);
    }
  }
  error = finishObject(r);
  if (!error.ok()) return error;

  if (!haveCarrier) return badJson("carrierHz is required");
  if (!haveDurations) return badJson("durationsUs is required");
  if (count > kMaxDurations) {
    return makeError(413, err::kTooLarge,
                     "durationsUs has " + std::to_string(count) + " values; the limit is " +
                         std::to_string(kMaxDurations));
  }
  if (count == 0) return makeError(400, err::kInvalidDurations, "durationsUs is empty");
  if (count % 2 == 0) {
    return makeError(400, err::kInvalidDurations,
                     "durationsUs must have an odd number of values (mark first and last), got " +
                         std::to_string(count));
  }
  uint64_t total = 0;
  for (size_t i = 0; i < values.size(); ++i) {
    const int64_t v = values[i];
    if (v < static_cast<int64_t>(kMinDurationUs) || v > static_cast<int64_t>(kMaxDurationUs)) {
      return makeError(400, err::kInvalidDurations,
                       "durationsUs[" + std::to_string(i) + "] = " +
                           std::to_string(static_cast<long long>(v)) + " is outside " +
                           std::to_string(kMinDurationUs) + ".." + std::to_string(kMaxDurationUs));
    }
    total += static_cast<uint64_t>(v);
  }
  if (total > kMaxPatternUs) {
    return makeError(400, err::kInvalidDurations,
                     "total duration " + std::to_string(total) + " us exceeds maxPatternUs " +
                         std::to_string(kMaxPatternUs));
  }
  if (carrier < static_cast<int64_t>(kCarrierMinHz) ||
      carrier > static_cast<int64_t>(kCarrierMaxHz)) {
    return makeError(400, err::kCarrierOutOfRange,
                     "carrierHz " + std::to_string(static_cast<long long>(carrier)) +
                         " is outside " + std::to_string(kCarrierMinHz) + ".." +
                         std::to_string(kCarrierMaxHz));
  }

  job.carrierHz = static_cast<uint32_t>(carrier);
  job.durationsUs.reserve(values.size());
  for (int64_t v : values) job.durationsUs.push_back(static_cast<uint32_t>(v));
  job.totalUs = total;
  return ApiError();
}

ApiError parsePair(const std::string& body, std::string& client) {
  client.clear();
  json::Reader r(body);
  ApiError error;
  if (!openObject(r, error)) return error;
  bool haveClient = false;
  std::string key;
  const char* kNameRule = "client must be a string of 1 to 32 characters without control characters";
  while (r.nextMember(key)) {
    if (key == "client") {
      if (haveClient) return badJson("duplicate field client");
      haveClient = true;
      if (r.peekType() != json::Type::String) return typeError(r, kNameRule);
      bool truncated = false;
      if (!r.readString(&client, kMaxClientNameChars * 4, &truncated)) return syntaxError(r);
      if (truncated || !isValidDisplayName(client, kMaxClientNameChars)) {
        // Keep validating the rest so malformed JSON still reads as bad_json.
        error = badJson(kNameRule);
      }
    } else if (!r.skipValue()) {
      return syntaxError(r);
    }
  }
  const ApiError tail = finishObject(r);
  if (!tail.ok()) return tail;
  if (!haveClient) return badJson("client is required");
  if (!error.ok()) {
    client.clear();
    return error;
  }
  return ApiError();
}

ApiError parseLearn(const std::string& body, uint32_t& timeoutMs) {
  timeoutMs = kDefaultLearnTimeoutMs;
  if (isBlank(body)) return ApiError();
  json::Reader r(body);
  ApiError error;
  if (!openObject(r, error)) return error;
  bool haveTimeout = false;
  int64_t value = kDefaultLearnTimeoutMs;
  std::string key;
  while (r.nextMember(key)) {
    if (key == "timeoutMs") {
      if (haveTimeout) return badJson("duplicate field timeoutMs");
      haveTimeout = true;
      if (!readInteger(r, value, "timeoutMs", error)) return error;
    } else if (!r.skipValue()) {
      return syntaxError(r);
    }
  }
  error = finishObject(r);
  if (!error.ok()) return error;
  if (value < 0 || value > static_cast<int64_t>(kMaxLearnTimeoutMs)) {
    return badJson("timeoutMs must be between 0 (capture mode) and " +
                   std::to_string(kMaxLearnTimeoutMs));
  }
  timeoutMs = static_cast<uint32_t>(value);
  return ApiError();
}

ApiError parseSendAc(const std::string& body) {
  json::Reader r(body);
  ApiError error;
  if (!openObject(r, error)) return error;
  std::string key;
  while (r.nextMember(key)) {
    if (!r.skipValue()) return syntaxError(r);
  }
  return finishObject(r);
}

std::string formatDecodedValue(const DecodedSignal& decoded) {
  static const char kHex[] = "0123456789ABCDEF";
  std::string out = "0x";
  if (!decoded.state.empty()) {
    for (uint8_t b : decoded.state) {
      out += kHex[b >> 4];
      out += kHex[b & 0x0F];
    }
    return out;
  }
  size_t digits = (static_cast<size_t>(decoded.bits) + 3) / 4;
  if (digits < 1) digits = 1;
  if (digits > 16) digits = 16;
  size_t needed = 1;
  for (uint64_t v = decoded.value >> 4; v != 0; v >>= 4) ++needed;
  const size_t n = digits > needed ? digits : needed;
  for (size_t i = n; i-- > 0;) {
    out += kHex[(decoded.value >> (4 * i)) & 0x0F];
  }
  return out;
}

std::string buildCaptureMessage(const Capture& capture) {
  size_t count = capture.durationsUs.size();
  if (count > kMaxDurations) count = kMaxDurations;
  if (count % 2 == 0 && count > 0) --count;  // drop a trailing space
  if (count == 0) return std::string();

  std::string out;
  out.reserve(64 + count * 7);
  json::Writer w(out);
  w.beginObject().key("type").str("capture").key("carrierHz");
  if (capture.carrierHz == 0) {
    w.null();
  } else {
    w.unum(capture.carrierHz);
  }
  w.key("durationsUs").beginArray();
  for (size_t i = 0; i < count; ++i) {
    uint32_t v = capture.durationsUs[i];
    if (v < kMinDurationUs) v = kMinDurationUs;
    if (v > kMaxDurationUs) v = kMaxDurationUs;
    w.unum(v);
  }
  w.endArray().key("decoded");
  if (capture.decoded.protocol.empty()) {
    w.null();
  } else {
    w.beginObject()
        .key("protocol")
        .str(capture.decoded.protocol)
        .key("value")
        .str(formatDecodedValue(capture.decoded))
        .key("bits")
        .unum(capture.decoded.bits)
        .endObject();
  }
  w.key("atMs").unum(capture.atMs).endObject();
  return out;
}

std::string buildLearnTimeoutMessage() { return "{\"type\":\"learn_timeout\"}"; }
std::string buildLearnStoppedMessage() { return "{\"type\":\"learn_stopped\"}"; }

}  // namespace bridge
