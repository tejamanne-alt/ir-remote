import 'dart:io';

import 'package:check_licenses/check_licenses.dart';
import 'package:test/test.dart';

const _mit = 'Permission is hereby granted, free of charge, to any person ...';
const _bsd3 =
    'Redistribution and use in source and binary forms ... '
    'Neither the name of the copyright holder ...';
const _gpl = 'GNU GENERAL PUBLIC LICENSE Version 3';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('licenses'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ResolvedPackage pkg(String name, String? license) {
    final d = Directory('${tmp.path}/$name')..createSync();
    if (license != null) File('${d.path}/LICENSE').writeAsStringSync(license);
    return ResolvedPackage(name, d.path);
  }

  test('classifies common licenses', () {
    expect(classifyLicense(_mit), 'MIT');
    expect(classifyLicense(_bsd3), 'BSD-3-Clause');
    expect(
      classifyLicense('Redistribution and use in source and binary forms'),
      'BSD-2-Clause',
    );
    expect(
      classifyLicense('Apache License\n Version 2.0, January 2004'),
      'Apache-2.0',
    );
    expect(classifyLicense(_gpl), 'GPL');
    expect(classifyLicense('GNU LESSER GENERAL PUBLIC LICENSE'), 'LGPL');
    expect(
      classifyLicense(
        'Permission to use, copy, modify, and/or distribute this software',
      ),
      'ISC',
    );
    expect(
      classifyLicense("This software is provided 'as-is', without any express"),
      'Zlib',
    );
    expect(classifyLicense('CC0 1.0 Universal'), 'CC0-1.0');
    expect(classifyLicense('Mozilla Public License'), 'MPL-2.0');
    expect(
      classifyLicense(
        'Mozilla Public License Version 2.0 ... GNU Lesser General Public License',
      ),
      'MPL-2.0',
    );
    expect(classifyLicense('all rights reserved'), 'unknown');
  });

  test('passes when every package is listed with its license', () {
    final r = check(
      [pkg('a', _mit), pkg('b', _bsd3)],
      {'a': 'MIT', 'b': 'BSD-3-Clause'},
    );
    expect(r.ok, isTrue, reason: r.errors.join('\n'));
  });

  test('fails on an unlisted package (fixture for the M0 gate)', () {
    final r = check([pkg('a', _mit), pkg('sneaky', _mit)], {'a': 'MIT'});
    expect(r.ok, isFalse);
    expect(
      r.errors.single,
      contains('sneaky: missing from docs/THIRD_PARTY.md'),
    );
  });

  test('fails on a disallowed or mismatched license, or none at all', () {
    final r = check(
      [pkg('g', _gpl), pkg('m', _mit), pkg('n', null)],
      {'g': 'GPL', 'm': 'BSD-3-Clause'},
    );
    expect(
      r.errors.any(
        (e) => e.contains('g: license "GPL" is not on the allowed list'),
      ),
      isTrue,
    );
    expect(r.errors.any((e) => e.contains('m: THIRD_PARTY.md says')), isTrue);
    expect(r.errors.any((e) => e.contains('n: no LICENSE file')), isTrue);
  });

  test(
    'skips workspace members, trusts Flutter SDK packages, warns on stale rows',
    () {
      final r = check(
        [
          const ResolvedPackage('ir_core', '/nowhere', workspaceMember: true),
          const ResolvedPackage('sky_engine', '/nowhere'),
        ],
        {'sky_engine': 'BSD-3-Clause', 'gone': 'MIT'},
      );
      expect(r.ok, isTrue);
      expect(r.warnings.single, contains('gone'));
    },
  );

  test('a non-allowed license passes only when marked not shipped', () {
    const mpl = 'Mozilla Public License Version 2.0';
    final shipped = check([pkg('dbus', mpl)], {'dbus': 'MPL-2.0'});
    expect(shipped.ok, isFalse);
    final notShipped = check(
      [pkg('dbus2', mpl)],
      {'dbus2': 'MPL-2.0'},
      notShipped: {'dbus2'},
    );
    expect(notShipped.ok, isTrue);
    final ns = <String>{};
    readThirdPartyTable(
      '## Dart packages\n| Package | License | Use |\n| `dbus` | MPL-2.0 | not shipped (Linux) |\n',
      notShipped: ns,
    );
    expect(ns, {'dbus'});
  });

  test('reads only the Dart packages table', () {
    const md = '''
# Third party
## Data sources
| Source | License |
| --- | --- |
| irdb | custom |
## Dart packages
| Package | License | Use |
| --- | --- | --- |
| `drift` | MIT | direct |
| `path` | BSD-3-Clause | transitive or dev |
## Firmware
| `ArduinoJson` | MIT | x |
''';
    expect(readThirdPartyTable(md), {'drift': 'MIT', 'path': 'BSD-3-Clause'});
    expect(
      renderTable({'b': 'MIT', 'a': 'ISC'}, {'a'}),
      contains('| `a` | ISC | direct |'),
    );
  });
}
