// Broadlink RM local protocol: frames, checksums, AES, RM command framing,
// hello packets, the devtype table and the IR payload codec.
//
// This is an independent Dart implementation written from the protocol as
// described by the MIT-licensed python-broadlink project. No code was
// translated; the references were read to learn the wire format:
//
// * https://github.com/mjg59/python-broadlink
//   at commit 730853e5faf2cf979596662faf9def2b1f8fee6d
//   - protocol.md: 0x38-byte frame header layout, the 0xBEAF additive
//     checksum, the AES-128-CBC initial key and fixed IV, the auth payload
//     and auth reply layout, the hello packet, the IR payload layout (0x26
//     marker, repeat byte, little-endian length, 0x00-escaped big-endian
//     values above 255 units) and the 0x00 0x0d 0x05 capture trailer.
//   - broadlink/device.py: header fields as actually sent (devtype 0x24,
//     packet type 0x26, counter 0x28 and its update rule, reversed MAC
//     0x2a, session id 0x30, payload checksum 0x34), packet types 0x65
//     (auth) and 0x6a (command), the reply checksum check and the hello
//     reply offsets (devtype 0x34, MAC 0x3a, name 0x40, lock flag 0x7f).
//   - broadlink/remote.py: RM command codes 0x02 (send), 0x03 (enter
//     learning), 0x04 (check data) and the two command framings (plain
//     32-bit command for RM2/RM pro/RM mini 3, length-prefixed for RM4).
//   - broadlink/__init__.py: devtype to model table.
//   - broadlink/exceptions.py: device error codes.
// * https://github.com/DAB-LABS/python-broadlink (maintained fork)
//   at commit 6c6567ddeba8905537e0049a1343ebd0e5e165a2
//   - broadlink_async/remote.py and README "Timing": the IR unit is
//     8192/269 us (upstream's 32.84 is a documented bug, mjg59#839),
//     rounding to the nearest unit, and appending an off time to a code
//     that ends on a mark (an RM4 Pro otherwise stretches the last pulse).
//     Also command 0x1e (cancel learning) and the "nothing captured yet"
//     codes -5 and -10.
//   - broadlink_async/device.py: the error codes that call for a fresh
//     auth (-2, -7, -4012) and matching replies to requests by counter.
//   - broadlink_async/__init__.py: extra devtypes (RM5 plus).
//
// Both repositories are MIT licensed (Copyright (c) 2014 Mike Ryan,
// Copyright (c) 2016 Matthew Garrett).

/// Pure, socket-free building blocks of the Broadlink RM protocol.
///
/// Everything here is deterministic and testable without a network: frame
/// building and parsing, AES, RM command framing, hello packets and the IR
/// payload codec. Every parser throws only [BroadlinkFormatException] (or
/// its subtype [BroadlinkDecryptException]) for malformed input, never a
/// `RangeError`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ir_core/ir_core.dart';
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base class of every error the Broadlink code reports.
sealed class BroadlinkException implements Exception {
  const BroadlinkException(this.message);

  /// Human-readable detail.
  final String message;

  String get _label;

  @override
  String toString() => '$_label: $message';
}

/// A packet or payload that does not have the expected structure.
final class BroadlinkFormatException extends BroadlinkException {
  /// Creates a format error.
  const BroadlinkFormatException(super.message);

  @override
  String get _label => 'BroadlinkFormatException';
}

/// A reply that cannot be decrypted with the current session key: its
/// length is not a whole number of AES blocks, or the decrypted structure is
/// inconsistent. Usually means the session key is stale.
final class BroadlinkDecryptException extends BroadlinkFormatException {
  /// Creates a decrypt error.
  const BroadlinkDecryptException(super.message);

  @override
  String get _label => 'BroadlinkDecryptException';
}

/// The device answered with a non-zero error code.
final class BroadlinkDeviceException extends BroadlinkException {
  /// Creates a device error for [code].
  BroadlinkDeviceException(this.code, String context)
    : super('$context (device error $code: ${describeBroadlinkError(code)})');

  /// The signed 16-bit error code from offset 0x22 of the reply.
  final int code;

  @override
  String get _label => 'BroadlinkDeviceException';
}

/// No usable reply arrived in time.
final class BroadlinkTimeoutException extends BroadlinkException {
  /// Creates a timeout error.
  const BroadlinkTimeoutException(this.after, super.message);

  /// How long the caller waited.
  final Duration after;

  @override
  String get _label => 'BroadlinkTimeoutException';
}

/// A socket could not be opened or used, or the transport was disposed.
final class BroadlinkNetworkException extends BroadlinkException {
  /// Creates a network error.
  const BroadlinkNetworkException(super.message);

  @override
  String get _label => 'BroadlinkNetworkException';
}

/// The device is not a Broadlink RM model this code knows how to drive.
final class BroadlinkUnsupportedDeviceException extends BroadlinkException {
  /// Creates an unsupported-device error.
  const BroadlinkUnsupportedDeviceException(super.message);

  @override
  String get _label => 'BroadlinkUnsupportedDeviceException';
}

/// The request conflicts with the transport's current state (for example a
/// second learn session while one is running).
final class BroadlinkStateException extends BroadlinkException {
  /// Creates a state error.
  const BroadlinkStateException(super.message);

  @override
  String get _label => 'BroadlinkStateException';
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// UDP port Broadlink devices listen on.
const int broadlinkDefaultPort = 80;

/// Length of the frame header; the encrypted payload starts here.
const int broadlinkHeaderLength = 0x38;

/// Shortest reply the parser accepts (the reference accepts 48 bytes).
const int broadlinkMinFrameLength = 0x30;

/// Initial value of the additive 16-bit checksum.
const int broadlinkChecksumSeed = 0xBEAF;

/// AES-128 key used before authentication (protocol.md).
const List<int> broadlinkInitialKey = [
  0x09, 0x76, 0x28, 0x34, 0x3f, 0xe9, 0x9e, 0x23, //
  0x76, 0x5c, 0x15, 0x13, 0xac, 0xcf, 0x8b, 0x02,
];

/// Fixed AES-CBC IV used for every message, before and after auth.
const List<int> broadlinkIv = [
  0x56, 0x2e, 0x17, 0x99, 0x6d, 0x09, 0x3d, 0x28, //
  0xdd, 0xb3, 0xba, 0x69, 0x5a, 0x2e, 0x6f, 0x58,
];

/// The magic bytes at the start of every command frame.
const List<int> broadlinkFrameMagic = [
  0x5a, 0xa5, 0xaa, 0x55, 0x5a, 0xa5, 0xaa, 0x55, //
];

/// Values of the packet-type field (offset 0x26).
abstract final class BroadlinkPacketType {
  /// Discovery hello (unencrypted 48-byte packet).
  static const int hello = 0x06;

  /// Authentication request.
  static const int auth = 0x65;

  /// Encrypted command.
  static const int command = 0x6a;
}

/// RM command codes carried inside a [BroadlinkPacketType.command] payload.
abstract final class BroadlinkRmCommand {
  /// Transmit an IR/RF payload.
  static const int sendData = 0x02;

  /// Enter IR learning mode.
  static const int enterLearning = 0x03;

  /// Read back the last captured code.
  static const int checkData = 0x04;

  /// Leave learning mode (verified by the fork on an RM4 Pro only).
  static const int cancelLearning = 0x1e;
}

/// Device error codes with a defined meaning.
abstract final class BroadlinkErrorCode {
  /// Authentication failed.
  static const int authFailed = -1;

  /// The session was logged out.
  static const int loggedOut = -2;

  /// Command not supported.
  static const int notSupported = -4;

  /// "Storage full": what an RM4 answers to check-data before a capture.
  static const int storageFull = -5;

  /// Control key expired.
  static const int keyExpired = -7;

  /// Send error.
  static const int sendError = -8;

  /// "Read error": what older firmware answers to check-data before a
  /// capture.
  static const int readError = -10;

  /// Device control id error.
  static const int controlIdError = -4012;

  /// Codes after which a fresh auth is expected to fix the session.
  static const Set<int> reauth = {loggedOut, keyExpired, controlIdError};

  /// Codes check-data returns while nothing has been captured yet.
  static const Set<int> nothingCaptured = {storageFull, readError};
}

/// Describes a device error code for logs.
String describeBroadlinkError(int code) => switch (code) {
  0 => 'ok',
  -1 => 'authentication failed',
  -2 => 'logged out',
  -3 => 'device offline',
  -4 => 'command not supported',
  -5 => 'storage full / nothing captured',
  -6 => 'structure abnormal',
  -7 => 'control key expired',
  -8 => 'send error',
  -9 => 'write error',
  -10 => 'read error / nothing captured',
  -11 => 'SSID not found',
  -4012 => 'control id error',
  _ => 'unknown error',
};

// ---------------------------------------------------------------------------
// Checksum and byte helpers
// ---------------------------------------------------------------------------

/// The protocol's 16-bit checksum: [broadlinkChecksumSeed] plus every byte
/// in `bytes[start, end)`, wrapped to 16 bits.
int broadlinkChecksum(List<int> bytes, [int start = 0, int? end]) {
  final stop = end ?? bytes.length;
  var sum = broadlinkChecksumSeed;
  for (var i = start; i < stop; i++) {
    sum = (sum + (bytes[i] & 0xff)) & 0xffff;
  }
  return sum;
}

int _u16le(List<int> b, int at) => (b[at] & 0xff) | ((b[at + 1] & 0xff) << 8);

int _s16le(List<int> b, int at) {
  final v = _u16le(b, at);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int _u32le(List<int> b, int at) => _u16le(b, at) | (_u16le(b, at + 2) << 16);

void _put16le(Uint8List b, int at, int v) {
  b[at] = v & 0xff;
  b[at + 1] = (v >> 8) & 0xff;
}

void _put32le(Uint8List b, int at, int v) {
  _put16le(b, at, v & 0xffff);
  _put16le(b, at + 2, (v >> 16) & 0xffff);
}

// ---------------------------------------------------------------------------
// AES-128-CBC
// ---------------------------------------------------------------------------

/// AES-128-CBC with the protocol's fixed IV and zero padding.
///
/// The protocol reuses one IV for every message; that is a property of the
/// device firmware, not a choice made here.
final class BroadlinkCipher {
  /// Creates a cipher for a 16-byte [key].
  BroadlinkCipher(List<int> key) : _key = Uint8List.fromList(key) {
    if (key.length != 16) {
      throw ArgumentError.value(key.length, 'key.length', 'must be 16');
    }
  }

  /// The cipher used before authentication.
  factory BroadlinkCipher.initial() => BroadlinkCipher(broadlinkInitialKey);

  final Uint8List _key;

  /// A copy of the key.
  Uint8List get key => Uint8List.fromList(_key);

  /// Zero-pads [plaintext] to a multiple of 16 bytes and encrypts it.
  Uint8List encrypt(List<int> plaintext) {
    final padded = Uint8List((plaintext.length + 15) & ~15)
      ..setRange(0, plaintext.length, plaintext);
    return _run(true, padded);
  }

  /// Decrypts [ciphertext]. Throws [BroadlinkDecryptException] when its
  /// length is not a multiple of 16.
  Uint8List decrypt(List<int> ciphertext) {
    if (ciphertext.length % 16 != 0) {
      throw BroadlinkDecryptException(
        'encrypted payload is ${ciphertext.length} bytes, '
        'not a multiple of 16',
      );
    }
    return _run(false, Uint8List.fromList(ciphertext));
  }

  Uint8List _run(bool forEncryption, Uint8List input) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        forEncryption,
        ParametersWithIV<KeyParameter>(
          KeyParameter(_key),
          Uint8List.fromList(broadlinkIv),
        ),
      );
    final out = Uint8List(input.length);
    for (var off = 0; off < input.length; off += 16) {
      cipher.processBlock(input, off, out, off);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

/// Builds an encrypted frame: the 0x38-byte header followed by [payload]
/// zero-padded and encrypted with [cipher].
///
/// [mac] is the device MAC in display order (as printed on the label); the
/// frame carries it reversed. Requests use [errorCode] 0; the parameter
/// exists for fake devices in tests.
Uint8List buildBroadlinkFrame({
  required int packetType,
  required int devtype,
  required int count,
  required List<int> mac,
  required int sessionId,
  required List<int> payload,
  required BroadlinkCipher cipher,
  int errorCode = 0,
}) {
  if (mac.length != 6) {
    throw ArgumentError.value(mac.length, 'mac.length', 'must be 6');
  }
  final encrypted = cipher.encrypt(payload);
  final frame = Uint8List(broadlinkHeaderLength + encrypted.length)
    ..setRange(0, 8, broadlinkFrameMagic);
  _put16le(frame, 0x22, errorCode & 0xffff);
  _put16le(frame, 0x24, devtype & 0xffff);
  _put16le(frame, 0x26, packetType & 0xffff);
  _put16le(frame, 0x28, count & 0xffff);
  for (var i = 0; i < 6; i++) {
    frame[0x2a + i] = mac[5 - i] & 0xff;
  }
  _put32le(frame, 0x30, sessionId);
  // The payload checksum covers the unpadded plaintext; zero padding does
  // not change an additive sum, so either reading gives the same value.
  _put16le(frame, 0x34, broadlinkChecksum(payload));
  frame.setRange(broadlinkHeaderLength, frame.length, encrypted);
  _put16le(frame, 0x20, broadlinkChecksum(frame));
  return frame;
}

/// A parsed frame header plus its still-encrypted payload. Requests and
/// replies share the layout.
final class BroadlinkFrame {
  BroadlinkFrame._({
    required this.errorCode,
    required this.devtype,
    required this.packetType,
    required this.count,
    required this.mac,
    required this.sessionId,
    required this.payloadChecksum,
    required this.encryptedPayload,
  });

  /// Parses and checksum-checks a frame. Throws [BroadlinkFormatException]
  /// when it is shorter than 48 bytes or the checksum does not match.
  static BroadlinkFrame parse(List<int> bytes) {
    if (bytes.length < broadlinkMinFrameLength) {
      throw BroadlinkFormatException(
        'frame is ${bytes.length} bytes; at least '
        '$broadlinkMinFrameLength expected',
      );
    }
    final nominal = _u16le(bytes, 0x20);
    final actual =
        (broadlinkChecksum(bytes) -
            (bytes[0x20] & 0xff) -
            (bytes[0x21] & 0xff)) &
        0xffff;
    if (nominal != actual) {
      throw BroadlinkFormatException(
        'frame checksum is 0x${nominal.toRadixString(16)}; '
        'computed 0x${actual.toRadixString(16)}',
      );
    }
    final len = bytes.length;
    final mac = <int>[
      for (var i = 5; i >= 0; i--) bytes[0x2a + i] & 0xff, //
    ];
    return BroadlinkFrame._(
      errorCode: _s16le(bytes, 0x22),
      devtype: _u16le(bytes, 0x24),
      packetType: _u16le(bytes, 0x26),
      count: _u16le(bytes, 0x28),
      mac: List.unmodifiable(mac),
      sessionId: len >= 0x34 ? _u32le(bytes, 0x30) : 0,
      payloadChecksum: len >= 0x36 ? _u16le(bytes, 0x34) : 0,
      encryptedPayload: len > broadlinkHeaderLength
          ? Uint8List.fromList(bytes.sublist(broadlinkHeaderLength))
          : Uint8List(0),
    );
  }

  /// Signed 16-bit error code (0 means success).
  final int errorCode;

  /// Device type.
  final int devtype;

  /// Packet type.
  final int packetType;

  /// Request counter; replies echo the request's value.
  final int count;

  /// MAC in display order.
  final List<int> mac;

  /// Session id assigned at auth (0 before).
  final int sessionId;

  /// Checksum of the plaintext payload, as stated in the header.
  final int payloadChecksum;

  /// Payload bytes after the header, still encrypted.
  final Uint8List encryptedPayload;
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Client name sent in the auth request. The value is the one the
/// reference sends and is known to be accepted by real devices.
const String broadlinkAuthClientName = 'Test 1';

/// Builds the 0x50-byte plaintext auth payload: a 16-byte client id of
/// ASCII '1', flag bytes at 0x1e and 0x2d, and the client name at 0x30.
Uint8List buildBroadlinkAuthPayload() {
  final p = Uint8List(0x50)..fillRange(0x04, 0x14, 0x31);
  p[0x1e] = 0x01;
  p[0x2d] = 0x01;
  final name = ascii.encode(broadlinkAuthClientName);
  p.setRange(0x30, 0x30 + name.length, name);
  return p;
}

/// The session id and key a device returns from auth.
final class BroadlinkAuthReply {
  /// Creates an auth reply.
  BroadlinkAuthReply({required this.sessionId, required List<int> key})
    : key = Uint8List.fromList(key);

  /// Parses a decrypted auth reply payload: id (LE u32) then a 16-byte key.
  /// Throws [BroadlinkDecryptException] when it is too short.
  static BroadlinkAuthReply parse(List<int> decrypted) {
    if (decrypted.length < 0x14) {
      throw BroadlinkDecryptException(
        'auth reply payload is ${decrypted.length} bytes; 20 expected',
      );
    }
    return BroadlinkAuthReply(
      sessionId: _u32le(decrypted, 0),
      key: decrypted.sublist(0x04, 0x14),
    );
  }

  /// Session id to put at offset 0x30 of later frames.
  final int sessionId;

  /// Session AES key.
  final Uint8List key;
}

// ---------------------------------------------------------------------------
// RM models and command framing
// ---------------------------------------------------------------------------

/// How RM commands are framed inside the encrypted payload.
enum BroadlinkFamily {
  /// RM2, RM pro and RM mini 3 on older firmware: a little-endian 32-bit
  /// command code followed by the data; replies carry 4 bytes before the
  /// data.
  rm2,

  /// RM4 family (RM4 mini, RM4C, RM4 pro, RM4S, RM4 TV mate), RM mini 3 on
  /// newer firmware and RM5 plus: a little-endian 16-bit length (data + 4)
  /// before the command code; replies carry the same 6-byte prefix.
  rm4,
}

/// A known RM model.
final class BroadlinkModel {
  /// Creates a model description.
  const BroadlinkModel(this.name, this.family);

  /// Marketing name.
  final String name;

  /// Command framing.
  final BroadlinkFamily family;

  @override
  String toString() => '$name (${family.name})';
}

const _rm2 = BroadlinkFamily.rm2;
const _rm4 = BroadlinkFamily.rm4;

/// IR-capable RM devtypes from the reference tables. Other Broadlink
/// devices (plugs, sensors) answer hello too and must not be sent IR
/// commands, so anything not listed is treated as unsupported.
const Map<int, BroadlinkModel> broadlinkRmModels = {
  // RM mini 3 / RM mini (plain framing).
  0x2737: BroadlinkModel('RM mini 3', _rm2),
  0x278f: BroadlinkModel('RM mini', _rm2),
  0x27b7: BroadlinkModel('RM mini 3', _rm2),
  0x27c2: BroadlinkModel('RM mini 3', _rm2),
  0x27c7: BroadlinkModel('RM mini 3', _rm2),
  0x27c8: BroadlinkModel('RM mini 3', _rm2),
  0x27cc: BroadlinkModel('RM mini 3', _rm2),
  0x27cd: BroadlinkModel('RM mini 3', _rm2),
  0x27d0: BroadlinkModel('RM mini 3', _rm2),
  0x27d1: BroadlinkModel('RM mini 3', _rm2),
  0x27d3: BroadlinkModel('RM mini 3', _rm2),
  0x27dc: BroadlinkModel('RM mini 3', _rm2),
  0x27de: BroadlinkModel('RM mini 3', _rm2),
  // RM pro / RM home / RM plus (plain framing).
  0x2712: BroadlinkModel('RM pro/pro+', _rm2),
  0x272a: BroadlinkModel('RM pro', _rm2),
  0x273d: BroadlinkModel('RM pro', _rm2),
  0x277c: BroadlinkModel('RM home', _rm2),
  0x2783: BroadlinkModel('RM home', _rm2),
  0x2787: BroadlinkModel('RM pro', _rm2),
  0x278b: BroadlinkModel('RM plus', _rm2),
  0x2797: BroadlinkModel('RM pro+', _rm2),
  0x279d: BroadlinkModel('RM pro+', _rm2),
  0x27a1: BroadlinkModel('RM plus', _rm2),
  0x27a6: BroadlinkModel('RM plus', _rm2),
  0x27a9: BroadlinkModel('RM pro+', _rm2),
  0x27c3: BroadlinkModel('RM pro+', _rm2),
  // RM mini 3 on newer firmware (length-prefixed framing).
  0x5f36: BroadlinkModel('RM mini 3', _rm4),
  0x6507: BroadlinkModel('RM mini 3', _rm4),
  0x6508: BroadlinkModel('RM mini 3', _rm4),
  // RM4 mini family.
  0x51da: BroadlinkModel('RM4 mini', _rm4),
  0x5209: BroadlinkModel('RM4 TV mate', _rm4),
  0x520c: BroadlinkModel('RM4 mini', _rm4),
  0x520d: BroadlinkModel('RM4C mini', _rm4),
  0x5211: BroadlinkModel('RM4C mate', _rm4),
  0x5212: BroadlinkModel('RM4 TV mate', _rm4),
  0x5216: BroadlinkModel('RM4 mini', _rm4),
  0x521c: BroadlinkModel('RM4 mini', _rm4),
  0x6070: BroadlinkModel('RM4C mini', _rm4),
  0x610e: BroadlinkModel('RM4 mini', _rm4),
  0x610f: BroadlinkModel('RM4C mini', _rm4),
  0x62bc: BroadlinkModel('RM4 mini', _rm4),
  0x62be: BroadlinkModel('RM4C mini', _rm4),
  0x6364: BroadlinkModel('RM4S', _rm4),
  0x648d: BroadlinkModel('RM4 mini', _rm4),
  0x6539: BroadlinkModel('RM4C mini', _rm4),
  0x653a: BroadlinkModel('RM4 mini', _rm4),
  // RM4 pro family.
  0x520b: BroadlinkModel('RM4 pro', _rm4),
  0x5213: BroadlinkModel('RM4 pro', _rm4),
  0x5218: BroadlinkModel('RM4C pro', _rm4),
  0x6026: BroadlinkModel('RM4 pro', _rm4),
  0x6184: BroadlinkModel('RM4C pro', _rm4),
  0x61a2: BroadlinkModel('RM4 pro', _rm4),
  0x649b: BroadlinkModel('RM4 pro', _rm4),
  0x653c: BroadlinkModel('RM4 pro', _rm4),
  // RM5 plus (fork only).
  0x5224: BroadlinkModel('RM5 plus', _rm4),
};

/// The model for [devtype], or `null` when it is not a known RM device.
BroadlinkModel? broadlinkModelFor(int devtype) => broadlinkRmModels[devtype];

/// Builds the plaintext of an RM command for [family].
Uint8List buildBroadlinkRmCommand(
  BroadlinkFamily family,
  int command, [
  List<int> data = const [],
]) {
  switch (family) {
    case BroadlinkFamily.rm2:
      final out = Uint8List(4 + data.length);
      _put32le(out, 0, command);
      out.setRange(4, out.length, data);
      return out;
    case BroadlinkFamily.rm4:
      final out = Uint8List(6 + data.length);
      _put16le(out, 0, data.length + 4);
      _put32le(out, 2, command);
      out.setRange(6, out.length, data);
      return out;
  }
}

/// Extracts the data from a decrypted RM reply payload.
///
/// For [BroadlinkFamily.rm4] the length prefix must be consistent with the
/// buffer; garbage there almost always means the payload was decrypted with
/// the wrong key, so this throws [BroadlinkDecryptException]. For
/// [BroadlinkFamily.rm2] there is no structure to check beyond the 4-byte
/// prefix. Zero padding after the data is kept for rm2 replies, as the
/// device sends it; IR parsing ignores it.
Uint8List unwrapBroadlinkRmReply(BroadlinkFamily family, List<int> decrypted) {
  switch (family) {
    case BroadlinkFamily.rm2:
      if (decrypted.length < 4) {
        throw BroadlinkDecryptException(
          'RM reply payload is ${decrypted.length} bytes; at least 4 expected',
        );
      }
      return Uint8List.fromList(decrypted.sublist(4));
    case BroadlinkFamily.rm4:
      if (decrypted.length < 6) {
        throw BroadlinkDecryptException(
          'RM4 reply payload is ${decrypted.length} bytes; at least 6 '
          'expected',
        );
      }
      final declared = _u16le(decrypted, 0);
      if (declared < 4 || declared + 2 > decrypted.length) {
        throw BroadlinkDecryptException(
          'RM4 reply declares $declared bytes in a '
          '${decrypted.length}-byte payload',
        );
      }
      return Uint8List.fromList(decrypted.sublist(6, declared + 2));
  }
}

// ---------------------------------------------------------------------------
// Hello
// ---------------------------------------------------------------------------

/// Builds the 48-byte hello (discovery) packet.
///
/// The time fields follow the reference implementation's layout (which
/// differs slightly from the table in its protocol.md): UTC offset in hours
/// (LE i32) at 0x08, year (LE u16) at 0x0c, minute 0x0e, hour 0x0f,
/// two-digit year 0x10, ISO weekday 0x11, day 0x12, month 0x13. Devices
/// reply to the datagram's source, so [localIp] and [localPort] may be
/// left as zeros.
Uint8List buildBroadlinkHelloPacket({
  required DateTime now,
  List<int> localIp = const [0, 0, 0, 0],
  int localPort = 0,
}) {
  if (localIp.length != 4) {
    throw ArgumentError.value(localIp.length, 'localIp.length', 'must be 4');
  }
  final p = Uint8List(0x30);
  _put32le(p, 0x08, now.timeZoneOffset.inHours);
  _put16le(p, 0x0c, now.year);
  p[0x0e] = now.minute;
  p[0x0f] = now.hour;
  p[0x10] = now.year % 100;
  p[0x11] = now.weekday; // Dart weekdays are ISO: Monday 1 .. Sunday 7.
  p[0x12] = now.day;
  p[0x13] = now.month;
  for (var i = 0; i < 4; i++) {
    p[0x18 + i] = localIp[3 - i] & 0xff;
  }
  _put16le(p, 0x1c, localPort);
  p[0x26] = BroadlinkPacketType.hello;
  _put16le(p, 0x20, broadlinkChecksum(p));
  return p;
}

/// What a device says about itself in its hello reply.
final class BroadlinkHelloReply {
  /// Creates a hello reply.
  BroadlinkHelloReply({
    required this.devtype,
    required List<int> mac,
    this.name,
    this.isLocked,
  }) : mac = List.unmodifiable(mac);

  /// Parses a hello reply. Needs at least 0x40 bytes (devtype and MAC); the
  /// name (from 0x40 up to a NUL) and lock flag (0x7f) are read when
  /// present. Throws [BroadlinkFormatException] when too short.
  static BroadlinkHelloReply parse(List<int> bytes) {
    if (bytes.length < 0x40) {
      throw BroadlinkFormatException(
        'hello reply is ${bytes.length} bytes; at least 64 expected',
      );
    }
    final mac = [for (var i = 5; i >= 0; i--) bytes[0x3a + i] & 0xff];
    String? name;
    final nameEnd = bytes.length < 0x7f ? bytes.length : 0x7f;
    final raw = <int>[];
    for (var i = 0x40; i < nameEnd; i++) {
      final b = bytes[i] & 0xff;
      if (b == 0) break;
      raw.add(b);
    }
    if (raw.isNotEmpty) name = utf8.decode(raw, allowMalformed: true);
    return BroadlinkHelloReply(
      devtype: _u16le(bytes, 0x34),
      mac: mac,
      name: name,
      isLocked: bytes.length > 0x7f ? bytes[0x7f] != 0 : null,
    );
  }

  /// Device type.
  final int devtype;

  /// MAC in display order.
  final List<int> mac;

  /// Name set in the Broadlink app, if the reply carries one.
  final String? name;

  /// Whether the device is locked against local control, if reported.
  final bool? isLocked;
}

/// Formats a MAC as lowercase colon-separated hex.
String formatBroadlinkMac(List<int> mac) =>
    mac.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join(':');

// ---------------------------------------------------------------------------
// IR payload codec
// ---------------------------------------------------------------------------

/// First byte of an IR payload (0xb2 / 0xd7 are RF and not handled here).
const int broadlinkIrMarker = 0x26;

/// Length of the IR payload header (marker, repeat, LE length).
const int broadlinkIrHeaderLength = 4;

/// One Broadlink timing unit in microseconds: 8192/269 (about 30.45 us).
const double broadlinkTickUs = 8192 / 269;

/// Largest value one encoded duration can hold, in units.
const int broadlinkMaxTicks = 0xffff;

/// The off time, in units, that ends every capture (about 101.5 ms), and
/// that is appended to a code which ends on a mark when no gap is given.
const int broadlinkTrailerTicks = 0x0d05;

/// Carrier assumed for captures; the receiver cannot measure it.
const int broadlinkLearnCarrierHz = 38000;

/// Converts microseconds to units, rounding to nearest and never below 1
/// (a 0 would read as the long-value escape). Throws [ArgumentError] for
/// non-positive input or values above [broadlinkMaxTicks] units.
int broadlinkUsToTicks(int us) {
  if (us <= 0) throw ArgumentError.value(us, 'us', 'must be positive');
  // round(us * 269 / 8192) in integer arithmetic.
  final t = (us * 269 + 4096) ~/ 8192;
  if (t > broadlinkMaxTicks) {
    throw ArgumentError.value(us, 'us', 'exceeds $broadlinkMaxTicks units');
  }
  return t < 1 ? 1 : t;
}

/// Converts units to whole microseconds, rounding to nearest.
int broadlinkTicksToUs(int ticks) => (ticks * 8192 + 134) ~/ 269;

/// An IR code in device units, as carried by send-data and check-data.
final class BroadlinkIrCode {
  /// Creates a code from durations in units, mark first.
  BroadlinkIrCode({required List<int> ticks, this.repeat = 0})
    : ticks = List.unmodifiable(ticks) {
    if (repeat < 0 || repeat > 0xff) {
      throw ArgumentError.value(repeat, 'repeat', 'must be 0..255');
    }
    for (final t in ticks) {
      if (t < 1 || t > broadlinkMaxTicks) {
        throw ArgumentError.value(t, 'ticks', 'must be 1..$broadlinkMaxTicks');
      }
    }
  }

  /// Builds a code from microsecond [durationsUs] (mark first). When the
  /// count is odd (the code ends on a mark) an off time is appended:
  /// [trailingGapUs] if given, else [broadlinkTrailerTicks].
  factory BroadlinkIrCode.fromDurations(
    List<int> durationsUs, {
    int repeat = 0,
    int? trailingGapUs,
  }) {
    final ticks = [for (final d in durationsUs) broadlinkUsToTicks(d)];
    if (ticks.length.isOdd) {
      ticks.add(
        trailingGapUs == null
            ? broadlinkTrailerTicks
            : broadlinkUsToTicks(trailingGapUs),
      );
    }
    return BroadlinkIrCode(ticks: ticks, repeat: repeat);
  }

  /// Parses an IR payload. Trailing bytes after the declared length (zero
  /// padding) are ignored. Throws [BroadlinkFormatException] when the
  /// marker is not IR, the declared length overruns the buffer, a long
  /// value is cut off, a duration is zero, or there are no durations.
  static BroadlinkIrCode decode(List<int> payload) {
    if (payload.length < broadlinkIrHeaderLength) {
      throw BroadlinkFormatException(
        'IR payload is ${payload.length} bytes; at least 4 expected',
      );
    }
    final marker = payload[0] & 0xff;
    if (marker != broadlinkIrMarker) {
      throw BroadlinkFormatException(
        'payload type is 0x${marker.toRadixString(16)}, not IR (0x26)',
      );
    }
    final declared = _u16le(payload, 2);
    final end = broadlinkIrHeaderLength + declared;
    if (end > payload.length) {
      throw BroadlinkFormatException(
        'IR payload declares $declared bytes; only '
        '${payload.length - broadlinkIrHeaderLength} present',
      );
    }
    final ticks = <int>[];
    var i = broadlinkIrHeaderLength;
    while (i < end) {
      var v = payload[i++] & 0xff;
      if (v == 0) {
        if (i + 2 > end) {
          throw const BroadlinkFormatException(
            'IR payload ends inside a long duration',
          );
        }
        v = ((payload[i] & 0xff) << 8) | (payload[i + 1] & 0xff);
        i += 2;
        if (v == 0) {
          throw const BroadlinkFormatException(
            'IR payload has a zero duration',
          );
        }
      }
      ticks.add(v);
    }
    if (ticks.isEmpty) {
      throw const BroadlinkFormatException('IR payload has no durations');
    }
    return BroadlinkIrCode(ticks: ticks, repeat: payload[1] & 0xff);
  }

  /// Durations in device units, mark first.
  final List<int> ticks;

  /// Extra transmissions the device adds after the first (byte 1).
  final int repeat;

  /// Durations in whole microseconds.
  List<int> get durationsUs => [for (final t in ticks) broadlinkTicksToUs(t)];

  /// Size of [encode]'s output without building it.
  int get encodedLength {
    var n = broadlinkIrHeaderLength;
    for (final t in ticks) {
      n += t > 0xff ? 3 : 1;
    }
    return n;
  }

  /// Encodes the payload: marker, repeat, LE length, then each duration as
  /// one byte, or 0x00 and a big-endian 16-bit value when above 255.
  Uint8List encode() {
    final dataLength = encodedLength - broadlinkIrHeaderLength;
    if (dataLength > 0xffff) {
      throw StateError('IR payload of $dataLength bytes exceeds 65535');
    }
    final out = Uint8List(encodedLength);
    out[0] = broadlinkIrMarker;
    out[1] = repeat;
    _put16le(out, 2, dataLength);
    var i = broadlinkIrHeaderLength;
    for (final t in ticks) {
      if (t > 0xff) {
        out[i] = 0;
        out[i + 1] = t >> 8;
        out[i + 2] = t & 0xff;
        i += 3;
      } else {
        out[i++] = t;
      }
    }
    return out;
  }
}

/// Converts a captured IR payload into an [IrSignal]: carrier
/// [broadlinkLearnCarrierHz], whole-microsecond durations, mark first, with
/// the trailing gap (the capture's timeout off time) removed so the frame
/// ends on a mark. Throws [BroadlinkFormatException] for a malformed
/// payload.
IrSignal broadlinkCaptureToSignal(List<int> payload) {
  final durations = BroadlinkIrCode.decode(payload).durationsUs;
  if (durations.length.isEven) durations.removeLast();
  if (durations.isEmpty) {
    throw const BroadlinkFormatException('capture has no marks');
  }
  return IrSignal(carrierHz: broadlinkLearnCarrierHz, durationsUs: durations);
}
