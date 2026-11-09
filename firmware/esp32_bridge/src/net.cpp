// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "net.h"

#include <AsyncTCP.h>
#include <DNSServer.h>
#include <ESPmDNS.h>
#include <WiFi.h>

#include <atomic>
#include <mutex>

namespace net {

namespace {

constexpr uint64_t kStationRetryMs = 30000;
constexpr uint64_t kRescanMs = 30000;

bridge::WifiCredentials creds;
std::string hostname;
std::string apSsid;
bool modeApplied = false;
bridge::WifiMode appliedMode = bridge::WifiMode::Station;
bool stationStarted = false;
std::atomic<bool> apUp{false};
std::atomic<bool> connected{false};
DNSServer dns;
bool mdnsStarted = false;
uint64_t lastRetryMs = 0;
uint64_t lastScanMs = 0;
bool scanning = false;
std::mutex scanLock;
std::vector<bridge::ScannedNetwork> scanned;

void startStation() {
  if (creds.ssid.empty()) return;
  WiFi.setSleep(false);  // modem sleep adds 100+ ms to incoming requests
  WiFi.setAutoReconnect(true);
  WiFi.begin(creds.ssid.c_str(), creds.password.empty() ? nullptr : creds.password.c_str());
  stationStarted = true;
}

void startScan(uint64_t nowMs) {
  if (WiFi.scanNetworks(true) == WIFI_SCAN_FAILED) {
    scanning = false;
  } else {
    scanning = true;
  }
  lastScanMs = nowMs;
}

void pollScan(uint64_t nowMs) {
  if (!scanning) {
    if (nowMs - lastScanMs >= kRescanMs) startScan(nowMs);
    return;
  }
  const int16_t n = WiFi.scanComplete();
  if (n == WIFI_SCAN_RUNNING) return;
  scanning = false;
  if (n < 0) return;
  std::vector<bridge::ScannedNetwork> found;
  for (int16_t i = 0; i < n; ++i) {
    bridge::ScannedNetwork net;
    net.ssid = WiFi.SSID(i).c_str();
    net.rssi = WiFi.RSSI(i);
    net.secure = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
    bool duplicate = false;
    for (const auto& f : found) duplicate = duplicate || f.ssid == net.ssid;
    if (!net.ssid.empty() && !duplicate) found.push_back(net);
  }
  WiFi.scanDelete();
  std::lock_guard<std::mutex> g(scanLock);
  scanned.swap(found);
}

void startAccessPoint(uint64_t nowMs) {
#ifdef BRIDGE_SETUP_AP_PASSWORD
  WiFi.softAP(apSsid.c_str(), BRIDGE_SETUP_AP_PASSWORD);
#else
  WiFi.softAP(apSsid.c_str());  // open; see docs/ADR-provisioning.md
#endif
  dns.start(53, "*", WiFi.softAPIP());  // every name resolves to the portal
  apUp = true;
  startScan(nowMs);
  log_i("setup access point %s up at %s", apSsid.c_str(), WiFi.softAPIP().toString().c_str());
}

void stopAccessPoint() {
  dns.stop();
  WiFi.softAPdisconnect(true);
  apUp = false;
}

void applyMode(bridge::WifiMode mode, uint64_t nowMs) {
  switch (mode) {
    case bridge::WifiMode::Station:
      if (apUp) stopAccessPoint();
      WiFi.mode(WIFI_STA);
      WiFi.setAutoReconnect(true);
      if (!stationStarted) {
        startStation();
      } else {
        WiFi.reconnect();
      }
      break;
    case bridge::WifiMode::AccessPoint:
      WiFi.mode(WIFI_AP);
      if (!apUp) startAccessPoint(nowMs);
      break;
    case bridge::WifiMode::StationAndAccessPoint:
      // The AP and the station share one radio channel. While the setup page
      // is open, stop the station from hunting for its network so the AP
      // does not hop channels under the phone that is using it.
      WiFi.mode(WIFI_AP_STA);
      WiFi.setAutoReconnect(false);
      WiFi.disconnect(false, false);
      if (!apUp) startAccessPoint(nowMs);
      break;
  }
}

void startMdns(const bridge::Identity& identity) {
  if (!MDNS.begin(hostname.c_str())) {
    log_e("mDNS start failed");
    return;
  }
  MDNS.setInstanceName(identity.name.c_str());
  MDNS.addService("irbridge", "tcp", bridge::kHttpPort);  // -> _irbridge._tcp
  for (const auto& kv : bridge::mdnsTxtRecords(identity)) {
    MDNS.addServiceTxt("irbridge", "tcp", kv.first.c_str(), kv.second.c_str());
  }
  mdnsStarted = true;
  log_i("mDNS %s.local, _irbridge._tcp port %u", hostname.c_str(), bridge::kHttpPort);
}

}  // namespace

void begin(const bridge::WifiCredentials& credentials, const std::string& host,
           const std::string& ssid) {
  creds = credentials;
  hostname = host;
  apSsid = ssid;
  WiFi.persistent(false);  // credentials live in our own NVS namespace
  WiFi.setHostname(hostname.c_str());
}

void loop(uint64_t nowMs, bridge::WifiPolicy& policy, const bridge::Identity& identity) {
  const bool isUp = WiFi.status() == WL_CONNECTED;
  if (isUp != connected.load()) {
    connected = isUp;
    if (isUp) {
      log_i("station connected, IP %s", WiFi.localIP().toString().c_str());
    } else {
      log_w("station offline");
    }
  }
  policy.setStationConnected(isUp, nowMs);

  const bridge::WifiMode mode = policy.mode(nowMs);
  if (!modeApplied || mode != appliedMode) {
    applyMode(mode, nowMs);
    appliedMode = mode;
    modeApplied = true;
    lastRetryMs = nowMs;
  }
  if (mode == bridge::WifiMode::Station && !isUp && nowMs - lastRetryMs >= kStationRetryMs) {
    lastRetryMs = nowMs;
    WiFi.disconnect(false, false);
    startStation();
  }
  if (isUp && !mdnsStarted) startMdns(identity);
  if (apUp) {
    dns.processNextRequest();  // no-op on Arduino-ESP32 3.x (async), needed on 2.x
    pollScan(nowMs);
  }
}

bool stationConnected() { return connected.load(); }
bool accessPointUp() { return apUp.load(); }

bool isAccessPointClient(AsyncWebServerRequest* request) {
  if (!apUp.load() || request == nullptr || request->client() == nullptr) return false;
  return request->client()->localIP() == WiFi.softAPIP();
}

std::vector<bridge::ScannedNetwork> networks() {
  std::lock_guard<std::mutex> g(scanLock);
  return scanned;
}

}  // namespace net
