# App Review video: shot list

Apple expects a video of the app on a **physical** Apple device pairing with,
and using, the required hardware. Record it with a second camera, not as a
screen recording. Keep it to 2–3 minutes, in one continuous take where
possible.

1. **Context, 10 s.** The iPhone and the IR Bridge (ESP32) side by side, with
   the TV in frame and turned off. Say: "iPhones have no IR blaster; this app
   needs a Wi-Fi IR hub."
2. **First launch, 15 s.** Open the app. Show the onboarding screen: "Connect
   a hub", the supported hubs list, and the line-of-sight tip.
3. **Local network prompt, 10 s.** Tap Connect a hub, then allow the iOS
   Local Network prompt.
4. **Discovery, 15 s.** The bridge appears under "Found on your network".
   Tap it.
5. **Pairing, 20 s.** Press the bridge's BOOT button on camera, then tap
   Pair. Show "… is connected."
6. **Add a TV, 40 s.** Add device, TV, brand. "Set 1 of N", then Send Power:
   the TV turns on, on camera. Tap Yes, then Send Volume up: the volume
   changes. Tap Yes, name the device, Save.
7. **Use it, 30 s.** Power off and on, volume up held (the volume ramps),
   mute, d-pad navigation. Each press visibly changes the TV.
8. **Offline, 10 s.** Turn on Airplane Mode, then turn Wi-Fi back on (LAN
   only). The remote still works: no internet is needed.
9. **Settings, 10 s.** About shows the no-affiliation line. Licenses lists the
   code sources.

Review notes to paste: the app requires a compatible Wi-Fi IR hub on iPhone
(IR Bridge or Broadlink RM4 mini). The supported hubs are listed in the app.
We can ship a review unit on request.
