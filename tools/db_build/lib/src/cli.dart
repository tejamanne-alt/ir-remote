/// Command-line interface of the database build.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:code_db/code_db.dart';
import 'package:path/path.dart' as p;

import 'pipeline.dart';
import 'sources.dart';

/// Exit code for a successful build.
const int exitOk = 0;

/// Exit code for a failed build (gate, source, licence or provenance).
const int exitFailed = 1;

/// Exit code for bad arguments.
const int exitUsage = 64;

ArgParser _parser() => ArgParser()
  ..addOption('out', help: 'Output directory (required).', valueHelp: 'dir')
  ..addFlag(
    'include-irdb',
    negatable: false,
    help:
        'Include probonopd/irdb. Refused unless docs/THIRD_PARTY.md records '
        '"irdb announcement issue: https://github.com/probonopd/irdb/issues/<n>" '
        '(gate L4).',
  )
  ..addOption(
    'cache-dir',
    help: 'Where pinned sources are cloned (outside the repository).',
    valueHelp: 'dir',
  )
  ..addOption(
    'imported-at',
    help:
        'Fixed import date (YYYY-MM-DD). Default: each pinned commit date, so '
        'builds are reproducible.',
  )
  ..addOption(
    'third-party',
    help:
        'Path of THIRD_PARTY.md. Default: docs/THIRD_PARTY.md of the '
        'workspace containing the current directory.',
  )
  ..addFlag(
    'offline',
    negatable: false,
    help: 'Do not fetch; the pinned commits must already be cached.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

/// The workspace root above [start] (the directory whose pubspec.yaml has a
/// `workspace:` section), or `null`.
String? findWorkspaceRoot(String start) {
  var dir = Directory(start).absolute;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Runs the CLI with [args] and returns the exit code.
///
/// [resolver] replaces git fetching and licence checks (tests);
/// [sources] replaces the pinned source list (tests).
int runCli(
  List<String> args, {
  SourceResolver? resolver,
  List<SourceSpec> sources = pinnedSources,
  StringSink? out,
  StringSink? err,
}) {
  final o = out ?? stdout;
  final e = err ?? stderr;
  final parser = _parser();
  final ArgResults a;
  try {
    a = parser.parse(args);
  } on FormatException catch (x) {
    e
      ..writeln(x.message)
      ..writeln(parser.usage);
    return exitUsage;
  }
  if (a.flag('help')) {
    o
      ..writeln('dart run db_build:build --out <dir> [options]')
      ..writeln(parser.usage);
    return exitOk;
  }
  final outDir = a.option('out');
  if (outDir == null || a.rest.isNotEmpty) {
    e
      ..writeln('--out is required and no positional arguments are taken')
      ..writeln(parser.usage);
    return exitUsage;
  }
  final root = findWorkspaceRoot(Directory.current.path);
  final thirdParty =
      a.option('third-party') ??
      (root == null
          ? 'docs/THIRD_PARTY.md'
          : p.join(root, 'docs', 'THIRD_PARTY.md'));
  final fetcher = GitFetcher(
    cacheDir: a.option('cache-dir') ?? GitFetcher.defaultCacheDir(),
    offline: a.flag('offline'),
    log: o.writeln,
  );
  try {
    final outcome = runBuild(
      BuildConfig(
        outDir: outDir,
        thirdPartyPath: thirdParty,
        includeIrdb: a.flag('include-irdb'),
        importedAt: a.option('imported-at'),
      ),
      resolver ?? fetcher.resolve,
      sources: sources,
      log: o.writeln,
    );
    final db = outcome.report['database']! as Map<String, Object?>;
    final sets = outcome.report['codeSets']! as Map<String, Object?>;
    o
      ..writeln(
        'code sets: ${sets['afterDedupe']} '
        '(${sets['duplicatesMerged']} duplicates merged) '
        'by category ${sets['byCategory']}',
      )
      ..writeln('database: ${db['bytes']} bytes, ${db['gzipBytes']} gzipped')
      ..writeln('content sha256: ${db['contentSha256']}')
      ..writeln('report: ${p.join(outDir, 'codes.report.json')}');
    return exitOk;
  } on GateException catch (x) {
    e.writeln('build refused by gate ${x.gate}: ${x.message}');
  } on CodeDbProvenanceException catch (x) {
    e.writeln('build failed gate L1 (provenance): ${x.message}');
  } on CodeDbException catch (x) {
    e.writeln('build failed: $x');
  } on SourceException catch (x) {
    e.writeln('build failed: ${x.message}');
  } on ArgumentError catch (x) {
    e.writeln('bad argument: ${x.message}');
    return exitUsage;
  }
  return exitFailed;
}
