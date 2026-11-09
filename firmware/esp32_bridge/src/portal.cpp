// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "portal.h"

#include <WiFi.h>

#include <esp_http_server.h>

#include <atomic>
#include <cstring>
#include <mutex>

#include "bridge_core.h"
#include "http_api.h"
#include "net.h"
#include "nvs_store.h"

namespace portal {

namespace {

std::mutex nameLock;
std::string currentName;
std::atomic<bool> restart{false};

std::string param(const std::string& body, const char* key) {
  std::string value;
  return bridge::formField(body, key, value) ? value : std::string();
}

esp_err_t sendPage(httpd_req_t* r, int status, const std::string& html) {
  bridge::Response res;
  res.status = status;
  res.body = html;
  res.contentType = "text/html; charset=utf-8";
  return http_api::send(r, res);
}

std::string name() {
  std::lock_guard<std::mutex> g(nameLock);
  return currentName;
}

}  // namespace

void begin(const std::string& bridgeName) {
  std::lock_guard<std::mutex> g(nameLock);
  currentName = bridgeName;
}

bool claims(httpd_req_t* r) {
  if (!net::accessPointUp() || !net::isAccessPointClient(r)) return false;
  return http_api::path(r).rfind("/v1/", 0) != 0;
}

esp_err_t handle(httpd_req_t* r) {
  const std::string apIp = WiFi.softAPIP().toString().c_str();
  // Captive-portal detection (Android generate_204, Apple hotspot-detect,
  // Windows connecttest) asks for other hosts: send everything to the page.
  std::string host = http_api::header(r, "Host");
  const size_t colon = host.find(':');
  if (colon != std::string::npos) host.resize(colon);
  if (host != apIp) return http_api::redirect(r, "http://" + apIp + "/");
  const bridge::Method m = http_api::method(r);
  const std::string p = http_api::path(r);
  if (p == "/" && m == bridge::Method::Get) {
    return sendPage(r, 200, bridge::renderSetupPage(name(), net::networks(), ""));
  }
  if (p == "/save" && m == bridge::Method::Post) {
    std::string body;
    if (!http_api::readBody(r, body, bridge::kMaxFormBytes)) {
      return sendPage(r, 400, bridge::renderSetupPage(name(), net::networks(),
                                                      "The form was too large. Try again."));
    }
    bridge::WifiCredentials c;
    c.ssid = param(body, "ssid");
    c.password = param(body, "pass");
    c.name = param(body, "name");
    const bridge::CredentialError e = bridge::validateCredentials(c);
    if (e != bridge::CredentialError::None) {
      return sendPage(r, 400, bridge::renderSetupPage(name(), net::networks(),
                                                      bridge::describeCredentialError(e)));
    }
    if (!nvs_store::saveWifi(c)) {
      return sendPage(r, 500, bridge::renderSetupPage(name(), net::networks(),
                                                      "Could not save the settings. Try again."));
    }
    restart = true;
    return sendPage(r, 200, bridge::renderSavedPage(c.ssid));
  }
  return http_api::redirect(r, "/");
}

bool restartRequested() { return restart.load(); }

}  // namespace portal
