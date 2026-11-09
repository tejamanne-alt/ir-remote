// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_json.h"

#include <cstring>

namespace bridge {
namespace json {

namespace {

inline bool isWs(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
inline bool isDigit(char c) { return c >= '0' && c <= '9'; }

int hexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

inline bool isCont(unsigned char c) { return (c & 0xC0) == 0x80; }

// Length (1..4) of the valid UTF-8 sequence starting at p, or 0 when invalid.
size_t utf8SequenceLength(const unsigned char* p, size_t avail) {
  if (avail == 0) return 0;
  const unsigned char c = p[0];
  if (c < 0x80) return 1;
  if (c >= 0xC2 && c <= 0xDF) {
    return (avail >= 2 && isCont(p[1])) ? 2 : 0;
  }
  if (c >= 0xE0 && c <= 0xEF) {
    if (avail < 3 || !isCont(p[1]) || !isCont(p[2])) return 0;
    if (c == 0xE0 && p[1] < 0xA0) return 0;  // overlong
    if (c == 0xED && p[1] > 0x9F) return 0;  // UTF-16 surrogate
    return 3;
  }
  if (c >= 0xF0 && c <= 0xF4) {
    if (avail < 4 || !isCont(p[1]) || !isCont(p[2]) || !isCont(p[3])) return 0;
    if (c == 0xF0 && p[1] < 0x90) return 0;  // overlong
    if (c == 0xF4 && p[1] > 0x8F) return 0;  // above U+10FFFF
    return 4;
  }
  return 0;
}

size_t encodeUtf8(uint32_t cp, char out[4]) {
  if (cp < 0x80) {
    out[0] = static_cast<char>(cp);
    return 1;
  }
  if (cp < 0x800) {
    out[0] = static_cast<char>(0xC0 | (cp >> 6));
    out[1] = static_cast<char>(0x80 | (cp & 0x3F));
    return 2;
  }
  if (cp < 0x10000) {
    out[0] = static_cast<char>(0xE0 | (cp >> 12));
    out[1] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
    out[2] = static_cast<char>(0x80 | (cp & 0x3F));
    return 3;
  }
  out[0] = static_cast<char>(0xF0 | (cp >> 18));
  out[1] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
  out[2] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
  out[3] = static_cast<char>(0x80 | (cp & 0x3F));
  return 4;
}

}  // namespace

const char* errorName(Error e) {
  switch (e) {
    case Error::None: return "none";
    case Error::Syntax: return "syntax error";
    case Error::TooDeep: return "nesting too deep";
    case Error::BadUtf8: return "invalid UTF-8";
  }
  return "unknown";
}

int64_t Number::asInt64() const {
  // magnitude never exceeds kMaxMagnitude, so the cast cannot overflow.
  const int64_t m = static_cast<int64_t>(magnitude);
  return negative ? -m : m;
}

Reader::Reader(const char* data, size_t len) : p_(data), len_(data ? len : 0) {}

Reader::Reader(const char* nulTerminated)
    : Reader(nulTerminated, nulTerminated ? std::strlen(nulTerminated) : 0) {}

void Reader::fail(Error e) {
  if (error_ == Error::None) {
    error_ = e;
    errorOffset_ = pos_;
  }
}

void Reader::skipWs() {
  while (pos_ < len_ && isWs(p_[pos_])) ++pos_;
}

Type Reader::peekType() {
  if (!ok()) return Type::Invalid;
  skipWs();
  if (pos_ >= len_) return Type::Invalid;
  const char c = p_[pos_];
  switch (c) {
    case '{': return Type::Object;
    case '[': return Type::Array;
    case '"': return Type::String;
    case 't': return Type::True;
    case 'f': return Type::False;
    case 'n': return Type::Null;
    default: break;
  }
  if (c == '-' || isDigit(c)) return Type::Number;
  return Type::Invalid;
}

bool Reader::atEnd() {
  skipWs();
  return pos_ >= len_;
}

bool Reader::expectEnd() {
  if (!ok()) return false;
  if (!atEnd()) {
    fail(Error::Syntax);
    return false;
  }
  return true;
}

bool Reader::enterObject() {
  if (!ok()) return false;
  skipWs();
  if (pos_ >= len_ || p_[pos_] != '{') {
    fail(Error::Syntax);
    return false;
  }
  if (depth_ >= kMaxDepth) {
    fail(Error::TooDeep);
    return false;
  }
  ++pos_;
  isObject_[depth_] = true;
  first_[depth_] = true;
  ++depth_;
  return true;
}

bool Reader::enterArray() {
  if (!ok()) return false;
  skipWs();
  if (pos_ >= len_ || p_[pos_] != '[') {
    fail(Error::Syntax);
    return false;
  }
  if (depth_ >= kMaxDepth) {
    fail(Error::TooDeep);
    return false;
  }
  ++pos_;
  isObject_[depth_] = false;
  first_[depth_] = true;
  ++depth_;
  return true;
}

bool Reader::readMemberKey(std::string* key, size_t maxKeyBytes) {
  bool truncated = false;
  if (!readString(key, maxKeyBytes, &truncated)) return false;
  if (truncated && key) key->assign(1, '\0');
  skipWs();
  if (pos_ >= len_ || p_[pos_] != ':') {
    fail(Error::Syntax);
    return false;
  }
  ++pos_;
  return true;
}

bool Reader::nextMember(std::string& key, size_t maxKeyBytes) {
  if (!ok()) return false;
  if (depth_ == 0 || !isObject_[depth_ - 1]) {
    fail(Error::Syntax);
    return false;
  }
  skipWs();
  if (pos_ >= len_) {
    fail(Error::Syntax);
    return false;
  }
  if (p_[pos_] == '}') {
    ++pos_;
    --depth_;
    return false;
  }
  bool& first = first_[depth_ - 1];
  if (!first) {
    if (p_[pos_] != ',') {
      fail(Error::Syntax);
      return false;
    }
    ++pos_;
  }
  first = false;
  return readMemberKey(&key, maxKeyBytes);
}

bool Reader::nextElement() {
  if (!ok()) return false;
  if (depth_ == 0 || isObject_[depth_ - 1]) {
    fail(Error::Syntax);
    return false;
  }
  skipWs();
  if (pos_ >= len_) {
    fail(Error::Syntax);
    return false;
  }
  if (p_[pos_] == ']') {
    ++pos_;
    --depth_;
    return false;  // end of array
  }
  bool& first = first_[depth_ - 1];
  if (!first) {
    if (p_[pos_] != ',') {
      fail(Error::Syntax);
      return false;
    }
    ++pos_;
  }
  first = false;
  return true;
}

bool Reader::readHex4(uint32_t& out) {
  if (len_ - pos_ < 4) {
    fail(Error::Syntax);
    return false;
  }
  uint32_t v = 0;
  for (int i = 0; i < 4; ++i) {
    const int h = hexValue(p_[pos_ + static_cast<size_t>(i)]);
    if (h < 0) {
      fail(Error::Syntax);
      return false;
    }
    v = (v << 4) | static_cast<uint32_t>(h);
  }
  pos_ += 4;
  out = v;
  return true;
}

bool Reader::readString(std::string* out, size_t maxBytes, bool* truncated) {
  if (truncated) *truncated = false;
  if (out) out->clear();
  if (!ok()) return false;
  skipWs();
  if (pos_ >= len_ || p_[pos_] != '"') {
    fail(Error::Syntax);
    return false;
  }
  ++pos_;
  bool stopped = false;
  auto emit = [&](const char* s, size_t n) {
    if (!out || stopped) return;
    if (out->size() + n > maxBytes) {
      stopped = true;
      if (truncated) *truncated = true;
      return;
    }
    out->append(s, n);
  };
  for (;;) {
    if (pos_ >= len_) {
      fail(Error::Syntax);
      return false;
    }
    const unsigned char c = static_cast<unsigned char>(p_[pos_]);
    if (c == '"') {
      ++pos_;
      return true;
    }
    if (c == '\\') {
      if (len_ - pos_ < 2) {
        fail(Error::Syntax);
        return false;
      }
      const char e = p_[pos_ + 1];
      pos_ += 2;
      switch (e) {
        case '"': emit("\"", 1); break;
        case '\\': emit("\\", 1); break;
        case '/': emit("/", 1); break;
        case 'b': emit("\b", 1); break;
        case 'f': emit("\f", 1); break;
        case 'n': emit("\n", 1); break;
        case 'r': emit("\r", 1); break;
        case 't': emit("\t", 1); break;
        case 'u': {
          uint32_t cp = 0;
          if (!readHex4(cp)) return false;
          if (cp >= 0xD800 && cp <= 0xDBFF) {
            if (len_ - pos_ < 2 || p_[pos_] != '\\' || p_[pos_ + 1] != 'u') {
              fail(Error::Syntax);
              return false;
            }
            pos_ += 2;
            uint32_t lo = 0;
            if (!readHex4(lo)) return false;
            if (lo < 0xDC00 || lo > 0xDFFF) {
              fail(Error::Syntax);
              return false;
            }
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
            fail(Error::Syntax);
            return false;
          }
          char buf[4];
          const size_t n = encodeUtf8(cp, buf);
          emit(buf, n);
          break;
        }
        default:
          fail(Error::Syntax);
          return false;
      }
      continue;
    }
    if (c < 0x20) {
      fail(Error::Syntax);
      return false;
    }
    const size_t n = utf8SequenceLength(reinterpret_cast<const unsigned char*>(p_ + pos_),
                                        len_ - pos_);
    if (n == 0) {
      fail(Error::BadUtf8);
      return false;
    }
    emit(p_ + pos_, n);
    pos_ += n;
  }
}

bool Reader::readNumber(Number& out) {
  out = Number();
  if (!ok()) return false;
  skipWs();
  if (pos_ < len_ && p_[pos_] == '-') {
    out.negative = true;
    ++pos_;
  }
  if (pos_ >= len_ || !isDigit(p_[pos_])) {
    fail(Error::Syntax);
    return false;
  }
  out.integer = true;
  if (p_[pos_] == '0') {
    ++pos_;
  } else {
    while (pos_ < len_ && isDigit(p_[pos_])) {
      const uint64_t d = static_cast<uint64_t>(p_[pos_] - '0');
      if (!out.saturated) {
        if (out.magnitude > (kMaxMagnitude - d) / 10) {
          out.saturated = true;
          out.magnitude = kMaxMagnitude;
        } else {
          out.magnitude = out.magnitude * 10 + d;
        }
      }
      ++pos_;
    }
  }
  if (pos_ < len_ && p_[pos_] == '.') {
    out.integer = false;
    ++pos_;
    if (pos_ >= len_ || !isDigit(p_[pos_])) {
      fail(Error::Syntax);
      return false;
    }
    while (pos_ < len_ && isDigit(p_[pos_])) ++pos_;
  }
  if (pos_ < len_ && (p_[pos_] == 'e' || p_[pos_] == 'E')) {
    out.integer = false;
    ++pos_;
    if (pos_ < len_ && (p_[pos_] == '+' || p_[pos_] == '-')) ++pos_;
    if (pos_ >= len_ || !isDigit(p_[pos_])) {
      fail(Error::Syntax);
      return false;
    }
    while (pos_ < len_ && isDigit(p_[pos_])) ++pos_;
  }
  if (!out.integer) out.magnitude = 0;
  return true;
}

bool Reader::readBool(bool& out) {
  if (!ok()) return false;
  skipWs();
  if (len_ - pos_ >= 4 && std::memcmp(p_ + pos_, "true", 4) == 0) {
    pos_ += 4;
    out = true;
    return true;
  }
  if (len_ - pos_ >= 5 && std::memcmp(p_ + pos_, "false", 5) == 0) {
    pos_ += 5;
    out = false;
    return true;
  }
  fail(Error::Syntax);
  return false;
}

bool Reader::readNull() {
  if (!ok()) return false;
  skipWs();
  if (len_ - pos_ >= 4 && std::memcmp(p_ + pos_, "null", 4) == 0) {
    pos_ += 4;
    return true;
  }
  fail(Error::Syntax);
  return false;
}

bool Reader::skipValue() {
  if (!ok()) return false;
  // Explicit stack of open containers (true = object). Combined with the
  // containers opened through enterObject/enterArray, depth stays <= kMaxDepth.
  bool stack[kMaxDepth];
  size_t sp = 0;
  const size_t limit = kMaxDepth - depth_;
  for (;;) {
    // Parse the start of one value.
    skipWs();
    if (pos_ >= len_) {
      fail(Error::Syntax);
      return false;
    }
    const char c = p_[pos_];
    bool opened = false;
    if (c == '{' || c == '[') {
      const bool isObj = (c == '{');
      if (sp >= limit) {
        fail(Error::TooDeep);
        return false;
      }
      ++pos_;
      skipWs();
      if (pos_ < len_ && p_[pos_] == (isObj ? '}' : ']')) {
        ++pos_;  // empty container: a complete value
      } else {
        stack[sp++] = isObj;
        if (isObj && !readMemberKey(nullptr, 0)) return false;
        opened = true;
      }
    } else if (c == '"') {
      if (!readString(nullptr, 0, nullptr)) return false;
    } else if (c == 't' || c == 'f') {
      bool b = false;
      if (!readBool(b)) return false;
    } else if (c == 'n') {
      if (!readNull()) return false;
    } else {
      Number n;
      if (!readNumber(n)) return false;
    }
    if (opened) continue;
    // A value is complete: close containers or move to the next item.
    for (;;) {
      if (sp == 0) return true;
      skipWs();
      if (pos_ >= len_) {
        fail(Error::Syntax);
        return false;
      }
      const char d = p_[pos_];
      const bool isObj = stack[sp - 1];
      if (d == ',') {
        ++pos_;
        if (isObj && !readMemberKey(nullptr, 0)) return false;
        break;
      }
      if (d == (isObj ? '}' : ']')) {
        ++pos_;
        --sp;
        continue;
      }
      fail(Error::Syntax);
      return false;
    }
  }
}

Error validate(const char* data, size_t len) {
  Reader r(data, len);
  if (!r.skipValue()) return r.error();
  if (!r.expectEnd()) return r.error();
  return Error::None;
}

bool isValidUtf8(const char* data, size_t len) {
  size_t i = 0;
  while (i < len) {
    const size_t n =
        utf8SequenceLength(reinterpret_cast<const unsigned char*>(data + i), len - i);
    if (n == 0) return false;
    i += n;
  }
  return true;
}

size_t countCodePoints(const std::string& utf8) {
  size_t n = 0;
  for (char ch : utf8) {
    if (!isCont(static_cast<unsigned char>(ch))) ++n;
  }
  return n;
}

void appendQuoted(std::string& out, const char* s, size_t len) {
  static const char kHex[] = "0123456789abcdef";
  out += '"';
  size_t i = 0;
  while (i < len) {
    const unsigned char c = static_cast<unsigned char>(s[i]);
    if (c >= 0x80) {
      const size_t n = utf8SequenceLength(reinterpret_cast<const unsigned char*>(s + i), len - i);
      if (n == 0) {
        out += "\\ufffd";
        ++i;
      } else {
        out.append(s + i, n);
        i += n;
      }
      continue;
    }
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\b': out += "\\b"; break;
      case '\f': out += "\\f"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          out += "\\u00";
          out += kHex[c >> 4];
          out += kHex[c & 0x0F];
        } else {
          out += static_cast<char>(c);
        }
    }
    ++i;
  }
  out += '"';
}

void Writer::prefix() {
  if (afterKey_) {
    afterKey_ = false;
    return;
  }
  if (depth_ > 0) {
    if (hasItem_[depth_ - 1]) out_ += ',';
    hasItem_[depth_ - 1] = true;
  }
}

void Writer::push() {
  if (depth_ < kMaxDepth) hasItem_[depth_] = false;
  ++depth_;
}

void Writer::pop() {
  if (depth_ > 0) --depth_;
}

Writer& Writer::beginObject() {
  prefix();
  out_ += '{';
  push();
  return *this;
}

Writer& Writer::endObject() {
  out_ += '}';
  pop();
  return *this;
}

Writer& Writer::beginArray() {
  prefix();
  out_ += '[';
  push();
  return *this;
}

Writer& Writer::endArray() {
  out_ += ']';
  pop();
  return *this;
}

Writer& Writer::key(const char* name) {
  prefix();
  appendQuoted(out_, name, std::strlen(name));
  out_ += ':';
  afterKey_ = true;
  return *this;
}

Writer& Writer::str(const std::string& value) {
  prefix();
  appendQuoted(out_, value.data(), value.size());
  return *this;
}

Writer& Writer::str(const char* value) {
  prefix();
  appendQuoted(out_, value, std::strlen(value));
  return *this;
}

Writer& Writer::num(int64_t value) {
  prefix();
  out_ += std::to_string(static_cast<long long>(value));
  return *this;
}

Writer& Writer::unum(uint64_t value) {
  prefix();
  out_ += std::to_string(static_cast<unsigned long long>(value));
  return *this;
}

Writer& Writer::boolean(bool value) {
  prefix();
  out_ += value ? "true" : "false";
  return *this;
}

Writer& Writer::null() {
  prefix();
  out_ += "null";
  return *this;
}

}  // namespace json
}  // namespace bridge
