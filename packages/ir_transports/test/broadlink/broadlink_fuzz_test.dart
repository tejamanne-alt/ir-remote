// Fuzz: random and mutated packets through every Broadlink parser. The
// only exception allowed out of a parser is BroadlinkFormatException (or
// its subtype BroadlinkDecryptException); anything else fails the test.
//
// Protocol per the MIT-licensed python-broadlink: mjg59/python-broadlink at
// 730853e5faf2cf979596662faf9def2b1f8fee6d and the DAB-LABS fork at
// 6c6567ddeba8905537e0049a1343ebd0e5e165a2; see the header of
// lib/src/broadlink/broadlink_protocol.dart for what each specifies.

import 'dart:math';
import 'dart:typed_data';

import 'package:ir_transports/src/broadlink/broadlink_protocol.dart';
import 'package:test/test.dart';

const iterations = 10000;

/// Runs [parse] and fails on anything but success or a format error.
void survive(String what, List<int> input, void Function() parse) {
  try {
    parse();
  } on BroadlinkFormatException {
    // Expected for malformed input.
  } on Object catch (e, st) {
    fail('$what threw for ${_hex(input)}: $e\n$st');
  }
}

String _hex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

Uint8List mutate(Random rnd, Uint8List seed) {
  final b = Uint8List.fromList(seed);
  switch (rnd.nextInt(5)) {
    case 0: // flip a few bytes
      for (var i = 0; i < 1 + rnd.nextInt(4) && b.isNotEmpty; i++) {
        b[rnd.nextInt(b.length)] = rnd.nextInt(256);
      }
      return b;
    case 1: // truncate
      return Uint8List.sublistView(b, 0, rnd.nextInt(b.length + 1));
    case 2: // extend with garbage
      return Uint8List.fromList([
        ...b,
        for (var i = 0; i < rnd.nextInt(40); i++) rnd.nextInt(256),
      ]);
    case 3: // set length-ish fields to extremes
      if (b.length > 4) {
        b[2] = rnd.nextBool() ? 0xff : rnd.nextInt(256);
        b[3] = rnd.nextBool() ? 0xff : rnd.nextInt(256);
      }
      return b;
    default: // fully random
      return Uint8List.fromList([
        for (var i = 0; i < rnd.nextInt(300); i++) rnd.nextInt(256),
      ]);
  }
}

/// Fixes the header checksum so mutated frames reach the deeper parsers.
Uint8List fixChecksum(Uint8List b) {
  if (b.length < broadlinkMinFrameLength) return b;
  b[0x20] = 0;
  b[0x21] = 0;
  final sum = broadlinkChecksum(b);
  b[0x20] = sum & 0xff;
  b[0x21] = sum >> 8;
  return b;
}

void main() {
  final key = Uint8List.fromList(List.generate(16, (i) => i * 7));
  final cipher = BroadlinkCipher(key);
  const mac = [1, 2, 3, 4, 5, 6];

  test('$iterations reply frames through frame, auth and RM parsers', () {
    final rnd = Random(20261109);
    final seeds = [
      for (final family in BroadlinkFamily.values)
        buildBroadlinkFrame(
          packetType: 0x3ee,
          devtype: 0x520c,
          count: 0x8123,
          mac: mac,
          sessionId: 9,
          payload: buildBroadlinkRmCommand(
            family,
            BroadlinkRmCommand.checkData,
            BroadlinkIrCode(ticks: const [296, 148, 18, 3333]).encode(),
          ),
          cipher: cipher,
        ),
      buildBroadlinkFrame(
        packetType: 0x3e9,
        devtype: 0x520c,
        count: 1,
        mac: mac,
        sessionId: 0,
        payload: [1, 0, 0, 0, ...key],
        cipher: BroadlinkCipher.initial(),
      ),
    ];
    for (var i = 0; i < iterations; i++) {
      var input = mutate(rnd, seeds[rnd.nextInt(seeds.length)]);
      if (rnd.nextBool()) input = fixChecksum(input);
      survive('frame pipeline', input, () {
        final frame = BroadlinkFrame.parse(input);
        survive('auth reply', input, () {
          BroadlinkAuthReply.parse(
            BroadlinkCipher.initial().decrypt(frame.encryptedPayload),
          );
        });
        for (final family in BroadlinkFamily.values) {
          survive('rm reply ${family.name}', input, () {
            final data = unwrapBroadlinkRmReply(
              family,
              cipher.decrypt(frame.encryptedPayload),
            );
            survive('capture', data, () => broadlinkCaptureToSignal(data));
          });
        }
      });
      // Plaintext RM replies, mutated directly (no encryption layer).
      final plain = mutate(
        rnd,
        Uint8List.fromList([0x12, 0, 0, 0, 0, 0, 0x26]),
      );
      for (final family in BroadlinkFamily.values) {
        survive(
          'rm unwrap',
          plain,
          () => unwrapBroadlinkRmReply(family, plain),
        );
      }
      survive('hello reply', input, () => BroadlinkHelloReply.parse(input));
    }
  });

  test('$iterations IR payloads through the IR decoder', () {
    final rnd = Random(38000);
    for (var i = 0; i < iterations; i++) {
      final ticks = [
        for (var j = 0; j < 1 + rnd.nextInt(80); j++)
          rnd.nextInt(5) == 0
              ? 256 + rnd.nextInt(0xff00)
              : 1 + rnd.nextInt(255),
      ];
      final input = mutate(rnd, BroadlinkIrCode(ticks: ticks).encode());
      survive('ir decode', input, () {
        final code = BroadlinkIrCode.decode(input);
        // Whatever decodes must re-encode and decode to the same units.
        expect(BroadlinkIrCode.decode(code.encode()).ticks, code.ticks);
      });
      survive('capture', input, () => broadlinkCaptureToSignal(input));
    }
  });

  test('random hello replies', () {
    final rnd = Random(80);
    for (var i = 0; i < iterations; i++) {
      final input = Uint8List.fromList([
        for (var j = 0; j < rnd.nextInt(200); j++) rnd.nextInt(256),
      ]);
      survive('hello reply', input, () => BroadlinkHelloReply.parse(input));
    }
  });
}
