/// Read-only access to a code database file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ir_core/ir_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'content_hash.dart';
import 'encoding.dart';
import 'errors.dart';
import 'schema.dart';

/// How much [CodeDb.open] checks.
enum CodeDbVerification {
  /// Recompute the content hash over every row and compare it with the
  /// stored hash and with the expected one, if given. Detects corruption.
  full,

  /// Compare only the stored hash with the expected one. Use when the file
  /// was verified by [full] before and has not changed since.
  storedHashOnly,
}

/// Code-set and brand counts of one category.
final class CategorySummary {
  /// Creates a summary.
  const CategorySummary(this.category, this.codeSetCount, this.brandCount);

  /// The category.
  final DeviceCategory category;

  /// Code sets in the category.
  final int codeSetCount;

  /// Brands with at least one code set in the category.
  final int brandCount;
}

/// One brand of a category, as listed in the add-device flow.
final class BrandSummary {
  /// Creates a summary.
  const BrandSummary({
    required this.name,
    required this.codeSetCount,
    required this.primaryMarket,
  });

  /// Brand name, plain text.
  final String name;

  /// Code sets for this brand in the category.
  final int codeSetCount;

  /// Whether the brand is on the category's primary-market ranking list.
  final bool primaryMarket;
}

/// A data source recorded in the database, with its required notice.
final class SourceInfo {
  /// Creates a source record.
  const SourceInfo({
    required this.name,
    required this.url,
    required this.commit,
    required this.license,
    required this.importedAt,
    required this.notice,
  });

  /// Short name, for example `flipperdevices/irdb`.
  final String name;

  /// Repository URL.
  final String url;

  /// Pinned commit.
  final String commit;

  /// Licence identifier.
  final String license;

  /// Import date.
  final String importedAt;

  /// Notice to show verbatim on the licences screen.
  final String notice;
}

/// Whole-database counts.
final class CodeDbTotals {
  /// Creates totals.
  const CodeDbTotals({
    required this.codeSets,
    required this.brands,
    required this.keyCodes,
    required this.mergedDuplicates,
    required this.codeSetsBySource,
  });

  /// Code sets.
  final int codeSets;

  /// Brands.
  final int brands;

  /// Key codes over all code sets.
  final int keyCodes;

  /// Duplicate code sets merged at build time (resolvable as aliases).
  final int mergedDuplicates;

  /// Code sets per source name.
  final Map<String, int> codeSetsBySource;
}

/// The bundled, read-only IR code database.
///
/// User data never lives here: saved remotes keep their own snapshot of each
/// resolved signal in the app's database.
final class CodeDb {
  CodeDb._(this._db, this.contentHash, this.meta);

  final Database _db;

  /// The verified content hash.
  final String contentHash;

  /// The `meta` table.
  final Map<String, String> meta;

  static const String _setColumns =
      'cs.id, cs.uid, b.name, cs.category, cs.rank, cs.label, cs.source, '
      'cs.source_url, cs.source_commit, cs.license, cs.imported_at, cs.path';

  static const String _keyColumns =
      'k.code_set_id, k.key, k.protocol, k.params, k.carrier_hz, k.durations, '
      'k.repeat_frame, k.repeat_lead_in_us, k.repeat_gap_us, k.repeat_min';

  /// Opens the database at [path] read-only and verifies it.
  ///
  /// Throws [CodeDbOpenException] when the file is missing or not SQLite,
  /// [CodeDbSchemaException] when it is not a code database of schema
  /// version [codeDbSchemaVersion], and [CodeDbIntegrityException] when the
  /// stored or recomputed content hash differs from [expectedContentHash]
  /// or from each other.
  static CodeDb open(
    String path, {
    String? expectedContentHash,
    CodeDbVerification verification = CodeDbVerification.full,
  }) {
    if (!File(path).existsSync()) {
      throw CodeDbOpenException('no code database at $path');
    }
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw CodeDbOpenException('cannot open $path: ${e.message}');
    }
    try {
      db.execute('PRAGMA query_only = ON');
      final appId = db.select('PRAGMA application_id').first.columnAt(0);
      if (appId != codeDbApplicationId) {
        throw CodeDbSchemaException('$path is not a code database');
      }
      if (db.userVersion != codeDbSchemaVersion) {
        throw CodeDbSchemaException(
          'schema version ${db.userVersion}; expected $codeDbSchemaVersion',
        );
      }
      final meta = <String, String>{
        for (final r in db.select('SELECT key, value FROM meta'))
          r.columnAt(0) as String: r.columnAt(1) as String,
      };
      final stored = meta[metaContentHash];
      if (stored == null) {
        throw const CodeDbSchemaException('content hash missing');
      }
      if (expectedContentHash != null && stored != expectedContentHash) {
        throw CodeDbIntegrityException(
          'stored content hash is not the expected one',
          expected: expectedContentHash,
          actual: stored,
        );
      }
      if (verification == CodeDbVerification.full) {
        final actual = computeContentHash(db);
        if (actual != stored) {
          throw CodeDbIntegrityException(
            'rows do not match the stored content hash',
            expected: stored,
            actual: actual,
          );
        }
      }
      return CodeDb._(db, stored, Map.unmodifiable(meta));
    } on SqliteException catch (e) {
      db.close();
      throw CodeDbSchemaException('unreadable code database: ${e.message}');
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Closes the database.
  void close() => _db.close();

  /// Categories that have code sets, in [DeviceCategory] order.
  List<CategorySummary> categories() {
    final rows = _db.select(
      'SELECT category, COUNT(*), COUNT(DISTINCT brand_id) FROM code_set '
      'GROUP BY category',
    );
    final out = [
      for (final r in rows)
        CategorySummary(
          _category(r.columnAt(0) as String),
          r.columnAt(1) as int,
          r.columnAt(2) as int,
        ),
    ]..sort((a, b) => a.category.index.compareTo(b.category.index));
    return out;
  }

  /// Brands with code sets in [category]: primary-market brands first in
  /// ranking order, then the rest alphabetically. A non-empty [search]
  /// keeps brands whose name contains it, ignoring case, spaces and
  /// punctuation.
  List<BrandSummary> brands(DeviceCategory category, {String search = ''}) {
    final key = brandSearchKey(search);
    final pattern = key.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
    const searchClause = r"AND b.search_key LIKE ? ESCAPE '\' ";
    final rows = _db.select(
      'SELECT b.name, bc.code_set_count, bc.primary_market '
      'FROM brand_category bc JOIN brand b ON b.id = bc.brand_id '
      'WHERE bc.category = ? ${key.isEmpty ? '' : searchClause}'
      'ORDER BY bc.position',
      [category.name, if (key.isNotEmpty) '%$pattern%'],
    );
    return [
      for (final r in rows)
        BrandSummary(
          name: r.columnAt(0) as String,
          codeSetCount: r.columnAt(1) as int,
          primaryMarket: r.columnAt(2) == 1,
        ),
    ];
  }

  /// Code sets of [brand] (exact name, as returned by [brands]) in
  /// [category], in matching order: try the first one first.
  List<CodeSet> codeSets(String brand, DeviceCategory category) =>
      _load('b.name = ? AND cs.category = ?', [brand, category.name]);

  /// The code set with [id], also when [id] is a duplicate that was merged
  /// into another code set at build time; `null` when unknown.
  CodeSet? codeSetById(String id) {
    final direct = _load('cs.uid = ?', [id]);
    if (direct.isNotEmpty) return direct.single;
    final alias = _load(
      'cs.id = (SELECT code_set_id FROM code_set_alias WHERE uid = ?)',
      [id],
    );
    return alias.isEmpty ? null : alias.single;
  }

  /// Whole-database counts.
  CodeDbTotals totals() {
    final bySource = <String, int>{
      for (final r in _db.select(
        'SELECT source, COUNT(*) FROM code_set GROUP BY source ORDER BY source',
      ))
        r.columnAt(0) as String: r.columnAt(1) as int,
    };
    int count(String table) =>
        _db.select('SELECT COUNT(*) FROM $table').first.columnAt(0) as int;
    return CodeDbTotals(
      codeSets: count('code_set'),
      brands: count('brand'),
      keyCodes: count('key_code'),
      mergedDuplicates: count('code_set_alias'),
      codeSetsBySource: Map.unmodifiable(bySource),
    );
  }

  /// Sources with their notices, for the licences screen (gate L3).
  List<SourceInfo> sources() => [
    for (final r in _db.select(
      'SELECT name, url, commit_sha, license, imported_at, notice FROM source '
      'ORDER BY name',
    ))
      SourceInfo(
        name: r.columnAt(0) as String,
        url: r.columnAt(1) as String,
        commit: r.columnAt(2) as String,
        license: r.columnAt(3) as String,
        importedAt: r.columnAt(4) as String,
        notice: r.columnAt(5) as String,
      ),
  ];

  List<CodeSet> _load(String where, List<Object?> args) {
    final sets = _db.select(
      'SELECT $_setColumns FROM code_set cs JOIN brand b ON b.id = cs.brand_id '
      'WHERE $where ORDER BY cs.rank, cs.id',
      args,
    );
    if (sets.isEmpty) return const [];
    final keys = _db.select(
      'SELECT $_keyColumns FROM key_code k '
      'JOIN code_set cs ON cs.id = k.code_set_id '
      'JOIN brand b ON b.id = cs.brand_id '
      'WHERE $where ORDER BY k.code_set_id, k.ord',
      args,
    );
    final byId = <int, Map<String, KeyCode>>{};
    for (final r in keys) {
      byId.putIfAbsent(r.columnAt(0) as int, () => {})[r.columnAt(1)
          as String] = keyCodeFromColumns((
        protocol: r.columnAt(2) as String?,
        params: r.columnAt(3) as String?,
        carrierHz: r.columnAt(4) as int?,
        durations: r.columnAt(5) as Uint8List?,
        repeatFrame: r.columnAt(6) as Uint8List?,
        repeatLeadInUs: r.columnAt(7) as int?,
        repeatGapUs: r.columnAt(8) as int?,
        repeatMin: r.columnAt(9) as int?,
      ));
    }
    return [
      for (final r in sets)
        CodeSet(
          id: r.columnAt(1) as String,
          brand: r.columnAt(2) as String,
          category: _category(r.columnAt(3) as String),
          rank: r.columnAt(4) as int,
          label: r.columnAt(5) as String?,
          keys: byId[r.columnAt(0) as int] ?? const {},
          provenance: Provenance(
            source: r.columnAt(6) as String,
            sourceUrl: r.columnAt(7) as String,
            sourceCommit: r.columnAt(8) as String,
            license: r.columnAt(9) as String,
            importedAt: r.columnAt(10) as String,
            path: r.columnAt(11) as String?,
          ),
        ),
    ];
  }

  static DeviceCategory _category(String name) {
    try {
      return DeviceCategory.parse(name);
    } on FormatException {
      throw CodeDbFormatException('unknown category "$name"');
    }
  }
}
