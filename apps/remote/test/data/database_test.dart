// Repository round trips and schema migration tests.
//
// The migration test walks every schema version in drift_schemas/ forward
// to the current one, so adding a version automatically adds its tests
// (regenerate helpers with `dart run drift_dev make-migrations`).
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:irremote/data/database.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/data/repositories.dart';

import '../helpers.dart';
import 'generated/schema.dart';

void main() {
  group('migrations', () {
    late SchemaVerifier verifier;
    setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

    test('every earlier schema migrates forward to the current one', () async {
      final probe = memoryDb();
      final current = probe.schemaVersion;
      await probe.close();
      for (var from = 1; from <= current; from++) {
        final schema = await verifier.schemaAt(from);
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, current);
        await db.close();
      }
    });
  });

  group('repositories', () {
    late AppDatabase db;
    late DeviceRepository devices;
    setUp(() {
      db = memoryDb();
      devices = DeviceRepository(db);
    });
    tearDown(() => db.close());

    test(
      'a saved remote keeps its code-set reference and exact snapshots',
      () async {
        final rc5 = snapshotKey(
          Keys.power,
          const ProtocolKeyCode('RC5', {'D': 0, 'F': 12}),
        );
        final raw = SavedKey(
          key: 'custom:Netflix',
          label: 'Netflix',
          signal: IrSignal(carrierHz: 38000, durationsUs: [100, 200, 300]),
          source: KeySource.learned,
          position: 3,
        );
        final roomId = await devices.addRoom('Bedroom');
        final d = SavedDevice(
          id: 'd1',
          name: 'TV',
          category: DeviceCategory.tv,
          brand: 'Philips',
          codeSetId: 'philips-a',
          roomId: roomId,
          createdAt: DateTime.utc(2026, 11, 9),
          keys: {rc5.key: rc5, raw.key: raw},
        );
        await devices.save(d);
        final back = (await devices.load('d1'))!;
        expect(back.codeSetId, 'philips-a');
        expect(back.roomId, roomId);
        expect(back.keys[Keys.power]!.signal, rc5.signal);
        expect(back.keys[Keys.power]!.toggled, rc5.toggled);
        expect(back.keys[Keys.power]!.params, {'D': 0, 'F': 12, 'T': 0});
        expect(back.keys['custom:Netflix']!.label, 'Netflix');
        expect(back.keys['custom:Netflix']!.source, KeySource.learned);

        await devices.rename('d1', 'Bedroom TV');
        await devices.setFavourite('d1', favourite: true);
        await devices.setTransport('d1', 'esp:abc');
        await devices.touch('d1', DateTime.utc(2026, 11, 9, 10));
        var again = (await devices.load('d1'))!;
        expect(again.name, 'Bedroom TV');
        expect(again.favourite, isTrue);
        expect(again.transportId, 'esp:abc');
        await devices.clearTransport('esp:abc');
        again = (await devices.load('d1'))!;
        expect(again.transportId, isNull);

        await devices.deleteRoom(roomId);
        expect(
          (await devices.load('d1'))!.roomId,
          isNull,
          reason: 'room deletion sets null',
        );
        await devices.deleteKey('d1', 'custom:Netflix');
        expect((await devices.load('d1'))!.keys.length, 1);
        await devices.delete('d1');
        expect(await devices.load('d1'), isNull);
        expect(
          await db.select(db.deviceKeys).get(),
          isEmpty,
          reason: 'keys cascade',
        );
      },
    );

    test('AC state is stored as the last state sent, with its time', () async {
      await devices.save(
        SavedDevice(
          id: 'ac',
          name: 'AC',
          category: DeviceCategory.airConditioner,
          createdAt: DateTime.utc(2026),
          ac: const AcInfo(protocolId: 'test-ac', capsVersion: 2),
        ),
      );
      final state = AcState.matchingProbe.copyWith(targetTempC: 22, fan: 2);
      await devices.saveAcState('ac', state, DateTime.utc(2026, 11, 9, 10, 42));
      final back = (await devices.load('ac'))!;
      expect(back.ac!.lastState, state);
      expect(back.ac!.capsVersion, 2);
      expect(back.ac!.lastSentAt, DateTime.utc(2026, 11, 9, 10, 42));
    });

    test(
      'a corrupt key row hides one key instead of breaking the remote',
      () async {
        await devices.save(
          SavedDevice(
            id: 'x',
            name: 'X',
            category: DeviceCategory.generic,
            createdAt: DateTime.utc(2026),
            keys: {
              'A': SavedKey(
                key: 'A',
                signal: IrSignal(carrierHz: 38000, durationsUs: [1]),
                source: KeySource.imported,
              ),
            },
          ),
        );
        await db.customStatement(
          "UPDATE device_keys SET signal = '{broken' WHERE key_name = 'A'",
        );
        final back = (await devices.load('x'))!;
        expect(back.keys, isEmpty);
        expect(back.name, 'X');
      },
    );

    test('hubs and settings round-trip', () async {
      final hubs = HubRepository(db);
      await hubs.upsert(
        const HubRecord(
          id: 'esp:a1',
          kind: TransportKind.espBridge,
          name: 'Hall',
          host: '192.168.1.40',
          port: 80,
          token: '0123456789abcdef0123456789abcdef',
          extra: {'fw': '0.1.0'},
        ),
        DateTime.utc(2026),
      );
      final h = (await hubs.all()).single;
      expect(h.token, '0123456789abcdef0123456789abcdef');
      expect(h.extra['fw'], '0.1.0');
      await hubs.delete('esp:a1');
      expect(await hubs.all(), isEmpty);

      final settings = SettingsRepository(db);
      await settings.set('a', '1');
      await settings.set('a', '2');
      expect(await settings.get('a'), '2');
      expect(await settings.all(), {'a': '2'});
    });
  });
}
