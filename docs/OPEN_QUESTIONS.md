# Open questions

Each question has options and a recommendation. Work that does not depend on
it continues.

## Q1. Publisher and bundle ID ({{PUBLISHER}}, {{BUNDLE_ID}})

**Needed by:** M8 (store builds); earlier for signed betas.
**Status:** open. Code uses the placeholder `com.example.irremote`.
**Options:** (a) supply the publisher name and domain, so the app becomes
`<reversed domain>.irremote` on both stores; (b) keep the placeholder for
internal builds only.
**Recommendation:** (a) before any external build. The release check fails
while `com.example` remains.

## Q2. AC encoder licensing route (gate L2)

**Needed by:** M5.
**Options:** (a) encode on the ESP32 bridge with IRremoteESP8266 (LGPL;
compliance means publishing firmware source, which already happens) and
reach it through `POST /v1/send/ac`; (b) support each AC brand through
learned captures only; (c) get legal advice on clean-room encoders written
from public descriptions and human captures.
**Recommendation:** (b) now, which is how the app works today, plus
clean-room encoders as human captures arrive (c only if a brand cannot be
done that way). Note that (a) does not help phone-only users.

## Q3. Final v1 AC brands and order

**Needed by:** M5. Candidates: Voltas, LG, Samsung, Daikin, Blue Star,
Lloyd, Panasonic, Hitachi. Please confirm eight, in priority order, and
capture the scripted state list for each (see HARDWARE_TEST_PLAN H4).

## Q4. `dbus` (MPL-2.0) in the dependency graph

**Context:** bonsoir's Linux desktop plugin (`bonsoir_linux`) depends on
`dbus` (MPL-2.0). It is resolved but never compiled into the Android or iOS
apps. **Options:** (a) accept, since it is not shipped on mobile (recorded as
"not shipped" in THIRD_PARTY.md); (b) replace bonsoir with a hand-written
NSD/NWBrowser platform channel. **Recommendation:** (a). Revisit if a
desktop target is ever added.

## Q5. Flipper-IRDB community repository (UberGuidoZ)

Only contributions after a specific commit are CC0. Resolving per-file
history is expensive, and some files predate the change. **Recommendation:**
exclude it from v1. If wanted later, import only files whose full history
postdates the CC0 commit, verified by `db_build`.

## Q6. irdb announcement issue (gate L4)

A human must open an issue on probonopd/irdb announcing the app, then record
the link in THIRD_PARTY.md. Until then, the bundled database excludes irdb
data (Flipper's MIT-licensed irdb is used instead).

## Q7. Hub token storage

Tokens are in the app's private SQLite (ADR-013). **Options:** keep them
there, or move them to Keychain/Keystore (adds `flutter_secure_storage`,
BSD-3). **Recommendation:** move them in M8 hardening.

## Q8. Apple multicast entitlement

The Account Holder must request `com.apple.developer.networking.multicast`.
Until it is granted, Broadlink on iOS works by typed IP only (ADR-015).
