// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Status lines and form decoding used by the esp_http_server glue.
#include <cstring>
#include <string>

#include "bridge_http.h"
#include "test_support.h"

namespace {

void test_status_lines() {
  TEST_ASSERT_EQUAL_STRING("200 OK", bridge::statusLine(200));
  TEST_ASSERT_EQUAL_STRING("202 Accepted", bridge::statusLine(202));
  TEST_ASSERT_EQUAL_STRING("401 Unauthorized", bridge::statusLine(401));
  TEST_ASSERT_EQUAL_STRING("405 Method Not Allowed", bridge::statusLine(405));
  TEST_ASSERT_EQUAL_STRING("413 Content Too Large", bridge::statusLine(413));
  TEST_ASSERT_EQUAL_STRING("426 Upgrade Required", bridge::statusLine(426));
  TEST_ASSERT_EQUAL_STRING("507 Insufficient Storage", bridge::statusLine(507));
  // Unknown codes fall back to their class.
  TEST_ASSERT_EQUAL_STRING("400 Bad Request", bridge::statusLine(418));
  TEST_ASSERT_EQUAL_STRING("500 Internal Server Error", bridge::statusLine(599));
  TEST_ASSERT_EQUAL_STRING("500 Internal Server Error", bridge::statusLine(-1));
}

void test_url_decode() {
  std::string out;
  TEST_ASSERT_TRUE(bridge::urlDecode("My+Wi-Fi%21%20%C3%A9", out));
  TEST_ASSERT_EQUAL_STRING("My Wi-Fi! \xC3\xA9", out.c_str());
  TEST_ASSERT_TRUE(bridge::urlDecode("", out));
  TEST_ASSERT_EQUAL_STRING("", out.c_str());
  TEST_ASSERT_FALSE(bridge::urlDecode("bad%2", out));
  TEST_ASSERT_FALSE(bridge::urlDecode("bad%zz", out));
  TEST_ASSERT_FALSE(bridge::urlDecode("%", out));
}

void test_form_fields() {
  const std::string body = "ssid=Home+Net&pass=p%26ss%3Dword&name=&x";
  std::string v;
  TEST_ASSERT_TRUE(bridge::formField(body, "ssid", v));
  TEST_ASSERT_EQUAL_STRING("Home Net", v.c_str());
  TEST_ASSERT_TRUE(bridge::formField(body, "pass", v));
  TEST_ASSERT_EQUAL_STRING("p&ss=word", v.c_str());
  TEST_ASSERT_TRUE(bridge::formField(body, "name", v));
  TEST_ASSERT_EQUAL_STRING("", v.c_str());
  TEST_ASSERT_FALSE(bridge::formField(body, "x", v));      // no '='
  TEST_ASSERT_FALSE(bridge::formField(body, "ssi", v));    // prefix only
  TEST_ASSERT_FALSE(bridge::formField(body, "missing", v));
  TEST_ASSERT_FALSE(bridge::formField("a=%G0", "a", v));    // bad escape
  TEST_ASSERT_FALSE(bridge::formField(std::string(bridge::kMaxFormBytes + 1, 'a'), "a", v));
  TEST_ASSERT_FALSE(bridge::formField(body, nullptr, v));
}

void test_form_fuzz() {
  // Random bytes must never crash or read out of bounds (ASan watches).
  uint64_t s = 0x9e3779b97f4a7c15ULL;
  std::string v;
  for (int i = 0; i < 3000; ++i) {
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    const size_t len = static_cast<size_t>(s % 64);
    std::string body;
    for (size_t k = 0; k < len; ++k) {
      s ^= s << 13;
      s ^= s >> 7;
      s ^= s << 17;
      static const char kAlphabet[] = "ab=&%+0F9z";
      body.push_back(kAlphabet[s % (sizeof(kAlphabet) - 1)]);
    }
    (void)bridge::formField(body, "a", v);
    (void)bridge::urlDecode(body, v);
  }
  TEST_ASSERT_TRUE(true);
}

}  // namespace

void run_form_tests() {
  RUN_TEST(test_status_lines);
  RUN_TEST(test_url_decode);
  RUN_TEST(test_form_fields);
  RUN_TEST(test_form_fuzz);
}
