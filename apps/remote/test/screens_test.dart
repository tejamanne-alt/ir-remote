import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/services/app_services.dart';
import 'package:irremote/services/app_settings.dart';
import 'package:irremote/services/hub_service.dart';
import 'package:irremote/transports/android_consumer_ir.dart';
import 'package:irremote/ui/ac/ac_panel.dart';
import 'package:irremote/ui/hubs/hubs_screen.dart';
import 'package:irremote/ui/remote/remote_screen.dart';
import 'package:irremote/ui/settings/settings_screen.dart';
import 'package:irremote/ui/widgets/remote_button.dart';

import 'helpers.dart';

/// The real HTTP client, instead of flutter_test's always-400 mock.
final class _RealHttp extends HttpOverrides {}

Future<SavedDevice> _saveTv(
  AppServices services, {
  String id = 'tv',
  String set = 'samsung-a',
  DeviceCategory category = DeviceCategory.tv,
}) async {
  final codes = testLibrary().byId(set)!;
  final d = SavedDevice(
    id: id,
    name: 'Test TV',
    category: category,
    brand: codes.brand,
    codeSetId: set,
    createdAt: DateTime(2026, 11, 9),
    keys: {
      for (final e in codes.keys.entries) e.key: snapshotKey(e.key, e.value),
    },
  );
  await services.devices.save(d);
  return d;
}

Future<void> _openRemote(WidgetTester tester, String id) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => RemoteScreen(deviceId: id)));
  await settle(tester);
}

void main() {
  group('onboarding', () {
    testWidgets('a phone with an emitter is told it can send IR', (
      tester,
    ) async {
      final (s, _) = await buildServices(
        emitter: const EmitterInfo(
          platformSupported: true,
          hasFeature: true,
          hasEmitter: true,
        ),
        withSimulator: false,
      );
      await pumpApp(tester, s, onboarded: false);
      expect(find.text('Your phone can send IR'), findsOneWidget);
      expect(find.text('Add your first device'), findsOneWidget);
      expect(find.textContaining('clear line of sight'), findsOneWidget);
      await disposeServices(tester, s);
    });

    testWidgets(
      'an iPhone leads with "Connect a hub" and says one is required',
      (tester) async {
        final (s, _) = await buildServices(
          platform: TargetPlatform.iOS,
          withSimulator: false,
        );
        await pumpApp(tester, s, onboarded: false);
        expect(find.text('Connect a hub'), findsWidgets);
        expect(
          find.textContaining('iPhones have no IR blaster'),
          findsOneWidget,
        );
        expect(find.text('Supported hubs'), findsOneWidget);
        await disposeServices(tester, s);
      },
    );

    testWidgets(
      'Android without an emitter lists what works, with no dead end',
      (tester) async {
        final (s, _) = await buildServices(withSimulator: false);
        await pumpApp(tester, s, onboarded: false);
        expect(
          find.text("This phone can't send IR. Here's what works"),
          findsOneWidget,
        );
        expect(
          find.text('IR Bridge (ESP32, build it yourself)'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(find.text('Later'), 200);
        await tester.tap(find.text('Later'));
        await settle(tester);
        expect(find.text('Remotes'), findsOneWidget);
        expect(find.textContaining('Nothing can send IR yet'), findsOneWidget);
        expect(
          await tester.runAsync(() async => s.settings.onboardingDone),
          isTrue,
        );
        await disposeServices(tester, s);
      },
    );

    testWidgets('an emitter is only trusted when both platform checks agree', (
      tester,
    ) async {
      expect(
        const EmitterInfo(
          platformSupported: true,
          hasFeature: true,
          hasEmitter: false,
        ).canTransmit,
        isFalse,
      );
      expect(
        const EmitterInfo(
          platformSupported: true,
          hasFeature: false,
          hasEmitter: true,
        ).canTransmit,
        isFalse,
      );
      expect(EmitterInfo.none.canTransmit, isFalse);
    });
  });

  group('remote', () {
    testWidgets(
      'keys send their snapshot; missing keys are disabled and labelled',
      (tester) async {
        final (s, sim) = await buildServices();
        await tester.runAsync(() => _saveTv(s, id: 'lg', set: 'lg-a'));
        await pumpApp(tester, s);
        await _openRemote(tester, 'lg');
        await tester.tap(find.bySemanticsLabel('Power').first);
        await settle(tester);
        expect(sim.sent.single.signal, const Nec1().encode({'D': 4, 'F': 8}));
        // VOL_DOWN is not in the set: shown disabled, announced as missing.
        expect(find.bySemanticsLabel('Volume down (no code)'), findsWidgets);
        await tester.tap(find.bySemanticsLabel('Volume down (no code)').first);
        await settle(tester);
        expect(sim.sent.length, 1);
        await disposeServices(tester, s);
      },
    );

    testWidgets('a failed send names the cause', (tester) async {
      final (s, sim) = await buildServices();
      await tester.runAsync(() => _saveTv(s));
      await pumpApp(tester, s);
      await _openRemote(tester, 'tv');
      sim.offline = true;
      await tester.tap(find.bySemanticsLabel('Mute').first);
      await settle(tester);
      expect(find.textContaining("Couldn't reach Simulator"), findsOneWidget);
      sim
        ..offline = false
        ..nextResult = const TransmitTimeout(Duration(seconds: 5));
      await tester.tap(find.bySemanticsLabel('Mute').first);
      await settle(tester);
      expect(find.textContaining("didn't respond in time"), findsOneWidget);
      await disposeServices(tester, s);
    });

    testWidgets('RC5 presses alternate the toggle bit; holds keep it', (
      tester,
    ) async {
      final (s, sim) = await buildServices();
      await tester.runAsync(() => _saveTv(s, id: 'ph', set: 'philips-a'));
      await pumpApp(tester, s);
      await _openRemote(tester, 'ph');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.bySemanticsLabel('Power').first);
        await settle(tester);
      }
      final toggles = [
        for (final x in sim.sent)
          const Rc5().decode(x.signal.durationsUs)!.params['T'],
      ];
      expect(toggles, [0, 1, 0]);
      await disposeServices(tester, s);
    });

    testWidgets('holding Volume up sends the NEC-family repeat frame', (
      tester,
    ) async {
      final (s, sim) = await buildServices();
      await tester.runAsync(() => _saveTv(s, id: 'lg', set: 'lg-a'));
      await pumpApp(tester, s);
      await _openRemote(tester, 'lg');
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Volume up').first),
      );
      // The hold delay and repeat gaps run on the test's fake clock.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await gesture.up();
      await settle(tester);
      expect(sim.sent.length, greaterThan(1));
      expect(sim.sent.first.signal, const Nec1().encode({'D': 4, 'F': 2}));
      // Repeats are the 9 ms + 2.25 ms ditto, not the full code again.
      expect(sim.sent[1].signal.durationsUs, [9024, 2256, 564]);
      await disposeServices(tester, s);
    });

    testWidgets('a drag that starts on a button scrolls and sends nothing', (
      tester,
    ) async {
      final (s, sim) = await buildServices();
      await tester.runAsync(() => _saveTv(s, id: 'lg', set: 'lg-a'));
      await pumpApp(tester, s);
      await _openRemote(tester, 'lg');
      final volUp = find.bySemanticsLabel('Volume up').first;
      await tester.drag(volUp, const Offset(0, -300));
      await settle(tester);
      expect(sim.sent, isEmpty);

      // A drag that starts after a short pause still belongs to the scroll.
      final gesture = await tester.startGesture(tester.getCenter(volUp));
      await tester.pump(remotePressDelay ~/ 2);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Holding still after the scroll has won sends nothing either.
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await settle(tester);
      expect(sim.sent, isEmpty);

      // A plain tap still sends exactly one frame.
      await tester.tap(find.bySemanticsLabel('Volume up').first);
      await settle(tester);
      expect(sim.sent.length, 1);
      expect(sim.sent.single.signal, const Nec1().encode({'D': 4, 'F': 2}));

      // Latency budget: a press that stays put starts sending once the
      // press delay has passed, before the finger lifts.
      final press = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Volume up').first),
      );
      await tester.pump(remotePressDelay + const Duration(milliseconds: 1));
      await tester.pump();
      expect(sim.sent.length, 2, reason: 'sent while the finger is down');
      await press.up();
      await settle(tester);
      expect(remotePressDelay, lessThan(const Duration(milliseconds: 50)));
      await disposeServices(tester, s);
    });

    testWidgets('every key of a TV, box or projector appears exactly once', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1000, 6000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (s, _) = await buildServices();
      const placed = [
        Keys.power, Keys.input, Keys.mute, Keys.volUp, Keys.volDown, //
        Keys.chUp, Keys.chDown, Keys.up, Keys.down, Keys.left, Keys.right, //
        Keys.ok, Keys.back, Keys.home, Keys.menu, Keys.guide, Keys.info, //
        Keys.exit, Keys.red, Keys.green, Keys.yellow, Keys.blue, //
        Keys.lastChannel, Keys.focusIn, Keys.focusOut, Keys.keystoneUp, //
        Keys.keystoneDown, Keys.play, 'custom:Netflix', ...Keys.digits,
      ];
      for (final c in [
        DeviceCategory.tv,
        DeviceCategory.setTopBox,
        DeviceCategory.projector,
      ]) {
        await tester.runAsync(
          () => s.devices.save(
            SavedDevice(
              id: c.name,
              name: c.name,
              category: c,
              createdAt: DateTime.utc(2026, 11, 9),
              keys: {
                for (final (i, k) in placed.indexed)
                  k: snapshotKey(
                    k,
                    ProtocolKeyCode('NEC1', {'D': 1, 'F': i}),
                    position: i,
                  ),
              },
            ),
          ),
        );
      }
      await pumpApp(tester, s);
      for (final c in [
        DeviceCategory.tv,
        DeviceCategory.setTopBox,
        DeviceCategory.projector,
      ]) {
        await _openRemote(tester, c.name);
        final numbers = find.text('Numbers');
        if (numbers.evaluate().isNotEmpty) {
          await tester.tap(numbers);
          await settle(tester);
        }
        for (final k in placed) {
          expect(
            find.byWidgetPredicate((w) => w is RemoteButton && w.keyName == k),
            findsOneWidget,
            reason: '$k on the ${c.name} remote',
          );
        }
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await settle(tester);
      }
      await disposeServices(tester, s);
    });

    testWidgets('power never auto-repeats while held', (tester) async {
      final (s, sim) = await buildServices();
      await tester.runAsync(() => _saveTv(s, id: 'lg', set: 'lg-a'));
      await pumpApp(tester, s);
      await _openRemote(tester, 'lg');
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Power').first),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await gesture.up();
      await settle(tester);
      expect(sim.sent.length, 1);
      await disposeServices(tester, s);
    });

    testWidgets('every remote button meets the 48 dp minimum target', (
      tester,
    ) async {
      final (s, _) = await buildServices();
      await tester.runAsync(() => _saveTv(s));
      await pumpApp(tester, s);
      await _openRemote(tester, 'tv');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await disposeServices(tester, s);
    });
  });

  group('hubs', () {
    testWidgets('lists discovered bridges and validates typed addresses', (
      tester,
    ) async {
      final discovery = FakeDiscovery();
      final (s, _) = await buildServices(discovery: discovery);
      await pumpApp(tester, s);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const AddHubScreen()));
      await settle(tester);
      expect(
        find.text('Looking for IR Bridges on this Wi-Fi…'),
        findsOneWidget,
      );
      discovery.controller.add(const [
        DiscoveredBridge(
          name: 'Hall bridge',
          host: '192.168.1.40',
          port: 80,
          id: 'a1b2c3d4e5f6',
        ),
      ]);
      await settle(tester);
      expect(find.text('Hall bridge'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '999.1.1');
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(
        find.text('Enter an IPv4 address such as 192.168.1.40.'),
        findsOneWidget,
      );
      await disposeServices(tester, s);
    });

    testWidgets('bridges that are already added are marked in discovery', (
      tester,
    ) async {
      final discovery = FakeDiscovery();
      final (s, _) = await buildServices(discovery: discovery);
      // In the test zone: the registry's futures belong to it.
      await s.hubs.saveRecord(
        const HubRecord(
          id: 'esp:a1b2c3d4e5f6',
          kind: TransportKind.espBridge,
          name: 'Hall bridge',
          host: '192.168.1.40',
          port: 80,
        ),
      );
      await pumpApp(tester, s);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const AddHubScreen()));
      await settle(tester);
      discovery.controller.add(const [
        DiscoveredBridge(
          name: 'Hall bridge',
          host: '192.168.1.41',
          port: 80,
          id: 'a1b2c3d4e5f6',
        ),
        DiscoveredBridge(
          name: 'Kitchen bridge',
          host: '192.168.1.42',
          port: 80,
          id: '0a0b0c0d0e0f',
        ),
      ]);
      await settle(tester);
      expect(find.textContaining('Already added'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Hall bridge'),
          matching: find.textContaining('Already added'),
        ),
        findsOneWidget,
      );
      await disposeServices(tester, s);
    });

    testWidgets('leaving the pairing screen while Pair is pending is safe', (
      tester,
    ) async {
      final (s, _) = await buildServices();
      await pumpApp(tester, s);
      // A loopback port with nothing listening: the request fails, but only
      // once real I/O runs, after the screen has gone.
      final closed = await tester.runAsync(() async {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        return port;
      });
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => PairBridgeScreen(
            hub: HubRecord(
              id: 'esp:a1',
              kind: TransportKind.espBridge,
              name: 'Hall',
              host: '127.0.0.1',
              port: closed!,
            ),
          ),
        ),
      );
      await settle(tester);
      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.tap(find.text('Pair'));
        await tester.pump();
      }, _RealHttp());
      // Finish the pop on the fake clock only, so the screen is disposed
      // before real I/O lets the request fail.
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PairBridgeScreen), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await settle(tester);
      await disposeServices(tester, s);
    });

    testWidgets(
      'iOS shows the Local Network recovery hint after a silent browse',
      (tester) async {
        final (s, _) = await buildServices(platform: TargetPlatform.iOS);
        await pumpApp(tester, s);
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const AddHubScreen(browseTimeout: Duration(milliseconds: 50)),
          ),
        );
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 100));
        await settle(tester);
        expect(find.text('Allow local network access'), findsOneWidget);
        await disposeServices(tester, s);
      },
    );

    test('IPv4 validation', () {
      expect(isValidIpv4('192.168.1.40'), isTrue);
      expect(isValidIpv4(' 10.0.0.1 '), isTrue);
      for (final bad in [
        '',
        '1.2.3',
        '256.1.1.1',
        'a.b.c.d',
        '1.2.3.4.5',
        '1..2.3',
      ]) {
        expect(isValidIpv4(bad), isFalse, reason: bad);
      }
    });
  });

  group('settings', () {
    testWidgets(
      'About states no affiliation; Licenses lists every source notice',
      (tester) async {
        final (s, _) = await buildServices();
        await pumpApp(tester, s);
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
        await settle(tester);
        expect(find.textContaining('not affiliated with'), findsOneWidget);
        nav.pop();
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const LicensesScreen()),
        );
        await settle(tester);
        expect(find.text('Fixture notice text.'), findsOneWidget);
        await disposeServices(tester, s);
      },
    );

    testWidgets('the Signal Inspector lists sends (debug builds)', (
      tester,
    ) async {
      final (s, _) = await buildServices();
      await tester.runAsync(() => _saveTv(s));
      await pumpApp(tester, s);
      await _openRemote(tester, 'tv');
      await tester.tap(find.bySemanticsLabel('Power').first);
      await settle(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(builder: (_) => const SignalInspectorScreen()),
      );
      await settle(tester);
      expect(find.textContaining('38400 Hz'), findsOneWidget);
      expect(find.textContaining('front cameras'), findsOneWidget);
      expect(s.log.exportJson(), contains('"carrierHz": 38400'));
      await disposeServices(tester, s);
    });

    testWidgets('theme and unit settings persist', (tester) async {
      final (s, _) = await buildServices();
      await pumpApp(tester, s);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await settle(tester);
      await tester.tap(find.text('Dark'));
      await settle(tester);
      await tester.tap(find.text('°F'));
      await settle(tester);
      expect(s.settings.themeMode, ThemeMode.dark);
      expect(s.settings.unit, TemperatureUnit.fahrenheit);
      final stored = await tester.runAsync(
        () => AppSettings.load(s.settings.repoForTest),
      );
      expect(stored!.unit, TemperatureUnit.fahrenheit);
      await disposeServices(tester, s);
    });
  });

  group('AC panel', () {
    test('temperature converts at the UI edge only', () {
      expect(formatTemp(24, TemperatureUnit.celsius), '24');
      expect(formatTemp(24, TemperatureUnit.fahrenheit), '75.2');
      expect(formatTemp(25, TemperatureUnit.fahrenheit), '77');
    });
  });
}
