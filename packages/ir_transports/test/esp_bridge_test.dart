// EspBridgeTransport against a fake bridge that implements docs/BRIDGE_API.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:test/test.dart';

const _token = '0123456789abcdef0123456789abcdef';

/// Minimal in-process bridge implementing the v1 contract.
final class FakeBridge {
  late final HttpServer _server;
  bool pairingOpen = false;
  final List<Map<String, Object?>> sends = [];
  int busyResponses = 0;
  bool learning = false;
  int learnTimeoutMs = -1;
  WebSocket? socket;
  Duration sendDelay = Duration.zero;
  bool silent = false;
  String? rawInfo;
  Uri? redirectTo;
  int requests = 0;
  int lastContentLength = -1;
  bool closeUnauthorizedAfterUpgrade = false;
  bool lastChunked = false;
  Duration wsDelay = Duration.zero;
  int learnStarts = 0;
  int socketsOpened = 0;
  int socketsClosed = 0;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() async {
    await socket?.close();
    await _server.close(force: true);
  }

  void _json(HttpRequest r, int status, Object body) {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    unawaited(r.response.close());
  }

  void _error(HttpRequest r, int status, String code) =>
      _json(r, status, {'error': code, 'detail': 'fake: $code'});

  Future<void> _handle(HttpRequest r) async {
    requests++;
    if (silent) return; // never answer
    if (redirectTo != null) {
      return r.response.redirect(redirectTo!.replace(path: r.uri.path));
    }
    final path = r.uri.path;
    final authed =
        r.headers.value(HttpHeaders.authorizationHeader) == 'Bearer $_token';
    lastContentLength = r.contentLength;
    lastChunked = r.headers.chunkedTransferEncoding;
    final text = await utf8.decodeStream(r);
    Object? body;
    if (text.isNotEmpty) body = jsonDecode(text);

    if (path == '/v1/info' && r.method == 'GET') {
      if (rawInfo != null) {
        r.response.write(rawInfo);
        return r.response.close();
      }
      return _json(r, 200, {
        'api': 1,
        'fw': '0.1.0',
        'id': 'a1b2c3d4e5f6',
        'name': 'Fake Bridge',
        'caps': {
          'carrierMinHz': 30000,
          'carrierMaxHz': 60000,
          'maxPatternUs': 4000000,
          'maxDurations': 1024,
          'canLearn': true,
          'ac': <String>[],
        },
        'pairingWindowOpen': pairingOpen,
      });
    }
    if (path == '/v1/pair' && r.method == 'POST') {
      if (!pairingOpen) return _error(r, 403, 'pairing_window_closed');
      pairingOpen = false;
      return _json(r, 200, {'token': _token});
    }
    if (path == '/v1/ws') {
      if (!authed && closeUnauthorizedAfterUpgrade) {
        // esp_http_server firmware: upgrade first, then close with 1008.
        final s = await WebSocketTransformer.upgrade(r);
        await s.close(1008, 'unauthorized');
        return;
      }
      if (!authed) return _error(r, 401, 'unauthorized');
      await Future<void>.delayed(wsDelay);
      socket = await WebSocketTransformer.upgrade(r);
      socketsOpened++;
      socket!.listen((_) {}, onDone: () => socketsClosed++);
      return;
    }
    if (!authed) return _error(r, 401, 'unauthorized');
    switch ((r.method, path)) {
      case ('GET', '/v1/health'):
        return _json(r, 200, {
          'ok': true,
          'uptimeS': 12,
          'rssi': -50,
          'freeHeap': 1,
          'learning': learning,
        });
      case ('POST', '/v1/send/raw'):
        if (busyResponses > 0) {
          busyResponses--;
          return _error(r, 409, 'busy');
        }
        final m = body! as Map<String, Object?>;
        final carrier = m['carrierHz']! as int;
        if (carrier < 30000 || carrier > 60000) {
          return _error(r, 400, 'carrier_out_of_range');
        }
        await Future<void>.delayed(sendDelay);
        sends.add(m);
        return _json(r, 200, {'sent': true, 'elapsedUs': 1000});
      case ('POST', '/v1/learn'):
        learnStarts++;
        learning = true;
        learnTimeoutMs = (body! as Map)['timeoutMs'] as int;
        return _json(r, 202, {'learning': true});
      case ('DELETE', '/v1/learn'):
        learning = false;
        return _json(r, 200, {'learning': false});
    }
    return _error(r, 404, 'not_found');
  }
}

Future<void> _waitFor(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue);
}

void main() {
  late FakeBridge bridge;
  late EspBridgeTransport client;
  final nec = const Nec1().encode({'D': 4, 'F': 8});

  setUp(() async {
    bridge = FakeBridge();
    await bridge.start();
    client = EspBridgeTransport(
      baseUri: bridge.uri,
      id: 'esp:a1b2c3d4e5f6',
      requestTimeout: const Duration(milliseconds: 500),
    );
  });

  tearDown(() async {
    await client.dispose();
    await bridge.stop();
  });

  test('reads info and adopts the bridge caps', () async {
    final info = await client.fetchInfo();
    expect(info.firmware, '0.1.0');
    expect(info.name, 'Fake Bridge');
    expect(client.caps.maxDurations, 1024);
    expect(client.caps.canLearn, isTrue);
    expect(client.kind, TransportKind.espBridge);
  });

  test('rejects malformed or future-API info', () async {
    bridge.rawInfo =
        '{"api": 2, "fw": "9", "id": "x", "name": "n", "caps": '
        '{"carrierMinHz": 1, "carrierMaxHz": 2, "maxPatternUs": 1, "maxDurations": 1}}';
    await expectLater(client.fetchInfo(), throwsA(isA<BridgeException>()));
    for (final bad in [
      null,
      1,
      {'caps': 1},
      {
        'caps': {'carrierMinHz': 'x'},
      },
    ]) {
      expect(() => BridgeInfo.fromJson(bad), throwsFormatException);
    }
  });

  test('pairing needs the button window and stores the token', () async {
    await expectLater(
      client.pair('Phone'),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          'pairing_window_closed',
        ),
      ),
    );
    bridge.pairingOpen = true;
    expect(
      await client.pair('A very long phone name that exceeds the limit'),
      _token,
    );
    expect(client.token, _token);
  });

  test(
    'refuses to send before pairing, without touching the network',
    () async {
      final r = await client.transmit(nec);
      expect((r as TransmitRejected).reason, RejectReason.refusedByHub);
      expect(bridge.sends, isEmpty);
    },
  );

  group('paired', () {
    setUp(() => client.token = _token);

    test('sends the flattened pattern and reports success', () async {
      final r = await client.transmit(nec, repeats: 2);
      expect(r, isA<TransmitSent>());
      expect(bridge.sends.single['carrierHz'], 38400);
      expect(bridge.sends.single['durationsUs'], nec.flatten(repeats: 2));
    });

    test(
      'rejects an out-of-range carrier locally; never substitutes',
      () async {
        final r = await client.transmit(
          IrSignal(carrierHz: 455000, durationsUs: [100]),
        );
        expect((r as TransmitRejected).reason, RejectReason.carrierOutOfRange);
        expect(bridge.sends, isEmpty);
      },
    );

    test('maps hub-side carrier refusal', () async {
      client.caps = const TransportCapabilities(
        carrierRangesHz: [CarrierRange(20000, 90000)],
        maxPatternUs: 4000000,
        canLearn: true,
        latencyClass: LatencyClass.lan,
      );
      final r = await client.transmit(
        IrSignal(carrierHz: 80000, durationsUs: [100]),
      );
      expect((r as TransmitRejected).reason, RejectReason.carrierOutOfRange);
    });

    test('retries while busy, then succeeds', () async {
      bridge.busyResponses = 2;
      expect(await client.transmit(nec), isA<TransmitSent>());
      bridge.busyResponses = 10;
      final r = await client.transmit(nec);
      expect((r as TransmitRejected).detail, contains('busy'));
    });

    test('splits long holds into chunks within maxDurations', () async {
      final r = await client.transmit(nec, repeats: 40);
      expect(r, isA<TransmitSent>());
      expect(bridge.sends.length, greaterThan(1));
      for (final s in bridge.sends) {
        expect((s['durationsUs']! as List).length, lessThanOrEqualTo(1024));
      }
    });

    test('a lost token maps to a re-pair message', () async {
      client.token = 'ffffffffffffffffffffffffffffffff';
      final r = await client.transmit(nec);
      expect((r as TransmitRejected).detail, contains('pair it again'));
      expect(await client.health(), isA<Degraded>());
    });

    test('a long pattern gets time to transmit before the reply', () async {
      // The bridge replies after transmitting; 600 ms of pattern must not
      // trip a 500 ms network timeout.
      bridge.sendDelay = const Duration(milliseconds: 650);
      final long = IrSignal(
        carrierHz: 38000,
        durationsUs: [for (var i = 0; i < 61; i++) i.isEven ? 10000 : 10000],
      );
      expect(await client.transmit(long), isA<TransmitSent>());
    });

    test('requests carry a Content-Length instead of chunked bodies', () async {
      expect(await client.transmit(nec), isA<TransmitSent>());
      expect(bridge.lastContentLength, greaterThan(0));
      expect(bridge.lastChunked, isFalse);
    });

    test('health reports latency', () async {
      final h = await client.health();
      expect(h, isA<Healthy>());
      expect((h as Healthy).latency, isNotNull);
    });

    test('a silent hub times out; an absent hub is unavailable', () async {
      bridge.silent = true;
      expect(await client.transmit(nec), isA<TransmitTimeout>());
      expect(await client.health(), isA<Unreachable>());
      final deadUri = bridge.uri;
      await bridge.stop();
      final gone = EspBridgeTransport(
        baseUri: deadUri,
        id: 'gone',
        token: _token,
        requestTimeout: const Duration(milliseconds: 300),
      );
      final r = await gone.transmit(nec);
      expect(
        r,
        anyOf(isA<TransmitTransportUnavailable>(), isA<TransmitTimeout>()),
      );
      await gone.dispose();
      bridge = FakeBridge();
      await bridge.start(); // for tearDown
    });

    test('learn yields the first capture and stops learn mode', () async {
      final first = client.learn()!.first;
      await _waitFor(() => bridge.socket != null && bridge.learning);
      expect(bridge.learnTimeoutMs, 15000);
      bridge.socket!
        ..add('not json')
        ..add(
          jsonEncode({
            'type': 'capture',
            'durationsUs': [-1],
          }),
        )
        ..add(
          jsonEncode({
            'type': 'capture',
            'carrierHz': null,
            'durationsUs': [...nec.durationsUs, 40000],
            'decoded': {'protocol': 'NEC', 'value': '0x20DF10EF', 'bits': 32},
          }),
        );
      final s = await first;
      expect(s.signal.durationsUs, nec.durationsUs);
      expect(s.signal.carrierHz, 38000);
      expect(s.hubDecodedProtocol, 'NEC');
      expect(ProtocolRegistry.standard.identify(s.signal.durationsUs)!.params, {
        'D': 4,
        'S': 251,
        'F': 8,
      });
      await _waitFor(() => !bridge.learning);
    });

    test('learn timeout surfaces as a typed error', () async {
      final events = client.learn()!;
      final done = expectLater(
        events,
        emitsError(isA<LearnTimeoutException>()),
      );
      await _waitFor(() => bridge.socket != null);
      bridge.socket!.add(jsonEncode({'type': 'learn_timeout'}));
      await done;
      expect(const LearnTimeoutException().toString(), contains('timeout'));
    });

    test('continuous capture keeps streaming until cancelled', () async {
      final got = <LearnedSignal>[];
      final sub = client.learnStream(continuous: true).listen(got.add);
      await _waitFor(() => bridge.socket != null && bridge.learning);
      expect(bridge.learnTimeoutMs, 0);
      for (var i = 0; i < 3; i++) {
        bridge.socket!.add(
          jsonEncode({
            'type': 'capture',
            'carrierHz': 36000,
            'durationsUs': [889, 889, 889],
          }),
        );
      }
      await _waitFor(() => got.length == 3);
      expect(got.first.signal.carrierHz, 36000);
      await sub.cancel();
      await _waitFor(() => !bridge.learning);
    });
  });

  group('lifecycle', () {
    setUp(() => client.token = _token);

    test('cancelling learn before the socket connects leaves nothing '
        'open', () async {
      bridge.wsDelay = const Duration(milliseconds: 50);
      final sub = client.learnStream(continuous: true).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await _waitFor(() => bridge.socketsOpened == 1);
      await _waitFor(() => bridge.socketsClosed == 1);
      expect(bridge.learnStarts, 0, reason: 'learn mode never started');
      expect(bridge.learning, isFalse);
    });

    test('a socket that connects after the timeout is closed', () async {
      bridge.wsDelay = const Duration(milliseconds: 700);
      await expectLater(client.learn()!, emitsError(isA<TimeoutException>()));
      await _waitFor(() => bridge.socketsOpened == 1);
      await _waitFor(() => bridge.socketsClosed == 1);
      expect(bridge.learnStarts, 0);
    });

    test('dispose ends an open learn stream', () async {
      final done = client.learnStream(continuous: true).toList();
      await _waitFor(() => bridge.socket != null && bridge.learning);
      await client.dispose();
      expect(await done, isEmpty);
      await _waitFor(() => bridge.socketsClosed == 1);
    });

    test('after dispose, transmit and health answer instead of '
        'throwing', () async {
      await client.dispose();
      expect(await client.transmit(nec), isA<TransmitTransportUnavailable>());
      expect(await client.health(), isA<Unreachable>());
      await expectLater(client.learn()!, emitsError(isA<StateError>()));
    });

    test('a negative repeat count is rejected, not thrown', () async {
      final r = await client.transmit(nec, repeats: -1);
      expect(
        r,
        isA<TransmitRejected>().having(
          (e) => e.reason,
          'reason',
          RejectReason.invalidDurations,
        ),
      );
      expect(bridge.sends, isEmpty);
    });

    test('a timed-out request frees its connection', () async {
      // A raw TCP peer that reads the request and never answers, so the
      // client's side of the connection closing is visible.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var opened = 0;
      var closed = 0;
      server.listen((s) {
        opened++;
        s.listen((_) {}, onDone: () => closed++, onError: (_) => closed++);
      });
      final mute = EspBridgeTransport(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        id: 'mute',
        token: _token,
        requestTimeout: const Duration(milliseconds: 200),
      );
      expect(await mute.transmit(nec), isA<TransmitTimeout>());
      expect(opened, 1);
      await _waitFor(() => closed == 1);
      await mute.dispose();
      await server.close();
    });

    test('redirects are not followed', () async {
      final elsewhere = FakeBridge();
      await elsewhere.start();
      bridge.redirectTo = elsewhere.uri;
      expect(await client.health(), isNot(isA<Healthy>()));
      expect(await client.transmit(nec), isA<TransmitRejected>());
      expect(elsewhere.sends, isEmpty);
      expect(elsewhere.requests, 0, reason: 'never contacted');
      await elsewhere.stop();
    });

    test('an unpaired or de-paired hub answers but cannot send', () async {
      client.token = null;
      final unpaired = await client.health();
      expect(unpaired, isA<Degraded>());
      expect(unpaired.isUsable, isFalse);
      client.token = 'ffffffffffffffffffffffffffffffff';
      final cleared = await client.health();
      expect(cleared, isA<Degraded>());
      expect(cleared.isUsable, isFalse);
    });
  });

  test('learn without a token fails cleanly', () async {
    await expectLater(client.learn()!, emitsError(anything));
  });

  test('a 1008 close after the upgrade surfaces as unauthorized', () async {
    bridge.closeUnauthorizedAfterUpgrade = true;
    client.token = 'ffffffffffffffffffffffffffffffff';
    await expectLater(
      client.learn()!,
      emitsError(
        isA<BridgeException>().having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
  });
}
