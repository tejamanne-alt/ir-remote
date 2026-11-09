/// The one interface everything that touches IR hardware implements.
///
/// Implementations live in `ir_transports` (and the app's platform channel);
/// this file only defines the contract, so it stays free of dart:io.
library;

import '../signal/ir_signal.dart';

/// An inclusive carrier frequency range in Hz.
final class CarrierRange {
  /// Creates a range; [minHz] must not exceed [maxHz].
  const CarrierRange(this.minHz, this.maxHz) : assert(minHz <= maxHz);

  /// Lower bound in Hz.
  final int minHz;

  /// Upper bound in Hz.
  final int maxHz;

  /// Whether [hz] falls inside the range.
  bool contains(int hz) => hz >= minHz && hz <= maxHz;

  @override
  bool operator ==(Object other) =>
      other is CarrierRange && other.minHz == minHz && other.maxHz == maxHz;

  @override
  int get hashCode => Object.hash(minHz, maxHz);

  @override
  String toString() => '$minHz-$maxHz Hz';
}

/// How quickly a transport usually starts transmitting after a request.
enum LatencyClass {
  /// The phone's own emitter.
  local,

  /// A hub on the local network.
  lan,
}

/// What a transport can do. The validator checks every signal against these
/// before it reaches the hardware.
final class TransportCapabilities {
  /// Creates a capability description.
  const TransportCapabilities({
    required this.carrierRangesHz,
    required this.maxPatternUs,
    required this.canLearn,
    required this.latencyClass,
    this.maxDurations,
  });

  /// Supported carrier ranges, or `null` when the platform could not report
  /// them (Android's `getCarrierFrequencies()` may return null). Unknown
  /// ranges are validated against [plausibleCarrier] instead.
  final List<CarrierRange>? carrierRangesHz;

  /// The longest single pattern the transport accepts, in microseconds.
  /// Android requires patterns shorter than 2 seconds.
  final int maxPatternUs;

  /// Maximum number of durations in one pattern, if the transport has one.
  final int? maxDurations;

  /// Whether the transport can capture signals from an original remote.
  final bool canLearn;

  /// Expected latency class.
  final LatencyClass latencyClass;

  /// The range assumed when [carrierRangesHz] is unknown. It covers every
  /// consumer IR protocol the app encodes and is a sanity bound, not a claim
  /// about the hardware.
  static const CarrierRange plausibleCarrier = CarrierRange(20000, 60000);

  @override
  String toString() =>
      'TransportCapabilities(carriers: '
      '${carrierRangesHz ?? 'unknown'}, maxPattern: $maxPatternUs us, '
      'maxDurations: ${maxDurations ?? 'none'}, canLearn: $canLearn, '
      '$latencyClass)';
}

/// Why a transport refused a signal before sending it.
enum RejectReason {
  /// The signal has no durations, an even count, or a value out of bounds.
  invalidDurations,

  /// The carrier is outside the transport's supported ranges.
  carrierOutOfRange,

  /// A single frame is longer than the transport's maximum pattern.
  patternTooLong,

  /// The pattern has more durations than the transport accepts.
  tooManyDurations,

  /// The hub refused the request (for example a missing pairing token).
  refusedByHub,

  /// The platform reported an error while transmitting.
  hardwareError,
}

/// Outcome of a transmit request. A value, never an exception, so the UI can
/// map every case to a specific message.
sealed class TransmitResult {
  const TransmitResult();
}

/// The signal was sent (or acknowledged by a hub).
final class TransmitSent extends TransmitResult {
  /// Creates a success result.
  const TransmitSent({required this.elapsed});

  /// Time from dequeue to completion (or hub acknowledgement).
  final Duration elapsed;

  @override
  String toString() => 'sent in ${elapsed.inMilliseconds} ms';
}

/// The signal was refused before it was sent.
final class TransmitRejected extends TransmitResult {
  /// Creates a rejection result.
  const TransmitRejected(this.reason, this.detail);

  /// Machine-readable reason.
  final RejectReason reason;

  /// Human-readable detail for logs and the inspector.
  final String detail;

  @override
  String toString() => 'rejected(${reason.name}): $detail';
}

/// The transport is not available (no emitter, hub offline, permission
/// denied).
final class TransmitTransportUnavailable extends TransmitResult {
  /// Creates an unavailable result.
  const TransmitTransportUnavailable(this.detail);

  /// Why the transport is unavailable.
  final String detail;

  @override
  String toString() => 'transportUnavailable: $detail';
}

/// The transport did not complete or acknowledge in time.
final class TransmitTimeout extends TransmitResult {
  /// Creates a timeout result.
  const TransmitTimeout(this.after);

  /// How long the transport waited.
  final Duration after;

  @override
  String toString() => 'timeout after ${after.inMilliseconds} ms';
}

/// Result of a transport health check.
sealed class HealthStatus {
  const HealthStatus({required this.checkedAt});

  /// When the check ran.
  final DateTime checkedAt;

  /// Whether the transport can be used right now.
  bool get isUsable;
}

/// The transport responded normally.
final class Healthy extends HealthStatus {
  /// Creates a healthy status.
  const Healthy({required super.checkedAt, this.latency, this.detail});

  /// Round-trip latency of the check, for hubs.
  final Duration? latency;

  /// Optional detail such as a firmware version.
  final String? detail;

  @override
  bool get isUsable => true;
}

/// The transport answers but something needs attention.
final class Degraded extends HealthStatus {
  /// Creates a degraded status. [canSend] is false when the transport
  /// answers but cannot transmit until the user acts (for example a hub
  /// that is not paired), so automatic selection skips it.
  const Degraded({
    required super.checkedAt,
    required this.reason,
    this.canSend = true,
  });

  /// What needs attention.
  final String reason;

  /// Whether the transport can still transmit.
  final bool canSend;

  @override
  bool get isUsable => canSend;
}

/// The transport cannot be used.
final class Unreachable extends HealthStatus {
  /// Creates an unreachable status.
  const Unreachable({required super.checkedAt, required this.reason});

  /// Why it cannot be used.
  final String reason;

  @override
  bool get isUsable => false;
}

/// A signal captured from an original remote by a hub with a receiver.
final class LearnedSignal {
  /// Creates a captured signal.
  const LearnedSignal({
    required this.signal,
    required this.capturedAt,
    this.hubDecodedProtocol,
    this.hubDecodedValue,
  });

  /// The raw capture. Carrier is the hub's measurement, or 38 kHz when the
  /// receiver cannot measure it.
  final IrSignal signal;

  /// When the capture arrived.
  final DateTime capturedAt;

  /// Protocol name reported by the hub's own decoder, if any. The app runs its
  /// own decoder too; this is informational.
  final String? hubDecodedProtocol;

  /// Value reported by the hub's decoder, if any.
  final String? hubDecodedValue;
}

/// The kinds of transport the registry knows about.
enum TransportKind {
  /// The phone's own IR emitter (Android only).
  builtIn,

  /// The ESP32 reference bridge.
  espBridge,

  /// A Broadlink RM hub.
  broadlink,

  /// The in-memory simulator used in tests and debug builds.
  simulated,
}

/// Anything that can put IR on the air.
abstract interface class IrTransport {
  /// Stable identifier, unique across transports (for example a hub's MAC).
  String get id;

  /// Name shown to the user.
  String get displayName;

  /// The transport family.
  TransportKind get kind;

  /// Current capabilities. May change after [health] (for example once a
  /// hub reports its firmware info).
  TransportCapabilities get caps;

  /// Sends [signal] with [repeats] repeat frames (at least the protocol's
  /// minimum). Never throws; every failure is a [TransmitResult] value.
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0});

  /// Starts learn mode. Each event is one captured signal; cancelling the
  /// subscription ends learn mode. Returns `null` when [caps] cannot learn.
  Stream<LearnedSignal>? learn();

  /// Checks whether the transport is usable. Never throws.
  Future<HealthStatus> health();

  /// Releases sockets, channels and timers.
  Future<void> dispose();
}
