/// The manifest written next to a code database file.
library;

import 'dart:convert';

import 'errors.dart';

/// File names of the bundled database inside `packages/code_db/assets/`.
abstract final class BundledCodeDb {
  /// The database file.
  static const String fileName = 'codes.sqlite';

  /// The manifest.
  static const String manifestName = 'codes.manifest.json';

  /// One line with the content hash.
  static const String sidecarName = 'codes.sqlite.sha256';

  /// Flutter asset key of the database when this package is a dependency.
  static const String assetKey = 'packages/code_db/assets/$fileName';

  /// Flutter asset key of the manifest.
  static const String manifestAssetKey =
      'packages/code_db/assets/$manifestName';
}

/// One source entry of a manifest.
final class ManifestSource {
  /// Creates an entry.
  const ManifestSource({
    required this.name,
    required this.url,
    required this.commit,
    required this.license,
    required this.importedAt,
  });

  /// Source name.
  final String name;

  /// Repository URL.
  final String url;

  /// Pinned commit.
  final String commit;

  /// Licence identifier.
  final String license;

  /// Import date.
  final String importedAt;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'commit': commit,
    'license': license,
    'importedAt': importedAt,
  };
}

/// Describes a database file: its hashes, size, schema and sources. Holds
/// nothing time-dependent, so the same build inputs give the same manifest.
final class CodeDbManifest {
  /// Creates a manifest.
  CodeDbManifest({
    required this.schemaVersion,
    required this.file,
    required this.contentSha256,
    required this.fileSha256,
    required this.fileBytes,
    required List<ManifestSource> sources,
    required Map<String, int> counts,
  }) : sources = List.unmodifiable(sources),
       counts = Map.unmodifiable(counts);

  /// Schema version of the file.
  final int schemaVersion;

  /// File name of the database.
  final String file;

  /// Content hash (rows); verified by `CodeDb.open`.
  final String contentSha256;

  /// SHA-256 of the file bytes; for download verification.
  final String fileSha256;

  /// File size in bytes.
  final int fileBytes;

  /// Sources the file was built from.
  final List<ManifestSource> sources;

  /// Counts such as `codeSets`, `brands`, `keyCodes` and per category.
  final Map<String, int> counts;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'file': file,
    'contentSha256': contentSha256,
    'fileSha256': fileSha256,
    'fileBytes': fileBytes,
    'sources': [for (final s in sources) s.toJson()],
    'counts': counts,
  };

  /// Pretty JSON text with a trailing newline.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Parses [encode] output; throws [CodeDbFormatException].
  static CodeDbManifest parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw CodeDbFormatException('manifest is not JSON: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const CodeDbFormatException('manifest must be an object');
    }
    T req<T>(Map<String, Object?> m, String k) {
      final v = m[k];
      if (v is! T) throw CodeDbFormatException('manifest.$k is missing');
      return v;
    }

    final sources = req<List<Object?>>(json, 'sources');
    final counts = req<Map<String, Object?>>(json, 'counts');
    return CodeDbManifest(
      schemaVersion: req<int>(json, 'schemaVersion'),
      file: req<String>(json, 'file'),
      contentSha256: req<String>(json, 'contentSha256'),
      fileSha256: req<String>(json, 'fileSha256'),
      fileBytes: req<int>(json, 'fileBytes'),
      sources: [
        for (final s in sources)
          if (s is Map<String, Object?>)
            ManifestSource(
              name: req<String>(s, 'name'),
              url: req<String>(s, 'url'),
              commit: req<String>(s, 'commit'),
              license: req<String>(s, 'license'),
              importedAt: req<String>(s, 'importedAt'),
            )
          else
            throw const CodeDbFormatException('manifest source not an object'),
      ],
      counts: {
        for (final e in counts.entries)
          e.key: e.value is int
              ? e.value! as int
              : throw CodeDbFormatException('manifest.counts.${e.key}'),
      },
    );
  }
}
