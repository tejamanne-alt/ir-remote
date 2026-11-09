// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
//
// Identity, mDNS records, setup portal and Wi-Fi policy.
#include "test_support.h"

using bridge::CredentialError;
using bridge::WifiCredentials;
using bridge::WifiMode;
using bridge::WifiPolicy;

namespace {

const uint8_t kMac[6] = {0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6};

void test_identity_from_mac() {
  TEST_ASSERT_EQUAL_STRING("a1b2c3d4e5f6", bridge::deviceIdFromMac(kMac).c_str());
  TEST_ASSERT_EQUAL_STRING("irbridge-d4e5f6", bridge::hostnameFromMac(kMac).c_str());
  TEST_ASSERT_EQUAL_STRING("IRBridge-Setup-d4e5f6", bridge::apSsidFromMac(kMac).c_str());
}

void test_mdns_txt_records_match_contract() {
  bridge::Identity id = testsupport::testIdentity();
  const auto txt = bridge::mdnsTxtRecords(id);
  TEST_ASSERT_EQUAL_INT(4, txt.size());
  TEST_ASSERT_EQUAL_STRING("api", txt[0].first.c_str());
  TEST_ASSERT_EQUAL_STRING("1", txt[0].second.c_str());
  TEST_ASSERT_EQUAL_STRING("id", txt[1].first.c_str());
  TEST_ASSERT_EQUAL_STRING("a1b2c3d4e5f6", txt[1].second.c_str());
  TEST_ASSERT_EQUAL_STRING("fw", txt[2].first.c_str());
  TEST_ASSERT_EQUAL_STRING("0.1.0", txt[2].second.c_str());
  TEST_ASSERT_EQUAL_STRING("name", txt[3].first.c_str());
  TEST_ASSERT_EQUAL_STRING("IR Bridge", txt[3].second.c_str());
}

void test_credential_validation() {
  WifiCredentials c;
  c.ssid = "Home";
  c.password = "correct horse";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::None);
  c.password = "";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::None);  // open network
  c.password = std::string(64, 'a');
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::None);  // raw PSK
  c.password = std::string(64, 'z');
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::PasswordInvalid);
  c.password = "short";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::PasswordInvalid);
  c.password = std::string(63, 'p');
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::None);
  c.password = "tab\there!";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::PasswordInvalid);
  c.password = "";
  c.ssid = "";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::SsidInvalid);
  c.ssid = std::string(33, 's');
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::SsidInvalid);
  c.ssid = std::string(32, 's');
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::None);
  c.ssid = "bad\xff";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::SsidInvalid);
  c.ssid = "Home";
  c.name = "Living room";
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::None);
  c.name = std::string(33, 'n');
  TEST_ASSERT_TRUE(bridge::validateCredentials(c) == CredentialError::NameInvalid);
}

void test_setup_page_escapes_hostile_ssids() {
  std::vector<bridge::ScannedNetwork> nets = {
      {"<script>alert(1)</script>", -40, true},
      {"\"><img src=x onerror=alert(2)>", -60, false},
      {"Caf\xc3\xa9 & Bar", -70, true},
  };
  const std::string page = bridge::renderSetupPage("Bridge \"<b>\"", nets, "Wrong <password>");
  TEST_ASSERT_TRUE(page.find("<script>") == std::string::npos);
  TEST_ASSERT_TRUE(page.find("<img") == std::string::npos);
  TEST_ASSERT_TRUE(page.find("&lt;script&gt;alert(1)&lt;/script&gt;") != std::string::npos);
  TEST_ASSERT_TRUE(page.find("&quot;&gt;&lt;img src=x onerror=alert(2)&gt;") != std::string::npos);
  TEST_ASSERT_TRUE(page.find("Caf\xc3\xa9 &amp; Bar") != std::string::npos);
  TEST_ASSERT_TRUE(page.find("Bridge &quot;&lt;b&gt;&quot;") != std::string::npos);
  TEST_ASSERT_TRUE(page.find("Wrong &lt;password&gt;") != std::string::npos);
  TEST_ASSERT_TRUE(page.find("action=\"/save\"") != std::string::npos);
  const std::string saved = bridge::renderSavedPage("<x>");
  TEST_ASSERT_TRUE(saved.find("&lt;x&gt;") != std::string::npos);
}

void test_wifi_policy_without_credentials_runs_portal() {
  WifiPolicy p;
  p.begin(false, 0);
  TEST_ASSERT_TRUE(p.mode(0) == WifiMode::AccessPoint);
  TEST_ASSERT_TRUE(p.portalActive(999999999));
  TEST_ASSERT_FALSE(p.offline(999999));
  TEST_ASSERT_FALSE(p.handleShortPress(999999));  // pairing press, not a portal press
}

void test_wifi_policy_portal_needs_button_when_offline() {
  WifiPolicy p;
  p.begin(true, 0);
  TEST_ASSERT_TRUE(p.mode(0) == WifiMode::Station);
  // Offline right after boot: a press is still a pairing press.
  TEST_ASSERT_FALSE(p.handleShortPress(5000));
  // Offline for a while: no portal by itself ...
  TEST_ASSERT_TRUE(p.mode(600000) == WifiMode::Station);
  TEST_ASSERT_TRUE(p.offline(600000));
  // ... until someone presses BOOT.
  TEST_ASSERT_TRUE(p.handleShortPress(600000));
  TEST_ASSERT_TRUE(p.mode(600001) == WifiMode::StationAndAccessPoint);
  TEST_ASSERT_TRUE(p.portalActive(600000 + bridge::kSetupPortalMs - 1));
  TEST_ASSERT_FALSE(p.portalActive(600000 + bridge::kSetupPortalMs));
  TEST_ASSERT_TRUE(p.mode(600000 + bridge::kSetupPortalMs) == WifiMode::Station);
}

void test_wifi_policy_connection_closes_portal() {
  WifiPolicy p;
  p.begin(true, 0);
  p.setStationConnected(true, 1000);
  TEST_ASSERT_FALSE(p.offline(500000));
  TEST_ASSERT_FALSE(p.handleShortPress(500000));
  p.setStationConnected(false, 600000);
  TEST_ASSERT_FALSE(p.offline(605000));
  TEST_ASSERT_TRUE(p.offline(610000));
  TEST_ASSERT_TRUE(p.handleShortPress(610000));
  TEST_ASSERT_TRUE(p.portalActive(610001));
  p.setStationConnected(true, 620000);
  TEST_ASSERT_FALSE(p.portalActive(620001));
  TEST_ASSERT_TRUE(p.mode(620001) == WifiMode::Station);
}

}  // namespace

void run_provisioning_tests() {
  RUN_TEST(test_identity_from_mac);
  RUN_TEST(test_mdns_txt_records_match_contract);
  RUN_TEST(test_credential_validation);
  RUN_TEST(test_setup_page_escapes_hostile_ssids);
  RUN_TEST(test_wifi_policy_without_credentials_runs_portal);
  RUN_TEST(test_wifi_policy_portal_needs_button_when_offline);
  RUN_TEST(test_wifi_policy_connection_closes_portal);
}
