/// Builds the code database from pinned sources with provenance: fetch at
/// pinned commits, verify licences, import Flipper `.ir` and irdb CSV files,
/// normalize, deduplicate, rank and write a deterministic SQLite file.
library;

export 'src/brands.dart';
export 'src/candidate.dart';
export 'src/cli.dart';
export 'src/dedupe.dart';
export 'src/importers.dart';
export 'src/pipeline.dart';
export 'src/report.dart';
export 'src/sources.dart';
