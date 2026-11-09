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
  const SendOutcome(
    this.result, {
    this.transportName,
    this.transportKind,
    this.missingKey = false,
  });

  /// No transport could send.
  static const SendOutcome noTransport = SendOutcome(
    TransmitTransportUnavailable('no transport'),
  );

  /// The transmit result.
  final TransmitResult result;

  /// Display name of the transport that handled it.
  final String? transportName;

  /// Kind of the transport that handled it, so the UI can name the phone's
  /// own emitter and the simulator in the user's language.
  final TransportKind? transportKind;

  /// The remote has no code for the key.
  final bool missingKey;

  /// Whether nothing could send at all.
  bool get isNoTransport => transportName == null && !missingKey;

  /// Whether the signal went out.
  bool get ok => result is TransmitSent;
}

/// Keys that must never auto-repeat while held.
const Set<String> nonRepeatingKeys = {Keys.power, Keys.powerOn, Keys.powerOff};

/// Most frames one press may send (main frame and repeats), about 30 s of
/// NEC dittos.
const int maxHoldFrames = 300;

/// Repeat frames handed to the transport in one call while a key is held
/// cover at least this much air time (gaps included). One call's overhead
/// is then paid per batch rather than per frame, and the gaps inside a batch
/// are exact; the cost is that a release is noticed at the next batch
/// boundary (one frame for NEC, RC5 and RC6, three 45 ms frames for Sony).
const int repeatBatchUs = 100000;

/// The signal sent for each repeat while [signal]'s key is held: its repeat
/// frame, carrying the repeat gap as its own trailing gap so transports keep
/// the protocol's period. `null` when [signal] has no repeat rule.
IrSignal? repeatFrameSignal(IrSignal signal) {
  final r = signal.repeat;
  if (r == null) return null;
  return IrSignal(
    carrierHz: signal.carrierHz,
    durationsUs: r.frameUs,
    repeat: RepeatSpec(
      frameUs: r.frameUs,
      leadInGapUs: r.gapUs,
      gapUs: r.gapUs,
    ),
  );
}

/// Sends saved keys through the registry.
final class SendService {
  /// Creates the service.
  SendService({
    required this.registry,
    required this.devices,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Transport registry.
  final TransportRegistry registry;

  /// For recording use (recents).
  final DeviceRepository devices;

  final DateTime Function() _clock;

  /// Toggle state per device ID, or per unsaved matching scope.
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
    if (k == null) return _missingKey;
    return sendSignal(device, _signalFor(device.id, k, isRepeat: isRepeat));
  }

  static const SendOutcome _missingKey = SendOutcome(
    TransmitRejected(RejectReason.invalidDurations, 'no code for this key'),
    missingKey: true,
  );

  IrSignal _signalFor(String scope, SavedKey k, {required bool isRepeat}) {
    if (!k.hasToggle) return k.signal;
    final current = _toggle[scope] ?? true;
    final next = isRepeat ? current : !current;
    _toggle[scope] = next;
    return next ? k.toggled! : k.signal;
  }

  /// Sends an arbitrary signal for [device] (AC frames, tests, matching).
  Future<SendOutcome> sendSignal(
    SavedDevice device,
    IrSignal signal, {
    int repeats = 0,
  }) => _send(device, signal, repeats: repeats, touch: true);

  Future<SendOutcome> _send(
    SavedDevice device,
    IrSignal signal, {
    required int repeats,
    required bool touch,
  }) async {
    final t = transportFor(device);
    if (t == null) return SendOutcome.noTransport;
    final r = await t.transmit(signal, repeats: repeats);
    if (touch && r is TransmitSent) {
      unawaited(devices.touch(device.id, _clock()).catchError((Object _) {}));
    }
    return SendOutcome(r, transportName: t.displayName, transportKind: t.kind);
  }

  /// Sends [signal] through the default transport (no saved device yet, as
  /// in code matching).
  Future<SendOutcome> sendUnsaved(
    IrSignal signal, {
    String? preferredId,
  }) async {
    final t = registry.resolve(preferredId: preferredId);
    if (t == null) return SendOutcome.noTransport;
    return SendOutcome(
      await t.transmit(signal),
      transportName: t.displayName,
      transportKind: t.kind,
    );
  }

  /// Sends a new press of [key] for an appliance that is not saved yet (code
  /// matching). Toggle protocols alternate per press within [toggleScope],
  /// exactly as they do for a saved remote (ADR-008).
  Future<SendOutcome> sendUnsavedKey(
    SavedKey key, {
    required String toggleScope,
    String? preferredId,
  }) => sendUnsaved(
    _signalFor(toggleScope, key, isRepeat: false),
    preferredId: preferredId,
  );

  /// Hands the toggle state of the unsaved [scope] to the saved remote
  /// [deviceId], so its first press flips the bit relative to the last code
  /// the appliance saw during matching.
  void adoptToggleState({required String scope, required String deviceId}) {
    final v = _toggle.remove(scope);
    if (v != null) _toggle[deviceId] = v;
  }

  /// Starts a press that repeats while held.
  ///
  /// The first transmit carries the key's signal with its [RepeatSpec], so
  /// the transport sends the protocol's minimum repeats (Sony's three frames
  /// per tap) and keeps the lead-in gap after it. While the press is held,
  /// repeats follow on the protocol's own timing: the first one
  /// [RepeatSpec.leadInGapUs] after the frame (39.8 ms for an NEC ditto), the
  /// next ones [RepeatSpec.gapUs] apart, each carried by
  /// [repeatFrameSignal] and handed over as a repeat count of about
  /// [repeatBatchUs] of air time. Transports enforce the trailing gap of
  /// what they sent; the service also waits it out after each transmit
  /// returns, so a transport that returns before its frames are on the air
  /// (the simulator, a hub that acknowledges early) is not flooded. The
  /// repeat frame is the NEC ditto, the same Sony frame, or the same RC5/RC6
  /// frame with the press's toggle. At most [maxHoldFrames] frames go out.
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
    final k = device.keys[key];
    if (k == null) {
      onOutcome?.call(_missingKey);
      return;
    }
    final signal = _signalFor(device.id, k, isRepeat: false);
    final first = await sendSignal(device, signal);
    onOutcome?.call(first);
    s._sent += 1 + signal.minRepeats;
    final r = signal.repeat;
    final repeatSignal = repeatFrameSignal(signal);
    if (!first.ok ||
        r == null ||
        repeatSignal == null ||
        nonRepeatingKeys.contains(key)) {
      return;
    }
    final period = r.frameLengthUs + r.gapUs;
    final perBatch = (repeatBatchUs + period - 1) ~/ period;
    var gapUs = signal.minRepeats > 0 ? r.gapUs : r.leadInGapUs;
    while (s._held && s._sent < maxHoldFrames) {
      await Future<void>.delayed(Duration(microseconds: gapUs));
      if (!s._held) return;
      final left = maxHoldFrames - s._sent;
      final n = perBatch < left ? perBatch : left;
      final o = await _send(device, repeatSignal, repeats: n - 1, touch: false);
      s._sent += n;
      if (!o.ok) {
        onOutcome?.call(o);
        return;
      }
      gapUs = r.gapUs;
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
