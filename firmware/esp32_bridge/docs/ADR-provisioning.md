# ADR: Wi-Fi provisioning by SoftAP captive page

- Status: accepted for F1; not yet verified on hardware (human gate H2)
- Date: 2026-11-09
- Scope: `firmware/esp32_bridge` only. The app needs no code for it.

## Context

The bridge has no screen and one button (BOOT). Before it can join the
user's network it needs the SSID and password. The build contract allows a
SoftAP captive page or BLE, stored in NVS. The app runs on iOS and Android,
and on iOS the bridge is the main way to send IR at all.

## Options

| Option | For | Against |
| --- | --- | --- |
| **SoftAP captive page** | Works with any phone or laptop browser; no app code, permissions or BLE stack; the captive-portal sheet opens by itself on iOS and Android; easy to debug | The phone has to leave its home Wi-Fi for a minute; the setup network is open unless a password is printed somewhere |
| BLE (custom GATT or Improv-BLE) | Phone stays on its Wi-Fi; link-layer pairing possible | App needs a BLE stack, Bluetooth permissions on both platforms and more App Review explanation; adds about 300 to 500 KB of flash and RAM pressure on the ESP32; two radios to debug |
| SmartConfig / ESP-Touch | No AP switch | Broadcasts the Wi-Fi password in a recoverable form; unreliable on 5 GHz-only phones; needs app code |
| Improv over USB serial | Simple and secure | Needs a computer and cable; not a consumer flow |
| WPS | No typing | Disabled on many routers; WPS PIN is insecure |

## Decision

Use a **SoftAP captive portal**:

1. With no credentials in NVS (namespace `irb-wifi`), the bridge starts an
   access point `IRBridge-Setup-xxxxxx` and answers every DNS query with its own
   address (192.168.4.1). Captive-portal probes (Android `generate_204`, Apple
   `hotspot-detect.html`, Windows `connecttest.txt`) are redirected to the setup
   page, so the phone opens it automatically.
2. The page lists nearby networks (scanned, HTML-escaped) and asks for SSID,
   password and a bridge name. Input is validated (`bridge::validateCredentials`):
   SSID 1 to 32 bytes; password empty, 8 to 63 printable ASCII characters or
   64 hex digits; name 1 to 32 characters.
3. The settings go to NVS and the bridge restarts as a station. The setup page
   is only served to clients of the setup AP, never on the LAN.
4. **Re-provisioning needs the button.** If stored credentials stop working
   (new router password), the bridge keeps retrying and does not bring the AP
   back by itself. After it has been offline for 10 s, a short BOOT press opens
   the setup AP for 10 minutes. While the setup AP is up, the station stops
   connecting, because the AP and the station share one radio channel and the
   AP would hop channels under the phone. A 15 s hold is a factory reset: it
   forgets the tokens and the Wi-Fi settings.

The decision logic is `bridge::WifiPolicy` in `bridge_core` and is unit-tested.
The glue in `src/net.cpp` and `src/portal.cpp` only applies it.

## Consequences

- No BLE code in the app or the firmware, and no Bluetooth permission prompts.
- The setup network is **open**, so the home Wi-Fi password crosses the air
  unencrypted once, inside a window the user starts. That is acceptable for a
  hobby-grade reference hub set up at home, and the page says so. If it is not
  acceptable, the options are:
  - Build with `-DBRIDGE_SETUP_AP_PASSWORD=\"...\"` (WPA2 on the setup AP).
    A shared default password does not stop a passive attacker who knows it,
    so this only helps with a per-device secret.
  - A per-device random AP password printed on the serial console or a label.
  - WPA3-SAE on the setup AP, which resists passive capture even with a known
    password. It needs a newer ESP-IDF configuration than Arduino-ESP32 ships.
- A neighbour cannot re-provision the bridge without pressing its button.
- The phone leaves its home network during setup. The app's onboarding should
  say "join `IRBridge-Setup-...`, then come back", and then rediscover the bridge
  over mDNS.

## Verification

Pending hardware (H2): first boot opens the setup AP; the captive sheet appears
on one iOS and one Android phone; a saved network is joined after the restart;
a wrong password leads to the "offline" LED pattern; a BOOT press brings the
setup AP back; a factory reset returns to setup.
