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
| 2026-11-09 | AndroidX test (runner 1.6.2, ext-junit 1.2.1) | maven.google.com (redirects to dl.google.com, blocked from the sandbox) | Not verifiable here; pinned to known-published versions, resolved by CI |
| 2026-11-09 | Arduino-IRremote | raw.githubusercontent.com LICENSE | MIT; LG 28-bit notes in `src/ir_LG.hpp` |

## ADR-001: Stack is Flutter 3.47.9 / Dart 3.13.7 in a pub workspace

**Context:** `{{STACK}}` defaults to the latest stable Flutter. **Decision:**
use Flutter 3.47.9, with one pub workspace (root `pubspec.yaml`, workspace
members `apps/remote`, `packages/*` and `tools/*`) and a single lockfile.
**Consequences:** shared resolution, so `test` follows the version
flutter_test pins (1.31.1). Codegen versions are capped by that analyzer.

## ADR-002: Unfilled variables use their defaults

`{{APP_NAME}}`: working name `irremote` in code, display name "IR Remote"
until M8. `{{PUBLISHER}}`: **Astradite**, with `{{BUNDLE_ID}}`
`com.astradite.irremote` on both stores (supplied by the owner on 2026-11-09;
before that it was the placeholder `com.example.irremote`). `{{PRIMARY_MARKET}}` en-IN (strings in
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

## ADR-017: Hybrid code DB — bundle the v1 key-code categories

The bundled database holds every v1 key-code category from
flipperdevices/irdb (MIT, pinned at `f7b1536`): 2,547 code sets, 1.6 MB
gzipped. Other markets will come later from a pinned CDN URL, verified
against the manifest's `fileSha256` before use. irdb itself suggests runtime
access over bundling, which is why this hybrid is recorded here. probonopd/irdb
is excluded until gate L4 is met (ADR-018).

## ADR-018: irdb is excluded until its announcement issue is recorded

`db_build --include-irdb` refuses to run unless THIRD_PARTY.md has a line
`irdb announcement issue: https://github.com/probonopd/irdb/issues/<n>`.
`tools/scripts/check_code_db.sh` checks this in CI.

## ADR-019: Flipper field mappings come from data, not GPL source

Flipper's documentation doesn't say how each protocol packs address and
command. The mappings (NECext little-endian, SIRC20 split, Kaseikyo vendor
0x2002 to Panasonic, RC5X command+64) were established by decoding the
database's own raw captures with our decoders, and by matching against
probonopd/irdb. The GPL firmware code was not read. Unverifiable mappings
(NEC42, RCA, Pioneer, other Kaseikyo vendors) are skipped and counted in the
build report.

## ADR-020: Content hash over canonical rows; verify fully once

The DB's identity is a SHA-256 over a canonical serialization of every row,
stored in its `meta` table and in the manifest. The app copies the asset
once, recomputes the full hash on that first open, and then checks only the
stored hash (under 1 ms). A copy that fails verification is deleted, and the
app falls back to an empty library.

## ADR-021: Protocol definitions follow IrpTransmogrifier where DecodeIR differs

IrpTransmogrifier's protocol list is the maintained successor of DecodeIR.
Where they differ, it wins: the NECx subdevice default is 255-D, and the
NECx1 repeat carries ~D:1. Only the IRP notation, a protocol description, is
used. No IrpTransmogrifier code (GPL-3) is used.

## ADR-022: Backups exclude pairing tokens and replace all data

A backup is canonical JSON, so export → wipe → import → export is
byte-identical. Hub tokens are credentials, so they are never exported;
hubs are re-paired after a restore. An import validates everything first,
then replaces all data in one transaction.

## ADR-023: Bridge contract clarified from the firmware build

`docs/BRIDGE_API.md` now states the check order, the OTA exemption from the
16 KiB body cap and the OTA status codes, plus `426 upgrade_required`,
`500 storage_error` and the `timeoutMs` range. It also requires
`Content-Length` on JSON bodies and a send timeout of network timeout plus
pattern length. The client already follows all of this: `EspBridgeTransport`
sends a fixed length, and its send timeout scales with the chunk. Separately,
`QueuedTransport` limits now scale with on-air time, so a legal 4 s pattern
is never reported as a timeout. API version stays 1, because only
previously unspecified behaviour was defined.

## ADR-024: Hubs are LAN-only, everywhere

`isLanHost` (RFC 1918, link-local, ULA, loopback, `.local`) is checked for
typed addresses, discovered services, backup imports and stored rows before
any transport is created. A crafted backup therefore cannot make the app
contact an internet host.

## ADR-025: Bridge web server is ESP-IDF's esp_http_server

**Context:** ESPAsyncWebServer and AsyncTCP are LGPL-3.0, outside the L5
allow-list. They add an installation-information duty for pre-flashed units
(Q12). **Decision (owner: "whichever is best"):** use esp_http_server
(Apache-2.0). It ships inside the Arduino-ESP32 core (ESP-IDF 5.5), and that
core is built with `CONFIG_HTTPD_WS_SUPPORT=y`, checked in
esp32-arduino-lib-builder `configs/defconfig.common` on 2026-11-09. So no
library is added. **Consequences:**
- One server task; a send waits there while the loop transmits.
- Request bodies need a Content-Length (the app sends one).
- The build has no WebSocket pre-handshake hook, so a bad token on the upgrade
  closes with 1008 after the handshake, instead of 401 (documented in
  BRIDGE_API).
- The only LGPL code left is LGPL-2.1 (Arduino-ESP32, IRremoteESP8266), met by
  publishing the source.
- The glue was syntax-checked against the real ESP-IDF 5.5 headers, and CI
  builds it.
