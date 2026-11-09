/// Typed access to user data. Screens never touch drift tables directly.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ir_core/ir_core.dart';

import 'database.dart';
import 'models.dart';

/// Saved remotes and rooms.
final class DeviceRepository {
  /// Creates the repository over [db].
  DeviceRepository(this.db);

  /// The database.
  final AppDatabase db;

  SavedDevice _fromRow(DeviceRow r, [List<DeviceKeyRow> keys = const []]) {
    AcInfo? ac;
    if (r.acProtocolId != null) {
      AcState? state;
      if (r.acLastState != null) {
        try {
          state = AcState.fromJson(jsonDecode(r.acLastState!));
        } on FormatException {
          state = null; // a damaged assumption is dropped, never guessed
        }
      }
      ac = AcInfo(
        protocolId: r.acProtocolId!,
        capsVersion: r.acCapsVersion ?? 1,
        lastState: state,
        lastSentAt: r.acLastSentAt,
      );
    }
    final keyMap = <String, SavedKey>{};
    for (final k in keys) {
      final key = _keyFromRow(k);
      if (key != null) keyMap[key.key] = key;
    }
    DeviceCategory category;
    try {
      category = DeviceCategory.parse(r.category);
    } on FormatException {
      category = DeviceCategory.generic;
    }
    return SavedDevice(
      id: r.id,
      name: r.name,
      category: category,
      brand: r.brand,
      codeSetId: r.codeSetId,
      roomId: r.roomId,
      transportId: r.transportId,
      favourite: r.favourite,
      createdAt: r.createdAt,
      lastUsedAt: r.lastUsedAt,
      keys: keyMap,
      ac: ac,
    );
  }

  static SavedKey? _keyFromRow(DeviceKeyRow k) {
    try {
      final params = k.params == null
          ? null
          : (jsonDecode(k.params!) as Map).map(
              (a, b) => MapEntry(a as String, b as int),
            );
      return SavedKey(
        key: k.keyName,
        label: k.label,
        signal: IrSignal.fromJson(jsonDecode(k.signal)),
        toggled: k.signalToggled == null
            ? null
            : IrSignal.fromJson(jsonDecode(k.signalToggled!)),
        source: KeySource.values.firstWhere(
          (s) => s.name == k.source,
          orElse: () => KeySource.imported,
        ),
        protocol: k.protocol,
        params: params,
        position: k.position,
      );
    } on Object {
      return null; // a corrupt row hides one key instead of breaking the remote
    }
  }

  DeviceKeysCompanion _keyCompanion(String deviceId, SavedKey k) =>
      DeviceKeysCompanion.insert(
        deviceId: deviceId,
        keyName: k.key,
        label: Value(k.label),
        signal: jsonEncode(k.signal.toJson()),
        signalToggled: Value(
          k.toggled == null ? null : jsonEncode(k.toggled!.toJson()),
        ),
        source: k.source.name,
        protocol: Value(k.protocol),
        params: Value(k.params == null ? null : jsonEncode(k.params)),
        position: Value(k.position),
      );

  /// All remotes without their keys, for lists.
  Stream<List<SavedDevice>> watchDevices() {
    final q = db.select(db.devices)
      ..orderBy([
        (d) => OrderingTerm.asc(d.sortOrder),
        (d) => OrderingTerm.asc(d.createdAt),
      ]);
    return q.watch().map((rows) => [for (final r in rows) _fromRow(r)]);
  }

  /// One remote with its keys, or `null`.
  Future<SavedDevice?> load(String id) async {
    final row = await (db.select(
      db.devices,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final keys =
        await (db.select(db.deviceKeys)
              ..where((k) => k.deviceId.equals(id))
              ..orderBy([(k) => OrderingTerm.asc(k.position)]))
            .get();
    return _fromRow(row, keys);
  }

  /// Watches one remote with its keys.
  Stream<SavedDevice?> watch(String id) {
    final q = db.select(db.devices)..where((d) => d.id.equals(id));
    return q.watchSingleOrNull().asyncMap((_) => load(id));
  }

  /// Inserts or replaces a remote and all of its keys in one transaction.
  Future<void> save(SavedDevice d) => db.transaction(() async {
    await db
        .into(db.devices)
        .insertOnConflictUpdate(
          DevicesCompanion.insert(
            id: d.id,
            name: d.name,
            category: d.category.name,
            brand: Value(d.brand),
            codeSetId: Value(d.codeSetId),
            roomId: Value(d.roomId),
            transportId: Value(d.transportId),
            favourite: Value(d.favourite),
            createdAt: d.createdAt,
            lastUsedAt: Value(d.lastUsedAt),
            acProtocolId: Value(d.ac?.protocolId),
            acCapsVersion: Value(d.ac?.capsVersion),
            acLastState: Value(
              d.ac?.lastState == null
                  ? null
                  : jsonEncode(d.ac!.lastState!.toJson()),
            ),
            acLastSentAt: Value(d.ac?.lastSentAt),
          ),
        );
    await (db.delete(
      db.deviceKeys,
    )..where((k) => k.deviceId.equals(d.id))).go();
    await db.batch((b) {
      b.insertAll(db.deviceKeys, [
        for (final k in d.keys.values) _keyCompanion(d.id, k),
      ]);
    });
  });

  /// Adds or replaces one key.
  Future<void> upsertKey(String deviceId, SavedKey key) => db
      .into(db.deviceKeys)
      .insertOnConflictUpdate(_keyCompanion(deviceId, key));

  /// Removes one key.
  Future<void> deleteKey(String deviceId, String key) => (db.delete(
    db.deviceKeys,
  )..where((k) => k.deviceId.equals(deviceId) & k.keyName.equals(key))).go();

  Future<void> _update(String id, DevicesCompanion c) =>
      (db.update(db.devices)..where((d) => d.id.equals(id))).write(c);

  /// Renames a remote.
  Future<void> rename(String id, String name) =>
      _update(id, DevicesCompanion(name: Value(name)));

  /// Pins or unpins a remote.
  Future<void> setFavourite(String id, {required bool favourite}) =>
      _update(id, DevicesCompanion(favourite: Value(favourite)));

  /// Moves a remote to a room (or none).
  Future<void> setRoom(String id, int? roomId) =>
      _update(id, DevicesCompanion(roomId: Value(roomId)));

  /// Chooses a transport (or automatic).
  Future<void> setTransport(String id, String? transportId) =>
      _update(id, DevicesCompanion(transportId: Value(transportId)));

  /// Records use, for the recents row.
  Future<void> touch(String id, DateTime at) =>
      _update(id, DevicesCompanion(lastUsedAt: Value(at)));

  /// Records the AC state just sent.
  Future<void> saveAcState(String id, AcState state, DateTime at) => _update(
    id,
    DevicesCompanion(
      acLastState: Value(jsonEncode(state.toJson())),
      acLastSentAt: Value(at),
    ),
  );

  /// Clears transport choices that point at [transportId].
  Future<void> clearTransport(String transportId) =>
      (db.update(db.devices)..where((d) => d.transportId.equals(transportId)))
          .write(const DevicesCompanion(transportId: Value(null)));

  /// Deletes a remote and its keys.
  Future<void> delete(String id) =>
      (db.delete(db.devices)..where((d) => d.id.equals(id))).go();

  /// All rooms in order.
  Stream<List<Room>> watchRooms() {
    final q = db.select(db.rooms)
      ..orderBy([
        (r) => OrderingTerm.asc(r.sortOrder),
        (r) => OrderingTerm.asc(r.name),
      ]);
    return q.watch().map(
      (rows) => [for (final r in rows) Room(id: r.id, name: r.name)],
    );
  }

  /// Adds a room and returns its ID.
  Future<int> addRoom(String name) =>
      db.into(db.rooms).insert(RoomsCompanion.insert(name: name));

  /// Deletes a room; its remotes move to "no room".
  Future<void> deleteRoom(int id) =>
      (db.delete(db.rooms)..where((r) => r.id.equals(id))).go();
}

/// Hubs the user added.
final class HubRepository {
  /// Creates the repository over [db].
  HubRepository(this.db);

  /// The database.
  final AppDatabase db;

  HubRecord _fromRow(HubRow r) {
    Map<String, Object?> extra = const {};
    if (r.extra != null) {
      try {
        final v = jsonDecode(r.extra!);
        if (v is Map<String, Object?>) extra = v;
      } on FormatException {
        extra = const {};
      }
    }
    return HubRecord(
      id: r.id,
      kind: TransportKind.values.firstWhere(
        (k) => k.name == r.kind,
        orElse: () => TransportKind.espBridge,
      ),
      name: r.name,
      host: r.host,
      port: r.port,
      token: r.token,
      extra: extra,
    );
  }

  /// All hubs.
  Future<List<HubRecord>> all() async => [
    for (final r in await db.select(db.hubs).get()) _fromRow(r),
  ];

  /// Watches all hubs.
  Stream<List<HubRecord>> watch() => db
      .select(db.hubs)
      .watch()
      .map((rows) => [for (final r in rows) _fromRow(r)]);

  /// Inserts or replaces a hub.
  Future<void> upsert(HubRecord h, DateTime addedAt) => db
      .into(db.hubs)
      .insertOnConflictUpdate(
        HubsCompanion.insert(
          id: h.id,
          kind: h.kind.name,
          name: h.name,
          host: h.host,
          port: h.port,
          token: Value(h.token),
          extra: Value(h.extra.isEmpty ? null : jsonEncode(h.extra)),
          addedAt: addedAt,
        ),
      );

  /// Deletes a hub.
  Future<void> delete(String id) =>
      (db.delete(db.hubs)..where((h) => h.id.equals(id))).go();
}

/// Key-value settings with typed accessors.
final class SettingsRepository {
  /// Creates the repository over [db].
  SettingsRepository(this.db);

  /// The database.
  final AppDatabase db;

  /// Reads a raw value.
  Future<String?> get(String key) async => (await (db.select(
    db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  /// Writes a raw value.
  Future<void> set(String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  /// Reads all settings at once (startup).
  Future<Map<String, String>> all() async => {
    for (final r in await db.select(db.settings).get()) r.key: r.value,
  };
}
