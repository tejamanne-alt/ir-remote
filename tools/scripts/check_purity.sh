#!/usr/bin/env bash
# Gate: packages/ir_core must stay pure Dart (no Flutter, no dart:io, no FFI,
# no platform-specific libraries) so it tests in seconds and stays portable.
# Usage: tools/scripts/check_purity.sh [package-dir]
set -uo pipefail
dir="${1:-packages/ir_core}"
status=0
targets=()
for d in lib bin; do [ -d "$dir/$d" ] && targets+=("$dir/$d"); done
if [ "${#targets[@]}" -eq 0 ]; then
  echo "purity check: no lib/ or bin/ under $dir" >&2
  exit 1
fi
pattern="^\s*(import|export)\s+['\"](package:flutter|dart:(io|ffi|html|js|js_interop|ui|isolate|mirrors))"
if grep -rnE "$pattern" "${targets[@]}"; then
  echo "purity violation: forbidden import in $dir (see lines above)" >&2
  status=1
fi
if grep -nE "^\s*(flutter|sky_engine)\s*:" "$dir/pubspec.yaml"; then
  echo "purity violation: $dir/pubspec.yaml depends on Flutter" >&2
  status=1
fi
[ "$status" -eq 0 ] && echo "purity OK: $dir"
exit "$status"
