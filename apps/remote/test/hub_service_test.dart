import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:irremote/data/models.dart';
import 'package:irremote/data/repositories.dart';
import 'package:irremote/services/hub_service.dart';

import 'helpers.dart';

void main() {
  test('stored hubs become registered transports of the right kind', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final repo = HubRepository(db);
    final registry = TransportRegistry();
    addTearDown(registry.dispose);
    await repo.upsert(
      const HubRecord(
        id: 'esp:a1',
        kind: TransportKind.espBridge,
        name: 'Hall',
        host: '192.0.2.10',
        port: 80,
      ),
      DateTime.utc(2026),
    );
    await repo.upsert(
      const HubRecord(
        id: 'broadlink:aa:bb:cc:dd:ee:ff',
        kind: TransportKind.broadlink,
        name: 'Bedroom RM4',
        host: '192.0.2.11',
        port: 80,
        extra: {'mac': 'aa:bb:cc:dd:ee:ff', 'devtype': 0x51da},
      ),
      DateTime.utc(2026),
    );
    final hubs = HubService(
      repo: repo,
      registry: registry,
      devices: DeviceRepository(db),
    );
    await hubs.loadAll();
    expect(registry.byId('esp:a1')!.kind, TransportKind.espBridge);
    final bl = registry.byId('broadlink:aa:bb:cc:dd:ee:ff')!;
    expect(bl.kind, TransportKind.broadlink);
    expect(bl.caps.carrierRangesHz!.single.contains(38000), isTrue);
    expect(bl.caps.carrierRangesHz!.single.contains(56000), isFalse);
  });

  test('a damaged stored MAC keeps the hub but does not register it', () async {
    expect(() => HubService.parseMac('nope'), throwsUnsupportedError);
    expect(HubService.parseMac('01:02:03:04:05:ff'), [1, 2, 3, 4, 5, 255]);
  });

  test(
    'adding a Broadlink hub saves it and clears choices on removal',
    () async {
      final db = memoryDb();
      addTearDown(db.close);
      final registry = TransportRegistry();
      addTearDown(registry.dispose);
      final devices = DeviceRepository(db);
      final hubs =
          HubService(
              repo: HubRepository(db),
              registry: registry,
              devices: devices,
            )
            ..broadlinkConnector = (host) async => HubRecord(
              id: 'broadlink:01:02:03:04:05:06',
              kind: TransportKind.broadlink,
              name: 'RM4 mini',
              host: host,
              port: 80,
              extra: const {'mac': '01:02:03:04:05:06', 'devtype': 0x51da},
            );
      final r = await hubs.addBroadlink('192.0.2.20');
      expect(hubs.hubs.single.id, r.id);
      expect(registry.byId(r.id), isNotNull);
      await devices.save(
        SavedDevice(
          id: 'd',
          name: 'TV',
          category: DeviceCategory.tv,
          createdAt: DateTime.utc(2026),
          transportId: r.id,
        ),
      );
      await hubs.remove(r.id);
      expect(hubs.hubs, isEmpty);
      expect(registry.byId(r.id), isNull);
      expect((await devices.load('d'))!.transportId, isNull);
    },
  );
}
