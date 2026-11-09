/// A strictly serial task queue and the transport decorator built on it.
library;

import 'dart:async';
import 'dart:collection';

import 'package:ir_core/ir_core.dart';

/// Thrown into a task's future when the queue refuses it because its backlog
/// is full.
final class QueueFullException implements Exception {
  /// Creates the exception.
  const QueueFullException(this.capacity);

  /// The backlog limit that was hit.
  final int capacity;

  @override
  String toString() => 'QueueFullException: backlog limit $capacity reached';
}

/// Runs async tasks one at a time, in submission order.
///
/// A task starts only after the previous one has completed (successfully or
/// not), so two transmissions never overlap on air.
final class SerialQueue {
  /// Creates a queue that holds at most [capacity] waiting tasks.
  SerialQueue({this.capacity = 32}) : assert(capacity > 0);

  /// Maximum number of tasks waiting behind the running one.
  final int capacity;

  final Queue<_Job<Object?>> _waiting = Queue();
  bool _running = false;

  /// Number of tasks waiting (not counting the one running).
  int get pending => _waiting.length;

  /// Whether a task is running.
  bool get isBusy => _running;

  /// Enqueues [task]. The returned future completes with its result, or with
  /// [QueueFullException] when the backlog is full.
  Future<T> run<T>(Future<T> Function() task) {
    if (_waiting.length >= capacity) {
      return Future.error(QueueFullException(capacity));
    }
    final job = _Job<T>(task);
    _waiting.add(job);
    _pump();
    return job.completer.future;
  }

  void _pump() {
    if (_running || _waiting.isEmpty) return;
    _running = true;
    final job = _waiting.removeFirst();
    job.start().whenComplete(() {
      _running = false;
      _pump();
    });
  }
}

final class _Job<T> {
  _Job(this.task);

  final Future<T> Function() task;
  final Completer<T> completer = Completer<T>();

  Future<void> start() async {
    try {
      completer.complete(await task());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  }
}

/// Wraps any [IrTransport] so that transmissions run through one serial
/// queue, are bounded by a timeout, and can never throw.
///
/// The registry wraps every transport in one of these; inner transports may
/// therefore assume calls arrive one at a time.
final class QueuedTransport implements IrTransport {
  /// Wraps [inner].
  QueuedTransport(
    this.inner, {
    this.timeout = const Duration(seconds: 5),
    int capacity = 32,
    this.onRecord,
  }) : _queue = SerialQueue(capacity: capacity);

  /// The wrapped transport.
  final IrTransport inner;

  /// Upper bound for a single transmit, measured from when it starts.
  final Duration timeout;

  final SerialQueue _queue;

  /// Observer for every completed transmission.
  final void Function(TransmitRecord record)? onRecord;

  /// Number of transmissions waiting.
  int get pending => _queue.pending;

  @override
  String get id => inner.id;

  @override
  String get displayName => inner.displayName;

  @override
  TransportKind get kind => inner.kind;

  @override
  TransportCapabilities get caps => inner.caps;

  /// How long the queue stays held by a transmit that already timed out,
  /// so a stuck call cannot overlap the next one on air, yet cannot block
  /// the queue forever.
  Duration get holdLimit => timeout * 4;

  /// Total on-air time of [signal] with [repeats], gaps included.
  static int airTimeUs(IrSignal signal, int repeats) {
    var t = 0;
    for (final f in signal.frames(repeats: repeats)) {
      t += f.frame.fold(0, (a, b) => a + b) + f.gapAfterUs;
    }
    return t;
  }

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    final enqueued = DateTime.now();
    final reply = Completer<TransmitResult>();
    void answer(TransmitResult r) {
      if (!reply.isCompleted) reply.complete(r);
    }

    unawaited(
      _queue
          .run(() async {
            // The caller hears about a timeout at [timeout]; the queue keeps
            // waiting for the inner call (up to [holdLimit]) so the hardware is
            // idle before the next transmission starts.
            // Both limits grow with the signal's own on-air time, so a long
            // legitimate hold is never reported as a timeout.
            final onAir = Duration(microseconds: airTimeUs(signal, repeats));
            final limit = timeout + onAir;
            final timer = Timer(limit, () => answer(TransmitTimeout(limit)));
            try {
              answer(
                await inner
                    .transmit(signal, repeats: repeats)
                    .timeout(
                      holdLimit + onAir,
                      onTimeout: () => TransmitTimeout(limit),
                    ),
              );
            } catch (e) {
              answer(TransmitTransportUnavailable('transport error: $e'));
            } finally {
              timer.cancel();
            }
          })
          .catchError((Object e) {
            answer(
              e is QueueFullException
                  ? TransmitRejected(
                      RejectReason.hardwareError,
                      'too many presses waiting (${e.capacity}); try again',
                    )
                  : TransmitTransportUnavailable('queue error: $e'),
            );
          }),
    );
    final result = await reply.future;
    onRecord?.call(
      TransmitRecord(
        at: enqueued,
        transportId: id,
        transportKind: kind,
        signal: signal,
        repeats: repeats,
        result: result,
      ),
    );
    return result;
  }

  @override
  Stream<LearnedSignal>? learn() => inner.learn();

  @override
  Future<HealthStatus> health() async {
    try {
      return await inner.health().timeout(
        timeout,
        onTimeout: () => Unreachable(
          checkedAt: DateTime.now(),
          reason: 'health check timed out after ${timeout.inSeconds} s',
        ),
      );
    } catch (e) {
      return Unreachable(checkedAt: DateTime.now(), reason: 'health error: $e');
    }
  }

  @override
  Future<void> dispose() => inner.dispose();
}

/// One transmission, as recorded for the debug Signal Inspector.
final class TransmitRecord {
  /// Creates a record.
  const TransmitRecord({
    required this.at,
    required this.transportId,
    required this.transportKind,
    required this.signal,
    required this.repeats,
    required this.result,
  });

  /// When the press was enqueued.
  final DateTime at;

  /// Transport that handled it.
  final String transportId;

  /// Its kind.
  final TransportKind transportKind;

  /// The signal sent.
  final IrSignal signal;

  /// Repeats requested.
  final int repeats;

  /// The outcome.
  final TransmitResult result;

  /// JSON for the inspector's export.
  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'transport': transportId,
    'transportKind': transportKind.name,
    'carrierHz': signal.carrierHz,
    'durationsUs': signal.durationsUs,
    'totalUs': signal.frameLengthUs,
    'repeats': repeats,
    'result': result.toString(),
  };
}
