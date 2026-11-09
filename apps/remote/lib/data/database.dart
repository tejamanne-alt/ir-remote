/// User data: rooms, saved remotes with signal snapshots, hubs and settings.
///
/// Stored in local SQLite through drift. The schema is versioned; every
/// migration is tested forward from every earlier version
/// (test/data/migration_test.dart). The read-only code database is a separate
/// file and never holds user data.
library;

import 'package:drift/drift.dart';

import 'database.steps.dart';

part 'database.g.dart';

/// Rooms group remotes on the home screen.
@DataClassName('RoomRow')
class Rooms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// A saved remote.
@DataClassName('DeviceRow')
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// `DeviceCategory.name`.
  TextColumn get category => text()();
  TextColumn get brand => text().nullable()();

  /// Code-set reference (`null` for learned or imported remotes).
  TextColumn get codeSetId => text().nullable()();
  IntColumn get roomId => integer().nullable().references(
    Rooms,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The user's chosen transport, or `null` for automatic selection.
  TextColumn get transportId => text().nullable()();
  BoolColumn get favourite => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  /// AC remotes: protocol variant, capability-descriptor version, and the
  /// last state sent (AcState JSON) with its time.
  TextColumn get acProtocolId => text().nullable()();
  IntColumn get acCapsVersion => integer().nullable()();
  TextColumn get acLastState => text().nullable()();
  DateTimeColumn get acLastSentAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One key of a saved remote, with the resolved signal snapshot.
@DataClassName('DeviceKeyRow')
class DeviceKeys extends Table {
  TextColumn get deviceId =>
      text().references(Devices, #id, onDelete: KeyAction.cascade)();

  /// Normalized key name (`Keys`), or `custom:<label>`.
  TextColumn get keyName => text()();

  /// User label for custom keys.
  TextColumn get label => text().nullable()();

  /// IrSignal JSON snapshot. Database updates never change it silently.
  TextColumn get signal => text()();

  /// For toggle protocols (RC5, RC6): the snapshot with the toggle bit set.
  TextColumn get signalToggled => text().nullable()();

  /// Where the key came from: `database`, `learned` or `imported`.
  TextColumn get source => text()();

  /// Protocol and parameters when known (informational, for the inspector
  /// and "Update codes" diffs).
  TextColumn get protocol => text().nullable()();
  TextColumn get params => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {deviceId, keyName};
}

/// A paired or added hub.
@DataClassName('HubRow')
class Hubs extends Table {
  TextColumn get id => text()();

  /// `TransportKind.name` (espBridge or broadlink).
  TextColumn get kind => text()();
  TextColumn get name => text().withLength(min: 1, max: 64)();
  TextColumn get host => text()();
  IntColumn get port => integer()();

  /// Pairing token (ESP32 bridge). LAN-only credential.
  TextColumn get token => text().nullable()();

  /// Kind-specific JSON (for example the Broadlink device type and MAC).
  TextColumn get extra => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value app settings.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// A macro: ordered commands with delays (schema v2).
@DataClassName('MacroRow')
class Macros extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// JSON list of steps: `{"deviceId", "key", "delayMs"}`.
  TextColumn get steps => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The user-data database.
@DriftDatabase(tables: [Rooms, Devices, DeviceKeys, Hubs, Settings, Macros])
class AppDatabase extends _$AppDatabase {
  /// Opens the database on [executor].
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      from1To2: (m, schema) async => m.createTable(schema.macros),
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
