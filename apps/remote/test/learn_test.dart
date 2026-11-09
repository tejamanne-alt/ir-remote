// Learning: a learn stream that ends before a capture, and the backstop that
// keeps a capture raw unless re-encoding reproduces its first frame.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/ui/learn/learn_screen.dart';

import 'helpers.dart';

/// A hub whose learn stream the test controls.
final class _Learner implements IrTransport {
  StreamController<LearnedSignal>? controller;
  int sessions = 0;

  @override
  String get id => 'learner';

  @override
  String get displayName => 'Learner';

  @override
  TransportKind get kind => TransportKind.espBridge;

  @override
  TransportCapabilities get caps => const TransportCapabilities(
    carrierRangesHz: [CarrierRange(30000, 60000)],
    maxPatternUs: 2000000,
    canLearn: true,
    latencyClass: LatencyClass.lan,
  );

  @override
  Stream<LearnedSignal>? learn() {
    sessions++;
    return (controller = StreamController<LearnedSignal>()).stream;
  }

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async =>
      const TransmitSent(elapsed: Duration.zero);

  @override
  Future<HealthStatus> health() async => Healthy(checkedAt: DateTime.now());

  @override
  Future<void> dispose() async => controller?.close();
}

/// An NEC1 frame followed, with only short spaces, by more pulses: the
/// start of a longer frame (for example an AC state frame).
IrSignal _longerThanNec() {
  final nec = const Nec1().encode({'D': 4, 'F': 8});
  return IrSignal(
    carrierHz: 38000,
    durationsUs: [
      ...nec.durationsUs,
      for (var i = 0; i < 16; i++) ...[560, i.isEven ? 560 : 1690],
      560,
    ],
  );
}

void main() {
  testWidgets('a learn session that ends before a capture fails with a retry', (
    tester,
  ) async {
    final learner = _Learner();
    final (s, _) = await buildServices(extraTransports: [learner]);
    await tester.runAsync(
      () => s.devices.save(
        SavedDevice(
          id: 'g',
          name: 'Custom',
          category: DeviceCategory.generic,
          createdAt: DateTime.utc(2026, 11, 9),
        ),
      ),
    );
    await pumpApp(tester, s);
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const LearnScreen(deviceId: 'g'),
          ),
        );
    await settle(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Waiting for a signal…'), findsOneWidget);

    // The bridge sent learn_stopped / the socket closed.
    await learner.controller!.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(
        'The hub stopped listening before a signal arrived. '
        'Try again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(learner.sessions, 2);
    expect(find.text('Waiting for a signal…'), findsOneWidget);
    await disposeServices(tester, s);
  });

  test('a capture that only starts with a valid NEC frame is saved raw', () {
    final capture = _longerThanNec();
    final k = keyFromCapture('custom:Cool', 'Cool', capture);
    expect(k.protocol, isNull);
    expect(k.signal, capture);
    expect(decodeCapture(capture), isNull);
  });

  test('the backstop holds even when a decoder matches a prefix', () {
    // Independent of the decoders: a decode that names NEC1 for the longer
    // capture does not reproduce its first frame, so it is not used.
    final decoded = DecodedCommand(
      protocolId: 'NEC1',
      params: const Nec1().normalize({'D': 4, 'F': 8}),
      consumed: 67,
    );
    expect(reproducesFirstFrame(_longerThanNec(), decoded), isFalse);

    final nec = const Nec1().encode({'D': 4, 'F': 8});
    // The frame alone, the frame with its ditto after the 40 ms gap, and
    // the frame with every timing 20% long are all reproduced.
    expect(reproducesFirstFrame(nec, decoded), isTrue);
    expect(
      reproducesFirstFrame(
        IrSignal(carrierHz: 38000, durationsUs: nec.flatten(repeats: 1)),
        decoded,
      ),
      isTrue,
    );
    expect(
      reproducesFirstFrame(
        IrSignal(
          carrierHz: 38000,
          durationsUs: [for (final d in nec.durationsUs) d * 6 ~/ 5],
        ),
        decoded,
      ),
      isTrue,
    );
    // One duration 40% off is not.
    final off = [...nec.durationsUs];
    off[5] = off[5] * 7 ~/ 5;
    expect(
      reproducesFirstFrame(
        IrSignal(carrierHz: 38000, durationsUs: off),
        decoded,
      ),
      isFalse,
    );
  });

  test('a clean NEC capture is still saved as the protocol', () {
    final nec = const Nec1().encode({'D': 4, 'F': 8});
    // Frame and ditto, as a hub captures a short press.
    final capture = IrSignal(
      carrierHz: 38000,
      durationsUs: nec.flatten(repeats: 1),
    );
    final k = keyFromCapture('custom:Power', 'Power', capture);
    expect(k.protocol, 'NEC1');
    expect(k.signal, nec);
  });
}
