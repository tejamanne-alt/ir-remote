// M6 gates: export, wipe, import yields identical data; backup parser
// fuzzing; macro scheduler ordering, delays, cancellation and failures.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:irremote/data/backup.dart';
import 'package:irremote/data/database.dart';
import 'package:irremote/data/macros.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/data/names.dart';
import 'package:irremote/data/repositories.dart';
import 'package:irremote/services/macro_runner.dart';
import 'package:irremote/services/send_service.dart';
import 'package:irremote/ui/learn/flipper_import.dart';

import '../helpers.dart';

Future<void> _seed(AppDatabase db) async {
  final devices = DeviceRepository(db);
  final room = await devices.addRoom('Living room');
  final set = testLibrary().byId('samsung-a')!;
  await devices.save(
    SavedDevice(
      id: 'tv',
      name: 'TV',
      category: DeviceCategory.tv,
      brand: 'Samsung',
      codeSetId: set.id,
      roomId: room,
      favourite: true,
      createdAt: DateTime.utc(2026, 11, 9, 8),
      lastUsedAt: DateTime.utc(2026, 11, 9, 9),
      keys: {
        for (final e in set.keys.entries) e.key: snapshotKey(e.key, e.value),
      },
    ),
  );
  final rc5 = testLibrary().byId('philips-a')!;
  await devices.save(
    SavedDevice(
      id: 'ph',
      name: 'Philips',
      category: DeviceCategory.tv,
      createdAt: DateTime.utc(2026, 11, 9, 8),
      keys: {
        for (final e in rc5.keys.entries) e.key: snapshotKey(e.key, e.value),
      },
    ),
  );
  await devices.save(
    SavedDevice(
      id: 'ac',
      name: 'AC',
      category: DeviceCategory.airConditioner,
      createdAt: DateTime.utc(2026, 11, 9, 8),
      ac: AcInfo(
        protocolId: 'x',
        capsVersion: 1,
        lastState: AcState.matchingProbe.withFeature(
          AcFeature.swingV,
          on: true,
        ),
        lastSentAt: DateTime.utc(2026, 11, 9, 10, 42),
      ),
      keys: {
        'custom:Cool': SavedKey(
          key: 'custom:Cool',
          label: 'Cool',
          signal: RawFormat.parse('9000 4500 560 560 560'),
          source: KeySource.learned,
        ),
      },
    ),
  );
  await HubRepository(db).upsert(
    const HubRecord(
      id: 'esp:a1',
      kind: TransportKind.espBridge,
      name: 'Hall',
      host: '192.168.1.40',
      port: 80,
      token: '0123456789abcdef0123456789abcdef',
      extra: {'fw': '0.1.0'},
    ),
    DateTime.utc(2026, 11, 9, 7),
  );
  await SettingsRepository(db).set('themeMode', 'dark');
  await MacroRepository(db).save(
    Macro(
      id: 'm1',
      name: 'Movie night',
      createdAt: DateTime.utc(2026, 11, 9, 8),
      steps: const [
        MacroStep(
          deviceId: 'tv',
          key: Keys.power,
          delay: Duration(milliseconds: 500),
        ),
        MacroStep(deviceId: 'tv', key: Keys.mute),
      ],
    ),
  );
}

void main() {
  group('backup', () {
    test('export, wipe, import yields identical data', () async {
      final db = memoryDb();
      addTearDown(db.close);
      await _seed(db);
      final codec = BackupCodec(db);
      final first = await codec.export();

      final fresh = memoryDb();
      addTearDown(fresh.close);
      await BackupCodec(fresh).import(first);
      expect(await BackupCodec(fresh).export(), first);

      // Importing over existing data replaces it entirely.
      await BackupCodec(db).import(first);
      expect(await codec.export(), first);

      // Remotes still resolve to the same signals after the round trip.
      final tv = (await DeviceRepository(fresh).load('tv'))!;
      expect(
        tv.keys[Keys.power]!.signal,
        const NecX2().encode({'D': 7, 'S': 7, 'F': 2}),
      );
      expect(
        (await DeviceRepository(fresh).load('ph'))!.keys[Keys.power]!.toggled,
        isNotNull,
      );
      expect(
        (await DeviceRepository(fresh).load('ac'))!.ac!.lastState!
            .has(AcFeature.swingV),
        isTrue,
      );
      expect((await MacroRepository(fresh).all()).single.steps.length, 2);
    });

    test('never exports hub pairing tokens', () async {
      final db = memoryDb();
      addTearDown(db.close);
      await _seed(db);
      final text = await BackupCodec(db).export();
      expect(text, isNot(contains('0123456789abcdef0123456789abcdef')));
      expect(text, contains('"host": "192.168.1.40"'));
    });

    test(
      'rejects malformed backups and leaves the database untouched',
      () async {
        final db = memoryDb();
        addTearDown(db.close);
        await _seed(db);
        final codec = BackupCodec(db);
        final before = await codec.export();
        final good = jsonDecode(before) as Map<String, Object?>;
        final bad = <String>[
          '',
          '[]',
          '{"format":"other","version":1}',
          jsonEncode({...good, 'version': 99}),
          jsonEncode({...good, 'rooms': 'x'}),
          jsonEncode({
            ...good,
            'devices': [
              {
                ...(good['devices']! as List).first as Map,
                'category': 'toaster',
              },
            ],
          }),
          jsonEncode({
            ...good,
            'hubs': [
              {...(good['hubs']! as List).first as Map, 'port': 0},
            ],
          }),
          jsonEncode({
            ...good,
            'hubs': [
              {...(good['hubs']! as List).first as Map, 'host': 'example.com'},
            ],
          }),
          jsonEncode({
            ...good,
            'macros': [
              {
                'id': 'm',
                'name': 'n',
                'createdAt': '2026-01-01T00:00:00Z',
                'steps': [
                  {'deviceId': 'tv', 'key': 'POWER', 'delayMs': -1},
                ],
              },
            ],
          }),
          'x' * (maxBackupBytes + 1),
        ];
        for (final b in bad) {
          await expectLater(
            codec.import(b),
            throwsFormatException,
            reason: b.length > 80 ? b.substring(0, 80) : b,
          );
        }
        expect(await codec.export(), before);
      },
    );

    test('duplicate room, hub or macro IDs are a FormatException', () async {
      final db = memoryDb();
      addTearDown(db.close);
      await _seed(db);
      final codec = BackupCodec(db);
      final before = await codec.export();
      final good = jsonDecode(before) as Map<String, Object?>;
      List<Object?> twice(String k) => [
        (good[k]! as List).first,
        (good[k]! as List).first,
      ];
      for (final k in ['rooms', 'hubs', 'macros']) {
        await expectLater(
          codec.import(jsonEncode({...good, k: twice(k)})),
          throwsFormatException,
          reason: 'duplicate $k',
        );
      }
      expect(await codec.export(), before);
    });

    test('a Flipper button with a 90-character name survives a backup '
        'round trip', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final devices = DeviceRepository(db);
      await devices.save(
        SavedDevice(
          id: 'g',
          name: 'Imported',
          category: DeviceCategory.generic,
          createdAt: DateTime.utc(2026, 11, 9),
        ),
      );
      final name = 'Living room lights ${'very ' * 14}long'.substring(0, 90);
      expect(name.length, 90);
      final file =
          'Filetype: IR signals file\nVersion: 1\n#\nname: $name\n'
          'type: parsed\nprotocol: NEC\naddress: 04 00 00 00\n'
          'command: 08 00 00 00\n';
      for (final k in keysFromFlipper(FlipperIr.parse(file))) {
        expect(k.key.length, lessThanOrEqualTo(maxKeyNameLength));
        await devices.upsertKey('g', k);
      }
      final text = await BackupCodec(db).export();
      final fresh = memoryDb();
      addTearDown(fresh.close);
      await BackupCodec(fresh).import(text);
      final g = (await DeviceRepository(fresh).load('g'))!;
      expect(g.keys.values.single.label, name);
      expect(
        g.keys.values.single.signal,
        const Nec1().encode({'D': 4, 'F': 8}),
      );
      expect(await BackupCodec(fresh).export(), text);
    });

    test('names an older version stored uncut still restore, and macros '
        'follow them', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final devices = DeviceRepository(db);
      final long = 'custom:${'x' * 120}';
      final long2 = 'custom:${'x' * 121}';
      final signal = const Nec1().encode({'D': 4, 'F': 8});
      await devices.save(
        SavedDevice(
          id: 'g',
          name: 'Old',
          category: DeviceCategory.generic,
          createdAt: DateTime.utc(2026, 11, 9),
          keys: {
            for (final k in [long, long2])
              k: SavedKey(
                key: k,
                label: 'y' * 2000,
                signal: signal,
                source: KeySource.imported,
              ),
          },
        ),
      );
      await MacroRepository(db).save(
        Macro(
          id: 'm',
          name: 'M',
          createdAt: DateTime.utc(2026),
          steps: [
            MacroStep(deviceId: 'g', key: long),
            MacroStep(deviceId: 'g', key: long2),
          ],
        ),
      );
      final text = await BackupCodec(db).export();
      final fresh = memoryDb();
      addTearDown(fresh.close);
      await BackupCodec(fresh).import(text);
      final g = (await DeviceRepository(fresh).load('g'))!;
      expect(g.keys.length, 2);
      for (final k in g.keys.values) {
        expect(k.key.length, lessThanOrEqualTo(maxKeyNameLength));
        expect(k.label!.length, maxKeyLabelLength);
      }
      final steps = (await MacroRepository(fresh).all()).single.steps;
      expect(steps.map((s) => s.key).toSet(), g.keys.keys.toSet());
    });

    test('survives 2,000 mutated backups with only FormatException', () async {
      final db = memoryDb();
      addTearDown(db.close);
      await _seed(db);
      final codec = BackupCodec(db);
      final seed = await codec.export();
      final rng = Random(6);
      const alphabet = '{}[]":,0123456789-abcxyz\\ ';
      for (var i = 0; i < 2000; i++) {
        final chars = seed.split('');
        for (var e = 0; e < 1 + rng.nextInt(5); e++) {
          final pos = rng.nextInt(chars.length);
          switch (rng.nextInt(3)) {
            case 0:
              chars[pos] = alphabet[rng.nextInt(alphabet.length)];
            case 1:
              chars.removeAt(pos);
            default:
              chars.insert(pos, alphabet[rng.nextInt(alphabet.length)]);
          }
        }
        try {
          await codec.import(chars.join());
        } on FormatException {
          // expected for most mutations
        }
      }
      // Whatever got imported must still be a consistent, exportable state.
      jsonDecode(await codec.export());
    });
  });

  group('macro runner', () {
    late AppDatabase db;
    late SimulatedTransport sim;
    late MacroRunner runner;

    setUp(() async {
      db = memoryDb();
      await _seed(db);
      sim = SimulatedTransport();
      final registry = TransportRegistry();
      await registry.register(sim);
      final devices = DeviceRepository(db);
      runner = MacroRunner(
        send: SendService(registry: registry, devices: devices),
        devices: devices,
      );
    });
    tearDown(() => db.close());

    Macro macro(List<MacroStep> steps) =>
        Macro(id: 'm', name: 'M', steps: steps, createdAt: DateTime.utc(2026));

    test('runs steps in order with delays and reports progress', () async {
      final sw = Stopwatch()..start();
      final events = await runner
          .run(
            macro(const [
              MacroStep(
                deviceId: 'tv',
                key: Keys.power,
                delay: Duration(milliseconds: 120),
              ),
              MacroStep(deviceId: 'tv', key: Keys.volUp),
              MacroStep(deviceId: 'tv', key: Keys.mute),
            ]),
          )
          .events
          .toList();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(110));
      expect(events.whereType<MacroStepStarted>().map((e) => e.index), [
        0,
        1,
        2,
      ]);
      expect(events.last, isA<MacroCompleted>());
      expect(
        [for (final s in sim.sent) s.signal],
        [
          const NecX2().encode({'D': 7, 'S': 7, 'F': 2}),
          const NecX2().encode({'D': 7, 'S': 7, 'F': 7}),
          const NecX2().encode({'D': 7, 'S': 7, 'F': 15}),
        ],
      );
    });

    test('cancel stops during a delay; nothing after it is sent', () async {
      final run = runner.run(
        macro(const [
          MacroStep(
            deviceId: 'tv',
            key: Keys.power,
            delay: Duration(seconds: 30),
          ),
          MacroStep(deviceId: 'tv', key: Keys.mute),
        ]),
      );
      final done = run.events.toList();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      run.cancel();
      final events = await done;
      expect(events.last, isA<MacroCancelled>());
      expect((events.last as MacroCancelled).afterSteps, 1);
      expect(sim.sent.length, 1);
    });

    test(
      'a failed send or a deleted remote stops the macro with the cause',
      () async {
        sim.offline = true;
        var events = await runner
            .run(macro(const [MacroStep(deviceId: 'tv', key: Keys.power)]))
            .events
            .toList();
        expect((events.last as MacroStepFailed).outcome!.ok, isFalse);
        sim.offline = false;
        events = await runner
            .run(
              macro(const [
                MacroStep(deviceId: 'gone', key: Keys.power),
                MacroStep(deviceId: 'tv', key: Keys.power),
              ]),
            )
            .events
            .toList();
        expect((events.last as MacroStepFailed).missingDevice, isTrue);
        expect(sim.sent, isEmpty);
      },
    );

    test('step parsing enforces limits', () {
      expect(() => parseSteps('{}'), throwsFormatException);
      expect(
        () => parseSteps(
          jsonEncode(List.filled(51, {'deviceId': 'a', 'key': 'b'})),
        ),
        throwsFormatException,
      );
      expect(
        () =>
            MacroStep.fromJson({'deviceId': 'a', 'key': 'b', 'delayMs': 60001}),
        throwsFormatException,
      );
      expect(
        parseSteps('[{"deviceId":"a","key":"b"}]').single.delay,
        Duration.zero,
      );
    });
  });
}
