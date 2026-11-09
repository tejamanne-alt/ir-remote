// The Bonjour discovery lifecycle when the listener leaves early.
import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irremote/services/hub_service.dart';

final class _FakeBrowser implements MdnsBrowser {
  _FakeBrowser(this.ready);

  final Future<void> ready;
  // Never emits; a broadcast stream needs no listener cleanup.
  // ignore: close_sinks
  final events = StreamController<BonsoirDiscoveryEvent>.broadcast();
  var started = false;
  var stopped = false;

  @override
  Future<void> initialize() => ready;

  @override
  Stream<BonsoirDiscoveryEvent>? get eventStream => events.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => stopped = true;

  @override
  void resolve(BonsoirService service) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/network');
  late List<String> lockCalls;
  late Completer<void> lockReply;

  setUp(() {
    lockCalls = [];
    lockReply = Completer<void>()..complete();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          lockCalls.add(call.method);
          if (call.method == 'acquireMulticastLock') await lockReply.future;
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('cancelling while the browser initializes stops it and releases the '
      'lock', () async {
    final ready = Completer<void>();
    final browser = _FakeBrowser(ready.future);
    final d = BonsoirBridgeDiscovery(
      network: channel,
      browserFactory: (_) => browser,
    );
    final sub = d.discover().listen((_) {});
    await pumpEventQueue();
    await sub.cancel();
    ready.complete();
    await pumpEventQueue();
    expect(browser.started, isFalse);
    expect(browser.stopped, isTrue);
    expect(lockCalls, ['acquireMulticastLock', 'releaseMulticastLock']);
  });

  test('cancelling while the lock is acquired starts nothing', () async {
    lockReply = Completer<void>();
    var created = 0;
    final d = BonsoirBridgeDiscovery(
      network: channel,
      browserFactory: (_) {
        created++;
        return _FakeBrowser(Future<void>.value());
      },
    );
    final sub = d.discover().listen((_) {});
    await pumpEventQueue();
    await sub.cancel();
    lockReply.complete();
    await pumpEventQueue();
    expect(created, 0);
    expect(lockCalls, ['acquireMulticastLock', 'releaseMulticastLock']);
  });

  test(
    'a set-up failure after cancel is not added to the closed stream',
    () async {
      // An uncaught "Cannot add event after closing" fails the test.
      final ready = Completer<void>();
      final browser = _FakeBrowser(ready.future);
      final d = BonsoirBridgeDiscovery(
        network: channel,
        browserFactory: (_) => browser,
      );
      final sub = d.discover().listen((_) {}, onError: (Object _) {});
      await pumpEventQueue();
      await sub.cancel();
      ready.completeError(StateError('platform browser failed'));
      await pumpEventQueue();
      expect(lockCalls, ['acquireMulticastLock', 'releaseMulticastLock']);
    },
  );

  test('a running browse is stopped once on cancel', () async {
    final browser = _FakeBrowser(Future<void>.value());
    final d = BonsoirBridgeDiscovery(
      network: channel,
      browserFactory: (_) => browser,
    );
    final lists = <List<DiscoveredBridge>>[];
    final sub = d.discover().listen(lists.add);
    await pumpEventQueue();
    expect(browser.started, isTrue);
    expect(lists, [isEmpty]);
    await sub.cancel();
    expect(browser.stopped, isTrue);
    expect(lockCalls, ['acquireMulticastLock', 'releaseMulticastLock']);
  });
}
