// Full add-device integration on the Simulated transport: category, brand,
// matching with a confirm key, save, and the remote that results.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';

import 'helpers.dart';

void main() {
  testWidgets('matches a TV in two answers and saves a working remote', (
    tester,
  ) async {
    final (services, sim) = await buildServices();
    await pumpApp(tester, services);

    expect(find.text('No remotes yet'), findsOneWidget);
    await tester.tap(find.text('Add device'));
    await settle(tester);
    await tester.tap(find.text('TV'));
    await settle(tester);

    // Primary-market brands first, then the rest, then "Not listed".
    final samsung = tester.getTopLeft(find.text('Samsung')).dy;
    final lg = tester.getTopLeft(find.text('LG')).dy;
    final philips = tester.getTopLeft(find.text('Philips')).dy;
    expect(samsung < lg && lg < philips, isTrue);
    expect(find.text('Not listed'), findsOneWidget);

    await tester.tap(find.text('Samsung'));
    await settle(tester);
    expect(find.text('Set 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Send Power'));
    await settle(tester);
    expect(
      sim.sent.last.signal,
      const NecX2().encode({'D': 7, 'S': 7, 'F': 2}),
    );
    expect(find.text('Did it respond?'), findsOneWidget);
    expect(find.textContaining('counts as a response'), findsOneWidget);

    // "No" moves to the next set.
    await tester.tap(find.text('No'));
    await settle(tester);
    expect(find.text('Set 2 of 2'), findsOneWidget);
    await tester.tap(find.text('Send Power'));
    await settle(tester);
    expect(
      sim.sent.last.signal,
      const NecX2().encode({'D': 5, 'S': 5, 'F': 2}),
    );
    await tester.tap(find.text('Yes'));
    await settle(tester);

    // Confirmation with a different key rules out shared power codes.
    expect(find.text('Now try Volume up. Did it respond too?'), findsOneWidget);
    await tester.tap(find.text('Send Volume up'));
    await settle(tester);
    expect(
      sim.sent.last.signal,
      const NecX2().encode({'D': 5, 'S': 5, 'F': 7}),
    );
    await tester.tap(find.text('Yes'));
    await settle(tester);

    expect(find.text('Name your device'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Living room TV');
    await tester.tap(find.text('Save'));
    await settle(tester, rounds: 8);

    // The remote opens and sends the saved snapshot.
    expect(find.text('Living room TV'), findsWidgets);
    final before = sim.sent.length;
    await tester.tap(find.bySemanticsLabel('Mute').first);
    await settle(tester);
    expect(sim.sent.length, before + 1);
    expect(
      sim.sent.last.signal,
      const NecX2().encode({'D': 5, 'S': 5, 'F': 15}),
    );

    final saved = await tester.runAsync(
      () => services.devices.watchDevices().first,
    );
    expect(saved!.single.codeSetId, 'samsung-b');
    final full = await tester.runAsync(
      () => services.devices.load(saved.single.id),
    );
    expect(full!.keys.length, 6);
    expect(full.keys[Keys.power]!.protocol, 'NECx2');
    await disposeServices(tester, services);
  });

  testWidgets('when every set fails the user gets learning and Pronto paste', (
    tester,
  ) async {
    final (services, _) = await buildServices();
    await pumpApp(tester, services);
    await tester.tap(find.text('Add device'));
    await settle(tester);
    await tester.tap(find.text('TV'));
    await settle(tester);
    await tester.tap(find.text('LG'));
    await settle(tester);
    await tester.tap(find.text('Send Power'));
    await settle(tester);
    await tester.tap(find.text('No'));
    await settle(tester);
    expect(find.text('None of the codes worked'), findsOneWidget);
    expect(
      find.textContaining('Learn from your original remote'),
      findsOneWidget,
    );
    expect(find.text('Paste a Pronto Hex code'), findsOneWidget);

    // Pronto paste creates a working remote.
    await tester.tap(find.text('Paste a Pronto Hex code'));
    await settle(tester);
    final hex = Pronto.format(const Nec1().encode({'D': 4, 'F': 8}));
    await tester.enterText(find.byType(TextField).last, hex);
    await tester.tap(find.text('Add'));
    await settle(tester, rounds: 8);
    expect(find.bySemanticsLabel('Power'), findsWidgets);
    await disposeServices(tester, services);
  });

  testWidgets('a brand with no sets and "Not listed" never dead-end', (
    tester,
  ) async {
    final (services, _) = await buildServices();
    await pumpApp(tester, services);
    await tester.tap(find.text('Add device'));
    await settle(tester);
    await tester.tap(find.text('Fan'));
    await settle(tester);
    await tester.tap(find.text('Not listed'));
    await settle(tester);
    expect(
      find.text('There are no codes for this choice yet.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Learn from your original remote'),
      findsOneWidget,
    );
    await disposeServices(tester, services);
  });

  testWidgets('brand search filters and reports no matches', (tester) async {
    final (services, _) = await buildServices();
    await pumpApp(tester, services);
    await tester.tap(find.text('Add device'));
    await settle(tester);
    await tester.tap(find.text('TV'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'phil');
    await settle(tester);
    expect(find.text('Philips'), findsOneWidget);
    expect(find.text('Samsung'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.text('No brands match "zzz".'), findsOneWidget);
    expect(find.text('Not listed'), findsOneWidget);
    await disposeServices(tester, services);
  });
}
