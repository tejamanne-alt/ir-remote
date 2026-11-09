// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "portal.h"

#include <WiFi.h>

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

std::string param(AsyncWebServerRequest* r, const char* name) {
  const AsyncWebParameter* p = r->getParam(name, true);
  return p ? std::string(p->value().c_str()) : std::string();
}

void sendPage(AsyncWebServerRequest* r, int status, const std::string& html) {
  bridge::Response res;
  res.status = status;
  res.body = html;
  res.contentType = "text/html; charset=utf-8";
  http_api::send(r, res);
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

bool claims(AsyncWebServerRequest* r) {
  if (!net::accessPointUp() || !net::isAccessPointClient(r)) return false;
  return !r->url().startsWith("/v1/");
}

void handle(AsyncWebServerRequest* r) {
  const String apIp = WiFi.softAPIP().toString();
  // Captive-portal detection (Android generate_204, Apple hotspot-detect,
  // Windows connecttest) asks for other hosts: send everything to the page.
  if (r->host() != apIp) {
    r->redirect(String("http://") + apIp + "/");
    return;
  }
  const bool isGet = std::strcmp(r->methodToString(), "GET") == 0;
  const bool isPost = std::strcmp(r->methodToString(), "POST") == 0;
  if (r->url() == "/" && isGet) {
    sendPage(r, 200, bridge::renderSetupPage(name(), net::networks(), ""));
    return;
  }
  if (r->url() == "/save" && isPost) {
    bridge::WifiCredentials c;
    c.ssid = param(r, "ssid");
    c.password = param(r, "pass");
    c.name = param(r, "name");
    const bridge::CredentialError e = bridge::validateCredentials(c);
    if (e != bridge::CredentialError::None) {
      sendPage(r, 400, bridge::renderSetupPage(name(), net::networks(),
                                               bridge::describeCredentialError(e)));
      return;
    }
    if (!nvs_store::saveWifi(c)) {
      sendPage(r, 500, bridge::renderSetupPage(name(), net::networks(),
                                               "Could not save the settings. Try again."));
      return;
    }
    sendPage(r, 200, bridge::renderSavedPage(c.ssid));
    restart = true;
    return;
  }
  r->redirect("/");
}

bool restartRequested() { return restart.load(); }

}  // namespace portal
