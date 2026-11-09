// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Native unit tests for bridge_core.
//   pio test -e native               (real Unity, via PlatformIO)
//   tools/run_host_tests.sh          (system g++ + test/host_shim/unity.h)
#include "bridge_core.h"
#include "test_support.h"

void setUp(void) {}
void tearDown(void) {}

int main(int, char**) {
  UNITY_BEGIN();
  run_json_tests();
  run_signal_tests();
  run_api_tests();
  run_pairing_tests();
  run_ota_tests();
  run_provisioning_tests();
  run_fuzz_tests();
  return UNITY_END();
}
