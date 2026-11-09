# ESP32 bridge API, v1

This is the contract between `firmware/esp32_bridge` and `EspBridgeTransport` in
`packages/ir_transports`. Both sides test against it. Changes need an ADR and a
bump of `api` in `GET /v1/info`.

## Discovery

- mDNS service `_irbridge._tcp`, port 80.
- Hostname `irbridge-<last 6 hex digits of MAC>.local`.
- TXT records: `api=1`, `id=<12 lowercase hex MAC>`, `fw=<semver>`, `name=<user name>`.
- Fallback: the user types the IP address.

## Transport and errors

- Plain HTTP on the LAN; JSON bodies (`Content-Type: application/json`), UTF-8.
- Request bodies are capped at 16 KiB, and a longer body gets `413 too_large`.
- Every error response is `{"error": "<code>", "detail": "<human text>"}`.

| HTTP | `error` | When |
| --- | --- | --- |
| 400 | `bad_json` | Body is not valid JSON or a field has the wrong type |
| 400 | `invalid_durations` | Empty, even count, a value ≤ 0 or > 150000, or total > `maxPatternUs` |
| 400 | `carrier_out_of_range` | Carrier outside `carrierMinHz..carrierMaxHz` |
| 401 | `unauthorized` | Missing or unknown token |
| 403 | `pairing_window_closed` | `POST /v1/pair` without a recent button press |
| 404 | `not_found` | Unknown route |
| 405 | `method_not_allowed` | Known route, wrong method |
| 409 | `busy` | A transmission is in progress (the client retries after it) |
| 413 | `too_large` | Body over 16 KiB, or more than `maxDurations` durations |
| 501 | `not_implemented` | `POST /v1/send/ac` on firmware built without AC encoders |
| 507 | `pairing_full` | Already 8 paired clients; the user clears pairings with a long press |

## Authentication and pairing

- Every route except `GET /v1/info` and `POST /v1/pair` requires
  `Authorization: Bearer <token>`.
- A short press on the BOOT button opens a 60 s pairing window, and the status LED
  blinks while it is open.
- `POST /v1/pair` with `{"client": "<device name, ≤ 32 chars>"}` returns
  `200 {"token": "<32 lowercase hex>"}` while the window is open, then closes the
  window. Tokens persist in NVS, up to 8 of them.
- A long press (≥ 5 s) clears every token.

## Routes

### `GET /v1/info` (no auth)

```json
{
  "api": 1,
  "fw": "0.1.0",
  "id": "a1b2c3d4e5f6",
  "name": "IR Bridge",
  "caps": {
    "carrierMinHz": 30000,
    "carrierMaxHz": 60000,
    "maxPatternUs": 4000000,
    "maxDurations": 1024,
    "canLearn": true,
    "ac": []
  },
  "pairingWindowOpen": false
}
```

`caps.ac` lists AC protocol IDs the firmware can encode (Gate L2 option a). It is
empty in v1.

### `GET /v1/health`

`200 {"ok": true, "uptimeS": 1234, "rssi": -55, "freeHeap": 123456, "learning": false}`

### `POST /v1/send/raw`

Request: `{"carrierHz": 38000, "durationsUs": [9024, 4512, 564, ...]}`

- `durationsUs` is mark-first and odd in length. Inter-frame gaps are spaces
  inside the list (the client flattens frames and gaps).
- The response comes after transmission ends:
  `200 {"sent": true, "elapsedUs": 67512}`.

### `POST /v1/send/ac`

Request: `{"protocol": "<id>", "model": 0, "state": <AcState JSON>}`. Returns
`501 not_implemented` unless the firmware was built with AC encoders.

### `POST /v1/learn`

Request: `{"timeoutMs": 15000}`. Learn mode ends after the first capture, or at
the timeout. `timeoutMs: 0` starts capture mode, which keeps capturing until
`DELETE /v1/learn`. That mode is the test-rig instrument.

Response: `202 {"learning": true}`.

### `DELETE /v1/learn`

`200 {"learning": false}`

### `GET /v1/ws` (WebSocket, auth header required on the upgrade)

Server-to-client messages:

```json
{"type": "capture", "carrierHz": null, "durationsUs": [9010, 4490, ...],
 "decoded": {"protocol": "NEC", "value": "0x20DF10EF", "bits": 32}, "atMs": 123456}
{"type": "learn_timeout"}
{"type": "learn_stopped"}
```

- `carrierHz` is `null` when the receiver module demodulates and cannot measure
  the carrier. The app then assumes 38 kHz.
- `decoded` is `null` when the firmware decoder does not recognise the protocol.
  The app runs its own decoder anyway.
- Captures start with a mark. The firmware drops the leading gap and ends a
  capture after 100 ms of silence.

### `POST /v1/ota`

The body is the raw firmware image. Headers are `Authorization`,
`X-Firmware-SHA256: <hex>` and `Content-Length`. The firmware checks the hash
before it switches partitions. Details are in ADR-011.
