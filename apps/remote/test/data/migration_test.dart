// Schema migrations: every version forward to every later one (schema only),
// plus data integrity for each upgrade. Regenerate helpers after a schema
// change with `dart run drift_dev make-migrations`.
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irremote/data/database.dart';

import 'generated/app/generated/schema.dart';
import 'generated/app/generated/schema_v1.dart' as v1;
import 'generated/app/generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  group('schema migrations', () {
    const versions = GeneratedHelper.versions;
    test('the current schema version has a snapshot', () {
      expect(versions.last, 2);
    });
    for (final (i, from) in versions.indexed) {
      for (final to in versions.skip(i + 1)) {
        test('v$from to v$to', () async {
          final schema = await verifier.schemaAt(from);
          final db = AppDatabase(schema.newConnection());
          await verifier.migrateAndValidate(db, to);
          await db.close();
        });
      }
    }
  });

  test('v1 to v2 keeps every row of user data', () async {
    const room = v1.RoomsData(id: 1, name: 'Hall', sortOrder: 0);
    const device = v1.DevicesData(
      id: 'd1',
      name: 'TV',
      category: 'tv',
      brand: 'Samsung',
      codeSetId: 'samsung-a',
      roomId: 1,
      transportId: 'esp:a1',
      favourite: 1,
      sortOrder: 0,
      createdAt: '2026-11-09T10:00:00.000Z',
      lastUsedAt: '2026-11-09T10:05:00.000Z',
      acProtocolId: null,
      acCapsVersion: null,
      acLastState: null,
      acLastSentAt: null,
    );
    const key = v1.DeviceKeysData(
      deviceId: 'd1',
      keyName: 'POWER',
      label: null,
      signal: '{"carrierHz":38400,"durationsUs":[4512]}',
      signalToggled: null,
      source: 'database',
      protocol: 'NECx2',
      params: '{"D":7,"S":7,"F":2}',
      position: 0,
    );
    const hub = v1.HubsData(
      id: 'esp:a1',
      kind: 'espBridge',
      name: 'Hall bridge',
      host: '192.168.1.40',
      port: 80,
      token: '0123456789abcdef0123456789abcdef',
      extra: null,
      addedAt: '2026-11-09T09:00:00.000Z',
    );
    const setting = v1.SettingsData(key: 'themeMode', value: 'dark');
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch
          ..insert(oldDb.rooms, room)
          ..insert(oldDb.devices, device)
          ..insert(oldDb.deviceKeys, key)
          ..insert(oldDb.hubs, hub)
          ..insert(oldDb.settings, setting);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.rooms).get(), [
          const v2.RoomsData(id: 1, name: 'Hall', sortOrder: 0),
        ]);
        final d = (await newDb.select(newDb.devices).get()).single;
        expect(
          [d.id, d.name, d.codeSetId, d.roomId, d.transportId, d.createdAt],
          ['d1', 'TV', 'samsung-a', 1, 'esp:a1', '2026-11-09T10:00:00.000Z'],
        );
        final k = (await newDb.select(newDb.deviceKeys).get()).single;
        expect([k.signal, k.params], [key.signal, key.params]);
        expect((await newDb.select(newDb.hubs).get()).single.token, hub.token);
        expect((await newDb.select(newDb.settings).get()).single.value, 'dark');
        expect(await newDb.select(newDb.macros).get(), isEmpty);
      },
    );
  });
}
