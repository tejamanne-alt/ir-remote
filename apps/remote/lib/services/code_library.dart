/// The read-only code library the add-device flow queries.
library;

import 'package:ir_core/ir_core.dart';

/// A brand offered for a category.
final class BrandEntry {
  /// Creates an entry.
  const BrandEntry(this.name, this.codeSetCount, {this.primaryMarket = false});

  /// Brand as plain text.
  final String name;

  /// Number of code sets to try.
  final int codeSetCount;

  /// Whether the brand is in the primary-market ranking list.
  final bool primaryMarket;
}

/// One data source shown on the Licenses screen with its notice verbatim.
final class DataSourceNotice {
  /// Creates a notice.
  const DataSourceNotice({
    required this.source,
    required this.url,
    required this.license,
    required this.notice,
  });

  /// Source name.
  final String source;

  /// Source URL.
  final String url;

  /// License name.
  final String license;

  /// Required notice text, verbatim.
  final String notice;
}

/// Query API over code sets. Implementations must be fast and offline.
abstract interface class CodeLibrary {
  /// Brands that have code sets for [category], primary-market brands first.
  /// [query] filters by case-insensitive substring.
  List<BrandEntry> brands(DeviceCategory category, {String query = ''});

  /// Code sets for [brand] in matching order. With `brand == null` ("Not
  /// listed"), the most common sets of the category across brands.
  List<CodeSet> codeSets(
    DeviceCategory category, {
    String? brand,
    int limit = 40,
  });

  /// A code set by ID, or `null`.
  CodeSet? byId(String id);

  /// Every data source in the library with its required notice.
  List<DataSourceNotice> get notices;
}

/// An in-memory library, used in tests and as the empty fallback.
final class InMemoryCodeLibrary implements CodeLibrary {
  /// Creates a library over [sets] with [ranking] (primary-market brand
  /// order per category).
  InMemoryCodeLibrary(
    List<CodeSet> sets, {
    Map<DeviceCategory, List<String>> ranking = const {},
    this.notices = const [],
  }) : _sets = List.unmodifiable(sets),
       _ranking = Map.unmodifiable(ranking);

  /// An empty library (no bundled database).
  factory InMemoryCodeLibrary.empty() => InMemoryCodeLibrary(const []);

  final List<CodeSet> _sets;
  final Map<DeviceCategory, List<String>> _ranking;

  @override
  final List<DataSourceNotice> notices;

  @override
  List<BrandEntry> brands(DeviceCategory category, {String query = ''}) {
    final counts = <String, int>{};
    for (final s in _sets) {
      if (s.category == category) counts[s.brand] = (counts[s.brand] ?? 0) + 1;
    }
    final ranked = _ranking[category] ?? const [];
    final q = query.trim().toLowerCase();
    final entries = [
      for (final e in counts.entries)
        if (q.isEmpty || e.key.toLowerCase().contains(q))
          BrandEntry(e.key, e.value, primaryMarket: ranked.contains(e.key)),
    ];
    int rank(String b) {
      final i = ranked.indexOf(b);
      return i < 0 ? ranked.length : i;
    }

    entries.sort((a, b) {
      final r = rank(a.name).compareTo(rank(b.name));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  List<CodeSet> codeSets(
    DeviceCategory category, {
    String? brand,
    int limit = 40,
  }) {
    final out = [
      for (final s in _sets)
        if (s.category == category && (brand == null || s.brand == brand)) s,
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    return out.take(limit).toList();
  }

  @override
  CodeSet? byId(String id) {
    for (final s in _sets) {
      if (s.id == id) return s;
    }
    return null;
  }
}
