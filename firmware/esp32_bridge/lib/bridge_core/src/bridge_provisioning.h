// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Identity (id, mDNS hostname, TXT records), Wi-Fi credential validation,
// the SoftAP setup page, and the Wi-Fi mode policy (docs/ADR-provisioning.md).
#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "bridge_config.h"

namespace bridge {

struct Identity {
  std::string id;    // 12 lowercase hex digits of the station MAC
  std::string name;  // user-visible bridge name
  std::string fw = kFirmwareVersion;
};

std::string deviceIdFromMac(const uint8_t mac[6]);  // "a1b2c3d4e5f6"
std::string hostnameFromMac(const uint8_t mac[6]);  // "irbridge-d4e5f6"
std::string apSsidFromMac(const uint8_t mac[6]);    // "IRBridge-Setup-d4e5f6"

// mDNS TXT records for _irbridge._tcp: api, id, fw, name (in that order).
std::vector<std::pair<std::string, std::string>> mdnsTxtRecords(const Identity& identity);

struct WifiCredentials {
  std::string ssid;
  std::string password;  // empty = open network
  std::string name;      // bridge name; empty keeps the current one
};

enum class CredentialError : uint8_t { None, SsidInvalid, PasswordInvalid, NameInvalid };

// SSID: 1..32 bytes of UTF-8 without control characters. Password: empty,
// 8..63 printable ASCII characters, or 64 hex digits. Name: empty or a valid
// display name of at most kMaxBridgeNameChars characters.
CredentialError validateCredentials(const WifiCredentials& credentials);
const char* describeCredentialError(CredentialError e);

struct ScannedNetwork {
  std::string ssid;
  int32_t rssi = 0;
  bool secure = true;
};

std::string htmlEscape(const std::string& text);

// The setup page served on the access point. Everything that comes from the
// air (SSIDs) or from the user is HTML-escaped.
std::string renderSetupPage(const std::string& bridgeName, const std::vector<ScannedNetwork>& networks,
                            const std::string& notice);
std::string renderSavedPage(const std::string& ssid);

enum class WifiMode : uint8_t { Station, AccessPoint, StationAndAccessPoint };

// Decides which Wi-Fi interfaces should be up.
//  * No stored credentials: access point only (setup portal).
//  * Credentials stored: station only. When the station has been offline for
//    kOfflineBeforePortalMs, a short press on BOOT opens the setup portal for
//    kSetupPortalMs next to the station. The portal is never opened without a
//    button press, so a neighbour cannot re-provision the bridge.
class WifiPolicy {
 public:
  void begin(bool hasCredentials, uint64_t nowMs);
  void setStationConnected(bool connected, uint64_t nowMs);
  // Returns true when the press was used to open the portal (the station is
  // offline); false means the caller should treat it as a pairing press.
  bool handleShortPress(uint64_t nowMs);
  WifiMode mode(uint64_t nowMs) const;
  bool portalActive(uint64_t nowMs) const;
  bool offline(uint64_t nowMs) const;
  bool hasCredentials() const { return hasCredentials_; }

 private:
  bool hasCredentials_ = false;
  bool connected_ = false;
  uint64_t offlineSinceMs_ = 0;
  bool portalOpen_ = false;
  uint64_t portalOpenedMs_ = 0;
};

}  // namespace bridge
