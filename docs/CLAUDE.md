# CLAUDE.md: working agreement for this repo

The contract is `docs/BUILD_PROMPT.md`. This file covers how to work here day
to day. Keep it under 200 lines; CI checks the length.

## Session loop

1. Read this file, `PROGRESS.md`, `DECISIONS.md` and `OPEN_QUESTIONS.md`.
   Re-run the current milestone's gate, and trust the gate over the notes.
2. Pick the next unblocked task. Write it and its acceptance check in
   `PROGRESS.md`.
3. Contract first: write the interface and its tests, then the implementation.
4. Inner loop (below) until green. Then the outer loop: security (parsers,
   network input, secrets), performance budgets, data integrity (migrations,
   snapshots, export round trip). Record findings, even when there are none.
5. Small conventional commits. Close the session with `PROGRESS.md`, ADRs and
   the session report.

## Toolchain (as installed, 2026-11-09)

| Tool | Version | Notes |
| --- | --- | --- |
| Flutter | 3.47.9 stable | `/opt/flutter/bin/flutter` in the cloud sandbox |
| Dart | 3.13.7 | `/opt/flutter/bin/cache/dart-sdk/bin/dart` (no root banner) |
| drift / drift_dev | 2.35.4 / 2.35.3 | build_runner 2.16.1 (pinned by flutter_test's analyzer) |
| Python | 3.13 | `tools/fixtures/irp_oracle.py`, `tools/scripts/*.py` |
| PlatformIO | CI only | registry blocked in the sandbox |

The sandbox cannot reach dl.google.com (no Android SDK) or build iOS, so CI
runs those builds. Locally, everything under `packages/`, `tools/` and the
app's tests runs.

## Commands

Run from the repo root unless noted. `tools/scripts/inner_loop.sh` runs the
whole inner loop.

```bash
flutter pub get                                   # whole workspace
dart format --output=none --set-exit-if-changed packages tools apps/remote/lib apps/remote/test
(cd packages/ir_core && dart analyze --fatal-infos && dart test)
(cd packages/ir_transports && dart analyze --fatal-infos && dart test)
(cd packages/code_db && dart analyze --fatal-infos && dart test)
(cd tools/db_build && dart analyze --fatal-infos && dart test)
(cd apps/remote && flutter analyze && flutter test)
tools/scripts/check_purity.sh                     # ir_core stays pure Dart
dart run check_licenses                           # gate L5
python3 tools/fixtures/irp_oracle.py --check      # golden fixtures current
```

Milestone gates:

- **M1:** `(cd packages/ir_core && dart test --coverage-path=coverage/lcov.info) && python3 tools/scripts/coverage_gate.py packages/ir_core/coverage/lcov.info lib/src/codecs/ 95`
- **M2:** `tools/scripts/check_code_db.sh` (rebuilds the bundled code DB from the pinned sources and compares it byte for byte; needs github.com; set `DART` if `dart` is not on PATH)
- **Codegen:** `(cd apps/remote && dart run build_runner build)`. For a new schema version, also run `dart run drift_dev make-migrations`.
- **l10n:** `(cd apps/remote && flutter gen-l10n)`. Strings live in `lib/l10n/app_en.arb`.

## Layout

```
apps/remote              Flutter app: UI, state, platform channels (Kotlin in android/)
packages/ir_core         Pure Dart: signal model, validator, codecs, Pronto/raw/Flipper/irdb parsers, code-set model, AC model
packages/ir_transports   Serial queue, registry, Simulated, ESP32 bridge client, Broadlink
packages/code_db         Bundled read-only code DB: schema, loader, query API
tools/db_build           Builds code_db from pinned sources with provenance
tools/check_licenses     Gate L5
tools/fixtures           IRP oracle that generates codec golden fixtures
tools/scripts            purity, coverage, inner loop, release checks
firmware/esp32_bridge    Bridge firmware (PlatformIO), own LGPL LICENSE
docs/                    this file, PROGRESS, DECISIONS, OPEN_QUESTIONS, HARDWARE_TEST_PLAN, THIRD_PARTY, BRIDGE_API, release/
```

## Rules

- `ir_core` imports no Flutter and no `dart:io`, `dart:ffi` or `dart:isolate`.
  `check_purity.sh` enforces this.
- Every codec file header cites the published description it was written
  from. Never paste code from another project.
- Errors: parsers throw `FormatException` only, and fuzz tests prove it.
  Transports never throw from `transmit`/`health`; they return
  `TransmitResult`/`HealthStatus` values. UI maps each result to a specific
  message (`ui/labels.dart`).
- One serial queue per transport (`QueuedTransport`). Nothing transmits on the
  UI thread. Android `transmit()` runs on a Kotlin single-thread executor.
- Saved remotes store the code-set ID **and** signal snapshots (both toggle
  variants for RC5/RC6). Database updates never change a working remote
  silently.
- AC state is always "as sent from this phone", never a reading.
- Every user-visible string goes in the ARB file. No brand logos. Brand names
  appear only as plain text.
- Names: Dart `lowerCamelCase` members, `UpperCamelCase` types, files
  `snake_case.dart`. Key names come from `Keys` (`POWER`, `VOL_UP`, ...), and
  unknown keys become `custom:<name>`.

## Forbidden

- Claiming a code or feature works on a real appliance without a human result
  in `HARDWARE_TEST_PLAN.md`.
- Weakening, skipping or deleting a failing test; mocking the unit under test;
  hardcoding expected outputs in production code.
- Copying source from GPL, LGPL or unlicensed projects into the app.
- Adding a dependency without a `THIRD_PARTY.md` entry (CI fails).
- `TODO` or stub code on a user-reachable path in a milestone marked done.
- Runtime network calls other than LAN hubs, the pinned code-DB CDN and
  opt-in crash reporting.
- Any organization name other than `{{PUBLISHER}}` in code, metadata or
  listings.

## Escalate

Write the question, the options and a recommendation to `OPEN_QUESTIONS.md`,
then continue with other unblocked work. Escalate when a licensing gate is
unresolved, a gate fails after 3 different attempts, you would deviate from
the contract, a task needs purchases, accounts or store actions, or two
requirements conflict.

## Other docs

- `PROGRESS.md`: done, next, blocked, and the session reports
- `DECISIONS.md`: ADRs and freshness checks
- `OPEN_QUESTIONS.md`: questions waiting on a human
- `HARDWARE_TEST_PLAN.md`: human gates H1 to H6 and the appliance matrix
- `THIRD_PARTY.md`: every dependency and data source
- `BRIDGE_API.md`: ESP32 bridge HTTP/WebSocket contract
- `release/`: store copy, App Review video shot list, privacy policy
