// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Fakes and helpers shared by the native tests.
#pragma once

#include <unity.h>

#include <cstdint>
#include <string>
#include <vector>

#include "bridge_core.h"

namespace testsupport {

using bridge::Method;

struct MemoryStorage : bridge::TokenStorage {
  std::string blob;
  bool failLoad = false;
  bool failSave = false;
  int saves = 0;
  bool loadBlob(std::string& out) override {
    if (failLoad) return false;
    out = blob;
    return true;
  }
  bool saveBlob(const std::string& b) override {
    if (failSave) return false;
    blob = b;
    ++saves;
    return true;
  }
};

// Deterministic "random" bytes (splitmix64). Tests never need real entropy.
struct FakePlatform : bridge::Platform {
  uint64_t state = 0x1234567890abcdefULL;
  bool stuck = false;  // always the same bytes, to exercise collision handling
  void randomBytes(uint8_t* out, size_t len) override {
    for (size_t i = 0; i < len; ++i) {
      if (stuck) {
        out[i] = 0x42;
        continue;
      }
      state += 0x9e3779b97f4a7c15ULL;
      uint64_t z = state;
      z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
      z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
      out[i] = static_cast<uint8_t>(z ^ (z >> 31));
    }
  }
  int32_t rssiDbm() override { return -55; }
  uint32_t freeHeapBytes() override { return 123456; }
};

struct FakeOta : bridge::OtaTarget {
  size_t capacity = 64 * 1024;
  std::vector<uint8_t> written;
  bool begun = false;
  bool finalized = false;
  bool activated = false;
  int aborts = 0;
  bool failBegin = false;
  bool failWriteAt = false;
  size_t failWriteOffset = 0;
  bool failFinalize = false;
  bool failActivate = false;

  size_t capacityBytes() override { return capacity; }
  bool begin(size_t) override {
    if (failBegin) return false;
    begun = true;
    written.clear();
    return true;
  }
  bool write(const uint8_t* data, size_t len) override {
    if (failWriteAt && written.size() + len > failWriteOffset) return false;
    written.insert(written.end(), data, data + len);
    return true;
  }
  bool finalize() override {
    if (failFinalize) {
      begun = false;
      return false;
    }
    finalized = true;
    return true;
  }
  bool activate() override {
    if (failActivate) return false;
    activated = true;
    return true;
  }
  void abort() override {
    ++aborts;
    begun = false;
  }
};

inline bridge::Identity testIdentity() {
  bridge::Identity id;
  id.id = "a1b2c3d4e5f6";
  id.name = "IR Bridge";
  id.fw = "0.1.0";
  return id;
}

// Reads a top-level string field from a JSON object ("<missing>" if absent).
inline std::string jsonString(const std::string& body, const char* name) {
  bridge::json::Reader r(body);
  if (!r.enterObject()) return "<not an object>";
  std::string key;
  while (r.nextMember(key)) {
    if (key == name && r.peekType() == bridge::json::Type::String) {
      std::string v;
      r.readString(&v, 1 << 16, nullptr);
      return v;
    }
    if (!r.skipValue()) break;
  }
  return "<missing>";
}

inline std::string errorCode(const bridge::Response& r) { return jsonString(r.body, "error"); }

// Every error body must be exactly {"error": <string>, "detail": <string>}.
inline bool isErrorShape(const std::string& body) {
  bridge::json::Reader r(body);
  if (!r.enterObject()) return false;
  std::string key;
  int fields = 0;
  bool sawError = false, sawDetail = false;
  while (r.nextMember(key)) {
    ++fields;
    if (r.peekType() != bridge::json::Type::String) return false;
    if (!r.readString(nullptr, 0, nullptr)) return false;
    if (key == "error") sawError = true;
    if (key == "detail") sawDetail = true;
  }
  return r.ok() && r.expectEnd() && fields == 2 && sawError && sawDetail;
}

struct Rig {
  MemoryStorage storage;
  FakePlatform platform;
  FakeOta ota;
  bridge::Bridge bridge;
  uint64_t now = 1000;

  Rig() : bridge(testIdentity(), storage, platform, &ota) { bridge.begin(); }

  bridge::Outcome call(Method method, const std::string& path, const std::string& body = "",
                       const std::string& auth = "", bool upgrade = false) {
    bridge::Request req;
    req.method = method;
    req.path = path;
    req.body = body;
    req.contentLength = body.size();
    req.authorization = auth;
    req.webSocketUpgrade = upgrade;
    return bridge.handle(req, now);
  }

  bridge::Response respond(Method method, const std::string& path, const std::string& body = "",
                           const std::string& auth = "") {
    return call(method, path, body, auth).response;
  }

  // Short press + POST /v1/pair; returns "Bearer <token>".
  std::string pair(const std::string& client = "Pixel 8") {
    bridge.onButton(bridge::ButtonEvent::ShortPress, now);
    const bridge::Response r =
        respond(Method::Post, "/v1/pair", "{\"client\":\"" + client + "\"}");
    TEST_ASSERT_EQUAL_INT(200, r.status);
    const std::string token = jsonString(r.body, "token");
    TEST_ASSERT_TRUE(bridge::isTokenFormat(token));
    return "Bearer " + token;
  }

  std::vector<std::string> wsMessages() {
    std::vector<std::string> out;
    for (const bridge::Event& e : bridge.takeEvents()) {
      if (e.kind == bridge::Event::Kind::WebSocketText) out.push_back(e.text);
    }
    return out;
  }
};

// Small deterministic PRNG for fuzz tests.
struct Prng {
  uint64_t s;
  explicit Prng(uint64_t seed) : s(seed ? seed : 1) {}
  uint64_t next() {
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    return s;
  }
  uint32_t below(uint32_t n) { return n == 0 ? 0 : static_cast<uint32_t>(next() % n); }
};

}  // namespace testsupport

// Test groups, one per file; called from test_main.cpp.
void run_json_tests();
void run_signal_tests();
void run_api_tests();
void run_pairing_tests();
void run_ota_tests();
void run_provisioning_tests();
void run_fuzz_tests();
