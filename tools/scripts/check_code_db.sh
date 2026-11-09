#!/usr/bin/env bash
# Gates for the bundled code database:
#  - the committed asset passes the code_db verification tests (L1: every
#    provenance field present; content hash matches);
#  - a fresh build from the pinned sources reproduces it byte for byte
#    (needs network access to github.com);
#  - L4: irdb data is refused until its announcement issue is recorded.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DART="${DART:-dart}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

(cd packages/code_db && "$DART" test test/bundled_asset_test.dart)
(cd tools/db_build && "$DART" run db_build:build --out "$out" --cache-dir "$out/cache")
diff "$out/codes.sqlite.sha256" packages/code_db/assets/codes.sqlite.sha256
cmp "$out/codes.sqlite" packages/code_db/assets/codes.sqlite
echo "bundled code DB reproduces exactly: $(cat packages/code_db/assets/codes.sqlite.sha256)"

if (cd tools/db_build && "$DART" run db_build:build --out "$out/irdb" --cache-dir "$out/cache" --include-irdb >/dev/null 2>&1); then
  if ! grep -qE '^- irdb announcement issue: https://github.com/probonopd/irdb/issues/[0-9]+' docs/THIRD_PARTY.md; then
    echo "L4 violated: irdb build succeeded without a recorded announcement issue" >&2
    exit 1
  fi
else
  echo "L4 OK: irdb refused until the announcement issue is recorded"
fi
