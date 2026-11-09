// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// HTTP and WebSocket on ESP-IDF's esp_http_server (Apache-2.0), which is part
// of the Arduino-ESP32 core: no extra libraries, and nothing LGPL-3.0.
//
// Notes on esp_http_server behaviour this file relies on (ESP-IDF 5.5):
// - Handlers run one at a time on the server task. A send waits there for the
//   loop task to finish transmitting, so /v1/info answers after the LED is
//   free; the core still reports 409 busy for overlapping sends.
// - Request bodies need a Content-Length (no chunked uploads); the app sends
//   one (docs/BRIDGE_API.md).
// - The Arduino build has no WebSocket pre-handshake hook, so the token on an
//   upgrade is checked right after the handshake and a bad one closes the
//   socket with code 1008 (contract note in docs/BRIDGE_API.md).
#include "http_api.h"

#include <Arduino.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <optional>
#include <string>

namespace http_api {

namespace {

constexpr size_t kMaxClients = 16;
constexpr size_t kMaxWsInboundFrame = 512;

httpd_handle_t server = nullptr;
bridge::Bridge* core = nullptr;
PortalHooks portal;
std::mutex lock;

// The one transmission in flight (the core refuses a second with 409 busy).
std::mutex slotLock;
struct Slot {
  bool pending = false;  // posted by a handler, not yet taken by the loop
  bridge::SendRawJob job;
  bridge::Response response;
} slot;
SemaphoreHandle_t slotDone = nullptr;

uint64_t nowMs() { return static_cast<uint64_t>(esp_timer_get_time()) / 1000; }

struct WsWork {
  std::string text;
  bool closeAll = false;
};

void closeWebSocket(httpd_handle_t hd, int fd) {
  // Close frame payload: status 1008 (policy violation) + reason.
  static const uint8_t kPayload[] = {0x03, 0xF0, 'u', 'n', 'a', 'u', 't', 'h', 'o', 'r', 'i', 'z', 'e', 'd'};
  httpd_ws_frame_t frame;
  std::memset(&frame, 0, sizeof(frame));
  frame.final = true;
  frame.type = HTTPD_WS_TYPE_CLOSE;
  frame.payload = const_cast<uint8_t*>(kPayload);
  frame.len = sizeof(kPayload);
  httpd_ws_send_frame_async(hd, fd, &frame);
  httpd_sess_trigger_close(hd, fd);
}

// Runs on the server task (queued with httpd_queue_work).
void wsWork(void* arg) {
  std::unique_ptr<WsWork> work(static_cast<WsWork*>(arg));
  if (server == nullptr) return;
  size_t count = kMaxClients;
  int fds[kMaxClients];
  if (httpd_get_client_list(server, &count, fds) != ESP_OK) return;
  for (size_t i = 0; i < count; ++i) {
    if (httpd_ws_get_fd_info(server, fds[i]) != HTTPD_WS_CLIENT_WEBSOCKET) continue;
    if (work->closeAll) {
      closeWebSocket(server, fds[i]);
      continue;
    }
    httpd_ws_frame_t frame;
    std::memset(&frame, 0, sizeof(frame));
    frame.final = true;
    frame.type = HTTPD_WS_TYPE_TEXT;
    frame.payload = reinterpret_cast<uint8_t*>(&work->text[0]);
    frame.len = work->text.size();
    if (httpd_ws_send_frame_async(server, fds[i], &frame) != ESP_OK) {
      httpd_sess_trigger_close(server, fds[i]);  // a stuck client is dropped
    }
  }
}

bridge::Response waitForTransmit(bridge::SendRawJob job) {
  const uint64_t patternMs = job.totalUs / 1000;
  xSemaphoreTake(slotDone, 0);  // drop a signal left by an abandoned wait
  {
    std::lock_guard<std::mutex> g(slotLock);
    slot = Slot();
    slot.pending = true;
    slot.job = std::move(job);
  }
  // The loop picks the job up within a few milliseconds; allow the pattern's
  // own length plus a margin.
  const TickType_t wait = pdMS_TO_TICKS(patternMs + 3000);
  if (xSemaphoreTake(slotDone, wait) == pdTRUE) {
    std::lock_guard<std::mutex> g(slotLock);
    return slot.response;
  }
  bool neverStarted = false;
  {
    std::lock_guard<std::mutex> g(slotLock);
    neverStarted = slot.pending;
    slot.pending = false;
  }
  if (neverStarted) {
    std::lock_guard<std::mutex> g(lock);
    core->finishTransmit(0);  // clear the busy state; its reply is not used
  }
  log_e("transmission did not complete in time");
  return bridge::errorResponse(500, bridge::err::kTransmitFailed, "the IR task did not run");
}

esp_err_t handleOta(httpd_req_t* r) {
  bridge::OtaRequest o;
  o.authorization = header(r, "Authorization");
  o.sha256Header = header(r, "X-Firmware-SHA256");
  o.hasContentLength = !header(r, "Content-Length").empty();
  o.contentLength = r->content_len;
  std::optional<bridge::Response> refusal;
  {
    std::lock_guard<std::mutex> g(lock);
    refusal = core->otaBegin(o, nowMs());
  }
  if (refusal) {
    send(r, *refusal);
    // Do not drain a refused image: close the connection instead.
    return r->content_len > 0 ? ESP_FAIL : ESP_OK;
  }
  std::unique_ptr<uint8_t[]> buf(new uint8_t[1024]);
  size_t remaining = r->content_len;
  int timeouts = 0;
  while (remaining > 0) {
    const int n = httpd_req_recv(r, reinterpret_cast<char*>(buf.get()), std::min<size_t>(1024, remaining));
    if (n == HTTPD_SOCK_ERR_TIMEOUT && ++timeouts < 3) continue;
    if (n <= 0) {
      std::lock_guard<std::mutex> g(lock);
      core->otaAbort();
      return ESP_FAIL;  // client went away: drop the partial image
    }
    timeouts = 0;
    {
      std::lock_guard<std::mutex> g(lock);
      core->otaWrite(buf.get(), static_cast<size_t>(n));  // failures surface in otaFinish()
    }
    remaining -= static_cast<size_t>(n);
  }
  bridge::Response response;
  std::vector<bridge::Event> events;
  {
    std::lock_guard<std::mutex> g(lock);
    response = core->otaFinish();
    events = core->takeEvents();
  }
  const esp_err_t sent = send(r, response);
  dispatch(std::move(events));
  return sent;
}

esp_err_t handleHttp(httpd_req_t* r) {
  if (portal.claims != nullptr && portal.claims(r)) return portal.handle(r);
  bridge::Request req;
  req.method = method(r);
  req.path = path(r);
  if (req.path == "/v1/ota" && req.method == bridge::Method::Post) return handleOta(r);
  req.authorization = header(r, "Authorization");
  req.contentLength = r->content_len;
  req.webSocketUpgrade = false;  // real upgrades on /v1/ws are taken by handleWs

  // Header-only checks first, so an oversized body is never read.
  bridge::Preflight pf;
  {
    std::lock_guard<std::mutex> g(lock);
    pf = core->preflight(req.method, req.path, req.authorization, req.contentLength);
  }
  if (!pf.ok) {
    send(r, pf.error);
    return r->content_len > bridge::kMaxBodyBytes ? ESP_FAIL : ESP_OK;
  }
  if (!readBody(r, req.body, bridge::kMaxBodyBytes)) return ESP_FAIL;

  bridge::Outcome out;
  std::vector<bridge::Event> events;
  {
    std::lock_guard<std::mutex> g(lock);
    out = core->handle(req, nowMs());
    events = core->takeEvents();
  }
  dispatch(std::move(events));
  switch (out.action) {
    case bridge::Action::Respond:
      return send(r, out.response);
    case bridge::Action::AcceptWebSocket:
      return send(r, bridge::errorResponse(426, bridge::err::kUpgradeRequired, "use a WebSocket client"));
    case bridge::Action::Transmit:
      return send(r, waitForTransmit(std::move(out.job)));
  }
  return send(r, bridge::errorResponse(500, bridge::err::kTransmitFailed, "unexpected outcome"));
}

esp_err_t handleWs(httpd_req_t* r) {
  const int fd = httpd_req_to_sockfd(r);
  if (httpd_ws_get_fd_info(r->handle, fd) != HTTPD_WS_CLIENT_WEBSOCKET) {
    return handleHttp(r);  // a plain GET without an upgrade: 426 from the core
  }
  if (r->method == HTTP_GET) {
    // The handshake just completed. The contract requires a valid token on
    // the upgrade request, whose headers are still available here.
    bridge::Preflight pf;
    {
      std::lock_guard<std::mutex> g(lock);
      pf = core->preflight(bridge::Method::Get, "/v1/ws", header(r, "Authorization"), 0);
    }
    if (!pf.ok) closeWebSocket(r->handle, fd);
    return ESP_OK;
  }
  // A frame from the client. The stream is server-to-client only: read and
  // discard it, and drop clients that send oversized frames.
  httpd_ws_frame_t frame;
  std::memset(&frame, 0, sizeof(frame));
  if (httpd_ws_recv_frame(r, &frame, 0) != ESP_OK) return ESP_FAIL;
  if (frame.len == 0) return ESP_OK;
  if (frame.len > kMaxWsInboundFrame) return ESP_FAIL;
  uint8_t buf[kMaxWsInboundFrame];
  frame.payload = buf;
  return httpd_ws_recv_frame(r, &frame, frame.len);
}

}  // namespace

std::mutex& coreLock() { return lock; }

std::string header(httpd_req_t* r, const char* name) {
  const size_t len = httpd_req_get_hdr_value_len(r, name);
  if (len == 0) return std::string();
  std::string value(len + 1, '\0');
  if (httpd_req_get_hdr_value_str(r, name, &value[0], value.size()) != ESP_OK) return std::string();
  value.resize(len);
  return value;
}

std::string path(httpd_req_t* r) {
  std::string p(r->uri);
  const size_t q = p.find('?');
  if (q != std::string::npos) p.resize(q);
  return p;
}

bridge::Method method(httpd_req_t* r) {
  return bridge::parseMethod(http_method_str(static_cast<enum http_method>(r->method)));
}

bool readBody(httpd_req_t* r, std::string& out, size_t cap) {
  out.clear();
  if (r->content_len > cap) return false;
  size_t remaining = r->content_len;
  out.reserve(remaining);
  char buf[512];
  int timeouts = 0;
  while (remaining > 0) {
    const int n = httpd_req_recv(r, buf, std::min(sizeof(buf), remaining));
    if (n == HTTPD_SOCK_ERR_TIMEOUT && ++timeouts < 3) continue;
    if (n <= 0) return false;
    timeouts = 0;
    out.append(buf, static_cast<size_t>(n));
    remaining -= static_cast<size_t>(n);
  }
  return true;
}

esp_err_t send(httpd_req_t* r, const bridge::Response& response) {
  httpd_resp_set_status(r, bridge::statusLine(response.status));
  httpd_resp_set_type(r, response.contentType);
  httpd_resp_set_hdr(r, "Cache-Control", "no-store");
  if (!response.allow.empty()) httpd_resp_set_hdr(r, "Allow", response.allow.c_str());
  return httpd_resp_send(r, response.body.data(), static_cast<ssize_t>(response.body.size()));
}

esp_err_t redirect(httpd_req_t* r, const std::string& location) {
  httpd_resp_set_status(r, bridge::statusLine(302));
  httpd_resp_set_hdr(r, "Location", location.c_str());
  httpd_resp_set_hdr(r, "Cache-Control", "no-store");
  return httpd_resp_send(r, nullptr, 0);
}

bool begin(bridge::Bridge& bridgeCore, PortalHooks hooks) {
  core = &bridgeCore;
  portal = hooks;
  slotDone = xSemaphoreCreateBinary();

  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = bridge::kHttpPort;
  config.core_id = 0;  // keep off core 1, where the loop times the IR carrier
  config.stack_size = 8192;
  config.max_uri_handlers = 12;
  config.lru_purge_enable = true;
  config.recv_wait_timeout = 10;
  config.send_wait_timeout = 10;
  config.uri_match_fn = httpd_uri_match_wildcard;
  if (slotDone == nullptr || httpd_start(&server, &config) != ESP_OK) {
    log_e("HTTP server failed to start");
    server = nullptr;
    return false;
  }

  // The WebSocket endpoint first: handlers match in registration order.
  httpd_uri_t ws;
  std::memset(&ws, 0, sizeof(ws));
  ws.uri = "/v1/ws";
  ws.method = HTTP_GET;
  ws.handler = handleWs;
  ws.is_websocket = true;
  httpd_register_uri_handler(server, &ws);

  // Everything else goes to the core, which answers 404/405 itself.
  static const httpd_method_t kMethods[] = {HTTP_GET, HTTP_HEAD, HTTP_POST, HTTP_PUT,
                                            HTTP_DELETE, HTTP_PATCH, HTTP_OPTIONS};
  for (httpd_method_t m : kMethods) {
    httpd_uri_t any;
    std::memset(&any, 0, sizeof(any));
    any.uri = "/*";
    any.method = m;
    any.handler = handleHttp;
    httpd_register_uri_handler(server, &any);
  }
  return true;
}

bool takePendingTransmit(bridge::SendRawJob& job) {
  std::lock_guard<std::mutex> g(slotLock);
  if (!slot.pending) return false;
  slot.pending = false;
  job = std::move(slot.job);
  return true;
}

void completeTransmit(const bridge::Response& response) {
  {
    std::lock_guard<std::mutex> g(slotLock);
    slot.response = response;
  }
  xSemaphoreGive(slotDone);
}

void dispatch(std::vector<bridge::Event> events) {
  if (server == nullptr) return;
  for (bridge::Event& e : events) {
    std::unique_ptr<WsWork> work(new WsWork());
    if (e.kind == bridge::Event::Kind::WebSocketText) {
      work->text = std::move(e.text);
    } else if (e.kind == bridge::Event::Kind::CloseWebSockets) {
      work->closeAll = true;
    } else {
      continue;
    }
    if (httpd_queue_work(server, wsWork, work.get()) == ESP_OK) work.release();
  }
}

}  // namespace http_api
