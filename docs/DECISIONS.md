# Decisions

ADRs in order. Each one lists its context, the decision and its consequences.
Freshness checks record what was verified, where, and when.

## Freshness log

| Date | What | Source | Finding |
| --- | --- | --- | --- |
| 2026-11-09 | Flutter stable | storage.googleapis.com `releases_linux.json` | 3.47.9 (Dart 3.13.7), released 2026-10-29; sha256 verified on download |
| 2026-11-09 | Dart packages | pub.dev API | drift 2.35.4, drift_flutter 0.3.1, sqlite3 3.9.1 (sqlite3_flutter_libs is end-of-life, 0.6.0+eol), bonsoir 7.1.6 (MIT), pointycastle 4.0.0, build_runner 2.17.1 (2.16.1 resolved, pinned by flutter_test's analyzer) |
| 2026-11-09 | `ConsumerIrManager` | developer.android.com reference | Added in API 19; `transmit()` is synchronous and only patterns shorter than 2 s are sent; `getCarrierFrequencies()`, `hasIrEmitter()` unchanged |
| 2026-11-09 | `NEARBY_WIFI_DEVICES` | developer.android.com Wi-Fi permissions | Required (target 13+) only for local-only hotspot, Wi-Fi Aware, Wi-Fi P2P, RTT and scan results. NSD and plain sockets do not need it, so it is **not** declared |
| 2026-11-09 | irdb licence | raw.githubusercontent.com probonopd/irdb LICENSE.md | Conditions as described in the contract (issue before use, fixed notice, up to 3 free copies) |
| 2026-11-09 | Source pins | `git ls-remote` | probonopd/irdb `11aa5eb3…`, flipperdevices/irdb `f7b15366…` |
| 2026-11-09 | Arduino-IRremote | raw.githubusercontent.com LICENSE | MIT; LG 28-bit notes in `src/ir_LG.hpp` |

## ADR-001: Stack is Flutter 3.47.9 / Dart 3.13.7 in a pub workspace

**Context:** `{{STACK}}` defaults to the latest stable Flutter. **Decision:**
use Flutter 3.47.9, with one pub workspace (root `pubspec.yaml`, workspace
members `apps/remote`, `packages/*` and `tools/*`) and a single lockfile.
**Consequences:** shared resolution, so `test` follows the version
flutter_test pins (1.31.1). Codegen versions are capped by that analyzer.

## ADR-002: Unfilled variables use their defaults

`{{APP_NAME}}`: working name `irremote` in code, display name "IR Remote"
until M8. `{{PUBLISHER}}` was not supplied, so the bundle ID is the
placeholder `com.example.irremote` (OPEN_QUESTIONS Q1). The release check
fails while it remains. `{{PRIMARY_MARKET}}` en-IN (strings in
`app_en.arb`), `{{MIN_ANDROID_API}}` 26, `{{MIN_IOS}}` 17.0, brand lists as
given, no monetization, no analytics.

## ADR-003: Golden fixtures come from an independent IRP oracle

**Context:** fixtures must come from the cited specification, not from the
codec under test. **Decision:** `tools/fixtures/irp_oracle.py` is a generic
IRP-notation interpreter that knows nothing about individual protocols. It
evaluates the published DecodeIR IRP strings into
`test/fixtures/<protocol>/<case>.json`, and CI checks the fixtures are
current. **Consequences:** a codec bug cannot hide behind self-generated
fixtures. A spec error in an IRP string would hit both sides equally, so human
captures (`HARDWARE_TEST_PLAN.md`) remain the final authority and are added as
fixtures with `source` set to the device and date.

## ADR-004: RepeatSpec carries frame, lead-in gap, gap and minimum repeats

`IrSignal.repeat` is refined to
`RepeatSpec{frameUs, leadInGapUs, gapUs, minRepeats}`. Extents (`^108m`)
become gaps (`period - frame length`). A leading space (the RC5 start bit) is
absorbed into the preceding gap. A trailing space merges into the gap. This
keeps frames mark-first and mark-last, as the contract requires.

## ADR-005: TransportCapabilities gains `maxDurations`

Hubs limit pattern size by element count (bridge: 1024; Broadlink: a byte
budget). The validator and planner split at frame boundaries against both
`maxPatternUs` and `maxDurations`.

## ADR-006: Result and health types are sealed classes

`TransmitResult` is sealed (`TransmitSent`, `TransmitRejected(reason)`,
`TransmitTransportUnavailable`, `TransmitTimeout`). `RejectReason` adds
`tooManyDurations`, `refusedByHub` and `hardwareError`. `HealthStatus` is
`Healthy`/`Degraded`/`Unreachable`. The UI switch over them is exhaustive.

## ADR-007: Sony sends three frames per tap

Sony receivers commonly act only on a repeated frame. `RepeatSpec.minRepeats
= 2` for Sony12/15/20.

## ADR-008: Toggle protocols snapshot both toggle values

Saved RC5/RC6 keys store snapshots for T=0 and T=1. The send pipeline
alternates per new press and keeps the value for repeats. That keeps toggle
state per device for the session without re-encoding at send time.

## ADR-009: Unknown carrier ranges use a 20–60 kHz plausibility window

When Android returns `null` from `getCarrierFrequencies()`, the value is
logged and the validator accepts 20–60 kHz. That is a sanity bound, not a
substitution: the signal's own carrier is sent unchanged.

## ADR-010: A timed-out transmit still holds its queue

`QueuedTransport` answers the caller with `TransmitTimeout` at the timeout,
but keeps the queue held until the inner call returns, up to four times the
timeout. A blocked Android `transmit()` can therefore never overlap the next
press on air.

## ADR-011: No third-party state management

`ChangeNotifier` plus an `InheritedWidget` (`AppScope`) plus drift streams.
That means fewer dependencies and licences, and plain Flutter is enough at
this size. Reversible.

## ADR-012: Broadlink transport choices

Broadlink hubs use a fixed carrier of about 38 kHz, so the transport declares
35–41 kHz and rejects anything else before sending. IR unit is 8192/269 µs
(the DAB-LABS fork's fix of upstream's 32.84 µs). The repeat byte is 0
(repeats are flattened). Send-data goes at most once, so a lost ack cannot
toggle power twice; idempotent requests are resent within the timeout. It
re-authenticates once on a key error or an undecryptable reply. Unknown
device types are refused unless `familyOverride` is set. Unicast hello by IP
is the primary path; broadcast discovery is opt-in.

## ADR-013: Hub pairing tokens live in the user database

The ESP32 bridge token is a LAN-only credential, stored in the app's private
SQLite. M8 hardening may move it to Keychain or Keystore (OPEN_QUESTIONS Q7).

## ADR-014: No AC encoder ships before human captures exist

Gate L2 needs clean-room encoders verified against human-captured frames.
None are available yet, so `AcEncoderRegistry.standard` is empty. AC remotes
use learned buttons, and the panel explains why. The full AC panel is built
and tested against an injected encoder, so encoders can drop in once
fixtures exist. Unverified encoders sit behind a debug-only flag.

## ADR-015: iOS Broadlink support without the multicast entitlement

Until the Account Holder obtains `com.apple.developer.networking.multicast`,
iOS adds Broadlink hubs by IP with a unicast hello. The ESP32 bridge uses
system Bonjour (bonsoir → NWBrowser), which needs no entitlement. Local
Network denial is inferred from a browse that times out, and the user sees a
recovery card.

## ADR-016: Bridge Wi-Fi provisioning and OTA

See `firmware/esp32_bridge/docs/ADR-provisioning.md` and `ADR-ota.md`.
