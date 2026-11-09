# ESP32 IR bridge firmware

The reference Wi-Fi IR hub for the IR Remote app. It sends raw IR patterns on
a 940 nm LED, captures and decodes IR with a 38 kHz receiver, streams captures
over a WebSocket (learn mode, and capture mode for the closed-loop test rig),
and speaks the versioned LAN API in [`docs/BRIDGE_API.md`](../../docs/BRIDGE_API.md)
(v1). It is a separate binary from the app, under its own licence (see
[License and LGPL compliance](#license-and-lgpl-compliance)).

## Status

**Hardware verification is pending.** Nobody has flashed a board with this
firmware yet. Human gate **H2** (board flashed, paired, capture loop working)
is open, and nothing in this directory has been checked on real hardware: not
the pin map, not the resistor values, not IR timing accuracy, not Wi-Fi
provisioning, mDNS or OTA.

What *has* been checked:

| Check | Result |
| --- | --- |
| `bridge_core` unit tests (routing, auth, pairing, validation, JSON, OTA verification, fuzzing) with g++ 13 under ASan/UBSan (`tools/run_host_tests.sh`) | 80 tests pass |
| `pio test -e native` | not run: the PlatformIO registry was unreachable from the authoring sandbox |
| `pio run -e esp32dev` (firmware build) | not run, for the same reason; `src/` was only syntax-checked against stub headers |

To pass H2, a person needs to: build and flash (`pio run -e esp32dev -t upload`),
provision Wi-Fi through the setup page, pair the app (BOOT press), send the NEC
test vectors, and confirm in capture mode that they come back decoded. Record
the result in `docs/HARDWARE_TEST_PLAN.md`.

## Hardware

### Parts

| Ref | Part | Notes |
| --- | --- | --- |
| U1 | ESP32 dev board (ESP32-WROOM-32: DevKitC, DOIT DevKit V1 or similar) | Powered from USB (5 V on `VIN`/`5V`) |
| D1, D2 | 940 nm IR LED, 5 mm (e.g. Vishay TSAL6200) | D2 optional, for wider coverage |
| Q1 | NPN transistor, PN2222A / 2N2222A or BC337-40 | ≥ 500 mA collector rating |
| R1 | 470 Ω | GPIO4 to Q1 base |
| R2 | 10 kΩ | Q1 base to GND: keeps the LEDs off while GPIO4 floats at reset |
| R3, R4 | 33 Ω, ¼ W | One in series with each LED, from 5 V |
| C1 | 100 µF, ≥ 10 V electrolytic | 5 V to GND next to the LEDs, absorbs the current pulses |
| U2 | 38 kHz IR receiver module, TSOP38238 class | Powered from **3.3 V** |
| R5, C2 | 100 Ω and 100 nF | Receiver supply filter (datasheet application circuit) |
| R6 | 10 kΩ (optional) | Receiver OUT pull-up to 3.3 V; the TSOP has one inside, GPIO34 has none |
| D3, R7 | Status LED + 330 Ω | Only if the board has no LED on GPIO2 (DevKitC has none) |

### Pin map

| Function | GPIO | Direction | Notes |
| --- | --- | --- | --- |
| IR LED driver (Q1 base via R1) | **GPIO4** | out | Not a strapping pin |
| IR receiver output | **GPIO34** | in | Input-only pin with no boot-time output, so it never drives against the receiver |
| BOOT button | **GPIO0** | in | On the board. Do not hold it while resetting: GPIO0 low at reset enters the ROM download mode |
| Status LED | **GPIO2** | out | Active high. On-board LED on DevKit V1 |

The pins are constants in [`src/board_config.h`](src/board_config.h).

### Wiring

```
 IR transmitter (all grounds common with the ESP32 board)

 5V (VIN) ----+------------------+------------------+
              |                  |                  |
          [R3 33R]           [R4 33R]           C1 100uF (+)
              |                  |                  |
          D1 anode           D2 anode              GND
          D1 cathode         D2 cathode
              |                  |
              +---------+--------+
                        |
                   Q1 collector
 GPIO4 --[R1 470R]--+-- Q1 base        Q1 = PN2222A (NPN)
                    |   Q1 emitter --- GND
                [R2 10k]
                    |
                   GND

 IR receiver (TSOP38238: dome towards you, legs down = 1 OUT, 2 GND, 3 VS)

 3V3 --[R5 100R]--+-- U2 pin 3 VS
                  |
              [C2 100nF]
                  |
 GND -------------+-- U2 pin 2 GND
 GPIO34 ------------- U2 pin 1 OUT      (optional R6 10k from OUT to 3V3)
```

Netlist:

| From | Through | To |
| --- | --- | --- |
| 5V | R3 33 Ω | D1 anode (long leg); D1 cathode (flat side) → Q1 collector |
| 5V | R4 33 Ω | D2 anode; D2 cathode → Q1 collector (D2 optional) |
| GPIO4 | R1 470 Ω | Q1 base |
| Q1 base | R2 10 kΩ | GND |
| Q1 emitter | | GND |
| 5V | C1 100 µF (+ to 5V) | GND |
| 3V3 | R5 100 Ω | U2 VS; C2 100 nF from U2 VS to GND |
| U2 OUT | | GPIO34 (R6 10 kΩ to 3V3 optional) |
| U2 GND | | GND |

Pinouts differ between receiver brands and breakout boards (VS1838B clones in
particular), so check the datasheet of the part you have. Never power the
receiver from 5 V: its output would then put 5 V on GPIO34.

### Component values

Calculated, not measured (see [Status](#status)):

- **LED current.** (5.0 V − V<sub>F</sub> 1.5 V − V<sub>CE(sat)</sub> 0.2 V) / 33 Ω ≈ **100 mA
  peak per LED**. The carrier runs at about 33 % duty, so a mark averages about
  33 mA and a whole frame much less. That is within the TSAL6200 ratings
  (100 mA continuous, 200 mA peak). Resistor dissipation is 0.33 W while the
  LED is on and about 0.1 W averaged over a mark, so ¼ W parts are enough.
- **Base drive.** (3.3 V − V<sub>BE(sat)</sub> 0.8 V) / 470 Ω ≈ **5.3 mA** from GPIO4. That
  is a forced β of about 19 at 100 mA (one LED) and 38 at 200 mA (two LEDs), well
  inside saturation for a PN2222A (h<sub>FE</sub> ≥ 100 at 150 mA), and far below the
  GPIO's drive limit.
- **Supply.** Two LEDs draw about 200 mA in pulses on top of the ESP32's Wi-Fi
  peaks. C1 smooths that; use a USB supply that can deliver at least 500 mA.
- **Range.** Expect very roughly 5 to 8 m for one LED at 100 mA (unmeasured).
  Aim the LEDs at the appliance; point D2 a different way for a wider beam.

## Build, flash and test

```sh
cd firmware/esp32_bridge
pio run -e esp32dev                 # build .pio/build/esp32dev/firmware.bin
pio run -e esp32dev -t upload       # flash over USB
pio device monitor                  # 115200 baud logs
pio test -e native                  # bridge_core unit tests (host, real Unity)
tools/run_host_tests.sh             # same tests: system g++, ASan + UBSan, no PlatformIO
```

`tools/run_host_tests.sh` compiles `lib/bridge_core` and `test/test_native/*.cpp`
with `-std=c++17 -Wall -Wextra -Werror -Wpedantic -Wshadow -fsanitize=address,undefined`
against `test/host_shim/unity.h`, a small stand-in for the Unity macros the
tests use. It exits non-zero on a compile error, a failed test or a sanitizer
report. `pio test -e native` runs the same files with the real Unity.

## First-time setup

1. **Power the bridge.** With no Wi-Fi settings stored, it opens an access point
   named `IRBridge-Setup-xxxxxx` (last six hex digits of the MAC). The status LED
   blinks slowly (1 s on, 1 s off).
2. **Join that network** from a phone. The setup page opens by itself (captive
   portal); if it does not, browse to `http://192.168.4.1/`. Enter the home
   network, its password and a name for the bridge, then save. The bridge restarts
   and joins the network.
3. **Pair the app.** Press BOOT once: the LED blinks at 2 Hz for 60 s. Within that
   window the app calls `POST /v1/pair` and receives its token. The window closes
   after one successful pairing.

Why a SoftAP page and not BLE: [`docs/ADR-provisioning.md`](docs/ADR-provisioning.md).

### BOOT button

| Press | Effect |
| --- | --- |
| Short (< 5 s) | Opens the 60 s pairing window. If Wi-Fi settings are stored but the bridge has been offline for 10 s or more, it opens the setup access point for 10 minutes instead |
| Hold ≥ 5 s | Clears every paired token and closes open WebSocket sessions (LED flashes fast for 2 s) |
| Hold ≥ 15 s | Factory reset: also forgets the Wi-Fi settings and the name, then restarts into setup |

### Status LED

| Pattern | Meaning |
| --- | --- |
| Off | Connected and idle |
| Solid | Learn or capture mode is active |
| 2 Hz blink | Pairing window open |
| Fast flash for 2 s | Tokens were just cleared |
| 1 s on / 1 s off | Setup access point is up |
| Short flash every 2 s | Wi-Fi settings stored, but not connected |

## API

The binding contract is [`docs/BRIDGE_API.md`](../../docs/BRIDGE_API.md) (v1):
`GET /v1/info`, `GET /v1/health`, `POST /v1/pair`, `POST /v1/send/raw`,
`POST /v1/send/ac` (always `501` in v1: `caps.ac` is empty), `POST|DELETE /v1/learn`,
the `GET /v1/ws` WebSocket and `POST /v1/ota` ([`docs/ADR-ota.md`](docs/ADR-ota.md)).
mDNS: `_irbridge._tcp`, port 80, host `irbridge-xxxxxx.local`, TXT `api`, `id`,
`fw`, `name`.

```sh
# Pair (press BOOT first), then send an NEC frame.
curl -s -X POST http://irbridge-xxxxxx.local/v1/pair \
     -H 'Content-Type: application/json' -d '{"client":"laptop"}'
curl -s -X POST http://irbridge-xxxxxx.local/v1/send/raw \
     -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
     -d '{"carrierHz":38000,"durationsUs":[9024,4512,564,564,564]}'
```

JSON bodies must be sent with `Content-Type: application/json`. A
form-encoded body (curl's `-d` default) is consumed by the web server library
and answered with `400 bad_json`.

### Contract notes

Where the contract is silent, the firmware does the following. Changing any
of these is a contract change.

- **Check order.** `404 not_found` (before auth; the route list is public) →
  `405 method_not_allowed` with an `Allow` header → `413 too_large` (body over
  16 KiB) → `401 unauthorized` → body errors → state errors (`403`, `507`, `409`).
  For `/v1/send/raw`, body errors go `bad_json` (syntax, wrong type, missing or
  duplicate field) → `413 too_large` (more than 1024 values) → `invalid_durations`
  → `carrier_out_of_range`. Integers must be JSON integers: `38000.0` is `bad_json`.
- **OTA is exempt from the 16 KiB cap**, because a firmware image cannot fit in it.
- **Extra error codes**, for cases the table does not cover: `400 bad_request`
  (OTA headers), `400 hash_mismatch`, `400 bad_image`, `500 ota_failed`,
  `500 storage_error` (NVS write failed while pairing), `426 upgrade_required`
  (`GET /v1/ws` without a WebSocket upgrade). Every error body still has the
  contract shape `{"error", "detail"}`.
- **OTA success** answers `200 {"updated": true, "rebooting": true}` and restarts
  about 1.5 s later.
- **`POST /v1/learn`**: `timeoutMs` defaults to 15000 when omitted (an empty
  body is accepted). It must be 0 to 3,600,000, otherwise `bad_json`. A new
  request replaces a running session. `DELETE` while idle answers `200` and
  sends no `learn_stopped`. A capture that arrives after the deadline is dropped,
  and `learn_timeout` is sent instead.
- **`POST /v1/pair`**: `client` must be 1 to 32 Unicode characters with no control
  characters, otherwise `bad_json`. A bad body leaves the window open; `507`
  leaves it open too.
- **`POST /v1/send/ac`** checks that the body is a JSON object (`400 bad_json`)
  before it answers `501`.
- **Captures** are trimmed to an odd count of at most 1024 values (a trailing
  space is dropped) and each value is clamped to 1..150000 µs, so a capture can
  be sent back as it is. `atMs` is milliseconds since boot. `decoded.protocol` is
  IRremoteESP8266's protocol name (`NEC`, `SONY`, `SAMSUNG`, `DAIKIN`, ...).
  `decoded.value` is `0x` + uppercase hex, zero-padded to ⌈bits/4⌉ digits. For
  multi-byte A/C protocols it is the state bytes in IRremoteESP8266's order.
  `decoded` is `null` when the receive buffer overflowed.
- **WebSocket**: the token goes in the `Authorization` header of the upgrade
  (browsers cannot do that; the app can). Messages from clients are ignored.
  Clearing tokens closes every session with code 1008.
- **Busy**: `409 busy` is also returned while an OTA upload is in progress.
- `HEAD` and `OPTIONS` are `405`. Paths are matched exactly: `/v1/info/` is `404`.

## Security

- LAN only, plain HTTP, as the contract says. Anyone on the same Wi-Fi who can
  sniff traffic can read tokens and IR patterns; WPA2 protects only against
  outsiders. This web server stack does not offer TLS on the ESP32.
- Pairing needs physical access: a short BOOT press opens a 60 s window for one
  client. Tokens are 128 bits from the hardware RNG, kept in NVS (up to 8),
  compared in constant time. A long press revokes them all.
- Re-provisioning Wi-Fi also needs the button: the setup access point never
  comes back by itself once settings are stored, so a neighbour cannot move the
  bridge to another network. The setup network itself is open (see the ADR).
- OTA needs a token and a matching SHA-256. The digest proves integrity, not
  origin: any paired client can install firmware. Signed images are the planned
  next step ([`docs/ADR-ota.md`](docs/ADR-ota.md)).
- Request bodies are bounded (16 KiB, 1024 durations, nesting depth 16), and
  the JSON parser does not recurse. It is fuzzed in the unit tests.

## Architecture

```
lib/bridge_core/   portable C++17, no Arduino/ESP-IDF headers, unit-tested on the host
  bridge_core      Bridge: routing (method + path), preflight, handlers, events
  bridge_json      bounded, iterative, validating pull parser + writer
  bridge_signal    request body parsing/validation, capture message
  bridge_auth      tokens, Bearer parsing, token store behind TokenStorage
  bridge_controls  BOOT button classifier, pairing window, LED patterns (time injected)
  bridge_ota       streamed OTA session over an OtaTarget, SHA-256 check
  bridge_sha256    SHA-256 (FIPS 180-4)
  bridge_provisioning  id/hostname/TXT, Wi-Fi credential checks, setup page, Wi-Fi policy
src/               Arduino glue only
  main.cpp         loop: button, Wi-Fi, IR receive/transmit, LED, restarts
  http_api.cpp     ESPAsyncWebServer + AsyncWebSocket <-> Bridge
  ir_io.cpp        IRremoteESP8266 send/receive
  net.cpp          station / setup AP, captive DNS, scan, mDNS
  portal.cpp       setup page handlers
  nvs_store.cpp    Preferences (NVS)
  ota_partition.cpp  esp_ota_* as an OtaTarget
test/test_native/  Unity tests for bridge_core (also built by tools/run_host_tests.sh)
test/host_shim/    minimal Unity-compatible header for the host script
```

HTTP callbacks run on the AsyncTCP task (pinned to core 0). IR transmission
runs on the Arduino loop task (core 1): a `send/raw` request is validated and
marked busy in the core, the HTTP request is paused, the loop transmits, and
then the reply goes out with the measured `elapsedUs`. Every call into `Bridge`
holds one mutex. The core is not thread-safe and does not need to be.

The receiver is switched off while the bridge transmits, so the bridge does not
capture its own signal. The carrier is generated in software by
IRremoteESP8266, so timing accuracy under Wi-Fi load must be measured on the
rig (H2).

## Third-party

| Component | Version (pinned) | License | Role |
| --- | --- | --- | --- |
| [IRremoteESP8266](https://github.com/crankyoldgit/IRremoteESP8266) | 2.9.0 | LGPL-2.1 | IR send, receive and decode; linked into the firmware |
| [ESPAsyncWebServer](https://github.com/ESP32Async/ESPAsyncWebServer) (ESP32Async) | 3.12.1 | **LGPL-3.0** | HTTP server and WebSocket; linked into the firmware |
| [AsyncTCP](https://github.com/ESP32Async/AsyncTCP) (ESP32Async) | 3.5.0 | **LGPL-3.0** | TCP layer of the web server; linked into the firmware |
| [Arduino-ESP32](https://github.com/espressif/arduino-esp32) core and its bundled libraries (WiFi, Preferences, DNSServer, ESPmDNS) | 3.3.x via platform 8.0.0 | LGPL-2.1 | Framework; linked into the firmware |
| [ESP-IDF](https://github.com/espressif/esp-idf) (prebuilt inside Arduino-ESP32: FreeRTOS, lwIP, mbedTLS, Wi-Fi, mDNS, OTA) | as bundled | Apache-2.0, with component licences (FreeRTOS MIT, lwIP BSD-3-Clause, mbedTLS Apache-2.0, others) | SDK; linked into the firmware |
| [platform-espressif32](https://github.com/platformio/platform-espressif32) | 8.0.0 | Apache-2.0 | Build tooling only |
| [platform-native](https://github.com/platformio/platform-native) | 1.2.1 | Apache-2.0 | Build tooling only (host tests) |
| [Unity](https://github.com/ThrowTheSwitch/Unity) | as installed by PlatformIO | MIT | Test framework only; not in the firmware |

The pinned versions match the upstream release tags as of 2026-11-09. They have
not yet been resolved against the PlatformIO registry (it was unreachable while
this was written). No third-party code is copied into this directory: the
libraries are used through their public APIs and fetched by PlatformIO at build
time. `bridge_core` has no third-party dependencies at all.

## License and LGPL compliance

The firmware source in this directory is licensed under the **GNU Lesser General
Public License v2.1 or later** (`LGPL-2.1-or-later`); the text is in
[`LICENSE`](LICENSE). It is a separate program from the IR Remote app. The app
talks to it only over the network and contains none of its code or of the
libraries above (Gate L2).

The firmware image statically links LGPL-2.1 libraries (Arduino-ESP32,
IRremoteESP8266) and LGPL-3.0 libraries (ESPAsyncWebServer, AsyncTCP). We meet
their relinking requirement by publishing the complete corresponding source of
the firmware with every binary release:

1. Every bridge firmware release is a git tag. The release attaches the
   `firmware.bin`, its SHA-256, and a source archive of `firmware/esp32_bridge`
   at that tag, including `platformio.ini` with the exact library versions.
2. Anyone can rebuild the image with modified versions of any of those
   libraries (`pio run -e esp32dev`) and install it over USB or through
   `POST /v1/ota`. No device is locked against that: no secure boot, no flash
   encryption.
3. The release bundle includes this `LICENSE`, [`NOTICE`](NOTICE) and the licence
   texts of the linked libraries (LGPL-2.1, LGPL-3.0 with GPL-3.0, Apache-2.0 and
   the ESP-IDF component licences).
4. The source stays available for at least three years after the last binary
   release.

The release checklist item "Firmware source and LGPL notice published with
the bridge release" refers to the steps above. See `NOTICE` for the copyright
and attribution lines.
