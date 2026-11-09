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
  /// same ID.
  Future<void> register(IrTransport transport) async {
    final old = _transports.remove(transport.id);
    if (old != null) await old.dispose();
    _transports[transport.id] = transport is QueuedTransport
        ? transport
        : QueuedTransport(transport, timeout: timeout, onRecord: onRecord);
    _changes.add(null);
  }

  /// Removes and disposes the transport with [id].
  Future<void> unregister(String id) async {
    final t = _transports.remove(id);
    _health.remove(id);
    _lastHealthy.remove(id);
    if (t != null) {
      await t.dispose();
      _changes.add(null);
    }
  }

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
    _health[id] = h;
    if (h.isUsable) _lastHealthy[id] = h.checkedAt;
    _changes.add(null);
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

  /// Disposes every transport.
  Future<void> dispose() async {
    for (final t in _transports.values) {
      await t.dispose();
    }
    _transports.clear();
    await _changes.close();
  }
}
