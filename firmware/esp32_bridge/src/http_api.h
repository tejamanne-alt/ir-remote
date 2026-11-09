// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Glue between ESPAsyncWebServer/AsyncWebSocket and bridge::Bridge.
// HTTP callbacks run on the AsyncTCP task; IR transmissions run on the
// Arduino loop task. Every call into the core holds coreLock().
#pragma once

#include <ESPAsyncWebServer.h>

#include <functional>
#include <mutex>
#include <vector>

#include "bridge_core.h"

namespace http_api {

struct PortalHooks {
  // True when the request belongs to the setup portal (setup AP client,
  // non-API path). Called on the AsyncTCP task.
  std::function<bool(AsyncWebServerRequest*)> claims;
  std::function<void(AsyncWebServerRequest*)> handle;
};

std::mutex& coreLock();

void begin(bridge::Bridge& core, PortalHooks portal);

// Loop task: takes the transmission waiting for the IR LED, if any.
bool takePendingTransmit(bridge::SendRawJob& job, AsyncWebServerRequestPtr& request);
// Loop task: answers a request that was paused for a transmission.
void answerPaused(AsyncWebServerRequestPtr request, const bridge::Response& response);
// Any task, without coreLock held: carries out core events (WebSocket text,
// closing sessions after the tokens were cleared).
void dispatch(std::vector<bridge::Event> events);
// Loop task, about once a second.
void housekeeping();

void send(AsyncWebServerRequest* request, const bridge::Response& response);

}  // namespace http_api
