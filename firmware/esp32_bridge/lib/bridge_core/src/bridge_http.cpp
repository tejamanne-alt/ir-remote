// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_http.h"

#include <cstring>

#include "bridge_json.h"

namespace bridge {

namespace {

bool equalsIgnoreCase(const char* a, const char* b) {
  for (; *a && *b; ++a, ++b) {
    char x = *a, y = *b;
    if (x >= 'a' && x <= 'z') x = static_cast<char>(x - 32);
    if (y >= 'a' && y <= 'z') y = static_cast<char>(y - 32);
    if (x != y) return false;
  }
  return *a == *b;
}

}  // namespace

Method parseMethod(const char* name) {
  if (name == nullptr) return Method::Other;
  static const struct {
    const char* name;
    Method method;
  } kMethods[] = {
      {"GET", Method::Get},       {"HEAD", Method::Head},   {"POST", Method::Post},
      {"PUT", Method::Put},       {"DELETE", Method::Delete}, {"PATCH", Method::Patch},
      {"OPTIONS", Method::Options},
  };
  for (const auto& m : kMethods) {
    if (equalsIgnoreCase(name, m.name)) return m.method;
  }
  return Method::Other;
}

const char* methodName(Method m) {
  switch (m) {
    case Method::Get: return "GET";
    case Method::Head: return "HEAD";
    case Method::Post: return "POST";
    case Method::Put: return "PUT";
    case Method::Delete: return "DELETE";
    case Method::Patch: return "PATCH";
    case Method::Options: return "OPTIONS";
    case Method::Other: return "OTHER";
  }
  return "OTHER";
}

Response errorResponse(int status, const char* code, const std::string& detail) {
  Response r;
  r.status = status;
  json::Writer w(r.body);
  w.beginObject().key("error").str(code).key("detail").str(detail).endObject();
  return r;
}

}  // namespace bridge
