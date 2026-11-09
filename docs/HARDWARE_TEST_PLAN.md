# Hardware test plan

Nothing here has been run yet. Nothing in this repository has been verified
on a real phone emitter, hub or appliance. Only rows marked **passed** by a
human may set `verifiedOn` in the code database, or add rows to the OEM quirk
table (`apps/remote/assets/oem_quirks.json`).

## Human gates

| Gate | What a human does | Pass condition | Status |
| --- | --- | --- | --- |
| H1 | Phone emitter sends the NEC test vectors; the bridge in capture mode decodes them | Each capture decodes to the sent protocol and parameters, with timings within ±25% | BLOCKED-ON-HUMAN: needs an Android phone with an emitter and a flashed bridge |
| H2 | Flash the ESP32 bridge, pair it (button press), run the capture loop | `GET /v1/info` answers, pairing issues a token, and captures stream over `/v1/ws` | BLOCKED-ON-HUMAN: needs the board, a 940 nm LED, a transistor and a 38 kHz receiver |
| H3 | Match and control a real TV and a set-top box, on an Android emitter and on iOS through a hub | Power plus the confirm key work on both paths; the rows below are filled in | BLOCKED-ON-HUMAN |
| H4 | Each v1 AC brand verified on a real unit, from captured fixtures | Encoder output reproduces each captured frame bit for bit, with timings within tolerance | BLOCKED-ON-HUMAN: needs the Q3 brand list and captures |
| H5 | Each system surface (widget, tile, intents, Control Center) sends a command | M7 | not started |
| H6 | Store submissions | M8 | not started |

## Closed-loop rig procedure (H1, per phone model and hub)

1. Put the bridge in capture mode next to the transport under test.
2. Run the debug Loopback screen (arrives with M3/H1) to send every codec's
   test vectors (`packages/ir_core/test/fixtures/`).
3. Each capture is decoded by `ProtocolRegistry.identify`, and the JSON report
   is attached here.
4. Record the phone's `Build.MANUFACTURER`/`MODEL`, `getCarrierFrequencies()`
   and the per-call transmit durations from logcat (`ConsumerIr` tag).

## AC capture script (H4, per brand)

Use bridge learn mode with the original remote, one capture per state: off;
cool 24 °C fan auto; cool 18 °C fan high; heat 30 °C; dry; fan only; swing on.
Save each as `packages/ir_core/test/fixtures/ac/<brand>/<state>.json` with
`source: "<remote model>, <tester>, <date>"`.

## Appliance matrix

Columns: Appliance model · Transport · Key or state · Result · Tester · Date · Notes

| Appliance model | Transport | Key or state | Result | Tester | Date | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| _TV (brand/model)_ | Android emitter (_phone model_) | POWER | | | | |
| _TV (brand/model)_ | Android emitter | VOL_UP | | | | |
| _TV (brand/model)_ | ESP32 bridge from iPhone | POWER | | | | |
| _TV (brand/model)_ | ESP32 bridge from iPhone | VOL_UP | | | | |
| _TV (brand/model)_ | Broadlink RM4 mini | POWER | | | | |
| _Set-top box (operator/model)_ | Android emitter | POWER | | | | |
| _Set-top box (operator/model)_ | Android emitter | CH_UP | | | | |
| _Set-top box (operator/model)_ | ESP32 bridge from iPhone | GUIDE | | | | |
| _AC (brand/model)_ | ESP32 bridge | learned POWER | | | | |
