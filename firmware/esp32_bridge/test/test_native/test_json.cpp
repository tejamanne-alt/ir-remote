// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "test_support.h"

using bridge::json::Error;
using bridge::json::validate;

namespace {

Error v(const std::string& s) { return validate(s.data(), s.size()); }

void test_json_accepts_valid_documents() {
  const char* valid[] = {
      "{}", "[]", "0", "-0", "1", "-1", "123456789", "1.5", "-1.5e10", "1E+2", "1e-2",
      "\"\"", "\"abc\"", "true", "false", "null", " \t\r\n{ } \n",
      "{\"a\":1,\"b\":[1,2,{\"c\":null}],\"d\":\"x\"}", "[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]",
      "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9\\uD83D\\uDE00\"", "\"\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80\"",
      "{\"carrierHz\":38000,\"durationsUs\":[9000,4500,560]}",
  };
  for (const char* s : valid) {
    TEST_ASSERT_TRUE_MESSAGE(v(s) == Error::None, s);
  }
}

void test_json_rejects_invalid_documents() {
  const char* invalid[] = {
      "", " ", "{", "}", "[", "]", "{]", "[}", "{\"a\"}", "{\"a\":}", "{\"a\":1,}", "[1,]",
      "[,1]", "{,}", "{\"a\" 1}", "{a:1}", "{'a':1}", "01", "-", "1.", ".5", "1e", "1e+",
      "+1", "0x10", "NaN", "Infinity", "tru", "nul", "falsey", "\"abc", "\"\\x\"", "\"\\u12\"",
      "\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0041\"", "\"a\nb\"", "[1 2]", "{} {}",
      "{\"a\":1}x", "\"\xff\"", "\"\xc0\xaf\"", "\"\xed\xa0\x80\"", "\"\xf4\x90\x80\x80\"",
      "\"\xe2\x82\"", "\xef\xbb\xbf{}",
  };
  for (const char* s : invalid) {
    TEST_ASSERT_TRUE_MESSAGE(v(s) != Error::None, s);
  }
}

void test_json_rejects_embedded_nul_and_raw_controls() {
  const std::string withNul("{\"a\":\"x\0y\"}", 11);
  TEST_ASSERT_TRUE(v(withNul) != Error::None);
  const std::string trailingNul("{}\0", 3);
  TEST_ASSERT_TRUE(v(trailingNul) != Error::None);
}

void test_json_depth_limit_is_enforced_iteratively() {
  std::string ok(bridge::json::kMaxDepth, '[');
  ok += std::string(bridge::json::kMaxDepth, ']');
  TEST_ASSERT_TRUE(v(ok) == Error::None);
  std::string deep(bridge::json::kMaxDepth + 1, '[');
  deep += std::string(bridge::json::kMaxDepth + 1, ']');
  TEST_ASSERT_TRUE(v(deep) == Error::TooDeep);
  // Far deeper than any stack could take if the parser recursed.
  const std::string huge(1000000, '[');
  TEST_ASSERT_TRUE(v(huge) == Error::TooDeep);
  std::string objects;
  for (int i = 0; i < 100000; ++i) objects += "{\"a\":";
  TEST_ASSERT_TRUE(v(objects) == Error::TooDeep);
}

void test_json_numbers_saturate_instead_of_overflowing() {
  bridge::json::Reader r("123456789012345678901234567890");
  bridge::json::Number n;
  TEST_ASSERT_TRUE(r.readNumber(n));
  TEST_ASSERT_TRUE(n.integer);
  TEST_ASSERT_TRUE(n.saturated);
  TEST_ASSERT_EQUAL_UINT64(bridge::json::kMaxMagnitude, n.magnitude);
  bridge::json::Reader neg("-99999999999999999999999");
  TEST_ASSERT_TRUE(neg.readNumber(n));
  TEST_ASSERT_TRUE(n.asInt64() < 0);
  TEST_ASSERT_EQUAL_INT64(-static_cast<long long>(bridge::json::kMaxMagnitude), n.asInt64());
  bridge::json::Reader frac("1.25");
  TEST_ASSERT_TRUE(frac.readNumber(n));
  TEST_ASSERT_FALSE(n.integer);
  const std::string longDigits(20000, '7');
  TEST_ASSERT_TRUE(v(longDigits) == Error::None);
}

void test_json_string_decoding() {
  bridge::json::Reader r("\"a\\u00e9\\uD83D\\uDE00\\n\\\"\"");
  std::string s;
  bool truncated = true;
  TEST_ASSERT_TRUE(r.readString(&s, 64, &truncated));
  TEST_ASSERT_FALSE(truncated);
  TEST_ASSERT_EQUAL_STRING("a\xc3\xa9\xf0\x9f\x98\x80\n\"", s.c_str());
  bridge::json::Reader t("\"abcdefgh\"");
  TEST_ASSERT_TRUE(t.readString(&s, 4, &truncated));
  TEST_ASSERT_TRUE(truncated);
  TEST_ASSERT_EQUAL_STRING("abcd", s.c_str());
  // A truncated read never splits a multi-byte character.
  bridge::json::Reader u("\"ab\xe2\x82\xac\"");
  TEST_ASSERT_TRUE(u.readString(&s, 4, &truncated));
  TEST_ASSERT_TRUE(truncated);
  TEST_ASSERT_EQUAL_STRING("ab", s.c_str());
}

void test_json_object_iteration_and_errors_are_sticky() {
  bridge::json::Reader r("{\"a\":1,\"b\":[true,false],\"c\":{\"d\":null}}");
  TEST_ASSERT_TRUE(r.enterObject());
  std::string key;
  std::vector<std::string> keys;
  while (r.nextMember(key)) {
    keys.push_back(key);
    TEST_ASSERT_TRUE(r.skipValue());
  }
  TEST_ASSERT_TRUE(r.ok());
  TEST_ASSERT_TRUE(r.expectEnd());
  TEST_ASSERT_EQUAL_INT(3, keys.size());
  TEST_ASSERT_EQUAL_STRING("c", keys[2].c_str());

  bridge::json::Reader bad("{\"a\":1 \"b\":2}");
  TEST_ASSERT_TRUE(bad.enterObject());
  TEST_ASSERT_TRUE(bad.nextMember(key));
  TEST_ASSERT_TRUE(bad.skipValue());
  TEST_ASSERT_FALSE(bad.nextMember(key));
  TEST_ASSERT_FALSE(bad.ok());
  TEST_ASSERT_FALSE(bad.skipValue());  // sticky
  TEST_ASSERT_TRUE(bad.peekType() == bridge::json::Type::Invalid);
}

void test_json_long_keys_never_match_known_fields() {
  std::string body = "{\"" + std::string(100, 'k') + "\":1}";
  bridge::json::Reader r(body);
  TEST_ASSERT_TRUE(r.enterObject());
  std::string key;
  TEST_ASSERT_TRUE(r.nextMember(key, 16));
  TEST_ASSERT_EQUAL_INT(1, key.size());
  TEST_ASSERT_EQUAL_INT(0, key[0]);
}

void test_json_writer_escapes_and_produces_valid_json() {
  std::string out;
  bridge::json::Writer w(out);
  const std::string tricky = std::string("q\"b\\n\n\t\x01 \xc3\xa9 \xff end");
  w.beginObject()
      .key("s").str(tricky)
      .key("n").num(-42)
      .key("u").unum(18446744073709551615ULL)
      .key("b").boolean(false)
      .key("z").null()
      .key("a").beginArray().num(1).beginObject().endObject().beginArray().endArray().endArray()
      .endObject();
  TEST_ASSERT_TRUE(bridge::json::isValid(out));
  TEST_ASSERT_EQUAL_STRING(
      "{\"s\":\"q\\\"b\\\\n\\n\\t\\u0001 \xc3\xa9 \\ufffd end\",\"n\":-42,"
      "\"u\":18446744073709551615,\"b\":false,\"z\":null,\"a\":[1,{},[]]}",
      out.c_str());
}

void test_utf8_helpers() {
  TEST_ASSERT_TRUE(bridge::json::isValidUtf8("", 0));
  TEST_ASSERT_TRUE(bridge::json::isValidUtf8("h\xc3\xa9", 3));
  TEST_ASSERT_FALSE(bridge::json::isValidUtf8("\xc3", 1));
  TEST_ASSERT_FALSE(bridge::json::isValidUtf8("\xe0\x80\x80", 3));  // overlong
  TEST_ASSERT_EQUAL_INT(3, bridge::json::countCodePoints("a\xc3\xa9\xf0\x9f\x98\x80"));
}

}  // namespace

void run_json_tests() {
  RUN_TEST(test_json_accepts_valid_documents);
  RUN_TEST(test_json_rejects_invalid_documents);
  RUN_TEST(test_json_rejects_embedded_nul_and_raw_controls);
  RUN_TEST(test_json_depth_limit_is_enforced_iteratively);
  RUN_TEST(test_json_numbers_saturate_instead_of_overflowing);
  RUN_TEST(test_json_string_decoding);
  RUN_TEST(test_json_object_iteration_and_errors_are_sticky);
  RUN_TEST(test_json_long_keys_never_match_known_fields);
  RUN_TEST(test_json_writer_escapes_and_produces_valid_json);
  RUN_TEST(test_utf8_helpers);
}
