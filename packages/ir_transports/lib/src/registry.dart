/// The transport registry: which transport sends for which device.
library;

import 'dart:async';

import 'package:ir_core/ir_core.dart';

import 'serial_queue.dart';

/// Holds every known transport, each behind its own serial queue, and picks
/// one per device.
///
/// Selection rule (build contract): the device's chosen transport, else the
/// phone's built-in emitter, else the hub that was most recently healthy.
final class TransportRegistry {
  /// Creates an empty registry. [onRecord] receives every transmission (the
  /// debug Signal Inspector listens here).
  TransportRegistry({
    this.timeout = const Duration(seconds: 5),
    this.onRecord,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Per-transmit timeout applied by each transport's queue.
  final Duration timeout;

  /// Observer for every transmission.
  final void Function(TransmitRecord record)? onRecord;

  final DateTime Function() _clock;
  final Map<String, QueuedTransport> _transports = {};
  final Map<String, HealthStatus> _health = {};
  final Map<String, DateTime> _lastHealthy = {};
  final StreamController<void> _changes = StreamController.broadcast();

  bool _disposed = false;
  Future<void>? _disposing;

  /// Register, unregister and dispose run one at a time, so two calls for
  /// the same ID cannot interleave around a `dispose` await.
  Future<void> _tail = Future<void>.value();

  Future<void> _serial(Future<void> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  /// Fires whenever a transport is added, removed or its health changes.
  Stream<void> get changes => _changes.stream;

  /// All transports, in registration order.
  List<IrTransport> get all => List.unmodifiable(_transports.values);

  /// Hubs only (everything except the built-in emitter and the simulator).
  List<IrTransport> get hubs => [
    for (final t in _transports.values)
      if (t.kind == TransportKind.espBridge ||
          t.kind == TransportKind.broadlink)
        t,
  ];

  /// The phone's own emitter, if registered.
  IrTransport? get builtIn {
    for (final t in _transports.values) {
      if (t.kind == TransportKind.builtIn) return t;
    }
    return null;
  }

  /// Registers [transport], replacing (and disposing) any transport with the
  /// same ID. The new transport is in place before the old one is disposed,
  /// so [resolve] never sees a gap. Health recorded for the old transport is
  /// dropped: it described a different object.
  Future<void> register(IrTransport transport) => _serial(() async {
    if (_disposed) {
      await transport.dispose();
      return;
    }
    final id = transport.id;
    final queued = transport is QueuedTransport
        ? transport
        : QueuedTransport(transport, timeout: timeout, onRecord: onRecord);
    final old = _transports[id];
    _transports[id] = queued;
    if (!identical(old, queued)) {
      _health.remove(id);
      _lastHealthy.remove(id);
    }
    _notify();
    if (old != null && !identical(old, queued)) await old.dispose();
  });

  /// Removes and disposes the transport with [id].
  Future<void> unregister(String id) => _serial(() async {
    final t = _transports.remove(id);
    _health.remove(id);
    _lastHealthy.remove(id);
    if (t != null) {
      _notify();
      await t.dispose();
    }
  });

  /// The transport with [id], or `null`.
  IrTransport? byId(String id) => _transports[id];

  /// Last health result for [id], if any check has run.
  HealthStatus? healthOf(String id) => _health[id];

  /// Runs a health check on [id] and records the result.
  Future<HealthStatus> checkHealth(String id) async {
    final t = _transports[id];
    if (t == null) {
      return Unreachable(checkedAt: _clock(), reason: 'not registered');
    }
    final h = await t.health();
    // The registry was disposed, or the transport was replaced or removed
    // while the check ran: the result no longer describes anything here.
    if (_disposed || !identical(_transports[id], t)) return h;
    _health[id] = h;
    if (h.isUsable) _lastHealthy[id] = h.checkedAt;
    _notify();
    return h;
  }

  /// Checks every transport concurrently.
  Future<void> checkAll() => Future.wait([
    for (final id in _transports.keys.toList()) checkHealth(id),
  ]);

  /// Picks the transport for a device whose user-chosen transport is
  /// [preferredId] (may be `null`). Returns `null` when nothing can send.
  IrTransport? resolve({String? preferredId}) {
    if (preferredId != null) {
      final chosen = _transports[preferredId];
      if (chosen != null) return chosen;
    }
    final emitter = builtIn;
    if (emitter != null) return emitter;
    IrTransport? best;
    DateTime? bestAt;
    for (final hub in hubs) {
      final at = _lastHealthy[hub.id];
      if (at != null && (bestAt == null || at.isAfter(bestAt))) {
        best = hub;
        bestAt = at;
      }
    }
    if (best != null) return best;
    // No hub has been healthy yet: use the first hub not known to be down.
    for (final hub in hubs) {
      final h = _health[hub.id];
      if (h == null || h.isUsable) return hub;
    }
    for (final t in _transports.values) {
      if (t.kind == TransportKind.simulated) return t;
    }
    return null;
  }

  /// Disposes every transport. Health checks still in flight complete
  /// quietly afterwards; registrations queued behind this are disposed.
  Future<void> dispose() => _disposing ??= () {
    _disposed = true;
    return _serial(() async {
      final all = _transports.values.toList();
      _transports.clear();
      _health.clear();
      _lastHealthy.clear();
      await Future.wait([for (final t in all) t.dispose()]);
      await _changes.close();
    });
  }();
}
