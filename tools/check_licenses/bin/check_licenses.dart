// Gate L5 CLI. Run from the workspace root after `flutter pub get`:
//   dart run check_licenses            # check, exit 1 on any problem
//   dart run check_licenses --write    # rewrite the Dart packages table
import 'dart:io';

import 'package:check_licenses/check_licenses.dart';

void main(List<String> args) {
  var root = Directory.current.path;
  while (!File('$root/.dart_tool/package_config.json').existsSync() ||
      !File('$root/docs/THIRD_PARTY.md').existsSync()) {
    final parent = Directory(root).parent.path;
    if (parent == root) {
      stderr.writeln('Run from inside the workspace after `flutter pub get`.');
      exit(2);
    }
    root = parent;
  }
  final mdFile = File('$root/docs/THIRD_PARTY.md');
  final md = mdFile.readAsStringSync();
  final packages = readPackageConfig(root);
  final notShipped = <String>{};
  final listed = readThirdPartyTable(md, notShipped: notShipped);
  final report = check(packages, listed, notShipped: notShipped);

  if (args.contains('--write')) {
    final direct = _directDependencies(root);
    final uses = <String, String>{};
    for (final line in md.split('\n')) {
      final cells = line.split('|').map((c) => c.trim()).toList();
      if (cells.length > 4 && cells[3].contains(notShippedMarker)) {
        uses[cells[1].replaceAll('`', '')] = cells[3];
      }
    }
    final table = renderTable(report.resolved, direct, uses: uses);
    final start = md.indexOf('## Dart packages');
    if (start < 0) {
      stderr.writeln('THIRD_PARTY.md has no "## Dart packages" section.');
      exit(2);
    }
    final bodyStart = md.indexOf('\n|', start);
    final next = md.indexOf('\n## ', start + 1);
    final end = next < 0 ? md.length : next;
    final before = md.substring(
      0,
      bodyStart < 0 || bodyStart > end ? md.indexOf('\n', start) : bodyStart,
    );
    final after = md.substring(end);
    mdFile.writeAsStringSync('${before.trimRight()}\n\n$table$after');
    stdout.writeln(
      'Wrote ${report.resolved.length} packages to docs/THIRD_PARTY.md.',
    );
    return;
  }

  for (final w in report.warnings) {
    stdout.writeln('warning: $w');
  }
  for (final e in report.errors) {
    stderr.writeln('error: $e');
  }
  stdout.writeln(
    '${report.resolved.length} packages checked, '
    '${report.errors.length} errors, ${report.warnings.length} warnings.',
  );
  exit(report.ok ? 0 : 1);
}

Set<String> _directDependencies(String root) {
  final out = <String>{};
  for (final f in [
    'apps/remote/pubspec.yaml',
    'packages/ir_core/pubspec.yaml',
    'packages/ir_transports/pubspec.yaml',
    'packages/code_db/pubspec.yaml',
    'tools/db_build/pubspec.yaml',
  ]) {
    final file = File('$root/$f');
    if (!file.existsSync()) continue;
    var inDeps = false;
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('dependencies:')) {
        inDeps = true;
        continue;
      }
      if (line.isNotEmpty && !line.startsWith(' ')) inDeps = false;
      final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
      if (inDeps && m != null) out.add(m.group(1)!);
    }
  }
  return out;
}
