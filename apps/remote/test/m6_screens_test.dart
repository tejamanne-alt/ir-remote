import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:irremote/data/macros.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/services/app_services.dart';
import 'package:irremote/ui/backup/backup_screen.dart';
import 'package:irremote/ui/macros/macros_screen.dart';
import 'package:irremote/ui/remote/edit_keys_screen.dart';
import 'package:irremote/ui/remote/remote_screen.dart';

import 'helpers.dart';

Future<void> _saveTv(AppServices s) async {
  final set = testLibrary().byId('samsung-a')!;
  await s.devices.save(
    SavedDevice(
      id: 'tv',
      name: 'Test TV',
      category: DeviceCategory.tv,
      createdAt: DateTime.utc(2026, 11, 9),
      keys: {
        for (final e in set.keys.entries) e.key: snapshotKey(e.key, e.value),
      },
    ),
  );
}

void _push(WidgetTester tester, Widget w) => tester
    .state<NavigatorState>(find.byType(Navigator).first)
    .push(MaterialPageRoute<void>(builder: (_) => w));

const _flipper = '''
Filetype: IR signals file
Version: 1
#
name: Power
type: parsed
protocol: Samsung32
address: 07 00 00 00
command: 02 00 00 00
#
name: Netflix
type: parsed
protocol: NEC
address: 04 00 00 00
command: 56 00 00 00
''';

void main() {
  testWidgets('a macro runs its steps with progress, then can be run again', (
    tester,
  ) async {
    final (s, sim) = await buildServices();
    await tester.runAsync(() => _saveTv(s));
    await tester.runAsync(
      () => s.macros.save(
        Macro(
          id: 'm',
          name: 'TV on and mute',
          createdAt: DateTime.utc(2026),
          steps: const [
            MacroStep(deviceId: 'tv', key: Keys.power),
            MacroStep(deviceId: 'tv', key: Keys.mute),
          ],
        ),
      ),
    );
    await pumpApp(tester, s);
    _push(tester, const MacrosScreen());
    await settle(tester);
    expect(find.text('TV on and mute'), findsOneWidget);
    expect(find.text('2 steps'), findsOneWidget);
    await tester.tap(find.text('Run'));
    await settle(tester, rounds: 8);
    expect(find.text('Done.'), findsOneWidget);
    expect(sim.sent.map((x) => x.signal), [
      const NecX2().encode({'D': 7, 'S': 7, 'F': 2}),
      const NecX2().encode({'D': 7, 'S': 7, 'F': 15}),
    ]);
    await disposeServices(tester, s);
  });

  testWidgets('cancelling a running macro stops later steps', (tester) async {
    final (s, sim) = await buildServices();
    await tester.runAsync(() => _saveTv(s));
    await tester.runAsync(
      () => s.macros.save(
        Macro(
          id: 'm',
          name: 'Slow',
          createdAt: DateTime.utc(2026),
          steps: const [
            MacroStep(
              deviceId: 'tv',
              key: Keys.power,
              delay: Duration(seconds: 30),
            ),
            MacroStep(deviceId: 'tv', key: Keys.mute),
          ],
        ),
      ),
    );
    await pumpApp(tester, s);
    _push(tester, const MacrosScreen());
    await settle(tester);
    await tester.tap(find.text('Run'));
    await settle(tester);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Cancelled. Later steps were not sent.'), findsOneWidget);
    expect(sim.sent.length, 1);
    await disposeServices(tester, s);
  });

  testWidgets('the macro editor adds steps and saves', (tester) async {
    final (s, _) = await buildServices();
    await tester.runAsync(() => _saveTv(s));
    await pumpApp(tester, s);
    _push(tester, const MacroEditorScreen());
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Quick mute');
    await tester.tap(find.text('Add step'));
    await settle(tester);
    await tester.tap(find.text('Add').last);
    await settle(tester);
    expect(find.textContaining('Test TV ·'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final saved = await tester.runAsync(() => s.macros.all());
    expect(saved!.single.name, 'Quick mute');
    expect(saved.single.steps.single.deviceId, 'tv');
    await disposeServices(tester, s);
  });

  testWidgets('backup exports through the share sheet and restores', (
    tester,
  ) async {
    final files = FakeFileIo();
    final (s, _) = await buildServices(files: files);
    await tester.runAsync(() => _saveTv(s));
    await pumpApp(tester, s);
    _push(tester, const BackupScreen());
    await settle(tester);
    await tester.tap(find.text('Export a backup'));
    await settle(tester, rounds: 8);
    expect(files.shared.single.$1, startsWith('irremote-backup-'));
    final exported = files.shared.single.$2;
    expect(exported, contains('"name": "Test TV"'));

    await tester.runAsync(() => s.devices.delete('tv'));
    files.nextPick = exported;
    await tester.tap(find.text('Restore from a backup'));
    await settle(tester);
    expect(find.text('Replace everything?'), findsOneWidget);
    await tester.tap(find.text('Restore from a backup').last);
    await settle(tester, rounds: 8);
    expect(find.text('Restored.'), findsOneWidget);
    expect(await tester.runAsync(() => s.devices.load('tv')), isNotNull);

    files.nextPick = '{"format":"nope"}';
    await tester.tap(find.text('Restore from a backup'));
    await settle(tester);
    await tester.tap(find.text('Restore from a backup').last);
    await settle(tester, rounds: 8);
    expect(find.textContaining("Couldn't import the file"), findsOneWidget);
    await disposeServices(tester, s);
  });

  testWidgets('a Flipper .ir file adds its buttons to a remote', (
    tester,
  ) async {
    final files = FakeFileIo()..nextPick = _flipper;
    final (s, sim) = await buildServices(files: files);
    await tester.runAsync(
      () => s.devices.save(
        SavedDevice(
          id: 'g',
          name: 'Imported',
          category: DeviceCategory.generic,
          createdAt: DateTime.utc(2026),
        ),
      ),
    );
    await pumpApp(tester, s);
    _push(tester, const RemoteScreen(deviceId: 'g'));
    await settle(tester);
    await tester.tap(find.byTooltip('Show menu'));
    await settle(tester);
    await tester.tap(find.text('Import a Flipper .ir file'));
    await settle(tester, rounds: 8);
    expect(find.text('Imported 2 buttons.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Power').first);
    await settle(tester);
    expect(
      sim.sent.last.signal,
      const NecX2().encode({'D': 7, 'S': 7, 'F': 2}),
    );
    expect(find.bySemanticsLabel('Netflix'), findsWidgets);
    await disposeServices(tester, s);
  });

  testWidgets('the button editor renames and deletes keys', (tester) async {
    final (s, _) = await buildServices();
    await tester.runAsync(() => _saveTv(s));
    await pumpApp(tester, s);
    _push(tester, const EditKeysScreen(deviceId: 'tv'));
    await settle(tester);
    expect(find.text('Power'), findsOneWidget);
    await tester.tap(find.byTooltip('Rename').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'TV power');
    await tester.tap(find.text('Save'));
    await settle(tester, rounds: 6);
    expect(find.text('TV power'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete').last);
    await settle(tester, rounds: 6);
    final d = await tester.runAsync(() => s.devices.load('tv'));
    expect(d!.keys.length, 5);
    await disposeServices(tester, s);
  });

  test('reordering writes positions in the new order', () async {
    final (s, _) = await buildServices();
    await _saveTv(s);
    final d = (await s.devices.load('tv'))!;
    final ordered = d.keys.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    await saveKeyOrder(s, 'tv', ordered.reversed.toList());
    final after = (await s.devices.load('tv'))!;
    final positions = {for (final k in after.keys.values) k.key: k.position};
    expect(positions[ordered.last.key], 0);
    expect(positions[ordered.first.key], ordered.length - 1);
    expect(positions.values.toSet().length, ordered.length);
    await s.dispose();
  });
}
