// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Wi-Fi station / setup access point, captive DNS, network scan and mDNS
// (_irbridge._tcp). The decisions come from bridge::WifiPolicy.
#pragma once

#include <esp_http_server.h>

#include <string>
#include <vector>

#include "bridge_core.h"

namespace net {

void begin(const bridge::WifiCredentials& credentials, const std::string& hostname,
           const std::string& apSsid);
// Loop task. Applies the policy's mode, retries the station, scans for the
// setup page and starts mDNS once the station is up.
void loop(uint64_t nowMs, bridge::WifiPolicy& policy, const bridge::Identity& identity);

bool stationConnected();
bool accessPointUp();
// True when the request arrived through the setup access point interface.
bool isAccessPointClient(httpd_req_t* request);
// Last scan result (copy; safe from any task).
std::vector<bridge::ScannedNetwork> networks();

}  // namespace net
