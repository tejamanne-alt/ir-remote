/// The send pipeline: key → snapshot signal → transport, with toggle state
/// and hold-to-repeat.
library;

import 'dart:async';

import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';

import '../data/models.dart';
import '../data/repositories.dart';

/// Result of sending a key, with the transport used.
final class SendOutcome {
  /// Creates an outcome.
  const SendOutcome(this.result, {this.transportName, this.missingKey = false});

  /// No transport could send.
  static const SendOutcome noTransport = SendOutcome(
    TransmitTransportUnavailable('no transport'),
  );

  /// The transmit result.
  final TransmitResult result;

  /// Display name of the transport that handled it.
  final String? transportName;

  /// The remote has no code for the key.
  final bool missingKey;

  /// Whether nothing could send at all.
  bool get isNoTransport => transportName == null && !missingKey;

  /// Whether the signal went out.
  bool get ok => result is TransmitSent;
}

/// Keys that must never auto-repeat while held.
const Set<String> nonRepeatingKeys = {Keys.power, Keys.powerOn, Keys.powerOff};

/// Sends saved keys through the registry.
final class SendService {
  /// Creates the service.
  SendService({
    required this.registry,
    required this.devices,
    DateTime Function()? clock,
    this.holdDelay = const Duration(milliseconds: 350),
  }) : _clock = clock ?? DateTime.now;

  /// Transport registry.
  final TransportRegistry registry;

  /// For recording use (recents).
  final DeviceRepository devices;

  /// How long a press must last before repeats start.
  final Duration holdDelay;

  final DateTime Function() _clock;
  final Map<String, bool> _toggle = {};

  /// Resolves which transport would send for [device].
  IrTransport? transportFor(SavedDevice device) =>
      registry.resolve(preferredId: device.transportId);

  /// Sends one press of [key]. A new press flips the toggle bit of toggle
  /// protocols; [isRepeat] keeps it.
  Future<SendOutcome> sendKey(
    SavedDevice device,
    String key, {
    bool isRepeat = false,
  }) async {
    final k = device.keys[key];
    if (k == null) {
      return const SendOutcome(
        TransmitRejected(RejectReason.invalidDurations, 'no code for this key'),
        missingKey: true,
      );
    }
    return sendSignal(device, _signalFor(device.id, k, isRepeat: isRepeat));
  }

  IrSignal _signalFor(String deviceId, SavedKey k, {required bool isRepeat}) {
    if (!k.hasToggle) return k.signal;
    final current = _toggle[deviceId] ?? true;
    final next = isRepeat ? current : !current;
    _toggle[deviceId] = next;
    return next ? k.toggled! : k.signal;
  }

  /// Sends an arbitrary signal for [device] (AC frames, tests, matching).
  Future<SendOutcome> sendSignal(
    SavedDevice device,
    IrSignal signal, {
    int repeats = 0,
  }) async {
    final t = transportFor(device);
    if (t == null) return SendOutcome.noTransport;
    final r = await t.transmit(signal, repeats: repeats);
    if (r is TransmitSent) {
      unawaited(devices.touch(device.id, _clock()).catchError((Object _) {}));
    }
    return SendOutcome(r, transportName: t.displayName);
  }

  /// Sends [signal] through the default transport (no saved device yet, as
  /// in code matching).
  Future<SendOutcome> sendUnsaved(
    IrSignal signal, {
    String? preferredId,
  }) async {
    final t = registry.resolve(preferredId: preferredId);
    if (t == null) return SendOutcome.noTransport;
    return SendOutcome(await t.transmit(signal), transportName: t.displayName);
  }

  /// Starts a press that repeats while held. The first frame goes out at
  /// once; after [holdDelay] the protocol's repeat frame follows (the NEC
  /// ditto, the same Sony frame, the same RC5/RC6 toggle) until [HoldSession.release].
  HoldSession press(
    SavedDevice device,
    String key, {
    void Function(SendOutcome outcome)? onOutcome,
  }) {
    final session = HoldSession._();
    unawaited(_runHold(session, device, key, onOutcome));
    return session;
  }

  Future<void> _runHold(
    HoldSession s,
    SavedDevice device,
    String key,
    void Function(SendOutcome outcome)? onOutcome,
  ) async {
    final first = await sendKey(device, key);
    onOutcome?.call(first);
    s._sent++;
    final k = device.keys[key];
    if (!first.ok || k == null || nonRepeatingKeys.contains(key)) return;
    await Future<void>.delayed(holdDelay);
    final base = k.hasToggle
        ? _signalFor(device.id, k, isRepeat: true)
        : k.signal;
    final r = base.repeat;
    if (r == null) return;
    final repeatOnly = IrSignal(
      carrierHz: base.carrierHz,
      durationsUs: r.frameUs,
    );
    // Safety cap: at most 30 s of repeats from one press.
    const maxRepeats = 300;
    while (s._held && s._sent < maxRepeats) {
      final o = await sendSignal(device, repeatOnly);
      s._sent++;
      if (!o.ok) {
        onOutcome?.call(o);
        return;
      }
      await Future<void>.delayed(Duration(microseconds: r.gapUs));
    }
  }
}

/// A key press that may be held.
final class HoldSession {
  HoldSession._();

  bool _held = true;
  int _sent = 0;

  /// Frames sent so far (main frame plus repeats).
  int get framesSent => _sent;

  /// Ends the press; no repeat starts after this.
  void release() => _held = false;
}
