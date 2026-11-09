// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "test_support.h"

using bridge::ApiError;
using bridge::SendRawJob;

namespace {

std::string rawBody(uint32_t carrier, const std::vector<long long>& durations) {
  std::string s = "{\"carrierHz\":" + std::to_string(carrier) + ",\"durationsUs\":[";
  for (size_t i = 0; i < durations.size(); ++i) {
    if (i) s += ',';
    s += std::to_string(durations[i]);
  }
  return s + "]}";
}

std::string repeated(size_t count, long long value) {
  std::string s = "{\"carrierHz\":38000,\"durationsUs\":[";
  for (size_t i = 0; i < count; ++i) {
    if (i) s += ',';
    s += std::to_string(value);
  }
  return s + "]}";
}

ApiError parse(const std::string& body) {
  SendRawJob job;
  return bridge::parseSendRaw(body, job);
}

void expectCode(int status, const char* code, const std::string& body) {
  const ApiError e = parse(body);
  TEST_ASSERT_EQUAL_INT_MESSAGE(status, e.status, body.substr(0, 120).c_str());
  TEST_ASSERT_EQUAL_STRING_MESSAGE(code, e.code ? e.code : "<ok>", body.substr(0, 120).c_str());
}

void test_send_raw_accepts_nec_frame() {
  SendRawJob job;
  const ApiError e = bridge::parseSendRaw(
      "{\"carrierHz\": 38000, \"durationsUs\": [9024, 4512, 564, 564, 564]}", job);
  TEST_ASSERT_TRUE(e.ok());
  TEST_ASSERT_EQUAL_UINT32(38000, job.carrierHz);
  TEST_ASSERT_EQUAL_INT(5, job.durationsUs.size());
  TEST_ASSERT_EQUAL_UINT32(9024, job.durationsUs[0]);
  TEST_ASSERT_EQUAL_UINT64(9024 + 4512 + 564 * 3, job.totalUs);
}

void test_send_raw_field_order_whitespace_and_unknown_fields() {
  SendRawJob job;
  const ApiError e = bridge::parseSendRaw(
      " \n{\"durationsUs\":[100],\"extra\":{\"nested\":[1,2,\"x\"]},\"carrierHz\":40000}\r\n", job);
  TEST_ASSERT_TRUE(e.ok());
  TEST_ASSERT_EQUAL_UINT32(40000, job.carrierHz);
  TEST_ASSERT_EQUAL_INT(1, job.durationsUs.size());
}

void test_send_raw_bad_json_cases() {
  const char* cases[] = {
      "",
      "not json",
      "[]",
      "\"str\"",
      "{\"carrierHz\":38000}",
      "{\"durationsUs\":[1]}",
      "{\"carrierHz\":\"38000\",\"durationsUs\":[1]}",
      "{\"carrierHz\":38000.0,\"durationsUs\":[1]}",
      "{\"carrierHz\":3.8e4,\"durationsUs\":[1]}",
      "{\"carrierHz\":null,\"durationsUs\":[1]}",
      "{\"carrierHz\":38000,\"durationsUs\":\"1,2,3\"}",
      "{\"carrierHz\":38000,\"durationsUs\":[1,\"2\",3]}",
      "{\"carrierHz\":38000,\"durationsUs\":[1,2.5,3]}",
      "{\"carrierHz\":38000,\"durationsUs\":[1,[2],3]}",
      "{\"carrierHz\":38000,\"durationsUs\":{\"0\":1}}",
      "{\"carrierHz\":38000,\"carrierHz\":38000,\"durationsUs\":[1]}",
      "{\"carrierHz\":38000,\"durationsUs\":[1],\"durationsUs\":[1]}",
      "{\"carrierHz\":38000,\"durationsUs\":[1]",
      "{\"carrierHz\":38000,\"durationsUs\":[1]}}",
      "{\"carrierHz\":38000,\"durationsUs\":[1,]}",
      "{\"carrierHz\":38000,\"durationsUs\":[01]}",
  };
  for (const char* c : cases) expectCode(400, "bad_json", c);
}

void test_send_raw_invalid_durations() {
  expectCode(400, "invalid_durations", rawBody(38000, {}));
  expectCode(400, "invalid_durations", rawBody(38000, {100, 200}));
  expectCode(400, "invalid_durations", rawBody(38000, {0}));
  expectCode(400, "invalid_durations", rawBody(38000, {-5}));
  expectCode(400, "invalid_durations", rawBody(38000, {100, 150001, 100}));
  expectCode(400, "invalid_durations", rawBody(38000, {100, 99999999999999999LL, 100}));
  expectCode(400, "invalid_durations", repeated(1024, 500));  // even, though within the count limit
  // 27 x 150000 us = 4.05 s > maxPatternUs
  expectCode(400, "invalid_durations", repeated(27, 150000));
}

void test_send_raw_limits_inclusive() {
  SendRawJob job;
  TEST_ASSERT_TRUE(bridge::parseSendRaw(rawBody(38000, {1}), job).ok());
  TEST_ASSERT_TRUE(bridge::parseSendRaw(rawBody(38000, {150000}), job).ok());
  // Exactly maxPatternUs: 25 x 150000 + 250000 split into odd-count values.
  std::vector<long long> exact(25, 150000);
  exact.push_back(125000);
  exact.push_back(125000);
  TEST_ASSERT_TRUE(bridge::parseSendRaw(rawBody(38000, exact), job).ok());
  TEST_ASSERT_EQUAL_UINT64(4000000, job.totalUs);
  exact.back() = 125001;
  expectCode(400, "invalid_durations", rawBody(38000, exact));
  TEST_ASSERT_TRUE(bridge::parseSendRaw(repeated(1023, 500), job).ok());
  TEST_ASSERT_EQUAL_INT(1023, job.durationsUs.size());
}

void test_send_raw_too_many_durations_is_413() {
  expectCode(413, "too_large", repeated(1025, 500));
  expectCode(413, "too_large", repeated(5000, 1));
  // Malformed JSON still wins over the count.
  std::string broken = repeated(2000, 1);
  broken.pop_back();
  expectCode(400, "bad_json", broken);
}

void test_send_raw_carrier_range() {
  expectCode(400, "carrier_out_of_range", rawBody(29999, {100}));
  expectCode(400, "carrier_out_of_range", rawBody(60001, {100}));
  expectCode(400, "carrier_out_of_range", "{\"carrierHz\":-38000,\"durationsUs\":[100]}");
  expectCode(400, "carrier_out_of_range", "{\"carrierHz\":0,\"durationsUs\":[100]}");
  SendRawJob job;
  TEST_ASSERT_TRUE(bridge::parseSendRaw(rawBody(30000, {100}), job).ok());
  TEST_ASSERT_TRUE(bridge::parseSendRaw(rawBody(60000, {100}), job).ok());
}

void test_pair_body_validation() {
  std::string client;
  TEST_ASSERT_TRUE(bridge::parsePair("{\"client\":\"Pixel 8\"}", client).ok());
  TEST_ASSERT_EQUAL_STRING("Pixel 8", client.c_str());
  // 32 characters, several of them multi-byte, is allowed.
  std::string name32;
  for (int i = 0; i < 16; ++i) name32 += "a\xc3\xa9";
  TEST_ASSERT_TRUE(bridge::parsePair("{\"client\":\"" + name32 + "\"}", client).ok());
  const char* bad[] = {
      "{}",
      "{\"client\":\"\"}",
      "{\"client\":42}",
      "{\"client\":null}",
      "{\"client\":\"a\\nb\"}",
      "{\"client\":\"a\\u0000b\"}",
      "{\"client\":\"\\u0085\"}",
      "{\"client\":\"123456789012345678901234567890123\"}",
      "{\"client\":\"x\",\"client\":\"y\"}",
      "{\"client\":\"x\"",
      "[\"client\"]",
      "",
  };
  for (const char* b : bad) {
    const ApiError e = bridge::parsePair(b, client);
    TEST_ASSERT_EQUAL_INT_MESSAGE(400, e.status, b);
    TEST_ASSERT_EQUAL_STRING_MESSAGE("bad_json", e.code, b);
  }
}

void test_learn_body_validation() {
  uint32_t t = 1;
  TEST_ASSERT_TRUE(bridge::parseLearn("{\"timeoutMs\":15000}", t).ok());
  TEST_ASSERT_EQUAL_UINT32(15000, t);
  TEST_ASSERT_TRUE(bridge::parseLearn("{\"timeoutMs\":0}", t).ok());
  TEST_ASSERT_EQUAL_UINT32(0, t);
  TEST_ASSERT_TRUE(bridge::parseLearn("", t).ok());
  TEST_ASSERT_EQUAL_UINT32(bridge::kDefaultLearnTimeoutMs, t);
  TEST_ASSERT_TRUE(bridge::parseLearn("{}", t).ok());
  TEST_ASSERT_EQUAL_UINT32(bridge::kDefaultLearnTimeoutMs, t);
  const char* bad[] = {"{\"timeoutMs\":-1}", "{\"timeoutMs\":3600001}", "{\"timeoutMs\":\"5\"}",
                       "{\"timeoutMs\":1.5}", "{\"timeoutMs\":1", "x"};
  for (const char* b : bad) {
    TEST_ASSERT_EQUAL_STRING_MESSAGE("bad_json", bridge::parseLearn(b, t).code, b);
  }
}

void test_capture_message_matches_contract_example() {
  bridge::Capture c;
  c.durationsUs = {9010, 4490, 560};
  c.decoded.protocol = "NEC";
  c.decoded.value = 0x20DF10EF;
  c.decoded.bits = 32;
  c.atMs = 123456;
  TEST_ASSERT_EQUAL_STRING(
      "{\"type\":\"capture\",\"carrierHz\":null,\"durationsUs\":[9010,4490,560],"
      "\"decoded\":{\"protocol\":\"NEC\",\"value\":\"0x20DF10EF\",\"bits\":32},\"atMs\":123456}",
      bridge::buildCaptureMessage(c).c_str());
}

void test_capture_message_normalises() {
  bridge::Capture c;
  c.durationsUs = {0, 500, 200000, 100};  // even: trailing space dropped; values clamped
  c.carrierHz = 38000;
  const std::string msg = bridge::buildCaptureMessage(c);
  TEST_ASSERT_TRUE(bridge::json::isValid(msg));
  TEST_ASSERT_EQUAL_STRING(
      "{\"type\":\"capture\",\"carrierHz\":38000,\"durationsUs\":[1,500,150000],"
      "\"decoded\":null,\"atMs\":0}",
      msg.c_str());
  c.durationsUs.assign(3000, 100);
  const std::string big = bridge::buildCaptureMessage(c);
  // Re-parse through the send/raw validator: a capture must be re-sendable.
  std::string resend = "{\"carrierHz\":38000,\"durationsUs\":" +
                       big.substr(big.find('['), big.find(']') - big.find('[') + 1) + "}";
  SendRawJob job;
  TEST_ASSERT_TRUE(bridge::parseSendRaw(resend, job).ok());
  TEST_ASSERT_EQUAL_INT(1023, job.durationsUs.size());
  c.durationsUs.clear();
  TEST_ASSERT_EQUAL_STRING("", bridge::buildCaptureMessage(c).c_str());
}

void test_decoded_value_formatting() {
  bridge::DecodedSignal d;
  d.protocol = "SONY";
  d.bits = 12;
  d.value = 0xA90;
  TEST_ASSERT_EQUAL_STRING("0xA90", bridge::formatDecodedValue(d).c_str());
  d.bits = 32;
  d.value = 0x1;
  TEST_ASSERT_EQUAL_STRING("0x00000001", bridge::formatDecodedValue(d).c_str());
  d.bits = 0;
  d.value = 0;
  TEST_ASSERT_EQUAL_STRING("0x0", bridge::formatDecodedValue(d).c_str());
  d.bits = 4;
  d.value = 0xFFFFFFFFFFFFFFFFULL;  // value wider than bits: print all digits
  TEST_ASSERT_EQUAL_STRING("0xFFFFFFFFFFFFFFFF", bridge::formatDecodedValue(d).c_str());
  d.state = {0x11, 0xDA, 0x27, 0x00};
  d.bits = 32;
  TEST_ASSERT_EQUAL_STRING("0x11DA2700", bridge::formatDecodedValue(d).c_str());
}

}  // namespace

void run_signal_tests() {
  RUN_TEST(test_send_raw_accepts_nec_frame);
  RUN_TEST(test_send_raw_field_order_whitespace_and_unknown_fields);
  RUN_TEST(test_send_raw_bad_json_cases);
  RUN_TEST(test_send_raw_invalid_durations);
  RUN_TEST(test_send_raw_limits_inclusive);
  RUN_TEST(test_send_raw_too_many_durations_is_413);
  RUN_TEST(test_send_raw_carrier_range);
  RUN_TEST(test_pair_body_validation);
  RUN_TEST(test_learn_body_validation);
  RUN_TEST(test_capture_message_matches_contract_example);
  RUN_TEST(test_capture_message_normalises);
  RUN_TEST(test_decoded_value_formatting);
}
