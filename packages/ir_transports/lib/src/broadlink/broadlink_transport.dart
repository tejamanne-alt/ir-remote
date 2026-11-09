// IrTransport for Broadlink RM hubs (RM4 mini is the reference device).
//
// Independent Dart implementation; protocol behaviour taken from the
// MIT-licensed python-broadlink (read, not translated):
// * https://github.com/mjg59/python-broadlink
//   at commit 730853e5faf2cf979596662faf9def2b1f8fee6d
//   - broadlink/device.py: auth flow (packet 0x65 with the initial key,
//     reply carries session id + key), command flow (packet 0x6a with the
//     session key), random 16-bit counter with the top bit set, resending
//     an unanswered request every second until the timeout, the
//     watchdog "ping" note for firmware >= v53.
//   - broadlink/remote.py: send data / enter learning / check data.
// * https://github.com/DAB-LABS/python-broadlink
//   at commit 6c6567ddeba8905537e0049a1343ebd0e5e165a2
//   - broadlink_async/device.py: one serialized request at a time per
//     device, matching replies to requests by counter and dropping late
//     replies, re-authenticating once on -2 / -7 / -4012.
//   - broadlink_async/remote.py: polling check data every 0.5 s, treating
//     -5 / -10 as "nothing yet", re-arming learning every 15 s (an RM4 Pro
//     leaves learning mode silently after 25-40 s) and after any send,
//     sending 0x1e when a learn window closes.

/// The Broadlink RM [IrTransport].
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ir_core/ir_core.dart';

import 'broadlink_discovery.dart';
import 'broadlink_protocol.dart';

/// Carrier ranges a Broadlink RM hub accepts.
///
/// RM hubs have no carrier setting: they always modulate at a fixed
/// carrier of about 38 kHz. Consumer IR receivers are demodulators with a
/// band-pass response a few kHz wide, so a signal designed for a carrier
/// between 35 and 41 kHz (36, 37.9, 38 and 40 kHz protocols) is reproduced
/// acceptably at 38 kHz. Anything outside (for example 56 kHz or 455 kHz
/// codes) is rejected with [RejectReason.carrierOutOfRange] rather than
/// sent on the wrong carrier.
const List<CarrierRange> broadlinkCarrierRanges = [CarrierRange(35000, 41000)];

/// Default byte budget for one IR payload.
///
/// Keeps every send-data request inside one unfragmented UDP datagram on a
/// 1500-byte MTU: 1472 bytes of UDP payload = 56-byte header + 1408 bytes of
/// AES blocks, minus the 6-byte RM4 command prefix. Small embedded stacks
/// often do not reassemble IP fragments. The device's own limit is not
/// documented.
const int broadlinkDefaultMaxIrPayloadBytes = 1402;

/// Default longest pattern sent in one request, in microseconds.
///
/// The protocol has no documented limit (single durations go up to about
/// 2 s). Two seconds bounds how long one request occupies the hub, keeps a
/// held key's repeats in reasonably short requests and matches the
/// built-in emitter's limit.
const int broadlinkDefaultMaxPatternUs = 2000000;

/// Tuning for [BroadlinkTransport]. Defaults suit a real hub on a LAN;
/// tests shrink the timeouts.
final class BroadlinkTransportOptions {
  /// Creates options.
  const BroadlinkTransportOptions({
    this.requestTimeout = const Duration(seconds: 3),
    this.resendInterval = const Duration(seconds: 1),
    this.learnTimeout = const Duration(seconds: 30),
    this.learnPollInterval = const Duration(milliseconds: 500),
    this.learnRearmInterval = const Duration(seconds: 15),
    this.cancelLearningTimeout = const Duration(seconds: 2),
    this.maxIrPayloadBytes = broadlinkDefaultMaxIrPayloadBytes,
    this.maxPatternUs = broadlinkDefaultMaxPatternUs,
    this.familyOverride,
    this.bindAddress,
  });

  /// How long one request waits for its reply. A send-data request also
  /// gets the on-air time of its payload, in case the hub acknowledges only
  /// after transmitting.
  final Duration requestTimeout;

  /// How often an unanswered idempotent request (hello, auth, learning
  /// commands) is resent within [requestTimeout]. Send-data is never
  /// resent: a lost acknowledgement must not fire the code twice (a power
  /// toggle sent twice turns the device back off).
  final Duration resendInterval;

  /// How long [BroadlinkTransport.learn] waits for a capture.
  final Duration learnTimeout;

  /// Interval between check-data polls while learning.
  final Duration learnPollInterval;

  /// Interval after which learning mode is entered again while waiting.
  final Duration learnRearmInterval;

  /// How long the best-effort cancel-learning request may take.
  final Duration cancelLearningTimeout;

  /// Byte budget for one IR payload (header and trailing gap included).
  final int maxIrPayloadBytes;

  /// Longest pattern per request, reported as
  /// [TransportCapabilities.maxPatternUs].
  final int maxPatternUs;

  /// Command framing to use for a devtype missing from
  /// [broadlinkRmModels]. Without it, unknown devtypes are refused (they
  /// may be Broadlink plugs or sensors, which also answer hello).
  final BroadlinkFamily? familyOverride;

  /// Local address to bind the UDP socket to (any IPv4 by default).
  final InternetAddress? bindAddress;
}

/// Drives a Broadlink RM hub over its local UDP protocol.
///
/// One instance per hub. Requests to the hub are serialized; transmit
/// validates with [SignalValidator] first and never throws. Signals are
/// flattened (frames, repeats and gaps) into one IR payload when they fit
/// the hub's limits, else sent as planned chunks one after another with
/// each chunk's gap waited out. The payload's repeat byte is always 0
/// because repeats are flattened here.
///
/// Unknown devtypes are refused: [transmit] returns
/// [TransmitTransportUnavailable] and [learn] returns `null`, unless
/// [BroadlinkTransportOptions.familyOverride] says how to frame commands.
///
/// Known issues:
/// * Written from the python-broadlink protocol description and its
///   maintained fork's bench notes; not yet tested against a real hub.
/// * Some RM4 owners report Wi-Fi drops or reboots on newer firmware when
///   the hub cannot reach the Broadlink cloud (the reference notes a
///   watchdog on firmware v53+ that a local keep-alive packet feeds; this
///   transport does not send it yet). Leave the hub's internet access as it
///   is; local control does not need it to be blocked.
/// * A hub locked in the Broadlink app answers hello but refuses auth;
///   [health] reports that, and the user has to unlock it in the app.
/// * Learning is IR only, the carrier is not measured (captures report
///   38 kHz) and an RM4 Pro leaves learning mode on its own after 25-40 s,
///   so the transport re-enters it every
///   [BroadlinkTransportOptions.learnRearmInterval].
/// * Whether the hub acknowledges send-data before or after the IR goes
///   out is undocumented; waits between chunks cover both cases, at the
///   cost of a longer gap if it acknowledges early.
/// * The protocol's AES uses a fixed IV and a key handed out on request:
///   it offers no real protection on the LAN.
final class BroadlinkTransport implements IrTransport {
  /// Creates a transport for [device] (usually from [broadlinkHello]).
  BroadlinkTransport({
    required this.device,
    String? displayName,
    this.options = const BroadlinkTransportOptions(),
    Random? random,
  }) : _family = device.model?.family ?? options.familyOverride,
       displayName = _chooseName(displayName, device) {
    _count = 0x8000 | (random ?? Random()).nextInt(0x8000);
    caps = TransportCapabilities(
      carrierRangesHz: broadlinkCarrierRanges,
      maxPatternUs: options.maxPatternUs,
      // Every duration takes at least one byte and the trailing gap at
      // least one more, so more than this can never fit; whether fewer
      // fit depends on how many need the 3-byte form, which transmit
      // checks exactly.
      maxDurations: options.maxIrPayloadBytes - broadlinkIrHeaderLength - 1,
      canLearn: _family != null,
      latencyClass: LatencyClass.lan,
    );
  }

  /// Says hello to [address] and creates a transport for the device that
  /// answers. Throws [BroadlinkTimeoutException] when nothing answers and
  /// [BroadlinkNetworkException] when no socket can be used.
  static Future<BroadlinkTransport> connect(
    InternetAddress address, {
    int port = broadlinkDefaultPort,
    String? displayName,
    BroadlinkTransportOptions options = const BroadlinkTransportOptions(),
  }) async {
    final info = await broadlinkHello(
      address,
      port: port,
      timeout: options.requestTimeout,
      resendInterval: options.resendInterval,
      bindAddress: options.bindAddress,
    );
    if (info == null) {
      throw BroadlinkTimeoutException(
        options.requestTimeout,
        'no Broadlink device answered at ${address.address}:$port',
      );
    }
    return BroadlinkTransport(
      device: info,
      displayName: displayName,
      options: options,
    );
  }

  /// The hub.
  final BroadlinkDeviceInfo device;

  /// Tuning.
  final BroadlinkTransportOptions options;

  final BroadlinkFamily? _family;
  final SignalValidator _validator = const SignalValidator();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  _PendingExchange? _pending;
  final List<int> _recentCounts = [];
  late int _count;

  _Session? _session;
  Future<void> _tail = Future.value();
  int _txGeneration = 0;
  _LearnSession? _activeLearn;
  bool _disposed = false;

  /// Monotonic clock; [_lastSentAt] is the moment the most recent request
  /// frame first went out, so inter-chunk waits do not absorb auth time.
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastSentAt = Duration.zero;

  @override
  String get id => 'broadlink:${device.macString}';

  @override
  final String displayName;

  static String _chooseName(String? explicit, BroadlinkDeviceInfo device) {
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final name = device.name;
    if (name != null && name.isNotEmpty) return name;
    return 'Broadlink ${device.model?.name ?? device.devtypeHex}';
  }

  @override
  TransportKind get kind => TransportKind.broadlink;

  @override
  late final TransportCapabilities caps;

  /// Whether a session key is held (auth has succeeded and not been
  /// invalidated).
  bool get isAuthenticated => _session != null;

  String get _unsupportedDetail =>
      'Broadlink devtype ${device.devtypeHex} at ${device.address.address} '
      'is not a known RM model; it may not be an IR hub';

  // -------------------------------------------------------------------------
  // transmit
  // -------------------------------------------------------------------------

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    final clock = Stopwatch()..start();
    try {
      if (_disposed) {
        return const TransmitTransportUnavailable(
          'Broadlink transport disposed',
        );
      }
      if (_family == null) {
        return TransmitTransportUnavailable(_unsupportedDetail);
      }
      if (repeats < 0) {
        return TransmitRejected(
          RejectReason.invalidDurations,
          'repeats is $repeats; must be >= 0',
        );
      }
      final issues = _validator.validate(signal, caps);
      if (issues.isNotEmpty) {
        return TransmitRejected(issues.first.reason, issues.join('; '));
      }
      final (payloads, rejected) = _planPayloads(signal, repeats);
      if (rejected != null) return rejected;
      return await _serialized(() => _sendPayloads(payloads!, clock));
    } on Object catch (e) {
      return _resultForError(e);
    }
  }

  (List<_PlannedPayload>?, TransmitRejected?) _planPayloads(
    IrSignal signal,
    int repeats,
  ) {
    final frames = signal.frames(repeats: repeats);
    final flat = signal.flatten(repeats: repeats);
    if (_sum(flat) < caps.maxPatternUs && flat.length <= caps.maxDurations!) {
      final single = _encode(flat, frames.last.gapAfterUs);
      if (single != null) return ([single], null);
    }
    final planned = [
      for (final c in _validator.plan(signal, caps, repeats: repeats))
        _encode(c.durationsUs, c.gapAfterUs),
    ];
    if (!planned.contains(null)) return (planned.cast(), null);
    // Joined frames overflowed the byte budget; one frame per request.
    final perFrame = [for (final f in frames) _encode(f.frame, f.gapAfterUs)];
    if (!perFrame.contains(null)) return (perFrame.cast(), null);
    final worst = frames
        .map(
          (f) => BroadlinkIrCode.fromDurations(
            f.frame,
            trailingGapUs: f.gapAfterUs,
          ).encodedLength,
        )
        .reduce(max);
    return (
      null,
      TransmitRejected(
        RejectReason.tooManyDurations,
        'a frame encodes to $worst bytes; the hub accepts at most '
        '${options.maxIrPayloadBytes} bytes per IR code',
      ),
    );
  }

  _PlannedPayload? _encode(List<int> durationsUs, int gapAfterUs) {
    final code = BroadlinkIrCode.fromDurations(
      durationsUs,
      trailingGapUs: gapAfterUs,
    );
    if (code.encodedLength > options.maxIrPayloadBytes) return null;
    return _PlannedPayload(
      code.encode(),
      onAirUs: _sum(durationsUs),
      gapAfterUs: gapAfterUs,
    );
  }

  Future<TransmitResult> _sendPayloads(
    List<_PlannedPayload> payloads,
    Stopwatch clock,
  ) async {
    _txGeneration++;
    for (var i = 0; i < payloads.length; i++) {
      final p = payloads[i];
      final onAir = Duration(microseconds: p.onAirUs);
      final reply = await _command(
        BroadlinkRmCommand.sendData,
        data: p.bytes,
        resend: false,
        timeout: options.requestTimeout + onAir,
      );
      if (reply.errorCode != 0) {
        return _rejectSend(reply.errorCode, i, payloads.length);
      }
      if (i < payloads.length - 1) {
        final gap = Duration(microseconds: p.gapAfterUs);
        final sinceSent = _clock.elapsed - _lastSentAt;
        final untilGapEnds = onAir + gap - sinceSent;
        await Future<void>.delayed(untilGapEnds > gap ? untilGapEnds : gap);
      }
    }
    return TransmitSent(elapsed: clock.elapsed);
  }

  TransmitResult _rejectSend(int code, int index, int count) {
    final where = count > 1 ? ' (chunk ${index + 1} of $count)' : '';
    final detail =
        'hub refused send-data$where: device error $code '
        '(${describeBroadlinkError(code)})';
    final reason = switch (code) {
      BroadlinkErrorCode.sendError ||
      -9 ||
      BroadlinkErrorCode.readError => RejectReason.hardwareError,
      _ => RejectReason.refusedByHub,
    };
    return TransmitRejected(reason, detail);
  }

  TransmitResult _resultForError(Object e) {
    if (e is! BroadlinkException) {
      return TransmitTransportUnavailable('unexpected Broadlink error: $e');
    }
    return switch (e) {
      BroadlinkTimeoutException() => TransmitTimeout(e.after),
      BroadlinkNetworkException() => TransmitTransportUnavailable(e.message),
      BroadlinkDeviceException() => TransmitRejected(
        RejectReason.refusedByHub,
        '${e.message}. If the hub is locked in the Broadlink app, unlock it '
        'there.',
      ),
      BroadlinkFormatException() => TransmitTransportUnavailable(
        'hub sent a reply that could not be read: ${e.message}',
      ),
      BroadlinkUnsupportedDeviceException() => TransmitTransportUnavailable(
        e.message,
      ),
      BroadlinkStateException() => TransmitTransportUnavailable(e.message),
    };
  }

  // -------------------------------------------------------------------------
  // learn
  // -------------------------------------------------------------------------

  /// Starts IR learning. The stream emits one [LearnedSignal] and closes,
  /// or emits a [BroadlinkException] (a [BroadlinkTimeoutException] when
  /// nothing is captured within [BroadlinkTransportOptions.learnTimeout])
  /// and closes. Cancelling the subscription stops polling; the returned
  /// future completes once no further poll will be sent. Learning mode is
  /// then cancelled on the hub on a best-effort basis.
  ///
  /// Returns `null` for an unsupported devtype.
  @override
  Stream<LearnedSignal>? learn() {
    if (!caps.canLearn) return null;
    final session = _LearnSession();
    session.controller = StreamController<LearnedSignal>(
      onListen: () => unawaited(_runLearn(session)),
      onCancel: () {
        session.cancel();
        return session.stopped.future;
      },
    );
    return session.controller.stream;
  }

  Future<void> _runLearn(_LearnSession s) async {
    var armed = false;
    try {
      if (_disposed) {
        throw const BroadlinkNetworkException('Broadlink transport disposed');
      }
      if (_activeLearn != null) {
        throw const BroadlinkStateException(
          'a Broadlink learn session is already running',
        );
      }
      _activeLearn = s;
      final clock = Stopwatch()..start();

      Future<void> arm() async {
        final r = await _serialized(
          () => _command(BroadlinkRmCommand.enterLearning),
        );
        if (r.errorCode != 0) {
          throw BroadlinkDeviceException(
            r.errorCode,
            'hub refused to enter learning mode',
          );
        }
        armed = true;
      }

      await arm();
      var armedAt = clock.elapsed;
      var generation = _txGeneration;
      var timeouts = 0;
      while (!s.cancelled) {
        final remaining = options.learnTimeout - clock.elapsed;
        if (remaining <= Duration.zero) {
          throw BroadlinkTimeoutException(
            options.learnTimeout,
            'no IR signal captured within '
            '${options.learnTimeout.inMilliseconds} ms',
          );
        }
        final poll = options.learnPollInterval;
        await s.sleep(remaining < poll ? remaining : poll);
        if (s.cancelled) break;

        ({int errorCode, Uint8List data})? reply;
        try {
          reply = await _serialized(
            () => _command(BroadlinkRmCommand.checkData),
          );
          timeouts = 0;
        } on BroadlinkTimeoutException {
          if (++timeouts >= 3) rethrow;
          generation = -1; // Device state unknown: re-arm.
        }
        if (reply != null) {
          final code = reply.errorCode;
          final data = reply.data;
          if (code == 0 && data.isNotEmpty && data[0] != 0) {
            final signal = broadlinkCaptureToSignal(data);
            armed = false; // The hub holds one code per learning session.
            if (!s.cancelled) {
              s.controller.add(
                LearnedSignal(signal: signal, capturedAt: DateTime.now()),
              );
            }
            return;
          }
          if (code != 0 && !BroadlinkErrorCode.nothingCaptured.contains(code)) {
            throw BroadlinkDeviceException(code, 'check-data failed');
          }
        }
        final stale = clock.elapsed - armedAt >= options.learnRearmInterval;
        if (!s.cancelled && (generation != _txGeneration || stale)) {
          await arm();
          armedAt = clock.elapsed;
          generation = _txGeneration;
        }
      }
    } on BroadlinkException catch (e) {
      if (!s.cancelled) s.controller.addError(e);
    } on Object catch (e) {
      if (!s.cancelled) {
        s.controller.addError(
          BroadlinkStateException('unexpected learn error: $e'),
        );
      }
    } finally {
      if (identical(_activeLearn, s)) _activeLearn = null;
      s.markStopped();
      unawaited(s.close());
      if (armed && !_disposed) unawaited(_cancelLearningQuietly());
    }
  }

  Future<void> _cancelLearningQuietly() async {
    try {
      await _serialized(
        () => _command(
          BroadlinkRmCommand.cancelLearning,
          resend: false,
          timeout: options.cancelLearningTimeout,
          allowReauth: false,
        ),
      );
    } on Object {
      // Best effort: the hub may not answer, and it leaves learning mode on
      // its own after a while anyway.
    }
  }

  // -------------------------------------------------------------------------
  // health
  // -------------------------------------------------------------------------

  /// Says hello to the hub (latency, identity, lock flag) and makes sure a
  /// session key is held, authenticating if needed. Never throws.
  @override
  Future<HealthStatus> health() async {
    final checkedAt = DateTime.now();
    try {
      if (_disposed) {
        return Unreachable(checkedAt: checkedAt, reason: 'transport disposed');
      }
      final clock = Stopwatch()..start();
      final info = await broadlinkHello(
        device.address,
        port: device.port,
        timeout: options.requestTimeout,
        resendInterval: options.resendInterval,
        bindAddress: options.bindAddress,
      );
      final latency = clock.elapsed;
      if (info == null) {
        return Unreachable(
          checkedAt: checkedAt,
          reason:
              'no answer from ${device.address.address}:${device.port} '
              'within ${options.requestTimeout.inMilliseconds} ms',
        );
      }
      if (info.macString != device.macString) {
        return Unreachable(
          checkedAt: checkedAt,
          reason:
              'a different device (${info.macString}) now answers at '
              '${device.address.address}; expected ${device.macString}',
        );
      }
      if (info.isLocked ?? false) {
        return Unreachable(
          checkedAt: checkedAt,
          reason:
              'the hub is locked in the Broadlink app; unlock it there to '
              'allow local control',
        );
      }
      if (_family == null) {
        return Unreachable(checkedAt: checkedAt, reason: _unsupportedDetail);
      }
      await _serialized(_ensureSession);
      return Healthy(
        checkedAt: checkedAt,
        latency: latency,
        detail: '${device.model?.name ?? 'Broadlink'} ${device.devtypeHex}',
      );
    } on BroadlinkException catch (e) {
      return Unreachable(checkedAt: checkedAt, reason: e.message);
    } on Object catch (e) {
      return Unreachable(checkedAt: checkedAt, reason: 'unexpected: $e');
    }
  }

  // -------------------------------------------------------------------------
  // dispose
  // -------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _activeLearn?.cancel();
    _pending?.fail(
      const BroadlinkNetworkException('Broadlink transport disposed'),
    );
    await _closeSocket();
  }

  // -------------------------------------------------------------------------
  // Session and requests. Everything below runs inside [_serialized].
  // -------------------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }

  Future<void> _ensureSession() async {
    if (_session == null) await _authenticate();
  }

  Future<void> _authenticate() async {
    _session = null;
    final initial = BroadlinkCipher.initial();
    final count = _nextCount();
    final frame = buildBroadlinkFrame(
      packetType: BroadlinkPacketType.auth,
      devtype: device.devtype,
      count: count,
      mac: device.mac,
      sessionId: 0,
      payload: buildBroadlinkAuthPayload(),
      cipher: initial,
    );
    final reply = await _exchange(
      frame,
      count,
      timeout: options.requestTimeout,
      resend: true,
    );
    if (reply.errorCode != 0) {
      throw BroadlinkDeviceException(
        reply.errorCode,
        'hub refused authentication',
      );
    }
    final auth = BroadlinkAuthReply.parse(
      initial.decrypt(reply.encryptedPayload),
    );
    _session = _Session(auth.sessionId, BroadlinkCipher(auth.key));
  }

  /// Sends one RM command and returns the reply's error code and data.
  /// Re-authenticates once when the hub reports a stale session or the
  /// reply cannot be decrypted, then repeats the request.
  Future<({int errorCode, Uint8List data})> _command(
    int command, {
    List<int> data = const [],
    bool resend = true,
    Duration? timeout,
    bool allowReauth = true,
  }) async {
    final family = _family;
    if (family == null) {
      throw BroadlinkUnsupportedDeviceException(_unsupportedDetail);
    }
    await _ensureSession();
    var reauthed = !allowReauth;
    while (true) {
      final session = _session!;
      final count = _nextCount();
      final frame = buildBroadlinkFrame(
        packetType: BroadlinkPacketType.command,
        devtype: device.devtype,
        count: count,
        mac: device.mac,
        sessionId: session.id,
        payload: buildBroadlinkRmCommand(family, command, data),
        cipher: session.cipher,
      );
      final reply = await _exchange(
        frame,
        count,
        timeout: timeout ?? options.requestTimeout,
        resend: resend,
      );
      final code = reply.errorCode;
      if (BroadlinkErrorCode.reauth.contains(code) && !reauthed) {
        reauthed = true;
        await _authenticate();
        continue;
      }
      if (code != 0) return (errorCode: code, data: Uint8List(0));
      try {
        final plain = session.cipher.decrypt(reply.encryptedPayload);
        return (errorCode: 0, data: unwrapBroadlinkRmReply(family, plain));
      } on BroadlinkDecryptException {
        if (reauthed) rethrow;
        reauthed = true;
        await _authenticate();
      }
    }
  }

  int _nextCount() {
    _count = ((_count + 1) | 0x8000) & 0xffff;
    return _count;
  }

  Future<BroadlinkFrame> _exchange(
    Uint8List frame,
    int count, {
    required Duration timeout,
    required bool resend,
  }) async {
    if (_disposed) {
      throw const BroadlinkNetworkException('Broadlink transport disposed');
    }
    final socket = await _openSocket();
    final pending = _PendingExchange(count);
    _pending = pending;
    _recentCounts.add(count);
    if (_recentCounts.length > 64) _recentCounts.removeAt(0);
    Timer? resendTimer;
    final timeoutTimer = Timer(timeout, () {
      final ignored = pending.lastIgnored;
      pending.fail(
        BroadlinkTimeoutException(
          timeout,
          'no reply from ${device.address.address}:${device.port} within '
          '${timeout.inMilliseconds} ms'
          '${ignored == null ? '' : ' (ignored a malformed reply: '
                    '${ignored.message})'}',
        ),
      );
    });
    try {
      _send(socket, frame);
      _lastSentAt = _clock.elapsed;
      if (resend) {
        resendTimer = Timer.periodic(options.resendInterval, (_) {
          try {
            _send(socket, frame);
          } on BroadlinkException catch (e) {
            pending.fail(e);
          }
        });
      }
      return await pending.future;
    } finally {
      resendTimer?.cancel();
      timeoutTimer.cancel();
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void _send(RawDatagramSocket socket, Uint8List frame) {
    try {
      final sent = socket.send(frame, device.address, device.port);
      if (sent != frame.length) {
        throw BroadlinkNetworkException(
          'UDP send to ${device.address.address} wrote $sent of '
          '${frame.length} bytes',
        );
      }
    } on SocketException catch (e) {
      unawaited(_closeSocket());
      throw BroadlinkNetworkException(
        'cannot send to ${device.address.address}:${device.port}: '
        '${e.message}',
      );
    }
  }

  Future<RawDatagramSocket> _openSocket() async {
    final existing = _socket;
    if (existing != null) return existing;
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        options.bindAddress ?? InternetAddress.anyIPv4,
        0,
      );
    } on SocketException catch (e) {
      throw BroadlinkNetworkException('cannot open a UDP socket: ${e.message}');
    }
    if (_disposed) {
      socket.close();
      throw const BroadlinkNetworkException('Broadlink transport disposed');
    }
    _socket = socket;
    _socketSub = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        for (var d = socket.receive(); d != null; d = socket.receive()) {
          _onDatagram(d);
        }
      },
      onError: (Object e) {
        _pending?.fail(BroadlinkNetworkException('UDP socket error: $e'));
        unawaited(_closeSocket());
      },
      onDone: () {
        if (identical(_socket, socket)) {
          _socket = null;
          _socketSub = null;
        }
      },
    );
    return socket;
  }

  void _onDatagram(Datagram d) {
    final pending = _pending;
    if (pending == null) return;
    if (d.address != device.address || d.port != device.port) return;
    final BroadlinkFrame frame;
    try {
      frame = BroadlinkFrame.parse(d.data);
    } on BroadlinkFormatException catch (e) {
      pending.lastIgnored = e;
      return;
    }
    // A reply carrying an earlier request's counter is a late or duplicate
    // answer; one with a counter not used recently is accepted, for
    // firmware that does not echo it.
    if (frame.count != pending.count && _recentCounts.contains(frame.count)) {
      return;
    }
    pending.complete(frame);
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    _socket = null;
    final closing = _socketSub?.cancel();
    _socketSub = null;
    socket?.close();
    await closing;
  }
}

int _sum(List<int> xs) => xs.fold(0, (a, b) => a + b);

final class _Session {
  _Session(this.id, this.cipher);

  final int id;
  final BroadlinkCipher cipher;
}

final class _PlannedPayload {
  _PlannedPayload(
    this.bytes, {
    required this.onAirUs,
    required this.gapAfterUs,
  });

  final Uint8List bytes;
  final int onAirUs;
  final int gapAfterUs;
}

final class _PendingExchange {
  _PendingExchange(this.count);

  final int count;
  final Completer<BroadlinkFrame> _completer = Completer();
  BroadlinkFormatException? lastIgnored;

  Future<BroadlinkFrame> get future => _completer.future;

  void complete(BroadlinkFrame frame) {
    if (!_completer.isCompleted) _completer.complete(frame);
  }

  void fail(BroadlinkException error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}

final class _LearnSession {
  late final StreamController<LearnedSignal> controller;
  final Completer<void> stopped = Completer();
  bool cancelled = false;
  Completer<void>? _wake;

  void cancel() {
    cancelled = true;
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void markStopped() {
    if (!stopped.isCompleted) stopped.complete();
  }

  Future<void> close() => controller.close();

  Future<void> sleep(Duration d) {
    if (cancelled) return Future.value();
    final wake = Completer<void>();
    _wake = wake;
    final timer = Timer(d, () {
      if (!wake.isCompleted) wake.complete();
    });
    return wake.future.whenComplete(timer.cancel);
  }
}
