// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// SHA-256 vectors and the streamed OTA path.
#include "test_support.h"

using bridge::Method;
using bridge::Response;
using bridge::Sha256;
using testsupport::errorCode;
using testsupport::Rig;

namespace {

std::string sha(const std::string& s) {
  return Sha256::hexDigest(reinterpret_cast<const uint8_t*>(s.data()), s.size());
}

void test_sha256_fips_vectors() {
  TEST_ASSERT_EQUAL_STRING("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                           sha("").c_str());
  TEST_ASSERT_EQUAL_STRING("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                           sha("abc").c_str());
  TEST_ASSERT_EQUAL_STRING(
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      sha("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").c_str());
  TEST_ASSERT_EQUAL_STRING(
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
      sha("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")
          .c_str());
  // One million 'a' bytes, fed in uneven chunks.
  Sha256 h;
  const std::string chunk(997, 'a');
  size_t left = 1000000;
  while (left > 0) {
    const size_t n = left < chunk.size() ? left : chunk.size();
    h.update(reinterpret_cast<const uint8_t*>(chunk.data()), n);
    left -= n;
  }
  uint8_t d[32];
  h.finish(d);
  TEST_ASSERT_EQUAL_STRING("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
                           bridge::toHex(d, 32).c_str());
}

void test_sha256_chunking_is_irrelevant() {
  std::string data;
  for (int i = 0; i < 1000; ++i) data += static_cast<char>(i * 7 + 3);
  const std::string whole = sha(data);
  for (size_t step = 1; step < 130; step += 7) {
    Sha256 h;
    for (size_t off = 0; off < data.size(); off += step) {
      const size_t n = (data.size() - off) < step ? data.size() - off : step;
      h.update(reinterpret_cast<const uint8_t*>(data.data()) + off, n);
    }
    uint8_t d[32];
    h.finish(d);
    TEST_ASSERT_EQUAL_STRING(whole.c_str(), bridge::toHex(d, 32).c_str());
  }
  // Every length around the 55/56/64-byte padding boundaries.
  for (size_t len = 50; len < 140; ++len) {
    const std::string s(len, 'x');
    TEST_ASSERT_EQUAL_INT(64, sha(s).size());
  }
}

void test_hex_helpers() {
  uint8_t out[2];
  TEST_ASSERT_TRUE(bridge::fromHex("aB09", out, 2));
  TEST_ASSERT_EQUAL_INT(0xAB, out[0]);
  TEST_ASSERT_EQUAL_INT(0x09, out[1]);
  TEST_ASSERT_FALSE(bridge::fromHex("aB0", out, 2));
  TEST_ASSERT_FALSE(bridge::fromHex("zz00", out, 2));
}

struct OtaRig : Rig {
  std::string auth;
  std::vector<uint8_t> image;
  OtaRig() {
    auth = pair();
    for (int i = 0; i < 5000; ++i) image.push_back(static_cast<uint8_t>((i * 31) ^ (i >> 3)));
  }
  bridge::OtaRequest request(const std::string& digest) const {
    bridge::OtaRequest r;
    r.authorization = auth;
    r.sha256Header = digest;
    r.hasContentLength = true;
    r.contentLength = image.size();
    return r;
  }
  std::string digest() const { return Sha256::hexDigest(image.data(), image.size()); }
  bool stream(size_t chunk) {
    for (size_t off = 0; off < image.size(); off += chunk) {
      const size_t n = (image.size() - off) < chunk ? image.size() - off : chunk;
      if (!bridge.otaWrite(image.data() + off, n)) return false;
    }
    return true;
  }
};

void test_ota_happy_path() {
  OtaRig rig;
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.bridge.otaActive());
  TEST_ASSERT_TRUE(rig.stream(1460));
  const Response r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_INT(200, r.status);
  TEST_ASSERT_EQUAL_STRING("{\"updated\":true,\"rebooting\":true}", r.body.c_str());
  TEST_ASSERT_TRUE(rig.ota.finalized);
  TEST_ASSERT_TRUE(rig.ota.activated);
  TEST_ASSERT_TRUE(rig.ota.written == rig.image);
  TEST_ASSERT_TRUE(rig.bridge.rebootRequested());
  TEST_ASSERT_FALSE(rig.bridge.otaActive());
}

void test_ota_uppercase_digest_accepted() {
  OtaRig rig;
  std::string upper = rig.digest();
  for (char& c : upper) {
    if (c >= 'a' && c <= 'f') c = static_cast<char>(c - 32);
  }
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(" " + upper + " "), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.stream(4096));
  TEST_ASSERT_EQUAL_INT(200, rig.bridge.otaFinish().status);
}

void test_ota_hash_mismatch_never_activates() {
  OtaRig rig;
  std::string wrong = rig.digest();
  wrong[0] = (wrong[0] == '0') ? '1' : '0';
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(wrong), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.stream(512));
  const Response r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_INT(400, r.status);
  TEST_ASSERT_EQUAL_STRING("hash_mismatch", errorCode(r).c_str());
  TEST_ASSERT_FALSE(rig.ota.finalized);
  TEST_ASSERT_FALSE(rig.ota.activated);
  TEST_ASSERT_EQUAL_INT(1, rig.ota.aborts);
  TEST_ASSERT_FALSE(rig.bridge.rebootRequested());
  TEST_ASSERT_FALSE(rig.bridge.otaActive());
}

void test_ota_corrupted_byte_is_detected() {
  OtaRig rig;
  const std::string good = rig.digest();
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(good), rig.now).has_value());
  rig.image[2500] ^= 0x01;  // flipped in transit
  TEST_ASSERT_TRUE(rig.stream(700));
  TEST_ASSERT_EQUAL_STRING("hash_mismatch", errorCode(rig.bridge.otaFinish()).c_str());
  TEST_ASSERT_FALSE(rig.ota.activated);
}

void test_ota_header_and_size_errors() {
  OtaRig rig;
  bridge::OtaRequest r = rig.request("abc");
  std::optional<Response> e = rig.bridge.otaBegin(r, rig.now);
  TEST_ASSERT_TRUE(e.has_value());
  TEST_ASSERT_EQUAL_INT(400, e->status);
  TEST_ASSERT_EQUAL_STRING("bad_request", errorCode(*e).c_str());

  r = rig.request(rig.digest());
  r.hasContentLength = false;
  e = rig.bridge.otaBegin(r, rig.now);
  TEST_ASSERT_EQUAL_STRING("bad_request", errorCode(*e).c_str());

  r = rig.request(rig.digest());
  r.contentLength = 0;
  e = rig.bridge.otaBegin(r, rig.now);
  TEST_ASSERT_EQUAL_STRING("bad_request", errorCode(*e).c_str());

  r = rig.request(rig.digest());
  r.contentLength = rig.ota.capacity + 1;
  e = rig.bridge.otaBegin(r, rig.now);
  TEST_ASSERT_EQUAL_INT(413, e->status);
  TEST_ASSERT_EQUAL_STRING("too_large", errorCode(*e).c_str());

  r = rig.request(rig.digest());
  r.authorization = "Bearer 0123456789abcdef0123456789abcdef";
  e = rig.bridge.otaBegin(r, rig.now);
  TEST_ASSERT_EQUAL_INT(401, e->status);

  rig.ota.failBegin = true;
  e = rig.bridge.otaBegin(rig.request(rig.digest()), rig.now);
  TEST_ASSERT_EQUAL_INT(500, e->status);
  TEST_ASSERT_EQUAL_STRING("ota_failed", errorCode(*e).c_str());
  TEST_ASSERT_FALSE(rig.bridge.otaActive());
}

void test_ota_length_mismatches() {
  OtaRig rig;
  // Short body.
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.bridge.otaWrite(rig.image.data(), 100));
  Response r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_STRING("bad_request", errorCode(r).c_str());
  TEST_ASSERT_FALSE(rig.ota.activated);
  // Long body.
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.stream(1000));
  const uint8_t extra = 0;
  TEST_ASSERT_FALSE(rig.bridge.otaWrite(&extra, 1));
  r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_STRING("bad_request", errorCode(r).c_str());
  TEST_ASSERT_FALSE(rig.ota.activated);
}

void test_ota_flash_failures() {
  OtaRig rig;
  rig.ota.failWriteAt = true;
  rig.ota.failWriteOffset = 2000;
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  TEST_ASSERT_FALSE(rig.stream(1000));
  Response r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_INT(500, r.status);
  TEST_ASSERT_EQUAL_STRING("ota_failed", errorCode(r).c_str());

  rig.ota.failWriteAt = false;
  rig.ota.failFinalize = true;
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.stream(1000));
  r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_STRING("bad_image", errorCode(r).c_str());
  TEST_ASSERT_FALSE(rig.ota.activated);

  rig.ota.failFinalize = false;
  rig.ota.failActivate = true;
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  TEST_ASSERT_TRUE(rig.stream(1000));
  r = rig.bridge.otaFinish();
  TEST_ASSERT_EQUAL_STRING("ota_failed", errorCode(r).c_str());
  TEST_ASSERT_FALSE(rig.bridge.rebootRequested());
}

void test_ota_busy_interlocks() {
  OtaRig rig;
  // A transmission blocks an update ...
  const bridge::Outcome tx = rig.call(Method::Post, "/v1/send/raw",
                                      "{\"carrierHz\":38000,\"durationsUs\":[500]}", rig.auth);
  TEST_ASSERT_TRUE(tx.action == bridge::Action::Transmit);
  std::optional<Response> e = rig.bridge.otaBegin(rig.request(rig.digest()), rig.now);
  TEST_ASSERT_EQUAL_INT(409, e->status);
  rig.bridge.finishTransmit(500);
  // ... and an update blocks transmissions and a second update.
  TEST_ASSERT_FALSE(rig.bridge.otaBegin(rig.request(rig.digest()), rig.now).has_value());
  const Response busy = rig.respond(Method::Post, "/v1/send/raw",
                                    "{\"carrierHz\":38000,\"durationsUs\":[500]}", rig.auth);
  TEST_ASSERT_EQUAL_INT(409, busy.status);
  TEST_ASSERT_EQUAL_STRING("busy", errorCode(busy).c_str());
  e = rig.bridge.otaBegin(rig.request(rig.digest()), rig.now);
  TEST_ASSERT_EQUAL_INT(409, e->status);
  // Client disconnects mid-upload.
  rig.bridge.otaAbort();
  TEST_ASSERT_FALSE(rig.bridge.otaActive());
  TEST_ASSERT_EQUAL_INT(1, rig.ota.aborts);
  TEST_ASSERT_FALSE(rig.bridge.otaWrite(rig.image.data(), 10));
  TEST_ASSERT_EQUAL_STRING("bad_request", errorCode(rig.bridge.otaFinish()).c_str());
}

void test_ota_route_through_handle_is_not_body_capped() {
  Rig rig;
  const std::string auth = rig.pair();
  const bridge::Preflight pf =
      rig.bridge.preflight(Method::Post, "/v1/ota", auth, 1500000);  // 1.5 MB image
  TEST_ASSERT_TRUE(pf.ok);
  TEST_ASSERT_TRUE(pf.route == bridge::Route::Ota);
}

}  // namespace

void run_ota_tests() {
  RUN_TEST(test_sha256_fips_vectors);
  RUN_TEST(test_sha256_chunking_is_irrelevant);
  RUN_TEST(test_hex_helpers);
  RUN_TEST(test_ota_happy_path);
  RUN_TEST(test_ota_uppercase_digest_accepted);
  RUN_TEST(test_ota_hash_mismatch_never_activates);
  RUN_TEST(test_ota_corrupted_byte_is_detected);
  RUN_TEST(test_ota_header_and_size_errors);
  RUN_TEST(test_ota_length_mismatches);
  RUN_TEST(test_ota_flash_failures);
  RUN_TEST(test_ota_busy_interlocks);
  RUN_TEST(test_ota_route_through_handle_is_not_body_capped);
}
