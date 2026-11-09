# Store listings (draft; display name and publisher pending Q1)

## App Store (iPhone)

- **Subtitle:** Universal IR remote via a Wi-Fi hub
- **First line of the description:** Requires a compatible Wi-Fi IR hub on
  iPhone. iPhones have no IR blaster.
- **Body:** Control TVs, set-top boxes, ACs, fans, projectors and soundbars
  through an IR hub on your home Wi-Fi. Guided code matching, learning from
  your original remote, custom remotes, and no account. Works offline.
- **Supported hubs:** IR Bridge (ESP32, open hardware), Broadlink RM4 mini
  (best effort).
- **Screenshots:** every screenshot caption says "with a Wi-Fi IR hub". None
  shows the iPhone pointed at a TV as if it emitted IR.

## Google Play

- **Short description:** Universal IR remote. Needs an IR blaster or a
  supported hub.
- **First line of the description:** Needs a phone with an IR blaster, or a
  supported Wi-Fi IR hub. To check: open the app, which tells you on the
  first screen; or look for "IR blaster" in your phone's specifications.
- `android.hardware.consumerir` is declared **not required**, so phones
  without an emitter can install the app and use hubs.
- **Data safety:** no data collected; crash data only if the user opts in.

## Both

- Brand names appear only as plain compatibility text ("Works with many
  Samsung TVs"). No brand logos.
- "Not affiliated with any appliance manufacturer" appears in the description
  footer and on the About screen.
