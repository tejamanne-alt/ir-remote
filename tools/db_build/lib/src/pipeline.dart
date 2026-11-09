/// The database build: sources to candidates to a verified SQLite file.
library;

import 'dart:io';

import 'package:code_db/code_db.dart';
import 'package:ir_core/ir_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'brands.dart';
import 'candidate.dart';
import 'dedupe.dart';
import 'importers.dart';
import 'report.dart';
import 'sources.dart';

/// Version of this build tool, recorded in the database `meta` table.
const String dbBuildVersion = '1';

/// Categories bundled with the app (the primary-market subset).
const Set<DeviceCategory> bundledCategories = {
  DeviceCategory.tv,
  DeviceCategory.setTopBox,
  DeviceCategory.airConditioner,
  DeviceCategory.fan,
  DeviceCategory.projector,
  DeviceCategory.soundbar,
  DeviceCategory.airPurifier,
};

/// Thrown when a licensing or human-action gate refuses the build.
final class GateException implements Exception {
  /// Creates the exception.
  const GateException(this.gate, this.message);

  /// Gate name, for example `L4`.
  final String gate;

  /// Why the gate refused.
  final String message;

  @override
  String toString() => 'Gate $gate: $message';
}

/// Gate L4: the irdb announcement issue URL recorded in THIRD_PARTY.md, or
/// `null` when the file or the line is missing.
///
/// The line must read, with a real issue number:
/// `irdb announcement issue: https://github.com/probonopd/irdb/issues/123`.
String? irdbAnnouncementIssue(String thirdPartyPath) {
  final f = File(thirdPartyPath);
  if (!f.existsSync()) return null;
  final m = RegExp(
    r'irdb announcement issue:\s*(https://github\.com/probonopd/irdb/issues/[0-9]+)(?![0-9A-Za-z/])',
    caseSensitive: false,
  ).firstMatch(f.readAsStringSync());
  return m?.group(1);
}

/// Inputs of one build.
final class BuildConfig {
  /// Creates a config.
  const BuildConfig({
    required this.outDir,
    required this.thirdPartyPath,
    this.includeIrdb = false,
    this.importedAt,
  });

  /// Directory receiving codes.sqlite, its sidecar, manifest and report.
  final String outDir;

  /// Path of docs/THIRD_PARTY.md (gate L4).
  final String thirdPartyPath;

  /// Whether irdb data was requested (`--include-irdb`).
  final bool includeIrdb;

  /// Fixed `importedAt` date; `null` uses each source's pinned commit date.
  final String? importedAt;
}

/// What a build produced.
final class BuildOutcome {
  /// Creates an outcome.
  const BuildOutcome(this.result, this.report, this.manifest);

  /// The writer's result.
  final CodeDbWriteResult result;

  /// The report (also written as codes.report.json).
  final Map<String, Object?> report;

  /// The manifest (also written as codes.manifest.json).
  final CodeDbManifest manifest;
}

/// Resolves a pinned source to a verified checkout.
typedef SourceResolver = ResolvedSource Function(SourceSpec spec);

/// Runs a build.
///
/// Throws [GateException] when gate L4 refuses irdb, [SourceException] when
/// a source cannot be fetched or its licence is not the reviewed one, and
/// [CodeDbProvenanceException] when any provenance field is empty (gate
/// L1). Nothing is written to [BuildConfig.outDir] unless the build
/// succeeds.
BuildOutcome runBuild(
  BuildConfig config,
  SourceResolver resolve, {
  List<SourceSpec> sources = pinnedSources,
  void Function(String line)? log,
}) {
  final importedAt = config.importedAt;
  if (importedAt != null &&
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(importedAt)) {
    throw ArgumentError.value(importedAt, 'importedAt', 'must be YYYY-MM-DD');
  }
  String? issue;
  final selected = <SourceSpec>[];
  final excluded = <String, String>{
    'UberGuidoZ/Flipper-IRDB':
        'excluded in v1: its CC0 grant covers only contributions after a '
        'specific commit',
  };
  for (final s in sources) {
    if (s.kind == SourceKind.irdb) {
      if (!config.includeIrdb) {
        excluded[s.name] = 'not requested (--include-irdb not given)';
        continue;
      }
      issue = irdbAnnouncementIssue(config.thirdPartyPath);
      if (issue == null) {
        throw GateException(
          'L4',
          '--include-irdb needs "irdb announcement issue: '
              'https://github.com/probonopd/irdb/issues/<n>" in '
              '${config.thirdPartyPath}',
        );
      }
    }
    selected.add(s);
  }

  final stats = <String, SourceStats>{};
  final resolved = <ResolvedSource>[];
  final candidates = <Candidate>[];
  for (final spec in selected) {
    log?.call('resolving ${spec.name}@${spec.commit}');
    final src = resolve(spec);
    resolved.add(src);
    final date = importedAt ?? src.commitDate;
    final st = stats[spec.name] = SourceStats();
    log?.call('importing ${spec.name}');
    candidates.addAll(switch (spec.kind) {
      SourceKind.flipper => FlipperImporter.run(src, date, st),
      SourceKind.irdb => IrdbImporter.run(src, date, st),
    });
  }

  final canon = BrandCanonicalizer();
  for (final c in candidates) {
    canon.add(c.rawBrand);
  }
  final bundled = <Candidate>[];
  var outsideSubset = 0;
  for (final c in candidates) {
    c.brand = canon.canonical(c.rawBrand);
    if (c.brand.isEmpty || !bundledCategories.contains(c.category)) {
      outsideSubset++;
      continue;
    }
    bundled.add(c);
  }
  final kept = deduplicate(bundled);
  final byGroup = <String, List<Candidate>>{};
  for (final c in kept) {
    byGroup.putIfAbsent('${c.category.name}/${c.brand}', () => []).add(c);
  }
  final ranks = <String, int>{
    for (final g in byGroup.values) ...rankWithinBrand(g),
  };

  final dbSources = [
    for (final r in resolved)
      CodeDbSource(
        name: r.spec.name,
        url: r.spec.url,
        commit: r.spec.commit,
        license: r.spec.licenseId,
        importedAt: importedAt ?? r.commitDate,
        notice: r.notice,
      ),
  ];
  final entries = [
    for (final c in kept)
      CodeDbEntry(
        CodeSet(
          id: c.id,
          brand: c.brand,
          category: c.category,
          keys: c.keys,
          provenance: c.provenance,
          label: c.label,
          rank: ranks[c.id]!,
        ),
        mergedIds: [for (final m in _flatten(c)) m.id]..sort(),
      ),
  ];
  final content = CodeDbContent(
    sources: dbSources,
    entries: entries,
    primaryBrands: primaryBrands,
    meta: {
      'build_tool': 'tools/db_build $dbBuildVersion',
      'subset': 'primary-market',
      'irdb_announcement_issue': ?issue,
    },
  );
  // Gate L1 before anything touches the output directory.
  CodeDbWriter.validate(content);

  final out = Directory(config.outDir)..createSync(recursive: true);
  final dbPath = p.join(out.path, BundledCodeDb.fileName);
  log?.call('writing $dbPath');
  final result = CodeDbWriter.write(content, dbPath);
  // Read back through the loader: the file must verify and match.
  final db = CodeDb.open(dbPath, expectedContentHash: result.contentHash);
  final categories = db.categories();
  db.close();

  final counts = <String, int>{
    'codeSets': result.codeSetCount,
    'brands': result.brandCount,
    'keyCodes': result.keyCount,
    'mergedDuplicates': result.aliasCount,
    for (final c in categories) 'codeSets.${c.category.name}': c.codeSetCount,
    for (final c in categories) 'brands.${c.category.name}': c.brandCount,
  };
  final manifest = CodeDbManifest(
    schemaVersion: codeDbSchemaVersion,
    file: BundledCodeDb.fileName,
    contentSha256: result.contentHash,
    fileSha256: result.fileSha256,
    fileBytes: result.fileBytes,
    sources: [
      for (final s in dbSources)
        ManifestSource(
          name: s.name,
          url: s.url,
          commit: s.commit,
          license: s.license,
          importedAt: s.importedAt,
        ),
    ],
    counts: counts,
  );

  final gz = gzip.encode(File(dbPath).readAsBytesSync()).length;
  final ranked = <String, Object?>{};
  for (final e in primaryBrands.entries) {
    ranked[e.key.name] = {
      for (final b in e.value)
        b: kept.where((c) => c.category == e.key && c.brand == b).length,
    };
  }
  final report = <String, Object?>{
    'sources': {
      for (final r in resolved)
        r.spec.name: {
          'commit': r.spec.commit,
          'commitDate': r.commitDate,
          'license': r.spec.licenseId,
          'licenseFile': r.spec.licensePath,
          'licenseSha256': r.spec.licenseSha256,
          ...stats[r.spec.name]!.toJson(),
        },
    },
    'excludedSources': {
      for (final k in excluded.keys.toList()..sort()) k: excluded[k],
    },
    'gates': {
      'L1': 'pass: every code set and source has all provenance fields',
      'L4': issue == null
          ? 'irdb not included'
          : 'irdb included; announcement issue $issue',
    },
    'codeSets': {
      'candidates': candidates.length,
      'outsideBundledSubset': outsideSubset,
      'beforeDedupe': bundled.length,
      'duplicatesMerged': result.aliasCount,
      'afterDedupe': result.codeSetCount,
      'byCategory': {
        for (final c in categories) c.category.name: c.codeSetCount,
      },
      'brandsByCategory': {
        for (final c in categories) c.category.name: c.brandCount,
      },
      'rankedBrands': ranked,
    },
    'database': {
      'file': BundledCodeDb.fileName,
      'bytes': result.fileBytes,
      'gzipBytes': gz,
      'contentSha256': result.contentHash,
      'fileSha256': result.fileSha256,
      'schemaVersion': codeDbSchemaVersion,
      'sqliteVersion': sqlite3.version.libVersion,
      'brands': result.brandCount,
      'keyCodes': result.keyCount,
    },
  };

  File(p.join(out.path, BundledCodeDb.sidecarName))
      .writeAsStringSync('${result.contentHash}\n');
  File(p.join(out.path, BundledCodeDb.manifestName))
      .writeAsStringSync(manifest.encode());
  File(p.join(out.path, 'codes.report.json'))
      .writeAsStringSync(prettyJson(report));
  return BuildOutcome(result, report, manifest);
}

Iterable<Candidate> _flatten(Candidate c) sync* {
  for (final m in c.merged) {
    yield m;
    yield* _flatten(m);
  }
}
