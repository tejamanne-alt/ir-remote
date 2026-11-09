// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Pairing window, BOOT button, token store and its persistence.
#include <cstdio>

#include "test_support.h"

using bridge::ButtonEvent;
using bridge::ButtonTracker;
using bridge::Method;
using bridge::Response;
using testsupport::errorCode;
using testsupport::jsonString;
using testsupport::MemoryStorage;
using testsupport::Rig;

namespace {

void test_pair_requires_open_window() {
  Rig rig;
  const Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"Pixel 8\"}");
  TEST_ASSERT_EQUAL_INT(403, r.status);
  TEST_ASSERT_EQUAL_STRING("pairing_window_closed", errorCode(r).c_str());
  TEST_ASSERT_EQUAL_INT(0, rig.bridge.pairedClients());
}

void test_pair_issues_token_and_closes_window() {
  Rig rig;
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  TEST_ASSERT_TRUE(rig.bridge.pairingWindowOpen(rig.now));
  const Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"Pixel 8\"}");
  TEST_ASSERT_EQUAL_INT(200, r.status);
  const std::string token = jsonString(r.body, "token");
  TEST_ASSERT_TRUE(bridge::isTokenFormat(token));
  TEST_ASSERT_EQUAL_STRING(("{\"token\":\"" + token + "\"}").c_str(), r.body.c_str());
  TEST_ASSERT_FALSE(rig.bridge.pairingWindowOpen(rig.now));
  const Response again = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"Other\"}");
  TEST_ASSERT_EQUAL_STRING("pairing_window_closed", errorCode(again).c_str());
  TEST_ASSERT_EQUAL_INT(1, rig.bridge.pairedClients());
  TEST_ASSERT_TRUE(rig.storage.blob.find(token) != std::string::npos);
  TEST_ASSERT_TRUE(rig.storage.blob.find("Pixel 8") != std::string::npos);
}

void test_pairing_window_lasts_60_seconds() {
  Rig rig;
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  const uint64_t opened = rig.now;
  rig.now = opened + 59999;
  TEST_ASSERT_TRUE(rig.bridge.pairingWindowOpen(rig.now));
  TEST_ASSERT_TRUE(rig.bridge.ledPattern(rig.now) == bridge::LedPattern::PairingBlink);
  rig.now = opened + 60000;
  TEST_ASSERT_FALSE(rig.bridge.pairingWindowOpen(rig.now));
  const Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"late\"}");
  TEST_ASSERT_EQUAL_STRING("pairing_window_closed", errorCode(r).c_str());
  // A new press re-opens it.
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Post, "/v1/pair", "{\"client\":\"ok\"}").status);
}

void test_bad_pair_body_keeps_window_open() {
  Rig rig;
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  const Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":7}");
  TEST_ASSERT_EQUAL_STRING("bad_json", errorCode(r).c_str());
  TEST_ASSERT_TRUE(rig.bridge.pairingWindowOpen(rig.now));
}

void test_ninth_client_gets_507_until_long_press() {
  Rig rig;
  for (int i = 0; i < 8; ++i) rig.pair("client " + std::to_string(i));
  TEST_ASSERT_EQUAL_INT(8, rig.bridge.pairedClients());
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"ninth\"}");
  TEST_ASSERT_EQUAL_INT(507, r.status);
  TEST_ASSERT_EQUAL_STRING("pairing_full", errorCode(r).c_str());
  rig.bridge.onButton(ButtonEvent::LongPress, rig.now);
  TEST_ASSERT_EQUAL_INT(0, rig.bridge.pairedClients());
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"ninth\"}");
  TEST_ASSERT_EQUAL_INT(200, r.status);
}

void test_tokens_survive_restart() {
  MemoryStorage storage;
  testsupport::FakePlatform platform;
  std::string auth;
  {
    bridge::Bridge first(testsupport::testIdentity(), storage, platform);
    TEST_ASSERT_TRUE(first.begin());
    first.onButton(ButtonEvent::ShortPress, 0);
    bridge::Request req;
    req.method = Method::Post;
    req.path = "/v1/pair";
    req.body = "{\"client\":\"tablet\"}";
    const Response r = first.handle(req, 10).response;
    TEST_ASSERT_EQUAL_INT(200, r.status);
    auth = "Bearer " + jsonString(r.body, "token");
  }
  bridge::Bridge second(testsupport::testIdentity(), storage, platform);
  TEST_ASSERT_TRUE(second.begin());
  TEST_ASSERT_EQUAL_INT(1, second.pairedClients());
  bridge::Request health;
  health.path = "/v1/health";
  health.authorization = auth;
  TEST_ASSERT_EQUAL_INT(200, second.handle(health, 20).response.status);
}

void test_storage_failures() {
  Rig rig;
  rig.storage.failSave = true;
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  const Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"x\"}");
  TEST_ASSERT_EQUAL_INT(500, r.status);
  TEST_ASSERT_EQUAL_STRING("storage_error", errorCode(r).c_str());
  TEST_ASSERT_EQUAL_INT(0, rig.bridge.pairedClients());
  TEST_ASSERT_TRUE(rig.bridge.pairingWindowOpen(rig.now));

  MemoryStorage broken;
  broken.failLoad = true;
  testsupport::FakePlatform platform;
  bridge::Bridge b(testsupport::testIdentity(), broken, platform);
  TEST_ASSERT_FALSE(b.begin());
  TEST_ASSERT_EQUAL_INT(0, b.pairedClients());
}

void test_cleared_tokens_are_saved_even_after_a_storage_error() {
  Rig rig;
  const std::string auth = rig.pair();
  rig.storage.failSave = true;
  TEST_ASSERT_FALSE(rig.bridge.onButton(ButtonEvent::LongPress, rig.now));
  TEST_ASSERT_TRUE(rig.bridge.storageErrorPending());
  TEST_ASSERT_EQUAL_INT(401, rig.respond(Method::Get, "/v1/health", "", auth).status);
  rig.now += 2010;  // past the 2 s "cleared" flash
  rig.bridge.tick(rig.now);
  TEST_ASSERT_TRUE(rig.bridge.ledPattern(rig.now) == bridge::LedPattern::StorageError);
  // Storage recovers: the next retry writes the empty list.
  rig.storage.failSave = false;
  rig.now += bridge::kStorageRetryMs;
  rig.bridge.tick(rig.now);
  TEST_ASSERT_FALSE(rig.bridge.storageErrorPending());
  TEST_ASSERT_TRUE(rig.bridge.ledPattern(rig.now) == bridge::LedPattern::Off);
  // After a restart the old token stays revoked.
  bridge::Bridge restarted(testsupport::testIdentity(), rig.storage, rig.platform);
  TEST_ASSERT_TRUE(restarted.begin());
  TEST_ASSERT_EQUAL_INT(0, restarted.pairedClients());
}

void test_websocket_auth_frame() {
  Rig rig;
  const std::string auth = rig.pair();
  const std::string token = auth.substr(7);
  TEST_ASSERT_TRUE(rig.bridge.authorizeWebSocketFrame("{\"type\":\"auth\",\"token\":\"" + token + "\"}"));
  TEST_ASSERT_TRUE(
      rig.bridge.authorizeWebSocketFrame(" {\"token\":\"" + token + "\", \"x\":[1], \"type\":\"auth\"} "));
  const char* bad[] = {
      "",
      "auth",
      "{}",
      "{\"type\":\"auth\"}",
      "{\"type\":\"auth\",\"token\":\"ffffffffffffffffffffffffffffffff\"}",
      "{\"type\":\"auth\",\"token\":7}",
      "[\"auth\"]",
  };
  for (const char* b : bad) TEST_ASSERT_TRUE_MESSAGE(!rig.bridge.authorizeWebSocketFrame(b), b);
  TEST_ASSERT_FALSE(rig.bridge.authorizeWebSocketFrame("{\"type\":\"other\",\"token\":\"" + token + "\"}"));
  TEST_ASSERT_FALSE(rig.bridge.authorizeWebSocketFrame("{\"type\":\"auth\",\"token\":\"" + token + "0\"}"));
  TEST_ASSERT_FALSE(rig.bridge.authorizeWebSocketFrame("{\"type\":\"auth\",\"token\":\"" + token + "\"} x"));
  TEST_ASSERT_FALSE(rig.bridge.authorizeWebSocketFrame(
      "{\"type\":\"auth\",\"pad\":\"" + std::string(300, 'a') + "\",\"token\":\"" + token + "\"}"));
  rig.bridge.onButton(ButtonEvent::LongPress, rig.now);
  TEST_ASSERT_FALSE(rig.bridge.authorizeWebSocketFrame("{\"type\":\"auth\",\"token\":\"" + token + "\"}"));
}

void test_random_collision_is_handled() {
  Rig rig;
  rig.platform.stuck = true;  // every token would be identical
  rig.pair("first");
  rig.bridge.onButton(ButtonEvent::ShortPress, rig.now);
  const Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"second\"}");
  TEST_ASSERT_EQUAL_INT(500, r.status);
  TEST_ASSERT_EQUAL_INT(1, rig.bridge.pairedClients());
}

void test_serialization_round_trip_and_corruption() {
  std::vector<bridge::PairedClient> in = {
      {"0123456789abcdef0123456789abcdef", "Pixel 8"},
      {"fedcba9876543210fedcba9876543210", "iPhone \xc3\xa9"},
  };
  std::vector<bridge::PairedClient> out;
  TEST_ASSERT_TRUE(bridge::parseClients(bridge::serializeClients(in), out));
  TEST_ASSERT_EQUAL_INT(2, out.size());
  TEST_ASSERT_EQUAL_STRING("iPhone \xc3\xa9", out[1].client.c_str());

  TEST_ASSERT_TRUE(bridge::parseClients("", out));
  TEST_ASSERT_EQUAL_INT(0, out.size());
  TEST_ASSERT_FALSE(bridge::parseClients("garbage", out));
  TEST_ASSERT_EQUAL_INT(0, out.size());
  // Bad records are dropped, good ones kept, duplicates collapsed.
  const std::string mixed = std::string("irbtok1\n") +
                            "0123456789abcdef0123456789abcdef\tok\n"
                            "0123456789ABCDEF0123456789ABCDEF\tupper\n"
                            "short\tx\n"
                            "no tab here\n"
                            "0123456789abcdef0123456789abcdef\tdup\n"
                            "11111111111111111111111111111111\t\n"
                            "22222222222222222222222222222222\tlast";
  TEST_ASSERT_TRUE(bridge::parseClients(mixed, out));
  TEST_ASSERT_EQUAL_INT(2, out.size());
  TEST_ASSERT_EQUAL_STRING("ok", out[0].client.c_str());
  TEST_ASSERT_EQUAL_STRING("last", out[1].client.c_str());
  // Never more than 8.
  std::string many = "irbtok1\n";
  for (int i = 0; i < 20; ++i) {
    char tok[33];
    std::snprintf(tok, sizeof tok, "%032x", i + 1);
    many += std::string(tok) + "\tc\n";
  }
  TEST_ASSERT_TRUE(bridge::parseClients(many, out));
  TEST_ASSERT_EQUAL_INT(8, out.size());
}

void test_bearer_parsing() {
  std::string t;
  TEST_ASSERT_TRUE(bridge::parseBearer("Bearer abc", t));
  TEST_ASSERT_EQUAL_STRING("abc", t.c_str());
  TEST_ASSERT_TRUE(bridge::parseBearer("bEaReR\t\tabc \t", t));
  TEST_ASSERT_EQUAL_STRING("abc", t.c_str());
  TEST_ASSERT_FALSE(bridge::parseBearer("", t));
  TEST_ASSERT_FALSE(bridge::parseBearer("Bearer", t));
  TEST_ASSERT_FALSE(bridge::parseBearer("Bearer   ", t));
  TEST_ASSERT_FALSE(bridge::parseBearer("Bearerabc", t));
  TEST_ASSERT_FALSE(bridge::parseBearer("Bear abc", t));
  TEST_ASSERT_FALSE(bridge::parseBearer("Bearer a b", t));
  TEST_ASSERT_FALSE(bridge::parseBearer("Basic abc", t));
  TEST_ASSERT_TRUE(bridge::constantTimeEquals("abc", "abc"));
  TEST_ASSERT_FALSE(bridge::constantTimeEquals("abc", "abd"));
  TEST_ASSERT_FALSE(bridge::constantTimeEquals("abc", "abcd"));
}

void test_button_short_press_with_debounce() {
  ButtonTracker b;
  uint64_t t = 0;
  TEST_ASSERT_TRUE(b.update(false, t) == ButtonEvent::None);
  // Contact bounce shorter than the debounce time is ignored.
  for (int i = 0; i < 10; ++i) {
    t += 2;
    TEST_ASSERT_TRUE(b.update(i % 2 == 0, t) == ButtonEvent::None);
  }
  TEST_ASSERT_FALSE(b.pressed());
  t += 100;
  TEST_ASSERT_TRUE(b.update(false, t) == ButtonEvent::None);
  // Press for 300 ms.
  TEST_ASSERT_TRUE(b.update(true, t) == ButtonEvent::None);
  t += 40;
  TEST_ASSERT_TRUE(b.update(true, t) == ButtonEvent::None);
  TEST_ASSERT_TRUE(b.pressed());
  t += 260;
  TEST_ASSERT_TRUE(b.update(false, t) == ButtonEvent::None);
  t += 40;
  TEST_ASSERT_TRUE(b.update(false, t) == ButtonEvent::ShortPress);
  t += 40;
  TEST_ASSERT_TRUE(b.update(false, t) == ButtonEvent::None);
}

void test_button_long_and_factory_reset_press() {
  ButtonTracker b;
  uint64_t t = 1000;
  b.update(true, t);
  int longs = 0, resets = 0, shorts = 0;
  for (int i = 0; i < 1700; ++i) {  // 17 s held, sampled every 10 ms
    t += 10;
    const ButtonEvent e = b.update(true, t);
    if (e == ButtonEvent::LongPress) {
      ++longs;
      TEST_ASSERT_GREATER_OR_EQUAL(1000 + bridge::kLongPressMs, t);
      TEST_ASSERT_LESS_OR_EQUAL(1000 + bridge::kLongPressMs + 10, t);
    }
    if (e == ButtonEvent::FactoryResetPress) ++resets;
    if (e == ButtonEvent::ShortPress) ++shorts;
  }
  for (int i = 0; i < 10; ++i) {
    t += 10;
    if (b.update(false, t) == ButtonEvent::ShortPress) ++shorts;
  }
  TEST_ASSERT_EQUAL_INT(1, longs);
  TEST_ASSERT_EQUAL_INT(1, resets);
  TEST_ASSERT_EQUAL_INT(0, shorts);  // releasing after a long press is not a short press
}

void test_button_4999ms_is_still_short() {
  ButtonTracker b;
  uint64_t t = 0;
  b.update(true, t);
  t = 4990;
  TEST_ASSERT_TRUE(b.update(true, t) == ButtonEvent::None);
  b.update(false, t);
  // The 5 s mark passes while the release is being debounced: still short.
  for (int i = 0; i < 4; ++i) {
    t += 10;
    const ButtonEvent e = b.update(false, t);
    TEST_ASSERT_TRUE(e != ButtonEvent::LongPress);
    if (e == ButtonEvent::ShortPress) return;
  }
  TEST_FAIL_MESSAGE("no short press after release");
}

void test_pairing_window_class() {
  bridge::PairingWindow w(1000);
  TEST_ASSERT_FALSE(w.isOpen(0));
  w.open(5000);
  TEST_ASSERT_TRUE(w.isOpen(5000));
  TEST_ASSERT_EQUAL_UINT64(500, w.remainingMs(5500));
  TEST_ASSERT_FALSE(w.isOpen(6000));
  TEST_ASSERT_TRUE(w.isOpen(4000) == true);  // clock stepped back: still within the window
  w.tick(7000);
  TEST_ASSERT_FALSE(w.isOpen(5001));  // tick closed it for good
}

void test_led_patterns() {
  TEST_ASSERT_FALSE(bridge::ledLevel(bridge::LedPattern::Off, 0));
  TEST_ASSERT_TRUE(bridge::ledLevel(bridge::LedPattern::Solid, 12345));
  TEST_ASSERT_TRUE(bridge::ledLevel(bridge::LedPattern::PairingBlink, 0));
  TEST_ASSERT_FALSE(bridge::ledLevel(bridge::LedPattern::PairingBlink, 250));
  TEST_ASSERT_TRUE(bridge::ledLevel(bridge::LedPattern::OfflineBlip, 4050));
  TEST_ASSERT_FALSE(bridge::ledLevel(bridge::LedPattern::OfflineBlip, 4150));
}

}  // namespace

void run_pairing_tests() {
  RUN_TEST(test_pair_requires_open_window);
  RUN_TEST(test_pair_issues_token_and_closes_window);
  RUN_TEST(test_pairing_window_lasts_60_seconds);
  RUN_TEST(test_bad_pair_body_keeps_window_open);
  RUN_TEST(test_ninth_client_gets_507_until_long_press);
  RUN_TEST(test_tokens_survive_restart);
  RUN_TEST(test_storage_failures);
  RUN_TEST(test_cleared_tokens_are_saved_even_after_a_storage_error);
  RUN_TEST(test_websocket_auth_frame);
  RUN_TEST(test_random_collision_is_handled);
  RUN_TEST(test_serialization_round_trip_and_corruption);
  RUN_TEST(test_bearer_parsing);
  RUN_TEST(test_button_short_press_with_debounce);
  RUN_TEST(test_button_long_and_factory_reset_press);
  RUN_TEST(test_button_4999ms_is_still_short);
  RUN_TEST(test_pairing_window_class);
  RUN_TEST(test_led_patterns);
}
