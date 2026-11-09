// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_provisioning.h"

#include "bridge_auth.h"
#include "bridge_controls.h"
#include "bridge_json.h"

namespace bridge {

namespace {

std::string hexBytes(const uint8_t* bytes, size_t n) {
  static const char kHex[] = "0123456789abcdef";
  std::string out;
  for (size_t i = 0; i < n; ++i) {
    out += kHex[bytes[i] >> 4];
    out += kHex[bytes[i] & 0x0F];
  }
  return out;
}

bool isHexDigit(char c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

}  // namespace

std::string deviceIdFromMac(const uint8_t mac[6]) { return hexBytes(mac, 6); }
std::string hostnameFromMac(const uint8_t mac[6]) { return "irbridge-" + hexBytes(mac + 3, 3); }
std::string apSsidFromMac(const uint8_t mac[6]) { return "IRBridge-Setup-" + hexBytes(mac + 3, 3); }

std::vector<std::pair<std::string, std::string>> mdnsTxtRecords(const Identity& identity) {
  return {
      {"api", std::to_string(kApiVersion)},
      {"id", identity.id},
      {"fw", identity.fw},
      {"name", identity.name},
  };
}

CredentialError validateCredentials(const WifiCredentials& c) {
  if (c.ssid.empty() || c.ssid.size() > 32 || !json::isValidUtf8(c.ssid.data(), c.ssid.size())) {
    return CredentialError::SsidInvalid;
  }
  for (char ch : c.ssid) {
    const unsigned char u = static_cast<unsigned char>(ch);
    if (u < 0x20 || u == 0x7F) return CredentialError::SsidInvalid;
  }
  const std::string& p = c.password;
  if (!p.empty()) {
    if (p.size() == 64) {
      for (char ch : p) {
        if (!isHexDigit(ch)) return CredentialError::PasswordInvalid;
      }
    } else {
      if (p.size() < 8 || p.size() > 63) return CredentialError::PasswordInvalid;
      for (char ch : p) {
        if (ch < 0x20 || ch > 0x7E) return CredentialError::PasswordInvalid;
      }
    }
  }
  if (!c.name.empty() && !isValidDisplayName(c.name, kMaxBridgeNameChars)) {
    return CredentialError::NameInvalid;
  }
  return CredentialError::None;
}

const char* describeCredentialError(CredentialError e) {
  switch (e) {
    case CredentialError::None: return "ok";
    case CredentialError::SsidInvalid: return "The network name must be 1 to 32 bytes.";
    case CredentialError::PasswordInvalid:
      return "The password must be empty (open network), 8 to 63 characters, or 64 hex digits.";
    case CredentialError::NameInvalid:
      return "The bridge name must be 1 to 32 characters without control characters.";
  }
  return "invalid input";
}

std::string htmlEscape(const std::string& text) {
  std::string out;
  out.reserve(text.size());
  for (char c : text) {
    switch (c) {
      case '&': out += "&amp;"; break;
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '"': out += "&quot;"; break;
      case '\'': out += "&#39;"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          out += ' ';
        } else {
          out += c;
        }
    }
  }
  return out;
}

namespace {

const char kPageHead[] =
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    "<title>IR Bridge setup</title><style>"
    "body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#f6f6f6;color:#111}"
    "main{max-width:420px;margin:0 auto;background:#fff;padding:16px;border-radius:8px}"
    "label{display:block;margin-top:12px;font-weight:600}"
    "input{width:100%;box-sizing:border-box;padding:10px;margin-top:4px;font-size:16px}"
    "button{margin-top:16px;width:100%;padding:12px;font-size:16px}"
    ".note{background:#fff4d6;padding:8px;border-radius:4px}"
    "@media(prefers-color-scheme:dark){body{background:#111;color:#eee}"
    "main{background:#222}.note{background:#4a3c10}}"
    "</style></head><body><main>";
const char kPageTail[] = "</main></body></html>";

}  // namespace

std::string renderSetupPage(const std::string& bridgeName, const std::vector<ScannedNetwork>& networks,
                            const std::string& notice) {
  std::string out(kPageHead);
  out += "<h1>IR Bridge setup</h1>";
  if (!notice.empty()) {
    out += "<p class=\"note\">";
    out += htmlEscape(notice);
    out += "</p>";
  }
  out +=
      "<p>Choose the Wi-Fi network the bridge should join. Your phone must use the same "
      "network to control it.</p>"
      "<form method=\"post\" action=\"/save\">"
      "<label for=\"ssid\">Network name (SSID)</label>"
      "<input id=\"ssid\" name=\"ssid\" list=\"nets\" maxlength=\"32\" required autocomplete=\"off\">"
      "<datalist id=\"nets\">";
  size_t shown = 0;
  for (const ScannedNetwork& n : networks) {
    if (n.ssid.empty()) continue;
    if (++shown > 20) break;
    out += "<option value=\"";
    out += htmlEscape(n.ssid);
    out += "\">";
    out += n.secure ? "secured" : "open";
    out += ", ";
    out += std::to_string(static_cast<long long>(n.rssi));
    out += " dBm</option>";
  }
  out +=
      "</datalist>"
      "<label for=\"pass\">Password</label>"
      "<input id=\"pass\" name=\"pass\" type=\"password\" maxlength=\"64\" autocomplete=\"off\">"
      "<label for=\"name\">Bridge name</label>"
      "<input id=\"name\" name=\"name\" maxlength=\"32\" value=\"";
  out += htmlEscape(bridgeName);
  out +=
      "\">"
      "<button type=\"submit\">Save and restart</button></form>"
      "<p>This setup network is unencrypted; set up the bridge where you trust the people "
      "nearby. It closes when the bridge joins your network.</p>";
  out += kPageTail;
  return out;
}

std::string renderSavedPage(const std::string& ssid) {
  std::string out(kPageHead);
  out += "<h1>Saved</h1><p>The bridge restarts and joins <b>";
  out += htmlEscape(ssid);
  out +=
      "</b>. Reconnect your phone to that network, open the app and add the bridge.</p>"
      "<p>If it cannot join, the status LED flashes briefly every 2 seconds. Press BOOT once "
      "to bring this setup network back.</p>";
  out += kPageTail;
  return out;
}

void WifiPolicy::begin(bool hasCredentials, uint64_t nowMs) {
  hasCredentials_ = hasCredentials;
  connected_ = false;
  offlineSinceMs_ = nowMs;
  portalOpen_ = false;
}

void WifiPolicy::setStationConnected(bool connected, uint64_t nowMs) {
  if (connected == connected_) return;
  connected_ = connected;
  if (connected) {
    portalOpen_ = false;  // the station works again; the portal has no purpose
  } else {
    offlineSinceMs_ = nowMs;
  }
}

bool WifiPolicy::offline(uint64_t nowMs) const {
  return hasCredentials_ && !connected_ &&
         elapsedMs(nowMs, offlineSinceMs_) >= kOfflineBeforePortalMs;
}

bool WifiPolicy::handleShortPress(uint64_t nowMs) {
  if (!offline(nowMs)) return false;
  portalOpen_ = true;
  portalOpenedMs_ = nowMs;
  return true;
}

bool WifiPolicy::portalActive(uint64_t nowMs) const {
  if (!hasCredentials_) return true;
  return portalOpen_ && elapsedMs(nowMs, portalOpenedMs_) < kSetupPortalMs;
}

WifiMode WifiPolicy::mode(uint64_t nowMs) const {
  if (!hasCredentials_) return WifiMode::AccessPoint;
  return portalActive(nowMs) ? WifiMode::StationAndAccessPoint : WifiMode::Station;
}

}  // namespace bridge
