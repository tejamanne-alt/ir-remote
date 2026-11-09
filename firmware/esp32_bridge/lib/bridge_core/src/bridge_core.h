// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// bridge_core: all request handling of the ESP32 IR bridge, API v1
// (docs/BRIDGE_API.md), in portable C++17. No Arduino or ESP-IDF headers.
//
// The device glue (src/) owns the network stack, the IR hardware, NVS and the
// clock. It feeds requests, button events, captures and the time into Bridge
// and carries out what Bridge returns. Bridge is not thread-safe: the glue
// serialises every call (one mutex).
#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "bridge_auth.h"
#include "bridge_config.h"
#include "bridge_controls.h"
#include "bridge_http.h"
#include "bridge_json.h"
#include "bridge_ota.h"
#include "bridge_provisioning.h"
#include "bridge_sha256.h"
#include "bridge_signal.h"

namespace bridge {

// Device services the core needs but cannot implement portably.
class Platform {
 public:
  virtual ~Platform() = default;
  // Cryptographically secure random bytes (esp_fill_random on the device).
  virtual void randomBytes(uint8_t* out, size_t len) = 0;
  virtual int32_t rssiDbm() = 0;
  virtual uint32_t freeHeapBytes() = 0;
};

enum class Route : uint8_t { Info, Health, Pair, SendRaw, SendAc, Learn, WebSocket, Ota, Unknown };

// Result of the header-only checks (route, method, body size, token).
struct Preflight {
  bool ok = false;
  Route route = Route::Unknown;
  Response error;  // when !ok
};

enum class Action : uint8_t {
  Respond,          // send `response` now
  Transmit,         // send `job` on the IR LED, then answer with finishTransmit()
  AcceptWebSocket,  // complete the WebSocket upgrade
};

struct Outcome {
  Action action = Action::Respond;
  Response response;
  SendRawJob job;
};

enum class LearnMode : uint8_t { Idle, Learn, Capture };

// Things the glue must do after a call returns (drained with takeEvents()).
struct Event {
  enum class Kind : uint8_t {
    WebSocketText,    // broadcast `text` to every WebSocket client
    CloseWebSockets,  // tokens were cleared: drop authenticated sessions
  };
  Kind kind = Kind::WebSocketText;
  std::string text;
};

struct OtaRequest {
  std::string authorization;
  std::string sha256Header;  // X-Firmware-SHA256
  bool hasContentLength = false;
  uint64_t contentLength = 0;
};

struct BridgeOptions {
  bool canLearn = true;
  size_t maxQueuedEvents = 16;
};

class Bridge {
 public:
  Bridge(Identity identity, TokenStorage& storage, Platform& platform, OtaTarget* ota = nullptr,
         BridgeOptions options = BridgeOptions());

  // Loads the paired tokens. Returns false if storage could not be read; the
  // bridge then starts with no paired clients.
  bool begin();

  // --- HTTP -------------------------------------------------------------
  // Checks in order: 404 unknown path, 405 wrong method, 413 body over
  // kMaxBodyBytes (except /v1/ota), 401 missing or unknown token.
  Preflight preflight(Method method, const std::string& path, const std::string& authorization,
                      uint64_t bodyBytes) const;
  // Handles one complete request (everything except the OTA body stream).
  Outcome handle(const Request& request, uint64_t nowMs);
  // Call after carrying out a Transmit outcome; clears the busy state.
  Response finishTransmit(uint64_t elapsedUs);

  // --- OTA (POST /v1/ota, streamed) --------------------------------------
  // nullopt: accepted, stream the body with otaWrite() and end with
  // otaFinish(). Otherwise the response to send (and ignore the body).
  std::optional<Response> otaBegin(const OtaRequest& request, uint64_t nowMs);
  bool otaWrite(const uint8_t* data, size_t len);
  Response otaFinish();
  void otaAbort();
  bool otaActive() const { return ota_.active(); }
  // True after a successful update; the glue restarts once the response is out.
  bool rebootRequested() const { return rebootRequested_; }

  // --- Device events -----------------------------------------------------
  // Returns false when clearing tokens could not be persisted.
  bool onButton(ButtonEvent event, uint64_t nowMs);
  void onCapture(const Capture& capture);
  void tick(uint64_t nowMs);
  std::vector<Event> takeEvents();

  // --- State -------------------------------------------------------------
  bool pairingWindowOpen(uint64_t nowMs) const { return window_.isOpen(nowMs); }
  LearnMode learnMode() const { return learnMode_; }
  bool learning() const { return learnMode_ != LearnMode::Idle; }
  bool transmitting() const { return transmitting_; }
  size_t pairedClients() const { return tokens_.size(); }
  LedPattern ledPattern(uint64_t nowMs) const;
  const Identity& identity() const { return identity_; }

 private:
  bool authorized(const std::string& authorization) const;
  Response info(uint64_t nowMs) const;
  Response health(uint64_t nowMs) const;
  Response pair(const std::string& body, uint64_t nowMs);
  Outcome sendRaw(const std::string& body);
  Response sendAc(const std::string& body);
  Response startLearn(const std::string& body, uint64_t nowMs);
  Response stopLearn();
  void pushEvent(Event event);

  Identity identity_;
  TokenStore tokens_;
  Platform& platform_;
  OtaTarget* otaTarget_;
  BridgeOptions options_;

  PairingWindow window_;
  bool transmitting_ = false;
  LearnMode learnMode_ = LearnMode::Idle;
  uint64_t learnDeadlineMs_ = 0;
  bool clearedFlash_ = false;
  uint64_t clearedAtMs_ = 0;
  OtaSession ota_;
  bool rebootRequested_ = false;
  std::vector<Event> events_;
};

}  // namespace bridge
