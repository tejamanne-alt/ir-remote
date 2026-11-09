#!/usr/bin/env bash
# The inner loop: format, analyze with zero issues, tests, gates that need no
# network. Run from anywhere inside the repo; exits non-zero on the first failure.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
FLUTTER="${FLUTTER:-flutter}"
DART="${DART:-dart}"
step() { printf '\n== %s\n' "$*"; }

step "pub get";        "$FLUTTER" pub get >/dev/null
step "format";         "$DART" format --output=none --set-exit-if-changed packages tools/check_licenses tools/db_build apps/remote/lib apps/remote/test
step "purity";         tools/scripts/check_purity.sh
step "licenses (L5)";  "$DART" run check_licenses
step "fixtures";       python3 tools/fixtures/irp_oracle.py --check
step "CLAUDE.md size"; test "$(wc -l < docs/CLAUDE.md)" -le 200
for p in packages/ir_core packages/ir_transports packages/code_db tools/db_build tools/check_licenses; do
  step "$p";           (cd "$p" && "$DART" analyze --fatal-infos && "$DART" test)
done
step "M1 coverage";    (cd packages/ir_core && "$DART" test --coverage-path=coverage/lcov.info >/dev/null) \
                         && python3 tools/scripts/coverage_gate.py packages/ir_core/coverage/lcov.info lib/src/codecs/ 95 | tail -1
step "app";            (cd apps/remote && "$FLUTTER" analyze && "$FLUTTER" test)
step "OK"
