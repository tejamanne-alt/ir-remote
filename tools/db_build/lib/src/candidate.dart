/// Candidate code sets produced by the importers, before dedupe and ranking.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ir_core/ir_core.dart';

import 'report.dart';
import 'sources.dart';

/// The contract's per-element cap for stored signals (150 ms).
const int maxElementUs = 150000;

/// One imported file, not yet deduplicated or ranked.
final class Candidate {
  /// Creates a candidate.
  Candidate({
    required this.id,
    required this.rawBrand,
    required this.category,
    required this.label,
    required this.keys,
    required this.provenance,
    required this.source,
  });

  /// Stable ID derived from the source and path.
  final String id;

  /// Brand as spelled in the source (directory name).
  final String rawBrand;

  /// Category.
  final DeviceCategory category;

  /// Model or file label.
  final String label;

  /// Normalized key name to code.
  final Map<String, KeyCode> keys;

  /// Per-file provenance.
  final Provenance provenance;

  /// The source spec.
  final SourceSpec source;

  /// Canonical brand, set after all sources are read.
  String brand = '';

  /// Equivalent candidates merged into this one.
  final List<Candidate> merged = [];

  /// Number of code sets this one stands for, itself included.
  int get weight => 1 + merged.fold(0, (a, c) => a + c.weight);
}

/// Stable code-set ID: a prefix plus 12 hex digits of SHA-256 over the
/// source name and the file path, so it survives rebuilds while the file
/// stays where it is.
String stableId(String prefix, String sourceName, String path) {
  final h = sha256.convert(utf8.encode('$sourceName:$path')).toString();
  return '$prefix-${h.substring(0, 12)}';
}

/// Builds the key map of one file, normalizing names and resolving clashes.
final class KeyAssembler {
  /// Creates an assembler that counts into [stats].
  KeyAssembler(this.stats, {this.aliases = const {}});

  /// Statistics sink.
  final SourceStats stats;

  /// Source-provided aliases: original name to a name `Keys.normalize`
  /// understands (Flipper `config.json` key maps).
  final Map<String, String> aliases;

  /// The keys added so far.
  final Map<String, KeyCode> keys = {};

  /// Adds [code] under the normalized form of [name].
  ///
  /// A second code for an already used key keeps its original name as
  /// `custom:<name>`; an exact repeat of a code under the same key is
  /// dropped.
  void add(String name, KeyCode code) {
    if (code is RawKeyCode &&
        code.signal.durationsUs.any((d) => d > maxElementUs)) {
      stats.signalsSkipped.add('durationOver150ms:raw');
      return;
    }
    var key = Keys.normalize(name);
    if (key.startsWith(Keys.customPrefix)) {
      final alias = aliases[name];
      final viaAlias = alias == null ? null : Keys.normalize(alias);
      if (viaAlias != null && !viaAlias.startsWith(Keys.customPrefix)) {
        key = viaAlias;
        stats.keysViaSourceAlias++;
      }
    }
    final existing = keys[key];
    if (existing != null) {
      if (sameCode(existing, code)) {
        stats.signalsSkipped.add('duplicateKeySameCode');
        return;
      }
      key = '${Keys.customPrefix}${name.trim()}';
      if (keys.containsKey(key)) {
        stats.signalsSkipped.add('duplicateKeyName');
        return;
      }
    }
    keys[key] = code;
    stats.signalsImported++;
    if (key.startsWith(Keys.customPrefix)) {
      stats.keysCustom++;
    } else {
      stats.keysNormalized++;
    }
  }
}

/// Whether two codes are identical (same protocol and parameters, or the
/// same raw signal).
bool sameCode(KeyCode a, KeyCode b) => switch ((a, b)) {
  (final ProtocolKeyCode a, final ProtocolKeyCode b) =>
    a.protocol == b.protocol &&
        a.params.length == b.params.length &&
        a.params.entries.every((e) => b.params[e.key] == e.value),
  (final RawKeyCode a, final RawKeyCode b) => a.signal == b.signal,
  _ => false,
};
