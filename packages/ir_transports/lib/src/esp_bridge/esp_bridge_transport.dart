/// Client for the ESP32 reference bridge (docs/BRIDGE_API.md, API v1).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ir_core/ir_core.dart';

/// Largest HTTP or WebSocket message accepted from a bridge.
const int maxBridgeMessageBytes = 64 * 1024;

/// Most durations accepted in one capture.
const int maxCaptureDurations = 10000;

/// What `GET /v1/info` reports.
final class BridgeInfo {
  /// Creates an info record.
  const BridgeInfo({
    required this.api,
    required this.firmware,
    required this.id,
    required this.name,
    required this.caps,
    required this.pairingWindowOpen,
    this.acProtocols = const [],
  });

  /// API version; this client speaks 1.
  final int api;

  /// Firmware version.
  final String firmware;

  /// Bridge ID (MAC, 12 hex digits).
  final String id;

  /// User-visible name.
  final String name;

  /// Transport capabilities derived from the bridge's caps.
  final TransportCapabilities caps;

  /// Whether the pairing button was pressed in the last 60 s.
  final bool pairingWindowOpen;

  /// AC protocols the firmware encodes (empty in v1).
  final List<String> acProtocols;

  /// Parses an info body; throws [FormatException] on anything unexpected.
  static BridgeInfo fromJson(Object? json) {
    if (json is! Map) throw const FormatException('info must be an object');
    final caps = json['caps'];
    if (caps is! Map) throw const FormatException('info.caps missing');
    int i(Map<Object?, Object?> m, String k) {
      final v = m[k];
      if (v is! int) throw FormatException('info field $k must be an integer');
      return v;
    }

    String s(String k) {
      final v = json[k];
      if (v is! String || v.length > 64) {
        throw FormatException('info field $k must be a short string');
      }
      return v;
    }

    final minHz = i(caps, 'carrierMinHz');
    final maxHz = i(caps, 'carrierMaxHz');
    if (minHz <= 0 || maxHz < minHz) {
      throw const FormatException('info carrier range is invalid');
    }
    final ac = caps['ac'];
    return BridgeInfo(
      api: i(json, 'api'),
      firmware: s('fw'),
      id: s('id'),
      name: s('name'),
      pairingWindowOpen: json['pairingWindowOpen'] == true,
      acProtocols: ac is List
          ? [
              for (final p in ac)
                if (p is String) p,
            ]
          : const [],
      caps: TransportCapabilities(
        carrierRangesHz: [CarrierRange(minHz, maxHz)],
        maxPatternUs: i(caps, 'maxPatternUs'),
        maxDurations: i(caps, 'maxDurations'),
        canLearn: caps['canLearn'] == true,
        latencyClass: LatencyClass.lan,
      ),
    );
  }
}

/// A bridge error response (`{"error": code, "detail": text}`).
final class BridgeException implements Exception {
  /// Creates the exception.
  const BridgeException(this.status, this.code, this.detail);

  /// HTTP status.
  final int status;

  /// Contract error code, for example `pairing_window_closed`.
  final String code;

  /// Human-readable detail.
  final String detail;

  @override
  String toString() => 'BridgeException($status $code): $detail';
}

/// Learn mode ended without a capture.
final class LearnTimeoutException implements Exception {
  /// Creates the exception.
  const LearnTimeoutException();

  @override
  String toString() => 'No signal received before the timeout.';
}

/// Sends IR through an ESP32 bridge over HTTP, learns over its WebSocket.
final class EspBridgeTransport implements IrTransport {
  /// Creates a client for the bridge at [baseUri] (for example
  /// `http://192.168.1.40`). [token] comes from [pair].
  EspBridgeTransport({
    required this.baseUri,
    required this.id,
    this.displayName = 'IR Bridge',
    this.token,
    this.requestTimeout = const Duration(seconds: 3),
    this.learnTimeout = const Duration(seconds: 15),
    TransportCapabilities? caps,
    this.validator = const SignalValidator(),
  }) : caps = caps ?? defaultCaps {
    _http.connectionTimeout = requestTimeout;
  }

  /// Caps assumed until `GET /v1/info` has been read.
  static const TransportCapabilities defaultCaps = TransportCapabilities(
    carrierRangesHz: [CarrierRange(30000, 60000)],
    maxPatternUs: 4000000,
    maxDurations: 1024,
    canLearn: true,
    latencyClass: LatencyClass.lan,
  );

  /// Bridge base URI.
  final Uri baseUri;

  @override
  final String id;

  @override
  final String displayName;

  /// Pairing token, or `null` before pairing.
  String? token;

  /// Per-request timeout.
  final Duration requestTimeout;

  /// How long single-capture learn mode waits.
  final Duration learnTimeout;

  /// Validator applied before any request.
  final SignalValidator validator;

  @override
  TransportCapabilities caps;

  @override
  TransportKind get kind => TransportKind.espBridge;

  final HttpClient _http = HttpClient();
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Reads `GET /v1/info` and adopts the bridge's capabilities.
  Future<BridgeInfo> fetchInfo() async {
    final body = await _request('GET', '/v1/info', auth: false);
    final info = BridgeInfo.fromJson(body);
    if (info.api != 1) {
      throw BridgeException(
        200,
        'unsupported_api',
        'bridge speaks API ${info.api}',
      );
    }
    caps = info.caps;
    return info;
  }

  /// Pairs with the bridge while its pairing window is open, storing and
  /// returning the token.
  Future<String> pair(String clientName) async {
    final name = clientName.length > 32
        ? clientName.substring(0, 32)
        : clientName;
    final body = await _request(
      'POST',
      '/v1/pair',
      body: {'client': name},
      auth: false,
    );
    final t = body is Map ? body['token'] : null;
    if (t is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(t)) {
      throw const FormatException('pair response has no valid token');
    }
    token = t;
    return t;
  }

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    final stopwatch = Stopwatch()..start();
    final issues = validator.validate(signal, caps);
    if (issues.isNotEmpty) {
      return TransmitRejected(issues.first.reason, issues.first.detail);
    }
    if (token == null) {
      return const TransmitRejected(
        RejectReason.refusedByHub,
        'this hub is not paired yet; press its button and pair again',
      );
    }
    final chunks = validator.plan(signal, caps, repeats: repeats);
    for (final chunk in chunks) {
      final wait = _quietUntil.difference(DateTime.now());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      final r = await _sendChunk(chunk);
      _quietUntil = DateTime.now().add(
        Duration(microseconds: chunk.gapAfterUs),
      );
      if (r != null) return r;
    }
    return TransmitSent(elapsed: stopwatch.elapsed);
  }

  /// Sends one chunk; returns `null` on success or the failure result.
  Future<TransmitResult?> _sendChunk(TransmitChunk chunk) async {
    const maxBusyRetries = 3;
    for (var attempt = 0; ; attempt++) {
      try {
        await _request(
          'POST',
          '/v1/send/raw',
          // The bridge answers after the pattern has been sent, so allow
          // for its length on top of the network timeout.
          timeout: requestTimeout + Duration(microseconds: chunk.lengthUs),
          body: {
            'carrierHz': chunk.carrierHz,
            'durationsUs': chunk.durationsUs,
          },
        );
        return null;
      } on BridgeException catch (e) {
        if (e.code == 'busy' && attempt < maxBusyRetries) {
          await Future<void>.delayed(
            Duration(milliseconds: 40 * (attempt + 1)),
          );
          continue;
        }
        return _mapError(e);
      } on TimeoutException {
        return TransmitTimeout(requestTimeout);
      } on SocketException catch (e) {
        return TransmitTransportUnavailable('hub unreachable: ${e.message}');
      } on HttpException catch (e) {
        return TransmitTransportUnavailable(
          'hub connection failed: ${e.message}',
        );
      } on FormatException catch (e) {
        return TransmitTransportUnavailable(
          'hub sent an invalid reply: ${e.message}',
        );
      }
    }
  }

  TransmitResult _mapError(BridgeException e) => switch (e.code) {
    'invalid_durations' => TransmitRejected(
      RejectReason.invalidDurations,
      e.detail,
    ),
    'carrier_out_of_range' => TransmitRejected(
      RejectReason.carrierOutOfRange,
      e.detail,
    ),
    'too_large' => TransmitRejected(RejectReason.tooManyDurations, e.detail),
    'unauthorized' => const TransmitRejected(
      RejectReason.refusedByHub,
      'the hub no longer recognises this phone; pair it again',
    ),
    'busy' => const TransmitRejected(
      RejectReason.hardwareError,
      'hub stayed busy',
    ),
    _ => TransmitRejected(RejectReason.refusedByHub, '${e.code}: ${e.detail}'),
  };

  @override
  Future<HealthStatus> health() async {
    final stopwatch = Stopwatch()..start();
    try {
      if (token == null) {
        await _request('GET', '/v1/info', auth: false);
        return Degraded(
          checkedAt: DateTime.now(),
          reason: 'reachable but not paired',
        );
      }
      final body = await _request('GET', '/v1/health');
      if (body is Map && body['ok'] == true) {
        return Healthy(
          checkedAt: DateTime.now(),
          latency: stopwatch.elapsed,
          detail: 'uptime ${body['uptimeS']} s',
        );
      }
      return Degraded(
        checkedAt: DateTime.now(),
        reason: 'hub reported a problem',
      );
    } on BridgeException catch (e) {
      if (e.code == 'unauthorized') {
        return Degraded(
          checkedAt: DateTime.now(),
          reason: 'pairing was cleared on the hub',
        );
      }
      return Degraded(checkedAt: DateTime.now(), reason: e.detail);
    } on Object catch (e) {
      return Unreachable(checkedAt: DateTime.now(), reason: _describe(e));
    }
  }

  @override
  Stream<LearnedSignal>? learn() =>
      caps.canLearn ? learnStream(continuous: false) : null;

  /// Learn mode: a single capture (ends after the first one or the timeout),
  /// or with [continuous] the capture mode used by the test rig.
  Stream<LearnedSignal> learnStream({bool continuous = false}) {
    late StreamController<LearnedSignal> controller;
    WebSocket? socket;
    StreamSubscription<Object?>? sub;
    var closed = false;

    Future<void> stop({bool remote = true}) async {
      if (closed) return;
      closed = true;
      await sub?.cancel();
      await socket?.close();
      if (remote) {
        try {
          await _request('DELETE', '/v1/learn');
        } on Object {
          // best effort: the bridge also times out on its own
        }
      }
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<LearnedSignal>(
      onListen: () async {
        try {
          final wsUri = baseUri.replace(
            scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
            path: '/v1/ws',
          );
          socket = await WebSocket.connect(
            wsUri.toString(),
            headers: {'Authorization': 'Bearer ${token ?? ''}'},
          ).timeout(requestTimeout);
          sub = socket!.listen(
            (msg) {
              if (msg is! String || msg.length > maxBridgeMessageBytes) return;
              final event = _parseWsEvent(msg);
              switch (event) {
                case final LearnedSignal s:
                  controller.add(s);
                  if (!continuous) unawaited(stop());
                case 'learn_timeout':
                  controller.addError(const LearnTimeoutException());
                  unawaited(stop(remote: false));
                case 'learn_stopped':
                  unawaited(stop(remote: false));
                default:
                  break; // malformed or unknown: ignore
              }
            },
            onError: (Object e) {
              controller.addError(e);
              unawaited(stop(remote: false));
            },
            onDone: () => unawaited(stop(remote: false)),
          );
          await _request(
            'POST',
            '/v1/learn',
            body: {'timeoutMs': continuous ? 0 : learnTimeout.inMilliseconds},
          );
        } on Object catch (e) {
          controller.addError(e);
          await stop(remote: false);
        }
      },
      onCancel: () => stop(),
    );
    return controller.stream;
  }

  static Object? _parseWsEvent(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final type = json['type'];
    if (type != 'capture') return type is String ? type : null;
    final d = json['durationsUs'];
    if (d is! List || d.isEmpty || d.length > maxCaptureDurations) return null;
    final durations = <int>[];
    for (final v in d) {
      if (v is! int || v <= 0 || v > 1000000) return null;
      durations.add(v);
    }
    if (durations.length.isEven) durations.removeLast(); // trailing gap
    if (durations.isEmpty) return null;
    final carrier = json['carrierHz'];
    final decoded = json['decoded'];
    return LearnedSignal(
      signal: IrSignal(
        carrierHz: carrier is int && carrier > 0 ? carrier : 38000,
        durationsUs: durations,
      ),
      capturedAt: DateTime.now(),
      hubDecodedProtocol: decoded is Map && decoded['protocol'] is String
          ? decoded['protocol'] as String
          : null,
      hubDecodedValue: decoded is Map && decoded['value'] is String
          ? decoded['value'] as String
          : null,
    );
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    Duration? timeout,
  }) async {
    Future<Object?> run() async {
      final req = await _http.openUrl(method, baseUri.replace(path: path));
      req.headers.contentType = ContentType.json;
      if (auth && token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        // A fixed Content-Length, not chunked encoding: embedded HTTP
        // servers handle it more reliably.
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close();
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > maxBridgeMessageBytes) {
          throw const FormatException('reply too large');
        }
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final Object? json = text.isEmpty ? null : jsonDecode(text);
      if (res.statusCode >= 400) {
        final code = json is Map && json['error'] is String
            ? json['error'] as String
            : 'http_${res.statusCode}';
        final detail = json is Map && json['detail'] is String
            ? json['detail'] as String
            : 'HTTP ${res.statusCode}';
        throw BridgeException(res.statusCode, code, detail);
      }
      return json;
    }

    return run().timeout(timeout ?? requestTimeout);
  }

  static String _describe(Object e) => switch (e) {
    SocketException(:final message) => 'hub unreachable: $message',
    TimeoutException() => 'hub did not answer in time',
    _ => 'hub error: $e',
  };

  @override
  Future<void> dispose() async => _http.close(force: true);
}
