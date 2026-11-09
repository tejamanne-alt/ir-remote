/// Deterministic writer for code database files.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ir_core/ir_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'content_hash.dart';
import 'encoding.dart';
import 'errors.dart';
import 'schema.dart';

/// A data source as recorded in the database (gates L1 and L3).
final class CodeDbSource {
  /// Creates a source record.
  const CodeDbSource({
    required this.name,
    required this.url,
    required this.commit,
    required this.license,
    required this.importedAt,
    required this.notice,
  });

  /// Short name, for example `flipperdevices/irdb`; code sets refer to it in
  /// `Provenance.source`.
  final String name;

  /// Repository URL.
  final String url;

  /// Pinned commit.
  final String commit;

  /// Licence identifier.
  final String license;

  /// ISO-8601 import date.
  final String importedAt;

  /// The notice the app must show verbatim (for MIT, the licence text).
  final String notice;
}

/// One code set to write, with the IDs of duplicates merged into it.
final class CodeDbEntry {
  /// Creates an entry.
  CodeDbEntry(this.codeSet, {List<String> mergedIds = const []})
    : mergedIds = List.unmodifiable(mergedIds);

  /// The code set. Its `rank` orders it within its brand and category.
  final CodeSet codeSet;

  /// IDs of equivalent code sets that were merged into this one; they stay
  /// resolvable through `CodeDb.codeSetById`.
  final List<String> mergedIds;
}

/// Everything a database file holds.
final class CodeDbContent {
  /// Creates the content.
  CodeDbContent({
    required List<CodeDbSource> sources,
    required List<CodeDbEntry> entries,
    Map<DeviceCategory, List<String>> primaryBrands = const {},
    Map<String, String> meta = const {},
  }) : sources = List.unmodifiable(sources),
       entries = List.unmodifiable(entries),
       primaryBrands = Map.unmodifiable(primaryBrands),
       meta = Map.unmodifiable(meta);

  /// Sources referenced by the entries.
  final List<CodeDbSource> sources;

  /// Code sets in any order; the writer imposes the canonical order.
  final List<CodeDbEntry> entries;

  /// Primary-market brands per category, in ranking order. They are listed
  /// first in that order; every other brand follows alphabetically.
  final Map<DeviceCategory, List<String>> primaryBrands;

  /// Extra `meta` rows (for example the build tool version).
  final Map<String, String> meta;
}

/// What [CodeDbWriter.write] produced.
final class CodeDbWriteResult {
  /// Creates a result.
  const CodeDbWriteResult({
    required this.contentHash,
    required this.fileSha256,
    required this.fileBytes,
    required this.codeSetCount,
    required this.brandCount,
    required this.keyCount,
    required this.aliasCount,
  });

  /// SHA-256 over the canonical rows (see `computeContentHash`).
  final String contentHash;

  /// SHA-256 of the file bytes.
  final String fileSha256;

  /// File size in bytes.
  final int fileBytes;

  /// Number of code sets.
  final int codeSetCount;

  /// Number of brands.
  final int brandCount;

  /// Number of key codes.
  final int keyCount;

  /// Number of merged-duplicate aliases.
  final int aliasCount;
}

int _compareNames(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
}

/// Writes code database files. The same [CodeDbContent] always produces a
/// byte-identical file with the same SQLite library: rows are inserted in a
/// canonical order into an in-memory database, which is then written with
/// `VACUUM INTO`, and nothing time-dependent is stored.
abstract final class CodeDbWriter {
  static const Set<String> _reservedMeta = {
    metaContentHash,
    metaSchemaVersion,
    'code_set_count',
    'brand_count',
    'key_code_count',
  };

  /// Checks [content] without writing. Throws [CodeDbProvenanceException]
  /// when a provenance field is missing or empty (gate L1), or when a code
  /// set's provenance does not match its declared source, and
  /// [CodeDbBuildException] for any other invalid input.
  static void validate(CodeDbContent content) {
    final sources = <String, CodeDbSource>{};
    for (final s in content.sources) {
      for (final (field, value) in [
        ('name', s.name),
        ('url', s.url),
        ('commit', s.commit),
        ('license', s.license),
        ('importedAt', s.importedAt),
        ('notice', s.notice),
      ]) {
        if (value.trim().isEmpty) {
          throw CodeDbProvenanceException(
            'source "${s.name}" has an empty $field',
          );
        }
      }
      if (sources.containsKey(s.name)) {
        throw CodeDbBuildException('duplicate source "${s.name}"');
      }
      sources[s.name] = s;
    }
    final ids = <String>{};
    for (final e in content.entries) {
      final set = e.codeSet;
      final p = set.provenance;
      for (final (field, value) in [
        ('source', p.source),
        ('sourceUrl', p.sourceUrl),
        ('sourceCommit', p.sourceCommit),
        ('license', p.license),
        ('importedAt', p.importedAt),
      ]) {
        if (value.trim().isEmpty) {
          throw CodeDbProvenanceException(
            'code set "${set.id}" has an empty provenance.$field',
          );
        }
      }
      final src = sources[p.source];
      if (src == null) {
        throw CodeDbProvenanceException(
          'code set "${set.id}" names undeclared source "${p.source}"',
        );
      }
      if (src.url != p.sourceUrl ||
          src.commit != p.sourceCommit ||
          src.license != p.license) {
        throw CodeDbProvenanceException(
          'code set "${set.id}" provenance does not match source '
          '"${p.source}"',
        );
      }
      if (set.id.trim().isEmpty) {
        throw const CodeDbBuildException('code set with an empty id');
      }
      if (set.brand.trim().isEmpty || set.brand != set.brand.trim()) {
        throw CodeDbBuildException('code set "${set.id}" has a bad brand');
      }
      if (set.keys.isEmpty) {
        throw CodeDbBuildException('code set "${set.id}" has no keys');
      }
      for (final id in [set.id, ...e.mergedIds]) {
        if (!ids.add(id)) {
          throw CodeDbBuildException('duplicate code set id "$id"');
        }
      }
      set.keys.forEach((key, code) {
        if (!Keys.isValid(key)) {
          throw CodeDbBuildException('code set "${set.id}": bad key "$key"');
        }
        _canonical(set.id, key, code);
      });
    }
    for (final k in content.meta.keys) {
      if (k.isEmpty || _reservedMeta.contains(k)) {
        throw CodeDbBuildException('meta key "$k" is reserved or empty');
      }
    }
  }

  /// Returns the code in canonical form: protocol codes use the codec's
  /// canonical ID and normalized parameters in codec order without the
  /// session toggle bit.
  static KeyCode _canonical(String setId, String key, KeyCode code) {
    switch (code) {
      case ProtocolKeyCode(:final protocol, :final params):
        final codec = ProtocolRegistry.standard.lookup(protocol);
        if (codec == null) {
          throw CodeDbBuildException(
            'code set "$setId" key $key: unknown protocol "$protocol"',
          );
        }
        final Map<String, int> n;
        try {
          n = codec.normalize(params);
        } on ProtocolParamException catch (e) {
          throw CodeDbBuildException(
            'code set "$setId" key $key: ${e.message}',
          );
        }
        return ProtocolKeyCode(codec.id, {
          for (final p in codec.params)
            if (p.name != 'T') p.name: n[p.name]!,
        });
      case RawKeyCode(:final signal):
        final d = signal.durationsUs;
        if (signal.carrierHz <= 0 ||
            d.isEmpty ||
            d.length.isEven ||
            d.any((v) => v <= 0 || v > 0xFFFFFFFF)) {
          throw CodeDbBuildException(
            'code set "$setId" key $key: invalid raw signal',
          );
        }
        return code;
    }
  }

  /// Validates [content] and writes it to [path], replacing any file there.
  static CodeDbWriteResult write(CodeDbContent content, String path) {
    validate(content);

    // Brands: ids by name order; per category, primary brands first.
    final brandNames = {
      for (final e in content.entries) e.codeSet.brand,
    }.toList()..sort(_compareNames);
    final brandId = {
      for (var i = 0; i < brandNames.length; i++) brandNames[i]: i + 1,
    };
    final byCategory = <DeviceCategory, Map<String, List<CodeDbEntry>>>{};
    for (final e in content.entries) {
      byCategory
          .putIfAbsent(e.codeSet.category, () => {})
          .putIfAbsent(e.codeSet.brand, () => [])
          .add(e);
    }
    final categories = byCategory.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final db = sqlite3.openInMemory();
    try {
      db
        ..execute('PRAGMA application_id = $codeDbApplicationId')
        ..execute('PRAGMA user_version = $codeDbSchemaVersion')
        ..execute(codeDbDdl)
        ..execute('BEGIN');
      PreparedStatement insert(String table) {
        final spec = codeDbTables.firstWhere((t) => t.name == table);
        return db.prepare(
          'INSERT INTO $table (${spec.columns.join(', ')}) VALUES '
          '(${List.filled(spec.columns.length, '?').join(', ')})',
        );
      }

      final sources = [...content.sources]
        ..sort((a, b) => a.name.compareTo(b.name));
      final sourceStmt = insert('source');
      for (final s in sources) {
        sourceStmt.execute([
          s.name,
          s.url,
          s.commit,
          s.license,
          s.importedAt,
          s.notice,
        ]);
      }
      sourceStmt.close();

      final brandStmt = insert('brand');
      for (final name in brandNames) {
        brandStmt.execute([brandId[name], name, brandSearchKey(name)]);
      }
      brandStmt.close();

      final bcStmt = insert('brand_category');
      final setStmt = insert('code_set');
      final keyStmt = insert('key_code');
      final aliases = <(String, int)>[];
      var setId = 0;
      var keyCount = 0;
      for (final category in categories) {
        final brands = byCategory[category]!;
        final primary = <String>[];
        for (final b in content.primaryBrands[category] ?? const <String>[]) {
          if (brands.containsKey(b) && !primary.contains(b)) primary.add(b);
        }
        final rest = brands.keys.where((b) => !primary.contains(b)).toList()
          ..sort(_compareNames);
        final ordered = [...primary, ...rest];
        for (var pos = 0; pos < ordered.length; pos++) {
          final brand = ordered[pos];
          final sets = [...brands[brand]!]
            ..sort((a, b) {
              final c = a.codeSet.rank.compareTo(b.codeSet.rank);
              return c != 0 ? c : a.codeSet.id.compareTo(b.codeSet.id);
            });
          bcStmt.execute([
            category.name,
            brandId[brand],
            pos,
            pos < primary.length ? 1 : 0,
            sets.length,
          ]);
          for (var rank = 0; rank < sets.length; rank++) {
            final e = sets[rank];
            final set = e.codeSet;
            final p = set.provenance;
            setId++;
            final keys = set.keys.keys.toList()..sort(compareKeys);
            final canonical = {
              for (final k in keys) k: _canonical(set.id, k, set.keys[k]!),
            };
            final shared = CodeSet(
              id: set.id,
              brand: set.brand,
              category: set.category,
              keys: canonical,
              provenance: p,
            ).protocol;
            setStmt.execute([
              setId,
              set.id,
              brandId[brand],
              category.name,
              rank,
              set.label,
              shared,
              keys.length,
              e.mergedIds.length,
              p.source,
              p.sourceUrl,
              p.sourceCommit,
              p.license,
              p.importedAt,
              p.path,
            ]);
            for (var ord = 0; ord < keys.length; ord++) {
              final c = keyCodeToColumns(canonical[keys[ord]]!);
              keyStmt.execute([
                setId,
                ord,
                keys[ord],
                c.protocol,
                c.params,
                c.carrierHz,
                c.durations,
                c.repeatFrame,
                c.repeatLeadInUs,
                c.repeatGapUs,
                c.repeatMin,
              ]);
              keyCount++;
            }
            for (final alias in e.mergedIds) {
              aliases.add((alias, setId));
            }
          }
        }
      }
      bcStmt.close();
      setStmt.close();
      keyStmt.close();

      aliases.sort((a, b) => a.$1.compareTo(b.$1));
      final aliasStmt = insert('code_set_alias');
      for (final (uid, id) in aliases) {
        aliasStmt.execute([uid, id]);
      }
      aliasStmt.close();

      final meta = <String, String>{
        ...content.meta,
        metaSchemaVersion: '$codeDbSchemaVersion',
        'code_set_count': '$setId',
        'brand_count': '${brandNames.length}',
        'key_code_count': '$keyCount',
      };
      final metaStmt = insert('meta');
      for (final k in meta.keys.toList()..sort()) {
        metaStmt.execute([k, meta[k]]);
      }
      final hash = computeContentHash(db);
      metaStmt
        ..execute([metaContentHash, hash])
        ..close();
      db.execute('COMMIT');

      final out = File(path);
      final partial = File('$path.partial');
      if (partial.existsSync()) partial.deleteSync();
      out.parent.createSync(recursive: true);
      db.execute('VACUUM INTO ?', [partial.path]);
      partial.renameSync(out.path);
      final bytes = out.readAsBytesSync();
      return CodeDbWriteResult(
        contentHash: hash,
        fileSha256: sha256.convert(bytes).toString(),
        fileBytes: bytes.length,
        codeSetCount: setId,
        brandCount: brandNames.length,
        keyCount: keyCount,
        aliasCount: aliases.length,
      );
    } finally {
      db.close();
    }
  }
}
