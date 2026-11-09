# Progress

Status per milestone. "Passed" means the gate command passed. Nothing has
been verified on real hardware; every human gate is pending (see
`HARDWARE_TEST_PLAN.md`).

| Milestone | Status | Gate evidence |
| --- | --- | --- |
| M0 Bootstrap | **gate passed** | CI run 1 green on GitHub ([run 42574974217](https://github.com/tejamanne-alt/ir-remote/actions/runs/42574974217)): inner loop, Android debug APK, iOS no-codesign build, firmware host tests; `check_licenses`: 141 packages, 0 errors |
| M1 Signal core | **gate passed** (CI) | golden fixtures from the independent IRP oracle; property, jitter and fuzz tests; codec line coverage 97.40% (≥ 95%); Pronto parser 10,000 fuzz cases |
| M2 Code database | **gate passed** (CI) | L1 + L5 checks; Flipper/irdb parser fuzzing (12,000 each); `tools/scripts/check_code_db.sh` rebuilds byte-identically (content hash `1b5fa616…`); L4 refuses irdb |
| M3 Transports | in progress | transport tests against fakes pass (115); Android instrumented test for capability detection written (`androidTest/.../ConsumerIrCapabilitiesTest.kt`), runs in the nightly emulator job, first run pending; H1 pending |
| F1 Bridge firmware | **gate passed**; H2 pending | CI [run 42689292033](https://github.com/tejamanne-alt/ir-remote/actions/runs/42689292033): `pio run -e esp32dev` builds, `pio test -e native` passes; 87 host tests pass with ASan/UBSan. Audit fixes (boot, in-band WS auth, async sends) are untested on hardware. H2 (flash, pair, capture loop) needs a board |
| M4 Key-code app | in progress | widget tests for onboarding, add device, remote, hubs, settings, AC panel, macros, backup; add-device integration test written (nightly emulator/simulator job, not yet run); migration tests v1→v2; H3 pending |
| M5 AC engine | blocked on human | `AcState`, `AcCapabilities`, encoder contract and the AC panel exist; **no encoders ship** (Q2 licensing route, Q3 brand list, H4 captures) |
| M6 Learning, custom remotes, macros, import/export | gate tests pass; one feature gap | export → wipe → import identical; 2,000-mutation backup fuzz; Flipper import fixtures; macro scheduler tests; learning screen; button editor (drag to reorder, rename, delete; theme colours only). **Missing:** copying a single key from a database code set into a custom remote |
| M7 System surfaces | not started | |
| M8 Hardening and release | not started | release checklist and script drafted (`docs/release/`) |

## Next

1. H2 first, on a board: boot, pairing, the in-band WebSocket auth
   (ADR-026) and the async send path. They are built and host-tested, but
   have not been run on hardware.
2. M3: confirm the first nightly run of the emulator job (integration test
   plus `connectedDebugAndroidTest`) and the iOS simulator job.
3. Debug Loopback screen for the closed-loop rig, so H1 can run.
4. M6: let custom remotes take single keys from database code sets.
5. M7: Android widget and Quick Settings tile; iOS widgets, App Intents,
   Control Center; room management (move a remote, delete a room).

## Blocked on human

- Q2, Q3, H4: AC licensing route, brand list, captured frames.
- Q6: open the irdb announcement issue, then record its link in THIRD_PARTY.md.
- Q8: Apple multicast entitlement (Account Holder).
- Q13–Q14: bridge setup-AP password, signed OTA.
- H1–H3: test hardware (an Android phone with an emitter, a Broadlink RM4
  mini, an ESP32 with a 940 nm LED, a transistor and a 38 kHz receiver).

## Session 1 — 2026-11-09

Milestone: M0 to M2 gates pass locally; M3, F1, M4 and M6 in progress; M5
blocked on a human.

Done:
- Workspace and app shell (commit 5578f06); `ir_core` signal model,
  validator, 15 codecs, Pronto/raw formats, IRP oracle fixtures (09361d3)
- Serial queue, registry, simulator, ESP32 bridge client (3cb4680)
- App: onboarding, add device with matching, remotes, hubs, AC panel shell,
  learning, Pronto, settings, inspector, drift v1 (22485c7)
- Broadlink transport and its app wiring (918d9ea)
- License gate L5, docs, release checklist (0f7b5f1)
- M2 code DB: parsers, db_build, code_db, bundled DB (f3463d3)
- NECx defaults and aliases corrected against IrpProtocols (62fdb6b)
- M6: macros (schema v2), backup, Flipper import, bundled DB in app (dd2156e)
- F1 firmware (8c490c9); LAN-only hubs and timeout fixes (288b2e0); CI (9f04ec9)

Gates: inner pass · outer 9 findings (all fixed, listed below) · M1 pass via
`coverage_gate.py … lib/src/codecs/ 95` · M2 pass via
`tools/scripts/check_code_db.sh`

Outer-loop findings, all fixed in this session:
1. `normalize` crashed when a required parameter was missing (computed default read it).
2. A health check finishing after the registry was disposed threw "add after close".
3. The license classifier read MPL-2.0 as LGPL; `--write` dropped "not shipped" rows.
4. An open remote didn't refresh after keys were learned or imported.
5. A cancelled macro left its delay timer running for up to 60 s.
6. A crafted backup or mDNS answer could point a hub at an internet host
   (now LAN-only, ADR-024).
7. The bridge send timeout (3 s) was shorter than a legal 4 s pattern; the
   queue timeout ignored on-air time.
8. The bridge client sent chunked bodies; now sends Content-Length.
9. NECx subdevice default, NECx1 repeat bit and two protocol aliases were
   wrong (ADR-021).

Performance: budgets not yet measured on devices (M8). The transport queue
adds no measurable latency in tests.

Decisions: ADR-001 to ADR-024 (see DECISIONS.md).

Blocked on human:
- Q1 publisher/bundle ID → the publisher name and domain
- Q2/Q3/H4 AC → licensing route, the final 8 brands, captured frames
- Q6 irdb → open the announcement issue and record its URL in THIRD_PARTY.md
- H1–H3 → the test hardware listed above

Also fixed while closing: the three text dialogs disposed their controller
while the dialog's closing animation still used it (crash in debug). They
now share `showTextInputDialog`, which owns its controller. User-renamed
standard keys now show their new label.

CI: run 1 green on all push jobs (inner loop, Android, iOS, firmware host).

CI run 3 is green on every push job: inner loop and all gates, Android debug
APK, iOS no-codesign build, firmware host tests, `pio test -e native`, and
`pio run -e esp32dev`.

Next session starts with: the first nightly emulator and simulator runs
(integration test plus instrumented test).

## Session 2 — 2026-11-09

Milestone: F1 rework (web server licence) and release identity. M0 to M2 and
F1 gates still pass.

Done:
- App ID is `com.astradite.irremote` on Android (namespace, applicationId,
  Kotlin package) and iOS (bundle identifier); OPEN_QUESTIONS Q1 resolved
- Bridge web server moved from ESPAsyncWebServer/AsyncTCP (LGPL-3.0) to
  ESP-IDF esp_http_server (Apache-2.0), part of the Arduino core; no LGPL-3.0
  code remains (ADR-025, Q12 resolved). New portable helpers (status lines,
  form decoding) have host tests; the glue was syntax-checked against the
  real ESP-IDF 5.5 headers
- Bridge client: a 1008 close after the WebSocket upgrade reports
  "unauthorized"; fixed a crash when a later error hit an already-closed
  learn stream
- release_checks.sh: the L4 check no longer mistakes flipperdevices/irdb for
  probonopd/irdb; all scripted release checks pass

Gates: inner pass · outer 2 findings (closed-stream crash, L4 false positive;
both fixed) · F1 via CI `pio run -e esp32dev`

Next session starts with: the first nightly emulator and simulator runs.

## Session 3 — 2026-11-09

Milestone: an audit of correctness, robustness and resiliency across every
package. The M0 to M2 and F1 gates still pass.

Done:
- Four independent audits: transports, firmware, core with code DB, and the
  app. 45 findings, every one reproduced before it was fixed. 43 are fixed
  with regression tests; 2 are documented. The full list is in
  `docs/AUDIT_2026-11-09.md`.
- **Critical (firmware):**
  - the bridge aborted on every boot (TCP/IP stack not up);
  - newer cores never checked the WebSocket token.

  Both are fixed (ADR-026), but neither fix has been verified on hardware.
- **High:**
  - decoders matched a prefix of longer frames, so learn saved the wrong
    signal;
  - scrolling sent IR;
  - hold-to-repeat timing was wrong (ADR-027, ADR-028);
  - Broadlink could send twice on an unreadable ack.

Gates:
- Inner loop: pass.
- Firmware host tests: 87/87.
- CI run 8: firmware built with PlatformIO.
- M1: 97.65%.
- M2: hash unchanged.
- Outer loop: this session was the outer loop. Its findings are the audit.

Decisions: ADR-026 (in-band WebSocket auth, async sends), ADR-027 (gesture
arena, 40 ms press delay), ADR-028 (repeat timing from RepeatSpec).

Next session starts with: H2 on a board, then the nightly emulator and
simulator runs.
