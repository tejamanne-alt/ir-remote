// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// ESP32 IR bridge, API v1 (docs/BRIDGE_API.md).
//
// All protocol logic lives in lib/bridge_core and is unit-tested on the host.
// This file only wires it to the hardware and the network:
//   AsyncTCP task  -> HTTP + WebSocket callbacks (http_api.cpp)
//   Arduino loop   -> BOOT button, Wi-Fi, IR receive, IR transmit, LED
// Every call into the core holds http_api::coreLock().
#include <Arduino.h>
#include <WiFi.h>
#include <esp_mac.h>
#include <esp_random.h>
#include <esp_timer.h>

#include <mutex>
#include <vector>

#include "board_config.h"
#include "bridge_core.h"
#include "http_api.h"
#include "ir_io.h"
#include "net.h"
#include "nvs_store.h"
#include "ota_partition.h"
#include "portal.h"

namespace {

class EspPlatform : public bridge::Platform {
 public:
  // Hardware RNG; it is a true RNG while the radio is on, which it is
  // whenever a client can pair.
  void randomBytes(uint8_t* out, size_t len) override { esp_fill_random(out, len); }
  int32_t rssiDbm() override { return net::stationConnected() ? WiFi.RSSI() : 0; }
  uint32_t freeHeapBytes() override { return ESP.getFreeHeap(); }
};

EspPlatform platform;
nvs_store::TokenBlobStorage tokenStorage;
EspOtaTarget otaTarget;
bridge::Bridge* core = nullptr;
bridge::Identity identity;
bridge::WifiPolicy wifiPolicy;
bridge::ButtonTracker button;
uint64_t restartAtMs = 0;
uint64_t lastHousekeepingMs = 0;

uint64_t nowMs() { return static_cast<uint64_t>(esp_timer_get_time()) / 1000; }

void setLed(bool on) {
  digitalWrite(board::kStatusLedPin, (on == board::kStatusLedActiveHigh) ? HIGH : LOW);
}

void runCoreEvents(std::vector<bridge::Event> events) { http_api::dispatch(std::move(events)); }

void handleButton(uint64_t now) {
  const bool pressed = digitalRead(board::kBootButtonPin) == LOW;
  const bridge::ButtonEvent e = button.update(pressed, now);
  if (e == bridge::ButtonEvent::None) return;
  log_i("BOOT button: %s press", bridge::buttonEventName(e));
  // Offline with stored credentials: a short press brings the setup page back.
  if (e == bridge::ButtonEvent::ShortPress && wifiPolicy.handleShortPress(now)) {
    log_i("setup access point opened by button");
    return;
  }
  std::vector<bridge::Event> events;
  {
    std::lock_guard<std::mutex> g(http_api::coreLock());
    if (!core->onButton(e, now)) log_e("could not persist the cleared token list");
    events = core->takeEvents();
  }
  runCoreEvents(std::move(events));
  if (e == bridge::ButtonEvent::FactoryResetPress) {
    log_w("factory reset: forgetting Wi-Fi settings and restarting");
    nvs_store::clearWifi();
    restartAtMs = now + board::kRestartDelayMs;
  }
}

void handleCapture(uint64_t now) {
  bridge::Capture capture;
  if (!ir_io::poll(capture, now)) return;
  std::vector<bridge::Event> events;
  {
    std::lock_guard<std::mutex> g(http_api::coreLock());
    core->onCapture(capture);
    events = core->takeEvents();
  }
  runCoreEvents(std::move(events));
}

void handleTransmit() {
  bridge::SendRawJob job;
  AsyncWebServerRequestPtr request;
  if (!http_api::takePendingTransmit(job, request)) return;
  // Not holding the core lock: /v1/info, /v1/health and the WebSocket keep
  // answering while the LED is busy, and a second send gets 409 busy.
  const uint64_t elapsedUs = ir_io::transmit(job);
  bridge::Response response;
  {
    std::lock_guard<std::mutex> g(http_api::coreLock());
    response = core->finishTransmit(elapsedUs);
  }
  http_api::answerPaused(request, response);
}

void updateLed(uint64_t now) {
  bridge::LedPattern pattern;
  {
    std::lock_guard<std::mutex> g(http_api::coreLock());
    pattern = core->ledPattern(now);
  }
  if (pattern == bridge::LedPattern::Off) {
    if (net::accessPointUp()) {
      pattern = bridge::LedPattern::ProvisioningBlink;
    } else if (wifiPolicy.offline(now)) {
      pattern = bridge::LedPattern::OfflineBlip;
    }
  }
  setLed(bridge::ledLevel(pattern, now));
}

void scheduleRestart(uint64_t now) {
  if (restartAtMs != 0) {
    if (now >= restartAtMs) {
      log_w("restarting");
      ESP.restart();
    }
    return;
  }
  bool updated = false;
  {
    std::lock_guard<std::mutex> g(http_api::coreLock());
    updated = core->rebootRequested();
  }
  // Leave time for the HTTP reply to reach the client first.
  if (updated || portal::restartRequested()) restartAtMs = now + board::kRestartDelayMs;
}

}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(board::kBootButtonPin, INPUT_PULLUP);
  pinMode(board::kStatusLedPin, OUTPUT);
  setLed(false);

  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  bridge::WifiCredentials credentials;
  const bool hasCredentials = nvs_store::loadWifi(credentials);

  identity.id = bridge::deviceIdFromMac(mac);
  identity.name = credentials.name.empty() ? bridge::kDefaultBridgeName : credentials.name;
  identity.fw = bridge::kFirmwareVersion;

  static bridge::Bridge bridgeCore(identity, tokenStorage, platform, &otaTarget);
  core = &bridgeCore;
  if (!core->begin()) log_e("could not read paired tokens; starting with none");
  log_i("IR bridge fw %s id %s, %u paired client(s)", identity.fw.c_str(), identity.id.c_str(),
        static_cast<unsigned>(core->pairedClients()));

  ir_io::begin();
  wifiPolicy.begin(hasCredentials, nowMs());
  net::begin(credentials, bridge::hostnameFromMac(mac), bridge::apSsidFromMac(mac));
  portal::begin(identity.name);
  http_api::begin(*core, http_api::PortalHooks{portal::claims, portal::handle});
}

void loop() {
  const uint64_t now = nowMs();
  handleButton(now);
  net::loop(now, wifiPolicy, identity);
  {
    std::vector<bridge::Event> events;
    {
      std::lock_guard<std::mutex> g(http_api::coreLock());
      core->tick(now);  // pairing window expiry, learn timeout
      events = core->takeEvents();
    }
    runCoreEvents(std::move(events));
  }
  handleCapture(now);
  handleTransmit();
  updateLed(now);
  if (now - lastHousekeepingMs >= 1000) {
    lastHousekeepingMs = now;
    http_api::housekeeping();
  }
  scheduleRestart(now);
  delay(1);
}
