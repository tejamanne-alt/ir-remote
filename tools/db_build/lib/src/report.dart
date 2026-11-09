/// Counters collected while building, and the build report.
library;

import 'dart:convert';

/// A string-keyed counter that serializes in key order.
final class Tally {
  final Map<String, int> _counts = {};

  /// Adds [n] to [key].
  void add(String key, [int n = 1]) => _counts[key] = (_counts[key] ?? 0) + n;

  /// The count for [key].
  int operator [](String key) => _counts[key] ?? 0;

  /// Sum of all counts.
  int get total => _counts.values.fold(0, (a, b) => a + b);

  /// Counts sorted by key.
  Map<String, int> toJson() => {
    for (final k in _counts.keys.toList()..sort()) k: _counts[k]!,
  };
}

/// Per-source import statistics.
final class SourceStats {
  /// Files found.
  int filesSeen = 0;

  /// Files that produced a candidate code set.
  int filesImported = 0;

  /// Files not imported, by reason.
  final Tally filesExcluded = Tally();

  /// Signals that became key codes.
  int signalsImported = 0;

  /// Signals not imported, by reason (`reason:protocol`).
  final Tally signalsSkipped = Tally();

  /// Key names mapped to the fixed vocabulary.
  int keysNormalized = 0;

  /// Key names kept as `custom:<original>`.
  int keysCustom = 0;

  /// Key names mapped through the source's own alias file (Flipper
  /// `config.json` `key_map`) after `Keys.normalize` left them custom.
  int keysViaSourceAlias = 0;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'files': {
      'seen': filesSeen,
      'imported': filesImported,
      'excluded': filesExcluded.toJson(),
    },
    'signals': {
      'imported': signalsImported,
      'skipped': signalsSkipped.toJson(),
      'skippedTotal': signalsSkipped.total,
    },
    'keys': {
      'normalized': keysNormalized,
      'custom': keysCustom,
      'viaSourceAlias': keysViaSourceAlias,
    },
  };
}

/// Pretty JSON with a trailing newline.
String prettyJson(Object? json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';
