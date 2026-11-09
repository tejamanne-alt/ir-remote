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
  HealthStatus Function()? healthResult;
  Duration disposeDelay = Duration.zero;
  bool disposed = false;

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
    return healthResult?.call() ?? Healthy(checkedAt: DateTime.now());
  }

  @override
  Future<void> dispose() async {
    await Future<void>.delayed(disposeDelay);
    disposed = true;
  }
}

IrTransport _innerOf(IrTransport? t) => (t! as QueuedTransport).inner;

void main() {
  group('isLanHost', () {
    test('accepts private, link-local and loopback addresses', () {
      for (final h in [
        '10.0.0.5',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.1.40',
        '169.254.10.2',
        '127.0.0.1',
        'fe80::1',
        'fd12:3456::1',
        '::1',
      ]) {
        expect(isLanHost(h), isTrue, reason: h);
      }
    });

    test('rejects public addresses and internet hostnames', () {
      for (final h in [
        '8.8.8.8',
        '172.32.0.1',
        '100.64.0.1',
        '2001:4860::8888',
        'example.com',
        'evil.local.example.com',
        // Names resolve later, possibly to an internet host.
        'irbridge-a1b2c3.local',
        'localhost',
        '::ffff:8.8.8.8',
        '',
        'not an address',
      ]) {
        expect(isLanHost(h), isFalse, reason: h);
      }
    });
  });

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
      // NEC is ~108 ms on air, so the caller's limit is 20 + 108 ms and the
      // queue is held for up to 80 + 108 ms; a 160 ms call lands between.
      final inner = _SlowTransport(const Duration(milliseconds: 160));
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

    test('the timeout grows with the signal on-air time', () async {
      // 40 ms of transmission against a 20 ms base timeout is not a timeout.
      final inner = _SlowTransport(const Duration(milliseconds: 40));
      final q = QueuedTransport(
        inner,
        timeout: const Duration(milliseconds: 20),
      );
      final long = IrSignal(
        carrierHz: 38000,
        durationsUs: [for (var i = 0; i < 9; i++) 6000],
      );
      expect(
        QueuedTransport.airTimeUs(long, 0),
        54000 + IrSignal.defaultTrailingGapUs,
      );
      expect(await q.transmit(long), isA<TransmitSent>());
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

  test(
    'Simulated rejects a negative repeat count instead of throwing',
    () async {
      final sim = SimulatedTransport();
      expect(await sim.transmit(_nec, repeats: -1), isA<TransmitRejected>());
      expect(sim.sent, isEmpty);
      await sim.dispose();
    },
  );

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

    test('concurrent re-registration keeps the last call and disposes the '
        'rest', () async {
      final reg = TransportRegistry();
      final a = _SlowTransport(Duration.zero, id: 'x')
        ..disposeDelay = const Duration(milliseconds: 20);
      final b = _SlowTransport(Duration.zero, id: 'x');
      final c = _SlowTransport(Duration.zero, id: 'x');
      await reg.register(a);
      await Future.wait([reg.register(b), reg.register(c)]);
      expect(_innerOf(reg.byId('x')), same(c));
      expect(a.disposed, isTrue);
      expect(b.disposed, isTrue, reason: 'b was replaced, not leaked');
      expect(c.disposed, isFalse);
      await reg.dispose();
      expect(c.disposed, isTrue);
    });

    test(
      'a replacement is in place while the old transport disposes',
      () async {
        final reg = TransportRegistry();
        final a = _SlowTransport(Duration.zero, id: 'x')
          ..disposeDelay = const Duration(milliseconds: 20);
        await reg.register(a);
        final b = _SlowTransport(Duration.zero, id: 'x');
        final pending = reg.register(b);
        await Future<void>.delayed(Duration.zero);
        expect(_innerOf(reg.byId('x')), same(b));
        await pending;
        await reg.dispose();
      },
    );

    test(
      'unregister and register racing dispose do not throw or leak',
      () async {
        final reg = TransportRegistry();
        final a = _SlowTransport(Duration.zero, id: 'a')
          ..disposeDelay = const Duration(milliseconds: 10);
        final b = _SlowTransport(Duration.zero, id: 'b')
          ..disposeDelay = const Duration(milliseconds: 10);
        await reg.register(a);
        await reg.register(b);
        final late = _SlowTransport(Duration.zero, id: 'late');
        await Future.wait([
          reg.dispose(),
          reg.unregister('a'),
          reg.register(late),
          reg.dispose(),
        ]);
        expect(a.disposed && b.disposed && late.disposed, isTrue);
        expect(reg.all, isEmpty);
      },
    );

    test('a health result for a replaced transport is dropped', () async {
      final reg = TransportRegistry();
      await reg.register(
        _SlowTransport(const Duration(milliseconds: 30), id: 'h'),
      );
      final pending = reg.checkHealth('h');
      await reg.register(_SlowTransport(Duration.zero, id: 'h'));
      await pending;
      expect(reg.healthOf('h'), isNull);
      await reg.dispose();
    });

    test('a hub that answers but cannot send is not auto-selected', () async {
      final reg = TransportRegistry();
      await reg.register(
        _SlowTransport(Duration.zero, id: 'unpaired')
          ..healthResult = () => Degraded(
            checkedAt: DateTime.now(),
            reason: 'reachable but not paired',
            canSend: false,
          ),
      );
      await reg.checkHealth('unpaired');
      expect(reg.resolve(), isNull);
      expect(reg.resolve(preferredId: 'unpaired')!.id, 'unpaired');
      await reg.dispose();
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
