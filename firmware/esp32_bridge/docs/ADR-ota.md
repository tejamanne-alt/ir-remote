# ADR: OTA firmware updates with token auth and SHA-256 verification

- Status: accepted for F1; not yet verified on hardware (human gate H2)
- Date: 2026-11-09
- Contract: `POST /v1/ota` in `docs/BRIDGE_API.md`. The contract points to
  "ADR-011", which does not exist yet; this document is that design and can be
  renumbered when it moves into `docs/DECISIONS.md`.

## Context

The contract fixes the request: the body is the raw firmware image, and the
headers are `Authorization: Bearer <token>`, `X-Firmware-SHA256: <hex>` and
`Content-Length`. The firmware checks the hash before it switches partitions.
The build contract adds: LAN only, authenticated, with an ADR.

Constraints:

- The image (about 1.2 to 1.6 MB) is far larger than RAM, so it must be streamed
  to flash.
- The 16 KiB JSON body cap cannot apply to this route.
- The handler reads the body with `httpd_req_recv` in 1 KiB chunks on the esp_http_server task.
  Nothing on that task may block for seconds (watchdog, other clients).
- A failed or interrupted update must leave the running firmware untouched.

## Decision

1. **Partition layout**: `min_spiffs.csv`, two 1.875 MB OTA app slots
   (`app0`/`app1`) plus `otadata`. An update always goes to the inactive slot.
2. **Admission** (`Bridge::otaBegin`, checked at the first body chunk, in order):
   route and method → `401` without a valid token → `409 busy` while a
   transmission or another update is running → `400 bad_request` unless
   `X-Firmware-SHA256` is 64 hex digits (either case) and `Content-Length` is
   present and non-zero (no chunked uploads) → `413 too_large` when the image is
   larger than the slot → `500 ota_failed` if the slot cannot be opened.
3. **Streaming**: each chunk is fed to an incremental SHA-256 (`bridge_sha256`,
   written from FIPS 180-4) and written with `esp_ota_write`. `esp_ota_begin`
   uses `OTA_WITH_SEQUENTIAL_WRITES`, which erases sector by sector instead of
   erasing 1.5 MB up front, so no single step blocks the network task for long.
   More bytes than `Content-Length` abort the update.
4. **Verification, in this order, before anything changes on boot**:
   1. byte count equals `Content-Length`, otherwise `400 bad_request`;
   2. SHA-256 equals the header, otherwise `400 hash_mismatch` (slot discarded);
   3. `esp_ota_end` validates the image structure, otherwise `400 bad_image`;
   4. only then does `esp_ota_set_boot_partition` select the new slot (a failure
      gives `500 ota_failed`).
5. **Reply and restart**: `200 {"updated": true, "rebooting": true}`, then a restart
   1.5 s later so the reply reaches the client.
6. **Disconnects**: if the client goes away mid-upload, the session is aborted
   and the slot discarded. `send/raw` answers `409 busy` while an upload runs,
   because flash writes stall the CPU and would distort IR timing.

The decision logic lives in `bridge_core` (`OtaSession`, `Bridge::ota*`) behind
an `OtaTarget` interface, and is unit-tested: happy path, wrong digest, flipped
byte, short and long bodies, header errors, flash failures and busy interlocks.
`src/ota_partition.cpp` maps `OtaTarget` onto `esp_ota_*`.

## Consequences and limits

- **Integrity, not authenticity.** The digest catches corruption and truncation.
  It does not prove who built the image: any paired client, or anyone who has
  sniffed a token on the LAN (plain HTTP), can install arbitrary firmware. That
  is the main residual risk of v1.
- **No automatic rollback.** v1 does not depend on bootloader app rollback,
  because we have not verified that it is enabled in Arduino-ESP32's prebuilt
  bootloader. An image that validates but does not work (for example, it never
  joins Wi-Fi) has to be recovered over USB. Hardware gate H2 should include one
  deliberate bad-update test.
- The client must send `Content-Length`; chunked uploads are refused.

## Follow-ups (each needs a contract change and an `api` decision)

1. **Signed images.** The release pipeline signs the image with Ed25519, the
   firmware carries the public key, and the request gains
   `X-Firmware-Signature`. Verification fits in `bridge_core` and is testable on
   the host. This is the recommended next step.
2. **Physical presence for updates.** Accept `POST /v1/ota` only within 60 s of a
   BOOT press, reusing the pairing-window machinery. This needs app UX for it.
3. **Bootloader rollback.** Build with `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE`
   (an ESP-IDF + Arduino component build), and mark the new app valid only after
   it has joined Wi-Fi and served `/v1/health`.
