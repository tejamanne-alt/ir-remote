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

const char* statusLine(int status) {
  switch (status) {
    case 101: return "101 Switching Protocols";
    case 200: return "200 OK";
    case 202: return "202 Accepted";
    case 204: return "204 No Content";
    case 302: return "302 Found";
    case 400: return "400 Bad Request";
    case 401: return "401 Unauthorized";
    case 403: return "403 Forbidden";
    case 404: return "404 Not Found";
    case 405: return "405 Method Not Allowed";
    case 409: return "409 Conflict";
    case 411: return "411 Length Required";
    case 413: return "413 Content Too Large";
    case 426: return "426 Upgrade Required";
    case 500: return "500 Internal Server Error";
    case 501: return "501 Not Implemented";
    case 503: return "503 Service Unavailable";
    case 507: return "507 Insufficient Storage";
    default: break;
  }
  if (status >= 200 && status < 300) return "200 OK";
  if (status >= 300 && status < 400) return "302 Found";
  if (status >= 400 && status < 500) return "400 Bad Request";
  return "500 Internal Server Error";
}

namespace {

int hexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

}  // namespace

bool urlDecode(const std::string& in, std::string& out) {
  out.clear();
  out.reserve(in.size());
  for (size_t i = 0; i < in.size(); ++i) {
    const char c = in[i];
    if (c == '+') {
      out.push_back(' ');
    } else if (c == '%') {
      if (i + 2 >= in.size()) return false;
      const int hi = hexValue(in[i + 1]);
      const int lo = hexValue(in[i + 2]);
      if (hi < 0 || lo < 0) return false;
      out.push_back(static_cast<char>((hi << 4) | lo));
      i += 2;
    } else {
      out.push_back(c);
    }
  }
  return true;
}

bool formField(const std::string& body, const char* key, std::string& value) {
  if (key == nullptr || body.size() > kMaxFormBytes) return false;
  const size_t keyLen = std::strlen(key);
  size_t start = 0;
  while (start <= body.size()) {
    size_t end = body.find('&', start);
    if (end == std::string::npos) end = body.size();
    const size_t eq = body.find('=', start);
    if (eq != std::string::npos && eq < end && eq - start == keyLen &&
        body.compare(start, keyLen, key) == 0) {
      return urlDecode(body.substr(eq + 1, end - eq - 1), value);
    }
    start = end + 1;
  }
  return false;
}

Response errorResponse(int status, const char* code, const std::string& detail) {
  Response r;
  r.status = status;
  json::Writer w(r.body);
  w.beginObject().key("error").str(code).key("detail").str(detail).endObject();
  return r;
}

}  // namespace bridge
