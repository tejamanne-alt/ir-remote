// Hold-to-repeat timing on a transport that keeps an on-air timeline on the
// test's fake clock, the way the built-in emitter and the ESP32 bridge do:
// a transmit returns once its last frame has gone out, and the next one
// waits out the trailing gap of the previous one.
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:irremote/data/database.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/data/repositories.dart';
import 'package:irremote/services/send_service.dart';

import 'helpers.dart';

final class ClockedTransport implements IrTransport {
  ClockedTransport(this._now);

  final Duration Function() _now;
  int _quietUntilUs = 0;

  /// Every frame put on the air, with its start time in microseconds.
  final List<({int startUs, List<int> frame})> onAir = [];

  @override
  String get id => 'clocked';

  @override
  String get displayName => 'Clocked';

  @override
  TransportKind get kind => TransportKind.builtIn;

  @override
  TransportCapabilities get caps => const TransportCapabilities(
    carrierRangesHz: null,
    maxPatternUs: 2000000,
    canLearn: false,
    latencyClass: LatencyClass.local,
  );

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    var t = _now().inMicroseconds;
    if (_quietUntilUs > t) {
      await Future<void>.delayed(Duration(microseconds: _quietUntilUs - t));
      t = _now().inMicroseconds;
    }
    final frames = signal.frames(repeats: repeats);
    var cursor = t;
    for (final (i, f) in frames.indexed) {
      onAir.add((startUs: cursor, frame: f.frame));
      cursor += f.frame.fold(0, (a, b) => a + b);
      if (i < frames.length - 1) cursor += f.gapAfterUs;
    }
    await Future<void>.delayed(Duration(microseconds: cursor - t));
    _quietUntilUs = _now().inMicroseconds + frames.last.gapAfterUs;
    return TransmitSent(elapsed: Duration(microseconds: cursor - t));
  }

  @override
  Stream<LearnedSignal>? learn() => null;

  @override
  Future<HealthStatus> health() async => Healthy(checkedAt: DateTime.now());

  @override
  Future<void> dispose() async {}
}

int _len(List<int> d) => d.fold(0, (a, b) => a + b);

SavedDevice _device(String key, KeyCode code) => SavedDevice(
  id: 'dev',
  name: 'Device',
  category: DeviceCategory.tv,
  createdAt: DateTime.utc(2026, 11, 9),
  keys: {key: snapshotKey(key, code)},
);

Future<(SendService, ClockedTransport, AppDatabase)> _setUp(
  WidgetTester tester,
) async {
  final sw = tester.binding.clock.stopwatch()..start();
  final t = ClockedTransport(() => sw.elapsed);
  final registry = TransportRegistry();
  await registry.register(t);
  final db = memoryDb();
  return (
    SendService(registry: registry, devices: DeviceRepository(db)),
    t,
    db,
  );
}

Future<void> _hold(WidgetTester tester, HoldSession s, Duration d) async {
  for (var left = d; left > Duration.zero;) {
    const step = Duration(milliseconds: 5);
    await tester.pump(step);
    left -= step;
  }
  s.release();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('NEC: the first ditto follows the frame by its lead-in gap, '
      'then one ditto per 108 ms period', (tester) async {
    final (send, t, db) = await _setUp(tester);
    final device = _device(
      Keys.volUp,
      const ProtocolKeyCode('NEC1', {'D': 4, 'F': 2}),
    );
    final signal = device.keys[Keys.volUp]!.signal;
    final r = signal.repeat!;
    await _hold(
      tester,
      send.press(device, Keys.volUp),
      Duration(milliseconds: 500),
    );
    final f = t.onAir;
    expect(f.length, greaterThanOrEqualTo(4));
    expect(f.first.frame, signal.durationsUs);
    final mainEnd = f[0].startUs + _len(f[0].frame);
    // 39.8 ms after the frame, not after a fixed UI hold delay.
    expect(f[1].startUs - mainEnd, r.leadInGapUs);
    for (var i = 1; i < f.length; i++) {
      expect(f[i].frame, r.frameUs, reason: 'frame $i is a ditto');
      if (i > 1) {
        expect(f[i].startUs - f[i - 1].startUs, 108000, reason: 'frame $i');
      }
    }
    await tester.runAsync(db.close);
  });

  testWidgets('Sony: repeats keep the 45 ms frame period', (tester) async {
    final (send, t, db) = await _setUp(tester);
    final device = _device(
      Keys.volUp,
      const ProtocolKeyCode('Sony12', {'D': 1, 'F': 18}),
    );
    final signal = device.keys[Keys.volUp]!.signal;
    await _hold(
      tester,
      send.press(device, Keys.volUp),
      Duration(milliseconds: 400),
    );
    final f = t.onAir;
    expect(f.length, greaterThanOrEqualTo(8));
    for (var i = 0; i < f.length; i++) {
      expect(f[i].frame, signal.durationsUs);
      if (i > 0) {
        expect(f[i].startUs - f[i - 1].startUs, 45000, reason: 'frame $i');
      }
    }
    await tester.runAsync(db.close);
  });

  testWidgets('a tap sends only the protocol minimum; release stops repeats', (
    tester,
  ) async {
    final (send, t, db) = await _setUp(tester);
    final device = _device(
      Keys.volUp,
      const ProtocolKeyCode('NEC1', {'D': 4, 'F': 2}),
    );
    final s = send.press(device, Keys.volUp)..release();
    await tester.pump(const Duration(seconds: 1));
    expect(t.onAir.length, 1);
    expect(s.framesSent, 1);

    final sony = _device(
      Keys.volUp,
      const ProtocolKeyCode('Sony12', {'D': 1, 'F': 18}),
    );
    t.onAir.clear();
    send.press(sony, Keys.volUp).release();
    await tester.pump(const Duration(seconds: 1));
    expect(t.onAir.length, 3, reason: 'Sony sends three frames per tap');

    t.onAir.clear();
    final held = send.press(device, Keys.volUp);
    await tester.pump(const Duration(milliseconds: 300));
    held.release();
    await tester.pump(const Duration(milliseconds: 200));
    final atRelease = t.onAir.length;
    await tester.pump(const Duration(seconds: 2));
    expect(t.onAir.length, atRelease);
    await tester.runAsync(db.close);
  });

  testWidgets('RC5 repeats keep the press toggle; a hold stops at 300 frames', (
    tester,
  ) async {
    final (send, t, db) = await _setUp(tester);
    final device = _device(
      Keys.volUp,
      const ProtocolKeyCode('RC5', {'D': 0, 'F': 16}),
    );
    final s = send.press(device, Keys.volUp);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(s.framesSent, 300);
    expect(t.onAir.length, 300);
    final first = t.onAir.first.frame;
    expect(t.onAir.every((x) => _listEq(x.frame, first)), isTrue);
    s.release();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
