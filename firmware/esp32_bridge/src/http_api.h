// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Glue between ESP-IDF's esp_http_server (HTTP + WebSocket, Apache-2.0) and
// bridge::Bridge. Requests run on the server task (pinned to core 0); IR
// transmissions run on the Arduino loop task (core 1). Every call into the
// core holds coreLock().
#pragma once

#include <esp_http_server.h>

#include <mutex>
#include <string>
#include <vector>

#include "bridge_core.h"

namespace http_api {

struct PortalHooks {
  // True when the request belongs to the setup portal (setup AP client,
  // non-API path). Called on the server task.
  bool (*claims)(httpd_req_t* request) = nullptr;
  esp_err_t (*handle)(httpd_req_t* request) = nullptr;
};

std::mutex& coreLock();

// Starts the server on bridge::kHttpPort. Returns false if it could not start.
bool begin(bridge::Bridge& core, PortalHooks portal);

// Loop task: takes the transmission waiting for the IR LED, if any, and its
// sequence number.
bool takePendingTransmit(bridge::SendRawJob& job, uint32_t& seq);
// Loop task: answers the request of transmission `seq` with its result.
void completeTransmit(uint32_t seq, const bridge::Response& response);
// Any task, without coreLock held: carries out core events (WebSocket text,
// closing sessions after the tokens were cleared). Runs on the server task.
void dispatch(std::vector<bridge::Event> events);

// Helpers for request handlers (server task).
esp_err_t send(httpd_req_t* request, const bridge::Response& response);
esp_err_t redirect(httpd_req_t* request, const std::string& location);
std::string header(httpd_req_t* request, const char* name);
std::string path(httpd_req_t* request);
bridge::Method method(httpd_req_t* request);
// Reads the whole body (Content-Length bytes, at most `cap`). False on a
// socket error, a timeout or a body over `cap`.
bool readBody(httpd_req_t* request, std::string& out, size_t cap);

}  // namespace http_api
