// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// HTTP and WebSocket on ESP-IDF's esp_http_server (Apache-2.0), which is part
// of the Arduino-ESP32 core: no extra libraries, and nothing LGPL-3.0.
//
// Notes on esp_http_server behaviour this file relies on (ESP-IDF 5.5):
// - Handlers run one at a time on the server task. A send is handed to the
//   loop task as an async request (httpd_req_async_handler_begin), so the
//   server keeps answering while the LED transmits and the core's 409 busy
//   reaches a second sender. Each job carries a sequence number: a reply can
//   only complete the request it belongs to.
// - Request bodies need a Content-Length (no chunked uploads); the app sends
//   one (docs/BRIDGE_API.md). Body reads have an absolute deadline.
// - WebSocket authentication is in-band (ADR-026): depending on the core
//   version the handler may not run at the handshake at all, so a session is
//   unauthorized until its first text frame carries a paired token. Only
//   authorized sessions receive broadcasts; others are closed with 1008 after
//   kWsAuthTimeoutMs. Where the handler does run at the handshake, a valid
//   Authorization header authorizes at once and a bad one closes with 1008.
#include "http_api.h"

#include <Arduino.h>
#include <esp_timer.h>
#include <lwip/sockets.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <memory>
#include <new>
#include <optional>
#include <string>

namespace http_api {

namespace {

constexpr size_t kMaxClients = 16;
constexpr size_t kMaxWsInboundFrame = 512;
constexpr uint64_t kTakeTimeoutMs = 3000;      // loop must pick a job up within this
constexpr uint64_t kBodyDeadlineMs = 15000;    // whole body (at most 16 KiB)
constexpr uint64_t kOtaDeadlineMs = 180000;    // whole image (under 2 MB)
constexpr size_t kMaxRefusalDrainBytes = 64 * 1024;
constexpr uint64_t kRefusalDrainMs = 2000;
constexpr int kWsSendTimeoutS = 1;             // a stalled WebSocket peer is dropped

httpd_handle_t server = nullptr;
bridge::Bridge* core = nullptr;
PortalHooks portal;
std::mutex lock;
esp_timer_handle_t sweepTimer = nullptr;
std::atomic<bool> closeAllPending{false};

// The one transmission in flight (the core refuses a second with 409 busy).
struct TxJob {
  uint32_t seq = 0;
  httpd_req_t* request = nullptr;  // async copy, completed exactly once
  bridge::SendRawJob job;
  uint64_t postedMs = 0;
  bool taken = false;  // the loop task has it
};
std::mutex slotLock;
std::optional<TxJob> slot;
uint32_t nextSeq = 1;

uint64_t nowMs() { return static_cast<uint64_t>(esp_timer_get_time()) / 1000; }

// Per-session WebSocket state, owned by esp_http_server's session context
// (freed when the session closes, so a reused fd never inherits it).
struct WsSession {
  bool authorized = false;
  uint64_t firstSeenMs = 0;
};

void freeWsSession(void* p) { delete static_cast<WsSession*>(p); }

WsSession* wsSession(httpd_handle_t hd, int fd) {
  auto* s = static_cast<WsSession*>(httpd_sess_get_ctx(hd, fd));
  if (s != nullptr) return s;
  s = new (std::nothrow) WsSession();
  if (s == nullptr) return nullptr;
  s->firstSeenMs = nowMs();
  httpd_sess_set_ctx(hd, fd, s, freeWsSession);
  return s;
}

void markAuthorized(httpd_handle_t hd, int fd, WsSession* s) {
  s->authorized = true;
  // Broadcasts run on the server task: never let one peer stall it for the
  // default 10 s send timeout.
  struct timeval tv;
  tv.tv_sec = kWsSendTimeoutS;
  tv.tv_usec = 0;
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  static const char kReady[] = "{\"type\":\"ready\"}";
  httpd_ws_frame_t frame;
  std::memset(&frame, 0, sizeof(frame));
  frame.final = true;
  frame.type = HTTPD_WS_TYPE_TEXT;
  frame.payload = reinterpret_cast<uint8_t*>(const_cast<char*>(kReady));
  frame.len = sizeof(kReady) - 1;
  httpd_ws_send_frame_async(hd, fd, &frame);
}

struct WsWork {
  std::string text;
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
  WsSession* s = static_cast<WsSession*>(httpd_sess_get_ctx(hd, fd));
  if (s != nullptr) s->authorized = false;  // no broadcast reaches it any more
  httpd_ws_send_frame_async(hd, fd, &frame);
  httpd_sess_trigger_close(hd, fd);
}

size_t webSockets(int* fds) {
  size_t count = kMaxClients;
  if (server == nullptr || httpd_get_client_list(server, &count, fds) != ESP_OK) return 0;
  size_t n = 0;
  for (size_t i = 0; i < count; ++i) {
    if (httpd_ws_get_fd_info(server, fds[i]) == HTTPD_WS_CLIENT_WEBSOCKET) fds[n++] = fds[i];
  }
  return n;
}

// Runs on the server task (queued with httpd_queue_work).
void wsWork(void* arg) {
  std::unique_ptr<WsWork> work(static_cast<WsWork*>(arg));
  int fds[kMaxClients];
  const size_t n = webSockets(fds);
  for (size_t i = 0; i < n; ++i) {
    auto* s = static_cast<WsSession*>(httpd_sess_get_ctx(server, fds[i]));
    if (s == nullptr || !s->authorized) continue;  // fail closed
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

void finishJob(TxJob& job, const bridge::Response& response) {
  send(job.request, response);
  httpd_req_async_handler_complete(job.request);
  job.request = nullptr;
}

// Runs on the server task once a second (queued by an esp_timer).
void sweepWork(void*) {
  const uint64_t now = nowMs();
  // 1. A job the loop never took (the loop stalled): answer it and free the
  //    busy state. A job already taken is completed by the loop.
  std::optional<TxJob> stale;
  {
    std::lock_guard<std::mutex> g(slotLock);
    if (slot && !slot->taken && now - slot->postedMs > kTakeTimeoutMs) {
      stale = std::move(slot);
      slot.reset();
    }
  }
  if (stale) {
    {
      std::lock_guard<std::mutex> g(lock);
      core->finishTransmit(0);  // clears the busy state; its reply is not used
    }
    log_e("transmission %u was never started", static_cast<unsigned>(stale->seq));
    finishJob(*stale, bridge::errorResponse(500, bridge::err::kTransmitFailed, "the IR task did not run"));
  }
  // 2. WebSocket sessions: close everything after the tokens were cleared,
  //    and drop sessions that did not authenticate in time.
  const bool closeAll = closeAllPending.exchange(false);
  int fds[kMaxClients];
  const size_t n = webSockets(fds);
  for (size_t i = 0; i < n; ++i) {
    if (closeAll) {
      closeWebSocket(server, fds[i]);
      continue;
    }
    WsSession* s = wsSession(server, fds[i]);
    if (s != nullptr && !s->authorized && now - s->firstSeenMs > bridge::kWsAuthTimeoutMs) {
      closeWebSocket(server, fds[i]);
    }
  }
}

void onSweepTimer(void*) {
  if (server != nullptr) httpd_queue_work(server, sweepWork, nullptr);  // retried next second
}

// Refuses a request whose body has not been read. The body is drained (up to
// a bound) so the client sees the response: closing with unread data makes
// lwIP send a RST, which can discard the response before it is delivered.
esp_err_t refuse(httpd_req_t* r, const bridge::Response& response) {
  if (r->content_len > kMaxRefusalDrainBytes) httpd_resp_set_hdr(r, "Connection", "close");
  send(r, response);
  if (r->content_len == 0) return ESP_OK;
  size_t remaining = std::min<size_t>(r->content_len, kMaxRefusalDrainBytes);
  const uint64_t deadline = nowMs() + kRefusalDrainMs;
  char buf[512];
  while (remaining > 0 && nowMs() < deadline) {
    const int n = httpd_req_recv(r, buf, std::min(sizeof(buf), remaining));
    if (n == HTTPD_SOCK_ERR_TIMEOUT) continue;
    if (n <= 0) break;
    remaining -= static_cast<size_t>(n);
  }
  // Keep the connection only when the whole body was read.
  return (remaining == 0 && r->content_len <= kMaxRefusalDrainBytes) ? ESP_OK : ESP_FAIL;
}

// The core accepted a send (and is now busy): hand it to the loop task.
esp_err_t startTransmit(httpd_req_t* r, bridge::SendRawJob job) {
  bool occupied = false;
  {
    std::lock_guard<std::mutex> g(slotLock);
    // The previous job is finished in the core but its reply is still being
    // sent: refuse this one as busy, and clear the busy state it just set.
    occupied = slot.has_value();
  }
  httpd_req_t* copy = nullptr;
  if (occupied || httpd_req_async_handler_begin(r, &copy) != ESP_OK || copy == nullptr) {
    {
      std::lock_guard<std::mutex> g(lock);
      core->finishTransmit(0);
    }
    return send(r, occupied ? bridge::errorResponse(409, bridge::err::kBusy,
                                                    "a transmission is in progress; retry after it")
                            : bridge::errorResponse(500, bridge::err::kTransmitFailed, "out of memory"));
  }
  // Only this task fills the slot, so it is still empty.
  std::lock_guard<std::mutex> g(slotLock);
  TxJob t;
  t.seq = nextSeq++;
  if (nextSeq == 0) nextSeq = 1;
  t.request = copy;
  t.job = std::move(job);
  t.postedMs = nowMs();
  slot = std::move(t);
  return ESP_OK;  // the loop answers through the async copy
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
  if (refusal) return refuse(r, *refusal);
  std::unique_ptr<uint8_t[]> buf(new uint8_t[1024]);
  size_t remaining = r->content_len;
  int timeouts = 0;
  const uint64_t deadline = nowMs() + kOtaDeadlineMs;
  while (remaining > 0) {
    const int n = httpd_req_recv(r, reinterpret_cast<char*>(buf.get()), std::min<size_t>(1024, remaining));
    if (n == HTTPD_SOCK_ERR_TIMEOUT && ++timeouts < 3 && nowMs() < deadline) continue;
    if (n <= 0 || nowMs() >= deadline) {
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
  if (!pf.ok) return refuse(r, pf.error);
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
      return startTransmit(r, std::move(out.job));
  }
  return send(r, bridge::errorResponse(500, bridge::err::kTransmitFailed, "unexpected outcome"));
}

esp_err_t handleWs(httpd_req_t* r) {
  const int fd = httpd_req_to_sockfd(r);
  if (httpd_ws_get_fd_info(r->handle, fd) != HTTPD_WS_CLIENT_WEBSOCKET) {
    return handleHttp(r);  // a plain GET without an upgrade: 426 from the core
  }
  WsSession* session = wsSession(r->handle, fd);
  if (session == nullptr) return ESP_FAIL;  // out of memory: drop the client
  if (r->method == HTTP_GET) {
    // Older cores call the handler right after the handshake, with the
    // upgrade request's headers still available: check them now. Newer
    // cores skip this call, and the auth frame below is the only check.
    bridge::Preflight pf;
    {
      std::lock_guard<std::mutex> g(lock);
      pf = core->preflight(bridge::Method::Get, "/v1/ws", header(r, "Authorization"), 0);
    }
    if (pf.ok) {
      markAuthorized(r->handle, fd, session);
    } else if (!header(r, "Authorization").empty()) {
      closeWebSocket(r->handle, fd);  // a wrong token: refuse now
    }
    return ESP_OK;  // no header: wait for the auth frame
  }
  // A frame from the client. Only the auth frame means anything; drop
  // clients that send oversized frames.
  httpd_ws_frame_t frame;
  std::memset(&frame, 0, sizeof(frame));
  if (httpd_ws_recv_frame(r, &frame, 0) != ESP_OK) return ESP_FAIL;
  if (frame.len == 0) return ESP_OK;
  if (frame.len > kMaxWsInboundFrame) return ESP_FAIL;
  uint8_t buf[kMaxWsInboundFrame];
  frame.payload = buf;
  if (httpd_ws_recv_frame(r, &frame, frame.len) != ESP_OK) return ESP_FAIL;
  if (session->authorized || frame.type != HTTPD_WS_TYPE_TEXT) return ESP_OK;
  bool ok = false;
  {
    std::lock_guard<std::mutex> g(lock);
    ok = core->authorizeWebSocketFrame(std::string(reinterpret_cast<char*>(buf), frame.len));
  }
  if (ok) {
    markAuthorized(r->handle, fd, session);
  } else {
    closeWebSocket(r->handle, fd);
  }
  return ESP_OK;
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
  // An absolute deadline: a peer trickling one byte at a time cannot hold
  // the only server task for long.
  const uint64_t deadline = nowMs() + kBodyDeadlineMs;
  while (remaining > 0) {
    if (nowMs() >= deadline) return false;
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

  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = bridge::kHttpPort;
  config.core_id = 0;  // keep off core 1, where the loop times the IR carrier
  config.stack_size = 8192;
  config.max_uri_handlers = 12;
  config.lru_purge_enable = true;
  config.recv_wait_timeout = 10;
  config.send_wait_timeout = 10;
  config.uri_match_fn = httpd_uri_match_wildcard;
  if (httpd_start(&server, &config) != ESP_OK) {
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

  esp_timer_create_args_t timer;
  std::memset(&timer, 0, sizeof(timer));
  timer.callback = onSweepTimer;
  timer.name = "httpd_sweep";
  if (esp_timer_create(&timer, &sweepTimer) != ESP_OK ||
      esp_timer_start_periodic(sweepTimer, 1000000) != ESP_OK) {
    log_e("HTTP sweep timer failed to start");
    return false;
  }
  return true;
}

bool takePendingTransmit(bridge::SendRawJob& job, uint32_t& seq) {
  std::lock_guard<std::mutex> g(slotLock);
  if (!slot || slot->taken) return false;
  slot->taken = true;
  seq = slot->seq;
  job = std::move(slot->job);
  return true;
}

void completeTransmit(uint32_t seq, const bridge::Response& response) {
  std::optional<TxJob> done;
  {
    std::lock_guard<std::mutex> g(slotLock);
    if (!slot || slot->seq != seq) return;  // not ours (cannot happen once taken)
    done = std::move(slot);
    slot.reset();
  }
  // Sending on an async request from another task is what the async API is
  // for; the server task keeps serving meanwhile.
  finishJob(*done, response);
}

void dispatch(std::vector<bridge::Event> events) {
  if (server == nullptr) return;
  for (bridge::Event& e : events) {
    if (e.kind == bridge::Event::Kind::CloseWebSockets) {
      // Done by the next sweep, which retries until the server task runs
      // it: revoked sessions must not stay open because a queue was full.
      closeAllPending = true;
      continue;
    }
    if (e.kind != bridge::Event::Kind::WebSocketText) continue;
    std::unique_ptr<WsWork> work(new (std::nothrow) WsWork());
    if (work == nullptr) continue;
    work->text = std::move(e.text);
    if (httpd_queue_work(server, wsWork, work.get()) == ESP_OK) work.release();
  }
}

}  // namespace http_api
