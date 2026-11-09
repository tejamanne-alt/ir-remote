// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// SoftAP captive setup page (docs/ADR-provisioning.md). Served only to
// clients of the setup access point; the LAN never sees it.
#pragma once

#include <ESPAsyncWebServer.h>

#include <string>

namespace portal {

void begin(const std::string& bridgeName);
bool claims(AsyncWebServerRequest* request);
void handle(AsyncWebServerRequest* request);
// Set after new credentials were saved; the loop restarts the bridge.
bool restartRequested();

}  // namespace portal
