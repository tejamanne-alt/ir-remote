/// Length limits for names the app stores, shared by every place that
/// creates a name, the database and the backup importer.
///
/// Lengths are UTF-16 code units (`String.length`), which is what SQLite's
/// length checks in drift and the backup importer count. A text field's
/// `maxLength` counts visible characters instead, so one emoji can be two
/// or more units: input must be checked with [fitsName].
library;

import 'package:ir_core/ir_core.dart';

/// Longest key name (`POWER`, `custom:<name>`) stored or restored.
const int maxKeyNameLength = 80;

/// Longest custom key label stored or restored (what backups have always
/// accepted).
const int maxKeyLabelLength = 1024;

/// Longest room, remote and macro name (the database's own limit).
const int maxNameLength = 40;

/// Whether [text] fits [max] UTF-16 code units once trimmed.
bool fitsName(String text, int max) => text.trim().length <= max;

/// Cuts [s] to at most [max] UTF-16 code units, never between the two
/// halves of a surrogate pair.
String truncateUtf16(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final last = s.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--; // a lone high surrogate
  return s.substring(0, end);
}

/// [key] cut to [maxKeyNameLength]. Vocabulary names are far shorter and
/// come back unchanged; only long `custom:<name>` keys are shortened.
String boundedKeyName(String key) => truncateUtf16(key, maxKeyNameLength);

/// Maps a button name from the user or a file onto the key vocabulary,
/// as a `custom:<name>` key of at most [maxKeyNameLength] when it is not a
/// known key.
String customKeyName(String label) => boundedKeyName(Keys.normalize(label));

/// [label] cut to [maxKeyLabelLength].
String? boundedLabel(String? label) =>
    label == null ? null : truncateUtf16(label, maxKeyLabelLength);
