// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "nvs_store.h"

#include <Preferences.h>

#include <vector>

namespace nvs_store {

namespace {

const char kAuthNs[] = "irb-auth";
const char kClientsKey[] = "clients";
const char kWifiNs[] = "irb-wifi";

std::string readString(Preferences& prefs, const char* key) {
  if (!prefs.isKey(key)) return std::string();
  return std::string(prefs.getString(key, "").c_str());
}

}  // namespace

bool TokenBlobStorage::loadBlob(std::string& out) {
  out.clear();
  Preferences prefs;
  // Read-write so the namespace is created on first boot.
  if (!prefs.begin(kAuthNs, false)) return false;
  bool ok = true;
  if (prefs.isKey(kClientsKey)) {
    const size_t len = prefs.getBytesLength(kClientsKey);
    if (len > 0) {
      std::vector<char> buf(len);
      ok = prefs.getBytes(kClientsKey, buf.data(), len) == len;
      if (ok) out.assign(buf.data(), len);
    }
  }
  prefs.end();
  return ok;
}

bool TokenBlobStorage::saveBlob(const std::string& blob) {
  Preferences prefs;
  if (!prefs.begin(kAuthNs, false)) return false;
  // NVS replaces a blob atomically: a power cut leaves the old or the new list.
  const bool ok = prefs.putBytes(kClientsKey, blob.data(), blob.size()) == blob.size();
  prefs.end();
  return ok;
}

bool loadWifi(bridge::WifiCredentials& out) {
  out = bridge::WifiCredentials();
  Preferences prefs;
  if (!prefs.begin(kWifiNs, false)) return false;
  out.ssid = readString(prefs, "ssid");
  out.password = readString(prefs, "pass");
  out.name = readString(prefs, "name");
  prefs.end();
  return !out.ssid.empty();
}

bool saveWifi(const bridge::WifiCredentials& c) {
  Preferences prefs;
  if (!prefs.begin(kWifiNs, false)) return false;
  bool ok = prefs.putString("ssid", c.ssid.c_str()) == c.ssid.size();
  // putString returns 0 for an empty string, which is a valid open network.
  prefs.putString("pass", c.password.c_str());
  if (!c.name.empty()) ok = ok && prefs.putString("name", c.name.c_str()) == c.name.size();
  prefs.end();
  return ok;
}

bool clearWifi() {
  Preferences prefs;
  if (!prefs.begin(kWifiNs, false)) return false;
  const bool ok = prefs.clear();
  prefs.end();
  return ok;
}

}  // namespace nvs_store
