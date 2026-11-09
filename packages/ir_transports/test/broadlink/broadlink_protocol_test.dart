// Protocol vectors for the Broadlink packet layer.
//
// Expected bytes were derived independently with Python's `cryptography`
// package from python-broadlink's protocol.md (MIT,
// https://github.com/mjg59/python-broadlink at
// 730853e5faf2cf979596662faf9def2b1f8fee6d), not produced by this Dart
// code. The RM command framing vectors are the oracle fixtures of the
// DAB-LABS fork (tests/oracle/fixtures.json at
// 6c6567ddeba8905537e0049a1343ebd0e5e165a2, MIT).

import 'dart:math';
import 'dart:typed_data';

import 'package:ir_transports/src/broadlink/broadlink_protocol.dart';
import 'package:test/test.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

String toHex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

const mac = [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff];
final sessionKey = hex('00112233445566778899aabbccddeeff');

void main() {
  group('checksum', () {
    test('starts at 0xbeaf and adds bytes', () {
      expect(broadlinkChecksum(const []), 0xbeaf);
      expect(broadlinkChecksum(const [1, 2, 3]), 0xbeb5);
    });

    test('wraps at 16 bits', () {
      // 0xbeaf + 65 * 0xff + 0x92 == 0x10000.
      expect(broadlinkChecksum([...List.filled(65, 0xff), 0x92]), 0);
    });
  });

  group('AES-128-CBC', () {
    test('matches FIPS-197 C.1 (first CBC block = AES(P xor IV))', () {
      final key = Uint8List.fromList(List.generate(16, (i) => i));
      final p = hex('00112233445566778899aabbccddeeff');
      final xored = [for (var i = 0; i < 16; i++) p[i] ^ broadlinkIv[i]];
      expect(
        toHex(BroadlinkCipher(key).encrypt(xored)),
        '69c4e0d86a7b0430d8cdb78070b4c55a',
      );
    });

    test('initial key and IV match the derived vector', () {
      final plain = List.generate(32, (i) => i);
      expect(
        toHex(BroadlinkCipher.initial().encrypt(plain)),
        '6652475b5619177997b8941ecc2fbf7a7b1c95d35d6519397297d41d0a82eb11',
      );
    });

    test('decrypt(encrypt(x)) is x zero-padded', () {
      final rnd = Random(7);
      final cipher = BroadlinkCipher(sessionKey);
      for (var n = 0; n < 70; n++) {
        final x = List.generate(n, (_) => rnd.nextInt(256));
        final padded = [...x, ...List.filled((16 - n % 16) % 16, 0)];
        expect(cipher.decrypt(cipher.encrypt(x)), padded);
      }
    });

    test('rejects ciphertext that is not whole blocks', () {
      expect(
        () => BroadlinkCipher.initial().decrypt(Uint8List(17)),
        throwsA(isA<BroadlinkDecryptException>()),
      );
    });
  });

  group('frames', () {
    test('auth payload layout', () {
      expect(
        toHex(buildBroadlinkAuthPayload()),
        '00000000313131313131313131313131'
        '31313131000000000000000000000100'
        '00000000000000000000000000010000'
        '5465737420310000000000000000000000000000000000000000000000000000',
      );
    });

    test('auth request frame matches the derived vector', () {
      final frame = buildBroadlinkFrame(
        packetType: BroadlinkPacketType.auth,
        devtype: 0x520c,
        count: 0x8001,
        mac: mac,
        sessionId: 0,
        payload: buildBroadlinkAuthPayload(),
        cipher: BroadlinkCipher.initial(),
      );
      expect(
        toHex(frame),
        '5aa5aa555aa5aa550000000000000000'
        '00000000000000000000000000000000'
        '1ef200000c5265000180ffeeddccbbaa'
        '00000000b2c30000453452e7f92eda95'
        '8344930835ef9a6d93b0b6da60530408'
        'ebba79410b080296f9f7cd7779b46f25'
        '13e2c5bbd4450e907fa1ba8fc5e01697'
        '76e2620824fff3f85f6f64f7120b1f724ff1b048b76e3e30',
      );
      // Header checksum 0xf21e and payload checksum 0xc3b2, by hand above.
      expect(frame[0x20] | frame[0x21] << 8, 0xf21e);
      expect(frame[0x34] | frame[0x35] << 8, 0xc3b2);
    });

    test('RM4 send-data frame matches the derived vector', () {
      final ir = BroadlinkIrCode.fromDurations(const [
        9000,
        4500,
        560,
      ], trailingGapUs: 100000).encode();
      final plain = buildBroadlinkRmCommand(
        BroadlinkFamily.rm4,
        BroadlinkRmCommand.sendData,
        ir,
      );
      expect(toHex(plain), '100002000000260008000001289412000cd4');
      final frame = buildBroadlinkFrame(
        packetType: BroadlinkPacketType.command,
        devtype: 0x520c,
        count: 0x9abc,
        mac: mac,
        sessionId: 0x01020304,
        payload: plain,
        cipher: BroadlinkCipher(sessionKey),
      );
      expect(
        toHex(frame),
        '5aa5aa555aa5aa550000000000000000'
        '00000000000000000000000000000000'
        'b8d900000c526a00bc9affeeddccbbaa'
        '040302019ec00000276d3b61679ff4c7'
        'fd2e665bee234705167759537d0042d2770cf966b1bf50e6',
      );
    });

    test('RM2 send-data frame matches the derived vector', () {
      final ir = hex('260008000001289412000cd4');
      final frame = buildBroadlinkFrame(
        packetType: BroadlinkPacketType.command,
        devtype: 0x2737,
        count: 0x8000,
        mac: mac,
        sessionId: 7,
        payload: buildBroadlinkRmCommand(
          BroadlinkFamily.rm2,
          BroadlinkRmCommand.sendData,
          ir,
        ),
        cipher: BroadlinkCipher(sessionKey),
      );
      expect(
        toHex(frame),
        '5aa5aa555aa5aa550000000000000000'
        '00000000000000000000000000000000'
        '07d4000037276a000080ffeeddccbbaa'
        '070000008ec00000cb84ee53b6ba057282fa5ccdff38f47d',
      );
    });

    test('parses a derived auth reply', () {
      final frame = BroadlinkFrame.parse(
        hex(
          '5aa5aa555aa5aa550000000000000000'
          '00000000000000000000000000000000'
          'c2d600000c52e9030180ffeeddccbbaa'
          '0000000051c70000ab6b9010922d2225'
          '67b35644502c5bc384487229ac00013506e958bdcb31479f',
        ),
      );
      expect(frame.errorCode, 0);
      expect(frame.devtype, 0x520c);
      expect(frame.packetType, 0x03e9);
      expect(frame.count, 0x8001);
      expect(frame.mac, mac);
      final auth = BroadlinkAuthReply.parse(
        BroadlinkCipher.initial().decrypt(frame.encryptedPayload),
      );
      expect(auth.sessionId, 0x11223344);
      expect(auth.key, sessionKey);
    });

    test('reads a negative error code', () {
      final frame = BroadlinkFrame.parse(
        buildBroadlinkFrame(
          packetType: 0x3ee,
          devtype: 0x520c,
          count: 1,
          mac: mac,
          sessionId: 1,
          payload: const [],
          cipher: BroadlinkCipher(sessionKey),
          errorCode: BroadlinkErrorCode.controlIdError,
        ),
      );
      expect(frame.errorCode, -4012);
      expect(frame.encryptedPayload, isEmpty);
    });

    test('rejects short frames and bad checksums', () {
      expect(
        () => BroadlinkFrame.parse(Uint8List(0x2f)),
        throwsA(isA<BroadlinkFormatException>()),
      );
      final good = buildBroadlinkFrame(
        packetType: 0x3ee,
        devtype: 0x520c,
        count: 1,
        mac: mac,
        sessionId: 1,
        payload: const [1, 2, 3],
        cipher: BroadlinkCipher(sessionKey),
      );
      final bad = Uint8List.fromList(good)..[0x40] ^= 0x01;
      expect(
        () => BroadlinkFrame.parse(bad),
        throwsA(isA<BroadlinkFormatException>()),
      );
    });
  });

  group('RM command framing (fork oracle fixtures)', () {
    final code = hex('2600180012341234123412340d05');

    test('rm4 commands carry a length prefix', () {
      expect(
        toHex(buildBroadlinkRmCommand(BroadlinkFamily.rm4, 0x02, code)),
        '1200020000002600180012341234123412340d05',
      );
      expect(
        toHex(buildBroadlinkRmCommand(BroadlinkFamily.rm4, 0x03)),
        '040003000000',
      );
      expect(
        toHex(buildBroadlinkRmCommand(BroadlinkFamily.rm4, 0x04)),
        '040004000000',
      );
    });

    test('rm2 commands are a bare 32-bit code', () {
      expect(
        toHex(buildBroadlinkRmCommand(BroadlinkFamily.rm2, 0x02, code)),
        '020000002600180012341234123412340d05',
      );
      expect(
        toHex(buildBroadlinkRmCommand(BroadlinkFamily.rm2, 0x03)),
        '03000000',
      );
    });

    test('unwraps replies', () {
      expect(
        toHex(
          unwrapBroadlinkRmReply(
            BroadlinkFamily.rm4,
            hex('1200000000002600180012341234123412340d05'),
          ),
        ),
        '2600180012341234123412340d05',
      );
      expect(
        toHex(
          unwrapBroadlinkRmReply(
            BroadlinkFamily.rm2,
            hex('010000002600180012341234123412340d05'),
          ),
        ),
        '2600180012341234123412340d05',
      );
      expect(
        unwrapBroadlinkRmReply(BroadlinkFamily.rm4, hex('040000000000')),
        isEmpty,
      );
    });

    test('an inconsistent rm4 length reads as a decrypt failure', () {
      for (final bad in ['ffff00000000', '0300000000000000', '0100']) {
        expect(
          () => unwrapBroadlinkRmReply(BroadlinkFamily.rm4, hex(bad)),
          throwsA(isA<BroadlinkDecryptException>()),
          reason: bad,
        );
      }
    });
  });

  group('hello', () {
    test('request matches the derived vector', () {
      final p = buildBroadlinkHelloPacket(
        now: DateTime.utc(2026, 11, 9, 14, 37),
        localIp: const [192, 168, 1, 23],
        localPort: 54321,
      );
      expect(
        toHex(p),
        '000000000000000000000000ea07250e'
        '1a01090b000000001701a8c031d400008dc20000000006000000000000000000',
      );
    });

    test('parses a reply', () {
      final r = Uint8List(0x80);
      r[0x34] = 0x0c;
      r[0x35] = 0x52;
      r.setRange(0x3a, 0x40, mac.reversed);
      r.setRange(0x40, 0x46, 'Living'.codeUnits);
      r[0x7f] = 1;
      final hello = BroadlinkHelloReply.parse(r);
      expect(hello.devtype, 0x520c);
      expect(hello.mac, mac);
      expect(hello.name, 'Living');
      expect(hello.isLocked, isTrue);
      expect(formatBroadlinkMac(hello.mac), 'aa:bb:cc:dd:ee:ff');
    });

    test('optional fields are absent on a short reply', () {
      final hello = BroadlinkHelloReply.parse(Uint8List(0x40));
      expect(hello.name, isNull);
      expect(hello.isLocked, isNull);
      expect(
        () => BroadlinkHelloReply.parse(Uint8List(0x3f)),
        throwsA(isA<BroadlinkFormatException>()),
      );
    });
  });

  group('models', () {
    test('known RM devtypes map to their framing', () {
      expect(broadlinkModelFor(0x520c)?.family, BroadlinkFamily.rm4);
      expect(broadlinkModelFor(0x520c)?.name, 'RM4 mini');
      expect(broadlinkModelFor(0x6026)?.name, 'RM4 pro');
      expect(broadlinkModelFor(0x2737)?.family, BroadlinkFamily.rm2);
      expect(broadlinkModelFor(0x272a)?.family, BroadlinkFamily.rm2);
      expect(broadlinkModelFor(0x5f36)?.family, BroadlinkFamily.rm4);
    });

    test('non-RM devtypes are unknown', () {
      expect(broadlinkModelFor(0x2711), isNull); // SP2 plug
      expect(broadlinkModelFor(0x0000), isNull);
    });
  });

  group('IR timing', () {
    test('unit is 8192/269 us', () {
      expect(broadlinkTickUs, closeTo(30.4535, 0.0001));
    });

    test('protocol.md worked example within one unit', () {
      // 8920 us -> 0x124 and 4450 us -> 0x92 in protocol.md (truncating);
      // rounding to nearest lands within one unit.
      expect(broadlinkUsToTicks(8920), 293);
      expect(broadlinkUsToTicks(4450), 146);
      expect((broadlinkUsToTicks(8920) - 0x124).abs(), lessThanOrEqualTo(1));
      expect((broadlinkUsToTicks(4450) - 0x92).abs(), lessThanOrEqualTo(1));
    });

    test('units -> us -> units is the identity for every value', () {
      for (var t = 1; t <= broadlinkMaxTicks; t++) {
        final back = broadlinkUsToTicks(broadlinkTicksToUs(t));
        if (back != t) fail('tick $t came back as $back');
      }
    });

    test('us -> units -> us stays within one unit', () {
      for (var us = 1; us <= 150000; us++) {
        final back = broadlinkTicksToUs(broadlinkUsToTicks(us));
        if ((back - us).abs() > broadlinkTickUs) {
          fail('$us us came back as $back us');
        }
      }
    });

    test('never encodes a zero unit', () {
      expect(broadlinkUsToTicks(1), 1);
      expect(broadlinkUsToTicks(15), 1);
      expect(() => broadlinkUsToTicks(0), throwsArgumentError);
      expect(() => broadlinkUsToTicks(2000000), throwsArgumentError);
    });
  });

  group('IR payload codec', () {
    test('encodes the derived vector', () {
      final code = BroadlinkIrCode.fromDurations(const [
        9000,
        4500,
        560,
      ], trailingGapUs: 100000);
      expect(toHex(code.encode()), '260008000001289412000cd4');
      expect(code.encodedLength, 12);
    });

    test('appends the 0x00 0x0d 0x05 trailer to a code ending on a mark', () {
      final bytes = BroadlinkIrCode.fromDurations(const [560]).encode();
      expect(toHex(bytes), '2600040012000d05');
    });

    test('even-length durations are encoded as given', () {
      final bytes = BroadlinkIrCode.fromDurations(const [560, 560]).encode();
      expect(toHex(bytes), '260002001212');
    });

    test('payload -> durations -> payload is identical', () {
      final rnd = Random(11);
      for (var i = 0; i < 500; i++) {
        final n = 2 * (1 + rnd.nextInt(150));
        final ticks = [
          for (var j = 0; j < n; j++)
            rnd.nextInt(4) == 0
                ? 256 + rnd.nextInt(broadlinkMaxTicks - 255)
                : 1 + rnd.nextInt(255),
        ];
        final payload = BroadlinkIrCode(ticks: ticks).encode();
        final decoded = BroadlinkIrCode.decode(payload);
        expect(decoded.ticks, ticks);
        final again = BroadlinkIrCode.fromDurations(decoded.durationsUs);
        expect(again.encode(), payload);
        // Zero padding after the declared length is ignored.
        final padded = [...payload, ...List.filled(13, 0)];
        expect(BroadlinkIrCode.decode(padded).ticks, ticks);
      }
    });

    test('us -> payload -> us stays within one unit', () {
      final rnd = Random(12);
      for (var i = 0; i < 500; i++) {
        final n = 1 + 2 * rnd.nextInt(60);
        final us = [for (var j = 0; j < n; j++) 1 + rnd.nextInt(150000)];
        final back = BroadlinkIrCode.decode(
          BroadlinkIrCode.fromDurations(us).encode(),
        ).durationsUs;
        expect(back.length, us.length + 1); // trailer appended
        for (var j = 0; j < us.length; j++) {
          expect((back[j] - us[j]).abs(), lessThanOrEqualTo(broadlinkTickUs));
        }
      }
    });

    test('keeps the repeat byte', () {
      final code = BroadlinkIrCode(ticks: const [20, 20], repeat: 3);
      expect(BroadlinkIrCode.decode(code.encode()).repeat, 3);
    });

    test('rejects malformed payloads with a format exception', () {
      for (final bad in [
        '',
        '260000', // short header
        'b20002001212', // RF marker
        '260005001212', // length overruns
        '260002000012', // long value cut off
        '26000300000000', // zero duration
        '26000000', // no durations
      ]) {
        expect(
          () => BroadlinkIrCode.decode(hex(bad)),
          throwsA(isA<BroadlinkFormatException>()),
          reason: bad,
        );
      }
    });
  });

  group('captures', () {
    test('become a 38 kHz mark-first signal without the trailing gap', () {
      // NEC-like capture: leader, two bits, stop mark, 0x0d05 trailer.
      final capture = BroadlinkIrCode(
        ticks: const [296, 148, 18, 18, 18, 55, 18, broadlinkTrailerTicks],
      ).encode();
      final signal = broadlinkCaptureToSignal([...capture, 0, 0, 0, 0]);
      expect(signal.carrierHz, 38000);
      expect(signal.durationsUs, [9014, 4507, 548, 548, 548, 1675, 548]);
      expect(signal.durationsUs.length.isOdd, isTrue);
      expect(signal.repeat, isNull);
    });

    test('a capture that already ends on a mark is kept whole', () {
      final capture = BroadlinkIrCode(ticks: const [20, 20, 20]).encode();
      expect(broadlinkCaptureToSignal(capture).durationsUs, [609, 609, 609]);
    });

    test('a capture with no marks is an error', () {
      final capture = BroadlinkIrCode(ticks: const [20]).encode();
      // One duration (a mark) is fine; a lone pair strips to one mark.
      expect(broadlinkCaptureToSignal(capture).durationsUs, [609]);
      expect(
        () => broadlinkCaptureToSignal(hex('26000000')),
        throwsA(isA<BroadlinkFormatException>()),
      );
    });
  });
}
