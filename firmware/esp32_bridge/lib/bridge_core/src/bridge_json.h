// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// A small, bounded JSON reader and writer for the few request and response
// shapes of the bridge API.
//
// Reader is a validating pull parser over a caller-owned buffer:
//  * no recursion (skipValue uses an explicit, fixed-size stack),
//  * nesting depth capped at kMaxDepth,
//  * strings must be valid UTF-8, escapes and surrogate pairs are checked,
//  * integers saturate instead of overflowing,
//  * every access is bounds-checked, and errors are sticky.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace bridge {
namespace json {

constexpr size_t kMaxDepth = 16;
constexpr uint64_t kMaxMagnitude = 1000000000000000000ULL;  // 1e18, fits int64

enum class Error : uint8_t { None, Syntax, TooDeep, BadUtf8 };
enum class Type : uint8_t { Object, Array, String, Number, True, False, Null, Invalid };

const char* errorName(Error e);

struct Number {
  bool integer = false;    // no fraction and no exponent
  bool negative = false;
  bool saturated = false;  // magnitude hit kMaxMagnitude
  uint64_t magnitude = 0;  // meaningful when integer is true
  int64_t asInt64() const;
};

class Reader {
 public:
  // The reader does not copy: the buffer must outlive it.
  Reader(const char* data, size_t len);
  explicit Reader(const char* nulTerminated);
  explicit Reader(const std::string& text) : Reader(text.data(), text.size()) {}
  Reader(std::string&&) = delete;  // a temporary would leave the reader dangling

  bool ok() const { return error_ == Error::None; }
  Error error() const { return error_; }
  size_t errorOffset() const { return errorOffset_; }

  // Type of the next value, after skipping whitespace. Invalid at end of input
  // or on a character that cannot start a value. Does not set an error.
  Type peekType();
  // True when only whitespace remains.
  bool atEnd();
  // Sets a syntax error when anything but whitespace remains.
  bool expectEnd();

  // Objects: enterObject() consumes '{'. Each nextMember() call reads the next
  // key and ':' and returns true, or consumes '}' and returns false. The caller
  // must consume exactly one value per member. Keys longer than maxKeyBytes
  // come back as a single NUL byte, which never equals a real field name.
  bool enterObject();
  bool nextMember(std::string& key, size_t maxKeyBytes = 64);

  // Arrays: enterArray() consumes '['; nextElement() returns true before each
  // element and false after consuming ']'.
  bool enterArray();
  bool nextElement();

  // Reads a string. out may be null to discard it. When the decoded string
  // would exceed maxBytes, the rest is still validated but not stored, and
  // *truncated (if given) is set.
  bool readString(std::string* out, size_t maxBytes, bool* truncated);
  bool readNumber(Number& out);
  bool readBool(bool& out);
  bool readNull();
  // Validates and discards exactly one value of any type.
  bool skipValue();

 private:
  void fail(Error e);
  void skipWs();
  bool readHex4(uint32_t& out);
  bool readMemberKey(std::string* key, size_t maxKeyBytes);

  const char* p_;
  size_t len_;
  size_t pos_ = 0;
  Error error_ = Error::None;
  size_t errorOffset_ = 0;
  size_t depth_ = 0;
  bool isObject_[kMaxDepth] = {};
  bool first_[kMaxDepth] = {};
};

// True when [data, data+len) holds exactly one JSON value plus optional
// surrounding whitespace.
Error validate(const char* data, size_t len);
inline bool isValid(const std::string& text) {
  return validate(text.data(), text.size()) == Error::None;
}

// UTF-8 helpers (RFC 3629: no overlongs, no surrogates, max U+10FFFF).
bool isValidUtf8(const char* data, size_t len);
size_t countCodePoints(const std::string& utf8);  // assumes valid UTF-8

// Appends s as a quoted JSON string. Invalid UTF-8 bytes become U+FFFD.
void appendQuoted(std::string& out, const char* s, size_t len);

class Writer {
 public:
  explicit Writer(std::string& out) : out_(out) {}
  Writer& beginObject();
  Writer& endObject();
  Writer& beginArray();
  Writer& endArray();
  Writer& key(const char* name);
  Writer& str(const std::string& value);
  Writer& str(const char* value);
  Writer& num(int64_t value);
  Writer& unum(uint64_t value);
  Writer& boolean(bool value);
  Writer& null();

 private:
  void prefix();
  void push();
  void pop();

  std::string& out_;
  size_t depth_ = 0;
  bool hasItem_[kMaxDepth] = {};
  bool afterKey_ = false;
};

}  // namespace json
}  // namespace bridge
