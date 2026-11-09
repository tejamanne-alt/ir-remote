#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 IR Remote contributors
#
# Builds lib/bridge_core and the native tests in test/test_native with the
# system C++ compiler, against test/host_shim/unity.h instead of the real
# Unity, under AddressSanitizer and UndefinedBehaviorSanitizer, and runs them.
# Use it where PlatformIO is not available; `pio test -e native` runs the
# same test files with the real Unity.
#
# Exit status: 0 when every test passes; non-zero on a compile error, a test
# failure or a sanitizer report.
#
# Environment: CXX (default g++), EXTRA_CXXFLAGS.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cxx="${CXX:-g++}"
build="$(mktemp -d "${TMPDIR:-/tmp}/bridge-host-tests.XXXXXX")"
trap 'rm -rf "$build"' EXIT

flags=(
  -std=c++17
  -Wall -Wextra -Werror -Wpedantic -Wshadow
  -O1 -g -fno-omit-frame-pointer
  -fsanitize=address,undefined -fno-sanitize-recover=all
  -DBRIDGE_HOST_TEST
)
# shellcheck disable=SC2206
extra=(${EXTRA_CXXFLAGS:-})

echo "== compiler: $("$cxx" --version | head -n 1)"
echo "== building bridge_core + test/test_native"
"$cxx" "${flags[@]}" "${extra[@]}" \
  -I "$root/lib/bridge_core/src" \
  -I "$root/test/host_shim" \
  "$root"/lib/bridge_core/src/*.cpp \
  "$root"/test/test_native/*.cpp \
  -o "$build/bridge_tests"

echo "== running"
export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=0:detect_leaks=1:halt_on_error=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"
status=0
"$build/bridge_tests" || status=$?
if [ "$status" -ne 0 ]; then
  echo "== FAILED (exit $status)"
  exit "$status"
fi
echo "== all host tests passed"
