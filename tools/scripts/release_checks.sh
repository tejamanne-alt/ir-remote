#!/usr/bin/env bash
# Scripted pre-release checks (docs/release/checklist.md). Fails until the
# human-only inputs (publisher, irdb issue) are supplied.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
ok() { echo "ok:   $*"; }

grep -q 'applicationId = "com.example' apps/remote/android/app/build.gradle.kts \
  && bad "Android applicationId is still a com.example placeholder (OPEN_QUESTIONS Q1)" \
  || ok "Android applicationId set"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.example' apps/remote/ios/Runner.xcodeproj/project.pbxproj \
  && bad "iOS bundle identifier is still a com.example placeholder (Q1)" \
  || ok "iOS bundle identifier set"
dart run check_licenses >/dev/null 2>&1 && ok "licenses (L5)" || bad "check_licenses failed"
if find apps/remote/assets -iname '*logo*' | grep -q .; then bad "logo-like assets found"; else ok "no logo assets"; fi
if grep -q 'irdb' packages/code_db/assets/*.json 2>/dev/null && \
   ! grep -qE '^- irdb announcement issue: https://github.com/probonopd/irdb/issues/[0-9]+' docs/THIRD_PARTY.md; then
  bad "bundled DB contains irdb data but no irdb issue link is recorded (L4)"
else ok "irdb gate (L4)"; fi
exit "$fail"
