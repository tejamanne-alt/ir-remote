/// Gate L5: every resolved Dart package has an allowed license and an entry
/// in docs/THIRD_PARTY.md that names the same license.
library;

import 'dart:convert';
import 'dart:io';

/// Licenses allowed without asking (build contract, gate L5).
const Set<String> allowedLicenses = {
  'MIT',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'ISC',
  'Zlib',
  'CC0-1.0',
};

/// Packages that ship inside the Flutter SDK (BSD-3-Clause, Flutter
/// authors). Their LICENSE files aggregate many notices, so text
/// classification does not apply.
const Set<String> flutterSdkPackages = {
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_driver',
  'flutter_web_plugins',
  'integration_test',
  'fuchsia_remote_debug_protocol',
  'sky_engine',
};

/// Classifies a license text; returns an SPDX-style ID or `unknown`.
String classifyLicense(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ');
  bool has(String s) => t.contains(s);
  // MPL first: its text quotes the GPL family as "Secondary Licenses".
  if (has('Mozilla Public License')) return 'MPL-2.0';
  if (has('GNU LESSER GENERAL PUBLIC LICENSE') ||
      has('GNU Lesser General Public License')) {
    return 'LGPL';
  }
  if (has('GNU GENERAL PUBLIC LICENSE') || has('GNU Affero')) return 'GPL';
  if (has('Apache License') && (has('Version 2.0') || has('version 2.0'))) {
    return 'Apache-2.0';
  }
  if (has('Redistribution and use in source and binary forms')) {
    return has('Neither the name') || has('may be used to endorse or promote')
        ? 'BSD-3-Clause'
        : 'BSD-2-Clause';
  }
  if (has('Permission to use, copy, modify, and/or distribute this software')) {
    return 'ISC';
  }
  if (has('Permission is hereby granted, free of charge')) return 'MIT';
  if (has('altered source versions must be plainly marked') ||
      has('This software is provided \'as-is\'')) {
    return 'Zlib';
  }
  if (has('CC0 1.0') || has('Creative Commons Zero')) return 'CC0-1.0';
  if (has('free and unencumbered software released into the public domain')) {
    return 'Unlicense';
  }
  return 'unknown';
}

/// One resolved package.
final class ResolvedPackage {
  /// Creates a record.
  const ResolvedPackage(
    this.name,
    this.rootDir, {
    this.workspaceMember = false,
  });

  /// Package name.
  final String name;

  /// Directory holding the package.
  final String rootDir;

  /// Whether the package is part of this repository.
  final bool workspaceMember;
}

/// Reads `.dart_tool/package_config.json` under [workspaceRoot].
List<ResolvedPackage> readPackageConfig(String workspaceRoot) {
  final file = File('$workspaceRoot/.dart_tool/package_config.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final configDir = file.parent.uri;
  final root = Directory(workspaceRoot).absolute.uri;
  final out = <ResolvedPackage>[];
  for (final p in (json['packages']! as List).cast<Map<String, Object?>>()) {
    final uri = configDir.resolve(p['rootUri']! as String);
    final dir = uri.toFilePath();
    final member =
        uri.toString().startsWith(root.toString()) &&
        !uri.toString().contains('/.pub-cache/') &&
        !uri.toString().contains('/.dart_tool/');
    out.add(
      ResolvedPackage(p['name']! as String, dir, workspaceMember: member),
    );
  }
  return out;
}

/// Finds and classifies the license of [p], or `null` if no file exists.
({String license, String file})? licenseOf(ResolvedPackage p) {
  for (final n in [
    'LICENSE',
    'LICENSE.md',
    'LICENSE.txt',
    'LICENCE',
    'COPYING',
  ]) {
    final f = File('${p.rootDir}${p.rootDir.endsWith('/') ? '' : '/'}$n');
    if (f.existsSync()) {
      return (license: classifyLicense(f.readAsStringSync()), file: f.path);
    }
  }
  return null;
}

/// Marker in the Use column for packages that never reach a mobile binary
/// (for example Linux-desktop federated plugins). Only such rows may carry a
/// license outside [allowedLicenses], and each needs an OPEN_QUESTIONS entry.
const String notShippedMarker = 'not shipped';

/// Parses the "Dart packages" table of THIRD_PARTY.md: `| name | license | use |`.
/// Returns package → license; [notShipped] collects rows marked
/// [notShippedMarker].
Map<String, String> readThirdPartyTable(
  String markdown, {
  Set<String>? notShipped,
}) {
  final out = <String, String>{};
  var inSection = false;
  for (final line in const LineSplitter().convert(markdown)) {
    if (line.startsWith('## ')) inSection = line.trim() == '## Dart packages';
    if (!inSection || !line.startsWith('|')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 4) continue;
    final name = cells[1].replaceAll('`', '');
    if (name.isEmpty || name == 'Package' || name.startsWith('-')) continue;
    out[name] = cells[2];
    if (cells.length > 4 && cells[3].contains(notShippedMarker)) {
      notShipped?.add(name);
    }
  }
  return out;
}

/// Outcome of a check.
final class CheckReport {
  /// Problems that fail the gate.
  final List<String> errors = [];

  /// Notes that do not fail the gate.
  final List<String> warnings = [];

  /// Package → classified license, for --write.
  final Map<String, String> resolved = {};

  /// Whether the gate passes.
  bool get ok => errors.isEmpty;
}

/// Runs the gate for [packages] against [table].
CheckReport check(
  List<ResolvedPackage> packages,
  Map<String, String> table, {
  Set<String> notShipped = const {},
}) {
  final r = CheckReport();
  for (final p in packages) {
    if (p.workspaceMember) continue;
    String license;
    if (flutterSdkPackages.contains(p.name)) {
      license = 'BSD-3-Clause';
    } else {
      final found = licenseOf(p);
      if (found == null) {
        r.errors.add('${p.name}: no LICENSE file found in ${p.rootDir}');
        continue;
      }
      license = found.license;
    }
    r.resolved[p.name] = license;
    if (!allowedLicenses.contains(license) && !notShipped.contains(p.name)) {
      r.errors.add(
        '${p.name}: license "$license" is not on the allowed list; '
        'record it in docs/OPEN_QUESTIONS.md and get approval',
      );
    }
    final listed = table[p.name];
    if (listed == null) {
      r.errors.add(
        '${p.name}: missing from docs/THIRD_PARTY.md (license $license)',
      );
    } else if (listed != license) {
      r.errors.add(
        '${p.name}: THIRD_PARTY.md says "$listed" but the package is $license',
      );
    }
  }
  for (final name in table.keys) {
    if (!r.resolved.containsKey(name)) {
      r.warnings.add(
        '$name: listed in THIRD_PARTY.md but not resolved (stale entry?)',
      );
    }
  }
  return r;
}

/// Renders the "Dart packages" table for [resolved].
String renderTable(
  Map<String, String> resolved,
  Set<String> direct, {
  Map<String, String> uses = const {},
}) {
  final names = resolved.keys.toList()..sort();
  final b = StringBuffer()
    ..writeln('| Package | License | Use |')
    ..writeln('| --- | --- | --- |');
  for (final n in names) {
    final use =
        uses[n] ?? (direct.contains(n) ? 'direct' : 'transitive or dev');
    b.writeln('| `$n` | ${resolved[n]} | $use |');
  }
  return b.toString();
}
