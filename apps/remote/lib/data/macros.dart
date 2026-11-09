/// Macros: ordered commands with delays. Stored in the macros table; run
/// only when the user taps Run, never on launch.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// One step: send [key] of [deviceId], then wait [delay].
final class MacroStep {
  /// Creates a step.
  const MacroStep({
    required this.deviceId,
    required this.key,
    this.delay = Duration.zero,
  });

  /// Longest delay allowed between steps.
  static const Duration maxDelay = Duration(seconds: 60);

  /// Remote to send through.
  final String deviceId;

  /// Key to send.
  final String key;

  /// Wait after sending.
  final Duration delay;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'key': key,
    'delayMs': delay.inMilliseconds,
  };

  /// Parses [toJson] output; throws [FormatException].
  static MacroStep fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('macro step must be an object');
    }
    final d = json['deviceId'];
    final k = json['key'];
    final ms = json['delayMs'] ?? 0;
    if (d is! String || k is! String || ms is! int) {
      throw const FormatException('macro step needs deviceId, key and delayMs');
    }
    if (ms < 0 || ms > maxDelay.inMilliseconds) {
      throw FormatException(
        'macro delay must be 0..${maxDelay.inMilliseconds} ms',
      );
    }
    return MacroStep(
      deviceId: d,
      key: k,
      delay: Duration(milliseconds: ms),
    );
  }
}

/// A saved macro.
final class Macro {
  /// Creates a macro.
  const Macro({
    required this.id,
    required this.name,
    required this.steps,
    required this.createdAt,
  });

  /// Most steps in one macro.
  static const int maxSteps = 50;

  /// ID.
  final String id;

  /// Name.
  final String name;

  /// Steps in order.
  final List<MacroStep> steps;

  /// Creation time.
  final DateTime createdAt;
}

/// Parses a stored steps list; throws [FormatException].
List<MacroStep> parseSteps(String json) {
  final Object? v;
  try {
    v = jsonDecode(json);
  } on FormatException {
    rethrow;
  }
  if (v is! List) throw const FormatException('steps must be a list');
  if (v.length > Macro.maxSteps) {
    throw const FormatException('too many macro steps');
  }
  return [for (final s in v) MacroStep.fromJson(s)];
}

/// Macro persistence.
final class MacroRepository {
  /// Creates the repository.
  MacroRepository(this.db);

  /// The database.
  final AppDatabase db;

  Macro? _fromRow(MacroRow r) {
    try {
      return Macro(
        id: r.id,
        name: r.name,
        steps: parseSteps(r.steps),
        createdAt: r.createdAt,
      );
    } on FormatException {
      return null;
    }
  }

  /// All macros (damaged rows are skipped).
  Stream<List<Macro>> watch() =>
      (db.select(db.macros)..orderBy([(m) => OrderingTerm.asc(m.sortOrder)]))
          .watch()
          .map((rows) => [for (final r in rows) ?_fromRow(r)]);

  /// All macros once.
  Future<List<Macro>> all() async => [
    for (final r in await db.select(db.macros).get()) ?_fromRow(r),
  ];

  /// Inserts or replaces a macro.
  Future<void> save(Macro m) {
    if (m.steps.length > Macro.maxSteps) throw ArgumentError('too many steps');
    return db
        .into(db.macros)
        .insertOnConflictUpdate(
          MacrosCompanion.insert(
            id: m.id,
            name: m.name,
            steps: jsonEncode([for (final s in m.steps) s.toJson()]),
            createdAt: m.createdAt,
          ),
        );
  }

  /// Deletes a macro.
  Future<void> delete(String id) =>
      (db.delete(db.macros)..where((m) => m.id.equals(id))).go();
}
