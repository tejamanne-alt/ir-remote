// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "http_api.h"

#include <Arduino.h>
#include <AsyncTCP.h>
#include <esp_timer.h>

#include <cstdlib>
#include <cstring>
#include <optional>
#include <string>

namespace http_api {

namespace {

AsyncWebServer server(bridge::kHttpPort);
AsyncWebSocket ws("/v1/ws");
bridge::Bridge* core = nullptr;
PortalHooks portal;
std::mutex lock;

// Guarded by `lock`.
struct Pending {
  bool valid = false;
  bridge::SendRawJob job;
  AsyncWebServerRequestPtr request;
} pending;
AsyncWebServerRequest* otaOwner = nullptr;  // identity only, never dereferenced

uint64_t nowMs() { return static_cast<uint64_t>(esp_timer_get_time()) / 1000; }

std::string header(AsyncWebServerRequest* r, const char* name) {
  const AsyncWebHeader* h = r->getHeader(name);
  return h ? std::string(h->value().c_str()) : std::string();
}

bool isOtaRequest(AsyncWebServerRequest* r) {
  return r->url() == "/v1/ota" && std::strcmp(r->methodToString(), "POST") == 0;
}

bridge::OtaRequest otaRequest(AsyncWebServerRequest* r) {
  bridge::OtaRequest o;
  o.authorization = header(r, "Authorization");
  o.sha256Header = header(r, "X-Firmware-SHA256");
  o.hasContentLength = r->hasHeader("Content-Length");
  o.contentLength = r->contentLength();
  return o;
}

// Per-request scratch, kept in request->_tempObject. The library releases it
// with free(), so it is a plain malloc'ed block: this header, then the body.
struct Scratch {
  uint32_t len;
  uint32_t cap;
  bool truncated;
  bool ota;
  bool otaOwner;
  int16_t refusedStatus;  // OTA refused at its first chunk
  char refusedBody[224];
  char* data() { return reinterpret_cast<char*>(this + 1); }
};

Scratch* scratch(AsyncWebServerRequest* r) { return static_cast<Scratch*>(r->_tempObject); }

Scratch* allocScratch(AsyncWebServerRequest* r, size_t cap) {
  void* mem = std::malloc(sizeof(Scratch) + cap);
  if (mem == nullptr) return nullptr;
  std::memset(mem, 0, sizeof(Scratch));
  Scratch* s = static_cast<Scratch*>(mem);
  s->cap = static_cast<uint32_t>(cap);
  r->_tempObject = s;
  return s;
}

bool growScratch(AsyncWebServerRequest* r, size_t need) {
  Scratch* s = scratch(r);
  if (need <= s->cap) return true;
  size_t cap = s->cap ? s->cap : 512;
  while (cap < need) cap *= 2;
  if (cap > bridge::kMaxBodyBytes) cap = bridge::kMaxBodyBytes;
  if (cap < need) return false;
  void* mem = std::realloc(s, sizeof(Scratch) + cap);
  if (mem == nullptr) return false;
  s = static_cast<Scratch*>(mem);
  s->cap = static_cast<uint32_t>(cap);
  r->_tempObject = s;
  return true;
}

void storeRefusal(Scratch* s, const bridge::Response& refusal) {
  s->refusedStatus = static_cast<int16_t>(refusal.status);
  if (refusal.body.size() < sizeof(s->refusedBody)) {
    std::memcpy(s->refusedBody, refusal.body.c_str(), refusal.body.size() + 1);
  } else {
    const bridge::Response generic =
        bridge::errorResponse(refusal.status, bridge::err::kBadRequest, "update refused");
    std::strncpy(s->refusedBody, generic.body.c_str(), sizeof(s->refusedBody) - 1);
  }
}

void onBody(AsyncWebServerRequest* r, uint8_t* data, size_t len, size_t index, size_t total) {
  if (index == 0 && scratch(r) == nullptr) {
    if (isOtaRequest(r)) {
      Scratch* s = allocScratch(r, 0);
      if (s == nullptr) return;
      s->ota = true;
      std::optional<bridge::Response> refusal;
      {
        std::lock_guard<std::mutex> g(lock);
        refusal = core->otaBegin(otaRequest(r), nowMs());
        if (!refusal) otaOwner = r;
      }
      if (refusal) {
        storeRefusal(s, *refusal);
      } else {
        s->otaOwner = true;
        r->onDisconnect([r]() {
          std::lock_guard<std::mutex> g(lock);
          if (otaOwner == r) {
            core->otaAbort();
            otaOwner = nullptr;
          }
        });
      }
    } else {
      // total is 0 for a chunked body: start small and grow up to the cap.
      const bool oversized = total > bridge::kMaxBodyBytes;
      const size_t cap = oversized ? 0 : (total > 0 ? total : 1024);
      Scratch* s = allocScratch(r, cap);
      if (s == nullptr) return;
      s->truncated = oversized;  // drained, never stored: the core answers 413
    }
  }
  Scratch* s = scratch(r);
  if (s == nullptr) return;
  if (s->ota) {
    if (s->otaOwner) {
      std::lock_guard<std::mutex> g(lock);
      if (otaOwner == r) core->otaWrite(data, len);  // failures surface in otaFinish()
    }
    return;
  }
  if (s->truncated || len == 0) return;
  if (s->len + len > bridge::kMaxBodyBytes || !growScratch(r, s->len + len)) {
    scratch(r)->truncated = true;
    return;
  }
  s = scratch(r);
  std::memcpy(s->data() + s->len, data, len);
  s->len += static_cast<uint32_t>(len);
}

void finishOta(AsyncWebServerRequest* r) {
  Scratch* s = scratch(r);
  bridge::Response response;
  std::vector<bridge::Event> events;
  {
    std::lock_guard<std::mutex> g(lock);
    if (s != nullptr && s->otaOwner && otaOwner == r) {
      response = core->otaFinish();
      otaOwner = nullptr;
    } else if (s != nullptr && s->refusedStatus != 0) {
      response.status = s->refusedStatus;
      response.body = s->refusedBody;
    } else {
      // No body arrived at all (Content-Length: 0): let the core explain.
      const std::optional<bridge::Response> refusal = core->otaBegin(otaRequest(r), nowMs());
      response = refusal ? *refusal : core->otaFinish();
    }
    events = core->takeEvents();
  }
  send(r, response);
  dispatch(std::move(events));
}

void onRequest(AsyncWebServerRequest* r) {
  if (portal.claims && portal.claims(r)) {
    portal.handle(r);
    return;
  }
  if (isOtaRequest(r)) {
    finishOta(r);
    return;
  }
  Scratch* s = scratch(r);
  bridge::Request req;
  req.method = bridge::parseMethod(r->methodToString());
  req.path = r->url().c_str();
  req.authorization = header(r, "Authorization");
  req.contentLength = r->contentLength();
  req.webSocketUpgrade = false;  // real upgrades on /v1/ws are taken by `ws`
  if (s != nullptr) {
    req.body.assign(s->data(), s->len);
    req.bodyTruncated = s->truncated;
  }

  bridge::Outcome out;
  std::vector<bridge::Event> events;
  {
    std::lock_guard<std::mutex> g(lock);
    if (s == nullptr && req.contentLength > 0) {
      // A form-encoded body is consumed by the library and never reaches us.
      const bridge::Preflight pf =
          core->preflight(req.method, req.path, req.authorization, req.contentLength);
      out.response = pf.ok ? bridge::errorResponse(400, bridge::err::kBadJson,
                                                   "send the body as Content-Type: application/json")
                           : pf.error;
    } else {
      out = core->handle(req, nowMs());
      if (out.action == bridge::Action::Transmit) {
        pending.valid = true;
        pending.job = std::move(out.job);
        pending.request = r->pause();  // answered from the loop task after transmitting
      }
    }
    events = core->takeEvents();
  }
  if (out.action == bridge::Action::Respond) {
    send(r, out.response);
  } else if (out.action == bridge::Action::AcceptWebSocket) {
    send(r, bridge::errorResponse(426, bridge::err::kUpgradeRequired, "use a WebSocket client"));
  }
  dispatch(std::move(events));
}

}  // namespace

std::mutex& coreLock() { return lock; }

void send(AsyncWebServerRequest* request, const bridge::Response& response) {
  // The const char* overload copies the body; the uint8_t* one would not.
  AsyncWebServerResponse* res =
      request->beginResponse(response.status, response.contentType, response.body.c_str());
  if (!response.allow.empty()) res->addHeader("Allow", response.allow.c_str());
  res->addHeader("Cache-Control", "no-store");
  request->send(res);
}

void begin(bridge::Bridge& bridgeCore, PortalHooks hooks) {
  core = &bridgeCore;
  portal = std::move(hooks);

  // The upgrade itself needs a valid token (contract: auth header on the upgrade).
  ws.addMiddleware([](AsyncWebServerRequest* r, ArMiddlewareNext next) {
    bridge::Preflight pf;
    {
      std::lock_guard<std::mutex> g(lock);
      pf = core->preflight(bridge::Method::Get, "/v1/ws", header(r, "Authorization"), 0);
    }
    if (!pf.ok) {
      send(r, pf.error);
      return;
    }
    next();
  });
  ws.onEvent([](AsyncWebSocket*, AsyncWebSocketClient* client, AwsEventType type, void*, uint8_t*,
                size_t) {
    (void)client;  // only used by log_i, which may be compiled out
    if (type == WS_EVT_CONNECT) {
      log_i("ws client %u connected", static_cast<unsigned>(client->id()));
    } else if (type == WS_EVT_DISCONNECT) {
      log_i("ws client %u disconnected", static_cast<unsigned>(client->id()));
    }
    // Messages from clients are ignored: the stream is server-to-client only.
  });
  server.addHandler(&ws);
  server.onRequestBody(onBody);
  server.onNotFound(onRequest);
  server.begin();
}

bool takePendingTransmit(bridge::SendRawJob& job, AsyncWebServerRequestPtr& request) {
  std::lock_guard<std::mutex> g(lock);
  if (!pending.valid) return false;
  job = std::move(pending.job);
  request = pending.request;
  pending = Pending();
  return true;
}

void answerPaused(AsyncWebServerRequestPtr request, const bridge::Response& response) {
  // The client may have gone away during the transmission.
  if (auto r = request.lock()) send(r.get(), response);
}

void dispatch(std::vector<bridge::Event> events) {
  for (const bridge::Event& e : events) {
    if (e.kind == bridge::Event::Kind::WebSocketText) {
      ws.textAll(e.text.c_str(), e.text.size());
    } else if (e.kind == bridge::Event::Kind::CloseWebSockets) {
      ws.closeAll(1008, "pairings cleared");
    }
  }
}

void housekeeping() { ws.cleanupClients(); }

}  // namespace http_api
