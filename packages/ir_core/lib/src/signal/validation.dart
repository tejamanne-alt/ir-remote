/// Signal validation and transmit planning, run before any transmit.
library;

import '../transport/transport.dart';
import 'ir_signal.dart';

/// Limits that apply regardless of transport.
final class ValidationLimits {
  /// Creates limits. The default per-element cap is 150 ms.
  const ValidationLimits({this.maxElementUs = 150000});

  /// Largest single mark or space allowed inside a frame or as a gap.
  final int maxElementUs;
}

/// One problem found by the validator.
final class ValidationIssue {
  /// Creates an issue.
  const ValidationIssue(this.reason, this.detail);

  /// The reject reason a transport reports for this issue.
  final RejectReason reason;

  /// Human-readable detail.
  final String detail;

  @override
  String toString() => '${reason.name}: $detail';
}

/// One pattern handed to a transport in a single hardware call, followed by
/// [gapAfterUs] of silence before the next chunk.
final class TransmitChunk {
  /// Creates a chunk.
  TransmitChunk({
    required this.carrierHz,
    required List<int> durationsUs,
    required this.gapAfterUs,
  }) : durationsUs = List.unmodifiable(durationsUs);

  /// Carrier in Hz.
  final int carrierHz;

  /// Mark-first, mark-last durations.
  final List<int> durationsUs;

  /// Silence after this chunk. The last chunk's gap still matters: the queue
  /// keeps the transport idle for it so frames from the next press do not run
  /// into this one.
  final int gapAfterUs;

  /// Total on-air length of [durationsUs].
  int get lengthUs => durationsUs.fold(0, (a, b) => a + b);
}

/// Validates signals against transport capabilities and splits long
/// transmissions at frame boundaries.
final class SignalValidator {
  /// Creates a validator with [limits].
  const SignalValidator({this.limits = const ValidationLimits()});

  /// The limits applied to every signal.
  final ValidationLimits limits;

  /// Returns every problem with [signal] for a transport with [caps]. An
  /// empty list means the signal may be sent.
  List<ValidationIssue> validate(IrSignal signal, TransportCapabilities caps) {
    final issues = <ValidationIssue>[];
    _checkFrame(signal.durationsUs, 'frame', issues);
    final r = signal.repeat;
    if (r != null) {
      _checkFrame(r.frameUs, 'repeat frame', issues);
      _checkGap(r.leadInGapUs, 'lead-in gap', issues);
      _checkGap(r.gapUs, 'repeat gap', issues);
    }
    _checkCarrier(signal.carrierHz, caps, issues);
    if (issues.isEmpty) {
      if (signal.frameLengthUs >= caps.maxPatternUs) {
        issues.add(
          ValidationIssue(
            RejectReason.patternTooLong,
            'frame is ${signal.frameLengthUs} us; transport maximum is '
            '${caps.maxPatternUs} us',
          ),
        );
      }
      if (r != null && r.frameLengthUs >= caps.maxPatternUs) {
        issues.add(
          ValidationIssue(
            RejectReason.patternTooLong,
            'repeat frame is ${r.frameLengthUs} us; transport maximum is '
            '${caps.maxPatternUs} us',
          ),
        );
      }
      final maxN = caps.maxDurations;
      if (maxN != null) {
        final longest =
            r == null || r.frameUs.length < signal.durationsUs.length
            ? signal.durationsUs.length
            : r.frameUs.length;
        if (longest > maxN) {
          issues.add(
            ValidationIssue(
              RejectReason.tooManyDurations,
              'frame has $longest durations; transport maximum is $maxN',
            ),
          );
        }
      }
    }
    return issues;
  }

  /// Splits one transmission into chunks that each fit the transport. Frames
  /// are joined into a chunk while the joined pattern stays under the limits;
  /// a frame is never split. Call [validate] first; this throws
  /// [ArgumentError] if a single frame does not fit.
  List<TransmitChunk> plan(
    IrSignal signal,
    TransportCapabilities caps, {
    int repeats = 0,
  }) {
    final frames = signal.frames(repeats: repeats);
    final chunks = <TransmitChunk>[];
    var current = <int>[];
    var currentLength = 0;
    var lastGap = 0;
    final maxN = caps.maxDurations;
    for (final f in frames) {
      final fLen = f.frame.fold(0, (a, b) => a + b);
      if (fLen >= caps.maxPatternUs ||
          (maxN != null && f.frame.length > maxN)) {
        throw ArgumentError('frame does not fit the transport; validate first');
      }
      if (current.isNotEmpty) {
        final joinedLength = currentLength + lastGap + fLen;
        final joinedCount = current.length + 1 + f.frame.length;
        final fits =
            joinedLength < caps.maxPatternUs &&
            (maxN == null || joinedCount <= maxN);
        if (fits) {
          current
            ..add(lastGap)
            ..addAll(f.frame);
          currentLength = joinedLength;
          lastGap = f.gapAfterUs;
          continue;
        }
        chunks.add(
          TransmitChunk(
            carrierHz: signal.carrierHz,
            durationsUs: current,
            gapAfterUs: lastGap,
          ),
        );
      }
      current = [...f.frame];
      currentLength = fLen;
      lastGap = f.gapAfterUs;
    }
    chunks.add(
      TransmitChunk(
        carrierHz: signal.carrierHz,
        durationsUs: current,
        gapAfterUs: lastGap,
      ),
    );
    return chunks;
  }

  void _checkFrame(List<int> d, String what, List<ValidationIssue> issues) {
    if (d.isEmpty) {
      issues.add(
        ValidationIssue(RejectReason.invalidDurations, '$what is empty'),
      );
      return;
    }
    if (d.length.isEven) {
      issues.add(
        ValidationIssue(
          RejectReason.invalidDurations,
          '$what must start and end with a mark (odd count); has ${d.length}',
        ),
      );
    }
    for (var i = 0; i < d.length; i++) {
      final v = d[i];
      if (v <= 0 || v > limits.maxElementUs) {
        issues.add(
          ValidationIssue(
            RejectReason.invalidDurations,
            '$what element $i is $v us; allowed 1..${limits.maxElementUs}',
          ),
        );
        return;
      }
    }
  }

  void _checkGap(int gap, String what, List<ValidationIssue> issues) {
    if (gap <= 0 || gap > limits.maxElementUs) {
      issues.add(
        ValidationIssue(
          RejectReason.invalidDurations,
          '$what is $gap us; allowed 1..${limits.maxElementUs}',
        ),
      );
    }
  }

  void _checkCarrier(
    int hz,
    TransportCapabilities caps,
    List<ValidationIssue> issues,
  ) {
    final ranges = caps.carrierRangesHz;
    final ok = ranges == null
        ? TransportCapabilities.plausibleCarrier.contains(hz)
        : ranges.any((r) => r.contains(hz));
    if (!ok) {
      issues.add(
        ValidationIssue(
          RejectReason.carrierOutOfRange,
          'carrier $hz Hz is outside '
          '${ranges ?? [TransportCapabilities.plausibleCarrier]}'
          '${ranges == null ? ' (transport ranges unknown)' : ''}',
        ),
      );
    }
  }
}
