// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Route-level tests against docs/BRIDGE_API.md (v1).
#include <cctype>

#include "test_support.h"

using bridge::Action;
using bridge::Method;
using bridge::Response;
using testsupport::errorCode;
using testsupport::isErrorShape;
using testsupport::jsonString;
using testsupport::Rig;

namespace {

const char* kNec = "{\"carrierHz\":38000,\"durationsUs\":[9024,4512,564,564,564]}";

void expectError(const Response& r, int status, const char* code) {
  TEST_ASSERT_EQUAL_INT_MESSAGE(status, r.status, r.body.c_str());
  TEST_ASSERT_EQUAL_STRING_MESSAGE(code, errorCode(r).c_str(), r.body.c_str());
  TEST_ASSERT_TRUE_MESSAGE(isErrorShape(r.body), r.body.c_str());
  TEST_ASSERT_EQUAL_STRING("application/json", r.contentType);
}

void test_info_needs_no_auth_and_matches_contract() {
  Rig rig;
  const Response r = rig.respond(Method::Get, "/v1/info");
  TEST_ASSERT_EQUAL_INT(200, r.status);
  TEST_ASSERT_EQUAL_STRING(
      "{\"api\":1,\"fw\":\"0.1.0\",\"id\":\"a1b2c3d4e5f6\",\"name\":\"IR Bridge\","
      "\"caps\":{\"carrierMinHz\":30000,\"carrierMaxHz\":60000,\"maxPatternUs\":4000000,"
      "\"maxDurations\":1024,\"canLearn\":true,\"ac\":[]},\"pairingWindowOpen\":false}",
      r.body.c_str());
  rig.bridge.onButton(bridge::ButtonEvent::ShortPress, rig.now);
  const Response open = rig.respond(Method::Get, "/v1/info");
  TEST_ASSERT_TRUE(open.body.find("\"pairingWindowOpen\":true") != std::string::npos);
}

void test_unknown_route_is_404_without_auth() {
  Rig rig;
  expectError(rig.respond(Method::Get, "/v1/nope"), 404, "not_found");
  expectError(rig.respond(Method::Get, "/"), 404, "not_found");
  expectError(rig.respond(Method::Get, "/v1/info/"), 404, "not_found");
  expectError(rig.respond(Method::Get, "/v2/info"), 404, "not_found");
  expectError(rig.respond(Method::Post, "/v1/send"), 404, "not_found");
}

void test_wrong_method_is_405_with_allow_header() {
  Rig rig;
  Response r = rig.respond(Method::Post, "/v1/info");
  expectError(r, 405, "method_not_allowed");
  TEST_ASSERT_EQUAL_STRING("GET", r.allow.c_str());
  r = rig.respond(Method::Get, "/v1/send/raw");
  expectError(r, 405, "method_not_allowed");
  TEST_ASSERT_EQUAL_STRING("POST", r.allow.c_str());
  r = rig.respond(Method::Put, "/v1/learn");
  expectError(r, 405, "method_not_allowed");
  TEST_ASSERT_EQUAL_STRING("POST, DELETE", r.allow.c_str());
  expectError(rig.respond(Method::Get, "/v1/pair"), 405, "method_not_allowed");
  expectError(rig.respond(Method::Get, "/v1/ota"), 405, "method_not_allowed");
  expectError(rig.respond(Method::Head, "/v1/health"), 405, "method_not_allowed");
  expectError(rig.respond(Method::Other, "/v1/info"), 405, "method_not_allowed");
}

void test_protected_routes_reject_missing_and_unknown_tokens() {
  Rig rig;
  const struct {
    Method m;
    const char* path;
  } routes[] = {{Method::Get, "/v1/health"}, {Method::Post, "/v1/send/raw"},
                {Method::Post, "/v1/send/ac"}, {Method::Post, "/v1/learn"},
                {Method::Delete, "/v1/learn"}, {Method::Get, "/v1/ws"},
                {Method::Post, "/v1/ota"}};
  const char* badAuth[] = {"", "Bearer", "Bearer ", "Basic YWxhZGRpbjpvcGVuc2VzYW1l",
                           "Bearer 00000000000000000000000000000000",
                           "Bearer not-a-token", "Token 0123456789abcdef0123456789abcdef"};
  for (const auto& route : routes) {
    for (const char* auth : badAuth) {
      expectError(rig.respond(route.m, route.path, kNec, auth), 401, "unauthorized");
    }
  }
}

void test_valid_token_and_header_variants() {
  Rig rig;
  const std::string auth = rig.pair();
  const std::string token = auth.substr(7);
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Get, "/v1/health", "", auth).status);
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Get, "/v1/health", "", "bearer " + token).status);
  TEST_ASSERT_EQUAL_INT(200,
                        rig.respond(Method::Get, "/v1/health", "", "  BEARER \t" + token + "  ").status);
  std::string upper = token;
  for (char& c : upper) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  if (upper != token) {
    expectError(rig.respond(Method::Get, "/v1/health", "", "Bearer " + upper), 401, "unauthorized");
  }
  expectError(rig.respond(Method::Get, "/v1/health", "", "Bearer " + token + " extra"), 401,
              "unauthorized");
  expectError(rig.respond(Method::Get, "/v1/health", "", "Bearer" + token), 401, "unauthorized");
}

void test_health_body() {
  Rig rig;
  const std::string auth = rig.pair();
  rig.now = 1234 * 1000 + 999;
  const Response r = rig.respond(Method::Get, "/v1/health", "", auth);
  TEST_ASSERT_EQUAL_INT(200, r.status);
  TEST_ASSERT_EQUAL_STRING(
      "{\"ok\":true,\"uptimeS\":1234,\"rssi\":-55,\"freeHeap\":123456,\"learning\":false}",
      r.body.c_str());
}

void test_body_over_16k_is_413_before_auth() {
  Rig rig;
  const std::string big(bridge::kMaxBodyBytes + 1, ' ');
  expectError(rig.respond(Method::Post, "/v1/send/raw", big), 413, "too_large");
  expectError(rig.respond(Method::Post, "/v1/pair", big), 413, "too_large");
  // The glue may stop buffering early and only report the declared length.
  bridge::Request req;
  req.method = Method::Post;
  req.path = "/v1/send/raw";
  req.contentLength = 1u << 20;
  expectError(rig.bridge.handle(req, rig.now).response, 413, "too_large");
  bridge::Request truncated;
  truncated.method = Method::Post;
  truncated.path = "/v1/learn";
  truncated.bodyTruncated = true;
  expectError(rig.bridge.handle(truncated, rig.now).response, 413, "too_large");
  // Exactly 16 KiB is fine (it is then judged as JSON).
  const std::string auth = rig.pair();
  std::string exact = std::string(kNec);
  exact += std::string(bridge::kMaxBodyBytes - exact.size(), ' ');
  TEST_ASSERT_EQUAL_INT(bridge::kMaxBodyBytes, exact.size());
  const bridge::Outcome o = rig.call(Method::Post, "/v1/send/raw", exact, auth);
  TEST_ASSERT_TRUE(o.action == Action::Transmit);
}

void test_send_raw_transmit_busy_and_finish() {
  Rig rig;
  const std::string auth = rig.pair();
  const bridge::Outcome first = rig.call(Method::Post, "/v1/send/raw", kNec, auth);
  TEST_ASSERT_TRUE(first.action == Action::Transmit);
  TEST_ASSERT_EQUAL_UINT32(38000, first.job.carrierHz);
  TEST_ASSERT_EQUAL_INT(5, first.job.durationsUs.size());
  TEST_ASSERT_TRUE(rig.bridge.transmitting());
  // A second request while the first is on air.
  expectError(rig.respond(Method::Post, "/v1/send/raw", kNec, auth), 409, "busy");
  // Validation errors still win over busy.
  expectError(rig.respond(Method::Post, "/v1/send/raw", "{}", auth), 400, "bad_json");
  // Other routes keep working during a transmission.
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Get, "/v1/info").status);
  const Response done = rig.bridge.finishTransmit(67512);
  TEST_ASSERT_EQUAL_INT(200, done.status);
  TEST_ASSERT_EQUAL_STRING("{\"sent\":true,\"elapsedUs\":67512}", done.body.c_str());
  TEST_ASSERT_FALSE(rig.bridge.transmitting());
  TEST_ASSERT_TRUE(rig.call(Method::Post, "/v1/send/raw", kNec, auth).action == Action::Transmit);
}

void test_send_raw_errors_through_router() {
  Rig rig;
  const std::string auth = rig.pair();
  expectError(rig.respond(Method::Post, "/v1/send/raw", "{\"carrierHz\":38000,\"durationsUs\":[1,2]}", auth),
              400, "invalid_durations");
  expectError(rig.respond(Method::Post, "/v1/send/raw", "{\"carrierHz\":70000,\"durationsUs\":[1]}", auth),
              400, "carrier_out_of_range");
  expectError(rig.respond(Method::Post, "/v1/send/raw", "{oops", auth), 400, "bad_json");
  std::string many = "{\"carrierHz\":38000,\"durationsUs\":[1";
  for (int i = 0; i < 1100; ++i) many += ",1";
  many += "]}";
  expectError(rig.respond(Method::Post, "/v1/send/raw", many, auth), 413, "too_large");
  TEST_ASSERT_FALSE(rig.bridge.transmitting());
}

void test_send_ac_is_501_in_v1() {
  Rig rig;
  const std::string auth = rig.pair();
  expectError(rig.respond(Method::Post, "/v1/send/ac",
                          "{\"protocol\":\"daikin\",\"model\":0,\"state\":{\"power\":true}}", auth),
              501, "not_implemented");
  expectError(rig.respond(Method::Post, "/v1/send/ac", "{nope", auth), 400, "bad_json");
}

void test_learn_first_capture_ends_learn_mode() {
  Rig rig;
  const std::string auth = rig.pair();
  rig.wsMessages();
  Response r = rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":15000}", auth);
  TEST_ASSERT_EQUAL_INT(202, r.status);
  TEST_ASSERT_EQUAL_STRING("{\"learning\":true}", r.body.c_str());
  TEST_ASSERT_TRUE(rig.bridge.learnMode() == bridge::LearnMode::Learn);
  r = rig.respond(Method::Get, "/v1/health", "", auth);
  TEST_ASSERT_TRUE(r.body.find("\"learning\":true") != std::string::npos);

  bridge::Capture c;
  c.durationsUs = {9010, 4490, 560};
  c.atMs = rig.now + 500;
  rig.bridge.onCapture(c);
  std::vector<std::string> msgs = rig.wsMessages();
  TEST_ASSERT_EQUAL_INT(1, msgs.size());
  TEST_ASSERT_EQUAL_STRING("capture", jsonString(msgs[0], "type").c_str());
  TEST_ASSERT_FALSE(rig.bridge.learning());
  // A second capture after learn mode ended is not streamed.
  rig.bridge.onCapture(c);
  TEST_ASSERT_EQUAL_INT(0, rig.wsMessages().size());
}

void test_learn_timeout_message() {
  Rig rig;
  const std::string auth = rig.pair();
  rig.wsMessages();
  TEST_ASSERT_EQUAL_INT(202, rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":1000}", auth).status);
  rig.bridge.tick(rig.now + 999);
  TEST_ASSERT_TRUE(rig.bridge.learning());
  TEST_ASSERT_EQUAL_INT(0, rig.wsMessages().size());
  rig.bridge.tick(rig.now + 1000);
  TEST_ASSERT_FALSE(rig.bridge.learning());
  const std::vector<std::string> msgs = rig.wsMessages();
  TEST_ASSERT_EQUAL_INT(1, msgs.size());
  TEST_ASSERT_EQUAL_STRING("{\"type\":\"learn_timeout\"}", msgs[0].c_str());
  // A capture arriving after the deadline is dropped, not streamed.
  TEST_ASSERT_EQUAL_INT(202, rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":1000}", auth).status);
  bridge::Capture late;
  late.durationsUs = {500};
  late.atMs = rig.now + 5000;
  rig.bridge.onCapture(late);
  const std::vector<std::string> after = rig.wsMessages();
  TEST_ASSERT_EQUAL_INT(1, after.size());
  TEST_ASSERT_EQUAL_STRING("{\"type\":\"learn_timeout\"}", after[0].c_str());
}

void test_capture_mode_streams_until_delete() {
  Rig rig;
  const std::string auth = rig.pair();
  rig.wsMessages();
  TEST_ASSERT_EQUAL_INT(202, rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":0}", auth).status);
  TEST_ASSERT_TRUE(rig.bridge.learnMode() == bridge::LearnMode::Capture);
  TEST_ASSERT_TRUE(rig.bridge.ledPattern(rig.now) == bridge::LedPattern::Solid ||
                   rig.bridge.ledPattern(rig.now) == bridge::LedPattern::PairingBlink);
  bridge::Capture c;
  c.durationsUs = {9010, 4490, 560};
  c.decoded.protocol = "NEC";
  c.decoded.bits = 32;
  c.decoded.value = 0x20DF10EF;
  for (int i = 0; i < 5; ++i) {
    c.atMs = rig.now + 1000ULL * 3600 * static_cast<uint64_t>(i);  // hours apart: never times out
    rig.bridge.tick(c.atMs);
    rig.bridge.onCapture(c);
  }
  TEST_ASSERT_EQUAL_INT(5, rig.wsMessages().size());
  TEST_ASSERT_TRUE(rig.bridge.learning());
  const Response r = rig.respond(Method::Delete, "/v1/learn", "", auth);
  TEST_ASSERT_EQUAL_INT(200, r.status);
  TEST_ASSERT_EQUAL_STRING("{\"learning\":false}", r.body.c_str());
  const std::vector<std::string> msgs = rig.wsMessages();
  TEST_ASSERT_EQUAL_INT(1, msgs.size());
  TEST_ASSERT_EQUAL_STRING("{\"type\":\"learn_stopped\"}", msgs[0].c_str());
  // DELETE when idle: same answer, no message.
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Delete, "/v1/learn", "", auth).status);
  TEST_ASSERT_EQUAL_INT(0, rig.wsMessages().size());
}

void test_learn_request_replaces_running_session() {
  Rig rig;
  const std::string auth = rig.pair();
  TEST_ASSERT_EQUAL_INT(202, rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":0}", auth).status);
  TEST_ASSERT_EQUAL_INT(202, rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":2000}", auth).status);
  TEST_ASSERT_TRUE(rig.bridge.learnMode() == bridge::LearnMode::Learn);
  expectError(rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":\"x\"}", auth), 400, "bad_json");
  TEST_ASSERT_TRUE(rig.bridge.learnMode() == bridge::LearnMode::Learn);
}

void test_websocket_upgrade_requires_auth_and_upgrade() {
  Rig rig;
  const std::string auth = rig.pair();
  TEST_ASSERT_TRUE(rig.call(Method::Get, "/v1/ws", "", auth, true).action == Action::AcceptWebSocket);
  expectError(rig.call(Method::Get, "/v1/ws", "", "", true).response, 401, "unauthorized");
  expectError(rig.call(Method::Get, "/v1/ws", "", auth, false).response, 426, "upgrade_required");
  const bridge::Preflight pf = rig.bridge.preflight(Method::Get, "/v1/ws", auth, 0);
  TEST_ASSERT_TRUE(pf.ok);
  TEST_ASSERT_TRUE(pf.route == bridge::Route::WebSocket);
}

void test_long_press_revokes_tokens_and_closes_websockets() {
  Rig rig;
  const std::string a = rig.pair("phone a");
  const std::string b = rig.pair("phone b");
  rig.bridge.takeEvents();
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Get, "/v1/health", "", a).status);
  TEST_ASSERT_TRUE(rig.bridge.onButton(bridge::ButtonEvent::LongPress, rig.now));
  expectError(rig.respond(Method::Get, "/v1/health", "", a), 401, "unauthorized");
  expectError(rig.respond(Method::Get, "/v1/health", "", b), 401, "unauthorized");
  const std::vector<bridge::Event> events = rig.bridge.takeEvents();
  TEST_ASSERT_EQUAL_INT(1, events.size());
  TEST_ASSERT_TRUE(events[0].kind == bridge::Event::Kind::CloseWebSockets);
  TEST_ASSERT_TRUE(rig.bridge.ledPattern(rig.now + 10) == bridge::LedPattern::ClearedFlash);
  rig.bridge.tick(rig.now + 2000);
  TEST_ASSERT_TRUE(rig.bridge.ledPattern(rig.now + 2000) == bridge::LedPattern::Off);
}

void test_all_error_bodies_have_contract_shape() {
  Rig rig;
  const std::string auth = rig.pair();
  const struct {
    Method m;
    const char* path;
    const char* body;
    const char* auth;
  } cases[] = {
      {Method::Get, "/x", "", ""},
      {Method::Delete, "/v1/info", "", ""},
      {Method::Get, "/v1/health", "", ""},
      {Method::Post, "/v1/pair", "{\"client\":\"x\"}", ""},
      {Method::Post, "/v1/pair", "{", ""},
      {Method::Post, "/v1/send/raw", "[]", auth.c_str()},
      {Method::Post, "/v1/learn", "{\"timeoutMs\":-1}", auth.c_str()},
      {Method::Post, "/v1/send/ac", "{}", auth.c_str()},
      {Method::Get, "/v1/ws", "", auth.c_str()},
  };
  for (const auto& c : cases) {
    const Response r = rig.respond(c.m, c.path, c.body, c.auth);
    TEST_ASSERT_TRUE_MESSAGE(r.status >= 400, c.path);
    TEST_ASSERT_TRUE_MESSAGE(isErrorShape(r.body), r.body.c_str());
  }
}

}  // namespace

void run_api_tests() {
  RUN_TEST(test_info_needs_no_auth_and_matches_contract);
  RUN_TEST(test_unknown_route_is_404_without_auth);
  RUN_TEST(test_wrong_method_is_405_with_allow_header);
  RUN_TEST(test_protected_routes_reject_missing_and_unknown_tokens);
  RUN_TEST(test_valid_token_and_header_variants);
  RUN_TEST(test_health_body);
  RUN_TEST(test_body_over_16k_is_413_before_auth);
  RUN_TEST(test_send_raw_transmit_busy_and_finish);
  RUN_TEST(test_send_raw_errors_through_router);
  RUN_TEST(test_send_ac_is_501_in_v1);
  RUN_TEST(test_learn_first_capture_ends_learn_mode);
  RUN_TEST(test_learn_timeout_message);
  RUN_TEST(test_capture_mode_streams_until_delete);
  RUN_TEST(test_learn_request_replaces_running_session);
  RUN_TEST(test_websocket_upgrade_requires_auth_and_upgrade);
  RUN_TEST(test_long_press_revokes_tokens_and_closes_websockets);
  RUN_TEST(test_all_error_bodies_have_contract_shape);
}
