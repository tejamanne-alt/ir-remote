// End-to-end tests of BroadlinkTransport against FakeBroadlinkDevice over
// UDP on 127.0.0.1.
//
// Protocol per the MIT-licensed python-broadlink: mjg59/python-broadlink at
// 730853e5faf2cf979596662faf9def2b1f8fee6d and the DAB-LABS fork at
// 6c6567ddeba8905537e0049a1343ebd0e5e165a2; see the header of
// lib/src/broadlink/broadlink_protocol.dart for what each specifies.

import 'dart:async';
import 'dart:typed_data';

import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/src/broadlink/broadlink_discovery.dart';
import 'package:ir_transports/src/broadlink/broadlink_protocol.dart';
import 'package:ir_transports/src/broadlink/broadlink_transport.dart';
import 'package:test/test.dart';

import 'fake_broadlink_device.dart';

const fast = BroadlinkTransportOptions(
  requestTimeout: Duration(milliseconds: 250),
  resendInterval: Duration(milliseconds: 80),
  learnTimeout: Duration(seconds: 2),
  learnPollInterval: Duration(milliseconds: 15),
  learnRearmInterval: Duration(seconds: 5),
  cancelLearningTimeout: Duration(milliseconds: 150),
);

/// NEC-shaped signal: 9 ms leader, a few bits, stop mark, NEC repeat frame.
IrSignal necLike({int carrierHz = 38000}) => IrSignal(
  carrierHz: carrierHz,
  durationsUs: const [9000, 4500, 560, 560, 560, 1690, 560],
  repeat: RepeatSpec(
    frameUs: const [9000, 2250, 560],
    leadInGapUs: 40000,
    gapUs: 96000,
  ),
);

void main() {
  late FakeBroadlinkDevice fake;
  late BroadlinkTransport transport;

  Future<BroadlinkTransport> open({
    BroadlinkTransportOptions options = fast,
    BroadlinkDeviceInfo? info,
  }) async {
    transport = BroadlinkTransport(device: info ?? fake.info, options: options);
    addTearDown(transport.dispose);
    return transport;
  }

  setUp(() async {
    fake = await FakeBroadlinkDevice.start();
    addTearDown(fake.close);
  });

  group('identity and caps', () {
    test('reports a LAN Broadlink transport keyed by MAC', () async {
      final t = await open();
      expect(t.kind, TransportKind.broadlink);
      expect(t.id, 'broadlink:aa:bb:cc:dd:ee:ff');
      expect(t.displayName, 'Fake RM4');
      expect(t.caps.carrierRangesHz, [const CarrierRange(35000, 41000)]);
      expect(t.caps.maxPatternUs, 2000000);
      expect(t.caps.maxDurations, 1397);
      expect(t.caps.canLearn, isTrue);
      expect(t.caps.latencyClass, LatencyClass.lan);
    });

    test('connect() says hello first', () async {
      final t = await BroadlinkTransport.connect(
        fake.address,
        port: fake.port,
        options: fast,
      );
      addTearDown(t.dispose);
      expect(t.device.devtype, 0x520c);
      expect(t.device.macString, 'aa:bb:cc:dd:ee:ff');
      expect(fake.hellos, 1);
    });

    test('connect() to a silent address throws a timeout', () async {
      fake.silent = true;
      await expectLater(
        BroadlinkTransport.connect(
          fake.address,
          port: fake.port,
          options: fast,
        ),
        throwsA(isA<BroadlinkTimeoutException>()),
      );
    });
  });

  group('transmit', () {
    test('authenticates and sends one flattened payload', () async {
      final t = await open();
      final signal = necLike();
      final result = await t.transmit(signal, repeats: 2);
      expect(result, isA<TransmitSent>());
      expect(fake.auths, 1);
      expect(fake.sentIr, hasLength(1));

      final payload = fake.sentIr.single;
      expect(payload[0], 0x26);
      expect(payload[1], 0, reason: 'repeat byte must be 0');
      final decoded = BroadlinkIrCode.decode(payload).durationsUs;
      final expected = [...signal.flatten(repeats: 2), 96000];
      expect(decoded, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(
          (decoded[i] - expected[i]).abs(),
          lessThanOrEqualTo(broadlinkTickUs),
        );
      }
    });

    test('reuses the session for later sends', () async {
      final t = await open();
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      expect(fake.auths, 1);
      expect(fake.sentIr, hasLength(2));
    });

    test('works with RM mini 3 (rm2 framing)', () async {
      await fake.close();
      fake = await FakeBroadlinkDevice.start(devtype: 0x2737, name: 'Mini');
      addTearDown(fake.close);
      final t = await open();
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      expect(fake.sentIr, hasLength(1));
      expect(BroadlinkIrCode.decode(fake.sentIr.single).ticks.first, 296);
    });

    test('rejects 56 kHz without sending any packet', () async {
      final t = await open();
      final result = await t.transmit(necLike(carrierHz: 56000));
      expect(result, isA<TransmitRejected>());
      expect(
        (result as TransmitRejected).reason,
        RejectReason.carrierOutOfRange,
      );
      expect(fake.requests, isEmpty);
    });

    test('accepts 36 kHz and 40 kHz signals unchanged on the wire', () async {
      final t = await open();
      for (final hz in [36000, 40000]) {
        expect(
          await t.transmit(necLike(carrierHz: hz)),
          isA<TransmitSent>(),
          reason: '$hz Hz',
        );
      }
    });

    test('rejects invalid durations and negative repeats', () async {
      final t = await open();
      final even = IrSignal(carrierHz: 38000, durationsUs: const [500, 500]);
      final r1 = await t.transmit(even);
      expect((r1 as TransmitRejected).reason, RejectReason.invalidDurations);
      final r2 = await t.transmit(necLike(), repeats: -1);
      expect((r2 as TransmitRejected).reason, RejectReason.invalidDurations);
      expect(fake.requests, isEmpty);
    });

    test('a silent device gives TransmitTimeout', () async {
      fake.silent = true;
      final t = await open();
      final result = await t.transmit(necLike());
      expect(result, isA<TransmitTimeout>());
      expect((result as TransmitTimeout).after, fast.requestTimeout);
      // Auth is idempotent and was resent within the timeout.
      expect(fake.requests.length, greaterThan(1));
    });

    test('send-data is never resent when the ack is missing', () async {
      fake.silentToCommands = true;
      final t = await open();
      final result = await t.transmit(necLike());
      expect(result, isA<TransmitTimeout>());
      expect(fake.countCommand(BroadlinkRmCommand.sendData), 1);
    });

    test('a hub send error is a hardwareError rejection', () async {
      fake.sendDataError = BroadlinkErrorCode.sendError;
      final t = await open();
      final result = await t.transmit(necLike());
      expect((result as TransmitRejected).reason, RejectReason.hardwareError);
    });

    test('splits into planned chunks and waits each gap', () async {
      final t = await open(
        options: const BroadlinkTransportOptions(
          requestTimeout: Duration(milliseconds: 250),
          maxIrPayloadBytes: 40,
        ),
      );
      final frame = List.filled(11, 2000);
      final signal = IrSignal(
        carrierHz: 38000,
        durationsUs: frame,
        repeat: RepeatSpec(frameUs: frame, leadInGapUs: 7000, gapUs: 7000),
      );
      final result = await t.transmit(signal, repeats: 4);
      expect(result, isA<TransmitSent>());
      // 5 frames of 11 durations; 35 durations (3 frames) fit 40 bytes.
      expect(fake.sentIr, hasLength(2));
      expect(BroadlinkIrCode.decode(fake.sentIr[0]).ticks, hasLength(36));
      expect(BroadlinkIrCode.decode(fake.sentIr[1]).ticks, hasLength(24));
      final sends = fake.requests
          .where((r) => r.command == BroadlinkRmCommand.sendData)
          .toList();
      // The first chunk is 33 x 2 ms + 2 x 7 ms = 80 ms on air, then a 7 ms
      // gap: the next send waits about 87 ms after the first, not just the
      // gap. The margin absorbs scheduling noise at the fake.
      expect(
        sends[1].at.difference(sends[0].at),
        greaterThanOrEqualTo(const Duration(milliseconds: 75)),
      );
    });

    test('falls back to one frame per payload when joined chunks overflow '
        'the byte budget', () async {
      final t = await open(
        options: const BroadlinkTransportOptions(
          requestTimeout: Duration(milliseconds: 250),
          maxIrPayloadBytes: 40,
        ),
      );
      final frame = List.filled(11, 600);
      final signal = IrSignal(
        carrierHz: 38000,
        durationsUs: frame,
        // 20 ms gaps need the 3-byte form, so 3 joined frames overflow.
        repeat: RepeatSpec(frameUs: frame, leadInGapUs: 20000, gapUs: 20000),
      );
      expect(await t.transmit(signal, repeats: 4), isA<TransmitSent>());
      expect(fake.sentIr, hasLength(5));
    });

    test('rejects a frame that cannot fit the byte budget', () async {
      final t = await open(
        options: const BroadlinkTransportOptions(maxIrPayloadBytes: 40),
      );
      final signal = IrSignal(
        carrierHz: 38000,
        durationsUs: List.filled(21, 10000), // 3 bytes each
      );
      final result = await t.transmit(signal);
      expect(
        (result as TransmitRejected).reason,
        RejectReason.tooManyDurations,
      );
      expect(fake.requests, isEmpty);
    });

    test('unknown devtypes are refused unless a family is forced', () async {
      final info = BroadlinkDeviceInfo(
        address: fake.address,
        port: fake.port,
        mac: fake.mac,
        devtype: 0x2711, // SP2 smart plug
      );
      final t = await open(info: info);
      expect(await t.transmit(necLike()), isA<TransmitTransportUnavailable>());
      expect(t.learn(), isNull);
      expect(t.caps.canLearn, isFalse);
      expect(fake.requests, isEmpty);

      final forced = BroadlinkTransport(
        device: info,
        options: const BroadlinkTransportOptions(
          requestTimeout: Duration(milliseconds: 250),
          familyOverride: BroadlinkFamily.rm4,
        ),
      );
      addTearDown(forced.dispose);
      expect(await forced.transmit(necLike()), isA<TransmitSent>());
    });

    test(
      'after dispose transmit is unavailable and health unreachable',
      () async {
        final t = await open();
        await t.dispose();
        expect(
          await t.transmit(necLike()),
          isA<TransmitTransportUnavailable>(),
        );
        expect(await t.health(), isA<Unreachable>());
      },
    );
  });

  group('re-auth', () {
    test('re-authenticates once when the hub reports an expired key', () async {
      final t = await open();
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      fake.rotateKey();
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      expect(fake.auths, 2);
      expect(fake.staleRejections, 1);
      expect(fake.sentIr, hasLength(2));
    });

    test('re-authenticates once when the reply cannot be decrypted', () async {
      fake.staleKeyReply = StaleKeyReply.encryptedWithNewKey;
      final t = await open();
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      fake.rotateKey();
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      expect(fake.auths, 2);
      expect(fake.staleRejections, 1);
      expect(fake.sentIr, hasLength(2));
    });

    test('gives up after one re-auth', () async {
      fake.alwaysExpired = true;
      final t = await open();
      final result = await t.transmit(necLike());
      expect((result as TransmitRejected).reason, RejectReason.refusedByHub);
      expect(fake.auths, 2);
      // Sent once with each key, refused both times, never transmitted.
      expect(fake.countCommand(BroadlinkRmCommand.sendData), 2);
      expect(fake.sentIr, isEmpty);
    });
  });

  group('health', () {
    test('Healthy with latency when the hub answers', () async {
      final t = await open();
      final h = await t.health();
      expect(h, isA<Healthy>());
      expect((h as Healthy).latency, isNotNull);
      expect(h.detail, contains('RM4 mini'));
      expect(t.isAuthenticated, isTrue);
      expect(fake.hellos, 1);
      expect(fake.auths, 1);
    });

    test('Unreachable when the hub is silent', () async {
      fake.silent = true;
      final t = await open();
      final h = await t.health();
      expect(h, isA<Unreachable>());
      expect(h.isUsable, isFalse);
    });

    test('Unreachable when nothing listens on the port', () async {
      final t = await open();
      await fake.close();
      expect(await t.health(), isA<Unreachable>());
    });

    test('Unreachable with a clear reason when the hub is locked', () async {
      await fake.close();
      fake = await FakeBroadlinkDevice.start(locked: true);
      addTearDown(fake.close);
      final t = await open();
      final h = await t.health();
      expect((h as Unreachable).reason, contains('locked'));
    });

    test('Unreachable when another device answers at the address', () async {
      final info = BroadlinkDeviceInfo(
        address: fake.address,
        port: fake.port,
        mac: const [1, 2, 3, 4, 5, 6],
        devtype: 0x520c,
      );
      final t = await open(info: info);
      final h = await t.health();
      expect((h as Unreachable).reason, contains('different device'));
    });
  });

  group('learn', () {
    final captureTicks = [296, 148, 18, 18, 18, 55, 18, broadlinkTrailerTicks];

    test('emits the capture and closes', () async {
      fake
        ..capture = BroadlinkIrCode(ticks: captureTicks).encode()
        ..pollsBeforeCapture = 3;
      final t = await open();
      final events = await t.learn()!.toList();
      expect(events, hasLength(1));
      final signal = events.single.signal;
      expect(signal.carrierHz, 38000);
      expect(signal.durationsUs, [9014, 4507, 548, 548, 548, 1675, 548]);
      expect(fake.countCommand(BroadlinkRmCommand.enterLearning), 1);
      expect(fake.countCommand(BroadlinkRmCommand.checkData), 4);
      // The hub left learning mode by itself; no cancel needed.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fake.countCommand(BroadlinkRmCommand.cancelLearning), 0);
    });

    test('works with RM mini 3 (rm2 framing, -10 while waiting)', () async {
      await fake.close();
      fake = await FakeBroadlinkDevice.start(devtype: 0x2737);
      addTearDown(fake.close);
      fake.capture = BroadlinkIrCode(ticks: captureTicks).encode();
      final t = await open();
      final events = await t.learn()!.toList();
      expect(events.single.signal.durationsUs, hasLength(7));
    });

    test('cancelling the subscription stops polling', () async {
      final t = await open();
      final sub = t.learn()!.listen((_) => fail('nothing was captured'));
      expect(
        await eventually(
          () => fake.countCommand(BroadlinkRmCommand.checkData) >= 2,
        ),
        isTrue,
      );
      await sub.cancel();
      final polls = fake.countCommand(BroadlinkRmCommand.checkData);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(fake.countCommand(BroadlinkRmCommand.checkData), polls);
      expect(
        await eventually(
          () => fake.countCommand(BroadlinkRmCommand.cancelLearning) == 1,
        ),
        isTrue,
      );
      expect(fake.learning, isFalse);
    });

    test('times out with a typed error', () async {
      final t = await open(
        options: const BroadlinkTransportOptions(
          requestTimeout: Duration(milliseconds: 250),
          learnTimeout: Duration(milliseconds: 150),
          learnPollInterval: Duration(milliseconds: 20),
          cancelLearningTimeout: Duration(milliseconds: 100),
        ),
      );
      await expectLater(
        t.learn(),
        emitsInOrder([emitsError(isA<BroadlinkTimeoutException>()), emitsDone]),
      );
      expect(
        await eventually(
          () => fake.countCommand(BroadlinkRmCommand.cancelLearning) == 1,
        ),
        isTrue,
      );
    });

    test('a silent hub surfaces as a stream error, not a crash', () async {
      fake.silent = true;
      final t = await open();
      await expectLater(
        t.learn(),
        emitsInOrder([emitsError(isA<BroadlinkTimeoutException>()), emitsDone]),
      );
    });

    test('a hub that refuses learning surfaces a device error', () async {
      fake.alwaysExpired = true;
      final t = await open();
      await expectLater(
        t.learn(),
        emitsInOrder([emitsError(isA<BroadlinkDeviceException>()), emitsDone]),
      );
    });

    test('an undecodable capture surfaces a format error', () async {
      fake.capture = Uint8List.fromList([0x26, 0, 9, 0, 1, 2]); // truncated
      final t = await open();
      await expectLater(
        t.learn(),
        emitsInOrder([emitsError(isA<BroadlinkFormatException>()), emitsDone]),
      );
    });

    test('re-arms learning after a transmit in the middle', () async {
      final t = await open();
      final events = t.learn()!.toList();
      expect(
        await eventually(
          () => fake.countCommand(BroadlinkRmCommand.checkData) >= 1,
        ),
        isTrue,
      );
      expect(await t.transmit(necLike()), isA<TransmitSent>());
      expect(
        await eventually(
          () => fake.countCommand(BroadlinkRmCommand.enterLearning) == 2,
        ),
        isTrue,
      );
      fake.capture = BroadlinkIrCode(ticks: captureTicks).encode();
      expect(await events, hasLength(1));
    });

    test('a second concurrent session is refused', () async {
      final t = await open();
      final first = t.learn()!.listen((_) {});
      addTearDown(first.cancel);
      await expectLater(
        t.learn(),
        emitsInOrder([emitsError(isA<BroadlinkStateException>()), emitsDone]),
      );
    });
  });
}
