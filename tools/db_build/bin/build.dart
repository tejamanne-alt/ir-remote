/// Builds the bundled code database from pinned sources.
///
/// ```sh
/// dart run db_build:build --out DIR [--include-irdb] [--cache-dir DIR]
///     [--imported-at YYYY-MM-DD] [--third-party FILE] [--offline]
/// ```
library;

import 'dart:io';

import 'package:db_build/db_build.dart';

void main(List<String> args) {
  exitCode = runCli(args);
}
