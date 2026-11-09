// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// A tiny stand-in for the Unity test framework, used only by
// tools/run_host_tests.sh where PlatformIO (and so the real Unity) is not
// available. It implements just the macros the tests in test/test_native use,
// with the same names and argument order as Unity. `pio test -e native` uses
// the real Unity and never sees this file.
//
// A failed assertion throws, so C++ destructors run and AddressSanitizer
// stays quiet about the test that failed.
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <string>

extern "C" void setUp(void);
extern "C" void tearDown(void);

namespace unity_shim {

struct Failure {
  const char* file;
  int line;
  std::string message;
};

struct Counters {
  int tests = 0;
  int failures = 0;
};

inline Counters& counters() {
  static Counters c;
  return c;
}

[[noreturn]] inline void fail(const char* file, int line, const std::string& message) {
  throw Failure{file, line, message};
}

inline void begin() { counters() = Counters(); }

inline int end() {
  const Counters& c = counters();
  std::printf("\n-----------------------\n%d Tests %d Failures 0 Ignored\n%s\n", c.tests,
              c.failures, c.failures == 0 ? "OK" : "FAIL");
  return c.failures;
}

inline void run(void (*fn)(void), const char* name, int line) {
  Counters& c = counters();
  ++c.tests;
  try {
    setUp();
    fn();
    tearDown();
    std::printf("test:%d:%s:PASS\n", line, name);
  } catch (const Failure& f) {
    ++c.failures;
    std::printf("%s:%d:%s:FAIL: %s\n", f.file, f.line, name, f.message.c_str());
    try {
      tearDown();
    } catch (...) {
    }
  } catch (const std::exception& e) {
    ++c.failures;
    std::printf("test:%d:%s:FAIL: unexpected exception: %s\n", line, name, e.what());
  }
  std::fflush(stdout);
}

inline std::string describeInt(long long expected, long long actual) {
  return "Expected " + std::to_string(expected) + " Was " + std::to_string(actual);
}

inline std::string describeUint(unsigned long long expected, unsigned long long actual) {
  return "Expected " + std::to_string(expected) + " Was " + std::to_string(actual);
}

inline void assertString(const char* expected, const char* actual, const char* file, int line,
                         const char* msg) {
  if (expected == nullptr || actual == nullptr) {
    if (expected != actual) fail(file, line, "Expected string pointer mismatch (null)");
    return;
  }
  if (std::strcmp(expected, actual) != 0) {
    std::string m = std::string("Expected \"") + expected + "\" Was \"" + actual + "\"";
    if (msg) m += std::string(". ") + msg;
    fail(file, line, m);
  }
}

}  // namespace unity_shim

#define UNITY_BEGIN() (unity_shim::begin(), 0)
#define UNITY_END() unity_shim::end()
#define RUN_TEST(fn) unity_shim::run(fn, #fn, __LINE__)

#define TEST_FAIL_MESSAGE(msg) unity_shim::fail(__FILE__, __LINE__, (msg))
#define TEST_ASSERT_TRUE_MESSAGE(cond, msg)                                      \
  do {                                                                           \
    if (!(cond)) unity_shim::fail(__FILE__, __LINE__, std::string("Expected TRUE: " #cond ". ") + (msg)); \
  } while (0)
#define TEST_ASSERT_TRUE(cond)                                                   \
  do {                                                                           \
    if (!(cond)) unity_shim::fail(__FILE__, __LINE__, "Expected TRUE Was FALSE: " #cond); \
  } while (0)
#define TEST_ASSERT_FALSE(cond)                                                  \
  do {                                                                           \
    if (cond) unity_shim::fail(__FILE__, __LINE__, "Expected FALSE Was TRUE: " #cond); \
  } while (0)
#define TEST_ASSERT(cond) TEST_ASSERT_TRUE(cond)
#define TEST_ASSERT_NULL(p) TEST_ASSERT_TRUE((p) == nullptr)
#define TEST_ASSERT_NOT_NULL(p) TEST_ASSERT_TRUE((p) != nullptr)

#define TEST_ASSERT_EQUAL_INT(expected, actual)                                         \
  do {                                                                                  \
    const long long e_ = static_cast<long long>(expected);                              \
    const long long a_ = static_cast<long long>(actual);                                \
    if (e_ != a_) unity_shim::fail(__FILE__, __LINE__, unity_shim::describeInt(e_, a_)); \
  } while (0)
#define TEST_ASSERT_EQUAL_INT_MESSAGE(expected, actual, msg)                            \
  do {                                                                                  \
    const long long e_ = static_cast<long long>(expected);                              \
    const long long a_ = static_cast<long long>(actual);                                \
    if (e_ != a_)                                                                       \
      unity_shim::fail(__FILE__, __LINE__, unity_shim::describeInt(e_, a_) + ". " + (msg)); \
  } while (0)
#define TEST_ASSERT_EQUAL(expected, actual) TEST_ASSERT_EQUAL_INT(expected, actual)
#define TEST_ASSERT_EQUAL_INT64(expected, actual) TEST_ASSERT_EQUAL_INT(expected, actual)

#define TEST_ASSERT_EQUAL_UINT64(expected, actual)                                         \
  do {                                                                                     \
    const unsigned long long e_ = static_cast<unsigned long long>(expected);               \
    const unsigned long long a_ = static_cast<unsigned long long>(actual);                 \
    if (e_ != a_) unity_shim::fail(__FILE__, __LINE__, unity_shim::describeUint(e_, a_)); \
  } while (0)
#define TEST_ASSERT_EQUAL_UINT32(expected, actual) TEST_ASSERT_EQUAL_UINT64(expected, actual)
#define TEST_ASSERT_EQUAL_UINT(expected, actual) TEST_ASSERT_EQUAL_UINT64(expected, actual)

#define TEST_ASSERT_LESS_OR_EQUAL(threshold, actual)                                   \
  do {                                                                                 \
    const long long t_ = static_cast<long long>(threshold);                            \
    const long long a_ = static_cast<long long>(actual);                               \
    if (!(a_ <= t_))                                                                   \
      unity_shim::fail(__FILE__, __LINE__,                                             \
                       "Expected <= " + std::to_string(t_) + " Was " + std::to_string(a_)); \
  } while (0)
#define TEST_ASSERT_GREATER_OR_EQUAL(threshold, actual)                                \
  do {                                                                                 \
    const long long t_ = static_cast<long long>(threshold);                            \
    const long long a_ = static_cast<long long>(actual);                               \
    if (!(a_ >= t_))                                                                   \
      unity_shim::fail(__FILE__, __LINE__,                                             \
                       "Expected >= " + std::to_string(t_) + " Was " + std::to_string(a_)); \
  } while (0)

#define TEST_ASSERT_EQUAL_STRING(expected, actual) \
  unity_shim::assertString((expected), (actual), __FILE__, __LINE__, nullptr)
#define TEST_ASSERT_EQUAL_STRING_MESSAGE(expected, actual, msg) \
  unity_shim::assertString((expected), (actual), __FILE__, __LINE__, (msg))

#define TEST_ASSERT_EQUAL_MEMORY(expected, actual, len)                                 \
  do {                                                                                  \
    if (std::memcmp((expected), (actual), (len)) != 0)                                  \
      unity_shim::fail(__FILE__, __LINE__, "Memory mismatch");                          \
  } while (0)
