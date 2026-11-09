import 'dart:async';

import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:test/test.dart';

final _nec = const Nec1().encode({'D': 4, 'F': 8});

/// A transport whose transmit takes as long as the test says.
final class _SlowTransport implements IrTransport {
  _SlowTransport(
    this.delay, {
    this.kind = TransportKind.espBridge,
    this.id = 'slow',
  });

  final Duration delay;
  @override
  final TransportKind kind;
  @override
  final String id;
  int inFlight = 0;
  int maxInFlight = 0;
  final List<int> order = [];
  bool throwOnSend = false;
  bool throwOnHealth = false;

  @override
  String get displayName => id;

  @override
  TransportCapabilities get caps => EspBridgeTransport.defaultCaps;

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (throwOnSend) throw StateError('boom');
      await Future<void>.delayed(delay);
      order.add(repeats);
      return TransmitSent(elapsed: delay);
    } finally {
      inFlight--;
    }
  }

  @override
  Stream<LearnedSignal>? learn() => null;

  @override
  Future<HealthStatus> health() async {
    if (throwOnHealth) throw StateError('health boom');
    await Future<void>.delayed(delay);
    return Healthy(checkedAt: DateTime.now());
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('SerialQueue', () {
    test('runs tasks strictly in order, one at a time', () async {
      final q = SerialQueue();
      final log = <String>[];
      var running = 0;
      Future<int> task(int i) => q.run(() async {
        running++;
        expect(running, 1);
        log.add('start $i');
        await Future<void>.delayed(Duration(milliseconds: 5 - i));
        log.add('end $i');
        running--;
        return i;
      });
      final results = await Future.wait([task(0), task(1), task(2)]);
      expect(results, [0, 1, 2]);
      expect(log, ['start 0', 'end 0', 'start 1', 'end 1', 'start 2', 'end 2']);
    });

    test('a failing task does not block the next one', () async {
      final q = SerialQueue();
      final a = q.run<int>(() async => throw StateError('x'));
      final b = q.run(() async => 2);
      await expectLater(a, throwsStateError);
      expect(await b, 2);
      expect(q.isBusy, isFalse);
    });

    test('refuses work beyond its capacity', () async {
      final q = SerialQueue(capacity: 2);
      final gate = Completer<void>();
      final futures = [
        for (var i = 0; i < 4; i++) q.run(() => gate.future.then((_) => i)),
      ];
      // One running + two waiting; the fourth is refused.
      await expectLater(futures[3], throwsA(isA<QueueFullException>()));
      expect(q.pending, 2);
      gate.complete();
      expect(await Future.wait(futures.take(3)), [0, 1, 2]);
      expect(const QueueFullException(2).toString(), contains('2'));
    });
  });

  group('QueuedTransport', () {
    test('presses never overlap on air', () async {
      final inner = _SlowTransport(const Duration(milliseconds: 5));
      final q = QueuedTransport(inner);
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) q.transmit(_nec, repeats: i),
      ]);
      expect(results.every((r) => r is TransmitSent), isTrue);
      expect(inner.maxInFlight, 1);
      expect(inner.order, [0, 1, 2, 3, 4]);
      expect(q.id, 'slow');
      expect(q.displayName, 'slow');
      expect(q.kind, TransportKind.espBridge);
      expect(q.caps, same(EspBridgeTransport.defaultCaps));
      expect(q.learn(), isNull);
    });

    test('a timeout answers the caller but still holds the queue', () async {
      final inner = _SlowTransport(const Duration(milliseconds: 60));
      final q = QueuedTransport(
        inner,
        timeout: const Duration(milliseconds: 20),
      );
      final first = q.transmit(_nec);
      final second = q.transmit(_nec);
      expect(await first, isA<TransmitTimeout>());
      expect(q.holdLimit, const Duration(milliseconds: 80));
      expect(await second, isA<TransmitTimeout>());
      expect(inner.maxInFlight, 1, reason: 'second must wait for the first');
    });

    test('exceptions become transportUnavailable and are recorded', () async {
      final records = <TransmitRecord>[];
      final inner = _SlowTransport(Duration.zero)..throwOnSend = true;
      final q = QueuedTransport(inner, onRecord: records.add);
      final r = await q.transmit(_nec);
      expect(r, isA<TransmitTransportUnavailable>());
      expect(records.single.result, same(r));
      final json = records.single.toJson();
      expect(json['carrierHz'], 38400);
      expect(json['transportKind'], 'espBridge');
      expect(json['result'], contains('transportUnavailable'));
    });

    test('a full backlog is rejected with a clear message', () async {
      final inner = _SlowTransport(const Duration(milliseconds: 20));
      final q = QueuedTransport(inner, capacity: 1);
      final results = await Future.wait([
        for (var i = 0; i < 3; i++) q.transmit(_nec),
      ]);
      expect(
        results.whereType<TransmitRejected>().single.detail,
        contains('too many presses'),
      );
      expect(q.pending, 0);
    });

    test('health never throws and honours the timeout', () async {
      final slow = QueuedTransport(
        _SlowTransport(const Duration(milliseconds: 50)),
        timeout: const Duration(milliseconds: 10),
      );
      expect(await slow.health(), isA<Unreachable>());
      final broken = QueuedTransport(
        _SlowTransport(Duration.zero)..throwOnHealth = true,
      );
      expect(await broken.health(), isA<Unreachable>());
    });
  });

  group('SimulatedTransport', () {
    test('records valid signals with their planned chunks', () async {
      final sim = SimulatedTransport();
      expect(await sim.transmit(_nec, repeats: 2), isA<TransmitSent>());
      expect(sim.sent.single.repeats, 2);
      expect(
        sim.sent.single.chunks.single.durationsUs,
        _nec.flatten(repeats: 2),
      );
    });

    test('rejects invalid signals, honours injected failures', () async {
      final sim = SimulatedTransport();
      final r = await sim.transmit(
        IrSignal(carrierHz: 455000, durationsUs: [1]),
      );
      expect((r as TransmitRejected).reason, RejectReason.carrierOutOfRange);
      sim.nextResult = const TransmitTimeout(Duration(seconds: 1));
      expect(await sim.transmit(_nec), isA<TransmitTimeout>());
      sim.offline = true;
      expect(await sim.transmit(_nec), isA<TransmitTransportUnavailable>());
      expect(await sim.health(), isA<Unreachable>());
      sim.offline = false;
      expect(await sim.health(), isA<Healthy>());
      expect(sim.sent, isEmpty);
    });

    test('learn delivers simulated captures', () async {
      final sim = SimulatedTransport(latency: const Duration(milliseconds: 1));
      final first = sim.learn()!.first;
      sim.simulateCapture(_nec);
      expect((await first).signal, _nec);
      sim.caps = const TransportCapabilities(
        carrierRangesHz: null,
        maxPatternUs: 2000000,
        canLearn: false,
        latencyClass: LatencyClass.local,
      );
      expect(sim.learn(), isNull);
      await sim.dispose();
    });
  });

  group('TransportRegistry', () {
    test('prefers chosen, then built-in, then last healthy hub', () async {
      var now = DateTime(2026, 11, 9, 10);
      final reg = TransportRegistry(clock: () => now);
      expect(reg.resolve(), isNull);
      await reg.register(SimulatedTransport());
      expect(reg.resolve()!.kind, TransportKind.simulated);

      final hubA = _SlowTransport(Duration.zero, id: 'hubA');
      final hubB = _SlowTransport(
        Duration.zero,
        id: 'hubB',
        kind: TransportKind.broadlink,
      );
      await reg.register(hubA);
      await reg.register(hubB);
      // No health yet: first hub not known to be down.
      expect(reg.resolve()!.id, 'hubA');
      await reg.checkHealth('hubA');
      now = now.add(const Duration(minutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await reg.checkHealth('hubB');
      expect(reg.resolve()!.id, 'hubB', reason: 'most recently healthy');
      expect(reg.healthOf('hubB'), isA<Healthy>());
      expect(reg.hubs.length, 2);

      await reg.register(
        _SlowTransport(Duration.zero, id: 'phone', kind: TransportKind.builtIn),
      );
      expect(reg.resolve()!.id, 'phone');
      expect(reg.builtIn!.id, 'phone');
      expect(reg.resolve(preferredId: 'hubA')!.id, 'hubA');
      expect(reg.resolve(preferredId: 'gone')!.id, 'phone');

      await reg.unregister('phone');
      expect(reg.builtIn, isNull);
      expect(await reg.checkHealth('phone'), isA<Unreachable>());
      await reg.checkAll();
      expect(reg.all.length, 3);
      await reg.dispose();
    });

    test('re-registering replaces and notifies', () async {
      final reg = TransportRegistry();
      final events = <void>[];
      final sub = reg.changes.listen(events.add);
      await reg.register(SimulatedTransport());
      await reg.register(SimulatedTransport());
      expect(reg.all.length, 1);
      expect(reg.byId('simulated'), isA<QueuedTransport>());
      await Future<void>.delayed(Duration.zero);
      expect(events.length, 2);
      await sub.cancel();
      await reg.dispose();
    });

    test('health checks finishing after dispose are ignored', () async {
      final reg = TransportRegistry();
      await reg.register(
        _SlowTransport(const Duration(milliseconds: 30), id: 'h'),
      );
      final pending = reg.checkHealth('h');
      await reg.dispose();
      expect(await pending, isA<HealthStatus>());
      await reg.dispose(); // idempotent
      await reg.register(SimulatedTransport());
      expect(reg.all, isEmpty);
    });

    test('hubs known to be down are skipped when nothing is healthy', () async {
      final reg = TransportRegistry();
      final down = _SlowTransport(Duration.zero, id: 'down')
        ..throwOnHealth = true;
      await reg.register(down);
      await reg.checkHealth('down');
      expect(reg.resolve(), isNull);
      await reg.dispose();
    });
  });
}
