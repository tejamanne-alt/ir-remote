// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_core.h"

#include <utility>

#include "bridge_json.h"

namespace bridge {

namespace {

constexpr uint8_t kGet = 1;
constexpr uint8_t kPost = 2;
constexpr uint8_t kDelete = 4;

struct RouteSpec {
  const char* path;
  Route route;
  uint8_t methods;
  const char* allow;
  bool authRequired;
  bool bodyCapped;
};

const RouteSpec kRoutes[] = {
    {"/v1/info", Route::Info, kGet, "GET", false, true},
    {"/v1/health", Route::Health, kGet, "GET", true, true},
    {"/v1/pair", Route::Pair, kPost, "POST", false, true},
    {"/v1/send/raw", Route::SendRaw, kPost, "POST", true, true},
    {"/v1/send/ac", Route::SendAc, kPost, "POST", true, true},
    {"/v1/learn", Route::Learn, kPost | kDelete, "POST, DELETE", true, true},
    {"/v1/ws", Route::WebSocket, kGet, "GET", true, true},
    // The OTA body is a firmware image, not JSON; the 16 KiB cap cannot apply.
    {"/v1/ota", Route::Ota, kPost, "POST", true, false},
};

uint8_t methodBit(Method m) {
  switch (m) {
    case Method::Get: return kGet;
    case Method::Post: return kPost;
    case Method::Delete: return kDelete;
    default: return 0;
  }
}

Outcome respond(Response r) {
  Outcome o;
  o.action = Action::Respond;
  o.response = std::move(r);
  return o;
}

Response fromError(const ApiError& e) { return errorResponse(e.status, e.code, e.detail); }

Response jsonResponse(int status, std::string body) {
  Response r;
  r.status = status;
  r.body = std::move(body);
  return r;
}

constexpr uint64_t kClearedFlashMs = 2000;

}  // namespace

Bridge::Bridge(Identity identity, TokenStorage& storage, Platform& platform, OtaTarget* ota,
               BridgeOptions options)
    : identity_(std::move(identity)),
      tokens_(storage),
      platform_(platform),
      otaTarget_(ota),
      options_(options) {}

bool Bridge::begin() { return tokens_.load(); }

bool Bridge::authorized(const std::string& authorization) const {
  std::string token;
  if (!parseBearer(authorization, token)) return false;
  return tokens_.contains(token);
}

bool Bridge::authorizeWebSocketFrame(const std::string& frame) const {
  if (frame.size() > kMaxWsAuthFrameBytes) return false;
  json::Reader r(frame);
  if (!r.enterObject()) return false;
  std::string key;
  std::string type;
  std::string token;
  bool truncated = false;
  while (r.nextMember(key)) {
    if (key == "type") {
      if (r.peekType() != json::Type::String || !r.readString(&type, 16, &truncated)) return false;
    } else if (key == "token") {
      if (r.peekType() != json::Type::String ||
          !r.readString(&token, kTokenHexLength + 1, &truncated)) {
        return false;
      }
    } else if (!r.skipValue()) {
      return false;
    }
  }
  if (!r.ok() || !r.expectEnd() || truncated || type != "auth") return false;
  return tokens_.contains(token);
}

Preflight Bridge::preflight(Method method, const std::string& path,
                            const std::string& authorization, uint64_t bodyBytes) const {
  Preflight pf;
  const RouteSpec* spec = nullptr;
  for (const RouteSpec& r : kRoutes) {
    if (path == r.path) {
      spec = &r;
      break;
    }
  }
  if (spec == nullptr) {
    pf.error = errorResponse(404, err::kNotFound,
                             std::string("no route ") + methodName(method) + " " + path);
    return pf;
  }
  pf.route = spec->route;
  if ((methodBit(method) & spec->methods) == 0) {
    pf.error = errorResponse(405, err::kMethodNotAllowed,
                             std::string(methodName(method)) + " is not allowed on " + path +
                                 "; use " + spec->allow);
    pf.error.allow = spec->allow;
    return pf;
  }
  if (spec->bodyCapped && bodyBytes > kMaxBodyBytes) {
    pf.error = errorResponse(413, err::kTooLarge,
                             "request body exceeds " + std::to_string(kMaxBodyBytes) + " bytes");
    return pf;
  }
  if (spec->authRequired && !authorized(authorization)) {
    pf.error = errorResponse(401, err::kUnauthorized,
                             authorization.empty()
                                 ? "Authorization: Bearer <token> is required; pair first"
                                 : "unknown or malformed token; pair again");
    return pf;
  }
  pf.ok = true;
  return pf;
}

Outcome Bridge::handle(const Request& request, uint64_t nowMs) {
  tick(nowMs);
  uint64_t bodyBytes = request.contentLength;
  if (request.body.size() > bodyBytes) bodyBytes = request.body.size();
  if (request.bodyTruncated && bodyBytes <= kMaxBodyBytes) bodyBytes = kMaxBodyBytes + 1;

  const Preflight pf = preflight(request.method, request.path, request.authorization, bodyBytes);
  if (!pf.ok) return respond(pf.error);

  switch (pf.route) {
    case Route::Info: return respond(info(nowMs));
    case Route::Health: return respond(health(nowMs));
    case Route::Pair: return respond(pair(request.body, nowMs));
    case Route::SendRaw: return sendRaw(request.body);
    case Route::SendAc: return respond(sendAc(request.body));
    case Route::Learn:
      return respond(request.method == Method::Post ? startLearn(request.body, nowMs)
                                                    : stopLearn());
    case Route::WebSocket: {
      if (!request.webSocketUpgrade) {
        return respond(errorResponse(426, err::kUpgradeRequired,
                                     "GET /v1/ws needs a WebSocket upgrade"));
      }
      Outcome o;
      o.action = Action::AcceptWebSocket;
      o.response.status = 101;
      return o;
    }
    case Route::Ota:
      return respond(errorResponse(400, err::kBadRequest,
                                   "the firmware image must be streamed (internal routing error)"));
    case Route::Unknown: break;
  }
  return respond(errorResponse(404, err::kNotFound, "no route"));
}

Response Bridge::info(uint64_t nowMs) const {
  std::string body;
  json::Writer w(body);
  w.beginObject()
      .key("api").num(kApiVersion)
      .key("fw").str(identity_.fw)
      .key("id").str(identity_.id)
      .key("name").str(identity_.name)
      .key("caps").beginObject()
          .key("carrierMinHz").unum(kCarrierMinHz)
          .key("carrierMaxHz").unum(kCarrierMaxHz)
          .key("maxPatternUs").unum(kMaxPatternUs)
          .key("maxDurations").unum(kMaxDurations)
          .key("canLearn").boolean(options_.canLearn)
          .key("ac").beginArray().endArray()
      .endObject()
      .key("pairingWindowOpen").boolean(window_.isOpen(nowMs))
      .endObject();
  return jsonResponse(200, std::move(body));
}

Response Bridge::health(uint64_t nowMs) const {
  std::string body;
  json::Writer w(body);
  w.beginObject()
      .key("ok").boolean(true)
      .key("uptimeS").unum(nowMs / 1000)
      .key("rssi").num(platform_.rssiDbm())
      .key("freeHeap").unum(platform_.freeHeapBytes())
      .key("learning").boolean(learning())
      .endObject();
  return jsonResponse(200, std::move(body));
}

Response Bridge::pair(const std::string& body, uint64_t nowMs) {
  std::string client;
  const ApiError e = parsePair(body, client);
  if (!e.ok()) return fromError(e);
  if (!window_.isOpen(nowMs)) {
    return errorResponse(403, err::kPairingWindowClosed,
                         "press the BOOT button on the bridge, then pair within 60 seconds");
  }
  if (tokens_.full()) {
    return errorResponse(507, err::kPairingFull,
                         "8 clients are already paired; hold BOOT for 5 seconds to clear them");
  }
  std::string token;
  bool unique = false;
  for (int attempt = 0; attempt < 4 && !unique; ++attempt) {
    uint8_t bytes[kTokenBytes];
    platform_.randomBytes(bytes, sizeof bytes);
    token = tokenFromBytes(bytes);
    unique = !tokens_.contains(token);
  }
  if (!unique) return errorResponse(500, err::kStorageError, "random source failure");
  switch (tokens_.add(PairedClient{token, client})) {
    case TokenStore::AddResult::Full:
      return errorResponse(507, err::kPairingFull,
                           "8 clients are already paired; hold BOOT for 5 seconds to clear them");
    case TokenStore::AddResult::StorageError:
      return errorResponse(500, err::kStorageError, "could not save the token; try again");
    case TokenStore::AddResult::Added: break;
  }
  window_.close();
  std::string out;
  json::Writer w(out);
  w.beginObject().key("token").str(token).endObject();
  return jsonResponse(200, std::move(out));
}

Outcome Bridge::sendRaw(const std::string& body) {
  SendRawJob job;
  const ApiError e = parseSendRaw(body, job);
  if (!e.ok()) return respond(fromError(e));
  if (transmitting_) {
    return respond(errorResponse(409, err::kBusy, "a transmission is in progress; retry after it"));
  }
  if (ota_.active()) {
    return respond(errorResponse(409, err::kBusy, "a firmware update is in progress"));
  }
  transmitting_ = true;
  Outcome o;
  o.action = Action::Transmit;
  o.job = std::move(job);
  return o;
}

Response Bridge::finishTransmit(uint64_t elapsedUs) {
  transmitting_ = false;
  std::string out;
  json::Writer w(out);
  w.beginObject().key("sent").boolean(true).key("elapsedUs").unum(elapsedUs).endObject();
  return jsonResponse(200, std::move(out));
}

Response Bridge::sendAc(const std::string& body) {
  const ApiError e = parseSendAc(body);
  if (!e.ok()) return fromError(e);
  return errorResponse(501, err::kNotImplemented,
                       "this firmware was built without AC encoders (caps.ac is empty)");
}

Response Bridge::startLearn(const std::string& body, uint64_t nowMs) {
  if (!options_.canLearn) {
    return errorResponse(501, err::kNotImplemented, "this bridge has no IR receiver");
  }
  uint32_t timeoutMs = 0;
  const ApiError e = parseLearn(body, timeoutMs);
  if (!e.ok()) return fromError(e);
  // A new request replaces any running session.
  learnMode_ = (timeoutMs == 0) ? LearnMode::Capture : LearnMode::Learn;
  learnDeadlineMs_ = nowMs + timeoutMs;
  return jsonResponse(202, "{\"learning\":true}");
}

Response Bridge::stopLearn() {
  if (learnMode_ != LearnMode::Idle) {
    learnMode_ = LearnMode::Idle;
    pushEvent(Event{Event::Kind::WebSocketText, buildLearnStoppedMessage()});
  }
  return jsonResponse(200, "{\"learning\":false}");
}

std::optional<Response> Bridge::otaBegin(const OtaRequest& request, uint64_t nowMs) {
  tick(nowMs);
  const Preflight pf = preflight(Method::Post, "/v1/ota", request.authorization, 0);
  if (!pf.ok) return pf.error;
  if (otaTarget_ == nullptr) {
    return errorResponse(501, err::kNotImplemented, "this build cannot update over the network");
  }
  if (rebootRequested_) {
    // The new image is already active; a second update would overwrite it.
    return errorResponse(409, err::kBusy, "restarting to apply an update");
  }
  if (transmitting_) {
    return errorResponse(409, err::kBusy, "a transmission is in progress; retry after it");
  }
  if (ota_.active()) return errorResponse(409, err::kBusy, "an update is already in progress");
  const ApiError e =
      ota_.begin(*otaTarget_, request.sha256Header, request.hasContentLength, request.contentLength);
  if (!e.ok()) return fromError(e);
  return std::nullopt;
}

bool Bridge::otaWrite(const uint8_t* data, size_t len) { return ota_.write(data, len); }

Response Bridge::otaFinish() {
  Response r = ota_.finish();
  if (r.status == 200) rebootRequested_ = true;
  return r;
}

void Bridge::otaAbort() { ota_.abort(); }

bool Bridge::onButton(ButtonEvent event, uint64_t nowMs) {
  tick(nowMs);
  switch (event) {
    case ButtonEvent::None: return true;
    case ButtonEvent::ShortPress:
      window_.open(nowMs);
      return true;
    case ButtonEvent::LongPress:
    case ButtonEvent::FactoryResetPress: {
      const bool persisted = tokens_.clear();
      persistPending_ = !persisted;
      lastPersistTryMs_ = nowMs;
      window_.close();
      clearedFlash_ = true;
      clearedAtMs_ = nowMs;
      pushEvent(Event{Event::Kind::CloseWebSockets, std::string()});
      return persisted;
    }
  }
  return true;
}

void Bridge::onCapture(const Capture& capture) {
  tick(capture.atMs);
  if (learnMode_ == LearnMode::Idle) return;
  std::string message = buildCaptureMessage(capture);
  if (message.empty()) return;
  pushEvent(Event{Event::Kind::WebSocketText, std::move(message)});
  if (learnMode_ == LearnMode::Learn) learnMode_ = LearnMode::Idle;
}

void Bridge::tick(uint64_t nowMs) {
  window_.tick(nowMs);
  if (learnMode_ == LearnMode::Learn && nowMs >= learnDeadlineMs_) {
    learnMode_ = LearnMode::Idle;
    pushEvent(Event{Event::Kind::WebSocketText, buildLearnTimeoutMessage()});
  }
  if (clearedFlash_ && elapsedMs(nowMs, clearedAtMs_) >= kClearedFlashMs) clearedFlash_ = false;
  if (persistPending_ && elapsedMs(nowMs, lastPersistTryMs_) >= kStorageRetryMs) {
    lastPersistTryMs_ = nowMs;
    persistPending_ = !tokens_.persist();
  }
}

void Bridge::pushEvent(Event event) {
  if (options_.maxQueuedEvents == 0) return;
  // Bounded: if the glue falls behind, the oldest messages are dropped.
  while (events_.size() >= options_.maxQueuedEvents) events_.erase(events_.begin());
  events_.push_back(std::move(event));
}

std::vector<Event> Bridge::takeEvents() {
  std::vector<Event> out;
  out.swap(events_);
  return out;
}

LedPattern Bridge::ledPattern(uint64_t nowMs) const {
  if (clearedFlash_ && elapsedMs(nowMs, clearedAtMs_) < kClearedFlashMs) {
    return LedPattern::ClearedFlash;
  }
  if (persistPending_) return LedPattern::StorageError;
  if (window_.isOpen(nowMs)) return LedPattern::PairingBlink;
  if (learning()) return LedPattern::Solid;
  return LedPattern::Off;
}

}  // namespace bridge
