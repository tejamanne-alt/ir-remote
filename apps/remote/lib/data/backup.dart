/// App JSON backup: export everything the user made, wipe, import it back.
///
/// Hub pairing tokens are never exported (they are credentials; hubs are
/// re-paired after a restore). Imports are bounded: at most 5 MB and 10,000
/// signals, and every value is type-checked; malformed input throws
/// [FormatException] and changes nothing.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart' show isLanHost;

import 'database.dart';
import 'macros.dart';

/// Format identifier written into every backup.
const String backupFormat = 'irremote-backup';

/// Current backup format version.
const int backupVersion = 1;

/// Largest backup accepted, in bytes.
const int maxBackupBytes = 5 * 1024 * 1024;

/// Most signals accepted in one import.
const int maxBackupSignals = 10000;

/// Serializes and restores user data.
final class BackupCodec {
  /// Creates the codec over [db].
  BackupCodec(this.db);

  /// The database.
  final AppDatabase db;

  /// Exports all user data as canonical JSON (stable key order).
  Future<String> export() async {
    final rooms = await (db.select(
      db.rooms,
    )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
    final devices = await (db.select(
      db.devices,
    )..orderBy([(d) => OrderingTerm.asc(d.id)])).get();
    final keys =
        await (db.select(db.deviceKeys)..orderBy([
              (k) => OrderingTerm.asc(k.deviceId),
              (k) => OrderingTerm.asc(k.keyName),
            ]))
            .get();
    final hubs = await (db.select(
      db.hubs,
    )..orderBy([(h) => OrderingTerm.asc(h.id)])).get();
    final settings = await (db.select(
      db.settings,
    )..orderBy([(s) => OrderingTerm.asc(s.key)])).get();
    final macros = await (db.select(
      db.macros,
    )..orderBy([(m) => OrderingTerm.asc(m.id)])).get();
    final doc = {
      'format': backupFormat,
      'version': backupVersion,
      'rooms': [
        for (final r in rooms)
          {'id': r.id, 'name': r.name, 'sortOrder': r.sortOrder},
      ],
      'devices': [
        for (final d in devices)
          {
            'id': d.id,
            'name': d.name,
            'category': d.category,
            'brand': d.brand,
            'codeSetId': d.codeSetId,
            'roomId': d.roomId,
            'transportId': d.transportId,
            'favourite': d.favourite,
            'sortOrder': d.sortOrder,
            'createdAt': d.createdAt.toUtc().toIso8601String(),
            'lastUsedAt': d.lastUsedAt?.toUtc().toIso8601String(),
            'acProtocolId': d.acProtocolId,
            'acCapsVersion': d.acCapsVersion,
            'acLastState': d.acLastState == null
                ? null
                : jsonDecode(d.acLastState!),
            'acLastSentAt': d.acLastSentAt?.toUtc().toIso8601String(),
            'keys': [
              for (final k in keys)
                if (k.deviceId == d.id)
                  {
                    'key': k.keyName,
                    'label': k.label,
                    'signal': jsonDecode(k.signal),
                    'signalToggled': k.signalToggled == null
                        ? null
                        : jsonDecode(k.signalToggled!),
                    'source': k.source,
                    'protocol': k.protocol,
                    'params': k.params == null ? null : jsonDecode(k.params!),
                    'position': k.position,
                  },
            ],
          },
      ],
      'hubs': [
        for (final h in hubs)
          {
            'id': h.id,
            'kind': h.kind,
            'name': h.name,
            'host': h.host,
            'port': h.port,
            'extra': h.extra == null ? null : jsonDecode(h.extra!),
            'addedAt': h.addedAt.toUtc().toIso8601String(),
          },
      ],
      'settings': {for (final s in settings) s.key: s.value},
      'macros': [
        for (final m in macros)
          {
            'id': m.id,
            'name': m.name,
            'steps': jsonDecode(m.steps),
            'sortOrder': m.sortOrder,
            'createdAt': m.createdAt.toUtc().toIso8601String(),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Replaces all user data with [text]. Validates everything before writing;
  /// on any problem throws [FormatException] and leaves the database as it was.
  Future<void> import(String text) async {
    if (utf8.encode(text).length > maxBackupBytes) {
      throw const FormatException('backup is larger than 5 MB');
    }
    final Object? json = jsonDecode(text);
    final plan = _validate(json);
    await db.transaction(() async {
      await db.delete(db.deviceKeys).go();
      await db.delete(db.devices).go();
      await db.delete(db.rooms).go();
      await db.delete(db.hubs).go();
      await db.delete(db.settings).go();
      await db.delete(db.macros).go();
      await db.batch((b) {
        b
          ..insertAll(db.rooms, plan.rooms)
          ..insertAll(db.devices, plan.devices)
          ..insertAll(db.deviceKeys, plan.keys)
          ..insertAll(db.hubs, plan.hubs)
          ..insertAll(db.settings, plan.settings)
          ..insertAll(db.macros, plan.macros);
      });
    });
  }

  static _Plan _validate(Object? json) {
    final m = _map(json, 'backup');
    if (m['format'] != backupFormat) {
      throw const FormatException('not an IR Remote backup');
    }
    final v = m['version'];
    if (v is! int || v < 1 || v > backupVersion) {
      throw FormatException('unsupported backup version $v');
    }
    final plan = _Plan();
    var signals = 0;
    for (final r in _list(m['rooms'], 'rooms')) {
      final rm = _map(r, 'room');
      plan.rooms.add(
        RoomsCompanion.insert(
          id: Value(_int(rm['id'], 'room.id')),
          name: _str(rm['name'], 'room.name', max: 40),
          sortOrder: Value(_int(rm['sortOrder'] ?? 0, 'room.sortOrder')),
        ),
      );
    }
    final roomIds = {for (final r in plan.rooms) r.id.value};
    final deviceIds = <String>{};
    for (final d in _list(m['devices'], 'devices')) {
      final dm = _map(d, 'device');
      final id = _str(dm['id'], 'device.id', max: 64);
      if (!deviceIds.add(id)) throw FormatException('duplicate device $id');
      DeviceCategory.parse(_str(dm['category'], 'device.category'));
      final roomId = dm['roomId'] == null
          ? null
          : _int(dm['roomId'], 'device.roomId');
      final ac = dm['acLastState'];
      if (ac != null) AcState.fromJson(ac);
      plan.devices.add(
        DevicesCompanion.insert(
          id: id,
          name: _str(dm['name'], 'device.name', max: 40),
          category: dm['category'] as String,
          brand: Value(_optStr(dm['brand'], 'device.brand')),
          codeSetId: Value(_optStr(dm['codeSetId'], 'device.codeSetId')),
          roomId: Value(roomIds.contains(roomId) ? roomId : null),
          transportId: Value(_optStr(dm['transportId'], 'device.transportId')),
          favourite: Value(dm['favourite'] == true),
          sortOrder: Value(_int(dm['sortOrder'] ?? 0, 'device.sortOrder')),
          createdAt: _date(dm['createdAt'], 'device.createdAt'),
          lastUsedAt: Value(
            dm['lastUsedAt'] == null
                ? null
                : _date(dm['lastUsedAt'], 'device.lastUsedAt'),
          ),
          acProtocolId: Value(
            _optStr(dm['acProtocolId'], 'device.acProtocolId'),
          ),
          acCapsVersion: Value(
            dm['acCapsVersion'] == null
                ? null
                : _int(dm['acCapsVersion'], 'device.acCapsVersion'),
          ),
          acLastState: Value(ac == null ? null : jsonEncode(ac)),
          acLastSentAt: Value(
            dm['acLastSentAt'] == null
                ? null
                : _date(dm['acLastSentAt'], 'device.acLastSentAt'),
          ),
        ),
      );
      final seenKeys = <String>{};
      for (final k in _list(dm['keys'] ?? const <Object?>[], 'device.keys')) {
        final km = _map(k, 'key');
        final name = _str(km['key'], 'key.key', max: 80);
        if (!seenKeys.add(name)) {
          throw FormatException('duplicate key $name in $id');
        }
        final signal = IrSignal.fromJson(km['signal']);
        final toggled = km['signalToggled'] == null
            ? null
            : IrSignal.fromJson(km['signalToggled']);
        signals += toggled == null ? 1 : 2;
        if (signals > maxBackupSignals) {
          throw const FormatException('more than 10,000 signals');
        }
        final params = km['params'];
        if (params != null) {
          final pm = _map(params, 'key.params');
          if (pm.values.any((v) => v is! int)) {
            throw const FormatException('key.params must be integers');
          }
        }
        final source = _str(km['source'], 'key.source');
        if (!const {'database', 'learned', 'imported'}.contains(source)) {
          throw FormatException('unknown key source $source');
        }
        plan.keys.add(
          DeviceKeysCompanion.insert(
            deviceId: id,
            keyName: name,
            label: Value(_optStr(km['label'], 'key.label')),
            signal: jsonEncode(signal.toJson()),
            signalToggled: Value(
              toggled == null ? null : jsonEncode(toggled.toJson()),
            ),
            source: source,
            protocol: Value(_optStr(km['protocol'], 'key.protocol')),
            params: Value(params == null ? null : jsonEncode(params)),
            position: Value(_int(km['position'] ?? 0, 'key.position')),
          ),
        );
      }
    }
    for (final h in _list(m['hubs'] ?? const <Object?>[], 'hubs')) {
      final hm = _map(h, 'hub');
      final kind = _str(hm['kind'], 'hub.kind');
      if (!const {'espBridge', 'broadlink'}.contains(kind)) {
        throw FormatException('unknown hub kind $kind');
      }
      final host = _str(hm['host'], 'hub.host', max: 253);
      if (!isLanHost(host)) {
        throw FormatException('hub.host $host is not a local-network address');
      }
      final port = _int(hm['port'], 'hub.port');
      if (port < 1 || port > 65535) {
        throw const FormatException('hub.port out of range');
      }
      final extra = hm['extra'];
      if (extra != null) _map(extra, 'hub.extra');
      plan.hubs.add(
        HubsCompanion.insert(
          id: _str(hm['id'], 'hub.id', max: 64),
          kind: kind,
          name: _str(hm['name'], 'hub.name', max: 64),
          host: host,
          port: port,
          extra: Value(extra == null ? null : jsonEncode(extra)),
          addedAt: _date(hm['addedAt'], 'hub.addedAt'),
        ),
      );
    }
    final settings = _map(
      m['settings'] ?? const <String, Object?>{},
      'settings',
    );
    settings.forEach((k, v) {
      plan.settings.add(
        SettingsCompanion.insert(
          key: _str(k, 'settings key', max: 64),
          value: _str(v, 'settings value', max: 256),
        ),
      );
    });
    for (final mc in _list(m['macros'] ?? const <Object?>[], 'macros')) {
      final mm = _map(mc, 'macro');
      final steps = parseSteps(jsonEncode(mm['steps']));
      plan.macros.add(
        MacrosCompanion.insert(
          id: _str(mm['id'], 'macro.id', max: 64),
          name: _str(mm['name'], 'macro.name', max: 40),
          steps: jsonEncode([for (final s in steps) s.toJson()]),
          sortOrder: Value(_int(mm['sortOrder'] ?? 0, 'macro.sortOrder')),
          createdAt: _date(mm['createdAt'], 'macro.createdAt'),
        ),
      );
    }
    return plan;
  }

  static Map<Object?, Object?> _map(Object? v, String what) =>
      v is Map ? v : throw FormatException('$what must be an object');

  static List<Object?> _list(Object? v, String what) {
    if (v is! List) throw FormatException('$what must be a list');
    if (v.length > maxBackupSignals) {
      throw FormatException('$what has too many entries');
    }
    return v;
  }

  static String _str(Object? v, String what, {int max = 1024}) {
    if (v is! String || v.isEmpty || v.length > max) {
      throw FormatException(
        '$what must be a non-empty string of at most $max characters',
      );
    }
    return v;
  }

  static String? _optStr(Object? v, String what) =>
      v == null ? null : _str(v, what);

  static int _int(Object? v, String what) =>
      v is int ? v : throw FormatException('$what must be an integer');

  static DateTime _date(Object? v, String what) {
    final s = _str(v, what, max: 40);
    final d = DateTime.tryParse(s);
    if (d == null) throw FormatException('$what is not a date');
    return d;
  }
}

final class _Plan {
  final rooms = <RoomsCompanion>[];
  final devices = <DevicesCompanion>[];
  final keys = <DeviceKeysCompanion>[];
  final hubs = <HubsCompanion>[];
  final settings = <SettingsCompanion>[];
  final macros = <MacrosCompanion>[];
}
