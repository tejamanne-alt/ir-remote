/// An in-memory transport that records signals. Default in tests and debug
/// builds; never presented as real hardware.
library;

import 'dart:async';

import 'package:ir_core/ir_core.dart';

/// A recorded transmission.
final class SimulatedSend {
  /// Creates a record.
  const SimulatedSend(this.signal, this.repeats, this.chunks);

  /// The signal requested.
  final IrSignal signal;

  /// Repeats requested.
  final int repeats;

  /// The chunks the validator planned for the simulated caps.
  final List<TransmitChunk> chunks;
}

/// Records every signal and optionally injects failures and latency.
final class SimulatedTransport implements IrTransport {
  /// Creates a simulator.
  SimulatedTransport({
    this.id = 'simulated',
    this.displayName = 'Simulator',
    this.caps = const TransportCapabilities(
      carrierRangesHz: [CarrierRange(30000, 60000)],
      maxPatternUs: 2000000,
      canLearn: true,
      latencyClass: LatencyClass.local,
    ),
    this.latency = Duration.zero,
    this.validator = const SignalValidator(),
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  TransportKind get kind => TransportKind.simulated;

  @override
  TransportCapabilities caps;

  /// Simulated time per transmission.
  Duration latency;

  /// Validator applied before "sending".
  final SignalValidator validator;

  /// Every accepted transmission, oldest first.
  final List<SimulatedSend> sent = [];

  /// When set, the next transmit returns this result instead of sending.
  TransmitResult? nextResult;

  /// When true, every transmit and health check reports the transport as
  /// unavailable.
  bool offline = false;

  final StreamController<LearnedSignal> _captures =
      StreamController.broadcast();

  /// Number of transmissions in flight, for overlap assertions in tests.
  int inFlight = 0;

  /// Highest [inFlight] observed.
  int maxInFlight = 0;

  /// Feeds a capture to anyone listening to [learn].
  void simulateCapture(IrSignal signal) =>
      _captures.add(LearnedSignal(signal: signal, capturedAt: DateTime.now()));

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    final stopwatch = Stopwatch()..start();
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (offline) {
        return const TransmitTransportUnavailable('simulator offline');
      }
      final forced = nextResult;
      if (forced != null) {
        nextResult = null;
        return forced;
      }
      final issues = validator.validate(signal, caps);
      if (issues.isNotEmpty) {
        return TransmitRejected(issues.first.reason, issues.first.detail);
      }
      final chunks = validator.plan(signal, caps, repeats: repeats);
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      sent.add(SimulatedSend(signal, repeats, chunks));
      return TransmitSent(elapsed: stopwatch.elapsed);
    } finally {
      inFlight--;
    }
  }

  @override
  Stream<LearnedSignal>? learn() => caps.canLearn ? _captures.stream : null;

  @override
  Future<HealthStatus> health() async => offline
      ? Unreachable(checkedAt: DateTime.now(), reason: 'simulator offline')
      : Healthy(checkedAt: DateTime.now(), detail: 'simulated');

  @override
  Future<void> dispose() => _captures.close();
}
