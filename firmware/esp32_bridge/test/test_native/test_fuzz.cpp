// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Fuzz-style tests: random and mutated input against the JSON parser, the
// body parsers and the router. Deterministic seeds, bounded sizes; the
// assertions are "no crash" (ASan/UBSan in tools/run_host_tests.sh), "answer
// is a contract status with a contract-shaped JSON body" and "limits hold".
#include "test_support.h"

using bridge::Action;
using bridge::Method;
using testsupport::isErrorShape;
using testsupport::Prng;
using testsupport::Rig;

namespace {

const char* const kSeeds[] = {
    "{\"carrierHz\":38000,\"durationsUs\":[9024,4512,564,564,564,1692,564]}",
    "{\"client\":\"Pixel 8\"}",
    "{\"timeoutMs\":15000}",
    "{\"timeoutMs\":0}",
    "{\"protocol\":\"daikin\",\"model\":0,\"state\":{\"power\":true,\"mode\":\"cool\",\"temp\":24,"
    "\"fan\":\"auto\",\"swing\":[false,null,1.5e3]}}",
    "{\"a\":\"\\u00e9\\uD83D\\uDE00\\n\",\"b\":[[],{},[{}]],\"c\":-0.5E-7}",
};

const char kAlphabet[] = "{}[]:,\"\\ -+.0123456789eEtrufalsn\t\r\nabcxyzU\xc3\xa9\xff\x00";

bool isContractStatus(int s) {
  switch (s) {
    case 200: case 202: case 400: case 401: case 403: case 404: case 405:
    case 409: case 413: case 426: case 500: case 501: case 507:
      return true;
    default:
      return false;
  }
}

std::string randomBytes(Prng& rng, size_t maxLen) {
  const size_t len = rng.below(static_cast<uint32_t>(maxLen + 1));
  std::string s;
  s.reserve(len);
  const bool structured = rng.below(2) == 0;
  for (size_t i = 0; i < len; ++i) {
    if (structured) {
      s += kAlphabet[rng.below(sizeof(kAlphabet) - 1)];
    } else {
      s += static_cast<char>(rng.below(256));
    }
  }
  return s;
}

std::string mutate(Prng& rng, std::string s) {
  const int edits = 1 + static_cast<int>(rng.below(8));
  for (int e = 0; e < edits; ++e) {
    const size_t pos = s.empty() ? 0 : rng.below(static_cast<uint32_t>(s.size()));
    switch (rng.below(9)) {
      case 0:  // flip a bit
        if (!s.empty()) s[pos] = static_cast<char>(s[pos] ^ (1 << rng.below(8)));
        break;
      case 1:  // insert a structural or random byte
        s.insert(s.begin() + static_cast<std::ptrdiff_t>(pos), kAlphabet[rng.below(sizeof(kAlphabet) - 1)]);
        break;
      case 2:  // delete a span
        if (!s.empty()) s.erase(pos, 1 + rng.below(8));
        break;
      case 3:  // truncate
        s.resize(pos);
        break;
      case 4:  // duplicate a span
        if (!s.empty()) s.insert(pos, s.substr(pos, 1 + rng.below(32)));
        break;
      case 5:  // deep nesting
        s.insert(pos, std::string(1 + rng.below(40), rng.below(2) ? '[' : '{'));
        break;
      case 6:  // a huge number
        s.insert(pos, std::string(1 + rng.below(400), static_cast<char>('0' + rng.below(10))));
        break;
      case 7:  // a long string
        s.insert(pos, "\"" + std::string(rng.below(300), 'x') + "\"");
        break;
      default:  // splice another seed
        s.insert(pos, kSeeds[rng.below(sizeof(kSeeds) / sizeof(kSeeds[0]))]);
        break;
    }
    if (s.size() > 20000) s.resize(20000);
  }
  return s;
}

const char* const kPaths[] = {"/v1/info", "/v1/health", "/v1/pair", "/v1/send/raw",
                              "/v1/send/ac", "/v1/learn", "/v1/ws", "/v1/ota"};
const Method kMethods[] = {Method::Get, Method::Post, Method::Delete, Method::Put, Method::Head};

// Sends one request and checks the answer; returns the HTTP status.
int exercise(Rig& rig, Method m, const std::string& path, const std::string& body,
             const std::string& auth, bool upgrade) {
  const bridge::Outcome o = rig.call(m, path, body, auth, upgrade);
  if (o.action == Action::Transmit) {
    TEST_ASSERT_TRUE(o.job.durationsUs.size() % 2 == 1);
    TEST_ASSERT_LESS_OR_EQUAL(bridge::kMaxDurations, o.job.durationsUs.size());
    TEST_ASSERT_LESS_OR_EQUAL(bridge::kMaxPatternUs, o.job.totalUs);
    TEST_ASSERT_TRUE(o.job.carrierHz >= bridge::kCarrierMinHz && o.job.carrierHz <= bridge::kCarrierMaxHz);
    const bridge::Response done = rig.bridge.finishTransmit(o.job.totalUs);
    TEST_ASSERT_TRUE(bridge::json::isValid(done.body));
    return 200;
  }
  if (o.action == Action::AcceptWebSocket) return 101;
  const bridge::Response& r = o.response;
  TEST_ASSERT_TRUE_MESSAGE(isContractStatus(r.status), r.body.c_str());
  TEST_ASSERT_TRUE_MESSAGE(bridge::json::isValid(r.body), r.body.c_str());
  if (r.status >= 400) TEST_ASSERT_TRUE_MESSAGE(isErrorShape(r.body), r.body.c_str());
  return r.status;
}

// Walks a document with every typed reader call (not only skipValue), the
// way the body parsers do. Bounded by the reader's own depth limit.
void walk(bridge::json::Reader& r, int depth) {
  using bridge::json::Type;
  std::string text;
  bool truncated = false;
  switch (r.peekType()) {
    case Type::Object: {
      if (!r.enterObject()) return;
      std::string key;
      int members = 0;
      while (r.nextMember(key, 8) && members++ < 2000) walk(r, depth + 1);
      return;
    }
    case Type::Array: {
      if (!r.enterArray()) return;
      int items = 0;
      while (r.nextElement() && items++ < 5000) walk(r, depth + 1);
      return;
    }
    case Type::String: r.readString(&text, 5, &truncated); return;
    case Type::Number: {
      bridge::json::Number n;
      if (r.readNumber(n) && n.integer) (void)n.asInt64();
      return;
    }
    case Type::True:
    case Type::False: {
      bool b = false;
      r.readBool(b);
      return;
    }
    case Type::Null: r.readNull(); return;
    case Type::Invalid: r.skipValue(); return;
  }
}

// Copies the input into a heap block of exactly its size (no trailing NUL as
// std::string has), so AddressSanitizer flags any read past the end.
struct ExactBuffer {
  std::vector<char> bytes;
  explicit ExactBuffer(const std::string& s) : bytes(s.begin(), s.end()) {}
  const char* data() const { return bytes.empty() ? nullptr : bytes.data(); }
  size_t size() const { return bytes.size(); }
};

void test_fuzz_json_validate_random_bytes() {
  Prng rng(0xC0FFEE);
  int valid = 0;
  for (int i = 0; i < 20000; ++i) {
    const std::string s = randomBytes(rng, 256);
    const ExactBuffer buf(s);
    const bridge::json::Error e = bridge::json::validate(buf.data(), buf.size());
    if (e == bridge::json::Error::None) ++valid;
    bridge::json::Reader r(buf.data(), buf.size());
    walk(r, 0);
    // The walker and the validator agree on what is valid JSON.
    if (r.ok() && r.atEnd()) TEST_ASSERT_TRUE_MESSAGE(e == bridge::json::Error::None, s.c_str());
  }
  TEST_ASSERT_TRUE(valid > 0);  // the alphabet does produce some valid documents
}

void test_fuzz_mutated_documents_exact_buffers() {
  Prng rng(0xFEED);
  for (int i = 0; i < 20000; ++i) {
    const std::string s = mutate(rng, kSeeds[rng.below(sizeof(kSeeds) / sizeof(kSeeds[0]))]);
    const ExactBuffer buf(s);
    const bridge::json::Error e = bridge::json::validate(buf.data(), buf.size());
    bridge::json::Reader r(buf.data(), buf.size());
    walk(r, 0);
    if (e == bridge::json::Error::None) {
      TEST_ASSERT_TRUE_MESSAGE(r.ok() && r.atEnd(), s.c_str());
    }
  }
}

void test_fuzz_body_parsers_with_mutations() {
  Prng rng(0xBADC0DE);
  for (int i = 0; i < 20000; ++i) {
    const std::string seed = kSeeds[rng.below(sizeof(kSeeds) / sizeof(kSeeds[0]))];
    const std::string s = mutate(rng, seed);
    bridge::SendRawJob job;
    const bridge::ApiError raw = bridge::parseSendRaw(s, job);
    if (raw.ok()) {
      TEST_ASSERT_TRUE(job.durationsUs.size() % 2 == 1);
      TEST_ASSERT_LESS_OR_EQUAL(bridge::kMaxPatternUs, job.totalUs);
    } else {
      TEST_ASSERT_TRUE(raw.status == 400 || raw.status == 413);
    }
    std::string client;
    const bridge::ApiError pair = bridge::parsePair(s, client);
    if (pair.ok()) TEST_ASSERT_TRUE(bridge::isValidDisplayName(client, bridge::kMaxClientNameChars));
    uint32_t timeout = 0;
    const bridge::ApiError learn = bridge::parseLearn(s, timeout);
    if (learn.ok()) TEST_ASSERT_LESS_OR_EQUAL(bridge::kMaxLearnTimeoutMs, timeout);
    const bridge::ApiError ac = bridge::parseSendAc(s);
    // parseSendAc accepts exactly the JSON objects.
    const bool isObject = bridge::json::isValid(s) && s.find('{') != std::string::npos &&
                          s.find_first_not_of(" \t\r\n") == s.find('{');
    TEST_ASSERT_TRUE(ac.ok() == isObject);
  }
}

void test_fuzz_router_random_requests() {
  Prng rng(0x5EED);
  Rig rig;
  const std::string auth = rig.pair();
  for (int i = 0; i < 6000; ++i) {
    const Method m = kMethods[rng.below(sizeof(kMethods) / sizeof(kMethods[0]))];
    const char* path = kPaths[rng.below(sizeof(kPaths) / sizeof(kPaths[0]))];
    std::string body;
    switch (rng.below(3)) {
      case 0: body = randomBytes(rng, 512); break;
      case 1: body = mutate(rng, kSeeds[rng.below(sizeof(kSeeds) / sizeof(kSeeds[0]))]); break;
      default: body = kSeeds[rng.below(sizeof(kSeeds) / sizeof(kSeeds[0]))]; break;
    }
    if (rng.below(50) == 0) body.append(bridge::kMaxBodyBytes, ' ');
    const std::string a = rng.below(4) == 0 ? randomBytes(rng, 48) : auth;
    exercise(rig, m, path, body, a, rng.below(2) == 0);
    rig.now += rng.below(5000);
    if (rng.below(20) == 0) {
      bridge::Capture c;
      c.durationsUs.resize(rng.below(1500));
      for (uint32_t& d : c.durationsUs) d = static_cast<uint32_t>(rng.next());
      c.atMs = rig.now;
      rig.bridge.onCapture(c);
    }
    for (const bridge::Event& e : rig.bridge.takeEvents()) {
      if (e.kind == bridge::Event::Kind::WebSocketText) {
        TEST_ASSERT_TRUE_MESSAGE(bridge::json::isValid(e.text), e.text.c_str());
      }
    }
  }
  // The token survives all of that and still works.
  TEST_ASSERT_EQUAL_INT(200, rig.respond(Method::Get, "/v1/health", "", auth).status);
}

void test_fuzz_paths_and_headers() {
  Prng rng(77);
  Rig rig;
  for (int i = 0; i < 5000; ++i) {
    std::string path = "/v1/" + randomBytes(rng, 16);
    if (rng.below(3) == 0) path = randomBytes(rng, 24);
    const int status = exercise(rig, kMethods[rng.below(5)], path, "", randomBytes(rng, 64), false);
    // A random path can only be a known route by accident; random tokens never authorise.
    TEST_ASSERT_TRUE(status == 404 || status == 405 || status == 401 || status == 200 ||
                     status == 403 || status == 400 || status == 413);
  }
}

void test_fuzz_state_machine_invariants() {
  Prng rng(2026);
  Rig rig;
  std::vector<std::string> tokens;
  for (int i = 0; i < 20000; ++i) {
    rig.now += rng.below(3000);
    switch (rng.below(10)) {
      case 0:
        rig.bridge.onButton(bridge::ButtonEvent::ShortPress, rig.now);
        break;
      case 1:
        if (rng.below(10) == 0) {
          rig.bridge.onButton(bridge::ButtonEvent::LongPress, rig.now);
          tokens.clear();
        }
        break;
      case 2: {
        const bridge::Response r = rig.respond(Method::Post, "/v1/pair", "{\"client\":\"fuzz\"}");
        if (r.status == 200) tokens.push_back("Bearer " + testsupport::jsonString(r.body, "token"));
        TEST_ASSERT_TRUE(r.status == 200 || r.status == 403 || r.status == 507);
        break;
      }
      case 3:
      case 4: {
        if (tokens.empty()) break;
        const std::string& t = tokens[rng.below(static_cast<uint32_t>(tokens.size()))];
        const char* bodies[] = {"{\"timeoutMs\":0}", "{\"timeoutMs\":2000}", "{}"};
        exercise(rig, rng.below(2) ? Method::Post : Method::Delete, "/v1/learn",
                 bodies[rng.below(3)], t, false);
        break;
      }
      case 5: {
        bridge::Capture c;
        c.durationsUs = {9000, 4500, 560};
        c.atMs = rig.now;
        rig.bridge.onCapture(c);
        break;
      }
      case 6:
        if (!tokens.empty()) {
          exercise(rig, Method::Post, "/v1/send/raw", kSeeds[0], tokens.back(), false);
        }
        break;
      default:
        rig.bridge.tick(rig.now);
        break;
    }
    TEST_ASSERT_LESS_OR_EQUAL(bridge::kMaxPairedClients, rig.bridge.pairedClients());
    TEST_ASSERT_EQUAL_INT(tokens.size(), rig.bridge.pairedClients());
    TEST_ASSERT_FALSE(rig.bridge.transmitting());
    const std::vector<bridge::Event> events = rig.bridge.takeEvents();
    TEST_ASSERT_LESS_OR_EQUAL(16, events.size());
    for (const bridge::Event& e : events) {
      if (e.kind == bridge::Event::Kind::WebSocketText) TEST_ASSERT_TRUE(bridge::json::isValid(e.text));
    }
  }
}

void test_event_queue_is_bounded() {
  Rig rig;
  const std::string auth = rig.pair();
  TEST_ASSERT_EQUAL_INT(202, rig.respond(Method::Post, "/v1/learn", "{\"timeoutMs\":0}", auth).status);
  bridge::Capture c;
  c.durationsUs = {100};
  for (int i = 0; i < 1000; ++i) {
    c.atMs = rig.now + static_cast<uint64_t>(i);
    rig.bridge.onCapture(c);
  }
  const std::vector<bridge::Event> events = rig.bridge.takeEvents();
  TEST_ASSERT_EQUAL_INT(16, events.size());
  // The newest captures are kept.
  TEST_ASSERT_TRUE(events.back().text.find("\"atMs\":" + std::to_string(rig.now + 999)) !=
                   std::string::npos);
}

}  // namespace

void run_fuzz_tests() {
  RUN_TEST(test_fuzz_json_validate_random_bytes);
  RUN_TEST(test_fuzz_mutated_documents_exact_buffers);
  RUN_TEST(test_fuzz_body_parsers_with_mutations);
  RUN_TEST(test_fuzz_router_random_requests);
  RUN_TEST(test_fuzz_paths_and_headers);
  RUN_TEST(test_fuzz_state_machine_invariants);
  RUN_TEST(test_event_queue_is_bounded);
}
