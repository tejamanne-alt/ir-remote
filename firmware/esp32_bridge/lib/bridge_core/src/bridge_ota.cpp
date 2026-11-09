// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 IR Remote contributors
#include "bridge_ota.h"

#include "bridge_json.h"

namespace bridge {

namespace {

ApiError otaError(int status, const char* code, std::string detail) {
  ApiError e;
  e.status = status;
  e.code = code;
  e.detail = std::move(detail);
  return e;
}

}  // namespace

ApiError OtaSession::begin(OtaTarget& target, const std::string& sha256Header,
                           bool hasContentLength, uint64_t contentLength) {
  if (state_ != State::Idle) return otaError(409, err::kBusy, "an update is already in progress");
  std::string hex = sha256Header;
  while (!hex.empty() && (hex.back() == ' ' || hex.back() == '\t')) hex.pop_back();
  while (!hex.empty() && (hex.front() == ' ' || hex.front() == '\t')) hex.erase(0, 1);
  if (!fromHex(hex, want_, sizeof want_)) {
    return otaError(400, err::kBadRequest, "X-Firmware-SHA256 must be 64 hex characters");
  }
  if (!hasContentLength) {
    return otaError(400, err::kBadRequest, "Content-Length is required for an update");
  }
  if (contentLength == 0) return otaError(400, err::kBadRequest, "the firmware image is empty");
  const size_t capacity = target.capacityBytes();
  if (contentLength > capacity) {
    return otaError(413, err::kTooLarge,
                    "image of " + std::to_string(contentLength) +
                        " bytes does not fit the update partition (" + std::to_string(capacity) +
                        " bytes)");
  }
  if (!target.begin(static_cast<size_t>(contentLength))) {
    return otaError(500, err::kOtaFailed, "could not open the update partition");
  }
  target_ = &target;
  expected_ = contentLength;
  received_ = 0;
  hash_.reset();
  failure_ = Response();
  state_ = State::Receiving;
  return ApiError();
}

void OtaSession::failWith(int status, const char* code, const std::string& detail) {
  if (target_) target_->abort();
  failure_ = errorResponse(status, code, detail);
  state_ = State::Failed;
}

bool OtaSession::write(const uint8_t* data, size_t len) {
  if (state_ != State::Receiving) return false;
  if (len == 0) return true;
  if (len > expected_ - received_) {
    failWith(400, err::kBadRequest, "body is longer than Content-Length");
    return false;
  }
  hash_.update(data, len);
  if (!target_->write(data, len)) {
    failWith(500, err::kOtaFailed, "flash write failed at byte " + std::to_string(received_));
    return false;
  }
  received_ += len;
  return true;
}

Response OtaSession::finish() {
  Response result;
  if (state_ == State::Idle) {
    return errorResponse(400, err::kBadRequest, "no update in progress");
  }
  if (state_ == State::Failed) {
    result = failure_;
  } else if (received_ != expected_) {
    failWith(400, err::kBadRequest,
             "body ended after " + std::to_string(received_) + " of " +
                 std::to_string(expected_) + " bytes");
    result = failure_;
  } else {
    uint8_t got[Sha256::kDigestBytes];
    hash_.finish(got);
    unsigned diff = 0;
    for (size_t i = 0; i < sizeof got; ++i) diff |= static_cast<unsigned>(got[i] ^ want_[i]);
    if (diff != 0) {
      failWith(400, err::kHashMismatch,
               "SHA-256 of the received image is " + toHex(got, sizeof got) +
                   ", which does not match X-Firmware-SHA256");
      result = failure_;
    } else if (!target_->finalize()) {
      result = errorResponse(400, err::kBadImage,
                             "the image was received intact but is not a valid firmware image");
    } else if (!target_->activate()) {
      result = errorResponse(500, err::kOtaFailed, "could not select the new boot partition");
    } else {
      json::Writer w(result.body);
      w.beginObject().key("updated").boolean(true).key("rebooting").boolean(true).endObject();
      result.status = 200;
    }
  }
  state_ = State::Idle;
  target_ = nullptr;
  failure_ = Response();
  return result;
}

void OtaSession::abort() {
  if (state_ == State::Receiving && target_) target_->abort();
  state_ = State::Idle;
  target_ = nullptr;
  failure_ = Response();
}

}  // namespace bridge
